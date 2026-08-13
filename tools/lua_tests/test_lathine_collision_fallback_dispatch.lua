local reader_path = assert(arg[1], 'accessxi_reader.lua path is required')
local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local start_marker = 'function accessxi.nav_compute_route_with_zoneline_approach(player, point)'
local end_marker = 'function accessxi.nav_route_recorder_display_name(name, pos)'
local first = assert(source:find(start_marker, 1, true), 'route dispatcher is missing')
local last = assert(source:find(end_marker, first + #start_marker, true), 'route dispatcher end is missing')
local block = source:sub(first, last - 1)

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end

string.fmt = string.format

accessxi = { nav_route_last_reject_reason = '' }
local collision_calls = 0
local mesh_calls = 0

function accessxi.nav_recorded_survey_route(_, _)
    return T({}), false, true
end
function accessxi.nav_lathine_recorded_corridor_route()
    error('collision-blocked survey route fell into a recorded corridor')
end
function accessxi.nav_lathine_recorded_ravine_escape_route()
    error('collision-blocked survey route fell into a recorded ravine route')
end
function accessxi.nav_lathine_recorded_ravine_escape_required()
    error('collision-blocked survey route checked a recorded ravine route')
end
function accessxi.nav_lathine_lower_ravine_recovery_route()
    error('collision-blocked survey route fell into a recorded recovery route')
end
function accessxi.nav_route_override_points()
    return T({})
end
local nearby_direct = false
function accessxi.nav_nearby_zoneline_direct_route_allowed()
    return nearby_direct
end
function accessxi.nav_dat_collision_route(player, point)
    collision_calls = collision_calls + 1
    return T({
        { zone = 102, x = -433.000, z = 224.810, y = 7.981 },
        { zone = 102, x = -421.000, z = 217.667, y = 8.115 },
    }), 'ready', ''
end
function nav_compute_mesh_route(player, point)
    mesh_calls = mesh_calls + 1
    assert(player.x == -433.269, 'navmesh received the wrong route start')
    if point.name == "Ordelle's Caves paired landing" then
        return T({
            { zone = 102, x = -433.269, z = 224.810, y = 8.088, source = 'navmesh' },
            { zone = 102, x = -345.878, z = 376.292, y = 2.736, source = 'navmesh' },
            { zone = 102, x = -272.118, z = 98.859, y = 21.715, source = 'navmesh' },
        })
    end
    assert(point.name == 'Galaihaurat', 'navmesh received the wrong route request')
    return T({
        { zone = 102, x = -433.269, z = 224.810, y = 8.088, source = 'navmesh' },
        { zone = 102, x = -439.600, z = 217.600, y = 5.550, source = 'navmesh' },
        { zone = 102, x = -450.800, z = 206.400, y = 2.350, source = 'navmesh' },
    })
end
function accessxi.nav_point_is_zoneline(point) return point ~= nil and point.zoneline == true end
function accessxi.nav_zoneline_approach_candidates(point)
    assert(point ~= nil and point.name == "Ordelle's Caves zone line",
        'the wrong zoneline requested paired approaches')
    return T({
        {
            zone = 102, x = -272.118, z = 98.859, y = 21.715,
            name = "Ordelle's Caves paired landing",
        },
    })
end
function accessxi.nav_append_final_zoneline_point(points, point)
    points:append({
        zone = point.zone, x = point.x, z = point.z, y = point.y,
        name = point.name, to_zone = point.to_zone,
    })
end
function accessxi.nav_dat_collision_zoneline_approach()
    error('ready DAT route incorrectly requested a zoneline approach')
end
function accessxi.escape_probe_log_text(value) return tostring(value or '') end

function nav_clean_field(value) return tostring(value or '') end
function nav_distance() return 100 end
function log_line(_) end

local chunk, reason = loadstring(block, '@lathine-collision-fallback-dispatch')
assert(chunk, reason)
chunk()

local route, route_reason = accessxi.nav_compute_route_with_zoneline_approach(
    { zone = 102, x = -433.269, z = 224.810, y = 8.088 },
    { zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' })
assert(route_reason == nil and route:len() == 3 and mesh_calls == 1 and collision_calls == 0,
    'La Theine objective did not use the immediate full-zone navmesh before terrain construction')
for _, waypoint in ipairs(route) do
    assert(waypoint.route_override_id == 'lathine-navmesh',
        'La Theine navmesh route was not marked for segment-bounded steering')
end

-- The live Ruillont route starts with the proven La Theine -> Ordelle's Caves
-- transition.  That zoneline has an immediate path in the already-loaded
-- La_Theine_Plateau.nav.  It must not bypass that mesh and spend 91 seconds
-- building DAT terrain before failing with no connected corridor.
local ordelle_line = {
    zone = 102,
    x = -276.649,
    z = 99.618,
    y = 20.594,
    name = "Ordelle's Caves zone line",
    to_zone = 193,
    zoneline = true,
}
local ordelle_route, ordelle_reason = accessxi.nav_compute_route_with_zoneline_approach(
    { zone = 102, x = -433.269, z = 224.810, y = 8.088 },
    ordelle_line)
assert(ordelle_reason == nil and ordelle_route:len() == 4
        and mesh_calls == 2 and collision_calls == 0,
    "Ruillont's La Theine zoneline invoked terrain mapping instead of the loaded navmesh")
for _, waypoint in ipairs(ordelle_route) do
    assert(waypoint.route_override_id == 'lathine-navmesh',
        'La Theine zoneline route was not marked for locally safe steering')
end

-- A player already beside a clear transition should still receive direct
-- trigger guidance.  Do not replace that established fast path with a mesh
-- query just because the destination is in La Theine.
nearby_direct = true
local mesh_before_nearby = mesh_calls
local collision_before_nearby = collision_calls
local nearby_route = accessxi.nav_compute_route_with_zoneline_approach(
    { zone = 102, x = -276.800, z = 99.700, y = 20.600 },
    {
        zone = 102, x = -276.649, z = 99.618, y = 20.594,
        name = "Nearby Ordelle's Caves zone line", to_zone = 193,
        zoneline = true,
    })
assert(nearby_route:len() == 0 and mesh_calls == mesh_before_nearby
        and collision_calls == collision_before_nearby,
    'a nearby clear La Theine zoneline performed unnecessary path construction')
nearby_direct = false

-- If the installed mesh cannot reach a La Theine zoneline, fail immediately.
-- Never fall through to the slow native terrain builder.
function nav_compute_mesh_route(_, _) return T({}) end
local collision_before_failure = collision_calls
local missing_route = accessxi.nav_compute_route_with_zoneline_approach(
    { zone = 102, x = -433.269, z = 224.810, y = 8.088 },
    ordelle_line)
assert(missing_route:len() == 0 and collision_calls == collision_before_failure,
    'an unreachable La Theine zoneline fell through to native terrain mapping')

print('La Theine fast navmesh dispatch checks passed')
