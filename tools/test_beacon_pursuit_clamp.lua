-- THE AIM MUST BE SOMEWHERE THE PLAYER CAN ACTUALLY WALK.
--
-- On 2026-08-22 the beacon aim was unified on nav_route_pursuit_aim and
-- inserted as an early return guarded by `route_count > 1` -- the SAME guard as
-- the validation block below it. Pursuit only declines when the route has fewer
-- than two points, which that guard already excludes, so the early return won
-- every pulse and the sightline clamp, the walkability test, the backward
-- rejoin and the "No clear line ahead" refusal all became unreachable.
--
-- The log settles it: 16,885 'nav sightline' lines, the last at 2026-08-22
-- 11:49:00; the first pursuit aim at 11:49:11; 40,394 pursuit pulses since and
-- not one sightline. Five days with the geometry defence switched off.
--
-- Measured consequence over 2,247 reconstructed (position, aim) pairs: 22.9% of
-- Jugner aims cross unwalkable ground, and when one does the player can walk a
-- median 3.1 yalms before leaving it -- while being told nine. The player:
-- "the beacons do lead you but try to run you in to walls".
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local src = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

local from = src:find('function accessxi.nav_pursuit_aim_reachable(player, aim)', 1, true);
claim(from ~= nil, 'the clamp exists in the deployed reader');
local to = from and src:find('\nend\n', from, true) or nil;
if (from == nil or to == nil) then print('pursuit clamp: 0 passed, 1 failed'); os.exit(1); end
assert((loadstring or load)(src:sub(from, to + 4), 'clamp'))();
claim(type(accessxi.nav_pursuit_aim_reachable) == 'function', 'the real clamp loaded');

-- A wall at a given distance along +z from the origin.
local wall_at = 100;
accessxi.nav_beacon_sightline_see = function () return nil; end
accessxi.nav_leg_walkable = function (ax, ay, az, bx, by, bz)
    local dz = (tonumber(bz) or 0) - (tonumber(az) or 0);
    local dx = (tonumber(bx) or 0) - (tonumber(ax) or 0);
    return math.sqrt((dx * dx) + (dz * dz)) <= wall_at;
end

local player = { x = 0, y = 0, z = 0 };
local function aim_at(d) return { x = 0, y = 0, z = d, source = 'route-pursuit' }; end

-- 1. A clear aim is returned untouched, and costs nothing.
wall_at = 100;
local got = accessxi.nav_pursuit_aim_reachable(player, aim_at(9));
claim(got ~= nil and got.z == 9, 'a walkable aim is passed straight through');
claim(got.clamped_to == nil, 'and is not marked as clamped');

-- 2. THE REGRESSION. A blocked aim is pulled back to what IS reachable.
wall_at = 6.0;
got = accessxi.nav_pursuit_aim_reachable(player, aim_at(9));
claim(got ~= nil, 'a blocked nine-yalm aim still yields an aim');
claim(got.z <= 6.0, 'that stops short of the obstacle, got ' .. tostring(got and got.z));
claim(got.z > 5.4, 'but takes the furthest reachable point, got ' .. tostring(got and got.z));
claim(got.clamped_from ~= nil and got.clamped_to ~= nil, 'and records that it clamped');

-- 3. The bearing is preserved -- walking the aim back along the SAME line is
--    what keeps the tone steady. A clamp that swung the direction would make
--    the beacon unholdable, which is a defect this addon has already had once.
wall_at = 5.0;
got = accessxi.nav_pursuit_aim_reachable({ x = 0, y = 0, z = 0 },
    { x = 6, y = 0, z = 8 });        -- a 10-yalm aim on a 3-4-5 bearing
claim(got ~= nil, 'a diagonal blocked aim still yields one');
local bearing_in = math.atan2(8, 6);
local bearing_out = math.atan2(got.z, got.x);
claim(math.abs(bearing_in - bearing_out) < 0.001,
    'and keeps the bearing exactly, in=' .. bearing_in .. ' out=' .. bearing_out);

-- 4. PINNED. When even the floor cannot be reached, return nil so the block
--    below -- wall-escape, sightline, detour -- finally gets its turn. Before
--    this, that block had been unreachable since 2026-08-22.
wall_at = 1.0;
claim(accessxi.nav_pursuit_aim_reachable(player, aim_at(9)) == nil,
    'a pinned player yields nil rather than a useless two-yalm aim');
