-- AXWG v1 LuaJIT loader and incremental A* behavior tests.
-- Run from the AccessXI repository root:
--   luajit tests/lua/test_walk_graph.lua

package.path = './tools/navbuild/lua/?.lua;' .. package.path;

local ffi = require('ffi');
local bit = require('bit');
local walk_graph = require('walk_graph');

ffi.cdef[[
typedef struct {
    char magic[4]; uint16_t version; uint16_t header_size;
    uint32_t endian_tag; uint32_t zone_id; uint32_t flags;
    uint32_t node_count; uint32_t edge_count;
    uint32_t nodes_offset; uint32_t edges_offset;
    uint32_t policy_offset; uint32_t grid_offset;
    uint32_t grid_bucket_count; uint32_t grid_entry_count;
    uint32_t payload_crc32; uint32_t file_size; uint32_t component_count;
} TestAxwgHeader;
typedef struct {
    float agent_radius; float agent_height; float support_sample_step;
    float support_smooth_window; float max_up_grade;
    float max_continuous_down_grade; float max_step_up; float max_step_down;
    float max_drop; float min_clearance; float max_edge_run;
    float grid_cell_size; uint32_t policy_flags; uint32_t source_obj_crc32;
    uint32_t builder_revision; uint32_t reserved;
} TestAxwgPolicy;
typedef struct {
    float x; float z; float y; uint32_t first_edge; uint32_t component_id;
    uint32_t source_ref; uint16_t edge_count; uint16_t flags; float clearance;
} TestAxwgNode;
typedef struct {
    uint32_t to; float cost; int16_t rise_cm; uint16_t run_cm;
    uint16_t min_clearance_cm; uint16_t flags;
} TestAxwgEdge;
typedef struct {
    float min_x; float min_z; float cell_size; uint32_t width; uint32_t height;
    uint32_t buckets_offset; uint32_t entries_offset; uint32_t reserved;
} TestAxwgGrid;
typedef struct { uint32_t first_entry; uint32_t entry_count; } TestAxwgBucket;
]];

local FLAGS = { DIRECTED = 1, Y_DOWN = 2, GRID = 4 };

local function crc32(data, offset, length)
    local crc = 0xFFFFFFFF;
    for i = offset, offset + length - 1 do
        crc = bit.bxor(crc, data[i]);
        for _ = 1, 8 do
            local mask = -bit.band(crc, 1);
            crc = bit.bxor(bit.rshift(crc, 1), bit.band(0xEDB88320, mask));
        end
    end
    return tonumber(ffi.cast('uint32_t', bit.bnot(crc)));
end

local crc_check = ffi.new('uint8_t[9]');
ffi.copy(crc_check, '123456789', 9);
assert(crc32(crc_check, 0, 9) == 0xCBF43926,
    'fixture writer is not using standard IEEE CRC32');

