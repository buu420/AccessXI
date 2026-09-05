-- Offline AXWG v1/v2 loader and path search runtime.
-- This module is deliberately not installed into the live Ashita addon.

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
} AxwgHeaderV1;
typedef struct {
    float agent_radius; float agent_height; float support_sample_step;
    float support_smooth_window; float max_up_grade;
    float max_continuous_down_grade; float max_step_up; float max_step_down;
    float max_drop; float min_clearance; float max_edge_run;
    float grid_cell_size; uint32_t policy_flags; uint32_t source_obj_crc32;
    uint32_t builder_revision; uint32_t reserved;
} AxwgPolicyV1;
typedef struct {
    float x; float z; float y; uint32_t first_edge; uint32_t component_id;
    uint32_t source_ref; uint16_t edge_count; uint16_t flags; float clearance;
} AxwgNodeV1;
typedef struct {
    uint32_t to; float cost; int16_t rise_cm; uint16_t run_cm;
    uint16_t min_clearance_cm; uint16_t flags;
} AxwgEdgeV1;
typedef struct {
    float min_x; float min_z; float cell_size; uint32_t width; uint32_t height;
    uint32_t buckets_offset; uint32_t entries_offset; uint32_t reserved;
} AxwgGridV1;
typedef struct { uint32_t first_entry; uint32_t entry_count; } AxwgBucketV1;
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
} AxwgHeaderV2;
typedef struct {
    float agent_radius; float agent_height; float support_sample_step;
    float support_smooth_window; float max_up_grade;
    float max_continuous_down_grade; float max_step_up; float max_step_down;
    float max_drop; float min_safe_span; float max_edge_run;
    float grid_cell_size; uint32_t policy_flags; uint32_t source_obj_crc32;
    uint32_t builder_revision; uint32_t weld_tolerance_mm;
} AxwgPolicyV2;
typedef struct {
    uint32_t to; float cost; int16_t rise_cm; uint16_t run_cm;
    uint16_t flags; uint16_t reserved; uint32_t portal_id;
} AxwgEdgeV2;
typedef struct {
    uint32_t node_a; uint32_t node_b;
    float left_x; float left_z; float right_x; float right_z;
    float left_y_a; float left_y_b; float right_y_a; float right_y_b;
    uint16_t capacity_cm; uint16_t flags; uint32_t reserved;
} AxwgPortalV2;
]];

assert(ffi.sizeof('AxwgHeaderV1') == 64, 'AXWG header ABI mismatch');
assert(ffi.sizeof('AxwgPolicyV1') == 64, 'AXWG policy ABI mismatch');
assert(ffi.sizeof('AxwgNodeV1') == 32, 'AXWG node ABI mismatch');
assert(ffi.sizeof('AxwgEdgeV1') == 16, 'AXWG edge ABI mismatch');
assert(ffi.sizeof('AxwgGridV1') == 32, 'AXWG grid ABI mismatch');
assert(ffi.sizeof('AxwgBucketV1') == 8, 'AXWG bucket ABI mismatch');
assert(ffi.sizeof('AxwgHeaderV2') == 80, 'AXWG v2 header ABI mismatch');
assert(ffi.sizeof('AxwgPolicyV2') == 64, 'AXWG v2 policy ABI mismatch');
assert(ffi.sizeof('AxwgEdgeV2') == 20, 'AXWG v2 edge ABI mismatch');
assert(ffi.sizeof('AxwgPortalV2') == 48, 'AXWG v2 portal ABI mismatch');

local M = {};
local Graph = {};
Graph.__index = Graph;
local Search = {};
Search.__index = Search;
local SearchV2 = {};
SearchV2.__index = SearchV2;

local DEFAULT_LOAD_READ_CHUNK_SIZE = 256 * 1024;
local DEFAULT_LOAD_CRC_CHUNK_SIZE = 16 * 1024;
local DEFAULT_LOAD_VALIDATION_BATCH_SIZE = 256;
local DEFAULT_LOAD_BUDGET_MS = 2;
local DEFAULT_MAX_FILE_SIZE = 512 * 1024 * 1024;

local FLAG_DIRECTED = 0x01;
local FLAG_Y_DOWN = 0x02;
local FLAG_GRID = 0x04;
local FLAG_CAPSULE_VERIFIED = 0x08;
local FLAG_HAS_DROPS = 0x10;
local FLAG_HAS_PORTALS = 0x20;
local FLAG_SAFE_PORTAL_INTERVALS = 0x40;
local EDGE_WALK = 0x01;
local EDGE_DROP = 0x04;
local PORTAL_SAFE_INTERVAL_CERTIFIED = 0x01;
local PORTAL_WALL_ERODED = 0x02;
local PORTAL_HEADROOM_CHECKED = 0x04;
local PORTAL_FULL_CAPSULE_CHECKED = 0x08;
local V2_MIN_AGENT_RADIUS = 0.70;
local V2_MIN_AGENT_HEIGHT = 1.80;
local V2_MAX_UP_GRADE = 0.649407566;
local V2_MAX_DOWN_GRADE = 1.0;
local V2_MAX_STEP_UP = 0.5;
local V2_MAX_STEP_DOWN = 0.5;
local V2_MIN_SAFE_SPAN = 0.05;
local V2_WELD_TOLERANCE_MM = 20;

local CRC32_TABLE = {};
for value = 0, 255 do
    local crc = value;
    for _ = 1, 8 do
        if (bit.band(crc, 1) ~= 0) then
            crc = bit.bxor(bit.rshift(crc, 1), 0xEDB88320);
        else
            crc = bit.rshift(crc, 1);
        end
    end
    CRC32_TABLE[value] = crc;
end

local function crc32(bytes, offset, length, checkpoint, chunk_size)
    local crc = 0xFFFFFFFF;
    local since_checkpoint = 0;
    chunk_size = math.max(1, math.floor(tonumber(chunk_size) or 16384));
    for i = offset, offset + length - 1 do
        local index = bit.band(bit.bxor(crc, bytes[i]), 0xFF);
        crc = bit.bxor(bit.rshift(crc, 8), CRC32_TABLE[index]);
        if (checkpoint ~= nil) then
            since_checkpoint = since_checkpoint + 1;
            if (since_checkpoint >= chunk_size) then
                checkpoint(true);
                since_checkpoint = 0;
            end
        end
    end
    if (checkpoint ~= nil and since_checkpoint > 0) then checkpoint(true); end
    return tonumber(ffi.cast('uint32_t', bit.bnot(crc)));
end

local function finite(value)
    value = tonumber(value);
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge;
end

local function rounded(value)
    if (value >= 0) then return math.floor(value + 0.5); end
    return math.ceil(value - 0.5);
end

local function section(file_size, offset, count, item_size, name)
    offset, count = tonumber(offset), tonumber(count);
    if offset == nil or count == nil or offset < 64 or offset % 4 ~= 0 then
        return nil, ('invalid AXWG %s offset'):format(name);
    end
    local last = offset + (count * item_size);
    if last < offset or last > file_size then
        return nil, ('AXWG %s is outside the file'):format(name);
    end
    return { first = offset, last = last, name = name };
end

