local reader_path = assert(arg[1], 'accessxi_reader.lua path is required')

local function check(condition, message)
    if not condition then error(message or 'check failed', 2) end
end

local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local first = source:find('function accessxi.nav_collision_smoother_route', 1, true)
check(first ~= nil, 'reader has no collision-validated smoother-route selector')
local last = assert(source:find('function accessxi.nav_compute_mesh_endpoint_approach', first, true))
local block = source:sub(first, last - 1)

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear()
    for index = #self, 1, -1 do self[index] = nil end
end
T = function(value) return setmetatable(value or {}, { __index = list_methods }) end
string.fmt = string.format

accessxi = {
    nav_atan2 = function(y, x) return math.atan2(y, x) end,
    nav_normalize_angle = function(value)
        while value > math.pi do value = value - (2 * math.pi) end
        while value < -math.pi do value = value + (2 * math.pi) end
        return value
    end,
    nav_dat_collision_state = nil,
    escape_probe_log_text = function(value) return tostring(value or '') end,
}
local logs = {}
log_line = function(value) logs[#logs + 1] = value end
nav_clean_field = function(value) return tostring(value or '') end

local function point(x, z, y, source)
    return T({ zone = 244, name = 'Waypoint', x = x, z = z, y = y,
        kind = 'route', source = source or 'dat-collision' })
end

-- Exact 2026-08-13 Upper Jeuno collision route.  Its P9 hairpin turns more
-- than 104 degrees even though the installed mesh has a shorter smooth tail.
local collision = T({
    point(-105.223, 186.988, -0.021),
    point(-69.734, 133.722, -0.076),
    point(-69.526, 82.805, -0.069),
    point(-42.776, 41.305, -0.076),
    point(-16.026, 34.138, -0.067),
    point(11.974, -23.528, -0.100),
    point(9.391, -29.612, -0.060),
    point(11.441, -32.328, -0.973),
    point(23.391, -36.528, -1.156),
    point(16.891, -46.112, -0.977),
    point(4.763, -54.883, 1.179),
})
local mesh = T({
    point(-105.223, 186.988, -0.023, 'navmesh'),
    point(-78.359, 128.997, 0, 'navmesh'),
    point(-71.559, 111.797, 0, 'navmesh'),
    point(-64.359, 88.597, 0, 'navmesh'),
    point(-50.759, 59.797, -0.2, 'navmesh'),
    point(-33.559, 30.997, -1, 'navmesh'),
    point(-32.759, 30.597, -1, 'navmesh'),
    point(-22.759, 30.997, 0, 'navmesh'),
    point(-18.359, 25.797, 0, 'navmesh'),
    point(10.841, -21.803, -0.2, 'navmesh'),
    point(12.441, -29.003, 0, 'navmesh'),
    point(13.641, -31.003, -1.2, 'navmesh'),
    point(14.441, -31.803, -1.2, 'navmesh'),
    point(18.041, -35.003, -1.2, 'navmesh'),
    point(18.841, -36.603, -1.2, 'navmesh'),
    point(18.441, -43.003, -1.2, 'navmesh'),
    point(4.763, -54.883, 1.107, 'navmesh'),
    point(4.763, -54.883, -1.796, 'navmesh'),
})
local player = point(-105.223, 186.988, 0)
local destination = point(4.763, -54.883, -1.796)
destination.name = 'Lower Jeuno zone line'

local mesh_calls = 0
nav_compute_mesh_route = function(start_point, end_point, quiet)
    check(quiet == true, 'smoother-route probing must be quiet')
    mesh_calls = mesh_calls + 1
    if start_point == player and end_point == destination then
        return mesh
    end
    -- The chosen P6 -> mesh-P11 bridge is a direct installed-navmesh leg.
    if math.abs(start_point.x - 11.974) < 0.01
        and math.abs(end_point.x - 12.441) < 0.01
        and math.abs(end_point.z + 29.003) < 0.01 then
        return T({ point(start_point.x, start_point.z, start_point.y, 'navmesh'),
            point(end_point.x, end_point.z, end_point.y, 'navmesh') })
    end
    return T({})
end

local validated = nil
accessxi.nav_dat_collision_state = {
    validate_direct_route = function(_, candidate)
        validated = candidate
        return true, ''
    end,
}

local chunk, reason = loadstring(block, '@collision-route-hybrid')
check(chunk ~= nil, reason)
chunk()

local selected = accessxi.nav_collision_smoother_route(player, destination, collision)
check(selected ~= collision and selected:len() > collision:len(),
    'the exact Upper Jeuno hairpin did not select its smoother validated hybrid')
check(mesh_calls == 2 and validated == selected,
    'the selector must make one full-path query, one direct bridge query, and validate the final hybrid')
for _, waypoint in ipairs(selected) do
    check(waypoint.source == 'dat-collision',
        'a collision-validated hybrid must remain precise DAT-collision guidance')
    check(math.abs(waypoint.x - 23.391) > 0.01,
        'the smoother hybrid retained the unnecessary 104-degree DAT hairpin')
end
check(math.abs(selected[6].x - 11.974) < 0.01
    and math.abs(selected[7].x - 12.441) < 0.01,
    'the hybrid did not reconnect at the exact direct P6-to-mesh-P11 bridge')
check(math.abs(selected[#selected].y - 1.107) < 0.01,
    'the hybrid replaced its projected walkable endpoint with a same-X/Z raw-height duplicate')
check(#logs == 1 and logs[1]:find('smoother corridor', 1, true) ~= nil,
    'the selected hybrid must leave one concrete route provenance record')
check(logs[1]:find('collision_cumulative_turn=424.6', 1, true) ~= nil
    and logs[1]:find('hybrid_cumulative_turn=319.2', 1, true) ~= nil,
    'the Upper Jeuno hybrid did not prove its cumulative curvature reduction')

-- If even one final segment fails the direct DAT capsule sweep, the native
-- collision route remains authoritative.
mesh_calls = 0
validated = nil
accessxi.nav_dat_collision_state.validate_direct_route = function(_, candidate)
    validated = candidate
    return false, 'Collision candidate segment 7 is blocked.'
end
local rejected = accessxi.nav_collision_smoother_route(player, destination, collision)
check(rejected == collision and validated ~= nil,
    'a blocked mesh hybrid replaced the authoritative collision route')

-- A shorter route with a low individual turn can still weave more overall.
-- Its many small side-to-side corrections must fail the cumulative-turn gate.
mesh_calls = 0
validated = nil
local weaving = T({})
for index = 1, 16 do weaving:append(mesh[index]) end
for _, coordinates in ipairs({
    { 16.862398, -44.638997 }, { 14.890352, -45.822003 },
    { 13.442898, -47.608997 }, { 11.470852, -48.792003 },
    { 10.023398, -50.578997 }, { 8.051352, -51.762003 },
    { 6.603898, -53.548997 },
}) do
    weaving:append(point(coordinates[1], coordinates[2], -1.2, 'navmesh'))
end
weaving:append(mesh[17])
nav_compute_mesh_route = function(start_point, end_point, quiet)
    mesh_calls = mesh_calls + 1
    if start_point == player and end_point == destination then return weaving end
    return T({ point(start_point.x, start_point.z, start_point.y, 'navmesh'),
        point(end_point.x, end_point.z, end_point.y, 'navmesh') })
end
accessxi.nav_dat_collision_state.validate_direct_route = function(_, candidate)
    validated = candidate
    return true, ''
end
local weave_rejected = accessxi.nav_collision_smoother_route(player, destination, collision)
check(weave_rejected == collision and validated == nil,
    'a shorter low-maximum-turn route with greater cumulative curvature was selected')

-- Ordinary routes without a severe bend must not pay for another synchronous
-- mesh query or a set of capsule sweeps.
mesh_calls = 0
validated = nil
local straight = T({ point(0, 0, 0), point(10, 0, 0), point(20, 0, 0) })
local unchanged = accessxi.nav_collision_smoother_route(straight[1], straight[3], straight)
check(unchanged == straight and mesh_calls == 0 and validated == nil,
    'a normal collision route paid for unnecessary smoother-corridor probing')

print('collision route hybrid checks passed')
