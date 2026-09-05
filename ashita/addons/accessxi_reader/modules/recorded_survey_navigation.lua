local survey_id = '20260712-170700-z102';
local route_id = 'lathine-recorded-survey-20260712';
local west_corridor_prefix = 'lathine-recorded-corridor-20260712-west-via-';
local survey_collision_blocked_edges = {
    ['3924:3923'] = true,
};
-- tail_budget: how far the short mesh hop from the marked node to the zone-line
--   trigger may run in total.  Defaults to 20 yalms; only widen it for a mark
--   whose measured gap to the trigger is larger, and never past what the walk
--   supports.  Every other tail check still applies.
-- When an edge here cannot be served -- the player is off the walked line, or
-- the tail will not verify -- the walk hands back to the mesh rather than
-- calling the zone line unreachable, so a marked edge can only ever add routes.
local survey_zoneline_marked_edges = {
    [947204730] = {
        node_id = 845,
        label = 'ordelles caves zone 2',
        from_zone = 102,
        to_zone = 193,
        x = -60.125,
        z = 148.001,
        y = 27.231,
    },
    -- Valkurm Dunes was the one La Theine exit with no override, no marked edge
    -- and no survey coverage -- the live log has 14 "Valkurm Dunes zone line is
    -- not reachable from here".  The player walked to and marked it as survey
    -- node 1969; the trigger sits 26.9 yalms further on, across flat ground
    -- (vertical delta 0.41), so the tail budget is widened to cover that hop.
    [880095866] = {
        node_id = 1969,
        label = 'valkern dunes zone line',
        from_zone = 102,
        to_zone = 103,
        x = 159.989,
        z = -760.190,
        y = 31.950,
        tail_budget = 32.0,
    },
};

local function survey_horizontal_vertical(a, b)
    local dx = (tonumber(a ~= nil and a.x) or 0) - (tonumber(b ~= nil and b.x) or 0);
    local dz = (tonumber(a ~= nil and a.z) or 0) - (tonumber(b ~= nil and b.z) or 0);
    local dy = (tonumber(a ~= nil and a.y) or 0) - (tonumber(b ~= nil and b.y) or 0);
    return math.sqrt((dx * dx) + (dz * dz)), math.abs(dy), math.sqrt((dx * dx) + (dz * dz) + (dy * dy));
end

local function survey_fail(reason)
    accessxi.nav_recorded_survey_nodes:clear();
    accessxi.nav_recorded_survey_load_error = tostring(reason or 'invalid recorded survey');
    log_line(('nav recorded survey rejected reason="%s"'):fmt(accessxi.nav_recorded_survey_load_error));
    return false;
end

local function survey_parse_neighbors(text)
    local neighbors = T{};
    for value in tostring(text or ''):gmatch('([^,]+)') do
        local id = tonumber(value);
        if (id ~= nil and id > 0) then
            neighbors:append(math.floor(id));
        end
    end
    return neighbors;
end

