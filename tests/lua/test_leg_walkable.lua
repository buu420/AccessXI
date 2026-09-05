-- Behaviour tests for the leg walkability predicate.
-- Run: luajit tests/lua/test_leg_walkable.lua <addon_dir>
--
-- CanSeeDestination is a LINE OF SIGHT test, not a walkability test: you can
-- see straight up a cliff face. Live 2026-08-20, the beacon aimed at a leg
-- 1.6 yalms away and 3.2 yalms UP, and the sight test cheerfully returned
-- visible=true. Climb limits calibrated on the player's own walked ground:
-- across 3201 recorded climbs the steepest was rise/run 0.64, while descents
-- reached 2.24 -- you can drop off a ledge you cannot climb back up.

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
local clear = function() return true; end
local W = function(ax, ay, az, bx, by, bz) return accessxi.nav_leg_walkable(ax, ay, az, bx, by, bz, clear); end

-- FFXI: lower Y is HIGHER ground, so a smaller destination y means climbing.
print('\n== the live failure ==');
check('a 3.2 yalm climb over 1.6 yalms of ground is rejected',
    W(19.3, 15.7, 23.5, 17.7, 12.5, 23.3) == false, 'accepted a 63 degree climb');

print('\n== ground the player actually walked must stay walkable ==');
check('the steepest recorded climb (ratio 0.64) is accepted',
    W(0, 10.0, 0, 3.0, 10.0 - 1.92, 0) == true, 'rejected real walked ground');
check('a gentle slope is accepted', W(0, 10, 0, 5, 9.5, 0) == true);
check('flat ground is accepted', W(0, 10, 0, 5, 10, 0) == true);

print('\n== dropping is not climbing ==');
check('a steep drop is allowed', W(0, 10, 0, 2, 13.5, 0) == true,
    'you can drop off a ledge');
check('an absurd drop is still rejected', W(0, 10, 0, 1, 40, 0) == false);

print('\n== short steps ==');
check('a small step up is fine', W(0, 10, 0, 0.3, 9.5, 0) == true);
check('a vertical wall at your feet is not', W(0, 10, 0, 0.2, 6.0, 0) == false);

print('\n== line of sight still applies ==');
local blocked = function() return false; end
check('a flat but blocked leg is rejected',
    accessxi.nav_leg_walkable(0, 10, 0, 5, 10, 0, blocked) == false);
check('with no sight test, slope alone decides',
    accessxi.nav_leg_walkable(0, 10, 0, 5, 10, 0, nil) == true
        and accessxi.nav_leg_walkable(19.3, 15.7, 23.5, 17.7, 12.5, 23.3, nil) == false);

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
