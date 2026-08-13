local module_path = assert(arg[1], 'recorded survey module path is required')
local graph_path = assert(arg[2], 'recorded survey graph path is required')
local reader_path = assert(arg[3], 'accessxi reader path is required')

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value end
function list_methods:clear() for i = #self, 1, -1 do self[i] = nil end end
function list_methods:contains(value)
    for _, item in ipairs(self) do
        if item == value then return true end
    end
    return false
end

function T(value)
    return setmetatable(value or {}, { __index = list_methods })
end

string.fmt = string.format
function string.contains(value, needle) return value:find(needle, 1, true) ~= nil end

accessxi = {
    nav_recorded_survey_path = graph_path,
    nav_recorded_survey_loaded = false,
    nav_recorded_survey_nodes = T({}),
    nav_route_last_reject_reason = '',
}

function nav_split_tsv(line)
    local parts = T({})
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do
        parts:append(part)
    end
    return parts
end

function nav_clean_field(value)
    return tostring(value or '')
end

function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end

function log_line(_) end

assert(loadfile(module_path))()

local recorded_ordelle_edge = {
    id = 947204730,
    from_zone = 102,
    from_code = 'z2u8',
    to_zone = 193,
}
local unmarked_ordelle_edge = {
    id = 913650298,
    from_zone = 102,
    from_code = 'z2u6',
    to_zone = 193,
}
assert(type(accessxi.nav_recorded_survey_zoneline_edge_priority) == 'function',
    'recorded survey does not expose its explicitly walked zone-line entrances')
assert(accessxi.nav_recorded_survey_zoneline_edge_priority(recorded_ordelle_edge)
        < accessxi.nav_recorded_survey_zoneline_edge_priority(unmarked_ordelle_edge),
    "the explicit recorded Ordelle's Caves entrance is not preferred")

local reader_file = assert(io.open(reader_path, 'rb'))
local reader_source = assert(reader_file:read('*a'))
reader_file:close()
local rank_start = assert(reader_source:find('function accessxi.nav_zoneline_edge_rank', 1, true))
local rank_end = assert(reader_source:find('function accessxi.nav_zoneline_approach_candidates', rank_start, true))
local rank_chunk, rank_reason = loadstring(reader_source:sub(rank_start, rank_end - 1), '@recorded-entrance-rank')
assert(rank_chunk, rank_reason)
accessxi.nav_zoneline_edges = T({
    T(recorded_ordelle_edge),
    T(unmarked_ordelle_edge),
})
function accessxi.nav_load_zoneline_graph() end
rank_chunk()
local selected_ordelle_path = accessxi.nav_zoneline_path(102, 193)
assert(selected_ordelle_path:len() == 1 and selected_ordelle_path[1].id == 947204730,
    "mission routing did not select the explicit recorded Ordelle's Caves entrance")

local current_route, current_route_required, current_collision_required =
    accessxi.nav_recorded_survey_route(
        { zone = 102, x = -434.488, z = 211.434, y = 8.005, name = 'current live start' },
        { zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' })
assert(current_route_required == false and current_collision_required == true
    and current_route:len() == 0,
    'ordinary La Theine destination reused the alternate 4412-to-3904 survey wall path')

local wall_route, wall_route_required, collision_required = accessxi.nav_recorded_survey_route(
    { zone = 102, x = -433.269, z = 224.810, y = 8.088, name = 'live wall position' },
    { zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' })
assert(wall_route_required == false and collision_required == true and wall_route:len() == 0,
    'recorded survey accepted the unsafe reverse 3924-to-3923 wall crossing instead of yielding to DAT terrain')

print('La Theine recorded-survey wall fallback checks passed')
