local module_path = assert(arg[1], 'runtime module path is required')
local generated_policy_path = assert(arg[2], 'generated policy module path is required')

local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)
local runtime_module = chunk()

assert(type(runtime_module) == 'table')
assert(type(runtime_module.new) == 'function')
assert(type(runtime_module.classify_exact_leg) == 'function')

local generated_policy_chunk, generated_policy_error = loadfile(generated_policy_path)
assert(generated_policy_chunk ~= nil, generated_policy_error)
local generated_policy = generated_policy_chunk()
for fixture_id, fixture in pairs(generated_policy.fixtures) do
    local fixture_request = {
        zone = 143,
        start = fixture.request.start,
        ['end'] = fixture.request['end'],
    }
    assert(runtime_module.classify_exact_leg(
        generated_policy, fixture_request, fixture.observation, {}) == fixture.expect,
        'Lua runtime policy parity failed for ' .. fixture_id)
end

local runtime = runtime_module.new({})
assert(type(runtime) == 'table')
assert(type(runtime.authorize_start) == 'function')
assert(type(runtime.authorize_transition) == 'function')

local function copy_identity(identity)
    return {
        size_low = identity.size_low,
        size_high = identity.size_high,
        write_time_low = identity.write_time_low,
        write_time_high = identity.write_time_high,
    }
end

