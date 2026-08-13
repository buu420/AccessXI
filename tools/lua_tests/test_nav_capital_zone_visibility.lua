local addon_path = assert(arg[1], 'expected accessxi_reader.lua path')
local graph_path = assert(arg[2], 'expected checked-in zoneline graph path')
local handle = assert(io.open(addon_path, 'rb'))
local source = handle:read('*a')
handle:close()

local function extract(first_marker, next_marker)
    local first = assert(source:find(first_marker, 1, true), 'missing source marker: ' .. first_marker)
    local last = assert(source:find(next_marker, first + #first_marker, true), 'missing end marker: ' .. next_marker)
    return source:sub(first, last - 1)
end

function string.contains(value, needle)
    return string.find(value, needle, 1, true) ~= nil
end

function string.startswith(value, prefix)
    return value:sub(1, #prefix) == prefix
end

function string.trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function string.fmt(value, ...)
    return string.format(value, ...)
end

local list_methods = {}
function list_methods:append(value)
    self[#self + 1] = value
    return self
end
function list_methods:clear()
    for key in pairs(self) do
        self[key] = nil
    end
end
function list_methods:len()
    return #self
end

function T(value)
    return setmetatable(value or {}, { __index = list_methods })
end

function nav_clean_field(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
end

local current_player = T{ zone = 239, x = 0, z = 135, y = -17 }
local now = 1000
local spoken = {}
local logged = {}
local started_legs = {}

function nav_cached_player_position()
    return current_player
end

function nav_zone_id()
    return current_player.zone
end

function nav_load_points()
end

function nav_distance(a, b)
    local dx = (tonumber(b and b.x) or 0) - (tonumber(a and a.x) or 0)
    local dz = (tonumber(b and b.z) or 0) - (tonumber(a and a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz
end

function tick()
    return now
end

function speak(text)
    spoken[#spoken + 1] = text
end

function log_line(text)
    logged[#logged + 1] = text
end

accessxi = {
    nav_points = T{},
    nav_zoneline_graph_path = graph_path,
    nav_zoneline_edges_loaded = false,
    nav_zoneline_edges = T{},
    nav_menu_items = T{},
    nav_menu_index = 1,
    nav_menu_dirty_categories = {},
    nav_menu_open = false,
    nav_menu_poll_key = 0,
    nav_menu_poll_tick = 0,
    nav_menu_open_tick = 0,
    nav_menu_search_query = 'Heavens Tower',
    nav_zone_search_target = nil,
    nav_zone_search_query = '',
    nav_zone_search_waiting_zone = 0,
    nav_zone_search_waiting_from_zone = 0,
    nav_zone_search_last_replan_tick = 0,
    nav_active = false,
    -- Empty character-access fixtures must not hide either ordinary capital zone.
    nav_nation = '',
    nav_rank = 0,
    nav_mission_states = T{},
    nav_quest_states = T{},
    nav_key_items = T{},
}

function accessxi.nav_zone_resource_name(zone)
    local names = {
        [235] = 'Bastok Markets',
        [237] = 'Metalworks',
        [239] = 'Windurst Walls',
        [242] = 'Heavens Tower',
    }
    return names[tonumber(zone) or 0] or ''
end

function accessxi.nav_point_effective_kind(point)
    return nav_clean_field(point and point.kind or ''):lower()
end

function accessxi.nav_copy_point(point)
    local copy = T{}
    for key, value in pairs(point or {}) do
        copy[key] = value
    end
    return copy
end

function accessxi.speech_name(value)
    return tostring(value or '')
end

function accessxi.nav_start_route_to_point(point, reason)
    started_legs[#started_legs + 1] = {
        point = accessxi.nav_copy_point(point),
        reason = reason,
    }
    accessxi.nav_active = true
    return ('Started %s.'):fmt(point.name or 'route')
end

function accessxi.nav_clear_zone_search()
    accessxi.nav_zone_search_target = nil
    accessxi.nav_zone_search_query = ''
    accessxi.nav_zone_search_waiting_zone = 0
    accessxi.nav_zone_search_waiting_from_zone = 0
    accessxi.nav_zone_search_last_replan_tick = 0
end

local split_source = extract('local function nav_split_tsv(line)', '\nfunction accessxi.nav_point_is_zoneline')
split_source = split_source:gsub('local function nav_split_tsv', 'function nav_split_tsv', 1)
assert(loadstring(split_source, '@reader-tsv-loader-helper'))()

local loader_source = extract('function accessxi.nav_load_zoneline_graph()', 'function accessxi.nav_graph_zone_name')
assert(loadstring(loader_source, '@reader-zoneline-loader'))()

local graph_name_source = extract('function accessxi.nav_graph_zone_name(zone)', 'function accessxi.nav_zoneline_edge_rank')
assert(loadstring(graph_name_source, '@reader-graph-zone-name'))()

local edge_source = extract('function accessxi.nav_zoneline_edge_rank(edge, player)', 'function accessxi.nav_zoneline_path(from_zone, to_zone, final_edge_id)')
assert(loadstring(edge_source, '@reader-zoneline-edges'))()

local path_source = extract('function accessxi.nav_zoneline_path(from_zone, to_zone, final_edge_id)', 'function accessxi.nav_zoneline_approach_candidates')
assert(loadstring(path_source, '@reader-zone-path'))()

local search_text_source = extract('accessxi.nav_search_text = function (value)', 'local function nav_collect_menu_items')
assert(loadstring(search_text_source, '@reader-search-text'))()

local confidence_source = extract('local function nav_point_confidence(point)', 'local function nav_write_route_evidence')
confidence_source = confidence_source:gsub('local function nav_point_confidence', 'function nav_point_confidence', 1)
confidence_source = confidence_source:gsub('local function nav_point_confidence_rank', 'function nav_point_confidence_rank', 1)
assert(loadstring(confidence_source, '@reader-confidence'))()

local rank_source = extract('local function nav_point_source_rank(point)', 'accessxi.nav_menu_static_key = function')
rank_source = rank_source:gsub('local function nav_point_source_rank', 'function nav_point_source_rank', 1)
assert(loadstring(rank_source, '@reader-source-rank'))()

local results_source = extract('function accessxi.nav_zone_search_npc_results(query, player)', 'function accessxi.nav_find_zone_search_npc(query, player)')
assert(loadstring(results_source, '@reader-global-zone-results'))()

local next_leg_source = extract('function accessxi.nav_zone_search_start_next_leg(reason)', 'function accessxi.nav_zone_search_start(query)')
assert(loadstring(next_leg_source, '@reader-zone-next-leg'))()

local poll_source = extract('function accessxi.poll_nav_zone_search()', 'local function nav_focus_target_position()')
assert(loadstring(poll_source, '@reader-zone-poll'))()

accessxi.nav_load_zoneline_graph()
local forward = accessxi.nav_zoneline_path(239, 242)
local reverse = accessxi.nav_zoneline_path(242, 239)
assert(forward:len() == 1 and forward[1].id == 239242086,
    'Windurst Walls to Heavens Tower must be exactly scripted edge 239242086')
assert(reverse:len() == 1 and reverse[1].id == 242239041,
    'Heavens Tower to Windurst Walls must be exactly scripted edge 242239041')

local heavens_results = accessxi.nav_zone_search_npc_results('Heavens Tower', current_player)
assert(#heavens_results == 1, 'empty access state should expose exactly one Heavens Tower zone result')
local heavens = heavens_results[1]
assert(heavens.zone == 242 and heavens.name == 'Heavens Tower',
    'Heavens Tower search returned the wrong canonical zone')
assert(heavens.zone_search_result == true and heavens.zone_search_zone_result == true,
    'Heavens Tower must use the existing selectable zone-search row')
assert(heavens.zone_search_canonical_edge_id == 239242086
    and heavens.zone_search_canonical_from_zone == 239,
    'Heavens Tower must pin the ordinary Windurst Walls ingress')
assert(heavens.x == 0 and heavens.z == -22.4 and heavens.y == 0,
    'Heavens Tower result must use the scripted landing position')

local metalworks_results = accessxi.nav_zone_search_npc_results('Metalworks', current_player)
assert(#metalworks_results == 1, 'Metalworks must remain one canonical capital-zone result')
local metalworks = metalworks_results[1]
assert(metalworks.zone == 237 and metalworks.name == 'Metalworks',
    'Metalworks search returned the wrong canonical zone')
assert(metalworks.zone_search_canonical_edge_id == 912930426
    and metalworks.zone_search_canonical_from_zone == 235,
    'Metalworks canonical ingress changed or was duplicated')

local menu_environment = setmetatable({
    accessxi = accessxi,
    T = T,
    nav_clean_field = nav_clean_field,
    nav_cached_player_position = nav_cached_player_position,
    nav_current_category = function() return { key = 'search-results' } end,
    nav_menu_rebuild = function() end,
    speak = speak,
    log_line = log_line,
    tick = tick,
}, { __index = _G })
local menu_source = extract('local function nav_menu_start_route()', '\nlocal nav_route_stop;')
local menu_chunk = assert(loadstring(menu_source .. '\nreturn nav_menu_start_route', '@reader-zone-menu-start'))
setfenv(menu_chunk, menu_environment)
local nav_menu_start_route = assert(menu_chunk())

accessxi.nav_menu_items = T{ heavens }
nav_menu_start_route()
assert(accessxi.nav_zone_search_target ~= nil and accessxi.nav_zone_search_target.zone == 242,
    'selecting Heavens Tower did not retain zone 242 as the target')
assert(#started_legs == 1, 'selecting Heavens Tower should start exactly one cross-zone leg')
local ingress = started_legs[1].point
assert(ingress.zone == 239 and ingress.to_zone == 242,
    'selected Heavens Tower row did not use the Windurst Walls ingress')
assert(ingress.x == 0 and ingress.z == 141 and ingress.y == -16.5,
    'selected Heavens Tower row did not route to trigger area 1')
assert(ingress.source:find('239242086', 1, true) ~= nil,
    'selected Heavens Tower row lost its canonical ingress identity')
assert(accessxi.nav_zone_search_waiting_from_zone == 239
    and accessxi.nav_zone_search_waiting_zone == 242,
    'Heavens Tower selection must wait for the observed 239-to-242 zone change')

accessxi.nav_active = false
assert(accessxi.poll_nav_zone_search() == false and #started_legs == 1,
    'Heavens Tower search resumed while the player was still in Windurst Walls')

current_player = T{ zone = 242, x = 0, z = -22.4, y = 0 }
now = 4000
assert(accessxi.poll_nav_zone_search() == true and #started_legs == 2,
    'Heavens Tower search did not resume after the observed zone-242 change')
assert(started_legs[2].point.zone == 242 and started_legs[2].reason == 'zone-search-resume',
    'zone-242 observation did not hand off to the representative in-zone target')

print('capital zone graph visibility checks ok')
