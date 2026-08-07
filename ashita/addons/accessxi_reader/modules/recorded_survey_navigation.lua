local survey_id = '20260712-170700-z102';
local route_id = 'lathine-recorded-survey-20260712';
local west_corridor_prefix = 'lathine-recorded-corridor-20260712-west-via-';

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

local function survey_route_append(route, point, node_id)
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

local function survey_west_route(player_id, point)
    local empty = T{};
    if type(accessxi.nav_load_route_overrides) ~= 'function'
        or type(accessxi.nav_lathine_recorded_corridor_candidate) ~= 'function' then
        return empty;
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
                if path:len() > 0 and tail ~= nil and tail:len() > 1 then
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
                        return candidate;
                    end
                end
            end
        end
    end
    return empty;
end

function accessxi.nav_recorded_survey_route(player, point)
    local route = T{};
    if (player == nil or point == nil
        or (tonumber(player.zone) or 0) ~= 102
        or (tonumber(point.zone) or 0) ~= 102) then
        return route, false;
    end

    local destination_name = tostring(point.name or ''):lower();
    local destination_is_west = destination_name:find('west ronfaure', 1, true) ~= nil;

    local player_id, player_horizontal, player_vertical = accessxi.nav_recorded_survey_nearest(player);
    local player_covered = player_id > 0 and player_horizontal <= 6.0 and player_vertical <= 4.5;
    if (not player_covered) then
        return route, false;
    end

    if (destination_is_west) then
        route = survey_west_route(player_id, point);
        if (route:len() > 1) then
            accessxi.nav_route_last_reject_reason = '';
            log_line(('nav recorded survey west route destination="%s" start=%d count=%d'):fmt(
                point.name or '', player_id, route:len()));
            return route, true;
        end
        accessxi.nav_route_last_reject_reason = 'complete walked La Theine survey has no proven West exit connection';
        return T{}, true;
    end

    local destination_id, destination_horizontal, destination_vertical = accessxi.nav_recorded_survey_nearest(point);
    if (destination_id <= 0 or destination_horizontal > 6.0 or destination_vertical > 4.5) then
        accessxi.nav_route_last_reject_reason = 'destination is outside the complete walked La Theine survey';
        return route, true;
    end

    local path = accessxi.nav_recorded_survey_shortest_path(player_id, destination_id);
    if (path:len() <= 0) then
        accessxi.nav_route_last_reject_reason = 'complete walked La Theine survey has no connected course';
        return route, true;
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

    accessxi.nav_route_last_reject_reason = '';
    log_line(('nav recorded survey route destination="%s" start=%d finish=%d count=%d'):fmt(
        point.name or '', player_id, destination_id, route:len()));
    return route, true;
end
