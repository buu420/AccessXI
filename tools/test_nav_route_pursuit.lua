-- The beacon's one rule: aim at the point on the route a fixed distance ahead.
--
--   luajit tools/test_nav_route_pursuit.lua
--
-- These claims are about what the PLAYER HEARS. The measure is the pulse-to-
-- pulse change in the bearing they are asked to face, because that is the thing
-- that made centring impossible: live 2026-08-22 11:42, eight seconds of
-- ordinary walking produced -54, -38, 34, 44, -72, -43, 85, -97 degrees.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;
log_line = function () end;

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1; print('  ok  ' .. text);
    else failures = failures + 1; print('  FAIL ' .. text); end
end

local ok_load, err = pcall(dofile, ADDON .. '/modules/nav_route_pursuit.lua');
if (not ok_load) then
    print('  FAIL nav_route_pursuit failed to load: ' .. tostring(err));
    os.exit(1);
end

local function bearing(player, aim)
    return math.atan2(aim.x - player.x, aim.z - player.z) * 180 / math.pi;
end
local function angle_diff(a, b)
    local d = a - b;
    while (d > 180) do d = d - 360; end
    while (d < -180) do d = d + 360; end
    return math.abs(d);
end

-- A curving route with 8-yalm legs, the shape the builder actually emits.
local route = T{};
for i = 0, 40 do
    local a = i * 0.09;
    route:append(T{ x = math.sin(a) * 60, z = i * 8.0, y = 0, zone = 101 });
end

print('A player standing still hears a bearing that does not move:');
local still = T{ x = math.sin(0.45) * 60, z = 40.0, y = 0, zone = 101 };
local first_aim = accessxi.nav_route_pursuit_aim(still, route, 6);
local worst_still = 0;
for _ = 1, 12 do
    local again = accessxi.nav_route_pursuit_aim(still, route, 6);
    worst_still = math.max(worst_still, angle_diff(bearing(still, again), bearing(still, first_aim)));
end
claim(first_aim ~= nil, 'an aim point is produced');
claim(worst_still < 0.001,
    ('twelve pulses from one standing position give one identical bearing (%.4f degrees of drift)'):format(worst_still));

