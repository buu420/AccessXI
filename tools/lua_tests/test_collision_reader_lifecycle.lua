local reader_path = assert(arg[1], 'accessxi_reader.lua path is required')

local function check(condition, message)
    if not condition then
        error(message or 'check failed', 2)
    end
end

local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local first = assert(source:find('function accessxi.nav_dat_collision_bootstrap()', 1, true))
local last = assert(source:find('function accessxi.nav_route_lookahead_distance', first, true))
local block = source:sub(first, last - 1)

local new_calls = 0
local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value end
function list_methods:clear()
    for index = #self, 1, -1 do
        self[index] = nil
    end
end

accessxi = {
    nav_dat_collision_state = nil,
    nav_dat_collision_failure_reason = '',
    load_module_table = function(name)
        if name == 'collision_navigation' then
            return {
                new = function()
                    new_calls = new_calls + 1
                    return {}
                end,
            }
        end
        if name == 'accessxi_sha256' then
            return { sha256 = function() return string.rep('a', 64) end }
        end
        return nil
    end,
    escape_probe_log_text = function(value) return tostring(value or '') end,
    nav_arrival_radius = function() return 8 end,
    nav_route_points = nil,
}
accessxi_paths = {
    addon_path = function() return 'C:\\AccessXI' end,
    ffxi_root = 'C:\\FFXI',
}
ffi = {}
utf8_to_wide = function(value) return value end
nav_clean_field = function(value) return tostring(value or '') end
safe_call = function(fn, fallback)
    local ok, value = pcall(fn)
    return ok and value or fallback
end
AshitaCore = {
    GetResourceManager = function()
        return { GetString = function() return 'Zone' end }
    end,
}
log_line = function() end
string.fmt = string.format
T = function(value) return setmetatable(value or {}, { __index = list_methods }) end

local chunk, reason = loadstring(block, '@collision-reader-lifecycle')
check(chunk ~= nil, reason)
chunk()

check(new_calls == 0,
    'loading the reader collision integration must not hash or load native collision code at game startup')
check(accessxi.nav_dat_collision_state == nil,
    'collision state must remain uninitialized until a route requests it')
check(accessxi.nav_dat_collision_bootstrap() == true and new_calls == 1,
    'the first explicit collision request must initialize the native state once')

local player = T({ zone = 101, x = 188.462, z = -430.106, y = -0.417 })
local destination = T({
    zone = 101,
    name = "Southern San d'Oria zone line",
    x = 79.181,
    z = 280.841,
    y = -70.089,
    kind = 'zoneline',
    source = 'objective-prefix',
    to_zone = 100,
    to_zone_name = 'West Ronfaure',
    final_zone = 140,
    final_name = 'Hut Door',
    same_zone_reentry_step = 1,
    same_zone_reentry_edge_id = 123,
})
local approach = T({
    zone = 101,
    name = "Southern San d'Oria zone line approach",
    x = 86.131,
    z = 273.861,
    y = -65.817,
    kind = 'zoneline-approach',
    source = 'zoneline-graph-reverse',
})
local spoken = {}

