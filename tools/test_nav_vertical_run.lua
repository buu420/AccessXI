-- Ramp / stairwell guidance, including the negative gates sol required.
--
--   luajit tools/test_nav_vertical_run.lua
--
-- Live geometry of 2026-08-22: East Ronfaure, walking at the King Ranperre's
-- Tomb zone line. Trigger (200.0, -544.6) at height -8.5; the last route
-- waypoints sat 1.6 / 3.2 / 4.4 yalms above the player at 1-5 yalms horizontal.
-- The index jammed at 182 of 184 and the player circled the ramp for 2 minutes.
--
-- FFXI Y points DOWN: a smaller y is higher ground.

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

local ok_load, err = pcall(dofile, ADDON .. '/modules/nav_vertical_run.lua');
if (not ok_load) then
    print('  FAIL nav_vertical_run failed to load: ' .. tostring(err));
    os.exit(1);
end

local function route(list)
    local pts = T{};
    for _, p in ipairs(list) do
        pts:append(T{ x = p[1], z = p[2], y = p[3], zone = 101 });
    end
    return pts;
end

-- The tomb ramp, from the waypoints actually logged at 01:15 on 2026-08-22.
-- Grades 0.63 to 2.15 -- 32 to 65 degrees. This is what a ramp looks like.
local ramp = route({
    { 199.8, -532.0,  2.0 },
    { 199.9, -534.0,  0.9 },
    { 200.0, -536.1, -0.1 },
    { 200.0, -538.1, -4.4 },
    { 200.0, -541.1, -6.3 },
    { 200.0, -544.6, -8.5 },
});

print('Detecting the run:');
local run = accessxi.nav_vertical_run_detect(ramp, 1);
claim(run ~= nil, 'the tomb ramp is recognised as a vertical run');
claim(run ~= nil and run.direction == 1, 'it is recognised as a CLIMB (y decreasing is up)');
claim(run ~= nil and run.last == 6, 'the run reaches the trigger at the top');

local flat = route({ { 0, 0, 0 }, { 0, -8, 0 }, { 0, -16, 0.1 }, { 0, -24, 0 } });
claim(accessxi.nav_vertical_run_detect(flat, 1) == nil, 'flat ground is not a vertical run');

-- THE LIVE REGRESSION of 2026-08-22 11:28: this is real King Ranperre's Tomb
-- terrain, 3 to 8 degrees, and it was detected as a ramp. That put ordinary
-- walking under the ramp rules, where anything unproven pauses the index, and
-- the player could not centre the beacon.
local hillside = route({
    { -143.2, 188.2, 5.4 },
    { -140.3, 178.9, 4.9 },
    { -140.2, 174.5, 3.7 },
    { -140.0, 165.5, 2.5 },
});
claim(accessxi.nav_vertical_run_detect(hillside, 1) == nil,
    'a 3-to-8 degree hillside is NOT a ramp and stays under ordinary steering');

-- Apex: up then down. The run must stop at the top, not continue over it.
local hill = route({
    { 0, 0, 0 }, { 0, -3, -2 }, { 0, -6, -4 }, { 0, -9, -2 }, { 0, -12, 0 },
});
local hill_run = accessxi.nav_vertical_run_detect(hill, 1);
claim(hill_run ~= nil and hill_run.last == 3, 'a run stops at the apex, it does not continue over the top');

-- A corner sharper than 25 degrees ends the run.
local corner = route({
    { 0, 0, 0 }, { 0, -3, -2 }, { 0, -6, -4 }, { 5, -8, -6 },
});
local corner_run = accessxi.nav_vertical_run_detect(corner, 1);
claim(corner_run ~= nil and corner_run.last == 3, 'a run stops before a corner sharper than 25 degrees');

print('Aiming along the run:');
local player = T{ x = 199.8, z = -532.0, y = 2.0, zone = 101 };
local aim, walked = accessxi.nav_vertical_run_aim(player, ramp, run);
claim(aim ~= nil, 'an aim point is produced');
claim(walked >= accessxi.nav_vertical_run_aim_min,
    ('the aim is at least %.0f yalms along the run (%.1f) so the bearing is steady')
        :format(accessxi.nav_vertical_run_aim_min, walked or 0));
claim(aim ~= nil and aim.z <= -536.0, 'the aim is further UP the ramp, not the waypoint underfoot');