local function sections_do_not_overlap(parts)
    local occupied = {};
    for _, part in ipairs(parts) do
        if (part.last > part.first) then occupied[#occupied + 1] = part; end
    end
    table.sort(occupied, function(a, b) return a.first < b.first; end);
    for i = 2, #occupied do
        if occupied[i].first < occupied[i - 1].last then
            return nil, ('AXWG sections overlap: %s and %s'):format(
                occupied[i - 1].name, occupied[i].name);
        end
    end
    return true;
end

function Graph:is_capsule_verified()
    return bit.band(self.flags, FLAG_CAPSULE_VERIFIED) ~= 0;
end

function Graph:is_headroom_checked()
    return self._all_portals_headroom_checked == true;
end

function Graph:portal(portal_id, from_node_id)
    if (self.version ~= 2) then return nil, 'AXWG v1 has no certified portals'; end
    portal_id, from_node_id = tonumber(portal_id), tonumber(from_node_id);
    if (portal_id == nil or portal_id % 1 ~= 0
            or portal_id < 0 or portal_id >= self.portal_count) then
        return nil, 'invalid zero-based AXWG portal ID';
    end
    if (from_node_id == nil or from_node_id % 1 ~= 0
            or from_node_id < 0 or from_node_id >= self.node_count) then
        return nil, 'invalid zero-based AXWG portal source node ID';
    end
    local portal = self._portals[portal_id];
    local node_a, node_b = tonumber(portal.node_a), tonumber(portal.node_b);
    local forward;
    if (from_node_id == node_a) then
        forward = true;
    elseif (from_node_id == node_b) then
        forward = false;
    else
        return nil, 'AXWG portal does not bind the source node';
    end

    local function point(x, z, y_from, y_to)
        return {
            x = tonumber(x), z = tonumber(z),
            y_from = tonumber(y_from), y_to = tonumber(y_to),
        };
    end
    if (forward) then
        return {
            portal_id = portal_id,
            node_from = node_a, node_to = node_b,
            left = point(portal.left_x, portal.left_z, portal.left_y_a, portal.left_y_b),
            right = point(portal.right_x, portal.right_z, portal.right_y_a, portal.right_y_b),
            capacity_cm = tonumber(portal.capacity_cm),
            flags = tonumber(portal.flags),
        };
    end
    return {
        portal_id = portal_id,
        node_from = node_b, node_to = node_a,
        left = point(portal.right_x, portal.right_z, portal.right_y_b, portal.right_y_a),
        right = point(portal.left_x, portal.left_z, portal.left_y_b, portal.left_y_a),
        capacity_cm = tonumber(portal.capacity_cm),
        flags = tonumber(portal.flags),
    };
end

function Graph:point(node_id)
    node_id = tonumber(node_id);
    if (node_id == nil or node_id % 1 ~= 0 or node_id < 0 or node_id >= self.node_count) then
        return nil, 'invalid zero-based AXWG node ID';
    end
    local node = self._nodes[node_id];
    return {
        node_id = node_id,
        zone = self.zone_id,
        x = tonumber(node.x),
        z = tonumber(node.z),
        y = tonumber(node.y),
        component_id = tonumber(node.component_id),
        source_ref = tonumber(node.source_ref),
        flags = tonumber(node.flags),
        clearance = tonumber(node.clearance),
    };
end

function Graph:nearest(x, z, y, max_horizontal, max_vertical, minimum_clearance)
    x, z, y = tonumber(x), tonumber(z), tonumber(y);
    max_horizontal, max_vertical = tonumber(max_horizontal), tonumber(max_vertical);
    minimum_clearance = tonumber(minimum_clearance) or 0;
    if (not finite(x) or not finite(z) or not finite(y)
            or not finite(max_horizontal) or max_horizontal < 0
            or not finite(max_vertical) or max_vertical < 0
            or not finite(minimum_clearance) or minimum_clearance < 0) then
        return nil, 'invalid nearest-node bounds';
    end

    local grid, nodes = self._grid, self._nodes;
    local cell_size = tonumber(grid.cell_size);
    local min_x, min_z = tonumber(grid.min_x), tonumber(grid.min_z);
    local width, height = tonumber(grid.width), tonumber(grid.height);
    local first_x = math.max(0, math.floor((x - max_horizontal - min_x) / cell_size));
    local last_x = math.min(width - 1, math.floor((x + max_horizontal - min_x) / cell_size));
    local first_z = math.max(0, math.floor((z - max_horizontal - min_z) / cell_size));
    local last_z = math.min(height - 1, math.floor((z + max_horizontal - min_z) / cell_size));
    if (first_x > last_x or first_z > last_z) then
        return nil, 'no graph node within bounds';
    end

    local best_id, best_score, best_horizontal, best_vertical;
    local max_h_sq = max_horizontal * max_horizontal;
    for cell_z = first_z, last_z do
        for cell_x = first_x, last_x do
            local bucket = self._buckets[(cell_z * width) + cell_x];
            local first = tonumber(bucket.first_entry);
            for entry_index = first, first + tonumber(bucket.entry_count) - 1 do
                local node_id = tonumber(self._entries[entry_index]);
                local node = nodes[node_id];
                if (tonumber(node.clearance) >= minimum_clearance) then
                    local dx, dz = tonumber(node.x) - x, tonumber(node.z) - z;
                    local h_sq = dx * dx + dz * dz;
                    local vertical = math.abs(tonumber(node.y) - y);
                    if (h_sq <= max_h_sq and vertical <= max_vertical) then
                        local score = h_sq + vertical * vertical;
                        if (best_score == nil or score < best_score
                                or (score == best_score and node_id < best_id)) then
                            best_id, best_score = node_id, score;
                            best_horizontal, best_vertical = math.sqrt(h_sq), vertical;
                        end
                    end
                end
            end
        end
    end
    if (best_id == nil) then return nil, 'no graph node within bounds'; end
    return best_id, best_horizontal, best_vertical;
end

function Graph:candidates(x, z, y, options)
    options = options or {};
    x, z, y = tonumber(x), tonumber(z), tonumber(y);
    local max_horizontal = tonumber(options.max_horizontal);
    local max_vertical = tonumber(options.max_vertical);
    local minimum_clearance = tonumber(options.minimum_node_clearance) or 0;
    local max_results = tonumber(options.max_results) or 32;
    if (not finite(x) or not finite(z) or not finite(y)
            or not finite(max_horizontal) or max_horizontal < 0
            or not finite(max_vertical) or max_vertical < 0
            or not finite(minimum_clearance) or minimum_clearance < 0
            or not finite(max_results) or max_results < 1 or max_results % 1 ~= 0) then
        return nil, 'invalid candidate bounds';
    end

    local grid, nodes = self._grid, self._nodes;
    local cell_size = tonumber(grid.cell_size);
    local min_x, min_z = tonumber(grid.min_x), tonumber(grid.min_z);
    local width, height = tonumber(grid.width), tonumber(grid.height);
    local first_x = math.max(0, math.floor((x - max_horizontal - min_x) / cell_size));
    local last_x = math.min(width - 1, math.floor((x + max_horizontal - min_x) / cell_size));
    local first_z = math.max(0, math.floor((z - max_horizontal - min_z) / cell_size));
    local last_z = math.min(height - 1, math.floor((z + max_horizontal - min_z) / cell_size));
    local result = {};
    if (first_x > last_x or first_z > last_z) then return result; end

    local max_h_sq = max_horizontal * max_horizontal;
    for cell_z = first_z, last_z do
        for cell_x = first_x, last_x do
            local bucket = self._buckets[(cell_z * width) + cell_x];
            local first = tonumber(bucket.first_entry);
            for entry_index = first, first + tonumber(bucket.entry_count) - 1 do
                local node_id = tonumber(self._entries[entry_index]);
                local node = nodes[node_id];
                if (tonumber(node.clearance) >= minimum_clearance) then
                    local dx, dz = tonumber(node.x) - x, tonumber(node.z) - z;
                    local h_sq = dx * dx + dz * dz;
                    local vertical = math.abs(tonumber(node.y) - y);
                    if (h_sq <= max_h_sq and vertical <= max_vertical) then
                        local horizontal = math.sqrt(h_sq);
                        result[#result + 1] = {
                            node_id = node_id,
                            x = tonumber(node.x), z = tonumber(node.z), y = tonumber(node.y),
                            horizontal = horizontal,
                            vertical = vertical,
                            distance = math.sqrt(h_sq + vertical * vertical),
                            component_id = tonumber(node.component_id),
                            connector_certified = false,
                        };
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if (a.distance ~= b.distance) then return a.distance < b.distance; end
        return a.node_id < b.node_id;
    end);
    while (#result > max_results) do result[#result] = nil; end
    return result;
end

local function route_arc_prefix(graph, route)
    if (type(route) ~= 'table' or type(route.edge_ids) ~= 'table'
            or #route < 1 or #route.edge_ids ~= #route - 1) then
        return nil, 'malformed AXWG v2 route for live matching';
    end
    local prefix = { [1] = 0 };
    for index = 1, #route.edge_ids do
        local from, to = tonumber(route[index]), tonumber(route[index + 1]);
        local edge_id = tonumber(route.edge_ids[index]);
        if (from == nil or from % 1 ~= 0 or from < 0 or from >= graph.node_count
                or to == nil or to % 1 ~= 0 or to < 0 or to >= graph.node_count
                or edge_id == nil or edge_id % 1 ~= 0
                or edge_id < 0 or edge_id >= graph.edge_count) then
            return nil, ('malformed AXWG v2 route at index %d'):format(index);
        end
        local edge = graph._edges[edge_id];
        local cost = tonumber(edge.cost);
        if (tonumber(graph._edge_from[edge_id]) ~= from or tonumber(edge.to) ~= to
                or not finite(cost) or cost <= 0) then
            return nil, ('AXWG v2 route edge disagrees at index %d'):format(index);
        end
        prefix[index + 1] = prefix[index] + cost;
    end
    return prefix;
end

function Graph:match_route_candidate(route, x, z, y, previous_index, options)
    if (self.version ~= 2) then
        return nil, 'route-local candidate matching requires AXWG v2';
    end
    options = options or {};
    previous_index = tonumber(previous_index);
    local max_forward_arc = tonumber(options.max_forward_arc);
    local max_backward_indices = tonumber(options.max_backward_indices) or 0;
    if (type(route) ~= 'table' or #route < 1
            or previous_index == nil or previous_index % 1 ~= 0
            or previous_index < 1 or previous_index > #route
            or not finite(max_forward_arc) or max_forward_arc < 0
            or not finite(max_backward_indices) or max_backward_indices < 0
            or max_backward_indices % 1 ~= 0) then
        return nil, 'invalid route-local candidate bounds';
    end

    local prefix, prefix_error = route_arc_prefix(self, route);
    if (prefix == nil) then return nil, prefix_error; end
    local candidate_options = {
        max_horizontal = options.max_horizontal,
        max_vertical = options.max_vertical,
        minimum_node_clearance = options.minimum_node_clearance,
        -- Spatial aliases can otherwise crowd the true owned-corridor node out of a
        -- fixed-size nearest list. Arc distance, not list truncation, is authoritative.
        max_results = self.node_count,
    };
    local candidates, candidate_error = self:candidates(x, z, y, candidate_options);
    if (candidates == nil) then return nil, candidate_error; end

    local route_indices = {};
    for index, node_id in ipairs(route) do
        node_id = tonumber(node_id);
        if (node_id == nil or node_id % 1 ~= 0
                or node_id < 0 or node_id >= self.node_count) then
            return nil, ('malformed AXWG v2 route node at index %d'):format(index);
        end
        local indices = route_indices[node_id];
        if (indices == nil) then indices = {}; route_indices[node_id] = indices; end
        indices[#indices + 1] = index;
    end

    local earliest = math.max(1, previous_index - max_backward_indices);
    local best, best_index, best_arc;
    for _, candidate in ipairs(candidates) do
        local indices = route_indices[candidate.node_id];
        if (indices ~= nil) then
            for _, index in ipairs(indices) do
                local arc = prefix[index] - prefix[previous_index];
                local allowed = index >= earliest
                    and (index <= previous_index or arc <= max_forward_arc + 1e-6);
                if (allowed) then
                    if (best == nil
                            or candidate.distance < best.distance
                            or (candidate.distance == best.distance
                                and (arc < best_arc
                                    or (arc == best_arc
                                        and (index < best_index
                                            or (index == best_index
                                                and candidate.node_id < best.node_id)))))) then
                        best, best_index, best_arc = candidate, index, arc;
                    end
                end
            end
        end
    end
    if (best == nil) then
        return nil, 'no route-consistent candidate within bounds';
    end
    return {
        node_id = best.node_id,
        route_index = best_index,
        forward_arc = best_arc,
        x = best.x, z = best.z, y = best.y,
        horizontal = best.horizontal,
        vertical = best.vertical,
        distance = best.distance,
        component_id = best.component_id,
        connector_certified = false,
    };
end

local function workspace(graph)
    if (graph._workspace ~= nil) then return graph._workspace; end
    local count = graph.node_count;
    graph._workspace = {
        generation = 0,
        score = ffi.new('double[?]', count),
        parent = ffi.new('int32_t[?]', count),
        stamp = ffi.new('uint32_t[?]', count),
        closed = ffi.new('uint32_t[?]', count),
        heap_nodes = ffi.new('uint32_t[?]', count),
        heap_scores = ffi.new('double[?]', count),
        heap_position = ffi.new('int32_t[?]', count),
    };
    return graph._workspace;
end

local function heuristic(nodes, from, goal)
    local a, b = nodes[from], nodes[goal];
    local dx = tonumber(b.x) - tonumber(a.x);
    local dz = tonumber(b.z) - tonumber(a.z);
    local dy = tonumber(b.y) - tonumber(a.y);
    return math.sqrt(dx * dx + dz * dz + dy * dy);
end

local function heap_less(search, left, right)
    local ws = search._workspace;
    local a, b = tonumber(ws.heap_scores[left]), tonumber(ws.heap_scores[right]);
    if (a ~= b) then return a < b; end
    return tonumber(ws.heap_nodes[left]) < tonumber(ws.heap_nodes[right]);
end

local function heap_swap(search, left, right)
    local ws = search._workspace;
    local left_node, right_node = ws.heap_nodes[left], ws.heap_nodes[right];
    local left_score = ws.heap_scores[left];
    ws.heap_nodes[left], ws.heap_scores[left] = right_node, ws.heap_scores[right];
    ws.heap_nodes[right], ws.heap_scores[right] = left_node, left_score;
    ws.heap_position[tonumber(right_node)] = left;
    ws.heap_position[tonumber(left_node)] = right;
end

local function heap_up(search, index)
    while index > 0 do
        local parent = math.floor((index - 1) / 2);
        if (not heap_less(search, index, parent)) then break; end
        heap_swap(search, index, parent);
        index = parent;
    end
end

local function heap_down(search, index)
    while true do
        local left = (index * 2) + 1;
        if (left >= search._heap_size) then return; end
        local right, smallest = left + 1, left;
        if (right < search._heap_size and heap_less(search, right, left)) then smallest = right; end
        if (not heap_less(search, smallest, index)) then return; end
        heap_swap(search, index, smallest);
        index = smallest;
    end
end

local function heap_set(search, node_id, score)
    local ws = search._workspace;
    local position = tonumber(ws.heap_position[node_id]);
    if (position >= 0) then
        if (score < tonumber(ws.heap_scores[position])) then
            ws.heap_scores[position] = score;
            heap_up(search, position);
        end
        return;
    end
    position = search._heap_size;
    search._heap_size = position + 1;
    ws.heap_nodes[position], ws.heap_scores[position] = node_id, score;
    ws.heap_position[node_id] = position;
    heap_up(search, position);
end

local function heap_pop(search)
    local ws = search._workspace;
    local node_id = tonumber(ws.heap_nodes[0]);
    search._heap_size = search._heap_size - 1;
    ws.heap_position[node_id] = -1;
    if (search._heap_size > 0) then
        local replacement = ws.heap_nodes[search._heap_size];
        ws.heap_nodes[0] = replacement;
        ws.heap_scores[0] = ws.heap_scores[search._heap_size];
        ws.heap_position[tonumber(replacement)] = 0;
        heap_down(search, 0);
    end
    return node_id;
end

local function reconstruct(search)
    local reverse, node_id = {}, search.goal_id;
    for _ = 1, search.graph.node_count + 1 do
        reverse[#reverse + 1] = node_id;
        if (node_id == search.start_id) then break; end
        node_id = tonumber(search._workspace.parent[node_id]);
        if (node_id < 0) then return nil, 'AXWG parent chain ended before the start'; end
    end
    if (reverse[#reverse] ~= search.start_id) then return nil, 'AXWG parent chain contains a cycle'; end
    local path = {};
    for i = #reverse, 1, -1 do path[#path + 1] = reverse[i]; end
    return path;
end

function Search:step(max_expansions)
    max_expansions = tonumber(max_expansions);
    if (max_expansions == nil or max_expansions < 1 or max_expansions % 1 ~= 0) then
        return nil, nil, 'max_expansions must be a positive integer';
    end
    if (self.graph._search_serial ~= self._serial) then
        return nil, nil, 'search was superseded by a newer graph search';
    end
    if (self._terminal ~= nil) then
        return self._terminal, self._path, self._reason;
    end

    local graph, ws, generation = self.graph, self._workspace, self._generation;
    local used = 0;
    while used < max_expansions and self._heap_size > 0 do
        local current = heap_pop(self);
        if (ws.closed[current] ~= generation) then
            ws.closed[current] = generation;
            used, self.expansions = used + 1, self.expansions + 1;
            if (current == self.goal_id) then
                local path, path_error = reconstruct(self);
                if (path == nil) then
                    self._terminal, self._reason = 'no-path', path_error;
                else
                    self._terminal, self._path = 'ready', path;
                end
                return self._terminal, self._path, self._reason;
            end

            local node = graph._nodes[current];
            local first = tonumber(node.first_edge);
            for edge_index = first, first + tonumber(node.edge_count) - 1 do
                local edge = graph._edges[edge_index];
                local neighbour = tonumber(edge.to);
                if (tonumber(edge.min_clearance_cm) >= graph.minimum_clearance_cm
                        and ws.closed[neighbour] ~= generation) then
                    local candidate = tonumber(ws.score[current]) + tonumber(edge.cost);
                    if (ws.stamp[neighbour] ~= generation or candidate < tonumber(ws.score[neighbour])) then
                        if (ws.stamp[neighbour] ~= generation) then
                            ws.stamp[neighbour] = generation;
                            ws.heap_position[neighbour] = -1;
                        end
                        ws.score[neighbour] = candidate;
                        ws.parent[neighbour] = current;
                        heap_set(self, neighbour,
                            candidate + heuristic(graph._nodes, neighbour, self.goal_id));
                    end
                end
            end
        end
    end
    if (self._heap_size == 0) then
        self._terminal, self._reason = 'no-path', 'directed graph has no route';
        return self._terminal, nil, self._reason;
    end
    return 'pending';
end

function Graph:begin_astar(start_id, goal_id)
    if (self.version == 2) then
        return self:begin_route({ start_id }, { goal_id });
    end
    start_id, goal_id = tonumber(start_id), tonumber(goal_id);
    if (start_id == nil or goal_id == nil or start_id % 1 ~= 0 or goal_id % 1 ~= 0
            or start_id < 0 or start_id >= self.node_count
            or goal_id < 0 or goal_id >= self.node_count) then
        return nil, 'start and goal must be valid zero-based node IDs';
    end

    local ws = workspace(self);
    ws.generation = ws.generation + 1;
    if (ws.generation >= 0xFFFFFFFF) then
        ffi.fill(ws.stamp, ffi.sizeof('uint32_t') * self.node_count);
        ffi.fill(ws.closed, ffi.sizeof('uint32_t') * self.node_count);
        ws.generation = 1;
    end
    self._search_serial = (self._search_serial or 0) + 1;
    local search = setmetatable({
        graph = self,
        start_id = start_id,
        goal_id = goal_id,
        expansions = 0,
        _workspace = ws,
        _generation = ws.generation,
        _serial = self._search_serial,
        _heap_size = 0,
    }, Search);

    if (tonumber(self._nodes[start_id].component_id)
            ~= tonumber(self._nodes[goal_id].component_id)) then
        search._terminal, search._reason = 'no-path', 'start and goal are in different components';
        return search;
    end
    if (start_id == goal_id) then
        search._terminal, search._path = 'ready', { start_id };
        return search;
    end

    local generation = ws.generation;
    ws.stamp[start_id] = generation;
    ws.closed[start_id] = 0;
    ws.score[start_id] = 0;
    ws.parent[start_id] = -1;
    ws.heap_position[start_id] = -1;
    heap_set(search, start_id, heuristic(self._nodes, start_id, goal_id));
    return search;
end

local function workspace_v2(graph)
    if (graph._workspace_v2 ~= nil) then return graph._workspace_v2; end
    local count = graph.edge_count + graph.node_count + 1;
    graph._workspace_v2 = {
        generation = 0,
        state_count = count,
        score = ffi.new('double[?]', count),
        parent = ffi.new('int32_t[?]', count),
        parent_edge = ffi.new('int32_t[?]', count),
        stamp = ffi.new('uint32_t[?]', count),
        closed = ffi.new('uint32_t[?]', count),
        heap_states = ffi.new('uint32_t[?]', count),
        heap_scores = ffi.new('double[?]', count),
        heap_position = ffi.new('int32_t[?]', count),
    };
    return graph._workspace_v2;
end

local function v2_state_node(search, state_id)
    if (state_id < search.graph.edge_count) then
        return tonumber(search.graph._edges[state_id].to);
    end
    if (state_id < search._virtual_goal) then
        return state_id - search.graph.edge_count;
    end
    return nil;
end

local function v2_edge_portal_points(graph, edge_id)
    local edge = graph._edges[edge_id];
    local from, to = tonumber(graph._edge_from[edge_id]), tonumber(edge.to);
    local portal = graph._portals[tonumber(edge.portal_id)];
    local x = (tonumber(portal.left_x) + tonumber(portal.right_x)) * 0.5;
    local z = (tonumber(portal.left_z) + tonumber(portal.right_z)) * 0.5;
    if (from == tonumber(portal.node_a) and to == tonumber(portal.node_b)) then
        return x, z,
            (tonumber(portal.left_y_a) + tonumber(portal.right_y_a)) * 0.5,
            (tonumber(portal.left_y_b) + tonumber(portal.right_y_b)) * 0.5;
    end
    return x, z,
        (tonumber(portal.left_y_b) + tonumber(portal.right_y_b)) * 0.5,
        (tonumber(portal.left_y_a) + tonumber(portal.right_y_a)) * 0.5;
end

local function v2_state_position(search, state_id)
    if (state_id < search.graph.edge_count) then
        local x, z, _, y_to = v2_edge_portal_points(search.graph, state_id);
        return x, z, y_to;
    end
    local node_id = v2_state_node(search, state_id);
    local node = search.graph._nodes[node_id];
    return tonumber(node.x), tonumber(node.z), tonumber(node.y);
end

local function distance3(ax, az, ay, bx, bz, by)
    local dx, dz, dy = bx - ax, bz - az, by - ay;
    return math.sqrt(dx * dx + dz * dz + dy * dy);
end

local function v2_transition_cost(search, current_state, outgoing_edge)
    local current_x, current_z, current_y = v2_state_position(search, current_state);
    local portal_x, portal_z, y_from, y_to =
        v2_edge_portal_points(search.graph, outgoing_edge);
    return distance3(current_x, current_z, current_y,
        portal_x, portal_z, y_from) + math.abs(y_to - y_from);
end

local function v2_goal_cost(search, state_id, node_id, connector_cost)
    local x, z, y = v2_state_position(search, state_id);
    local node = search.graph._nodes[node_id];
    return distance3(x, z, y,
        tonumber(node.x), tonumber(node.z), tonumber(node.y)) + connector_cost;
end

local function v2_heuristic(search, state_id)
    local x, z, y = v2_state_position(search, state_id);
    local best = math.huge;
    for _, goal in ipairs(search._goals) do
        local target = search.graph._nodes[goal.node_id];
        local estimate = distance3(x, z, y,
            tonumber(target.x), tonumber(target.z), tonumber(target.y))
                + goal.connector_cost;
        if (estimate < best) then best = estimate; end
    end
    return best;
end

local function v2_heap_less(search, left, right)
    local ws = search._workspace;
    local a, b = tonumber(ws.heap_scores[left]), tonumber(ws.heap_scores[right]);
    if (a ~= b) then return a < b; end
    return tonumber(ws.heap_states[left]) < tonumber(ws.heap_states[right]);
end

local function v2_heap_swap(search, left, right)
    local ws = search._workspace;
    local left_state, right_state = ws.heap_states[left], ws.heap_states[right];
    local left_score = ws.heap_scores[left];
    ws.heap_states[left], ws.heap_scores[left] = right_state, ws.heap_scores[right];
    ws.heap_states[right], ws.heap_scores[right] = left_state, left_score;
    ws.heap_position[tonumber(right_state)] = left;
    ws.heap_position[tonumber(left_state)] = right;
end

local function v2_heap_up(search, index)
    while index > 0 do
        local parent = math.floor((index - 1) / 2);
        if (not v2_heap_less(search, index, parent)) then break; end
        v2_heap_swap(search, index, parent);
        index = parent;
    end
end

local function v2_heap_down(search, index)
    while true do
        local left = index * 2 + 1;
        if (left >= search._heap_size) then return; end
        local right, smallest = left + 1, left;
        if (right < search._heap_size and v2_heap_less(search, right, left)) then
            smallest = right;
        end
        if (not v2_heap_less(search, smallest, index)) then return; end
        v2_heap_swap(search, smallest, index);
        index = smallest;
    end
end

local function v2_heap_set(search, state_id, score)
    local ws = search._workspace;
    local position = tonumber(ws.heap_position[state_id]);
    if (position >= 0) then
        if (score < tonumber(ws.heap_scores[position])) then
            ws.heap_scores[position] = score;
            v2_heap_up(search, position);
        end
        return;
    end
    position = search._heap_size;
    search._heap_size = position + 1;
    ws.heap_states[position], ws.heap_scores[position] = state_id, score;
    ws.heap_position[state_id] = position;
    v2_heap_up(search, position);
end

local function v2_heap_pop(search)
    local ws = search._workspace;
    local state_id = tonumber(ws.heap_states[0]);
    search._heap_size = search._heap_size - 1;
    ws.heap_position[state_id] = -1;
    if (search._heap_size > 0) then
        local replacement = ws.heap_states[search._heap_size];
        ws.heap_states[0] = replacement;
        ws.heap_scores[0] = ws.heap_scores[search._heap_size];
        ws.heap_position[tonumber(replacement)] = 0;
        v2_heap_down(search, 0);
    end
    return state_id;
end

local function normalize_route_candidate(graph, candidate, role)
    if (type(candidate) == 'number') then
        local node_id = tonumber(candidate);
        if (node_id % 1 ~= 0 or node_id < 0 or node_id >= graph.node_count) then
            return nil, role .. ' node ID is invalid';
        end
        local node = graph._nodes[node_id];
        return {
            node_id = node_id,
            connector_cost = 0,
            connector_certified = true,
            exact_node = true,
            x = tonumber(node.x), z = tonumber(node.z), y = tonumber(node.y),
        };
    end
    if (type(candidate) ~= 'table') then
        return nil, role .. ' candidate must be a node ID or table';
    end
    local node_id = tonumber(candidate.node_id);
    local connector_cost = tonumber(candidate.connector_cost);
    if (node_id == nil or node_id % 1 ~= 0
            or node_id < 0 or node_id >= graph.node_count) then
        return nil, role .. ' candidate has an invalid node ID';
    end
    if (candidate.connector_certified ~= true) then
        return nil, role .. ' connector is not independently certified';
    end
    if (not finite(candidate.x) or not finite(candidate.z) or not finite(candidate.y)) then
        return nil, role .. ' connector requires finite x,z,y';
    end
    if (not finite(connector_cost) or connector_cost < 0) then
        return nil, role .. ' connector cost must be finite and nonnegative';
    end
    local node = graph._nodes[node_id];
    local connector_dx = tonumber(node.x) - tonumber(candidate.x);
    local connector_dz = tonumber(node.z) - tonumber(candidate.z);
    local connector_dy = tonumber(node.y) - tonumber(candidate.y);
    if (connector_dx * connector_dx + connector_dz * connector_dz <= 1e-12
            and math.abs(connector_dy) > 1e-6) then
        return nil, role .. ' direct connector has no horizontal walk';
    end
    local direct = distance3(
        tonumber(candidate.x), tonumber(candidate.z), tonumber(candidate.y),
        tonumber(node.x), tonumber(node.z), tonumber(node.y));
    if (connector_cost + 1e-6 < direct) then
        return nil, role .. ' connector cost is below its certified direct distance';
    end
    return {
        node_id = node_id,
        connector_cost = connector_cost,
        connector_certified = true,
        exact_node = false,
        x = tonumber(candidate.x), z = tonumber(candidate.z), y = tonumber(candidate.y),
        input = candidate,
    };
end

local function normalize_route_candidates(graph, candidates, role)
    if (type(candidates) ~= 'table' or #candidates == 0) then
        return nil, role .. ' candidates must be a nonempty array';
    end
    local best_by_node = {};
    for index, candidate in ipairs(candidates) do
        local normalized, candidate_error = normalize_route_candidate(
            graph, candidate, role .. ' candidate ' .. index);
        if (normalized == nil) then return nil, candidate_error; end
        local prior = best_by_node[normalized.node_id];
        if (prior == nil or normalized.connector_cost < prior.connector_cost) then
            best_by_node[normalized.node_id] = normalized;
        end
    end
    local result = {};
    for _, candidate in pairs(best_by_node) do result[#result + 1] = candidate; end
    table.sort(result, function(a, b)
        if (a.node_id ~= b.node_id) then return a.node_id < b.node_id; end
        return a.connector_cost < b.connector_cost;
    end);
    return result;
end

local function reconstruct_v2(search)
    local ws = search._workspace;
    local state = tonumber(ws.parent[search._virtual_goal]);
    if (state < 0) then return nil, 'AXWG v2 goal has no parent state'; end
    local reverse_states = {};
    for _ = 1, ws.state_count + 1 do
        reverse_states[#reverse_states + 1] = state;
        local parent = tonumber(ws.parent[state]);
        if (parent < 0) then break; end
        state = parent;
    end
    if (tonumber(ws.parent[reverse_states[#reverse_states]]) >= 0) then
        return nil, 'AXWG v2 parent chain contains a cycle';
    end
    local root_state = reverse_states[#reverse_states];
    if (root_state < search.graph.edge_count or root_state >= search._virtual_goal) then
        return nil, 'AXWG v2 parent chain did not end at a pseudo start';
    end

    local route = { edge_ids = {}, portal_ids = {} };
    local nodes = {};
    local root_node = root_state - search.graph.edge_count;
    nodes[1], route[1] = root_node, root_node;
    for i = #reverse_states - 1, 1, -1 do
        local edge_id = reverse_states[i];
        if (edge_id >= search.graph.edge_count) then
            return nil, 'AXWG v2 parent chain contains an interior pseudo state';
        end
        local edge = search.graph._edges[edge_id];
        route.edge_ids[#route.edge_ids + 1] = edge_id;
        route.portal_ids[#route.portal_ids + 1] = tonumber(edge.portal_id);
        local node_id = tonumber(edge.to);
        nodes[#nodes + 1], route[#route + 1] = node_id, node_id;
    end
    route.nodes = nodes;
    local start = search._start_by_state[root_state];
    route.start_candidate = start.input or start;
    route.goal_candidate = search._selected_goal.input or search._selected_goal;
    route._start_connector = start;
    route._goal_connector = search._selected_goal;
    route.total_cost = tonumber(ws.score[search._virtual_goal]);
    return route;
end

function SearchV2:step(max_expansions)
    max_expansions = tonumber(max_expansions);
    if (max_expansions == nil or max_expansions < 1 or max_expansions % 1 ~= 0) then
        return nil, nil, 'max_expansions must be a positive integer';
    end
    if (self.graph._search_serial ~= self._serial) then
        return nil, nil, 'search was superseded by a newer graph search';
    end
    if (self._terminal ~= nil) then
        return self._terminal, self._route, self._reason;
    end

    local graph, ws, generation = self.graph, self._workspace, self._generation;
    local used = 0;
    while used < max_expansions and self._heap_size > 0 do
        local current = v2_heap_pop(self);
        if (ws.closed[current] ~= generation) then
            ws.closed[current] = generation;
            used, self.expansions = used + 1, self.expansions + 1;
            if (current == self._virtual_goal) then
                local route, route_error = reconstruct_v2(self);
                if (route == nil) then
                    self._terminal, self._reason = 'no-path', route_error;
                else
                    self._terminal, self._route = 'ready', route;
                end
                return self._terminal, self._route, self._reason;
            end

            local current_node = v2_state_node(self, current);
            local goal = self._goal_by_node[current_node];
            if (goal ~= nil) then
                local goal_score = tonumber(ws.score[current])
                    + v2_goal_cost(self, current, current_node, goal.connector_cost);
                if (ws.stamp[self._virtual_goal] ~= generation
                        or goal_score < tonumber(ws.score[self._virtual_goal])) then
                    if (ws.stamp[self._virtual_goal] ~= generation) then
                        ws.stamp[self._virtual_goal] = generation;
                        ws.heap_position[self._virtual_goal] = -1;
                    end
                    ws.score[self._virtual_goal] = goal_score;
                    ws.parent[self._virtual_goal] = current;
                    ws.parent_edge[self._virtual_goal] = -1;
                    self._selected_goal = goal;
                    v2_heap_set(self, self._virtual_goal, goal_score);
                end
            end

            local node = graph._nodes[current_node];
            local first = tonumber(node.first_edge);
            for edge_id = first, first + tonumber(node.edge_count) - 1 do
                local next_state = edge_id;
                if (ws.closed[next_state] ~= generation) then
                    local candidate = tonumber(ws.score[current])
                        + v2_transition_cost(self, current, edge_id);
                    if (ws.stamp[next_state] ~= generation
                            or candidate < tonumber(ws.score[next_state])) then
                        if (ws.stamp[next_state] ~= generation) then
                            ws.stamp[next_state] = generation;
                            ws.heap_position[next_state] = -1;
                        end
                        ws.score[next_state] = candidate;
                        ws.parent[next_state] = current;
                        ws.parent_edge[next_state] = edge_id;
                        v2_heap_set(self, next_state,
                            candidate + v2_heuristic(self, next_state));
                    end
                end
            end
        end
    end
    if (self._heap_size == 0) then
        self._terminal, self._reason = 'no-path', 'directed graph has no route';
        return self._terminal, nil, self._reason;
    end
    return 'pending';
end

function Graph:begin_route(start_candidates, goal_candidates)
    if (self.version ~= 2) then
        return nil, 'certified portal routing requires AXWG v2';
    end
    local starts, start_error = normalize_route_candidates(self, start_candidates, 'start');
    if (starts == nil) then return nil, start_error; end
    local goals, goal_error = normalize_route_candidates(self, goal_candidates, 'goal');
    if (goals == nil) then return nil, goal_error; end

    local compatible_components = {};
    for _, goal in ipairs(goals) do
        compatible_components[tonumber(self._nodes[goal.node_id].component_id)] = true;
    end
    local compatible_starts = {};
    for _, start in ipairs(starts) do
        if (compatible_components[tonumber(self._nodes[start.node_id].component_id)]) then
            compatible_starts[#compatible_starts + 1] = start;
        end
    end

    local ws = workspace_v2(self);
    ws.generation = ws.generation + 1;
    if (ws.generation >= 0xFFFFFFFF) then
        ffi.fill(ws.stamp, ffi.sizeof('uint32_t') * ws.state_count);
        ffi.fill(ws.closed, ffi.sizeof('uint32_t') * ws.state_count);
        ws.generation = 1;
    end
    self._search_serial = (self._search_serial or 0) + 1;
    local search = setmetatable({
        graph = self,
        expansions = 0,
        _workspace = ws,
        _generation = ws.generation,
        _serial = self._search_serial,
        _heap_size = 0,
        _virtual_goal = self.edge_count + self.node_count,
        _start_by_state = {},
        _goals = goals,
        _goal_by_node = {},
    }, SearchV2);

    for _, goal in ipairs(goals) do
        local prior = search._goal_by_node[goal.node_id];
        if (prior == nil or goal.connector_cost < prior.connector_cost) then
            search._goal_by_node[goal.node_id] = goal;
        end
    end
    if (#compatible_starts == 0) then
        search._terminal, search._reason =
            'no-path', 'start and goal candidates are in different components';
        return search;
    end

    local generation = ws.generation;
    for _, start in ipairs(compatible_starts) do
        local state = self.edge_count + start.node_id;
        if (ws.stamp[state] ~= generation
                or start.connector_cost < tonumber(ws.score[state])) then
            ws.stamp[state] = generation;
            ws.closed[state] = 0;
            ws.score[state] = start.connector_cost;
            ws.parent[state] = -1;
            ws.parent_edge[state] = -1;
            ws.heap_position[state] = -1;
            search._start_by_state[state] = start;
            v2_heap_set(search, state,
                start.connector_cost + v2_heuristic(search, state));
        end
    end
    return search;
end

local function funnel_point(point, role)
    if (type(point) ~= 'table' or point.connector_certified ~= true) then
        return nil, role .. ' connector is not independently certified';
    end
    if (not finite(point.x) or not finite(point.z) or not finite(point.y)) then
        return nil, role .. ' connector requires finite x,z,y';
    end
    return {
        x = tonumber(point.x), z = tonumber(point.z), y = tonumber(point.y),
        connector_certified = true,
        kind = role,
    };
end

local function area2(a, b, c)
    -- Match Detour's triarea2 sign convention exactly: cross(c-a, b-a), not the
    -- conventional cross(b-a, c-a). The funnel inequalities below are Detour's.
    return (c.x - a.x) * (b.z - a.z) - (b.x - a.x) * (c.z - a.z);
end

local function same_xz(a, b)
    local dx, dz = a.x - b.x, a.z - b.z;
    return dx * dx + dz * dz <= 1e-12;
end

local function copy_funnel_endpoint(endpoint)
    local copy = {};
    for key, value in pairs(endpoint) do copy[key] = value; end
    return copy;
end

local function append_funnel_corner(corners, endpoint)
    if (#corners == 0 or not same_xz(corners[#corners], endpoint)) then
        corners[#corners + 1] = copy_funnel_endpoint(endpoint);
    end
end

local function pull_funnel(channel, start_point, goal_point)
    local corners = { copy_funnel_endpoint(start_point) };
    local apex = start_point;
    local left, right = start_point, start_point;
    local apex_index, left_index, right_index = 0, 0, 0;
    local i = 1;
    local last = #channel + 1;
    local epsilon = 1e-10;
    while i <= last do
        local new_left, new_right;
        if (i == last) then
            new_left, new_right = goal_point, goal_point;
        else
            new_left, new_right = channel[i].left, channel[i].right;
        end
        local restarted = false;

        if (area2(apex, right, new_right) <= epsilon) then
            if (same_xz(apex, right) or area2(apex, left, new_right) > epsilon) then
                right, right_index = new_right, i;
            else
                append_funnel_corner(corners, left);
                apex, apex_index = left, left_index;
                left, right = apex, apex;
                left_index, right_index = apex_index, apex_index;
                i, restarted = apex_index + 1, true;
            end
        end

        if (not restarted and area2(apex, left, new_left) >= -epsilon) then
            if (same_xz(apex, left) or area2(apex, right, new_left) < -epsilon) then
                left, left_index = new_left, i;
            else
                append_funnel_corner(corners, right);
                apex, apex_index = right, right_index;
                left, right = apex, apex;
                left_index, right_index = apex_index, apex_index;
                i, restarted = apex_index + 1, true;
            end
        end

        if (not restarted) then i = i + 1; end
    end
    append_funnel_corner(corners, goal_point);
    return corners;
end

local function cross2(ax, az, bx, bz)
    return ax * bz - az * bx;
end

local function segment_portal_intersection(a, b, left, right, minimum_t)
    local rx, rz = b.x - a.x, b.z - a.z;
    local sx, sz = right.x - left.x, right.z - left.z;
    local qx, qz = left.x - a.x, left.z - a.z;
    local denominator = cross2(rx, rz, sx, sz);
    local epsilon = 1e-8;
    if (math.abs(denominator) > epsilon) then
        local t = cross2(qx, qz, sx, sz) / denominator;
        local u = cross2(qx, qz, rx, rz) / denominator;
        if (t >= minimum_t - epsilon and t >= -epsilon and t <= 1 + epsilon
                and u >= -epsilon and u <= 1 + epsilon) then
            return math.max(0, math.min(1, t)), math.max(0, math.min(1, u));
        end
        return nil;
    end

    if (math.abs(cross2(qx, qz, rx, rz)) > epsilon) then return nil; end
    local length_sq = rx * rx + rz * rz;
    local portal_len_sq = sx * sx + sz * sz;
    if (length_sq <= 1e-12 or portal_len_sq <= 1e-12) then return nil; end
    local t0 = (qx * rx + qz * rz) / length_sq;
    local t1 = ((right.x - a.x) * rx + (right.z - a.z) * rz) / length_sq;
    local lo = math.max(math.min(t0, t1), minimum_t, 0);
    local hi = math.min(math.max(t0, t1), 1);
    if (lo > hi + epsilon) then return nil; end
    if (hi - lo > epsilon) then
        local endpoint_t, endpoint_u, endpoint_count;
        endpoint_count = 0;
        local function note_endpoint(point, t)
            if (t + epsilon < minimum_t) then return; end
            if (same_xz(point, left)) then
                endpoint_t, endpoint_u, endpoint_count = t, 0, endpoint_count + 1;
            elseif (same_xz(point, right)) then
                endpoint_t, endpoint_u, endpoint_count = t, 1, endpoint_count + 1;
            end
        end
        note_endpoint(a, 0);
        note_endpoint(b, 1);
        if (endpoint_count == 1) then
            -- The pulled polyline has an explicit turn at one certified doorway end.
            -- Anchor the transition to that unique corner; the XZ path remains unchanged
            -- and both owner heights are defined at the serialized endpoint.
            return endpoint_t, endpoint_u;
        end
        -- A pulled segment lying along a doorway for a nonzero interval has infinitely
        -- many possible crossings. Choosing one would invent the surface-transition
        -- point and owner heights. A single shared endpoint, however, is unambiguous.
        return nil, nil, ('ambiguous collinear portal crossing segment=(%.6f,%.6f)'
                .. '->(%.6f,%.6f) portal=(%.6f,%.6f)->(%.6f,%.6f)'):format(
            a.x, a.z, b.x, b.z, left.x, left.z, right.x, right.z);
    end
    local t = math.max(0, math.min(1, (lo + hi) * 0.5));
    local x, z = a.x + rx * t, a.z + rz * t;
    local u = ((x - left.x) * sx + (z - left.z) * sz) / portal_len_sq;
    return t, math.max(0, math.min(1, u));
end

local function same_xyz(a, b)
    local dx, dz, dy = a.x - b.x, a.z - b.z, a.y - b.y;
    return dx * dx + dz * dz + dy * dy <= 1e-10;
end

local function funnel_segments(corners)
    local segments = {};
    for index = 1, #corners - 1 do
        local a, b = corners[index], corners[index + 1];
        local dx, dz = b.x - a.x, b.z - a.z;
        local length = math.sqrt(dx * dx + dz * dz);
        if (length <= 1e-8) then
            return nil, ('AXWG funnel produced collapsed segment %d'):format(index);
        end
        segments[#segments + 1] = {
            index = index, from = a, to = b, length = length,
        };
    end
    return segments;
end

function Graph:funnel(route, start_point, goal_point)
    if (self.version ~= 2) then return nil, 'certified portal funnel requires AXWG v2'; end
    local start, start_error = funnel_point(start_point, 'start');
    if (start == nil) then return nil, start_error; end
    local goal, goal_error = funnel_point(goal_point, 'goal');
    if (goal == nil) then return nil, goal_error; end
    if (type(route) ~= 'table' or type(route.edge_ids) ~= 'table'
            or type(route.portal_ids) ~= 'table'
            or #route < 1 or #route.edge_ids ~= #route - 1
            or #route.portal_ids ~= #route.edge_ids) then
        return nil, 'malformed AXWG v2 route corridor';
    end

    local channel = {};
    for path_index = 1, #route.edge_ids do
        local from, to = tonumber(route[path_index]), tonumber(route[path_index + 1]);
        local edge_id = tonumber(route.edge_ids[path_index]);
        local portal_id = tonumber(route.portal_ids[path_index]);
        if (edge_id == nil or edge_id % 1 ~= 0
                or edge_id < 0 or edge_id >= self.edge_count
                or portal_id == nil or portal_id % 1 ~= 0
                or portal_id < 0 or portal_id >= self.portal_count) then
            return nil, ('malformed AXWG portal or edge at path index %d'):format(
                path_index);
        end
        local edge = self._edges[edge_id];
        if (tonumber(self._edge_from[edge_id]) ~= from or tonumber(edge.to) ~= to
                or tonumber(edge.portal_id) ~= portal_id) then
            return nil, ('AXWG route corridor disagrees at path index %d'):format(
                path_index);
        end
        local portal, portal_error = self:portal(portal_id, from);
        if (portal == nil or portal.node_to ~= to) then
            return nil, portal_error or ('AXWG portal %d does not bind route'):format(
                portal_id);
        end
        portal.path_index = path_index;
        portal.edge_id = edge_id;
        portal.left.portal_id, portal.right.portal_id = portal_id, portal_id;
        portal.left.edge_id, portal.right.edge_id = edge_id, edge_id;
        portal.left.path_index, portal.right.path_index = path_index, path_index;
        portal.left.side, portal.right.side = 'left', 'right';
        channel[#channel + 1] = portal;
    end

    local start_connector = route._start_connector;
    local goal_connector = route._goal_connector;
    if (type(start_connector) ~= 'table' or type(goal_connector) ~= 'table'
            or start_connector.node_id ~= tonumber(route[1])
            or goal_connector.node_id ~= tonumber(route[#route])) then
        return nil, 'AXWG route is missing its certified connector ownership';
    end
    if (not same_xyz(start, start_connector)
            or not same_xyz(goal, goal_connector)) then
        return nil, 'funnel endpoint does not match its certified route connector';
    end
    local start_node = self._nodes[tonumber(route[1])];
    local goal_node = self._nodes[tonumber(route[#route])];
    local start_anchor = {
        x = tonumber(start_node.x), z = tonumber(start_node.z), y = tonumber(start_node.y),
        connector_certified = true, kind = 'graph-start',
    };
    local goal_anchor = {
        x = tonumber(goal_node.x), z = tonumber(goal_node.z), y = tonumber(goal_node.y),
        connector_certified = true, kind = 'graph-goal',
    };

    local graph_corners = pull_funnel(channel, start_anchor, goal_anchor);
    local graph_segments, graph_segment_error = funnel_segments(graph_corners);
    if (graph_segments == nil) then return nil, graph_segment_error; end

    local crossings = {};
    local segment_index, minimum_t = 1, 0;
    for portal_index, portal in ipairs(channel) do
        local found_t, found_u, found_segment;
        for index = segment_index, #graph_segments do
            local lower_t = index == segment_index and minimum_t or 0;
            local t, u, intersection_error = segment_portal_intersection(
                graph_segments[index].from, graph_segments[index].to,
                portal.left, portal.right, lower_t);
            if (intersection_error ~= nil) then
                return nil, ('AXWG funnel has ambiguous portal %d crossing: %s'):format(
                    portal.portal_id, intersection_error);
            end
            if (t ~= nil) then
                found_t, found_u, found_segment = t, u, index;
                break;
            end
        end
        if (found_segment == nil) then
            return nil, ('AXWG funnel did not cross certified portal %d'):format(
                portal.portal_id);
        end
        local segment = graph_segments[found_segment];
        local x = segment.from.x + (segment.to.x - segment.from.x) * found_t;
        local z = segment.from.z + (segment.to.z - segment.from.z) * found_t;
        crossings[#crossings + 1] = {
            portal_id = portal.portal_id,
            edge_id = portal.edge_id,
            path_index = portal.path_index,
            segment_index = found_segment,
            x = x, z = z,
            y_from = portal.left.y_from
                + (portal.right.y_from - portal.left.y_from) * found_u,
            y_to = portal.left.y_to
                + (portal.right.y_to - portal.left.y_to) * found_u,
            portal_parameter = found_u,
        };
        segment_index, minimum_t = found_segment, found_t;
    end

    local corners = {};
    append_funnel_corner(corners, start);
    append_funnel_corner(corners, start_anchor);
    local connector_segment_count = #corners - 1;
    for _, corner in ipairs(graph_corners) do append_funnel_corner(corners, corner); end
    append_funnel_corner(corners, goal_anchor);
    append_funnel_corner(corners, goal);
    local segments, segment_error = funnel_segments(corners);
    if (segments == nil) then return nil, segment_error; end
    for _, crossing in ipairs(crossings) do
        crossing.segment_index = crossing.segment_index + connector_segment_count;
    end

    return {
        route = route,
        start = start,
        goal = goal,
        corners = corners,
        crossings = crossings,
        segments = segments,
        graph_corners = graph_corners,
        start_anchor = start_anchor,
        goal_anchor = goal_anchor,
    };
end

local function load_v2(file_size, storage, expected_zone, expected_source_crc,
        checkpoint, crc_chunk_size)
    if (file_size < 80) then return nil, 'AXWG v2 file is shorter than its header'; end
    local header = ffi.cast('const AxwgHeaderV2*', storage);
    if (tonumber(header.version) ~= 2 or tonumber(header.header_size) ~= 80) then
        return nil, 'unsupported AXWG v2 version or header size';
    end
    if (tonumber(header.edge_record_size) ~= 20) then
        return nil, 'unsupported AXWG v2 edge record size';
    end
    if (tonumber(header.portal_record_size) ~= 48) then
        return nil, 'unsupported AXWG v2 portal record size';
    end
    if (tonumber(header.reserved) ~= 0) then
        return nil, 'AXWG v2 header reserved field must be zero';
    end
    if (tonumber(header.endian_tag) ~= 0x01020304) then
        return nil, 'AXWG endian tag mismatch';
    end
    local flags = tonumber(header.flags);
    local required_flags = bit.bor(
        FLAG_DIRECTED, FLAG_Y_DOWN, FLAG_GRID,
        FLAG_HAS_PORTALS, FLAG_SAFE_PORTAL_INTERVALS);
    if (bit.band(flags, FLAG_DIRECTED) == 0) then
        return nil, 'AXWG DIRECTED flag is required';
    end
    if (bit.band(flags, FLAG_Y_DOWN) == 0) then
        return nil, 'AXWG Y_DOWN flag is required';
    end
    if (bit.band(flags, FLAG_GRID) == 0) then
        return nil, 'AXWG GRID flag is required';
    end
    if (bit.band(flags, FLAG_HAS_PORTALS) == 0) then
        return nil, 'AXWG HAS_PORTALS flag is required';
    end
    if (bit.band(flags, FLAG_SAFE_PORTAL_INTERVALS) == 0) then
        return nil, 'AXWG SAFE_PORTAL_INTERVALS flag is required';
    end
    if (bit.band(flags, bit.bnot(0x7F)) ~= 0) then
        return nil, 'AXWG v2 contains unknown header flags';
    end
    if (bit.band(flags, bit.bor(FLAG_CAPSULE_VERIFIED, FLAG_HAS_DROPS)) ~= 0
            or flags ~= required_flags) then
        return nil, 'AXWG v2 revision 3 contains unsupported header flags';
    end
    local zone_id = tonumber(header.zone_id);
    if (expected_zone ~= nil and zone_id ~= tonumber(expected_zone)) then
        return nil, ('AXWG zone mismatch: expected %s, got %d'):format(
            tostring(expected_zone), zone_id);
    end
    if (tonumber(header.file_size) ~= file_size) then
        return nil, 'AXWG file-size field mismatch';
    end
    local stored_crc = tonumber(header.payload_crc32);
    local actual_crc = crc32(
        storage, 80, file_size - 80, checkpoint, crc_chunk_size);
    if (stored_crc ~= actual_crc) then
        return nil, ('AXWG CRC mismatch: expected %u, got %u'):format(
            stored_crc, actual_crc);
    end

    local node_count = tonumber(header.node_count);
    local edge_count = tonumber(header.edge_count);
    local portal_count = tonumber(header.portal_count);
    local component_count = tonumber(header.component_count);
    local bucket_count = tonumber(header.grid_bucket_count);
    local entry_count = tonumber(header.grid_entry_count);
    if (node_count < 1 or portal_count < 1 or component_count < 1) then
        return nil, 'AXWG v2 node, portal, and component counts must be positive';
    end
    if (entry_count ~= node_count) then
        return nil, 'AXWG v2 grid must contain every node exactly once';
    end

    local policy_part, part_error = section(
        file_size, header.policy_offset, 1, 64, 'policy section');
    if (policy_part == nil) then return nil, part_error; end
    local grid_part; grid_part, part_error = section(
        file_size, header.grid_offset, 1, 32, 'grid section');
    if (grid_part == nil) then return nil, part_error; end
    local nodes_part; nodes_part, part_error = section(
        file_size, header.nodes_offset, node_count, 32, 'node section');
    if (nodes_part == nil) then return nil, part_error; end
    local edges_part; edges_part, part_error = section(
        file_size, header.edges_offset, edge_count, 20, 'edge section');
    if (edges_part == nil) then return nil, part_error; end
    local portals_part; portals_part, part_error = section(
        file_size, header.portals_offset, portal_count, 48, 'portal section');
    if (portals_part == nil) then return nil, part_error; end

    local policy = ffi.cast('const AxwgPolicyV2*', storage + tonumber(header.policy_offset));
    if (tonumber(policy.builder_revision) ~= 3) then
        return nil, 'unsupported AXWG v2 builder revision';
    end
    if (tonumber(policy.policy_flags) ~= 1) then
        return nil, 'unsupported AXWG v2 policy flags';
    end
    if (not finite(policy.agent_radius) or tonumber(policy.agent_radius) <= 0
            or not finite(policy.agent_height) or tonumber(policy.agent_height) <= 0
            or not finite(policy.support_sample_step)
                or tonumber(policy.support_sample_step) <= 0
            or not finite(policy.support_smooth_window)
                or tonumber(policy.support_smooth_window) <= 0
            or not finite(policy.max_up_grade) or tonumber(policy.max_up_grade) < 0
            or not finite(policy.max_continuous_down_grade)
                or tonumber(policy.max_continuous_down_grade) < 0
            or not finite(policy.max_step_up) or tonumber(policy.max_step_up) < 0
            or not finite(policy.max_step_down) or tonumber(policy.max_step_down) < 0
            or not finite(policy.max_edge_run) or tonumber(policy.max_edge_run) <= 0
            or not finite(policy.grid_cell_size) or tonumber(policy.grid_cell_size) <= 0) then
        return nil, 'AXWG v2 policy contains invalid dimensions';
    end
    if (not finite(policy.min_safe_span) or tonumber(policy.min_safe_span) <= 0) then
        return nil, 'AXWG v2 policy has an invalid safe-span floor';
    end
    if (not finite(policy.max_drop) or tonumber(policy.max_drop) ~= 0) then
        return nil, 'AXWG v2 revision 3 policy must disable drops';
    end
    local policy_epsilon = 1e-5;
    if (tonumber(policy.agent_radius) + policy_epsilon < V2_MIN_AGENT_RADIUS) then
        return nil, 'AXWG v2 certified agent radius is below the runtime minimum';
    end
    if (tonumber(policy.agent_height) + policy_epsilon < V2_MIN_AGENT_HEIGHT) then
        return nil, 'AXWG v2 certified agent height is below the runtime minimum';
    end
    if (tonumber(policy.max_up_grade) > V2_MAX_UP_GRADE + policy_epsilon) then
        return nil, 'AXWG v2 climb grade is above the reviewed runtime maximum';
    end
    if (tonumber(policy.max_continuous_down_grade)
            > V2_MAX_DOWN_GRADE + policy_epsilon) then
        return nil, 'AXWG v2 descent grade is above the reviewed runtime maximum';
    end
    if (tonumber(policy.max_step_up) > V2_MAX_STEP_UP + policy_epsilon) then
        return nil, 'AXWG v2 step-up policy is above the reviewed runtime maximum';
    end
    if (tonumber(policy.max_step_down) > V2_MAX_STEP_DOWN + policy_epsilon) then
        return nil, 'AXWG v2 step-down policy is above the reviewed runtime maximum';
    end
    if (tonumber(policy.min_safe_span) + policy_epsilon < V2_MIN_SAFE_SPAN) then
        return nil, 'AXWG v2 safe-span floor is below the reviewed runtime minimum';
    end
    if (tonumber(policy.weld_tolerance_mm) ~= V2_WELD_TOLERANCE_MM) then
        return nil, 'AXWG v2 weld tolerance is not the reviewed revision-3 value';
    end
    local source_crc = tonumber(policy.source_obj_crc32);
    if (source_crc == 0) then
        return nil, 'AXWG v2 source OBJ CRC provenance is missing';
    end
    local expected_crc = tonumber(expected_source_crc);
    if (expected_source_crc ~= nil
            and (not finite(expected_crc) or expected_crc < 0
                or expected_crc > 0xFFFFFFFF or expected_crc % 1 ~= 0)) then
        return nil, 'expected source OBJ CRC must be a uint32';
    end
    if (expected_crc ~= nil and source_crc ~= expected_crc) then
        return nil, ('AXWG v2 source OBJ CRC mismatch: expected %u, got %u'):format(
            expected_crc, source_crc);
    end
    local nodes = ffi.cast('const AxwgNodeV1*', storage + tonumber(header.nodes_offset));
    local edges = ffi.cast('const AxwgEdgeV2*', storage + tonumber(header.edges_offset));
    local portals = ffi.cast('const AxwgPortalV2*', storage + tonumber(header.portals_offset));
    local grid = ffi.cast('const AxwgGridV1*', storage + tonumber(header.grid_offset));
    if (tonumber(grid.reserved) ~= 0) then
        return nil, 'AXWG v2 grid reserved field must be zero';
    end
    if (not finite(grid.min_x) or not finite(grid.min_z)
            or not finite(grid.cell_size) or tonumber(grid.cell_size) <= 0
            or tonumber(grid.width) < 1 or tonumber(grid.height) < 1
            or tonumber(grid.width) * tonumber(grid.height) ~= bucket_count) then
        return nil, 'AXWG v2 grid dimensions are invalid';
    end
    if (not finite(policy.grid_cell_size)
            or math.abs(tonumber(policy.grid_cell_size) - tonumber(grid.cell_size)) > 0.0001) then
        return nil, 'AXWG v2 policy and spatial-grid cell sizes disagree';
    end
    local buckets_part; buckets_part, part_error = section(
        file_size, grid.buckets_offset, bucket_count, 8, 'grid bucket section');
    if (buckets_part == nil) then return nil, part_error; end
    local entries_part; entries_part, part_error = section(
        file_size, grid.entries_offset, entry_count, 4, 'grid entry section');
    if (entries_part == nil) then return nil, part_error; end
    local no_overlap, overlap_error = sections_do_not_overlap({
        policy_part, grid_part, nodes_part, edges_part, portals_part,
        buckets_part, entries_part,
    });
    if (no_overlap == nil) then return nil, overlap_error; end

    local edge_from = ffi.new('uint32_t[?]', edge_count);
    local edge_cursor = 0;
    for from = 0, node_count - 1 do
        local node = nodes[from];
        if (not finite(node.x) or not finite(node.z) or not finite(node.y)
                or not finite(node.clearance) or tonumber(node.clearance) < 0) then
            return nil, ('AXWG node %d contains invalid geometry'):format(from);
        end
        if (tonumber(node.flags) ~= 0) then
            return nil, ('AXWG node %d flags are unknown for revision 3'):format(from);
        end
        if (tonumber(node.component_id) >= component_count) then
            return nil, ('AXWG node %d has invalid component id'):format(from);
        end
        local first = tonumber(node.first_edge);
        local count = tonumber(node.edge_count);
        if (first ~= edge_cursor or first + count > edge_count) then
            return nil, ('AXWG node %d has invalid CSR range'):format(from);
        end
        for edge_index = first, first + count - 1 do edge_from[edge_index] = from; end
        edge_cursor = edge_cursor + count;
        if (checkpoint ~= nil) then checkpoint(false); end
    end
    if (edge_cursor ~= edge_count) then return nil, 'AXWG CSR does not cover every edge'; end

    local minimum_safe_span_cm = math.max(
        0, math.ceil(tonumber(policy.min_safe_span) * 100 - 0.001));
    local all_headroom = portal_count > 0;
    for portal_id = 0, portal_count - 1 do
        local portal = portals[portal_id];
        local node_a, node_b = tonumber(portal.node_a), tonumber(portal.node_b);
        if (node_a < 0 or node_b >= node_count or node_a >= node_b) then
            return nil, ('AXWG portal %d must have valid node_a < node_b'):format(
                portal_id);
        end
        if (not finite(portal.left_x) or not finite(portal.left_z)
                or not finite(portal.right_x) or not finite(portal.right_z)) then
            return nil, ('AXWG portal %d has non-finite endpoints'):format(portal_id);
        end
        if (not finite(portal.left_y_a) or not finite(portal.left_y_b)
                or not finite(portal.right_y_a) or not finite(portal.right_y_b)) then
            return nil, ('AXWG portal %d has a non-finite owner height'):format(portal_id);
        end
        local portal_dx = tonumber(portal.right_x) - tonumber(portal.left_x);
        local portal_dz = tonumber(portal.right_z) - tonumber(portal.left_z);
        if (portal_dx * portal_dx + portal_dz * portal_dz <= 1e-12) then
            return nil, ('AXWG portal %d has a collapsed interval'):format(portal_id);
        end
        local node_dx = tonumber(nodes[node_b].x) - tonumber(nodes[node_a].x);
        local node_dz = tonumber(nodes[node_b].z) - tonumber(nodes[node_a].z);
        local orientation = node_dx * portal_dz - node_dz * portal_dx;
        if (not finite(orientation) or orientation >= -1e-8) then
            return nil, ('AXWG portal %d has invalid canonical orientation'):format(
                portal_id);
        end
        if (tonumber(portal.capacity_cm) < minimum_safe_span_cm) then
            return nil, ('AXWG portal %d is below the serialized safe-span floor'):format(
                portal_id);
        end
        local interval_cm = math.floor(
            math.sqrt(portal_dx * portal_dx + portal_dz * portal_dz) * 100 + 0.001);
        if (tonumber(portal.capacity_cm) > interval_cm) then
            return nil, ('AXWG portal %d capacity exceeds its interval'):format(portal_id);
        end
        if (tonumber(portal.reserved) ~= 0) then
            return nil, ('AXWG portal %d reserved field must be zero'):format(portal_id);
        end
        local portal_flags = tonumber(portal.flags);
        if (bit.band(portal_flags, bit.bnot(0x0F)) ~= 0) then
            return nil, ('AXWG portal %d has unknown portal flags'):format(portal_id);
        end
        if (bit.band(portal_flags, PORTAL_HEADROOM_CHECKED) ~= 0) then
            return nil, ('AXWG portal %d falsely claims HEADROOM_CHECKED'):format(portal_id);
        end
        if (bit.band(portal_flags, PORTAL_FULL_CAPSULE_CHECKED) ~= 0) then
            return nil, ('AXWG portal %d falsely claims FULL_CAPSULE_CHECKED'):format(
                portal_id);
        end
        if (bit.band(portal_flags, PORTAL_SAFE_INTERVAL_CERTIFIED) == 0) then
            return nil, ('AXWG portal %d is missing SAFE_INTERVAL_CERTIFIED'):format(
                portal_id);
        end
        if (bit.band(portal_flags, PORTAL_WALL_ERODED) == 0) then
            return nil, ('AXWG portal %d is missing WALL_ERODED'):format(portal_id);
        end
        all_headroom = false;
        if (checkpoint ~= nil) then checkpoint(false); end
    end
    local portal_directions = ffi.new('uint8_t[?]', portal_count);
    local pair_directions = {};
    for edge_index = 0, edge_count - 1 do
        if (tonumber(edges[edge_index].reserved) ~= 0) then
            return nil, ('AXWG edge %d reserved field must be zero'):format(edge_index);
        end
        local edge_flags = tonumber(edges[edge_index].flags);
        if (bit.band(edge_flags, EDGE_WALK) == 0) then
            return nil, ('AXWG edge %d is missing the WALK flag'):format(edge_index);
        end
        if (bit.band(edge_flags, bit.bnot(0x03)) ~= 0) then
            return nil, ('AXWG edge %d has unknown edge flags'):format(edge_index);
        end
        local edge = edges[edge_index];
        local from, to = tonumber(edge_from[edge_index]), tonumber(edge.to);
        local portal_id = tonumber(edge.portal_id);
        if (to < 0 or to >= node_count or portal_id < 0 or portal_id >= portal_count) then
            return nil, ('AXWG edge %d has an invalid destination or portal ID'):format(
                edge_index);
        end
        if (tonumber(nodes[from].component_id) ~= tonumber(nodes[to].component_id)) then
            return nil, ('AXWG edge %d crosses component ids'):format(edge_index);
        end
        local dx = tonumber(nodes[to].x) - tonumber(nodes[from].x);
        local dz = tonumber(nodes[to].z) - tonumber(nodes[from].z);
        local dy = tonumber(nodes[to].y) - tonumber(nodes[from].y);
        local horizontal = math.sqrt(dx * dx + dz * dz);
        local geometric = math.sqrt(horizontal * horizontal + dy * dy);
        local cost = tonumber(edge.cost);
        if (not finite(cost) or cost <= 0 or cost + 0.001 < geometric) then
            return nil, ('AXWG edge %d cost is below geometric distance'):format(edge_index);
        end
        if (not finite(policy.max_edge_run) or tonumber(policy.max_edge_run) <= 0
                or horizontal > tonumber(policy.max_edge_run) + 0.001) then
            return nil, ('AXWG edge %d exceeds the policy maximum run'):format(edge_index);
        end
        if (math.abs(tonumber(edge.run_cm) - rounded(horizontal * 100)) > 1) then
            return nil, ('AXWG edge %d run metadata does not match its nodes'):format(
                edge_index);
        end
        if (math.abs(tonumber(edge.rise_cm) - rounded(-dy * 100)) > 1) then
            return nil, ('AXWG edge %d rise metadata does not match its nodes'):format(
                edge_index);
        end
        local step_down = bit.band(edge_flags, 0x02) ~= 0;
        if (step_down ~= (tonumber(edge.rise_cm) < 0)) then
            return nil, ('AXWG edge %d STEP_DOWN flag disagrees with quantized rise'):format(
                edge_index);
        end
        local upward_rise = -dy;
        if (upward_rise > 0
                and (horizontal <= 0
                    or upward_rise
                        > tonumber(policy.max_up_grade) * horizontal + 0.0001)) then
            return nil, ('AXWG edge %d up grade exceeds declared maximum'):format(edge_index);
        end
        if (upward_rise < 0
                and (horizontal <= 0
                    or -upward_rise
                        > tonumber(policy.max_continuous_down_grade) * horizontal
                            + 0.0001)) then
            return nil, ('AXWG edge %d down grade exceeds declared maximum'):format(
                edge_index);
        end
        local portal = portals[portal_id];
        local node_a, node_b = tonumber(portal.node_a), tonumber(portal.node_b);
        if (not ((from == node_a and to == node_b)
                or (from == node_b and to == node_a))) then
            return nil, ('AXWG edge %d portal does not bind exactly {from,to}'):format(
                edge_index);
        end
        local direction_bit = from == node_a and 1 or 2;
        local existing_directions = tonumber(portal_directions[portal_id]);
        if (bit.band(existing_directions, direction_bit) ~= 0) then
            return nil, ('AXWG edge %d duplicates a from-to-portal edge'):format(
                edge_index);
        end
        portal_directions[portal_id] = bit.bor(existing_directions, direction_bit);
        local pair_key = node_a * 4294967296 + node_b;
        pair_directions[pair_key] = bit.bor(
            pair_directions[pair_key] or 0, direction_bit);
        local function owner_step_ok(y_a, y_b)
            local y_from, y_to;
            if (from == node_a) then
                y_from, y_to = tonumber(y_a), tonumber(y_b);
            else
                y_from, y_to = tonumber(y_b), tonumber(y_a);
            end
            local rise = y_from - y_to;
            return rise <= tonumber(policy.max_step_up) + 0.0001
                and -rise <= tonumber(policy.max_step_down) + 0.0001;
        end
        if (not owner_step_ok(portal.left_y_a, portal.left_y_b)
                or not owner_step_ok(portal.right_y_a, portal.right_y_b)) then
            return nil, ('AXWG edge %d portal owner step exceeds policy'):format(edge_index);
        end
        if (checkpoint ~= nil) then checkpoint(false); end
    end
    for portal_id = 0, portal_count - 1 do
        local portal = portals[portal_id];
        local directions = tonumber(portal_directions[portal_id]);
        if (directions == 0) then
            return nil, ('AXWG portal %d is unreferenced'):format(portal_id);
        end
        local pair_key = tonumber(portal.node_a) * 4294967296 + tonumber(portal.node_b);
        local pair_mask = pair_directions[pair_key];
        if (pair_mask == 3 and directions ~= 3) then
            return nil, ('AXWG portal %d does not have a matching reverse portal edge'):format(
                portal_id);
        end
        if (pair_mask ~= 3 and directions ~= pair_mask) then
            return nil, ('AXWG portal %d has inconsistent one-way direction'):format(
                portal_id);
        end
        if (checkpoint ~= nil) then checkpoint(false); end
    end
    local buckets = ffi.cast(
        'const AxwgBucketV1*', storage + tonumber(grid.buckets_offset));
    local entries = ffi.cast(
        'const uint32_t*', storage + tonumber(grid.entries_offset));
    local seen = ffi.new('uint8_t[?]', node_count);
    local grid_cursor = 0;
    local width = tonumber(grid.width);
    local cell_size = tonumber(grid.cell_size);
    local min_x, min_z = tonumber(grid.min_x), tonumber(grid.min_z);
    for bucket_index = 0, bucket_count - 1 do
        local bucket = buckets[bucket_index];
        local first, count = tonumber(bucket.first_entry), tonumber(bucket.entry_count);
        if (first ~= grid_cursor or first + count > entry_count) then
            return nil, ('AXWG grid bucket %d has invalid CSR range'):format(bucket_index);
        end
        local expected_x = bucket_index % width;
        local expected_z = math.floor(bucket_index / width);
        for entry_index = first, first + count - 1 do
            local node_id = tonumber(entries[entry_index]);
            if (node_id < 0 or node_id >= node_count) then
                return nil, ('AXWG grid entry %d has invalid node id'):format(entry_index);
            end
            if (seen[node_id] ~= 0) then
                return nil, ('AXWG grid entry %d duplicates node %d'):format(
                    entry_index, node_id);
            end
            seen[node_id] = 1;
            local cell_x = math.floor((tonumber(nodes[node_id].x) - min_x) / cell_size);
            local cell_z = math.floor((tonumber(nodes[node_id].z) - min_z) / cell_size);
            if (cell_x ~= expected_x or cell_z ~= expected_z) then
                return nil, ('AXWG grid entry %d is in the wrong bucket'):format(entry_index);
            end
            if (checkpoint ~= nil) then checkpoint(false); end
        end
        grid_cursor = grid_cursor + count;
        if (checkpoint ~= nil) then checkpoint(false); end
    end
    if (grid_cursor ~= entry_count) then
        return nil, 'AXWG grid CSR does not cover every entry';
    end
    return setmetatable({
        _storage = storage,
        _header = header,
        _policy = policy,
        _nodes = nodes,
        _edges = edges,
        _portals = portals,
        _edge_from = edge_from,
        _portal_directions = portal_directions,
        _grid = grid,
        _buckets = buckets,
        _entries = entries,
        _all_portals_headroom_checked = all_headroom,
        version = 2,
        zone_id = zone_id,
        flags = flags,
        node_count = node_count,
        edge_count = edge_count,
        portal_count = portal_count,
        component_count = component_count,
        minimum_safe_span_cm = minimum_safe_span_cm,
        agent_radius = tonumber(policy.agent_radius),
        agent_height = tonumber(policy.agent_height),
        max_up_grade = tonumber(policy.max_up_grade),
        max_down_grade = tonumber(policy.max_continuous_down_grade),
        max_step_up = tonumber(policy.max_step_up),
        max_step_down = tonumber(policy.max_step_down),
        source_obj_crc32 = source_crc,
        builder_revision = tonumber(policy.builder_revision),
        weld_tolerance_mm = tonumber(policy.weld_tolerance_mm),
    }, Graph);
end

local function load_v1(file_size, storage, expected_zone, expected_source_crc,
        checkpoint, crc_chunk_size)
    if (file_size < 64) then return nil, 'AXWG file is shorter than its header'; end
    local header = ffi.cast('const AxwgHeaderV1*', storage);
    if (tonumber(header.version) ~= 1 or tonumber(header.header_size) ~= 64) then
        return nil, 'unsupported AXWG version or header size';
    end
    if (tonumber(header.endian_tag) ~= 0x01020304) then
        return nil, 'AXWG endian tag mismatch';
    end
    local zone_id = tonumber(header.zone_id);
    if (expected_zone ~= nil and zone_id ~= tonumber(expected_zone)) then
        return nil, ('AXWG zone mismatch: expected %s, got %d'):format(
            tostring(expected_zone), zone_id);
    end
    if (tonumber(header.file_size) ~= file_size) then
        return nil, 'AXWG file-size field mismatch';
    end

    local flags = tonumber(header.flags);
    if (bit.band(flags, FLAG_DIRECTED) == 0) then
        return nil, 'AXWG DIRECTED flag is required';
    end
    if (bit.band(flags, FLAG_Y_DOWN) == 0) then
        return nil, 'AXWG Y_DOWN flag is required';
    end
    if (bit.band(flags, FLAG_GRID) == 0) then
        return nil, 'AXWG GRID flag is required';
    end
    if (bit.band(flags, FLAG_HAS_DROPS) ~= 0) then
        return nil, 'AXWG v1 does not permit drops';
    end

    local stored_crc = tonumber(header.payload_crc32);
    local actual_crc = crc32(
        storage, 64, file_size - 64, checkpoint, crc_chunk_size);
    if (stored_crc ~= actual_crc) then
        return nil, ('AXWG CRC mismatch: expected %u, got %u'):format(
            stored_crc, actual_crc);
    end

    local node_count = tonumber(header.node_count);
    local edge_count = tonumber(header.edge_count);
    local component_count = tonumber(header.component_count);
    local bucket_count = tonumber(header.grid_bucket_count);
    local entry_count = tonumber(header.grid_entry_count);
    if (node_count < 1 or component_count < 1) then
        return nil, 'AXWG node and component counts must be positive';
    end
    if (entry_count ~= node_count) then
        return nil, 'AXWG grid must contain every node exactly once';
    end

    local policy_part, part_error = section(
        file_size, header.policy_offset, 1, 64, 'policy section');
    if (policy_part == nil) then return nil, part_error; end
    local nodes_part; nodes_part, part_error = section(
        file_size, header.nodes_offset, node_count, 32, 'node section');
    if (nodes_part == nil) then return nil, part_error; end
    local edges_part; edges_part, part_error = section(
        file_size, header.edges_offset, edge_count, 16, 'edge section');
    if (edges_part == nil) then return nil, part_error; end
    local grid_part; grid_part, part_error = section(
        file_size, header.grid_offset, 1, 32, 'grid section');
    if (grid_part == nil) then return nil, part_error; end

    local policy = ffi.cast('const AxwgPolicyV1*', storage + tonumber(header.policy_offset));
    local nodes = ffi.cast('const AxwgNodeV1*', storage + tonumber(header.nodes_offset));
    local edges = ffi.cast('const AxwgEdgeV1*', storage + tonumber(header.edges_offset));
    local grid = ffi.cast('const AxwgGridV1*', storage + tonumber(header.grid_offset));
    if (not finite(grid.cell_size) or tonumber(grid.cell_size) <= 0
            or tonumber(grid.width) < 1 or tonumber(grid.height) < 1
            or tonumber(grid.width) * tonumber(grid.height) ~= bucket_count) then
        return nil, 'AXWG grid dimensions are invalid';
    end
    if (not finite(grid.min_x) or not finite(grid.min_z)) then
        return nil, 'AXWG grid origin is invalid';
    end
    local buckets_part; buckets_part, part_error = section(
        file_size, grid.buckets_offset, bucket_count, 8, 'grid bucket section');
    if (buckets_part == nil) then return nil, part_error; end
    local entries_part; entries_part, part_error = section(
        file_size, grid.entries_offset, entry_count, 4, 'grid entry section');
    if (entries_part == nil) then return nil, part_error; end
    local no_overlap, overlap_error = sections_do_not_overlap({
        policy_part, nodes_part, edges_part, grid_part, buckets_part, entries_part,
    });
    if (no_overlap == nil) then return nil, overlap_error; end

    if (not finite(policy.agent_radius) or tonumber(policy.agent_radius) <= 0
            or not finite(policy.agent_height) or tonumber(policy.agent_height) <= 0
            or not finite(policy.support_sample_step) or tonumber(policy.support_sample_step) <= 0
            or not finite(policy.support_smooth_window) or tonumber(policy.support_smooth_window) <= 0
            or not finite(policy.max_up_grade) or tonumber(policy.max_up_grade) < 0
            or not finite(policy.max_continuous_down_grade)
                or tonumber(policy.max_continuous_down_grade) < 0
            or not finite(policy.max_step_up) or tonumber(policy.max_step_up) < 0
            or not finite(policy.max_step_down) or tonumber(policy.max_step_down) < 0
            or not finite(policy.max_drop) or tonumber(policy.max_drop) < 0
            or not finite(policy.min_clearance) or tonumber(policy.min_clearance) < 0
            or not finite(policy.max_edge_run) or tonumber(policy.max_edge_run) <= 0
            or not finite(policy.grid_cell_size) or tonumber(policy.grid_cell_size) <= 0) then
        return nil, 'AXWG policy contains invalid dimensions';
    end
    if (math.abs(tonumber(policy.grid_cell_size) - tonumber(grid.cell_size)) > 0.0001) then
        return nil, 'AXWG policy and spatial-grid cell sizes disagree';
    end
    if (tonumber(policy.max_drop) ~= 0) then
        return nil, 'AXWG v1 policy must disable drops';
    end

    local cursor = 0;
    for i = 0, node_count - 1 do
        local node = nodes[i];
        if (not finite(node.x) or not finite(node.z) or not finite(node.y)
                or not finite(node.clearance) or tonumber(node.clearance) < 0) then
            return nil, ('AXWG node %d contains non-finite or negative geometry'):format(i);
        end
        if (tonumber(node.component_id) >= component_count) then
            return nil, ('AXWG node %d has invalid component id'):format(i);
        end
        local first, count = tonumber(node.first_edge), tonumber(node.edge_count);
        if (first ~= cursor or first + count > edge_count) then
            return nil, ('AXWG node %d has invalid CSR range'):format(i);
        end
        cursor = cursor + count;
        if (checkpoint ~= nil) then checkpoint(false); end
    end
    if (cursor ~= edge_count) then return nil, 'AXWG CSR does not cover every edge'; end

    for from = 0, node_count - 1 do
        local node = nodes[from];
        local first = tonumber(node.first_edge);
        for edge_index = first, first + tonumber(node.edge_count) - 1 do
            local edge = edges[edge_index];
            local to = tonumber(edge.to);
            if (to < 0 or to >= node_count) then
                return nil, ('AXWG edge %d has invalid destination'):format(edge_index);
            end
            if (bit.band(tonumber(edge.flags), EDGE_DROP) ~= 0) then
                return nil, ('AXWG edge %d uses unsupported drops'):format(edge_index);
            end
            if (bit.band(tonumber(edge.flags), EDGE_WALK) == 0) then
                return nil, ('AXWG edge %d is missing the WALK flag'):format(edge_index);
            end
            if (tonumber(nodes[to].component_id) ~= tonumber(node.component_id)) then
                return nil, ('AXWG edge %d crosses component ids'):format(edge_index);
            end
            local dx = tonumber(nodes[to].x) - tonumber(node.x);
            local dz = tonumber(nodes[to].z) - tonumber(node.z);
            local dy = tonumber(nodes[to].y) - tonumber(node.y);
            local horizontal = math.sqrt(dx * dx + dz * dz);
            local geometric = math.sqrt(horizontal * horizontal + dy * dy);
            local cost = tonumber(edge.cost);
            if (not finite(cost) or cost <= 0 or cost + 0.001 < geometric) then
                return nil, ('AXWG edge %d cost is below geometric distance'):format(edge_index);
            end
            if (horizontal > tonumber(policy.max_edge_run) + 0.001) then
                return nil, ('AXWG edge %d exceeds the policy maximum run'):format(edge_index);
            end
            if (math.abs(tonumber(edge.run_cm) - rounded(horizontal * 100)) > 1) then
                return nil, ('AXWG edge %d run metadata does not match its nodes'):format(edge_index);
            end
            if (math.abs(tonumber(edge.rise_cm) - rounded(-dy * 100)) > 1) then
                return nil, ('AXWG edge %d rise metadata does not match its nodes'):format(edge_index);
            end
            local upward_rise = -dy;
            local grade_epsilon = 0.0001;
            if (upward_rise > 0
                    and (horizontal <= 0
                        or upward_rise > tonumber(policy.max_up_grade) * horizontal
                            + grade_epsilon)) then
                local grade = horizontal > 0 and upward_rise / horizontal or math.huge;
                return nil, ('AXWG edge %d up grade %.6f exceeds declared maximum %.6f'):format(
                    edge_index, grade, tonumber(policy.max_up_grade));
            end
            if (upward_rise < 0
                    and (horizontal <= 0
                        or -upward_rise
                            > tonumber(policy.max_continuous_down_grade) * horizontal
                                + grade_epsilon)) then
                local grade = horizontal > 0 and -upward_rise / horizontal or math.huge;
                return nil, ('AXWG edge %d down grade %.6f exceeds declared maximum %.6f'):format(
                    edge_index, grade, tonumber(policy.max_continuous_down_grade));
            end
            if (checkpoint ~= nil) then checkpoint(false); end
        end
    end

    local buckets = ffi.cast('const AxwgBucketV1*', storage + tonumber(grid.buckets_offset));
    local entries = ffi.cast('const uint32_t*', storage + tonumber(grid.entries_offset));
    local seen = ffi.new('uint8_t[?]', node_count);
    cursor = 0;
    local width = tonumber(grid.width);
    local cell_size = tonumber(grid.cell_size);
    local min_x, min_z = tonumber(grid.min_x), tonumber(grid.min_z);
    for bucket_index = 0, bucket_count - 1 do
        local bucket = buckets[bucket_index];
        local first, count = tonumber(bucket.first_entry), tonumber(bucket.entry_count);
        if (first ~= cursor or first + count > entry_count) then
            return nil, ('AXWG grid bucket %d has invalid CSR range'):format(bucket_index);
        end
        local expected_x, expected_z = bucket_index % width, math.floor(bucket_index / width);
        for entry_index = first, first + count - 1 do
            local node_id = tonumber(entries[entry_index]);
            if (node_id < 0 or node_id >= node_count) then
                return nil, ('AXWG grid entry %d has invalid node id'):format(entry_index);
            end
            if (seen[node_id] ~= 0) then
                return nil, ('AXWG grid entry %d duplicates node %d'):format(entry_index, node_id);
            end
            seen[node_id] = 1;
            local cell_x = math.floor((tonumber(nodes[node_id].x) - min_x) / cell_size);
            local cell_z = math.floor((tonumber(nodes[node_id].z) - min_z) / cell_size);
            if (cell_x ~= expected_x or cell_z ~= expected_z) then
                return nil, ('AXWG grid entry %d is in the wrong bucket'):format(entry_index);
            end
            if (checkpoint ~= nil) then checkpoint(false); end
        end
        cursor = cursor + count;
        if (checkpoint ~= nil) then checkpoint(false); end
    end
    if (cursor ~= entry_count) then return nil, 'AXWG grid CSR does not cover every entry'; end

    return setmetatable({
        _storage = storage,
        _header = header,
        _policy = policy,
        _nodes = nodes,
        _edges = edges,
        _grid = grid,
        _buckets = buckets,
        _entries = entries,
        version = 1,
        zone_id = zone_id,
        flags = flags,
        node_count = node_count,
        edge_count = edge_count,
        component_count = component_count,
        minimum_clearance_cm = math.max(
            0, math.ceil(tonumber(policy.min_clearance) * 100 - 0.001)),
    }, Graph);
end

local function positive_integer(value, default_value, name)
    if (value == nil) then return default_value; end
    value = tonumber(value);
    if (value == nil or not finite(value) or value < 1 or value % 1 ~= 0) then
        return nil, ('AXWG %s must be a positive integer'):format(name);
    end
    return value;
end

local function close_load_file(loader)
    local file = loader ~= nil and loader._file or nil;
    loader._file = nil;
    if (file ~= nil) then pcall(function() file:close(); end); end
end

local function fail_load(loader, reason)
    close_load_file(loader);
    loader._status = 'failed';
    loader._error = tostring(reason or 'AXWG load failed');
    loader._validation = nil;
    loader._storage = nil;
    return 'failed', nil, loader._error;
end

local function load_checkpoint(loader, force_clock_check)
    if (not force_clock_check) then
        loader._validation_work = loader._validation_work + 1;
        if (loader._validation_work < loader._validation_batch_size) then return; end
    end
    loader._validation_work = 0;
    if (loader._clock() >= loader._deadline) then coroutine.yield(); end
end

local function validate_loaded_storage(loader)
    local storage = loader._storage;
    local header = ffi.cast('const AxwgHeaderV1*', storage);
    if (header.magic[0] ~= 65 or header.magic[1] ~= 88
            or header.magic[2] ~= 87 or header.magic[3] ~= 71) then
        return nil, 'AXWG magic mismatch';
    end
    local checkpoint = function(force_clock_check)
        load_checkpoint(loader, force_clock_check == true);
    end;
    local version = tonumber(header.version);
    if (version == 2) then
        return load_v2(
            loader._file_size, storage,
            loader._expected_zone, loader._expected_source_crc,
            checkpoint, loader._crc_chunk_size);
    end
    if (version == 1) then
        return load_v1(
            loader._file_size, storage,
            loader._expected_zone, loader._expected_source_crc,
            checkpoint, loader._crc_chunk_size);
    end
    return nil, 'unsupported AXWG version or header size';
end

-- Starts an AXWG read without pulling the whole file into one Lua string. The caller
-- advances it with step_load; options exist so the addon can tune bounded per-frame
-- work and tests can substitute only the clock.
function M.begin_load(path, expected_zone, expected_source_crc, options)
    options = options or {};
    if (type(options) ~= 'table') then
        return nil, 'AXWG load options must be a table';
    end
    local read_chunk_size, option_error = positive_integer(
        options.read_chunk_size, DEFAULT_LOAD_READ_CHUNK_SIZE, 'read chunk size');
    if (read_chunk_size == nil) then return nil, option_error; end
    local crc_chunk_size; crc_chunk_size, option_error = positive_integer(
        options.crc_chunk_size, DEFAULT_LOAD_CRC_CHUNK_SIZE, 'CRC chunk size');
    if (crc_chunk_size == nil) then return nil, option_error; end
    local validation_batch_size; validation_batch_size, option_error = positive_integer(
        options.validation_batch_size,
        DEFAULT_LOAD_VALIDATION_BATCH_SIZE, 'validation batch size');
    if (validation_batch_size == nil) then return nil, option_error; end
    local max_file_size; max_file_size, option_error = positive_integer(
        options.max_file_size, DEFAULT_MAX_FILE_SIZE, 'maximum file size');
    if (max_file_size == nil) then return nil, option_error; end
    local clock = options.clock or os.clock;
    if (type(clock) ~= 'function') then return nil, 'AXWG load clock must be a function'; end

    local file, open_error = io.open(path, 'rb');
    if (file == nil) then return nil, open_error or 'could not open AXWG file'; end
    local seek_ok, file_size, seek_error = pcall(function()
        return file:seek('end');
    end);
    if (not seek_ok or file_size == nil) then
        pcall(function() file:close(); end);
        return nil, seek_ok and (seek_error or 'could not size AXWG file') or file_size;
    end
    local reset_ok, reset_position, reset_error = pcall(function()
        return file:seek('set', 0);
    end);
    if (not reset_ok or reset_position ~= 0) then
        pcall(function() file:close(); end);
        return nil, reset_ok and (reset_error or 'could not rewind AXWG file') or reset_position;
    end
    file_size = tonumber(file_size);
    if (file_size == nil or file_size % 1 ~= 0 or file_size < 64) then
        pcall(function() file:close(); end);
        return nil, 'AXWG file is shorter than its header';
    end
    if (file_size > max_file_size) then
        pcall(function() file:close(); end);
        return nil, ('AXWG file exceeds the configured maximum size (%d bytes)'):format(
            max_file_size);
    end

    return {
        _axwg_loader = true,
        _status = 'pending',
        _phase = 'allocate',
        _file = file,
        _file_size = file_size,
        _read_offset = 0,
        _read_chunk_size = read_chunk_size,
        _crc_chunk_size = crc_chunk_size,
        _validation_batch_size = validation_batch_size,
        _validation_work = 0,
        _clock = clock,
        _expected_zone = expected_zone,
        _expected_source_crc = expected_source_crc,
    };
end

function M.cancel_load(loader)
    if (type(loader) ~= 'table' or loader._axwg_loader ~= true) then return false; end
    if (loader._status ~= 'pending') then return false; end
    fail_load(loader, 'AXWG load canceled');
    return true;
end

function M.step_load(loader, budget_ms)
    if (type(loader) ~= 'table' or loader._axwg_loader ~= true) then
        return 'failed', nil, 'invalid AXWG loader';
    end
    if (loader._status == 'ready') then return 'ready', loader._graph; end
    if (loader._status == 'failed') then return 'failed', nil, loader._error; end

    budget_ms = tonumber(budget_ms) or DEFAULT_LOAD_BUDGET_MS;
    if ((budget_ms ~= math.huge and not finite(budget_ms)) or budget_ms <= 0) then
        return fail_load(loader, 'AXWG load budget must be positive');
    end
    loader._deadline = loader._clock() + (budget_ms / 1000);

    while (loader._status == 'pending') do
        if (loader._phase == 'allocate') then
            local allocated, storage = pcall(
                ffi.new, 'uint8_t[?]', loader._file_size);
            if (not allocated or storage == nil) then
                return fail_load(loader,
                    'could not allocate AXWG file storage: ' .. tostring(storage));
            end
            loader._storage = storage;
            loader._phase = 'read';
        elseif (loader._phase == 'read') then
            local remaining = loader._file_size - loader._read_offset;
            if (remaining <= 0) then
                close_load_file(loader);
                loader._phase = 'validate';
                loader._validation = coroutine.create(function()
                    return validate_loaded_storage(loader);
                end);
            else
                local amount = math.min(loader._read_chunk_size, remaining);
                local read_ok, chunk, read_error = pcall(function()
                    return loader._file:read(amount);
                end);
                if (not read_ok) then
                    return fail_load(loader, 'could not read AXWG file: ' .. tostring(chunk));
                end
                if (chunk == nil) then
                    return fail_load(loader, read_error or 'could not read AXWG file');
                end
                if (#chunk ~= amount) then
                    return fail_load(loader, 'AXWG file ended before its measured size');
                end
                ffi.copy(loader._storage + loader._read_offset, chunk, amount);
                loader._read_offset = loader._read_offset + amount;
                if (loader._read_offset == loader._file_size) then
                    close_load_file(loader);
                    loader._phase = 'validate';
                    loader._validation = coroutine.create(function()
                        return validate_loaded_storage(loader);
                    end);
                end
            end
        elseif (loader._phase == 'validate') then
            local resumed, graph, reason = coroutine.resume(loader._validation);
            if (not resumed) then
                return fail_load(loader, 'AXWG validation crashed: ' .. tostring(graph));
            end
            if (coroutine.status(loader._validation) == 'dead') then
                if (graph == nil) then return fail_load(loader, reason); end
                loader._status = 'ready';
                loader._graph = graph;
                loader._validation = nil;
                loader._storage = nil;
                return 'ready', graph;
            end
            return 'pending';
        else
            return fail_load(loader, 'AXWG loader entered an invalid phase');
        end

        if (loader._clock() >= loader._deadline) then return 'pending'; end
    end
    return 'pending';
end

function M.load(path, expected_zone, expected_source_crc, options)
    local loader, begin_error = M.begin_load(
        path, expected_zone, expected_source_crc, options);
    if (loader == nil) then return nil, begin_error; end
    while (true) do
        local status, graph, reason = M.step_load(loader, math.huge);
        if (status == 'ready') then return graph; end
        if (status == 'failed') then return nil, reason; end
    end
end

return M;
