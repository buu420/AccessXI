-- Behaviour tests for approving a proposed override of the beacon aim point.
-- Run: luajit tests/lua/test_beacon_override.lua <addon_dir>
--
-- nav_apply_dynamic_obstacle and nav_apply_wall_avoidance run AFTER the aim
-- point has been validated and silently REPLACE it. Live 2026-08-20: a verified
-- north-east detour target was swapped for a 'wall-escape' target 5.4 yalms up
-- a ledge, and because 'wall-escape' also counts as an explicit correction the
-- beacon followed it into the rock. Nine fixes were defeated this way.
--
-- Rule: one component chooses the aim point. Others may VETO it. None may
-- substitute an aim point that has not itself been checked.

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

local PLAYER = { zone = 102, x = -1.2, z = 35.2, y = 15.4 };
local APPROVED = T{ zone = 102, x = 1.86, z = 38.29, y = 15.65, source = 'sightline-detour' };
local ESCAPE_UP = T{ zone = 102, x = -3.0, z = 29.3, y = 10.0, source = 'wall-escape' };
local ESCAPE_OK = T{ zone = 102, x = 2.5, z = 38.0, y = 15.5, source = 'wall-escape' };
local clear = function() return true; end

print('\n== an override that aims up a ledge is refused ==');
check('the verified target survives an unwalkable proposal',
    accessxi.nav_beacon_approve_override(PLAYER, APPROVED, ESCAPE_UP, clear) == APPROVED,
    'the wall-escape target was accepted');

print('\n== a sound override is still allowed ==');
check('a walkable proposal is accepted',
    accessxi.nav_beacon_approve_override(PLAYER, APPROVED, ESCAPE_OK, clear) == ESCAPE_OK);

print('\n== guards ==');
check('an unchanged proposal passes straight through',
    accessxi.nav_beacon_approve_override(PLAYER, APPROVED, APPROVED, clear) == APPROVED);
check('a nil proposal is treated as a veto and keeps the verified target',
    accessxi.nav_beacon_approve_override(PLAYER, APPROVED, nil, clear) == APPROVED);
check('with no verified target the proposal is used',
    accessxi.nav_beacon_approve_override(PLAYER, nil, ESCAPE_UP, clear) == ESCAPE_UP);
check('with no walkability test the proposal is left alone',
    accessxi.nav_beacon_approve_override(PLAYER, APPROVED, ESCAPE_UP, nil) == ESCAPE_UP);

print('\n== line of sight is honoured too ==');
local blind = function() return false; end
check('a proposal behind geometry is refused',
    accessxi.nav_beacon_approve_override(PLAYER, APPROVED, ESCAPE_OK, blind) == APPROVED);

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