local function fixture_sha256(bytes)
    local output = {}
    for seed = 1, 8 do
        local value = (seed * 104729) % 2147483647
        for index = 1, #bytes do
            value = ((value * (127 + seed)) + bytes:byte(index) + index) % 2147483647
        end
        output[#output + 1] = ('%08x'):format(value)
    end
    return table.concat(output)
end

local function lua_value(value)
    local kind = type(value)
    if kind == 'string' then return string.format('%q', value) end
    if kind == 'number' or kind == 'boolean' then return tostring(value) end
    assert(kind == 'table', 'unsupported fixture Lua value: ' .. kind)
    local is_array = true
    local count = 0
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then is_array = false end
    end
    if is_array and count == #value then
        local items = {}
        for index = 1, #value do items[index] = lua_value(value[index]) end
        return '{ ' .. table.concat(items, ', ') .. ' }'
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local items = {}
    for _, key in ipairs(keys) do
        items[#items + 1] = '[' .. lua_value(key) .. '] = ' .. lua_value(value[key])
    end
    return '{ ' .. table.concat(items, ', ') .. ' }'
end

local function new_loader_fixture()
    local root = 'C:\\fixture\\accessxi_reader\\'
    local manifest_relative = 'data/mission-quest-route-manifest.tsv'
    local definitions = {
        {
            relative_path = 'data/ffxi-nav-destinations.tsv',
            kind = 'destinations',
            bytes = '# fixture destinations\n',
        },
        {
            relative_path = 'data/ffxi-nav-zoneline-graph.tsv',
            kind = 'graph',
            bytes = 'zoneline_id\tfrom_zone\tfrom_name\tfrom_code\tfrom_x\tfrom_z\tfrom_y\tto_zone\tto_name\tto_code\tto_x\tto_z\tto_y\tsource\tconfidence\tnote\n',
        },
        {
            relative_path = 'modules/mission_quest_route_contracts.lua',
            kind = 'contracts',
            bytes = 'EXECUTION_FLAGS.contracts = EXECUTION_FLAGS.contracts + 1\nreturn {}\n',
        },
        {
            relative_path = 'modules/mission_quest_route_policy.lua',
            kind = 'policy',
            bytes = 'EXECUTION_FLAGS.policy = EXECUTION_FLAGS.policy + 1\nreturn { schema_version = 2, policy_revision = "objective-route-proof-v2.1", policy_sha256 = "' .. string.rep('b', 64) .. '", probe_protocol = "accessxi-navprobe-jsonl-v2", probe_schema = 2, thresholds = { endpoint_epsilon_yalms = 0.75, maximum_segment_length_yalms = 80, maximum_waypoint_count = 65536, minimum_endpoint_clearance_yalms = 0.5, minimum_waypoint_clearance_yalms = 0.25, transition_corridor_radius_yalms = 3 }, fixtures = {} }\n',
        },
        {
            relative_path = 'modules/mission_quest_route_runtime.lua',
            kind = 'runtime',
            bytes = 'return { fixture_runtime_bytes = true }\n',
        },
        {
            relative_path = 'modules/mission_quest_route_transitions.lua',
            kind = 'transitions',
            bytes = 'EXECUTION_FLAGS.transitions = EXECUTION_FLAGS.transitions + 1\nreturn { schema_version = 2, source_registry_sha256 = "' .. string.rep('c', 64) .. '", definitions = {}, authorized = {} }\n',
        },
        {
            relative_path = 'third_party/FFXI-NavMesh-Builder/FFXINAV.dll',
            kind = 'ffxinav',
            bytes = 'fixture dll bytes',
        },
    }
    local state = {
        root = root,
        manifest_relative = manifest_relative,
        definitions = definitions,
        files = {},
        read_count = {},
        load_records = {},
        execution_flags = { policy = 0, transitions = 0, contracts = 0, mismatch = false },
    }
    function state:path(relative_path)
        return self.root .. relative_path:gsub('/', '\\')
    end
    for ordinal, definition in ipairs(definitions) do
        state.files[state:path(definition.relative_path)] = {
            bytes = definition.bytes,
            identity = {
                size_low = #definition.bytes,
                size_high = 0,
                write_time_low = ordinal,
                write_time_high = 100,
            },
        }
    end
    function state:rebuild_manifest()
        table.sort(self.definitions, function(left, right)
            local left_key = left.relative_path:lower()
            local right_key = right.relative_path:lower()
            return left_key == right_key and left.relative_path < right.relative_path or left_key < right_key
        end)
        local lines = { 'relative_path\tsha256\tkind\tzone\tmesh_name\n' }
        for _, definition in ipairs(self.definitions) do
            local file = assert(self.files[self:path(definition.relative_path)])
            lines[#lines + 1] = table.concat({
                definition.relative_path,
                fixture_sha256(file.bytes),
                definition.kind,
                definition.zone or '',
                definition.mesh_name or '',
            }, '\t') .. '\n'
        end
        local bytes = table.concat(lines)
        self.files[self:path(self.manifest_relative)] = {
            bytes = bytes,
            identity = {
                size_low = #bytes,
                size_high = 0,
                write_time_low = 999,
                write_time_high = 100,
            },
        }
        self.manifest_digest = fixture_sha256(bytes)
    end
    state:rebuild_manifest()

    state.file_hasher = {
        read_and_hash_file = function(_, path)
            state.read_count[path] = (state.read_count[path] or 0) + 1
            local file = state.files[path]
            if file == nil then
                return nil, nil, nil, 'synthetic missing file: ' .. tostring(path)
            end
            return file.bytes, fixture_sha256(file.bytes), copy_identity(file.identity)
        end,
        hash_file = function(self, path)
            local bytes, digest, identity, reason = self:read_and_hash_file(path)
            if bytes == nil then return nil, nil, reason end
            return digest, identity
        end,
    }
    function state:options()
        local environment = setmetatable({ EXECUTION_FLAGS = self.execution_flags }, { __index = _G })
        local options = {
            expected_manifest_sha256 = self.manifest_digest,
            manifest_path = self:path(self.manifest_relative),
            path_for = function(relative_path) return self:path(relative_path) end,
            file_hasher = self.file_hasher,
            sha256 = fixture_sha256,
            module_environment = environment,
            load_chunk = function(bytes, chunk_name, chunk_environment)
                self.load_records[#self.load_records + 1] = { bytes = bytes, name = chunk_name }
                local loaded, reason = loadstring(bytes, chunk_name)
                if loaded ~= nil and chunk_environment ~= nil then
                    setfenv(loaded, chunk_environment)
                end
                return loaded, reason
            end,
        }
        if self.native_snapshot ~= nil then
            options.native_integrity_state = function()
                return {
                    trusted = self.native_snapshot.trusted,
                    dll = {
                        path = self.native_snapshot.dll.path,
                        sha256 = self.native_snapshot.dll.sha256,
                        identity = copy_identity(self.native_snapshot.dll.identity),
                    },
                    mesh = {
                        path = self.native_snapshot.mesh.path,
                        sha256 = self.native_snapshot.mesh.sha256,
                        identity = copy_identity(self.native_snapshot.mesh.identity),
                        mesh_name = self.native_snapshot.mesh.mesh_name,
                        zone = self.native_snapshot.mesh.zone,
                    },
                }
            end
        end
        return options
    end
    return state
end

local valid = new_loader_fixture()
local loaded_runtime = runtime_module.new(valid:options())
assert(type(loaded_runtime.is_ready) == 'function')
assert(loaded_runtime:is_ready() == true, tostring(loaded_runtime:failure_reason()))
assert(valid.execution_flags.policy == 1)
assert(valid.execution_flags.transitions == 1)
assert(valid.execution_flags.contracts == 1)
assert(valid.read_count[valid:path('data/ffxi-nav-destinations.tsv')] == nil,
    'an empty rooted contract set must not hash or parse the 9 MB destination catalogue during addon load')
assert(valid.read_count[valid:path('data/ffxi-nav-zoneline-graph.tsv')] == nil,
    'an empty rooted contract set must not hash or parse the zone graph during addon load')
assert(valid.read_count[valid:path('modules/mission_quest_route_runtime.lua')] == 1,
    'the zero-contract fast path must still authenticate the runtime module')
assert(#valid.load_records == 3)
for _, record in ipairs(valid.load_records) do
    local relative_path = record.name:match('^@(.+)$')
    assert(relative_path ~= nil)
    assert(record.bytes == valid.files[valid:path(relative_path)].bytes,
        'loader must execute the exact bytes returned by read_and_hash_file')
end

local wrong_pin = new_loader_fixture()
local wrong_options = wrong_pin:options()
wrong_options.expected_manifest_sha256 = string.rep('0', 64)
local wrong_runtime = runtime_module.new(wrong_options)
assert(wrong_runtime:is_ready() == false)
assert(wrong_runtime:failure_reason():lower():find('manifest', 1, true) ~= nil)
assert(#wrong_pin.load_records == 0)
assert(wrong_pin.execution_flags.policy == 0)

local mismatch = new_loader_fixture()
local mismatch_path = mismatch:path('modules/mission_quest_route_policy.lua')
mismatch.files[mismatch_path].bytes = 'EXECUTION_FLAGS.mismatch = true\nreturn {}\n'
local mismatch_runtime = runtime_module.new(mismatch:options())
assert(mismatch_runtime:is_ready() == false)
assert(mismatch_runtime:failure_reason():lower():find('hash', 1, true) ~= nil)
assert(mismatch.execution_flags.mismatch == false,
    'hash-mismatched Lua bytes must be rejected before compilation or execution')
assert(#mismatch.load_records == 0,
    'a hash-mismatched first Lua child must never reach loadstring')

local function definition_by_path(fixture, relative_path)
    for _, definition in ipairs(fixture.definitions) do
        if definition.relative_path == relative_path then return definition end
    end
    return nil
end

local function replace_file_bytes(fixture, relative_path, bytes)
    local file = assert(fixture.files[fixture:path(relative_path)])
    file.bytes = bytes
    file.identity.size_low = #bytes
    file.identity.write_time_low = file.identity.write_time_low + 1000
end

local function new_authorization_fixture()
    local fixture = new_loader_fixture()
    local destination_line = table.concat({
        '143', 'Fixture Enemy', '1.000', '0.000', '0.000', 'enemy', 'fixture',
        'untested', '', 'camp:v1:143:fixture-enemy:aaaaaaaaaaaaaaaaaaaa',
        'lsb:fixture:enemy', '1001', 'complete-link-v1-h120-y24',
    }, '\t') .. '\n'
    local destination_bytes = '# AccessXI fixture destinations.\n' .. destination_line
    local graph_header = 'zoneline_id\tfrom_zone\tfrom_name\tfrom_code\tfrom_x\tfrom_z\tfrom_y\tto_zone\tto_name\tto_code\tto_x\tto_z\tto_y\tsource\tconfidence\tnote\n'
    local first_prefix_line = table.concat({
        '10', '100', 'Fixture Start', 'fixture', '1.000', '1.000', '0.000',
        '106', 'North Gustaberg', 'fixture', '10.000', '10.000', '0.000',
        'fixture-live-walk', 'proven', '',
    }, '\t') .. '\n'
    local ingress_line = table.concat({
        '20', '106', 'North Gustaberg', 'fixture', '10.000', '10.000', '0.000',
        '143', 'Palborough Mines', 'fixture', '0.000', '0.000', '0.000',
        'fixture-live-walk', 'proven', '',
    }, '\t') .. '\n'
    local graph_lines = {
        table.concat({ '42', '108', 'Fixture Cycle B', 'fixture', '0', '0', '0', '107', 'Fixture Cycle A', 'fixture', '0', '0', '0', 'fixture-live-walk', 'proven', '' }, '\t') .. '\n',
        table.concat({ '5', '100', 'Fixture Start', 'fixture', '0', '0', '0', '143', 'Palborough Mines', 'fixture', '0', '0', '0', 'fixture-static', 'untested', '' }, '\t') .. '\n',
        ingress_line,
        table.concat({ '41', '107', 'Fixture Cycle A', 'fixture', '0', '0', '0', '108', 'Fixture Cycle B', 'fixture', '0', '0', '0', 'fixture-live-walk', 'proven', '' }, '\t') .. '\n',
        first_prefix_line,
        table.concat({ '40', '107', 'Fixture Cycle A', 'fixture', '0', '0', '0', '100', 'Fixture Start', 'fixture', '0', '0', '0', 'fixture-live-walk', 'proven', '' }, '\t') .. '\n',
        table.concat({ '30', '106', 'North Gustaberg', 'fixture', '0', '0', '0', '100', 'Fixture Start', 'fixture', '0', '0', '0', 'fixture-live-walk', 'proven', '' }, '\t') .. '\n',
        table.concat({ '60', '100', 'Fixture Start', 'fixture', '0', '0', '0', '109', 'Reverse Only', 'fixture', '0', '0', '0', 'fixture-live-walk', 'proven', '' }, '\t') .. '\n',
    }
    local graph_bytes = graph_header .. table.concat(graph_lines)
    local dll_bytes = 'rooted fixture dll bytes'
    local mesh_bytes = 'rooted fixture mesh bytes'
    replace_file_bytes(fixture, 'data/ffxi-nav-destinations.tsv', destination_bytes)
    replace_file_bytes(fixture, 'data/ffxi-nav-zoneline-graph.tsv', graph_bytes)
    replace_file_bytes(fixture, 'third_party/FFXI-NavMesh-Builder/FFXINAV.dll', dll_bytes)
    local mesh_relative = 'third_party/xiNavmeshes/Palborough_Mines.nav'
    fixture.definitions[#fixture.definitions + 1] = {
        relative_path = mesh_relative,
        kind = 'mesh',
        zone = '143',
        mesh_name = 'Palborough_Mines.nav',
    }
    fixture.files[fixture:path(mesh_relative)] = {
        bytes = mesh_bytes,
        identity = { size_low = #mesh_bytes, size_high = 0, write_time_low = 800, write_time_high = 100 },
    }
    fixture.meshes_by_zone = {
        [100] = { name = 'Fixture_Start.nav', bytes = 'rooted zone 100 mesh bytes' },
        [106] = { name = 'North_Gustaberg.nav', bytes = 'rooted zone 106 mesh bytes' },
        [107] = { name = 'Fixture_Cycle_A.nav', bytes = 'rooted zone 107 mesh bytes' },
        [108] = { name = 'Fixture_Cycle_B.nav', bytes = 'rooted zone 108 mesh bytes' },
        [143] = { name = 'Palborough_Mines.nav', bytes = mesh_bytes },
    }
    for zone, binding in pairs(fixture.meshes_by_zone) do
        if zone ~= 143 then
            local relative_path = 'third_party/xiNavmeshes/' .. binding.name
            fixture.definitions[#fixture.definitions + 1] = {
                relative_path = relative_path,
                kind = 'mesh',
                zone = tostring(zone),
                mesh_name = binding.name,
            }
            fixture.files[fixture:path(relative_path)] = {
                bytes = binding.bytes,
                identity = {
                    size_low = #binding.bytes,
                    size_high = 0,
                    write_time_low = 800 + zone,
                    write_time_high = 100,
                },
            }
        end
    end
    fixture.native_snapshot = {
        trusted = true,
        dll = {
            path = fixture:path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll'),
            sha256 = fixture_sha256(dll_bytes),
            identity = copy_identity(fixture.files[fixture:path(
                'third_party/FFXI-NavMesh-Builder/FFXINAV.dll')].identity),
        },
        mesh = {
            path = fixture:path(mesh_relative),
            sha256 = fixture_sha256(mesh_bytes),
            identity = copy_identity(fixture.files[fixture:path(mesh_relative)].identity),
            mesh_name = 'Palborough_Mines.nav',
            zone = 143,
        },
    }
    local contract = {
        schema = 2,
        contract_id = 'route:v2:' .. string.rep('a', 64),
        candidate_id = 'mission:Bastok:3:step-006:claim-01:candidate:fixture',
        action_id = 'mission:Bastok:3:step-006:claim-01',
        group_id = 'mission:Bastok:3:step-006:claim-01:group:fixture',
        destination_id = 'camp:v1:143:fixture-enemy:aaaaaaaaaaaaaaaaaaaa',
        zone = 143,
        destination = {
            name = 'Fixture Enemy', x = 1, z = 0, y = 0, kind = 'enemy',
            destination_id = 'camp:v1:143:fixture-enemy:aaaaaaaaaaaaaaaaaaaa',
            raw_identity = 'lsb:fixture:enemy', raw_spawn_ids = { 1001 },
            cluster_policy_version = 'complete-link-v1-h120-y24',
        },
        authorized_directed_prefix = { 20 },
        local_leg = {
            leg = {
                zone = 143,
                destination_id = 'camp:v1:143:fixture-enemy:aaaaaaaaaaaaaaaaaaaa',
                zoneline_id = 20,
            },
            probe_request = { zone = 143, start = { x = 0, z = 0, y = 0 }, ['end'] = { x = 1, z = 0, y = 0 } },
            observations = { path_length = 1 },
        },
        required_transition_ids = {},
        transition_evidence_ids = {},
        expected_inputs = {
            mesh_name = 'Palborough_Mines.nav',
            mesh_sha256 = fixture_sha256(mesh_bytes),
            ffxinav_sha256 = fixture_sha256(dll_bytes),
            probe_protocol = 'accessxi-navprobe-jsonl-v2',
            probe_schema = 2,
            policy_revision = 'objective-route-proof-v2.1',
            policy_sha256 = string.rep('b', 64),
            transition_registry_sha256 = string.rep('c', 64),
            destinations_sha256 = fixture_sha256(destination_bytes),
            graph_sha256 = fixture_sha256(graph_bytes),
            destination_row_sha256 = fixture_sha256(destination_line),
            ingress_row_sha256 = fixture_sha256(ingress_line),
            zone_mesh_name = 'Palborough_Mines.nav',
        },
        route_ready = true,
    }
    fixture.contract = contract
    fixture.graph_header = graph_header
    fixture.graph_lines = graph_lines
    fixture.first_prefix_line = first_prefix_line
    fixture.ingress_line = ingress_line
    replace_file_bytes(
        fixture,
        'modules/mission_quest_route_contracts.lua',
        'EXECUTION_FLAGS.contracts = EXECUTION_FLAGS.contracts + 1\nreturn ' .. lua_value({ contract }) .. '\n')
    fixture:rebuild_manifest()
    return fixture
end

local schema_drift = new_loader_fixture()
replace_file_bytes(
    schema_drift,
    'modules/mission_quest_route_policy.lua',
    'return { schema_version = 3, policy_revision = "objective-route-proof-v2.1", policy_sha256 = "' .. string.rep('b', 64) .. '", probe_protocol = "accessxi-navprobe-jsonl-v2", probe_schema = 2, thresholds = {}, fixtures = {} }\n')
schema_drift:rebuild_manifest()
local schema_runtime = runtime_module.new(schema_drift:options())
assert(schema_runtime:is_ready() == false)
assert(schema_runtime:failure_reason():lower():find('schema', 1, true) ~= nil)

local revision_drift = new_loader_fixture()
replace_file_bytes(
    revision_drift,
    'modules/mission_quest_route_policy.lua',
    'return { schema_version = 2, policy_revision = "drifted", policy_sha256 = "' .. string.rep('b', 64) .. '", probe_protocol = "accessxi-navprobe-jsonl-v2", probe_schema = 2, thresholds = {}, fixtures = {} }\n')
revision_drift:rebuild_manifest()
local revision_runtime = runtime_module.new(revision_drift:options())
assert(revision_runtime:is_ready() == false)
assert(revision_runtime:failure_reason():lower():find('revision', 1, true) ~= nil)

local missing_child = new_loader_fixture()
local policy_definition = assert(definition_by_path(missing_child, 'modules/mission_quest_route_policy.lua'))
for index, definition in ipairs(missing_child.definitions) do
    if definition == policy_definition then table.remove(missing_child.definitions, index); break end
end
missing_child:rebuild_manifest()
local missing_runtime = runtime_module.new(missing_child:options())
assert(missing_runtime:is_ready() == false)
assert(missing_runtime:failure_reason():lower():find('missing', 1, true) ~= nil)

local duplicate_manifest = new_loader_fixture()
local manifest_path = duplicate_manifest:path(duplicate_manifest.manifest_relative)
local manifest_file = duplicate_manifest.files[manifest_path]
local duplicate_line = 'modules/mission_quest_route_policy.lua\t'
    .. fixture_sha256(duplicate_manifest.files[duplicate_manifest:path('modules/mission_quest_route_policy.lua')].bytes)
    .. '\tpolicy\t\t\n'
manifest_file.bytes = manifest_file.bytes .. duplicate_line
manifest_file.identity.size_low = #manifest_file.bytes
local duplicate_options = duplicate_manifest:options()
duplicate_options.expected_manifest_sha256 = fixture_sha256(manifest_file.bytes)
local duplicate_runtime = runtime_module.new(duplicate_options)
assert(duplicate_runtime:is_ready() == false)
assert(duplicate_runtime:failure_reason():lower():find('duplicat', 1, true) ~= nil
    or duplicate_runtime:failure_reason():lower():find('sorted', 1, true) ~= nil)

local duplicate_contract = new_authorization_fixture()
replace_file_bytes(
    duplicate_contract,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ duplicate_contract.contract, duplicate_contract.contract }) .. '\n')
duplicate_contract:rebuild_manifest()
local duplicate_contract_runtime = runtime_module.new(duplicate_contract:options())
assert(duplicate_contract_runtime:is_ready() == false)
assert(duplicate_contract_runtime:failure_reason():lower():find('contract', 1, true) ~= nil)

local authorization = new_authorization_fixture()
local authorization_runtime = runtime_module.new(authorization:options())
assert(authorization_runtime:is_ready() == true, authorization_runtime:failure_reason())
local function menu_row(contract, overrides)
    local row = {
        objective_kind = 'mission',
        objective_native_key = 'mission:Bastok:3',
        objective_guide_step_id = 'mission:Bastok:3:step-006',
        objective_character_identity = 'alpha:1001',
        objective_world_id = 1001,
        objective_session_epoch = 77,
        objective_candidate_id = contract.candidate_id,
        objective_action_id = contract.action_id,
        objective_group_id = contract.group_id,
        objective_destination_id = contract.destination_id,
        objective_classification = 'catalogue-candidate',
        objective_action_instruction = 'Defeat the fixture enemy.',
        objective_instruction_only = false,
        objective_target = contract.destination,
        route_contract_id = 'route:v2:' .. string.rep('f', 64),
        route_ready = true,
        route_evidence = 'legacy free text must be ignored',
    }
    for key, value in pairs(overrides or {}) do row[key] = value end
    return row
end

local selected = menu_row(authorization.contract)
local fresh = menu_row(authorization.contract)
local fixture_player = { zone = 100, x = 0, z = 0, y = 0 }
local payload, ready_message, ready_mode = authorization_runtime:authorize_start(selected, fresh, fixture_player)
assert(ready_mode == 'ready', tostring(ready_message))
assert(type(payload) == 'table')
assert(ready_message == '')
assert(payload.zone == authorization.contract.zone)
assert(payload.x == authorization.contract.destination.x)
assert(payload.z == authorization.contract.destination.z)
assert(payload.y == authorization.contract.destination.y)
assert(payload.objective_route_contract_id == authorization.contract.contract_id)
assert(payload.objective_route_contract_id ~= selected.route_contract_id)
assert(payload.objective_contract_id == nil)
assert(payload.objective_candidate_id == authorization.contract.candidate_id)
assert(payload.objective_action_id == authorization.contract.action_id)
assert(payload.objective_group_id == authorization.contract.group_id)
assert(payload.objective_destination_id == authorization.contract.destination_id)
for _, field in ipairs({
    'objective_kind', 'objective_native_key', 'objective_guide_step_id',
    'objective_character_identity', 'objective_world_id', 'objective_session_epoch',
    'objective_classification', 'objective_action_instruction',
}) do
    assert(payload[field] == fresh[field], 'ready payload did not preserve ' .. field)
end
assert(type(payload.objective_contract_snapshot) == 'table')
assert(payload.objective_route_contract == nil)
payload.objective_contract_snapshot.contract_id = 'caller mutation'
local fresh_payload = assert(authorization_runtime:authorize_start(selected, fresh, fixture_player))
assert(fresh_payload.objective_contract_snapshot.contract_id == authorization.contract.contract_id)

for _, changed_field in ipairs({
    'objective_kind', 'objective_native_key', 'objective_guide_step_id',
    'objective_character_identity', 'objective_world_id', 'objective_session_epoch',
    'objective_candidate_id', 'objective_action_id', 'objective_group_id',
    'objective_destination_id', 'objective_classification', 'objective_action_instruction',
}) do
    local changed = menu_row(authorization.contract)
    if type(changed[changed_field]) == 'number' then
        changed[changed_field] = changed[changed_field] + 1
    else
        changed[changed_field] = changed[changed_field] .. ':changed'
    end
    local blocked_payload, blocked_message, blocked_mode = authorization_runtime:authorize_start(
        selected, changed, fixture_player)
    assert(blocked_payload == nil and blocked_mode == 'blocked', changed_field .. ': ' .. tostring(blocked_message))
end

local invented = {}
for key, value in pairs(selected) do invented[key] = value end
invented.objective_candidate_id = invented.objective_candidate_id .. ':invented'
local invented_fresh = {}
for key, value in pairs(invented) do invented_fresh[key] = value end
local invented_payload, invented_message, invented_mode = authorization_runtime:authorize_start(
    invented, invented_fresh, fixture_player)
assert(invented_payload == nil and invented_mode == 'blocked', tostring(invented_message))

local instruction_selected = menu_row(authorization.contract, {
    objective_guide_step_id = 'mission:Bastok:3:step-007',
    objective_candidate_id = '',
    objective_action_id = 'mission:Bastok:3:step-007:claim-01',
    objective_group_id = '',
    objective_destination_id = '',
    objective_classification = 'instruction-only',
    objective_action_instruction = 'Choose the second menu option.',
    objective_instruction_only = true,
    objective_target = nil,
})
local instruction_fresh = menu_row(authorization.contract, {
    objective_guide_step_id = instruction_selected.objective_guide_step_id,
    objective_candidate_id = '',
    objective_action_id = instruction_selected.objective_action_id,
    objective_group_id = '',
    objective_destination_id = '',
    objective_classification = 'instruction-only',
    objective_action_instruction = instruction_selected.objective_action_instruction,
    objective_instruction_only = true,
    objective_target = nil,
})
local instruction_payload, instruction_message, instruction_mode = authorization_runtime:authorize_start(
    instruction_selected, instruction_fresh, {})
assert(instruction_payload == instruction_fresh.objective_action_instruction)
assert(instruction_mode == 'instruction')
assert(instruction_message == '')
instruction_fresh.objective_classification = 'catalogue-candidate'
local unsafe_payload, unsafe_message, unsafe_mode = authorization_runtime:authorize_start(
    instruction_selected, instruction_fresh, {})
assert(unsafe_payload == nil and unsafe_mode == 'blocked', tostring(unsafe_message))

local wrong_policy_digest = new_authorization_fixture()
wrong_policy_digest.contract.expected_inputs.policy_sha256 = string.rep('d', 64)
replace_file_bytes(
    wrong_policy_digest,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ wrong_policy_digest.contract }) .. '\n')
wrong_policy_digest:rebuild_manifest()
local wrong_policy_runtime = runtime_module.new(wrong_policy_digest:options())
assert(wrong_policy_runtime:is_ready() == false)
assert(wrong_policy_runtime:failure_reason():lower():find('policy', 1, true) ~= nil)

local wrong_transition_digest = new_authorization_fixture()
wrong_transition_digest.contract.expected_inputs.transition_registry_sha256 = string.rep('d', 64)
replace_file_bytes(
    wrong_transition_digest,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ wrong_transition_digest.contract }) .. '\n')
