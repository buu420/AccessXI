local module = {}

local MANIFEST_HEADER = 'relative_path\tsha256\tkind\tzone\tmesh_name'
local GRAPH_HEADER = 'zoneline_id\tfrom_zone\tfrom_name\tfrom_code\tfrom_x\tfrom_z\tfrom_y\tto_zone\tto_name\tto_code\tto_x\tto_z\tto_y\tsource\tconfidence\tnote'
local REQUIRED_RUNTIME_PATHS = {
    ['data/ffxi-nav-destinations.tsv'] = 'destinations',
    ['data/ffxi-nav-zoneline-graph.tsv'] = 'graph',
    ['modules/mission_quest_route_contracts.lua'] = 'contracts',
    ['modules/mission_quest_route_policy.lua'] = 'policy',
    ['modules/mission_quest_route_runtime.lua'] = 'runtime',
    ['modules/mission_quest_route_transitions.lua'] = 'transitions',
    ['third_party/FFXI-NavMesh-Builder/FFXINAV.dll'] = 'ffxinav',
}
local GENERATED_MODULES = {
    'modules/mission_quest_route_policy.lua',
    'modules/mission_quest_route_transitions.lua',
    'modules/mission_quest_route_contracts.lua',
}
local EXPECTED_POLICY_SCHEMA = 2
local EXPECTED_POLICY_REVISION = 'objective-route-proof-v2.1'
local EXPECTED_PROBE_PROTOCOL = 'accessxi-navprobe-jsonl-v2'
local EXPECTED_PROBE_SCHEMA = 2
local CONTRACT_INPUT_FIELDS = {
    'mesh_name',
    'mesh_sha256',
    'ffxinav_sha256',
    'probe_protocol',
    'probe_schema',
    'policy_revision',
    'policy_sha256',
    'transition_registry_sha256',
    'destinations_sha256',
    'graph_sha256',
    'destination_row_sha256',
    'ingress_row_sha256',
    'zone_mesh_name',
}

local Runtime = {}
Runtime.__index = Runtime
local PRIVATE = setmetatable({}, { __mode = 'k' })

local function private(runtime)
    return PRIVATE[runtime]
end

local function canonical_sha256(value)
    return type(value) == 'string' and value:match('^[0-9a-f]+$') ~= nil and #value == 64
end

local function canonical_relative_path(value)
    if type(value) ~= 'string' or value == '' or value:find('[%z\1-\31]') then
        return false
    end
    if value:find('\\', 1, true) or value:sub(1, 1) == '/' or value:find(':', 1, true) then
        return false
    end
    for part in value:gmatch('[^/]+') do
        if part == '.' or part == '..' or part == '' then
            return false
        end
    end
    return not value:find('//', 1, true)
end

