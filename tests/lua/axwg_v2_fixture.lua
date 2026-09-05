local ffi = require('ffi');
local bit = require('bit');

ffi.cdef[[
typedef struct {
    char magic[4]; uint16_t version; uint16_t header_size;
    uint32_t endian_tag; uint32_t zone_id; uint32_t flags;
    uint32_t node_count; uint32_t edge_count;
    uint32_t nodes_offset; uint32_t edges_offset;
    uint32_t policy_offset; uint32_t grid_offset;
    uint32_t grid_bucket_count; uint32_t grid_entry_count;
    uint32_t payload_crc32; uint32_t file_size; uint32_t component_count;
    uint32_t portal_count; uint32_t portals_offset;
    uint16_t edge_record_size; uint16_t portal_record_size;
    uint32_t reserved;
} TestAxwgHeaderV2;
typedef struct {
    float agent_radius; float agent_height; float support_sample_step;
    float support_smooth_window; float max_up_grade;
    float max_continuous_down_grade; float max_step_up; float max_step_down;
    float max_drop; float min_safe_span; float max_edge_run;
    float grid_cell_size; uint32_t policy_flags; uint32_t source_obj_crc32;
    uint32_t builder_revision; uint32_t weld_tolerance_mm;
} TestAxwgPolicyV2;
typedef struct {
    float x; float z; float y; uint32_t first_edge; uint32_t component_id;
    uint32_t source_ref; uint16_t edge_count; uint16_t flags; float clearance;
} TestAxwgNodeV2;
typedef struct {
    uint32_t to; float cost; int16_t rise_cm; uint16_t run_cm;
    uint16_t flags; uint16_t reserved; uint32_t portal_id;
} TestAxwgEdgeV2;
typedef struct {
    uint32_t node_a; uint32_t node_b;
    float left_x; float left_z; float right_x; float right_z;
    float left_y_a; float left_y_b; float right_y_a; float right_y_b;
    uint16_t capacity_cm; uint16_t flags; uint32_t reserved;
} TestAxwgPortalV2;
typedef struct {
    float min_x; float min_z; float cell_size; uint32_t width; uint32_t height;
    uint32_t buckets_offset; uint32_t entries_offset; uint32_t reserved;
} TestAxwgGridV2;
typedef struct { uint32_t first_entry; uint32_t entry_count; } TestAxwgBucketV2;
]];

assert(ffi.sizeof('TestAxwgHeaderV2') == 80);
assert(ffi.sizeof('TestAxwgPolicyV2') == 64);
assert(ffi.sizeof('TestAxwgNodeV2') == 32);
assert(ffi.sizeof('TestAxwgEdgeV2') == 20);
assert(ffi.sizeof('TestAxwgPortalV2') == 48);
assert(ffi.sizeof('TestAxwgGridV2') == 32);
assert(ffi.sizeof('TestAxwgBucketV2') == 8);

local M = {};

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

local function quantize(value)
    if (value >= 0) then return math.floor(value * 100 + 0.5); end
    return math.ceil(value * 100 - 0.5);
end

local function default_spec()
    return {
        zone_id = 102,
        component_count = 1,
        nodes = {
            { x = 0, z = 0, y = 0, component = 0, clearance = 2 },
            { x = 4, z = 0, y = 0, component = 0, clearance = 2 },
        },
        portals = {
            {
                node_a = 0, node_b = 1,
                left_x = 2, left_z = 1,
                right_x = 2, right_z = -1,
                left_y_a = 0, left_y_b = 0,
                right_y_a = 0, right_y_b = 0,
                capacity_cm = 200, flags = 3,
            },
        },
        adjacency = {
            { { to = 1, portal_id = 0 } },
            { { to = 0, portal_id = 0 } },
        },
    };
end

function M.default_spec()
    return default_spec();
end

