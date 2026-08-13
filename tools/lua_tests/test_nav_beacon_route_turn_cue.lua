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

local reset_source = ''
if (source:find('function accessxi.nav_beacon_reset_direction_state', 1, true) ~= nil) then
    reset_source = block(
        'function accessxi.nav_beacon_reset_direction_state',
        'function accessxi.nav_beacon_direction_delta')
end

local selected = table.concat({
    block('function accessxi.nav_normalize_angle', 'function accessxi.nav_atan2'),
    block('function accessxi.nav_atan2', 'function accessxi.nav_capitalize'),
    block('function accessxi.nav_heading_to', 'function accessxi.nav_relative_turn_phrase'),
    block('function accessxi.nav_project_to_segment', 'function accessxi.nav_route_live_match'),
    block('function accessxi.nav_indexed_lookahead_target', 'function accessxi.nav_sync_route_index'),
    reset_source,
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
    nav_beacon_centered = false,
    nav_beacon_center_index = 2,
    nav_beacon_previous_delta = nil,
    nav_beacon_motion_x = nil,
    nav_beacon_motion_z = nil,
    nav_route_point_index = 2,
}

function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end

local chunk, reason = loadstring(selected, '@nav-beacon-route-turn-cue')
assert(chunk, reason)
chunk()

assert(type(accessxi.nav_beacon_reset_direction_state) == 'function',
    'beacon direction stabilization has no lifecycle reset helper')
accessxi.nav_beacon_route_acquired = true
accessxi.nav_beacon_centered = true
accessxi.nav_beacon_center_index = 7
accessxi.nav_beacon_previous_delta = 0.1
accessxi.nav_beacon_motion_x = 12
accessxi.nav_beacon_motion_z = 34
accessxi.nav_beacon_route_identity = T({})
accessxi.nav_beacon_reset_direction_state()
assert(accessxi.nav_beacon_route_acquired ~= true
        and accessxi.nav_beacon_centered ~= true
        and accessxi.nav_beacon_center_index == nil
        and accessxi.nav_beacon_previous_delta == nil
        and accessxi.nav_beacon_motion_x == nil
        and accessxi.nav_beacon_motion_z == nil
        and accessxi.nav_beacon_route_identity == nil,
    'beacon direction stabilization leaked across a route lifecycle reset')
accessxi.nav_beacon_route_acquired = true
accessxi.nav_beacon_center_index = 2

local straight = T({
    T({ x = 0, z = 0, y = 0 }),
    T({ x = 10, z = 0, y = 0 }),
    T({ x = 20, z = 0, y = 0 }),
})
local player = T({ x = 6, z = 0, y = 0, yaw = 1.4 })
local target = T({ x = 8, z = 0, y = 0, source = 'dat-collision-segment-steering' })

local delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
local _, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta - 1.4) < 0.001 and prefix == 'front' and bin < 6,
    'an acquired straight route did not rotate when the character turned away from its target')

player.yaw = -1.1
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
_, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta + 1.1) < 0.001 and prefix == 'front' and bin > 6,
    'turning across the target did not move the acquired beacon to the opposite side')

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
assert(math.abs(delta + 1.3) < 0.001,
    'route acquisition suppressed later facing-relative beacon guidance')

-- Once the route has been acquired, natural walking wobble should not move the
-- sound out of the center on every pulse.  The wider exit threshold prevents
-- chatter at the boundary, while the tighter entry threshold requires the
-- player to be genuinely aligned before the beacon recenters.
accessxi.nav_beacon_route_acquired = true
accessxi.nav_beacon_centered = false
accessxi.nav_beacon_center_index = 2
accessxi.nav_beacon_previous_delta = nil
player.yaw = 10 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta) < 0.001 and accessxi.nav_beacon_centered == true,
    'an acquired route did not center a ten-degree natural walking wobble')

player.yaw = 17 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta) < 0.001 and accessxi.nav_beacon_centered == true,
    'the centered beacon chattered before leaving its eighteen-degree envelope')

player.yaw = 19 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta - player.yaw) < 0.001 and accessxi.nav_beacon_centered ~= true,
    'a meaningful turn was hidden by the acquired-route center envelope')

player.yaw = 14 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta - player.yaw) < 0.001 and accessxi.nav_beacon_centered ~= true,
    'the beacon recentered before the player was genuinely aligned')

player.yaw = 11 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta) < 0.001 and accessxi.nav_beacon_centered == true,
    'the beacon did not reenter center inside the twelve-degree envelope')

accessxi.nav_beacon_centered = false
accessxi.nav_beacon_previous_delta = 17 * math.pi / 180
player.yaw = -17 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta) < 0.001 and accessxi.nav_beacon_centered == true,
    'a small left-to-right center crossing still produced drunk-walk feedback')

accessxi.nav_beacon_centered = false
accessxi.nav_beacon_previous_delta = 30 * math.pi / 180
player.yaw = -30 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta - player.yaw) < 0.001 and accessxi.nav_beacon_centered ~= true,
    'a real thirty-degree direction change was swallowed as center jitter')

accessxi.nav_beacon_centered = true
accessxi.nav_beacon_center_index = 2
accessxi.nav_beacon_previous_delta = 0
player.yaw = 10 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 3, true)
assert(math.abs(delta - player.yaw) < 0.001
        and accessxi.nav_beacon_centered ~= true
        and accessxi.nav_beacon_center_index == 3,
    'waypoint handoff did not bypass and reset center stabilization')

