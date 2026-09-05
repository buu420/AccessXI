-- A CORNER IS SHORT AND STILL SOLID.
--
-- Live 2026-08-24, Southern San d'Oria: the beacon walked the player into a wall
-- and held them there ten seconds. Player (8.6,39.3), aim (4.0,47.1), direct
-- 9.05 yalms. The length test demanded the way round exceed 9.05*1.35+1.5 =
-- 13.7 yalms before calling the straight line wrong, and going around a building
-- corner is barely longer than going through it. The mesh had already answered:
-- the probe returned FIVE points where a straight walk is two.
--
-- Drives the REAL nav_beacon_detour_target with a stub probe.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
local Tmt = {}; Tmt.__index = {
    append = function (s, v) s[#s + 1] = v; return s; end,
    len = function (s) return #s; end,
    each = function (s, f) for i, v in ipairs(s) do f(v, i); end end,
};
_G.T = function (t) return setmetatable(t or {}, Tmt); end
_G.accessxi = {};
_G.tick = function () return 1000; end
dofile(ADDON .. '/modules/beacon_sightline.lua');

local passed, failed = 0, 0;
local function claim(ok, what)
    if (ok) then passed = passed + 1;
    else failed = failed + 1; io.write(('  FAIL  %s\n'):format(what)); end
end

-- Neutralise the repair and the reachability gate so this test isolates the
-- accept/reject decision the bug lived in.
accessxi.nav_beacon_repair_detour = function (route) return route; end
accessxi.nav_beacon_sightline_see = function () return function () return true; end; end
accessxi.nav_leg_walkable = function () return true; end

local function probe_returning(points)
    return function (ax, ay, az, bx, by, bz, producer)
        local out = T{};
        out:append(T{ x = ax, y = ay, z = az });
        for _, p in ipairs(points) do
            out:append(T{ x = p[1], y = 0, z = p[2] });
        end
        out:append(T{ x = bx, y = by, z = bz });
        return out;
    end
end

local player = { zone = 230, x = 8.596, y = 0.0, z = 39.305 };
local target = { zone = 230, x = 4.0, y = -1.9, z = 47.1, name = 'route ahead',
                 kind = 'route', source = 'route-pursuit' };

-- 1. THE LIVE CASE. A corner: barely longer, but bowed several yalms off the
--    straight line. Must be treated as a detour.
local corner = accessxi.nav_beacon_detour_target(player, target,
    probe_returning({ { 9.0, 44.0 }, { 7.0, 46.5 }, { 5.0, 47.0 } }));
claim(corner ~= nil and (corner.x ~= target.x or corner.z ~= target.z),
    'a corner that bows off the direct line is treated as a detour');

-- 2. A straight corridor with mesh noise must NOT become a detour -- that would
--    make the beacon chase its own jitter.
local straight = accessxi.nav_beacon_detour_target(player, target,
    probe_returning({ { 7.4, 41.3 }, { 6.2, 43.4 }, { 5.1, 45.3 } }));
claim(straight ~= nil and straight.x == target.x and straight.z == target.z,
    'a nearly-straight path with ordinary wiggle is left alone');

-- 3. A two-point path is a clear straight walk and must be left alone.
local direct = accessxi.nav_beacon_detour_target(player, target, probe_returning({}));
claim(direct ~= nil and direct.x == target.x and direct.z == target.z,
    'a two-point path is the direct line and is left alone');

-- 4. The long way round still triggers on length alone, as it always did.
local longway = accessxi.nav_beacon_detour_target(player, target,
    probe_returning({ { 20.0, 40.0 }, { 22.0, 48.0 }, { 10.0, 52.0 } }));
claim(longway ~= nil and (longway.x ~= target.x or longway.z ~= target.z),
    'a genuinely long way round still triggers on length');

io.write(('\n%d claims passed, %d failed\n'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
