-- Behaviour tests for clamping the beacon's aim point to what the player can see.
-- Run: luajit tests/lua/test_beacon_sightline.lua <addon_dir>
--
-- The beacon aims 5-9 yalms ahead ALONG THE ROUTE. Around a corner that lands
-- past the bend, and the straight line the player walks toward it goes through
-- rock -- so a correctly routed path still marches them into a wall. The aim
-- point has to be clamped to something actually visible from where they stand.

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

-- An L-shaped corridor turning around a corner at the origin. Anything that
-- crosses the corner block (x > 0 and z > 0) is not visible.
local function blocked(ax, az, bx, bz)
    for step = 0, 20 do
        local t = step / 20;
        local x = ax + (bx - ax) * t;
        local z = az + (bz - az) * t;
        if (x > 0.5 and z > 0.5) then return true; end
    end
    return false;
end
local see = function(ax, ay, az, bx, by, bz) return not blocked(ax, az, bx, bz); end

-- Route runs up the west leg, rounds the corner, then east along the north leg.
local route = T{};
for _, p in ipairs({ {-4, -8}, {-4, -4}, {-4, 0}, {-2, 2}, {2, 4}, {6, 4}, {10, 4} }) do
    route:append(T{ zone = 102, x = p[1], z = p[2], y = 0 });
end

local PLAYER = { zone = 102, x = -4, z = -8, y = 0 };
-- What the unclamped lookahead would pick: a point past the corner.
local FAR = route[6];   -- (6, 4) -- not visible from the player

print('\n== aiming around a corner ==');
check('the unclamped target really is invisible from here',
    see(PLAYER.x, PLAYER.y, PLAYER.z, FAR.x, FAR.y, FAR.z) == false,
    'test geometry is wrong');

local clamped = accessxi.nav_beacon_clamp_to_sightline(PLAYER, route, 2, FAR, see);
check('the aim point is clamped to something visible',
    clamped ~= nil and see(PLAYER.x, PLAYER.y, PLAYER.z, clamped.x, clamped.y, clamped.z) == true,
    clamped and ('aimed at (%.1f,%.1f)'):fmt(clamped.x, clamped.z) or 'nil');

check('it still aims as far ahead as it can see',
    clamped ~= nil and clamped.z >= 0,
    clamped and ('aimed at (%.1f,%.1f)'):fmt(clamped.x, clamped.z) or 'nil');

print('\n== behaviour that must not change ==');
local open = function() return true; end
local unclamped = accessxi.nav_beacon_clamp_to_sightline(PLAYER, route, 2, FAR, open);
check('a visible target is returned untouched', unclamped == FAR,
    'a clear sightline should not be second-guessed');

check('no sight function leaves the target alone',
    accessxi.nav_beacon_clamp_to_sightline(PLAYER, route, 2, FAR, nil) == FAR);

check('a nil target stays nil',
    accessxi.nav_beacon_clamp_to_sightline(PLAYER, route, 2, nil, see) == nil);

print('\n== nothing visible at all ==');
-- Never return nil and silence the beacon: aim at the next waypoint regardless.
local blind_all = function() return false; end
local fallback = accessxi.nav_beacon_clamp_to_sightline(PLAYER, route, 2, FAR, blind_all);
check('an entirely blocked route still yields a target', fallback ~= nil,
    'returning nil here would silence the beacon');

print('\n== when nothing on the route is visible ==');
-- Live case 2026-08-20: player at (22.1,20.8,15.3), aim point (17.4,19.4,9.8)
-- 4.9 yalms away but 5.5 up a ledge, visible=false. The mesh's own path goes
-- NORTH first and loops back. Falling back to the invisible waypoint just
-- points at rock; the way round has to be asked for.
local nothing_visible = function(ax, ay, az, bx, by, bz) return bz > 22; end
local detour = T{ zone = 102, x = 21.2, z = 23.2, y = 15.9 };
local path_fn = function(ax, ay, az, bx, by, bz)
    return T{ T{ zone = 102, x = ax, z = az, y = ay }, detour,
              T{ zone = 102, x = bx, z = bz, y = by } };
