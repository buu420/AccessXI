-- Same-zone transport planning for Promyvion.
--
-- Each floor is a disconnected navmesh island.  A Memory Stream is a real,
-- temporary directed transition selected by the server after a paired Memory
-- Receptacle dies; it is not a long walkable leg and must never be fed to the
-- funnel as one.  This module routes only within the current island, waits
-- without a directional beacon, observes the transition, then replans from the
-- landing.  The server's chosen Stream is never predicted from static data.

local function clean(value)
    if (type(nav_clean_field) == 'function') then return nav_clean_field(value); end
    return tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('^%s+', ''):gsub('%s+$', '');
end

local function list_count(value)
    if (type(value) ~= 'table') then return 0; end
    if (type(value.len) == 'function') then
        local ok, count = pcall(value.len, value);
        if (ok) then return tonumber(count) or 0; end
    end
    return #value;
end

local function copy(value)
    if (type(value) ~= 'table') then return value; end
    local out = T{};
    for key, child in pairs(value) do out[key] = copy(child); end
    return out;
end

local function distance_3d(first, second)
    if (type(first) ~= 'table' or type(second) ~= 'table') then return math.huge; end
    local dx = (tonumber(second.x) or 0) - (tonumber(first.x) or 0);
    local dz = (tonumber(second.z) or 0) - (tonumber(first.z) or 0);
    local dy = (tonumber(second.y) or 0) - (tonumber(first.y) or 0);
    return math.sqrt((dx * dx) + (dz * dz) + (dy * dy));
end

local STREAM_WAIT_DEADLINE_MS = 600000;
-- LandSandBoat opens the chosen Stream on the receptacle's despawn, which
-- follows the death state within a tick; the retail trace of 2026-09-01 showed
-- the paired Stream rendered open eight seconds after the kill.  Twelve seconds
-- is that observation with room to spare, not a guess about server timing.
local KILL_WATCH_MS = 12000;
local JUMP_WAIT_DEADLINE_MS = 90000;
local POSITION_JUMP_DISTANCE = 50.0;

-- CLIENT-VISIBLE LIVENESS.
--
-- A despawned entity does NOT free its slot.  The client keeps the server id,
-- name, HP and last position and marks the entity only in its render flags, so
-- every one of those retained fields will happily describe something that is no
-- longer there.  Measured on 2026-09-01: Holla Stream 16843061 read rendered
-- flags (0x40400000, 0x0880) while genuinely open, and the very next snapshot
-- read the same status 8 with (0x40404000, 0x1000) after the player left it
-- behind.  Renderedness is what separates evidence from a retained value.
--
-- Arithmetic, not bit.band: this module is exercised under stock Lua 5.1, which
-- has no bit library.
local RENDER_DESPAWN_FLAG0 = 0x4000;
local RENDER_DESPAWN_FLAG1 = 0x1000;

local function has_flag(value, flag)
    value = tonumber(value);
    if (value == nil or value < 0) then return false; end
    return math.floor(value / flag) % 2 == 1;
end

-- true rendered, false despawned, nil when the snapshot cannot answer.
local function render_evidence(entity)
    if (type(entity) ~= 'table') then return nil; end
    local flags0 = tonumber(entity.render_flags_0);
    local flags1 = tonumber(entity.render_flags_1);
    if (flags0 == nil and flags1 == nil) then return nil; end
    return not (has_flag(flags1, RENDER_DESPAWN_FLAG1)
        or has_flag(flags0, RENDER_DESPAWN_FLAG0));
end

local function row_anchor(row, landing)
    local prefix = landing and 'landing_' or 'anchor_';
    return T{
        zone = tonumber(row.zone) or 0,
        name = clean(row.name),
        x = tonumber(row[prefix .. 'x']) or 0,
        z = tonumber(row[prefix .. 'z']) or 0,
        y = tonumber(row[prefix .. 'y']) or 0,
        kind = 'transport',
        source = clean(row.source),
        arrival_radius = math.max(1.5, tonumber(row.radius) or 3.0),
        promyvion_record_id = clean(row.record_id),
    };
end

local function same_destination(left, right)
    return type(left) == 'table' and type(right) == 'table'
        and tonumber(left.zone) == tonumber(right.zone)
        and clean(left.name) == clean(right.name)
        and math.abs((tonumber(left.x) or 0) - (tonumber(right.x) or 0)) <= 0.1
        and math.abs((tonumber(left.z) or 0) - (tonumber(right.z) or 0)) <= 0.1
        and math.abs((tonumber(left.y) or 0) - (tonumber(right.y) or 0)) <= 0.1;
end

local function tag_route(route, phase, row)
    for _, point in ipairs(type(route) == 'table' and route or T{}) do
        point.promyvion_phase = phase;
        point.promyvion_record_id = clean(row ~= nil and row.record_id or '');
    end
    return route;
end

local numeric_fields = {
    zone = true, anchor_x = true, anchor_z = true, anchor_y = true, radius = true,
    entity_server_id = true, paired_server_id = true, landing_x = true,
    landing_z = true, landing_y = true, window_seconds = true,
};