wrong_transition_digest:rebuild_manifest()
local wrong_transition_runtime = runtime_module.new(wrong_transition_digest:options())
assert(wrong_transition_runtime:is_ready() == false)
assert(wrong_transition_runtime:failure_reason():lower():find('transition', 1, true) ~= nil)

local ungrouped = new_authorization_fixture()
ungrouped.contract.group_id = ''
replace_file_bytes(
    ungrouped,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ ungrouped.contract }) .. '\n')
ungrouped:rebuild_manifest()
local ungrouped_runtime = runtime_module.new(ungrouped:options())
assert(ungrouped_runtime:is_ready() == true, ungrouped_runtime:failure_reason())
local ungrouped_selected = menu_row(ungrouped.contract)
local ungrouped_payload, ungrouped_message, ungrouped_mode = ungrouped_runtime:authorize_start(
    ungrouped_selected, ungrouped_selected, fixture_player)
assert(type(ungrouped_payload) == 'table' and ungrouped_mode == 'ready', tostring(ungrouped_message))
local wrong_group = {}
for key, value in pairs(ungrouped_selected) do wrong_group[key] = value end
wrong_group.objective_group_id = 'invented-group'
local wrong_group_payload, wrong_group_message, wrong_group_mode = ungrouped_runtime:authorize_start(
    ungrouped_selected, wrong_group, fixture_player)
assert(wrong_group_payload == nil and wrong_group_mode == 'blocked', tostring(wrong_group_message))

for _, changed_path in ipairs({
    'data/ffxi-nav-destinations.tsv',
    'data/ffxi-nav-zoneline-graph.tsv',
    'modules/mission_quest_route_contracts.lua',
    'modules/mission_quest_route_policy.lua',
    'modules/mission_quest_route_runtime.lua',
    'modules/mission_quest_route_transitions.lua',
    'third_party/FFXI-NavMesh-Builder/FFXINAV.dll',
    'third_party/xiNavmeshes/Palborough_Mines.nav',
}) do
    local changed_fixture = new_authorization_fixture()
    local changed_runtime = runtime_module.new(changed_fixture:options())
    assert(changed_runtime:is_ready() == true, changed_runtime:failure_reason())
    changed_fixture.files[changed_fixture:path(changed_path)].identity.write_time_high = 101
    local changed_row = menu_row(changed_fixture.contract)
    local changed_payload, changed_message, changed_mode = changed_runtime:authorize_start(
        changed_row, changed_row, fixture_player)
    assert(changed_payload == nil and changed_mode == 'blocked',
        changed_path .. ' identity replacement was accepted: ' .. tostring(changed_message))
end
local changed_manifest_fixture = new_authorization_fixture()
local changed_manifest_runtime = runtime_module.new(changed_manifest_fixture:options())
assert(changed_manifest_runtime:is_ready() == true, changed_manifest_runtime:failure_reason())
changed_manifest_fixture.files[changed_manifest_fixture:path(
    changed_manifest_fixture.manifest_relative)].identity.write_time_low = 1000
local changed_manifest_row = menu_row(changed_manifest_fixture.contract)
local changed_manifest_payload, changed_manifest_message, changed_manifest_mode =
    changed_manifest_runtime:authorize_start(changed_manifest_row, changed_manifest_row, fixture_player)
assert(changed_manifest_payload == nil and changed_manifest_mode == 'blocked',
    'manifest identity replacement was accepted: ' .. tostring(changed_manifest_message))

local function edge_ids(edges)
    local result = {}
    for index, edge in ipairs(edges or {}) do result[index] = edge.zoneline_id end
    return table.concat(result, ',')
end

local ordinary_bfs_calls = 0
local graph_fixture = new_authorization_fixture()
local graph_options = graph_fixture:options()
graph_options.ordinary_zone_bfs = function()
    ordinary_bfs_calls = ordinary_bfs_calls + 1
    error('objective routing must never call the ordinary BFS')
end
local graph_runtime = runtime_module.new(graph_options)
assert(graph_runtime:is_ready() == true, graph_runtime:failure_reason())
assert(type(graph_runtime.find_objective_zone_path) == 'function')
local from_start, start_reason = graph_runtime:find_objective_zone_path(100, graph_fixture.contract.contract_id)
assert(type(from_start) == 'table', tostring(start_reason))
assert(edge_ids(from_start) == '10,20', 'an untested direct edge must never bypass the rooted prefix')
local from_middle = assert(graph_runtime:find_objective_zone_path(106, graph_fixture.contract.contract_id))
assert(edge_ids(from_middle) == '20', 'a current zone on the prefix must receive only its directed suffix')
local from_cycle = assert(graph_runtime:find_objective_zone_path(108, graph_fixture.contract.contract_id))
assert(edge_ids(from_cycle) == '42,40,10,20', 'cycles must terminate with deterministic edge ordering')
local same_zone = assert(graph_runtime:find_objective_zone_path(143, graph_fixture.contract.contract_id))
assert(#same_zone == 0)
local disconnected, disconnected_reason = graph_runtime:find_objective_zone_path(999, graph_fixture.contract.contract_id)
assert(disconnected == nil and tostring(disconnected_reason):lower():find('proven', 1, true) ~= nil)
local reverse_only, reverse_only_reason = graph_runtime:find_objective_zone_path(109, graph_fixture.contract.contract_id)
assert(reverse_only == nil and tostring(reverse_only_reason):lower():find('proven', 1, true) ~= nil,
    'a proven 100-to-109 edge must never authorize the absent 109-to-100 direction')
assert(ordinary_bfs_calls == 0)

local shuffled = new_authorization_fixture()
local reversed = {}
for index = #shuffled.graph_lines, 1, -1 do reversed[#reversed + 1] = shuffled.graph_lines[index] end
local shuffled_graph = shuffled.graph_header .. table.concat(reversed)
replace_file_bytes(shuffled, 'data/ffxi-nav-zoneline-graph.tsv', shuffled_graph)
shuffled.contract.expected_inputs.graph_sha256 = fixture_sha256(shuffled_graph)
replace_file_bytes(
    shuffled,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ shuffled.contract }) .. '\n')
