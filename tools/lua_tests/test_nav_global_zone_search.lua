local addon_path = assert(arg[1], 'expected accessxi_reader.lua path')
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

local current_player = T{ zone = 231, x = 25, z = 80, y = -2 }
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
    nav_zoneline_edges_loaded = true,
    nav_zoneline_edges = T{
        T{
            id = 812528762,
            from_zone = 167,
            from_name = 'Bostaunieux Oubliette',
            from_x = 99.973,
            from_z = 75.035,
            from_y = -27.768,
            to_zone = 233,
            to_name = "Chateau d'Oraguille",
            to_x = 14.872,
            to_z = 24.002,
            to_y = 8.918,
            source = 'lsb-zonelines',
            confidence = 'untested',
        },
        T{
            id = 231233001,
            from_zone = 231,
            from_name = "Northern San d'Oria",
            from_x = 0,
            from_z = 110,
            from_y = -2,
            to_zone = 233,
            to_name = "Chateau d'Oraguille",
            to_x = 0,
            to_z = -13,
            to_y = 0,
            source = 'lsb-scripted-trigger',
            confidence = 'proven',
        },
    },
    nav_menu_items = T{},
    nav_menu_index = 1,
    nav_menu_dirty_categories = {},
    nav_menu_open = false,
    nav_menu_poll_key = 0,
    nav_menu_poll_tick = 0,
    nav_menu_open_tick = 0,
    nav_menu_search_query = "Chateau d'Oraguille",
    nav_zone_search_target = nil,
    nav_zone_search_query = '',
    nav_zone_search_waiting_zone = 0,
    nav_zone_search_waiting_from_zone = 0,
    nav_zone_search_last_replan_tick = 0,
    nav_active = false,
}

function accessxi.nav_load_zoneline_graph()
end

function accessxi.nav_zone_resource_name(zone)
    local names = {
        [167] = 'Bostaunieux Oubliette',
        [231] = "Northern San d'Oria",
        [233] = "Chateau d'Oraguille",
    }
    return names[tonumber(zone) or 0] or ''
end

function accessxi.nav_graph_zone_name(zone)
    return accessxi.nav_zone_resource_name(zone)
end