local function write_minimal_graph(path, mutate, corrupt_after_crc)
    local header_size, policy_size, node_size, edge_size = 64, 64, 32, 16;
    local grid_size, bucket_size = 32, 8;
    local policy_offset = header_size;
    local nodes_offset = policy_offset + policy_size;
    local edges_offset = nodes_offset + (2 * node_size);
    local grid_offset = edges_offset + edge_size;
    local buckets_offset = grid_offset + grid_size;
    local entries_offset = buckets_offset + bucket_size;
    local file_size = entries_offset + 8;

    local bytes = ffi.new('uint8_t[?]', file_size);
    local h = ffi.cast('TestAxwgHeader*', bytes);
    h.magic[0], h.magic[1], h.magic[2], h.magic[3] = 65, 88, 87, 71; -- AXWG
    h.version, h.header_size, h.endian_tag = 1, header_size, 0x01020304;
    h.zone_id = 102;
    h.flags = FLAGS.DIRECTED + FLAGS.Y_DOWN + FLAGS.GRID;
    h.node_count, h.edge_count, h.component_count = 2, 1, 1;
    h.nodes_offset, h.edges_offset = nodes_offset, edges_offset;
    h.policy_offset, h.grid_offset = policy_offset, grid_offset;
    h.grid_bucket_count, h.grid_entry_count = 1, 2;
    h.file_size = file_size;

    local policy = ffi.cast('TestAxwgPolicy*', bytes + policy_offset);
    policy.agent_radius, policy.agent_height = 0.7, 1.8;
    policy.support_sample_step, policy.support_smooth_window = 0.15, 0.5;
    policy.max_up_grade, policy.max_continuous_down_grade = 0.75, 2.5;
    policy.max_step_up, policy.max_step_down = 0.5, 0.5;
    policy.max_drop, policy.min_clearance = 0, 0.7;
    policy.max_edge_run, policy.grid_cell_size = 8, 8;
    policy.builder_revision = 1;

    local nodes = ffi.cast('TestAxwgNode*', bytes + nodes_offset);
    nodes[0].x, nodes[0].z, nodes[0].y = 0, 0, 0;
    nodes[0].first_edge, nodes[0].edge_count = 0, 1;
    nodes[0].component_id, nodes[0].source_ref, nodes[0].clearance = 0, 10, 1.0;
    nodes[1].x, nodes[1].z, nodes[1].y = 4, 0, 0;
    nodes[1].first_edge, nodes[1].edge_count = 1, 0;
    nodes[1].component_id, nodes[1].source_ref, nodes[1].clearance = 0, 11, 1.0;

    local edges = ffi.cast('TestAxwgEdge*', bytes + edges_offset);
    edges[0].to, edges[0].cost = 1, 4;
    edges[0].rise_cm, edges[0].run_cm = 0, 400;
    edges[0].min_clearance_cm, edges[0].flags = 100, 1;

    local grid = ffi.cast('TestAxwgGrid*', bytes + grid_offset);
    grid.min_x, grid.min_z, grid.cell_size = 0, 0, 8;
    grid.width, grid.height = 1, 1;
    grid.buckets_offset, grid.entries_offset = buckets_offset, entries_offset;
    local bucket = ffi.cast('TestAxwgBucket*', bytes + buckets_offset);
    bucket.first_entry, bucket.entry_count = 0, 2;
    local entries = ffi.cast('uint32_t*', bytes + entries_offset);
    entries[0], entries[1] = 0, 1;

    if (mutate ~= nil) then
        mutate(bytes, h, policy, nodes, edges, grid, bucket, entries);
    end
    h.payload_crc32 = crc32(bytes, header_size, file_size - header_size);
    if (corrupt_after_crc ~= nil) then corrupt_after_crc(bytes, h); end
    local f = assert(io.open(path, 'wb'));
    assert(f:write(ffi.string(bytes, file_size)));
    assert(f:close());
end

local temp = os.tmpname();
write_minimal_graph(temp);
local graph, err = walk_graph.load(temp, 102);
os.remove(temp);

assert(graph ~= nil, err);
assert(graph.zone_id == 102, 'zone id was not loaded');
assert(graph.node_count == 2 and graph.edge_count == 1, 'graph counts were not loaded');
assert(graph:is_capsule_verified() == false,
    'development graph incorrectly claimed capsule verification');

print('AXWG loader behavior ok');

local function expect_rejected(name, mutate, corrupt_after_crc, expected)
    local path = os.tmpname();
    write_minimal_graph(path, mutate, corrupt_after_crc);
    local loaded, reason = walk_graph.load(path, 102);
    os.remove(path);
    assert(loaded == nil, name .. ' was accepted');
    assert(tostring(reason):find(expected, 1, true) ~= nil,
        name .. ' returned wrong error: ' .. tostring(reason));
end

expect_rejected('payload corruption', nil, function(bytes)
    bytes[80] = bit.bxor(bytes[80], 0x01);
end, 'CRC');

expect_rejected('missing directed flag', function(_, h)
    h.flags = FLAGS.Y_DOWN + FLAGS.GRID;
end, nil, 'DIRECTED');

expect_rejected('drop-enabled v1 graph', function(_, h)
    h.flags = h.flags + 16;
end, nil, 'drops');

expect_rejected('out-of-bounds node section', function(_, h)
    h.nodes_offset = h.file_size - 16;
end, nil, 'node section');

