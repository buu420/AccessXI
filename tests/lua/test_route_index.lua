-- Behaviour tests for nav_sync_route_index, sliced out of the monolith.
-- Run: luajit tests/lua/test_route_index.lua <addon_dir>
--
-- The index is chosen by NEAREST SEGMENT and only ever moves forward. A
-- waypoint sitting on top of a ledge is near in 3D even though the player
-- cannot climb to it, so the index ratchets past ground they never reached and
-- can never recover. Live 2026-08-20: player stationary at (25.9,24.4,16.5) in
-- the open, index stuck at 7 of 183, beacon aiming past an unclimbable ledge.

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
            if (line:find('^function accessxi%.nav_sync_route_index')) then
                capturing = true; out[#out + 1] = line;
            end
        else
            out[#out + 1] = line;
            if (line == 'end') then break; end
        end
    end
    assert(#out > 0, 'nav_sync_route_index not found');
    return table.concat(out, '\n');
end

-- Route climbs a ledge: waypoint 2 is a flat walk west, waypoint 3 is on top.
local function make_route()
    local pts = T{};
    for _, p in ipairs({ {25.9, 24.4, 16.16}, {17.8, 25.5, 15.60},
                         {17.2, 20.7, 10.10}, {17.7, 16.7, 9.43} }) do
        pts:append(T{ zone = 102, x = p[1], z = p[2], y = p[3] });
    end
    return pts;
end

local function build(nearest_segment, start_index)
    local accessxi = {
        nav_route_points = make_route(),
        nav_route_point_index = start_index or 1,
        nav_route_precise_override_active = function() return false; end,
        nav_route_points_are_collision = function() return false; end,
        nav_route_points_are_override = function() return false; end,
        nav_nearest_route_segment = function() return nearest_segment, 1.0; end,
        nav_leg_walkable = function(ax, ay, az, bx, by, bz)
            local run = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2);
            local climb = ay - by;
            if (climb <= 0) then return true; end
            if (run < 0.5) then return climb <= 0.75; end
            return climb <= (run * 0.8);
        end,
    };
    local env = { T = T, accessxi = accessxi, log_line = H.log_line,
                  nav_distance = H.nav_distance, tick = H.tick };
    setmetatable(env, { __index = _G });
    local chunk = assert(loadstring(slice(), 'sync_index'));
    setfenv(chunk, env);
    chunk();
    return accessxi;
end

-- Player standing in the open below the ledge.
local PLAYER = { zone = 102, x = 25.9, z = 24.4, y = 16.5 };

print('\n== the ratchet past an unclimbable ledge ==');
-- Nearest segment resolves to 2, so desired becomes waypoint 3 -- on the ledge,
-- 5.5 yalms up over 4.7 of ground. The player cannot be there.
local a = build(2, 1);
a.nav_sync_route_index(PLAYER);
check('the index does not advance onto ground the player cannot reach',
    a.nav_route_point_index < 3,
    ('index advanced to %d'):fmt(a.nav_route_point_index));

print('\n== normal progress must still work ==');
-- Nearest segment 1 -> desired 2, a flat walk west. This must advance.
a = build(1, 1);
a.nav_sync_route_index(PLAYER);
check('the index still advances onto reachable ground',
    a.nav_route_point_index == 2, ('index=%d'):fmt(a.nav_route_point_index));

a = build(3, 1);
a.nav_sync_route_index({ zone = 102, x = 17.5, z = 18.0, y = 9.5 });
check('a player already on top of the ledge advances normally',
    a.nav_route_point_index == 4, ('index=%d'):fmt(a.nav_route_point_index));

print('\n== guards ==');
a = build(2, 3);
a.nav_sync_route_index(PLAYER);
check('the index never moves backwards', a.nav_route_point_index == 3,
    ('index=%d'):fmt(a.nav_route_point_index));

a = build(2, 1);
a.nav_leg_walkable = nil;
a.nav_sync_route_index(PLAYER);
check('without a walkability test the old behaviour is preserved',
    a.nav_route_point_index == 3, ('index=%d'):fmt(a.nav_route_point_index));

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
