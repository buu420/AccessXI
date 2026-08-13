local module_path = assert(arg[1], 'collision_navigation.lua path is required')
local manifest_path = assert(arg[2], 'collision native manifest path is required')
local chunk = assert(loadfile(module_path))
local collision_navigation = chunk()

local function check(condition, message)
    if not condition then
        error(message or 'check failed', 2)
    end
end

local expected_settings_sha256 =
    'a8de71b6e9e79408ea9914d6448e1b783654a54c92d5fe61b2a033e9477e5f32'
check(collision_navigation.settings_sha256 == expected_settings_sha256,
    'collision navigation module settings digest is stale')
local manifest = assert(io.open(manifest_path, 'rb'))
local header = manifest:read('*l')
local row = manifest:read('*l')
manifest:close()
check(header == 'relative_path\tsha256\tabi_version\tsettings_sha256\trecast_commit\tbullet_commit',
    'collision native manifest header is invalid')
local fields = {}
for field in tostring(row):gmatch('[^\t]+') do
    fields[#fields + 1] = field
end
check(fields[3] == '3', 'collision native manifest ABI changed')
check(fields[4] == expected_settings_sha256,
    'collision native manifest settings digest does not match the module')

local FakeNative = {}
FakeNative.__index = FakeNative

function FakeNative.new()
    return setmetatable({
        state = 1,
        begin_calls = 0,
        cancel_calls = 0,
        find_calls = 0,
        sweep_calls = 0,
        sweep_clear = true,
        destroy_calls = 0,
        generation = 41,
        points = {
            { x = -115.0, y = 0.05, z = 218.3 },
            { x = -90.0, y = -6.25, z = 145.0 },
            { x = -45.0, y = 0.50, z = 40.0 },
            { x = 1.0, y = 1.419, z = -103.608 },
        },
    }, FakeNative)
end

function FakeNative:abi_version()
    return 3
end

function FakeNative:create_context()
    return {}
end

function FakeNative:begin_load(_context, zone, ffxi_root, cache_root)
    self.begin_calls = self.begin_calls + 1
    self.zone = zone
    self.ffxi_root = ffxi_root
    self.cache_root = cache_root
    self.generation = self.generation + 1
    self.state = 1
    return 0, self.generation
end

function FakeNative:poll_load(_context, generation)
    if generation ~= self.generation then
        return -2
    end
    return 0, {
        state = self.state,
        zone_id = self.zone,
        progress_percent = self.state == 2 and 100 or 55,
        generation = generation,
        message = self.message or (self.state == 2 and 'ready' or 'building'),
        dat_sha256 = self.state == 2 and string.rep('a', 64) or '',
        settings_sha256 = string.rep('b', 64),
    }
end

function FakeNative:find_path(_context, generation, start, destination, arrival_radius, capacity)
    self.find_calls = self.find_calls + 1
    self.last_start = start
    self.last_destination = destination
    self.last_arrival_radius = arrival_radius
    if generation ~= self.generation then
        return -2
    end
    check(capacity == 512, 'adapter must use the fixed safe point capacity')
    return 0, {
        status = 1,
        point_count = #self.points,
        total_length = 350,
        reason = '',
    }, self.points
end

function FakeNative:sweep(_context, generation, start, destination, radius, height)
    self.sweep_calls = self.sweep_calls + 1
    self.last_sweep_start = start
    self.last_sweep_destination = destination
    self.last_sweep_radius = radius
    self.last_sweep_height = height
    if generation ~= self.generation then
        return -2
    end
    local result = self.sweep_results ~= nil and table.remove(self.sweep_results, 1) or nil
    if result ~= nil then
        return 0, result
    end
    return 0, {
        clear = self.sweep_clear,
        fraction = self.sweep_clear and 1 or 0.5,
        point = destination,
        normal = self.sweep_clear and { x = 0, y = 0, z = 0 } or nil,
    }
end

function FakeNative:cancel_load(_context, generation)
    if generation == self.generation then
        self.cancel_calls = self.cancel_calls + 1
    end
    return 0
end

function FakeNative:destroy_context(_context)
    self.destroy_calls = self.destroy_calls + 1
end

-- Current-zone warmup must only begin the native terrain generation.  It must
-- not create a pending destination or query a route until the user actually
-- selects one.
local preload_native = FakeNative.new()
local preload_state, preload_reason = collision_navigation.new({
    native = preload_native,
    ffxi_root = 'C:\\FFXI',
    cache_root = 'C:\\cache',
    zone_name = function(zone) return 'Zone ' .. tostring(zone) end,
    arrival_radius = function() return 8 end,
})
check(preload_state ~= nil, preload_reason)
check(type(preload_state.preload) == 'function',
    'collision navigation has no begin-only current-zone preload API')

local preload_ok, preload_mode, preload_message = preload_state:preload(244)
check(preload_ok == true and preload_mode == 'pending' and preload_message == '',
    'first current-zone preload must begin silently')
preload_ok, preload_mode, preload_message = preload_state:preload(244)
check(preload_ok == true and preload_mode == 'pending' and preload_message == '',
    'repeated same-zone preload must silently reuse the generation')
check(preload_native.begin_calls == 1,
    'repeated same-zone preload restarted native terrain generation')
check(preload_native.find_calls == 0,
    'current-zone preload queried a path before a destination was selected')
check(preload_state.pending_destination == nil,
    'current-zone preload created a fake pending destination')

preload_native.state = 2
local preload_player = { zone = 244, x = 0, z = 0, y = 0 }
local preload_destination = { zone = 244, name = 'Upper Jeuno line', x = 5, z = 5, y = 0 }
local preload_points, preload_route_mode, preload_route_message =
    preload_state:route(preload_player, preload_destination)
check(preload_route_mode == 'ready' and #preload_points == #preload_native.points,
    preload_route_message)
check(preload_native.begin_calls == 1,
    'route selection restarted an already preloaded current-zone generation')
check(preload_native.find_calls == 1,
    'ready preloaded terrain did not perform exactly one selected route query')
preload_state:shutdown()

local native = FakeNative.new()
local state, new_reason = collision_navigation.new({
    native = native,
    ffxi_root = 'C:\\FFXI',
    cache_root = 'C:\\cache',
    zone_name = function(zone)
        if zone == 190 then return "King Ranperre's Tomb" end
        return 'Zone ' .. tostring(zone)
    end,
    arrival_radius = function() return 8 end,
})
check(state ~= nil, new_reason)

local player = { zone = 190, x = -115.0, z = 218.3, y = -0.05 }
local destination = {
    zone = 190,
    name = 'Tombstone',
    x = 1.0,
    z = -103.608,
    y = -1.419,
}

local points, mode, message = state:route(player, destination)
check(points == nil and mode == 'pending', 'first route must begin asynchronous mapping')
check(message == "Mapping terrain for King Ranperre's Tomb. Navigation will start automatically.", 'pending speech must be concrete')
check(native.begin_calls == 1, 'zone build must begin exactly once')

points, mode = state:route(player, destination)
check(points == nil and mode == 'pending', 'repeated route must remain pending')
check(native.begin_calls == 1, 'repeated route must not restart the build')

native.state = 2
points, mode, message = state:poll(player)
check(mode == 'ready' and #points == 4, message)
check(native.find_calls == 1, 'ready poll must make one complete path query')
check(native.last_start.x == player.x and native.last_start.y == -player.y and native.last_start.z == player.z,
    'AccessXI game height must be negated when converting x/z/y to native collision X/Y/Z')
check(native.last_destination.x == destination.x
    and native.last_destination.y == -destination.y
    and native.last_destination.z == destination.z,
    'destination game height must be negated before native pathfinding')
check(points[2].x == -90.0 and points[2].z == 145.0 and points[2].y == 6.25,
    'native collision height must be negated when copying X/Y/Z back to AccessXI x/z/y')
check(points[1].source == 'dat-collision' and points[1].zone == 190,
    'returned waypoints must identify collision-backed terrain')

-- A legacy navmesh corridor may only contribute a smoother route after every
-- adjacent segment passes a direct player-sized DAT collision sweep.  This
-- validation must not inherit the raised-step fallback used by the bounded
-- zoneline-tail recovery path.
native.sweep_calls = 0
native.sweep_results = nil
native.sweep_clear = true
local candidate = {
    { zone = 190, x = -115.0, z = 218.3, y = -0.05 },
    { zone = 190, x = -90.0, z = 145.0, y = 6.25 },
    { zone = 190, x = -45.0, z = 40.0, y = -0.50 },
}
local clear, clear_reason = state:validate_direct_route(candidate)
check(clear == true and clear_reason == '' and native.sweep_calls == 2,
    'a clear three-point candidate must use exactly one direct sweep per segment')
check(native.last_sweep_radius == 0.40 and native.last_sweep_height == 1.80,
    'candidate validation must use the installed player capsule dimensions')

native.sweep_calls = 0
native.sweep_results = {
    { clear = true, fraction = 1, point = {}, normal = {} },
    { clear = false, fraction = 0.25, point = {}, normal = {} },
}
clear, clear_reason = state:validate_direct_route(candidate)
check(clear == false and tostring(clear_reason):find('segment 2', 1, true) ~= nil,
    'a blocked candidate segment must fail closed with its exact segment index')
check(native.sweep_calls == 2,
    'blocked candidate validation must not attempt the raised-step fallback')
native.sweep_results = nil
native.sweep_clear = true
native.sweep_calls = 0

-- A Recast region split at a true zoneline may leave a short clear tail.
-- Only the zoneline-specific API may widen the projected arrival radius, and
-- it must validate the bounded tail with the native capsule sweep.
native.points = {
    { x = player.x, y = -player.y, z = player.z },
    { x = -14.0, y = 1.0, z = -96.0 },
}
local approach = { zone = 190, name = 'Reverse landing', x = 1, z = -103, y = -1.4 }
local exact_line = { zone = 190, name = 'Exact zone line', x = 3, z = -106, y = -1.5 }
points, mode, message = state:route_zoneline_tail(player, approach, exact_line)
check(mode == 'ready' and #points == 2, message)
check(native.last_arrival_radius == 20,
    'zoneline-tail recovery must use the bounded 20-yalm projected radius')
check(native.sweep_calls == 1 and native.last_sweep_radius > 0
    and native.last_sweep_height > 0,
    'zoneline-tail recovery did not validate its tail with a capsule sweep')
check(native.last_sweep_start.x == points[#points].x
    and native.last_sweep_start.y == -points[#points].y
    and native.last_sweep_destination.x == exact_line.x
    and native.last_sweep_destination.y == -exact_line.y,
    'zoneline-tail sweep did not bind the projected endpoint to the exact trigger')

native.sweep_clear = false
points, mode, message = state:route_zoneline_tail(player, approach, exact_line)
check(points == nil and mode == 'error' and message:find('tail', 1, true) ~= nil,
    'a blocked zoneline tail must fail closed')
native.sweep_clear = true

-- West Ronfaure's exact Ghelsba zoneline reaches a steep upward-facing
-- terrain triangle and then the terminal boundary wall.  The graph-specific
-- tail must step past support contacts and return a bounded wall-contact
-- waypoint so navigation can press into the real zoning boundary.
native.points = {
    { x = -450.579, y = 66.155, z = 456.175 },
    { x = -724.036, y = 60.813, z = 605.183 },
}
native.sweep_results = {
    {
        clear = false,
        fraction = 0.136702,
        point = { x = -726.346, y = 62.048, z = 608.000 },
        normal = { x = 0.124442, y = 0.536000, z = -0.837066 },
    },
    {
        clear = false,
        fraction = 0.091000,
        point = { x = -728.054, y = 63.199, z = 609.138 },
        normal = { x = 0.998877, y = 0.000000, z = 0.047380 },
    },
}
local live_player = { zone = 190, x = -450.579, z = 456.175, y = -66.155 }
local live_approach = { zone = 190, name = 'Ghelsba reverse landing', x = -738.178, z = 619.325, y = -67.173 }
local live_line = { zone = 190, name = 'Ghelsba exact line', x = -740.570, z = 623.341, y = -68.478 }
points, mode, message = state:route_zoneline_tail(live_player, live_approach, live_line)
check(mode == 'ready' and #points == 3, message)
check(points[3].source == 'dat-collision-zoneline-boundary'
    and points[3].x < -726 and points[3].x > -729,
    'zoneline boundary recovery did not return the exact bounded wall-contact waypoint')

-- A zone change cancels only the old build and begins the new zone generation.
local other_player = { zone = 191, x = 0, z = 0, y = 0 }
local other_destination = { zone = 191, name = 'Destination', x = 5, z = 5, y = 0 }
points, mode = state:route(other_player, other_destination)
check(points == nil and mode == 'pending', 'new zone must begin a new asynchronous generation')
check(native.cancel_calls == 1 and native.begin_calls == 2, 'zone change must cancel the old generation once')

-- Native output is copied and validated before reaching navigation.
native.state = 2
native.points = {
    { x = 0, y = 0, z = 0 },
    { x = 0 / 0, y = 0, z = 1 },
}
points, mode, message = state:poll(other_player)
check(points == nil and mode == 'error' and message:find('malformed', 1, true) ~= nil,
    'nonfinite native output must fail closed')

-- A terminal terrain-build failure must release the failed generation.  The
-- next explicit route request must begin a new native attempt instead of
-- replaying the old failure forever.
state:cancel('malformed-path-test-complete')
points, mode = state:route(other_player, other_destination)
check(points == nil and mode == 'pending', 'failure fixture must begin asynchronously')
native.state = 3
native.message = 'bad allocation'
points, mode, message = state:poll(other_player)
check(points == nil and mode == 'error' and message == 'bad allocation',
    'terminal native build failure must be reported exactly once')
local begins_after_failure = native.begin_calls
native.message = nil
points, mode = state:route(other_player, other_destination)
check(points == nil and mode == 'pending', 'a new route after failure must retry terrain mapping')
check(native.begin_calls == begins_after_failure + 1,
    'a new route after failure must begin a fresh native generation')

state:shutdown()
check(native.destroy_calls == 1, 'shutdown must destroy the native context exactly once')

local bad_state, bad_reason = collision_navigation.new({
    native = { abi_version = function() return 1 end },
    ffxi_root = 'C:\\FFXI',
})
check(bad_state == nil and bad_reason:find('ABI', 1, true) ~= nil, 'ABI mismatch must reject before use')

print('collision navigation tests passed')
