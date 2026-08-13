local module = {}

local ABI_VERSION = 3
local LOAD_PENDING = 1
local LOAD_READY = 2
local LOAD_FAILED = 3
local LOAD_CANCELED = 4
local PATH_READY = 1
local RESULT_OK = 0
local MAX_POINTS = 512
local ZONELINE_SUPPORT_NORMAL_Y = 0.50
local ZONELINE_BOUNDARY_NORMAL_Y = 0.25
local ZONELINE_BOUNDARY_HORIZONTAL_NORMAL = 0.95
local ZONELINE_SUPPORT_ADVANCE = 0.10
local ZONELINE_MAX_SWEEPS = 64
local DLL_RELATIVE_PATH = 'third_party/collision/accessxi_collision_native.dll'
local MANIFEST_HEADER = 'relative_path\tsha256\tabi_version\tsettings_sha256\trecast_commit\tbullet_commit'
local SETTINGS_SHA256 = 'a8de71b6e9e79408ea9914d6448e1b783654a54c92d5fe61b2a033e9477e5f32'
module.settings_sha256 = SETTINGS_SHA256
local RECAST_COMMIT = '9f4ce64458dfae86e1239c525ddc219c4e9e06f1'
local BULLET_COMMIT = '63c4d67e337017f9d8b298c900e9aabdb69296e7'

local State = {}
State.__index = State
local cdef_done = false

local function finite(value)
    return type(value) == 'number'
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function positive_integer(value)
    return type(value) == 'number' and value > 0 and value == math.floor(value)
end

local function canonical_sha256(value)
    return type(value) == 'string' and #value == 64 and value:match('^[0-9a-f]+$') ~= nil
end

local function read_file(path)
    local file, open_reason = io.open(path, 'rb')
    if file == nil then
        return nil, 'Could not open ' .. tostring(path) .. ': ' .. tostring(open_reason)
    end
    local ok, bytes = pcall(file.read, file, '*a')
    file:close()
    if not ok or type(bytes) ~= 'string' then
        return nil, 'Could not read exact bytes from ' .. tostring(path)
    end
    return bytes
end

