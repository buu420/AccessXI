local addon_path = assert(arg[1], 'missing addon path')
local fixture_path = assert(arg[2], 'missing destination fixture path')

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear() for index = #self, 1, -1 do self[index] = nil end end
T = function(values) return setmetatable(values or {}, { __index = list_methods }) end

string.startswith = function(self, value) return self:sub(1, #value) == value end
string.contains = function(self, value) return self:find(value, 1, true) ~= nil end

local source_file = assert(io.open(addon_path, 'rb'))
local source = source_file:read('*a')
source_file:close()
local split_start = assert(source:find('local function nav_split_tsv', 1, true))
local split_finish = assert(source:find('\nfunction accessxi.nav_point_is_zoneline', split_start, true))
local split_source = source:sub(split_start, split_finish - 1)
split_source = split_source:gsub('local function nav_split_tsv', 'nav_split_tsv = function', 1)
local clean_start = assert(source:find('local function nav_clean_field', 1, true))
local clean_finish = assert(source:find('\nlocal function nav_tsv_field', clean_start, true))
local clean_source = source:sub(clean_start, clean_finish - 1)
clean_source = clean_source:gsub('local function nav_clean_field', 'nav_clean_field = function', 1)
local start_at = assert(source:find('local function nav_load_points_file', 1, true))
local finish_at = assert(source:find('\nlocal function nav_load_points()', start_at, true))
local loader_source = source:sub(start_at, finish_at - 1)
loader_source = loader_source:gsub(
    'local function nav_load_points_file',
    'nav_load_points_file = function',
    1
)
local copy_start = assert(source:find('function accessxi.nav_copy_point', 1, true))
local copy_finish = assert(source:find('\naccessxi.load_code_module', copy_start, true))
local copy_source = source:sub(copy_start, copy_finish - 1)

local accessxi = {
    nav_points = T{},
    nav_generated_name_is_placeholder = function() return false end,
    nav_graph_zone_name = function() return '' end,
}
local environment = setmetatable(
    {
        accessxi = accessxi,
        T = T,
        clean_login_text = function(value) return tostring(value or '') end,
    },
    { __index = _G }
)
local split_chunk = assert(loadstring(split_source, '@actual-nav-split-tsv'))
setfenv(split_chunk, environment)
split_chunk()
assert(type(environment.nav_split_tsv) == 'function')
local clean_chunk = assert(loadstring(clean_source, '@actual-nav-clean-field'))
setfenv(clean_chunk, environment)
clean_chunk()
assert(type(environment.nav_clean_field) == 'function')
local loader_chunk = assert(loadstring(loader_source, '@actual-nav-load-points-file'))
setfenv(loader_chunk, environment)
loader_chunk()
assert(type(environment.nav_load_points_file) == 'function')
local copy_chunk = assert(loadstring(copy_source, '@actual-nav-copy-point'))
setfenv(copy_chunk, environment)
copy_chunk()
assert(type(accessxi.nav_copy_point) == 'function')

local count = environment.nav_load_points_file(fixture_path, 'database')
assert(count == 6)
assert(accessxi.nav_points:len() == 6)

local legacy = accessxi.nav_points[1]
assert(legacy.zone == 101 and legacy.name == 'Legacy')
assert(legacy.x == 1 and legacy.z == 2 and legacy.y == 3)
assert(legacy.kind == 'npc' and legacy.source == 'manual')
assert(legacy.confidence == '' and legacy.section == '')
assert(legacy.destination_id == '' and legacy.raw_identity == '')
assert(legacy.raw_spawn_ids:len() == 0 and legacy.cluster_policy_version == '')

local current = accessxi.nav_points[2]
assert(current.zone == 101 and current.name == 'Current')
assert(current.x == 4 and current.z == 5 and current.y == 6)
assert(current.kind == 'object' and current.source == 'manual')
assert(current.confidence == 'observed' and current.section == 'review note')
assert(current.destination_id == '' and current.raw_identity == '')
assert(current.raw_spawn_ids:len() == 0 and current.cluster_policy_version == '')

local empty_confidence = accessxi.nav_points[3]
assert(empty_confidence.confidence == '' and empty_confidence.section == 'section survives')

local appended = accessxi.nav_points[4]
assert(appended.zone == 101 and appended.name == 'Appended')
assert(appended.x == 7 and appended.z == 8 and appended.y == 9)
assert(appended.kind == 'area' and appended.source == 'lsb-zoneline-all')
assert(appended.confidence == 'untested' and appended.section == 'generated section')
assert(appended.destination_id == 'area:v1:101:987')
assert(appended.raw_identity == 'lsb:zonelines:987')
assert(appended.raw_spawn_ids:len() == 0 and appended.cluster_policy_version == '')

local duplicate = accessxi.nav_points[5]
assert(duplicate.zone == appended.zone and duplicate.name == appended.name)
assert(duplicate.x == appended.x and duplicate.z == appended.z and duplicate.y == appended.y)
assert(duplicate.confidence == appended.confidence and duplicate.section == appended.section)
assert(duplicate.destination_id == 'area:v1:101:988')
assert(duplicate.raw_identity == 'lsb:zonelines:988')

local enemy = accessxi.nav_points[6]
assert(enemy.kind == 'enemy')
assert(enemy.destination_id == 'camp:v1:101:orcish-fodder:abc')
assert(enemy.raw_identity == 'lsb:mob_spawn_points:group:34:mobname:Orcish_Fodder')
assert(enemy.raw_spawn_ids:len() == 2 and enemy.raw_spawn_ids[1] == 413697
    and enemy.raw_spawn_ids[2] == 413698)
assert(enemy.cluster_policy_version == 'complete-link-v1-h120-y24')

local copied_appended = accessxi.nav_copy_point(appended)
assert(copied_appended.zone == appended.zone and copied_appended.name == appended.name)
assert(copied_appended.confidence == appended.confidence and copied_appended.section == appended.section)
assert(copied_appended.destination_id == appended.destination_id)
assert(copied_appended.raw_identity == nil and copied_appended.raw_spawn_ids == nil)
assert(copied_appended.cluster_policy_version == nil)

local copied_enemy = accessxi.nav_copy_point(enemy)
assert(copied_enemy.destination_id == enemy.destination_id)
assert(copied_enemy.raw_identity == nil and copied_enemy.raw_spawn_ids == nil)
assert(copied_enemy.cluster_policy_version == nil)
assert(accessxi.nav_points:len() == 6)

print('actual navigation loader preserved first-nine behavior for 7, 9, and 13 column rows')
