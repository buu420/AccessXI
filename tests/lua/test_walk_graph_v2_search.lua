-- AXWG v2 edge-state A* and connector-boundary behavior.

package.path = './tests/lua/?.lua;./tools/navbuild/lua/?.lua;' .. package.path;

local fixture = require('axwg_v2_fixture');
local walk_graph = require('walk_graph');

local spec = {
    zone_id = 102,
    component_count = 1,
    nodes = {
        { x = 0, z = 0, y = 0, component = 0, clearance = 2 },
        { x = 4, z = 0, y = 0, component = 0, clearance = 2 },
        { x = 8, z = 0, y = 0, component = 0, clearance = 2 },
    },
    portals = {
        {
            node_a = 0, node_b = 1,
            left_x = 2, left_z = 2, right_x = 2, right_z = 1,
            left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
            capacity_cm = 100, flags = 3,
        },
        {
            node_a = 0, node_b = 1,
            left_x = 2, left_z = -1, right_x = 2, right_z = -2,
            left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
            capacity_cm = 100, flags = 3,
        },
        {
            node_a = 1, node_b = 2,
            left_x = 6, left_z = 0, right_x = 6, right_z = -2,
            left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
            capacity_cm = 200, flags = 3,
        },
    },
    adjacency = {
        {
            { to = 1, portal_id = 0, cost = 4 },
            { to = 1, portal_id = 1, cost = 4 },
        },
        {
            { to = 0, portal_id = 0, cost = 4 },
            { to = 0, portal_id = 1, cost = 4 },
            { to = 2, portal_id = 2, cost = 4 },
        },
        {},
    },
};

local path = os.tmpname();
fixture.write(path, spec);
local graph = assert(walk_graph.load(path, 102));
os.remove(path);

local exact = assert(graph:begin_astar(0, 2));
local status, route = exact:step(1);
assert(status == 'pending' and route == nil,
    'one-expansion edge-state A* slice did not yield pending');
repeat
    status, route = exact:step(1);
until status ~= 'pending';
assert(status == 'ready', 'edge-state A* did not find the directed route');
assert(#route == 3 and route[1] == 0 and route[2] == 1 and route[3] == 2,
    'v2 route did not preserve numeric node-path compatibility');
assert(#route.edge_ids == 2 and route.edge_ids[1] == 1 and route.edge_ids[2] == 4,
    'edge-state A* ignored the shorter incoming-to-outgoing portal transition');
assert(#route.portal_ids == 2 and route.portal_ids[1] == 1
        and route.portal_ids[2] == 2,
    'edge-state A* collapsed or lost the parallel portal component');
assert(math.abs(route.total_cost
        - (2.5 + math.sqrt(16.25) + math.sqrt(5))) < 0.0001,
    'edge-state route cost did not follow its selected portal midpoints');

local reverse = assert(graph:begin_astar(2, 0));
status, route = reverse:step(20);
assert(status == 'no-path' and route == nil,
    'edge-state A* invented a reverse edge through a one-way doorway');

local function certified(node_id, x, connector_cost, label)
    return {
        node_id = node_id, x = x, z = 0, y = 0,
        connector_cost = connector_cost,
        connector_certified = true,
        label = label,
    };
end

local multi = assert(graph:begin_route({
    certified(0, 0, 10, 'far start'),
    certified(1, 4, 0, 'near start'),
}, {
    certified(2, 8, 1, 'goal'),
}));
repeat
    status, route = multi:step(2);
until status ~= 'pending';
assert(status == 'ready', 'multi-source/multi-goal edge-state route failed');
assert(#route == 2 and route[1] == 1 and route[2] == 2,
    'multi-source route chose a single nearest/start candidate prematurely');
assert(route.start_candidate.label == 'near start'
        and route.goal_candidate.label == 'goal'
        and math.abs(route.total_cost - (1 + 2 * math.sqrt(5))) < 0.0001,
    'candidate connector costs or selected candidate identity were lost');

local uncertified, uncertified_reason = graph:begin_route({
    { node_id = 0, x = 0, z = 0, y = 0, connector_cost = 0 },
}, {
    certified(2, 8, 0, 'goal'),
});
assert(uncertified == nil
        and tostring(uncertified_reason):find('certified', 1, true) ~= nil,
    'route search accepted an uncertified live start connector');

