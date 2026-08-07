local synthesis_module_path = assert(arg[1], 'Expected synthesis slots module path.')
local speech_format_path = assert(arg[2], 'Expected speech format module path.')

local synthesis_chunk, synthesis_error = loadfile(synthesis_module_path)
assert(synthesis_chunk ~= nil, synthesis_error)
local synthesis = synthesis_chunk()

assert(type(synthesis) == 'table', 'Expected synthesis slots module table.')
assert(type(synthesis.is_menu_name) == 'function', 'Expected native synthesis menu detector.')
assert(type(synthesis.slot_for_cursor) == 'function', 'Expected live synthesis cursor resolver.')
assert(type(synthesis.slot_speech) == 'function', 'Expected synthesis slot speech formatter.')
assert(type(synthesis.control_for_cursor) == 'function', 'Expected live synthesis control resolver.')
assert(type(synthesis.control_speech) == 'function', 'Expected native synthesis control speech formatter.')

assert(synthesis.is_menu_name('menu    tskill1'), 'Expected tskill1 to be the native ingredient-slot menu.')
assert(not synthesis.is_menu_name('menu    inventory'), 'Inventory picker must not be treated as the synthesis slot grid.')
assert(not synthesis.is_menu_name('menu    tskill2'), 'Unverified tskill2 must remain outside the slot reader.')

for cursor = 1, 8 do
    assert(synthesis.slot_for_cursor(cursor) == cursor,
        ('Expected native cursor %d to resolve to synthesis slot %d.'):format(cursor, cursor))
end
assert(synthesis.slot_for_cursor(0) == nil, 'Cursor zero must stay silent.')
assert(synthesis.slot_for_cursor(9) == nil, 'The first non-slot control must not be mislabeled as an ingredient slot.')
assert(synthesis.slot_for_cursor(10) == nil, 'The second non-slot control must not be mislabeled as an ingredient slot.')
assert(synthesis.slot_for_cursor(99) == nil, 'Unknown controls must stay silent.')

assert(synthesis.slot_speech(1, false, '') == 'Synthesis slot 1. Empty.',
    'Expected an empty native ingredient slot to be announced.')
assert(synthesis.slot_speech(8, true, '') == 'Synthesis slot 8.',
    'An occupied slot without a proven item identity must not invent one.')
assert(synthesis.slot_speech(3, true, 'Beehive Chip. Quantity 2.') ==
    'Synthesis slot 3. Beehive Chip. Quantity 2.',
    'Expected proven native item speech to follow the synthesis slot number.')
assert(synthesis.slot_speech(9, false, '') == nil,
    'Non-slot controls must not receive slot speech.')

assert(synthesis.control_for_cursor(9) == 'synthesize',
    'Native cursor 9 must resolve to the separate synthesize control.')
assert(synthesis.control_for_cursor(10) == 'cancel',
    'Native cursor 10 must resolve to the separate cancel control.')
assert(synthesis.control_for_cursor(8) == nil,
    'Ingredient slots must not be mislabeled as controls.')
assert(synthesis.control_speech(9, 'Synthesize this combination of items.') ==
    'Synthesize this combination of items.',
    'The synthesize control must speak its live native help text.')
assert(synthesis.control_speech(10, 'Cancel.') == 'Cancel.',
    'The cancel control must speak its live native help text.')
assert(synthesis.control_speech(9, '') == nil,
    'A control without verified native text must stay silent.')
assert(synthesis.control_speech(11, 'Unknown.') == nil,
    'Unknown synthesis controls must stay silent.')

accessxi = {}
local speech_chunk, speech_error = loadfile(speech_format_path)
assert(speech_chunk ~= nil, speech_error)
speech_chunk()

assert(type(accessxi.menu_selection_speech) == 'function',
    'Expected shared selection-only speech formatter.')
assert(type(accessxi.menu_selection_detail_speech) == 'function',
    'Expected shared selection detail speech formatter.')
assert(accessxi.menu_selection_speech('Permanent Key Items') == 'Permanent Key Items.',
    'Key Items category speech should contain only the highlighted category.')
assert(accessxi.menu_selection_speech('airship pass') == 'airship pass.',
    'Key Items row speech should contain only the highlighted item.')
assert(accessxi.menu_selection_detail_speech('airship pass', 'Allows passage aboard airships.') ==
    'airship pass. Allows passage aboard airships.',
    'Key-item detail speech should retain the visible label and description without a menu prefix.')
assert(accessxi.menu_selection_detail_speech('', '') == '',
    'Blank native selection detail must remain silent.')

print('Synthesis slots and Key Items speech behavior checks passed')
