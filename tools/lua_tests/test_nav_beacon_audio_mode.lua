local reader_path = assert(arg[1], 'accessxi_reader.lua path is required')
local compatibility_dir = assert(arg[2], 'compatibility beacon directory is required')
local hrtf_dir = assert(arg[3], 'HRTF beacon directory is required')
local preference_path = assert(arg[4], 'temporary preference path is required')

local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local function block(first_marker, last_marker)
    local first = assert(source:find(first_marker, 1, true), 'missing ' .. first_marker)
    local last = assert(source:find(last_marker, first + #first_marker, true), 'missing ' .. last_marker)
    return source:sub(first, last - 1)
end

local selected = table.concat({
    block('function accessxi.nav_beacon_normalize_audio_mode', 'function accessxi.nav_collision_clamp_sample'),
    block('function accessxi.nav_beacon_ensure_files', 'function accessxi.nav_beacon_play'),
}, '\n')

function string.fmt(self, ...) return string.format(self, ...) end
function utf8_to_wide(value) return value end
local logs = {}
function log_line(value) logs[#logs + 1] = tostring(value) end

kernel32 = { CreateDirectoryW = function() return true end }
local fake_winmm = { PlaySoundW = function() return 1 end }
ffi = { load = function(name)
    assert(name == 'winmm', 'unexpected library request: ' .. tostring(name))
    return fake_winmm
end }

accessxi = {
    nav_beacon_parent_dir = compatibility_dir,
    nav_beacon_compat_dir = compatibility_dir,
    nav_beacon_hrtf_dir = hrtf_dir,
    nav_beacon_audio_mode_path = preference_path,
    nav_beacon_audio_mode = 'compatibility',
    nav_beacon_audio_mode_loaded = true,
    nav_beacon_files_ready = false,
    nav_beacon_winmm = nil,
    nav_beacon_last_tick = 0,
    nav_beacon_last_key = '',
}

local chunk, reason = loadstring(selected, '@nav-beacon-audio-mode')
assert(chunk, reason)
chunk()

assert(accessxi.nav_beacon_normalize_audio_mode('Headphones') == 'hrtf')
assert(accessxi.nav_beacon_normalize_audio_mode('binaural') == 'hrtf')
assert(accessxi.nav_beacon_normalize_audio_mode('speakers') == 'compatibility')
assert(accessxi.nav_beacon_normalize_audio_mode('stereo') == 'compatibility')
assert(accessxi.nav_beacon_normalize_audio_mode('unknown') == nil)

accessxi.nav_beacon_audio_mode = 'hrtf'
assert(accessxi.nav_beacon_ensure_files() == true)
assert(accessxi.nav_beacon_bank == 'hrtf' and accessxi.nav_beacon_dir == hrtf_dir,
    'a complete validated bank was not selected in headphone HRTF mode')

accessxi.nav_beacon_audio_mode = 'compatibility'
accessxi.nav_beacon_files_ready = false
assert(accessxi.nav_beacon_ensure_files() == true)
assert(accessxi.nav_beacon_bank == 'compatibility'
        and accessxi.nav_beacon_dir == compatibility_dir,
    'speaker mode did not select compatibility audio')

accessxi.nav_beacon_audio_mode = 'hrtf'
accessxi.nav_beacon_hrtf_dir = compatibility_dir
accessxi.nav_beacon_files_ready = false
assert(accessxi.nav_beacon_ensure_files() == true)
assert(accessxi.nav_beacon_bank == 'compatibility',
    'a malformed or manifest-free HRTF bank did not fail closed to compatibility audio')

accessxi.nav_beacon_hrtf_dir = hrtf_dir
local mode, save_reason = accessxi.nav_beacon_save_audio_mode('headphones')
assert(mode == 'hrtf' and save_reason == nil, 'headphone preference was not saved')
local saved = assert(io.open(preference_path, 'r'))
assert(saved:read('*l') == 'hrtf', 'saved headphone preference has the wrong value')
saved:close()
accessxi.nav_beacon_audio_mode_loaded = false
accessxi.nav_beacon_audio_mode = 'compatibility'
assert(accessxi.nav_beacon_load_audio_mode() == 'hrtf',
    'saved headphone preference did not survive a reload')

assert(source:find("args[3]:any('hrtf', 'headphone', 'headphones', 'binaural')", 1, true),
    'beacon command has no accessible headphone HRTF selection')
assert(source:find("args[3]:any('speaker', 'speakers', 'stereo', 'compatibility')", 1, true),
    'beacon command has no accessible speaker compatibility selection')

os.remove(preference_path)
print('navigation beacon audio-mode checks passed')
