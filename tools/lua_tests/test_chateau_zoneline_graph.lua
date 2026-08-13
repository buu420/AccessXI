local addon_path = assert(arg[1], 'missing accessxi_reader.lua path')
local graph_path = assert(arg[2], 'missing zoneline graph path')

local source_file = assert(io.open(addon_path, 'rb'))
local source = source_file:read('*a')
source_file:close()

local function extract(first_marker, next_marker)
    local first = assert(source:find(first_marker, 1, true), 'missing source marker: ' .. first_marker)
    local last = assert(source:find(next_marker, first + #first_marker, true), 'missing end marker: ' .. next_marker)
    return source:sub(first, last - 1)
end

function string.startswith(value, prefix)
    return value:sub(1, #prefix) == prefix
end

function string.contains(value, needle)
    return value:find(needle, 1, true) ~= nil
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
    for index = #self, 1, -1 do
        self[index] = nil
    end
    return self
end
function list_methods:len()
    return #self
end

T = function(values)
    return setmetatable(values or {}, { __index = list_methods })
end

function nav_clean_field(value)
    return tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
end

function nav_split_tsv(line)
    local parts = T{}
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do
        parts:append(part)
    end
    return parts
end

function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end

function log_line(_text)
end

accessxi = {
    nav_zoneline_edges = T{},
    nav_zoneline_edges_loaded = false,
    nav_zoneline_graph_path = graph_path,
}

function accessxi.nav_zone_resource_name(_zone)
    return ''
end

local graph_source = extract(
    'function accessxi.nav_load_zoneline_graph()',
    'function accessxi.nav_zoneline_approach_candidates(point)')
local graph_chunk, graph_error = loadstring(graph_source)
assert(graph_chunk, graph_error)
graph_chunk()

function nav_load_points()
end

function nav_zone_id()
    return 231
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

function nav_point_source_rank(_point)
    return 0
end

local search_source = extract(
    'function accessxi.nav_zone_search_npc_results(query, player)',
    'function accessxi.nav_find_zone_search_npc(query, player)')
local search_chunk, search_error = loadstring(search_source)
assert(search_chunk, search_error)
search_chunk()

accessxi.nav_load_zoneline_graph()

-- Missing route coverage must affect availability, not erase an authoritative
-- destination from the screen-reader search results.
local complete_graph = accessxi.nav_zoneline_edges
local graph_without_chateau = T{}
for _, edge in ipairs(complete_graph) do
    if (tonumber(edge.from_zone) or 0) ~= 233 and (tonumber(edge.to_zone) or 0) ~= 233 then
        graph_without_chateau:append(edge)
    end
end
accessxi.nav_zoneline_edges = graph_without_chateau
accessxi.nav_points = T{
    T{
        zone = 233,
        name = 'Halver',
        x = 2.420,
        z = 1.966,
        y = 0.000,
        kind = 'npc',
        source = 'lsb-npc-list-all',
        confidence = 'untested',
        destination_id = 'npc:v1:233:17731591',
        raw_identity = 'lsb:npc_list:17731591',
    },
}
local results = accessxi.nav_zone_search_npc_results('Halver', T{ zone = 231, x = 0, z = 0, y = 0 })
assert(#results == 1, 'Halver must remain visible when Chateau route coverage is absent')
assert(results[1].zone == 233, 'visible Halver result must retain authoritative Chateau zone 233')
assert(results[1].zone_search_reachable == false, 'Halver must be marked unreachable when Chateau has no graph edge')

accessxi.nav_zoneline_edges = complete_graph
local path = accessxi.nav_zoneline_path(231, 233)
local summary_parts = {}
for _, edge in ipairs(path) do
    summary_parts[#summary_parts + 1] = ('%d->%d'):format(
        tonumber(edge.from_zone) or 0,
        tonumber(edge.to_zone) or 0)
end
local summary = table.concat(summary_parts, ',')

assert(path:len() == 1,
    ('Northern San d\'Oria to Chateau must be one direct graph edge; got %d edges: %s'):format(path:len(), summary))
assert(path[1].from_zone == 231 and path[1].to_zone == 233,
    ('direct Chateau edge must be 231->233; got %s'):format(summary))
for _, edge in ipairs(path) do
    assert(edge.from_zone ~= 100 and edge.to_zone ~= 100,
        ('Chateau route must not detour through West Ronfaure: %s'):format(summary))
    assert(edge.from_zone ~= 167 and edge.to_zone ~= 167,
        ('Chateau route must not detour through Bostaunieux Oubliette: %s'):format(summary))
end

print('Chateau direct zoneline graph behavior ok')
