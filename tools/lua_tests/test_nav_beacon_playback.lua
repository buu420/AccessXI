local reader_path = assert(arg[1], 'accessxi_reader.lua path is required')
local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local function function_block(marker)
    local first = source:find(marker, 1, true)
    if (first == nil) then
        return ''
    end

    local after = first + #marker
    local next_public = source:find('\nfunction accessxi.', after, true)
    local next_local = source:find('\nlocal function ', after, true)
    local last = next_public
    if (last == nil or (next_local ~= nil and next_local < last)) then
        last = next_local
    end
    assert(last ~= nil, 'could not isolate ' .. marker)
    return source:sub(first, last - 1)
end

-- The helper is intentionally optional while this test is RED. Once the reader
-- delegates playback to nav_beacon_play, load the real helper into this harness
-- so its retry and success bookkeeping are exercised rather than mocked.
local playback_source = function_block('function accessxi.nav_beacon_play')
local poll_source = function_block('function accessxi.poll_nav_beacon()')
assert(poll_source ~= '', 'missing navigation beacon polling function')

local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
function string.fmt(self, ...) return string.format(self, ...) end

local now = 1000
local player = T({ zone = 245, x = 0, z = 0, y = 0, yaw = 0 })
local destination = T({ zone = 245, x = 100, z = 0, y = 0, name = 'Upper Jeuno zone line' })
local route_target = T({ zone = 245, x = 8, z = 0, y = 0, source = 'dat-collision-segment-steering' })

local play_results = {}
local play_calls = 0
local ensure_calls = 0
local ffi_load_calls = 0
local claim_calls = 0
local logs = {}
local direction_acquired = {}
local primary_winmm = nil
local reloaded_winmm = nil

local function next_play_result()
    play_calls = play_calls + 1
    local result = play_results[play_calls]
    if (result == nil) then
        return false
    end
    return result
end

local function new_winmm()
    return {
        PlaySoundW = function ()
            return next_play_result()
        end,
    }
end

accessxi = {
    nav_beacon_enabled = true,
    nav_active = true,
    nav_destination = destination,
    nav_route_points = T({
        T({ zone = 245, x = 0, z = 0, y = 0 }),
        T({ zone = 245, x = 100, z = 0, y = 0 }),
    }),
    nav_route_point_index = 2,
    nav_route_start_point = T({ zone = 245, x = 0, z = 0, y = 0 }),
    nav_beacon_route_identity = nil,
    nav_beacon_route_acquired = true,
    nav_beacon_motion_x = nil,
    nav_beacon_motion_z = nil,
    nav_beacon_last_tick = 0,
    nav_beacon_last_key = '',
}

