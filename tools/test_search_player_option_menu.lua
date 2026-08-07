local module_path = assert(arg[1], 'Expected search-player option module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local resolver = chunk()
assert(type(resolver) == 'table', 'Expected search-player option resolver table.')
assert(type(resolver.resolve_native_help) == 'function', 'Expected resolve_native_help function.')

local row_1 = 0x18DAD3C0
local row_2 = 0x18DAD7D0
local row_4 = 0x18DAD0E8
local help_1 = 0x047C5EE4
local help_2 = 0x047C2ED0
local help_4 = 0x047D1F64

local dwords = {
    [row_1 + 0x40] = help_1,
    [row_2 + 0x40] = help_2,
    [row_4 + 0x40] = help_4,
}
local strings = {
    [help_1] = 'Chat in "tell" mode.',
    [help_2] = 'Send friend a PlayOnline message.',
    [help_4] = "Express desire to join another's party.",
}

local function is_pointer(value)
    value = tonumber(value) or 0
    return value >= 0x10000 and value < 0x7FFFFFFF
end

local function read_u32(address)
    return dwords[address] or 0
end

local function read_string(address)
    return strings[address] or ''
end

local cases = {
    { selected = 1, entry = row_1, expected = 'Chat in "tell" mode.' },
    { selected = 2, entry = row_2, expected = 'Send friend a PlayOnline message.' },
    { selected = 4, entry = row_4, expected = "Express desire to join another's party." },
}
for _, case in ipairs(cases) do
    local text, reason = resolver.resolve_native_help(
        'menu    scoption', case.selected, case.entry, is_pointer, read_u32, read_string)
    assert(text == case.expected, ('Expected native row %d help text.'):format(case.selected))
    assert(reason == 'native-entry-help', ('Expected native source for row %d.'):format(case.selected))
end

local unsupported, unsupported_reason = resolver.resolve_native_help(
    'menu    scresult', 1, row_1, is_pointer, read_u32, read_string)
assert(unsupported == nil and unsupported_reason == 'unsupported-menu',
    'Expected silence outside the search-player option popup.')

local no_selection, no_selection_reason = resolver.resolve_native_help(
    'menu    scoption', 0, row_1, is_pointer, read_u32, read_string)
assert(no_selection == nil and no_selection_reason == 'invalid-selection',
    'Expected silence without a positive native cursor.')

local bad_entry, bad_entry_reason = resolver.resolve_native_help(
    'menu    scoption', 1, 0, is_pointer, read_u32, read_string)
assert(bad_entry == nil and bad_entry_reason == 'invalid-entry',
    'Expected silence for an invalid selected-entry pointer.')

local missing_help, missing_help_reason = resolver.resolve_native_help(
    'menu    scoption', 3, 0x18DAD560, is_pointer, read_u32, read_string)
assert(missing_help == nil and missing_help_reason == 'invalid-help-pointer',
    'Expected silence when the selected entry has no verified help pointer.')

dwords[0x18DAD908 + 0x40] = 0x047C0000
strings[0x047C0000] = '   '
local empty_help, empty_help_reason = resolver.resolve_native_help(
    'menu    scoption', 5, 0x18DAD908, is_pointer, read_u32, read_string)
assert(empty_help == nil and empty_help_reason == 'empty-native-help',
    'Expected silence when the native string is empty after trimming.')

local installed_accessxi = {}
local state_logs = {}
local context = {
    is_pointer = is_pointer,
    read_u32 = read_u32,
    read_string = read_string,
    clean_help = function(text)
        return tostring(text or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    end,
    escape_log_text = function(text) return tostring(text or '') end,
    log_state = function(text) state_logs[#state_logs + 1] = text end,
    tick = function() return 4242 end,
}
local install_chunk, install_error = loadfile(module_path)
assert(install_chunk ~= nil, install_error)
local install_env = {
    accessxi = installed_accessxi,
    search_player_options_context = context,
}
setmetatable(install_env, { __index = _G })
setfenv(install_chunk, install_env)
install_chunk()

assert(type(installed_accessxi.search_player_option_menu_speech) == 'function',
    'Expected the module to install the live search-player option speech function.')
local live_speech = installed_accessxi.search_player_option_menu_speech(
    'menu    scoption', 4, row_4)
assert(live_speech == "Express desire to join another's party.",
    'Expected live speech to use the selected entry native help.')
assert(installed_accessxi.last_native_menu_name == 'menu    scoption',
    'Expected live speech to preserve native menu state.')
assert(installed_accessxi.last_native_menu_selected == 4,
    'Expected live speech state to preserve the exact native cursor.')
assert(installed_accessxi.last_native_menu_label == live_speech,
    'Expected the spoken native help to become the current native label.')
assert(installed_accessxi.last_native_menu_tick == 4242,
    'Expected live speech state to use the injected monotonic tick.')
assert(installed_accessxi.current_speech_key ==
    "search-player-option:menu    scoption:4:0x18DAD0E8:Express desire to join another's party.",
    'Expected speech identity to include menu, cursor, entry, and native text.')
assert(#state_logs == 1 and state_logs[1]:find('source="entry+0x40"', 1, true) ~= nil,
    'Expected the live evidence log to record the proven native pointer source.')

local prior_key = installed_accessxi.current_speech_key
local quiet_speech = installed_accessxi.search_player_option_menu_speech(
    'menu    scoption', 3, 0x18DAD560)
assert(quiet_speech == nil, 'Expected live speech to remain silent for an unverified row.')
assert(installed_accessxi.current_speech_key == prior_key,
    'Expected an unverified row not to replace the last valid speech identity.')
assert(#state_logs == 2 and state_logs[2]:find('reason="invalid-help-pointer"', 1, true) ~= nil,
    'Expected a quiet evidence log when the native help pointer is invalid.')

print('Search player option native-help checks passed')
