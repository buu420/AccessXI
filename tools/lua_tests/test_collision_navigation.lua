local module_path = assert(arg[1], 'collision_navigation.lua path is required')
local manifest_path = assert(arg[2], 'collision native manifest path is required')
local chunk = assert(loadfile(module_path))
local collision_navigation = chunk()

local function check(condition, message)
    if not condition then
        error(message or 'check failed', 2)
    end
end

-- The module and the shipped manifest must agree on the terrain settings digest,
-- checked below against the manifest itself. Pinning a literal here only meant
-- this test had to be edited every time the native settings were re-derived,
-- which tested the edit rather than the agreement.
local expected_settings_sha256 = tostring(collision_navigation.settings_sha256 or '')
check(expected_settings_sha256:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x'
        .. '%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x'
        .. '%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil,
    'collision navigation module settings digest is not a sha256')
local manifest = assert(io.open(manifest_path, 'rb'))
local header = manifest:read('*l')
local row = manifest:read('*l')
manifest:close()
header = tostring(header or ''):gsub('\r$', '')
row = tostring(row or ''):gsub('\r$', '')
check(header == 'relative_path\tsha256\tabi_version\tsettings_sha256\trecast_commit\tbullet_commit',
    'collision native manifest header is invalid')
local fields = {}
for field in tostring(row):gmatch('[^\t]+') do
    fields[#fields + 1] = field
end
check(fields[3] == '3', 'collision native manifest ABI changed')
check(fields[4] == expected_settings_sha256,
    'collision native manifest settings digest does not match the module')
-- ABI 3 is deliberately unchanged by the asynchronous query: the new exports are
-- additive and every existing struct layout is identical.
check(fields[3] == '3', 'the asynchronous path query must not change the ABI')

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

-- ASYNCHRONOUS ROUTING FOR CRAWLER'S NEST.
--
-- Zone 197 validates every candidate against the client's contact body on the
-- original triangles, which measured up to 12 seconds inside one query. The
-- synchronous export runs that on the calling thread, so this zone must use
-- AXI_FindPathAsync and report planning until a worker finishes. Everything
-- below is about that contract: pending is not an answer, a stale answer is
-- never accepted, and there is no quiet fall back to blocking the game.
local AsyncNative = {}
AsyncNative.__index = AsyncNative

function AsyncNative.new(pending_ticks)
    return setmetatable({
        state = 2,
        begin_calls = 0,
        cancel_calls = 0,
        find_calls = 0,
        async_calls = 0,
        async_cancels = 0,
        destroy_calls = 0,
        generation = 70,
        pending_ticks = pending_ticks or 2,
        pending_reset = pending_ticks or 2,
        supports_async = true,
        starts = {},
        destinations = {},
        points = {
            { x = 381.367, y = 32.433, z = 4.581 },
            { x = 300.0, y = 32.0, z = -10.0 },
            { x = 60.0, y = 2.0, z = -13.0 },
        },
    }, AsyncNative)
end

function AsyncNative:abi_version() return 3 end
function AsyncNative:create_context() return {} end
function AsyncNative:destroy_context() self.destroy_calls = self.destroy_calls + 1 end

function AsyncNative:begin_load(_context, zone)
    self.begin_calls = self.begin_calls + 1
    self.zone = zone
    self.generation = self.generation + 1
    return 0, self.generation
end

function AsyncNative:cancel_load() self.cancel_calls = self.cancel_calls + 1; return 0 end

function AsyncNative:poll_load(_context, generation)
    if generation ~= self.generation then return -2 end
    return 0, {
        state = self.state,
        zone_id = self.zone,
        progress_percent = 100,
        generation = generation,
        message = 'ready',
        dat_sha256 = string.rep('a', 64),
        settings_sha256 = string.rep('b', 64),
    }
end

function AsyncNative:find_path(_context, _generation, start, destination)
    self.find_calls = self.find_calls + 1
    self.last_start = start
    self.last_destination = destination
    return 0, { status = 1, point_count = #self.points, total_length = 700, reason = '' },
        self.points
end

function AsyncNative:find_path_async(_context, generation, start, destination, radius, capacity)
    self.async_calls = self.async_calls + 1
    -- The native worker restarts for a different key, so a re-keyed request is
    -- always pending first. A fake that answered instantly would let the module
    -- look correct while skipping the pending path entirely.
    local key = table.concat({ start.x, start.y, start.z,
        destination.x, destination.y, destination.z, radius }, ':')
    if self.last_key ~= key then
        self.last_key = key
        self.pending_ticks = self.pending_reset or self.pending_ticks
    end
    self.starts[#self.starts + 1] = { x = start.x, y = start.y, z = start.z }
    self.destinations[#self.destinations + 1] =
        { x = destination.x, y = destination.y, z = destination.z }
    self.last_radius = radius
    if generation ~= self.generation then return -2 end
    check(capacity == 512, 'the asynchronous adapter must use the fixed safe capacity')
    if self.pending_ticks > 0 then
        self.pending_ticks = self.pending_ticks - 1
        -- Pending carries no points, exactly as the native export does.
        return 0, { status = 2, point_count = 0, total_length = 0, reason = '' }, {}
    end
    return 0, { status = 1, point_count = #self.points, total_length = 700, reason = '' },
        self.points
end

function AsyncNative:cancel_find_path()
    self.async_cancels = self.async_cancels + 1
    return 0
end

local function async_state(fake)
    local created, reason = collision_navigation.new({
        native = fake,
        ffxi_root = 'C:\\FFXI',
        cache_root = 'C:\\cache',
        zone_name = function(zone)
            if zone == 197 then return "Crawler's Nest" end
            return 'Zone ' .. tostring(zone)
        end,
        arrival_radius = function() return 3.5 end,
    })
    check(created ~= nil, reason)
    return created
end

local cave_player = { zone = 197, x = 381.367, y = -32.433, z = 4.581 }
local cave_target = { zone = 197, x = 60.0, y = -2.0, z = -13.0 }

-- Pending, then ready, without ever blocking and without losing the request.
do
    local fake = AsyncNative.new(2)
    local cave = async_state(fake)
    local points, mode, message = cave:route(cave_player, cave_target)
    check(points == nil and mode == 'pending', 'zone 197 must report pending, not block')
    check(message:find('Planning', 1, true) ~= nil, 'pending must speak a planning line')
    check(cave.pending_destination ~= nil, 'the request must be kept until a final answer')
    check(fake.find_calls == 0, 'zone 197 must never use the synchronous export')

    points, mode = cave:poll(cave_player)
    check(points == nil and mode == 'pending', 'a second tick still reports pending')

    points, mode, message = cave:poll(cave_player)
    check(mode == 'ready' and type(points) == 'table' and #points == 3,
        'the completed asynchronous route must be accepted')
    check(points[1].source == 'dat-collision', 'accepted points keep the terrain source')
    check(points[3].y == -2.0, 'the vertical sign conversion must survive the async path')
    check(cave.pending_destination == nil, 'a final answer clears the pending request')
    check(fake.find_calls == 0, 'no synchronous query may happen for zone 197')
end

-- THE QUESTION IS FROZEN WHILE IT IS BEING ANSWERED.
--
-- The native worker is keyed on the exact floats it was handed. Recomputing them
-- from the live player each tick would start a new query every frame and never
-- collect one, so small drift must not change the request.
do
    local fake = AsyncNative.new(3)
    local cave = async_state(fake)
    check(select(2, cave:route(cave_player, cave_target)) == 'pending')
    local drifted = { zone = 197, x = cave_player.x + 0.4, y = cave_player.y, z = cave_player.z }
    check(select(2, cave:route(drifted, cave_target)) == 'pending')
    check(fake.async_calls == 2, 'each tick polls the same query')
    check(fake.starts[1].x == fake.starts[2].x and fake.starts[1].z == fake.starts[2].z,
        'small drift must not change the frozen query start')
    check(fake.async_cancels == 0, 'small drift must not cancel the query')
end

-- A material move restarts the query instead of answering the old one.
do
    local fake = AsyncNative.new(4)
    local cave = async_state(fake)
    check(select(2, cave:route(cave_player, cave_target)) == 'pending')
    local moved = { zone = 197, x = cave_player.x + 9.0, y = cave_player.y, z = cave_player.z }
    check(select(2, cave:route(moved, cave_target)) == 'pending')
    check(fake.async_cancels == 1, 'a material move must cancel the in-flight query')
    check(fake.starts[2].x ~= fake.starts[1].x, 'and restart from the new position')
end

-- AN ANSWER FOR AN ABANDONED POSITION IS NEVER COLLECTED.
--
-- The query that was about to complete is discarded the moment the player has
-- walked past the threshold, so what comes back is planning for where they are
-- now rather than a route starting where they used to stand.
do
    local fake = AsyncNative.new(1)
    local cave = async_state(fake)
    check(select(2, cave:route(cave_player, cave_target)) == 'pending')
    check(fake.pending_ticks == 0, 'the first query is now one tick from answering')
    local moved = { zone = 197, x = cave_player.x + 9.0, y = cave_player.y, z = cave_player.z }
    local points, mode = cave:route(moved, cave_target)
    check(points == nil and mode == 'pending',
        'a route computed for an abandoned position must not be returned')
    check(fake.async_cancels >= 1, 'the stale query must be canceled')
    check(fake.starts[2].x ~= fake.starts[1].x, 'the replacement asks from the new position')
    check(cave.pending_destination ~= nil, 'and the request is still outstanding')
end

-- A different destination restarts rather than inheriting the old answer.
do
    local fake = AsyncNative.new(3)
    local cave = async_state(fake)
    check(select(2, cave:route(cave_player, cave_target)) == 'pending')
    local elsewhere = { zone = 197, x = 19.0, y = -16.0, z = 1.0 }
    check(select(2, cave:route(cave_player, elsewhere)) == 'pending')
    check(fake.async_cancels == 1, 'a new destination must cancel the previous query')
    check(fake.destinations[2].x == 19.0, 'and ask about the new destination')
end

-- NO SILENT SYNCHRONOUS FALLBACK.
--
-- Running this zone's query on the calling thread is the defect, not a degraded
-- mode, so an older native library must produce a refusal rather than a freeze.
do
    local fake = AsyncNative.new(0)
    fake.supports_async = false
    fake.find_path_async = nil
    local cave = async_state(fake)
    local points, mode, message = cave:route(cave_player, cave_target)
    check(points == nil and mode == 'error', 'missing async support must be an error')
    check(message:find('newer native library', 1, true) ~= nil,
        'and must say why rather than blocking')
    check(fake.find_calls == 0, 'it must not fall back to the synchronous query')
end

-- Other zones are untouched: still synchronous, never asynchronous.
do
    local fake = AsyncNative.new(0)
    local other = async_state(fake)
    local plain_player = { zone = 190, x = -115.0, y = 0.05, z = 218.3 }
    local plain_target = { zone = 190, x = 1.0, y = 1.419, z = -103.608 }
    local points, mode = other:route(plain_player, plain_target)
    check(mode == 'ready' and type(points) == 'table', 'other zones still route synchronously')
    check(fake.find_calls == 1, 'other zones use the synchronous export')
    check(fake.async_calls == 0, 'other zones never start an asynchronous query')
end

-- Shutdown abandons an in-flight query.
do
    local fake = AsyncNative.new(5)
    local cave = async_state(fake)
    check(select(2, cave:route(cave_player, cave_target)) == 'pending')
    cave:shutdown()
    check(fake.async_cancels >= 1, 'shutdown must abandon the in-flight query')
    check(fake.destroy_calls == 1, 'and still destroy the context exactly once')
end

-- A change of floor invalidates a pending route even without horizontal movement.
do
    local fake = AsyncNative.new(1)
    local cave = async_state(fake)
    check(select(2, cave:route(cave_player, cave_target)) == 'pending')
    local moved = { zone = 197, x = cave_player.x, y = cave_player.y + 3.0, z = cave_player.z }
    local points, mode = cave:route(moved, cave_target)
    check(points == nil and mode == 'pending', 'vertical movement must not accept a route from the old floor')
    check(fake.async_cancels == 1, 'vertical movement must cancel the old query')
    check(fake.starts[2].y == -moved.y, 'the new query must use the current floor')
end

print('collision navigation tests passed')
