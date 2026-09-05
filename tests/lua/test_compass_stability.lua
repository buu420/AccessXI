-- Behaviour tests for compass heading hysteresis.
-- Run: luajit tests/lua/test_compass_stability.lua <addon_dir>
--
-- The compass announces one of eight 45-degree sectors. With no angular
-- hysteresis, a player walking a straight line whose heading sits on a sector
-- boundary flip-flops across it on normal walking wobble. Measured live on
-- 2026-08-20: 21 spoken "Facing ..." announcements in 27 seconds, alternating
-- southwest/south/southeast, each interrupting the last and starving the
-- navigation beacon that polls after it in the same frame.

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

local accessxi = H.load_module(addon .. [[\modules\compass_stability.lua]], '', nil);

local D2R = math.pi / 180;

-- Yaw that reads as due south under the addon's convention.
local function yaw_for(degrees) return -(degrees * D2R); end

print('\n== raw sector behaviour is preserved ==');
check('with no previous heading it reports the raw sector',
    accessxi.nav_compass_direction_stable(yaw_for(0), '') == 'east',
    accessxi.nav_compass_direction_stable(yaw_for(0), ''));
check('nil yaw is unknown',
    accessxi.nav_compass_direction_stable(nil, 'south') == 'unknown');
check('a large, unambiguous turn is reported',
    accessxi.nav_compass_direction_stable(yaw_for(180), 'east') == 'west',
    accessxi.nav_compass_direction_stable(yaw_for(180), 'east'));

print('\n== the boundary must not chatter ==');
-- 'south' centres on 270 degrees; the southwest boundary sits at 247.5.
check('a heading just past the boundary holds the current sector',
    accessxi.nav_compass_direction_stable(yaw_for(246), 'south') == 'south',
    accessxi.nav_compass_direction_stable(yaw_for(246), 'south'));
check('a heading well into the next sector does switch',
    accessxi.nav_compass_direction_stable(yaw_for(235), 'south') == 'southwest',
    accessxi.nav_compass_direction_stable(yaw_for(235), 'south'));
check('the same margin applies on the other side',
    accessxi.nav_compass_direction_stable(yaw_for(294), 'south') == 'south',
    accessxi.nav_compass_direction_stable(yaw_for(294), 'south'));

print('\n== the live flip-flop must collapse ==');
-- Walking due south with normal wobble across the 247.5 boundary.
local wobble = { 270, 260, 249, 246, 250, 245, 252, 244, 268, 247, 251, 243,
                 270, 246, 253, 245, 249, 247, 271, 244, 250 };
local function count_changes(use_hysteresis)
    local current, changes = '', 0;
    for _, deg in ipairs(wobble) do
        local next_direction;
        if (use_hysteresis) then
            next_direction = accessxi.nav_compass_direction_stable(yaw_for(deg), current);
        else
            next_direction = accessxi.nav_compass_direction_raw(yaw_for(deg));
        end
        if (next_direction ~= current) then changes = changes + 1; current = next_direction; end
    end
    return changes;
end
local raw_changes = count_changes(false);
local stable_changes = count_changes(true);
check(('%d raw announcements collapse to %d'):fmt(raw_changes, stable_changes),
    raw_changes >= 8 and stable_changes <= 2,
    ('raw=%d stable=%d'):fmt(raw_changes, stable_changes));

print('\n== a real turn still gets through promptly ==');
local current = 'south';
local turned = 0;
for _, deg in ipairs({ 270, 260, 240, 215, 190, 180 }) do
    local next_direction = accessxi.nav_compass_direction_stable(yaw_for(deg), current);
    if (next_direction ~= current) then turned = turned + 1; current = next_direction; end
end
check('a deliberate 90 degree turn is announced', current == 'west' and turned >= 1,
    ('ended on %s after %d changes'):fmt(current, turned));

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