wall_at = 3.9;
claim(accessxi.nav_pursuit_aim_reachable(player, aim_at(9)) == nil,
    'and the floor is four yalms, not less');
wall_at = 4.6;
claim(accessxi.nav_pursuit_aim_reachable(player, aim_at(9)) ~= nil,
    'while just above the floor still steers');

-- 5. An aim already inside the floor and blocked is pinned, not shortened.
wall_at = 1.0;
claim(accessxi.nav_pursuit_aim_reachable(player, aim_at(3)) == nil,
    'a short blocked aim is pinned');

-- 6. SAFETY. A missing or raising test must never invent a refusal -- the
--    beacon going silent is worse than an imperfect aim.
accessxi.nav_leg_walkable = nil;
got = accessxi.nav_pursuit_aim_reachable(player, aim_at(9));
claim(got ~= nil and got.z == 9, 'no walkability test available means aim unchanged');
accessxi.nav_leg_walkable = function () error('boom'); end
got = accessxi.nav_pursuit_aim_reachable(player, aim_at(9));
claim(got ~= nil and got.z == 9, 'a raising test means aim unchanged');
accessxi.nav_leg_walkable = function () return true; end
claim(accessxi.nav_pursuit_aim_reachable(nil, aim_at(9)) ~= nil, 'a nil player is safe');
claim(accessxi.nav_pursuit_aim_reachable(player, nil) == nil, 'a nil aim is safe');

-- 7. THE WIRING. It must be called, and a blocked aim must FALL THROUGH rather
--    than return -- otherwise the defence below stays as dead as it has been.
claim(src:find('accessxi.nav_pursuit_aim_reachable(player, pursuit_aim)', 1, true) ~= nil,
    'the pursuit path calls the clamp');
local call_at = src:find('local reachable = accessxi.nav_pursuit_aim_reachable', 1, true);
local ret_at = call_at and src:find('return reachable;', call_at, true) or nil;
local clamp_at = src:find('aim = accessxi.nav_beacon_clamp_to_sightline(', 1, true);
claim(call_at ~= nil and ret_at ~= nil, 'and returns the clamped aim');
claim(clamp_at ~= nil and clamp_at > call_at,
    'the sightline clamp sits after it, and is now reachable when the aim is blocked');
claim(src:find('falling through to sightline', 1, true) ~= nil,
    'and the fall-through is logged so the next one of these is one grep');


-- 8. THE WORDS MUST AGREE WITH THE TONE.
--
-- There are TWO aim producers. The beacon tone comes from
-- nav_beacon_route_target, where this clamp lives; the spoken instruction comes
-- from nav_indexed_lookahead_target, which had none. Live 2026-08-27 in Jugner:
-- "nav pursuit CLAMPED 10.3 -> 5.1 yalms" and, the same second,
-- guidance="Go straight 9 yalms." The player stood still for 33 seconds. They
-- reported the beacon "seemed a little better" but still walked them into
-- walls -- the half that improved was the half that had been fixed.
claim(src:find('accessxi.nav_pursuit_aim_reachable, player, route_target', 1, true) ~= nil,
    'the SPOKEN target is clamped too, not only the tone');
local speech_at = src:find('accessxi.nav_pursuit_aim_reachable, player, route_target', 1, true);
local phrase_at = speech_at and src:find('accessxi.nav_guidance_phrase(player, route_target, next_target, false)', speech_at, true) or nil;
claim(phrase_at ~= nil and phrase_at > speech_at,
    'and is clamped BEFORE the phrase is built, not after');
claim(src:find('nav guidance CLAMPED', 1, true) ~= nil,
    'and says so in the log, distinctly from the tone clamp');

-- 9. A CLAMPED TARGET IS SHORT ON PURPOSE and must never be looked past.
--
-- nav_guidance_phrase looks past a target within 5 yalms to the next waypoint,
-- up to 30 away, so the player is not given a bearing to their own feet. For a
-- clamped target that reaches straight back into whatever the clamp just
-- steered around -- and a blocked aim clamps short by definition.
claim(src:find('next_target ~= nil and route_target.clamped_to == nil', 1, true) ~= nil,
    'the look-past is refused for a clamped target');
local guard_at = src:find('next_target ~= nil and route_target.clamped_to == nil', 1, true);
local sub_at = guard_at and src:find('route_target = next_target;', guard_at, true) or nil;
claim(sub_at ~= nil and sub_at > guard_at,
    'and the guard sits before the substitution it prevents');

print(('pursuit clamp: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
