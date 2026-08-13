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

local bytes = {}
local base = 0x01001000
local decoded_override = nil
local accessxi = {
    is_probe_pointer = function(ptr)
        return tonumber(ptr) == base
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
}

local function read_u8(address)
    return bytes[tonumber(address)]
end

local chunk = assert(loadstring(visible_source .. '\n' .. phrase_source, '@native-query-visible-length'))
setfenv(chunk, setmetatable({
    accessxi = accessxi,
    T = T,
    read_u8 = read_u8,
}, { __index = _G }))
chunk()

local function set_pair(offset, value)
    bytes[base + offset] = value:byte(1)
    bytes[base + offset + 1] = 0
end

local function decode(visible, visible_count, stale)
    bytes = {}
    for index = 1, #visible do
        set_pair((index - 1) * 2, visible:sub(index, index))
    end
    for index = 1, #(stale or '') do
        set_pair((#visible + index - 1) * 2, stale:sub(index, index))
    end
    bytes[base + 0x106] = visible_count
    return accessxi.native_query_phrase_from_ptr(base, '')
end

local function decode_truncated(visible, visible_count, available_pairs)
    bytes = {}
    for index = 1, math.min(#visible, available_pairs) do
        set_pair((index - 1) * 2, visible:sub(index, index))
    end
    bytes[base + 0x106] = visible_count
    return accessxi.native_query_visible_text_from_ptr(base)
end

local function decode_with_short_fragment(visible, visible_count, decoded)
    bytes = {}
    for index = 1, #visible do
        set_pair((index - 1) * 2, visible:sub(index, index))
    end
    bytes[base + 0x106] = visible_count
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

print('native query visible-length decoder behavior ok')