accessxi.nav_beacon_centered = true
accessxi.nav_beacon_center_index = 2
accessxi.nav_beacon_previous_delta = 0
target.source = 'live-route-return'
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta - player.yaw) < 0.001 and accessxi.nav_beacon_centered ~= true,
    'explicit route recovery was muted by ordinary center stabilization')
target.source = 'dat-collision-segment-steering'

accessxi.nav_beacon_route_acquired = false
accessxi.nav_beacon_centered = true
accessxi.nav_beacon_center_index = 2
player.yaw = 10 * math.pi / 180
delta = accessxi.nav_beacon_direction_delta(player, target, straight, 2, true)
assert(math.abs(delta - player.yaw) < 0.001 and accessxi.nav_beacon_route_acquired == true,
    'initial route acquisition was muted by ordinary center stabilization')

local left = T({
    T({ x = 0, z = 0, y = 0 }),
    T({ x = 10, z = 0, y = 0 }),
    T({ x = 10, z = 10, y = 0 }),
})
player = T({ x = 4, z = 0, y = 0, yaw = 0 })
target = accessxi.nav_indexed_lookahead_target(player, left, 9)
assert(math.abs(target.x - 10) < 0.001 and math.abs(target.z - 3) < 0.001,
    'route lookahead did not preview the outbound leg while staying on its polyline')
delta = accessxi.nav_beacon_direction_delta(player, target, left, 2, true)
assert(math.abs(delta - accessxi.nav_heading_to(player, target)) < 0.001,
    'beacon direction disagreed with the validated route lookahead target')

player.x = 7
target = accessxi.nav_indexed_lookahead_target(player, left, 9)
assert(math.abs(target.x - 10) < 0.001 and math.abs(target.z - 6) < 0.001,
    'route lookahead did not advance its turn prediction along the polyline')
player.x = 9.5
target = accessxi.nav_indexed_lookahead_target(player, left, 9)
assert(math.abs(target.x - 10) < 0.001 and math.abs(target.z - 8.5) < 0.001,
    'near-corner route lookahead did not preserve the remaining inbound distance')

local precise_player = T({ x = 8.25, z = 0, y = 0, yaw = 0 })
local precise_target = T({ x = 10, z = 0, y = 0, source = 'dat-collision' })
delta = accessxi.nav_beacon_direction_delta(precise_player, precise_target, left, 2, true)
assert(math.abs(delta) < 0.001,
    'beacon-local prediction cut across a precise collision corner before index handoff')

precise_player.x = 9.5
precise_target = T({ x = 10, z = 2, y = 0, source = 'dat-collision-segment-steering' })
local outbound_heading = accessxi.nav_heading_to(precise_player, precise_target)
delta = accessxi.nav_beacon_direction_delta(precise_player, precise_target, left, 3, true)
assert(math.abs(delta - outbound_heading) < 0.001,
    'post-handoff beacon did not point at the validated outbound segment target')
precise_player.yaw = -outbound_heading
delta = accessxi.nav_beacon_direction_delta(precise_player, precise_target, left, 3, true)
assert(math.abs(delta) < 0.001,
    'facing the validated outbound target did not center the beacon')

local off_route = T({ x = 4, z = 4, y = 0, yaw = 0 })
target = T({ x = 4, z = 0, y = 0, source = 'live-route-return' })
delta = accessxi.nav_beacon_direction_delta(off_route, target, straight, 2, true)
assert(math.abs(delta) > 0.5,
    'an explicit route-rejoin target was incorrectly forced to the center')

accessxi.nav_beacon_motion_x = 4
accessxi.nav_beacon_motion_z = 0
local drifting = T({ x = 4, z = 2, y = 0, yaw = 0 })
target = T({ x = 8, z = 0, y = 0, source = 'dat-collision-segment-steering' })
drifting.yaw = -accessxi.nav_heading_to(drifting, target)
delta = accessxi.nav_beacon_direction_delta(drifting, target, straight, 2, true)
_, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta) < 0.001 and prefix == 'front' and bin == 6,
    'sampled character movement curved a beacon that remained facing its route target')

local drifting_next = T({ x = 5, z = 2, y = 0, yaw = 0 })
drifting_next.yaw = -accessxi.nav_heading_to(drifting_next, target)
delta = accessxi.nav_beacon_direction_delta(drifting_next, target, straight, 2, true)
_, prefix, bin = accessxi.nav_beacon_file_for_delta(delta)
assert(math.abs(delta) < 0.001 and prefix == 'front' and bin == 6,
    'successive aligned pulses reintroduced movement-course correction oscillation')

local poll_start = assert(source:find('function accessxi.poll_nav_beacon()', 1, true))
local poll_end = assert(source:find('local function poll_nav_route()', poll_start, true))
local poll_source = source:sub(poll_start, poll_end - 1)
assert(poll_source:find('nav_beacon_direction_delta(', 1, true),
    'beacon polling does not use the stable route-turn direction policy')
local direction_source = block(
    'function accessxi.nav_beacon_direction_delta', 'function accessxi.nav_beacon_file_for_delta')
assert(not direction_source:find('nav_beacon_motion_', 1, true)
        and not direction_source:find('motion_heading', 1, true)
        and not direction_source:find('course_delta', 1, true),
    'movement-course steering was reintroduced into facing-relative beacon direction')

print('navigation beacon route-turn cue checks passed')