function accessxi.nav_promyvion_set_rows(rows)
    accessxi.nav_promyvion_rows = T{};
    accessxi.nav_promyvion_zones = {};
    for _, original in ipairs(type(rows) == 'table' and rows or T{}) do
        local row = copy(original);
        for field in pairs(numeric_fields) do
            if (row[field] ~= nil and row[field] ~= '') then row[field] = tonumber(row[field]) or 0; end
        end
        row.zone = tonumber(row.zone) or 0;
        row.island_id = clean(row.island_id);
        row.kind = clean(row.kind):lower();
        row.destination_island = clean(row.destination_island);
        accessxi.nav_promyvion_rows:append(row);

        if (row.zone > 0) then
            local zone = accessxi.nav_promyvion_zones[row.zone];
            if (zone == nil) then
                zone = { islands = {}, island_order = T{}, edges = T{},
                    edges_by_island = {}, anchors = T{}, terminal = T{} };
                accessxi.nav_promyvion_zones[row.zone] = zone;
            end
            if (row.kind == 'island' and row.island_id ~= '') then
                if (zone.islands[row.island_id] == nil) then zone.island_order:append(row.island_id); end
                zone.islands[row.island_id] = row;
                zone.anchors:append({ island = row.island_id, point = row_anchor(row, false) });
            elseif ((row.kind == 'forward' or row.kind == 'return')
                and row.island_id ~= '' and row.destination_island ~= '') then
                zone.edges:append(row);
                zone.edges_by_island[row.island_id] = zone.edges_by_island[row.island_id] or T{};
                zone.edges_by_island[row.island_id]:append(row);
                zone.anchors:append({ island = row.island_id, point = row_anchor(row, false) });
                if (row.destination_island:sub(1, 5) ~= 'zone:') then
                    zone.anchors:append({ island = row.destination_island, point = row_anchor(row, true) });
                end
            end
        end
    end

    for _, zone in pairs(accessxi.nav_promyvion_zones) do
        local has_forward = {};
        for _, edge in ipairs(zone.edges) do
            if (edge.kind == 'forward') then has_forward[edge.island_id] = true; end
        end
        for _, island in ipairs(zone.island_order) do
            if (has_forward[island] ~= true) then zone.terminal:append(island); end
        end
    end
    accessxi.nav_promyvion_data_loaded = true;
    accessxi.nav_promyvion_data_error = '';
    return list_count(accessxi.nav_promyvion_rows);
end

function accessxi.nav_promyvion_load()
    if (accessxi.nav_promyvion_data_loaded == true) then
        return list_count(accessxi.nav_promyvion_rows) > 0;
    end
    accessxi.nav_promyvion_data_loaded = true;
    accessxi.nav_promyvion_data_error = '';
    local path = accessxi_paths ~= nil and type(accessxi_paths.addon_path) == 'function'
        and accessxi_paths.addon_path('data', 'ffxi-nav-promyvion-transitions.tsv') or '';
    local handle = path ~= '' and io.open(path, 'rb') or nil;
    if (handle == nil) then
        accessxi.nav_promyvion_data_error = 'Promyvion transition data is unavailable.';
        return false;
    end
    local header, rows = nil, T{};
    for line in handle:lines() do
        line = tostring(line or ''):gsub('\r$', '');
        if (line ~= '' and line:sub(1, 1) ~= '#') then
            local fields = nav_split_tsv(line);
            if (header == nil) then
                header = fields;
            else
                local row = T{};
                for index, field in ipairs(header) do row[field] = fields[index] or ''; end
                rows:append(row);
            end
        end
    end
    handle:close();
    accessxi.nav_promyvion_set_rows(rows);
    if (list_count(rows) == 0) then
        accessxi.nav_promyvion_data_error = 'Promyvion transition data is empty.';
        return false;
    end
    log_line(('nav Promyvion topology loaded rows=%d'):fmt(list_count(rows)));
    return true;
end

function accessxi.nav_promyvion_applies(player, destination)
    if (type(player) ~= 'table' or type(destination) ~= 'table') then return false; end
    local zone = tonumber(player.zone) or 0;
    if (zone ~= tonumber(destination.zone)) then return false; end
    if (accessxi.nav_promyvion_load() ~= true) then return false; end
    return type(accessxi.nav_promyvion_zones[zone]) == 'table';
end

function accessxi.nav_promyvion_island_for_point(point, certify)
    if (type(point) ~= 'table' or accessxi.nav_promyvion_load() ~= true) then return nil; end
    local zone = accessxi.nav_promyvion_zones[tonumber(point.zone) or 0];
    if (type(zone) ~= 'table') then return nil; end

    -- The Spire is the final island's zone line.  Static island anchors are
    -- return/landing triggers, so pure nearest-anchor classification can put a
    -- distant Spire on the previous branch.  Terminality is topology evidence,
    -- not a coordinate guess.
    if (clean(point.name):lower():find('spire of ', 1, true) ~= nil
        and list_count(zone.terminal) == 1) then
        return zone.terminal[1];
    end

    local best_by_island = {};
    for _, anchor in ipairs(zone.anchors) do
        local candidate = distance_3d(point, anchor.point);
        local previous = best_by_island[anchor.island];
        if (previous == nil or candidate < previous.distance) then
            best_by_island[anchor.island] = {
                island = anchor.island,
                point = anchor.point,
                distance = candidate,
            };
        end
    end
    local ordered = T{};
    for _, candidate in pairs(best_by_island) do ordered:append(candidate); end
    table.sort(ordered, function(left, right)
        if (left.distance ~= right.distance) then return left.distance < right.distance; end
        return clean(left.island) < clean(right.island);
    end);

    if (certify == true) then
        -- Coordinates alone are not a floor identity.  Holla's Spire end is
        -- nearer a floor-one anchor than several floor-four anchors, even
        -- though the navmesh proves it is on floor four.  Ask the same mesh
        -- used for the route which island is actually connected, nearest
        -- candidate first; no result is safer than a proximity guess.
        for _, candidate in ipairs(ordered) do
            local ok, route = pcall(nav_compute_mesh_route, point, candidate.point, true);
            local count = ok and type(route) == 'table' and list_count(route) or 0;
            if (count > 1 or (count == 1 and candidate.distance <= 0.5)) then
                return candidate.island;
            end
        end
        return nil;
    end
    return ordered[1] ~= nil and ordered[1].island or nil;