end
local stuck_player = { zone = 102, x = 22.1, z = 20.8, y = 15.3 };
local stuck_route = T{};
for _, q in ipairs({ {22.1, 20.8}, {19.0, 20.0}, {17.4, 19.4} }) do
    stuck_route:append(T{ zone = 102, x = q[1], z = q[2], y = 15.3 });
end
local aim = accessxi.nav_beacon_clamp_to_sightline(
    stuck_player, stuck_route, 3, stuck_route[3], nothing_visible, path_fn);
check('it asks the mesh for the way round instead of aiming at rock',
    aim ~= nil and nothing_visible(stuck_player.x, stuck_player.y, stuck_player.z,
        aim.x, aim.y, aim.z) == true,
    aim and ('aimed at (%.1f,%.1f) which is still blocked'):fmt(aim.x, aim.z) or 'nil');

accessxi.nav_beacon_sightline_blocked = nil;
accessxi.nav_beacon_clamp_to_sightline(
    stuck_player, stuck_route, 3, stuck_route[3], nothing_visible, nil);
check('a blocked aim with no detour available is flagged for the player',
    accessxi.nav_beacon_sightline_blocked == true,
    tostring(accessxi.nav_beacon_sightline_blocked));

-- Codex, 2026-08-20: the direct-visible return cleared 'clamped' but not
-- 'blocked'. One boxed-in pulse would then latch true forever, and since the
-- caller withholds the aim point while blocked is set, the beacon would go
-- silent permanently with the way ahead wide open.
print('\n== blocked must not latch ==');
accessxi.nav_beacon_sightline_blocked = nil;
accessxi.nav_beacon_clamp_to_sightline(
    stuck_player, stuck_route, 3, stuck_route[3], nothing_visible, nil);
check('a boxed-in pulse sets the flag',
    accessxi.nav_beacon_sightline_blocked == true,
    tostring(accessxi.nav_beacon_sightline_blocked));

local clear_again = accessxi.nav_beacon_clamp_to_sightline(
    PLAYER, route, 2, route[2], open);
check('the very next pulse with a visible target clears it',
    accessxi.nav_beacon_sightline_blocked == false,
    tostring(accessxi.nav_beacon_sightline_blocked));
check('and that pulse still returns the target',
    clear_again ~= nil, tostring(clear_again));

-- Corrections bypass the reversal hysteresis. A detour target is exactly the
-- large swing the hysteresis would smooth, and smoothing it means one pulse of
-- the previous heading while the player walks.
print('\n== every correction is urgent ==');
accessxi.nav_beacon_sightline_clamped = false;
accessxi.nav_beacon_detour_active = false;
check('a plain route target is not urgent',
    accessxi.nav_beacon_urgent_correction('') == false);

-- A BYPASS LIST MUST BE NAMED SOURCES, NOT A STATE FLAG.
--
-- These two claims used to set nav_beacon_detour_active / _sightline_clamped
-- and expect an empty source to become urgent. That was the original design and
-- it was deliberately removed: keying urgency on those flags disabled the
-- reversal hysteresis on very nearly every pulse, because the flags stay set
-- long after the correction they describe. Urgency is now a property of the
-- SOURCE that produced this aim, which is a fact about this pulse.
accessxi.nav_beacon_detour_active = true;
check('a detour SOURCE is urgent',
    accessxi.nav_beacon_urgent_correction('dynamic-obstacle') == true);
check('but the detour flag alone does not make every aim urgent',
    accessxi.nav_beacon_urgent_correction('') == false);
accessxi.nav_beacon_detour_active = false;

accessxi.nav_beacon_sightline_clamped = true;
check('a wall escape is urgent',
    accessxi.nav_beacon_urgent_correction('wall-escape') == true);
check('and a clamped flag alone is not',
    accessxi.nav_beacon_urgent_correction('') == false);
