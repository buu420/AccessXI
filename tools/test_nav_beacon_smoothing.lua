-- The beacon's reversal hysteresis, replayed against the REAL shipped code.
--
--   luajit tools/test_nav_beacon_smoothing.lua
--
-- The live failure, 2026-08-22 11:35-11:36: a STATIONARY player, one unchanged
-- aim point (-136.8, 201.9), and the beacon alternating every pulse:
--
--   nav beacon front:05 pan=-0.16 delta=9      <- centred
--   nav beacon front:12 pan=0.99  delta=-84    <- hard right
--   nav beacon front:05 pan=-0.16 delta=9
--   nav beacon front:12 pan=0.99  delta=-84    ... for two solid minutes
--
-- Half the tones were a 93-degree lie, so centring was impossible. The
-- hysteresis that exists to reject exactly this was switched off, because
-- `sightline_clamped` and `detour_active` bought a bypass and both are true on
-- most pulses of an ordinary mesh route.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;
tick = function () return 0; end;
log_line = function () end;

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1; print('  ok  ' .. text);
    else failures = failures + 1; print('  FAIL ' .. text); end
end

-- The one piece of the host the module needs.
accessxi.nav_normalize_angle = function (a)
    while (a > math.pi) do a = a - (2 * math.pi); end
    while (a < -math.pi) do a = a + (2 * math.pi); end
    return a;
end

local ok_load, err = pcall(dofile, ADDON .. '/modules/beacon_sightline.lua');
if (not ok_load) then
    print('  FAIL beacon_sightline failed to load: ' .. tostring(err));
    os.exit(1);
end

local function deg(d) return d * math.pi / 180; end
local function to_deg(r) return r * 180 / math.pi; end

local function reset()
    accessxi.nav_beacon_previous_delta = nil;
    accessxi.nav_beacon_pending_delta = nil;
    accessxi.nav_beacon_reversal_holds = 0;
    accessxi.nav_beacon_sightline_clamped = false;
    accessxi.nav_beacon_detour_active = false;
end

print('What may bypass the hysteresis:');
reset();
accessxi.nav_beacon_sightline_clamped = true;
claim(accessxi.nav_beacon_urgent_correction('indexed-lookahead') == false,
    'a clamped aim is NOT an urgent correction (it is how the aim was chosen)');
accessxi.nav_beacon_sightline_clamped = false;
accessxi.nav_beacon_detour_active = true;
claim(accessxi.nav_beacon_urgent_correction('sightline-detour') == false,
    'an active detour is NOT an urgent correction');
reset();
claim(accessxi.nav_beacon_urgent_correction('live-route-return') == true,
    'return-to-route still bypasses immediately');
claim(accessxi.nav_beacon_urgent_correction('wall-escape') == true,
    'wall escape still bypasses immediately');

print('Replaying the live alternation (9, -84, 9, -84, ...):');
reset();
local played = {};
for pulse = 1, 10 do
    local sample = (pulse % 2 == 1) and deg(9) or deg(-84);
    local urgent = accessxi.nav_beacon_urgent_correction('sightline-detour');
    played[#played + 1] = to_deg(accessxi.nav_beacon_smoothed_heading(sample, urgent));
end
local worst = 0;
for _, p in ipairs(played) do worst = math.max(worst, math.abs(p - 9)); end
claim(worst < 1.0,
    ('every pulse plays the centred heading; worst deviation %.1f degrees'):format(worst));
local swings = 0;
for i = 2, #played do
    if (math.abs(played[i] - played[i - 1]) >= 90) then swings = swings + 1; end
end
claim(swings == 0, ('no 90-degree swing is ever played (%d)'):format(swings));

print('A genuine turn must still get through:');
reset();
accessxi.nav_beacon_smoothed_heading(deg(9), false);
local first = to_deg(accessxi.nav_beacon_smoothed_heading(deg(-84), false));
local second = to_deg(accessxi.nav_beacon_smoothed_heading(deg(-84), false));
claim(math.abs(first - 9) < 1.0, 'the first sample of a big turn is held for one pulse');
claim(math.abs(second - (-84)) < 1.0,
    'a second sample that AGREES lands, so a real turn is heard on the next pulse');

print('Two disagreeing samples in a row are not smothered:');
reset();
accessxi.nav_beacon_smoothed_heading(deg(0), false);
accessxi.nav_beacon_smoothed_heading(deg(120), false);      -- held
local third = to_deg(accessxi.nav_beacon_smoothed_heading(deg(-120), false));
claim(math.abs(third - (-120)) < 1.0,
    'after one hold the next sample plays, so the beacon never goes stale');

print('An urgent correction is never delayed:');
reset();
accessxi.nav_beacon_smoothed_heading(deg(9), false);
local urgent_play = to_deg(accessxi.nav_beacon_smoothed_heading(deg(-170), true));
claim(math.abs(urgent_play - (-170)) < 1.0,
    'a return-to-route reversal plays on the pulse it happens');

print(('%d claims passed, %d failed'):format(passes, failures));
os.exit(failures == 0 and 0 or 1);
