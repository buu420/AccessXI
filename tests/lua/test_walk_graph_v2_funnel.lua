-- AXWG v2 certified-portal funnel and dual-height crossing behavior.

package.path = './tests/lua/?.lua;./tools/navbuild/lua/?.lua;' .. package.path;

local fixture = require('axwg_v2_fixture');
local walk_graph = require('walk_graph');

local function load(spec)
    local path = os.tmpname();
    fixture.write(path, spec);
    local graph = assert(walk_graph.load(path, 102));
    os.remove(path);
    return graph;
end

local function ready(graph, start_id, goal_id)
    local search = assert(graph:begin_astar(start_id, goal_id));
    local status, route;
    repeat status, route = search:step(16); until status ~= 'pending';
    assert(status == 'ready', 'fixture route was not ready');
    return route;
end

local function point(x, z, y)
    return { x = x, z = z, y = y, connector_certified = true };
end

local function close(actual, expected)
    return math.abs(actual - expected) < 0.0001;
end

local straight = load({
    zone_id = 102,
    component_count = 1,
    nodes = {
        { x = 0, z = 0, y = 0, component = 0, clearance = 2 },
        { x = 4, z = 0, y = 0.2, component = 0, clearance = 2 },
        { x = 8, z = 0, y = 0.4, component = 0, clearance = 2 },
    },
    portals = {
        {
            node_a = 0, node_b = 1,
            left_x = 2, left_z = 1, right_x = 2, right_z = -1,
            left_y_a = 0, left_y_b = 0.2,
            right_y_a = 0, right_y_b = 0.2,
            capacity_cm = 200, flags = 3,
        },
        {
            node_a = 1, node_b = 2,
            left_x = 6, left_z = 1, right_x = 6, right_z = -1,
            left_y_a = 0.2, left_y_b = 0.4,
            right_y_a = 0.2, right_y_b = 0.4,
            capacity_cm = 200, flags = 3,
        },
    },
    adjacency = {
        { { to = 1, portal_id = 0 } },
        { { to = 0, portal_id = 0 }, { to = 2, portal_id = 1 } },
        { { to = 1, portal_id = 1 } },
    },
});

local straight_route = ready(straight, 0, 2);
local pulled = assert(straight:funnel(
    straight_route, point(0, 0, 0), point(8, 0, 0.4)));
assert(#pulled.corners == 2
        and close(pulled.corners[1].x, 0)
        and close(pulled.corners[2].x, 8),
    'straight certified corridor grew an unnecessary funnel corner');
assert(#pulled.crossings == 2,
    'funnel did not retain one crossing per certified portal');
assert(close(pulled.crossings[1].x, 2)
        and close(pulled.crossings[1].z, 0)
        and close(pulled.crossings[1].y_from, 0)
        and close(pulled.crossings[1].y_to, 0.2),
    'first ledge crossing lost its two owner-surface heights');
assert(close(pulled.crossings[2].x, 6)
        and close(pulled.crossings[2].y_from, 0.2)
        and close(pulled.crossings[2].y_to, 0.4),
    'second ledge crossing invented or averaged a height');

local reverse_route = ready(straight, 2, 0);
local reverse = assert(straight:funnel(
    reverse_route, point(8, 0, 0.4), point(0, 0, 0)));
assert(#reverse.crossings == 2
        and close(reverse.crossings[1].x, 6)
        and close(reverse.crossings[1].y_from, 0.4)
        and close(reverse.crossings[1].y_to, 0.2),
    'reverse funnel did not swap portal owner heights');

local external_start = {
    node_id = 0, x = -2, z = 2, y = 0,
    connector_cost = math.sqrt(8), connector_certified = true,
};
local external_search = assert(straight:begin_route({ external_start }, { 2 }));
local external_status, external_route;
repeat
    external_status, external_route = external_search:step(16);
until external_status ~= 'pending';
assert(external_status == 'ready', 'direct external connector route was not ready');
local external = assert(straight:funnel(
    external_route, point(-2, 2, 0), point(8, 0, 0.4)));
assert(#external.corners >= 3
        and close(external.corners[1].x, -2)
        and close(external.corners[1].z, 2)
        and close(external.corners[2].x, 0)
        and close(external.corners[2].z, 0),
    'funnel discarded the certified direct connector and invented a new chord');
