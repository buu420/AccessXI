local module_path = assert(arg[1], 'Expected navigation hotkey module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local nav = chunk()
assert(type(nav) == 'table', 'Expected navigation hotkey module table.')
assert(type(nav.new_state) == 'function', 'Expected new_state function.')
assert(type(nav.poll) == 'function', 'Expected poll function.')
assert(type(nav.should_claim_vk) == 'function', 'Expected should_claim_vk function.')
assert(type(nav.is_hotkey_vk) == 'function', 'Expected is_hotkey_vk function.')

local function snapshot(key, overrides)
    local value = {
        foreground = true,
        chat_open = false,
        modifier_down = false,
        route_active = false,
        route_pending = false,
        now = 1000,
        keys = { I = false, U = false, O = false, J = false, K = false, L = false },
    }
    if key ~= nil then
        value.keys[key] = true
    end
    for name, item in pairs(overrides or {}) do
        value[name] = item
    end
    return value
end

local state = nav.new_state()
local start_route = nav.poll(state, snapshot('I'))
assert(start_route == 'start_route',
    'Bare I must start the selected route when navigation is inactive.')
assert(nav.should_claim_vk(state, 0x49, snapshot(nil)) == true,
    'Bare I must be claimed as the route start and stop key.')
assert(nav.poll(state, snapshot('I', { now = 1500 })) == nil,
    'Holding I must not repeatedly start or stop navigation.')
nav.poll(state, snapshot(nil, { now = 1600 }))

local stop_route = nav.poll(state, snapshot('I', { route_active = true, now = 1700 }))
assert(stop_route == 'stop_route',
    'Bare I must stop an active route.')
nav.poll(state, snapshot(nil, { now = 1800 }))

local stop_pending_route = nav.poll(state, snapshot('I', { route_pending = true, now = 1900 }))
assert(stop_pending_route == 'stop_route',
    'Bare I must stop pending cross-zone navigation even between active legs.')
nav.poll(state, snapshot(nil, { now = 1950 }))

local expected_actions = {
    U = 'previous_category',
    O = 'next_category',
    J = 'previous_item',
    K = 'repeat_item',
    L = 'next_item',
}
for _, key in ipairs({ 'U', 'O', 'J', 'K', 'L' }) do
    local action = nav.poll(state, snapshot(key, { now = 2000 }))
    assert(action == expected_actions[key],
        ('Bare %s must dispatch %s.'):format(key, expected_actions[key]))
    assert(nav.should_claim_vk(state, string.byte(key), snapshot(nil)) == true,
        ('Navigation must claim bare %s from FFXI in the safe global context.'):format(key))
    nav.poll(state, snapshot(nil, { now = 2100 }))
end

local first_next = nav.poll(state, snapshot('L', { now = 3000 }))
assert(first_next == 'next_item', 'The first held L frame must move to the next item.')
local early_repeat = nav.poll(state, snapshot('L', { now = 3100 }))
assert(early_repeat == nil, 'A held navigation key must respect the repeat delay.')
local due_repeat = nav.poll(state, snapshot('L', { now = 3220 }))
assert(due_repeat == 'next_item', 'A held navigation key must repeat after the delay.')
nav.poll(state, snapshot(nil, { now = 3300 }))

local modified_state = nav.new_state()
local modified_i = nav.poll(modified_state, snapshot('I', { modifier_down = true }))
assert(modified_i == nil,
    'Modified I must remain available to FFXI and other shortcuts.')
assert(nav.should_claim_vk(modified_state, 0x49, snapshot(nil, { modifier_down = true })) == false,
    'Modified I must not be swallowed.')
local held_after_modifier = nav.poll(modified_state, snapshot('I', { now = 1200 }))
assert(held_after_modifier == nil,
    'A modifier-rejected I press must remain latched until the key is released.')
nav.poll(modified_state, snapshot(nil, { now = 1300 }))
assert(nav.poll(modified_state, snapshot('I', { now = 1400 })) == 'start_route',
    'Bare I must work after the modified press is released.')

local chat_state = nav.new_state()
assert(nav.poll(chat_state, snapshot('I', { chat_open = true })) == nil,
    'Chat input must suppress navigation hotkeys.')
assert(nav.should_claim_vk(chat_state, 0x49, snapshot(nil, { chat_open = true })) == false,
    'Chat input must receive I normally.')

local background_state = nav.new_state()
assert(nav.poll(background_state, snapshot('I', { foreground = false })) == nil,
    'Background FFXI must not start or stop navigation.')
assert(nav.should_claim_vk(background_state, 0x49, snapshot(nil, { foreground = false })) == false,
    'Background FFXI keys must not be swallowed.')

assert(nav.is_hotkey_vk(0x49) == true, 'Virtual key I must be recognized.')
assert(nav.is_hotkey_vk(0x55) == true, 'Virtual key U must be recognized.')
assert(nav.is_hotkey_vk(0x4F) == true, 'Virtual key O must be recognized.')
assert(nav.is_hotkey_vk(0x4A) == true, 'Virtual key J must be recognized.')
assert(nav.is_hotkey_vk(0x4B) == true, 'Virtual key K must be recognized.')
assert(nav.is_hotkey_vk(0x4C) == true, 'Virtual key L must be recognized.')
assert(nav.is_hotkey_vk(0x48) == false, 'Status key H must not be treated as a navigation key.')

print('Navigation hotkey checks passed')
