-- Offline regression for the dynamic-obstacle steering faults observed live
-- 2026-08-22 01:10-01:20, walking Southern San d'Oria -> Davoi.
--
--   luajit tools/test_nav_beacon_obstacle.lua
--
-- The live failure, from the log: player (104.3,-43.8) walking at route target
-- (107.0,-51.2); the accepted side-step was (100.3,-47.3), which the beacon
-- played as delta=166 -- "turn around" -- and the player crossed the plaza
-- backwards. That point is 1.9 yalms FORWARD along the leg and 5.0 yalms to the
-- side: 69 degrees off the route. A forward-progress test alone accepts it, so
-- the module gates on the bearing too.
--
-- The obstacle was "Sacredlight", another PLAYER character. FFXI applies no
-- collision between players, so it never blocked anything.

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

local ok_load, err = pcall(dofile, ADDON .. '/modules/nav_dynamic_obstacle.lua');
if (not ok_load) then
    print('  FAIL nav_dynamic_obstacle module failed to load: ' .. tostring(err));
    os.exit(1);
end
print('nav_dynamic_obstacle module loaded.');

-- The live leg, verbatim.
local player = T{ zone = 230, x = 104.3, y = 1.0, z = -43.8, index = 7 };
local target = T{ zone = 230, x = 107.0, y = 1.0, z = -51.2 };
local ux, uz = 0.34296, -0.93935;   -- unit vector along the leg

local entities = {};
local zone_id = 230;
accessxi.nav_live_entity_snapshot = function () return entities; end;
accessxi.nav_live_entity_valid = function (pos)
    return pos ~= nil and pos.name ~= nil and (tonumber(pos.zone) or 0) == zone_id;
end;
accessxi.nav_entity_kind = function (pos) return pos.kind or 'enemy'; end;
accessxi.nav_entity_name_looks_like_enemy = function (pos) return pos.reads_as_enemy == true; end;
accessxi.nav_wall_distance = function () return 5.0; end;
accessxi.nav_valid_mesh_position = function () return true; end;

-- Place an entity exactly on the leg, `ahead` yalms along it.
local function on_leg(ahead, overrides)
    local e = T{ zone = zone_id, index = 11, name = 'thing', kind = 'enemy',
        x = player.x + (ahead * ux), z = player.z + (ahead * uz) };
    for k, v in pairs(overrides or {}) do e[k] = v; end
    e.live_kind = e.kind;
    return e;
end

local function decompose(candidate)
    local dx = candidate.x - player.x;
    local dz = candidate.z - player.z;
    local forward = (dx * ux) + (dz * uz);
    local lateral = math.abs((dx * -uz) + (dz * ux));
    return forward, lateral;
end

print('Steerability -- detected is not the same as blocking:');

entities = { on_leg(4.0, { name = 'Sacredlight', kind = 'player' }) };
local aim, obstacle = accessxi.nav_obstacle_avoidance_target(player, target);
claim(aim == nil, 'a player character never moves the aim point');
claim(obstacle ~= nil, 'a player character is still DETECTED, so it can be announced');

zone_id = 230;   -- Southern San d'Oria is in the city suppression list
entities = { on_leg(4.0, { name = 'Ambrotien', kind = 'enemy', reads_as_enemy = false }) };
aim = accessxi.nav_obstacle_avoidance_target(player, target);
claim(aim == nil, 'a named city NPC never moves the aim point');

print('Geometry -- a side-step must still be a step forward:');

-- The live case: obstacle 2 yalms ahead. Both perpendicular candidates land
-- ~5.3 yalms to the side of a 2-yalm advance: 69 degrees off the leg.
zone_id = 149;   -- Davoi: nothing suppressed, a real enemy
entities = { on_leg(2.0, { name = 'Orcish Grunt', zone = 149, reads_as_enemy = true }) };
player.zone = 149;
aim, obstacle = accessxi.nav_obstacle_avoidance_target(player, target);
claim(obstacle ~= nil, 'an enemy two yalms ahead is detected');
claim(aim == nil, 'an obstacle too close to round produces NO steering point (the live 69-degree swerve)');

-- The same obstacle further down the leg: rounding it is a real forward move.
entities = { on_leg(8.0, { name = 'Orcish Grunt', zone = 149, reads_as_enemy = true }) };
aim = accessxi.nav_obstacle_avoidance_target(player, target);
claim(aim ~= nil, 'an enemy eight yalms ahead still yields a side-step');
if (aim ~= nil) then
    local forward, lateral = decompose(aim);
    claim(forward >= 0.5, ('the side-step advances along the leg (%.1f yalms, sol requires >= 0.5)'):format(forward));
    claim(lateral <= (forward * 1.7320508),
        ('the side-step stays within 60 degrees of the leg (%.1f lateral vs %.1f forward)'):format(lateral, forward));
end

-- Guard the exact point the game played, whatever produces it.
print('The point the beacon actually played on 2026-08-22 must be rejected:');
local live_point = { x = 100.3, z = -47.3 };
local f, l = decompose(live_point);
claim(f >= 0.5, ('the live point DID pass a forward-progress test (%.2f yalms) -- gate alone is not enough'):format(f));
claim(l > (f * 1.7320508),
    ('the live point fails the bearing gate (%.2f lateral vs %.2f forward = %.0f degrees)'):format(
        l, f, math.deg(math.atan2(l, f))));

print(('%d claims passed, %d failed'):format(passes, failures));
os.exit(failures == 0 and 0 or 1);
