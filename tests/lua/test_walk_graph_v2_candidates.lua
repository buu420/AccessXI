-- AXWG v2 bounded candidate lookup behavior.

package.path = './tests/lua/?.lua;./tools/navbuild/lua/?.lua;' .. package.path;

local fixture = require('axwg_v2_fixture');
local walk_graph = require('walk_graph');

local spec = {
    zone_id = 102,
    component_count = 3,
    nodes = {
        { x = 0, z = 0, y = 0, component = 0, clearance = 2 },
        { x = 0, z = 0, y = 10, component = 1, clearance = 2 },
        { x = 2, z = 0, y = 0, component = 2, clearance = 0.2 },
        { x = 4, z = 0, y = 0, component = 0, clearance = 2 },
    },
    portals = {
        {
            node_a = 0, node_b = 3,
            left_x = 2, left_z = 1, right_x = 2, right_z = -1,
            left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
            capacity_cm = 200, flags = 3,
        },
    },
    adjacency = {
        { { to = 3, portal_id = 0 } },
        {},
        {},
        { { to = 0, portal_id = 0 } },
    },
};

local path = os.tmpname();
fixture.write(path, spec);
local graph = assert(walk_graph.load(path, 102));
os.remove(path);

local upper = assert(graph:candidates(0, 0, 9.5, {
    max_horizontal = 5,
    max_vertical = 2,
    minimum_node_clearance = 0.7,
    max_results = 8,
}));
assert(#upper == 1 and upper[1].node_id == 1,
    'bounded candidate lookup merged stacked vertical layers');
assert(upper[1].connector_certified ~= true,
    'candidate lookup falsely certified a live connector');

local lower = assert(graph:candidates(1, 0, 0, {
    max_horizontal = 5,
    max_vertical = 2,
    minimum_node_clearance = 0.7,
    max_results = 8,
}));
assert(#lower == 2 and lower[1].node_id == 0 and lower[2].node_id == 3,
    'candidate lookup did not filter clearance or sort by literal 3-D distance');
assert(math.abs(lower[1].horizontal - 1) < 0.0001
        and math.abs(lower[2].horizontal - 3) < 0.0001,
    'candidate distances were not preserved');

local tied = assert(graph:candidates(2, 0, 0, {
    max_horizontal = 5,
    max_vertical = 2,
    minimum_node_clearance = 0.7,
    max_results = 1,
}));
assert(#tied == 1 and tied[1].node_id == 0,
    'candidate max_results or node-ID tie break is nondeterministic');

local invalid, invalid_reason = graph:candidates(0, 0, 0, {
    max_horizontal = -1,
    max_vertical = 2,
    minimum_node_clearance = 0.7,
    max_results = 8,
});
assert(invalid == nil and tostring(invalid_reason):find('bounds', 1, true) ~= nil,
    'candidate lookup accepted invalid bounds');

print('AXWG v2 bounded candidate behavior ok');
