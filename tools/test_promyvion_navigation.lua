-- State-machine coverage for same-zone Promyvion floors and Memory Streams.
-- No native waypoint result is allowed to stand in for a portal transition.

local ADDON = (...) or arg[1]
    or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = (os.getenv('ACCESSXI_ROOT') or 'C:/Users/buu42/AccessXI') .. '/tests/lua/?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

local now = 1000;
local spoken = T{};
local installed = T{};
local clear_count = 0;
local stop_count = 0;
local nav_active = false;
local blocked_x = {};
local one_point_x = {};
local mesh_unavailable = false;
local entities = {};
local snapshot_calls = T{};
local route_policy = nil;

local accessxi = {};
local env = {
    accessxi = accessxi,
    T = T,
    tick = function() return now; end,
    log_line = function() end,
    speak = function(text) spoken:append(tostring(text)); end,
    nav_clean_field = H.nav_clean_field,
    nav_split_tsv = H.nav_split_tsv,
    nav_distance = H.nav_distance,
    accessxi_paths = {
        addon_path = function(...) return table.concat({ ADDON, ... }, '\\'); end,
    },
    nav_compute_mesh_route = function(player, target)
        if (mesh_unavailable) then
            accessxi.nav_route_last_reject_reason = 'synthetic transient mesh miss';
            return T{};
        end
        if (blocked_x[tonumber(target.x) or 0] == true) then
            accessxi.nav_route_last_reject_reason = 'synthetic blocked route';
            return T{};
        end
        if (type(route_policy) == 'function' and route_policy(player, target) == false) then
            accessxi.nav_route_last_reject_reason = 'synthetic disconnected route';
            return T{};
        end
        if (one_point_x[tonumber(target.x) or 0] == true) then
            return T{ T{ zone = target.zone, x = target.x, y = target.y, z = target.z } };
        end
        return T{
            T{ zone = player.zone, x = player.x, y = player.y, z = player.z },
            T{ zone = target.zone, x = target.x, y = target.y, z = target.z },
        };
    end,
    entity_snapshot = function(server_id)
        snapshot_calls:append(tonumber(server_id) or 0);
        return entities[tonumber(server_id) or 0];
    end,
    install_route = function(player, destination, route)
        installed:append({ player = player, destination = destination, route = route });
    end,
    clear_route = function() clear_count = clear_count + 1; end,
    stop_route = function()
        stop_count = stop_count + 1;
        nav_active = false;
    end,
};
setmetatable(env, { __index = _G });
-- The module under test defaults to the deployed copy, but may be pointed at a
-- reviewed copy so it can be verified BEFORE it is deployed. Zone data and the
-- reader seam still come from ADDON either way.
local MODULE = arg[2] or (ADDON .. [[\modules\promyvion_navigation.lua]]);
local chunk = assert(loadfile(MODULE));
setfenv(chunk, env);
chunk();

local function npc_update_packet(server_id, mask, animation)
    local bytes = {};
    for i = 1, 0x40 do bytes[i] = 0; end
    local value = tonumber(server_id) or 0;
    bytes[0x04 + 1] = value % 256;
    bytes[0x05 + 1] = math.floor(value / 256) % 256;
    bytes[0x06 + 1] = math.floor(value / 65536) % 256;
    bytes[0x07 + 1] = math.floor(value / 16777216) % 256;
    bytes[0x0A + 1] = tonumber(mask) or 0;
    bytes[0x1F + 1] = tonumber(animation) or 0;
    return string.char(unpack(bytes));
end

-- HARNESS TRAP, SCOPED.
--
-- This used to replace the production Stream classifier outright, so every
-- claim below measured the fake instead of the shipped predicate. The legacy
-- fixtures drive the state machine through a synthetic `state` field, so keep
-- that shorthand -- but DELEGATE anything without it to the real classifier, so
-- the liveness claims exercise production code.
local production_stream_state = accessxi.nav_promyvion_stream_state;
accessxi.nav_promyvion_stream_state = function(entity)
    if (type(entity) == 'table' and entity.state ~= nil) then
        return tostring(entity.state);
    end
    return production_stream_state(entity);
end

-- Literal client shapes. A despawned entity keeps its slot, name, server id, HP
-- and last position; only the render flags mark it gone, so those retained
-- fields are not presence evidence.
local RENDERED_0, RENDERED_1 = 0x40400000, 0x880;
local DESPAWNED_0, DESPAWNED_1 = 0x40404000, 0x1000;

local function rendered_stream(status)
    return { server_id = 0, status = status, status_server = status,
        render_flags_0 = RENDERED_0, render_flags_1 = RENDERED_1 };
end

local function live_receptacle(server_id, x, z)
    return { server_id = server_id, name = 'Memory Receptacle', hp = 100, status = 0,
        x = x, z = z or 0, y = 0,
        render_flags_0 = RENDERED_0, render_flags_1 = RENDERED_1 };
end

