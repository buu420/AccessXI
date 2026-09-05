-- Which tone the player hears, and whether "centred" is something a person can
-- actually hold.
--
--   luajit tools/test_nav_beacon_centre.lua
--
-- The complaint: "sometimes it's difficult to center it and I feel like I'm zig
-- zagging", then "the same weird beacon that I can't center" in La Theine.
--
-- The aim was NOT at fault: the live log at 13:14:50-55 shows the pursuit point
-- sliding smoothly, one source, 9 yalms ahead throughout. What the player was
-- fighting was the TONE: the centre bin was about 4.8 degrees wide, delivered
-- roughly twice a second while they covered three to four yalms between tones.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;
tick = function () return 0; end;
log_line = function () end;
accessxi.nav_normalize_angle = function (a)
    while (a > math.pi) do a = a - (2 * math.pi); end
    while (a < -math.pi) do a = a + (2 * math.pi); end
    return a;
end

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1; print('  ok  ' .. text);
    else failures = failures + 1; print('  FAIL ' .. text); end
end

local ok_load, err = pcall(dofile, ADDON .. '/modules/beacon_sightline.lua');
if (not ok_load) then
    print('  FAIL beacon_sightline failed to load: ' .. tostring(err));
    os.exit(1);
end

local function deg(d) return d * math.pi / 180; end
local function bin(d)
    local prefix, b = accessxi.nav_beacon_bin_for_delta(deg(d));
    return prefix, b;
end

print('Centre is wide enough to hold:');
for _, d in ipairs({ 0, 3, 7, 10, 14 }) do
    local prefix, b = bin(d);
    claim(prefix == 'front' and b == 6, ('%d degrees off reads as centred'):format(d));
end
for _, d in ipairs({ -3, -7, -10, -14 }) do
    local prefix, b = bin(d);
    claim(prefix == 'front' and b == 6, ('%d degrees off reads as centred'):format(d));
end

print('But not so wide that a real turn is hidden:');
for _, d in ipairs({ 20, -20, 35, -35 }) do
    local prefix, b = bin(d);
    claim(b ~= 6, ('%d degrees off does NOT read as centred (bin %d)'):format(d, b));
end

print('Left and right still separate, and behind is still behind:');
local _, right = bin(40);
local _, left = bin(-40);
claim(right ~= left, 'a turn one way and the other give different tones');
local rear_prefix = bin(175);
claim(rear_prefix == 'rear', 'a target behind the player is still a rear tone');
local _, hard = bin(80);
claim(hard == 0 or hard == 12, ('a near-perpendicular target is a hard pan (bin %d)'):format(hard));

print('The live La Theine sequence, before and after:');
-- Exactly the deltas logged at 13:14:50-57 while the aim slid smoothly.
local live = { 33, 21, -43, -51, 10, 29, 7, -53, 3, 18, 39, 25 };
local function churn(deadband)
    local saved = accessxi.nav_beacon_centre_deadband;
    accessxi.nav_beacon_centre_deadband = deadband;
    local changes, previous, centred = 0, nil, 0;
    for _, d in ipairs(live) do
        local prefix, b = accessxi.nav_beacon_bin_for_delta(deg(d));
        if (previous ~= nil and b ~= previous) then changes = changes + 1; end
        if (b == 6) then centred = centred + 1; end
        previous = b;
    end
    accessxi.nav_beacon_centre_deadband = saved;
    return changes, centred;
end
local before_changes, before_centred = churn(0);
local after_changes, after_centred = churn(deg(15));
print(('       tone changes %d -> %d, centred tones %d -> %d over %d pulses'):format(
    before_changes, after_changes, before_centred, after_centred, #live));
claim(after_centred > before_centred,
    'more of the live sequence now reads as "walk this way"');
claim(after_changes <= before_changes,
    'and the tone moves no more often than it did');

print('The deadband is the documented 15 degrees:');
claim(math.abs(accessxi.nav_beacon_centre_deadband - deg(15)) < 0.0001,
    'centre deadband is 15 degrees');

print(('%d claims passed, %d failed'):format(passes, failures));
os.exit(failures == 0 and 0 or 1);