expect_rejected('invalid CSR range', function(_, _, _, nodes)
    nodes[0].first_edge = 1;
    nodes[0].edge_count = 1;
end, nil, 'CSR');

expect_rejected('invalid edge destination', function(_, _, _, _, edges)
    edges[0].to = 2;
end, nil, 'destination');

expect_rejected('edge without walk flag', function(_, _, _, _, edges)
    edges[0].flags = 0;
end, nil, 'WALK');

expect_rejected('edge cost below geometric distance', function(_, _, _, _, edges)
    edges[0].cost = 1;
end, nil, 'cost');

expect_rejected('invalid component id', function(_, _, _, nodes)
    nodes[1].component_id = 1;
end, nil, 'component');

expect_rejected('invalid grid member', function(_, _, _, _, _, _, _, entries)
    entries[1] = 2;
end, nil, 'grid entry');

expect_rejected('edge run metadata mismatch', function(_, _, _, _, edges)
    edges[0].run_cm = 390;
end, nil, 'run metadata');

expect_rejected('edge rise metadata mismatch', function(_, _, _, _, edges)
    edges[0].rise_cm = 5;
end, nil, 'rise metadata');

expect_rejected('edge longer than policy maximum', function(_, _, policy)
    policy.max_edge_run = 3;
end, nil, 'maximum run');

expect_rejected('non-finite grade policy', function(_, _, policy)
    policy.max_up_grade = 0 / 0;
end, nil, 'policy');

expect_rejected('edge above declared up-grade limit', function(_, _, policy, nodes, edges)
    policy.max_up_grade = 0.75;
    nodes[1].y = -4;
    edges[0].cost = math.sqrt(32);
    edges[0].rise_cm = 400;
end, nil, 'up grade');

expect_rejected('edge above declared down-grade limit', function(_, _, policy, nodes, edges)
    policy.max_continuous_down_grade = 0.75;
    nodes[1].y = 4;
    edges[0].cost = math.sqrt(32);
    edges[0].rise_cm = -400;
end, nil, 'down grade');

print('AXWG hostile-file rejection ok');