end

local function next_island(zone, from_island, target_island)
    if (from_island == target_island) then return from_island; end
    local queue, head = T{ from_island }, 1;
    local seen, parent = { [from_island] = true }, {};
    while head <= list_count(queue) do
        local island = queue[head];
        head = head + 1;
        for _, edge in ipairs(zone.edges_by_island[island] or T{}) do
            local destination = clean(edge.destination_island);
            if (destination ~= '' and destination:sub(1, 5) ~= 'zone:'
                and seen[destination] ~= true) then
                seen[destination] = true;
                parent[destination] = island;
                if (destination == target_island) then
                    local step = destination;
                    while parent[step] ~= nil and parent[step] ~= from_island do
                        step = parent[step];
                    end
                    return step;
                end
                queue:append(destination);
            end
        end
    end
    return nil;
end

-- A split floor has more than one forward island, and either branch can still
-- reach the Spire.  The server chooses which Receptacle opens a Stream, so a
-- deterministic BFS tie must not erase every platform on the other viable
-- branch.  Returns remain exact: when the requested destination is behind the
-- player, only the reviewed return edge is offered.
local function forward_reaches(zone, from_island, target_island)
    from_island, target_island = clean(from_island), clean(target_island);
    if (from_island == '' or target_island == '') then return false; end
    if (from_island == target_island) then return true; end
    local queue, seen, head = T{ from_island }, { [from_island] = true }, 1;
    while head <= list_count(queue) do
        local island = queue[head];
        head = head + 1;
        for _, edge in ipairs(zone.edges_by_island[island] or T{}) do
            local destination = clean(edge.destination_island);
            if clean(edge.kind) == 'forward' and destination ~= ''
                and destination:sub(1, 5) ~= 'zone:' and seen[destination] ~= true then
                if destination == target_island then return true; end
                seen[destination] = true;
                queue:append(destination);
            end
        end
    end
    return false;
end

local function transition_candidates(zone, island, next_id, target_island)
    local exact, forward_search = T{}, false;
    for _, row in ipairs(zone.edges_by_island[island] or T{}) do
        if (clean(row.destination_island) == clean(next_id)) then
            exact:append(row);
            if clean(row.kind) == 'forward' then forward_search = true; end
        end
    end
    local rows = exact;
    if (forward_search) then
        rows = T{};
        for _, row in ipairs(zone.edges_by_island[island] or T{}) do
            if clean(row.kind) == 'forward'
                and forward_reaches(zone, row.destination_island, target_island) then
                rows:append(row);
            end
        end
    end
    table.sort(rows, function(left, right)
        return clean(left.record_id) < clean(right.record_id);
    end);
    return rows;
end

-- MEMORY STREAM STATE FROM THE SERVER'S NPC UPDATE.
--
-- LandSandBoat's Promyvion script opens the selected Stream with openDoor(180).
-- Its entity packet writes the NPC animation at byte 0x1F whenever mask bit
-- 0x04 is present; the shared door constants are 8=open and 9=closed.  Windower
-- independently documents the same retail 0x00E offsets and mask.  Exact
-- values are evidence; every other value remains unknown.
function accessxi.nav_promyvion_packet_zone(zone)
    zone = tonumber(zone) or 0;
    if tonumber(accessxi.nav_promyvion_packet_zone_id) ~= zone then
        accessxi.nav_promyvion_packet_zone_id = zone;
        accessxi.nav_promyvion_packet_states = {};
        -- A kill witnessed in the Promyvion just left says nothing about the
        -- one being entered now.
        if (type(accessxi.nav_promyvion_forget_defeats) == 'function') then
            accessxi.nav_promyvion_forget_defeats();
        end
    end
end

function accessxi.nav_promyvion_entity_update_packet(data, zone, now)
    zone = tonumber(zone) or 0;
    accessxi.nav_promyvion_packet_zone(zone);
    if (zone ~= 16 and zone ~= 18 and zone ~= 20 and zone ~= 22)
        or type(data) ~= 'string' or #data < 0x20 then
        return false;
    end
    local mask = string.byte(data, 0x0A + 1) or 0;
    if (math.floor(mask / 0x04) % 2) ~= 1 then return false; end
    local b1 = string.byte(data, 0x04 + 1) or 0;
    local b2 = string.byte(data, 0x05 + 1) or 0;
    local b3 = string.byte(data, 0x06 + 1) or 0;
    local b4 = string.byte(data, 0x07 + 1) or 0;
    local server_id = b1 + (b2 * 256) + (b3 * 65536) + (b4 * 16777216);
    if (server_id <= 0) then return false; end
    local animation = string.byte(data, 0x1F + 1) or -1;
    accessxi.nav_promyvion_packet_states = accessxi.nav_promyvion_packet_states or {};
    local previous = accessxi.nav_promyvion_packet_states[server_id];
    accessxi.nav_promyvion_packet_states[server_id] = {
        animation = animation,
        tick = tonumber(now) or tick(),
        zone = zone,
    };
    if (animation == 8 or animation == 9) and (type(previous) ~= 'table'
        or tonumber(previous.animation) ~= animation) then
        log_line(('nav Promyvion Stream packet server=%d state=%s animation=%d mask=0x%02X'):fmt(
            server_id, animation == 8 and 'open' or 'closed', animation, mask));
    end
    return true;
end

