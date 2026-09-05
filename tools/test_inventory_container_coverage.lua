-- EVERY CONTAINER THE PLAYER OWNS, NOT ONLY THE ONE IN THEIR HANDS.
--
-- refresh_objective_inventory_state scanned container 0 and nothing else, so
-- Safe, Storage, Satchel, Sack, Case, Locker and the wardrobes were invisible.
-- On this character a Seedspall Lux is sitting in Mog Storage: asked whether
-- they held it we would have said no and sent them back to Jugner Forest to
-- farm one they already own.
--
-- It also accepted a capacity of ZERO -- the guard rejected only a negative --
-- and then stamped the result 'native-inventory' regardless, so a read taken
-- before the containers loaded was indistinguishable from a player carrying
-- nothing. 199 of 601 snapshots in the live log recorded zero items.
--
-- Drives the REAL builder, lifted from the deployed accessxi_reader.lua, over a
-- stubbed Ashita inventory.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local src = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

local from = src:find('function accessxi.refresh_objective_inventory_state(reason)', 1, true);
claim(from ~= nil, 'the builder exists in the deployed reader');
local to = from and src:find('\nend\n', from, true) or nil;
claim(to ~= nil, 'and is a complete function');
if (from == nil or to == nil) then
    print('inventory container coverage: 0 passed, 2 failed'); os.exit(1);
end

-- Addon plumbing the builder speaks through.
local logged = {};
_G.log_line = function (v) logged[#logged + 1] = tostring(v or ''); end
_G.tick = function () return 1000; end
_G.inventory_item_count = function (item) return tonumber(item.Count) or 0; end
accessxi.escape_probe_log_text = function (v) return tostring(v or ''); end
accessxi.current_player_name = function () return 'Longrod'; end
accessxi.current_player_identity = function () return 'longrod:127'; end
accessxi.current_objective_session_epoch = function () return 42; end
accessxi.current_player_world_id = function () return 127; end
accessxi.objective_item_name_for_id = function (id) return 'Item' .. tostring(id); end

-- The stub inventory. `stock` maps container -> { [slot] = {Id=, Count=} }.
local stock, capacity, asked = {}, {}, {};
_G.AshitaCore = {
    GetMemoryManager = function ()
        return {
            GetInventory = function ()
                return {
                    GetContainerCountMax = function (_, container)
                        asked[container] = true;
                        return capacity[container] or 0;
                    end,
                    GetContainerItem = function (_, container, slot)
                        local c = stock[container];
                        return (c and c[slot]) or { Id = 0, Count = 0 };
                    end,
                };
            end,
        };
    end,
};

local deltas = {};
accessxi.nav_mission_quest_reduce_signal = function (signal)
    deltas[#deltas + 1] = signal;
end

assert(load(src:sub(from, to + 4), 'builder'))();
claim(type(accessxi.refresh_objective_inventory_state) == 'function', 'the real builder loaded');

local function reset()
    stock, capacity, asked, deltas, logged = {}, {}, {}, {}, {};
    accessxi.objective_inventory_counts = nil;
    accessxi.inventory_packet_source = nil;
    accessxi.inventory_packet_identity = nil;
    accessxi.inventory_packet_session_epoch = nil;
    accessxi.inventory_packet_coverage = nil;
    accessxi.inventory_packet_slots = nil;
    accessxi.inventory_packet_key = nil;
end

-- 1. AN EMPTY READ IS REFUSED. This is the 199-of-601 case.
reset();
local changed, available = accessxi.refresh_objective_inventory_state('test-empty');
claim(available == false, 'a scan with no loaded container is unavailable');
claim(accessxi.inventory_packet_source == nil,
    'and it does NOT stamp the snapshot as native-inventory');
local said_capacity = false;
for _, line in ipairs(logged) do
    if (line:find('containers=0', 1, true)) then said_capacity = true; end
end
claim(said_capacity, 'and it says why in the log');

-- 2. THE REGRESSION. An item banked in Mog Storage must be found.
reset();
capacity[0] = 3;  stock[0] = { [1] = { Id = 1000, Count = 1 } };          -- Inventory
capacity[2] = 5;  stock[2] = { [2] = { Id = 2740, Count = 1 } };          -- Storage: Seedspall Lux
capacity[5] = 4;  stock[5] = { [1] = { Id = 2741, Count = 2 } };          -- Satchel
changed, available = accessxi.refresh_objective_inventory_state('test-wide');
claim(available == true, 'a scan that saw containers is available');
claim(accessxi.objective_inventory_counts[2740] == 1,
    'the Seedspall banked in Mog Storage is counted, got '
    .. tostring(accessxi.objective_inventory_counts[2740]));
claim(accessxi.objective_inventory_counts[2741] == 2,
    'and quantities from a satchel are counted');
claim(accessxi.objective_inventory_counts[1000] == 1, 'alongside ordinary inventory');

-- 3. It really did look at every container, not just the ones with stock.
local asked_count = 0;
for container = 0, 16 do if (asked[container]) then asked_count = asked_count + 1; end end
claim(asked_count == 17, 'capacity was asked for containers 0 through 16, got ' .. asked_count);
claim(asked[17] ~= true, 'and the Recycle Bin is not treated as a holding');

-- 4. Coverage is recorded, because availability now depends on it.
claim(accessxi.inventory_packet_coverage == '0,2,5',
    'the snapshot records which containers it saw, got '
    .. tostring(accessxi.inventory_packet_coverage));
claim((tonumber(accessxi.inventory_packet_slots) or 0) == 12,
    'and how many slots it read, got ' .. tostring(accessxi.inventory_packet_slots));

-- 5. WIDER EYES ARE NOT A WINDFALL. A coverage change must not look like the
--    player acquiring everything they had ever banked -- an inventory-delta can
--    COMPLETE an obtain step.
reset();
capacity[0] = 3; stock[0] = { [1] = { Id = 1000, Count = 1 } };
accessxi.refresh_objective_inventory_state('narrow');
claim(#deltas == 0, 'the first scan emits no deltas, got ' .. #deltas);
deltas = {};
capacity[2] = 5; stock[2] = { [1] = { Id = 2740, Count = 1 } };   -- storage becomes visible
accessxi.refresh_objective_inventory_state('now-wider');
claim(accessxi.objective_inventory_counts[2740] == 1, 'the newly visible item is counted');
claim(#deltas == 0,
    'but a coverage change emits NO acquisition deltas, got ' .. #deltas);
local rebaselined = false;
for _, line in ipairs(logged) do
    if (line:find('coverage changed', 1, true)) then rebaselined = true; end
end
claim(rebaselined, 'and it says it rebaselined');

-- 6. A genuine gain, with coverage unchanged, DOES still report.
deltas = {};
stock[0][2] = { Id = 1001, Count = 1 };
accessxi.refresh_objective_inventory_state('genuine-gain');
claim(#deltas == 1, 'an actual acquisition still emits one delta, got ' .. #deltas);
claim(deltas[1] ~= nil and deltas[1].kind == 'inventory-delta'
    and deltas[1].item_id == 1001,
    'and it names the item that arrived');

print(('inventory container coverage: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
