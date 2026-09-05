-- Behaviour tests for the navmesh route repair pass.
-- Run: luajit tests/lua/test_mesh_route_repair.lua <addon_dir>
--
-- Detour hands back corridor points that lie ON polygon boundaries -- against
-- walls -- spaced tens of yalms apart. Sighted players slide along geometry; a
-- blind player told "go straight 13 yalms" at a point on a wall walks into the
-- wall. Measured on the real La Theine mesh: 43 of 48 waypoints had less than
-- 0.25 yalms of wall clearance and 30 legs exceeded 6 yalms.

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

local accessxi = H.load_module(addon .. [[\modules\mesh_route_repair.lua]], '', nil);

-- Synthetic geometry: a wall along the plane z = 0. Clearance is |z|, capped.
-- Anything beyond |z| > 40 is off-mesh. Height is ignored.
local function flat_wall_probe()
    return {
        valid = function(x, y, z) return math.abs(z) <= 40; end,
        wall  = function(x, y, z) return math.min(math.abs(z), 10.0); end,
    };
end

local function pts(list)
    local out = T{};
    for _, p in ipairs(list) do
        out:append(T{ zone = 102, x = p[1], z = p[2], y = p[3] or 0, kind = 'route', source = 'navmesh' });
    end
    return out;
end

local function worst_clearance(route, probe)
    local worst = 1e9;
    for _, p in ipairs(route) do
        local w = probe.wall(p.x, p.y, p.z);
        if (w < worst) then worst = w; end
    end
    return worst;
end

local function longest_leg(route)
    local worst = 0;
    for i = 2, route:len() do
        local a, b = route[i - 1], route[i];
        local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 + (a.y - b.y) ^ 2);
        if (d > worst) then worst = d; end
    end
    return worst;
end

print('\n== waypoints pinned against a wall ==');
local probe = flat_wall_probe();
local route = accessxi.nav_mesh_route_repair(pts{ {0, 0}, {5, 0}, {10, 0} }, probe);
check('pushes on-wall waypoints into open ground',
    worst_clearance(route, probe) >= 1.75,
    ('worst clearance %.2f'):fmt(worst_clearance(route, probe)));
check('keeps every repaired waypoint on the mesh',
    (function()
        for _, p in ipairs(route) do if (not probe.valid(p.x, p.y, p.z)) then return false; end end
        return true;
    end)(), 'a waypoint left the mesh');

print('\n== legs too long to walk blind ==');
route = accessxi.nav_mesh_route_repair(pts{ {0, 20}, {60, 20} }, probe);
check('splits a 60 yalm leg into walkable steps', longest_leg(route) <= 6.0 + 0.001,
    ('longest leg %.2f'):fmt(longest_leg(route)));
check('keeps the original endpoints', route[1].x == 0 and route[route:len()].x == 60,
    ('first=%.1f last=%.1f'):fmt(route[1].x, route[route:len()].x));

print('\n== routes that are already fine ==');
local clean = pts{ {0, 20}, {4, 20}, {8, 20} };
route = accessxi.nav_mesh_route_repair(clean, probe);
check('leaves an already-walkable route alone', route:len() == 3,
    ('len=%d'):fmt(route:len()));

print('\n== degenerate input ==');
check('a single waypoint is returned unchanged',
    accessxi.nav_mesh_route_repair(pts{ {1, 20} }, probe):len() == 1);
check('an empty route is returned unchanged',
    accessxi.nav_mesh_route_repair(T{}, probe):len() == 0);
check('a missing probe returns the route untouched',
    accessxi.nav_mesh_route_repair(pts{ {0, 0}, {5, 0} }, nil):len() == 2);

print('\n== nowhere better to stand ==');
-- Wall everywhere: clearance is 0 no matter where you step.
local boxed = { valid = function() return true; end, wall = function() return 0.0; end };
route = accessxi.nav_mesh_route_repair(pts{ {0, 0}, {5, 0} }, boxed);
check('terminates and preserves the route when no improvement exists',
    route:len() >= 2, ('len=%d'):fmt(route:len()));

print('\n== metadata is preserved ==');
route = accessxi.nav_mesh_route_repair(pts{ {0, 0}, {30, 0} }, probe);
check('repaired waypoints keep zone and route kind',
    route[1].zone == 102 and route[1].kind == 'route',
    ('zone=%s kind=%s'):fmt(tostring(route[1].zone), tostring(route[1].kind)));

