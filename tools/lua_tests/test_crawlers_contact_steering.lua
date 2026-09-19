local reader = assert(arg[1], 'reader path is required')
local file = assert(io.open(reader, 'rb'))
local source = file:read('*a')
file:close()
local function block(first, last)
    local at = assert(source:find(first, 1, true))
    return source:sub(at, assert(source:find(last, at + #first, true)) - 1)
end
local methods = {}
function methods:len() return #self end
function methods:append(value) self[#self + 1] = value end
T = function(value) return setmetatable(value or {}, { __index = methods }) end
string.fmt = string.format
function string.startswith(value, prefix) return value:sub(1, #prefix) == prefix end
function nav_distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2)
end
function tick() return 1000 end
function log_line(_) end
accessxi = {}
function accessxi.nav_route_points_override_id(points) return points[1].source end
function accessxi.nav_route_points_are_collision(points) return points[1].source == 'dat-collision' end
function accessxi.nav_route_precise_override_active(_, points)
    return accessxi.nav_route_points_are_collision(points)
end
function accessxi.nav_precise_route_return_clear()
    accessxi.nav_precise_return_target = nil
    accessxi.nav_precise_return_points = nil
    accessxi.nav_precise_return_segment = 0
end
assert(loadstring(table.concat({
    block('function accessxi.nav_first_route_index', 'function accessxi.nav_distance_to_segment'),
    block('function accessxi.nav_project_to_segment', 'function accessxi.nav_route_live_match'),
    block('function accessxi.nav_route_live_match', 'function accessxi.nav_route_target_from_match'),
    block('function accessxi.nav_route_target_from_match', 'function accessxi.nav_precise_route_waypoint_passed'),
    block('function accessxi.nav_precise_route_track_index', 'function accessxi.nav_distance_to_route'),
    block('function accessxi.nav_precise_steering_target', 'function accessxi.nav_precise_guidance_cache_clear'),
}, '\n'), '@crawlers-contact-steering'))()

-- Exact terrain route across the reported entrance hill, converted to game Y.
local points = T{}
for _, p in ipairs({
    {221.966, 34.330, -53.534}, {218.966, 34.713, -59.221},
    {218.346, 35.763, -60.183}, {217.599, 36.748, -60.334},
    {217.299, 36.739, -60.034}, {208.758, 38.348, -58.742},
}) do
    points:append(T{ zone = 197, x = p[1], y = -p[2], z = p[3], source = 'dat-collision' })
end
accessxi.nav_route_points = points
accessxi.nav_route_point_index = 3
accessxi.nav_precise_route_track_tick = 0
assert(accessxi.nav_precise_route_track_index(points[2], 1000) == false
    and accessxi.nav_route_point_index == 3,
    'skipped the uphill corner while the player was still below it')
local target = accessxi.nav_precise_steering_target(points[2], points, 3, 9)
assert(target == points[3], 'steering skipped the next contact-settled corner')
for index = 3, 5 do
    assert(accessxi.nav_precise_route_track_index(points[index], 1000 + index * 100) == true
        and accessxi.nav_route_point_index == index + 1,
        'failed to advance after reaching a contact-settled corner')
end
-- Walking through the corner need not hit its exact centre. A player already
-- on the outgoing segment, 0.3 yalm to its side, should retain forward progress.
local dx, dz = points[4].x - points[3].x, points[4].z - points[3].z
local length = math.sqrt(dx * dx + dz * dz)
local walked_past = T{ zone = 197,
    x = points[3].x + dx * 0.75 - dz / length * 0.3,
    z = points[3].z + dz * 0.75 + dx / length * 0.3,
    y = points[3].y + (points[4].y - points[3].y) * 0.75 }
accessxi.nav_route_point_index = 3
assert(accessxi.nav_precise_route_track_index(walked_past, 1800)
    and accessxi.nav_route_point_index == 4, 'lost forward progress slightly off the cave corner')
local restart = T{ points[2], points[3], points[4], points[5] }
assert(accessxi.nav_first_route_index(points[2], restart, points[5]) == 2,
    'skipped the first uphill corner when installing a fresh route')

-- A nearby later corridor must not steal progress from the current segment.
local alias = T{ points[1], points[2], points[3], points[4], points[5], points[6],
    T{ zone = 197, x = points[2].x + 0.1, y = points[2].y, z = points[2].z, source = 'dat-collision' },
    T{ zone = 197, x = points[2].x + 0.2, y = points[2].y, z = points[2].z, source = 'dat-collision' } }
accessxi.nav_route_points = alias
accessxi.nav_route_point_index = 3
assert(accessxi.nav_precise_route_track_index(alias[7], 2000) == false
    and accessxi.nav_route_point_index == 3, 'a later corridor stole cave route progress')

-- Ordinary long corners in other zones retain their existing arrival tolerance.
local ordinary = T{
    T{ zone = 244, x = 0, y = 0, z = 0, source = 'dat-collision' },
    T{ zone = 244, x = 10, y = 0, z = 0, source = 'dat-collision' },
    T{ zone = 244, x = 10, y = 0, z = 10, source = 'dat-collision' },
}
accessxi.nav_route_points = ordinary
accessxi.nav_route_point_index = 2
assert(accessxi.nav_precise_route_track_index(T{ zone = 244, x = 9, y = 0, z = 0 }, 3000)
    and accessxi.nav_route_point_index == 3, 'changed ordinary waypoint arrival')
print('Crawler\'s Nest contact steering tests passed')
