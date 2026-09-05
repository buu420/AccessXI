-- AXWG v2 strict loader behavior.
-- Run from the AccessXI repository root under LuaJIT.

package.path = './tests/lua/?.lua;./tools/navbuild/lua/?.lua;' .. package.path;

local fixture = require('axwg_v2_fixture');
local walk_graph = require('walk_graph');
local bit = require('bit');

local path = os.tmpname();
fixture.write(path);
local graph, load_error = walk_graph.load(path, 102);
os.remove(path);

assert(graph ~= nil, load_error);
assert(graph.version == 2, 'v2 loader did not expose its format version');
assert(graph.node_count == 2 and graph.edge_count == 2 and graph.portal_count == 1,
    'v2 loader did not preserve graph counts');
assert(graph.minimum_safe_span_cm == 5,
    'v2 loader double-spent radius instead of using the serialized safe-span floor');
assert(math.abs(graph.agent_radius - 0.7) < 0.0001
        and math.abs(graph.agent_height - 1.8) < 0.0001
        and graph.source_obj_crc32 == 0x30BA83D1
        and graph.builder_revision == 3
        and graph.weld_tolerance_mm == 20,
    'v2 loader did not expose its enforced safety provenance');
assert(graph:is_headroom_checked() == false,
    'revision-3 graph falsely claimed headroom verification');
assert(graph:is_capsule_verified() == false,
    'revision-3 graph falsely claimed full-capsule verification');

local forward = assert(graph:portal(0, 0));
assert(forward.left.x == 2 and forward.left.z == 1
        and forward.right.x == 2 and forward.right.z == -1,
    'canonical A-to-B portal orientation was not preserved');
assert(forward.left.y_from == 0 and forward.left.y_to == 0,
    'forward portal owner heights were not preserved');

local reverse = assert(graph:portal(0, 1));
assert(reverse.left.x == 2 and reverse.left.z == -1
        and reverse.right.x == 2 and reverse.right.z == 1,
    'reverse traversal did not swap portal left and right');
assert(reverse.node_from == 1 and reverse.node_to == 0,
    'reverse traversal did not swap portal ownership');

print('AXWG v2 loader and oriented portal behavior ok');

local function expect_rejected(name, mutate, expected)
    local rejected_path = os.tmpname();
    fixture.write(rejected_path, nil, mutate);
    local loaded, reason = walk_graph.load(rejected_path, 102);
    os.remove(rejected_path);
    assert(loaded == nil, name .. ' was accepted');
    assert(tostring(reason):find(expected, 1, true) ~= nil,
        name .. ' returned wrong reason: ' .. tostring(reason));
end

expect_rejected('wrong EdgeV2 record size', function(context)
    context.header.edge_record_size = 16;
end, 'edge record size');

expect_rejected('missing safe-portal header semantics', function(context)
    context.header.flags = 0x27;
end, 'SAFE_PORTAL_INTERVALS');

expect_rejected('unknown header semantics', function(context)
    context.header.flags = 0xE7;
end, 'unknown');

expect_rejected('unsupported builder revision', function(context)
    context.policy.builder_revision = 2;
end, 'builder revision');

expect_rejected('unknown policy semantics', function(context)
    context.policy.policy_flags = 3;
end, 'policy flags');

expect_rejected('nonzero v2 header reserved field', function(context)
    context.header.reserved = 1;
end, 'header reserved');

expect_rejected('nonzero v2 grid reserved field', function(context)
    context.grid.reserved = 1;
end, 'grid reserved');

expect_rejected('false headroom certification', function(context)
    context.portals[0].flags = 7;
end, 'HEADROOM_CHECKED');

expect_rejected('false full-capsule certification', function(context)
    context.portals[0].flags = 11;
end, 'FULL_CAPSULE_CHECKED');

print('AXWG v2 metadata and certification rejection ok');

expect_rejected('portal missing wall erosion certificate', function(context)
    context.portals[0].flags = 1;
end, 'WALL_ERODED');

expect_rejected('portal with unknown flags', function(context)
    context.portals[0].flags = 0x13;
end, 'unknown portal flags');

expect_rejected('portal with nonzero reserved field', function(context)
    context.portals[0].reserved = 1;
end, 'portal 0 reserved');

expect_rejected('edge missing WALK flag', function(context)
    context.edges[0].flags = 0;
end, 'WALK');