function tick() return now end
function utf8_to_wide(path) return path end
function nav_route_suppressed() return false end
function nav_cached_player_position() return player end
function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end
function log_line(text) logs[#logs + 1] = tostring(text) end

function accessxi.beacon_audio_available() return true end
function accessxi.nav_door_waiting() return false end
function accessxi.nav_beacon_route_target() return route_target end
function accessxi.nav_route_precise_override_active() return true end
function accessxi.nav_apply_dynamic_obstacle(_, target) return target end
function accessxi.nav_apply_wall_avoidance(_, target) return target end
function accessxi.nav_arrival_radius() return 3 end
function accessxi.nav_beacon_direction_delta()
    direction_acquired[#direction_acquired + 1] = accessxi.nav_beacon_route_acquired
    return 0
end
function accessxi.nav_beacon_file_for_delta()
    return 'beacon\\front_06.wav', 'front', 6, 0
end
function accessxi.nav_beacon_ensure_files()
    ensure_calls = ensure_calls + 1
    -- The first call is the ordinary readiness check. A second call represents
    -- the forced reload path after a failed PlaySoundW result.
    if (ensure_calls >= 2) then
        accessxi.nav_beacon_winmm = reloaded_winmm
    end
    return accessxi.nav_beacon_winmm ~= nil
end
function accessxi.beacon_audio_claim(source, duration_ms, claim_now)
    claim_calls = claim_calls + 1
    accessxi.beacon_audio_busy_source = source
    accessxi.beacon_audio_busy_until = claim_now + duration_ms
end

ffi = {
    load = function(name)
        assert(name == 'winmm', 'unexpected library reload: ' .. tostring(name))
        ffi_load_calls = ffi_load_calls + 1
        accessxi.nav_beacon_winmm = reloaded_winmm
        return reloaded_winmm
    end,
}

local chunk, reason = loadstring(playback_source .. '\n' .. poll_source, '@nav-beacon-playback')
assert(chunk, reason)
chunk()

local function reset(results, start_now)
    play_results = results
    play_calls = 0
    ensure_calls = 0
    ffi_load_calls = 0
    claim_calls = 0
    logs = {}
    direction_acquired = {}
    now = start_now or 1000
    primary_winmm = new_winmm()
    reloaded_winmm = new_winmm()
    accessxi.nav_beacon_winmm = primary_winmm
    accessxi.nav_beacon_files_ready = true
    accessxi.nav_beacon_last_tick = 0
    accessxi.nav_beacon_last_attempt_tick = 0
    accessxi.nav_beacon_last_key = ''
    accessxi.nav_beacon_route_identity = accessxi.nav_route_start_point
    accessxi.nav_beacon_route_acquired = true
    accessxi.beacon_audio_busy_source = ''
    accessxi.beacon_audio_busy_until = 0
end

-- Win32 BOOL arrives through LuaJIT FFI as an integer-like value. In Lua, zero
-- is truthy, so use 0/1 here to catch wrappers that only test Lua truthiness.
reset({ 0, 0 })
accessxi.poll_nav_beacon()
assert(accessxi.nav_beacon_last_tick == 0,
    'PlaySoundW false was recorded as a successful navigation beacon pulse')
assert(claim_calls == 0,
    'PlaySoundW false incorrectly claimed the shared beacon audio channel')
assert(play_calls == 2,
    'a failed PlaySoundW call did not get exactly one immediate retry')
assert(ensure_calls >= 2 or ffi_load_calls >= 1,
    'a failed PlaySoundW call did not invoke the winmm reload path')
now = 1100
accessxi.poll_nav_beacon()
assert(play_calls == 2,
    'failed beacon playback retried every frame instead of respecting the 520ms pulse interval')

reset({ 0, 1 })
accessxi.poll_nav_beacon()
assert(play_calls == 2,
    'navigation beacon playback did not retry once after winmm returned false')
assert(ensure_calls >= 2 or ffi_load_calls >= 1,
    'navigation beacon recovery did not reload winmm before retrying')
assert(accessxi.nav_beacon_last_tick == now,
    'a successful retry did not record the navigation beacon pulse')
assert(claim_calls == 1,
    'a successful retry did not claim the audio channel exactly once')

reset({ 1, 1 }, 1000)
accessxi.poll_nav_beacon()
assert(play_calls == 1, 'the first navigation beacon pulse did not play')
local stable_key = accessxi.nav_beacon_last_key

now = 1519
accessxi.poll_nav_beacon()
assert(play_calls == 1, 'navigation beacon replayed before its 520ms interval')

now = 1520
accessxi.poll_nav_beacon()
assert(play_calls == 2,
    'an unchanged centered beacon direction was not replayed after 520ms')
assert(accessxi.nav_beacon_last_key == stable_key and stable_key == 'front:06',
    'the stable-direction replay unexpectedly depended on a direction-key change')
assert(claim_calls == 2,
    'two successful stable-direction pulses did not make two audio claims')

reset({ 1, 1, 1 }, 2000)
accessxi.poll_nav_beacon()
local original_points = accessxi.nav_route_points
assert(accessxi.nav_beacon_route_identity == original_points,
    'the original waypoint list was not established as the beacon route identity')
accessxi.nav_beacon_route_acquired = true
local replacement_points = T({
    T({ zone = 245, x = 0, z = 0, y = 0 }),
    T({ zone = 245, x = 0, z = 100, y = 0 }),
})
accessxi.nav_route_points = replacement_points
now = 2520
accessxi.poll_nav_beacon()
assert(direction_acquired[2] == false,
    'a replacement waypoint list reused the previous route alignment instead of reacquiring its new heading')
assert(accessxi.nav_beacon_route_identity == replacement_points,
    'beacon route identity did not follow the active waypoint list')
accessxi.nav_beacon_route_acquired = true
now = 3040
accessxi.poll_nav_beacon()
assert(direction_acquired[3] == true,
    'an unchanged waypoint list restarted facing acquisition on every beacon pulse')

print('navigation beacon playback checks passed')
