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

local table_methods = {}
function table_methods:len()
    return #self
end

T = setmetatable({}, {
    __call = function (_, value)
        return setmetatable(value or {}, { __index = table_methods })
    end,
})

accessxi = {}

function nav_clean_field(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
end

function nav_load_points()
end

function nav_zone_id()
    return 230
end

function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end

function accessxi.nav_search_text(value)
    return nav_clean_field(value):lower():gsub('[^%w%s]', ' '):gsub('%s+', ' ')
end

function accessxi.nav_point_effective_kind(point)
    return nav_clean_field(point and point.kind or ''):lower()
end

function accessxi.nav_point_matches_search(point, query)
    return accessxi.nav_search_text(point and point.name or ''):find(accessxi.nav_search_text(query), 1, true) ~= nil
end

function accessxi.nav_copy_point(point)
    local copy = T{}
    for key, value in pairs(point or {}) do
        copy[key] = value
    end
    return copy
end

function accessxi.nav_zoneline_path(_from_zone, _to_zone)
    return T{}
end

local confidence_source = extract('local function nav_point_confidence(point)', 'local function nav_write_route_evidence')
confidence_source = confidence_source:gsub('local function nav_point_confidence', 'function nav_point_confidence', 1)
confidence_source = confidence_source:gsub('local function nav_point_confidence_rank', 'function nav_point_confidence_rank', 1)
local confidence_chunk, confidence_error = loadstring(confidence_source)
assert(confidence_chunk, confidence_error)
confidence_chunk()

local rank_source = extract('local function nav_point_source_rank(point)', 'accessxi.nav_menu_static_key = function')
rank_source = rank_source:gsub('local function nav_point_source_rank', 'function nav_point_source_rank', 1)
local rank_chunk, rank_error = loadstring(rank_source)
assert(rank_chunk, rank_error)
rank_chunk()

local menu_key_source = extract('accessxi.nav_menu_static_key = function (point)', 'accessxi.nav_search_text = function')
local menu_key_chunk, menu_key_error = loadstring(menu_key_source)
assert(menu_key_chunk, menu_key_error)
menu_key_chunk()

local search_source = extract('function accessxi.nav_zone_search_npc_results(query, player)', 'function accessxi.nav_find_zone_search_npc(query, player)')
local search_chunk, search_error = loadstring(search_source)
assert(search_chunk, search_error)
search_chunk()

local function point(zone, name, x, z, y, source_name, confidence, destination_id, raw_identity)
    return T{
        zone = zone,
        name = name,
        x = x,
        z = z,
        y = y,
        kind = 'npc',
        source = source_name,
        confidence = confidence or '',
        section = '',
        destination_id = destination_id or '',
        raw_identity = raw_identity or '',
    }
end

local function results(points, query, player)
    accessxi.nav_points = T(points)
    return accessxi.nav_zone_search_npc_results(query, player or T{ zone = 230, x = 0, z = 0, y = 0 })
end

local maat = results({
    point(243, 'Maat', 10.877, 119.468, 3.101, 'lsb-npc-list', ''),
    point(243, 'Maat', 10.877, 119.468, 3.101, 'lsb-npc-list-all', 'untested', 'npc:v1:243:17772593', 'lsb:npc_list:17772593'),
    point(243, 'Maat', 10.877, 119.468, 3.101, 'lsb-npc-list-all', 'untested', 'npc:v1:243:17772594', 'lsb:npc_list:17772594'),
}, 'Maat')
assert(#maat == 1, 'exact-coordinate Maat identities should project to one zone-search row')
assert(maat[1].source == 'lsb-npc-list', 'deterministic Maat representative should be the better-ranked legacy row')
assert(#accessxi.nav_points == 3, 'presentation dedup must not delete Maat identity rows from nav_points')

local telepoint = results({
    point(102, 'Telepoint', 420.000, 20.200, 19.100, 'live-axi-pos-lathine-holla-gate-crystal-20260629', 'observed'),
    point(102, 'Telepoint', 420.000, 20.000, 19.104, 'lsb-npc-list-all', 'untested', 'npc:v1:102:17195618', 'lsb:npc_list:17195618'),
}, 'Telepoint', T{ zone = 102, x = 400, z = 20, y = 19 })
assert(#telepoint == 1, 'near-identical Telepoint rows should project to one zone-search row')
assert(telepoint[1].source == 'live-axi-pos-lathine-holla-gate-crystal-20260629', 'better-ranked observed Telepoint should be presented')

local agent_moogles = results({
    point(230, 'Agent Moogle', -62.675, -18.101, 1.500, 'lsb-npc-list-all', 'untested', 'npc:v1:230:17719759', 'lsb:npc_list:17719759'),
    point(230, 'Agent Moogle', -61.991, -17.515, 1.500, 'lsb-npc-list-all', 'untested', 'npc:v1:230:17719756', 'lsb:npc_list:17719756'),
}, 'Agent Moogle')
assert(#agent_moogles == 2, 'same-name Agent Moogles more than 0.5 yalm apart must remain separate')

local cross_zone = results({
    point(230, 'Gate Guard', 10, 10, 0, 'manual', 'observed'),
    point(231, 'Gate Guard', 10, 10, 0, 'manual', 'observed'),
}, 'Gate Guard')
assert(#cross_zone == 2, 'same-name points in different zones must remain separate')

local different_names = results({
    point(230, 'Target Alpha', 10, 10, 0, 'manual', 'observed'),
    point(230, 'Target Beta', 10, 10, 0, 'manual', 'observed'),
}, 'Target')
assert(#different_names == 2, 'different names at the same point must remain separate')

local stale_upper_jeuno = T{
    zone = 244,
    name = "Ru'Lude Gardens zone line",
    x = 25.136,
    z = -41.313,
    y = -3.000,
    kind = 'area',
    source = 'bg-wiki-lsb-npc-list',
    confidence = '',
}
local exact_upper_jeuno = T{
    zone = 244,
    name = "Ru'Lude Gardens zone line",
    x = 46.000,
    z = -30.915,
    y = -6.542,
    kind = 'area',
    source = 'lsb-zoneline-all',
    confidence = 'untested',
    destination_id = 'area:v1:244:879965818',
    raw_identity = 'lsb:zonelines:879965818',
}
assert(nav_point_source_rank(exact_upper_jeuno) < nav_point_source_rank(stale_upper_jeuno),
    'an exact immutable zoneline identity must beat an equally untested legacy estimate')

local observed_upper_jeuno = T{
    zone = stale_upper_jeuno.zone,
    name = stale_upper_jeuno.name,
    x = stale_upper_jeuno.x,
    z = stale_upper_jeuno.z,
    y = stale_upper_jeuno.y,
    kind = stale_upper_jeuno.kind,
    source = stale_upper_jeuno.source,
    confidence = 'observed',
}
assert(nav_point_source_rank(observed_upper_jeuno) < nav_point_source_rank(exact_upper_jeuno),
    'verified live evidence must still beat an untested generated zoneline')

local function select_upper_jeuno(player)
    local selected = nil
    for _, candidate in ipairs({ stale_upper_jeuno, exact_upper_jeuno }) do
        candidate.distance = nav_distance(player, candidate)
        if accessxi.nav_static_destination_is_better(candidate, selected) then
            selected = candidate
        end
    end
    return selected
end

local near_stale = select_upper_jeuno(T{ x = 25.136, z = -41.313 })
assert(near_stale.destination_id == 'area:v1:244:879965818',
    'Upper Jeuno selected the stale Ru\'Lude estimate when the player was near it')
local near_exact = select_upper_jeuno(T{ x = 46.000, z = -30.915 })
assert(near_exact.destination_id == 'area:v1:244:879965818',
    'Upper Jeuno exact Ru\'Lude identity changed with player position')

print('nav zone-search presentation dedup behavior ok')