function accessxi.nav_zoneline_out_edges(zone)
    local edges = T{}
    for _, edge in ipairs(accessxi.nav_zoneline_edges) do
        if (tonumber(edge.from_zone) or 0) == (tonumber(zone) or 0) then
            edges:append(edge)
        end
    end
    table.sort(edges, function(a, b)
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    return edges
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
    started_legs[#started_legs + 1] = { point = accessxi.nav_copy_point(point), reason = reason }
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

local search_text_source = extract('accessxi.nav_search_text = function (value)', 'local function nav_collect_menu_items')
assert(loadstring(search_text_source, '@reader-search-text'))()

local confidence_source = extract('local function nav_point_confidence(point)', 'local function nav_write_route_evidence')
confidence_source = confidence_source:gsub('local function nav_point_confidence', 'function nav_point_confidence', 1)
confidence_source = confidence_source:gsub('local function nav_point_confidence_rank', 'function nav_point_confidence_rank', 1)
assert(loadstring(confidence_source, '@reader-confidence'))()

local rank_source = extract('local function nav_point_source_rank(point)', 'accessxi.nav_menu_static_key = function')
rank_source = rank_source:gsub('local function nav_point_source_rank', 'function nav_point_source_rank', 1)
assert(loadstring(rank_source, '@reader-source-rank'))()

local edge_rank_source = extract('function accessxi.nav_zoneline_edge_rank(edge, player)', 'function accessxi.nav_zoneline_out_edges(zone, player)')
assert(loadstring(edge_rank_source, '@reader-edge-rank'))()

local path_source = extract('function accessxi.nav_zoneline_path(from_zone, to_zone, final_edge_id)', 'function accessxi.nav_zoneline_approach_candidates')
assert(loadstring(path_source, '@reader-zone-path'))()

local results_source = extract('function accessxi.nav_zone_search_npc_results(query, player)', 'function accessxi.nav_find_zone_search_npc(query, player)')
assert(loadstring(results_source, '@reader-global-zone-results'))()

local next_leg_source = extract('function accessxi.nav_zone_search_start_next_leg(reason)', 'function accessxi.nav_zone_search_start(query)')
assert(loadstring(next_leg_source, '@reader-zone-next-leg'))()

local poll_source = extract('function accessxi.poll_nav_zone_search()', 'local function nav_focus_target_position()')
assert(loadstring(poll_source, '@reader-zone-poll'))()

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

-- No mission, rank, nation, access, or NPC state exists in this fixture.
local results = accessxi.nav_zone_search_npc_results("Chateau d'Oraguille", current_player)
assert(#results == 1, "exact global zone-name search should expose one Chateau d'Oraguille result")
local chateau = results[1]
assert(chateau.zone == 233 and chateau.name == "Chateau d'Oraguille",
    'zone search returned the wrong canonical zone')
assert(chateau.zone_search_result == true and chateau.zone_search_zone_result == true,
    'canonical zone row must be selectable by the existing zone-search menu branch')
assert(chateau.kind == 'area', 'canonical zone result should use the navigable area kind')
assert(chateau.zone_search_canonical_edge_id == 231233001
    and chateau.zone_search_canonical_from_zone == 231,
    'Chateau must pin the direct Northern San dOria ingress, not Bostaunieux')
assert(chateau.x == 0 and chateau.z == -13 and chateau.y == 0,
    'zone result should target the representative landing inside zone 233')

local refresh_environment = setmetatable({
    accessxi = accessxi,
    T = T,
    nav_clean_field = nav_clean_field,
    nav_collect_menu_items = function()
        return {}
    end,
    nav_cached_player_position = nav_cached_player_position,
}, { __index = _G })
local refresh_source = extract('local function nav_refresh_search_results()', 'local function nav_build_menu_items()')
local refresh_chunk = assert(loadstring(refresh_source .. '\nreturn nav_refresh_search_results', '@reader-main-nav-search'))
setfenv(refresh_chunk, refresh_environment)
local nav_refresh_search_results = assert(refresh_chunk())
accessxi.nav_menu_search_query = "Chateau d'Oraguille"
accessxi.nav_menu_search_results = T{}
assert(nav_refresh_search_results() == 1,
    'main navigation Search Results should include an exact global zone-name match')
assert(accessxi.nav_menu_search_results[1].zone == 233
    and accessxi.nav_menu_search_results[1].zone_search_result == true,
    'main navigation Search Results did not expose the selectable Chateau zone row')

accessxi.nav_menu_items = T{ chateau }
nav_menu_start_route()
assert(accessxi.nav_zone_search_target ~= nil and accessxi.nav_zone_search_target.zone == 233,
    'selecting the zone row did not retain zone 233 as the final target')
assert(#started_legs == 1, 'selecting the zone row should start exactly one cross-zone leg')
local gate_leg = started_legs[1].point
assert(gate_leg.zone == 231 and gate_leg.to_zone == 233,
    'selected Chateau row did not route from Northern San dOria to zone 233')
assert(gate_leg.x == 0 and gate_leg.z == 110 and gate_leg.y == -2,
    'selected Chateau row did not route to the real castle gate trigger')
assert(gate_leg.source:find('231233001', 1, true) ~= nil,
    'selected Chateau row fell back to the Bostaunieux edge')
assert(accessxi.nav_zone_search_waiting_from_zone == 231
    and accessxi.nav_zone_search_waiting_zone == 233,
    'selected Chateau row must wait for the real 231-to-233 zone change')

accessxi.nav_active = false
assert(accessxi.poll_nav_zone_search() == false and #started_legs == 1,
    'zone search resumed before the player actually entered zone 233')

current_player = T{ zone = 233, x = 0, z = -13, y = 0 }
now = 4000
assert(accessxi.poll_nav_zone_search() == true and #started_legs == 2,
    'zone search did not resume after the authoritative zone-233 observation')
assert(started_legs[2].point.zone == 233 and started_legs[2].reason == 'zone-search-resume',
    'zone-233 observation did not hand off to the representative in-zone target')

print('global zone-name search and selection behavior ok')
