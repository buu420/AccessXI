local module_path = assert(arg[1], 'Expected records-of-eminence detail navigation module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local navigation = chunk()
assert(type(navigation) == 'table', 'Expected records-of-eminence detail navigation table.')
assert(type(navigation.signal_matches_row) == 'function', 'Expected signal_matches_row function.')
assert(type(navigation.resolve_dat_line) == 'function', 'Expected resolve_dat_line function.')

-- A matching signal must be accepted regardless of how many rows are actually visible; the
-- module must never hard-code a minimum row count such as 20 to decide a signal is valid.
local base_signal = { record_id = 1, selected = 1, visible_count = 16, slot_id = 0xE001 }
local base_row = { record_id = 1, selected = 1 }
assert(navigation.signal_matches_row(base_signal, base_row) == true,
    'A matching signal with only 16 visible rows must be accepted; no hard-coded minimum row count is allowed.')

local zero_visible_signal = { record_id = 1, selected = 1, visible_count = 0, slot_id = 0xE001 }
assert(navigation.signal_matches_row(zero_visible_signal, base_row) ~= true,
    'A signal reporting zero visible rows must be rejected.')

local low_slot_signal = { record_id = 1, selected = 1, visible_count = 16, slot_id = 0xE001 - 1 }
assert(navigation.signal_matches_row(low_slot_signal, base_row) ~= true,
    'A signal with a slot id below 0xE001 must be rejected.')

local mismatched_record_signal = { record_id = 2, selected = 1, visible_count = 16, slot_id = 0xE001 }
assert(navigation.signal_matches_row(mismatched_record_signal, base_row) ~= true,
    'A signal whose record_id does not match the row must be rejected.')

local mismatched_selected_signal = { record_id = 1, selected = 2, visible_count = 16, slot_id = 0xE001 }
assert(navigation.signal_matches_row(mismatched_selected_signal, base_row) ~= true,
    'A signal whose selected flag does not match the row must be rejected.')

-- Physical Damage Kills fixture: seven parts spanning title, four description lines,
-- a number-required line, and a rewards line.
local pdk_parts = {
    'Physical Damage Kills',
    '[Limited-time Challenge]',
    'Defeat line 1',
    'Defeat line 2',
    'areas',
    'Number Required. 0/20',
    'Rewards. 300 Spa.',
}
local pdk_kinds = {
    'title',
    'description',
    'description',
    'description',
    'description',
    'number-required',
    'rewards',
}

local pdk_text_2, pdk_index_2, pdk_reason_2, pdk_handled_2 =
    navigation.resolve_dat_line(2, pdk_parts, pdk_kinds, base_signal, base_row)
assert(pdk_handled_2 == true and pdk_text_2 == pdk_parts[1] and pdk_index_2 == 1,
    'Native detail position 2 must resolve to the title part (index 1).')

local pdk_text_3, pdk_index_3, pdk_reason_3, pdk_handled_3 =
    navigation.resolve_dat_line(3, pdk_parts, pdk_kinds, base_signal, base_row)
assert(pdk_handled_3 == true and pdk_text_3 == pdk_parts[2] and pdk_index_3 == 2,
    'Native detail position 3 must resolve to the first description part (index 2).')

local pdk_text_4, pdk_index_4, pdk_reason_4, pdk_handled_4 =
    navigation.resolve_dat_line(4, pdk_parts, pdk_kinds, base_signal, base_row)
assert(pdk_handled_4 == true and pdk_text_4 == pdk_parts[6] and pdk_index_4 == 6,
    'Native detail position 4 must resolve to the number-required part (index 6), not the second description line.')

local pdk_text_5, pdk_index_5, pdk_reason_5, pdk_handled_5 =
    navigation.resolve_dat_line(5, pdk_parts, pdk_kinds, base_signal, base_row)
assert(pdk_handled_5 == true and pdk_text_5 == pdk_parts[7] and pdk_index_5 == 7,
    'Native detail position 5 must resolve to the rewards part (index 7).')

-- Native detail position 6 is a known DAT surface but out of the resolvable range; this is
-- the regression for the line-8 bug where callers must be told to skip an expensive native
-- fallback rather than being handed a bogus eighth line.
local pdk_text_6, pdk_index_6, pdk_reason_6, pdk_handled_6 =
    navigation.resolve_dat_line(6, pdk_parts, pdk_kinds, base_signal, base_row)
assert(pdk_text_6 == nil, 'Native detail position 6 must not resolve to any text (line-8 bug regression).')
assert(pdk_index_6 == nil, 'Native detail position 6 must not resolve to any part index (line-8 bug regression).')
assert(type(pdk_reason_6) == 'string' and pdk_reason_6 ~= '',
    'Native detail position 6 must report a nonempty reason explaining why it is out of range.')
assert(pdk_handled_6 == true,
    'Native detail position 6 must be reported as handled so callers skip the expensive native fallback.')

-- A mismatched signal must never resolve a line, regardless of the requested native position.
local mismatched_text, mismatched_index, mismatched_reason, mismatched_handled =
    navigation.resolve_dat_line(2, pdk_parts, pdk_kinds, mismatched_record_signal, base_row)
assert(mismatched_handled == false,
    'A mismatched signal must return handled=false so the caller does not treat the surface as ours.')
assert(mismatched_text == nil and mismatched_index == nil,
    'A mismatched signal must not resolve any text or part index.')

-- First Step Forward fixture: a valid 16-row surface with only five parts, confirming the
-- resolver does not depend on any particular row count.
local fsf_parts = {
    'First Step Forward',
    'Speak to one of the following Records of Eminence',
    'guides',
    'Number Required. 0/1',
    'Rewards. 100 Spa.',
}
local fsf_kinds = {
    'title',
    'description',
    'description',
    'number-required',
    'rewards',
}

local fsf_text_2, fsf_index_2, fsf_reason_2, fsf_handled_2 =
    navigation.resolve_dat_line(2, fsf_parts, fsf_kinds, base_signal, base_row)
assert(fsf_handled_2 == true and fsf_text_2 == 'First Step Forward' and fsf_index_2 == 1,
    'Native detail position 2 for the First Step Forward fixture must resolve to the title part (index 1).')

print('Records of Eminence detail navigation checks passed')
