-- The La Theine walk-graph seam, sliced out of the real addon and run against
-- stubs.
-- Run: luajit tests/lua/test_walk_graph_seam.lua <addon_dir>
--
-- Two properties matter more than the rest and both are asserted below.
--
-- First, zone containment. The user's condition on this whole change was "as
-- long as it doesn't mess up the rest of the routes" -- every other zone works
-- today. So a player outside zone 102 must not reach one line of the provider,
-- and neither must a La Theine player routing to somewhere else.
--
-- Second, the difference between "the graph learned nothing" and "the graph
-- proved there is no way". Those must not behave alike. 'unavailable' has to
-- fall through to exactly today's behaviour, mesh and terrain builder included,
-- because that is the rollback path. 'no-path' must NOT, because the shipped
-- mesh cannot disprove a proof -- it can only disagree, and its disagreements
-- in this zone are what walked a blind player into the Galaihaurat cliff.

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local MONOLITH = addon .. [[\accessxi_reader.lua]];

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

local function slice()
    local out, capturing = {}, false;
    for line in io.lines(MONOLITH) do
        if (not capturing) then
            if (line:find('^function accessxi%.nav_compute_route_with_zoneline_approach')) then
                capturing = true; out[#out + 1] = line;
            end
        else
            out[#out + 1] = line;
            if (line == 'end') then break; end
        end
    end
    assert(#out > 0, 'nav_compute_route_with_zoneline_approach not found');
    return table.concat(out, '\n');
end

-- provider_result is what walk_graph_route.begin returns: points, mode, message
local function build(calls, provider_result, provider_enabled)
    local none = function() return T{}; end
    local accessxi = {
        nav_route_last_reject_reason = '',
        nav_walk_graph_pending = nil,
        escape_probe_log_text = function(s) return tostring(s or ''); end,
        nav_point_is_zoneline = function(p)
            return tostring(p and p.name or ''):lower():find('zone line', 1, true) ~= nil;
        end,
        nav_recorded_survey_route = function() return T{}, false, true; end,
        nav_zoneline_approach_candidates = function() return T{}; end,
        nav_append_final_zoneline_point = function() end,
        nav_nearby_zoneline_direct_route_allowed = function() return false; end,
        nav_lathine_recorded_ravine_escape_required = function() return false; end,
        nav_point_effective_kind = function() return 'npc'; end,
        nav_arrival_radius = function() return 3.0; end,
        nav_compute_mesh_endpoint_approach = function() return T{}; end,
        nav_transport_clear = function() end,
        nav_dangruf_fount_drop_clear = function() end,
        nav_dangruf_fount_drop_route = none,
        nav_verified_elevator_route = function() return T{}, false; end,
        nav_dat_collision_route = function()
            calls.dat = (calls.dat or 0) + 1; return T{}, 'error', 'dat unavailable';
        end,
        nav_dat_collision_zoneline_approach = function() return T{}, 'error', ''; end,
    };
    local function counted(key, ret)
        return function() calls[key] = (calls[key] or 0) + 1; return ret and ret() or T{}; end;
    end
    accessxi.nav_lathine_recorded_corridor_route = function()
        calls.corridor = (calls.corridor or 0) + 1; return T{}, false;
    end
    accessxi.nav_lathine_recorded_ravine_escape_route = counted('ravine');
    accessxi.nav_lathine_lower_ravine_recovery_route = counted('lower_ravine');
    accessxi.nav_route_override_points = counted('override');

    accessxi.walk_graph_route = {
        zone = function() return 102; end,
        enabled = function()
            calls.enabled = (calls.enabled or 0) + 1;
            return provider_enabled ~= false;
        end,
        applies = function(player, destination)
            calls.applies = (calls.applies or 0) + 1;
            return player ~= nil and destination ~= nil
                and (tonumber(player.zone) or 0) == 102
                and (tonumber(destination.zone) or 0) == 102;
        end,
        begin = function()
            calls.begin = (calls.begin or 0) + 1;
            return provider_result();
        end,
    };

    local env = {
        T = T, accessxi = accessxi, log_line = H.log_line,
        nav_distance = H.nav_distance, nav_clean_field = H.nav_clean_field,
        nav_compute_mesh_route = function()
            calls.mesh = (calls.mesh or 0) + 1; return T{};
        end,
    };
    setmetatable(env, { __index = _G });
    local chunk = assert(loadstring(slice(), 'route_fn'));
    setfenv(chunk, env);
    chunk();
    return accessxi, calls;
end

local LATHEINE = { zone = 102, x = -638.616, z = 274.570, y = 15.160 };
local TARGET = { zone = 102, name = 'Galaihaurat', x = -481.196, z = 220.547, y = -7.028 };

print('\n== the provider is never reached outside zone 102 ==');
local c = {};
local a = build(c, function() return nil, 'no-path', 'should not be called'; end);
a.nav_compute_route_with_zoneline_approach(
    { zone = 100, x = 0, z = 0, y = 0 }, { zone = 100, name = 'Somewhere', x = 5, z = 5, y = 0 });
check('a player in another zone never consults the graph', (c.begin or 0) == 0, c.begin or 0);
check('the other zone still reaches its normal providers',
    (c.mesh or 0) > 0 or (c.dat or 0) > 0 or (c.override or 0) > 0,
    ('mesh=%d dat=%d override=%d'):fmt(c.mesh or 0, c.dat or 0, c.override or 0));

print('\n== a La Theine player routing OUT of the zone is not covered ==');
local c1b = {};
local a1b = build(c1b, function() return nil, 'no-path', 'should not be called'; end);
a1b.nav_compute_route_with_zoneline_approach(LATHEINE,
    { zone = 100, name = 'West Ronfaure', x = 5, z = 5, y = 0 });
check('a cross-zone destination never consults the graph', (c1b.begin or 0) == 0, c1b.begin or 0);

print('\n== the switch really switches off ==');
local c2 = {};
local a2 = build(c2, function() return nil, 'no-path', 'should not be called'; end, false);
a2.nav_compute_route_with_zoneline_approach(LATHEINE, TARGET);
check('a disabled provider is never asked for a route', (c2.begin or 0) == 0, c2.begin or 0);
check('disabled falls through to the old behaviour', (c2.dat or 0) > 0, c2.dat or 0);

print('\n== a ready route is returned and tagged ==');
local c3 = {};
local a3 = build(c3, function()
    local points = T{};
    points:append(T{ zone = 102, x = -638, z = 274, y = 15,
        source = 'lathine-walk-graph-v2', route_override_id = 'lathine-walk-graph-v2' });
    points:append(T{ zone = 102, x = -481, z = 220, y = -7,
        source = 'lathine-walk-graph-v2', route_override_id = 'lathine-walk-graph-v2' });
    return points, 'ready', '';
end);
local r3 = a3.nav_compute_route_with_zoneline_approach(LATHEINE, TARGET);
check('the graph route is returned', r3 ~= nil and r3:len() == 2, r3 and r3:len() or 'nil');
check('it is tagged as the walk graph',
    r3 ~= nil and r3:len() > 0 and r3[1].route_override_id == 'lathine-walk-graph-v2',
    r3 and r3:len() > 0 and tostring(r3[1].route_override_id) or 'nil');
check('a ready route consults nothing downstream',
    (c3.mesh or 0) == 0 and (c3.dat or 0) == 0 and (c3.override or 0) == 0,
    ('mesh=%d dat=%d override=%d'):fmt(c3.mesh or 0, c3.dat or 0, c3.override or 0));

print('\n== pending parks the request and says something ==');
local c4 = {};
local a4 = build(c4, function() return nil, 'pending', 'Preparing the verified La Theine route.'; end);
local r4 = a4.nav_compute_route_with_zoneline_approach(LATHEINE, TARGET);
check('pending returns no route yet', r4 ~= nil and r4:len() == 0, r4 and r4:len() or 'nil');
check('pending records something to say',
    a4.nav_walk_graph_pending ~= nil
    and tostring(a4.nav_walk_graph_pending.message or '') ~= '',
    a4.nav_walk_graph_pending and a4.nav_walk_graph_pending.message or 'nil');
check('pending does not start the terrain builder', (c4.dat or 0) == 0, c4.dat or 0);

print('\n== unavailable is the rollback path: today behaviour, unchanged ==');
local c5 = {};
local a5 = build(c5, function() return nil, 'unavailable', 'graph missing'; end);
a5.nav_compute_route_with_zoneline_approach(LATHEINE, TARGET);
check('walked evidence is still consulted', (c5.override or 0) > 0, c5.override or 0);
check('the terrain builder is still reached', (c5.dat or 0) > 0, c5.dat or 0);
check('no pending is parked', a5.nav_walk_graph_pending == nil,
    tostring(a5.nav_walk_graph_pending));

print('\n== a proof restricts what may answer after it ==');
local c6 = {};
local a6 = build(c6, function()
    return nil, 'no-path', 'I cannot verify a safe route from here.';
end);
local r6 = a6.nav_compute_route_with_zoneline_approach(LATHEINE, TARGET);
check('walked evidence is still allowed to rescue it', (c6.override or 0) > 0, c6.override or 0);
check('recorded corridors are still consulted', (c6.corridor or 0) > 0, c6.corridor or 0);
check('the shipped mesh must NOT answer after a proof', (c6.mesh or 0) == 0, c6.mesh or 0);
check('the terrain builder must NOT answer after a proof', (c6.dat or 0) == 0, c6.dat or 0);
check('no route is returned', r6 ~= nil and r6:len() == 0, r6 and r6:len() or 'nil');
check('a reason is left for the caller to speak',
    H.nav_clean_field(a6.nav_route_last_reject_reason) ~= '',
    tostring(a6.nav_route_last_reject_reason));

print('\n== an unreachable live position behaves the same way ==');
local c7 = {};
local a7 = build(c7, function()
    return nil, 'unreachable', 'You are not standing on mapped ground.';
end);
a7.nav_compute_route_with_zoneline_approach(LATHEINE, TARGET);
check('the shipped mesh must not answer', (c7.mesh or 0) == 0, c7.mesh or 0);
check('walked evidence is still consulted', (c7.override or 0) > 0, c7.override or 0);

print('\n== a provider that throws must not take navigation down ==');
local c8 = {};
local a8 = build(c8, function() error('provider exploded'); end);
local ok8, r8 = pcall(a8.nav_compute_route_with_zoneline_approach, LATHEINE, TARGET);
check('the seam survives a throwing provider', ok8, tostring(r8));
check('and falls through to the old behaviour', (c8.dat or 0) > 0, c8.dat or 0);

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