function M.write(path, spec, mutate, corrupt_after_crc)
    spec = spec or default_spec();
    local nodes_spec = assert(spec.nodes);
    local adjacency = assert(spec.adjacency);
    local portals_spec = assert(spec.portals);
    local edge_count = 0;
    for i = 1, #nodes_spec do edge_count = edge_count + #(adjacency[i] or {}); end

    local cell_size = spec.grid_cell_size or 8;
    local min_x, min_z, max_x, max_z = math.huge, math.huge, -math.huge, -math.huge;
    for _, node in ipairs(nodes_spec) do
        min_x, min_z = math.min(min_x, node.x), math.min(min_z, node.z);
        max_x, max_z = math.max(max_x, node.x), math.max(max_z, node.z);
    end
    min_x = math.floor(min_x / cell_size) * cell_size;
    min_z = math.floor(min_z / cell_size) * cell_size;
    local width = math.floor((max_x - min_x) / cell_size) + 1;
    local height = math.floor((max_z - min_z) / cell_size) + 1;
    local bucket_count = width * height;
    local bucket_lists = {};
    for i = 1, bucket_count do bucket_lists[i] = {}; end
    for node_index, node in ipairs(nodes_spec) do
        local cell_x = math.floor((node.x - min_x) / cell_size);
        local cell_z = math.floor((node.z - min_z) / cell_size);
        local bucket = bucket_lists[(cell_z * width) + cell_x + 1];
        bucket[#bucket + 1] = node_index - 1;
    end

    local header_size, policy_size, grid_size = 80, 64, 32;
    local nodes_offset = header_size + policy_size + grid_size;
    local edges_offset = nodes_offset + (#nodes_spec * 32);
    local portals_offset = edges_offset + (edge_count * 20);
    local buckets_offset = portals_offset + (#portals_spec * 48);
    local entries_offset = buckets_offset + (bucket_count * 8);
    local file_size = entries_offset + (#nodes_spec * 4);
    local bytes = ffi.new('uint8_t[?]', file_size);

    local header = ffi.cast('TestAxwgHeaderV2*', bytes);
    header.magic[0], header.magic[1], header.magic[2], header.magic[3] = 65, 88, 87, 71;
    header.version, header.header_size = 2, header_size;
    header.endian_tag, header.zone_id = 0x01020304, spec.zone_id or 102;
    header.flags = spec.flags or 0x67;
    header.node_count, header.edge_count = #nodes_spec, edge_count;
    header.nodes_offset, header.edges_offset = nodes_offset, edges_offset;
    header.policy_offset, header.grid_offset = header_size, header_size + policy_size;
    header.grid_bucket_count, header.grid_entry_count = bucket_count, #nodes_spec;
    header.file_size = file_size;
    header.component_count = spec.component_count or 1;
    header.portal_count, header.portals_offset = #portals_spec, portals_offset;
    header.edge_record_size, header.portal_record_size = 20, 48;

    local policy = ffi.cast('TestAxwgPolicyV2*', bytes + header_size);
    policy.agent_radius, policy.agent_height = 0.7, 1.8;
    policy.support_sample_step, policy.support_smooth_window = 0.15, 0.5;
    policy.max_up_grade = spec.max_up_grade or 0.649407566;
    policy.max_continuous_down_grade = spec.max_down_grade or 1;
    policy.max_step_up, policy.max_step_down = 0.5, 0.5;
    policy.max_drop = 0;
    policy.min_safe_span = spec.min_safe_span or 0.05;
    policy.max_edge_run = spec.max_edge_run or 4;
    policy.grid_cell_size = cell_size;
    policy.policy_flags = 1;
    policy.source_obj_crc32 = 0x30BA83D1;
    policy.builder_revision = 3;
    policy.weld_tolerance_mm = 20;

    local nodes = ffi.cast('TestAxwgNodeV2*', bytes + nodes_offset);
    local edges = ffi.cast('TestAxwgEdgeV2*', bytes + edges_offset);
    local edge_cursor = 0;
    for node_index, node_spec in ipairs(nodes_spec) do
        local node = nodes[node_index - 1];
        node.x, node.z, node.y = node_spec.x, node_spec.z, node_spec.y;
        node.first_edge, node.edge_count = edge_cursor, #(adjacency[node_index] or {});
        node.component_id = node_spec.component or 0;
        node.source_ref = node_spec.source_ref or (node_index - 1);
        node.flags, node.clearance = node_spec.flags or 0, node_spec.clearance or 2;
        for _, edge_spec in ipairs(adjacency[node_index] or {}) do
            local target = nodes_spec[edge_spec.to + 1];
            local dx, dz = target.x - node_spec.x, target.z - node_spec.z;
            local rise = node_spec.y - target.y;
            local edge = edges[edge_cursor];
            edge.to = edge_spec.to;
            edge.cost = edge_spec.cost or math.sqrt(dx * dx + dz * dz + rise * rise);
            edge.rise_cm = edge_spec.rise_cm or quantize(rise);
            edge.run_cm = edge_spec.run_cm or quantize(math.sqrt(dx * dx + dz * dz));
            edge.flags = edge_spec.flags or (edge.rise_cm < 0 and 3 or 1);
            edge.portal_id = edge_spec.portal_id;
            edge_cursor = edge_cursor + 1;
        end
    end

    local portals = ffi.cast('TestAxwgPortalV2*', bytes + portals_offset);
    for portal_index, portal_spec in ipairs(portals_spec) do
        local portal = portals[portal_index - 1];
        portal.node_a, portal.node_b = portal_spec.node_a, portal_spec.node_b;
        portal.left_x, portal.left_z = portal_spec.left_x, portal_spec.left_z;
        portal.right_x, portal.right_z = portal_spec.right_x, portal_spec.right_z;
        portal.left_y_a, portal.left_y_b = portal_spec.left_y_a, portal_spec.left_y_b;
        portal.right_y_a, portal.right_y_b = portal_spec.right_y_a, portal_spec.right_y_b;
        portal.capacity_cm, portal.flags = portal_spec.capacity_cm, portal_spec.flags or 3;
    end

    local grid = ffi.cast('TestAxwgGridV2*', bytes + header.grid_offset);
    grid.min_x, grid.min_z, grid.cell_size = min_x, min_z, cell_size;
    grid.width, grid.height = width, height;
    grid.buckets_offset, grid.entries_offset = buckets_offset, entries_offset;
    local buckets = ffi.cast('TestAxwgBucketV2*', bytes + buckets_offset);
    local entries = ffi.cast('uint32_t*', bytes + entries_offset);
    local entry_cursor = 0;
    for bucket_index, ids in ipairs(bucket_lists) do
        buckets[bucket_index - 1].first_entry = entry_cursor;
        buckets[bucket_index - 1].entry_count = #ids;
        for _, node_id in ipairs(ids) do
            entries[entry_cursor] = node_id;
            entry_cursor = entry_cursor + 1;
        end
    end

    local context = {
        bytes = bytes, header = header, policy = policy, nodes = nodes,
        edges = edges, portals = portals, grid = grid, buckets = buckets,
        entries = entries, file_size = file_size,
    };
    if (mutate ~= nil) then mutate(context); end
    header.payload_crc32 = crc32(bytes, header_size, file_size - header_size);
    if (corrupt_after_crc ~= nil) then corrupt_after_crc(context); end

    local file = assert(io.open(path, 'wb'));
    assert(file:write(ffi.string(bytes, file_size)));
    assert(file:close());
end

return M;