function accessxi.nav_promyvion_packet_stream_state(server_id, zone, window_seconds, now)
    server_id = tonumber(server_id) or 0;
    zone = tonumber(zone) or 0;
    if tonumber(accessxi.nav_promyvion_packet_zone_id) ~= zone
        or type(accessxi.nav_promyvion_packet_states) ~= 'table' then
        return 'unknown';
    end
    local record = accessxi.nav_promyvion_packet_states[server_id];
    if (type(record) ~= 'table' or tonumber(record.zone) ~= zone) then return 'unknown'; end
    local animation = tonumber(record.animation) or -1;
    if (animation == 8 or animation == 9) then
        local age = (tonumber(now) or tick()) - (tonumber(record.tick) or 0);
        local window_ms = math.max(0, tonumber(window_seconds) or 0) * 1000;
        if (age >= 0 and window_ms > 0 and age <= window_ms) then
            return animation == 8 and 'open' or 'closed';
        end
    end
    return 'unknown';
end

function accessxi.nav_promyvion_stream_state(entity)
    if (type(entity) == 'table') then
        local explicit = clean(entity.promyvion_stream_state):lower();
        if (explicit == 'open' or explicit == 'closed') then return explicit; end
    end
    -- The client's entity Status is the ANIMATIONTYPE byte the server writes at
    -- packet offset 0x1F, not xi::Status: 8 is OPEN_DOOR and 9 is CLOSE_DOOR.
    -- Retail confirmed it on 2026-09-01 -- Stream 16843061 read rendered 9,
    -- Receptacle 16842781 died at 09:18:51, and the Stream read rendered 8 by
    -- 09:18:59, with two never-killed Streams holding at 9 as controls.
    -- Anything else, including a retained 8 on a despawned slot, is unknown.
    if (render_evidence(entity) ~= true) then return 'unknown'; end
    local status = tonumber(entity.status);
    if (status == nil) then status = tonumber(entity.status_server); end
    if (status == 8) then return 'open'; end
    if (status == 9) then return 'closed'; end
    return 'unknown';
end

-- Witnessed deaths, keyed by server id.  A kill the player heard happen is
-- evidence; an empty entity slot never is, because the server sends the byte
-- identical despawn for a death and for walking out of range.
--
-- Deliberately short lived: it is dropped when the route ends and when the
-- player changes zone, and any rendered sighting of the mob clears its own
-- entry.  Receptacles respawn, and this addon may not quote a respawn time, so
-- a memory that outlived one would start answering observed-dead about a mob
-- that is standing there again.  Fail toward unknown instead.
local witnessed_defeats = {};

function accessxi.nav_promyvion_receptacle_state(entity, server_id)
    local id = tonumber(server_id) or 0;
    local exact = id > 0 and type(entity) == 'table'
        and (tonumber(entity.server_id) or 0) == id;
    local rendered = render_evidence(entity);
    local status = type(entity) == 'table' and tonumber(entity.status) or nil;
    local hp = type(entity) == 'table' and tonumber(entity.hp) or nil;

    -- Standing here now outranks anything remembered: it respawned.
    if (exact and rendered == true and (hp or 0) > 0
        and status ~= 2 and status ~= 3) then
        witnessed_defeats[id] = nil;
        return 'present';
    end
    if (id > 0 and witnessed_defeats[id] ~= nil) then return 'observed-dead'; end
    if (exact and rendered == true and hp == 0 and status == 3) then
        return 'observed-dead';
    end
    -- Missing, despawned, or simply outside client range.  Never dead.
    return 'unknown';
end

-- Reported by the battle-message reader for a defeat the client actually
-- witnessed.  Arming the paired-Stream observation is deliberately narrow: only
-- the Receptacle this route is currently working on starts the clock.
function accessxi.nav_promyvion_receptacle_defeated(server_id, now)
    local id = tonumber(server_id) or 0;
    if (id <= 0) then return false; end
    now = tonumber(now) or tick();

    local state = accessxi.nav_promyvion_state;
    local row = type(state) == 'table' and state.transition or nil;
    if (type(row) ~= 'table' or (tonumber(row.paired_server_id) or 0) ~= id) then
        return false;
    end
    -- Do not bank a nearby party's kill for a platform this route may visit
    -- much later.  Without a trustworthy respawn timer that memory can turn a
    -- respawned mob outside render range into a false observed-dead claim.
    witnessed_defeats[id] = now;
    state.kill_watch_tick = now;
    log_line(('nav Promyvion Receptacle defeated server=%d record="%s"'):fmt(
        id, clean(row.record_id)));
    return true;
end

function accessxi.nav_promyvion_forget_defeats()
    witnessed_defeats = {};
end

local function receptacle_snapshot(row)
    local id = tonumber(type(row) == 'table' and row.paired_server_id or 0) or 0;
    if (id <= 0 or type(entity_snapshot) ~= 'function') then return nil, id; end
    local ok, snapshot = pcall(entity_snapshot, id);
    return (ok and snapshot or nil), id;
end

local function receptacle_present(row)
    local snapshot, id = receptacle_snapshot(row);
    local ok, state = pcall(accessxi.nav_promyvion_receptacle_state, snapshot, id);
    return ok and state == 'present';
end

local function stream_state(row)
    if (clean(row.availability) == 'always') then return 'open'; end
    local packet_state = accessxi.nav_promyvion_packet_stream_state(
        tonumber(row.entity_server_id) or 0,
        tonumber(row.zone) or 0,
        tonumber(row.window_seconds) or 0,
        tick());
    if (packet_state ~= 'unknown') then return packet_state; end
    local snapshot = type(entity_snapshot) == 'function'
        and entity_snapshot(tonumber(row.entity_server_id) or 0) or nil;
    local ok, state = pcall(accessxi.nav_promyvion_stream_state, snapshot);
    if (not ok) then return 'unknown'; end
    state = clean(state):lower();
    return (state == 'open' or state == 'closed') and state or 'unknown';
end