shuffled:rebuild_manifest()
local shuffled_runtime = runtime_module.new(shuffled:options())
assert(shuffled_runtime:is_ready() == true, shuffled_runtime:failure_reason())
assert(edge_ids(assert(shuffled_runtime:find_objective_zone_path(108, shuffled.contract.contract_id)))
    == '42,40,10,20', 'graph input order must not alter the objective path')

local unproven_prefix = new_authorization_fixture()
local observed_first = unproven_prefix.first_prefix_line:gsub('\tproven\t', '\tobserved\t', 1)
local unproven_lines = {}
for index, line in ipairs(unproven_prefix.graph_lines) do
    unproven_lines[index] = line == unproven_prefix.first_prefix_line and observed_first or line
end
local unproven_graph = unproven_prefix.graph_header .. table.concat(unproven_lines)
replace_file_bytes(unproven_prefix, 'data/ffxi-nav-zoneline-graph.tsv', unproven_graph)
unproven_prefix.contract.expected_inputs.graph_sha256 = fixture_sha256(unproven_graph)
replace_file_bytes(
    unproven_prefix,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ unproven_prefix.contract }) .. '\n')
unproven_prefix:rebuild_manifest()
local unproven_runtime = runtime_module.new(unproven_prefix:options())
assert(unproven_runtime:is_ready() == false
    and tostring(unproven_runtime:failure_reason()):lower():find('unselected', 1, true),
    'an observed dynamic predecessor and its stale mesh must fail closed')

local function copy_value(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy_value(key, seen)] = copy_value(item, seen) end
    return result
end

local function multi_contract_runtime(first_length, second_length, reverse_order)
    local fixture = new_authorization_fixture()
    local first = fixture.contract
    first.local_leg.observations.path_length = first_length
    local second = copy_value(first)
    second.contract_id = 'route:v2:' .. string.rep('b', 64)
    second.local_leg.observations.path_length = second_length
    local rows = reverse_order and { second, first } or { first, second }
    replace_file_bytes(
        fixture,
        'modules/mission_quest_route_contracts.lua',
        'return ' .. lua_value(rows) .. '\n')
    fixture:rebuild_manifest()
    return fixture, runtime_module.new(fixture:options()), first, second
end

for _, reversed_order in ipairs({ false, true }) do
    local multi_fixture, multi_runtime, _longer, shorter = multi_contract_runtime(9, 2, reversed_order)
    assert(multi_runtime:is_ready() == true, multi_runtime:failure_reason())
    local multi_row = menu_row(multi_fixture.contract)
    local multi_payload, multi_message, multi_mode = multi_runtime:authorize_start(
        multi_row, multi_row, fixture_player)
    assert(multi_mode == 'ready', tostring(multi_message))
    assert(multi_payload.objective_route_contract_id == shorter.contract_id,
        'eligible contract selection must be independent of generated row order')
end
local tie_fixture, tie_runtime, tie_first = multi_contract_runtime(2, 2, true)
assert(tie_runtime:is_ready() == true, tie_runtime:failure_reason())
local tie_row = menu_row(tie_fixture.contract)
local tie_payload, tie_message, tie_mode = tie_runtime:authorize_start(tie_row, tie_row, fixture_player)
assert(tie_mode == 'ready', tostring(tie_message))
assert(tie_payload.objective_route_contract_id == tie_first.contract_id,
    'equal validated leg lengths must use canonical contract ID ordering')
local no_zone_payload, no_zone_message, no_zone_mode = tie_runtime:authorize_start(
    tie_row, tie_row, { x = 0, z = 0, y = 0 })
assert(no_zone_payload == nil and no_zone_mode == 'blocked', tostring(no_zone_message))
local no_eligible_payload, no_eligible_message, no_eligible_mode = tie_runtime:authorize_start(
    tie_row, tie_row, { zone = 999, x = 0, z = 0, y = 0 })
assert(no_eligible_payload == nil and no_eligible_mode == 'blocked', tostring(no_eligible_message))

local exact_request = {
    zone = 143,
    objective_route_contract_id = graph_fixture.contract.contract_id,
    start = { x = 0, z = 0, y = 0 },
    ['end'] = { x = 10, z = 0, y = 0 },
}
local exact_observation = {
    status = 'exact-path', start_valid = true, end_valid = true, fallback_used = false,
    waypoint_count = 2,
    waypoints = {
        { x = 0, z = 0, y = 0, clearance = 1, zone = 143 },
        { x = 10, z = 0, y = 0, clearance = 1, zone = 143 },
    },
    first_endpoint_error = 0, last_endpoint_error = 0,
    start_clearance = 1, end_clearance = 1, minimum_waypoint_clearance = 1,
    path_length = 10,
}
assert(runtime_module.classify_exact_leg(generated_policy, exact_request, exact_observation, {}) == 'mesh-proven')
local wrong_zone_observation = copy_value(exact_observation)
wrong_zone_observation.waypoints[2].zone = 144
assert(runtime_module.classify_exact_leg(
    generated_policy, exact_request, wrong_zone_observation, {}) == 'waypoint-zone')
local nonfinite_observation = copy_value(exact_observation)
nonfinite_observation.waypoints[1].x = 0 / 0
assert(runtime_module.classify_exact_leg(
    generated_policy, exact_request, nonfinite_observation, {}) == 'waypoint-malformed')
local endpoint_clearance_observation = copy_value(exact_observation)
endpoint_clearance_observation.start_clearance = 0.1
assert(runtime_module.classify_exact_leg(
    generated_policy, exact_request, endpoint_clearance_observation, {}) == 'endpoint-clearance')
local crossing = {
    transition_id = 'fixture-lift:down', zone = 143,
    pre_anchor = { x = 5, z = 0, y = -1 },
    post_anchor = { x = 5, z = 0, y = 1 },
}
assert(runtime_module.classify_exact_leg(
    generated_policy, exact_request, exact_observation, { crossing }) == 'requires-transition')
local missing_zone_request = copy_value(exact_request)
missing_zone_request.zone = nil
assert(runtime_module.classify_exact_leg(
    generated_policy, missing_zone_request, exact_observation, {}) == 'endpoint-zone')
local fractional_zone_request = copy_value(exact_request)
fractional_zone_request.zone = 143.5
assert(runtime_module.classify_exact_leg(
    generated_policy, fractional_zone_request, exact_observation, {}) == 'endpoint-zone')

