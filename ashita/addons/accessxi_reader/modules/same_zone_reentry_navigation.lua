local SAME_BOUNDARY_RADIUS = 50;

local function point_from_edge(edge)
    return T{
        zone = tonumber(edge ~= nil and edge.from_zone) or 0,
        x = tonumber(edge ~= nil and edge.from_x) or 0,
        z = tonumber(edge ~= nil and edge.from_z) or 0,
        y = tonumber(edge ~= nil and edge.from_y) or 0,
        kind = 'area',
    };
end

local function point_after_edge(edge)
    return T{
        zone = tonumber(edge ~= nil and edge.to_zone) or 0,
        x = tonumber(edge ~= nil and edge.to_x) or 0,
        z = tonumber(edge ~= nil and edge.to_z) or 0,
        y = tonumber(edge ~= nil and edge.to_y) or 0,
        kind = 'area',
    };
end

local function route_count(route)
    if route == nil or type(route.len) ~= 'function' then
        return 0;
    end
    return tonumber(route:len()) or 0;
end

local function transition_is_verified(edge)
    local confidence = tostring(edge ~= nil and edge.confidence or ''):lower();
    return confidence == 'proven' or confidence == 'verified' or confidence == 'live-verified';
end

local function same_physical_boundary(exit_edge, reentry_edge)
    if exit_edge == nil or reentry_edge == nil then
        return true;
    end
    if (tonumber(exit_edge.from_zone) or 0) ~= (tonumber(reentry_edge.to_zone) or 0)
        or (tonumber(exit_edge.to_zone) or 0) ~= (tonumber(reentry_edge.from_zone) or 0) then
        return false;
    end

    return nav_distance(point_after_edge(exit_edge), point_from_edge(reentry_edge)) <= SAME_BOUNDARY_RADIUS
        and nav_distance(point_from_edge(exit_edge), point_after_edge(reentry_edge)) <= SAME_BOUNDARY_RADIUS;
end

local function candidate_score(exit_edge, reentry_edge, first_count, middle_count, final_count, player)
    local exit_rank = select(1, accessxi.nav_zoneline_edge_rank(exit_edge, player));
    local reentry_rank = select(1, accessxi.nav_zoneline_edge_rank(reentry_edge, point_after_edge(exit_edge)));
    return ((tonumber(exit_rank) or 50) + (tonumber(reentry_rank) or 50)) * 10000
        + (tonumber(first_count) or 0)
        + (tonumber(middle_count) or 0)
        + (tonumber(final_count) or 0);
end

function accessxi.nav_same_zone_reentry_find(player, target)
    if player == nil or target == nil then
        return nil;
    end

    local origin_zone = tonumber(player.zone) or 0;
    if origin_zone <= 0 or origin_zone ~= (tonumber(target.zone) or 0) then
        return nil;
    end

    local previous_reject_reason = accessxi.nav_route_last_reject_reason;
    local best = nil;
    for _, exit_edge in ipairs(accessxi.nav_zoneline_out_edges(origin_zone, player)) do
        local neighbor_zone = tonumber(exit_edge.to_zone) or 0;
        if neighbor_zone > 0 and neighbor_zone ~= origin_zone and transition_is_verified(exit_edge) then
            local first_route = nav_compute_mesh_route(player, point_from_edge(exit_edge));
            local first_count = route_count(first_route);
            if first_count > 1 then
                local neighbor_arrival = point_after_edge(exit_edge);
                for _, reentry_edge in ipairs(accessxi.nav_zoneline_out_edges(neighbor_zone, neighbor_arrival)) do
                    if (tonumber(reentry_edge.to_zone) or 0) == origin_zone
                        and transition_is_verified(reentry_edge)
                        and not same_physical_boundary(exit_edge, reentry_edge) then
                        local middle_route = nav_compute_mesh_route(neighbor_arrival, point_from_edge(reentry_edge));
                        local middle_count = route_count(middle_route);
                        if middle_count > 1 then
                            local final_route = nav_compute_mesh_route(point_after_edge(reentry_edge), target);
                            local final_count = route_count(final_route);
                            if final_count > 1 then
                                local score = candidate_score(exit_edge, reentry_edge, first_count, middle_count, final_count, player);
                                if best == nil or score < best.score then
                                    best = T{
                                        edges = T{ exit_edge, reentry_edge },
                                        origin_zone = origin_zone,
                                        neighbor_zone = neighbor_zone,
                                        score = score,
                                        first_count = first_count,
                                        middle_count = middle_count,
                                        final_count = final_count,
                                    };
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    accessxi.nav_route_last_reject_reason = previous_reject_reason;

    if best ~= nil then
        log_line(('nav same-zone reentry verified target="%s" origin=%d neighbor=%d exit=%d reentry=%d counts=%d/%d/%d'):fmt(
            nav_clean_field(target.name or ''),
            best.origin_zone,
            best.neighbor_zone,
            tonumber(best.edges[1].id) or 0,
            tonumber(best.edges[2].id) or 0,
            best.first_count,
            best.middle_count,
            best.final_count));
    end
    return best;
end

