local zone_id = 191;
local destination_match_radius = 6.0;
local destination_vertical_tolerance = 4.0;
local drop_approach_radius = 30.0;
local drop_approach_vertical_tolerance = 5.5;
local drop_continuation_probe_radius = 45.0;
local drop_prompt_repeat_ms = 15000;

-- Current native zone entities from ffxi-nav-destinations.tsv. The published
-- route reaches the fount through the false wall toward the Strange Apparatus,
-- then uses the one-way hole immediately before this door.
local fount = T{
    zone = zone_id,
    name = 'Geomagnetic Fount',
    x = -480.364,
    z = -58.355,
    y = 2.457,
    kind = 'object',
    source = 'lsb-npc-list-all:world-npcs-2026-06-20',
};

local cermet_door = T{
    zone = zone_id,
    name = 'Cermet Door',
    x = -466.483,
    z = -100.001,
    y = -6.730,
    kind = 'object',
    source = 'lsb-npc-list-all:world-npcs-2026-06-20',
};

local function point_copy(point)
    if (point == nil) then
        return nil;
    end
    return T{
        zone = tonumber(point.zone) or 0,
        name = tostring(point.name or ''),
        x = tonumber(point.x) or 0,
        z = tonumber(point.z) or 0,
        y = tonumber(point.y) or 0,
        kind = tostring(point.kind or ''),
        source = tostring(point.source or ''),
    };
end

local function vertical_distance(a, b)
    return math.abs((tonumber(a ~= nil and a.y) or 0) - (tonumber(b ~= nil and b.y) or 0));
end

local function point_matches(point, reference, horizontal_tolerance, vertical_tolerance)
    if (point == nil or reference == nil
        or (tonumber(point.zone) or 0) ~= (tonumber(reference.zone) or 0)) then
        return false;
    end
    return nav_distance(point, reference) <= (tonumber(horizontal_tolerance) or 0)
        and vertical_distance(point, reference) <= (tonumber(vertical_tolerance) or 0);
end

local function destination_is_fount(destination)
    return destination ~= nil
        and tostring(destination.name or ''):lower() == 'geomagnetic fount'
        and point_matches(
            destination,
            fount,
            destination_match_radius,
            destination_vertical_tolerance);
end

local function transition_destination_matches(state, destination)
    return state ~= nil
        and destination_is_fount(destination)
        and state.destination ~= nil
        and point_matches(
            destination,
            state.destination,
            destination_match_radius,
            destination_vertical_tolerance);
end

local function tag_route(route, phase)
    for _, point in ipairs(route or T{}) do
        point.special_transition_id = 'dangruf-fount-drop';
        point.special_transition_phase = phase;
    end
    return route;
end

local function reset_route_runtime(player, destination, route, now)
    accessxi.nav_route_points = route;
    accessxi.nav_route_point_index = accessxi.nav_first_route_index(player, route, destination);
    accessxi.nav_route_last_recalc_tick = now;
    accessxi.nav_route_live_replan_last_key = '';
    accessxi.nav_route_live_replan_last_tick = now;
    accessxi.nav_last_key = '';
    accessxi.nav_last_direction_text = '';
    accessxi.nav_beacon_last_key = '';
    accessxi.nav_beacon_last_tick = 0;
    if (type(accessxi.nav_reset_progress_watch) == 'function') then
        accessxi.nav_reset_progress_watch(nil, 0, now);
    else
        accessxi.nav_progress_x = nil;
        accessxi.nav_progress_z = nil;
        accessxi.nav_progress_distance = 0;
        accessxi.nav_progress_tick = now;
    end
    if (type(accessxi.nav_collision_reset) == 'function') then
        accessxi.nav_collision_reset(nil, 0, 0, now);
    else
        accessxi.nav_collision_x = nil;
        accessxi.nav_collision_z = nil;
        accessxi.nav_collision_tick = now;
    end
end

local function drop_instruction()
    return 'At the hidden passage. Continue through the false wall toward the Cermet Door, then fall through the hole immediately before the door. The route will resume after you land.';
end

function accessxi.nav_dangruf_fount_drop_clear(reason)
    local state = accessxi.nav_dangruf_fount_drop_transition;
    accessxi.nav_dangruf_fount_drop_transition = nil;
    if (state ~= nil) then
        log_line(('nav Dangruf fount drop clear phase="%s" reason="%s"'):fmt(
            tostring(state.phase or ''),
            accessxi.escape_probe_log_text(reason or '')));
    end
end