local function new_native_spy(paths, options)
    options = options or {}
    local spy = {
        calls = {},
        counts = { FindPath = 0, FindClosestPath = 0, Get_WayPoints = 0 },
        paths = paths,
        path_index = 0,
        validity = options.validity or {},
        validity_index = 0,
        clearance = options.clearance or 1,
    }
    function spy:is_valid_position(point)
        self.calls[#self.calls + 1] = 'IsValidPosition'
        self.validity_index = self.validity_index + 1
        self.last_valid_point = copy_value(point)
        local value = self.validity[self.validity_index]
        return value == nil and true or value
    end
    function spy:get_distance_to_wall(point)
        self.calls[#self.calls + 1] = 'GetDistanceToWall'
        if type(self.clearance) == 'function' then return self.clearance(point) end
        return self.clearance
    end
    function spy:find_path(start_point, end_point)
        self.calls[#self.calls + 1] = 'FindPath'
        self.counts.FindPath = self.counts.FindPath + 1
        self.path_index = self.path_index + 1
        self.find_start = copy_value(start_point)
        self.find_end = copy_value(end_point)
        self.active_path = self.paths[self.path_index] or {}
    end
    function spy:get_waypoints(maximum)
        self.calls[#self.calls + 1] = 'Get_WayPoints'
        self.counts.Get_WayPoints = self.counts.Get_WayPoints + 1
        self.maximum = maximum
        return self.active_path
    end
    function spy:find_closest_path()
        self.counts.FindClosestPath = self.counts.FindClosestPath + 1
        error('FindClosestPath is forbidden')
    end
    return spy
end


local function runtime_with_native(fixture, native, mutate_options)
    local options = fixture:options()
    options.objective_native = native
    if type(mutate_options) == 'function' then mutate_options(options) end
    return runtime_module.new(options)
end

assert(type(graph_runtime.compute_exact_objective_leg) == 'function')
local asymmetric_request = {
    zone = 143,
    objective_route_contract_id = graph_fixture.contract.contract_id,
    start = { x = 11, z = 22, y = -33 },
    ['end'] = { x = 44, z = 55, y = -66 },
}
local asymmetric_paths = {
    { { x = 11, y = -33, z = 22 }, { x = 44, y = -66, z = 55 } },
    {},
    { { x = 11, y = -33, z = 22 }, { x = 44, y = -66, z = 55 } },
}
local native = new_native_spy(asymmetric_paths)
local exact_fixture = new_authorization_fixture()
local exact_runtime = runtime_with_native(exact_fixture, native)
assert(exact_runtime:is_ready() == true, exact_runtime:failure_reason())
local exact_points, exact_reason, exact_evidence = exact_runtime:compute_exact_objective_leg(
    asymmetric_request)
assert(type(exact_points) == 'table' and exact_reason == '' and exact_evidence.reason == 'mesh-proven')
assert(native.find_start.x == 11 and native.find_start.y == -33 and native.find_start.z == 22)
assert(native.find_end.x == 44 and native.find_end.y == -66 and native.find_end.z == 55)
assert(exact_points[1].x == 11 and exact_points[1].z == 22 and exact_points[1].y == -33)
assert(exact_points[2].x == 44 and exact_points[2].z == 55 and exact_points[2].y == -66)
assert(table.concat(native.calls, ',') == table.concat({
    'IsValidPosition', 'GetDistanceToWall',
    'IsValidPosition', 'GetDistanceToWall',
    'FindPath', 'Get_WayPoints',
    'GetDistanceToWall', 'GetDistanceToWall',
}, ','), 'native exact-leg call order changed: ' .. table.concat(native.calls, ','))
assert(native.counts.FindPath == 1 and native.counts.Get_WayPoints == 1
    and native.counts.FindClosestPath == 0)
local forged_native = new_native_spy({ asymmetric_paths[1] })
local forged_points, forged_reason = exact_runtime:compute_exact_objective_leg(
    asymmetric_request, forged_native)
assert(forged_points == nil and tostring(forged_reason):lower():find('override', 1, true) ~= nil)
assert(forged_native.counts.FindPath == 0 and forged_native.counts.Get_WayPoints == 0,
    'a per-call native adapter must never bypass the observer-attested private adapter')
local no_points, no_path_reason = exact_runtime:compute_exact_objective_leg(asymmetric_request)
assert(no_points == nil and no_path_reason == 'no-exact-path')
local recovered_points, recovered_reason = exact_runtime:compute_exact_objective_leg(asymmetric_request)
assert(type(recovered_points) == 'table' and recovered_reason == '',
    'a zero-waypoint result must not leak stale waypoints across one long-lived handle')
assert(native.counts.FindPath == 3 and native.counts.Get_WayPoints == 3
    and native.counts.FindClosestPath == 0)

local binding_fixture = new_authorization_fixture()
local binding_native = new_native_spy({ asymmetric_paths[1], asymmetric_paths[1] })
local binding_runtime = runtime_with_native(binding_fixture, binding_native)
assert(binding_runtime:is_ready() == true, binding_runtime:failure_reason())
assert(binding_runtime:compute_exact_objective_leg(asymmetric_request))
binding_fixture.native_snapshot.mesh.identity.write_time_low =
    binding_fixture.native_snapshot.mesh.identity.write_time_low + 1
local stale_binding_points, stale_binding_reason = binding_runtime:compute_exact_objective_leg(
    asymmetric_request)
assert(stale_binding_points == nil and tostring(stale_binding_reason):lower():find('stale', 1, true) ~= nil)
assert(binding_native.counts.FindPath == 1 and binding_native.counts.Get_WayPoints == 1,
    'same-mesh reuse must recheck the observer before every objective native call')
local missing_observer_fixture = new_authorization_fixture()
local missing_observer_native = new_native_spy({ asymmetric_paths[1] })
local missing_observer_runtime = runtime_with_native(
    missing_observer_fixture,
    missing_observer_native,
    function(options) options.native_integrity_state = nil end)
assert(missing_observer_runtime:is_ready() == true, missing_observer_runtime:failure_reason())
local missing_observer_points, missing_observer_reason =
    missing_observer_runtime:compute_exact_objective_leg(asymmetric_request)
assert(missing_observer_points == nil
    and tostring(missing_observer_reason):lower():find('observer', 1, true) ~= nil)
assert(missing_observer_native.counts.FindPath == 0 and missing_observer_native.counts.Get_WayPoints == 0)

local corridor_fixture = new_authorization_fixture()
replace_file_bytes(
    corridor_fixture,
    'modules/mission_quest_route_transitions.lua',
    'return ' .. lua_value({
        schema_version = 2,
        source_registry_sha256 = string.rep('c', 64),
        definitions = { crossing },
        authorized = {},
    }) .. '\n')
corridor_fixture:rebuild_manifest()
local corridor_native = new_native_spy({ {
    { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 },
} })
local corridor_runtime = runtime_with_native(corridor_fixture, corridor_native)
assert(corridor_runtime:is_ready() == true, corridor_runtime:failure_reason())
local corridor_points, corridor_reason = corridor_runtime:compute_exact_objective_leg(
    exact_request)
assert(corridor_points == nil and corridor_reason == 'requires-transition',
    'a rooted but unauthorized transition definition must still block a direct mesh crossing')
local bypass_points, bypass_reason = corridor_runtime:compute_exact_objective_leg(
    exact_request, {})
assert(bypass_points == nil and tostring(bypass_reason):lower():find('override', 1, true) ~= nil,
    'caller transition/native arguments must be rejected instead of replacing private trust roots')
local unauthorized_transition = new_authorization_fixture()
unauthorized_transition.contract.required_transition_ids = { crossing.transition_id }
replace_file_bytes(
    unauthorized_transition,
    'modules/mission_quest_route_transitions.lua',
    'return ' .. lua_value({
        schema_version = 2,
        source_registry_sha256 = string.rep('c', 64),
        definitions = { crossing },
        authorized = {},
    }) .. '\n')
replace_file_bytes(
    unauthorized_transition,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ unauthorized_transition.contract }) .. '\n')
unauthorized_transition:rebuild_manifest()
local unauthorized_transition_runtime = runtime_module.new(unauthorized_transition:options())
assert(unauthorized_transition_runtime:is_ready() == false,
    'a corridor definition must never authorize transition execution')

local authorized_transition = new_authorization_fixture()
local authorized_definition = {
    transition_id = crossing.transition_id,
    base_id = 'fixture-lift',
    zone = 143,
    direction = 'down',
    pre_anchor = copy_value(crossing.pre_anchor),
    post_anchor = copy_value(crossing.post_anchor),
    expected_live_state = 'same-zone-floor-change-and-continuation',
    timeout_seconds = 45,
    cancellation = { 'timeout', 'player-left-zone', 'destination-changed' },
    interaction = { kind = 'automatic-platform', identity = 'fixture-lift' },
    required_destination_ids = {},
}
authorized_transition.contract.required_transition_ids = { authorized_definition.transition_id }
replace_file_bytes(
    authorized_transition,
    'modules/mission_quest_route_transitions.lua',
    'return ' .. lua_value({
        schema_version = 2,
        source_registry_sha256 = string.rep('c', 64),
        definitions = { authorized_definition },
        authorized = { authorized_definition },
    }) .. '\n')
replace_file_bytes(
    authorized_transition,
    'modules/mission_quest_route_contracts.lua',
    'return ' .. lua_value({ authorized_transition.contract }) .. '\n')
authorized_transition:rebuild_manifest()
local authorized_transition_runtime = runtime_module.new(authorized_transition:options())
assert(authorized_transition_runtime:is_ready(), authorized_transition_runtime:failure_reason())
local rooted_transition, rooted_transition_reason = authorized_transition_runtime:authorize_transition(
    authorized_transition.contract.contract_id,
    authorized_definition.transition_id)
assert(rooted_transition_reason == '' and type(rooted_transition) == 'table')
assert(rooted_transition.schema_version == 2
    and rooted_transition.transition_revision == 'objective-route-transition-v2'
    and rooted_transition.source_registry_sha256 == string.rep('c', 64))
assert(rooted_transition.transition_id == authorized_definition.transition_id
    and rooted_transition.direction == authorized_definition.direction
    and rooted_transition.pre_anchor.x == authorized_definition.pre_anchor.x)
rooted_transition.pre_anchor.x = 999
local rooted_transition_again = assert(authorized_transition_runtime:authorize_transition(
    authorized_transition.contract.contract_id,
    authorized_definition.transition_id))
assert(rooted_transition_again.pre_anchor.x == authorized_definition.pre_anchor.x,
    'authorized transition accessor leaked its private rooted definition')
local wrong_contract_transition, wrong_contract_reason =
    authorized_transition_runtime:authorize_transition(
        'route:v2:' .. string.rep('f', 64),
        authorized_definition.transition_id)
assert(wrong_contract_transition == nil
    and tostring(wrong_contract_reason):lower():find('contract', 1, true))
local definition_only_transition, definition_only_reason = corridor_runtime:authorize_transition(
    corridor_fixture.contract.contract_id,
    crossing.transition_id)
assert(definition_only_transition == nil
    and tostring(definition_only_reason):lower():find('authorized', 1, true))

local invalid_end_native = new_native_spy(asymmetric_paths, { validity = { true, false } })
local invalid_end_fixture = new_authorization_fixture()
local invalid_end_runtime = runtime_with_native(invalid_end_fixture, invalid_end_native)
local invalid_end_points, invalid_end_reason = invalid_end_runtime:compute_exact_objective_leg(
    asymmetric_request)
assert(invalid_end_points == nil and invalid_end_reason == 'end-invalid')
assert(invalid_end_native.counts.FindPath == 0 and invalid_end_native.counts.Get_WayPoints == 0
    and invalid_end_native.counts.FindClosestPath == 0)
assert(table.concat(invalid_end_native.calls, ',')
    == 'IsValidPosition,GetDistanceToWall,IsValidPosition')

local low_clearance_native = new_native_spy({ asymmetric_paths[1] }, {
    clearance = function(point) return point.x == 44 and 0.1 or 1 end,
})
local low_clearance_fixture = new_authorization_fixture()
local low_clearance_runtime = runtime_with_native(low_clearance_fixture, low_clearance_native)
local low_points, low_reason = low_clearance_runtime:compute_exact_objective_leg(asymmetric_request)
assert(low_points == nil and (low_reason == 'waypoint-clearance' or low_reason == 'endpoint-clearance'))
assert(low_clearance_native.counts.FindClosestPath == 0)

local small_policy_fixture = new_authorization_fixture()
replace_file_bytes(
    small_policy_fixture,
    'modules/mission_quest_route_policy.lua',
    'return { schema_version = 2, policy_revision = "objective-route-proof-v2.1", policy_sha256 = "'
        .. string.rep('b', 64)
        .. '", probe_protocol = "accessxi-navprobe-jsonl-v2", probe_schema = 2, thresholds = {'
        .. ' endpoint_epsilon_yalms = 0.75, maximum_segment_length_yalms = 80,'
        .. ' maximum_waypoint_count = 2, minimum_endpoint_clearance_yalms = 0.5,'
        .. ' minimum_waypoint_clearance_yalms = 0.25, transition_corridor_radius_yalms = 3 }, fixtures = {} }\n')
small_policy_fixture:rebuild_manifest()
local excessive_native = new_native_spy({ {
    { x = 11, y = -33, z = 22 },
    { x = 20, y = -40, z = 30 },
    { x = 44, y = -66, z = 55 },
} })
local small_policy_runtime = runtime_with_native(small_policy_fixture, excessive_native)
assert(small_policy_runtime:is_ready() == true, small_policy_runtime:failure_reason())
small_policy_runtime.policy = { thresholds = { maximum_waypoint_count = 999999 } }
small_policy_runtime.contracts = {}
small_policy_runtime.transitions = {}
small_policy_runtime.graph_rows = {}
local excessive_points, excessive_reason = small_policy_runtime:compute_exact_objective_leg(
    asymmetric_request)
assert(excessive_points == nil and excessive_reason == 'waypoint-count-excessive')
assert(excessive_native.counts.FindPath == 1 and excessive_native.counts.Get_WayPoints == 1
    and excessive_native.counts.FindClosestPath == 0)

do
    local first_call_drift_fixture = new_authorization_fixture()
    local first_call_drift_native = new_native_spy({ asymmetric_paths[1] })
    local first_call_validity = first_call_drift_native.is_valid_position
    local first_call_mutated = false
    function first_call_drift_native:is_valid_position(point)
        local result = first_call_validity(self, point)
        if not first_call_mutated then
            first_call_mutated = true
            first_call_drift_fixture.native_snapshot.mesh.identity.write_time_low =
                first_call_drift_fixture.native_snapshot.mesh.identity.write_time_low + 1
        end
        return result
    end
    local first_call_drift_runtime = runtime_with_native(
        first_call_drift_fixture, first_call_drift_native)
    local first_call_drift_points, first_call_drift_reason =
        first_call_drift_runtime:compute_exact_objective_leg(asymmetric_request)
    assert(first_call_drift_points == nil
        and tostring(first_call_drift_reason):lower():find('stale', 1, true) ~= nil,
        'observer drift after endpoint validity must block before the next native call')
    assert(table.concat(first_call_drift_native.calls, ',') == 'IsValidPosition'
        and first_call_drift_native.counts.FindPath == 0
        and first_call_drift_native.counts.Get_WayPoints == 0,
        'native calls continued after the first mid-sequence integrity drift')
end

do
    local find_path_drift_fixture = new_authorization_fixture()
    local find_path_drift_native = new_native_spy({ asymmetric_paths[1] })
    local find_path_method = find_path_drift_native.find_path
    function find_path_drift_native:find_path(start_point, end_point)
        find_path_method(self, start_point, end_point)
        find_path_drift_fixture.native_snapshot.mesh.identity.write_time_low =
            find_path_drift_fixture.native_snapshot.mesh.identity.write_time_low + 1
    end
    local find_path_drift_runtime = runtime_with_native(
        find_path_drift_fixture, find_path_drift_native)
    local find_path_drift_points, find_path_drift_reason =
        find_path_drift_runtime:compute_exact_objective_leg(asymmetric_request)
    assert(find_path_drift_points == nil
        and tostring(find_path_drift_reason):lower():find('stale', 1, true) ~= nil,
        'observer drift after FindPath must block before Get_WayPoints')
    assert(find_path_drift_native.counts.FindPath == 1
        and find_path_drift_native.counts.Get_WayPoints == 0
        and find_path_drift_native.counts.FindClosestPath == 0,
        'Get_WayPoints ran after FindPath changed the observer-attested binding')
end

for _, failure in ipairs({
    {
        name = 'validity throws',
        mutate = function(spy) spy.is_valid_position = function() error('synthetic validity failure') end end,
    },
    {
        name = 'validity malformed',
        mutate = function(spy) spy.is_valid_position = function() return 'yes' end end,
    },
    {
        name = 'clearance throws',
        mutate = function(spy) spy.get_distance_to_wall = function() error('synthetic clearance failure') end end,
    },
    {
        name = 'find throws',
        mutate = function(spy) spy.find_path = function() error('synthetic find failure') end end,
    },
    {
        name = 'waypoints throw',
        mutate = function(spy) spy.get_waypoints = function() error('synthetic waypoint failure') end end,
    },
    {
        name = 'waypoints malformed',
        mutate = function(spy) spy.get_waypoints = function() return { bad = true } end end,
    },
}) do
    local failing_native = new_native_spy({ asymmetric_paths[1] })
    failure.mutate(failing_native)
    local failing_fixture = new_authorization_fixture()
    local failing_runtime = runtime_with_native(failing_fixture, failing_native)
    local call_ok, failure_points, failure_reason = pcall(
        failing_runtime.compute_exact_objective_leg,
        failing_runtime,
        asymmetric_request)
    assert(call_ok and failure_points == nil, failure.name .. ' escaped or authorized a leg')
    assert(failure_reason == 'tool-error', failure.name .. ': ' .. tostring(failure_reason))
end

for _, invalid_hash in ipairs({
    function(bytes)
        if bytes:find('^42\t') then error('synthetic graph row hash failure') end
        return fixture_sha256(bytes)
    end,
    function(bytes)
        if bytes:find('^42\t') then return 'not-a-canonical-digest' end
        return fixture_sha256(bytes)
    end,
}) do
    local hash_fixture = new_authorization_fixture()
    local hash_options = hash_fixture:options()
    hash_options.sha256 = invalid_hash
    local creation_ok, hash_runtime = pcall(runtime_module.new, hash_options)
    assert(creation_ok and hash_runtime:is_ready() == false,
        'graph row hash failures must create a blocked runtime without throwing')
    assert(hash_runtime:failure_reason():lower():find('hash', 1, true) ~= nil)
end

function task45_runtime_red()
    local failures = {}
    local function check(value, message)
        if not value then failures[#failures + 1] = message end
    end
    local function add_mesh(fixture, relative_path, zone, mesh_name, bytes)
        fixture.definitions[#fixture.definitions + 1] = {
            relative_path = relative_path,
            kind = 'mesh',
            zone = zone,
            mesh_name = mesh_name,
        }
        fixture.files[fixture:path(relative_path)] = {
            bytes = bytes,
            identity = {
                size_low = #bytes,
                size_high = 0,
                write_time_low = 3000 + #fixture.definitions,
                write_time_high = 100,
            },
        }
    end
    local function remove_mesh(fixture, relative_path)
        for index = #fixture.definitions, 1, -1 do
            if fixture.definitions[index].relative_path == relative_path then
                table.remove(fixture.definitions, index)
            end
        end
        fixture.files[fixture:path(relative_path)] = nil
    end
    local function replace_contracts(fixture, contracts)
        replace_file_bytes(
            fixture,
            'modules/mission_quest_route_contracts.lua',
            'return ' .. lua_value(contracts) .. '\n')
    end
    local function expect_blocked_fixture(label, fixture)
        fixture:rebuild_manifest()
        local creation_ok, candidate_runtime = pcall(runtime_module.new, fixture:options())
        check(creation_ok and type(candidate_runtime) == 'table'
            and candidate_runtime:is_ready() == false,
            label .. ' was accepted')
    end

    local zero_extra = new_loader_fixture()
    add_mesh(
        zero_extra,
        'third_party/xiNavmeshes/Extra.nav',
        '230',
        'Extra.nav',
        'zero contract extra mesh')
    expect_blocked_fixture('zero-contract manifest with an extra mesh', zero_extra)

    local leading_zero = new_loader_fixture()
    add_mesh(
        leading_zero,
        'third_party/xiNavmeshes/000.nav',
        '0230',
        '000.nav',
        'leading zero mesh alias')
    expect_blocked_fixture('leading-zero manifest zone alias', leading_zero)

    local unicode_zone = new_loader_fixture()
    add_mesh(
        unicode_zone,
        'third_party/xiNavmeshes/001.nav',
        '\217\160\217\162\217\163\217\160',
        '001.nav',
        'unicode mesh zone alias')
    expect_blocked_fixture('Unicode manifest zone alias', unicode_zone)

    local duplicate_zone = new_loader_fixture()
    add_mesh(
        duplicate_zone,
        'third_party/xiNavmeshes/A.nav',
        '230',
        'A.nav',
        'duplicate mesh A')
    add_mesh(
        duplicate_zone,
        'third_party/xiNavmeshes/B.nav',
        '230',
        'B.nav',
        'duplicate mesh B')
    expect_blocked_fixture('duplicate numeric manifest mesh zone', duplicate_zone)

    local multi_prefix = new_authorization_fixture()
    multi_prefix.contract.authorized_directed_prefix = { 10, 20 }
    replace_contracts(multi_prefix, { multi_prefix.contract })
    expect_blocked_fixture('route:v2 multi-edge directed prefix', multi_prefix)

    local wrong_local_ingress = new_authorization_fixture()
    wrong_local_ingress.contract.local_leg.leg.zoneline_id = 10
    replace_contracts(wrong_local_ingress, { wrong_local_ingress.contract })
    expect_blocked_fixture('route:v2 prefix differs from local ingress', wrong_local_ingress)

    local missing_local_ingress = new_authorization_fixture()
    missing_local_ingress.contract.local_leg.leg = nil
    replace_contracts(missing_local_ingress, { missing_local_ingress.contract })
    expect_blocked_fixture('route:v2 local ingress identity is missing', missing_local_ingress)

    local missing_prefix_mesh = new_authorization_fixture()
    remove_mesh(
        missing_prefix_mesh,
        'third_party/xiNavmeshes/Fixture_Cycle_B.nav')
    expect_blocked_fixture('required proven predecessor mesh is missing', missing_prefix_mesh)

    local extra_unselected_mesh = new_authorization_fixture()
    add_mesh(
        extra_unselected_mesh,
        'third_party/xiNavmeshes/Reverse_Only.nav',
        '109',
        'Reverse_Only.nav',
        'unselected reverse-only mesh')
    expect_blocked_fixture('unselected graph mesh is present', extra_unselected_mesh)

    local wrong_prefix_mesh = new_authorization_fixture()
    remove_mesh(
        wrong_prefix_mesh,
        'third_party/xiNavmeshes/Fixture_Start.nav')
    add_mesh(
        wrong_prefix_mesh,
        'third_party/xiNavmeshes/Wrong_Start.nav',
        '100',
        'Wrong_Start.nav',
        'wrong prefix mapping mesh')
    expect_blocked_fixture('coordinated wrong prefix mesh mapping', wrong_prefix_mesh)

    local wrong_target_mesh = new_authorization_fixture()
    remove_mesh(
        wrong_target_mesh,
        'third_party/xiNavmeshes/Palborough_Mines.nav')
    add_mesh(
        wrong_target_mesh,
        'third_party/xiNavmeshes/Wrong_Target.nav',
        '143',
        'Wrong_Target.nav',
        'wrong target mapping mesh')
    local wrong_target_file = wrong_target_mesh.files[wrong_target_mesh:path(
        'third_party/xiNavmeshes/Wrong_Target.nav')]
    wrong_target_mesh.contract.expected_inputs.mesh_name = 'Wrong_Target.nav'
    wrong_target_mesh.contract.expected_inputs.zone_mesh_name = 'Wrong_Target.nav'
    wrong_target_mesh.contract.expected_inputs.mesh_sha256 = fixture_sha256(
        wrong_target_file.bytes)
    replace_contracts(wrong_target_mesh, { wrong_target_mesh.contract })
    expect_blocked_fixture('coordinated wrong target mesh mapping', wrong_target_mesh)

    local conflicting_names = new_authorization_fixture()
    local conflicting_graph = conflicting_names.files[conflicting_names:path(
        'data/ffxi-nav-zoneline-graph.tsv')].bytes:gsub(
            '\t100\tFixture Start\tfixture\t0\t0\t0\tfixture%-live%-walk\tproven\t',
            '\t100\tConflicting Start\tfixture\t0\t0\t0\tfixture-live-walk\tproven\t',
            1)
    replace_file_bytes(
        conflicting_names,
        'data/ffxi-nav-zoneline-graph.tsv',
        conflicting_graph)
    conflicting_names.contract.expected_inputs.graph_sha256 = fixture_sha256(
        conflicting_graph)
    replace_contracts(conflicting_names, { conflicting_names.contract })
    expect_blocked_fixture('conflicting required graph zone names', conflicting_names)

    local multi_contract = new_authorization_fixture()
    local alternate_predecessor_line = table.concat({
        '69', '93', 'Deep Alternate', 'fixture', '3', '4', '5',
        '101', 'Alternate Entry', 'fixture', '6', '7', '8',
        'fixture-live-walk', 'proven', '',
    }, '\t') .. '\n'
    local alternate_ingress_line = table.concat({
        '70', '101', 'Alternate Entry', 'fixture', '6', '7', '8',
        '143', 'Palborough Mines', 'fixture', '0', '0', '0',
        'fixture-live-walk', 'proven', '',
    }, '\t') .. '\n'
    local multi_graph = multi_contract.files[multi_contract:path(
        'data/ffxi-nav-zoneline-graph.tsv')].bytes
        .. alternate_predecessor_line .. alternate_ingress_line
    replace_file_bytes(
        multi_contract,
        'data/ffxi-nav-zoneline-graph.tsv',
        multi_graph)
    multi_contract.contract.expected_inputs.graph_sha256 = fixture_sha256(multi_graph)
    local alternate_contract = copy_value(multi_contract.contract)
    alternate_contract.contract_id = 'route:v2:' .. string.rep('b', 64)
    alternate_contract.authorized_directed_prefix = { 70 }
    alternate_contract.local_leg.leg.zoneline_id = 70
    alternate_contract.expected_inputs.ingress_row_sha256 = fixture_sha256(
        alternate_ingress_line)
    add_mesh(
        multi_contract,
        'third_party/xiNavmeshes/Deep_Alternate.nav',
        '93',
        'Deep_Alternate.nav',
        'multi-contract deep alternate mesh')
    add_mesh(
        multi_contract,
        'third_party/xiNavmeshes/Alternate_Entry.nav',
        '101',
        'Alternate_Entry.nav',
        'multi-contract alternate entry mesh')
    replace_contracts(
        multi_contract,
        { multi_contract.contract, alternate_contract })
    multi_contract:rebuild_manifest()
    local multi_contract_runtime = runtime_module.new(multi_contract:options())
    check(multi_contract_runtime:is_ready() == true,
        'same-candidate multi-ingress exact mesh union was rejected')
    local missing_alternate = new_authorization_fixture()
    replace_file_bytes(
        missing_alternate,
        'data/ffxi-nav-zoneline-graph.tsv',
        multi_graph)
    missing_alternate.contract.expected_inputs.graph_sha256 = fixture_sha256(multi_graph)
    local missing_alternate_contract = copy_value(missing_alternate.contract)
    missing_alternate_contract.contract_id = alternate_contract.contract_id
    missing_alternate_contract.authorized_directed_prefix = { 70 }
    missing_alternate_contract.local_leg.leg.zoneline_id = 70
    missing_alternate_contract.expected_inputs.ingress_row_sha256 = fixture_sha256(
        alternate_ingress_line)
    add_mesh(
        missing_alternate,
        'third_party/xiNavmeshes/Alternate_Entry.nav',
        '101',
        'Alternate_Entry.nav',
        'multi-contract alternate entry mesh')
    replace_contracts(
        missing_alternate,
        { missing_alternate.contract, missing_alternate_contract })
    expect_blocked_fixture(
        'same-candidate second ingress predecessor mesh is missing',
        missing_alternate)

    local equivalent_predecessor = new_authorization_fixture()
    local equivalent_edge_line = table.concat({
        '75', '93', 'Transition Start', 'fixture', '3', '4', '5',
        '100', 'Fixture Start', 'fixture', '6', '7', '8',
        'fixture-reviewed-transition', 'observed', '',
    }, '\t') .. '\n'
    local equivalent_graph = equivalent_predecessor.files[equivalent_predecessor:path(
        'data/ffxi-nav-zoneline-graph.tsv')].bytes .. equivalent_edge_line
    replace_file_bytes(
        equivalent_predecessor,
        'data/ffxi-nav-zoneline-graph.tsv',
        equivalent_graph)
    equivalent_predecessor.contract.expected_inputs.graph_sha256 = fixture_sha256(
        equivalent_graph)
    local equivalent_definition = {
        transition_id = 'fixture-transition:forward',
        base_id = 'fixture-transition',
        zone = 93,
        direction = 'forward',
        from_zone = 93,
        to_zone = 100,
        equivalent_zoneline_id = 75,
        reviewed = true,
        pre_anchor = { x = 3, z = 4, y = 5 },
        post_anchor = { x = 6, z = 7, y = 8 },
        expected_live_state = 'fixture-zone-change',
        timeout_seconds = 45,
        cancellation = {},
        interaction = { kind = 'fixture', identity = 'fixture-transition' },
        required_destination_ids = {},
    }
    equivalent_predecessor.contract.required_transition_ids = {
        equivalent_definition.transition_id,
    }
    replace_file_bytes(
        equivalent_predecessor,
        'modules/mission_quest_route_transitions.lua',
        'return ' .. lua_value({
            schema_version = 2,
            source_registry_sha256 = string.rep('c', 64),
            definitions = { equivalent_definition },
            authorized = { equivalent_definition },
        }) .. '\n')
    replace_contracts(
        equivalent_predecessor,
        { equivalent_predecessor.contract })
    add_mesh(
        equivalent_predecessor,
        'third_party/xiNavmeshes/Transition_Start.nav',
        '93',
        'Transition_Start.nav',
        'transition-equivalent predecessor mesh')
    equivalent_predecessor:rebuild_manifest()
    local equivalent_options = equivalent_predecessor:options()
    equivalent_options.transition_is_eligible = function(transition)
        return transition.transition_id == equivalent_definition.transition_id
    end
    local equivalent_runtime = runtime_module.new(equivalent_options)
    check(equivalent_runtime:is_ready() == true,
        'contract-authorized transition-equivalent predecessor was rejected')
    local missing_equivalent = new_authorization_fixture()
    replace_file_bytes(
        missing_equivalent,
        'data/ffxi-nav-zoneline-graph.tsv',
        equivalent_graph)
    missing_equivalent.contract.expected_inputs.graph_sha256 = fixture_sha256(
        equivalent_graph)
    missing_equivalent.contract.required_transition_ids = {
        equivalent_definition.transition_id,
    }
    replace_file_bytes(
        missing_equivalent,
        'modules/mission_quest_route_transitions.lua',
        'return ' .. lua_value({
            schema_version = 2,
            source_registry_sha256 = string.rep('c', 64),
            definitions = { equivalent_definition },
            authorized = { equivalent_definition },
        }) .. '\n')
    replace_contracts(missing_equivalent, { missing_equivalent.contract })
    missing_equivalent:rebuild_manifest()
    local missing_equivalent_options = missing_equivalent:options()
    missing_equivalent_options.transition_is_eligible = equivalent_options.transition_is_eligible
    local missing_equivalent_runtime = runtime_module.new(missing_equivalent_options)
    check(missing_equivalent_runtime:is_ready() == false,
        'transition-equivalent predecessor mesh was not required')

    local api_fixture = new_authorization_fixture()
    local api_runtime = runtime_module.new(api_fixture:options())
    check(type(api_runtime.prepare_next_objective_prefix_leg) == 'function',
        'prepare_next_objective_prefix_leg API is missing')

    if type(api_runtime.prepare_next_objective_prefix_leg) == 'function' then
        local function runtime_with_prefix_loader(fixture, native, mutate)
            local options = fixture:options()
            local load_calls = {}
            options.objective_native = native
            options.objective_mesh_loader = function(zone, mesh_name, path)
                load_calls[#load_calls + 1] = {
                    zone = zone,
                    mesh_name = mesh_name,
                    path = path,
                }
                native.calls[#native.calls + 1] = 'LoadMesh'
                local binding = fixture.meshes_by_zone[zone]
                if binding == nil or binding.name ~= mesh_name then return false end
                local relative_path = 'third_party/xiNavmeshes/' .. mesh_name
                if path ~= fixture:path(relative_path) then return false end
                local file = fixture.files[path]
                if file == nil then return false end
                fixture.native_snapshot.mesh = {
                    path = path,
                    sha256 = fixture_sha256(file.bytes),
                    identity = copy_identity(file.identity),
                    mesh_name = mesh_name,
                    zone = zone,
                }
                return true
            end
            if type(mutate) == 'function' then mutate(options, load_calls) end
            return runtime_module.new(options), load_calls
        end
        local function exact_keys(value, expected)
            if type(value) ~= 'table' then return false end
            local seen = {}
            for _, key in ipairs(expected) do seen[key] = true end
            local count = 0
            for key in pairs(value) do
                if not seen[key] then return false end
                count = count + 1
            end
            return count == #expected
        end
        local function prefix_path(start_point, end_point)
            return {
                { x = start_point.x, y = start_point.y, z = start_point.z },
                { x = end_point.x, y = end_point.y, z = end_point.z },
            }
        end
        local function invoke(runtime_value, contract_id, player, ...)
            local ok, descriptor, reason = pcall(
                runtime_value.prepare_next_objective_prefix_leg,
                runtime_value,
                contract_id,
                player,
                ...)
            return ok, descriptor, reason
        end

        local prefix_fixture = new_authorization_fixture()
        local prefix_native = new_native_spy({
            prefix_path(
                { x = 11, y = -33, z = 22 },
                { x = 1, y = 0, z = 1 }),
            {},
            prefix_path(
                { x = 11, y = -33, z = 22 },
                { x = 1, y = 0, z = 1 }),
        })
        local prefix_runtime, prefix_loads = runtime_with_prefix_loader(
            prefix_fixture, prefix_native)
        check(prefix_runtime:is_ready(), prefix_runtime:failure_reason())
        local call_ok, descriptor, reason = invoke(
            prefix_runtime,
            prefix_fixture.contract.contract_id,
            { zone = 100, x = 11, z = 22, y = -33 })
        check(call_ok and type(descriptor) == 'table' and reason == '',
            'rooted current-zone prefix leg was not prepared: ' .. tostring(reason))
        if type(descriptor) == 'table' then
            check(exact_keys(descriptor, {
                'objective_route_contract_id', 'objective_contract_snapshot',
                'stage', 'edge', 'from_zone', 'to_zone', 'edge_row_sha256',
                'endpoint', 'mesh', 'waypoints', 'path_suffix',
            }), 'prepared prefix descriptor field set is not exact')
            check(descriptor.objective_route_contract_id == prefix_fixture.contract.contract_id
                and descriptor.stage == 'prefix'
                and descriptor.edge.zoneline_id == 10
                and descriptor.from_zone == 100
                and descriptor.to_zone == 106
                and descriptor.edge_row_sha256 == fixture_sha256(
                    prefix_fixture.first_prefix_line),
                'prepared prefix descriptor edge identity is not exact')
            check(descriptor.endpoint.zone == 100
                and descriptor.endpoint.x == 1
                and descriptor.endpoint.z == 1
                and descriptor.endpoint.y == 0,
                'prepared prefix endpoint did not come from edge.from_x/from_z/from_y')
            check(type(descriptor.mesh) == 'table'
                and descriptor.mesh.zone == 100
                and descriptor.mesh.mesh_name == 'Fixture_Start.nav'
                and descriptor.mesh.relative_path
                    == 'third_party/xiNavmeshes/Fixture_Start.nav'
                and descriptor.mesh.path == prefix_fixture:path(
                    'third_party/xiNavmeshes/Fixture_Start.nav')
                and descriptor.mesh.sha256 == fixture_sha256(
                    prefix_fixture.meshes_by_zone[100].bytes),
                'prepared prefix descriptor mesh binding is not exact')
            check(edge_ids(descriptor.path_suffix) == '10,20',
                'prepared prefix descriptor did not preserve its rooted full suffix')
            check(#descriptor.waypoints == 2
                and descriptor.waypoints[1].x == 11
                and descriptor.waypoints[1].z == 22
                and descriptor.waypoints[1].y == -33
                and descriptor.waypoints[2].x == 1
                and descriptor.waypoints[2].z == 1
                and descriptor.waypoints[2].y == 0,
                'prepared prefix waypoints changed native axis order')
            descriptor.edge.from_x = 999
            descriptor.mesh.mesh_name = 'forged.nav'
            descriptor.path_suffix[1].zoneline_id = 999
        end
        check(#prefix_loads == 1
            and prefix_loads[1].zone == 100
            and prefix_loads[1].mesh_name == 'Fixture_Start.nav'
            and prefix_loads[1].path == prefix_fixture:path(
                'third_party/xiNavmeshes/Fixture_Start.nav'),
            'prefix loader did not receive the exact rooted current-zone mesh')
        check(prefix_native.find_start.x == 11
            and prefix_native.find_start.y == -33
            and prefix_native.find_start.z == 22
            and prefix_native.find_end.x == 1
            and prefix_native.find_end.y == 0
            and prefix_native.find_end.z == 1,
            'prefix FindPath endpoints were not derived with exact native axes')
        check(table.concat(prefix_native.calls, ',') == table.concat({
            'LoadMesh',
            'IsValidPosition', 'GetDistanceToWall',
            'IsValidPosition', 'GetDistanceToWall',
            'FindPath', 'Get_WayPoints',
            'GetDistanceToWall', 'GetDistanceToWall',
        }, ','), 'prefix native call sequence changed: '
            .. table.concat(prefix_native.calls, ','))
        check(prefix_native.counts.FindPath == 1
            and prefix_native.counts.Get_WayPoints == 1
            and prefix_native.counts.FindClosestPath == 0,
            'prefix operation used a native fallback or wrong call count')

        local second_ok, second_descriptor, second_reason = invoke(
            prefix_runtime,
            prefix_fixture.contract.contract_id,
            { zone = 100, x = 11, z = 22, y = -33 })
        check(second_ok and second_descriptor == nil
            and second_reason == 'no-exact-path',
            'zero-waypoint prefix result was not truthfully blocked')
        local third_ok, third_descriptor, third_reason = invoke(
            prefix_runtime,
            prefix_fixture.contract.contract_id,
            { zone = 100, x = 11, z = 22, y = -33 })
        check(third_ok and type(third_descriptor) == 'table' and third_reason == '',
            'valid prefix did not recover after a zero-waypoint result')
        if type(third_descriptor) == 'table' then
            check(third_descriptor.edge.zoneline_id == 10
                and third_descriptor.mesh.mesh_name == 'Fixture_Start.nav',
                'returned descriptor mutation leaked into private runtime state')
        end
        check(prefix_native.counts.FindPath == 3
            and prefix_native.counts.Get_WayPoints == 3
            and prefix_native.counts.FindClosestPath == 0,
            'same-handle valid-zero-valid sequence reused stale waypoints')

        local middle_fixture = new_authorization_fixture()
        local middle_native = new_native_spy({ prefix_path(
            { x = 5, y = -3, z = 6 },
            { x = 10, y = 0, z = 10 }) })
        local middle_runtime, middle_loads = runtime_with_prefix_loader(
            middle_fixture, middle_native)
        local middle_ok, middle_descriptor, middle_reason = invoke(
            middle_runtime,
            middle_fixture.contract.contract_id,
            { zone = 106, x = 5, z = 6, y = -3 })
        check(middle_ok and type(middle_descriptor) == 'table' and middle_reason == ''
            and middle_descriptor.edge.zoneline_id == 20
            and edge_ids(middle_descriptor.path_suffix) == '20'
            and middle_descriptor.endpoint.x == 10
            and middle_descriptor.endpoint.z == 10
            and middle_descriptor.endpoint.y == 0
            and #middle_loads == 1
            and middle_loads[1].mesh_name == 'North_Gustaberg.nav',
            'zone-change continuation did not recompute the next exact prefix leg')

        local final_fixture = new_authorization_fixture()
        local final_native = new_native_spy({ prefix_path(
            { x = 11, y = -33, z = 22 },
            { x = 1, y = 0, z = 0 }) })
        local final_runtime, final_loads = runtime_with_prefix_loader(
            final_fixture, final_native)
        local final_ok, final_descriptor, final_reason = invoke(
            final_runtime,
            final_fixture.contract.contract_id,
            { zone = 143, x = 11, z = 22, y = -33 })
        check(final_ok and type(final_descriptor) == 'table' and final_reason == ''
            and final_descriptor.stage == 'final'
            and final_descriptor.endpoint.zone == 143
            and final_descriptor.endpoint.x == 1
            and final_descriptor.endpoint.z == 0
            and final_descriptor.endpoint.y == 0
            and #final_descriptor.path_suffix == 0
            and #final_loads == 1
            and final_loads[1].mesh_name == 'Palborough_Mines.nav',
            'target-zone continuation did not compute the exact final destination leg')

        local cycle_fixture = new_authorization_fixture()
        local cycle_native = new_native_spy({ prefix_path(
            { x = 9, y = -7, z = 8 },
            { x = 0, y = 0, z = 0 }) })
        local cycle_runtime = runtime_with_prefix_loader(cycle_fixture, cycle_native)
        local cycle_ok, cycle_descriptor, cycle_reason = invoke(
            cycle_runtime,
            cycle_fixture.contract.contract_id,
            { zone = 108, x = 9, z = 8, y = -7 })
        check(cycle_ok and type(cycle_descriptor) == 'table' and cycle_reason == ''
            and cycle_descriptor.edge.zoneline_id == 42
            and edge_ids(cycle_descriptor.path_suffix) == '42,40,10,20',
            'cycle path did not choose the deterministic first directed edge')

        for _, field in ipairs({
            'edge_id', 'end', 'mesh_name', 'mesh_path', 'native', 'transition',
        }) do
            local override_fixture = new_authorization_fixture()
            local override_native = new_native_spy({ prefix_path(
                { x = 11, y = -33, z = 22 },
                { x = 1, y = 0, z = 1 }) })
            local override_runtime, override_loads = runtime_with_prefix_loader(
                override_fixture, override_native)
            local player = { zone = 100, x = 11, z = 22, y = -33 }
            player[field] = field == 'end' and { x = 999, z = 999, y = 999 }
                or 'forged'
            local override_ok, override_descriptor, override_reason = invoke(
                override_runtime,
                override_fixture.contract.contract_id,
                player)
            check(override_ok and override_descriptor == nil
                and tostring(override_reason):lower():find('malformed', 1, true) ~= nil
                and #override_loads == 0
                and override_native.counts.FindPath == 0,
                'caller-controlled ' .. field .. ' override was accepted')
        end
        local positional_fixture = new_authorization_fixture()
        local positional_native = new_native_spy({})
        local positional_runtime, positional_loads = runtime_with_prefix_loader(
            positional_fixture, positional_native)
        local positional_ok, positional_descriptor, positional_reason = invoke(
            positional_runtime,
            positional_fixture.contract.contract_id,
            { zone = 100, x = 11, z = 22, y = -33 },
            { edge_id = 10 })
        check(positional_ok and positional_descriptor == nil
            and tostring(positional_reason):lower():find('override', 1, true) ~= nil
            and #positional_loads == 0
            and positional_native.counts.FindPath == 0,
            'positional objective prefix override was accepted')

        for _, invalid in ipairs({
            { contract_id = 'route:v2:' .. string.rep('f', 64), player = { zone = 100, x = 1, z = 2, y = 3 } },
            { contract_id = prefix_fixture.contract.contract_id, player = { zone = '100', x = 1, z = 2, y = 3 } },
            { contract_id = prefix_fixture.contract.contract_id, player = { zone = 100, x = 0 / 0, z = 2, y = 3 } },
            { contract_id = prefix_fixture.contract.contract_id, player = { zone = 999, x = 1, z = 2, y = 3 } },
            { contract_id = prefix_fixture.contract.contract_id, player = { zone = 109, x = 1, z = 2, y = 3 } },
        }) do
            local invalid_fixture = new_authorization_fixture()
            local invalid_native = new_native_spy({})
            local invalid_runtime, invalid_loads = runtime_with_prefix_loader(
                invalid_fixture, invalid_native)
            local invalid_ok, invalid_descriptor = invoke(
                invalid_runtime, invalid.contract_id, invalid.player)
            check(invalid_ok and invalid_descriptor == nil
                and #invalid_loads == 0
                and invalid_native.counts.FindPath == 0
                and invalid_native.counts.FindClosestPath == 0,
                'malformed, unrooted, disconnected, or reverse-only prefix request ran native code')
        end

        for _, drift in ipairs({
            { relative_path = 'data/ffxi-nav-zoneline-graph.tsv', label = 'graph' },
            { relative_path = 'third_party/xiNavmeshes/Fixture_Start.nav', label = 'mesh' },
            { relative_path = 'modules/mission_quest_route_contracts.lua', label = 'contract' },
        }) do
            local drift_fixture = new_authorization_fixture()
            local drift_native = new_native_spy({ prefix_path(
                { x = 11, y = -33, z = 22 },
                { x = 1, y = 0, z = 1 }) })
            local drift_runtime, drift_loads = runtime_with_prefix_loader(
                drift_fixture, drift_native)
            drift_fixture.files[drift_fixture:path(drift.relative_path)]
                .identity.write_time_low = drift_fixture.files[drift_fixture:path(
                    drift.relative_path)].identity.write_time_low + 1
            local drift_ok, drift_descriptor = invoke(
                drift_runtime,
                drift_fixture.contract.contract_id,
                { zone = 100, x = 11, z = 22, y = -33 })
            check(drift_ok and drift_descriptor == nil
                and #drift_loads == 0
                and drift_native.counts.FindPath == 0,
                drift.label .. ' identity drift reached prefix mesh/native execution')
        end

        for _, loader_failure in ipairs({ 'missing', 'false', 'throw', 'wrong-observer' }) do
            local loader_fixture = new_authorization_fixture()
            local loader_native = new_native_spy({ prefix_path(
                { x = 11, y = -33, z = 22 },
                { x = 1, y = 0, z = 1 }) })
            local loader_runtime = runtime_with_prefix_loader(
                loader_fixture,
                loader_native,
                function(options)
                    if loader_failure == 'missing' then
                        options.objective_mesh_loader = nil
                    elseif loader_failure == 'false' then
                        options.objective_mesh_loader = function() return false end
                    elseif loader_failure == 'throw' then
                        options.objective_mesh_loader = function()
                            error('synthetic loader failure')
                        end
                    else
                        options.objective_mesh_loader = function()
                            loader_fixture.native_snapshot.mesh.mesh_name = 'wrong.nav'
                            return true
                        end
                    end
                end)
            local loader_ok, loader_descriptor = invoke(
                loader_runtime,
                loader_fixture.contract.contract_id,
                { zone = 100, x = 11, z = 22, y = -33 })
            check(loader_ok and loader_descriptor == nil
                and loader_native.counts.FindPath == 0
                and loader_native.counts.FindClosestPath == 0,
                loader_failure .. ' private mesh loader authorized a prefix')
        end

        local first_drift_fixture = new_authorization_fixture()
        local first_drift_native = new_native_spy({ prefix_path(
            { x = 11, y = -33, z = 22 },
            { x = 1, y = 0, z = 1 }) })
        local first_validity = first_drift_native.is_valid_position
        local first_mutated = false
        function first_drift_native:is_valid_position(point)
            local value = first_validity(self, point)
            if not first_mutated then
                first_mutated = true
                first_drift_fixture.native_snapshot.mesh.identity.write_time_low =
                    first_drift_fixture.native_snapshot.mesh.identity.write_time_low + 1
            end
            return value
        end
        local first_drift_runtime = runtime_with_prefix_loader(
            first_drift_fixture, first_drift_native)
        local first_drift_ok, first_drift_descriptor = invoke(
            first_drift_runtime,
            first_drift_fixture.contract.contract_id,
            { zone = 100, x = 11, z = 22, y = -33 })
        check(first_drift_ok and first_drift_descriptor == nil
            and table.concat(first_drift_native.calls, ',') == 'LoadMesh,IsValidPosition'
            and first_drift_native.counts.FindPath == 0,
            'observer drift after first prefix native call did not stop the sequence')

        local find_drift_fixture = new_authorization_fixture()
        local find_drift_native = new_native_spy({ prefix_path(
            { x = 11, y = -33, z = 22 },
            { x = 1, y = 0, z = 1 }) })
        local original_find = find_drift_native.find_path
        function find_drift_native:find_path(start_point, end_point)
            original_find(self, start_point, end_point)
            find_drift_fixture.native_snapshot.mesh.identity.write_time_low =
                find_drift_fixture.native_snapshot.mesh.identity.write_time_low + 1
        end
        local find_drift_runtime = runtime_with_prefix_loader(
            find_drift_fixture, find_drift_native)
        local find_drift_ok, find_drift_descriptor = invoke(
            find_drift_runtime,
            find_drift_fixture.contract.contract_id,
            { zone = 100, x = 11, z = 22, y = -33 })
        check(find_drift_ok and find_drift_descriptor == nil
            and find_drift_native.counts.FindPath == 1
            and find_drift_native.counts.Get_WayPoints == 0
            and find_drift_native.counts.FindClosestPath == 0,
            'observer drift after prefix FindPath did not stop Get_WayPoints')

        local corridor_fixture = new_authorization_fixture()
        local prefix_corridor = {
            transition_id = 'fixture-prefix-corridor:forward',
            zone = 100,
            pre_anchor = { x = 6, z = 6, y = -1 },
            post_anchor = { x = 6, z = 6, y = 1 },
        }
        replace_file_bytes(
            corridor_fixture,
            'modules/mission_quest_route_transitions.lua',
            'return ' .. lua_value({
                schema_version = 2,
                source_registry_sha256 = string.rep('c', 64),
                definitions = { prefix_corridor },
                authorized = {},
            }) .. '\n')
        corridor_fixture:rebuild_manifest()
        local corridor_native = new_native_spy({ prefix_path(
            { x = 11, y = 0, z = 11 },
            { x = 1, y = 0, z = 1 }) })
        local corridor_runtime = runtime_with_prefix_loader(
            corridor_fixture, corridor_native)
        local corridor_ok, corridor_descriptor, corridor_reason = invoke(
            corridor_runtime,
            corridor_fixture.contract.contract_id,
            { zone = 100, x = 11, z = 11, y = 0 })
        check(corridor_ok and corridor_descriptor == nil
            and corridor_reason == 'requires-transition'
            and corridor_native.counts.FindPath == 1
            and corridor_native.counts.FindClosestPath == 0,
            'rooted blocked transition corridor was crossed by a dynamic prefix')
    end

    if #failures > 0 then
        error('Task4.5 runtime RED failures (' .. tostring(#failures) .. '):\n - '
            .. table.concat(failures, '\n - '), 0)
    end
end

task45_runtime_red()
task45_runtime_red = nil

print('mission and quest route runtime tests passed')