function accessxi.nav_recorded_survey_load()
    if (accessxi.nav_recorded_survey_loaded) then
        return accessxi.nav_recorded_survey_nodes ~= nil and accessxi.nav_recorded_survey_nodes:len() > 0;
    end
    accessxi.nav_recorded_survey_loaded = true;
    accessxi.nav_recorded_survey_load_error = '';
    accessxi.nav_recorded_survey_nodes:clear();

    local file = io.open(accessxi.nav_recorded_survey_path, 'r');
    if (file == nil) then
        return survey_fail('recorded survey file unavailable');
    end

    local loaded = 0;
    for line in file:lines() do
        if (line ~= nil and line ~= '' and line:sub(1, 9) ~= 'survey_id') then
            local parts = nav_split_tsv(line);
            if (#parts < 12) then
                file:close();
                return survey_fail('recorded survey row has fewer than 12 columns');
            end
            local row_survey_id = nav_clean_field(parts[1] or '');
            local zone = tonumber(parts[2]) or 0;
            local node_id = math.floor(tonumber(parts[3]) or 0);
            local sequence = math.floor(tonumber(parts[4]) or 0);
            local x = tonumber(parts[5]);
            local z = tonumber(parts[6]);
            local y = tonumber(parts[7]);
            if (row_survey_id ~= survey_id or zone ~= 102 or node_id ~= (loaded + 1)
                or sequence <= 0 or x == nil or z == nil or y == nil) then
                file:close();
                return survey_fail(('invalid recorded survey node %d'):fmt(node_id));
            end
            accessxi.nav_recorded_survey_nodes[node_id] = T{
                id = node_id,
                sequence = sequence,
                zone = zone,
                x = x,
                z = z,
                y = y,
                event = nav_clean_field(parts[8] or ''),
                label = nav_clean_field(parts[9] or ''),
                neighbors = survey_parse_neighbors(parts[10] or ''),
                source = nav_clean_field(parts[11] or ''),
                confidence = nav_clean_field(parts[12] or ''),
            };
            loaded = loaded + 1;
        end
    end
    file:close();

    if (loaded ~= 6499) then
        return survey_fail(('recorded survey expected 6499 nodes, loaded %d'):fmt(loaded));
    end
    for _, node in ipairs(accessxi.nav_recorded_survey_nodes) do
        for _, neighbor_id in ipairs(node.neighbors) do
            local neighbor = accessxi.nav_recorded_survey_nodes[neighbor_id];
            if (neighbor == nil or not neighbor.neighbors:contains(node.id)) then
                return survey_fail(('invalid recorded survey edge %d-%d'):fmt(node.id, neighbor_id));
            end
            local horizontal, vertical, distance = survey_horizontal_vertical(node, neighbor);
            local consecutive = math.abs((tonumber(node.id) or 0) - (tonumber(neighbor.id) or 0)) == 1;
            if (distance > 6.0
                or ((not consecutive) and (horizontal > 0.500001 or vertical > 0.750001))) then
                return survey_fail(('unsafe recorded survey edge %d-%d'):fmt(node.id, neighbor_id));
            end
        end
    end

    log_line(('nav recorded survey loaded id="%s" nodes=%d'):fmt(survey_id, loaded));
    return true;
end

function accessxi.nav_recorded_survey_nearest(pos)
    if (pos == nil or (tonumber(pos.zone) or 0) ~= 102 or not accessxi.nav_recorded_survey_load()) then
        return 0, 999999, 999999, 999999;
    end

    local best_id = 0;
    local best_horizontal = 999999;
    local best_vertical = 999999;
    local best_distance = 999999;
    for _, node in ipairs(accessxi.nav_recorded_survey_nodes) do
        local horizontal, vertical, distance = survey_horizontal_vertical(pos, node);
        if (distance < best_distance) then
            best_id = node.id;
            best_horizontal = horizontal;
            best_vertical = vertical;
            best_distance = distance;
        end
    end
    return best_id, best_horizontal, best_vertical, best_distance;
end

function accessxi.nav_recorded_survey_zoneline_edge_priority(edge)
    local edge_id = math.floor(tonumber(edge ~= nil and edge.id) or 0);
    local expected = survey_zoneline_marked_edges[edge_id];
    if (expected == nil or not accessxi.nav_recorded_survey_load()) then
        return 0;
    end

    local node = accessxi.nav_recorded_survey_nodes[expected.node_id];
    if (node == nil
        or tostring(node.event or ''):lower() ~= 'mark'
        or tostring(node.label or ''):lower() ~= expected.label) then
        return 0;
    end
    return -1;
end

local function survey_heap_push(heap, item)
    heap[#heap + 1] = item;
    local index = #heap;
    while index > 1 do
        local parent = math.floor(index / 2);
        if ((tonumber(heap[parent].cost) or 999999999) <= (tonumber(item.cost) or 999999999)) then
            break;
        end
        heap[index] = heap[parent];
        index = parent;
    end
    heap[index] = item;
end

local function survey_heap_pop(heap)
    if (#heap <= 0) then
        return nil;
    end
    local first = heap[1];
    local last = table.remove(heap);
    if (#heap > 0) then
        local index = 1;
        while true do
            local left = index * 2;
            if (left > #heap) then
                break;
            end
            local right = left + 1;
            local child = left;
            if (right <= #heap and (tonumber(heap[right].cost) or 999999999) < (tonumber(heap[left].cost) or 999999999)) then
                child = right;
            end
            if ((tonumber(heap[child].cost) or 999999999) >= (tonumber(last.cost) or 999999999)) then
                break;
            end
            heap[index] = heap[child];
            index = child;
        end
        heap[index] = last;
    end
    return first;
end

local function survey_collision_edge_blocked(from_id, to_id)
    from_id = math.floor(tonumber(from_id) or 0);
    to_id = math.floor(tonumber(to_id) or 0);
    if (from_id <= 0 or to_id <= 0) then
        return false;
    end
    return survey_collision_blocked_edges[('%d:%d'):fmt(from_id, to_id)] == true
        or survey_collision_blocked_edges[('%d:%d'):fmt(to_id, from_id)] == true;
end

function accessxi.nav_recorded_survey_shortest_path(start_id, destination_id)
    local result = T{};
    start_id = math.floor(tonumber(start_id) or 0);
    destination_id = math.floor(tonumber(destination_id) or 0);
    if (not accessxi.nav_recorded_survey_load()
        or accessxi.nav_recorded_survey_nodes[start_id] == nil
        or accessxi.nav_recorded_survey_nodes[destination_id] == nil) then
        return result;
    end

    local distances = {};
    local previous = {};
    local heap = {};
    distances[start_id] = 0;
    survey_heap_push(heap, { id = start_id, cost = 0 });
    while #heap > 0 do
        local current = survey_heap_pop(heap);
        local current_cost = tonumber(current ~= nil and current.cost) or 999999999;
        local known_cost = tonumber(current ~= nil and distances[current.id]) or 999999999;
        if (current ~= nil and current_cost <= (known_cost + 0.000001)) then
            if (current.id == destination_id) then
                break;
            end
            local node = accessxi.nav_recorded_survey_nodes[current.id];
            for _, neighbor_id in ipairs(node.neighbors) do
                if (not survey_collision_edge_blocked(current.id, neighbor_id)) then
                    local neighbor = accessxi.nav_recorded_survey_nodes[neighbor_id];
                    local _, _, edge_distance = survey_horizontal_vertical(node, neighbor);
                    local candidate = current_cost + edge_distance;
                    if (candidate < (tonumber(distances[neighbor_id]) or 999999999)) then
                        distances[neighbor_id] = candidate;
                        previous[neighbor_id] = current.id;
                        survey_heap_push(heap, { id = neighbor_id, cost = candidate });
                    end
                end
            end
        end
    end

    if (distances[destination_id] == nil) then
        return result;
    end
    local reverse = T{};
    local current_id = destination_id;
    while current_id ~= nil do
        reverse:append(current_id);
        if (current_id == start_id) then
            break;
        end
        current_id = previous[current_id];
    end
    if (reverse[reverse:len()] ~= start_id) then
        return T{};
    end
    for i = reverse:len(), 1, -1 do
        result:append(reverse[i]);
    end
    return result;
end

local function survey_path_collision_blocked_edge(path)
    for index = 2, path:len() do
        local from_id = math.floor(tonumber(path[index - 1]) or 0);
        local to_id = math.floor(tonumber(path[index]) or 0);
        if (survey_collision_edge_blocked(from_id, to_id)) then
            return from_id, to_id;
        end
    end
    return 0, 0;
end

local survey_route_append;

local function survey_marked_zoneline_destination(point)
    if (point == nil) then
        return 0, nil, nil;
    end
    local source = tostring(point.source or ''):lower();
    local edge_id = math.floor(tonumber(source:match('^zonesearch:(%d+):%d+:%d+$')) or 0);
    local expected = survey_zoneline_marked_edges[edge_id];
    if (expected == nil or not accessxi.nav_recorded_survey_load()
        or (tonumber(point.zone) or 0) ~= (tonumber(expected.from_zone) or 0)
        or (tonumber(point.to_zone) or 0) ~= (tonumber(expected.to_zone) or 0)) then
        return 0, nil, nil;
    end

    local dx = (tonumber(point.x) or 0) - (tonumber(expected.x) or 0);
    local dz = (tonumber(point.z) or 0) - (tonumber(expected.z) or 0);
    local dy = math.abs((tonumber(point.y) or 0) - (tonumber(expected.y) or 0));
    if (math.sqrt((dx * dx) + (dz * dz)) > 0.25 or dy > 0.5) then
        return 0, nil, nil;
    end

    local node = accessxi.nav_recorded_survey_nodes[expected.node_id];
    if (node == nil
        or tostring(node.event or ''):lower() ~= 'mark'
        or tostring(node.label or ''):lower() ~= expected.label) then
        return 0, nil, nil;
    end
    return edge_id, expected, node;
end

local function survey_marked_zoneline_tail_is_local(tail, start_pos, destination, budget)
    local count = tail ~= nil and tail:len() or 0;
    if (count < 2 or count > 6 or start_pos == nil or destination == nil) then
        return false;
    end
    budget = tonumber(budget) or 20.0;

    local first_horizontal, first_vertical = survey_horizontal_vertical(tail[1], start_pos);
    local last_horizontal, last_vertical = survey_horizontal_vertical(tail[count], destination);
    if (first_horizontal > 1.5 or first_vertical > 2.0
        or last_horizontal > 1.0 or last_vertical > 4.0) then
        return false;
    end

    local total_distance = 0;
    local expected_zone = tonumber(destination.zone) or 0;
    for index, waypoint in ipairs(tail) do
        if ((tonumber(waypoint.zone) or 0) ~= expected_zone) then
            return false;
        end
        if (index > 1) then
            local _, _, segment_distance = survey_horizontal_vertical(tail[index - 1], waypoint);
            if (segment_distance > 12.0) then
                return false;
            end
            total_distance = total_distance + segment_distance;
        end
    end
    return total_distance <= budget;
end

local function survey_marked_zoneline_route(player_id, point, edge_id, expected, destination_node)
    local route = T{};
    local path = accessxi.nav_recorded_survey_shortest_path(player_id, expected.node_id);
    if (path:len() <= 0) then
        accessxi.nav_route_last_reject_reason = 'walked La Theine entrance has no connected course';
        return route;
    end

    for _, node_id in ipairs(path) do
        local node = accessxi.nav_recorded_survey_nodes[node_id];
        survey_route_append(route, T{
            zone = node.zone,
            name = node.label ~= '' and node.label or ('Recorded La Theine survey %d'):fmt(node.sequence),
            x = node.x,
            z = node.z,
            y = node.y,
        }, node.id);
    end

    local tail_start = T{
        zone = destination_node.zone,
        name = destination_node.label,
        x = destination_node.x,
        z = destination_node.z,
        y = destination_node.y,
    };
    local tail = type(nav_compute_mesh_route) == 'function'
        and nav_compute_mesh_route(tail_start, point, true) or T{};
    if (not survey_marked_zoneline_tail_is_local(tail, tail_start, point, expected.tail_budget)) then
        accessxi.nav_route_last_reject_reason = 'walked La Theine entrance has no verified short zone-line tail';
        return T{};
    end
    for index = 2, tail:len() do
        survey_route_append(route, tail[index], nil);
    end

    local final = route[route:len()];
    local final_horizontal, final_vertical = survey_horizontal_vertical(final, point);
    if (final == nil or final_horizontal > 0.05 or final_vertical > 0.05) then
        survey_route_append(route, point, nil);
    end

    accessxi.nav_route_last_reject_reason = '';
    log_line(('nav recorded survey marked zoneline route edge=%d destination="%s" start=%d finish=%d count=%d'):fmt(
        edge_id, point.name or '', player_id, expected.node_id, route:len()));
    return route;
end

survey_route_append = function(route, point, node_id)
    if (route == nil or point == nil) then
        return;
    end
    local last = route[route:len()];
    local _, _, distance = survey_horizontal_vertical(last, point);
    if (last ~= nil and distance <= 0.05) then
        return;
    end
    route:append(T{
        zone = tonumber(point.zone) or 102,
        name = tostring(point.name or ''),
        x = tonumber(point.x) or 0,
        z = tonumber(point.z) or 0,
        y = tonumber(point.y) or 0,
        kind = 'route',
        source = 'recorded-survey:' .. survey_id,
        route_override_id = route_id,
        survey_node_id = tonumber(node_id) or tonumber(point.survey_node_id),
    });
end

local function survey_owned_recovery_joins(owned_points, owned_index)
    local joins = T{};
    local count = owned_points ~= nil and owned_points:len() or 0;
    local index = math.floor(tonumber(owned_index) or 0);
    if (count <= 0 or index < 1 or index > count
        or tostring(owned_points[1] ~= nil and owned_points[1].route_override_id or '') ~= route_id) then
        return joins;
    end

    local walked = 0;
    local previous = nil;
    for route_index = index, count do
        local waypoint = owned_points[route_index];
        if (waypoint == nil or tostring(waypoint.route_override_id or '') ~= route_id) then
            return T{};
        end
        if (previous ~= nil) then
            local _, _, segment_distance = survey_horizontal_vertical(previous, waypoint);
            walked = walked + segment_distance;
            if (walked > 24.000001) then
                break;
            end
        end

        local node_id = math.floor(tonumber(waypoint.survey_node_id) or 0);
        local node = accessxi.nav_recorded_survey_nodes[node_id];
        if (node ~= nil) then
            local horizontal, vertical = survey_horizontal_vertical(waypoint, node);
            if (horizontal <= 0.05 and vertical <= 0.25) then
                joins:append(T{
                    route_index = route_index,
                    node = node,
                });
            end
        end
        previous = waypoint;
    end
    return joins;
end

local function survey_owned_connector_is_local(connector, player, join)
    local count = connector ~= nil and connector:len() or 0;
    if (count < 2 or count > 3 or player == nil or join == nil) then
        return false;
    end

    local expected_zone = tonumber(player.zone) or 0;
    if (expected_zone <= 0 or expected_zone ~= (tonumber(join.zone) or 0)) then
        return false;
    end
    local first_horizontal, first_vertical = survey_horizontal_vertical(connector[1], player);
    local last_horizontal, last_vertical = survey_horizontal_vertical(connector[count], join);
    if (first_horizontal > 1.5 or first_vertical > 2.0
        or last_horizontal > 1.25 or last_vertical > 2.0) then
        return false;
    end

    local player_y = tonumber(player.y) or 0;
    local join_y = tonumber(join.y) or 0;
    local minimum_y = math.min(player_y, join_y) - 2.0;
    local maximum_y = math.max(player_y, join_y) + 2.0;
    local direct_horizontal, _, direct_distance = survey_horizontal_vertical(player, join);
    if (direct_horizontal <= 0.001 or direct_distance > 20.0) then
        return false;
    end

    local direct_x = (tonumber(join.x) or 0) - (tonumber(player.x) or 0);
    local direct_z = (tonumber(join.z) or 0) - (tonumber(player.z) or 0);
    local direct_horizontal_squared = (direct_x * direct_x) + (direct_z * direct_z);
    local total_distance = 0;
    local previous = player;
    local previous_progress = -0.05;
    for connector_index, waypoint in ipairs(connector) do
        if (waypoint == nil or (tonumber(waypoint.zone) or 0) ~= expected_zone) then
            return false;
        end
        local waypoint_y = tonumber(waypoint.y) or 0;
        if (waypoint_y < minimum_y or waypoint_y > maximum_y) then
            return false;
        end

        local _, _, segment_distance = survey_horizontal_vertical(previous, waypoint);
        if (segment_distance <= 0.05
            or (count > 2 and connector_index > 1 and segment_distance > 12.0)) then
            return false;
        end
        total_distance = total_distance + segment_distance;

        local offset_x = (tonumber(waypoint.x) or 0) - (tonumber(player.x) or 0);
        local offset_z = (tonumber(waypoint.z) or 0) - (tonumber(player.z) or 0);
        local progress = ((offset_x * direct_x) + (offset_z * direct_z))
            / direct_horizontal_squared;
        if (connector_index > 1 and progress <= (previous_progress + 0.001)) then
            return false;
        end
        if (progress < -0.05 or progress > 1.05) then
            return false;
        end
        previous_progress = progress;
        previous = waypoint;
    end

    local _, _, snap_distance = survey_horizontal_vertical(previous, join);
    total_distance = total_distance + snap_distance;
    if (total_distance > 20.0 or total_distance > (direct_distance + 1.0)) then
        return false;
    end
    return true;
end

local function survey_owned_recovery_route(player, point, owned_points, owned_index)
    local route = T{};
    local joins = survey_owned_recovery_joins(owned_points, owned_index);
    if (joins:len() <= 0) then
        accessxi.nav_route_last_reject_reason =
            'walked La Theine recovery has no current or forward owned survey join';
        return route;
    end

    local saw_local_connector = false;
    for _, candidate in ipairs(joins) do
        local join_index = tonumber(candidate.route_index) or 0;
        local join_node = candidate.node;
        local direct_horizontal, direct_vertical, direct_distance =
            survey_horizontal_vertical(player, join_node);
        if (join_index > 0 and join_node ~= nil
            and direct_horizontal > 0.001 and direct_vertical <= 2.0 and direct_distance <= 20.0) then
            local join = T{
                zone = join_node.zone,
                name = join_node.label ~= '' and join_node.label
                    or ('Recorded La Theine survey %d'):fmt(join_node.sequence),
                x = join_node.x,
                z = join_node.z,
                y = join_node.y,
                survey_node_id = join_node.id,
            };
            local connector = type(nav_compute_closest_mesh_route) == 'function'
                and nav_compute_closest_mesh_route(player, join, true) or T{};
            if (survey_owned_connector_is_local(connector, player, join)) then
                saw_local_connector = true;
                if (type(nav_lathine_direct_target_safe) == 'function'
                    and nav_lathine_direct_target_safe(player, join)) then
                    for connector_index = 1, connector:len() do
                        if (connector_index == connector:len()) then
                            survey_route_append(route, join, join_node.id);
                        else
                            survey_route_append(route, connector[connector_index], nil);
                        end
                    end
                    for route_index = join_index + 1, owned_points:len() do
                        local waypoint = owned_points[route_index];
                        survey_route_append(route, waypoint,
                            waypoint ~= nil and waypoint.survey_node_id or nil);
                    end

                    if (route:len() > 1) then
                        accessxi.nav_route_last_reject_reason = '';
                        log_line(('nav recorded survey recovered destination="%s" join=%d route_index=%d connector=%d count=%d'):fmt(
                            point.name or '', join_node.id, join_index, connector:len(), route:len()));
                        return route;
                    end
                    route:clear();
                end
            end
        end
    end
    if (saw_local_connector) then
        accessxi.nav_route_last_reject_reason =
            'walked La Theine recovery connectors failed direct-target safety validation';
    else
        accessxi.nav_route_last_reject_reason =
            'walked La Theine recovery has no verified short local connector';
    end
    return T{};
end

local function survey_west_route(player_id, point)
    local empty = T{};
    local saw_collision_blocked_path = false;
    if type(accessxi.nav_load_route_overrides) ~= 'function'
        or type(accessxi.nav_lathine_recorded_corridor_candidate) ~= 'function' then
        return empty, false;
    end

    accessxi.nav_load_route_overrides();
    for _, corridor in ipairs(accessxi.nav_route_overrides or T{}) do
        local corridor_id = tostring(corridor ~= nil and corridor.id or '');
        if corridor_id:sub(1, #west_corridor_prefix) == west_corridor_prefix
            and corridor.waypoints ~= nil and corridor.waypoints:len() > 1 then
            local anchor = corridor.waypoints[1];
            local anchor_id, anchor_horizontal, anchor_vertical = accessxi.nav_recorded_survey_nearest(anchor);
            if anchor_id > 0 and anchor_horizontal <= 0.500001 and anchor_vertical <= 0.750001 then
                local path = accessxi.nav_recorded_survey_shortest_path(player_id, anchor_id);
                local tail = accessxi.nav_lathine_recorded_corridor_candidate(anchor, point, corridor, 1, 1);
                local blocked_from, blocked_to = survey_path_collision_blocked_edge(path);
                if (blocked_from > 0) then
                    saw_collision_blocked_path = true;
                    log_line(('nav recorded survey yielded collision-blocked edge %d->%d destination="%s"'):fmt(
                        blocked_from, blocked_to, point.name or ''));
                elseif path:len() > 0 and tail ~= nil and tail:len() > 1 then
                    local candidate = T{};
                    for _, node_id in ipairs(path) do
                        local node = accessxi.nav_recorded_survey_nodes[node_id];
                        survey_route_append(candidate, T{
                            zone = node.zone,
                            name = node.label ~= '' and node.label or ('Recorded La Theine survey %d'):fmt(node.sequence),
                            x = node.x,
                            z = node.z,
                            y = node.y,
                        }, node.id);
                    end
                    for _, waypoint in ipairs(tail) do
                        survey_route_append(candidate, waypoint, nil);
                    end
                    if candidate:len() > 1 then
                        return candidate, false;
                    end
                end
            end
        end
    end
    return empty, saw_collision_blocked_path;
end

-- The walked survey owns marked zoneline destinations by default, and a
-- caller must pass allow_marked_zoneline = false to decline that.
--
-- It was briefly the other way round. Handing these destinations to the
-- installed full-zone navmesh produced shorter, cheaper routes that were not
-- walkable: on 2026-08-17 the mesh returned the same 50-waypoint answer four
-- times in ninety seconds, each one walking the player into terrain around
-- waypoint 5-8 at zero clearance. The waypoint cursor reset 8->3->5->3 and
-- the distance to the destination rose from 581 to 605 yalms -- the player
-- walked in a circle. The survey is expensive and its recovery is narrow,
-- but the ground it covers is ground someone actually walked, and that is
-- the property that matters. Route quality first; cost second.
function accessxi.nav_recorded_survey_route(player, point, owned_points, owned_index, allow_marked_zoneline)
    local route = T{};
    if (player == nil or point == nil
        or (tonumber(player.zone) or 0) ~= 102
        or (tonumber(point.zone) or 0) ~= 102) then
        return route, false;
    end

    local destination_name = tostring(point.name or ''):lower();
    local destination_is_west = destination_name:find('west ronfaure', 1, true) ~= nil;
    -- Ownership is the default; only an explicit false declines it. Skipping
    -- the lookup in that case also avoids cold-loading the 6499-node survey
    -- purely to discard the answer.
    local marked_edge_id, marked_edge, marked_node = 0, nil, nil;
    if (allow_marked_zoneline ~= false) then
        marked_edge_id, marked_edge, marked_node = survey_marked_zoneline_destination(point);
    end
    -- Every zone-102 destination the walk actually covers is answered from the
    -- walk.  This used to yield everything except West Ronfaure and the one
    -- wired marked edge, which left the generic course below unreachable and
    -- handed ordinary destinations -- mission NPCs, the Telepoint, the Field
    -- Manual -- to a mesh that routes through cliffs.  Destinations the walk
    -- does not cover still yield further down, so the mesh keeps its turn.

    if (owned_points ~= nil or owned_index ~= nil) then
        route = survey_owned_recovery_route(player, point, owned_points, owned_index);
        if (route:len() > 1) then
            return route, true;
        end
        -- A refresh connector that cannot bridge back to the walked line means
        -- the walk has lost the player, not that the destination is gone.
        return T{}, false, true;
    end

    local player_id, player_horizontal, player_vertical = accessxi.nav_recorded_survey_nearest(player);
    local player_covered = player_id > 0 and player_horizontal <= 6.0 and player_vertical <= 4.5;
    if (not player_covered) then
        if (marked_edge_id > 0) then
            accessxi.nav_route_last_reject_reason =
                'live position is outside the walked La Theine entrance course';
            log_line(('nav recorded survey marked zoneline recovery waiting edge=%d destination="%s" horizontal=%.1f vertical=%.1f'):fmt(
                marked_edge_id,
                point.name or '',
                tonumber(player_horizontal) or 999999,
                tonumber(player_vertical) or 999999));
            -- The walk cannot snap a player standing this far off it, but it has
            -- no evidence about the ground they are on either, so it must not
            -- veto the whole leg.  Blocking here stranded a cross-zone mission
            -- leg on 2026-08-20 with nothing spoken but a refusal.  Hand back
            -- and let the verified overrides and the mesh answer.
            return T{}, false, true;
        end
        -- Handing off to the other providers, so do not leave an older
        -- rejection behind for the caller to speak as if it were this one.
        accessxi.nav_route_last_reject_reason = '';
        return route, false;
    end

    if (marked_edge_id > 0) then
        route = survey_marked_zoneline_route(player_id, point, marked_edge_id, marked_edge, marked_node);
        if (route:len() > 1) then
            return route, true;
        end
        -- Same rule as above: an unverifiable zone-line tail means the walk has
        -- no answer, not that the destination is unreachable.
        return T{}, false, true;
    end

    if (destination_is_west) then
        local collision_blocked = false;
        route, collision_blocked = survey_west_route(player_id, point);
        if (route:len() > 1) then
            accessxi.nav_route_last_reject_reason = '';
            log_line(('nav recorded survey west route destination="%s" start=%d count=%d'):fmt(
                point.name or '', player_id, route:len()));
            return route, true;
        end
        if (collision_blocked) then
            accessxi.nav_route_last_reject_reason = '';
            return T{}, false, true;
        end
        -- No proven West corridor in the walk is not the same as no way west.
        accessxi.nav_route_last_reject_reason = '';
        log_line(('nav recorded survey yielded west leg destination="%s"'):fmt(point.name or ''));
        return T{}, false, true;
    end

    local destination_id, destination_horizontal, destination_vertical = accessxi.nav_recorded_survey_nearest(point);
    if (destination_id <= 0 or destination_horizontal > 6.0 or destination_vertical > 4.5) then
        -- Off the walked ground.  Yield rather than claim the destination:
        -- blocking here would strand every target the walk never reached.
        accessxi.nav_route_last_reject_reason = '';
        log_line(('nav recorded survey yielded to full-zone collision terrain destination="%s"'):fmt(
            point.name or ''));
        return route, false, true;
    end

    local path = accessxi.nav_recorded_survey_shortest_path(player_id, destination_id);
    if (path:len() <= 0) then
        accessxi.nav_route_last_reject_reason = '';
        log_line(('nav recorded survey has no connected course destination="%s"'):fmt(point.name or ''));
        return route, false, true;
    end
    local blocked_from, blocked_to = survey_path_collision_blocked_edge(path);
    if (blocked_from > 0) then
        accessxi.nav_route_last_reject_reason = '';
        log_line(('nav recorded survey yielded collision-blocked edge %d->%d destination="%s"'):fmt(
            blocked_from, blocked_to, point.name or ''));
        return T{}, false, true;
    end
    for _, node_id in ipairs(path) do
        local node = accessxi.nav_recorded_survey_nodes[node_id];
        route:append(T{
            zone = node.zone,
            name = node.label ~= '' and node.label or ('Recorded La Theine survey %d'):fmt(node.sequence),
            x = node.x,
            z = node.z,
            y = node.y,
            kind = 'route',
            source = 'recorded-survey:' .. survey_id,
            route_override_id = route_id,
            survey_node_id = node.id,
        });
    end

    local final = route[route:len()];
    local final_horizontal, final_vertical = survey_horizontal_vertical(final, point);
    if (final ~= nil and final_horizontal <= 1.5 and final_vertical <= 2.0
        and nav_distance(final, point) > 0.05) then
        route:append(T{
            zone = point.zone,
            name = point.name,
            x = point.x,
            z = point.z,
            y = point.y,
            kind = 'route',
            source = 'recorded-survey:' .. survey_id .. ':final',
            route_override_id = route_id,
            survey_node_id = destination_id,
        });
    end

    -- The caller only accepts a course of more than one waypoint.  A single
    -- node -- the player already standing on the node nearest the destination,
    -- which happens on replans as the route completes -- would be claimed and
    -- then silently discarded, leaving the player with nothing.  Hand it back.
    if (route:len() <= 1) then
        accessxi.nav_route_last_reject_reason = '';
        log_line(('nav recorded survey yielded single-node course destination="%s" node=%d'):fmt(
            point.name or '', player_id));
        return T{}, false, true;
    end

    accessxi.nav_route_last_reject_reason = '';
    log_line(('nav recorded survey route destination="%s" start=%d finish=%d count=%d'):fmt(
        point.name or '', player_id, destination_id, route:len()));
    return route, true;
end