local mismatched_external, mismatched_external_reason = straight:funnel(
    external_route, point(-1.9, 2, 0), point(8, 0, 0.4));
assert(mismatched_external == nil
        and tostring(mismatched_external_reason):find('does not match', 1, true),
    'funnel substituted a point not owned by the route connector');

local corner_graph = load({
    zone_id = 102,
    component_count = 1,
    nodes = {
        { x = 0, z = 0, y = 0, component = 0, clearance = 2 },
        { x = 4, z = 0, y = 0, component = 0, clearance = 2 },
        { x = 4, z = 4, y = 0, component = 0, clearance = 2 },
    },
    portals = {
        {
            node_a = 0, node_b = 1,
            left_x = 2, left_z = 1, right_x = 2, right_z = -1,
            left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
            capacity_cm = 200, flags = 3,
        },
        {
            node_a = 1, node_b = 2,
            left_x = 3, left_z = 2, right_x = 5, right_z = 2,
            left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
            capacity_cm = 200, flags = 3,
        },
    },
    adjacency = {
        { { to = 1, portal_id = 0 } },
        { { to = 0, portal_id = 0 }, { to = 2, portal_id = 1 } },
        { { to = 1, portal_id = 1 } },
    },
});
local corner_route = ready(corner_graph, 0, 2);
local corner = assert(corner_graph:funnel(
    corner_route, point(0, 0, 0), point(4, 4, 0)));
local corner_dump = {};
for i, value in ipairs(corner.corners) do
    corner_dump[#corner_dump + 1] = ('%d=(%.3f,%.3f)'):format(i, value.x, value.z);
end
assert(#corner.corners == 4
        and close(corner.corners[2].x, 2) and close(corner.corners[2].z, 1)
        and close(corner.corners[3].x, 3) and close(corner.corners[3].z, 2)
        and #corner.crossings == 2
        and close(corner.crossings[1].x, 2)
        and close(corner.crossings[1].z, 1)
        and close(corner.crossings[2].x, 3)
        and close(corner.crossings[2].z, 2),
    'L-shaped certified corridor was replaced by an unsafe direct chord: '
        .. table.concat(corner_dump, ' '));

local unsafe, unsafe_reason = straight:funnel(
    straight_route, { x = 0, z = 0, y = 0 }, point(8, 0, 0.4));
assert(unsafe == nil and tostring(unsafe_reason):find('certified', 1, true) ~= nil,
    'funnel accepted an uncertified start connector');

local malformed_route = {
    straight_route[1], straight_route[2], straight_route[3],
    nodes = straight_route.nodes,
    edge_ids = straight_route.edge_ids,
    portal_ids = { 99, straight_route.portal_ids[2] },
};
local malformed, malformed_reason = straight:funnel(
    malformed_route, point(0, 0, 0), point(8, 0, 0.4));
assert(malformed == nil and tostring(malformed_reason):find('portal', 1, true) ~= nil,
    'funnel emitted guidance for a malformed portal sequence');

local collinear_graph = load({
    zone_id = 102,
    component_count = 1,
    nodes = {
        { x = 0, z = -2, y = 0, component = 0, clearance = 2 },
        { x = 0, z = 2, y = 0, component = 0, clearance = 2 },
    },
    portals = {
        {
            node_a = 0, node_b = 1,
            left_x = -1, left_z = 0, right_x = 1, right_z = 0,
            left_y_a = 0, left_y_b = 0,
            right_y_a = 0, right_y_b = 0,
            capacity_cm = 200, flags = 3,
        },
    },
    adjacency = {
        { { to = 1, portal_id = 0 } },
        { { to = 0, portal_id = 0 } },
    },
});
local collinear_route = ready(collinear_graph, 0, 1);
local anchored = assert(collinear_graph:funnel(
    collinear_route, point(0, -2, 0), point(0, 2, 0)));
assert(#anchored.corners == 2
        and close(anchored.crossings[1].x, 0)
        and close(anchored.crossings[1].z, 0),
    'a unique certified portal crossing was not retained deterministically');

print('AXWG v2 certified-portal funnel and dual-height crossing behavior ok');