function accessxi.nav_dangruf_fount_drop_route(player, destination)
    local empty = T{};
    if (player == nil or not destination_is_fount(destination)
        or (tonumber(player.zone) or 0) ~= zone_id) then
        return empty;
    end

    local approach = nav_compute_mesh_route(player, cermet_door);
    if (approach == nil or approach:len() <= 1) then
        accessxi.nav_dangruf_fount_drop_clear('approach-unavailable');
        log_line(('nav Dangruf fount drop rejected destination="%s" reason="Cermet Door approach unavailable"'):fmt(
            accessxi.escape_probe_log_text(destination.name or '')));
        return empty;
    end

    tag_route(approach, 'approach');
    accessxi.nav_dangruf_fount_drop_transition = T{
        zone = zone_id,
        phase = 'approach',
        approach = point_copy(cermet_door),
        destination = point_copy(destination),
        destination_name = tostring(destination.name or ''),
        last_prompt_tick = 0,
    };
    accessxi.nav_route_last_reject_reason = '';
    log_line(('nav Dangruf fount drop verified destination="%s" approach=%d door=(%.3f,%.3f,%.3f)'):fmt(
        accessxi.escape_probe_log_text(destination.name or ''),
        approach:len(),
        cermet_door.x,
        cermet_door.z,
        cermet_door.y));
    return approach;
end

function accessxi.nav_dangruf_fount_drop_start_suffix()
    if (accessxi.nav_dangruf_fount_drop_transition == nil) then
        return '';
    end
    return ' This route goes through the false wall toward the Strange Apparatus and uses the one-way drop immediately before the Cermet Door.';
end

function accessxi.nav_dangruf_fount_drop_beacon_target(player, now)
    local state = accessxi.nav_dangruf_fount_drop_transition;
    if (state == nil or player == nil
        or (tonumber(player.zone) or 0) ~= zone_id
        or tostring(state.phase or '') ~= 'approach'
        or not point_matches(
            player,
            state.approach,
            drop_approach_radius,
            drop_approach_vertical_tolerance)) then
        return nil, false;
    end

    local target = point_copy(state.approach);
    target.y = tonumber(player.y) or target.y;
    target.source = 'dangruf-fount-drop-beacon';
    return target, true;
end

function accessxi.nav_dangruf_fount_drop_poll(player, destination, now)
    local state = accessxi.nav_dangruf_fount_drop_transition;
    if (state == nil) then
        return false;
    end
    now = tonumber(now) or tick();

    if (player == nil or (tonumber(player.zone) or 0) ~= zone_id) then
        accessxi.nav_dangruf_fount_drop_clear('player-left-zone');
        return false;
    end
    if (not transition_destination_matches(state, destination)) then
        accessxi.nav_dangruf_fount_drop_clear('destination-changed');
        return false;
    end

    if (point_matches(
        player,
        destination,
        destination_match_radius,
        destination_vertical_tolerance)) then
        accessxi.nav_dangruf_fount_drop_clear('destination-reached');
        return false;
    end

    if (nav_distance(player, state.approach) > drop_continuation_probe_radius) then
        return false;
    end

    -- The landing is intentionally not encoded. A fresh multi-point route from
    -- the live character position is the only evidence that the one-way drop
    -- has placed the player on the fount's independently walkable component.
    local continuation = nav_compute_mesh_route(player, destination);
    if (continuation ~= nil and continuation:len() > 1) then
        tag_route(continuation, 'continuation');
        accessxi.nav_dangruf_fount_drop_clear('landing-verified');
        reset_route_runtime(player, destination, continuation, now);
        if (type(accessxi.nav_collision_quiet) == 'function') then
            accessxi.nav_collision_quiet('dangruf-fount-drop-landed', 3000, now);
        end
        local text = 'Drop complete. Route resumed to Geomagnetic Fount.';
        accessxi.nav_last_direction_text = text;
        speak(text);
        log_line(('nav Dangruf fount drop resumed count=%d player=(%.3f,%.3f,%.3f)'):fmt(
            continuation:len(),
            tonumber(player.x) or 0,
            tonumber(player.z) or 0,
            tonumber(player.y) or 0));
        return true;
    end

    if (point_matches(
        player,
        state.approach,
        drop_approach_radius,
        drop_approach_vertical_tolerance)) then
        if ((tonumber(state.last_prompt_tick) or 0) == 0
            or (now - (tonumber(state.last_prompt_tick) or 0)) >= drop_prompt_repeat_ms) then
            state.last_prompt_tick = now;
            local text = drop_instruction();
            accessxi.nav_last_key = '';
            accessxi.nav_last_direction_text = text;
            accessxi.nav_beacon_last_key = '';
            accessxi.nav_beacon_last_tick = 0;
            if (type(accessxi.nav_collision_quiet) == 'function') then
                accessxi.nav_collision_quiet('dangruf-fount-drop-approach', 6000, now);
            end
            speak(text);
            log_line('nav Dangruf fount drop waiting ' .. text);
        end
        return true;
    end

    return false;
end

return true;