print('\n== splitting must not invent walkable ground ==');
-- A long leg can span a gap the mesh rejects (a chasm, a missing polygon).
-- Interpolating blindly across it would hand the player a waypoint in mid-air.
local gapped = {
    valid = function(x, y, z) return not (x > 20 and x < 40); end,
    wall  = function(x, y, z) return 5.0; end,
};
route = accessxi.nav_mesh_route_repair(pts{ {0, 0}, {60, 0} }, gapped);
local offmesh = 0;
for i = 2, route:len() - 1 do
    if (not gapped.valid(route[i].x, route[i].y, route[i].z)) then offmesh = offmesh + 1; end
end
check('no interpolated waypoint lands off the mesh', offmesh == 0,
    ('%d of %d inserted waypoints are off-mesh'):fmt(offmesh, route:len()));

print('\n== a waypoint must not wander away from the corridor ==');
-- Clearance that keeps improving in one direction (a corridor that widens, or
-- an open field beside a doorway) must not drag the waypoint off the course
-- Detour actually planned -- that could walk the player into a different room.
local ramp = {
    valid = function() return true; end,
    wall  = function(x, y, z) return math.max(0.0, z * 0.05); end,
};
local origin = pts{ {0, 0} , {5, 0} };
route = accessxi.nav_mesh_route_repair(origin, ramp);
local drift = 0;
for i = 1, route:len() do
    for _, o in ipairs(origin) do
        local d = math.sqrt((route[i].x - o.x) ^ 2 + (route[i].z - o.z) ^ 2);
        if (i <= 2) then drift = math.max(drift, 0); end
    end
end
drift = math.max(
    math.sqrt((route[1].x - 0) ^ 2 + (route[1].z - 0) ^ 2),
    math.sqrt((route[route:len()].x - 5) ^ 2 + (route[route:len()].z - 0) ^ 2));
check('a repaired waypoint stays near where the mesh put it', drift <= 3.0 + 0.001,
    ('drifted %.2f yalms from the planned corridor'):fmt(drift));

print('\n== legs that cut through geometry ==');
-- A waypoint standing in open ground is not enough: the player walks the
-- STRAIGHT LINE between waypoints. Round a corner and that line can pass
-- through rock even though both ends are clear. Measured on the real La
-- Theine mesh: 2 to 5 such legs per route, and neither FindPath nor
-- FindClosestPath string-pulls them away.
-- Geometry: a finite barrier along x=0 spanning z in [-2, 2], small enough
-- to round locally -- which is the case measured on the real mesh, where a
-- 3 yalm bend cleared every blind leg on three separate routes.
local function crosses_barrier(ax, az, bx, bz)
    if ((ax < 0) == (bx < 0)) then return false; end
    local t = (0 - ax) / (bx - ax);
    local z = az + (bz - az) * t;
    return z >= -2 and z <= 2;
end
local barrier = {
    valid = function() return true; end,
    wall  = function(x, y, z)
        if (math.abs(x) > 6 or z < -2 or z > 2) then return 6.0; end
        return math.abs(x);
    end,
    see   = function(ax, ay, az, bx, by, bz) return not crosses_barrier(ax, az, bx, bz); end,
};
-- A leg straight through the barrier, which must be bent around its end.
route = accessxi.nav_mesh_route_repair(pts{ {-10, 0}, {10, 0} }, barrier);
local blind = 0;
for i = 2, route:len() do
    local a, b = route[i - 1], route[i];
    if (not barrier.see(a.x, a.y, a.z, b.x, b.y, b.z)) then blind = blind + 1; end
end
check('a leg through geometry is bent around it', blind == 0,
    ('%d legs still cut through, route is %d waypoints'):fmt(blind, route:len()));
check('the original endpoints survive the bend',
    route[1].x == -10 and route[route:len()].x == 10,
    ('first=%.1f last=%.1f'):fmt(route[1].x, route[route:len()].x));

-- A barrier too wide to round locally must degrade gracefully: leave the route
-- intact and do not mangle it, rather than inventing a way through.
local wide = {
    valid = function() return true; end,
    wall  = function(x, y, z) if (math.abs(x) > 6) then return 6.0; end return math.abs(x); end,
    see   = function(ax, ay, az, bx, by, bz)
        if ((ax < 0) == (bx < 0)) then return true; end
        return false;
    end,
};
local wide_route = accessxi.nav_mesh_route_repair(pts{ {-10, 0}, {10, 0} }, wide);
check('an unroundable barrier leaves the route intact rather than mangled',
    wide_route:len() >= 2 and wide_route[1].x == -10
        and wide_route[wide_route:len()].x == 10,
    ('len=%d'):fmt(wide_route:len()));

-- Without a sight test the pass must still work, just without bending.
local no_see = { valid = barrier.valid, wall = barrier.wall };
check('a probe with no sight test still returns a usable route',
    accessxi.nav_mesh_route_repair(pts{ {-10, 0}, {10, 0} }, no_see):len() >= 2);

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