function accessxi.nav_same_zone_reentry_clear()
    accessxi.nav_same_zone_reentry_edges = T{};
    accessxi.nav_same_zone_reentry_index = 0;
    accessxi.nav_same_zone_reentry_origin_zone = 0;
    accessxi.nav_same_zone_reentry_neighbor_zone = 0;
end

function accessxi.nav_same_zone_reentry_active()
    local edges = accessxi.nav_same_zone_reentry_edges;
    return accessxi.nav_zone_search_target ~= nil
        and edges ~= nil
        and type(edges.len) == 'function'
        and edges:len() == 2
        and (tonumber(accessxi.nav_same_zone_reentry_index) or 0) > 0;
end

function accessxi.nav_same_zone_reentry_begin(player, target)
    local plan = accessxi.nav_same_zone_reentry_find(player, target);
    if plan == nil then
        return false;
    end

    accessxi.nav_same_zone_reentry_edges = plan.edges;
    accessxi.nav_same_zone_reentry_index = 1;
    accessxi.nav_same_zone_reentry_origin_zone = plan.origin_zone;
    accessxi.nav_same_zone_reentry_neighbor_zone = plan.neighbor_zone;
    accessxi.nav_zone_search_target = accessxi.nav_copy_point(target);
    accessxi.nav_zone_search_query = nav_clean_field(target.name or '');
    accessxi.nav_zone_search_waiting_zone = 0;
    accessxi.nav_zone_search_waiting_from_zone = 0;
    accessxi.nav_zone_search_last_replan_tick = 0;
    return true;
end

function accessxi.nav_same_zone_reentry_start(player, target, reason)
    if type(accessxi.nav_zone_search_start_next_leg) ~= 'function'
        or not accessxi.nav_same_zone_reentry_begin(player, target) then
        return nil;
    end

    accessxi.nav_active = false;
    accessxi.nav_destination = nil;
    local text = accessxi.nav_zone_search_start_next_leg(reason or 'same-zone-reentry');
    log_line(('nav same-zone reentry start target="%s" result="%s"'):fmt(
        nav_clean_field(target ~= nil and target.name or ''),
        nav_clean_field(text or '')));
    return text;
end

function accessxi.nav_same_zone_reentry_current_leg(player)
    if not accessxi.nav_same_zone_reentry_active() then
        return nil, 'inactive';
    end

    local index = tonumber(accessxi.nav_same_zone_reentry_index) or 0;
    local edges = accessxi.nav_same_zone_reentry_edges;
    if index > edges:len() then
        if player ~= nil and (tonumber(player.zone) or 0) == (tonumber(accessxi.nav_same_zone_reentry_origin_zone) or 0) then
            return nil, 'complete';
        end
        return nil, 'waiting';
    end

    local edge = edges[index];
    if edge == nil or player == nil or (tonumber(player.zone) or 0) ~= (tonumber(edge.from_zone) or 0) then
        return nil, 'wrong-zone';
    end

    local target = accessxi.nav_zone_search_target;
    local next_zone = tonumber(edge.to_zone) or 0;
    local next_zone_name = accessxi.nav_graph_zone_name(next_zone);
    return T{
        zone = tonumber(edge.from_zone) or 0,
        name = ('%s zone line'):fmt(next_zone_name ~= '' and next_zone_name or nav_clean_field(edge.to_name or 'next zone')),
        x = tonumber(edge.from_x) or 0,
        z = tonumber(edge.from_z) or 0,
        y = tonumber(edge.from_y) or 0,
        kind = 'area',
        source = ('zonesearch:reentry:%d:%d:%d'):fmt(tonumber(edge.id) or 0, index, tonumber(accessxi.nav_same_zone_reentry_origin_zone) or 0),
        confidence = nav_clean_field(edge.confidence or ''),
        section = ('safe re-entry to %s'):fmt(target ~= nil and target.name or 'destination'),
        to_zone = next_zone,
        to_zone_name = next_zone_name,
        final_zone = tonumber(accessxi.nav_same_zone_reentry_origin_zone) or 0,
        final_name = target ~= nil and target.name or 'destination',
        same_zone_reentry_step = index,
        same_zone_reentry_edge_id = tonumber(edge.id) or 0,
    }, 'leg';
end

function accessxi.nav_same_zone_reentry_advance(destination)
    if not accessxi.nav_same_zone_reentry_active() or destination == nil then
        return false;
    end

    local index = tonumber(accessxi.nav_same_zone_reentry_index) or 0;
    local edge = accessxi.nav_same_zone_reentry_edges[index];
    if edge == nil
        or (tonumber(destination.same_zone_reentry_step) or 0) ~= index
        or (tonumber(destination.same_zone_reentry_edge_id) or 0) ~= (tonumber(edge.id) or 0)
        or (tonumber(destination.zone) or 0) ~= (tonumber(edge.from_zone) or 0)
        or (tonumber(destination.to_zone) or 0) ~= (tonumber(edge.to_zone) or 0) then
        return false;
    end

    accessxi.nav_same_zone_reentry_index = index + 1;
    log_line(('nav same-zone reentry advanced step=%d edge=%d from=%d to=%d'):fmt(
        index,
        tonumber(edge.id) or 0,
        tonumber(edge.from_zone) or 0,
        tonumber(edge.to_zone) or 0));
    return true;
end

return true;