local function route_to(player, row, phase)
    local target = row_anchor(row, false);
    if (phase == 'approach-receptacle') then
        -- A topology coordinate is where a Receptacle SPAWNS, not proof that
        -- one is standing there, so it is named for what it is.  Only a
        -- rendered snapshot under the exact paired id upgrades it to the mob
        -- itself, and then the mob's own coordinates are the target.
        target.name = 'Memory Receptacle search platform';
        target.server_id = tonumber(row.paired_server_id) or 0;
        local snapshot, id = receptacle_snapshot(row);
        local ok, live = pcall(accessxi.nav_promyvion_receptacle_state, snapshot, id);
        if (ok and live == 'present') then
            target.name = 'Memory Receptacle';
            target.x = tonumber(snapshot.x) or target.x;
            target.z = tonumber(snapshot.z) or target.z;
            target.y = tonumber(snapshot.y) or target.y;
            target.server_id = tonumber(snapshot.server_id) or target.server_id;
        end
    elseif row.kind == 'return' then
        target.name = 'Return Memory Stream';
    else
        target.name = 'Memory Stream';
        target.server_id = tonumber(row.entity_server_id) or 0;
    end
    local ok, route = pcall(nav_compute_mesh_route, player, target, true);
    if (not ok or type(route) ~= 'table') then return nil, target; end
    if (list_count(route) <= 1) then
        local radius = math.max(3.0, tonumber(row.radius) or 3.0) + 1.0;
        local vertical = math.abs((tonumber(player.y) or 0) - (tonumber(target.y) or 0));
        if (nav_distance(player, target) > radius or vertical > 6.0) then return nil, target; end
        -- FFXINAV returns one point when the player is already snapped onto
        -- the requested trigger.  That is arrival evidence, not a no-path.
        -- A two-point bounded approach lets the normal route-start contract
        -- run; the next poll immediately clears it into the waiting phase.
        route = T{ copy(player), copy(target) };
    end
    accessxi.nav_route_last_reject_reason = '';
    return tag_route(route, phase, row), target;
end

local function destination_copy(destination)
    return T{
        zone = tonumber(destination.zone) or 0, name = clean(destination.name),
        x = tonumber(destination.x) or 0, z = tonumber(destination.z) or 0,
        y = tonumber(destination.y) or 0, kind = clean(destination.kind),
        source = clean(destination.source), arrival_radius = tonumber(destination.arrival_radius),
    };
end

local function transition_landing_islands(zone, row)
    local islands = {};
    local destination = clean(type(row) == 'table' and row.destination_island or '');
    if (destination ~= '') then islands[destination] = true; end
    if (type(zone) ~= 'table' or type(row) ~= 'table' or row.kind ~= 'return') then
        return islands;
    end

    -- Holla, Dem and Mea each have one last-floor return whose destination is
    -- chosen by a server charvar.  The reviewed data therefore has two rows at
    -- one physical trigger.  They are possible landings, not two controls the
    -- player can choose between, so accept either observed landing and replan
    -- from where retail actually put the player.
    for _, candidate in ipairs(zone.edges_by_island[row.island_id] or T{}) do
        if candidate.kind == 'return'
            and math.abs((tonumber(candidate.anchor_x) or 0) - (tonumber(row.anchor_x) or 0)) <= 0.1
            and math.abs((tonumber(candidate.anchor_z) or 0) - (tonumber(row.anchor_z) or 0)) <= 0.1
            and math.abs((tonumber(candidate.anchor_y) or 0) - (tonumber(row.anchor_y) or 0)) <= 0.1 then
            local possible = clean(candidate.destination_island);
            if (possible ~= '') then islands[possible] = true; end
        end
    end
    return islands;
end

local function set_state(player, destination, current, target, next_id, rows, row, phase, message)
    local zone = accessxi.nav_promyvion_zones[tonumber(player.zone) or 0];
    accessxi.nav_promyvion_state = T{
        zone = tonumber(player.zone) or 0,
        island = current,
        target_island = target,
        -- The row actually selected owns the landing.  On a split floor it
        -- may differ from the deterministic BFS tie used to build candidates.
        next_island = clean(type(row) == 'table' and row.destination_island or '') ~= ''
            and clean(row.destination_island) or next_id,
        candidate_rows = rows,
        transition = row,
        landing_islands = transition_landing_islands(zone, row),
        transition_kind = clean(row ~= nil and row.kind or ''),
        phase = phase,
        destination = destination_copy(destination),
        start_message = clean(message),
        last_prompt_tick = 0,
        opened_tick = phase == 'approach-stream'
            and clean(row ~= nil and row.availability or '') ~= 'always' and tick() or 0,
        wait_started_tick = 0,
        wait_origin = copy(player),
        kill_watch_tick = 0,
        visited_platforms = {},
        platforms_exhausted = false,
    };
end

