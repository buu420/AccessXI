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

local bytes = {}
local base = 0x01001000
local node = 0x01002000
local legacy = 0x01003000
local dwords = {}
local decoded_override = nil
local fallback_reads = 0
local fallback_collects = 0
local accessxi = {
    is_probe_pointer = function(ptr)
        ptr = tonumber(ptr)
        return ptr == base or ptr == node or ptr == legacy
    end,
    probe_printable_ascii = function(value)
        value = tonumber(value) or 0
        return value >= 0x20 and value <= 0x7E
    end,
    decode_ffxi_menu_text_fragment = function(value)
        if (decoded_override ~= nil) then
            return decoded_override
        end
        return tostring(value or '')
    end,
    survival_guide_text = function(value)
        return tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('%s+', ' '):trim()
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

local function read_u8(address)
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
    visible_source .. '\n' .. phrase_source .. '\n' .. candidate_ptr_source .. '\n' .. candidate_node_source,
    '@native-query-visible-length'))
setfenv(chunk, setmetatable({
    accessxi = accessxi,
    T = T,
    read_u8 = read_u8,
    read_u32 = read_u32,
    read_probe_string = read_probe_string,
}, { __index = _G }))
chunk()

local function set_pair(ptr, offset, value)
    bytes[ptr + offset] = value:byte(1)
    bytes[ptr + offset + 1] = 0
end

local function write_text(ptr, value)
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

local function decode(visible, visible_count, stale)
    bytes = {}
    write_text(base, visible .. (stale or ''))
    set_native_metadata(base, 1, visible_count)
    return accessxi.native_query_phrase_from_ptr(base, '')
end

local function decode_truncated(visible, visible_count, available_pairs)
    bytes = {}
    for index = 1, math.min(#visible, available_pairs) do
        set_pair(base, (index - 1) * 2, visible:sub(index, index))
    end
    set_native_metadata(base, 1, visible_count)
    return accessxi.native_query_visible_text_from_ptr(base)
end

local function decode_with_short_fragment(visible, visible_count, decoded)
    bytes = {}
    write_text(base, visible)
    set_native_metadata(base, 1, visible_count)
    decoded_override = decoded
    local result = accessxi.native_query_visible_text_from_ptr(base)
    decoded_override = nil
    return result
end

assert(decode('NEVER MIND' .. string.char(0x0E), 11, 'FAVORITES') == 'Never mind.')
assert(decode('NOWHERE' .. string.char(0x0E), 8, 'SLES') == 'Nowhere.')
assert(decode('ON SECOND THOUGHT' .. string.char(0x0C) .. ' NONE' .. string.char(0x0E), 24) == 'On second thought, none.')
assert(decode('150-PT' .. string.char(0x0E) .. ' ITEMS' .. string.char(0x0E), 14) == '150-pt. Items.')
assert(decode('HE' .. string.char(0x07) .. 'S' .. string.char(0x0E), 5) == "He's.")
assert(decode('I' .. string.char(0x07) .. 'd' .. string.char(0x0E), 4) == "I'd.")
assert(decode('HE' .. string.char(0x07), 3, 'S') == 'He')
for _, bad in ipairs({ 0, 64, 255 }) do
    assert(decode('VALID', bad) == '')
end
assert(decode_truncated('VALID', 5, 4) == '')
assert(decode_with_short_fragment('VALID', 5, 'VAL') == '')

local function candidate_fixture(kind, visible_count, text, decoded)
    bytes = {}
    dwords = {}
    fallback_reads = 0
    fallback_collects = 0
    decoded_override = decoded
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

candidate_fixture(27, 5, 'VALIDSTALE', 'VAL')
assert(accessxi.native_query_candidate_label_from_ptr(base, '') == '')
assert(fallback_reads == 0)
assert(fallback_collects == 0)

candidate_fixture(3, 5, 'VALIDSTALE', 'VAL')
assert(accessxi.native_query_candidate_label_from_ptr(base, '') == '')
assert(fallback_reads == 0)
assert(fallback_collects == 0)
dwords[node + 0x10] = base
assert(accessxi.native_query_candidate_label_from_node(node, '', 1, 1) == '')
assert(fallback_reads == 0)
assert(fallback_collects == 0)
decoded_override = nil

bytes = {}
dwords = {}
fallback_reads = 0
fallback_collects = 0
write_text(legacy, 'LEGACY LABEL')
bytes[legacy + 0x104] = 0x42
bytes[legacy + 0x105] = 0x42
bytes[legacy + 0x106] = 0
bytes[legacy + 0x107] = 0
assert(accessxi.native_query_candidate_label_from_ptr(legacy, '') == 'LEGACY LABEL')
assert(fallback_reads == 1)

bytes = {}
dwords = {}
fallback_reads = 0
fallback_collects = 0
write_text(legacy, 'LEGACY UNFRAMED')
bytes[legacy + 0x104] = 27
assert(accessxi.native_query_candidate_label_from_ptr(legacy, '') == 'LEGACY UNFRAMED')
assert(fallback_reads == 1)

print('native query visible-length decoder behavior ok')
