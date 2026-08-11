local module_path = assert(arg[1], 'collision_navigation.lua path is required')
local chunk = assert(loadfile(module_path))
local collision_navigation = chunk()

local function check(condition, message)
    if not condition then
        error(message or 'check failed', 2)
    end
end

local FakeNative = {}
FakeNative.__index = FakeNative

function FakeNative.new()
    return setmetatable({
        state = 1,
        begin_calls = 0,
        cancel_calls = 0,
        find_calls = 0,
        destroy_calls = 0,
        generation = 41,
        points = {
            { x = -115.0, y = -0.05, z = 218.3 },
            { x = -90.0, y = 0.25, z = 145.0 },
            { x = -45.0, y = -0.50, z = 40.0 },
            { x = 1.0, y = -1.419, z = -103.608 },
        },
    }, FakeNative)
end

function FakeNative:abi_version()
    return 2
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
        message = self.state == 2 and 'ready' or 'building',
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

function FakeNative:cancel_load(_context, generation)
    if generation == self.generation then
        self.cancel_calls = self.cancel_calls + 1
    end
    return 0
end

function FakeNative:destroy_context(_context)
    self.destroy_calls = self.destroy_calls + 1
end

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
check(native.last_start.x == player.x and native.last_start.y == player.y and native.last_start.z == player.z,
    'AccessXI x/z/y must convert once to native X/Y/Z')
check(native.last_destination.x == destination.x
    and native.last_destination.y == destination.y
    and native.last_destination.z == destination.z,
    'destination coordinates must convert once to native X/Y/Z')
check(points[2].x == -90.0 and points[2].z == 145.0 and points[2].y == 0.25,
    'native X/Y/Z must copy back to AccessXI x/z/y')
check(points[1].source == 'dat-collision' and points[1].zone == 190,
    'returned waypoints must identify collision-backed terrain')

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

state:shutdown()
check(native.destroy_calls == 1, 'shutdown must destroy the native context exactly once')

local bad_state, bad_reason = collision_navigation.new({
    native = { abi_version = function() return 1 end },
    ffxi_root = 'C:\\FFXI',
})
check(bad_state == nil and bad_reason:find('ABI', 1, true) ~= nil, 'ABI mismatch must reject before use')

print('collision navigation tests passed')