expect_rejected('edge with unknown flags', function(context)
    context.edges[0].flags = 5;
end, 'unknown edge flags');

expect_rejected('edge with nonzero reserved field', function(context)
    context.edges[0].reserved = 1;
end, 'edge 0 reserved');

print('AXWG v2 record flag and reserved-field rejection ok');

local function expect_spec_rejected(name, spec, expected)
    local rejected_path = os.tmpname();
    fixture.write(rejected_path, spec);
    local loaded, reason = walk_graph.load(rejected_path, 102);
    os.remove(rejected_path);
    assert(loaded == nil, name .. ' was accepted');
    assert(tostring(reason):find(expected, 1, true) ~= nil,
        name .. ' returned wrong reason: ' .. tostring(reason));
end

expect_rejected('noncanonical portal owner order', function(context)
    context.portals[0].node_a, context.portals[0].node_b = 1, 0;
end, 'node_a < node_b');

expect_rejected('nonfinite portal endpoint', function(context)
    context.portals[0].left_x = 0 / 0;
end, 'non-finite');

expect_rejected('collapsed portal interval', function(context)
    context.portals[0].right_x = context.portals[0].left_x;
    context.portals[0].right_z = context.portals[0].left_z;
end, 'collapsed');

expect_rejected('reversed canonical portal orientation', function(context)
    local portal = context.portals[0];
    portal.left_z, portal.right_z = portal.right_z, portal.left_z;
end, 'orientation');

expect_rejected('portal below serialized safe-span floor', function(context)
    context.portals[0].capacity_cm = 4;
end, 'safe-span floor');

expect_rejected('portal capacity exceeding its interval', function(context)
    context.portals[0].capacity_cm = 300;
end, 'capacity exceeds');

expect_rejected('one-centimeter portal capacity overclaim', function(context)
    context.portals[0].capacity_cm = 201;
end, 'capacity exceeds');

expect_rejected('nonfinite portal owner height', function(context)
    context.portals[0].left_y_a = 0 / 0;
end, 'owner height');

expect_rejected('portal owner step above policy', function(context)
    context.portals[0].left_y_b = -1;
end, 'owner step');

local wrong_binding = fixture.default_spec();
wrong_binding.nodes[3] = { x = 0, z = 4, y = 0, component = 0, clearance = 2 };
wrong_binding.adjacency[3] = {};
wrong_binding.portals[1].node_b = 2;
wrong_binding.portals[1].left_x, wrong_binding.portals[1].left_z = -1, 2;
wrong_binding.portals[1].right_x, wrong_binding.portals[1].right_z = 1, 2;
expect_spec_rejected('edge bound to the wrong portal owners', wrong_binding, 'does not bind');

local unreferenced = fixture.default_spec();
unreferenced.portals[2] = {
    node_a = 0, node_b = 1,
    left_x = 1.5, left_z = 0.75,
    right_x = 1.5, right_z = -0.75,
    left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
    capacity_cm = 150, flags = 3,
};
expect_spec_rejected('serialized but unreferenced portal component', unreferenced, 'unreferenced');

local reverse_mismatch = fixture.default_spec();
reverse_mismatch.portals[2] = {
    node_a = 0, node_b = 1,
    left_x = 1.5, left_z = 0.75,
    right_x = 1.5, right_z = -0.75,
    left_y_a = 0, left_y_b = 0, right_y_a = 0, right_y_b = 0,
    capacity_cm = 150, flags = 3,
};
reverse_mismatch.adjacency[2][1].portal_id = 1;
expect_spec_rejected('reverse edges naming different portal sets', reverse_mismatch,
    'reverse portal');

local duplicate_edge = fixture.default_spec();
duplicate_edge.adjacency[1][2] = { to = 1, portal_id = 0 };
expect_spec_rejected('duplicate from-to-portal edge', duplicate_edge, 'duplicate');

local one_way = fixture.default_spec();
one_way.adjacency[2] = {};
local one_way_path = os.tmpname();
fixture.write(one_way_path, one_way);
local one_way_graph, one_way_error = walk_graph.load(one_way_path, 102);
os.remove(one_way_path);
assert(one_way_graph ~= nil, one_way_error);
assert(one_way_graph.edge_count == 1,
    'valid one-way certified doorway was rejected');

print('AXWG v2 portal geometry and binding rejection ok');

