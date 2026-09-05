-- Behaviour tests for nav_beacon_direction_delta, sliced out of the monolith.
-- Run: luajit tests/lua/test_beacon_direction.lua <addon_dir>
--
-- The player turns until the beacon is CENTRED and then walks forward, so the
-- angle this function returns IS the walking instruction. For nine fixes it
-- returned the compass heading of the ROUTE SEGMENT instead of the heading to
-- the aim point. Those coincide while the player stands on the route, which is
-- why it shipped -- and are unrelated the moment they drift off it, which is
-- exactly when they are stuck. Live on 2026-08-20 it played 9 degrees, meaning
-- "centred, walk forward", while the aim point was 106 degrees away.
--
-- The cue is now always heading(player -> aim point). Route geometry is not an
-- input. When the aim point is too close to give a steady bearing the fix is a
-- FURTHER aim point that passes the same walkability check, never a different
-- quantity.

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local MONOLITH = addon .. [[\accessxi_reader.lua]];
local SIGHTLINE = addon .. [[\modules\beacon_sightline.lua]];

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

local function slice()
    local out, capturing = {}, false;
    for line in io.lines(MONOLITH) do
        if (not capturing) then
            if (line:find('^function accessxi%.nav_beacon_direction_delta')) then
                capturing = true; out[#out + 1] = line;
            end
        else
            out[#out + 1] = line;
            if (line == 'end') then break; end
        end
    end
    assert(#out > 0, 'nav_beacon_direction_delta not found');
    return table.concat(out, '\n');
end

-- The real clamp and the real walkability test, loaded the way the addon does,
-- so the extension logic is exercised rather than stubbed.
local function build(see)
    local accessxi, env = H.load_module(SIGHTLINE, '', nil);
    accessxi.nav_beacon_route_acquired = true;
    accessxi.nav_heading_to = function(a, b)
        if (a == nil or b == nil) then return nil; end
        local dx, dz = (b.x or 0) - (a.x or 0), (b.z or 0) - (a.z or 0);
        if (math.abs(dx) < 1e-6 and math.abs(dz) < 1e-6) then return nil; end
        return math.atan2(dx, dz);
    end
    accessxi.nav_normalize_angle = function(a)
        while (a > math.pi) do a = a - (math.pi * 2); end
        while (a < -math.pi) do a = a + (math.pi * 2); end
        return a;
    end
    accessxi.nav_beacon_sightline_see = function() return see; end
    local chunk = assert(loadstring(slice(), 'direction_delta'));
    setfenv(chunk, env);
    chunk();
    return accessxi;
end

local function degrees(radians)
    return radians == nil and 'nil' or ('%.0f'):fmt(radians * 180 / math.pi);
end

local open = function() return true; end

-- ---------------------------------------------------------------------------
-- The live failure, 2026-08-20. Coordinates lifted straight from the probe:
--   nav sightline player=(11.2,27.5,14.9) ... index=3 count=191
--   nav direction corner=(0.2,34.7,13.0) target=(17.8,25.4,15.6)
--                 raw=106 route=9 acquired=true inbound=-114 outbound=-136
-- printed as (x,z,y). The player is 14.6 yalms off the route; the clamp has
-- correctly picked a waypoint BEHIND them to rejoin by, and the route segment
-- happens to run 97 degrees away from it.
-- ---------------------------------------------------------------------------
local STUCK = { zone = 102, x = 11.2, z = 27.5, y = 14.9, yaw = 0 };
local REJOIN = T{ zone = 102, x = 17.8, z = 25.4, y = 15.6 };
local stuck_route = T{};
for _, p in ipairs({ {-4.6, 8.2}, {-2.3, 21.6}, {0.2, 34.7}, {2.6, 47.5} }) do
    stuck_route:append(T{ zone = 102, x = p[1], z = p[2], y = 13.0 });
end

print('\n== the live failure: 106 degrees played as 9 ==');
local a = build(open);
local toward_rejoin = a.nav_heading_to(STUCK, REJOIN);
local segment = a.nav_heading_to(stuck_route[2], stuck_route[3]);
check('test geometry reproduces the 97 degree disagreement',
    math.abs(math.abs(a.nav_normalize_angle(toward_rejoin - segment)) * 180 / math.pi - 97) < 6,
    ('aim=%s segment=%s'):fmt(degrees(toward_rejoin), degrees(segment)));

local delta = a.nav_beacon_direction_delta(STUCK, REJOIN, stuck_route, 3, true);
check('the cue points at the aim point',
    delta ~= nil and math.abs(a.nav_normalize_angle(delta - toward_rejoin)) < 0.05,
    ('delta=%s, wanted %s'):fmt(degrees(delta), degrees(toward_rejoin)));
check('the cue is NOT the route segment heading',
    delta ~= nil and math.abs(a.nav_normalize_angle(delta - segment)) > 0.5,
    ('delta=%s, segment=%s'):fmt(degrees(delta), degrees(segment)));

-- A reachable corner is what defeated the previous guard: it tested whether the
-- corner was walkable, which it was, and concluded the segment heading was fine.
print('\n== a reachable corner does not license the segment heading ==');
a = build(open);
delta = a.nav_beacon_direction_delta(STUCK, REJOIN, stuck_route, 3, true);
check('even with every leg clear the cue still aims at the target',
    delta ~= nil and math.abs(a.nav_normalize_angle(delta - toward_rejoin)) < 0.05,
    ('delta=%s'):fmt(degrees(delta)));

-- ---------------------------------------------------------------------------
-- Jitter was the reason route geometry existed: the aim point is chosen 5-9
-- yalms ahead, and when it lands on top of the player the bearing swings wildly.
-- The answer is a further aim point, validated the same way -- not a different
-- quantity.
-- ---------------------------------------------------------------------------
local NEAR_PLAYER = { zone = 102, x = 0, z = 0, y = 0, yaw = 0 };
local straight = T{};
for _, p in ipairs({ {0, 0.4}, {0, 1.0}, {0, 6.0}, {0, 12.0} }) do
    straight:append(T{ zone = 102, x = p[1], z = p[2], y = 0 });
end
local CLOSE_TARGET = T{ zone = 102, x = 0, z = 0.4, y = 0 };

print('\n== a target on top of the player is extended, not substituted ==');
a = build(open);
delta = a.nav_beacon_direction_delta(NEAR_PLAYER, CLOSE_TARGET, straight, 1, true);
local far_enough = a.nav_beacon_extend_aim(NEAR_PLAYER, CLOSE_TARGET, straight, 1, open);
check('a further aim point is chosen from the route',
    far_enough ~= nil and H.nav_distance(NEAR_PLAYER, far_enough) >= 2.5,
    far_enough and ('picked (%.1f,%.1f) at %.1f yalms'):fmt(
        far_enough.x, far_enough.z, H.nav_distance(NEAR_PLAYER, far_enough)) or 'nil');
check('the cue points at that further aim point',
    delta ~= nil and far_enough ~= nil
        and math.abs(a.nav_normalize_angle(
            delta - a.nav_heading_to(NEAR_PLAYER, far_enough))) < 0.05,
    ('delta=%s'):fmt(degrees(delta)));

-- Codex, 2026-08-20: "Do not blindly advance along the polyline -- it could
-- cross a corner or wall."
print('\n== the further aim point must pass the same walkability check ==');
local only_near = function(ax, ay, az, bx, by, bz)
    return math.sqrt(((bx - ax) ^ 2) + ((bz - az) ^ 2)) < 8.0;
end
a = build(only_near);
far_enough = a.nav_beacon_extend_aim(NEAR_PLAYER, CLOSE_TARGET, straight, 1, only_near);
check('a blocked far waypoint is rejected in favour of a clear nearer one',
    far_enough ~= nil and math.abs(far_enough.z - 6.0) < 0.01,
    far_enough and ('picked z=%.1f'):fmt(far_enough.z) or 'nil');

print('\n== fail closed: no safe aim point means no confident angle ==');
local nothing_walkable = function() return false; end
a = build(nothing_walkable);
delta = a.nav_beacon_direction_delta(NEAR_PLAYER, CLOSE_TARGET, straight, 1, true);
check('guidance is suppressed rather than falling back to geometry',
    delta == nil, ('delta=%s'):fmt(degrees(delta)));
check('the suppression is recorded so the player can be told',
    a.nav_beacon_direction_suppressed == true,
    tostring(a.nav_beacon_direction_suppressed));

-- Suppressing a target the player CAN reach would throw away real information,
-- which for this mod is nearly as bad as a crash. Close but walkable is kept.
print('\n== a close target that is genuinely reachable is still used ==');
local reachable_only_close = function(ax, ay, az, bx, by, bz)
    return math.sqrt(((bx - ax) ^ 2) + ((bz - az) ^ 2)) < 1.0;
end
a = build(reachable_only_close);
delta = a.nav_beacon_direction_delta(NEAR_PLAYER, CLOSE_TARGET, straight, 1, true);
check('the cue still points at it',
    delta ~= nil and math.abs(a.nav_normalize_angle(
        delta - a.nav_heading_to(NEAR_PLAYER, CLOSE_TARGET))) < 0.05,
    ('delta=%s'):fmt(degrees(delta)));

-- Codex, 2026-08-20: extension excluded explicit-source corrections but not
-- clamped or detour targets. A detour target is deliberately close -- it is the
-- mesh's first step AROUND an obstacle -- so walking further along the route
-- past it aims back at the obstacle. That is the same substitution disease.
print('\n== a correction is never extended past ==');
-- The route has to BEND for this to prove anything: on a straight route the
-- extended point has the same bearing and the test cannot tell them apart.
local bent = T{};
for _, p in ipairs({ {0, 0.4}, {0, 1.0}, {5.0, 4.0}, {10.0, 8.0} }) do
    bent:append(T{ zone = 102, x = p[1], z = p[2], y = 0 });
end
local DETOUR_TARGET = T{ zone = 102, x = 0, z = 0.4, y = 0 };
a = build(open);
check('the bent route really would move the bearing if extended',
    math.abs(a.nav_normalize_angle(
        a.nav_heading_to(NEAR_PLAYER, bent[3]) - a.nav_heading_to(NEAR_PLAYER, DETOUR_TARGET))) > 0.5,
    'test geometry is wrong');
a = build(open);
a.nav_beacon_detour_active = true;
delta = a.nav_beacon_direction_delta(NEAR_PLAYER, DETOUR_TARGET, bent, 1, true);
check('a detour target is played as given, not extended',
    delta ~= nil and math.abs(a.nav_normalize_angle(
        delta - a.nav_heading_to(NEAR_PLAYER, DETOUR_TARGET))) < 0.05,
    ('delta=%s'):fmt(degrees(delta)));

a = build(open);
a.nav_beacon_sightline_clamped = true;
delta = a.nav_beacon_direction_delta(NEAR_PLAYER, DETOUR_TARGET, bent, 1, true);
check('a clamped target is played as given, not extended',
    delta ~= nil and math.abs(a.nav_normalize_angle(
        delta - a.nav_heading_to(NEAR_PLAYER, DETOUR_TARGET))) < 0.05,
    ('delta=%s'):fmt(degrees(delta)));

-- Acquisition used to answer a real 19 degree error with a literal 0, which
-- reads as "centred, walk forward". Latching is fine; lying about the angle is
-- the thing that put the player in a wall.
print('\n== acquisition reports the true angle ==');
a = build(open);
a.nav_beacon_route_acquired = false;
local OFF_BY = { zone = 102, x = 0, z = 0, y = 0, yaw = 0 };
local SLIGHTLY_RIGHT = T{ zone = 102, x = 3.0, z = 9.0, y = 0 };
delta = a.nav_beacon_direction_delta(OFF_BY, SLIGHTLY_RIGHT, straight, 1, true);
local true_heading = a.nav_heading_to(OFF_BY, SLIGHTLY_RIGHT);
check('a small error inside the acquisition window is still reported',
    delta ~= nil and math.abs(delta) > 0.01
        and math.abs(a.nav_normalize_angle(delta - true_heading)) < 0.05,
    ('delta=%s, true heading=%s'):fmt(degrees(delta), degrees(true_heading)));
check('the route is still latched as acquired',
    a.nav_beacon_route_acquired == true, tostring(a.nav_beacon_route_acquired));

print('\n== behaviour that must not change ==');
a = build(open);
check('a route with no geometry still returns a heading',
    a.nav_beacon_direction_delta(STUCK, REJOIN, stuck_route, 3, false) ~= nil);

a = build(nil);
check('no sight function still returns a heading',
    a.nav_beacon_direction_delta(STUCK, REJOIN, stuck_route, 3, true) ~= nil);

a = build(open);
check('a missing yaw still returns nil',
    a.nav_beacon_direction_delta({ x = 0, z = 0, y = 0 }, REJOIN, stuck_route, 3, true) == nil);

a = build(open);
check('a degrees-valued yaw is still converted',
    a.nav_beacon_direction_delta(
        { zone = 102, x = 11.2, z = 27.5, y = 14.9, yaw = 180 }, REJOIN, stuck_route, 3, true) ~= nil);

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
