-- Zone-to-zone chain selection for cross-zone navigation.
--
-- Extracted from accessxi_reader.lua on 2026-08-22 so the choice of ROAD can be
-- tested offline against the shipped zone-line graph
-- (tools/test_nav_zoneline_router.lua) rather than only discovered in play.
--
-- The fault this exists to prevent: two chains of equal edge count from
-- Southern San d'Oria to Davoi, the tie broken by graph order, and a blind
-- level-14 player routed through King Ranperre's Tomb while the guide step
-- named La Theine Plateau and Jugner Forest.
--
-- Loaded by accessxi_reader.lua via load_code_module('nav_zoneline_router').

-- A TOMB IS NOT A ROAD.
--
-- Live 2026-08-24, The Davoi Report. From East Ronfaure the player was sent to
-- Davoi through KING RANPERRE'S TOMB, and they were standing at its zone line
-- when they said it was leading them the wrong way. The server's own zone table
-- settles who was right: East Ronfaure's only neighbours are West Ronfaure,
-- Ghelsba Outpost, King Ranperre's Tomb and Southern San d'Oria -- there is NO
-- East Ronfaure to Jugner Forest link -- so there are exactly two ways:
--
--   via King Ranperre's Tomb   101 -> 190 -> 104 -> 149          3 zones
--   via La Theine Plateau      101 -> 100 -> 102 -> 104 -> 149   4 zones
--
-- This search counted edges, so the tomb won by one. It is a dungeon full of
-- undead, and the field route is what a player actually takes. The
-- classification is not a guess: LSB zone_settings types every zone, and King
-- Ranperre's Tomb and Ranguemont Pass are type 4 (dungeon) while East Ronfaure,
-- West Ronfaure, La Theine and Jugner Forest are type 2 (outdoors).
--
-- So transit through a dungeon costs four field zones. The DESTINATION is never
-- penalised -- Davoi is itself a dungeon and you have to go there. Four rather
-- than two because at two those chains tie, and a tie is settled by edge order,
-- which is how this bug would quietly come back.
local nav_zone_types = nil;
local DUNGEON_TRANSIT_COST = 4;

local function zone_transit_cost(zone_id, to_zone)
    if (zone_id == to_zone) then return 1; end
    if (nav_zone_types == nil) then
        -- A SILENT EMPTY TABLE MADE EVERY ZONE COST THE SAME.
        --
        -- This used to be pcall(require, 'nav_zone_types'). `require` resolves
        -- against package.path, which my offline harness sets and the ADDON does
        -- not -- so the harness routed correctly while the live game loaded
        -- nothing, every zone fell to the dungeon cost, and the tie between two
        -- SEVEN-ZONE chains out of Chateau d'Oraguille was settled by edge order
        -- instead of by road quality. Live 2026-08-25 that sent the player down
        -- through Bostaunieux Oubliette again even though the walked exit into
        -- Northern San d'Oria was loaded and available.
        --
        -- Use the addon's own module loader first, and SAY SO when the table
        -- comes back empty: a cost model that silently degrades to "everything
        -- is a dungeon" is indistinguishable from one that is working.
        local loaded = nil;
        if (type(accessxi.load_module_table) == 'function') then
            local ok_mod, got = pcall(accessxi.load_module_table, 'nav_zone_types', nil);
            if (ok_mod and type(got) == 'table') then loaded = got; end
        end
        if (type(loaded) ~= 'table' or next(loaded) == nil) then
            local ok_req, got = pcall(require, 'nav_zone_types');
            if (ok_req and type(got) == 'table') then loaded = got; end
        end
        nav_zone_types = type(loaded) == 'table' and loaded or {};
        if (next(nav_zone_types) == nil and type(log_line) == 'function') then
            log_line('nav zone types UNAVAILABLE -- every zone will cost the same and dungeons will not be avoided');
        elseif (type(log_line) == 'function') then
            local n = 0;
            for _ in pairs(nav_zone_types) do n = n + 1; end
            log_line(('nav zone types loaded %d zones'):fmt(n));
        end
    end
    local kind = tonumber(nav_zone_types[tonumber(zone_id) or -1]);
    -- 1 city, 2 outdoors: an ordinary road. Anything else -- dungeon,
    -- battlefield, instanced -- is somewhere you cross deliberately, not
    -- somewhere you pass through on the way past.
    if (kind == 1 or kind == 2) then return 1; end
    return DUNGEON_TRANSIT_COST;