expect_rejected('nonfinite safe-span policy', function(context)
    context.policy.min_safe_span = 0 / 0;
end, 'policy');

expect_rejected('drop-enabled revision-3 policy', function(context)
    context.policy.max_drop = 1;
end, 'drops');

expect_rejected('missing weld provenance', function(context)
    context.policy.weld_tolerance_mm = 0;
end, 'weld tolerance');

expect_rejected('node with nonfinite geometry', function(context)
    context.nodes[0].x = 0 / 0;
end, 'node 0');

expect_rejected('node with unknown flags', function(context)
    context.nodes[0].flags = 1;
end, 'node 0 flags');

expect_rejected('node with invalid component', function(context)
    context.nodes[1].component_id = 1;
end, 'component');

expect_rejected('invalid node CSR range', function(context)
    context.nodes[1].first_edge = 0;
end, 'CSR');

expect_rejected('grid missing a node', function(context)
    context.header.grid_entry_count = 1;
end, 'every node');

expect_rejected('duplicate grid membership', function(context)
    context.entries[1] = 0;
end, 'duplicates node');

expect_rejected('overlapping edge and portal sections', function(context)
    context.header.portals_offset = context.header.edges_offset;
end, 'sections overlap');

print('AXWG v2 policy, node, section, and grid rejection ok');

expect_rejected('edge with invalid destination', function(context)
    context.edges[0].to = 2;
end, 'destination');

expect_rejected('edge with invalid portal id', function(context)
    context.edges[0].portal_id = 1;
end, 'portal ID');

expect_rejected('edge crossing component ids', function(context)
    context.header.component_count = 2;
    context.nodes[1].component_id = 1;
end, 'crosses component');

expect_rejected('edge with nonfinite cost', function(context)
    context.edges[0].cost = 0 / 0;
end, 'cost');

expect_rejected('edge cost below centroid distance', function(context)
    context.edges[0].cost = 1;
end, 'cost');

expect_rejected('edge run metadata mismatch', function(context)
    context.edges[0].run_cm = 390;
end, 'run metadata');

expect_rejected('edge rise metadata mismatch', function(context)
    context.edges[0].rise_cm = 5;
end, 'rise metadata');

expect_rejected('STEP_DOWN flag mismatch', function(context)
    context.edges[0].flags = 3;
end, 'STEP_DOWN');

expect_rejected('edge above declared climb grade', function(context)
    context.nodes[1].y = -3;
    context.edges[0].cost = 5;
    context.edges[0].rise_cm = 300;
end, 'up grade');

expect_rejected('edge above declared descent grade', function(context)
    context.nodes[1].y = 5;
    context.edges[0].cost = math.sqrt(41);
    context.edges[0].rise_cm = -500;
    context.edges[0].flags = 3;
end, 'down grade');

expect_rejected('edge longer than declared run policy', function(context)
    context.policy.max_edge_run = 3;
end, 'maximum run');

print('AXWG v2 directed edge geometry and policy rejection ok');

expect_rejected('wrong PortalV2 record size', function(context)
    context.header.portal_record_size = 44;
end, 'portal record size');

expect_rejected('wrong endian tag', function(context)
    context.header.endian_tag = 0x04030201;
end, 'endian');

expect_rejected('wrong zone id', function(context)
    context.header.zone_id = 100;
end, 'zone mismatch');

expect_rejected('wrong file size field', function(context)
    context.header.file_size = context.header.file_size - 1;
end, 'file-size');

local crc_path = os.tmpname();
fixture.write(crc_path, nil, nil, function(context)
    context.bytes[100] = bit.bxor(context.bytes[100], 1);
end);
local crc_graph, crc_error = walk_graph.load(crc_path, 102);
os.remove(crc_path);
assert(crc_graph == nil and tostring(crc_error):find('CRC', 1, true) ~= nil,
    'v2 payload corruption was not rejected by CRC');

expect_rejected('invalid agent radius policy', function(context)
    context.policy.agent_radius = 0;
end, 'policy');

expect_rejected('undersized certified agent radius', function(context)
    context.policy.agent_radius = 0.69;
end, 'agent radius');

expect_rejected('undersized certified agent height', function(context)
    context.policy.agent_height = 1.79;
end, 'agent height');

expect_rejected('nonfinite climb-grade policy', function(context)
    context.policy.max_up_grade = 0 / 0;
end, 'policy');