-- Standing near the top, the aim must never fall back past the trigger.
local near_top = T{ x = 200.0, z = -541.1, y = -6.3, zone = 101 };
local top_run = accessxi.nav_vertical_run_detect(ramp, 5);
local top_aim = accessxi.nav_vertical_run_aim(near_top, ramp, top_run);
claim(top_aim ~= nil and top_aim.z == -544.6, 'near the top the aim is the trigger itself, still on the run');

-- The aim must never be a waypoint already walked past: the run begins at the
-- waypoint BEHIND the player, and accumulating from there once returned it.
local past_first = T{ x = 200.0, z = -535.9, y = -0.1, zone = 101 };
local past_run = accessxi.nav_vertical_run_detect(ramp, 3);
local past_aim = accessxi.nav_vertical_run_aim(past_first, ramp, past_run);
claim(past_aim ~= nil and past_aim.z < -536.0,
    'the aim is never a waypoint the player has already walked past');

print('Progress by projection, never by horizontal nearness:');
-- Halfway up: position agrees with the route height there.
local midway = T{ x = 200.0, z = -536.1, y = -0.1, zone = 101 };
local idx, advanced, reason = accessxi.nav_vertical_run_progress(midway, ramp, run, 1);
claim(advanced and idx == 4,
    ('a player standing on ramp waypoint 3 is now headed to waypoint 4 (index %d, %s)'):format(idx, reason));

-- THE LIVE JAM: the old rule refused this because the next waypoint was 4.4
-- yalms above. Projection does not care about that -- it cares whether the
-- player is on the run.
local at_four = T{ x = 200.0, z = -538.1, y = -4.4, zone = 101 };
idx, advanced, reason = accessxi.nav_vertical_run_progress(at_four, ramp, run, 3);
claim(advanced and idx == 5,
    'the index advances onto a waypoint more than 4 yalms above the player (the live jam)');

-- Negative gate 1: a wrong-floor point. Same footprint, 9 yalms below.
local wrong_floor = T{ x = 200.0, z = -536.1, y = 8.9, zone = 101 };
idx, advanced, reason = accessxi.nav_vertical_run_progress(wrong_floor, ramp, run, 1);
claim(not advanced and idx == 1,
    ('a player on the wrong floor does not advance (%s)'):format(reason));

-- Negative gate 2: 2D-visible but Y-mismatched. Directly under the ramp top.
local underneath = T{ x = 200.0, z = -544.6, y = 2.0, zone = 101 };
idx, advanced, reason = accessxi.nav_vertical_run_progress(underneath, ramp, run, 1);
claim(not advanced,
    ('standing underneath the top of the ramp does not count as reaching it (%s)'):format(reason));

-- Negative gate 3: a vertically overlapping switchback. Two legs share an XZ
-- footprint and their heights are within tolerance of each other.
local switchback = route({
    { 0,  0,  0.0 },
    { 0, -3, -1.6 },
    { 0, -3, -3.2 },
    { 0,  0, -4.8 },
});
local sb_run = accessxi.nav_vertical_run_detect(switchback, 1);
if (sb_run ~= nil) then
    local on_overlap = T{ x = 0.2, z = -1.5, y = -2.4, zone = 101 };
    idx, advanced, reason = accessxi.nav_vertical_run_progress(on_overlap, switchback, sb_run, 1);
    claim(not advanced and reason == 'ambiguous',
        ('an overlapping switchback refuses rather than guessing a floor (%s)'):format(reason));
else
    claim(true, 'the overlapping switchback is not even treated as a single run');
end

-- Forward only.
local back_down = T{ x = 199.9, z = -534.0, y = 0.9, zone = 101 };
idx, advanced, reason = accessxi.nav_vertical_run_progress(back_down, ramp, run, 5);
claim(not advanced and idx == 5, ('the index never runs backwards (%s)'):format(reason));

-- Off the run entirely.
local far_away = T{ x = 260.0, z = -500.0, y = 0.0, zone = 101 };
idx, advanced, reason = accessxi.nav_vertical_run_progress(far_away, ramp, run, 2);
claim(not advanced and reason == 'off-run', 'a player who has left the ramp does not advance');

print(('%d claims passed, %d failed'):format(passes, failures));
os.exit(failures == 0 and 0 or 1);
