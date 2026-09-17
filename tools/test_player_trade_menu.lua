-- Production player-trade loader/dispatcher, using the native cursor and offers.
local addon = assert(arg[1], 'pass the addon root')
local f = assert(io.open(addon .. '/accessxi_reader.lua', 'rb'))
local source = f:read('*a'); f:close()
local function between(first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a + #first, true), last)
    return source:sub(a, b - 1)
end
local obj, child, inventory, pointer, root = 0x25737648, 0x251BCA00, 0x19000000, 0x0F26B756, 0x0F65FD98
local u32, u16, u8, logs = {}, {}, {}, {}
u32[obj + 0x0C], u32[child + 8] = child, obj
u16[obj + 0x4C], u32[child + 0xC0] = 1, 3
u32[pointer], u32[root] = root, inventory
local own = inventory + 0x194C0
for i = 0, 8 do u32[own + i * 8], u16[own + i * 8 + 4], u8[own + i * 8 + 6] = 0, 65535, 0 end
u32[own + 8], u16[own + 12], u8[own + 14] = 3, 953, 14
local names = { [953] = 'Treant Bulb', [841] = 'Yagudo Feather', [1607] = 'Bitter Memory' }
local axi = {
    is_probe_pointer = function(p) return type(p) == 'number' and p >= 0x10000 and p < 0x80000000 end,
    resource_item_info = function(id) return {name = names[id] or ''} end,
    escape_probe_log_text = tostring,
}
local env = {
    accessxi = axi,
    accessxi_paths = {addon_path = function(a,b,c) return addon .. '/' .. a .. '/' .. b .. '/' .. c end},
    T = function(t) return t end,
    read_u32 = function(p) return u32[p] end,
    read_u16 = function(p) return u16[p] end,
    read_u8 = function(p) return u8[p] end,
    log_state = function(s) logs[#logs+1] = s end,
    log_line = function(s) error(s) end,
    tick = function() return 4343 end,
    safe_call = function(fn, fallback) local ok,r=pcall(fn); if ok then return r else return fallback end end,
    AshitaCore = {GetPointerManager = function() return {Get = function(_,key) assert(key=='inventory'); return pointer end} end},
    get_current_menu_object_ptr = function() return obj end,
}
setmetatable(env, {__index=_G})
string.fmt = string.format
string.eq = function(a,b) return a==b end
local function run(s) local fn=assert(loadstring(s));setfenv(fn,env);return fn() end
run(between('function accessxi.load_menu_code_module(name, env)', 'accessxi.debug_commands ='))
run(between('function accessxi.player_trade_inventory_base()', 'function accessxi.treasure_pool_module_context()'))
local function say(menu,row)
    u16[obj + 0x4C] = row
    return axi.player_trade_menu_speech(menu or 'menu    trade',obj,child)
end
assert(say(nil,1) == 'Your offer. Slot 1. Treant Bulb. Quantity 3.')
local old_key = axi.current_speech_key
u32[own + 8] = 2
assert(say(nil,1) == 'Your offer. Slot 1. Treant Bulb. Quantity 2.')
assert(axi.current_speech_key ~= old_key, 'Changed offers must update speech without cursor movement')
assert(say(nil,2) == 'Your offer. Slot 2. Empty.')
assert(say(nil,8) == 'Your offer. Slot 8. Empty.')
assert(say(nil,9) == 'Trade. Okay.')
assert(say(nil,10) == 'Trade. Cancel.')
u32[own] = 123456
assert(say(nil,11) == 'Your offer. Gil 123456.')
u16[own+4] = 0
assert(say(nil,11) == 'Your offer. Gil 0.', 'Mirror the renderer gil-record validity check')
u16[own+4] = 65535
assert(say(nil,12) == nil, 'Generic widget count13 is not selectable row count')
u32[child + 8] = obj + 4
assert(say(nil,1) == nil, 'Reject mismatched owner')
u32[child + 8] = obj
u32[root] = 0
assert(say(nil,9) == 'Trade. Okay.', 'Readable controls do not depend on inventory data')
assert(say(nil,1) == 'Your offer. Slot 1. Item information unavailable.')
u32[root] = inventory
names[953] = nil
assert(say(nil,1) == 'Your offer. Slot 1. Item information unavailable.')
names[953] = 'Treant Bulb'
assert(say('menu    handover',1) == nil, 'Keep NPC handovers in their existing reader')
-- The other offer uses a separate 0x2C record layout, not own 8-byte records.
local own_obj, own_child = obj, child
obj, child = 0x25736A80, 0x250737B0
u32[obj+0x0C], u32[child+8] = child, obj
u16[obj+0x24] = 10 -- Generic capacity is not the native row map.
local other = inventory + 0x19308
for i=1,8 do u16[other+i*0x2C], u32[other+i*0x2C+4] = 65535, 0 end
u16[other+0x2C], u32[other+0x2C+4] = 1607, 1
assert(say('menu    gift',1) == "Other player's offer. Slot 1. Bitter Memory. Quantity 1.")
assert(say('menu    gift',8) == "Other player's offer. Slot 8. Empty.")
u32[other+4] = 4000000000
assert(say('menu    gift',11) == "Other player's offer. Gil 4000000000.")
assert(say('menu    gift',9) == nil and say('menu    gift',10) == nil, 'Other pane has no Okay or Cancel rows')
u16[other+0x2C] = 0
u32[other+0x2C+4] = 999
assert(say('menu    gift',1) == "Other player's offer. Slot 1. Empty.", 'Native item-id sentinel controls other empty slots')
obj,child = own_obj,own_child
local native=assert(loadfile(addon .. '/modules/menus/native_menus.lua'));setfenv(native,env)
local titles=native().fixed_titles
axi.native_known_menu_title = function(name)
    for _,r in ipairs(titles) do for _,m in ipairs(r.menus) do if m==name then return r.title end end end
    return ''
end
axi.native_synthesis_menu_title = function() return '' end
axi.survival_guide_query_child_state_for_obj = function() error('Player trade must not use generic child cursor') end
local a=assert(source:find('function accessxi.native_known_menu_speech(name)',1,true))
local b=assert(source:find('\nfunction ',a+10,true))
run(source:sub(a,b-1))
u16[obj+0x4C]=1
assert(axi.native_known_menu_speech('menu    trade') == 'Your offer. Slot 1. Treant Bulb. Quantity 2.')
obj,child = 0x25736A80,0x250737B0
u16[obj+0x4C] = 11
assert(axi.native_known_menu_speech('menu    gift') == "Other player's offer. Gil 4000000000.")
assert(logs[#logs]:find('state player-trade',1,true))
print('Player trade native offers, guarded reads, production loader and dispatcher passed')
