-- Native loot layout: FFXiMain September 2026, render 1013EE10,
-- rebuild 1013EBE0. Display rows are sorted independently of pool slots.
local addon = assert(arg[1], 'pass the addon root')
local function read_file(path)
    local f = assert(io.open(path, 'rb')); local s = f:read('*a'); f:close(); return s
end
local source = read_file(addon .. '/accessxi_reader.lua')
local function between(first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a + #first, true), last)
    return source:sub(a, b - 1)
end
local obj, child = 0x251A83C0, 0x251BE190
local u32, u16, u8, logs = {}, {}, {}, {}
u32[obj + 0x0C], u32[child + 8] = child, obj
u16[obj + 0x4C], u16[child + 0x15C] = 2, 3
-- Generic object count is twelve, but only three treasure items are visible.
u16[obj + 0x24], u16[obj + 0x28] = 12, 12
for i, item in ipairs({ {856, 1, 9}, {768, 4, 2}, {868, 1, 6} }) do
    local row = child + 0x1C + (i - 1) * 0x20
    u16[row], u8[row + 2], u16[row + 4] = item[1], item[2], 0
    u8[row + 6], u16[row + 6] = item[3], 0xAB00 + item[3]
end
local names = { [856] = 'Rabbit Hide', [768] = 'Flint Stone', [868] = 'Pugil Scales' }
local axi = {
    is_probe_pointer = function(p) return type(p) == 'number' and p >= 0x10000 and p < 0x80000000 end,
    resource_item_info = function(id) return { name = names[id] or '' } end,
    escape_probe_log_text = function(s) return tostring(s) end,
}
local env = {
    accessxi = axi,
    accessxi_paths = { addon_path = function(a, b, c) return addon .. '/' .. a .. '/' .. b .. '/' .. c end },
    T = function(t) return t end,
    read_u32 = function(p) return u32[p] end,
    read_u16 = function(p) return u16[p] end,
    read_u8 = function(p) return u8[p] end,
    log_state = function(s) logs[#logs + 1] = s end,
    log_line = function(s) error(s) end,
    tick = function() return 4242 end,
    get_current_menu_object_ptr = function() return obj end,
}
setmetatable(env, {__index = _G})
string.fmt = string.format
string.eq = function(a, b) return a == b end
local function run(s)
    local f = assert(loadstring(s)); setfenv(f, env); return f()
end
run(between('function accessxi.load_menu_code_module(name, env)', 'accessxi.debug_commands ='))
run(between('function accessxi.treasure_pool_module_context()', 'function accessxi.search_player_options_module_context()'))
local speech = axi.treasure_pool_menu_speech('menu    loot', obj, child)
assert(speech == 'Treasure Pool. Flint Stone. Quantity 4. 2 of 3.', tostring(speech))
assert(axi.last_native_menu_selected == 2 and axi.last_native_menu_tick == 4242)
assert(logs[#logs]:find('poolSlot=2', 1, true), 'Log the actual pool slot, not cursor minus one')
local old_key = axi.current_speech_key
u16[obj + 0x4C] = 3
assert(axi.treasure_pool_menu_speech('menu    loot', obj, child) == 'Treasure Pool. Pugil Scales. 3 of 3.')
assert(axi.current_speech_key ~= old_key, 'Cursor changes must update speech identity')
u16[child + 0x1C + 2 * 0x20 + 4] = 65535
assert(axi.treasure_pool_menu_speech('menu    loot', obj, child) == 'Treasure Pool. Pugil Scales. Passed. 3 of 3.')
local function quiet(reason)
    assert(axi.treasure_pool_menu_speech('menu    loot', obj, child) == nil, reason)
    assert(logs[#logs]:find('reason="' .. reason .. '"', 1, true), logs[#logs])
end
u16[obj + 0x4C] = 4; quiet('invalid-selection')
u16[obj + 0x4C] = 2
u16[child + 0x15C] = 11; quiet('invalid-count')
u16[child + 0x15C] = nil; quiet('invalid-count')
u16[child + 0x15C] = 3
u32[child + 8] = obj + 4; quiet('parent-mismatch')
u32[child + 8] = obj
local row = child + 0x1C + 0x20
u8[row + 6] = 10
assert(axi.treasure_pool_menu_speech('menu    loot', obj, child) == 'Treasure Pool. Flint Stone. Quantity 4. 2 of 3.')
u8[row + 6] = 2
u16[row] = 0; quiet('invalid-item')
u16[row] = 768
u8[row + 2] = nil
assert(axi.treasure_pool_menu_speech('menu    loot', obj, child) == 'Treasure Pool. Flint Stone. 2 of 3.')
u8[row + 2] = 4
u16[row + 4] = 64000
assert(axi.treasure_pool_menu_speech('menu    loot', obj, child) == 'Treasure Pool. Flint Stone. Quantity 4. 2 of 3.')
u16[row + 4] = 0
names[768] = nil; quiet('missing-item-name')
names[768] = 'Flint Stone'
assert(axi.treasure_pool_menu_speech('menu    inventor', obj, child) == nil, 'Do not read other menu layouts')
u16[child + 0x15C] = 0
assert(axi.treasure_pool_menu_speech('menu    loot', obj, child) == 'Treasure Pool. Empty.')
u16[child + 0x15C] = 3

-- Exercise the production dispatcher, not just an isolated module. Its generic
-- query returns cursor 1 for loot, so it must not choose that query's cursor.
local native = assert(loadfile(addon .. '/modules/menus/native_menus.lua'))
setfenv(native, env); local titles = native().fixed_titles
axi.native_known_menu_title = function(name)
    for _, r in ipairs(titles) do for _, m in ipairs(r.menus) do if m == name then return r.title end end end
    return ''
end
axi.native_synthesis_menu_title = function() return '' end
axi.survival_guide_query_child_state_for_obj = function() error('Loot must use its own native layout') end
local a = assert(source:find('function accessxi.native_known_menu_speech(name)', 1, true))
local b = assert(source:find('\nfunction ', a + 10, true))
run(source:sub(a, b - 1))
assert(axi.native_known_menu_speech('menu    loot') == 'Treasure Pool. Flint Stone. Quantity 4. 2 of 3.')
-- 1013F340 opens lootope and copies one selected record, not a whole list.
-- 1013F460 maps row 1 to packet 0x041 (Lot), row 2 to 0x042 (Pass).
local popup = child + 0x1000
-- The pool cursor is independent of the newly focused action object.
u16[obj + 0x4C] = 3
obj = obj + 0x1000
u32[obj + 0x0C], u32[popup + 8] = popup, obj
u16[popup + 0x1C], u8[popup + 0x1E] = 856, nil
u16[popup + 0x20], u8[popup + 0x22], u16[popup + 0x22] = 0, 9, 0xAB09
u16[obj + 0x4C] = 1
assert(axi.native_known_menu_speech('menu    lootope') == 'Treasure Pool. Rabbit Hide. Lot.')
u16[obj + 0x4C] = 2
assert(axi.native_known_menu_speech('menu    lootope') == 'Treasure Pool. Rabbit Hide. Pass.')
u16[popup + 0x20] = 432
u16[obj + 0x4C] = 1
assert(axi.native_known_menu_speech('menu    lootope') == 'Treasure Pool. Rabbit Hide. Lot. Unavailable.')
u16[obj + 0x4C] = 3
assert(axi.native_known_menu_speech('menu    lootope') == nil, 'Do not invent a third action')
u16[obj + 0x4C] = 2
u16[popup + 0x1C] = 0
assert(axi.native_known_menu_speech('menu    lootope') == nil, 'Require the actual popup subject')
print('Treasure Pool native rows, guarded reads, production loader and dispatcher passed')
