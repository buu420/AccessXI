-- Behaviour tests for detour-aware beacon aiming.
-- Run: luajit tests/lua/test_beacon_detour.lua <addon_dir>
--
-- Neither a raycast nor a slope test detects an obstacle you must walk around.
-- Live 2026-08-20: player (2.8,34.5,15.2), target (-2.8,31.8,11.9), straight
-- line 6.2 yalms, LOS reported CLEAR, average slope a walkable 0.53 -- and the
-- mesh's own path was 15.7 yalms going NORTH first. The ratio between the two
-- is the only signal that catches it.

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

local accessxi = H.load_module(addon .. [[\modules\beacon_sightline.lua]], '', nil);

-- Production only reaches nav_beacon_detour_target from inside a `see ~= nil`
-- branch, and a candidate nothing has checked must never become a detour, so
-- the suite has to supply a sightline the way the real call site does. The
-- "no sightline, no detour" contract itself is pinned in test_beacon_sightline.
accessxi.nav_beacon_sightline_see = function()
    return function() return true; end
end

local PLAYER = { zone = 102, x = 2.8, z = 34.5, y = 15.2 };
local TARGET = T{ zone = 102, x = -2.8, z = 31.8, y = 11.9 };

-- The mesh path measured live: north first, then back south and up.
local function real_path()
    local p = T{};
    for _, q in ipairs({ {2.78, 34.72, 15.07}, {1.86, 38.29, 15.65},
                         {-2.12, 31.18, 10.38}, {-2.80, 31.80, 10.58},
                         {-2.80, 31.80, 11.90} }) do
        p:append(T{ zone = 102, x = q[1], z = q[2], y = q[3] });
    end
    return p;
end
local path_fn = function() return real_path(); end

print('\n== an obstacle a raycast cannot see ==');
local aim = accessxi.nav_beacon_detour_target(PLAYER, TARGET, path_fn);
check('the aim point moves to the first step of the detour',
    aim ~= nil and aim.z > 36,
    aim and ('aimed at (%.1f,%.1f) instead of north'):fmt(aim.x, aim.z) or 'nil');
check('it does not aim straight at the target', aim ~= TARGET);

print('\n== a clear straight leg is left alone ==');
-- Mesh path barely longer than the straight line: no obstacle, aim direct.
local direct = function()
    local p = T{};
    p:append(T{ zone = 102, x = 2.8, z = 34.5, y = 15.2 });
    p:append(T{ zone = 102, x = 0.0, z = 33.2, y = 13.5 });
    p:append(T{ zone = 102, x = -2.8, z = 31.8, y = 11.9 });
    return p;
end
check('a near-straight mesh path leaves the target alone',
    accessxi.nav_beacon_detour_target(PLAYER, TARGET, direct) == TARGET);

print('\n== guards ==');
check('no path function leaves the target alone',
    accessxi.nav_beacon_detour_target(PLAYER, TARGET, nil) == TARGET);
check('a nil target stays nil',
    accessxi.nav_beacon_detour_target(PLAYER, nil, path_fn) == nil);
check('an empty path leaves the target alone',
    accessxi.nav_beacon_detour_target(PLAYER, TARGET, function() return T{}; end) == TARGET);
check('a path that errors leaves the target alone',
    accessxi.nav_beacon_detour_target(PLAYER, TARGET, function() error('boom'); end) == TARGET);

print('\n== a very close target is not second-guessed ==');
local near = T{ zone = 102, x = 2.9, z = 34.6, y = 15.2 };
check('a target under a yalm away is returned as-is',
    accessxi.nav_beacon_detour_target(PLAYER, near, path_fn) == near);

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
