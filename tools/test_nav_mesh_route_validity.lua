-- A navmesh result is only a suggestion until every straight leg is safe.
--
-- FFXINAV reports one destination waypoint as success even when the start is
-- more than one hundred yalms from the graph.  Promyvion - Holla reproduced
-- that exact shape live: one point at the Spire, 133.48 yalms from the player.
-- A blind player must never receive a beacon for that result.
--
-- Run:
--   lua5.1 tools/test_nav_mesh_route_validity.lua <addon_dir>


local ADDON = (...) or arg[1]
    or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = (os.getenv('ACCESSXI_ROOT') or 'C:/Users/buu42/AccessXI') .. '/tests/lua/?.lua;' .. package.path;
local H = require('ashita_harness');

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then
        pass = pass + 1;
        print('  PASS  ' .. name);
    else
        fail = fail + 1;
        print('  FAIL  ' .. name .. '  -> ' .. tostring(detail));
    end
end

local accessxi = H.load_module(ADDON .. [[\modules\nav_route_validity.lua]], '', nil);

local function point(x, y, z)
    return { zone = 16, x = x, y = y, z = z };
end

local function route(...)
    return H.T({ ... });
end

local function policy(overrides)
    local calls = H.T{};
    local out = {
        arrival_radius = 4.0,
        max_anchor_snap = 12.0,
        max_endpoint_snap = 12.0,
        max_leg = 12.0,
        can_see = function() return true; end,
        leg_walkable = function(ax, ay, az, bx, by, bz, see)
            calls:append({ ax, ay, az, bx, by, bz, see });
            return true;
        end,
        calls = calls,
    };
    for key, value in pairs(overrides or {}) do out[key] = value; end
    return out;
end

print('\n== disconnected Promyvion results ==');
do
    local start = point(92.033, 0.0, 80.380);
    local destination = point(200.0, 0.0, 159.0);
    local reason = accessxi.nav_route_validity_reason(
        route(point(200.0, 0.0, 159.0)), start, destination, policy());
    check('a lone destination waypoint 133 yalms away is rejected',
        tostring(reason):find('one waypoint', 1, true) ~= nil, reason);
end

do
    local start = point(92.033, 0.0, 80.380);
    local destination = point(-40.0, -1.0, 200.0);
    local blocked = policy({
        max_leg = 100.0,
        can_see = function(ax, ay, az, bx, by, bz)
            local dx, dz = bx - ax, bz - az;
            return math.sqrt((dx * dx) + (dz * dz)) < 80.0;
        end,
    });
    local reason = accessxi.nav_route_validity_reason(route(
        point(92.0, 0.0, 80.4),
        point(10.0, 0.0, 116.0),
        point(-40.0, -1.0, 200.0)), start, destination, blocked);
    check('an 89-yalm blind leg is rejected even when under the length cap',
        tostring(reason):find('not visible', 1, true) ~= nil, reason);
end

print('\n== contract with the walkability predicate ==');
do
    local p = policy({
        leg_walkable = function(ax, ay, az, bx, by, bz, see)
            check('walkability receives six numeric coordinates',
                type(ax) == 'number' and type(ay) == 'number' and type(az) == 'number'
                    and type(bx) == 'number' and type(by) == 'number'
                    and type(bz) == 'number',
                ('%s/%s/%s/%s/%s/%s'):fmt(type(ax), type(ay), type(az),
                    type(bx), type(by), type(bz)));
            check('walkability receives the same sightline function',
                type(see) == 'function', type(see));
            return false;
        end,
    });
    local reason = accessxi.nav_route_validity_reason(route(
        point(0, 0, 0), point(5, -5, 0), point(10, -5, 0)),
        point(0, 0, 0), point(10, -5, 0), p);
    check('a leg refused by walkability rejects the route',
        tostring(reason):find('not walkable', 1, true) ~= nil, reason);
end

print('\n== anchoring and ordinary routes ==');
do
    local reason = accessxi.nav_route_validity_reason(route(
        point(0, 0, 0), point(5, 0, 0), point(20, 0, 0)),
        point(0, 0, 0), point(40, 0, 0), policy());
    check('a route that stops short of the requested destination is rejected',
        tostring(reason):find('destination', 1, true) ~= nil, reason);
end

do
    local p = policy();
    local reason = accessxi.nav_route_validity_reason(route(
        point(0, 0, 0), point(5, 0, 0), point(10, 0, 0)),
        point(0, 0, 0), point(10, 0, 0), p);
    check('a short anchored visible walkable route is accepted', reason == '', reason);
    check('every accepted leg was checked', #p.calls == 2, #p.calls);
end

do
    local reason = accessxi.nav_route_validity_reason(
        route(point(10, 0, 0)), point(8, 0, 0), point(10, 0, 0), policy());
    check('one point is accepted only when the player is already there', reason == '', reason);
end

print('\n== production seam ==');
do
    local handle = assert(io.open(ADDON .. [[\accessxi_reader.lua]], 'rb'));
    local source = handle:read('*a');
    handle:close();
    check('the validity module is loaded by the deployed addon',
        source:find("load_code_module('nav_route_validity'", 1, true) ~= nil);
    check('native mesh results cross the validity gate before installation',
        source:find('accessxi%.nav_route_validity_reason,%s*points,%s*start_pos,%s*end_pos') ~= nil);
    check('the old two-table walkability call cannot silently test zeroes',
        source:find('pcall(accessxi.nav_leg_walkable, a, b)', 1, true) == nil);
end

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
