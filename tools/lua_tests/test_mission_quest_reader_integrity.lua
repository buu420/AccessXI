local reader_path = assert(arg[1], 'reader source path is required')

if type(string.fmt) ~= 'function' then
    function string:fmt(...) return string.format(self, ...) end
end

local reader_file = assert(io.open(reader_path, 'rb'))
local reader_source = assert(reader_file:read('*a'))
reader_file:close()

local begin_marker = '-- ACCESSXI_OBJECTIVE_ROUTE_INTEGRITY_BEGIN'
local end_marker = '-- ACCESSXI_OBJECTIVE_ROUTE_INTEGRITY_END'
local first = assert(reader_source:find(begin_marker, 1, true),
    'reader objective integrity bootstrap block is missing')
local after = assert(reader_source:find(end_marker, first + #begin_marker, true),
    'reader objective integrity bootstrap end marker is missing')
local integrity_source = reader_source:sub(first + #begin_marker, after - 1)

local function digest(bytes)
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

local function copy_identity(identity)
    return {
        size_low = identity.size_low,
        size_high = identity.size_high,
        write_time_low = identity.write_time_low,
        write_time_high = identity.write_time_high,
    }
end

local function fixture_file(bytes, ordinal)
    return {
        bytes = bytes,
        identity = {
            size_low = #bytes,
            size_high = 0,
            write_time_low = ordinal,
            write_time_high = 200,
        },
    }
end

local function new_fixture(options)
    options = options or {}
    local root = 'C:\\fixture\\accessxi_reader'
    local function path(relative)
        return root .. '\\' .. relative:gsub('/', '\\')
    end
    local execution_flags = { runtime = 0 }
    local runtime_bytes = options.runtime_bytes or [[
EXECUTION_FLAGS.runtime = EXECUTION_FLAGS.runtime + 1
return {
    new = function(runtime_options)
        EXECUTION_FLAGS.runtime_options = runtime_options
        return {
            is_ready = function() return true end,
            failure_reason = function() return '' end,
            authorize_start = function() return nil, 'fixture', 'blocked' end,
        }
    end,
}
]]
    local dll_bytes = 'fixture rooted dll bytes'
    local mesh_bytes = 'fixture rooted mesh bytes'
    local runtime_digest = digest(runtime_bytes)
    local manifest_bytes = table.concat({
        'relative_path\tsha256\tkind\tzone\tmesh_name\n',
        'modules/mission_quest_route_runtime.lua\t', runtime_digest, '\truntime\t\t\n',
        'third_party/FFXI-NavMesh-Builder/FFXINAV.dll\t', digest(dll_bytes), '\tffxinav\t\t\n',
        'third_party/xiNavmeshes/Fixture.nav\t', digest(mesh_bytes), '\tmesh\t143\tFixture.nav\n',
    })
    local files = {
        [path('data/mission-quest-route-manifest.tsv')] = fixture_file(
            options.returned_manifest_bytes or manifest_bytes, 1),
        [path('modules/mission_quest_route_runtime.lua')] = fixture_file(
            options.returned_runtime_bytes or runtime_bytes, 2),
        [path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll')] = fixture_file(dll_bytes, 3),
        [path('third_party/xiNavmeshes/Fixture.nav')] = fixture_file(mesh_bytes, 4),
    }
    local compile_records = {}
    local stat_state = {
        close_count = 0,
        fail_open = false,
        fail_size = false,
        fail_time = false,
        fail_close = false,
        last_error = 87,
        set_last_error_count = 0,
        size_low = 0x89abcdef,
        size_high = 0x01234567,
        write_time_low = 0x76543210,
        write_time_high = 0xfedcba98,
    }
    local invalid_handle = {}
    local ffi = {
        C = {},
        cast = function() return invalid_handle end,
        new = function(kind)
            if kind == 'DWORD[1]' then return { [0] = 0 } end
            if kind == 'FILETIME[1]' then
                return { [0] = { dwLowDateTime = 0, dwHighDateTime = 0 } }
            end
            error('unexpected ffi.new fixture: ' .. tostring(kind))
        end,
    }
    local kernel32 = {
        CreateFileW = function()
            return stat_state.fail_open and invalid_handle or {}
        end,
        GetFileSize = function(_, high)
            high[0] = stat_state.size_high
            if stat_state.fail_size then
                stat_state.last_error = 5
                return 0xffffffff
            end
            return stat_state.size_low
        end,
        SetLastError = function(value)
            assert(value == 0)
            stat_state.last_error = 0
            stat_state.set_last_error_count = stat_state.set_last_error_count + 1
        end,
        GetLastError = function()
            return stat_state.last_error
        end,
        GetFileTime = function(_, _, _, write_time)
            if stat_state.fail_time then return 0 end
            write_time[0].dwLowDateTime = stat_state.write_time_low
            write_time[0].dwHighDateTime = stat_state.write_time_high
            return 1
        end,
        CloseHandle = function()
            stat_state.close_count = stat_state.close_count + 1
            return stat_state.fail_close and 0 or 1
        end,
    }
    local hasher = {
        read_and_hash_file = function(_, requested_path)
            local value = files[requested_path]
            if value == nil then return nil, nil, nil, 'fixture file missing' end
            return value.bytes, digest(value.bytes), copy_identity(value.identity)
        end,
    }
    local sha_module = {
        smoke_test = function()
            if options.smoke_failure then return nil, 'synthetic SHA smoke failure' end
            return true
        end,
        sha256 = digest,
        new_file_hasher = function() return hasher end,
    }
    local accessxi = {
        ordinary_navigation_sentinel = true,
        load_module_table = function(name)
            assert(name == 'accessxi_sha256')
            if options.sha_load_throw then error('synthetic SHA module load failure') end
            if options.sha_load_invalid then return {} end
            return sha_module
        end,
    }
    local accessxi_paths = {
        addon_path = function(...)
            local parts = { ... }
            return path(table.concat(parts, '/'))
        end,
        normalize = function(value) return tostring(value):gsub('/', '\\'):gsub('\\+$', '') end,
    }
    local real_loadstring = loadstring
    local environment = setmetatable({
        accessxi = accessxi,
        accessxi_paths = accessxi_paths,
        ffi = ffi,
        kernel32 = kernel32,
        bit = {},
        utf8_to_wide = function(value)
            if options.wide_failure then return nil end
            return value
        end,
        log_line = function() end,
        EXECUTION_FLAGS = execution_flags,
        loadstring = function(bytes, name)
            compile_records[#compile_records + 1] = { bytes = bytes, name = name }
            return real_loadstring(bytes, name)
        end,
    }, { __index = _G })
    local pinned_source, replacements = integrity_source:gsub(
        'ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256%s*=%s*"[0-9a-f]+"',
        'ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256 = "' .. digest(manifest_bytes) .. '"')
    assert(replacements == 1, 'test fixture could not substitute the one reviewed manifest pin')
    local chunk = assert(loadstring(pinned_source, '@reader-objective-integrity'))
    setfenv(chunk, environment)
    local ok, reason = pcall(chunk)
    return {
        ok = ok,
        reason = reason,
        environment = environment,
        accessxi = accessxi,
        files = files,
        path = path,
        manifest_bytes = manifest_bytes,
        runtime_bytes = runtime_bytes,
        compile_records = compile_records,
        execution_flags = execution_flags,
        stat_state = stat_state,
        invalid_handle = invalid_handle,
        hasher = hasher,
        sha_module = sha_module,
    }
end

local valid = new_fixture()
assert(valid.ok, tostring(valid.reason))
assert(type(valid.accessxi.objective_route_runtime) == 'table',
    'reader did not construct accessxi.objective_route_runtime')
assert(valid.execution_flags.runtime == 1, 'accepted runtime module did not execute exactly once')
assert(#valid.compile_records == 1 and valid.compile_records[1].bytes == valid.runtime_bytes,
    'reader did not compile the exact runtime bytes returned by read_and_hash_file')
assert(valid.execution_flags.runtime_options.expected_manifest_sha256 == digest(valid.manifest_bytes))
assert(valid.execution_flags.runtime_options.native_integrity_state
    == valid.accessxi.nav_objective_native_integrity_state)
assert(type(valid.execution_flags.runtime_options.objective_native) == 'table')

local mismatch = new_fixture({ returned_runtime_bytes = 'EXECUTION_FLAGS.runtime = 99\nreturn {}\n' })
assert(mismatch.ok, tostring(mismatch.reason))
assert(mismatch.execution_flags.runtime == 0, 'hash-mismatched runtime bytes executed')
assert(#mismatch.compile_records == 0, 'hash-mismatched runtime bytes reached loadstring')
assert(mismatch.accessxi.objective_route_runtime == nil)
assert(tostring(mismatch.accessxi.objective_route_runtime_failure_reason or ''):lower():find('hash', 1, true))

local manifest_mismatch = new_fixture({ returned_manifest_bytes = 'not the pinned manifest bytes\n' })
assert(manifest_mismatch.ok, tostring(manifest_mismatch.reason))
assert(manifest_mismatch.execution_flags.runtime == 0 and #manifest_mismatch.compile_records == 0,
    'unpinned manifest bytes reached runtime compilation or execution')
assert(manifest_mismatch.accessxi.objective_route_runtime == nil)

local smoke_failure = new_fixture({ smoke_failure = true })
assert(smoke_failure.ok, tostring(smoke_failure.reason))
assert(smoke_failure.accessxi.objective_route_runtime == nil)
assert(smoke_failure.accessxi.ordinary_navigation_sentinel == true,
    'SHA smoke failure disabled ordinary navigation')
assert(tostring(smoke_failure.accessxi.objective_route_runtime_failure_reason or ''):lower():find('smoke', 1, true))

for _, broken_sha in ipairs({
    new_fixture({ sha_load_throw = true }),
    new_fixture({ sha_load_invalid = true }),
}) do
    assert(broken_sha.ok, tostring(broken_sha.reason))
    assert(broken_sha.accessxi.objective_route_runtime == nil
        and broken_sha.accessxi.ordinary_navigation_sentinel == true,
        'malformed SHA dependency failure escaped the objective-only boundary')
end

local identity, identity_reason = valid.environment.accessxi_file_stat('C:\\fixture\\file.bin')
assert(identity_reason == nil and identity.size_low == 0x89abcdef
    and identity.size_high == 0x01234567
    and identity.write_time_low == 0x76543210
    and identity.write_time_high == 0xfedcba98,
    'accessxi_file_stat did not return the exact four uint32 words')
assert(valid.stat_state.close_count == 1)
assert(valid.stat_state.set_last_error_count == 1,
    'accessxi_file_stat did not clear stale Win32 last-error before GetFileSize')
valid.stat_state.fail_time = true
local missing_identity, missing_reason = valid.environment.accessxi_file_stat('C:\\fixture\\file.bin')
assert(missing_identity == nil and tostring(missing_reason):lower():find('time', 1, true))
assert(valid.stat_state.close_count == 2, 'failed stat leaked its file handle')
valid.stat_state.fail_time = false
valid.stat_state.fail_open = true
local unopened_identity = valid.environment.accessxi_file_stat('C:\\fixture\\file.bin')
assert(unopened_identity == nil and valid.stat_state.close_count == 2,
    'invalid CreateFile handle was accepted or closed')
valid.stat_state.fail_open = false
valid.stat_state.fail_size = true
local unsized_identity, unsized_reason = valid.environment.accessxi_file_stat('C:\\fixture\\file.bin')
assert(unsized_identity == nil and tostring(unsized_reason):lower():find('size', 1, true))
assert(valid.stat_state.close_count == 3, 'failed size query leaked its file handle')
valid.stat_state.fail_size = false
valid.stat_state.last_error = 123
valid.stat_state.size_low = 0xffffffff
local max_low_identity = assert(valid.environment.accessxi_file_stat('C:\\fixture\\file.bin'))
assert(max_low_identity.size_low == 0xffffffff,
    'valid 0xffffffff low size word was confused with a failed size query')
valid.stat_state.size_low = 0x89abcdef
valid.stat_state.size_high = 'partial'
local partial_identity = valid.environment.accessxi_file_stat('C:\\fixture\\file.bin')
assert(partial_identity == nil, 'non-uint32 stat word was accepted')
valid.stat_state.size_high = 0x01234567
valid.stat_state.fail_close = true
local unclosed_identity, unclosed_reason = valid.environment.accessxi_file_stat('C:\\fixture\\file.bin')
assert(unclosed_identity == nil and tostring(unclosed_reason):lower():find('close', 1, true),
    'CloseHandle failure was accepted')
local wide_failure = new_fixture({ wide_failure = true })
assert(wide_failure.ok, tostring(wide_failure.reason))
local wide_identity = wide_failure.environment.accessxi_file_stat('C:\\fixture\\file.bin')
assert(wide_identity == nil and wide_failure.stat_state.close_count == 0,
    'UTF-8 conversion failure opened or accepted a file stat')

local exact_identity = assert(new_fixture().environment.accessxi_file_stat('C:\\fixture\\file.bin'))
local identity_keys = 0
for key in pairs(exact_identity) do
    identity_keys = identity_keys + 1
    assert(key == 'size_low' or key == 'size_high'
        or key == 'write_time_low' or key == 'write_time_high',
        'accessxi_file_stat exposed an unreviewed identity field')
end
assert(identity_keys == 4, 'accessxi_file_stat identity must have exactly four fields')

local dll_path = valid.path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll')
local mesh_path = valid.path('third_party/xiNavmeshes/Fixture.nav')
assert(valid.accessxi.nav_objective_native_before_dll_load(dll_path) == true)
assert(valid.accessxi.nav_objective_native_before_mesh_load(143, 'Fixture.nav', mesh_path) == true)
local native_snapshot = valid.accessxi.nav_objective_native_integrity_state()
assert(native_snapshot.trusted == true and native_snapshot.dll.path == dll_path
    and native_snapshot.mesh.path == mesh_path and native_snapshot.mesh.zone == 143)
assert(native_snapshot.dll.sha256 == digest(valid.files[dll_path].bytes)
    and native_snapshot.mesh.sha256 == digest(valid.files[mesh_path].bytes),
    'native observer did not bind exact rooted DLL and mesh digests')
for _, observed in ipairs({ native_snapshot.dll.identity, native_snapshot.mesh.identity }) do
    assert(type(observed.size_low) == 'number' and type(observed.size_high) == 'number'
        and type(observed.write_time_low) == 'number' and type(observed.write_time_high) == 'number')
end
native_snapshot.mesh.identity.write_time_low = native_snapshot.mesh.identity.write_time_low + 100
assert(valid.accessxi.nav_objective_native_integrity_state().trusted == true,
    'native integrity accessor leaked a mutable internal identity')
valid.files[mesh_path].identity.write_time_low = valid.files[mesh_path].identity.write_time_low + 1
local stale_snapshot = valid.accessxi.nav_objective_native_integrity_state()
assert(stale_snapshot.trusted == false,
    'same-mesh/native observer did not reject a changed four-word identity')

local alias = new_fixture()
assert(alias.ok, tostring(alias.reason))
assert(alias.accessxi.nav_objective_native_before_dll_load(
    alias.path('third_party/FFXI-NavMesh-Builder/../FFXI-NavMesh-Builder/FFXINAV.dll')) == false,
    'native observer accepted a noncanonical DLL alias')
assert(alias.accessxi.nav_objective_native_integrity_state().trusted == false)

local dll_drift = new_fixture()
assert(dll_drift.ok, tostring(dll_drift.reason))
local drift_dll_path = dll_drift.path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll')
local drift_mesh_path = dll_drift.path('third_party/xiNavmeshes/Fixture.nav')
assert(dll_drift.accessxi.nav_objective_native_before_dll_load(drift_dll_path) == true)
assert(dll_drift.accessxi.nav_objective_native_before_mesh_load(143, 'Fixture.nav', drift_mesh_path) == true)
dll_drift.files[drift_dll_path].identity.write_time_high =
    dll_drift.files[drift_dll_path].identity.write_time_high + 1
assert(dll_drift.accessxi.nav_objective_native_integrity_state().trusted == false,
    'native observer did not reject independent DLL identity drift')

local ordered = new_fixture()
assert(ordered.ok, tostring(ordered.reason))
local events = {}
local native_library = {
    CreateFFXINavClass = function() return {} end,
    LoadMesh = function()
        events[#events + 1] = 'LoadMesh'
        return true
    end,
}
ordered.environment.ffi.load = function(path)
    events[#events + 1] = 'ffi.load'
    assert(path == ordered.path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll'))
    return native_library
end
local before_dll = assert(ordered.accessxi.nav_objective_native_before_dll_load)
ordered.accessxi.nav_objective_native_before_dll_load = function(path)
    events[#events + 1] = 'observe-dll'
    return before_dll(path)
end
local before_mesh = assert(ordered.accessxi.nav_objective_native_before_mesh_load)
ordered.accessxi.nav_objective_native_before_mesh_load = function(zone, mesh_name, path)
    events[#events + 1] = 'observe-mesh'
    return before_mesh(zone, mesh_name, path)
end
local revalidate_mesh = assert(ordered.accessxi.nav_objective_native_revalidate_loaded_mesh)
ordered.accessxi.nav_objective_native_revalidate_loaded_mesh = function(zone)
    events[#events + 1] = 'revalidate-mesh'
    return revalidate_mesh(zone)
end
ordered.accessxi.nav_mesh_dll_path = ordered.path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll')
ordered.accessxi.nav_mesh_dir = ordered.path('third_party/xiNavmeshes')
ordered.accessxi.nav_mesh_loaded = false
ordered.accessxi.nav_mesh_zone = 0
ordered.accessxi.nav_mesh_handle = nil
local nav_start = assert(reader_source:find('local function nav_try_load_mesh(zone)', 1, true))
local nav_after = assert(reader_source:find('\nlocal function nav_compute_mesh_route', nav_start, true))
local nav_source = 'local ffxinav = nil\n'
    .. reader_source:sub(nav_start, nav_after - 1)
    .. '\nreturn nav_try_load_mesh'
local nav_environment = setmetatable({
    accessxi = ordered.accessxi,
    ffi = ordered.environment.ffi,
    nav_mesh_name_for_zone = function(zone)
        assert(zone == 143)
        return 'Fixture.nav'
    end,
    utf8_to_wide = function(path) return path end,
    log_line = function() end,
}, { __index = _G })
local nav_chunk = assert(loadstring(nav_source, '@reader-nav-try-load-mesh'))
setfenv(nav_chunk, nav_environment)
local nav_try_load_mesh = assert(nav_chunk())
assert(nav_try_load_mesh(143) == true)
assert(table.concat(events, ',') == 'observe-dll,ffi.load,observe-mesh,LoadMesh',
    'native observer was not installed immediately before ffi.load and LoadMesh: '
        .. table.concat(events, ','))
events = {}
assert(nav_try_load_mesh(143) == true)
assert(table.concat(events, ',') == 'revalidate-mesh',
    'same-mesh fast path did not revalidate the loaded mesh identity')
events = {}
ordered.accessxi.nav_mesh_loaded = false
assert(nav_try_load_mesh(143) == true)
assert(table.concat(events, ',') == 'observe-mesh,LoadMesh',
    'mesh observer did not run immediately before repeated LoadMesh')

local function ordinary_load_fixture(configure)
    local fixture = new_fixture()
    assert(fixture.ok, tostring(fixture.reason))
    local observed_events = {}
    local library = {
        CreateFFXINavClass = function() return {} end,
        LoadMesh = function()
            observed_events[#observed_events + 1] = 'LoadMesh'
            return true
        end,
    }
    fixture.environment.ffi.load = function()
        observed_events[#observed_events + 1] = 'ffi.load'
        return library
    end
    fixture.accessxi.nav_mesh_dll_path = fixture.path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll')
    fixture.accessxi.nav_mesh_dir = fixture.path('third_party/xiNavmeshes')
    fixture.accessxi.nav_mesh_loaded = false
    fixture.accessxi.nav_mesh_zone = 0
    fixture.accessxi.nav_mesh_handle = nil
    if configure ~= nil then configure(fixture, observed_events, library) end
    local environment = setmetatable({
        accessxi = fixture.accessxi,
        ffi = fixture.environment.ffi,
        nav_mesh_name_for_zone = function() return 'Fixture.nav' end,
        utf8_to_wide = function(path) return path end,
        log_line = function() end,
    }, { __index = _G })
    local chunk = assert(loadstring(nav_source, '@reader-nav-ordinary-isolation'))
    setfenv(chunk, environment)
    return fixture, assert(chunk()), observed_events
end

for _, observer_failure in ipairs({
    function(fixture)
        fixture.accessxi.nav_objective_native_before_dll_load = nil
    end,
    function(fixture, observed_events)
        fixture.accessxi.nav_objective_native_before_dll_load = function()
            observed_events[#observed_events + 1] = 'observe-dll-throw'
            error('synthetic DLL observer failure')
        end
    end,
    function(fixture)
        fixture.files[fixture.path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll')].bytes = 'changed dll bytes'
    end,
    function(fixture, observed_events)
        local real_dll = fixture.accessxi.nav_objective_native_before_dll_load
        fixture.accessxi.nav_objective_native_before_dll_load = function(path)
            assert(real_dll(path) == true)
            observed_events[#observed_events + 1] = 'observe-dll'
            return true
        end
        fixture.accessxi.nav_objective_native_before_mesh_load = function()
            observed_events[#observed_events + 1] = 'observe-mesh-throw'
            error('synthetic mesh observer failure')
        end
    end,
}) do
    local isolated, isolated_load, isolated_events = ordinary_load_fixture(observer_failure)
    local ok, loaded = pcall(isolated_load, 143)
    assert(ok and loaded == true,
        'objective observer failure disabled ordinary native navigation: ' .. tostring(loaded))
    assert(isolated_events[#isolated_events] == 'LoadMesh'
        and isolated.accessxi.nav_mesh_loaded == true,
        'ordinary ffi.load/LoadMesh did not complete after objective observer failure')
    assert(isolated.accessxi.nav_objective_native_integrity_state().trusted == false,
        'observer failure left objective native snapshot trusted')
end

for _, load_mesh_failure in ipairs({
    function(_, observed_events, library)
        library.LoadMesh = function()
            observed_events[#observed_events + 1] = 'LoadMesh-false'
            return false
        end
    end,
    function(_, observed_events, library)
        library.LoadMesh = function()
            observed_events[#observed_events + 1] = 'LoadMesh-throw'
            error('synthetic LoadMesh failure')
        end
    end,
}) do
    local isolated, isolated_load = ordinary_load_fixture(load_mesh_failure)
    local ok, loaded = pcall(isolated_load, 143)
    assert(ok and loaded == false,
        'LoadMesh failure did not preserve the ordinary false-return contract')
    assert(isolated.accessxi.nav_objective_native_integrity_state().trusted == false,
        'failed LoadMesh left a just-recorded objective mesh snapshot trusted')
end

for _, mutate_loaded_identity in ipairs({
    function(fixture)
        local path = fixture.path('third_party/FFXI-NavMesh-Builder/FFXINAV.dll')
        fixture.files[path].identity.write_time_low = fixture.files[path].identity.write_time_low + 1
    end,
    function(fixture)
        local path = fixture.path('third_party/xiNavmeshes/Fixture.nav')
        fixture.files[path].identity.size_low = fixture.files[path].identity.size_low + 1
    end,
}) do
    local isolated, isolated_load, isolated_events = ordinary_load_fixture()
    assert(isolated_load(143) == true)
    for index = #isolated_events, 1, -1 do isolated_events[index] = nil end
    mutate_loaded_identity(isolated)
    local ok, reused = pcall(isolated_load, 143)
    assert(ok and reused == true and #isolated_events == 0,
        'same-mesh identity drift broke or reloaded ordinary navigation')
    assert(isolated.accessxi.nav_objective_native_integrity_state().trusted == false,
        'same-mesh identity drift remained objective-trusted')
end

print('mission and quest reader integrity tests passed')