accessxi.nav_beacon_sightline_clamped = false;

for _, s in ipairs({ 'live-route-return', 'dynamic-obstacle', 'wall-escape', 'lathine-local-safe' }) do
    check(("'%s' is urgent"):fmt(s), accessxi.nav_beacon_urgent_correction(s) == true);
end

-- Codex, 2026-08-20: nav_beacon_route_target can return a CACHED PRECISE
-- target before either the clamp or the detour runs, so all three "current
-- aim" flags survive from the previous pulse. A stale blocked announces "no
-- clear line" over a perfectly good target; a stale clamped or detour_active
-- silently disables extension and the hysteresis. They describe one pulse, so
-- the pulse must start by clearing them.
print('\n== flags do not survive a pulse that bypasses the helpers ==');
accessxi.nav_beacon_sightline_blocked = true;
accessxi.nav_beacon_sightline_clamped = true;
accessxi.nav_beacon_detour_active = true;
accessxi.nav_beacon_begin_pulse();
check('blocked is cleared', accessxi.nav_beacon_sightline_blocked == false,
    tostring(accessxi.nav_beacon_sightline_blocked));
check('clamped is cleared', accessxi.nav_beacon_sightline_clamped == false,
    tostring(accessxi.nav_beacon_sightline_clamped));
check('detour_active is cleared', accessxi.nav_beacon_detour_active == false,
    tostring(accessxi.nav_beacon_detour_active));
check('so nothing is inherited as an urgent correction',
    accessxi.nav_beacon_urgent_correction('') == false);

-- FindPath hands back Detour CORRIDOR PORTAL points, which lie ON polygon
-- boundaries. Live 2026-08-20, player stuck at (24.4,20.2,16.0): the mesh's own
-- detour had 3 of 7 waypoints at 0.00 wall clearance, and the beacon aimed at
-- one of them. Stored routes are repaired at load; this live query never was --
-- so the one path that only runs when the player is ALREADY in trouble served
-- raw on-wall points. Offline the repair fixes it in 2.3ms / 112 probes.
print('\n== the live detour is repaired before it can be aimed at ==');
local repair_calls = 0;
accessxi.nav_mesh_route_repair_probe = function() return { valid = open, wall = function() return 3.0; end }; end
accessxi.nav_mesh_route_repair = function(points)
    repair_calls = repair_calls + 1;
    local out = T{};
    for _, p in ipairs(points) do
        out:append(T{ zone = p.zone, x = p.x + 100, y = p.y, z = p.z, source = p.source });
    end
    return out;
end

local raw = T{};
for _, p in ipairs({ {24.4, 20.2}, {21.2, 23.2}, {20.0, 24.0} }) do
    raw:append(T{ zone = 102, x = p[1], z = p[2], y = 16.0, source = 'sightline-detour' });
end
local fixed = accessxi.nav_beacon_repair_detour(raw);
check('the path is repaired', repair_calls == 1 and fixed ~= nil and fixed[2].x > 100,
    ('calls=%d'):fmt(repair_calls));
-- Waypoint 1 is the player's own snapped position. Offline the repair pushed it
-- 3 yalms EAST, and the beacon picks the first step over 0.75 yalms out -- so
-- repairing it would have aimed the player backwards, away from the route.
check('the player position at the head is left where it is',
    fixed[1].x == 24.4 and fixed[1].z == 20.2,
    ('head=(%.1f,%.1f)'):fmt(fixed[1].x, fixed[1].z));

local again = accessxi.nav_beacon_repair_detour(raw);
check('an identical path within the window is not repaired twice',
    repair_calls == 1 and again ~= nil, ('calls=%d'):fmt(repair_calls));

local other = T{};
for _, p in ipairs({ {5.0, 5.0}, {6.0, 6.0}, {7.0, 7.0} }) do
    other:append(T{ zone = 102, x = p[1], z = p[2], y = 0, source = 'sightline-detour' });