local function write_custom_graph(path, node_specs, adjacency, component_count, options)
    options = options or {};
    local edge_count = 0;
    for i = 1, #node_specs do edge_count = edge_count + #(adjacency[i] or {}); end
    local min_x, min_z, max_x, max_z = math.huge, math.huge, -math.huge, -math.huge;
    for _, node in ipairs(node_specs) do
        min_x, min_z = math.min(min_x, node.x), math.min(min_z, node.z);
        max_x, max_z = math.max(max_x, node.x), math.max(max_z, node.z);
    end
    local cell_size = 8;
    min_x, min_z = math.floor(min_x / cell_size) * cell_size,
        math.floor(min_z / cell_size) * cell_size;
    local width = math.floor((max_x - min_x) / cell_size) + 1;
    local height = math.floor((max_z - min_z) / cell_size) + 1;
    local bucket_count = width * height;
    local lists = {};
    for i = 1, bucket_count do lists[i] = {}; end
    for id, node in ipairs(node_specs) do
        local cx = math.floor((node.x - min_x) / cell_size);
        local cz = math.floor((node.z - min_z) / cell_size);
        lists[(cz * width) + cx + 1][#lists[(cz * width) + cx + 1] + 1] = id - 1;
    end

    local policy_offset = 64;
    local nodes_offset = policy_offset + 64;
    local edges_offset = nodes_offset + (#node_specs * 32);
    local grid_offset = edges_offset + (edge_count * 16);
    local buckets_offset = grid_offset + 32;
    local entries_offset = buckets_offset + (bucket_count * 8);
    local file_size = entries_offset + (#node_specs * 4);
    local bytes = ffi.new('uint8_t[?]', file_size);
    local h = ffi.cast('TestAxwgHeader*', bytes);
    h.magic[0], h.magic[1], h.magic[2], h.magic[3] = 65, 88, 87, 71;
    h.version, h.header_size, h.endian_tag = 1, 64, 0x01020304;
    h.zone_id, h.flags = 102, FLAGS.DIRECTED + FLAGS.Y_DOWN + FLAGS.GRID;
    h.node_count, h.edge_count = #node_specs, edge_count;
    h.nodes_offset, h.edges_offset = nodes_offset, edges_offset;
    h.policy_offset, h.grid_offset = policy_offset, grid_offset;
    h.grid_bucket_count, h.grid_entry_count = bucket_count, #node_specs;
    h.file_size, h.component_count = file_size, component_count;

    local policy = ffi.cast('TestAxwgPolicy*', bytes + policy_offset);
    policy.agent_radius, policy.agent_height = 0.7, 1.8;
    policy.support_sample_step, policy.support_smooth_window = 0.15, 0.5;
    policy.max_up_grade = options.max_up_grade or 0.75;
    policy.max_continuous_down_grade = options.max_down_grade or 2.5;
    policy.max_step_up, policy.max_step_down = 0.5, 0.5;
    policy.max_drop, policy.min_clearance = 0, options.min_clearance or 0.7;
    policy.max_edge_run, policy.grid_cell_size = 32, cell_size;
    policy.builder_revision = 1;

    local nodes = ffi.cast('TestAxwgNode*', bytes + nodes_offset);
    local edges = ffi.cast('TestAxwgEdge*', bytes + edges_offset);
    local edge_cursor = 0;
    for id, spec in ipairs(node_specs) do
        local node = nodes[id - 1];
        node.x, node.z, node.y = spec.x, spec.z, spec.y;
        node.first_edge = edge_cursor;
        node.edge_count = #(adjacency[id] or {});
        node.component_id = spec.component or 0;
        node.source_ref, node.clearance = id - 1, spec.clearance or 1;
        for _, edge_spec in ipairs(adjacency[id] or {}) do
            local to = edge_spec.to;
            local target = node_specs[to + 1];
            local dx, dz = target.x - spec.x, target.z - spec.z;
            local edge = edges[edge_cursor];
            edge.to = to;
            edge.cost = edge_spec.cost;
            edge.rise_cm = math.floor((-(target.y - spec.y) * 100) + 0.5);
            edge.run_cm = math.floor((math.sqrt(dx * dx + dz * dz) * 100) + 0.5);
            edge.min_clearance_cm = edge_spec.min_clearance_cm or 100;
            edge.flags = 1;
            edge_cursor = edge_cursor + 1;
        end
    end

    local grid = ffi.cast('TestAxwgGrid*', bytes + grid_offset);
    grid.min_x, grid.min_z, grid.cell_size = min_x, min_z, cell_size;
    grid.width, grid.height = width, height;
    grid.buckets_offset, grid.entries_offset = buckets_offset, entries_offset;
    local buckets = ffi.cast('TestAxwgBucket*', bytes + buckets_offset);
    local entries = ffi.cast('uint32_t*', bytes + entries_offset);
    local entry_cursor = 0;
    for bucket_index, ids in ipairs(lists) do
        buckets[bucket_index - 1].first_entry = entry_cursor;
        buckets[bucket_index - 1].entry_count = #ids;
        for _, id in ipairs(ids) do
            entries[entry_cursor] = id;
            entry_cursor = entry_cursor + 1;
        end
    end
    h.payload_crc32 = crc32(bytes, 64, file_size - 64);
    local file = assert(io.open(path, 'wb'));
    assert(file:write(ffi.string(bytes, file_size)));
    assert(file:close());
end

local layered_path = os.tmpname();
write_custom_graph(layered_path, {
    { x = 1, z = 1, y = 0, clearance = 1 },
    { x = 1, z = 1, y = 10, clearance = 1 },
    { x = 2, z = 1, y = 0, clearance = 0.2 },
}, { {}, {}, {} }, 1);
local layered = assert(walk_graph.load(layered_path, 102));
os.remove(layered_path);
assert(layered:nearest(1, 1, 9.5, 3, 2, 0.7) == 1,
    'nearest-node lookup merged two vertical layers');
assert(layered:nearest(2, 1, 0, 3, 2, 0.7) == 0,
    'nearest-node lookup selected a node below required clearance');

local route_path = os.tmpname();
write_custom_graph(route_path, {
    { x = 0, z = 0, y = 0, component = 0 },
    { x = 1, z = 0, y = 0, component = 0 },
    { x = 0, z = 2, y = 0, component = 0 },
    { x = 2, z = 2, y = 0, component = 0 },
    { x = 4, z = 0, y = 0, component = 1 },
}, {
    { { to = 1, cost = 1 }, { to = 2, cost = 2 } },
    { { to = 3, cost = 10 } },
    { { to = 3, cost = 2 } },
    {},
    {},
}, 2);
local route_graph = assert(walk_graph.load(route_path, 102));
os.remove(route_path);

local route_point = assert(route_graph:point(2));
assert(route_point.node_id == 2 and route_point.x == 0 and route_point.z == 2
        and route_point.y == 0 and route_point.component_id == 0,
    'point lookup did not preserve x,z,y order and node metadata');
assert(route_graph:point(5) == nil, 'point lookup accepted an invalid node ID');

local search = assert(route_graph:begin_astar(0, 3));
local status, path = search:step(1);
assert(status == 'pending' and path == nil,
    'one-expansion A* slice did not yield pending');
for _ = 1, 10 do
    status, path = search:step(1);
    if (status ~= 'pending') then break; end
end
assert(status == 'ready', 'incremental A* did not find the route');
assert(#path == 3 and path[1] == 0 and path[2] == 2 and path[3] == 3,
    'A* did not choose the lowest-cost directed path');

local reverse = assert(route_graph:begin_astar(3, 0));
status = reverse:step(20);
assert(status == 'no-path', 'directed A* invented reverse edges');

local disconnected = assert(route_graph:begin_astar(0, 4));
status, path = disconnected:step(1);
assert(status == 'no-path' and disconnected.expansions == 0,
    'component mismatch did not reject the route before expansion');

local clearance_path = os.tmpname();
write_custom_graph(clearance_path, {
    { x = 0, z = 0, y = 0, component = 0 },
    { x = 1, z = 0, y = 0, component = 0 },
    { x = 0, z = 2, y = 0, component = 0 },
    { x = 2, z = 2, y = 0, component = 0 },
}, {
    {
        { to = 1, cost = 1, min_clearance_cm = 60 },
        { to = 2, cost = 2, min_clearance_cm = 100 },
    },
    { { to = 3, cost = 2.25, min_clearance_cm = 60 } },
    { { to = 3, cost = 2, min_clearance_cm = 100 } },
    {},
}, 1, { min_clearance = 0.7 });
local clearance_graph = assert(walk_graph.load(clearance_path, 102));
os.remove(clearance_path);
local clearance_search = assert(clearance_graph:begin_astar(0, 3));
for _ = 1, 10 do
    status, path = clearance_search:step(1);
    if (status ~= 'pending') then break; end
end
assert(status == 'ready' and #path == 3 and path[2] == 2,
    'A* chose a cheaper edge below the declared minimum clearance');

local blocked_clearance_path = os.tmpname();
write_custom_graph(blocked_clearance_path, {
    { x = 0, z = 0, y = 0, component = 0 },
    { x = 1, z = 0, y = 0, component = 0 },
}, {
    { { to = 1, cost = 1, min_clearance_cm = 60 } },
    {},
}, 1, { min_clearance = 0.7 });
local blocked_clearance_graph = assert(walk_graph.load(blocked_clearance_path, 102));
os.remove(blocked_clearance_path);
local blocked_clearance_search = assert(blocked_clearance_graph:begin_astar(0, 1));
status, path = blocked_clearance_search:step(10);
assert(status == 'no-path' and path == nil,
    'A* traversed an edge below the declared minimum clearance');

local current_axwg = os.getenv('AXWG_CURRENT_FILE');
if (current_axwg ~= nil and current_axwg ~= '') then
    local current_graph, current_error = walk_graph.load(current_axwg, 102);
    assert(current_graph == nil,
        'current AXWG with edges over its declared down-grade limit was accepted');
    assert(tostring(current_error):find('down grade', 1, true) ~= nil,
        'current AXWG failed for the wrong reason: ' .. tostring(current_error));
    print('current AXWG declared-grade enforcement ok');
end

local rebuilt_axwg = os.getenv('AXWG_REBUILT_FILE');
if (rebuilt_axwg ~= nil and rebuilt_axwg ~= '') then
    local rebuilt_graph = assert(walk_graph.load(rebuilt_axwg, 102));
    assert(rebuilt_graph.minimum_clearance_cm == 70,
        'rebuilt AXWG did not preserve the 0.70-yalm clearance policy');

    local function assert_rebuilt_route(name, start, goal)
        local start_id = assert(rebuilt_graph:nearest(
            start[1], start[2], start[3], 6, 4.5, 0.7));
        local goal_id = assert(rebuilt_graph:nearest(
            goal[1], goal[2], goal[3], 6, 4.5, 0.7));
        local rebuilt_search = assert(rebuilt_graph:begin_astar(start_id, goal_id));
        local rebuilt_status, rebuilt_path;
        repeat
            rebuilt_status, rebuilt_path = rebuilt_search:step(512);
        until rebuilt_status ~= 'pending';
        assert(rebuilt_status == 'ready', name .. ' is unreachable at 0.70 clearance');
        for i = 1, #rebuilt_path - 1 do
            local from, to = rebuilt_path[i], rebuilt_path[i + 1];
            local node = rebuilt_graph._nodes[from];
            local found_clearance;
            for edge_index = tonumber(node.first_edge),
                    tonumber(node.first_edge) + tonumber(node.edge_count) - 1 do
                local edge = rebuilt_graph._edges[edge_index];
                if (tonumber(edge.to) == to) then
                    found_clearance = tonumber(edge.min_clearance_cm);
                    break;
                end
            end
            assert(found_clearance ~= nil and found_clearance >= 70,
                name .. ' traversed an edge below 0.70 clearance');
        end
        print(('%s rebuilt route ready nodes=%d expansions=%d'):format(
            name, #rebuilt_path, rebuilt_search.expansions));
    end

    assert_rebuilt_route('r1', { 25.0, 25.6, 16.5 }, { 17.7, 16.7, 9.3 });
    assert_rebuilt_route('r2_wall', { 24.4, 20.2, 16.0 }, { 17.2, 20.7, 10.1 });
    print('rebuilt AXWG loader and clearance-filtered A* acceptance ok');
end

print('AXWG layered nearest-node and incremental directed A* behavior ok');

local benchmark_count = tonumber(os.getenv('AXWG_BENCH_NODES')) or 25000;
local benchmark_nodes, benchmark_edges = {}, {};
for i = 1, benchmark_count do
    benchmark_nodes[i] = { x = i - 1, z = 0, y = 0, component = 0 };
    benchmark_edges[i] = i < benchmark_count and { { to = i, cost = 1 } } or {};
end
local benchmark_path = os.tmpname();
local build_started = os.clock();
write_custom_graph(benchmark_path, benchmark_nodes, benchmark_edges, 1);
local build_ms = (os.clock() - build_started) * 1000;
local load_started = os.clock();
local benchmark_graph = assert(walk_graph.load(benchmark_path, 102));
local load_ms = (os.clock() - load_started) * 1000;
os.remove(benchmark_path);

local benchmark_search = assert(benchmark_graph:begin_astar(0, benchmark_count - 1));
local max_slice_ms, search_started = 0, os.clock();
while true do
    local slice_started = os.clock();
    local benchmark_status, benchmark_result = benchmark_search:step(512);
    max_slice_ms = math.max(max_slice_ms, (os.clock() - slice_started) * 1000);
    if (benchmark_status == 'ready') then
        assert(#benchmark_result == benchmark_count,
            'benchmark route reconstruction lost nodes');
        break;
    end
    assert(benchmark_status == 'pending', 'benchmark search unexpectedly failed');
end
local search_ms = (os.clock() - search_started) * 1000;
print(('AXWG benchmark nodes=%d build=%.1fms load=%.1fms search=%.1fms max512=%.3fms'):format(
    benchmark_count, build_ms, load_ms, search_ms, max_slice_ms));