local malformed, malformed_reason = graph:begin_route({
    { node_id = 0, connector_cost = 0, connector_certified = true },
}, {
    certified(2, 8, 0, 'goal'),
});
assert(malformed == nil
        and tostring(malformed_reason):find('finite x,z,y', 1, true) ~= nil,
    'route search accepted a certified connector without finite geometry');

local underpriced, underpriced_reason = graph:begin_route({
    certified(0, -2, 1, 'underpriced direct start'),
}, {
    certified(2, 8, 0, 'goal'),
});
assert(underpriced == nil
        and tostring(underpriced_reason):find('direct distance', 1, true) ~= nil,
    'route search accepted a connector cost below its certified direct segment');

local vertical_only, vertical_only_reason = graph:begin_route({
    {
        node_id = 0, x = 0, z = 0, y = 2,
        connector_cost = 2, connector_certified = true,
    },
}, {
    certified(2, 8, 0, 'goal'),
});
assert(vertical_only == nil
        and tostring(vertical_only_reason):find('no horizontal walk', 1, true) ~= nil,
    'route search accepted an impossible vertical-only direct connector');

local superseded = assert(graph:begin_astar(0, 2));
assert(graph:begin_astar(0, 1));
status, route, malformed_reason = superseded:step(1);
assert(status == nil and route == nil
        and tostring(malformed_reason):find('superseded', 1, true) ~= nil,
    'a newer edge-state search did not supersede the old workspace owner');

print('AXWG v2 edge-state A* and certified connector behavior ok');

local benchmark_count = tonumber(os.getenv('AXWG_V2_BENCH_NODES')) or 25000;
local benchmark_nodes, benchmark_portals, benchmark_adjacency = {}, {}, {};
for index = 1, benchmark_count do
    benchmark_nodes[index] = {
        x = index - 1, z = 0, y = 0, component = 0, clearance = 2,
    };
    benchmark_adjacency[index] = {};
    if (index < benchmark_count) then
        local middle = index - 0.5;
        benchmark_portals[index] = {
            node_a = index - 1, node_b = index,
            left_x = middle, left_z = 1,
            right_x = middle, right_z = -1,
            left_y_a = 0, left_y_b = 0,
            right_y_a = 0, right_y_b = 0,
            capacity_cm = 200, flags = 3,
        };
        benchmark_adjacency[index][1] = { to = index, portal_id = index - 1 };
    end
end
local benchmark_path = os.tmpname();
local build_started = os.clock();
fixture.write(benchmark_path, {
    zone_id = 102,
    component_count = 1,
    nodes = benchmark_nodes,
    portals = benchmark_portals,
    adjacency = benchmark_adjacency,
    max_edge_run = 2,
});
local build_ms = (os.clock() - build_started) * 1000;
local load_started = os.clock();
local benchmark_graph = assert(walk_graph.load(benchmark_path, 102));
local load_ms = (os.clock() - load_started) * 1000;
os.remove(benchmark_path);

local benchmark_search = assert(benchmark_graph:begin_astar(0, benchmark_count - 1));
local search_started, max_slice_ms = os.clock(), 0;
repeat
    local slice_started = os.clock();
    status, route = benchmark_search:step(512);
    max_slice_ms = math.max(max_slice_ms, (os.clock() - slice_started) * 1000);
until status ~= 'pending';
local search_ms = (os.clock() - search_started) * 1000;
assert(status == 'ready' and #route == benchmark_count
        and #route.edge_ids == benchmark_count - 1
        and #route.portal_ids == benchmark_count - 1,
    'large edge-state benchmark did not preserve its exact corridor');
local state_count = benchmark_graph.edge_count + benchmark_graph.node_count + 1;
print(('AXWG v2 benchmark nodes=%d edges=%d states=%d workspace=%.1fMiB '
        .. 'build=%.1fms load=%.1fms search=%.1fms max512=%.3fms expansions=%d'):format(
    benchmark_count, benchmark_graph.edge_count, state_count,
    state_count * 40 / 1048576, build_ms, load_ms, search_ms,
    max_slice_ms, benchmark_search.expansions));