end
accessxi.nav_beacon_repair_detour(other);
check('a different path is repaired afresh', repair_calls == 2,
    ('calls=%d'):fmt(repair_calls));

check('a path too short to repair is returned unchanged',
    accessxi.nav_beacon_repair_detour(T{ raw[1] }) ~= nil);

-- Codex, 2026-08-20: repaired[1] is the player's own snapped position, restored
-- so the repair cannot shove the player sideways. But the clamp's detour loop
-- started at step 1, so it could hand that snap straight back as the aim point
-- -- a "target" a fraction of a yalm from the player, which yields a wildly
-- unstable bearing and, because clamped targets are never extended, no way out.
-- And nav_beacon_detour_target skipped the head but validated nothing after it.
print('\n== the detour never aims at the player, and always validates ==');
accessxi.nav_mesh_route_repair = nil;   -- isolate the consumers from the repair

local head_visible = function(ax, ay, az, bx, by, bz)
    local d = math.sqrt(((bx - ax) ^ 2) + ((bz - az) ^ 2));
    return d < 0.6 or bz > 22;   -- the player's own snap, and the detour point
end
local chose = accessxi.nav_beacon_clamp_to_sightline(
    stuck_player, stuck_route, 3, stuck_route[3], head_visible, path_fn);
check('the clamp does not aim at the player snap',
    chose ~= nil and H.nav_distance(stuck_player, chose) >= 0.75,
    chose and ('aimed at (%.1f,%.1f), %.2f yalms away'):fmt(
        chose.x, chose.z, H.nav_distance(stuck_player, chose)) or 'nil');

local walker = { zone = 102, x = 0, z = 0, y = 0 };
local far = T{ zone = 102, x = 0, z = 10, y = 0 };
local bend = function(ax, ay, az, bx, by, bz)
    local out = T{ T{ zone = 102, x = ax, z = az, y = ay } };
    for _, p in ipairs({ {8, 2}, {2, 7} }) do
        out:append(T{ zone = 102, x = p[1], z = p[2], y = 0 });
    end
    out:append(T{ zone = 102, x = bx, z = bz, y = by });
    return out;
end
-- Everything is walkable except the first step out, which is deliberately blocked.
accessxi.nav_beacon_sightline_see = function()
    return function(ax, ay, az, bx, by, bz) return not (bx > 7 and bz < 3); end
end
local step = accessxi.nav_beacon_detour_target(walker, far, bend);
check('a blocked first detour step is skipped, not handed over',
    step ~= nil and not (step.x > 7 and step.z < 3),
    step and ('chose (%.1f,%.1f)'):fmt(step.x, step.z) or 'nil');
check('and the one it chose is far enough to give a bearing',
    step ~= nil and H.nav_distance(walker, step) >= 0.75,
    step and ('%.2f yalms'):fmt(H.nav_distance(walker, step)) or 'nil');

accessxi.nav_beacon_sightline_see = function() return function() return false; end end
accessxi.nav_beacon_detour_active = false;
local none = accessxi.nav_beacon_detour_target(walker, far, bend);
check('with nothing walkable it keeps the validated target',
    none == far, tostring(none));
check('and does not claim a detour is active',
    accessxi.nav_beacon_detour_active == false,
    tostring(accessxi.nav_beacon_detour_active));

-- Codex, 2026-08-20: the `see == nil or walkable(...)` fallback let an entirely
-- unchecked point become a detour. Unchecked must never read as clear -- that
-- rule is why nav_beacon_sightline_see returns nil rather than a permissive
-- stub when the mesh is unavailable.
print('\n== no sightline means no detour ==');
accessxi.nav_beacon_sightline_see = function() return nil; end
accessxi.nav_beacon_detour_active = false;
local unchecked = accessxi.nav_beacon_detour_target(walker, far, bend);
check('an unvalidated candidate never becomes a detour',
    unchecked == far, tostring(unchecked));
check('and no detour is claimed',
    accessxi.nav_beacon_detour_active == false,
    tostring(accessxi.nav_beacon_detour_active));

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