end

-- Cheapest chain by ROAD QUALITY rather than edge count. Uniform-cost search:
-- with every zone costing 1 it produces exactly the old breadth-first result.
-- The goal is accepted when it is POPPED, not when it is first discovered --
-- discovery order proves nothing once the steps have different costs.
function accessxi.nav_zoneline_shortest_path(from_zone, to_zone)
    local path = T{};
    if ((tonumber(from_zone) or 0) <= 0 or (tonumber(to_zone) or 0) <= 0) then
        return path;
    end

    local frontier = { from_zone };
    local cost = { [from_zone] = 0 };
    local previous = {};
    local settled = {};

    while (#frontier > 0) do
        local best_at, best_cost = 1, nil;
        for scan = 1, #frontier do
            local c = cost[frontier[scan]];
            if (c ~= nil and (best_cost == nil or c < best_cost)) then
                best_at, best_cost = scan, c;
            end
        end
        local zone = table.remove(frontier, best_at);

        if (zone == to_zone) then
            local reverse = {};
            local cursor = to_zone;
            while (cursor ~= from_zone) do
                local step = previous[cursor];
                if (step == nil or step.edge == nil) then
                    return T{};
                end
                table.insert(reverse, 1, step.edge);
                cursor = tonumber(step.zone) or 0;
            end
            for _, route_edge in ipairs(reverse) do
                path:append(route_edge);
            end
            return path;
        end

        if (not settled[zone]) then
            settled[zone] = true;
            for _, edge in ipairs(accessxi.nav_zoneline_out_edges(zone)) do
                local next_zone = tonumber(edge.to_zone) or 0;
                if (next_zone > 0 and not settled[next_zone]) then
                    local step_cost = (cost[zone] or 0)
                        + zone_transit_cost(next_zone, to_zone);
                    if (cost[next_zone] == nil or step_cost < cost[next_zone]) then
                        cost[next_zone] = step_cost;
                        previous[next_zone] = T{ zone = zone, edge = edge };
                        frontier[#frontier + 1] = next_zone;
                    end
                end
            end
        end
    end

    return path;
end

-- Zone ids the guide named for this step that are worth scoring: neither the
-- zone the player stands in nor the one they are travelling to. Returns nil
-- when there is nothing to prefer, so the caller keeps the plain shortest path.
function accessxi.nav_zoneline_preferred_set(preferred_zones, from_zone, to_zone)
    if (type(preferred_zones) ~= 'table') then
        return nil;
    end
    local set, count = {}, 0;
    for _, value in ipairs(preferred_zones) do
        local zone = tonumber(value) or 0;
        if (zone > 0 and zone ~= from_zone and zone ~= to_zone and set[zone] == nil) then
            set[zone] = true;
            count = count + 1;
        end
    end
    if (count == 0) then
        return nil;
    end
    return set;
end

-- THE GUIDE'S ROAD, AND AS LITTLE ELSE AS POSSIBLE.
--
-- The rule the player set on 2026-08-22, after being routed into King
-- Ranperre's Tomb twice and killed there: "just make sure it never chooses
-- anything other than what the guide has listed."
--
-- Taken literally that returns nothing at all -- from Southern San d'Oria the
-- only way to La Theine Plateau is through West Ronfaure, which The Davoi
-- Report never mentions. So the rule is expressed as a cost instead of a ban:
-- MINIMISE the zones the guide did not name. A road with one unnamed connector
-- beats a road with two, whatever their edge counts, so
--
--   San d'Oria -> [West Ronfaure] -> La Theine -> Jugner -> Davoi   (1 unnamed)
--
-- wins over
--
--   San d'Oria -> [East Ronfaure] -> [Ranperre's Tomb] -> Jugner -> Davoi  (2)
--
-- and a necessary connector still survives, which a hard ban would not allow.
-- Scoring the named zones instead of the unnamed ones was the earlier version
-- and it tied these two roads at equal edge count.
function accessxi.nav_zoneline_preferred_path(from_zone, to_zone, preferred, max_edges)
    local best, best_unnamed, best_edges, best_ids = nil, math.huge, math.huge, nil;
    local frontier = { T{ zone = from_zone, edges = T{}, unnamed = 0, ids = '' } };
    local visited = {};
    for _ = 1, max_edges do
        local nextf = {};
        for _, state in ipairs(frontier) do
            for _, edge in ipairs(accessxi.nav_zoneline_out_edges(state.zone)) do
                local next_zone = tonumber(edge.to_zone) or 0;
                if (next_zone > 0 and next_zone ~= from_zone) then
                    local repeated = false;
                    for _, walked in ipairs(state.edges) do
                        if ((tonumber(walked.to_zone) or 0) == next_zone) then
                            repeated = true;
                            break;
                        end
                    end
                    if (not repeated) then
                        local edges = T{};
                        for _, walked in ipairs(state.edges) do edges:append(walked); end
                        edges:append(edge);
                        -- The destination itself is never "unnamed"; it is where
                        -- the player is going, not a road they were sent down.
                        local unnamed = state.unnamed;
                        if (next_zone ~= to_zone and not preferred[next_zone]) then
                            unnamed = unnamed + 1;
                        end
                        local ids = state.ids .. ':' .. tostring(tonumber(edge.id) or 0);
                        if (next_zone == to_zone) then
                            local count = edges:len();
                            if (unnamed < best_unnamed
                                or (unnamed == best_unnamed and count < best_edges)
                                or (unnamed == best_unnamed and count == best_edges
                                    and (best_ids == nil or ids < best_ids))) then
                                best, best_unnamed, best_edges, best_ids = edges, unnamed, count, ids;
                            end
                        else
                            local key = ('%d:%d'):fmt(next_zone, unnamed);
                            local seen_edges = visited[key];
                            if (seen_edges == nil or edges:len() <= seen_edges) then
                                visited[key] = edges:len();
                                nextf[#nextf + 1] = T{
                                    zone = next_zone, edges = edges,
                                    unnamed = unnamed, ids = ids };
                            end
                        end
                    end
                end
            end
        end
        frontier = nextf;
        if (#frontier == 0) then
            break;
        end
    end
    return best, best_unnamed;
end

-- ONE SEARCH FOR EVERY DESTINATION, NOT ONE PER ENTRANCE.
--
-- Offering every zone a duplicated name lives in means asking whether each is
-- reachable, and the per-zone answer runs a search per INCOMING EDGE of the
-- destination: 852 of them on one objective, measured, and the whole corpus
-- went from 4.5 to 14.2 seconds. One breadth-first tree from where the player
-- stands answers all of them.
--
-- This is only equivalent when NO road is named. Guide-road scoring is
-- destination-specific -- it minimises the zones the guide did not name -- so a
-- shared plain tree must never replace it, or a level-14 player goes through
-- King Ranperre's Tomb again. The caller enforces that; these functions only
-- reproduce the plain-chain half of accessxi.nav_zoneline_path.

function accessxi.nav_zoneline_entry_edge_workspace(
    raw_edges,
    edge_available,
    edge_rank)

    local workspace = {
        outgoing = {},
        available_by_id = {},
        rank_by_edge = {},
        ordinal_by_edge = {},
    };

    for ordinal, edge in ipairs(
        type(raw_edges) == 'table'
            and raw_edges or {}) do
        local available = true;

        if (type(edge_available) == 'function') then
            local ok, value =
                pcall(edge_available, edge);

            -- A callback failure invalidates the optimization. It must not be
            -- converted into false evidence that an edge is unavailable.
            if (not ok) then error(value); end
            available = value == true;
        end

        if (available and type(edge) == 'table') then
            local id = tonumber(edge.id) or 0;
            local from_zone =
                tonumber(edge.from_zone) or 0;
            local to_zone =
                tonumber(edge.to_zone) or 0;
            local rank = 50;

            if (type(edge_rank) == 'function') then
                local ok, value =
                    pcall(edge_rank, edge);

                if (not ok) then error(value); end
                rank = tonumber(value) or 50;
            end

            workspace.rank_by_edge[edge] = rank;
            workspace.ordinal_by_edge[edge] = ordinal;

            if (id > 0) then
                workspace.available_by_id[id] =
                    workspace.available_by_id[id] or {};
                workspace.available_by_id[id][
                    #workspace.available_by_id[id] + 1] =
                        edge;
            end

            if (from_zone > 0 and to_zone > 0) then
                workspace.outgoing[from_zone] =
                    workspace.outgoing[from_zone] or {};
                workspace.outgoing[from_zone][
                    #workspace.outgoing[from_zone] + 1] =
                        edge;
            end
        end
    end

    for _, bucket in pairs(workspace.outgoing) do
        table.sort(bucket, function(left, right)
            local left_rank =
                workspace.rank_by_edge[left] or 50;
            local right_rank =
                workspace.rank_by_edge[right] or 50;

            if (left_rank ~= right_rank) then
                return left_rank < right_rank;
            end

            local left_id = tonumber(left.id) or 0;
            local right_id = tonumber(right.id) or 0;

            if (left_id ~= right_id) then
                return left_id < right_id;
            end

            return (workspace.ordinal_by_edge[left] or 0)
                < (workspace.ordinal_by_edge[right] or 0);
        end);
    end

    return workspace;
end

function accessxi.nav_zoneline_entry_edge_shortest_tree(
    workspace,
    from_zone)

    from_zone = tonumber(from_zone) or 0;

    local tree = {
        from_zone = from_zone,
        previous = {},
        depth = {},
    };

    if (from_zone <= 0
        or type(workspace) ~= 'table') then
        return tree;
    end

    local queue, head = { from_zone }, 1;
    tree.depth[from_zone] = 0;

    while (head <= #queue) do
        local zone = queue[head];
        head = head + 1;

        for _, edge in ipairs(
            workspace.outgoing[zone] or {}) do
            local next_zone =
                tonumber(edge.to_zone) or 0;

            if (next_zone > 0
                and tree.depth[next_zone] == nil) then
                tree.depth[next_zone] =
                    tree.depth[zone] + 1;
                tree.previous[next_zone] = {
                    zone = zone,
                    edge = edge,
                };
                queue[#queue + 1] = next_zone;
            end
        end
    end

    return tree;
end

local function entry_edge_tree_path(tree, to_zone)
    to_zone = tonumber(to_zone) or 0;

    if (to_zone == tree.from_zone) then
        return {};
    end
    if (tree.depth[to_zone] == nil) then
        return nil;
    end

    local reverse = {};
    local cursor = to_zone;

    while (cursor ~= tree.from_zone) do
        local step = tree.previous[cursor];

        if (type(step) ~= 'table'
            or type(step.edge) ~= 'table') then
            return nil;
        end

        reverse[#reverse + 1] = step.edge;
        cursor = tonumber(step.zone) or 0;
    end

    local path = {};

    for index = #reverse, 1, -1 do
        path[#path + 1] = reverse[index];
    end

    return path;
end

function accessxi.nav_zoneline_entry_edge_candidates(
    workspace,
    tree,
    destination_zones,
    incoming_edges)

    local result = {};
    local seen = {};

    for _, value in ipairs(
        type(destination_zones) == 'table'
            and destination_zones or {}) do
        local dest_zone = tonumber(value) or 0;

        if (dest_zone > 0 and not seen[dest_zone]) then
            seen[dest_zone] = true;
            result[dest_zone] = {};

            local incoming = {};

            if (type(incoming_edges) == 'function') then
                incoming = incoming_edges(dest_zone);
            elseif (type(incoming_edges) == 'table') then
                incoming = incoming_edges[dest_zone];
            end

            if (type(incoming) ~= 'table') then
                incoming = {};
            end

            for _, supplied_edge in ipairs(incoming) do
                if (type(supplied_edge) == 'table') then
                    local final_id =
                        tonumber(supplied_edge.id) or 0;
                    local matches =
                        workspace.available_by_id[final_id];
                    local canonical =
                        type(matches) == 'table'
                        and #matches == 1
                        and matches[1] or nil;

                    -- Canonical identity proves availability and endpoints.
                    -- The supplied physical row remains the returned/ranked
                    -- choice because it owns the entrance coordinates.
                    if (final_id > 0
                        and type(canonical) == 'table'
                        and (tonumber(canonical.to_zone) or 0)
                            == dest_zone
                        and (tonumber(canonical.from_zone) or 0)
                            > 0) then
                        local final_from =
                            tonumber(canonical.from_zone) or 0;
                        local prefix =
                            entry_edge_tree_path(
                                tree,
                                final_from);

                        if (prefix ~= nil) then
                            local conflict = false;

                            for _, edge in ipairs(prefix) do
                                if ((tonumber(edge.id) or 0)
                                        == final_id
                                    or (tonumber(edge.from_zone) or 0)
                                        == dest_zone
                                    or (tonumber(edge.to_zone) or 0)
                                        == dest_zone) then
                                    conflict = true;
                                    break;
                                end
                            end

                            if (not conflict) then
                                result[dest_zone][
                                    #result[dest_zone] + 1] = {
                                        edge = supplied_edge,
                                        path_len = #prefix + 1,
                                    };
                            end
                        end
                    end
                end
            end
        end
    end

    return result;
end

-- THE ENTRY POINT, moved here from accessxi_reader.lua so that the harnesses
-- can call the real one. Every caller asks this: given where the player is,
-- where they are going, optionally which entrance, and the zones the guide
-- named -- what is the road?
function accessxi.nav_zoneline_path(from_zone, to_zone, final_edge_id, preferred_zones)
    from_zone = tonumber(from_zone) or 0;
    to_zone = tonumber(to_zone) or 0;
    final_edge_id = tonumber(final_edge_id) or 0;
    local path = T{};
    if (from_zone <= 0 or to_zone <= 0 or final_edge_id < 0) then
        return path;
    end
    if (from_zone == to_zone) then
        return path;
    end

    if (final_edge_id > 0) then
        accessxi.nav_load_zoneline_graph();
        local final_edge = nil;
        local id_matches = 0;
        for _, edge in ipairs(accessxi.nav_zoneline_edges) do
            if ((tonumber(edge.id) or 0) == final_edge_id and accessxi.nav_transport_edge_available(edge)) then
                final_edge = edge;
                id_matches = id_matches + 1;
            end
        end
        if (id_matches ~= 1 or final_edge == nil
            or (tonumber(final_edge.to_zone) or 0) ~= to_zone
            or (tonumber(final_edge.from_zone) or 0) <= 0) then
            return path;
        end

        local final_from_zone = tonumber(final_edge.from_zone) or 0;
        if (from_zone == final_from_zone) then
            path:append(final_edge);
            return path;
        end
        -- AND THE ROAD MUST NOT BE STEERED THROUGH THE DESTINATION.
        -- The preference scores zones the guide named, and a travel step names
        -- its own destination -- "Make your way to Davoi" has zones = {Davoi}.
        -- So the PREFIX search preferred roads that pass through Davoi on the
        -- way to Davoi's doorstep, and the conflict check below then threw
        -- every one of them away. Measured on the shipped graph: Carpenters'
        -- Landing has three entrances reachable from Southern San d'Oria, and
        -- naming it as the destination left one. Offering one of three is
        -- choosing for the player, which is the one thing this must never do.
        local prefix_preferred = preferred_zones;
        if (type(preferred_zones) == 'table') then
            prefix_preferred = {};
            for _, value in ipairs(preferred_zones) do
                if ((tonumber(value) or 0) ~= to_zone) then
                    prefix_preferred[#prefix_preferred + 1] = value;
                end
            end
        end
        local prefix = accessxi.nav_zoneline_path(from_zone, final_from_zone, 0, prefix_preferred);
        if (prefix:len() == 0) then
            return path;
        end
        for _, edge in ipairs(prefix) do
            if ((tonumber(edge.id) or 0) == final_edge_id
                or (tonumber(edge.from_zone) or 0) == to_zone
                or (tonumber(edge.to_zone) or 0) == to_zone) then
                return T{};
            end
            path:append(edge);
        end
        path:append(final_edge);
        return path;
    end

    -- The chain search lives in nav_zoneline_router. If that module ever fails
    -- to load, cross-zone routing must degrade to "no chain" rather than
    -- raising out of the route poll.
    if (type(accessxi.nav_zoneline_shortest_path) ~= 'function') then
        return path;
    end
    local shortest = accessxi.nav_zoneline_shortest_path(from_zone, to_zone);
    if (shortest:len() == 0) then
        return path;
    end

    -- THE ROAD THE GUIDE NAMES. Edge count alone made two 4-zone chains to
    -- Davoi equal, and the tie fell to graph order: a blind level-14 player was
    -- sent through King Ranperre's Tomb on 2026-08-22 while the guide's own
    -- step named La Theine Plateau and Jugner Forest.
    --
    -- The preference is NOT a restriction on which zones may be walked -- that
    -- would drop West Ronfaure, an unnamed but necessary connector. Search the
    -- whole graph to one edge longer than the shortest chain and prefer the
    -- route that visits the most zones the guide actually named (sol, ruling
    -- D). Current and destination zones do not score: they are where the
    -- player is and where they are going, not a choice of road.
    local preferred = accessxi.nav_zoneline_preferred_set(preferred_zones, from_zone, to_zone);
    if (preferred == nil) then
        -- Say so. A silent fallback to "any shortest chain" is exactly how a
        -- level-14 player ended up in King Ranperre's Tomb, and from the log
        -- it was indistinguishable from the preference being honoured.
        local key = ('none:%d:%d'):fmt(from_zone, to_zone);
        if (key ~= tostring(accessxi.nav_zoneline_road_logged or '')) then
            accessxi.nav_zoneline_road_logged = key;
            local given_ids = 'nil';
            if (type(preferred_zones) == 'table') then
                local parts = {};
                for _, value in ipairs(preferred_zones) do
                    parts[#parts + 1] = ('%s(%s)'):fmt(
                        accessxi.nav_graph_zone_name(tonumber(value) or 0), tostring(value));
                end
                given_ids = #parts > 0 and table.concat(parts, ',') or 'empty-table';
            end
            log_line(('nav road from=%s to=%s NO GUIDE ROAD given=%s -- using any shortest chain'):fmt(
                accessxi.nav_graph_zone_name(from_zone), accessxi.nav_graph_zone_name(to_zone),
                given_ids));
        end
        return shortest;
    end
    -- Wider than the shortest chain by two, because the guide's road is worth
    -- a detour: the player would rather walk one extra zone than be sent
    -- through somewhere the guide never mentioned.
    local guided, unnamed = accessxi.nav_zoneline_preferred_path(
        from_zone, to_zone, preferred, shortest:len() + 2);
    if (guided ~= nil and guided:len() > 0) then
        local names = {};
        for _, edge in ipairs(guided) do
            names[#names + 1] = accessxi.nav_graph_zone_name(tonumber(edge.to_zone) or 0);
        end
        local key = ('%d:%d:%s'):fmt(from_zone, to_zone, table.concat(names, '>'));
        if (key ~= tostring(accessxi.nav_zoneline_road_logged or '')) then
            accessxi.nav_zoneline_road_logged = key;
            log_line(('nav road from=%s to=%s via=%s unnamed=%d edges=%d (shortest=%d) edge_id=%d'):fmt(
                accessxi.nav_graph_zone_name(from_zone), accessxi.nav_graph_zone_name(to_zone),
                table.concat(names, ' > '), tonumber(unnamed) or -1,
                guided:len(), shortest:len(), tonumber(final_edge_id) or 0));
        end
        return guided;
    end
    return shortest;
end
