local reader_path = assert(arg[1], 'accessxi_reader.lua path is required')
local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local player_position_start = assert(source:find('local function nav_player_position()', 1, true))
local player_position_end = assert(source:find('local function nav_cached_player_position()', player_position_start, true))
local player_position_source = source:sub(player_position_start, player_position_end - 1)
assert(player_position_source:find('raw.Heading', 1, true),
    'player navigation still reads animation/local-position yaw instead of entity heading')
assert(player_position_source:find('GetHeading', 1, true),
    'player navigation heading has no entity-manager fallback')

local function block(first_marker, last_marker)
    local first = assert(source:find(first_marker, 1, true), 'missing ' .. first_marker)
    local last = assert(source:find(last_marker, first + #first_marker, true), 'missing ' .. last_marker)
    return source:sub(first, last - 1)
end

local selected = table.concat({
    block('function accessxi.nav_normalize_angle', 'function accessxi.nav_atan2'),
    block('function accessxi.nav_atan2', 'function accessxi.nav_capitalize'),
    block('function accessxi.nav_heading_to', 'function accessxi.nav_relative_turn_phrase'),
    block('function accessxi.nav_beacon_direction_delta', 'function accessxi.nav_beacon_file_for_delta'),
    block('function accessxi.nav_beacon_file_for_delta', 'function accessxi.nav_wall_distance'),
}, '\n')

local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
function string.fmt(self, ...) return string.format(self, ...) end

accessxi = {
    nav_beacon_dir = 'beacon',
    nav_beacon_route_acquired = true,
    nav_beacon_motion_x = nil,
    nav_beacon_motion_z = nil,
}

function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end

local chunk, reason = loadstring(selected, '@nav-beacon-route-turn-cue')
assert(chunk, reason)
chunk()

local straight = T({
    T({ x = 0, z = 0, y = 0 }),
    T({ x = 10, z = 0, y = 0 }),
    T({ x = 20, z = 0, y = 0 }),
})
local player = T({ x = 6, z = 0, y = 0, yaw = 1.4 })
local target = T({ x = 8, z = 0, y = 0, source = 'dat-collision-segment-steering' })

local delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
local _, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta) < 0.001 and prefix == 'front' and bin == 6,
    'a straight route rotated the beacon with the character instead of keeping it centered')

player.yaw = -1.1
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
_, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta) < 0.001 and prefix == 'front' and bin == 6,
    'changing character yaw rotated a centered straight-route beacon')

accessxi.nav_beacon_route_acquired = false
player.yaw = math.pi / 2
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta) > 1,
    'a newly started route did not provide initial facing guidance')
player.yaw = 0
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta) < 0.001 and accessxi.nav_beacon_route_acquired == true,
    'facing the route did not acquire and center the beacon')
player.yaw = -1.3
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta) < 0.001,
    'raw character yaw resumed rotating the beacon after route acquisition')

local left = T({
    T({ x = 0, z = 0, y = 0 }),
    T({ x = 10, z = 0, y = 0 }),
    T({ x = 10, z = 10, y = 0 }),
})
player = T({ x = 4, z = 0, y = 0, yaw = 0.7 })
target = T({ x = 8, z = 0, y = 0, source = 'dat-collision-segment-steering' })
accessxi.nav_beacon_motion_x = player.x
accessxi.nav_beacon_motion_z = player.z
delta = accessxi.nav_beacon_direction_delta(player, target, left, 2, true)
_, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta) < 0.001 and prefix == 'front' and bin == 6,
    'the beacon announced a turn more than five yalms before the route corner')

player.x = 6
delta = accessxi.nav_beacon_direction_delta(player, target, left, 2, true)
_, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta - (math.pi / 2)) < 0.001 and prefix == 'front' and bin == 0,
    'a real upcoming left turn did not move the beacon left')

local right = T({
    T({ x = 0, z = 0, y = 0 }),
    T({ x = 10, z = 0, y = 0 }),
    T({ x = 10, z = -10, y = 0 }),
})
delta = accessxi.nav_beacon_direction_delta(player, target, right, 2, true)
_, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta + (math.pi / 2)) < 0.001 and prefix == 'front' and bin == 12,
    'a real upcoming right turn did not move the beacon right')

local off_route = T({ x = 4, z = 4, y = 0, yaw = 0 })
target = T({ x = 4, z = 0, y = 0, source = 'live-route-return' })
delta = accessxi.nav_beacon_direction_delta(off_route, target, straight, 2, true)
assert(math.abs(delta) > 0.5,
    'an explicit route-rejoin target was incorrectly forced to the center')

accessxi.nav_beacon_motion_x = 4
accessxi.nav_beacon_motion_z = 0
local drifting = T({ x = 4, z = 2, y = 0, yaw = 0 })
target = T({ x = 8, z = 0, y = 0, source = 'dat-collision-segment-steering' })
delta = accessxi.nav_beacon_direction_delta(drifting, target, straight, 2, true)
assert(math.abs(delta) > 0.5,
    'a large real course drift was incorrectly treated as straight travel')

local poll_start = assert(source:find('function accessxi.poll_nav_beacon()', 1, true))
local poll_end = assert(source:find('local function poll_nav_route()', poll_start, true))
local poll_source = source:sub(poll_start, poll_end - 1)
assert(poll_source:find('nav_beacon_direction_delta(', 1, true),
    'beacon polling does not use the stable route-turn direction policy')
assert(not poll_source:find('target_heading + yaw', 1, true),
    'beacon polling still rotates directly with character yaw')

print('navigation beacon route-turn cue checks passed')
