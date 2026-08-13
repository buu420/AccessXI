local reader_path = assert(arg[1], 'accessxi_reader.lua path is required')
local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local function block(first_marker, last_marker)
    local first = assert(source:find(first_marker, 1, true), 'missing ' .. first_marker)
    local last = assert(source:find(last_marker, first + #first_marker, true), 'missing ' .. last_marker)
    return source:sub(first, last - 1)
end

local selected = table.concat({
    block('function accessxi.nav_route_waypoint_arrival_radius', 'function accessxi.nav_first_route_index'),
    block('function accessxi.nav_first_route_index', 'function accessxi.nav_distance_to_segment'),
    block('function accessxi.nav_project_to_segment', 'function accessxi.nav_route_live_match'),
    block('function accessxi.nav_route_live_match', 'function accessxi.nav_route_target_from_match'),
    block('function accessxi.nav_route_target_from_match', 'function accessxi.nav_precise_route_waypoint_passed'),
    block('function accessxi.nav_precise_route_waypoint_passed', 'function accessxi.nav_distance_to_route'),
    block('function accessxi.nav_route_points_override_id', 'accessxi.nav_route_quarantine_rules'),
    block('function accessxi.nav_route_points_are_collision', 'function accessxi.nav_nearest_route_segment'),
    block('function accessxi.nav_route_points_are_override', 'function accessxi.nav_load_zoneline_graph'),
    block('function accessxi.nav_route_precise_override_active', 'function accessxi.nav_route_override_requires_full_start'),
    block('function accessxi.nav_sync_route_index', 'local function nav_route_phrase'),
    block('function accessxi.nav_lathine_live_recorded_corridor_handoff',
        "accessxi.load_code_module('recorded_survey_navigation'"),
    block('function accessxi.nav_precise_route_return_clear', 'function accessxi.nav_precise_steering_target'),
    block('function accessxi.nav_precise_steering_target', 'function accessxi.nav_beacon_route_target'),
    block('function accessxi.nav_beacon_route_target', 'function accessxi.nav_beacon_file_for_delta'),
}, '\n')

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value end
function list_methods:clear()
    while #self > 0 do table.remove(self) end
end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end

string.fmt = string.format
function string.startswith(value, prefix) return value:sub(1, #prefix) == prefix end
function string.contains(value, needle) return value:find(needle, 1, true) ~= nil end
function nav_clean_field(value) return tostring(value or '') end
function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end
function tick() return 1000 end
function log_line(_) end
function speak(_) end
function nav_route_stop()
    accessxi.nav_active = false
    accessxi.nav_destination = nil
    accessxi.nav_route_points:clear()
    accessxi.nav_route_point_index = 1
    return 'Route stopped.'
end

accessxi = {
    nav_precise_return_target = nil,
    nav_precise_return_points = nil,
    nav_precise_return_segment = 0,
}

local chunk, reason = loadstring(selected, '@dat-collision-segment-steering')
assert(chunk, reason)
chunk()

local function direct_mesh_route(start_point, end_point)
    return T({
        T({ zone = start_point.zone, x = start_point.x, z = start_point.z, y = start_point.y,
            source = 'navmesh' }),
        T({ zone = end_point.zone, x = end_point.x, z = end_point.z, y = end_point.y,
            source = 'navmesh' }),
    })
end

function nav_compute_mesh_route(start_point, end_point)
    return direct_mesh_route(start_point, end_point)
end
function accessxi.nav_valid_mesh_position(_) return true end
function accessxi.nav_wall_distance(_) return 5 end

local collision_points = T({
    T({ zone = 102, x = 0, z = 0, y = 0, source = 'dat-collision' }),
    T({ zone = 102, x = 1, z = 0, y = 0, source = 'dat-collision' }),
    T({ zone = 102, x = 5, z = 2.309, y = 0, source = 'dat-collision' }),
})
local player = T({ zone = 102, x = 0, z = 0, y = 0 })

assert(accessxi.nav_route_points_override_id(collision_points) == 'dat-collision',
    'collision route lacks an authoritative route identity')
assert(accessxi.nav_route_precise_override_active(player, collision_points) == true,
    'collision route is still using generic multi-waypoint steering')
assert(accessxi.nav_route_points_are_override(collision_points) == true,
    'collision route is still eligible for legacy route replacement')

local lathine_navmesh_points = T({
    T({ zone = 102, x = -431.587, z = 212.123, y = 8.091,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -439.600, z = 217.600, y = 5.550,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -450.800, z = 206.400, y = 2.350,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
})
assert(accessxi.nav_route_precise_override_active(player, lathine_navmesh_points) == true,
    'fast La Theine navmesh route can still smooth across a narrow corner')

local lathine_corner_points = T({
    T({ zone = 102, x = 0, z = 0, y = 0,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = 2, z = 0, y = 0,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = 10, z = 2, y = 0,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
})
local lathine_corner_target = accessxi.nav_precise_steering_target(
    T({ zone = 102, x = 0, z = 0, y = 0 }), lathine_corner_points, 2, 5)
assert(lathine_corner_target ~= nil
        and math.abs(lathine_corner_target.x - 2) < 0.001
        and math.abs(lathine_corner_target.z) < 0.001,
    'La Theine navmesh steering cut across an unvalidated narrow corner')

accessxi.nav_route_points = lathine_corner_points
accessxi.nav_route_point_index = 2
accessxi.nav_precise_route_track_tick = 0
assert(accessxi.nav_precise_route_track_index(
        T({ zone = 102, x = 2, z = 0, y = 0 }), 1000) == true,
    'La Theine navmesh route did not acknowledge its reached waypoint')
assert(accessxi.nav_route_point_index == 3,
    'La Theine navmesh route stayed locked on the segment behind its reached waypoint')

-- Exact shape returned by FFXINAV FindClosestPath for the first two yalms of
-- the 2026-08-12 Ordelle's Caves route. The final two native points share the
-- same X/Z and differ only because one is the navmesh-projected height and the
-- other is the requested steering height. That duplicate endpoint is not an
-- intervening corner and must not make a reachable route fail closed.
local ordelle_player = T({ zone = 102, x = -474.271, z = 227.064, y = -7.301 })
local ordelle_points = T({
    T({ zone = 102, x = -474.271, z = 227.064, y = -7.541,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -460.000, z = 266.000, y = -6.050,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -459.200, z = 266.400, y = -5.650,
        source = 'navmesh', route_override_id = 'lathine-navmesh' }),
})
function accessxi.nav_valid_mesh_position(_) return true end
function accessxi.nav_wall_distance(_) return 6.075 end
function nav_compute_mesh_route(start_point, end_point)
    return T({
        T({ zone = 102, x = start_point.x, z = start_point.z, y = -7.541, source = 'navmesh' }),
        T({ zone = 102, x = end_point.x, z = end_point.z, y = (tonumber(end_point.y) or 0) + 0.081526,
            source = 'navmesh' }),
        T({ zone = 102, x = end_point.x, z = end_point.z, y = end_point.y, source = 'navmesh' }),
    })
end
accessxi.nav_active = false
accessxi.nav_destination = nil
accessxi.nav_route_points = ordelle_points
accessxi.nav_route_point_index = 2
accessxi.nav_precise_route_return_clear()
accessxi.nav_lathine_local_target_cache_clear()
local ordelle_target = accessxi.nav_precise_steering_target(
    ordelle_player, ordelle_points, 2, 5)
assert(ordelle_target ~= nil,
    "Ordelle's Caves route rejected a duplicate projected endpoint as an extra corner")

-- Exact 15:59:15 route and a position from the live waypoint-5 loop.  Once
-- waypoint 5 owns progress, steering must stay on segment 4->5; rematching
-- segment 3->4 sends the beacon back around the cliff corner.
local live_loop_points = T({
    T({ zone = 102, x = -431.282, z = 219.098, y = 8.309, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -431.600, z = 215.600, y = 8.150, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -432.000, z = 214.800, y = 7.550, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -439.600, z = 217.600, y = 5.550, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -450.800, z = 206.400, y = 2.350, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -452.000, z = 202.800, y = 1.350, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -455.200, z = 193.200, y = -0.450, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -460.400, z = 193.600, y = -2.250, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -464.400, z = 198.000, y = -4.250, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -479.200, z = 219.600, y = -7.050, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -480.000, z = 220.000, y = -7.050, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -481.196, z = 220.547, y = -7.141, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -481.196, z = 220.547, y = -7.028, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
})
assert(accessxi.nav_first_route_index(
        T({ zone = 102, x = -431.545, z = 219.122, y = 8.537 }),
        live_loop_points,
        T({ zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' })) == 2,
    'La Theine precise route skipped its first two narrow-corner waypoints at startup')
accessxi.nav_precise_route_return_clear()
local live_loop_target = accessxi.nav_precise_steering_target(
    T({ zone = 102, x = -437.185, z = 217.647, y = 6.583 }), live_loop_points, 5, 5)
assert(live_loop_target ~= nil
        and math.abs(live_loop_target.x - -441.014) < 0.02
        and math.abs(live_loop_target.z - 216.186) < 0.02,
    'La Theine waypoint-5 steering rematched the segment behind the live player')
accessxi.nav_precise_route_return_clear()
local live_loop_overshoot_target = accessxi.nav_precise_steering_target(
    T({ zone = 102, x = -441.266, z = 220.037, y = 5.550 }), live_loop_points, 5, 5)
assert(live_loop_overshoot_target ~= nil
        and math.abs(live_loop_overshoot_target.x - -441.014) < 0.02
        and math.abs(live_loop_overshoot_target.z - 216.186) < 0.02,
    'La Theine waypoint-5 overshoot sent the beacon backward to waypoint 4')
accessxi.nav_precise_route_return_clear()
local live_loop_prior_segment_target = accessxi.nav_precise_steering_target(
    T({ zone = 102, x = -437.432, z = 214.919, y = 6.991 }), live_loop_points, 5, 5)
assert(live_loop_prior_segment_target ~= nil
        and math.abs(live_loop_prior_segment_target.x - -441.271) < 0.02
        and math.abs(live_loop_prior_segment_target.z - 215.929) < 0.02,
    'La Theine waypoint-5 steering globally rematched prior segment 3')

-- Exact first route and live position from the clean-login 2026-08-12
-- 16:17:12 run.  At 16:18:06 this route advanced to waypoint 4; at
-- 16:18:08 the player contacted a wall.  The installed navmesh reports zero
-- wall clearance for the raw intermediate waypoints, so production must emit
-- a direct, locally reachable inset target instead of its zero-clearance
-- two-yalm carrot.
local f91_points = T({
    T({ zone = 102, x = -440.902, z = 219.604, y = 5.606, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -450.800, z = 206.400, y = 2.350, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -452.000, z = 202.800, y = 1.350, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -455.200, z = 193.200, y = -0.450, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -460.400, z = 193.600, y = -2.250, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -464.400, z = 198.000, y = -4.250, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -479.200, z = 219.600, y = -7.050, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -480.000, z = 220.000, y = -7.050, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -481.196, z = 220.547, y = -7.141, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -481.196, z = 220.547, y = -7.028, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
})
local f91_player = T({ zone = 102, x = -450.941, z = 202.340, y = 2.144 })
local f91_raw_waypoint = f91_points[4]

function accessxi.nav_valid_mesh_position(point)
    return point ~= nil and tonumber(point.zone) == 102 and (tonumber(point.x) or -999) >= -453
end
function accessxi.nav_wall_distance(point)
    if point ~= nil and (tonumber(point.x) or -999) >= -450.85
        and (tonumber(point.z) or 999) <= 201.5 then
        return 1.5
    end
    return 0
end
function nav_compute_mesh_route(start_point, end_point)
    if accessxi.nav_wall_distance(end_point) >= 1.2 then
        return direct_mesh_route(start_point, end_point)
    end
    return T({
        T({ zone = 102, x = start_point.x, z = start_point.z, y = start_point.y, source = 'navmesh' }),
        T({ zone = 102, x = -451.400, z = 198.700, y = 1.500, source = 'navmesh' }),
        T({ zone = 102, x = end_point.x, z = end_point.z, y = end_point.y, source = 'navmesh' }),
    })
end

local f91_safe_target = accessxi.nav_precise_steering_target(
    f91_player, f91_points, 4, 5)
assert(f91_safe_target ~= nil and accessxi.nav_wall_distance(f91_safe_target) >= 1.2,
    'La Theine emitted the zero-clearance waypoint-4 steering carrot from the clean-login route')
local f91_direct = nav_compute_mesh_route(f91_player, f91_safe_target)
assert(f91_direct:len() <= 2,
    'La Theine emitted a target that needs another navmesh corner before it is locally reachable')
assert(nav_distance(f91_safe_target, f91_raw_waypoint) < nav_distance(f91_player, f91_raw_waypoint),
    'La Theine safe steering target did not make forward progress toward waypoint 4')
accessxi.nav_precise_return_target = T({
    zone = 102, x = -451.500, z = 198.500, y = 1.500, source = 'live-route-return',
})
accessxi.nav_precise_return_points = f91_points
accessxi.nav_precise_return_segment = 3
local f91_retained_safe_target = accessxi.nav_precise_steering_target(
    f91_player, f91_points, 4, 5)
assert(f91_retained_safe_target ~= nil and accessxi.nav_wall_distance(f91_retained_safe_target) >= 1.2,
    'La Theine reused an unsafe retained-return target without its local safety gate')
accessxi.nav_precise_route_return_clear()

-- A route that has no safe inset must be recomputed immediately with the
-- loaded FFXINAV mesh.  The refreshed local route remains active only when it
-- yields a direct target with usable wall clearance.
local original_f91_points = f91_points
local f91_destination = T({ zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' })
local f91_replanned = false
function accessxi.nav_valid_mesh_position(_) return true end
function accessxi.nav_wall_distance(_)
    return f91_replanned and 5 or 0
end
function nav_compute_mesh_route(start_point, end_point)
    if end_point == f91_destination then
        f91_replanned = true
        return T({
            T({ zone = 102, x = start_point.x, z = start_point.z, y = start_point.y, source = 'navmesh' }),
            T({ zone = 102, x = -450.200, z = 200.600, y = 1.900, source = 'navmesh' }),
            T({ zone = 102, x = end_point.x, z = end_point.z, y = end_point.y, source = 'navmesh' }),
        })
    end
    return direct_mesh_route(start_point, end_point)
end
accessxi.nav_active = true
accessxi.nav_destination = f91_destination
accessxi.nav_route_points = original_f91_points
accessxi.nav_route_point_index = 4
local f91_replanned_target = accessxi.nav_precise_steering_target(
    f91_player, original_f91_points, 4, 5)
assert(f91_replanned == true and accessxi.nav_route_points ~= original_f91_points,
    'La Theine did not immediately recompute an unsafe local route with the loaded navmesh')
assert(f91_replanned_target ~= nil and accessxi.nav_wall_distance(f91_replanned_target) >= 1.2,
    'La Theine replan did not yield a locally safe steering target')
assert(accessxi.nav_active == true,
    'La Theine stopped even though its immediate navmesh replan had a safe continuation')

-- If both the current route and its one immediate navmesh refresh have no
-- direct inset target, navigation must fail closed instead of emitting the
-- raw destination or another zero-clearance waypoint.
function accessxi.nav_wall_distance(_) return 0 end
function nav_compute_mesh_route(start_point, end_point)
    return T({
        T({ zone = 102, x = start_point.x, z = start_point.z, y = start_point.y, source = 'navmesh' }),
        T({ zone = 102, x = -451.400, z = 198.700, y = 1.500, source = 'navmesh' }),
        T({ zone = 102, x = end_point.x, z = end_point.z, y = end_point.y, source = 'navmesh' }),
    })
end
accessxi.nav_active = true
accessxi.nav_destination = f91_destination
accessxi.nav_route_points = original_f91_points
accessxi.nav_route_point_index = 4
local f91_blocked_target = accessxi.nav_precise_steering_target(
    f91_player, original_f91_points, 4, 5)
assert(f91_blocked_target == nil and accessxi.nav_active == false,
    'La Theine emitted guidance after both local safety checks failed')
assert(accessxi.nav_destination == nil and accessxi.nav_route_points:len() == 0,
    'La Theine fail-closed route left an unsafe destination active')

-- The generic precise-route recovery layer must not revive or pulse a route
-- that La Theine's stricter local-safety layer has already stopped.
local stopped_route_recovery_calls = 0
function accessxi.nav_compute_route_with_zoneline_approach(start_point, _)
    stopped_route_recovery_calls = stopped_route_recovery_calls + 1
    return T({
        T({ zone = 102, x = start_point.x, z = start_point.z, y = start_point.y,
            source = 'dat-collision' }),
        T({ zone = 102, x = -440, z = 210, y = 4, source = 'dat-collision' }),
    })
end
accessxi.nav_active = true
accessxi.nav_destination = f91_destination
accessxi.nav_route_points = original_f91_points
accessxi.nav_route_point_index = 4
local stopped_route_beacon_target = accessxi.nav_beacon_route_target(f91_player)
assert(stopped_route_beacon_target == nil and accessxi.nav_active == false,
    'La Theine fail-closed route emitted a phantom beacon target')
assert(stopped_route_recovery_calls == 0,
    'generic precise recovery revived a route already stopped by local safety')

function accessxi.nav_valid_mesh_position(_) return true end
function accessxi.nav_wall_distance(_) return 5 end
function nav_compute_mesh_route(start_point, end_point)
    return direct_mesh_route(start_point, end_point)
end
accessxi.nav_destination = nil

local target = accessxi.nav_precise_steering_target(player, collision_points, 2, 5)
assert(target ~= nil and math.abs(target.x - 1) < 0.001 and math.abs(target.z) < 0.001,
    'collision steering skipped the current capsule-validated segment endpoint')

-- Reduced reproduction of the exact 64-yalm Upper Jeuno DAT-collision leg.
-- A two-yalm carrot turns a routine 1.5-yalm lateral offset into a 37-degree
-- correction and then flips sides after the player crosses the centerline.
-- Keep the target on the current validated segment, but look far enough ahead
-- to avoid making a blind walker weave down an otherwise straight corridor.
local upper_straight_points = T({
    T({ zone = 244, x = 0, z = 0, y = 0, source = 'dat-collision' }),
    T({ zone = 244, x = 20, z = 0, y = 0, source = 'dat-collision' }),
})
local upper_straight_player = T({ zone = 244, x = 2, z = 1.5, y = 0 })
local upper_straight_target = accessxi.nav_precise_steering_target(
    upper_straight_player, upper_straight_points, 2, 5)
assert(upper_straight_target ~= nil
        and math.abs(upper_straight_target.x - 7) < 0.001
        and math.abs(upper_straight_target.z) < 0.001,
    'DAT collision steering still overcorrects with a two-yalm straight-leg target')

local upper_corner_points = T({
    T({ zone = 244, x = 0, z = 0, y = 0, source = 'dat-collision' }),
    T({ zone = 244, x = 4, z = 0, y = 0, source = 'dat-collision' }),
    T({ zone = 244, x = 4, z = 10, y = 0, source = 'dat-collision' }),
})
local upper_corner_target = accessxi.nav_precise_steering_target(
    T({ zone = 244, x = 2, z = 1, y = 0 }), upper_corner_points, 2, 5)
assert(upper_corner_target ~= nil
        and math.abs(upper_corner_target.x - 4) < 0.001
        and math.abs(upper_corner_target.z) < 0.001,
    'smoother DAT collision steering cut across its next validated corner')

local lathine_straight_points = T({
    T({ zone = 102, x = 0, z = 0, y = 0, source = 'dat-collision' }),
    T({ zone = 102, x = 20, z = 0, y = 0, source = 'dat-collision' }),
})
local lathine_straight_target = accessxi.nav_precise_steering_target(
    T({ zone = 102, x = 2, z = 1.5, y = 0 }), lathine_straight_points, 2, 5)
assert(lathine_straight_target ~= nil
        and math.abs(lathine_straight_target.x - 4) < 0.001,
    'La Theine lost its narrow-path two-yalm collision steering cap')

-- Walking just beyond the bounded segment match tolerance must not silently
-- leave a route active with no beacon target.  Production may recover a
-- target or fail the route closed, but it cannot keep silent navigation state.
local beacon_regression_failures = {}
local function beacon_regression_expect(condition, message)
    if not condition then
        beacon_regression_failures[#beacon_regression_failures + 1] = message
    end
end
local off_segment_player = T({ zone = 102, x = 0.5, z = 6.01, y = 0 })
local recovered_collision_points = T({
    T({ zone = 102, x = off_segment_player.x, z = off_segment_player.z, y = 0,
        source = 'dat-collision' }),
    T({ zone = 102, x = 4, z = 6.01, y = 0, source = 'dat-collision' }),
    T({ zone = 102, x = 10, z = 6.01, y = 0, source = 'dat-collision' }),
})
local precise_recovery_calls = 0
function accessxi.nav_compute_route_with_zoneline_approach(_, _)
    precise_recovery_calls = precise_recovery_calls + 1
    return recovered_collision_points
end
accessxi.nav_active = true
accessxi.nav_destination = collision_points[collision_points:len()]
accessxi.nav_route_points = collision_points
accessxi.nav_route_point_index = 2
accessxi.nav_precise_route_return_clear()
local off_segment_target = accessxi.nav_beacon_route_target(off_segment_player)
beacon_regression_expect(
    off_segment_target ~= nil and accessxi.nav_active == true and precise_recovery_calls == 1,
    'collision route did not immediately recover an audible target at 6.01 yalms off its bounded segment')

-- A retained correction anchor belongs only while it remains locally useful.
-- When it is stale but the player still matches the same live route, steering
-- must discard it and rematch instead of returning nil and silencing beacons.
local rematch_player = T({ zone = 102, x = 0.5, z = 0, y = 0 })
accessxi.nav_precise_return_target = T({
    zone = 102, x = 10, z = 0, y = 0, source = 'live-route-return',
})
accessxi.nav_precise_return_points = collision_points
accessxi.nav_precise_return_segment = 1
local rematched_target = accessxi.nav_precise_steering_target(
    rematch_player, collision_points, 2, 5)
beacon_regression_expect(
    rematched_target ~= nil and accessxi.nav_precise_return_target == nil,
    'stale same-route precise-return anchor was not cleared and rematched to an audible target')
if #beacon_regression_failures > 0 then
    error(table.concat(beacon_regression_failures, '\n'))
end

accessxi.nav_active = true
accessxi.nav_destination = T({ zone = 102, x = 10, z = 10, y = 0 })
accessxi.nav_route_points = T({})
accessxi.nav_dat_collision_pending = T({ destination = accessxi.nav_destination })
assert(accessxi.nav_beacon_route_target(player) == nil,
    'collision mapping emitted a beacon toward the raw destination before a terrain route existed')
accessxi.nav_dat_collision_pending = nil

-- Live La Theine evidence from 2026-08-12: waypoint 3 was
-- (-435.583, 206.250, 8.215), and the player repeatedly came within 0.7
-- yalms without the precise route advancing.  The old matcher preferred the
-- segment behind the player at the shared endpoint, so steering remained
-- locked on waypoint 3 and turned the player in circles.
local lathine_points = T({
    T({ zone = 102, x = -446.784, z = 235.915, y = 7.127, source = 'dat-collision' }),
    T({ zone = 102, x = -416.534, z = 237.161, y = 8.614, source = 'dat-collision' }),
    T({ zone = 102, x = -435.583, z = 206.250, y = 8.215, source = 'dat-collision' }),
    T({ zone = 102, x = -438.167, z = 222.417, y = 6.042, source = 'dat-collision' }),
})
accessxi.nav_route_points = lathine_points
accessxi.nav_route_point_index = 3
accessxi.nav_precise_route_track_tick = 0
local reached_corner = T({ zone = 102, x = -436.017, z = 205.743, y = 8.333 })
assert(accessxi.nav_precise_route_track_index(reached_corner, 1000) == true,
    'collision route did not acknowledge the reached La Theine corner')
assert(accessxi.nav_route_point_index == 4,
    'collision route stayed locked on the segment behind the reached La Theine corner')

local handoff_calls = 0
function accessxi.nav_lathine_recorded_corridor_route()
    handoff_calls = handoff_calls + 1
    return T({ collision_points[1], collision_points[2] })
end
local handoff = accessxi.nav_lathine_live_recorded_corridor_handoff(
    player,
    T({ zone = 102, x = 10, z = 10, y = 0, name = 'destination' }),
    collision_points)
assert(handoff:len() == 0 and handoff_calls == 0,
    'an active collision route was replaced by an old recorded corridor')

local recorded_corridor_points = T({
    T({ zone = 102, x = -439.283, z = 218.586, y = 5.912,
        route_override_id = 'lathine-recorded-corridor-20260712-04' }),
    T({ zone = 102, x = -450.800, z = 206.400, y = 2.350,
        route_override_id = 'lathine-recorded-corridor-20260712-04' }),
})
handoff_calls = 0
function accessxi.nav_lathine_recorded_corridor_route()
    handoff_calls = handoff_calls + 1
    return recorded_corridor_points
end
handoff = accessxi.nav_lathine_live_recorded_corridor_handoff(
    T({ zone = 102, x = -439.283, z = 218.586, y = 5.912 }),
    T({ zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' }),
    lathine_navmesh_points)
assert(handoff:len() == 0 and handoff_calls == 0,
    'an active La Theine navmesh route was replaced by the stale recorded corridor')

-- Closed-loop replay of the exact nine points returned by the installed
-- La Theine mesh from the user's 15:36:57 position.  An ideal follower moves
-- only toward the production steering target.  The old preferred-segment lock
-- stalls at the first waypoint; a stale-corridor handoff never gets this far.
local replay_points = T({
    T({ zone = 102, x = -439.283, z = 218.586, y = 5.658, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -450.800, z = 206.400, y = 2.350, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -452.000, z = 202.800, y = 1.350, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -455.200, z = 193.200, y = -0.450, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -460.400, z = 193.600, y = -2.250, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -464.400, z = 198.000, y = -4.250, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -479.200, z = 219.600, y = -7.050, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -480.000, z = 220.000, y = -7.050, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
    T({ zone = 102, x = -481.196, z = 220.547, y = -7.141, source = 'navmesh', route_override_id = 'lathine-navmesh' }),
})
local replay_player = T({ zone = 102, x = -439.283, z = 218.586, y = 5.912 })
accessxi.nav_route_points = replay_points
accessxi.nav_route_point_index = 2
accessxi.nav_precise_route_track_tick = 0
accessxi.nav_precise_route_return_clear()
local replay_reached = false
local replay_travelled = 0
local replay_previous_index = accessxi.nav_route_point_index
for frame = 1, 1000 do
    accessxi.nav_precise_route_track_index(replay_player, 1000 + (frame * 50))
    assert(accessxi.nav_route_point_index >= replay_previous_index,
        'La Theine navmesh route rewound during the closed-loop replay')
    replay_previous_index = accessxi.nav_route_point_index
    local replay_target = accessxi.nav_precise_steering_target(
        replay_player, replay_points, accessxi.nav_route_point_index, 5)
    assert(replay_target ~= nil,
        'La Theine navmesh beacon lost the route during the closed-loop replay')
    local dx = replay_target.x - replay_player.x
    local dz = replay_target.z - replay_player.z
    local dy = replay_target.y - replay_player.y
    local horizontal = math.sqrt((dx * dx) + (dz * dz))
    local step = math.min(0.20, horizontal)
    if horizontal > 0.0001 then
        local ratio = step / horizontal
        replay_player.x = replay_player.x + (dx * ratio)
        replay_player.z = replay_player.z + (dz * ratio)
        replay_player.y = replay_player.y + (dy * ratio)
        replay_travelled = replay_travelled + step
    end
    if nav_distance(replay_player, replay_points[replay_points:len()]) <= 0.75 then
        replay_reached = true
        break
    end
end
assert(replay_reached, 'La Theine navmesh beacon did not reach Galaihaurat in the closed-loop replay')
assert(replay_travelled < 90,
    'La Theine navmesh beacon circled instead of following the bounded route')

print('DAT collision segment steering checks passed')