local function plan_transition(player, destination, current, target, speak_expiry)
    local zone = accessxi.nav_promyvion_zones[tonumber(player.zone) or 0];
    local next_id = next_island(zone, current, target);
    if (next_id == nil) then
        return T{}, 'unavailable', 'No reviewed Promyvion transition connects these floors.';
    end
    local rows = transition_candidates(zone, current, next_id, target);
    if (list_count(rows) == 0) then
        return T{}, 'unavailable', 'The reviewed Promyvion transition is missing.';
    end

    -- Always-open returns and positively observed open Streams go first.
    for _, row in ipairs(rows) do
        if (stream_state(row) == 'open') then
            local route = route_to(player, row, 'approach-stream');
            if (route ~= nil) then
                local message = row.kind == 'return'
                    and 'Starting route to the return Memory Stream.'
                    or 'Memory Stream open for about three minutes. Starting route.';
                set_state(player, destination, current, target, next_id, rows, row,
                    'approach-stream', message);
                if (speak_expiry == true and row.kind ~= 'return') then speak(message); end
                return route, 'route', message;
            end
        end
    end

    local ordered = T{};
    for _, row in ipairs(rows) do ordered:append(row); end
    table.sort(ordered, function(left, right)
        local ld = nav_distance(player, row_anchor(left, false));
        local rd = nav_distance(player, row_anchor(right, false));
        if (ld ~= rd) then return ld < rd; end
        return clean(left.record_id) < clean(right.record_id);
    end);
    local saw_unknown = false;
    for _, row in ipairs(rows) do
        if (stream_state(row) == 'unknown') then saw_unknown = true; end
    end
    local message = saw_unknown
        and 'No Memory Stream on this floor is confirmed open. Defeat a Memory Receptacle.'
        or 'No Memory Stream on this floor is open. Defeat a Memory Receptacle.';
    for _, row in ipairs(ordered) do
        local route = route_to(player, row, 'approach-receptacle');
        if (route ~= nil) then
            set_state(player, destination, current, target, next_id, rows, row,
                'approach-receptacle', message);
            if (speak_expiry == true) then
                speak('The Memory Stream closed. Returning to the Receptacle search.');
            end
            return route, 'route', message;
        end
    end
    return T{}, 'unavailable',
        'I cannot verify a safe route to a Memory Receptacle on this floor.';
end

function accessxi.nav_promyvion_route(player, destination)
    local empty = T{};
    if (not accessxi.nav_promyvion_applies(player, destination)) then
        return empty, 'unavailable', clean(accessxi.nav_promyvion_data_error);
    end
    -- The route itself is stronger floor evidence than any anchor.  This is
    -- also the cheap path for ordinary same-floor destinations.
    local direct_ok, direct = pcall(nav_compute_mesh_route, player, destination, true);
    if (direct_ok and type(direct) == 'table' and list_count(direct) > 1) then
        accessxi.nav_route_last_reject_reason = '';
        accessxi.nav_promyvion_clear('same-island');
        return direct, 'same-island', '';
    end

    local current = accessxi.nav_promyvion_island_for_point(player, true);
    local target = accessxi.nav_promyvion_island_for_point(destination, true);
    if (current == nil or target == nil) then
        return empty, 'unavailable', 'I cannot identify the current Promyvion floor safely.';
    end
    if (current == target) then
        return empty, 'unavailable', 'I cannot verify a walkable route on this Promyvion floor.';
    end
    return plan_transition(player, destination, current, target, false);
end

function accessxi.nav_promyvion_start_suffix()
    local state = accessxi.nav_promyvion_state;
    if (type(state) ~= 'table' or clean(state.start_message) == '') then return ''; end
    return ' ' .. clean(state.start_message);
end

function accessxi.nav_promyvion_waiting()
    local phase = clean(type(accessxi.nav_promyvion_state) == 'table'
        and accessxi.nav_promyvion_state.phase or '');
    return phase == 'waiting-for-stream' or phase == 'waiting-for-jump';
end

local function near_anchor(player, row, landing)
    local anchor = row_anchor(row, landing);
    local radius = math.max(3.0, tonumber(row.radius) or 3.0) + 1.0;
    return nav_distance(player, anchor) <= radius
        and math.abs((tonumber(player.y) or 0) - (tonumber(anchor.y) or 0)) <= 6.0;
end

local function install(player, destination, route)
    if (type(install_route) == 'function') then
        install_route(player, destination, route);
    end
end

local function clear_active_route()
    if (type(clear_route) == 'function') then clear_route(); end
end

-- A wait deliberately clears only the current polyline because the objective
-- and its ownership must survive the transport.  A failure or deadline is the
-- opposite contract: it must end navigation itself, or the ordinary empty-route
-- poll silently recreates the route after speech has said it stopped.
local function stop_active_route(reason)
    accessxi.nav_promyvion_clear(reason);
    if (type(stop_route) == 'function') then
        stop_route();
    else
        clear_active_route();
    end
end

-- EVERY PLATFORM ONCE, THEN STOP.
--
-- A floor has one to four Receptacle platforms and the server's chosen portal
-- is invisible, so the only honest search is to check each platform once, say
-- what was found there, and hold.  Walking a blind player around the same loop
-- forever would be worse than saying nothing.
local function advance_to_unvisited_platform(player, destination, state, now, message)
    state.visited_platforms = state.visited_platforms or {};
    state.visited_platforms[clean(type(state.transition) == 'table'
        and state.transition.record_id or '')] = true;
    state.kill_watch_tick = 0;

    for _, candidate in ipairs(state.candidate_rows or T{}) do
        if (clean(candidate.kind) ~= 'return'
            and state.visited_platforms[clean(candidate.record_id)] ~= true) then
            local route = route_to(player, candidate, 'approach-receptacle');
            if (route ~= nil) then
                state.transition = candidate;
                state.transition_kind = clean(candidate.kind);
                state.next_island = clean(candidate.destination_island);
                state.landing_islands = transition_landing_islands(
                    accessxi.nav_promyvion_zones[tonumber(state.zone) or 0], candidate);
                state.phase = 'approach-receptacle';
                state.last_prompt_tick = 0;
                install(player, destination, route);
                speak(message .. ' Routing to the next Memory Receptacle platform.');
                return true;
            end
            state.visited_platforms[clean(candidate.record_id)] = true;
        end
    end

    -- Nothing left to check on this floor.  Hold the bounded wait where the
    -- player already is; its ten-minute deadline still governs.
    if (state.phase ~= 'waiting-for-stream') then
        state.phase = 'waiting-for-stream';
        state.wait_started_tick = now;
        state.wait_origin = copy(player);
        clear_active_route();
    end
    state.last_prompt_tick = now;
    if (state.platforms_exhausted ~= true) then
        state.platforms_exhausted = true;
        speak(message .. ' Every Memory Receptacle platform that can continue this route'
            .. ' on this floor has been checked. Enter any Memory Stream you can find,'
            .. ' or search again.');
    end
    return true;
