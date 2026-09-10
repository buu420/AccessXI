-- Sept. 10, 2026: valid selected IDs/counts, but Ashita's old name offset
-- produces no native label. Drive the real reader over both client layouts.
local addon = os.getenv('ACCESSXI_ADDON') or 'ashita/addons/accessxi_reader';
local file = assert(io.open(addon .. '/accessxi_reader.lua', 'rb'));
local source = file:read('*a'); file:close();
string.fmt = string.format;
bit = require('bit');
accessxi = {};
local passed, failed = 0, 0;
local function check(ok, message)
    if ok then passed = passed + 1;
    else failed = failed + 1; print('FAIL: ' .. message); end
end
local function load_function(name)
    local first = source:find('function accessxi.' .. name .. '(', 1, true);
    if not first then return false; end
    local last = assert(source:find('\nend', first, true));
    assert(loadstring(source:sub(first, last + 3), name))();
    return true;
end

local image, current, actual, selected, writes, logged, write_error, drop_write;
local base = 0x10000000;
local function bytes(hex)
    return (hex:gsub('%x%x', function(v) return string.char(tonumber(v, 16)); end));
end
local new_getter = bytes('8B410485C07501C38B80C8140000C3');
local new_caller = bytes('8B86C814000085C0741B0FBF4C2414556A005083C114');
local old_getter = bytes('8B410485C07501C38B80C80C0000C3');
local old_caller = bytes('8B86C80C000085C0741B0FBF4C2414556A005083C114');
ashita = { memory = { find = function(module, size, pattern, offset, usage)
    assert(module == ':ffximain' and size == 0, 'scan must target the game module');
    local tokens = {};
    for token in pattern:gmatch('..') do tokens[#tokens + 1] = token; end
    local found = 0;
    for i = 1, #image - #tokens + 1 do
        local match = true;
        for j, token in ipairs(tokens) do
            if token ~= '??' and image:byte(i + j - 1) ~= tonumber(token, 16) then
                match = false; break;
            end
        end
        if match then
            if found == usage then return base + i - 1 + offset; end
            found = found + 1;
        end
    end
    return 0;
end } };
function read_u32(address)
    local i = address - base + 1;
    local a, b, c, d = image:byte(i, i + 3);
    if not d then return 0; end
    return a + b * 256 + c * 65536 + d * 16777216;
end
local offsets = {
    Get = function(_, section, key)
        assert(section == 'inventory.selecteditem' and key == 'name.offset4');
        return current;
    end,
    Add = function(_, section, key, value)
        assert(section == 'inventory.selecteditem' and key == 'name.offset4');
        if write_error then error('cache unavailable'); end
        writes = writes + 1;
        if not drop_write then current = value; end
    end,
};
local inventory = {
    GetSelectedItemId = function() return selected.id; end,
    GetSelectedItemIndex = function() return selected.slot; end,
    GetDisplayItemSlot = function() return selected.row; end,
    -- Same boundary as Ashita: the configured terminal field supplies the
    -- current native label; the stale field does not contain an item name.
    GetSelectedItemName = function() return current == actual and selected.label or ''; end,
    GetContainerItem = function() return { Id = selected.id, Count = 1 }; end,
    GetContainerCount = function() return 30; end,
    GetContainerCountMax = function() return 30; end,
};
AshitaCore = {
    GetOffsetManager = function() return offsets; end,
    GetMemoryManager = function() return { GetInventory = function() return inventory; end }; end,
};
function safe_call(fn, fallback) local ok, v = pcall(fn); if ok then return v; end return fallback; end
function clean_login_text(v) return v or ''; end
function get_current_menu_object_ptr() return 0; end
function read_probe_string() return ''; end
function is_valid_inventory_item_id(id) return id and id > 0 and id < 65535; end
function inventory_item_count(item) return item and item.Count or 0; end
function resource_item_info(id) return { id = id, name = 'resource-only label', description = '' }; end
function T(t) return setmetatable(t, { __index = {
    append = function(self, v) self[#self + 1] = v; end,
    len = function(self) return #self; end,
} }); end
function item_static_detail_parts() return T{}; end
function item_dynamic_detail_parts() return {}; end
function has_charge_detail() return true; end
function tick() return 1000; end
function log_line(v) logged[#logged + 1] = v; end
log_state = log_line;
inventory_container_names = { [0] = 'Inventory' };
accessxi.plain_native_menu_label = function(v) return v or ''; end
accessxi.is_probe_pointer = function(v) return v and v >= 0x10000; end
accessxi.escape_probe_log_text = tostring;
accessxi.resource_item_speech_name = function(_, native) return native, 'native-name'; end
assert(load_function('get_native_selected_inventory_item_info'));
load_function('configure_inventory_name_offset');
local function configure()
    -- Before the fix, startup has no compatibility adjustment. This keeps the
    -- red test about the missing player-visible label, not a missing symbol.
    if accessxi.configure_inventory_name_offset then return accessxi.configure_inventory_name_offset(); end
end
local function reset(old)
    image = old and old_getter .. '\204\204' .. old_caller or new_getter .. '\204\204' .. new_caller;
    current, actual = 0xCC8, old and 0xCC8 or 0x14C8;
    selected = { id = 18166, slot = 24, row = 4, label = 'happy egg' };
    writes, logged, write_error, drop_write = 0, {}, false, false;
    accessxi.inventory_context = 'inventory';
end
local function info() return accessxi.get_native_selected_inventory_item_info('menu    inventor'); end

reset();
check(info() == nil, 'the captured failure is reproduced before adjustment');
configure();
local item = info();
check(item and item.name == 'happy egg' and item.visible_name == 'happy egg', 'updated client reads the current native item label');
check(item and item.id == 18166 and item.visible_position == 4 and item.container_count == 30, 'selection identity and counts survive');
selected = { id = 28540, slot = 27, row = 5, label = 'warp ring' };
item = info();
check(item and item.visible_name == 'warp ring' and item.id == 28540, 'moving the cursor reads the next native label');
selected.label = '';
check(info() == nil, 'a truly unavailable native label is not invented from resources');
configure();
check(writes == 1, 'repeat setup does not overwrite an already correct cache');

reset(true); configure();
check(info() and info().visible_name == 'happy egg' and writes == 0, 'old client keeps its working offset');
current = 0x14C8; configure();
check(info() and writes == 1, 'old client repairs an offset left at the newer reviewed layout');

local cases = {
    { 'missing getter', function() image = new_caller; end },
    { 'missing caller', function() image = new_getter; end },
    { 'duplicate getter', function() image = image .. new_getter; end },
    { 'duplicate caller', function() image = image .. new_caller; end },
    { 'disagreeing witnesses', function() image = old_getter .. new_caller; end },
    { 'unreviewed layout', function() image = image:gsub(bytes('C8140000'), bytes('C8180000')); end },
    { 'custom offset', function() current = 0x1234; end },
};
for _, case in ipairs(cases) do
    reset(); case[2](); local before = current;
    local ok = configure();
    check(ok ~= true and writes == 0 and current == before, case[1] .. ' leaves the offset untouched');
    check(#logged > 0, case[1] .. ' records why inventory compatibility was not applied');
end
reset(); write_error = true;
check(configure() == false and current == 0xCC8, 'cache write failure stays contained');
reset(); drop_write = true;
check(configure() == false, 'a failed cache read-back is not reported as applied');
reset(); local find = ashita.memory.find; ashita.memory.find = function() error('module unavailable'); end;
check(configure() == false and writes == 0, 'scanner errors do not stop addon startup');
ashita.memory.find = find;
print(('inventory name layout: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
