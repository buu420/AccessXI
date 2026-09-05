-- AXWG v2 route-local, arc-bounded candidate matching behavior.

package.path = './tests/lua/?.lua;./tools/navbuild/lua/?.lua;' .. package.path;

local fixture = require('axwg_v2_fixture');
local walk_graph = require('walk_graph');

local xs = { 0, 1, 100, 200, 1.1, 2 };
local nodes, portals, adjacency = {}, {}, {};
for i, x in ipairs(xs) do
    nodes[i] = { x = x, z = 0, y = 0, component = 0, clearance = 2 };
    adjacency[i] = {};
end
for i = 1, #xs - 1 do
    local from_x, to_x = xs[i], xs[i + 1];
    local middle = (from_x + to_x) / 2;
    local east = to_x > from_x;
    portals[i] = {
        node_a = i - 1, node_b = i,
        left_x = middle, left_z = east and 1 or -1,
        right_x = middle, right_z = east and -1 or 1,
        left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
        capacity_cm = 200, flags = 3,
    };
    adjacency[i][1] = { to = i, portal_id = i - 1 };
end

local path = os.tmpname();
fixture.write(path, {
    zone_id = 102,
    component_count = 1,
    nodes = nodes,
    portals = portals,
    adjacency = adjacency,
    max_edge_run = 250,
});
local graph = assert(walk_graph.load(path, 102));
os.remove(path);

local search = assert(graph:begin_astar(0, 5));
local status, route;
repeat status, route = search:step(32); until status ~= 'pending';
assert(status == 'ready' and #route == 6,
    'folded-route fixture did not produce its owned route');

local local_match = assert(graph:match_route_candidate(route, 1.09, 0, 0, 2, {
    max_horizontal = 1,
    max_vertical = 2,
    minimum_node_clearance = 0.7,
    max_forward_arc = 24,
    max_backward_indices = 0,
}));
assert(local_match.node_id == 1 and local_match.route_index == 2,
    'spatially closer folded alias jumped hundreds of route yalms forward');
assert(local_match.forward_arc == 0,
    'owned local route match reported a false forward arc');

local fast = assert(graph:match_route_candidate(route, 100, 0, 0, 2, {
    max_horizontal = 1,
    max_vertical = 2,
    minimum_node_clearance = 0.7,
    max_forward_arc = 120,
    max_backward_indices = 0,
}));
assert(fast.node_id == 2 and fast.route_index == 3
        and math.abs(fast.forward_arc - 99) < 0.0001,
    'plausible skipped sample inside the arc budget did not advance');

local no_rewind, no_rewind_reason = graph:match_route_candidate(
    route, 0, 0, 0, 2, {
        max_horizontal = 0.2,
        max_vertical = 2,
        minimum_node_clearance = 0.7,
        max_forward_arc = 24,
        max_backward_indices = 0,
    });
assert(no_rewind == nil and tostring(no_rewind_reason):find('route-consistent', 1, true),
    'route matching rewound without explicit backward permission');

local allowed_rewind = assert(graph:match_route_candidate(
    route, 0, 0, 0, 2, {
        max_horizontal = 0.2,
        max_vertical = 2,
        minimum_node_clearance = 0.7,
        max_forward_arc = 24,
        max_backward_indices = 1,
    }));
assert(allowed_rewind.node_id == 0 and allowed_rewind.route_index == 1,
    'explicit bounded backward recovery did not match the prior route node');

local absent, absent_reason = graph:match_route_candidate(route, 50, 0, 0, 2, {
    max_horizontal = 1,
    max_vertical = 2,
    minimum_node_clearance = 0.7,
    max_forward_arc = 24,
    max_backward_indices = 0,
});
assert(absent == nil and tostring(absent_reason):find('route-consistent', 1, true),
    'no local route candidate did not return a replan-safe miss');

print('AXWG v2 route-local arc-bounded matching behavior ok');