end

local function replan_after_floor_change(player, state, unexpected)
    local saved_destination = copy(state.destination);
    accessxi.nav_promyvion_state = nil;
    local route, mode, message = accessxi.nav_promyvion_route(player, saved_destination);
    if ((mode == 'route' or mode == 'same-island') and list_count(route) > 1) then
        install(player, saved_destination, route);
        local prefix = unexpected == true
            and 'The Stream landed on a different Promyvion floor. Route recalculated.'
            or 'Promyvion floor changed. Route resumed.';
        speak(prefix .. accessxi.nav_promyvion_start_suffix());
    else
        stop_active_route('floor-change-unavailable');
        speak(clean(message) ~= '' and clean(message)
            or 'The Promyvion floor changed, but I cannot verify the next route.');
    end
    return true;
end

local function observed_floor_change(player, state)
    local origin = type(state.wait_origin) == 'table' and state.wait_origin or state.pre_jump;
    if (distance_3d(origin, player) < POSITION_JUMP_DISTANCE) then return nil; end
    local landed = accessxi.nav_promyvion_island_for_point(player, true);
    if (landed ~= nil and landed ~= clean(state.island)) then return landed; end
    -- Walking away on the same floor is not a portal.  Move the comparison
    -- origin so an ordinary long walk does not force an expensive probe every
    -- pulse thereafter.
    if (landed ~= nil) then state.wait_origin = copy(player); end
    return nil;
end

function accessxi.nav_promyvion_poll(player, destination, now)
    local state = accessxi.nav_promyvion_state;
    if (type(state) ~= 'table') then return false; end
    now = tonumber(now) or tick();
    if (type(player) ~= 'table' or tonumber(player.zone) ~= tonumber(state.zone)
        or not same_destination(state.destination, destination)) then
        accessxi.nav_promyvion_clear('owner-changed');
        return false;
    end
    local row = state.transition;
    if (type(row) ~= 'table') then
        accessxi.nav_promyvion_clear('transition-missing');
        return false;
    end

    if (state.phase == 'approach-receptacle') then
        -- The kill owns the next twelve seconds even when a Trust lands it
        -- before the player reaches the anchor.  Waiting for proximity first
        -- reclassified the vanished mob as an empty platform and routed away
        -- from the Stream that retail opened eight seconds later.
        if ((tonumber(state.kill_watch_tick) or 0) > 0) then
            state.phase = 'waiting-for-stream';
            state.last_prompt_tick = now;
            state.wait_started_tick = now;
            state.wait_origin = copy(player);
            clear_active_route();
            speak('Memory Receptacle defeated. Checking its Memory Stream.');
            return true;
        end
        if (not near_anchor(player, row, false)) then return false; end
        -- Arriving is not finding.  Absence is reported as absence: it may be a
        -- kill somebody else made, or simply nothing loaded, and the client
        -- cannot tell those apart.
        if (not receptacle_present(row)) then
            return advance_to_unvisited_platform(player, destination, state, now,
                'Nothing is standing here right now.');
        end
        state.phase = 'waiting-for-stream';
        state.last_prompt_tick = now;
        state.wait_started_tick = now;
        state.wait_origin = copy(player);
        clear_active_route();
        speak('Defeat this Memory Receptacle. I will tell you if a Stream opens.');
        return true;
    end

    if (state.phase == 'waiting-for-stream') then
        if (observed_floor_change(player, state) ~= nil) then
            return replan_after_floor_change(player, state);
        end
        for _, candidate in ipairs(state.candidate_rows or T{}) do
            if (stream_state(candidate) == 'open') then
                local route = route_to(player, candidate, 'approach-stream');
                if (route ~= nil) then
                    state.transition = candidate;
                    state.transition_kind = clean(candidate.kind);
                    state.next_island = clean(candidate.destination_island);
                    state.landing_islands = transition_landing_islands(
                        accessxi.nav_promyvion_zones[tonumber(state.zone) or 0], candidate);
                    state.phase = 'approach-stream';
                    state.opened_tick = now;
                    state.last_prompt_tick = now;
                    state.wait_started_tick = 0;
                    state.wait_origin = copy(player);
                    install(player, destination, route);
                    speak('Memory Stream open for about three minutes. Starting route.');
                    return true;
                end
            end
        end
        -- A witnessed kill has an answer within seconds.  Positively closed
        -- means that platform led nowhere; unobservable means exactly that, and
        -- must never be dressed up as a decoy, because leaving on that basis
        -- could abandon a portal that opened where the addon could not see it.
        local watch = tonumber(state.kill_watch_tick) or 0;
        if (watch > 0 and (now - watch) >= KILL_WATCH_MS) then
            state.kill_watch_tick = 0;
            if (stream_state(row) == 'closed') then
                return advance_to_unvisited_platform(player, destination, state, now,
                    'That Memory Receptacle did not open a Memory Stream.');
            end
            state.last_prompt_tick = now;
            speak('I could not confirm whether a Memory Stream opened.'
                .. ' Enter any Memory Stream you can find, or search again.');
            return true;
        end
        if ((now - (tonumber(state.wait_started_tick) or now)) >= STREAM_WAIT_DEADLINE_MS) then
            stop_active_route('stream-wait-timeout');
            speak('No Memory Stream was confirmed after ten minutes. Route stopped. Start it again when ready.');
            return true;
        end
        if ((now - (tonumber(state.last_prompt_tick) or 0)) >= 12000) then
            state.last_prompt_tick = now;
            speak('No Memory Stream is confirmed open yet. Defeat a Memory Receptacle.');
        end
        return true;
    end

    if (state.phase == 'approach-stream') then
        local window_ms = math.max(0, tonumber(row.window_seconds) or 0) * 1000;
        local expired = clean(row.availability) ~= 'always'
            and window_ms > 0 and (tonumber(state.opened_tick) or 0) > 0
            and (now - (tonumber(state.opened_tick) or 0)) >= window_ms;
        if (expired or (clean(row.availability) ~= 'always' and stream_state(row) == 'closed')) then
            local current = accessxi.nav_promyvion_island_for_point(player, true) or state.island;
            local route, mode, message = plan_transition(
                player, destination, current, state.target_island, true);
            if (mode == 'route' and list_count(route) > 1) then install(player, destination, route); end
            if (mode == 'unavailable') then
                stop_active_route('stream-expired-unavailable');
                speak(clean(message));
                return true;
            end
            return mode ~= 'route';
        end
        if (not near_anchor(player, row, false)) then return false; end
        state.phase = 'waiting-for-jump';
        state.last_prompt_tick = now;
        state.pre_jump = copy(player);
        state.wait_origin = copy(player);
        state.wait_started_tick = now;
        clear_active_route();
        speak('Enter the Memory Stream. Navigation will resume after the jump.');
        return true;
    end

    if (state.phase == 'waiting-for-jump') then
        local landed = observed_floor_change(player, state);
        if (landed ~= nil) then
            if (type(state.landing_islands) == 'table' and state.landing_islands[landed] == true) then
                return replan_after_floor_change(player, state);
            end
            return replan_after_floor_change(player, state, true);
        end
        if ((now - (tonumber(state.wait_started_tick) or now)) >= JUMP_WAIT_DEADLINE_MS) then
            stop_active_route('jump-wait-timeout');
            speak('I did not detect the Promyvion jump. Route stopped. Start it again after crossing the Stream.');
            return true;
        end
        if ((now - (tonumber(state.last_prompt_tick) or 0)) >= 8000) then
            state.last_prompt_tick = now;
            speak('Enter the Memory Stream. Navigation will resume after the jump.');
        end
        return true;
    end
    return false;
