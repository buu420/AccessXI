-- Reproduce the 2026-09-04 Holla warp_05 obstacle through the deployed reader.
-- Run with Lua 5.1 or LuaJIT. ACCESSXI_ADDON may select an isolated live copy.
-- Only the game entity/terrain APIs and unrelated catalogue are fixtures; the
-- snapshot, nearby scan, classifiers, validity and obstacle selection are real.
local addon = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader'
local file = assert(io.open(addon .. '/accessxi_reader.lua', 'rb'))
local source = file:read('*a')
file:close()

local passed, failed = 0, 0
local function claim(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1 end
    print((ok and 'PASS ' or 'FAIL ') .. name)
end
local function extract(first, last)
    local start = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(last, start + #first, true), last)
    return source:sub(start, finish - 1)
end

local methods = {}
function methods:append(value) self[#self + 1] = value end
function methods:len() return #self end
function methods:concat(separator) return table.concat(self, separator) end
T = function(value) return setmetatable(value or {}, { __index = methods }) end
string.fmt = string.format
function string.contains(value, needle) return value:find(needle, 1, true) ~= nil end
function string.trim(value) return value:match('^%s*(.-)%s*$') end
function string.startswith(value, prefix) return value:sub(1, #prefix) == prefix end
bit = bit or {}
if not bit.band then
    function bit.band(a, b)
        local result, place = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then result = result + place end
            a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
        end
        return result
    end
end
function nav_clean_field(value) return tostring(value or ''):trim() end
function nav_zone_id() return 16 end
function nav_load_points() end -- The static NM catalogue is empty in this test.
function tick() return 50000 end
function log_line() end
local player = { index = 0, zone = 16, x = -280, y = 0.541, z = -48 }
local target = { zone = 16, x = -280, y = 0.541, z = -32 }
function nav_cached_player_position() return player end

local slots = {}
local entity = {}
function entity:GetEntityMapSize() return 3 end
local fields = {
    GetName = 'name', GetLocalPositionX = 'x', GetLocalPositionY = 'z',
    GetLocalPositionZ = 'y', GetLocalPositionYaw = 'yaw', GetServerId = 'server_id',
    GetType = 'type', GetHPPercent = 'hp', GetStatus = 'status',
    GetClaimStatus = 'claim', GetSpawnFlags = 'spawn_flags', GetNameColor = 'name_color',
    GetRenderFlags0 = 'render_flags_0', GetRenderFlags1 = 'render_flags_1',
}
for method, field in pairs(fields) do
    local key = field
    entity[method] = function(_, index)
        assert(index >= 0 and index <= 2)
        local row = slots[index]
        if row and key == 'render_flags_1' and row.render_error then error('unreadable render field') end
        return row and row[key]
    end
end
AshitaCore = { GetMemoryManager = function()
    return { GetEntity = function() return entity end }
end }
accessxi = { nav_points = {} }
accessxi.nav_valid_mesh_position = function() return true end
accessxi.nav_wall_distance = function() return 5 end

-- Keep the local reader helpers together so Lua resolves their real scope.
local code = extract('local function safe_call(fn, default)', 'local function get_ffximain_base()')
    .. extract('local function nav_entity_position(index, want_stream_evidence)',
        'function accessxi.nav_entity_snapshot_for_server_id(server_id)')
    .. extract('local function nav_distance(a, b)', 'local function nav_vertical_phrase(')
    .. 'local nav_nearby;\n'
    .. extract('nav_nearby = function (max_count, max_distance)',
        'function accessxi.nav_live_entity_search_range()')
    .. extract('function accessxi.nav_live_nm_names_for_zone(zone)',
        'function accessxi.nav_stable_destination_duplicate_key(point)')
    .. extract('function accessxi.nav_live_entity_snapshot(max_count, max_distance)',
        'function accessxi.nav_live_entities_for_category(')
    .. '\nreturn nav_entity_position;'
local position = assert(loadstring(code))()
dofile(addon .. '/modules/nav_dynamic_obstacle.lua')
dofile(addon .. '/modules/promyvion_navigation.lua')

-- Exact server id, anchor and observed status/spawn/render fields from the
-- reviewed topology and log line 1254215. HP/type are adversarial: neither is
-- a witness of hostility (the Ashita SDK calls type 3 doors/objects).
local stream = {
    server_id = 16843058, name = 'warp_05', x = -280.009, z = -39.956, y = 0.541,
    status = 9, spawn_flags = 34, render_flags_0 = 1077936640, render_flags_1 = 2176,
    type = 3, hp = 100,
}
slots[1] = stream
local live = accessxi.nav_live_entity_snapshot(80, 20)
claim('closed Stream remains an object in the real live scan', #live == 1 and live[1].live_kind == 'object')
claim('closed Stream is not an enemy', not accessxi.nav_entity_is_enemy(position(1)))
claim('closed Stream produces no enemy obstacle warning', accessxi.nav_segment_obstacle(player, target) == nil)
local aim, obstacle = accessxi.nav_obstacle_avoidance_target(player, target)
claim('closed Stream produces neither an avoidance target nor a blocked obstacle', aim == nil and obstacle == nil)
claim('closed Stream still reports closed', accessxi.nav_promyvion_stream_state(position(1, true)) == 'closed')

stream.status = 8
claim('open Stream remains approachable without an enemy obstacle', accessxi.nav_segment_obstacle(player, target) == nil)
claim('open Stream still reports open', accessxi.nav_promyvion_stream_state(position(1, true)) == 'open')
stream.render_flags_1 = 4096
claim('retained open Stream remains unknown after despawn', accessxi.nav_promyvion_stream_state(position(1, true)) == 'unknown')
stream.render_flags_1, stream.render_flags_0 = nil, nil
claim('unreadable open Stream remains unknown', accessxi.nav_promyvion_stream_state(position(1, true)) == 'unknown')
stream.render_flags_1, stream.render_flags_0 = 2176, 1077936640

stream.name = 'Bomb-shaped mechanism'
claim('native object evidence wins over an enemy-looking name', not accessxi.nav_entity_is_enemy(position(1)))
stream.name = 'warp_05'

-- Literal Monster flag 0x10 from the SDK. The full scan must retain actual
-- mobs while the nearer Stream no longer masks them in obstacle selection.
local mob = {
    server_id = 16842848, name = 'Memory Receptacle', x = -280, z = -37, y = 0.541,
    status = 1, spawn_flags = 16, render_flags_1 = 2176, type = 2, hp = 100,
}
slots[2] = mob
obstacle = accessxi.nav_segment_obstacle(player, target)
claim('nearer Stream does not mask the actual Receptacle obstacle',
    obstacle ~= nil and obstacle.entity.server_id == 16842848)
mob.name = 'Wanderer'
live = accessxi.nav_live_entity_snapshot(80, 20)
claim('ordinary mob survives the real snapshot and classification chain',
    #live == 2 and live[2].live_kind == 'enemy' and live[2].name == 'Wanderer')
mob.spawn_flags = 48
claim('positive Monster flag is not suppressed by a simultaneous Object bit', accessxi.nav_entity_is_enemy(position(2)))
mob.spawn_flags = 16
mob.render_flags_1 = nil
live = accessxi.nav_live_entity_snapshot(80, 20)
claim('ordinary mob with unreadable render evidence is not invented as live', #live == 1 and live[1].name == 'warp_05')
mob.render_error = true
live = accessxi.nav_live_entity_snapshot(80, 20)
claim('raising render accessor stays contained without inventing a mob', #live == 1 and live[1].name == 'warp_05')
mob.render_error, mob.render_flags_1 = nil, 4096
claim('despawned ordinary mob cannot become a dynamic obstacle', accessxi.nav_segment_obstacle(player, target) == nil)
mob.render_flags_1, mob.hp = 2176, 0
claim('ordinary corpse cannot become a dynamic obstacle', accessxi.nav_segment_obstacle(player, target) == nil)

print(('Promyvion Stream obstacles: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