print('Walking the route, the bearing changes smoothly:');
local swings, worst_walk, samples = {}, 0, 0;
local previous = nil;
local index = 2;
for stepn = 0, 60 do
    -- 1.5 yalms per pulse along the route, with half a yalm of wander -- more
    -- than a real player drifts.
    local along = stepn * 1.5;
    local leg = math.floor(along / 8.0) + 1;
    local frac = (along % 8.0) / 8.0;
    if (leg + 1 > route:len()) then break; end
    local a, b = route[leg], route[leg + 1];
    local jitter = ((stepn % 2 == 0) and 0.5 or -0.5);
    local player = T{
        x = a.x + ((b.x - a.x) * frac) + jitter,
        z = a.z + ((b.z - a.z) * frac),
        y = 0, zone = 101 };
    local aim, _, target = accessxi.nav_route_pursuit_aim(player, route, index);
    if (aim == nil) then break; end
    index = target or index;
    local b_now = bearing(player, aim);
    if (previous ~= nil) then
        local swing = angle_diff(b_now, previous);
        swings[#swings + 1] = swing;
        worst_walk = math.max(worst_walk, swing);
        samples = samples + 1;
    end
    previous = b_now;
end
local total = 0;
for _, s in ipairs(swings) do total = total + s; end
claim(samples > 30, ('the walk produced %d pulses to measure'):format(samples));
claim(worst_walk < 25,
    ('no pulse ever swings more than 25 degrees (worst %.1f) -- live it was 97'):format(worst_walk));
claim((total / math.max(1, samples)) < 8,
    ('the average change between pulses is small (%.1f degrees)'):format(total / math.max(1, samples)));
local reversals = 0;
for _, s in ipairs(swings) do if (s >= 90) then reversals = reversals + 1; end end
claim(reversals == 0, ('no reversal is ever played (%d)'):format(reversals));

print('The aim is always genuinely ahead, never underfoot:');
local near = T{ x = route[10].x, z = route[10].z, y = 0, zone = 101 };
local aim_near, achieved = accessxi.nav_route_pursuit_aim(near, route, 10);
claim(achieved >= accessxi.nav_route_pursuit_min,
    ('the aim is at least %.0f yalms away (%.1f)'):format(accessxi.nav_route_pursuit_min, achieved));

print('Approaching the end, the aim settles on the destination:');
local last = route[route:len()];
local nearly = T{ x = last.x, z = last.z - 3.0, y = 0, zone = 101 };
local aim_end, _, end_index = accessxi.nav_route_pursuit_aim(nearly, route, route:len() - 1);
claim(aim_end ~= nil and math.abs(aim_end.x - last.x) < 0.001 and math.abs(aim_end.z - last.z) < 0.001,
    'the aim becomes the route end rather than running off it');
claim(end_index == route:len(), 'and reports the final waypoint as the target');

print('A route that doubles back cannot teleport the aim across the zone:');
local folded = T{};
for i = 0, 12 do folded:append(T{ x = 0, z = i * 8.0, y = 0, zone = 101 }); end
for i = 1, 12 do folded:append(T{ x = 6, z = 96 - (i * 8.0), y = 0, zone = 101 }); end
local on_outbound = T{ x = 0.2, z = 24.0, y = 0, zone = 101 };
local at_out = accessxi.nav_route_pursuit_project(on_outbound, folded, 4);
claim(at_out ~= nil and at_out.segment <= 10,
    ('the projection stays on the outbound leg near the current index (segment %d)'):format(at_out and at_out.segment or -1));

-- ---------------------------------------------------------------------------
-- A ROUTE THAT CLIMBS PASSES OVER THE GROUND IT STARTED ON.
--
-- Live 2026-08-31 in La Theine, walking to the Shattered Telepoint. Y IS
-- INVERTED in FFXI -- smaller y is higher -- and the telepoint sits on a
-- platform at y=19.1 while the player circles its base at y=24.3, five yalms
-- below. Same route (count=11), same index (9/11), no mutation between, the
-- player moved 1.6 yalms:
--
--   19:14:13 nav pursuit aim=(325.2,-58.7,22.3) ... index=9/11
--   19:14:16 nav pursuit aim=(338.7,-59.3,19.1) ... index=9/11
--
-- The aim jumped 13.5 yalms onto a platform overhead, because this projection
-- measures the player against the route in XZ ONLY -- so a leg running along
-- the platform directly above them looks like the nearest place they are
-- standing. The addon's two other route matchers both weight height
-- (accessxi_reader.lua:71953 and :72365); this one did not.
--
-- Every point in every fixture above is at y = 0, which is why nothing here
-- could ever have caught it.
print('A route directly overhead is not where the player is standing:');
local stacked = T{};
-- The ground leg the player is actually on, three yalms to the south of them.
for i = 0, 4 do stacked:append(T{ x = 320 + (i * 5), z = -63, y = 24.3, zone = 102 }); end
-- Then the platform leg, doubling back west five yalms ABOVE and passing
-- exactly over the player's head. In XZ it is the nearer of the two, which is
-- the whole trap: measured flat, the route overhead looks like where you stand.
for i = 0, 4 do stacked:append(T{ x = 340 - (i * 5), z = -60, y = 19.1, zone = 102 }); end
local below = T{ x = 330, z = -60, y = 24.3, zone = 102 };
local at_stacked = accessxi.nav_route_pursuit_project(below, stacked, 3);
claim(at_stacked ~= nil and at_stacked.segment <= 4,
    ('the projection stays on the leg at the players own height, not the one overhead (segment %s)')
        :format(at_stacked and at_stacked.segment or 'nil'));
claim(at_stacked ~= nil and at_stacked.vertical ~= nil and math.abs(at_stacked.vertical) < 1.0,
    ('and reports how far above or below the chosen leg is (%.2f)')
        :format(at_stacked and (tonumber(at_stacked.vertical) or -1) or -1));
-- The returned distance is what callers log as "horizontal"; height may decide
-- WHICH leg wins but must not silently turn that number into a 3D distance.
-- The chosen ground leg is 3 yalms away in XZ and 0 in height, so a distance
-- that had absorbed the vertical term would read larger than 3.
claim(at_stacked ~= nil and math.abs((tonumber(at_stacked.distance) or 99) - 3.0) < 0.01,
    ('and distance is still the horizontal one, not a 3D one (%.3f)')
        :format(at_stacked and (tonumber(at_stacked.distance) or -1) or -1));

print(('%d claims passed, %d failed'):format(passes, failures));
os.exit(failures == 0 and 0 or 1);