end

function accessxi.nav_promyvion_clear(reason)
    local state = accessxi.nav_promyvion_state;
    accessxi.nav_promyvion_state = nil;
    accessxi.nav_promyvion_forget_defeats();
    if (state ~= nil) then
        log_line(('nav Promyvion clear phase="%s" island="%s" reason="%s"'):fmt(
            clean(state.phase), clean(state.island), clean(reason)));
    end
end

function accessxi.nav_promyvion_progress()
    local state = accessxi.nav_promyvion_state;
    if (type(state) ~= 'table') then
        return T{ phase = '', island = '', target_island = '', next_island = '',
            transition_kind = '', record_id = '' };
    end
    return T{
        phase = clean(state.phase), island = clean(state.island),
        target_island = clean(state.target_island), next_island = clean(state.next_island),
        transition_kind = clean(state.transition_kind),
        record_id = clean(type(state.transition) == 'table' and state.transition.record_id or ''),
    };
end

local function probe_value(entity, field)
    local value = type(entity) == 'table' and entity[field] or nil;
    return value == nil and '-' or tostring(value);
end

function accessxi.nav_promyvion_probe(player, now)
    if (type(player) ~= 'table' or accessxi.nav_promyvion_load() ~= true) then return false; end
    local zone = accessxi.nav_promyvion_zones[tonumber(player.zone) or 0];
    if (type(zone) ~= 'table' or type(entity_snapshot) ~= 'function') then return false; end
    now = tonumber(now) or tick();
    if ((now - (tonumber(accessxi.nav_promyvion_probe_tick) or 0)) < 500) then return false; end
    accessxi.nav_promyvion_probe_tick = now;
    accessxi.nav_promyvion_probe_keys = accessxi.nav_promyvion_probe_keys or {};
    -- Only a Stream on the floor the player occupies can be useful. Reading
    -- all eleven every half second forces the shared server-id snapshot to do
    -- work for disconnected floors the player cannot see or enter yet.
    local island = accessxi.nav_promyvion_island_for_point(player);
    for _, row in ipairs(zone.edges_by_island[island] or T{}) do
        if (row.kind == 'forward' and (tonumber(row.entity_server_id) or 0) > 0) then
            local entity = entity_snapshot(row.entity_server_id);
            if (type(entity) == 'table') then
                local parts = T{
                    ('status=%s'):fmt(probe_value(entity, 'status')),
                    ('server=%s'):fmt(probe_value(entity, 'status_server')),
                    ('event=%s'):fmt(probe_value(entity, 'status_event')),
                    ('spawn=%s'):fmt(probe_value(entity, 'spawn_flags')),
                };
                for index = 0, 3 do
                    parts:append(('anim%d=%s'):fmt(index, probe_value(entity, 'animation_' .. index)));
                end
                for index = 0, 8 do
                    parts:append(('render%d=%s'):fmt(index, probe_value(entity, 'render_flags_' .. index)));
                end
                local key = table.concat(parts, ' ');
                local id = clean(row.record_id);
                if (key ~= accessxi.nav_promyvion_probe_keys[id]) then
                    accessxi.nav_promyvion_probe_keys[id] = key;
                    log_line(('nav Promyvion Stream probe record="%s" entity=%d state=%s %s'):fmt(
                        id, tonumber(row.entity_server_id) or 0,
                        accessxi.nav_promyvion_stream_state(entity), key));
                end
            end
        end
    end
    return true;
end
