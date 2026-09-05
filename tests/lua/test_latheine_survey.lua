-- Behaviour tests for the La Theine walked-survey router (zone 102).
-- Run: luajit tests/lua/test_latheine_survey.lua <addon_dir>

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');

local MODULE = addon .. [[\modules\recorded_survey_navigation.lua]];
local SURVEY = addon .. [[\data\ffxi-nav-recorded-survey.tsv]];

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

-- A short, local mesh tail so marked-zoneline edges can be exercised.
-- Stands in for the installed navmesh's short hop from a marked survey node to
-- the zone-line trigger: evenly spaced waypoints, like a real Detour path.
local function tail_stub(from, to)
    local dx, dz, dy = to.x - from.x, to.z - from.z, to.y - from.y;
    local dist = math.sqrt(dx * dx + dz * dz + dy * dy);
    local steps = math.max(1, math.min(5, math.ceil(dist / 10.0)));
    local tail = H.T{};
    for i = 0, steps do
        local t = i / steps;
        tail:append({ zone = to.zone, name = (i == steps) and to.name or 'tail',
            x = from.x + dx * t, z = from.z + dz * t, y = from.y + dy * t });
    end
    return tail;
end

local accessxi = H.load_module(MODULE, SURVEY, tail_stub);

print('\n== survey loads ==');
check('survey loads 6499 nodes',
    accessxi.nav_recorded_survey_load() and accessxi.nav_recorded_survey_nodes:len() == 6499,
    accessxi.nav_recorded_survey_load_error);

-- Player standing on the walked trail at the West Ronfaure end (survey node 1).
local ON_TRAIL = { zone = 102, x = -559.850, z = 677.532, y = 0.000 };

local function route_to(name, x, z, y, extra)
    local point = { zone = 102, name = name, x = x, z = z, y = y };
    if (extra) then for k, v in pairs(extra) do point[k] = v; end end
    return accessxi.nav_recorded_survey_route(ON_TRAIL, point);
end

print('\n== quest and mission destinations the walk covers ==');
-- The Rescue Drill objective NPC. 2.98 yalms off the walked trail.
local r, required, yielded = route_to('Galaihaurat', -481.196, 220.547, -7.028);
check('routes to Galaihaurat (Rescue Drill NPC)', r:len() > 1,
    ('len=%d required=%s yielded=%s reason=%q'):fmt(r:len(), tostring(required),
        tostring(yielded), accessxi.nav_route_last_reject_reason));

r = route_to('Telepoint', 420.000, 20.200, 19.100);
check('routes to Telepoint', r:len() > 1, ('len=%d'):fmt(r:len()));

r = route_to('Survival Guide', 775.000, -18.000, 28.500);
check('routes to Survival Guide', r:len() > 1, ('len=%d'):fmt(r:len()));

r = route_to('Field Manual', -576.994, 661.371, -4.033);
check('routes to Field Manual', r:len() > 1, ('len=%d'):fmt(r:len()));

print('\n== destinations the walk does NOT cover must yield, never block ==');
-- Chocobo Tracks sits 22 yalms off-trail; the mesh must still get its turn.
r, required, yielded = route_to('Chocobo Tracks', -556.742, 523.814, 0.000);
check('uncovered destination yields to mesh (not blocked)',
    r:len() == 0 and yielded == true and required ~= true,
    ('len=%d required=%s yielded=%s'):fmt(r:len(), tostring(required), tostring(yielded)));

print('\n== regressions that must keep working ==');
-- West Ronfaure is a main exit.  With no corridor overrides available the walk
-- has no answer, and must hand off rather than veto the way back to San d'Oria.
r, required, yielded = route_to('West Ronfaure zone line', -558.569, 688.049, -7.049);
check('West Ronfaure hands off when the walk has no corridor',
    r:len() > 1 or required ~= true,
    ('len=%d required=%s yielded=%s reason=%q'):fmt(r:len(), tostring(required),
        tostring(yielded), accessxi.nav_route_last_reject_reason));

-- Same for a refresh whose connector cannot bridge back on a west leg.
local r6, rq6 = accessxi.nav_recorded_survey_route(ON_TRAIL,
    { zone = 102, name = 'West Ronfaure zone line', x = -558.569, z = 688.049, y = -7.049 },
    H.T{}, 1);
check('failed west refresh recovery hands off too', r6:len() > 1 or rq6 ~= true,
    ('len=%d required=%s'):fmt(r6:len(), tostring(rq6)))

-- Ordelle's z2u8 is the one wired marked-zoneline edge.
r = route_to("Ordelle's Caves zone line z2u8", -60.125, 148.001, 27.231,
    { source = 'zonesearch:947204730:1:1', to_zone = 193 });
check("Ordelle's z2u8 marked edge still routes", r:len() > 1, ('len=%d'):fmt(r:len()));

-- A player far off the trail must fall through to the other providers.
local OFF_TRAIL = { zone = 102, x = -770.84, z = 274.50, y = -4.61 };
local r2, req2, yld2 = accessxi.nav_recorded_survey_route(OFF_TRAIL,
    { zone = 102, name = 'Telepoint', x = 420.000, z = 20.200, y = 19.100 });
check('off-trail player falls through to other providers',
    r2:len() == 0 and req2 ~= true,
    ('len=%d required=%s yielded=%s'):fmt(r2:len(), tostring(req2), tostring(yld2)));

