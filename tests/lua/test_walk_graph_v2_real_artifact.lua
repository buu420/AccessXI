-- Deep audit of the corrected La Theine AXWG v2 artifact.
-- The production loader must accept the original bytes without normalization. This test
-- also parses the serialized records independently to audit flags, capacities, and portal
-- references before exercising real edge-state routes and their certified funnels.

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
    uint32_t portal_count; uint32_t portals_offset;
    uint16_t edge_record_size; uint16_t portal_record_size;
    uint32_t reserved;
} AuditAxwgHeaderV2;
typedef struct {
    uint32_t to; float cost; int16_t rise_cm; uint16_t run_cm;
    uint16_t flags; uint16_t reserved; uint32_t portal_id;
} AuditAxwgEdgeV2;
typedef struct {
    uint32_t node_a; uint32_t node_b;
    float left_x; float left_z; float right_x; float right_z;
    float left_y_a; float left_y_b; float right_y_a; float right_y_b;
    uint16_t capacity_cm; uint16_t flags; uint32_t reserved;
} AuditAxwgPortalV2;
]];

local artifact = os.getenv('AXWG_V2_FILE') or arg[1];
assert(artifact ~= nil and artifact ~= '', 'AXWG_V2_FILE or argv[1] is required');

local expected_source_crc = 0x30BA83D1;
local input = assert(io.open(artifact, 'rb'));
local contents = assert(input:read('*a'));
assert(input:close());
local bytes = ffi.new('uint8_t[?]', #contents);
ffi.copy(bytes, contents, #contents);
local header = ffi.cast('AuditAxwgHeaderV2*', bytes);
assert(tonumber(header.version) == 2 and tonumber(header.header_size) == 80,
    'real artifact is not AXWG v2/header80');
assert(tonumber(header.file_size) == #contents
        and tonumber(header.edge_record_size) == 20
        and tonumber(header.portal_record_size) == 48,
    'real artifact size or record ABI differs from AXWG v2');
assert(tonumber(header.node_count) == 228470
        and tonumber(header.edge_count) == 523139
        and tonumber(header.portal_count) == 262231,
    'real artifact counts differ from the corrected builder report');

local portals = ffi.cast('AuditAxwgPortalV2*', bytes + tonumber(header.portals_offset));
local safe, wall, headroom, capsule = 0, 0, 0, 0;
local capacity_mismatches, capacity_overclaims, capacity_underclaims = 0, 0, 0;
local epsilon_floor_differences = 0;
for portal_id = 0, tonumber(header.portal_count) - 1 do
    local portal = portals[portal_id];
    local flags = tonumber(portal.flags);
    if (bit.band(flags, 1) ~= 0) then safe = safe + 1; end
    if (bit.band(flags, 2) ~= 0) then wall = wall + 1; end
    if (bit.band(flags, 4) ~= 0) then headroom = headroom + 1; end
    if (bit.band(flags, 8) ~= 0) then capsule = capsule + 1; end
    local dx = tonumber(portal.right_x) - tonumber(portal.left_x);
    local dz = tonumber(portal.right_z) - tonumber(portal.left_z);
    local serialized_width_cm = math.sqrt(dx * dx + dz * dz) * 100;
    local serialized_floor = math.floor(serialized_width_cm);
    local loader_floor = math.floor(serialized_width_cm + 0.001);
    if (serialized_floor ~= loader_floor) then
        epsilon_floor_differences = epsilon_floor_differences + 1;
    end
    local delta = tonumber(portal.capacity_cm) - serialized_floor;
    if (delta ~= 0) then capacity_mismatches = capacity_mismatches + 1; end
    if (delta > 0) then
        capacity_overclaims = capacity_overclaims + 1;
    elseif (delta < 0) then
        capacity_underclaims = capacity_underclaims + 1;
    end
end
assert(safe == 262231 and wall == 262231 and headroom == 0 and capsule == 0,
    ('unexpected real portal flag census safe=%d wall=%d headroom=%d capsule=%d'):format(
        safe, wall, headroom, capsule));
assert(capacity_mismatches == 0
        and capacity_overclaims == 0 and capacity_underclaims == 0,
    ('serialized capacity mismatch total=%d over=%d under=%d'):format(
        capacity_mismatches, capacity_overclaims, capacity_underclaims));

local edges = ffi.cast('AuditAxwgEdgeV2*', bytes + tonumber(header.edges_offset));
local references = ffi.new('uint8_t[?]', tonumber(header.portal_count));
for edge_id = 0, tonumber(header.edge_count) - 1 do
    local portal_id = tonumber(edges[edge_id].portal_id);
    assert(portal_id >= 0 and portal_id < tonumber(header.portal_count),
        ('edge %d has invalid portal id %d'):format(edge_id, portal_id));
    assert(references[portal_id] < 2,
        ('portal %d is referenced more than twice'):format(portal_id));
    references[portal_id] = references[portal_id] + 1;
end
local unreferenced, referenced_once, referenced_twice = 0, 0, 0;
for portal_id = 0, tonumber(header.portal_count) - 1 do
    local count = tonumber(references[portal_id]);
    if (count == 0) then unreferenced = unreferenced + 1;
    elseif (count == 1) then referenced_once = referenced_once + 1;
    elseif (count == 2) then referenced_twice = referenced_twice + 1;
    else error(('portal %d has invalid reference count %d'):format(portal_id, count)); end
end
assert(unreferenced == 0 and referenced_once == 1323 and referenced_twice == 260908,
    ('portal reference census mismatch unreferenced=%d once=%d twice=%d'):format(
        unreferenced, referenced_once, referenced_twice));

print(('real serialized-capacity exact=%d over=0 under=0 epsilon-floor-differences=%d')
    :format(capacity_mismatches == 0 and tonumber(header.portal_count) or 0,
        epsilon_floor_differences));
print(('real portal references unreferenced=%d once=%d twice=%d')
    :format(unreferenced, referenced_once, referenced_twice));

local load_started = os.clock();
local graph, load_error = walk_graph.load(artifact, 102, expected_source_crc);
local load_ms = (os.clock() - load_started) * 1000;
assert(graph ~= nil,
    'corrected artifact failed strict loading without mutation: ' .. tostring(load_error));

local one_way, two_way = 0, 0;
for portal_id = 0, graph.portal_count - 1 do
    local directions = tonumber(graph._portal_directions[portal_id]);
    if (directions == 3) then two_way = two_way + 1;
    elseif (directions == 1 or directions == 2) then one_way = one_way + 1;
    else error(('portal %d has invalid direction mask %d'):format(portal_id, directions)); end
end
assert(one_way == 1323 and two_way == 260908,
    ('real direction census mismatch one-way=%d two-way=%d'):format(one_way, two_way));

local function audit_route(name, start, goal)
    local start_id = assert(graph:nearest(
        start[1], start[2], start[3], 6, 4.5, 0.7));
    local goal_id = assert(graph:nearest(
        goal[1], goal[2], goal[3], 6, 4.5, 0.7));
    local search = assert(graph:begin_astar(start_id, goal_id));
    local status, route;
    local started, max_slice_ms = os.clock(), 0;
    repeat
        local slice = os.clock();
        status, route = search:step(512);
        max_slice_ms = math.max(max_slice_ms, (os.clock() - slice) * 1000);
    until status ~= 'pending';
    local search_ms = (os.clock() - started) * 1000;
    assert(status == 'ready', name .. ' did not route: ' .. tostring(route));
    assert(#route > 1 and #route.edge_ids == #route - 1
            and #route.portal_ids == #route.edge_ids,
        name .. ' did not reconstruct an exact portal corridor');
    local narrowest = math.huge;
    for _, portal_id in ipairs(route.portal_ids) do
        narrowest = math.min(narrowest,
            tonumber(graph._portals[portal_id].capacity_cm));
    end
    local start_point, goal_point = assert(graph:point(start_id)), assert(graph:point(goal_id));
    start_point.connector_certified, goal_point.connector_certified = true, true;
    local pulled, funnel_error = graph:funnel(route, start_point, goal_point);
    assert(pulled ~= nil, name .. ' certified corridor did not funnel: '
        .. tostring(funnel_error));
    assert(#pulled.crossings == #route.portal_ids,
        name .. ' funnel lost a certified portal crossing');
    local pulled_length = 0;
    for _, segment in ipairs(pulled.segments) do
        pulled_length = pulled_length + segment.length;
    end
    assert(pulled_length <= route.total_cost + 0.001,
        ('%s funnel length %.3f exceeds its portal-midpoint witness %.3f'):format(
            name, pulled_length, route.total_cost));
    print(('%s nodes=%d edges=%d cost=%.1f narrowest=%dcm expansions=%d '
            .. 'search=%.1fms max512=%.3fms corners=%d pulled=%.1f'):format(
        name, #route, #route.edge_ids, route.total_cost, narrowest,
        search.expansions, search_ms, max_slice_ms, #pulled.corners, pulled_length));
end

audit_route('r1', { 25.0, 25.6, 16.5 }, { 17.7, 16.7, 9.3 });
audit_route('r2_wall', { 24.4, 20.2, 16.0 }, { 17.2, 20.7, 10.1 });

local state_count = graph.edge_count + graph.node_count + 1;
local workspace_bytes = state_count * 40;
print(('AXWG v2 real artifact deep audit ok load=%.1fms states=%d workspace=%.1fMiB '
        .. 'one-way=%d two-way=%d'):format(
    load_ms, state_count, workspace_bytes / 1048576, one_way, two_way));
