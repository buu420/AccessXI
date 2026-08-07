local module_path = assert(arg[1], 'Expected gear detail hotkey module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local gear = chunk()
assert(type(gear) == 'table', 'Expected gear detail hotkey module table.')
assert(type(gear.new_state) == 'function', 'Expected new_state function.')
assert(type(gear.set_detail) == 'function', 'Expected set_detail function.')
assert(type(gear.clear) == 'function', 'Expected clear function.')
assert(type(gear.needs_refresh) == 'function', 'Expected needs_refresh function.')
assert(type(gear.poll) == 'function', 'Expected poll function.')

local function snapshot(key, overrides)
    local value = {
        foreground = true,
        chat_open = false,
        modifier_down = false,
        current_menu = 'menu    equip',
        context_key = 'equipment-native:menu    equip:0:4660:100:Test Sword',
        now = 1100,
        keys = { J = false, K = false, L = false },
    }
    if key ~= nil then
        value.keys[key] = true
    end
    for name, item in pairs(overrides or {}) do
        value[name] = item
    end
    return value
end

local function detail(overrides)
    local value = {
        is_gear = true,
        menu = 'menu    equip',
        context_key = 'equipment-native:menu    equip:0:4660:100:Test Sword',
        id = 100,
        index = 4660,
        name = 'Test Sword',
        slot_name = 'Main',
        count = 2,
        detail_parts = {
            'Rare',
            'Sword',
            'All Races',
            'Level 99',
            'WAR, PLD',
        },
        description = 'A test weapon.',
        updated_tick = 1000,
    }
    for name, item in pairs(overrides or {}) do
        value[name] = item
    end
    return value
end

local rejected = gear.new_state()
assert(gear.set_detail(rejected, detail({ is_gear = false })) == false,
    'A non-gear item must never activate the gear reader.')
assert(gear.set_detail(rejected, detail({ id = 0 })) == false,
    'Gear without a verified item id must never activate the gear reader.')
assert(gear.set_detail(rejected, detail({ context_key = '' })) == false,
    'Gear without a current row identity must never activate the gear reader.')

local state = gear.new_state()
assert(gear.set_detail(state, detail()) == true,
    'Verified highlighted gear should activate the line reader.')
assert(#state.lines == 8,
    ('Expected all eight dynamic detail lines, got %d.'):format(#state.lines))
assert(state.lines[1] == 'Main, Test Sword', 'The first line must orient with slot and item name.')
assert(state.lines[2] == 'Quantity 2', 'Quantity must remain its own readable line.')
assert(state.lines[8] == 'A test weapon.', 'The full description must be the final line.')

assert(gear.needs_refresh(state, snapshot('K')) == true,
    'A new gear hotkey press must request a live row refresh.')
local text, handled = gear.poll(state, snapshot('K'))
assert(handled == true and text == 'Main, Test Sword',
    'The first K press must repeat the first detail line.')

text, handled = gear.poll(state, snapshot('K', { now = 1150 }))
assert(handled == true and text == '',
    'A held gear key must remain claimed while respecting the repeat delay.')
text, handled = gear.poll(state, snapshot('K', { now = 1320 }))
assert(handled == true and text == 'Main, Test Sword',
    'K must repeat the current detail line after the repeat delay.')
gear.poll(state, snapshot(nil, { now = 1400 }))

text, handled = gear.poll(state, snapshot('L', { now = 1500 }))
assert(handled == true and text == 'Quantity 2', 'L must read the next detail line.')
gear.poll(state, snapshot(nil, { now = 1510 }))
text, handled = gear.poll(state, snapshot('J', { now = 1600 }))
assert(handled == true and text == 'Main, Test Sword', 'J must read the previous detail line.')
gear.poll(state, snapshot(nil, { now = 1610 }))
text, handled = gear.poll(state, snapshot('J', { now = 1700 }))
assert(handled == true and text == 'First line. Main, Test Sword',
    'J at the beginning must announce the first-line boundary without wrapping.')

state.index = #state.lines
gear.poll(state, snapshot(nil, { now = 1800 }))
text, handled = gear.poll(state, snapshot('L', { now = 1900 }))
assert(handled == true and text == 'Last line. A test weapon.',
    'L at the end must announce the last-line boundary without wrapping.')

state.index = 4
assert(gear.set_detail(state, detail({ description = 'Updated description.', updated_tick = 2000 })) == true,
    'Refreshing the same highlighted item should remain active.')
assert(state.index == 4,
    'A live detail refresh for the same item must preserve the current line.')
assert(state.lines[#state.lines] == 'Updated description.',
    'A live detail refresh must replace changed native details.')
assert(gear.set_detail(state, detail({ id = 101, index = 4661, name = 'Other Sword', updated_tick = 2100 })) == true,
    'A different highlighted piece should replace the buffer.')
assert(state.index == 0, 'Changing highlighted gear must reset line navigation to the top.')

local many_parts = {}
for i = 1, 75 do
    many_parts[i] = ('Native detail %d'):format(i)
end
assert(gear.set_detail(state, detail({ id = 102, index = 4662, name = 'Long Gear', count = 1,
    slot_name = '', detail_parts = many_parts, description = '', updated_tick = 2200 })) == true,
    'A long native gear panel should remain readable.')
assert(#state.lines == 76,
    ('Gear lines must not use a fixed row count; expected 76, got %d.'):format(#state.lines))
assert(state.lines[76] == 'Native detail 75', 'The final dynamic detail line must be preserved.')

local mismatch = snapshot('K', {
    current_menu = 'menu    inventor',
    context_key = 'inventory-native:menu    inventor:0:2:102:Long Gear',
    now = 2250,
})
text, handled = gear.poll(state, mismatch)
assert(handled == false and text == nil,
    'A stale detail handoff must not claim keys in another menu or row.')

assert(gear.set_detail(state, detail({ updated_tick = 1000 })) == true)
text, handled = gear.poll(state, snapshot('K', { now = 5000 }))
assert(handled == false and text == nil,
    'Expired gear context must fail silent instead of reading stale information.')

assert(gear.set_detail(state, detail({ updated_tick = 6000 })) == true)
text, handled = gear.poll(state, snapshot('K', { now = 6050, chat_open = true }))
assert(handled == false and text == nil, 'Chat input must receive the letter normally.')
gear.poll(state, snapshot(nil, { now = 6060 }))
text, handled = gear.poll(state, snapshot('K', { now = 6070, modifier_down = true }))
assert(handled == false and text == nil, 'Modified keys must remain available to FFXI.')
gear.poll(state, snapshot(nil, { now = 6080 }))
text, handled = gear.poll(state, snapshot('K', { now = 6090, foreground = false }))
assert(handled == false and text == nil, 'Background FFXI must not read or claim gear keys.')

gear.clear(state)
assert(state.active == false and #state.lines == 0 and state.index == 0,
    'Clearing the reader must remove all stale gear state.')

print('Gear detail hotkey checks passed')
