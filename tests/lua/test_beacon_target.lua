-- Behaviour tests for nav_beacon_route_target, sliced out of the monolith.
-- Run: luajit tests/lua/test_beacon_target.lua <addon_dir>
--
-- The precise-guidance cache is only valid while the player has moved less
-- than 0.75 yalms from where it was stored. Standing still that holds, and the
-- beacon pulses correctly. Walking invalidates it almost immediately, and the
-- beacon was returning nil -- no target, no pulse, silence exactly when the
-- player is moving and most needs the cue. Measured live 2026-08-20: pulses
-- fell from 9 per 5s to 6 while no-target rose to 50, at a constant poll rate.

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
            if (line:find('^function accessxi%.nav_beacon_route_target')) then
                capturing = true; out[#out + 1] = line;
            end
        else
            out[#out + 1] = line;
            if (line == 'end') then break; end
        end
    end
    assert(#out > 0, 'nav_beacon_route_target not found');
    return table.concat(out, '\n');
end

-- opts.cached: what the precise-guidance cache hands back (nil = stale)
local function build(opts)
    local points = T{};
    for i = 1, 6 do
        points:append(T{ zone = 102, name = ('wp%d'):fmt(i), x = i * 5.0, z = 0, y = 0 });
    end
    local accessxi = {
        nav_active = true,
        nav_destination = T{ zone = 102, name = 'Ordelle', x = 100, z = 0, y = 0 },
        nav_precise_obstacle_recovery = nil,
        nav_dat_collision_pending = nil,
        nav_route_points = points,
        nav_route_point_index = 2,
        -- The walk-graph route id decides whether a cached precise target may
        -- be returned raw or must go through the sightline clamp first, so the
        -- slice needs this even when the case under test is not a graph route.
        nav_route_points_override_id = function() return opts.route_id or ''; end,
        nav_route_precise_override_active = function() return opts.precise == true; end,
        nav_precise_guidance_cached_target = function() return opts.cached; end,
        nav_sync_route_index = function() end,
        nav_route_lookahead_distance = function() return 10.0; end,
        nav_indexed_lookahead_target = function(_, pts, _) return pts[2], pts[3]; end,
    };
    local env = { T = T, accessxi = accessxi, log_line = H.log_line, nav_distance = H.nav_distance };
    setmetatable(env, { __index = _G });
    local chunk = assert(loadstring(slice(), 'beacon_target'));
    setfenv(chunk, env);
    chunk();
    return accessxi;
end

local PLAYER = { zone = 102, x = 6.0, z = 0, y = 0 };

print('\n== the walking case that went silent ==');
local a = build{ precise = true, cached = nil };   -- cache stale: the player moved
local target = a.nav_beacon_route_target(PLAYER);
check('a stale precise cache still yields a beacon target', target ~= nil,
    'returned nil - the beacon has nothing to point at');

print('\n== behaviour that must not change ==');
a = build{ precise = true, cached = T{ zone = 102, name = 'precise', x = 9, z = 0, y = 0 } };
target = a.nav_beacon_route_target(PLAYER);
check('a fresh precise cache is still preferred',
    target ~= nil and target.name == 'precise', target and target.name or 'nil');

a = build{ precise = false, cached = nil };
target = a.nav_beacon_route_target(PLAYER);
check('the ordinary route target is unaffected', target ~= nil,
    target and target.name or 'nil');

a = build{ precise = true, cached = nil };
a.nav_active = false;
check('an inactive route still yields no target',
    a.nav_beacon_route_target(PLAYER) == nil);

a = build{ precise = true, cached = nil };
a.nav_precise_obstacle_recovery = T{};
check('obstacle recovery still suppresses the beacon',
    a.nav_beacon_route_target(PLAYER) == nil);

a = build{ precise = true, cached = nil };
check('a player in another zone still yields no target',
    a.nav_beacon_route_target({ zone = 999, x = 0, z = 0, y = 0 }) == nil);

print('\n== a walk-graph route must not hand back an unvalidated cache ==');
-- Review 2026-08-20 caught this: because the walk-graph route is marked
-- precise, the cached-target early return above fired first and the sightline
-- clamp -- the thing that stops the shipped La Theine mesh substituting an aim
-- point -- was never reached on the normal path. The cached target must be
-- carried down as a candidate and validated, not returned raw. With no clamp
-- installed in this slice the value passes through unchanged, so the assertion
-- is that control reached the clamp at all.
local clamped_with, detour_seen, saw_call = nil, 'unset', false;
a = build{
    precise = true,
    route_id = 'lathine-walk-graph-v2',
    cached = T{ zone = 102, name = 'precise', x = 9, z = 0, y = 0 },
};
a.nav_beacon_sightline_see = function() return function() return true; end; end
a.nav_beacon_clamp_to_sightline = function(_, _, _, aim, _, path)
    saw_call = true; clamped_with = aim; detour_seen = path; return aim;
end
a.nav_mesh_probe_path = function() return T{}; end
target = a.nav_beacon_route_target(PLAYER);
check('the cached target is validated rather than returned early', saw_call,
    'the sightline clamp was never reached');
check('it is the cached precise point that gets validated',
    clamped_with ~= nil and clamped_with.name == 'precise',
    clamped_with and clamped_with.name or 'nil');
check('the shipped mesh is withheld from the clamp', detour_seen == nil,
    tostring(detour_seen));
check('a target still comes back', target ~= nil, tostring(target));

print('\n== a non-graph precise route keeps the early return ==');
saw_call = false;
a = build{
    precise = true,
    route_id = 'lathine-navmesh',
    cached = T{ zone = 102, name = 'precise', x = 9, z = 0, y = 0 },
};
a.nav_beacon_sightline_see = function() return function() return true; end; end
a.nav_beacon_clamp_to_sightline = function(_, _, _, aim) saw_call = true; return aim; end
target = a.nav_beacon_route_target(PLAYER);
check('an ordinary precise route returns its cache directly', not saw_call,
    'the clamp ran for a route that never used to reach it');
check('and that cache is what the beacon gets',
    target ~= nil and target.name == 'precise', target and target.name or 'nil');

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
