local module_path = assert(arg[1], 'Expected detail-summary navigation module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local navigation = chunk()
assert(type(navigation) == 'table', 'Expected detail-summary navigation table.')
assert(type(navigation.new_state) == 'function', 'Expected new_state function.')
assert(type(navigation.begin_surface) == 'function', 'Expected begin_surface function.')
assert(type(navigation.current_line) == 'function', 'Expected current_line function.')
assert(type(navigation.reset) == 'function', 'Expected reset function.')

local function lines_of(count)
    local lines = {}
    for index = 1, count do
        lines[index] = ('Line %d'):format(index)
    end
    return lines
end

local lines = lines_of(12)
local state = navigation.new_state()

local opened, opened_index, opened_reason = navigation.begin_surface(state, 'quest:101', 7)
assert(opened == nil and opened_index == nil and opened_reason ~= '',
    'Opening a summary must seed its native position without line speech.')

local unchanged, unchanged_index, unchanged_reason = navigation.current_line(state, 'quest:101', 7, lines)
assert(unchanged == nil and unchanged_index == nil and unchanged_reason ~= '',
    'An unchanged native position must remain silent.')

local second, second_index = navigation.current_line(state, 'quest:101', 8, lines)
assert(second == 'Line 2' and second_index == 2,
    'Moving one native position must return only the second line.')

local fourth, fourth_index = navigation.current_line(state, 'quest:101', 10, lines)
assert(fourth == 'Line 4' and fourth_index == 4,
    'Skipped native positions must resolve the current fourth line, not replay intermediate lines.')

local third, third_index = navigation.current_line(state, 'quest:101', 9, lines)
assert(third == 'Line 3' and third_index == 3,
    'Reverse movement must return the newly current third line.')

local changed_surface, changed_surface_index, changed_surface_reason =
    navigation.current_line(state, 'mission:202', 20, lines)
assert(changed_surface == nil and changed_surface_index == nil and changed_surface_reason ~= '',
    'A changed surface must reseed silently even when observed without begin_surface.')

local changed_surface_second, changed_surface_second_index =
    navigation.current_line(state, 'mission:202', 21, lines)
assert(changed_surface_second == 'Line 2' and changed_surface_second_index == 2,
    'A changed surface must use its own opening native position.')

local one_line_state = navigation.new_state()
navigation.begin_surface(one_line_state, 'roe:303', 2)
local one_line_unchanged = navigation.current_line(one_line_state, 'roe:303', 2, { 'Only line' })
assert(one_line_unchanged == nil, 'A one-line summary must not repeat at an unchanged position.')
local one_line_outside, _, one_line_reason = navigation.current_line(one_line_state, 'roe:303', 3, { 'Only line' })
assert(one_line_outside == nil and one_line_reason ~= '',
    'A native position outside an arbitrary one-line summary must remain silent.')

local invalid_state = navigation.new_state()
local invalid_open = navigation.begin_surface(invalid_state, '', 7)
assert(invalid_open == nil, 'An empty surface key must remain silent.')
local invalid_position = navigation.current_line(invalid_state, 'quest:invalid', 0, lines)
assert(invalid_position == nil, 'A nonpositive native position must remain silent.')
local nonnumeric_position = navigation.current_line(invalid_state, 'quest:invalid', 'eight', lines)
assert(nonnumeric_position == nil, 'A nonnumeric native position must remain silent.')

local blank_state = navigation.new_state()
navigation.begin_surface(blank_state, 'quest:blank', 1)
local blank_line, _, blank_reason = navigation.current_line(blank_state, 'quest:blank', 2,
    { 'Line 1', '   ', 'Line 3' })
assert(blank_line == nil and blank_reason ~= '', 'A blank mapped line must remain silent.')
local out_of_range, _, out_of_range_reason =
    navigation.current_line(blank_state, 'quest:blank', 99, { 'Line 1', 'Line 2' })
assert(out_of_range == nil and out_of_range_reason ~= '', 'An out-of-range mapped line must remain silent.')

navigation.reset(state)
local after_reset, after_reset_index, after_reset_reason =
    navigation.current_line(state, 'quest:101', 8, lines)
assert(after_reset == nil and after_reset_index == nil and after_reset_reason ~= '',
    'The first observation after reset must reseed silently.')
local after_reset_second, after_reset_second_index =
    navigation.current_line(state, 'quest:101', 9, lines)
assert(after_reset_second == 'Line 2' and after_reset_second_index == 2,
    'Movement after reset must use the newly seeded opening position.')

print('Scrollable detail summary navigation checks passed')
