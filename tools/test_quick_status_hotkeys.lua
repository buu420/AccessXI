local module_path = assert(arg[1], 'Expected quick-status hotkey module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local quick = chunk()
assert(type(quick) == 'table', 'Expected quick-status module table.')
assert(type(quick.new_state) == 'function', 'Expected new_state function.')
assert(type(quick.poll) == 'function', 'Expected poll function.')
assert(type(quick.classify_status) == 'function', 'Expected classify_status function.')
assert(type(quick.is_hotkey_vk) == 'function', 'Expected is_hotkey_vk function.')

local function snapshot(action, overrides)
    local value = {
        foreground = true,
        chat_open = false,
        modifier_down = false,
        keys = { D = false, B = false, H = false, M = false, X = false },
        vitals_available = true,
        hp_current = 731,
        hp_max = 1000,
        mp_current = 244,
        mp_max = 500,
        exp_current = 1173,
        exp_needed = 2800,
        statuses_available = true,
        statuses = {},
    }
    if action ~= nil then
        value.keys[action] = true
    end
    for key, item in pairs(overrides or {}) do
        value[key] = item
    end
    return value
end

local state = quick.new_state()

local hp, hp_action = quick.poll(state, snapshot('H'))
assert(hp == 'HP 731 of 1000.' and hp_action == 'hp',
    'Bare H must speak current and maximum HP.')
local held_hp = quick.poll(state, snapshot('H'))
assert(held_hp == nil, 'A held quick-status hotkey must speak only once.')
quick.poll(state, snapshot(nil))

local mp, mp_action = quick.poll(state, snapshot('M'))
assert(mp == 'MP 244 of 500.' and mp_action == 'mp',
    'Bare M must speak current and maximum MP.')
quick.poll(state, snapshot(nil))

local exp, exp_action = quick.poll(state, snapshot('X'))
assert(exp == 'Experience 1173. TNL 1627.' and exp_action == 'experience',
    'Bare X must speak current experience and calculated TNL.')
quick.poll(state, snapshot(nil))
local capped_tnl = quick.poll(state, snapshot('X', { exp_current = 3000, exp_needed = 2800 }))
assert(capped_tnl == 'Experience 3000. TNL 0.', 'TNL must never be negative.')
quick.poll(state, snapshot(nil))

local debuff_snapshot = snapshot('D', {
    statuses = {
        { id = 3, name = 'Poison', can_cancel = false },
        { id = 33, name = 'Haste', can_cancel = true },
        { id = 536, name = 'Gambit', can_cancel = false },
        { id = 3, name = 'Poison', can_cancel = false },
        { id = 636, name = 'DEBUG: Please report.', can_cancel = false },
    },
})
local debuffs, debuffs_action, debuffs_meta = quick.poll(state, debuff_snapshot)
assert(debuffs == 'Debuffs: Poison, Gambit.' and debuffs_action == 'debuffs',
    'Bare D must preserve live order, omit buffs and unknowns, and suppress duplicates.')
assert(type(debuffs_meta) == 'table' and #debuffs_meta.unknown_ids == 1
    and debuffs_meta.unknown_ids[1] == 636,
    'Unknown status IDs must be reported to the caller instead of guessed.')
quick.poll(state, snapshot(nil))

local buffs, buffs_action = quick.poll(state, snapshot('B', {
    statuses = {
        { id = 33, name = 'Haste', can_cancel = true },
        { id = 3, name = 'Poison', can_cancel = false },
        { id = 195, name = 'Paeon', can_cancel = false },
        { id = 33, name = 'Haste', can_cancel = true },
    },
}))
assert(buffs == 'Buffs: Haste, Paeon.' and buffs_action == 'buffs',
    'Bare B must include native cancellable buffs and reviewed non-cancellable buffs.')
quick.poll(state, snapshot(nil))

local no_debuffs = quick.poll(state, snapshot('D'))
assert(no_debuffs == 'No debuffs.', 'An available empty status list must say no debuffs.')
quick.poll(state, snapshot(nil))
local no_buffs = quick.poll(state, snapshot('B'))
assert(no_buffs == 'No buffs.', 'An available empty status list must say no buffs.')
quick.poll(state, snapshot(nil))

local unavailable_debuffs = quick.poll(state, snapshot('D', { statuses_available = false }))
assert(unavailable_debuffs == 'Debuff information unavailable.',
    'Missing status memory must not be mistaken for an empty debuff list.')
quick.poll(state, snapshot(nil))
local unavailable_hp = quick.poll(state, snapshot('H', { vitals_available = false }))
assert(unavailable_hp == 'HP information unavailable.',
    'Missing live HP memory must produce an explicit unavailable message.')
quick.poll(state, snapshot(nil))
local independently_available_hp = quick.poll(state, snapshot('H', {
    vitals_available = false,
    hp_available = true,
    exp_current = nil,
    exp_needed = nil,
}))
assert(independently_available_hp == 'HP 731 of 1000.',
    'HP speech must not depend on unrelated MP or experience memory.')
quick.poll(state, snapshot(nil))

local foreground_state = quick.new_state()
local background = quick.poll(foreground_state, snapshot('H', { foreground = false }))
assert(background == nil, 'Background FFXI must not announce quick-status hotkeys.')
local still_held_after_focus = quick.poll(foreground_state, snapshot('H'))
assert(still_held_after_focus == nil,
    'A key pressed while backgrounded must remain latched until release.')
quick.poll(foreground_state, snapshot(nil))
local after_focus_release = quick.poll(foreground_state, snapshot('H'))
assert(after_focus_release == 'HP 731 of 1000.',
    'A foreground hotkey must work after the background press is released.')

local chat_state = quick.new_state()
local in_chat = quick.poll(chat_state, snapshot('M', { chat_open = true }))
assert(in_chat == nil, 'Open chat input must suppress quick-status speech.')
local held_after_chat = quick.poll(chat_state, snapshot('M'))
assert(held_after_chat == nil, 'A chat-suppressed press must remain latched until release.')
quick.poll(chat_state, snapshot(nil))
local after_chat_release = quick.poll(chat_state, snapshot('M'))
assert(after_chat_release == 'MP 244 of 500.',
    'The hotkey must work after chat closes and the suppressed press is released.')

local modifier_state = quick.new_state()
local modified = quick.poll(modifier_state, snapshot('H', { modifier_down = true }))
assert(modified == nil, 'Modified H must remain available to FFXI and other shortcuts.')
local held_after_modifier = quick.poll(modifier_state, snapshot('H'))
assert(held_after_modifier == nil,
    'A modifier-suppressed press must remain latched until the bare key is released.')
quick.poll(modifier_state, snapshot(nil))
local after_modifier_release = quick.poll(modifier_state, snapshot('H'))
assert(after_modifier_release == 'HP 731 of 1000.',
    'Bare H must work after a modified press is released.')

assert(quick.classify_status(3, false) == 'debuff', 'Poison must be a reviewed debuff.')
assert(quick.classify_status(33, true) == 'buff', 'Native cancellable Haste must be a buff.')
assert(quick.classify_status(195, false) == 'buff', 'Non-cancellable Paeon must be reviewed as a buff.')
assert(quick.classify_status(636, false) == nil, 'Placeholder effects must remain unclassified.')

assert(quick.is_hotkey_vk(0x44) == true, 'Virtual key D must be recognized.')
assert(quick.is_hotkey_vk(0x42) == true, 'Virtual key B must be recognized.')
assert(quick.is_hotkey_vk(0x48) == true, 'Virtual key H must be recognized.')
assert(quick.is_hotkey_vk(0x4D) == true, 'Virtual key M must be recognized.')
assert(quick.is_hotkey_vk(0x58) == true, 'Virtual key X must be recognized.')
assert(quick.is_hotkey_vk(0x49) == false, 'Navigation toggle I must remain outside quick-status handling.')

print('Quick status hotkey checks passed')