local function split_tabs(line)
    local result = {}
    local start = 1
    while true do
        local position = line:find('\t', start, true)
        if position == nil then
            result[#result + 1] = line:sub(start)
            return result
        end
        result[#result + 1] = line:sub(start, position - 1)
        start = position + 1
    end
end

local function parse_manifest(bytes)
    if type(bytes) ~= 'string' or bytes:find('\0', 1, true) ~= nil then
        return nil, 'Collision native manifest bytes are malformed.'
    end
    bytes = bytes:gsub('\r\n', '\n')
    if bytes:sub(-1) == '\n' then bytes = bytes:sub(1, -2) end
    local lines = {}
    for line in (bytes .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end
    if #lines ~= 2 or lines[1] ~= MANIFEST_HEADER then
        return nil, 'Collision native manifest schema is invalid.'
    end
    local fields = split_tabs(lines[2])
    if #fields ~= 6
        or fields[1] ~= DLL_RELATIVE_PATH
        or not canonical_sha256(fields[2])
        or tonumber(fields[3]) ~= ABI_VERSION
        or fields[4] ~= SETTINGS_SHA256
        or fields[5] ~= RECAST_COMMIT
        or fields[6] ~= BULLET_COMMIT then
        return nil, 'Collision native manifest identity is invalid.'
    end
    return {
        relative_path = fields[1],
        dll_sha256 = fields[2],
        abi_version = tonumber(fields[3]),
        settings_sha256 = fields[4],
    }
end

local function join(root, relative)
    root = tostring(root or ''):gsub('/', '\\'):gsub('[\\/]+$', '')
    relative = tostring(relative or ''):gsub('/', '\\'):gsub('^[\\/]+', '')
    if root == '' then return relative end
    return root .. '\\' .. relative
end

local function declare_ffi(ffi)
    if cdef_done then return true end
    local ok, reason = pcall(ffi.cdef, [[
        typedef struct AXICollisionVec3 {
            float x;
            float y;
            float z;
        } AXICollisionVec3;
        #pragma pack(push, 4)
        typedef struct AXICollisionLoadStatus {
            unsigned int struct_size;
            int state;
            unsigned int zone_id;
            unsigned int progress_percent;
            unsigned long long generation;
            char message[256];
            char dat_sha256[65];
            char settings_sha256[65];
        } AXICollisionLoadStatus;
        #pragma pack(pop)
        typedef struct AXICollisionSweepResult {
            unsigned int struct_size;
            int clear;
            float fraction;
            AXICollisionVec3 point;
            AXICollisionVec3 normal;
            int triangle_index;
        } AXICollisionSweepResult;
        typedef struct AXICollisionPathResult {
            unsigned int struct_size;
            int status;
            unsigned int point_count;
            float total_length;
            AXICollisionVec3 projected_start;
            AXICollisionVec3 projected_end;
            char reason[256];
        } AXICollisionPathResult;
        unsigned int __cdecl AXI_GetAbiVersion(void);
        void* __cdecl AXI_CreateContext(void);
        void __cdecl AXI_DestroyContext(void* context);
        int __cdecl AXI_BeginLoadZone(void* context, unsigned int zone_id,
            const wchar_t* ffxi_root, const wchar_t* cache_root,
            unsigned long long* generation);
        int __cdecl AXI_CancelLoad(void* context, unsigned long long generation);
        int __cdecl AXI_PollLoadZone(void* context, unsigned long long generation,
            AXICollisionLoadStatus* status);
        int __cdecl AXI_SweepCapsule(void* context, unsigned long long generation,
            AXICollisionVec3 start, AXICollisionVec3 end,
            float radius, float height,
            AXICollisionSweepResult* result);
        int __cdecl AXI_FindPath(void* context, unsigned long long generation,
            AXICollisionVec3 start, AXICollisionVec3 destination, float arrival_radius,
            AXICollisionVec3* points, unsigned int capacity,
            AXICollisionPathResult* result);
    ]])
    if not ok then
        return nil, 'Collision native FFI declaration failed: ' .. tostring(reason)
    end
    cdef_done = true
    return true
end

local function real_native(deps)
    local ffi = deps.ffi
    if type(ffi) ~= 'table' then
        local ok, loaded = pcall(require, 'ffi')
        if not ok then return nil, 'LuaJIT FFI is unavailable.' end
        ffi = loaded
    end
    if type(deps.utf8_to_wide) ~= 'function' then
        return nil, 'Collision navigation requires UTF-8 to UTF-16 conversion.'
    end
    local declared, declare_reason = declare_ffi(ffi)
    if not declared then return nil, declare_reason end

    local manifest_bytes, manifest_reason = read_file(deps.manifest_path)
    if manifest_bytes == nil then return nil, manifest_reason end
    local manifest, parse_reason = parse_manifest(manifest_bytes)
    if manifest == nil then return nil, parse_reason end
    local dll_path = deps.dll_path or join(deps.addon_root, manifest.relative_path)
    local dll_bytes, dll_reason = read_file(dll_path)
    if dll_bytes == nil then return nil, dll_reason end
    if type(deps.sha256) ~= 'function' then
        return nil, 'Collision navigation SHA-256 dependency is unavailable.'
    end
    local ok_hash, digest, hash_reason = pcall(deps.sha256, dll_bytes)
    if not ok_hash or digest ~= manifest.dll_sha256 then
        return nil, 'Collision native DLL hash does not match its manifest: '
            .. tostring(hash_reason or digest or 'hash failed')
    end
    local ok_load, library = pcall(ffi.load, dll_path)
    if not ok_load or library == nil then
        return nil, 'Collision native DLL could not be loaded: ' .. tostring(library)
    end

    local native = { expected_settings_sha256 = manifest.settings_sha256 }
    function native:abi_version()
        return tonumber(library.AXI_GetAbiVersion())
    end
    function native:create_context()
        local context = library.AXI_CreateContext()
        if context == nil or context == ffi.NULL then return nil end
        return context
    end
    function native:destroy_context(context)
        library.AXI_DestroyContext(context)
    end
    function native:begin_load(context, zone, ffxi_root, cache_root)
        local generation = ffi.new('unsigned long long[1]')
        local wide_ffxi = deps.utf8_to_wide(ffxi_root)
        local wide_cache = deps.utf8_to_wide(cache_root)
        local result = tonumber(library.AXI_BeginLoadZone(
            context, zone, wide_ffxi, wide_cache, generation))
        return result, tonumber(generation[0])
    end
    function native:cancel_load(context, generation)
        return tonumber(library.AXI_CancelLoad(context, generation))
    end
    function native:poll_load(context, generation)
        local status = ffi.new('AXICollisionLoadStatus[1]')
        status[0].struct_size = ffi.sizeof('AXICollisionLoadStatus')
        local result = tonumber(library.AXI_PollLoadZone(context, generation, status))
        if result ~= RESULT_OK then return result end
        return result, {
            state = tonumber(status[0].state),
            zone_id = tonumber(status[0].zone_id),
            progress_percent = tonumber(status[0].progress_percent),
            generation = tonumber(status[0].generation),
            message = ffi.string(status[0].message),
            dat_sha256 = ffi.string(status[0].dat_sha256),
            settings_sha256 = ffi.string(status[0].settings_sha256),
        }
    end
    function native:sweep(context, generation, start, destination, radius, height)
        local result = ffi.new('AXICollisionSweepResult[1]')
        result[0].struct_size = ffi.sizeof('AXICollisionSweepResult')
        local native_start = ffi.new('AXICollisionVec3', start)
        local native_destination = ffi.new('AXICollisionVec3', destination)
        local code = tonumber(library.AXI_SweepCapsule(
            context, generation, native_start, native_destination,
            radius, height, result))
        if code ~= RESULT_OK then return code end
        return code, {
            clear = tonumber(result[0].clear) == 1,
            fraction = tonumber(result[0].fraction),
            point = {
                x = tonumber(result[0].point.x),
                y = tonumber(result[0].point.y),
                z = tonumber(result[0].point.z),
            },
            normal = {
                x = tonumber(result[0].normal.x),
                y = tonumber(result[0].normal.y),
                z = tonumber(result[0].normal.z),
            },
            triangle_index = tonumber(result[0].triangle_index),
        }
    end
    function native:find_path(context, generation, start, destination, arrival_radius, capacity)
        local points = ffi.new('AXICollisionVec3[?]', capacity)
        local result = ffi.new('AXICollisionPathResult[1]')
        result[0].struct_size = ffi.sizeof('AXICollisionPathResult')
        local native_start = ffi.new('AXICollisionVec3', start)
        local native_destination = ffi.new('AXICollisionVec3', destination)
        local code = tonumber(library.AXI_FindPath(
            context, generation, native_start, native_destination, arrival_radius,
            points, capacity, result))
        if code ~= RESULT_OK then return code end
        local copied = {}
        local count = tonumber(result[0].point_count)
        if count >= 0 and count <= capacity then
            for index = 0, count - 1 do
                copied[#copied + 1] = {
                    x = tonumber(points[index].x),
                    y = tonumber(points[index].y),
                    z = tonumber(points[index].z),
                }
            end
        end
        return code, {
            status = tonumber(result[0].status),
            point_count = count,
            total_length = tonumber(result[0].total_length),
            reason = ffi.string(result[0].reason),
        }, copied
    end
    return native
end

local function native_error(operation, code)
    return ('Collision terrain %s failed with native result %s.'):format(
        tostring(operation), tostring(code))
end

local function copy_destination(destination)
    local result = {}
    for key, value in pairs(destination or {}) do
        if type(value) ~= 'table' then result[key] = value end
    end
    return result
end

function State:_pending_message(zone)
    local name = ''
    if type(self.zone_name) == 'function' then
        local ok, value = pcall(self.zone_name, zone)
        if ok then name = tostring(value or '') end
    end
    if name == '' then name = 'this area' end
    return ('Mapping terrain for %s. Navigation will start automatically.'):format(name)
end

function State:_cancel_generation()
    if self.context ~= nil and self.generation ~= nil then
        pcall(self.native.cancel_load, self.native, self.context, self.generation)
    end
    self.generation = nil
    self.zone = 0
    self.pending_destination = nil
end

function State:_begin(zone, destination)
    if self.generation ~= nil and self.zone ~= zone then
        self:_cancel_generation()
    end
    if self.generation == nil then
        local ok, code, generation = pcall(
            self.native.begin_load,
            self.native,
            self.context,
            zone,
            self.ffxi_root,
            self.cache_root)
        if not ok then return nil, 'Collision terrain loading raised an error: ' .. tostring(code) end
        if code ~= RESULT_OK or not positive_integer(generation) then
            return nil, native_error('loading', code)
        end
        self.generation = generation
        self.zone = zone
    end
    if destination ~= nil then
        self.pending_destination = copy_destination(destination)
    end
    return true
end

function State:preload(zone)
    if self.shutdown_complete then
        return nil, 'error', 'Collision terrain navigation is shut down.'
    end
    if not positive_integer(zone) then
        return nil, 'error', 'Collision terrain preload requires a valid current zone.'
    end
    if self.pending_destination ~= nil then
        return nil, 'busy', ''
    end
    local began, begin_reason = self:_begin(zone, nil)
    if not began then return nil, 'error', begin_reason end
    local ok, code, status = pcall(
        self.native.poll_load, self.native, self.context, self.generation)
    if not ok then
        return nil, 'error', 'Collision terrain polling raised an error: ' .. tostring(code)
    end
    if code ~= RESULT_OK or type(status) ~= 'table' then
        return nil, 'error', native_error('polling', code)
    end
    if status.zone_id ~= self.zone or status.generation ~= self.generation then
        return nil, 'error', 'Collision terrain returned stale zone state.'
    end
    if self.expected_settings_sha256 ~= nil
        and status.settings_sha256 ~= self.expected_settings_sha256 then
        return nil, 'error', 'Collision terrain settings do not match the installed manifest.'
    end
    if status.state == LOAD_PENDING then
        return true, 'pending', ''
    end
    if status.state == LOAD_FAILED or status.state == LOAD_CANCELED then
        local reason = tostring(status.message or 'Collision terrain mapping failed.')
        self:_cancel_generation()
        return nil, 'error', reason
    end
    if status.state ~= LOAD_READY or not canonical_sha256(status.dat_sha256) then
        return nil, 'error', 'Collision terrain returned malformed ready state.'
    end
    return true, 'ready', ''
end

function State:_query(player, destination, arrival_radius)
    local query_radius = arrival_radius
    if query_radius ~= nil then
        query_radius = tonumber(query_radius)
        if not finite(query_radius) or query_radius < 1.5 or query_radius > 20 then
            return nil, 'error', 'Collision terrain received an invalid zoneline arrival radius.'
        end
    else
        query_radius = self.arrival_radius(destination)
    end
    local ok, code, result, native_points = pcall(
        self.native.find_path,
        self.native,
        self.context,
        self.generation,
        -- FFXI exposes vertical position with the opposite sign from the MZB
        -- collision coordinate system.  X and horizontal Z are unchanged.
        { x = player.x, y = -player.y, z = player.z },
        { x = destination.x, y = -destination.y, z = destination.z },
        query_radius,
        MAX_POINTS)
    if not ok then return nil, 'error', 'Collision terrain pathfinding raised an error: ' .. tostring(code) end
    if code ~= RESULT_OK then return nil, 'error', native_error('pathfinding', code) end
    if type(result) ~= 'table' or result.status ~= PATH_READY then
        local reason = type(result) == 'table' and tostring(result.reason or '') or ''
        if reason == '' then reason = 'No collision-safe path reaches this destination.' end
        return nil, 'error', reason
    end
    if type(native_points) ~= 'table'
        or result.point_count ~= #native_points
        or #native_points < 2
        or #native_points > MAX_POINTS then
        return nil, 'error', 'Collision terrain returned a malformed waypoint count.'
    end
    local points = {}
    for index, point in ipairs(native_points) do
        if type(point) ~= 'table'
            or not finite(point.x)
            or not finite(point.y)
            or not finite(point.z) then
            return nil, 'error', 'Collision terrain returned a malformed waypoint.'
        end
        points[index] = {
            zone = self.zone,
            name = ('Terrain waypoint %d'):format(index),
            x = point.x,
            z = point.z,
            y = -point.y,
            kind = 'route',
            source = 'dat-collision',
        }
    end
    self.pending_destination = nil
    return points, 'ready', ''
end

function State:_direct_capsule_segment_clear(start_point, end_point)
    if type(self.native.sweep) ~= 'function' then
        return nil, 'Collision terrain capsule validation is unavailable.'
    end
    local start_native = {
        x = start_point.x,
        y = -start_point.y,
        z = start_point.z,
    }
    local end_native = {
        x = end_point.x,
        y = -end_point.y,
        z = end_point.z,
    }
    local ok, code, result = pcall(
        self.native.sweep,
        self.native,
        self.context,
        self.generation,
        start_native,
        end_native,
        0.40,
        1.80)
    if not ok then
        return nil, 'Collision terrain capsule validation raised an error: ' .. tostring(code)
    end
    if code ~= RESULT_OK or type(result) ~= 'table'
        or type(result.clear) ~= 'boolean' then
        return nil, native_error('capsule validation', code)
    end
    return result.clear, ''
end

function State:_capsule_segment_clear(start_point, end_point)
    local direct, direct_reason = self:_direct_capsule_segment_clear(start_point, end_point)
    if direct == nil then return false, direct_reason end
    if direct then return true, '' end

    local raised_start = {
        x = start_point.x,
        y = start_point.y - 0.65,
        z = start_point.z,
    }
    local raised_end = {
        x = end_point.x,
        y = end_point.y - 0.65,
        z = end_point.z,
    }
    for _, segment in ipairs({
        { start_point, raised_start },
        { raised_start, raised_end },
        { raised_end, end_point },
    }) do
        local segment_clear, segment_reason = self:_direct_capsule_segment_clear(
            segment[1], segment[2])
        if segment_clear == nil then return false, segment_reason end
        if not segment_clear then
            return false, 'Collision terrain zoneline tail is blocked.'
        end
    end
    return true, ''
end

function State:validate_direct_route(points)
    if self.shutdown_complete then
        return false, 'Collision terrain navigation is shut down.'
    end
    if type(points) ~= 'table' or #points < 2 or #points > MAX_POINTS then
        return false, 'Collision terrain candidate route is malformed.'
    end
    for index, point in ipairs(points) do
        if type(point) ~= 'table'
            or not finite(point.x) or not finite(point.z) or not finite(point.y)
            or not positive_integer(point.zone) or point.zone ~= self.zone then
            return false, ('Collision terrain candidate waypoint %d is malformed.'):format(index)
        end
    end
    for index = 2, #points do
        local clear, reason = self:_direct_capsule_segment_clear(points[index - 1], points[index])
        if clear == nil then return false, reason end
        if not clear then
            return false, ('Collision candidate segment %d is blocked.'):format(index - 1)
        end
    end
    return true, ''
end

function State:_zoneline_tail_contact(start_point, end_point)
    if type(self.native.sweep) ~= 'function' then
        return false, nil, 'Collision terrain capsule validation is unavailable.'
    end
    local current = {
        x = start_point.x,
        y = -start_point.y,
        z = start_point.z,
    }
    local target = {
        x = end_point.x,
        y = -end_point.y,
        z = end_point.z,
    }
    for _ = 1, ZONELINE_MAX_SWEEPS do
        local dx = target.x - current.x
        local dy = target.y - current.y
        local dz = target.z - current.z
        local remaining = math.sqrt(dx * dx + dy * dy + dz * dz)
        if remaining < 0.01 then
            return true, nil, ''
        end
        local ok, code, result = pcall(
            self.native.sweep,
            self.native,
            self.context,
            self.generation,
            current,
            target,
            0.40,
            1.80)
        if not ok then
            return false, nil,
                'Collision terrain tail validation raised an error: ' .. tostring(code)
        end
        if code ~= RESULT_OK or type(result) ~= 'table'
            or type(result.clear) ~= 'boolean' then
            return false, nil, native_error('tail validation', code)
        end
        if result.clear then
            return true, nil, ''
        end
        local fraction = tonumber(result.fraction)
        local normal = result.normal
        local nx = type(normal) == 'table' and tonumber(normal.x) or nil
        local ny = type(normal) == 'table' and tonumber(normal.y) or nil
        local nz = type(normal) == 'table' and tonumber(normal.z) or nil
        if not finite(fraction) or fraction < 0 or fraction > 1
            or not finite(nx) or not finite(ny) or not finite(nz) then
            return false, nil, 'Collision terrain zoneline tail returned malformed contact data.'
        end
        if ny >= ZONELINE_SUPPORT_NORMAL_Y then
            local next_fraction = fraction + (ZONELINE_SUPPORT_ADVANCE / remaining)
            if next_fraction >= 1 then
                return false, nil, 'Collision terrain zoneline tail ended on unsupported terrain.'
            end
            current = {
                x = current.x + dx * next_fraction,
                y = current.y + dy * next_fraction,
                z = current.z + dz * next_fraction,
            }
        else
            local horizontal_normal = math.sqrt(nx * nx + nz * nz)
            local contact_x = current.x + dx * fraction
            local contact_y = current.y + dy * fraction
            local contact_z = current.z + dz * fraction
            local remaining_x = target.x - contact_x
            local remaining_y = target.y - contact_y
            local remaining_z = target.z - contact_z
            local remaining_to_line = math.sqrt(
                remaining_x * remaining_x
                + remaining_y * remaining_y
                + remaining_z * remaining_z)
            if math.abs(ny) > ZONELINE_BOUNDARY_NORMAL_Y
                or horizontal_normal < ZONELINE_BOUNDARY_HORIZONTAL_NORMAL
                or fraction <= 0
                or remaining_to_line > 20.5 then
                return false, nil, 'Collision terrain zoneline tail is blocked.'
            end
            return true, {
                zone = self.zone,
                name = 'Terrain zoneline boundary',
                x = contact_x,
                z = contact_z,
                y = -contact_y,
                kind = 'route',
                source = 'dat-collision-zoneline-boundary',
            }, ''
        end
    end
    return false, nil, 'Collision terrain zoneline tail contact search did not converge.'
end

function State:route_zoneline_tail(player, approach, destination)
    if self.shutdown_complete then
        return nil, 'error', 'Collision terrain navigation is shut down.'
    end
    if type(player) ~= 'table' or type(approach) ~= 'table'
        or type(destination) ~= 'table'
        or not positive_integer(player.zone)
        or player.zone ~= approach.zone
        or player.zone ~= destination.zone
        or self.generation == nil or self.zone ~= player.zone
        or not finite(player.x) or not finite(player.z) or not finite(player.y)
        or not finite(approach.x) or not finite(approach.z) or not finite(approach.y)
        or not finite(destination.x) or not finite(destination.z) or not finite(destination.y) then
        return nil, 'error', 'Collision terrain zoneline tail requires a ready same-zone route.'
    end
    local points, mode, reason = self:_query(player, approach, 20)
    if mode ~= 'ready' or type(points) ~= 'table' or #points < 2 then
        return nil, mode or 'error', reason
    end
    local last = points[#points]
    local dx = destination.x - last.x
    local dz = destination.z - last.z
    local dy = destination.y - last.y
    local horizontal = math.sqrt(dx * dx + dz * dz)
    local spatial = math.sqrt(dx * dx + dz * dz + dy * dy)
    if horizontal > 30 or spatial > 32 then
        return nil, 'error', 'Collision terrain zoneline tail exceeds the bounded recovery distance.'
    end
    local accepted, boundary, contact_reason =
        self:_zoneline_tail_contact(last, destination)
    if not accepted then
        return nil, 'error', contact_reason ~= '' and contact_reason
            or 'Collision terrain zoneline tail is blocked.'
    end
    if boundary ~= nil then
        points[#points + 1] = boundary
    end
    return points, 'ready', ''
end

function State:route(player, destination)
    if self.shutdown_complete then
        return nil, 'error', 'Collision terrain navigation is shut down.'
    end
    if type(player) ~= 'table' or type(destination) ~= 'table'
        or not positive_integer(player.zone)
        or player.zone ~= destination.zone
        or not finite(player.x) or not finite(player.z) or not finite(player.y)
        or not finite(destination.x) or not finite(destination.z) or not finite(destination.y) then
        return nil, 'error', 'Collision terrain requires a current same-zone player and destination.'
    end
    local began, begin_reason = self:_begin(player.zone, destination)
    if not began then return nil, 'error', begin_reason end
    local ok, code, status = pcall(
        self.native.poll_load, self.native, self.context, self.generation)
    if not ok then return nil, 'error', 'Collision terrain polling raised an error: ' .. tostring(code) end
    if code ~= RESULT_OK or type(status) ~= 'table' then
        return nil, 'error', native_error('polling', code)
    end
    if status.zone_id ~= self.zone or status.generation ~= self.generation then
        return nil, 'error', 'Collision terrain returned stale zone state.'
    end
    if self.expected_settings_sha256 ~= nil
        and status.settings_sha256 ~= self.expected_settings_sha256 then
        return nil, 'error', 'Collision terrain settings do not match the installed manifest.'
    end
    if status.state == LOAD_PENDING then
        return nil, 'pending', self:_pending_message(self.zone)
    end
    if status.state == LOAD_FAILED or status.state == LOAD_CANCELED then
        local reason = tostring(status.message or 'Collision terrain mapping failed.')
        self:_cancel_generation()
        return nil, 'error', reason
    end
    if status.state ~= LOAD_READY or not canonical_sha256(status.dat_sha256) then
        return nil, 'error', 'Collision terrain returned malformed ready state.'
    end
    return self:_query(player, destination)
end

function State:poll(player)
    if self.pending_destination == nil then return nil, 'idle', '' end
    return self:route(player, self.pending_destination)
end

function State:cancel(_reason)
    self:_cancel_generation()
end

function State:shutdown()
    if self.shutdown_complete then return end
    self:_cancel_generation()
    if self.context ~= nil then
        pcall(self.native.destroy_context, self.native, self.context)
        self.context = nil
    end
    self.shutdown_complete = true
end

function module.new(deps)
    deps = deps or {}
    local native = deps.native
    if native == nil then
        local reason
        native, reason = real_native(deps)
        if native == nil then return nil, reason end
    end
    if type(native.abi_version) ~= 'function' or native:abi_version() ~= ABI_VERSION then
        return nil, 'Collision native ABI version does not match AccessXI.'
    end
    if type(native.create_context) ~= 'function' then
        return nil, 'Collision native context constructor is unavailable.'
    end
    local context = native:create_context()
    if context == nil then return nil, 'Collision native context could not be created.' end
    if tostring(deps.ffxi_root or '') == '' then
        native:destroy_context(context)
        return nil, 'The installed FFXI root could not be resolved.'
    end
    local state = setmetatable({
        native = native,
        context = context,
        ffxi_root = tostring(deps.ffxi_root),
        cache_root = tostring(deps.cache_root or ''),
        zone_name = deps.zone_name,
        arrival_radius = type(deps.arrival_radius) == 'function'
            and deps.arrival_radius
            or function() return 1.5 end,
        expected_settings_sha256 = native.expected_settings_sha256,
        generation = nil,
        zone = 0,
        pending_destination = nil,
        shutdown_complete = false,
    }, State)
    return state
end

return module