print('\n== Valkurm Dunes exit ==');
-- The player marked this zone line during the walk (survey node 1969), but no
-- override, no marked edge and no survey coverage served it: the live log shows
-- "Valkurm Dunes zone line is not reachable from here" 14 times.
r = route_to('Valkurm Dunes zone line', 159.989, -760.190, 31.950,
    { source = 'zonesearch:880095866:1:1', to_zone = 103 });
check('routes to the Valkurm Dunes zone line', r:len() > 1,
    ('len=%d reason=%q'):fmt(r:len(), accessxi.nav_route_last_reject_reason));

-- If its tail cannot be verified it must hand back to the mesh, never block.
local a2 = H.load_module(MODULE, SURVEY, function() return H.T{}; end);
local rv, rq, yd = a2.nav_recorded_survey_route(ON_TRAIL,
    { zone = 102, name = 'Valkurm Dunes zone line', x = 159.989, z = -760.190, y = 31.950,
      source = 'zonesearch:880095866:1:1', to_zone = 103 });
check('Valkurm yields to the mesh when its tail is unverifiable',
    rv:len() == 0 and rq ~= true and yd == true,
    ('len=%d required=%s yielded=%s'):fmt(rv:len(), tostring(rq), tostring(yd)));

print('\n== must never claim a destination it cannot deliver ==');
-- Standing on the node that is also nearest the destination yields a one-node
-- course.  The caller only accepts len > 1, so claiming it strands the player.
local AT_NODE = { zone = 102, x = 419.941, z = 20.321, y = 19.104 };
local r3, rq3, yd3 = accessxi.nav_recorded_survey_route(AT_NODE,
    { zone = 102, name = 'Telepoint', x = 419.941, z = 20.321, y = 19.104 });
check('player already at the destination node does not block',
    r3:len() > 1 or rq3 ~= true,
    ('len=%d required=%s yielded=%s'):fmt(r3:len(), tostring(rq3), tostring(yd3)));

-- A refresh passes the owned points back in.  If the connector cannot bridge,
-- that must not block an ordinary destination that used to reach the mesh.
local r4, rq4, yd4 = accessxi.nav_recorded_survey_route(ON_TRAIL,
    { zone = 102, name = 'Telepoint', x = 420.000, z = 20.200, y = 19.100 },
    H.T{}, 1);
check('failed owned-route recovery does not block an ordinary destination',
    r4:len() > 1 or rq4 ~= true,
    ('len=%d required=%s yielded=%s'):fmt(r4:len(), tostring(rq4), tostring(yd4)));

print('\n== standing off the walked line near a marked zone line ==');
-- Reproduces the 2026-08-20 08:57:56 failure: The Rescue Drill, cross-zone leg
-- to Ruillont in Ordelle's Caves, player 8.6 horizontal / 3.6 vertical off the
-- walked line.  The walk cannot snap them, but that must hand off, not strand.
local OFF_NEAR_MARK = { zone = 102, x = -51.117, z = 159.123, y = 35.500 };
local r5, rq5, yd5 = accessxi.nav_recorded_survey_route(OFF_NEAR_MARK,
    { zone = 102, name = "Ordelle's Caves zone line", x = -60.125, z = 148.001,
      y = 27.231, source = 'zonesearch:947204730:1:1', to_zone = 193 });
check('off-trail near a marked zone line hands off instead of stranding',
    r5:len() > 1 or rq5 ~= true,
    ('len=%d required=%s yielded=%s reason=%q'):fmt(r5:len(), tostring(rq5),
        tostring(yd5), accessxi.nav_route_last_reject_reason));

print('\n== invariant: the walk answers or hands off, it never vetoes ==');
-- A veto (required == true with no route) leaves the player with a refusal and
-- no alternative.  Sweep real destinations from on-trail, off-trail and
-- far-off-trail positions and assert none of them produce one.
local sweep_points = {
    { 'Galaihaurat', -481.196, 220.547, -7.028 },
    { 'Telepoint', 420.000, 20.200, 19.100 },
    { 'Chocobo Tracks', -556.742, 523.814, 0.000 },
    { 'West Ronfaure zone line', -558.569, 688.049, -7.049 },
    { 'Jugner Forest zone line', 801.831, -37.618, 24.326 },
    { "Ordelle's Caves zone line z2u6", -276.649, 99.618, 20.594 },
    { 'Shattered Telepoint', 334.024, -56.596, 24.055 },
};
local sweep_players = {
    { 'on-trail', ON_TRAIL },
    { 'off-trail 8y', OFF_NEAR_MARK },
    { 'far off-trail', { zone = 102, x = -770.84, z = 274.50, y = -4.61 } },
};
local vetoes = {};
for _, who in ipairs(sweep_players) do
    for _, d in ipairs(sweep_points) do
        local rr, req = accessxi.nav_recorded_survey_route(who[2],
            { zone = 102, name = d[1], x = d[2], z = d[3], y = d[4] });
        if (rr:len() <= 1 and req == true) then
            vetoes[#vetoes + 1] = ('%s -> %s'):fmt(who[1], d[1]);
        end
    end
end
check(('no veto across %d player/destination combinations'):fmt(
        #sweep_players * #sweep_points),
    #vetoes == 0, table.concat(vetoes, '; '));

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