local function split_tabs(line)
    local fields = {}
    local start = 1
    while true do
        local position = line:find('\t', start, true)
        if position == nil then
            fields[#fields + 1] = line:sub(start)
            return fields
        end
        fields[#fields + 1] = line:sub(start, position - 1)
        start = position + 1
    end
end

local function deep_copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[deep_copy(key, seen)] = deep_copy(item, seen)
    end
    return result
end

local function deep_equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if right[key] == nil and value ~= nil then return false end
        if not deep_equal(value, right[key], seen) then return false end
    end
    for key, value in pairs(right) do
        if left[key] == nil and value ~= nil then return false end
    end
    return true
end

local function exact_array(value)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then return false end
        count = count + 1
    end
    return count == #value
end

local function nonempty(value)
    return type(value) == 'string' and value ~= ''
end

local function trim(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or ''
end

local function contract_key(candidate_id, action_id, group_id, destination_id)
    return table.concat({ candidate_id, action_id, group_id, destination_id }, '\0')
end

local OBJECTIVE_OWNER_STRING_FIELDS = {
    'objective_kind',
    'objective_native_key',
    'objective_guide_step_id',
    'objective_character_identity',
    'objective_candidate_id',
    'objective_action_id',
    'objective_group_id',
    'objective_destination_id',
    'objective_classification',
    'objective_action_instruction',
}

local function positive_integer(value)
    return type(value) == 'number' and value > 0 and value == math.floor(value)
end

local function nonnegative_integer(value)
    return type(value) == 'number' and value >= 0 and value == math.floor(value)
end

local function finite_number(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local IDENTITY_FIELDS = { 'size_low', 'size_high', 'write_time_low', 'write_time_high' }

local function valid_identity(identity)
    if type(identity) ~= 'table' then return false end
    local count = 0
    for field, value in pairs(identity) do
        local known = false
        for _, expected in ipairs(IDENTITY_FIELDS) do
            if field == expected then known = true; break end
        end
        if not known or not nonnegative_integer(value) or value > 4294967295 then return false end
        count = count + 1
    end
    if count ~= #IDENTITY_FIELDS then return false end
    for _, field in ipairs(IDENTITY_FIELDS) do
        if not nonnegative_integer(identity[field]) or identity[field] > 4294967295 then return false end
    end
    return true
end

local function identity_equal(left, right)
    if not valid_identity(left) or not valid_identity(right) then return false end
    for _, field in ipairs(IDENTITY_FIELDS) do
        if left[field] ~= right[field] then return false end
    end
    return true
end

local function validate_objective_owner(selected, fresh)
    for _, field in ipairs(OBJECTIVE_OWNER_STRING_FIELDS) do
        if type(selected[field]) ~= 'string' or selected[field] ~= fresh[field] then
            return nil, 'The current objective destination changed.'
        end
    end
    if selected.objective_instruction_only ~= fresh.objective_instruction_only
        or type(selected.objective_instruction_only) ~= 'boolean'
    then
        return nil, 'The current objective destination changed.'
    end
    if not positive_integer(selected.objective_world_id)
        or selected.objective_world_id ~= fresh.objective_world_id
        or not positive_integer(selected.objective_session_epoch)
        or selected.objective_session_epoch ~= fresh.objective_session_epoch
    then
        return nil, 'The current objective owner or session changed.'
    end
    if (selected.objective_kind ~= 'mission' and selected.objective_kind ~= 'quest')
        or not nonempty(selected.objective_native_key)
        or not nonempty(selected.objective_guide_step_id)
        or not nonempty(selected.objective_character_identity)
        or not nonempty(selected.objective_action_id)
        or not nonempty(selected.objective_action_instruction)
    then
        return nil, 'The current objective owner metadata is invalid.'
    end
    return true
end

local function parse_manifest(bytes)
    if type(bytes) ~= 'string' or bytes:sub(1, 3) == '\239\187\191' or bytes:sub(-1) ~= '\n' then
        return nil, 'Runtime manifest must be UTF-8 bytes without BOM and end in LF.'
    end
    local lines = {}
    for line in bytes:gmatch('([^\n]*)\n') do
        lines[#lines + 1] = line
    end
    if lines[1] ~= MANIFEST_HEADER then
        return nil, 'Runtime manifest header mismatch.'
    end
    local rows = {}
    local aliases = {}
    local previous = nil
    for index = 2, #lines do
        local fields = split_tabs(lines[index])
        if #fields ~= 5 or not canonical_relative_path(fields[1])
            or not canonical_sha256(fields[2]) or fields[3] == ''
        then
            return nil, ('Runtime manifest row %d is malformed.'):format(index)
        end
        local alias = fields[1]:lower()
        if aliases[alias] then
            return nil, ('Runtime manifest path %s is duplicated.'):format(fields[1])
        end
        if previous ~= nil and alias <= previous then
            return nil, 'Runtime manifest rows are not canonically sorted.'
        end
        aliases[alias] = true
        previous = alias
        local row = {
            relative_path = fields[1],
            sha256 = fields[2],
            kind = fields[3],
            zone = fields[4],
            mesh_name = fields[5],
        }
        if row.kind == 'mesh' then
            if not row.zone:match('^%d+$') or row.mesh_name == '' then
                return nil, 'Runtime manifest mesh metadata is malformed.'
            end
        elseif row.zone ~= '' or row.mesh_name ~= '' then
            return nil, 'Only runtime manifest mesh rows may carry zone metadata.'
        end
        rows[row.relative_path] = row
    end
    for path, kind in pairs(REQUIRED_RUNTIME_PATHS) do
        if rows[path] == nil or rows[path].kind ~= kind then
            return nil, ('Runtime manifest required child is missing or misclassified: %s'):format(path)
        end
    end
    for path, row in pairs(rows) do
        if REQUIRED_RUNTIME_PATHS[path] == nil and row.kind ~= 'mesh' then
            return nil, ('Runtime manifest contains an unexpected child: %s'):format(path)
        end
    end
    return rows
end

local function parse_graph(bytes, sha256)
    if type(bytes) ~= 'string' or bytes:sub(1, 3) == '\239\187\191' or bytes:sub(-1) ~= '\n' then
        return nil, 'Objective navigation graph must be UTF-8 bytes without BOM and end in LF.'
    end
    local rows = {}
    local by_id = {}
    local position = 1
    local line_number = 0
    while position <= #bytes do
        local ending = bytes:find('\n', position, true)
        if ending == nil then break end
        local raw = bytes:sub(position, ending)
        local body = raw:sub(1, -2)
        if body:sub(-1) == '\r' then body = body:sub(1, -2) end
        position = ending + 1
        line_number = line_number + 1
        if line_number == 1 then
            if body ~= GRAPH_HEADER then return nil, 'Objective navigation graph header mismatch.' end
        elseif body ~= '' then
            local fields = split_tabs(body)
            if #fields ~= 15 and #fields ~= 16 then
                return nil, ('Objective navigation graph row %d has a malformed field set.'):format(line_number)
            end
            local edge_id = tonumber(fields[1])
            local from_zone = tonumber(fields[2])
            local to_zone = tonumber(fields[8])
            local coordinates = {
                tonumber(fields[5]), tonumber(fields[6]), tonumber(fields[7]),
                tonumber(fields[11]), tonumber(fields[12]), tonumber(fields[13]),
            }
            if not nonnegative_integer(edge_id) or not nonnegative_integer(from_zone)
                or not nonnegative_integer(to_zone) or by_id[edge_id] ~= nil
            then
                return nil, ('Objective navigation graph row %d has an invalid or duplicate identity.'):format(line_number)
            end
            for _, coordinate in ipairs(coordinates) do
                if not finite_number(coordinate) then
                    return nil, ('Objective navigation graph row %d has a non-finite coordinate.'):format(line_number)
                end
            end
            local hash_ok, row_digest = pcall(sha256, raw)
            if not hash_ok or not canonical_sha256(row_digest) then
                return nil, ('Objective navigation graph row %d could not be hashed safely.'):format(line_number)
            end
            local row = {
                zoneline_id = edge_id,
                from_zone = from_zone,
                from_name = trim(fields[3]),
                from_code = trim(fields[4]),
                from_x = coordinates[1], from_z = coordinates[2], from_y = coordinates[3],
                to_zone = to_zone,
                to_name = trim(fields[9]),
                to_code = trim(fields[10]),
                to_x = coordinates[4], to_z = coordinates[5], to_y = coordinates[6],
                source = trim(fields[14]), confidence = trim(fields[15]), note = trim(fields[16] or ''),
                row_sha256 = row_digest,
            }
            rows[#rows + 1] = row
            by_id[edge_id] = row
        end
    end
    if line_number == 0 then return nil, 'Objective navigation graph is empty.' end
    return { rows = rows, by_id = by_id }
end

local function parse_destinations(bytes, sha256)
    if type(bytes) ~= 'string' or bytes:sub(1, 3) == '\239\187\191' or bytes:sub(-1) ~= '\n' then
        return nil, 'Objective destination catalogue must be UTF-8 bytes without BOM and end in LF.'
    end
    local rows, by_id = {}, {}
    local position, line_number = 1, 0
    while position <= #bytes do
        local ending = bytes:find('\n', position, true)
        if ending == nil then break end
        local raw = bytes:sub(position, ending)
        local body = raw:sub(1, -2)
        if body:sub(-1) == '\r' then body = body:sub(1, -2) end
        position = ending + 1
        line_number = line_number + 1
        if body ~= '' and not body:match('^%s*#') then
            local fields = split_tabs(body)
            if #fields ~= 7 and #fields ~= 9 and #fields ~= 13 then
                return nil, ('Objective destination row %d has a malformed field set.'):format(line_number)
            end
            local zone = tonumber(fields[1])
            local x, z, y = tonumber(fields[3]), tonumber(fields[4]), tonumber(fields[5])
            if not nonnegative_integer(zone) or not finite_number(x)
                or not finite_number(z) or not finite_number(y)
            then return nil, ('Objective destination row %d has malformed geometry.'):format(line_number) end
            local spawn_ids = {}
            if #fields == 13 and fields[12] ~= '' then
                local prior = nil
                for value in fields[12]:gmatch('[^,]+') do
                    local spawn_id = tonumber(value)
                    if not nonnegative_integer(spawn_id) or (prior ~= nil and spawn_id <= prior) then
                        return nil, ('Objective destination row %d has unsorted spawn identities.'):format(line_number)
                    end
                    spawn_ids[#spawn_ids + 1] = spawn_id
                    prior = spawn_id
                end
            end
            local hash_ok, row_digest = pcall(sha256, raw)
            if not hash_ok or not canonical_sha256(row_digest) then
                return nil, ('Objective destination row %d could not be hashed safely.'):format(line_number)
            end
            local row = {
                zone = zone, name = trim(fields[2]), x = x, z = z, y = y,
                kind = trim(fields[6]), source = trim(fields[7]),
                confidence = #fields >= 9 and trim(fields[8]) or '',
                section = #fields >= 9 and trim(fields[9]) or '',
                destination_id = #fields == 13 and trim(fields[10]) or '',
                raw_identity = #fields == 13 and trim(fields[11]) or '',
                raw_spawn_ids = spawn_ids,
                cluster_policy_version = #fields == 13 and trim(fields[13]) or '',
                row_sha256 = row_digest,
            }
            if row.destination_id ~= '' then
                if by_id[row.destination_id] ~= nil then
                    return nil, ('Objective destination ID is duplicated: %s'):format(row.destination_id)
                end
                by_id[row.destination_id] = row
            end
            rows[#rows + 1] = row
        end
    end
    return { rows = rows, by_id = by_id }
end

local function point_is_finite(point)
    return type(point) == 'table'
        and finite_number(point.x) and finite_number(point.z) and finite_number(point.y)
end

local function point_distance(first, second)
    local dx, dz, dy = first.x - second.x, first.z - second.z, first.y - second.y
    return math.sqrt((dx * dx) + (dz * dz) + (dy * dy))
end

local function policy_thresholds(policy)
    local thresholds = type(policy) == 'table' and policy.thresholds or nil
    if type(thresholds) ~= 'table' then return nil end
    for _, field in ipairs({
        'endpoint_epsilon_yalms', 'maximum_segment_length_yalms',
        'minimum_endpoint_clearance_yalms', 'minimum_waypoint_clearance_yalms',
        'transition_corridor_radius_yalms',
    }) do
        if not finite_number(thresholds[field]) or thresholds[field] <= 0 then return nil end
    end
    if not positive_integer(thresholds.maximum_waypoint_count) or thresholds.maximum_waypoint_count < 2 then
        return nil
    end
    return thresholds
end

local function point_segment_distance_2d(point, first, second)
    local dx, dz = second.x - first.x, second.z - first.z
    local denominator = (dx * dx) + (dz * dz)
    if denominator == 0 then
        local px, pz = point.x - first.x, point.z - first.z
        return math.sqrt((px * px) + (pz * pz))
    end
    local ratio = (((point.x - first.x) * dx) + ((point.z - first.z) * dz)) / denominator
    ratio = math.max(0, math.min(1, ratio))
    local px = point.x - (first.x + (ratio * dx))
    local pz = point.z - (first.z + (ratio * dz))
    return math.sqrt((px * px) + (pz * pz))
end

local function crosses_transition(waypoints, transition, radius, zone)
    if type(transition) ~= 'table' then return nil end
    if transition.zone ~= nil and tonumber(transition.zone) ~= tonumber(zone) then return false end
    local pre, post = transition.pre_anchor, transition.post_anchor
    if not point_is_finite(pre) or not point_is_finite(post) then return nil end
    local lower, upper = math.min(pre.y, post.y), math.max(pre.y, post.y)
    local center = { x = (pre.x + post.x) / 2, z = (pre.z + post.z) / 2 }
    for index = 2, #waypoints do
        local first, second = waypoints[index - 1], waypoints[index]
        local segment_lower, segment_upper = math.min(first.y, second.y), math.max(first.y, second.y)
        if segment_upper >= lower and segment_lower <= upper
            and point_segment_distance_2d(center, first, second) <= radius
        then return true end
    end
    return false
end

local function classify_exact_leg(policy, request, observation, declared_transitions)
    local thresholds = policy_thresholds(policy)
    if thresholds == nil or type(request) ~= 'table' or type(observation) ~= 'table'
        or not point_is_finite(request.start) or not point_is_finite(request['end'])
    then return 'malformed-observation' end
    if not nonnegative_integer(request.zone) then return 'endpoint-zone' end
    if type(observation.start_valid) ~= 'boolean' or type(observation.end_valid) ~= 'boolean'
        or type(observation.fallback_used) ~= 'boolean'
    then return 'malformed-observation' end
    if observation.status == 'tool-error' then return 'tool-error' end
    if not observation.start_valid then return 'start-invalid' end
    if not observation.end_valid then return 'end-invalid' end
    if observation.fallback_used then return 'closest-path-forbidden' end
    if observation.status ~= 'exact-path' then return 'no-exact-path' end
    if not nonnegative_integer(observation.waypoint_count) then return 'waypoint-count-mismatch' end
    if observation.waypoint_count > thresholds.maximum_waypoint_count then
        return 'waypoint-count-excessive'
    end
    if not exact_array(observation.waypoints)
        or observation.waypoint_count ~= #observation.waypoints
    then return 'waypoint-count-mismatch' end
    if #observation.waypoints < 2 then return 'too-few-waypoints' end
    for _, waypoint in ipairs(observation.waypoints) do
        if not point_is_finite(waypoint) or not finite_number(waypoint.clearance)
            or waypoint.clearance < 0
        then return 'waypoint-malformed' end
        if waypoint.zone ~= nil
            and tonumber(waypoint.zone) ~= request.zone
        then return 'waypoint-zone' end
    end
    for _, point in ipairs({ request.start, request['end'] }) do
        if point.zone ~= nil and tonumber(point.zone) ~= request.zone then return 'endpoint-zone' end
    end
    local first = observation.waypoints[1]
    local last = observation.waypoints[#observation.waypoints]
    local actual_first = point_distance(request.start, first)
    local actual_last = point_distance(request['end'], last)
    if not finite_number(observation.first_endpoint_error)
        or not finite_number(observation.last_endpoint_error)
    then return 'endpoint-error-recomputed' end
    if math.max(actual_first, actual_last, observation.first_endpoint_error,
        observation.last_endpoint_error) > thresholds.endpoint_epsilon_yalms
    then return 'endpoint-error' end
    if math.abs(actual_first - observation.first_endpoint_error) > 0.000001
        or math.abs(actual_last - observation.last_endpoint_error) > 0.000001
    then return 'endpoint-error-recomputed' end
    local minimum = first.clearance
    for _, waypoint in ipairs(observation.waypoints) do minimum = math.min(minimum, waypoint.clearance) end
    if not finite_number(observation.minimum_waypoint_clearance)
        or math.abs(minimum - observation.minimum_waypoint_clearance) > 0.000001
    then return 'waypoint-clearance-recomputed' end
    if minimum < thresholds.minimum_waypoint_clearance_yalms then return 'waypoint-clearance' end
    if not finite_number(observation.start_clearance) or not finite_number(observation.end_clearance)
    then return 'endpoint-clearance' end
    if math.min(observation.start_clearance, observation.end_clearance,
        first.clearance, last.clearance) < thresholds.minimum_endpoint_clearance_yalms
    then return 'endpoint-clearance' end
    local length = 0
    for index = 2, #observation.waypoints do
        local segment = point_distance(observation.waypoints[index - 1], observation.waypoints[index])
        if segment > thresholds.maximum_segment_length_yalms then return 'segment-too-long' end
        length = length + segment
    end
    if not finite_number(observation.path_length)
        or math.abs(length - observation.path_length) > 0.000000001
    then return 'path-length-mismatch' end
    if declared_transitions ~= nil and not exact_array(declared_transitions) then
        return 'transition-malformed'
    end
    for _, transition in ipairs(declared_transitions or {}) do
        local crossing = crosses_transition(
            observation.waypoints, transition, thresholds.transition_corridor_radius_yalms, request.zone)
        if crossing == nil then return 'transition-malformed' end
        if crossing then return 'requires-transition' end
    end
    return 'mesh-proven'
end

module.classify_exact_leg = classify_exact_leg

function Runtime:is_ready()
    local state = private(self)
    return state ~= nil and state.ready == true
end

function Runtime:failure_reason()
    local state = private(self)
    return state ~= nil and state.failure_reason or ''
end

function Runtime:_block(reason)
    local state = private(self)
    state.ready = false
    state.failure_reason = tostring(reason or 'Objective route runtime initialization failed.')
    return false
end

function Runtime:_read_accepted(path, expected_digest, label)
    local state = private(self)
    local ok, bytes, digest, identity, reason = pcall(
        state.file_hasher.read_and_hash_file,
        state.file_hasher,
        path)
    if not ok then
        return nil, nil, ('%s read failed: %s'):format(label, tostring(bytes))
    end
    if type(bytes) ~= 'string' or not canonical_sha256(digest) or not valid_identity(identity) then
        return nil, nil, ('%s read/hash result is malformed: %s'):format(label, tostring(reason or digest))
    end
    local hash_ok, recomputed, hash_reason = pcall(state.sha256, bytes)
    if not hash_ok or not canonical_sha256(recomputed) then
        return nil, nil, ('%s byte hash failed: %s'):format(label, tostring(hash_ok and hash_reason or recomputed))
    end
    if recomputed ~= digest or (expected_digest ~= nil and recomputed ~= expected_digest) then
        return nil, nil, ('%s hash mismatch.'):format(label)
    end
    return bytes, identity
end

function Runtime:_record_accepted(relative_path, path, digest, identity)
    local state = private(self)
    state.accepted_files[relative_path] = {
        path = path,
        sha256 = digest,
        identity = deep_copy(identity),
    }
end

function Runtime:_verify_current(relative_path, label)
    local state = private(self)
    local accepted = state.accepted_files[relative_path]
    local manifest_row = state.manifest_rows[relative_path]
    if accepted == nil or manifest_row == nil then
        return nil, ('%s has no accepted runtime identity.'):format(label)
    end
    local path_ok, path = pcall(state.path_for, relative_path)
    if not path_ok or path ~= accepted.path then
        return nil, ('%s canonical path changed.'):format(label)
    end
    local bytes, identity, reason = self:_read_accepted(path, manifest_row.sha256, label)
    if bytes == nil then return nil, reason end
    if not identity_equal(identity, accepted.identity) then
        return nil, ('%s file identity changed after validation.'):format(label)
    end
    return true
end

function Runtime:_accept_static_child(relative_path, label)
    local state = private(self)
    local row = state.manifest_rows[relative_path]
    local path_ok, path = pcall(state.path_for, relative_path)
    if row == nil or not path_ok or type(path) ~= 'string' or path == '' then
        return nil, ('%s path is unavailable.'):format(label)
    end
    local bytes, identity, reason = self:_read_accepted(path, row.sha256, label)
    if bytes == nil then return nil, reason end
    self:_record_accepted(relative_path, path, row.sha256, identity)
    return bytes
end

function Runtime:_verify_manifest_current()
    local state = private(self)
    local accepted = state.accepted_manifest
    local bytes, identity, reason = self:_read_accepted(
        accepted.path, state.manifest_digest, 'Runtime manifest')
    if bytes == nil then return nil, reason end
    if not identity_equal(identity, accepted.identity) then
        return nil, 'Runtime manifest file identity changed after validation.'
    end
    return true
end

function Runtime:_revalidate_contract_files(contract)
    local manifest_ok, manifest_error = self:_verify_manifest_current()
    if not manifest_ok then return nil, manifest_error end
    for _, relative_path in ipairs({
        'data/ffxi-nav-destinations.tsv',
        'data/ffxi-nav-zoneline-graph.tsv',
        'modules/mission_quest_route_contracts.lua',
        'modules/mission_quest_route_policy.lua',
        'modules/mission_quest_route_runtime.lua',
        'modules/mission_quest_route_transitions.lua',
        'third_party/FFXI-NavMesh-Builder/FFXINAV.dll',
        'third_party/xiNavmeshes/' .. contract.expected_inputs.mesh_name,
    }) do
        local ok, reason = self:_verify_current(relative_path, relative_path)
        if not ok then return nil, reason end
    end
    return true
end

function Runtime:_validate_native_binding(contract)
    local state = private(self)
    if type(state.native_integrity_state) ~= 'function' then
        return nil, 'The rooted native integrity observer is unavailable.'
    end
    local ok, snapshot = pcall(state.native_integrity_state)
    if not ok or type(snapshot) ~= 'table' or snapshot.trusted ~= true
        or type(snapshot.dll) ~= 'table' or type(snapshot.mesh) ~= 'table'
    then return nil, 'The rooted native integrity observer is not trusted.' end
    local dll_relative = 'third_party/FFXI-NavMesh-Builder/FFXINAV.dll'
    local mesh_relative = 'third_party/xiNavmeshes/' .. contract.expected_inputs.mesh_name
    local dll = state.accepted_files[dll_relative]
    local mesh = state.accepted_files[mesh_relative]
    if dll == nil or mesh == nil
        or snapshot.dll.path ~= dll.path or snapshot.dll.sha256 ~= dll.sha256
        or not identity_equal(snapshot.dll.identity, dll.identity)
        or snapshot.mesh.path ~= mesh.path or snapshot.mesh.sha256 ~= mesh.sha256
        or not identity_equal(snapshot.mesh.identity, mesh.identity)
        or snapshot.mesh.mesh_name ~= contract.expected_inputs.mesh_name
        or tonumber(snapshot.mesh.zone) ~= contract.zone
    then return nil, 'The loaded objective DLL or mesh identity is stale.' end
    return true
end

function Runtime:_load_generated(relative_path)
    local state = private(self)
    local row = state.manifest_rows[relative_path]
    local path_ok, path = pcall(state.path_for, relative_path)
    if not path_ok or type(path) ~= 'string' or path == '' then
        return nil, ('Runtime child path failed for %s: %s'):format(relative_path, tostring(path))
    end
    local bytes, _identity, read_error = self:_read_accepted(path, row.sha256, relative_path)
    if bytes == nil then
        return nil, read_error
    end
    local load_ok, chunk, load_error = pcall(
        state.load_chunk,
        bytes,
        '@' .. relative_path,
        state.module_environment)
    if not load_ok or type(chunk) ~= 'function' then
        return nil, ('Runtime child compilation failed for %s: %s'):format(
            relative_path,
            tostring(load_ok and load_error or chunk))
    end
    local execute_ok, value = pcall(chunk)
    if not execute_ok or type(value) ~= 'table' then
        return nil, ('Runtime child execution failed for %s: %s'):format(relative_path, tostring(value))
    end
    self:_record_accepted(relative_path, path, row.sha256, _identity)
    return value
end

function Runtime:_validate_policy(policy)
    if type(policy) ~= 'table' or policy.schema_version ~= EXPECTED_POLICY_SCHEMA then
        return nil, 'Objective route policy schema mismatch.'
    end
    if policy.policy_revision ~= EXPECTED_POLICY_REVISION then
        return nil, 'Objective route policy revision mismatch.'
    end
    if not canonical_sha256(policy.policy_sha256) then
        return nil, 'Objective route policy semantic SHA-256 is malformed.'
    end
    if policy.probe_protocol ~= EXPECTED_PROBE_PROTOCOL or policy.probe_schema ~= EXPECTED_PROBE_SCHEMA then
        return nil, 'Objective route policy probe schema or protocol mismatch.'
    end
    if type(policy.thresholds) ~= 'table' or type(policy.fixtures) ~= 'table' then
        return nil, 'Objective route policy tables are malformed.'
    end
    return true
end

function Runtime:_validate_transitions(bundle)
    if type(bundle) ~= 'table' or bundle.schema_version ~= 2
        or not canonical_sha256(bundle.source_registry_sha256)
        or not exact_array(bundle.definitions)
        or not exact_array(bundle.authorized)
    then
        return nil, 'Objective route transition index is malformed.'
    end
    local field_count = 0
    for field in pairs(bundle) do
        if field ~= 'schema_version' and field ~= 'source_registry_sha256'
            and field ~= 'definitions' and field ~= 'authorized'
        then return nil, 'Objective route transition wrapper field set is not exact.' end
        field_count = field_count + 1
    end
    if field_count ~= 4 then return nil, 'Objective route transition wrapper field set is incomplete.' end
    local definitions_by_id = {}
    for _, transition in ipairs(bundle.definitions) do
        local transition_id = type(transition) == 'table' and transition.transition_id or nil
        if not nonempty(transition_id) or definitions_by_id[transition_id] ~= nil then
            return nil, 'Objective route transition definition IDs must be nonempty and unique.'
        end
        if not nonnegative_integer(transition.zone)
            or not point_is_finite(transition.pre_anchor)
            or not point_is_finite(transition.post_anchor)
        then return nil, 'Objective route transition definition geometry is malformed.' end
        definitions_by_id[transition_id] = transition
    end
    local authorized_by_id = {}
    for _, transition in ipairs(bundle.authorized) do
        local transition_id = type(transition) == 'table' and transition.transition_id or nil
        if not nonempty(transition_id) or authorized_by_id[transition_id] ~= nil
            or not deep_equal(transition, definitions_by_id[transition_id])
        then return nil, 'Authorized objective transitions must exactly match unique rooted definitions.' end
        authorized_by_id[transition_id] = transition
    end
    local state = private(self)
    state.transitions_by_id = authorized_by_id
    state.transition_definitions_by_id = definitions_by_id
    state.transition_bundle = bundle
    state.transitions = bundle.authorized
    state.transition_definitions = bundle.definitions
    return true
end

function Runtime:_validate_contract_inputs(contract)
    local state = private(self)
    local inputs = contract.expected_inputs
    if type(inputs) ~= 'table' then
        return nil, 'Objective route contract expected inputs are missing.'
    end
    local expected = {}
    for _, field in ipairs(CONTRACT_INPUT_FIELDS) do expected[field] = true end
    local count = 0
    for field in pairs(inputs) do
        if not expected[field] then
            return nil, 'Objective route contract expected input set is not exact.'
        end
        count = count + 1
    end
    if count ~= #CONTRACT_INPUT_FIELDS then
        return nil, 'Objective route contract expected input set is incomplete.'
    end
    for _, field in ipairs({
        'mesh_sha256', 'ffxinav_sha256', 'policy_sha256', 'transition_registry_sha256',
        'destinations_sha256', 'graph_sha256', 'destination_row_sha256', 'ingress_row_sha256',
    }) do
        if not canonical_sha256(inputs[field]) then
            return nil, ('Objective route contract %s is malformed.'):format(field)
        end
    end
    if inputs.policy_sha256 ~= state.policy.policy_sha256 then
        return nil, 'Objective route contract policy semantic hash is stale.'
    end
    if inputs.transition_registry_sha256 ~= state.transition_bundle.source_registry_sha256 then
        return nil, 'Objective route contract transition registry hash is stale.'
    end
    if inputs.probe_protocol ~= state.policy.probe_protocol
        or inputs.probe_schema ~= state.policy.probe_schema
        or inputs.policy_revision ~= state.policy.policy_revision
        or not nonempty(inputs.mesh_name)
        or inputs.zone_mesh_name ~= inputs.mesh_name
    then
        return nil, 'Objective route contract policy or mesh binding is stale.'
    end
    local destinations = state.manifest_rows['data/ffxi-nav-destinations.tsv']
    local graph = state.manifest_rows['data/ffxi-nav-zoneline-graph.tsv']
    local dll = state.manifest_rows['third_party/FFXI-NavMesh-Builder/FFXINAV.dll']
    if inputs.destinations_sha256 ~= destinations.sha256
        or inputs.graph_sha256 ~= graph.sha256
        or inputs.ffxinav_sha256 ~= dll.sha256
    then
        return nil, 'Objective route contract rooted catalogue or DLL hash is stale.'
    end
    local mesh_path = 'third_party/xiNavmeshes/' .. inputs.mesh_name
    local mesh = state.manifest_rows[mesh_path]
    if mesh == nil or mesh.kind ~= 'mesh' or mesh.mesh_name ~= inputs.mesh_name
        or tonumber(mesh.zone) ~= contract.zone or mesh.sha256 ~= inputs.mesh_sha256
    then
        return nil, 'Objective route contract rooted mesh binding is unavailable.'
    end
    return true
end

function Runtime:_validate_contracts(contracts)
    if not exact_array(contracts) then
        return nil, 'Objective route contract index is malformed.'
    end
    local by_id = {}
    local by_key = {}
    for _, source_contract in ipairs(contracts) do
        local contract = deep_copy(source_contract)
        if type(contract) ~= 'table' or contract.schema ~= 2 or contract.route_ready ~= true then
            return nil, 'Objective route contract schema or ready state is invalid.'
        end
        local contract_id = contract.contract_id
        local digest = type(contract_id) == 'string' and contract_id:match('^route:v2:([0-9a-f]+)$') or nil
        if not canonical_sha256(digest) or by_id[contract_id] ~= nil then
            return nil, 'Objective route contract IDs must be canonical and unique.'
        end
        if not nonempty(contract.candidate_id) or not nonempty(contract.action_id)
            or type(contract.group_id) ~= 'string' or not nonempty(contract.destination_id)
            or type(contract.zone) ~= 'number' or contract.zone < 0 or contract.zone ~= math.floor(contract.zone)
            or type(contract.destination) ~= 'table' or type(contract.local_leg) ~= 'table'
            or not exact_array(contract.authorized_directed_prefix)
            or #contract.authorized_directed_prefix == 0
            or not exact_array(contract.required_transition_ids)
        then
            return nil, 'Objective route contract identity or geometry is malformed.'
        end
        local inputs_ok, inputs_error = self:_validate_contract_inputs(contract)
        if not inputs_ok then return nil, inputs_error end
        for _, transition_id in ipairs(contract.required_transition_ids) do
            if not nonempty(transition_id) or private(self).transitions_by_id[transition_id] == nil then
                return nil, 'Objective route contract references an unrooted transition.'
            end
        end
        local prefix, prefix_error = self:_validated_contract_prefix(contract)
        if prefix == nil then return nil, prefix_error end
        if contract.expected_inputs.ingress_row_sha256 ~= prefix[#prefix].row_sha256 then
            return nil, 'Objective route contract ingress row hash is stale.'
        end
        local rooted_destination = private(self).destinations_by_id[contract.destination_id]
        local destination = contract.destination
        if rooted_destination == nil
            or rooted_destination.zone ~= contract.zone
            or rooted_destination.name ~= destination.name
            or rooted_destination.x ~= destination.x
            or rooted_destination.z ~= destination.z
            or rooted_destination.y ~= destination.y
            or rooted_destination.kind ~= destination.kind
            or rooted_destination.destination_id ~= destination.destination_id
            or rooted_destination.raw_identity ~= destination.raw_identity
            or rooted_destination.cluster_policy_version ~= destination.cluster_policy_version
            or not exact_array(destination.raw_spawn_ids)
            or #rooted_destination.raw_spawn_ids ~= #destination.raw_spawn_ids
        then return nil, 'Objective route contract destination differs from the rooted catalogue.' end
        for index, spawn_id in ipairs(rooted_destination.raw_spawn_ids) do
            if spawn_id ~= destination.raw_spawn_ids[index] then
                return nil, 'Objective route contract spawn identities differ from the rooted catalogue.'
            end
        end
        if contract.expected_inputs.destination_row_sha256 ~= rooted_destination.row_sha256 then
            return nil, 'Objective route contract destination row hash is stale.'
        end
        by_id[contract_id] = contract
        local key = contract_key(
            contract.candidate_id,
            contract.action_id,
            contract.group_id,
            contract.destination_id)
        by_key[key] = by_key[key] or {}
        by_key[key][#by_key[key] + 1] = contract
    end
    for _, matches in pairs(by_key) do
        table.sort(matches, function(left, right)
            local left_length = tonumber(left.local_leg.observations and left.local_leg.observations.path_length)
                or math.huge
            local right_length = tonumber(right.local_leg.observations and right.local_leg.observations.path_length)
                or math.huge
            if left_length ~= right_length then return left_length < right_length end
            return left.contract_id < right.contract_id
        end)
    end
    local state = private(self)
    state.contracts_by_id = by_id
    state.contracts_by_key = by_key
    state.contracts = {}
    for _, contract in pairs(by_id) do state.contracts[#state.contracts + 1] = contract end
    table.sort(state.contracts, function(left, right) return left.contract_id < right.contract_id end)
    return true
end

function Runtime:_transition_equivalent(edge, contract)
    local state = private(self)
    local required = {}
    for _, transition_id in ipairs(contract.required_transition_ids or {}) do required[transition_id] = true end
    for transition_id, transition in pairs(state.transitions_by_id or {}) do
        if required[transition_id] == true
            and transition.reviewed == true
            and tonumber(transition.equivalent_zoneline_id) == edge.zoneline_id
            and tonumber(transition.from_zone) == edge.from_zone
            and tonumber(transition.to_zone) == edge.to_zone
            and type(state.transition_is_eligible) == 'function'
        then
            local ok, eligible = pcall(state.transition_is_eligible, transition, contract)
            if ok and eligible == true then return true end
        end
    end
    return false
end

function Runtime:_edge_authorized(edge, contract)
    return type(edge) == 'table'
        and (edge.confidence == 'proven' or self:_transition_equivalent(edge, contract))
end

function Runtime:_validated_contract_prefix(contract)
    local state = private(self)
    local prefix = {}
    local prior = nil
    for index, edge_id in ipairs(contract.authorized_directed_prefix or {}) do
        if not nonnegative_integer(edge_id) then
            return nil, 'Objective route contract directed prefix has a malformed edge ID.'
        end
        local edge = state.graph_by_id and state.graph_by_id[edge_id] or nil
        if edge == nil then return nil, 'Objective route contract directed prefix is absent from the rooted graph.' end
        if not self:_edge_authorized(edge, contract) then
            return nil, 'Objective route contract directed prefix contains an edge that is not proven.'
        end
        if prior ~= nil and prior.to_zone ~= edge.from_zone then
            return nil, 'Objective route contract directed prefix is not contiguous.'
        end
        prefix[index] = edge
        prior = edge
    end
    if #prefix == 0 or prefix[#prefix].to_zone ~= contract.zone then
        return nil, 'Objective route contract directed prefix does not reach its target zone.'
    end
    return prefix
end

function Runtime:find_objective_zone_path(start_zone, contract_id)
    if not self:is_ready() then return nil, self:failure_reason() end
    if not nonnegative_integer(start_zone) or not nonempty(contract_id) then
        return nil, 'Objective zone path inputs are malformed.'
    end
    local state = private(self)
    local contract = state.contracts_by_id[contract_id]
    if contract == nil then return nil, 'The rooted objective route contract is unavailable.' end
    local files_ok, files_error = self:_revalidate_contract_files(contract)
    if not files_ok then return nil, files_error end
    local prefix, prefix_error = self:_validated_contract_prefix(contract)
    if prefix == nil then return nil, prefix_error end
    if start_zone == contract.zone then return {} end
    for index, edge in ipairs(prefix) do
        if start_zone == edge.from_zone then
            local suffix = {}
            for suffix_index = index, #prefix do suffix[#suffix + 1] = deep_copy(prefix[suffix_index]) end
            return suffix
        end
    end

    local entry_zone = prefix[1].from_zone
    local adjacency = {}
    for _, edge in ipairs(state.graph_rows or {}) do
        if self:_edge_authorized(edge, contract) then
            adjacency[edge.from_zone] = adjacency[edge.from_zone] or {}
            adjacency[edge.from_zone][#adjacency[edge.from_zone] + 1] = edge
        end
    end
    for _, edges in pairs(adjacency) do
        table.sort(edges, function(left, right)
            if left.zoneline_id ~= right.zoneline_id then return left.zoneline_id < right.zoneline_id end
            if left.to_zone ~= right.to_zone then return left.to_zone < right.to_zone end
            return left.from_zone < right.from_zone
        end)
    end
    local queue, head = { start_zone }, 1
    local visited = { [start_zone] = true }
    local prior_zone, prior_edge = {}, {}
    while head <= #queue and not visited[entry_zone] do
        local zone = queue[head]
        head = head + 1
        for _, edge in ipairs(adjacency[zone] or {}) do
            if not visited[edge.to_zone] then
                visited[edge.to_zone] = true
                prior_zone[edge.to_zone] = zone
                prior_edge[edge.to_zone] = edge
                queue[#queue + 1] = edge.to_zone
            end
        end
    end
    if not visited[entry_zone] then
        return nil, 'No proven directed objective zone path reaches this route contract.'
    end
    local reverse = {}
    local zone = entry_zone
    while zone ~= start_zone do
        local edge = prior_edge[zone]
        if edge == nil then return nil, 'The proven objective zone path could not be reconstructed.' end
        reverse[#reverse + 1] = edge
        zone = prior_zone[zone]
    end
    local result = {}
    for index = #reverse, 1, -1 do result[#result + 1] = reverse[index] end
    for _, edge in ipairs(prefix) do result[#result + 1] = edge end
    local prior_target = start_zone
    for _, edge in ipairs(result) do
        if edge.from_zone ~= prior_target or not self:_edge_authorized(edge, contract) then
            return nil, 'The proven objective zone path changed during full-prefix revalidation.'
        end
        prior_target = edge.to_zone
    end
    if prior_target ~= contract.zone then
        return nil, 'The proven objective zone path does not reach the contract target.'
    end
    return deep_copy(result)
end

local function native_call(native, method, ...)
    local callable = type(native) == 'table' and native[method] or nil
    if type(callable) ~= 'function' then return false, 'native method is unavailable: ' .. method end
    return pcall(callable, native, ...)
end

function Runtime:compute_exact_objective_leg(request, native_override, transition_override)
    if not self:is_ready() then return nil, self:failure_reason() end
    local state = private(self)
    if native_override ~= nil or transition_override ~= nil then
        return nil, 'Per-call objective native or transition overrides are forbidden.'
    end
    local native = state.objective_native
    if type(native) ~= 'table' or type(request) ~= 'table'
        or not nonnegative_integer(request.zone)
        or not nonempty(request.objective_route_contract_id)
        or not point_is_finite(request.start) or not point_is_finite(request['end'])
    then return nil, 'malformed-request' end
    if request.start.zone ~= nil and tonumber(request.start.zone) ~= request.zone
        or request['end'].zone ~= nil and tonumber(request['end'].zone) ~= request.zone
    then return nil, 'endpoint-zone' end
    local contract = state.contracts_by_id[request.objective_route_contract_id]
    if contract == nil or contract.zone ~= request.zone then
        return nil, 'objective-contract-zone'
    end

    local observation = {
        status = 'tool-error',
        start_valid = false,
        end_valid = false,
        fallback_used = false,
        waypoint_count = 0,
        waypoints = {},
        first_endpoint_error = 0,
        last_endpoint_error = 0,
        start_clearance = 0,
        end_clearance = 0,
        minimum_waypoint_clearance = 0,
        path_length = 0,
    }
    local function revalidate_integrity()
        local files_ok, files_error = self:_revalidate_contract_files(contract)
        if not files_ok then return nil, files_error end
        return self:_validate_native_binding(contract)
    end
    local function checked_native_call(method, ...)
        local integrity_ok, integrity_error = revalidate_integrity()
        if not integrity_ok then return nil, nil, integrity_error end
        local call_ok, value = native_call(native, method, ...)
        return call_ok, value
    end
    local function integrity_failure(reason)
        observation.reason = reason
        return nil, reason, observation
    end
    local function finish()
        local integrity_ok, integrity_error = revalidate_integrity()
        if not integrity_ok then return integrity_failure(integrity_error) end
        local reason = classify_exact_leg(
            state.policy, request, observation, state.transition_definitions)
        observation.reason = reason
        if reason == 'mesh-proven' then return deep_copy(observation.waypoints), '', observation end
        return nil, reason, observation
    end
    local native_start = { x = request.start.x, y = request.start.y, z = request.start.z }
    local native_end = { x = request['end'].x, y = request['end'].y, z = request['end'].z }

    local ok, value, integrity_error = checked_native_call('is_valid_position', native_start)
    if integrity_error ~= nil then return integrity_failure(integrity_error) end
    if not ok or type(value) ~= 'boolean' then return finish() end
    observation.start_valid = value
    if not value then observation.status = 'start-invalid'; return finish() end

    ok, value, integrity_error = checked_native_call('get_distance_to_wall', native_start)
    if integrity_error ~= nil then return integrity_failure(integrity_error) end
    if not ok or not finite_number(value) or value < 0 then return finish() end
    observation.start_clearance = value

    ok, value, integrity_error = checked_native_call('is_valid_position', native_end)
    if integrity_error ~= nil then return integrity_failure(integrity_error) end
    if not ok or type(value) ~= 'boolean' then return finish() end
    observation.end_valid = value
    if not value then observation.status = 'end-invalid'; return finish() end

    ok, value, integrity_error = checked_native_call('get_distance_to_wall', native_end)
    if integrity_error ~= nil then return integrity_failure(integrity_error) end
    if not ok or not finite_number(value) or value < 0 then return finish() end
    observation.end_clearance = value

    ok, value, integrity_error = checked_native_call('find_path', native_start, native_end)
    if integrity_error ~= nil then return integrity_failure(integrity_error) end
    if not ok then return finish() end
    local maximum = state.policy.thresholds.maximum_waypoint_count
    local waypoints_ok, native_waypoints
    waypoints_ok, native_waypoints, integrity_error = checked_native_call('get_waypoints', maximum)
    if integrity_error ~= nil then return integrity_failure(integrity_error) end
    if not waypoints_ok or not exact_array(native_waypoints) then return finish() end

    observation.waypoint_count = #native_waypoints
    if #native_waypoints > maximum then
        observation.status = 'exact-path'
        return finish()
    end
    local copied = {}
    for index, native_point in ipairs(native_waypoints) do
        if type(native_point) ~= 'table' or not finite_number(native_point.x)
            or not finite_number(native_point.y) or not finite_number(native_point.z)
        then
            observation.status = 'exact-path'
            observation.waypoints = { {} }
            observation.waypoint_count = 1
            observation.reason = 'waypoint-malformed'
            return nil, 'waypoint-malformed', observation
        end
        copied[index] = {
            x = native_point.x,
            z = native_point.z,
            y = native_point.y,
            zone = native_point.zone == nil and request.zone or native_point.zone,
        }
    end
    observation.waypoints = copied
    observation.status = #copied >= 2 and 'exact-path' or 'no-exact-path'

    for _, point in ipairs(copied) do
        local native_point = { x = point.x, y = point.y, z = point.z }
        ok, value, integrity_error = checked_native_call('get_distance_to_wall', native_point)
        if integrity_error ~= nil then return integrity_failure(integrity_error) end
        if not ok or not finite_number(value) or value < 0 then
            observation.status = 'tool-error'
            return finish()
        end
        point.clearance = value
    end
    if #copied > 0 then
        observation.first_endpoint_error = point_distance(request.start, copied[1])
        observation.last_endpoint_error = point_distance(request['end'], copied[#copied])
        observation.minimum_waypoint_clearance = copied[1].clearance
        for _, point in ipairs(copied) do
            observation.minimum_waypoint_clearance = math.min(
                observation.minimum_waypoint_clearance, point.clearance)
        end
        for index = 2, #copied do
            observation.path_length = observation.path_length
                + point_distance(copied[index - 1], copied[index])
        end
    end
    return finish()
end

function Runtime:_initialize(options)
    local state = private(self)
    if not canonical_sha256(options.expected_manifest_sha256) then
        return self:_block('Expected objective route manifest SHA-256 is unavailable or malformed.')
    end
    if type(options.manifest_path) ~= 'string' or options.manifest_path == ''
        or type(options.path_for) ~= 'function'
        or type(options.file_hasher) ~= 'table'
        or type(options.file_hasher.read_and_hash_file) ~= 'function'
        or type(options.sha256) ~= 'function'
    then
        return self:_block('Objective route manifest loader dependencies are unavailable.')
    end
    state.file_hasher = options.file_hasher
    state.sha256 = options.sha256
    state.path_for = options.path_for
    state.transition_is_eligible = options.transition_is_eligible
    state.objective_native = options.objective_native
    state.native_integrity_state = options.native_integrity_state
    state.accepted_files = {}
    state.load_chunk = type(options.load_chunk) == 'function' and options.load_chunk
        or function(bytes, name, environment)
            local chunk, reason = loadstring(bytes, name)
            if chunk ~= nil and environment ~= nil then setfenv(chunk, environment) end
            return chunk, reason
        end
    state.module_environment = options.module_environment

    local manifest_bytes, manifest_identity, manifest_error = self:_read_accepted(
        options.manifest_path,
        options.expected_manifest_sha256,
        'Runtime manifest')
    if manifest_bytes == nil then
        return self:_block(manifest_error)
    end
    local rows, parse_error = parse_manifest(manifest_bytes)
    if rows == nil then
        return self:_block(parse_error)
    end
    state.manifest_rows = deep_copy(rows)
    state.manifest_digest = options.expected_manifest_sha256
    state.accepted_manifest = {
        path = options.manifest_path,
        sha256 = options.expected_manifest_sha256,
        identity = deep_copy(manifest_identity),
    }

    local destination_row = rows['data/ffxi-nav-destinations.tsv']
    local destination_path_ok, destination_path = pcall(state.path_for, destination_row.relative_path)
    if not destination_path_ok or type(destination_path) ~= 'string' or destination_path == '' then
        return self:_block('Objective destination catalogue path is unavailable.')
    end
    local destination_bytes, destination_identity, destination_read_error = self:_read_accepted(
        destination_path, destination_row.sha256, 'Objective destination catalogue')
    if destination_bytes == nil then return self:_block(destination_read_error) end
    local destinations, destination_error = parse_destinations(destination_bytes, state.sha256)
    if destinations == nil then return self:_block(destination_error) end
    state.destination_rows = deep_copy(destinations.rows)
    state.destinations_by_id = {}
    for _, destination in ipairs(state.destination_rows) do
        if destination.destination_id ~= '' then
            state.destinations_by_id[destination.destination_id] = destination
        end
    end
    self:_record_accepted(
        destination_row.relative_path, destination_path, destination_row.sha256, destination_identity)

    local graph_row = rows['data/ffxi-nav-zoneline-graph.tsv']
    local graph_path_ok, graph_path = pcall(state.path_for, graph_row.relative_path)
    if not graph_path_ok or type(graph_path) ~= 'string' or graph_path == '' then
        return self:_block('Objective navigation graph path is unavailable.')
    end
    local graph_bytes, graph_identity, graph_read_error = self:_read_accepted(
        graph_path, graph_row.sha256, 'Objective navigation graph')
    if graph_bytes == nil then return self:_block(graph_read_error) end
    local graph, graph_error = parse_graph(graph_bytes, state.sha256)
    if graph == nil then return self:_block(graph_error) end
    state.graph_rows = deep_copy(graph.rows)
    state.graph_by_id = {}
    for _, edge in ipairs(state.graph_rows) do state.graph_by_id[edge.zoneline_id] = edge end
    self:_record_accepted(graph_row.relative_path, graph_path, graph_row.sha256, graph_identity)

    for _, static_child in ipairs({
        { 'modules/mission_quest_route_runtime.lua', 'Objective route runtime module' },
        { 'third_party/FFXI-NavMesh-Builder/FFXINAV.dll', 'Objective FFXINAV DLL' },
    }) do
        local accepted, accept_error = self:_accept_static_child(static_child[1], static_child[2])
        if accepted == nil then return self:_block(accept_error) end
    end

    local loaded = {}
    for _, relative_path in ipairs(GENERATED_MODULES) do
        local value, reason = self:_load_generated(relative_path)
        if value == nil then
            return self:_block(reason)
        end
        loaded[relative_path] = value
    end
    state.policy = deep_copy(loaded['modules/mission_quest_route_policy.lua'])
    local transition_bundle = deep_copy(loaded['modules/mission_quest_route_transitions.lua'])
    local contracts = deep_copy(loaded['modules/mission_quest_route_contracts.lua'])
    local policy_ok, policy_error = self:_validate_policy(state.policy)
    if not policy_ok then return self:_block(policy_error) end
    local transitions_ok, transitions_error = self:_validate_transitions(transition_bundle)
    if not transitions_ok then return self:_block(transitions_error) end
    local contracts_ok, contracts_error = self:_validate_contracts(contracts)
    if not contracts_ok then return self:_block(contracts_error) end
    local accepted_meshes = {}
    for _, contract in ipairs(state.contracts) do
        local mesh_relative = 'third_party/xiNavmeshes/' .. contract.expected_inputs.mesh_name
        if not accepted_meshes[mesh_relative] then
            local accepted, accept_error = self:_accept_static_child(mesh_relative, 'Objective zone mesh')
            if accepted == nil then return self:_block(accept_error) end
            accepted_meshes[mesh_relative] = true
        end
    end
    state.ready = true
    state.failure_reason = ''
    return true
end

function Runtime:authorize_start(selected, fresh, player)
    if not self:is_ready() then
        return nil, self:failure_reason(), 'blocked'
    end
    if type(selected) ~= 'table' or type(fresh) ~= 'table' then
        return nil, 'The current objective selection is unavailable.', 'blocked'
    end
    local owner_ok, owner_error = validate_objective_owner(selected, fresh)
    if not owner_ok then return nil, owner_error, 'blocked' end
    if selected.objective_instruction_only == true
        or selected.objective_classification == 'instruction-only'
    then
        if selected.objective_instruction_only == true
            and selected.objective_classification == 'instruction-only'
            and selected.objective_candidate_id == ''
            and selected.objective_group_id == ''
            and selected.objective_destination_id == ''
        then return fresh.objective_action_instruction, '', 'instruction' end
        return nil, 'The current objective instruction is not validated.', 'blocked'
    end
    if selected.objective_instruction_only ~= false
        or selected.objective_classification ~= 'catalogue-candidate'
        or not nonempty(selected.objective_candidate_id)
        or type(selected.objective_group_id) ~= 'string'
        or not nonempty(selected.objective_destination_id)
    then
        return nil, 'The current objective destination metadata is invalid.', 'blocked'
    end
    local matches = private(self).contracts_by_key[contract_key(
        fresh.objective_candidate_id,
        fresh.objective_action_id,
        fresh.objective_group_id,
        fresh.objective_destination_id)]
    if type(matches) ~= 'table' or #matches == 0 then
        return nil, 'No rooted route contract matches this objective destination.', 'blocked'
    end
    if type(player) ~= 'table' or not nonnegative_integer(player.zone)
        or not point_is_finite(player)
    then return nil, 'The current player position is unavailable.', 'blocked' end
    local eligible = {}
    local last_reason = ''
    for _, candidate_contract in ipairs(matches) do
        local files_ok, files_error = self:_revalidate_contract_files(candidate_contract)
        if files_ok then
            local zone_path, path_error = self:find_objective_zone_path(
                player.zone, candidate_contract.contract_id)
            if zone_path ~= nil then
                eligible[#eligible + 1] = candidate_contract
            else
                last_reason = path_error or last_reason
            end
        else
            last_reason = files_error or last_reason
        end
    end
    if #eligible == 0 then
        return nil, last_reason ~= '' and last_reason
            or 'No currently proven route contract starts from this zone.', 'blocked'
    end
    table.sort(eligible, function(left, right)
        local left_length = tonumber(left.local_leg.observations
            and left.local_leg.observations.path_length) or math.huge
        local right_length = tonumber(right.local_leg.observations
            and right.local_leg.observations.path_length) or math.huge
        if left_length ~= right_length then return left_length < right_length end
        return left.contract_id < right.contract_id
    end)
    local contract = eligible[1]
    local payload = deep_copy(contract.destination)
    payload.zone = contract.zone
    for _, field in ipairs(OBJECTIVE_OWNER_STRING_FIELDS) do
        payload[field] = fresh[field]
    end
    payload.objective_world_id = fresh.objective_world_id
    payload.objective_session_epoch = fresh.objective_session_epoch
    payload.objective_route_contract_id = contract.contract_id
    payload.objective_contract_snapshot = deep_copy(contract)
    return payload, '', 'ready'
end

function module.new(options)
    options = type(options) == 'table' and options or {}
    local runtime = setmetatable({}, Runtime)
    PRIVATE[runtime] = {
        ready = false,
        failure_reason = 'Objective route runtime is not initialized.',
    }
    runtime:_initialize(options)
    return runtime
end

return module