print('\n== deployed topology loader ==');
check('the runtime parser loads all 87 reviewed transition records',
    accessxi.nav_promyvion_load() == true and #accessxi.nav_promyvion_rows == 87,
    type(accessxi.nav_promyvion_rows) == 'table' and #accessxi.nav_promyvion_rows or -1);
check('the runtime parser builds all four Promyvion zone graphs',
    accessxi.nav_promyvion_zones[16] ~= nil and accessxi.nav_promyvion_zones[18] ~= nil
        and accessxi.nav_promyvion_zones[20] ~= nil and accessxi.nav_promyvion_zones[22] ~= nil);
local reviewed_rows = accessxi.nav_promyvion_rows;

print('\n== server-backed Stream state ==');
do
    local stream_id = 16843061;
    check('the runtime exposes a testable NPC-update Stream-state parser',
        type(accessxi.nav_promyvion_entity_update_packet) == 'function'
            and type(accessxi.nav_promyvion_packet_stream_state) == 'function');
    if (type(accessxi.nav_promyvion_entity_update_packet) == 'function'
        and type(accessxi.nav_promyvion_packet_stream_state) == 'function') then
        accessxi.nav_promyvion_packet_zone(16);
        accessxi.nav_promyvion_entity_update_packet(
            npc_update_packet(stream_id, 0x04, 8), 16, now);
        check('animation 8 in an HP-status NPC update is positive open evidence',
            accessxi.nav_promyvion_packet_stream_state(stream_id, 16, 180, now) == 'open');
        accessxi.nav_promyvion_entity_update_packet(
            npc_update_packet(stream_id, 0x00, 9), 16, now + 1);
        check('an update without the HP-status mask cannot overwrite Stream state',
            accessxi.nav_promyvion_packet_stream_state(stream_id, 16, 180, now + 1) == 'open');
        check('open evidence cannot outlive the server three-minute window',
            accessxi.nav_promyvion_packet_stream_state(stream_id, 16, 180, now + 180001) == 'unknown');
        accessxi.nav_promyvion_entity_update_packet(
            npc_update_packet(stream_id, 0x04, 9), 16, now + 180002);
        check('animation 9 in an HP-status NPC update is positive closed evidence',
            accessxi.nav_promyvion_packet_stream_state(stream_id, 16, 180, now + 180002) == 'closed');
        check('closed evidence also expires instead of making a permanent world-state claim',
            accessxi.nav_promyvion_packet_stream_state(stream_id, 16, 180, now + 360003) == 'unknown');
        accessxi.nav_promyvion_packet_zone(230);
        check('zoning clears cached Stream evidence instead of reusing it on re-entry',
            accessxi.nav_promyvion_packet_stream_state(stream_id, 16, 180, now + 180003) == 'unknown');
    end
end

print('\n== live liveness classifiers ==');
do
    -- Retail trace, 2026-09-01 Promyvion - Holla: Stream 16843061 read rendered
    -- status 9, Receptacle 16842781 died at 09:18:51, and the same Stream read
    -- rendered status 8 by 09:18:59. A 09:20:26 snapshot still read 8 while
    -- carrying the despawn bit -- a retained value, not evidence.
    check('a rendered Stream at status 8 is positive open evidence',
        production_stream_state(rendered_stream(8)) == 'open',
        production_stream_state(rendered_stream(8)));
    check('a rendered Stream at status 9 is positive closed evidence',
        production_stream_state(rendered_stream(9)) == 'closed',
        production_stream_state(rendered_stream(9)));
    local stale = rendered_stream(8);
    stale.render_flags_0, stale.render_flags_1 = DESPAWNED_0, DESPAWNED_1;
    check('a despawned snapshot that retains status 8 is never called open',
        production_stream_state(stale) == 'unknown',
        production_stream_state(stale));
    check('a snapshot with no render evidence cannot claim a Stream state',
        production_stream_state({ status = 8 }) == 'unknown',
        production_stream_state({ status = 8 }));
    check('an absent Stream snapshot is unknown',
        production_stream_state(nil) == 'unknown', production_stream_state(nil));

    check('the runtime exposes a Receptacle liveness classifier',
        type(accessxi.nav_promyvion_receptacle_state) == 'function');
    if (type(accessxi.nav_promyvion_receptacle_state) == 'function') then
        local R = accessxi.nav_promyvion_receptacle_state;
        check('a rendered Receptacle with HP is present',
            R(live_receptacle(16842781, -40, 200), 16842781) == 'present',
            R(live_receptacle(16842781, -40, 200), 16842781));
        local corpse = live_receptacle(16842781, -40, 200);
        corpse.hp, corpse.status = 0, 3;
        check('a rendered corpse at HP zero with the death animation is observed dead',
            R(corpse, 16842781) == 'observed-dead', R(corpse, 16842781));
        local stale_alive = live_receptacle(16842781, -40, 200);
        stale_alive.render_flags_0, stale_alive.render_flags_1 = DESPAWNED_0, DESPAWNED_1;
        check('a despawned slot that still reads HP 100 is not present',
            R(stale_alive, 16842781) == 'unknown', R(stale_alive, 16842781));
        check('an absent Receptacle is unknown, never dead',
            R(nil, 16842781) == 'unknown', R(nil, 16842781));
        check('a snapshot for a different server id cannot stand in for the pair',
            R(live_receptacle(16842999, -40, 200), 16842781) == 'unknown',
            R(live_receptacle(16842999, -40, 200), 16842781));
    end

    check('the runtime exposes a witnessed-defeat entry point',
        type(accessxi.nav_promyvion_receptacle_defeated) == 'function');
end

local rows = T{
    T{ record_id = '16:island:1', zone = 16, island_id = 'floor-1', kind = 'island',
        name = 'floor 1', anchor_x = 0, anchor_z = 0, anchor_y = 0 },
    T{ record_id = '16:island:2', zone = 16, island_id = 'floor-2', kind = 'island',
        name = 'floor 2', anchor_x = 100, anchor_z = 0, anchor_y = 0 },
    T{ record_id = '16:island:3', zone = 16, island_id = 'floor-3', kind = 'island',
        name = 'floor 3', anchor_x = 200, anchor_z = 0, anchor_y = 0 },
    T{ record_id = '16:forward:a', zone = 16, island_id = 'floor-1', kind = 'forward',
        group_id = '1', name = 'first portal', anchor_x = 10, anchor_z = 0, anchor_y = 0,
        radius = 3, entity_server_id = 101, paired_server_id = 201,
        destination_island = 'floor-2', landing_x = 100, landing_z = 0, landing_y = 0,
        availability = 'stream-open-evidence', window_seconds = 180 },
    T{ record_id = '16:forward:b', zone = 16, island_id = 'floor-1', kind = 'forward',
        group_id = '1', name = 'second portal', anchor_x = 20, anchor_z = 0, anchor_y = 0,
        radius = 3, entity_server_id = 102, paired_server_id = 202,
        destination_island = 'floor-2', landing_x = 100, landing_z = 0, landing_y = 0,
        availability = 'stream-open-evidence', window_seconds = 180 },
    T{ record_id = '16:forward:c', zone = 16, island_id = 'floor-2', kind = 'forward',
        group_id = '2', name = 'upper portal', anchor_x = 110, anchor_z = 0, anchor_y = 0,
        radius = 3, entity_server_id = 103, paired_server_id = 203,
        destination_island = 'floor-3', landing_x = 200, landing_z = 0, landing_y = 0,
        availability = 'stream-open-evidence', window_seconds = 180 },
    T{ record_id = '16:return:1', zone = 16, island_id = 'floor-2', kind = 'return',
        name = 'return stream', anchor_x = 90, anchor_z = 0, anchor_y = 0, radius = 3,
        destination_island = 'floor-1', landing_x = 0, landing_z = 0, landing_y = 0,
        availability = 'always', window_seconds = 0 },
};
accessxi.nav_promyvion_set_rows(rows);

-- The paired mobs for the two floor-1 platforms. The state machine now asks
-- whether a Receptacle is actually standing on a platform before it tells the
-- player to fight one, so the arrival claims below need a live Receptacle to be
-- arriving at. Their coordinates match their platform anchors, exactly as
-- retail places a Receptacle on the platform of the Stream it can open.
entities[201] = live_receptacle(201, 10);
entities[202] = live_receptacle(202, 20);

local function p(x)
    return T{ zone = 16, x = x, z = 0, y = 0, name = 'player' };
end
local final = T{ zone = 16, x = 999, z = 0, y = 0, name = 'Spire of Test zone line' };

-- A synthetic mesh must model the same fact as retail: disconnected floors do
-- not produce one direct route, while every approach on the current floor does.
route_policy = function(player, target)
    if target.force_disconnected == true then return false; end
    if (target.name == 'player' or target.name == 'lower target')
        and math.abs((tonumber(target.x) or 0) - (tonumber(player.x) or 0)) > 40 then
        return false;
    end
    if tostring(target.name or ''):find('Spire of ', 1, true) ~= nil
        and player.allow_spire_direct ~= true then
        return false;
    end
    if player.certified_island == 'floor-2' then
        local x = tonumber(target.x) or 0;
        return x >= 80 and x <= 110;
    end
    return true;
end

print('\n== island graph ==');
check('the nearest reviewed island is identified',
    accessxi.nav_promyvion_island_for_point(p(4)) == 'floor-1');
check('a Spire target maps to the terminal island from topology',
    accessxi.nav_promyvion_island_for_point(final) == 'floor-3');
do
    local misleading = p(4);
    misleading.certified_island = 'floor-2';
    check('mesh reachability overrides a nearer anchor on another floor',
        accessxi.nav_promyvion_island_for_point(misleading, true) == 'floor-2');
end
do
    local route, mode = accessxi.nav_promyvion_route(p(0), p(5));
    check('same-island movement remains a certified mesh route',
        mode == 'same-island' and route:len() == 2, mode);
end
do
    local spire_floor = p(200);
    spire_floor.allow_spire_direct = true;
    local route, mode = accessxi.nav_promyvion_route(spire_floor, final);
    check('a direct certified route wins before proximity can misclassify the Spire floor',
        mode == 'same-island' and route:len() == 2, mode);
end

print('\n== no open stream ==');
blocked_x[10] = true;
entities[101] = { state = 'closed' };
entities[102] = { state = 'unknown' };
do
    local route, mode, message = accessxi.nav_promyvion_route(p(0), final);
    local state = accessxi.nav_promyvion_progress();
    check('an unroutable first receptacle falls through to another candidate',
        mode == 'route' and route:len() == 2 and route[2].x == 20, mode);
    check('the candidate phase is explicit', state.phase == 'approach-receptacle', state.phase);
    check('a successful transition clears rejection evidence from failed probes',
        accessxi.nav_route_last_reject_reason == '', accessxi.nav_route_last_reject_reason);
    check('Promyvion mesh legs are not mislabeled as generic route overrides',
        route[1].route_override_id == nil and route[1].promyvion_phase == 'approach-receptacle',
        route[1].route_override_id);
    check('unknown is not announced as closed',
        tostring(message):find('confirmed open', 1, true) ~= nil, message);
end


accessxi.nav_promyvion_clear('near-receptacle');
blocked_x[10] = true;
one_point_x[20] = true;
do
    local route, mode = accessxi.nav_promyvion_route(p(20), final);
    check('standing at a Receptacle turns a one-point mesh result into an immediate bounded approach',
        mode == 'route' and route:len() == 2, mode);
    accessxi.nav_promyvion_poll(p(20), final, now);
    check('the immediate approach enters the non-directional Stream wait',
        accessxi.nav_promyvion_progress().phase == 'waiting-for-stream',
        accessxi.nav_promyvion_progress().phase);
end
one_point_x[20] = nil;
accessxi.nav_promyvion_clear('near-receptacle-reset');
clear_count = 0;
spoken:clear();
installed:clear();
accessxi.nav_promyvion_route(p(0), final);

do
    accessxi.nav_promyvion_poll(p(20), final, now);
    local state = accessxi.nav_promyvion_progress();
    check('arrival at a receptacle becomes a non-directional wait',
        state.phase == 'waiting-for-stream' and clear_count == 1, state.phase);
    check('the player is told what action owns the wait',
        spoken[#spoken] == 'Defeat this Memory Receptacle. I will tell you if a Stream opens.',
        spoken[#spoken]);
end

do
    local before = #installed;
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(100), final, now);
    local state = accessxi.nav_promyvion_progress();
    check('a large position jump escapes an unknown Stream wait and replans',
        state.island == 'floor-2' and state.phase == 'approach-receptacle'
            and #installed == before + 1, state.phase);
    check('a manually crossed Stream is never a silent state change',
        tostring(spoken[#spoken]):find('Promyvion floor changed. Route resumed.', 1, true) == 1,
        spoken[#spoken]);
    check('a floor-change replan says what the new floor requires',
        tostring(spoken[#spoken]):find('Defeat a Memory Receptacle', 1, true) ~= nil,
        spoken[#spoken]);
end

do
    -- A same-zone teleport can briefly fail to snap while the new floor is
    -- settling.  A failed certification must not move the jump origin to the
    -- landing, or every later poll sees zero movement and waits forever.
    accessxi.nav_promyvion_clear('transient-certification-setup');
    installed:clear();
    spoken:clear();
    accessxi.nav_promyvion_route(p(0), final);
    accessxi.nav_promyvion_poll(p(20), final, now);
    mesh_unavailable = true;
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(100), final, now);
    mesh_unavailable = false;
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(100), final, now);
    local state = accessxi.nav_promyvion_progress();
    check('a transient first certification miss does not disarm floor-change detection',
        state.island == 'floor-2' and state.phase == 'approach-receptacle'
            and #installed == 1, state.phase);
end

print('\n== bounded waits ==');
accessxi.nav_promyvion_clear('wait-deadline-setup');
installed:clear();
spoken:clear();
clear_count = 0;
entities[101].state = 'closed';
entities[102].state = 'unknown';
accessxi.nav_promyvion_route(p(0), final);
accessxi.nav_promyvion_poll(p(20), final, now);
nav_active = true;
local stops_before_stream_deadline = stop_count;
now = now + 600001;
accessxi.nav_promyvion_poll(p(20), final, now);
check('waiting for an unconfirmed Stream has a ten-minute deadline',
    accessxi.nav_promyvion_progress().phase == '', accessxi.nav_promyvion_progress().phase);
check('the Stream deadline says why navigation stopped',
    spoken[#spoken] == 'No Memory Stream was confirmed after ten minutes. Route stopped. Start it again when ready.',
    spoken[#spoken]);
check('the Stream deadline actually stops navigation instead of silently replanning',
    nav_active == false and stop_count == stops_before_stream_deadline + 1,
    ('active=%s stops=%d'):fmt(tostring(nav_active), stop_count));

accessxi.nav_promyvion_clear('observed-open-setup');
installed:clear();
spoken:clear();
clear_count = 0;
now = now + 1000;
accessxi.nav_promyvion_route(p(0), final);
accessxi.nav_promyvion_poll(p(20), final, now);

print('\n== observed open stream and same-zone jump ==');
entities[102].state = 'unknown';
accessxi.nav_promyvion_entity_update_packet(npc_update_packet(102, 0x04, 8), 16, now);
now = now + 1000;
accessxi.nav_promyvion_poll(p(0), final, now);
do
    local state = accessxi.nav_promyvion_progress();
    check('positive server packet evidence starts the Stream approach',
        state.phase == 'approach-stream' and #installed == 1, state.phase);
    check('opening is spoken with its measured server window',
        spoken[#spoken] == 'Memory Stream open for about three minutes. Starting route.',
        spoken[#spoken]);
end


now = now + 1000;
accessxi.nav_promyvion_poll(p(20), final, now);
do
    local state = accessxi.nav_promyvion_progress();
    check('the trigger wait suppresses ordinary routing',
        state.phase == 'waiting-for-jump' and clear_count == 2, state.phase);
    check('the trigger instruction promises a post-jump replan',
        spoken[#spoken] == 'Enter the Memory Stream. Navigation will resume after the jump.',
        spoken[#spoken]);
end

do
    local saved_now = now;
    nav_active = true;
    local stops_before_jump_deadline = stop_count;
    now = now + 90001;
    accessxi.nav_promyvion_poll(p(20), final, now);
    check('waiting for a jump has a ninety-second deadline',
        accessxi.nav_promyvion_progress().phase == '', accessxi.nav_promyvion_progress().phase);
    check('a missed jump is explained instead of waiting forever',
        spoken[#spoken] == 'I did not detect the Promyvion jump. Route stopped. Start it again after crossing the Stream.',
        spoken[#spoken]);
    check('the jump deadline actually stops navigation instead of silently replanning',
        nav_active == false and stop_count == stops_before_jump_deadline + 1,
        ('active=%s stops=%d'):fmt(tostring(nav_active), stop_count));

    -- Recreate the observed-open path for the ordinary landing assertion.
    accessxi.nav_promyvion_clear('jump-deadline-reset');
    accessxi.nav_promyvion_packet_zone(230);
    accessxi.nav_promyvion_packet_zone(16);
    installed:clear();
    spoken:clear();
    clear_count = 0;
    now = saved_now + 1000;
    entities[102].state = 'unknown';
    accessxi.nav_promyvion_route(p(0), final);
    accessxi.nav_promyvion_poll(p(20), final, now);
    entities[102].state = 'open';
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(20), final, now);
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(20), final, now);
end


now = now + 1000;
accessxi.nav_promyvion_poll(p(100), final, now);
do
    local state = accessxi.nav_promyvion_progress();
    check('landing on the next island replans immediately',
        state.island == 'floor-2' and state.phase == 'approach-receptacle'
            and #installed == 2, state.phase);
end

do
    -- The server, not the static table, owns a Stream's landing.  A certified
    -- landing outside the expected set is a reason to recalculate from the
    -- observed floor, not to strand the player or claim navigation stopped.
    accessxi.nav_promyvion_clear('unexpected-landing-setup');
    installed:clear();
    spoken:clear();
    entities[101].state = 'closed';
    entities[102].state = 'open';
    now = now + 1000;
    accessxi.nav_promyvion_route(p(0), final);
    accessxi.nav_promyvion_poll(p(20), final, now);
    local unexpected = p(200);
    unexpected.allow_spire_direct = true;
    nav_active = true;
    local stops_before_unexpected = stop_count;
    now = now + 1000;
    accessxi.nav_promyvion_poll(unexpected, final, now);
    check('a mesh-certified unexpected landing replans instead of stopping',
        #installed == 1 and nav_active == true and stop_count == stops_before_unexpected,
        ('installed=%d active=%s stops=%d'):fmt(#installed, tostring(nav_active), stop_count));
    check('an unexpected landing is disclosed without claiming the route stopped',
        tostring(spoken[#spoken]):find(
            'The Stream landed on a different Promyvion floor. Route recalculated.', 1, true) == 1,
        spoken[#spoken]);
end

print('\n== expiry and return ==');
accessxi.nav_promyvion_clear('test-reset');
entities[101].state = 'open';
entities[102].state = 'closed';
blocked_x[10] = nil;
accessxi.nav_promyvion_route(p(0), final);
entities[101].state = 'closed';
now = now + 1000;
accessxi.nav_promyvion_poll(p(0), final, now);
do
    local state = accessxi.nav_promyvion_progress();
    check('a Stream that closes is demoted back to Receptacle search',
        state.phase == 'approach-receptacle', state.phase);
    check('expiry is never silent',
        spoken[#spoken] == 'The Memory Stream closed. Returning to the Receptacle search.',
        spoken[#spoken]);
end


accessxi.nav_promyvion_clear('unknown-expiry');
entities[101].state = 'open';
accessxi.nav_promyvion_route(p(0), final);
entities[101].state = 'unknown';
now = now + 181000;
accessxi.nav_promyvion_poll(p(0), final, now);
do
    local state = accessxi.nav_promyvion_progress();
    check('the measured three-minute window expires even when entity state becomes unknown',
        state.phase == 'approach-receptacle', state.phase);
    check('clock expiry is disclosed like an observed closure',
        spoken[#spoken] == 'The Memory Stream closed. Returning to the Receptacle search.',
        spoken[#spoken]);
end


accessxi.nav_promyvion_clear('test-return');
do
    local route, mode = accessxi.nav_promyvion_route(p(100), p(0));
    local state = accessxi.nav_promyvion_progress();
    check('an always-open return is a directed transition',
        mode == 'route' and route[2].x == 90 and state.transition_kind == 'return', mode);
end


accessxi.nav_promyvion_clear('route-stopped');
check('route ownership cancellation removes the pending jump',
    accessxi.nav_promyvion_progress().phase == '', accessxi.nav_promyvion_progress().phase);

print('\n== server-selected return landing ==');
do
    local ambiguous_rows = T{
        T{ record_id = '16:island:lower-east', zone = 16, island_id = 'lower-east', kind = 'island',
            name = 'lower east', anchor_x = 100, anchor_z = 0, anchor_y = 0 },
        T{ record_id = '16:island:lower-west', zone = 16, island_id = 'lower-west', kind = 'island',
            name = 'lower west', anchor_x = -100, anchor_z = 0, anchor_y = 0 },
        T{ record_id = '16:island:top', zone = 16, island_id = 'top', kind = 'island',
            name = 'top', anchor_x = 200, anchor_z = 0, anchor_y = 0 },
        -- Retail chooses this landing from a zone charvar.  The two reviewed
        -- rows describe one physical return trigger, not two player choices.
        T{ record_id = '16:return:top:east', zone = 16, island_id = 'top', kind = 'return',
            name = 'top return', anchor_x = 190, anchor_z = 0, anchor_y = 0, radius = 3,
            destination_island = 'lower-east', landing_x = 100, landing_z = 0, landing_y = 0,
            availability = 'always' },
        T{ record_id = '16:return:top:west', zone = 16, island_id = 'top', kind = 'return',
            name = 'top return', anchor_x = 190, anchor_z = 0, anchor_y = 0, radius = 3,
            destination_island = 'lower-west', landing_x = -100, landing_z = 0, landing_y = 0,
            availability = 'always' },
        T{ record_id = '16:return:west:east', zone = 16, island_id = 'lower-west', kind = 'return',
            name = 'west to east', anchor_x = -90, anchor_z = 0, anchor_y = 0, radius = 3,
            destination_island = 'lower-east', landing_x = 100, landing_z = 0, landing_y = 0,
            availability = 'always' },
    };
    accessxi.nav_promyvion_set_rows(ambiguous_rows);
    local target = T{ zone = 16, x = 100, z = 0, y = 0, name = 'lower target',
        force_disconnected = true };
    local route, mode = accessxi.nav_promyvion_route(p(200), target);
    check('the shared return trigger routes without claiming which branch the server will choose',
        mode == 'route' and route[2].x == 190, mode);
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(190), target, now);
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(-100), target, now);
    local state = accessxi.nav_promyvion_progress();
    check('either reviewed landing from one physical return resumes navigation',
        state.island == 'lower-west' and state.next_island == 'lower-east', state.island);
end

print('\n== all reviewed zone paths ==');
do
    accessxi.nav_promyvion_set_rows(reviewed_rows);
    local names = {
        [16] = 'Spire of Holla zone line', [18] = 'Spire of Dem zone line',
        [20] = 'Spire of Mea zone line', [22] = 'Spire of Vahzl zone line',
    };
    for _, zone_id in ipairs(T{ 16, 18, 20, 22 }) do
        accessxi.nav_promyvion_clear('zone-matrix');
        local graph = accessxi.nav_promyvion_zones[zone_id];
        local first = graph.islands[graph.island_order[1]];
        local player = T{ zone = zone_id, name = 'player',
            x = first.anchor_x, z = first.anchor_z, y = first.anchor_y };
        local destination = T{ zone = zone_id, name = names[zone_id],
            x = 999, z = 999, y = 0 };
        local route, mode = accessxi.nav_promyvion_route(player, destination);
        local state = accessxi.nav_promyvion_progress();
        check(('zone %d has a reviewed directed path from entry to its Spire'):fmt(zone_id),
            mode == 'route' and route:len() == 2
                and state.phase == 'approach-receptacle'
                and state.target_island == graph.terminal[1],
            ('mode=%s phase=%s target=%s'):fmt(
                tostring(mode), tostring(state.phase), tostring(state.target_island)));
    end
end

print('\n== bounded live probe ==');
do
    accessxi.nav_promyvion_set_rows(reviewed_rows);
    snapshot_calls:clear();
    local holla_entry = accessxi.nav_promyvion_zones[16].islands['floor-1'];
    now = now + 1000;
    accessxi.nav_promyvion_probe(T{
        zone = 16, name = 'player',
        x = holla_entry.anchor_x, z = holla_entry.anchor_z, y = holla_entry.anchor_y,
    }, now);
    check('the instrumentation reads Streams only on the current island',
        snapshot_calls:len() == 1 and snapshot_calls[1] == 16843061,
        table.concat(snapshot_calls, ','));
end

print('\n== witnessed kill and empty platforms ==');
local function defeated(server_id, when)
    if (type(accessxi.nav_promyvion_receptacle_defeated) ~= 'function') then
        return nil;
    end
    return accessxi.nav_promyvion_receptacle_defeated(server_id, when);
end
do
    -- A Trust can kill the selected Receptacle before the player reaches its
    -- platform.  The witnessed kill owns the next twelve seconds immediately;
    -- arrival must not reinterpret the vanished mob as an empty platform and
    -- walk away from the Stream that may be opening.
    accessxi.nav_promyvion_set_rows(rows);
    accessxi.nav_promyvion_clear('mid-approach-kill-setup');
    blocked_x = {};
    one_point_x = {};
    installed:clear();
    spoken:clear();
    entities[101] = rendered_stream(9);
    entities[101].server_id = 101;
    entities[102] = rendered_stream(9);
    entities[102].server_id = 102;
    entities[201] = live_receptacle(201, 10);
    entities[202] = live_receptacle(202, 20);
    now = now + 1000;
    accessxi.nav_promyvion_route(p(0), final);
    check('a witnessed defeat while still approaching is accepted',
        defeated(201, now) == true);
    local corpse = live_receptacle(201, 10);
    corpse.hp, corpse.status = 0, 3;
    entities[201] = corpse;
    now = now + 1;
    accessxi.nav_promyvion_poll(p(0), final, now);
    check('a mid-approach kill stops the walk and starts Stream observation',
        accessxi.nav_promyvion_progress().phase == 'waiting-for-stream'
            and accessxi.nav_promyvion_progress().record_id == '16:forward:a',
        ('%s | %s'):fmt(accessxi.nav_promyvion_progress().phase,
            accessxi.nav_promyvion_progress().record_id));
    check('a mid-approach kill does not route to another platform',
        tostring(spoken[#spoken]):find('Checking its Memory Stream', 1, true) ~= nil,
        spoken[#spoken]);
    entities[101] = rendered_stream(8);
    entities[101].server_id = 101;
    now = now + 8000;
    accessxi.nav_promyvion_poll(p(0), final, now);
    check('the Stream opened by a mid-approach kill is still consumed',
        accessxi.nav_promyvion_progress().phase == 'approach-stream'
            and accessxi.nav_promyvion_progress().record_id == '16:forward:a',
        ('%s | %s'):fmt(accessxi.nav_promyvion_progress().phase,
            accessxi.nav_promyvion_progress().record_id));
end
do
    -- LITERAL 2026-09-01 REPLAY, on the reviewed Holla topology.
    -- 09:18:51 "Tenzen defeats the Memory Receptacle." (16842781)
    -- 09:18:59 paired Stream 16843061 reads rendered status 8.
    accessxi.nav_promyvion_set_rows(reviewed_rows);
    accessxi.nav_promyvion_clear('kill-to-open-setup');
    accessxi.nav_promyvion_packet_zone(230);
    accessxi.nav_promyvion_packet_zone(16);
    blocked_x = {};
    one_point_x = {};
    installed:clear();
    spoken:clear();
    entities[16843061] = rendered_stream(9);
    entities[16843061].server_id = 16843061;
    entities[16842781] = live_receptacle(16842781, -40, 200);

    local platform = T{ zone = 16, name = 'player', x = -40, z = 200, y = 0.589 };
    local spire = T{ zone = 16, name = 'Spire of Holla zone line', x = 999, z = 999, y = 0 };
    now = now + 1000;
    local route, mode = accessxi.nav_promyvion_route(platform, spire);
    check('the reviewed Holla floor-1 platform is routable while its Receptacle stands there',
        mode == 'route' and route:len() == 2, mode);
    now = now + 1000;
    accessxi.nav_promyvion_poll(platform, spire, now);
    check('arriving at a platform with a live Receptacle asks for the kill',
        accessxi.nav_promyvion_progress().phase == 'waiting-for-stream'
            and spoken[#spoken] == 'Defeat this Memory Receptacle. I will tell you if a Stream opens.',
        ('%s | %s'):fmt(accessxi.nav_promyvion_progress().phase, tostring(spoken[#spoken])));

    check('a witnessed defeat of the active paired Receptacle is accepted',
        defeated(16842781, now) == true);
    check('a witnessed defeat of some other Receptacle does not arm this target',
        defeated(16842999, now) == false);
    check('an unrelated Receptacle defeat is not remembered for a future platform',
        accessxi.nav_promyvion_receptacle_state(nil, 16842999) == 'unknown',
        accessxi.nav_promyvion_receptacle_state(nil, 16842999));

    local corpse = live_receptacle(16842781, -40, 200);
    corpse.hp, corpse.status = 0, 3;
    entities[16842781] = corpse;
    entities[16843061] = rendered_stream(8);
    entities[16843061].server_id = 16843061;
    now = now + 8000;
    accessxi.nav_promyvion_poll(platform, spire, now);
    check('the retail kill-to-open trace announces the opening exactly as retail produced it',
        accessxi.nav_promyvion_progress().phase == 'approach-stream'
            and spoken[#spoken] == 'Memory Stream open for about three minutes. Starting route.',
        ('%s | %s'):fmt(accessxi.nav_promyvion_progress().phase, tostring(spoken[#spoken])));
end

do
    -- A kill that opens nothing. Twelve seconds of rendered-closed evidence is
    -- a real answer; an unobservable Stream is not, and must never be called a
    -- decoy or silently abandoned.
    accessxi.nav_promyvion_set_rows(rows);
    accessxi.nav_promyvion_clear('kill-watch-setup');
    blocked_x = {};
    one_point_x = {};
    installed:clear();
    spoken:clear();
    entities[101] = rendered_stream(9);
    entities[101].server_id = 101;
    entities[102] = rendered_stream(9);
    entities[102].server_id = 102;
    entities[201] = live_receptacle(201, 10);
    entities[202] = live_receptacle(202, 20);
    now = now + 1000;
    accessxi.nav_promyvion_route(p(10), final);
    accessxi.nav_promyvion_poll(p(10), final, now);
    check('a rendered-closed floor still routes the player to a Receptacle platform',
        accessxi.nav_promyvion_progress().phase == 'waiting-for-stream',
        accessxi.nav_promyvion_progress().phase);
    defeated(201, now);
    local corpse = live_receptacle(201, 10);
    corpse.hp, corpse.status = 0, 3;
    entities[201] = corpse;
    now = now + 12001;
    accessxi.nav_promyvion_poll(p(10), final, now);
    check('a kill whose paired Stream stays rendered-closed moves on to another platform',
        accessxi.nav_promyvion_progress().phase == 'approach-receptacle'
            and accessxi.nav_promyvion_progress().record_id == '16:forward:b',
        ('%s | %s'):fmt(accessxi.nav_promyvion_progress().phase,
            accessxi.nav_promyvion_progress().record_id));
    check('a Stream that was observed closed is described as not opening',
        tostring(spoken[#spoken]):find('did not open', 1, true) ~= nil, spoken[#spoken]);
    check('an observed-closed result is never called a decoy',
        tostring(spoken[#spoken]):lower():find('decoy', 1, true) == nil, spoken[#spoken]);
end

do
    -- The same kill, with the paired Stream out of view. Leaving could abandon
    -- an open portal the addon simply failed to observe, so the player decides.
    accessxi.nav_promyvion_clear('unconfirmed-kill-setup');
    installed:clear();
    spoken:clear();
    entities[201] = live_receptacle(201, 10);
    entities[101] = rendered_stream(9);
    entities[101].server_id = 101;
    now = now + 1000;
    accessxi.nav_promyvion_route(p(10), final);
    accessxi.nav_promyvion_poll(p(10), final, now);
    defeated(201, now);
    entities[101] = nil;
    now = now + 12001;
    accessxi.nav_promyvion_poll(p(10), final, now);
    check('an unobservable Stream after a kill stays on this platform',
        accessxi.nav_promyvion_progress().record_id == '16:forward:a',
        accessxi.nav_promyvion_progress().record_id);
    check('an unconfirmed result is disclosed without claiming the Receptacle was wrong',
        tostring(spoken[#spoken]):find('could not confirm', 1, true) ~= nil
            and tostring(spoken[#spoken]):lower():find('decoy', 1, true) == nil,
        spoken[#spoken]);
end

do
    -- Arriving where nothing is standing. Absence is reported as absence, never
    -- as a death, and the search advances without ever cycling forever.
    accessxi.nav_promyvion_clear('empty-platform-setup');
    installed:clear();
    spoken:clear();
    entities[101] = rendered_stream(9);
    entities[101].server_id = 101;
    entities[102] = rendered_stream(9);
    entities[102].server_id = 102;
    entities[201] = nil;
    entities[202] = nil;
    now = now + 1000;
    accessxi.nav_promyvion_route(p(10), final);
    accessxi.nav_promyvion_poll(p(10), final, now);
    check('an empty search platform is reported as empty, not as a kill',
        tostring(spoken[#spoken]):find('Nothing is standing here right now.', 1, true) == 1,
        spoken[#spoken]);
    check('an empty platform never asserts the Receptacle is dead',
        tostring(spoken[#spoken]):lower():find('dead', 1, true) == nil
            and tostring(spoken[#spoken]):lower():find('defeat', 1, true) == nil,
        spoken[#spoken]);
    check('an empty platform advances the search to an unvisited platform',
        accessxi.nav_promyvion_progress().phase == 'approach-receptacle'
            and accessxi.nav_promyvion_progress().record_id == '16:forward:b',
        ('%s | %s'):fmt(accessxi.nav_promyvion_progress().phase,
            accessxi.nav_promyvion_progress().record_id));
    local advanced = #installed;
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(20), final, now);
    check('the last unvisited platform does not send the player back around the floor',
        accessxi.nav_promyvion_progress().record_id == '16:forward:b'
            and #installed == advanced,
        ('%s | installed=%d'):fmt(accessxi.nav_promyvion_progress().record_id, #installed));
    check('an exhausted platform search says so instead of going quiet',
        tostring(spoken[#spoken]):find('checked', 1, true) ~= nil, spoken[#spoken]);
end

do
    -- Holla, Dem and Mea each split on floor two.  Both branches reach the
    -- Spire, so exhausting the two platforms for one BFS-selected branch is
    -- not exhausting the route.  This small graph is the same shape and makes
    -- the omitted second branch observable without reaching into module locals.
    local branch_rows = T{
        T{ record_id = '16:island:root', zone = 16, island_id = 'root', kind = 'island',
            name = 'root', anchor_x = 0, anchor_z = 0, anchor_y = 0 },
        T{ record_id = '16:island:east', zone = 16, island_id = 'east', kind = 'island',
            name = 'east', anchor_x = 100, anchor_z = 0, anchor_y = 0 },
        T{ record_id = '16:island:west', zone = 16, island_id = 'west', kind = 'island',
            name = 'west', anchor_x = 200, anchor_z = 0, anchor_y = 0 },
        T{ record_id = '16:island:spire', zone = 16, island_id = 'spire', kind = 'island',
            name = 'spire', anchor_x = 300, anchor_z = 0, anchor_y = 0 },
        T{ record_id = '16:forward:a', zone = 16, island_id = 'root', kind = 'forward',
            anchor_x = 10, anchor_z = 0, anchor_y = 0, radius = 3,
            entity_server_id = 301, paired_server_id = 401,
            destination_island = 'east', landing_x = 100, landing_z = 0, landing_y = 0,
            availability = 'stream-open-evidence', window_seconds = 180 },
        T{ record_id = '16:forward:b', zone = 16, island_id = 'root', kind = 'forward',
            anchor_x = 20, anchor_z = 0, anchor_y = 0, radius = 3,
            entity_server_id = 302, paired_server_id = 402,
            destination_island = 'east', landing_x = 100, landing_z = 0, landing_y = 0,
            availability = 'stream-open-evidence', window_seconds = 180 },
        T{ record_id = '16:forward:c', zone = 16, island_id = 'root', kind = 'forward',
            anchor_x = 30, anchor_z = 0, anchor_y = 0, radius = 3,
            entity_server_id = 303, paired_server_id = 403,
            destination_island = 'west', landing_x = 200, landing_z = 0, landing_y = 0,
            availability = 'stream-open-evidence', window_seconds = 180 },
        T{ record_id = '16:forward:d', zone = 16, island_id = 'root', kind = 'forward',
            anchor_x = 40, anchor_z = 0, anchor_y = 0, radius = 3,
            entity_server_id = 304, paired_server_id = 404,
            destination_island = 'west', landing_x = 200, landing_z = 0, landing_y = 0,
            availability = 'stream-open-evidence', window_seconds = 180 },
        T{ record_id = '16:forward:e', zone = 16, island_id = 'east', kind = 'forward',
            anchor_x = 110, anchor_z = 0, anchor_y = 0, radius = 3,
            entity_server_id = 305, paired_server_id = 405,
            destination_island = 'spire', landing_x = 300, landing_z = 0, landing_y = 0,
            availability = 'stream-open-evidence', window_seconds = 180 },
        T{ record_id = '16:forward:f', zone = 16, island_id = 'west', kind = 'forward',
            anchor_x = 210, anchor_z = 0, anchor_y = 0, radius = 3,
            entity_server_id = 306, paired_server_id = 406,
            destination_island = 'spire', landing_x = 300, landing_z = 0, landing_y = 0,
            availability = 'stream-open-evidence', window_seconds = 180 },
    };
    accessxi.nav_promyvion_set_rows(branch_rows);
    accessxi.nav_promyvion_clear('branch-platform-setup');
    blocked_x = {};
    one_point_x = {};
    installed:clear();
    spoken:clear();
    for id = 301, 306 do
        entities[id] = rendered_stream(9);
        entities[id].server_id = id;
    end
    for id = 401, 406 do entities[id] = nil; end
    local branch_final = T{ zone = 16, name = 'Spire of Test zone line',
        x = 999, z = 999, y = 0 };
    now = now + 1000;
    accessxi.nav_promyvion_route(p(0), branch_final);
    local visited = T{};
    for _, x in ipairs(T{ 10, 20, 30, 40 }) do
        visited:append(accessxi.nav_promyvion_progress().record_id);
        now = now + 1000;
        accessxi.nav_promyvion_poll(p(x), branch_final, now);
    end
    check('platform search covers both viable branches of a split floor',
        table.concat(visited, ',') == '16:forward:a,16:forward:b,16:forward:c,16:forward:d',
        table.concat(visited, ','));
    check('the exhaustion sentence says exactly which platforms were checked',
        tostring(spoken[#spoken]):find('that can continue this route', 1, true) ~= nil,
        spoken[#spoken]);

    -- The server can open a Stream on the other viable branch.  Switching the
    -- chosen row must switch its expected landing too; otherwise a normal west
    -- landing is announced as an unexpected one merely because BFS first chose
    -- east while planning the approach.
    accessxi.nav_promyvion_clear('branch-open-landing-setup');
    installed:clear();
    spoken:clear();
    for id = 301, 306 do
        entities[id] = rendered_stream(9);
        entities[id].server_id = id;
    end
    entities[401] = live_receptacle(401, 10);
    now = now + 1000;
    accessxi.nav_promyvion_route(p(0), branch_final);
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(10), branch_final, now);
    entities[303] = rendered_stream(8);
    entities[303].server_id = 303;
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(10), branch_final, now);
    check('an opened Stream may switch to the other viable branch',
        accessxi.nav_promyvion_progress().phase == 'approach-stream'
            and accessxi.nav_promyvion_progress().record_id == '16:forward:c',
        ('%s | %s'):fmt(accessxi.nav_promyvion_progress().phase,
            accessxi.nav_promyvion_progress().record_id));
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(30), branch_final, now);
    now = now + 1000;
    accessxi.nav_promyvion_poll(p(200), branch_final, now);
    check('the chosen Stream landing is not announced as unexpected',
        tostring(spoken[#spoken]):find('floor changed. Route resumed.', 1, true) ~= nil
            and tostring(spoken[#spoken]):lower():find('different', 1, true) == nil,
        spoken[#spoken]);
    accessxi.nav_promyvion_set_rows(rows);
end

print('\n== production seam ==');
do
    local reader_chunk, reader_error = loadfile(ADDON .. [[\accessxi_reader.lua]]);
    check('the deployed addon parses before source-level seam claims can pass',
        reader_chunk ~= nil, reader_error);
    local handle = assert(io.open(ADDON .. [[\accessxi_reader.lua]], 'rb'));
    local source = handle:read('*a');
    handle:close();
    check('the deployed addon loads the Promyvion provider',
        source:find("load_code_module('promyvion_navigation'", 1, true) ~= nil);
    check('route dispatch consults the same-zone provider',
        source:find('accessxi%.nav_promyvion_route,%s*player,%s*point') ~= nil);
    check('route polling advances the transition state machine',
        source:find('nav_promyvion_poll(player, destination, now)', 1, true) ~= nil);
    check('waiting phases suppress the directional beacon',
        source:find('nav_promyvion_waiting()', 1, true) ~= nil);
    check('route ownership cancellation clears a pending Stream jump',
        source:find('nav_promyvion_clear(reason)', 1, true) ~= nil);
    check('incoming NPC updates feed the Promyvion Stream-state parser',
        source:find('capture_promyvion_entity_update_packet(e)', 1, true) ~= nil
            and source:find('nav_promyvion_entity_update_packet(data, zone, tick())', 1, true) ~= nil);
    check('Promyvion deadlines call the real route-stop path',
        source:find('stop_route = function()', 1, true) ~= nil
            and source:find('nav_route_stop()', 1, true) ~= nil);
    check('the generic nearby-zoneline shortcut cannot bypass Promyvion floor routing',
        source:find("type(accessxi.nav_promyvion_applies) == 'function'", 1, true) ~= nil
            and source:find('accessxi.nav_promyvion_applies(player, destination)', 1, true) ~= nil);
    check('the retail snapshot exposes server and event status',
        source:find('entity:GetStatusServer(index)', 1, true) ~= nil
            and source:find('entity:GetStatusEvent(index)', 1, true) ~= nil);
    check('the retail snapshot exposes animation and render evidence',
        source:find('entity:GetAnimation(index, 0)', 1, true) ~= nil
            and source:find('entity:GetRenderFlags8(index)', 1, true) ~= nil);
    check('expensive Stream evidence is requested only by the server-id snapshot',
        source:find('local function nav_entity_position(index, want_stream_evidence)', 1, true) ~= nil
            and source:find('nav_entity_position(index, true)', 1, true) ~= nil);
    check('menu route starts surface every typed provider refusal',
        source:find('nav menu start provider refused', 1, true) ~= nil);
end

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