expect_rejected('negative descent-grade policy', function(context)
    context.policy.max_continuous_down_grade = -1;
end, 'policy');

expect_rejected('overpermissive climb-grade policy', function(context)
    context.policy.max_up_grade = 0.7;
end, 'climb grade');

expect_rejected('overpermissive descent-grade policy', function(context)
    context.policy.max_continuous_down_grade = 1.1;
end, 'descent grade');

expect_rejected('negative step policy', function(context)
    context.policy.max_step_up = -1;
end, 'policy');

expect_rejected('overpermissive step-up policy', function(context)
    context.policy.max_step_up = 0.6;
end, 'step-up');

expect_rejected('overpermissive step-down policy', function(context)
    context.policy.max_step_down = 0.6;
end, 'step-down');

expect_rejected('undersized residual safe span', function(context)
    context.policy.min_safe_span = 0.04;
end, 'safe-span');

expect_rejected('unreviewed weld tolerance', function(context)
    context.policy.weld_tolerance_mm = 21;
end, 'weld tolerance');

expect_rejected('missing source OBJ provenance', function(context)
    context.policy.source_obj_crc32 = 0;
end, 'source OBJ CRC');

expect_rejected('policy/grid cell-size disagreement', function(context)
    context.policy.grid_cell_size = 4;
end, 'cell sizes disagree');

expect_rejected('invalid grid bucket CSR', function(context)
    context.buckets[0].first_entry = 1;
end, 'grid bucket');

local wrong_bucket = fixture.default_spec();
wrong_bucket.nodes[2].x = 12;
wrong_bucket.portals[1].left_x, wrong_bucket.portals[1].right_x = 6, 6;
wrong_bucket.adjacency[1][1].cost = 12;
wrong_bucket.adjacency[1][1].run_cm = 1200;
wrong_bucket.adjacency[2][1].cost = 12;
wrong_bucket.adjacency[2][1].run_cm = 1200;
wrong_bucket.max_edge_run = 16;
local wrong_bucket_path = os.tmpname();
fixture.write(wrong_bucket_path, wrong_bucket, function(context)
    context.entries[0], context.entries[1] = context.entries[1], context.entries[0];
end);
local wrong_bucket_graph, wrong_bucket_error = walk_graph.load(wrong_bucket_path, 102);
os.remove(wrong_bucket_path);
assert(wrong_bucket_graph == nil
        and tostring(wrong_bucket_error):find('wrong bucket', 1, true) ~= nil,
    'node stored in the wrong spatial bucket was accepted: '
        .. tostring(wrong_bucket_error));

print('AXWG v2 ABI, CRC, policy, and grid hardening ok');

local expected_crc_path = os.tmpname();
fixture.write(expected_crc_path);
local expected_crc_graph, expected_crc_error = walk_graph.load(
    expected_crc_path, 102, 0x12345678);
os.remove(expected_crc_path);
assert(expected_crc_graph == nil
        and tostring(expected_crc_error):find('source OBJ CRC', 1, true),
    'caller-pinned source OBJ CRC mismatch was accepted');

local malformed_crc_path = os.tmpname();
fixture.write(malformed_crc_path);
local malformed_crc_graph, malformed_crc_error = walk_graph.load(
    malformed_crc_path, 102, 'not-a-crc');
os.remove(malformed_crc_path);
assert(malformed_crc_graph == nil
        and tostring(malformed_crc_error):find('expected source OBJ CRC', 1, true),
    'malformed caller source-CRC pin crashed or was accepted');

local supplied_artifact = os.getenv('AXWG_V2_FILE');
if (supplied_artifact ~= nil and supplied_artifact ~= '') then
    local supplied_graph, supplied_error = walk_graph.load(
        supplied_artifact, 102, 0x30BA83D1);
    assert(supplied_graph ~= nil,
        'corrected supplied AXWG v2 artifact failed strict loading: '
            .. tostring(supplied_error));
    assert(supplied_graph.node_count == 228470
            and supplied_graph.edge_count == 523139
            and supplied_graph.portal_count == 262231,
        'corrected supplied artifact counts differ from the reviewed build');
    assert(not supplied_graph:is_headroom_checked()
            and not supplied_graph:is_capsule_verified(),
        'corrected supplied artifact still overclaims headroom or capsule verification');
    print('supplied corrected AXWG v2 artifact accepted without normalization');
end