-- A stable current zone must warm collision terrain once without creating a
-- destination, route, or spoken announcement.  La Theine keeps its immediate
-- navmesh path and must not start the expensive generic terrain builder.
local preload_calls = {}
accessxi.nav_active = false
accessxi.nav_dat_collision_pending = nil
accessxi.nav_dat_collision_preload_zone = 0
accessxi.nav_dat_collision_preload_last_tick = 0
accessxi.nav_dat_collision_state = {
    preload = function(_, zone)
        preload_calls[#preload_calls + 1] = zone
        return true, 'pending', ''
    end,
}
nav_cached_player_position = function() return player end
speak = function(text) spoken[#spoken + 1] = text end
check(type(accessxi.poll_nav_dat_collision_preload) == 'function',
    'reader has no silent current-zone collision preload poll')
check(accessxi.poll_nav_dat_collision_preload(1000) == true,
    'stable zone did not start its silent collision terrain preload')
check(#preload_calls == 1 and preload_calls[1] == 101,
    'stable zone preload did not bind the current player zone exactly once')
check(accessxi.poll_nav_dat_collision_preload(2000) == false and #preload_calls == 1,
    'repeated stable-zone polls restarted the same preload')
check(accessxi.nav_dat_collision_pending == nil and accessxi.nav_active == false
    and accessxi.nav_destination == nil and #spoken == 0,
    'silent preload created route state or speech')

player.zone = 245
check(accessxi.poll_nav_dat_collision_preload(3000) == true
    and #preload_calls == 2 and preload_calls[2] == 245,
    'a new stable zone did not start exactly one new preload')
player.zone = 102
check(accessxi.poll_nav_dat_collision_preload(4000) == false and #preload_calls == 2,
    'La Theine must not start the generic collision terrain preload')
player.zone = 101

accessxi.nav_dat_collision_state = {
    route = function(_, _, point)
        if point.name == approach.name then
            return T({
                T({ zone = 101, name = 'Terrain waypoint', x = player.x, z = player.z, y = player.y }),
                T({ zone = 101, name = 'Terrain waypoint', x = approach.x, z = approach.z, y = approach.y }),
            }), 'ready', ''
        end
        return T({}), 'error', 'The destination is outside the generated walkable terrain.'
    end,
    poll = function()
        return nil, 'error', 'The destination is outside the generated walkable terrain.'
    end,
    cancel = function() end,
}
accessxi.nav_point_is_zoneline = function(point)
    return type(point) == 'table'
        and point.zone == destination.zone
        and point.x == destination.x
        and point.z == destination.z
end
accessxi.nav_zoneline_approach_candidates = function(point)
    return accessxi.nav_point_is_zoneline(point) and T({ approach }) or T({})
end
accessxi.nav_append_final_zoneline_point = function(points, point)
    points:append(T({
        zone = point.zone,
        name = point.name,
        x = point.x,
        z = point.z,
        y = point.y,
        kind = point.kind,
        source = point.source,
    }))
    return points
end
accessxi.nav_first_route_index = function() return 2 end
accessxi.nav_route_points = T({})
nav_cached_player_position = function() return player end
tick = function() return 1000 end
speak = function(text) spoken[#spoken + 1] = text end

check(type(accessxi.nav_dat_collision_zoneline_approach) == 'function',
    'collision routing must expose a graph-derived zoneline approach recovery')
local recovered, recovered_mode = accessxi.nav_dat_collision_zoneline_approach(player, destination)
check(recovered_mode == 'ready' and recovered:len() == 3,
    'the reachable reverse landing must recover the exact zoneline route')
check(recovered[3].x == destination.x and recovered[3].z == destination.z,
    'the recovered route must retain the exact final zoneline trigger')

accessxi.nav_dat_collision_pending = T({
    destination = accessxi.nav_dat_collision_destination_copy(destination),
    message = 'Mapping terrain.',
})
for field, expected in pairs({
    to_zone = 100,
    to_zone_name = 'West Ronfaure',
    final_zone = 140,
    final_name = 'Hut Door',
    same_zone_reentry_step = 1,
    same_zone_reentry_edge_id = 123,
}) do
    check(accessxi.nav_dat_collision_pending.destination[field] == expected,
        'collision pending destination dropped transition field ' .. field)
end
accessxi.nav_dat_collision_last_poll_tick = 0
accessxi.nav_route_points:clear()
check(accessxi.poll_nav_dat_collision(1000) == false,
    'a completed terrain poll must leave the pending state')
check(accessxi.nav_active == true and accessxi.nav_route_points:len() == 3,
    'an asynchronous raw-trigger failure must automatically start the recovered approach route')
check(accessxi.nav_destination ~= nil and accessxi.nav_destination.x == destination.x,
    'the automatic route must retain the original zoneline destination')
check(accessxi.nav_destination.to_zone == destination.to_zone
    and accessxi.nav_destination.final_zone == destination.final_zone,
    'the automatic route must retain its expected next and final zones')
check(#spoken == 1 and spoken[1]:find('Terrain map ready', 1, true) ~= nil,
    'approach recovery must speak route readiness instead of the raw-trigger terrain error')

local widened_calls = 0
local sweep_allowed = true
accessxi.nav_dat_collision_state = {
    route = function()
        return T({}), 'error', 'The generated walkable terrain has no connected corridor.'
    end,
    route_zoneline_tail = function(_, current_player, paired_landing, raw_trigger)
        widened_calls = widened_calls + 1
        check(current_player == player and paired_landing == approach
            and raw_trigger == destination,
            'zoneline-tail recovery did not bind the player, paired landing, and raw trigger')
        if not sweep_allowed then
            return nil, 'error', 'Collision terrain zoneline tail is blocked.'
        end
        return T({
            T({ zone = 101, name = 'Terrain waypoint', x = player.x, z = player.z, y = player.y }),
            T({ zone = 101, name = 'Terrain waypoint', x = 72.0, z = 272.0, y = -65.0 }),
        }), 'ready', ''
    end,
}
local widened, widened_mode = accessxi.nav_dat_collision_zoneline_approach(player, destination)
check(widened_mode == 'ready' and widened:len() == 3
    and widened[3].x == destination.x and widened[3].z == destination.z,
    'a sweep-validated projected zoneline tail did not append the exact trigger')
check(widened_calls == 1,
    'the no-corridor zoneline did not use exactly one bounded tail recovery')

sweep_allowed = false
local blocked, blocked_mode, blocked_reason =
    accessxi.nav_dat_collision_zoneline_approach(player, destination)
check(blocked_mode == 'error' and blocked:len() == 0
    and tostring(blocked_reason):find('no connected corridor', 1, true) ~= nil,
    'a blocked zoneline tail must preserve the original no-corridor rejection')
check(widened_calls == 2,
    'the blocked zoneline tail did not execute the same bounded validation path')

print('collision reader lifecycle tests passed')
