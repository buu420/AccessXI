local zone_id = 237;
local landing_radius = 3.5;
local landing_vertical_tolerance = 3.0;
local floor_vertical_tolerance = 3.25;
local zone_trigger_radius = 6.0;

-- Native verified elevator entities from the current LandSandBoat zone data.
-- Metalworks uses timed automatic elevators; Palborough uses its two Elevator
-- Levers. These are walkable interaction/handoff points, never guessed points
-- between navmesh components.
local elevators = T{
    T{
        id = 'metalworks-north-elevator',
        label = 'north Metalworks elevator',
        zone = zone_id,
        interaction = 'automatic',
        guard_metalworks_exit = true,
        platform = T{
            zone = zone_id,
            name = 'North Metalworks elevator platform',
            x = -56.006,
            z = 12.014,
            y = -13.100,
            kind = 'transport',
            source = 'lsb-native-elevator-platform:@6l0',
        },
        lower = T{
            zone = zone_id,
            name = 'North Metalworks elevator, lower door',
            x = -58.850,
            z = 12.002,
            y = 0.000,
            kind = 'transport',
            source = 'lsb-native-elevator-door:_6lv',
        },
        upper = T{
            zone = zone_id,
            name = 'North Metalworks elevator, upper door',
            x = -53.126,
            z = 12.040,
            y = -12.098,
            kind = 'transport',
            source = 'lsb-native-elevator-door:_6lu',
        },
    },
    T{
        id = 'metalworks-south-elevator',
        label = 'south Metalworks elevator',
        zone = zone_id,
        interaction = 'automatic',
        guard_metalworks_exit = true,
        platform = T{
            zone = zone_id,
            name = 'South Metalworks elevator platform',
            x = -55.978,
            z = -12.020,
            y = -13.100,
            kind = 'transport',
            source = 'lsb-native-elevator-platform:@6l1',
        },
        lower = T{
            zone = zone_id,
            name = 'South Metalworks elevator, lower door',
            x = -58.850,
            z = -11.914,
            y = 0.000,
            kind = 'transport',
            source = 'lsb-native-elevator-door:_6lt',
        },
        upper = T{
            zone = zone_id,
            name = 'South Metalworks elevator, upper door',
            x = -53.126,
            z = -11.875,
            y = -12.098,
            kind = 'transport',
            source = 'lsb-native-elevator-door:_6ls',
        },
    },
    T{
        id = 'palborough-mines-lift',
        label = 'Palborough Mines elevator',
        zone = 143,
        required_transport_id = 'palborough-mines-lift',
        interaction = 'lever',
        guard_metalworks_exit = false,
        platform = T{
            zone = 143,
            name = 'Palborough Mines elevator platform',
            x = 179.030,
            z = 62.612,
            y = -19.222,
            kind = 'transport',
            source = 'lsb-native-elevator-platform:@3z0',
        },
        lower = T{
            zone = 143,
            name = 'Elevator Lever, lower floor',
            x = 182.401,
            z = 64.408,
            y = 0.902,
            kind = 'transport',
            source = 'lsb-native-elevator-lever:_3z6',
        },
        upper = T{
            zone = 143,
            name = 'Elevator Lever, upper floor',
            x = 182.401,
            z = 64.408,
            y = -32.207,
            kind = 'transport',
            source = 'lsb-native-elevator-lever:_3z7',
        },
    },
};

