local reader_path = assert(arg[1], 'expected accessxi_reader.lua path')
local handle = assert(io.open(reader_path, 'rb'))
local source = handle:read('*a')
handle:close()

local function extract(first_marker, next_marker)
    local first = assert(source:find(first_marker, 1, true), 'missing source marker: ' .. first_marker)
    local last = assert(source:find(next_marker, first + #first_marker, true), 'missing end marker: ' .. next_marker)
    return source:sub(first, last - 1)
end

local function required_extract(first_marker, next_marker)
    local first = source:find(first_marker, 1, true)
    assert(first ~= nil, 'missing bounded native query decoder: ' .. first_marker)
    return extract(first_marker, next_marker)
end

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:concat(separator) return table.concat(self, separator or '') end

local function T(value)
    return setmetatable(value or {}, { __index = list_methods })
end

function string:trim()
    return self:gsub('^%s+', ''):gsub('%s+$', '')
end

function string:eq(other, insensitive)
    other = tostring(other or '')
    if (insensitive) then
        return self:lower() == other:lower()
    end
    return self == other
end

function string:contains(needle, insensitive)
    needle = tostring(needle or '')
    if (insensitive) then
        return self:lower():find(needle:lower(), 1, true) ~= nil
    end
    return self:find(needle, 1, true) ~= nil
end

local visible_source = required_extract(
    'function accessxi.native_query_visible_text_from_ptr(ptr)',
    'function accessxi.native_query_phrase_from_ptr(ptr, context)')
local phrase_source = extract(
    'function accessxi.native_query_phrase_from_ptr(ptr, context)',
    'function accessxi.home_point_query_normalize_phrase(phrase)')
local candidate_ptr_source = extract(
    'function accessxi.native_query_candidate_label_from_ptr(ptr, context)',
    'function accessxi.native_query_candidate_label_from_node(node, context, expected_count, selected)')
local candidate_node_source = extract(
    'function accessxi.native_query_candidate_label_from_node(node, context, expected_count, selected)',
    'function accessxi.native_query_collect_items_with_next(first, expected_count, next_off, context)')
local cleaner_source = extract(
    'function accessxi.survival_guide_text(text)',
    "accessxi.home_point_data = accessxi.load_menu_module_table('home_points', T{ points = T{} })")

local bytes = {}
local base = 0x01001000
local node = 0x01002000
local legacy = 0x01003000
local dwords = {}
local fallback_reads = 0
local fallback_collects = 0
local forbidden_reads = {}
local accessxi = {
    is_probe_pointer = function(ptr)
        ptr = tonumber(ptr)
        return ptr == base or ptr == node or ptr == legacy
    end,
    probe_printable_ascii = function(value)
        value = tonumber(value) or 0
        return value >= 0x20 and value <= 0x7E
    end,
    native_query_label_looks_real = function(value)
        return tostring(value or '') ~= ''
    end,
    survival_guide_native_label_is_polluted = function()
        return false
    end,
    native_query_normalize_phrase = function(value)
        return tostring(value or '')
    end,
    native_query_candidate_label_from_text = function(value)
        return tostring(value or ''):trim()
    end,
    native_query_label_for_position = function(value)
        return tostring(value or '')
    end,
    native_query_candidate_score = function()
        return 1
    end,
    collect_probe_ffxi_utf16_entries = function()
        fallback_collects = fallback_collects + 1
        return T{}
    end,
}

local function bxor(left, right)
    local result = 0
    local place = 1
    while left > 0 or right > 0 do
        local left_bit = left % 2
        local right_bit = right % 2
        if (left_bit ~= right_bit) then
            result = result + place
        end
        left = math.floor(left / 2)
        right = math.floor(right / 2)
        place = place * 2
    end
    return result
end

local function read_u8(address)
    assert(forbidden_reads[tonumber(address)] ~= true, string.format('read beyond declared native text at 0x%X', address))
    return bytes[tonumber(address)]
end

local function read_u32(address)
    return dwords[tonumber(address)]
end

local function read_probe_string(address)
    fallback_reads = fallback_reads + 1
    local chars = T{}
    for index = 0, 63 do
        local lo = read_u8(address + (index * 2))
        local hi = read_u8(address + (index * 2) + 1)
        if (lo == nil or hi == nil or lo == 0 or hi ~= 0) then
            break
        end
        chars:append(string.char(lo))
    end
    return chars:concat('')
end

local chunk = assert(loadstring(
    cleaner_source .. '\n' .. visible_source .. '\n' .. phrase_source .. '\n'
        .. candidate_ptr_source .. '\n' .. candidate_node_source,
    '@native-query-visible-length'))
setfenv(chunk, setmetatable({
    accessxi = accessxi,
    T = T,
    read_u8 = read_u8,
    read_u32 = read_u32,
    read_probe_string = read_probe_string,
    bit = { bxor = bxor },
}, { __index = _G }))
chunk()

local function set_pair(ptr, offset, value)
    bytes[ptr + offset] = type(value) == 'number' and value or value:byte(1)
    bytes[ptr + offset + 1] = 0
end

local function write_text(ptr, value)
    for offset = 0, 3 do
        bytes[ptr + offset] = 0
    end
    for index = 1, #value do
        local glyph = value:sub(index, index)
        set_pair(ptr, 0x04 + ((index - 1) * 2), glyph == ' ' and 0 or glyph)
    end
end

local function write_legacy_text(ptr, value)
    for index = 1, #value do
        set_pair(ptr, (index - 1) * 2, value:sub(index, index))
    end
end

local function set_native_metadata(ptr, kind, count)
    bytes[ptr + 0x104] = kind
    bytes[ptr + 0x105] = 0
    bytes[ptr + 0x106] = count
    bytes[ptr + 0x107] = 1
end

local function captured_words(parts)
    local words = {}
    for _, part in ipairs(parts) do
        if (type(part) == 'string') then
            for index = 1, #part do
                local glyph = part:byte(index)
                words[#words + 1] = glyph == 0x20 and 0 or glyph
            end
        else
            words[#words + 1] = assert(tonumber(part), 'captured word must be numeric')
        end
    end
    return words
end

local function decode_captured(parts, stale_parts, style)
    bytes = {}
    forbidden_reads = {}
    local words = captured_words(parts)
    local stale_words = captured_words(stale_parts or {})
    for offset = 0, 3 do
        bytes[base + offset] = 0
    end
    for index, word in ipairs(words) do
        bytes[base + 0x04 + ((index - 1) * 2)] = word % 0x100
        bytes[base + 0x05 + ((index - 1) * 2)] = math.floor(word / 0x100)
    end
    for index, word in ipairs(stale_words) do
        local pair = #words + index - 1
        bytes[base + 0x04 + (pair * 2)] = word % 0x100
        bytes[base + 0x05 + (pair * 2)] = math.floor(word / 0x100)
    end
    set_native_metadata(base, style or 1, #words)
    if (#stale_words > 0) then
        forbidden_reads[base + 0x04 + (#words * 2)] = true
        forbidden_reads[base + 0x05 + (#words * 2)] = true
    end
    return accessxi.native_query_visible_text_from_ptr(base)
end

local function decode(visible, visible_count, stale, style)
    bytes = {}
    forbidden_reads = {}
    write_text(base, visible .. (stale or ''))
    set_native_metadata(base, style or 1, visible_count)
    if (visible_count >= 1 and visible_count <= 63 and stale ~= nil and stale ~= '') then
        forbidden_reads[base + 0x04 + (visible_count * 2)] = true
        forbidden_reads[base + 0x05 + (visible_count * 2)] = true
    end
    return accessxi.native_query_phrase_from_ptr(base, '')
end

local function decode_visible(visible, visible_count, style, stale)
    bytes = {}
    forbidden_reads = {}
    write_text(base, visible .. (stale or ''))
    set_native_metadata(base, style or 1, visible_count)
    if (visible_count >= 1 and visible_count <= 63 and stale ~= nil and stale ~= '') then
        forbidden_reads[base + 0x04 + (visible_count * 2)] = true
        forbidden_reads[base + 0x05 + (visible_count * 2)] = true
    end
    return accessxi.native_query_visible_text_from_ptr(base)
end

local function decode_truncated(visible, visible_count, available_pairs)
    bytes = {}
    forbidden_reads = {}
    for offset = 0, 3 do
        bytes[base + offset] = 0
    end
    for index = 1, math.min(#visible, available_pairs) do
        set_pair(base, 0x04 + ((index - 1) * 2), visible:sub(index, index))
    end
    set_native_metadata(base, 1, visible_count)
    return accessxi.native_query_visible_text_from_ptr(base)
end

local function decode_unsupported(visible, visible_count, bad_index, bad_lo, bad_hi)
    bytes = {}
    forbidden_reads = {}
    write_text(base, visible)
    set_native_metadata(base, 1, visible_count)
    bytes[base + 0x04 + (bad_index * 2)] = bad_lo
    bytes[base + 0x05 + (bad_index * 2)] = bad_hi
    return accessxi.native_query_visible_text_from_ptr(base)
end

local copper_claimed = {
    0x0008, 0x009C, 0x0009, ' ',
    0xFEFE, 0x0023, 'OPPER ',
    0x0021, 0x000E, 0x002D, 0x000E, 0x0021, 0x000E, 0x002E, 0x000E,
    ' VOUCHER', 0xFEFF, ' X', 0x0017, 0x001A, ' ', 0x0011, 0x0010, 0x000E,
}
assert(decode_captured({ 0x0029, ' FORGOT WHY I', 0x0007, 'M HERE', 0x000E }) == "I FORGOT WHY I'M HERE.")
assert(decode_captured({ 'HOW DO ', 0x0029, ' PARTICIPATE', 0x001F }) == 'HOW DO I PARTICIPATE?')
assert(decode_captured({ 0x0029 }) == 'I')
assert(#captured_words(copper_claimed) == 37)
assert(decode_captured(copper_claimed, { 'STALE' }) == '(claimed) COPPER A.M.A.N. VOUCHER X7: 10.')
assert(accessxi.native_query_phrase_from_ptr(base, '') == 'Claimed. Copper A.M.A.N. voucher X7: 10.')

local themis_claimed = {
    0x0008, 0x009C, 0x0009, ' ',
    0xFEFE, 0x0034, 'HEMIS ORB', 0xFEFF, 0x001A, ' ', 0x0014, 0x0010, 0x000E,
}
assert(#captured_words(themis_claimed) == 21)
assert(decode_captured(themis_claimed, { 'STALE' }) == '(claimed) THEMIS ORB: 40.')
assert(accessxi.native_query_phrase_from_ptr(base, '') == 'Claimed. Themis orb: 40.')

assert(decode('NEVER MIND' .. string.char(0x0E), 11, 'FAVORITES') == 'Never mind.')
assert(decode('NOWHERE' .. string.char(0x0E), 8, 'SLES') == 'Nowhere.')
assert(decode_visible('TRAVEL TO ANOTHER HOME POINT' .. string.char(0x0E), 29, 1) == 'TRAVEL TO ANOTHER HOME POINT.')
assert(decode('ON SECOND THOUGHT' .. string.char(0x0C) .. ' NONE' .. string.char(0x0E), 24) == 'On second thought, none.')
assert(decode('150' .. string.char(0x0D) .. 'PT' .. string.char(0x0E) .. ' ITEMS' .. string.char(0x0E), 14, nil, 3) == '150-pt. Items.')
assert(decode('HE' .. string.char(0x07) .. 'S' .. string.char(0x0E), 5) == "He's.")
assert(decode('I' .. string.char(0x07) .. 'd' .. string.char(0x0E), 4) == "I'd.")
assert(decode_captured({ 'BRING IT ON', 0x0001 }, { 'STALE' }) == 'BRING IT ON!')
assert(decode('HE' .. string.char(0x07), 3, 'S') == "He'")
assert(decode('HE' .. string.char(0x0F), 3, 'STALE') == 'He/')
assert(decode('HE ', 3, 'STALE') == 'He')
assert(decode_visible(' ', 1, 1) == '')
for _, bad in ipairs({ 0, 64, 255 }) do
    assert(decode('VALID', bad) == '')
end
assert(decode_truncated('VALID', 5, 4) == '')
assert(decode_unsupported('VALID', 5, 2, 0x7F, 0) == '')
assert(decode_unsupported('VALID', 5, 2, string.byte('L'), 1) == '')

assert(decode_captured({ 'HOME POINT ', 0x0003, 0x0013, 0x000E }) == 'HOME POINT #3.')
assert(decode_captured({ 'I', 0x0007, 'M' }) == "I'M")
assert(decode_captured({ 'I', 0x0007, 'D' }) == "I'D")
assert(decode_captured({ 'I', 0x0007, 'VE' }) == "I'VE")
assert(decode_captured({ 'TU', 0x0007, 'LIA' }) == "TU'LIA")
assert(decode_captured({
    0xFEFE, 'SCROLL OF INSTANT WARP', 0xFEFF, 0x000E, ' ', 0x0008, 0x0011, 0x0010, 0x0009,
}) == 'SCROLL OF INSTANT WARP. (10)')
assert(decode_captured({ 0x000B }) == '+')
assert(decode_captured({ 'ONE', 0x000C, ' TWO', 0x000D, 'THREE', 0x000E }) == 'ONE, TWO-THREE.')
assert(decode_captured({ 'CHECK', 0x000F, 'EXCHANGE POINTS', 0x000E }) == 'CHECK/EXCHANGE POINTS.')
assert(decode_captured({ 0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0016, 0x0017, 0x0018, 0x0019 }) == '0123456789')
assert(decode_captured({ 'X', 0x0017, 0x001A, ' ', 0x0011, 0x0010, 0x000E }) == 'X7: 10.')
assert(decode_captured({ 'WOULD YOU CAST SIGNET ON ME', 0x001F }) == 'WOULD YOU CAST SIGNET ON ME?')
assert(decode_captured({
    0xFEFD, 'MAP OF THE JEUNO AREA', 0xFEFF,
    ' ', 0x0008, 0x0015, 0x0010, 0x0010, ' GIL', 0x0009, 0x000E,
}) == 'MAP OF THE JEUNO AREA (500 GIL).')
assert(decode_captured({ 0xFEFE, 0xFEFD, 0xFEFF }) == '')
assert(decode_captured({ 0xFEFC }) == '')

local function candidate_fixture(kind, visible_count, text)
    bytes = {}
    dwords = {}
    forbidden_reads = {}
    fallback_reads = 0
    fallback_collects = 0
    write_text(base, text)
    set_native_metadata(base, kind, visible_count)
end

candidate_fixture(1, 11, 'NEVER MIND' .. string.char(0x0E) .. 'FAVORITES')
assert(accessxi.native_query_candidate_label_from_ptr(base, '') == 'Never mind.')
assert(fallback_reads == 0)
assert(fallback_collects == 0)
dwords[node + 0x10] = base
assert(accessxi.native_query_candidate_label_from_node(node, '', 1, 1) == 'Never mind.')
assert(fallback_reads == 0)
assert(fallback_collects == 0)

candidate_fixture(1, nil, 'VALIDSTALE')
assert(accessxi.native_query_candidate_label_from_ptr(base, '') == '')
assert(fallback_reads == 0)
assert(fallback_collects == 0)

for _, malformed_count in ipairs({ 0, 64 }) do
    candidate_fixture(1, malformed_count, 'VALIDSTALE')
    assert(accessxi.native_query_candidate_label_from_ptr(base, '') == '')
    assert(fallback_reads == 0)
    assert(fallback_collects == 0)
end

for _, framed in ipairs({ { style = 27, count = 0 }, { style = 14, count = 64 } }) do
    candidate_fixture(framed.style, framed.count, 'VALIDSTALE')
    assert(accessxi.native_query_candidate_label_from_ptr(base, '') == '')
    assert(fallback_reads == 0)
    assert(fallback_collects == 0)
end

candidate_fixture(27, 5, 'VALID')
bytes[base + 0x08] = 0x7F
assert(accessxi.native_query_candidate_label_from_ptr(base, '') == '')
assert(fallback_reads == 0)
assert(fallback_collects == 0)

candidate_fixture(3, 5, 'VALID')
bytes[base + 0x08] = 0x7F
assert(accessxi.native_query_candidate_label_from_ptr(base, '') == '')
assert(fallback_reads == 0)
assert(fallback_collects == 0)
dwords[node + 0x10] = base
assert(accessxi.native_query_candidate_label_from_node(node, '', 1, 1) == '')
assert(fallback_reads == 0)
assert(fallback_collects == 0)
bytes = {}
dwords = {}
forbidden_reads = {}
fallback_reads = 0
fallback_collects = 0
write_legacy_text(legacy, 'LEGACY LABEL')
bytes[legacy + 0x104] = 0x42
bytes[legacy + 0x105] = 0x42
bytes[legacy + 0x106] = 0
bytes[legacy + 0x107] = 0
assert(accessxi.native_query_candidate_label_from_ptr(legacy, '') == 'LEGACY LABEL')
assert(fallback_reads == 1)

bytes = {}
dwords = {}
forbidden_reads = {}
fallback_reads = 0
fallback_collects = 0
write_legacy_text(legacy, 'LEGACY UNFRAMED')
bytes[legacy + 0x104] = 27
assert(accessxi.native_query_candidate_label_from_ptr(legacy, '') == 'LEGACY UNFRAMED')
assert(fallback_reads == 1)

print('native query visible-length decoder behavior ok')