-- Current Metalworks -> Bastok Markets trigger from ffxi-nav-zoneline-graph.tsv.
-- FFXINAV does not model zone triggers, so every otherwise-valid elevator leg
-- must also prove that it stays outside this trigger corridor.
local metalworks_exit = T{
    zone = zone_id,
    x = -6.175,
    z = -0.008,
    y = -2.966,
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

local function distance_3d(a, b)
    local dx = (tonumber(a ~= nil and a.x) or 0) - (tonumber(b ~= nil and b.x) or 0);
    local dz = (tonumber(a ~= nil and a.z) or 0) - (tonumber(b ~= nil and b.z) or 0);
    local dy = (tonumber(a ~= nil and a.y) or 0) - (tonumber(b ~= nil and b.y) or 0);
    return math.sqrt((dx * dx) + (dz * dz) + (dy * dy));
end

local function distance_to_segment_3d(point, a, b)
    local ax = tonumber(a ~= nil and a.x) or 0;
    local az = tonumber(a ~= nil and a.z) or 0;
    local ay = tonumber(a ~= nil and a.y) or 0;
    local bx = tonumber(b ~= nil and b.x) or 0;
    local bz = tonumber(b ~= nil and b.z) or 0;
    local by = tonumber(b ~= nil and b.y) or 0;
    local px = tonumber(point ~= nil and point.x) or 0;
    local pz = tonumber(point ~= nil and point.z) or 0;
    local py = tonumber(point ~= nil and point.y) or 0;
    local vx = bx - ax;
    local vz = bz - az;
    local vy = by - ay;
    local length_squared = (vx * vx) + (vz * vz) + (vy * vy);
    local ratio = 0;
    if (length_squared > 0.000001) then
        ratio = (((px - ax) * vx) + ((pz - az) * vz) + ((py - ay) * vy)) / length_squared;
        ratio = math.max(0, math.min(1, ratio));
    end
    local closest = T{
        x = ax + (vx * ratio),
        z = az + (vz * ratio),
        y = ay + (vy * ratio),
    };
    return distance_3d(point, closest);
end

local function route_crosses_zone_trigger(route, allow_terminal_contact)
    local count = route ~= nil and route:len() or 0;
    if (count < 2) then
        return false;
    end
    for index = 1, count - 1 do
        local first = route[index];
        local second = route[index + 1];
        local first_distance = distance_3d(first, metalworks_exit);
        local second_distance = distance_3d(second, metalworks_exit);
        local segment_distance = distance_to_segment_3d(metalworks_exit, first, second);
        if (segment_distance <= zone_trigger_radius) then
            local starts_inside_and_leaves = index == 1
                and first_distance <= zone_trigger_radius
                and second_distance >= (first_distance + 0.5)
                and segment_distance >= (first_distance - 0.25);
            local intended_terminal_contact = allow_terminal_contact == true
                and second_distance <= zone_trigger_radius;
            if (intended_terminal_contact) then
                for terminal_index = index + 1, count do
                    if (distance_3d(route[terminal_index], metalworks_exit) > zone_trigger_radius) then
                        intended_terminal_contact = false;
                        break;
                    end
                end
            end
            if (not starts_inside_and_leaves and not intended_terminal_contact) then
                return true, segment_distance, index;
            end
        end
    end
    return false;
end

local function destination_is_metalworks_exit(destination)
    return destination ~= nil
        and (tonumber(destination.zone) or 0) == zone_id
        and type(nav_point_is_zoneline) == 'function'
        and nav_point_is_zoneline(destination)
        and distance_3d(destination, metalworks_exit) <= 3.0;
end

local function route_length(route)
    local total = 0;
    local count = route ~= nil and route:len() or 0;
    for index = 1, count - 1 do
        total = total + distance_3d(route[index], route[index + 1]);
    end
    return total;
end

local function point_near_landing(point, landing, horizontal_tolerance, vertical_tolerance)
    if (point == nil or landing == nil
        or (tonumber(point.zone) or 0) ~= (tonumber(landing.zone) or 0)) then
        return false;
    end
    return nav_distance(point, landing) <= (tonumber(horizontal_tolerance) or landing_radius)
        and vertical_distance(point, landing) <= (tonumber(vertical_tolerance) or landing_vertical_tolerance);
end

local function leg_is_verified(route, start_point, end_point)
    if (route ~= nil and route:len() > 1) then
        return true;
    end
    return point_near_landing(start_point, end_point, landing_radius, landing_vertical_tolerance);
end

local function usable_leg(route, start_point, end_point)
    if (route ~= nil and route:len() > 1) then
        return route;
    end
    if (not leg_is_verified(route, start_point, end_point)) then
        return T{};
    end
    return T{ point_copy(start_point), point_copy(end_point) };
end

local function tag_leg(route, phase, direction, elevator_id)
    for _, point in ipairs(route or T{}) do
        point.transport_id = elevator_id;
        point.transport_phase = phase;
        point.transport_direction = direction;
    end
    return route;
end

local function transition_instruction(state)
    local floor = state.direction == 'up' and 'upper floor' or 'lower floor';
    if (tostring(state.interaction or '') == 'lever') then
        return ('At the %s. Target the Elevator Lever and press Enter. Choose the affirmative option, then follow the beacon onto the platform and ride to the %s. The route will resume after the live floor change.'):fmt(
            tostring(state.elevator_label or 'elevator'),
            floor);
    end
    return ('At the %s. It runs automatically. Follow the beacon through the doorway onto the platform; the beacon will go quiet once you are aboard. Ride to the %s, then the route will resume.'):fmt(
        tostring(state.elevator_label or 'Metalworks elevator'),
        floor);
end

local function transition_destination_matches(state, destination)
    if (state == nil or destination == nil
        or (tonumber(destination.zone) or 0) ~= (tonumber(state.zone) or 0)) then
        return false;
    end
    if (tostring(destination.name or '') ~= tostring(state.destination_name or '')) then
        return false;
    end
    local saved = state.destination;
    return saved ~= nil
        and nav_distance(saved, destination) <= 3
        and vertical_distance(saved, destination) <= 2;
end

function accessxi.nav_transport_clear(reason)
    local state = accessxi.nav_transport_transition;
    accessxi.nav_transport_transition = nil;
    if (state ~= nil) then
        log_line(('nav transport clear id="%s" phase="%s" reason="%s"'):fmt(
            tostring(state.elevator_id or ''),
            tostring(state.phase or ''),
            accessxi.escape_probe_log_text(reason or '')));
    end
end

local function try_direction(player, destination, elevator, from_landing, to_landing, direction)
    local approach = nav_compute_mesh_route(player, from_landing);
    if (not leg_is_verified(approach, player, from_landing)) then
        return nil;
    end
    local approach_crosses, approach_distance, approach_segment = false, 0, 0;
    if (elevator.guard_metalworks_exit == true) then
        approach_crosses, approach_distance, approach_segment = route_crosses_zone_trigger(approach);
    end
    if (approach_crosses) then
        log_line(('nav transport rejected id="%s" phase=approach reason="zone trigger" distance=%.2f segment=%d'):fmt(
            elevator.id,
            tonumber(approach_distance) or 0,
            tonumber(approach_segment) or 0));
        return nil;
    end

    local continuation = nav_compute_mesh_route(to_landing, destination);
    if (not leg_is_verified(continuation, to_landing, destination)) then
        return nil;
    end
    local allow_terminal_contact = elevator.guard_metalworks_exit == true
        and destination_is_metalworks_exit(destination);
    local continuation_crosses, continuation_distance, continuation_segment = false, 0, 0;
    if (elevator.guard_metalworks_exit == true) then
        continuation_crosses, continuation_distance, continuation_segment = route_crosses_zone_trigger(
            continuation,
            allow_terminal_contact);
    end
    if (continuation_crosses) then
        log_line(('nav transport rejected id="%s" phase=continuation reason="zone trigger" distance=%.2f segment=%d'):fmt(
            elevator.id,
            tonumber(continuation_distance) or 0,
            tonumber(continuation_segment) or 0));
        return nil;
    end

    approach = tag_leg(usable_leg(approach, player, from_landing), 'approach', direction, elevator.id);
    continuation = tag_leg(usable_leg(continuation, to_landing, destination), 'continuation', direction, elevator.id);
    if (approach:len() <= 1 or continuation:len() <= 1) then
        return nil;
    end

    return T{
        route = approach,
        continuation = continuation,
        from_landing = point_copy(from_landing),
        to_landing = point_copy(to_landing),
        direction = direction,
        elevator_id = elevator.id,
        elevator_label = elevator.label,
        zone = tonumber(elevator.zone) or 0,
        interaction = tostring(elevator.interaction or ''),
        guard_metalworks_exit = elevator.guard_metalworks_exit == true,
        boarding_target = point_copy(elevator.platform),
        score = route_length(approach) + route_length(continuation),
    };
end

local function candidate_elevators(player, destination, metalworks_only)
    local candidates = T{};
    if (player == nil or destination == nil
        or (tonumber(player.zone) or 0) ~= (tonumber(destination.zone) or 0)) then
        return candidates;
    end
    local zone = tonumber(player.zone) or 0;
    local requested_transport = tostring(destination.objective_transport_id or '');
    for _, elevator in ipairs(elevators) do
        local required_transport = tostring(elevator.required_transport_id or '');
        if ((tonumber(elevator.zone) or 0) == zone
            and (metalworks_only ~= true or zone == zone_id)
            and ((required_transport == '' and requested_transport == '')
                or (required_transport ~= '' and required_transport == requested_transport))) then
            candidates:append(elevator);
        end
    end
    return candidates;
end

local function verified_elevator_route(player, destination, candidates)
    local empty = T{};
    if (player == nil or destination == nil or candidates == nil or candidates:len() == 0) then
        return empty;
    end

    local lower_first = vertical_distance(player, candidates[1].lower)
        <= vertical_distance(player, candidates[1].upper);
    local best = nil;
    for _, elevator in ipairs(candidates) do
        local directions;
        if (lower_first) then
            directions = T{
                T{ from_landing = elevator.lower, to_landing = elevator.upper, direction = 'up' },
                T{ from_landing = elevator.upper, to_landing = elevator.lower, direction = 'down' },
            };
        else
            directions = T{
                T{ from_landing = elevator.upper, to_landing = elevator.lower, direction = 'down' },
                T{ from_landing = elevator.lower, to_landing = elevator.upper, direction = 'up' },
            };
        end
        for _, candidate in ipairs(directions) do
            local verified = try_direction(
                player,
                destination,
                elevator,
                candidate.from_landing,
                candidate.to_landing,
                candidate.direction);
            if (verified ~= nil
                and (best == nil or (tonumber(verified.score) or 999999) < (tonumber(best.score) or 999999))) then
                best = verified;
            end
        end
    end

    if (best == nil) then
        return empty;
    end

    accessxi.nav_transport_transition = T{
        elevator_id = best.elevator_id,
        elevator_label = best.elevator_label,
        transport_kind = 'verified-elevator',
        boarding_target = best.boarding_target,
        zone = best.zone,
        interaction = best.interaction,
        guard_metalworks_exit = best.guard_metalworks_exit,
        phase = 'approach',
        direction = best.direction,
        from_landing = best.from_landing,
        to_landing = best.to_landing,
        continuation = best.continuation,
        destination = point_copy(destination),
        destination_name = tostring(destination.name or ''),
        last_prompt_tick = 0,
    };
    accessxi.nav_route_last_reject_reason = '';
    log_line(('nav transport verified id="%s" direction=%s destination="%s" approach=%d continuation=%d score=%.1f'):fmt(
        best.elevator_id,
        best.direction,
        accessxi.escape_probe_log_text(destination.name or ''),
        best.route:len(),
        best.continuation:len(),
        tonumber(best.score) or 0));
    return best.route;
end

function accessxi.nav_verified_elevator_route(player, destination)
    local empty = T{};
    if (player == nil or destination == nil
        or (tonumber(player.zone) or 0) ~= (tonumber(destination.zone) or 0)) then
        return empty, false;
    end

    local requested_transport = tostring(destination.objective_transport_id or '');
    if (requested_transport ~= ''
        and vertical_distance(player, destination) <= floor_vertical_tolerance) then
        return empty, false;
    end
    local candidates = candidate_elevators(player, destination, false);
    local required = requested_transport ~= ''
        and vertical_distance(player, destination) > floor_vertical_tolerance;
    if (candidates:len() == 0) then
        return empty, required;
    end
    return verified_elevator_route(player, destination, candidates), required;
end

function accessxi.nav_metalworks_elevator_route(player, destination)
    local candidates = candidate_elevators(player, destination, true);
    return verified_elevator_route(player, destination, candidates);
end

function accessxi.nav_transport_transition_active()
    local state = accessxi.nav_transport_transition;
    return state ~= nil and tostring(state.transport_kind or '') == 'verified-elevator';
end

function accessxi.nav_transport_start_suffix()
    if (not accessxi.nav_transport_transition_active()) then
        return '';
    end
    return (' This route uses the %s.'):fmt(tostring(accessxi.nav_transport_transition.elevator_label or 'elevator'));
end

function accessxi.nav_transport_transition_waiting(player, now)
    local state = accessxi.nav_transport_transition;
    return state ~= nil
        and tostring(state.transport_kind or '') == 'verified-elevator'
        and tostring(state.phase or '') == 'waiting';
end

function accessxi.nav_transport_waiting_beacon_target(player, now)
    local state = accessxi.nav_transport_transition;
    local waiting = state ~= nil
        and tostring(state.transport_kind or '') == 'verified-elevator'
        and tostring(state.phase or '') == 'waiting';
    if (not waiting) then
        return nil, false;
    end
    local target = state.boarding_target;
    if (player == nil or target == nil or nav_distance(player, target) <= 1.8) then
        return nil, true;
    end
    local beacon_target = point_copy(target);
    beacon_target.y = tonumber(player.y) or beacon_target.y;
    beacon_target.source = 'transport-boarding-beacon';
    return beacon_target, true;
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

local function resume_from_destination_floor(player, destination, state, now)
    if (vertical_distance(player, state.to_landing) > floor_vertical_tolerance) then
        return false;
    end

    local fresh = nav_compute_mesh_route(player, destination);
    local route = fresh;
    local guard_metalworks_exit = state.guard_metalworks_exit == true;
    local allow_terminal_contact = guard_metalworks_exit
        and destination_is_metalworks_exit(destination);
    local fresh_crosses = route ~= nil
        and route:len() > 1
        and guard_metalworks_exit
        and route_crosses_zone_trigger(route, allow_terminal_contact);
    local saved_destination_is_current = nav_distance(state.destination, destination) <= 1.5
        and vertical_distance(state.destination, destination) <= 1.0;
    if ((fresh == nil or fresh:len() <= 1 or fresh_crosses)
        and saved_destination_is_current
        and point_near_landing(player, state.to_landing, 4.5, floor_vertical_tolerance)) then
        route = state.continuation;
    end
    if (route == nil
        or route:len() <= 1
        or (guard_metalworks_exit and route_crosses_zone_trigger(route, allow_terminal_contact))) then
        return false;
    end

    tag_leg(route, 'continuation', state.direction, state.elevator_id);
    local floor = state.direction == 'up' and 'Upper floor' or 'Lower floor';
    local destination_name = tostring(destination.name or 'destination');
    accessxi.nav_transport_clear('floor-change-verified');
    reset_route_runtime(player, destination, route, now);
    if (type(accessxi.nav_collision_quiet) == 'function') then
        accessxi.nav_collision_quiet('transport-floor-change', 3000, now);
    end
    local text = ('%s reached. Route resumed to %s.'):fmt(floor, destination_name);
    accessxi.nav_last_direction_text = text;
    speak(text);
    log_line(('nav transport resumed destination="%s" count=%d player=(%.3f,%.3f,%.3f)'):fmt(
        accessxi.escape_probe_log_text(destination_name),
        route:len(),
        tonumber(player.x) or 0,
        tonumber(player.z) or 0,
        tonumber(player.y) or 0));
    return true;
end

function accessxi.nav_transport_transition_poll(player, destination, now)
    local state = accessxi.nav_transport_transition;
    if (state == nil or tostring(state.transport_kind or '') ~= 'verified-elevator') then
        return false;
    end
    now = tonumber(now) or tick();

    if (player == nil or (tonumber(player.zone) or 0) ~= (tonumber(state.zone) or 0)) then
        accessxi.nav_transport_clear('player-left-zone');
        return false;
    end
    if (not transition_destination_matches(state, destination)) then
        accessxi.nav_transport_clear('destination-changed');
        accessxi.nav_route_points:clear();
        accessxi.nav_route_point_index = 1;
        return false;
    end

    if (tostring(state.phase or '') == 'approach') then
        if (not point_near_landing(player, state.from_landing, landing_radius, landing_vertical_tolerance)) then
            return false;
        end

        state.phase = 'waiting';
        state.last_prompt_tick = now;
        local text = transition_instruction(state);
        accessxi.nav_last_key = '';
        accessxi.nav_last_direction_text = text;
        accessxi.nav_beacon_last_key = '';
        accessxi.nav_beacon_last_tick = 0;
        accessxi.nav_progress_x = nil;
        accessxi.nav_progress_z = nil;
        accessxi.nav_progress_tick = now;
        if (type(accessxi.nav_collision_quiet) == 'function') then
            accessxi.nav_collision_quiet('transport-wait', 5000, now);
        end
        speak(text);
        log_line(('nav transport waiting id="%s" direction=%s %s'):fmt(
            state.elevator_id,
            state.direction,
            text));
        return true;
    end

    if (resume_from_destination_floor(player, destination, state, now)) then
        return true;
    end

    local source_vertical = vertical_distance(player, state.from_landing);
    local source_horizontal = nav_distance(player, state.from_landing);
    if (source_vertical <= landing_vertical_tolerance and source_horizontal > 8) then
        local approach = nav_compute_mesh_route(player, state.from_landing);
        local crosses = state.guard_metalworks_exit == true
            and approach ~= nil and approach:len() > 1
            and route_crosses_zone_trigger(approach);
        if (leg_is_verified(approach, player, state.from_landing) and not crosses) then
            approach = tag_leg(usable_leg(approach, player, state.from_landing), 'approach', state.direction, state.elevator_id);
            state.phase = 'approach';
            reset_route_runtime(player, destination, approach, now);
            local text = 'You moved away from the elevator. Route adjusted back to the landing.';
            accessxi.nav_last_direction_text = text;
            speak(text);
            log_line(('nav transport approach restored id="%s" direction=%s count=%d'):fmt(
                state.elevator_id,
                state.direction,
                approach:len()));
            return true;
        end
    end

    if (source_vertical <= landing_vertical_tolerance
        and (now - (tonumber(state.last_prompt_tick) or 0)) >= 15000) then
        state.last_prompt_tick = now;
        local text = transition_instruction(state);
        accessxi.nav_last_direction_text = text;
        speak(text);
        log_line(('nav transport waiting reminder id="%s" direction=%s'):fmt(
            state.elevator_id,
            state.direction));
    end
    return true;
end

local objective_owner_fields = {
    'objective_kind',
    'objective_native_key',
    'objective_guide_step_id',
    'objective_character_identity',
    'objective_world_id',
    'objective_session_epoch',
    'objective_candidate_id',
    'objective_action_id',
    'objective_group_id',
    'objective_destination_id',
    'objective_route_contract_id',
    'objective_transition_id',
    'objective_transition_revision',
    'objective_transition_registry_sha256',
    'objective_transition_direction',
    'objective_transition_zone',
    'objective_transition_expected_live_state',
    'objective_transition_timeout_seconds',
};

local function objective_copy(value, seen)
    if (type(value) ~= 'table') then
        return value;
    end
    seen = seen or {};
    if (seen[value] ~= nil) then
        return seen[value];
    end
    local result = T{};
    seen[value] = result;
    for key, child in pairs(value) do
        result[objective_copy(key, seen)] = objective_copy(child, seen);
    end
    return result;
end

local function objective_finite(value)
    value = tonumber(value);
    return value ~= nil and value == value
        and value ~= math.huge and value ~= -math.huge;
end

local function objective_anchor_valid(anchor, zone)
    return type(anchor) == 'table'
        and objective_finite(anchor.x)
        and objective_finite(anchor.z)
        and objective_finite(anchor.y)
        and (anchor.zone == nil or tonumber(anchor.zone) == tonumber(zone));
end

local function objective_anchor_equal(left, right)
    return type(left) == 'table' and type(right) == 'table'
        and tonumber(left.x) == tonumber(right.x)
        and tonumber(left.z) == tonumber(right.z)
        and tonumber(left.y) == tonumber(right.y)
        and (left.zone == nil or right.zone == nil or tonumber(left.zone) == tonumber(right.zone));
end

local function objective_sha256(value)
    return type(value) == 'string' and #value == 64
        and value:find('[^0-9a-f]') == nil;
end

local function objective_authorization_valid(value)
    if (type(value) ~= 'table') then
        return false;
    end
    for _, field in ipairs({
        'objective_kind', 'objective_native_key', 'objective_guide_step_id',
        'objective_character_identity', 'objective_candidate_id', 'objective_action_id',
        'objective_destination_id', 'objective_route_contract_id', 'objective_transition_id',
        'objective_transition_revision', 'objective_transition_direction',
        'objective_transition_expected_live_state',
    }) do
        if (type(value[field]) ~= 'string' or value[field] == '') then
            return false;
        end
    end
    return type(value.objective_group_id) == 'string'
        and tonumber(value.objective_world_id) ~= nil
        and tonumber(value.objective_session_epoch) ~= nil
        and tonumber(value.objective_transition_zone) ~= nil
        and tonumber(value.objective_transition_zone) == math.floor(tonumber(value.objective_transition_zone))
        and objective_sha256(value.objective_transition_registry_sha256)
        and value.objective_transition_revision == 'objective-route-transition-v2'
        and objective_anchor_valid(
            value.objective_transition_pre_anchor,
            value.objective_transition_zone)
        and objective_anchor_valid(
            value.objective_transition_post_anchor,
            value.objective_transition_zone)
        and tonumber(value.objective_transition_timeout_seconds) ~= nil
        and tonumber(value.objective_transition_timeout_seconds) > 0;
end

local function objective_authorization_equal(left, right)
    if (not objective_authorization_valid(left) or not objective_authorization_valid(right)) then
        return false;
    end
    for _, field in ipairs(objective_owner_fields) do
        if (left[field] ~= right[field]) then
            return false;
        end
    end
    return objective_anchor_equal(
        left.objective_transition_pre_anchor,
        right.objective_transition_pre_anchor)
        and objective_anchor_equal(
            left.objective_transition_post_anchor,
            right.objective_transition_post_anchor);
end

local function objective_definition_matches(authorization, definition)
    return type(definition) == 'table'
        and definition.schema_version == 2
        and definition.transition_revision == authorization.objective_transition_revision
        and definition.source_registry_sha256 == authorization.objective_transition_registry_sha256
        and definition.transition_id == authorization.objective_transition_id
        and tonumber(definition.zone) == tonumber(authorization.objective_transition_zone)
        and definition.direction == authorization.objective_transition_direction
        and definition.expected_live_state == authorization.objective_transition_expected_live_state
        and tonumber(definition.timeout_seconds)
            == tonumber(authorization.objective_transition_timeout_seconds)
        and objective_anchor_equal(definition.pre_anchor, authorization.objective_transition_pre_anchor)
        and objective_anchor_equal(definition.post_anchor, authorization.objective_transition_post_anchor);
end

local function objective_transition_authorized(authorization)
    if (type(objective_transition_is_authorized) ~= 'function') then
        return nil, 'The rooted objective transition authorizer is unavailable.';
    end
    local ok, definition, reason = pcall(objective_transition_is_authorized, authorization);
    if (not ok or not objective_definition_matches(authorization, definition)) then
        return nil, not ok and tostring(definition)
            or tostring(reason or 'No rooted authorized objective transition matches this request.');
    end
    return definition, '';
end

local function objective_destination_matches(state, destination)
    local saved = state ~= nil and state.destination or nil;
    return type(saved) == 'table' and type(destination) == 'table'
        and tostring(saved.name or '') == tostring(destination.name or '')
        and tonumber(saved.zone) == tonumber(destination.zone)
        and tonumber(saved.x) == tonumber(destination.x)
        and tonumber(saved.z) == tonumber(destination.z)
        and tonumber(saved.y) == tonumber(destination.y)
        and tostring(saved.objective_destination_id or '')
            == tostring(destination.objective_destination_id or '');
end

local function objective_exact_leg(start_point, end_point, authorization, stage)
    if (type(nav_compute_exact_objective_leg) ~= 'function') then
        return nil, 'The exact objective leg helper is unavailable.';
    end
    local request = T{
        zone = authorization.objective_transition_zone,
        objective_route_contract_id = authorization.objective_route_contract_id,
        start = point_copy(start_point),
        ['end'] = point_copy(end_point),
        start_point = point_copy(start_point),
        end_point = point_copy(end_point),
        objective_transition_id = authorization.objective_transition_id,
        objective_transition_stage = stage,
    };
    local ok, points, reason = pcall(nav_compute_exact_objective_leg, request);
    if (not ok or type(points) ~= 'table' or #points < 2) then
        return nil, not ok and tostring(points)
            or tostring(reason or 'No exact objective elevator leg is proven.');
    end
    local route = T{};
    for _, point in ipairs(points) do
        if (not objective_anchor_valid(point, authorization.objective_transition_zone)) then
            return nil, 'The exact objective elevator leg is malformed.';
        end
        local copied = point_copy(point);
        copied.zone = authorization.objective_transition_zone;
        copied.source = 'objective-exact-transport-' .. stage;
        route:append(copied);
    end
    return route, '';
end

function accessxi.nav_objective_transport_clear(reason)
    local state = accessxi.nav_objective_transport_transition;
    accessxi.nav_objective_transport_transition = nil;
    if (state ~= nil) then
        log_line(('nav objective transport clear id="%s" phase="%s" reason="%s"'):fmt(
            tostring(state.objective_transition_id or ''),
            tostring(state.phase or ''),
            tostring(reason or '')));
    end
end

function accessxi.nav_objective_transport_start(player, destination, authorization)
    local empty = T{};
    if (not objective_authorization_valid(authorization)
        or type(player) ~= 'table' or type(destination) ~= 'table'
        or tonumber(player.zone) ~= tonumber(authorization.objective_transition_zone)
        or tonumber(destination.zone) ~= tonumber(authorization.objective_transition_zone)
        or tostring(destination.objective_destination_id or '')
            ~= tostring(authorization.objective_destination_id or '')) then
        return empty, 'Objective transport authorization is incomplete.';
    end
    local definition, authorization_reason = objective_transition_authorized(authorization);
    if (definition == nil) then
        return empty, authorization_reason ~= '' and authorization_reason
            or 'No rooted authorized objective transition matches this request.';
    end
    local approach, approach_reason = objective_exact_leg(
        player,
        authorization.objective_transition_pre_anchor,
        authorization,
        'approach');
    if (approach == nil) then
        return empty, approach_reason;
    end
    local continuation, continuation_reason = objective_exact_leg(
        authorization.objective_transition_post_anchor,
        destination,
        authorization,
        'continuation');
    if (continuation == nil) then
        return empty, continuation_reason;
    end

    local state = objective_copy(authorization);
    state.transport_kind = 'objective-verified-elevator';
    state.phase = 'approach';
    state.definition = objective_copy(definition);
    state.approach = approach;
    state.continuation = continuation;
    state.destination = objective_copy(destination);
    state.started_tick = tick();
    state.deadline_tick = 0;
    accessxi.nav_objective_transport_transition = state;
    return approach, '';
end

function accessxi.nav_objective_transport_poll(player, destination, authorization, live_state, now)
    local state = accessxi.nav_objective_transport_transition;
    if (state == nil or state.transport_kind ~= 'objective-verified-elevator') then
        return false, 'No objective transport transition is active.';
    end
    now = tonumber(now) or tick();
    local function cancel(reason)
        accessxi.nav_objective_transport_clear(reason);
        return false, reason;
    end
    if (not objective_authorization_equal(state, authorization)) then
        return cancel('Objective transport authorization changed.');
    end
    if (not objective_destination_matches(state, destination)) then
        return cancel('Objective transport destination changed.');
    end
    if (type(player) ~= 'table'
        or tonumber(player.zone) ~= tonumber(state.objective_transition_zone)) then
        return cancel('Objective transport player zone changed.');
    end
    local definition, authorization_reason = objective_transition_authorized(authorization);
    if (definition == nil or not objective_definition_matches(state, definition)) then
        return cancel(authorization_reason ~= '' and authorization_reason
            or 'Objective transport authorization is no longer rooted.');
    end

    if (state.phase == 'approach') then
        if (not point_near_landing(
            player,
            state.objective_transition_pre_anchor,
            landing_radius,
            landing_vertical_tolerance)) then
            return true, '';
        end
        state.phase = 'waiting';
        state.deadline_tick = now
            + (tonumber(state.objective_transition_timeout_seconds) * 1000);
        local text = ('At the reviewed elevator transition. Use the visible elevator control if required, then ride to the destination floor.');
        accessxi.nav_last_direction_text = text;
        speak(text);
        return true, '';
    end

    if (now > (tonumber(state.deadline_tick) or 0)) then
        return cancel('Objective transport timed out.');
    end
    if (point_near_landing(
        player,
        state.objective_transition_post_anchor,
        landing_radius,
        landing_vertical_tolerance)) then
        if (tostring(live_state or '')
            ~= tostring(state.objective_transition_expected_live_state or '')) then
            return cancel('Objective transport live state changed.');
        end
        local continuation = state.continuation;
        accessxi.nav_objective_transport_clear('post-anchor-and-state-verified');
        reset_route_runtime(player, destination, continuation, now);
        local text = 'Destination floor verified. Objective route resumed.';
        accessxi.nav_last_direction_text = text;
        speak(text);
        return true, '';
    end
    return true, '';
end

function accessxi.nav_objective_transport_active()
    local state = accessxi.nav_objective_transport_transition;
    return state ~= nil and state.transport_kind == 'objective-verified-elevator';
end

return true;
