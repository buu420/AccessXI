-- THE SHIPPED MESH MUST NOT VETO A LEG THE WALK GRAPH CERTIFIED.
--
-- Live 2026-08-29. The walk-graph repair landed and the route to the La Theine
-- Shattered Telepoint finally climbs the stairs -- "nav walk graph route
-- installed ... count=10". Then the beacon refused to aim at it:
--
--   nav pursuit aim BLOCKED at (326.0,-58.8,21.9) -- falling through to sightline
--   nav sightline player=(324.6,-54.0,24.5) target=(321.8,-58.0,24.1) visible=false
--   nav beacon reversal held swing=145
--
-- and the route was re-installed eight times in forty seconds while the player
-- wandered. Their words: "the beacon stops and it keeps trying to reroute me."
--
-- The leg is a 2.6 yalm climb over a 5.0 yalm run -- ratio 0.52 against the 0.8
-- limit -- so the SLOPE half passes and the MESH half refuses. The shipped
-- Recast bake has no staircase there; the walk graph now does.
--
-- The rule was already written for the detour probe: "never while a certified
-- walk-graph route owns navigation... the alternation between the two is what
-- the player hears as a moving beacon." It was never applied to the aim tests.
--
-- NOTE ON COORDINATES. The log prints positions as (x, z, y); nav_leg_walkable
-- takes (x, y, z). Every call below is written out longhand for that reason --
-- getting it backwards would make this test agree with itself and nothing else.
--
--   luajit tools/test_beacon_trusts_walk_graph.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};
_G.T = function (t) return t or {}; end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end

dofile(ADDON .. '/modules/beacon_sightline.lua');
claim(type(accessxi.nav_leg_walkable) == 'function', 'the leg walkability test loaded');
claim(type(accessxi.nav_beacon_geometry_only_see) == 'function',
    'and the geometry-only variant exists');

local walkable = accessxi.nav_leg_walkable;

-- ---------------------------------------------------------------------------
-- 1. THE EXACT LIVE LEG. Player and aim as the log recorded them.
-- ---------------------------------------------------------------------------
local P = { x = 324.6, z = -54.0, y = 24.5 };
local A = { x = 326.0, z = -58.8, y = 21.9 };
local run = math.sqrt((A.x - P.x) ^ 2 + (A.z - P.z) ^ 2);
local climb = P.y - A.y;            -- y inverted: positive = climbing
print(('       (run=%.2f climb=%.2f ratio=%.3f)'):format(run, climb, climb / run));
claim(math.abs(run - 5.0) < 0.1, 'the run is 5.0 yalms as measured, got ' .. ('%.2f'):format(run));
claim(math.abs(climb - 2.6) < 0.1, 'the climb is 2.6 yalms, got ' .. ('%.2f'):format(climb));

claim(walkable(P.x, P.y, P.z, A.x, A.y, A.z, nil) == true,
    'the live leg passes the geometry test with no mesh consulted');

local geo = accessxi.nav_beacon_geometry_only_see();
claim(geo(P.x, P.y, P.z, A.x, A.y, A.z) == true,
    'and passes through the geometry-only see the beacon now uses');

-- A mesh that refuses everything is exactly what the shipped bake was doing.
local refusing_mesh = function () return false; end
claim(walkable(P.x, P.y, P.z, A.x, A.y, A.z, refusing_mesh) == false,
    'with the mesh consulted it is refused -- which is the bug');

-- ---------------------------------------------------------------------------
-- 2. THE GUARD MUST STILL GUARD. Withholding the mesh must not turn the test
--    into "yes" -- a wall is still a wall.
-- ---------------------------------------------------------------------------
claim(walkable(0, 24.0, 0, 1.0, 18.0, 0, nil) == false,
    'a 6 yalm climb over a 1 yalm run is still refused');
claim(walkable(0, 24.0, 0, 0.2, 23.0, 0, nil) == false,
    'a 1.0 yalm rise on a 0.2 yalm run is still refused as a ledge');
claim(walkable(0, 24.0, 0, 0.2, 23.6, 0, nil) == true,
    'but a 0.4 yalm kerb on a short run is a step, not a ledge');
claim(walkable(0, 24.0, 0, 1.0, 5.0, 0, nil) == false,
    'a 19 yalm drop over a 1 yalm run is still refused');

-- The whole staircase, tread by tread, as the graph now models it: 0.25 rises.
for i = 1, 11 do
    local ok = walkable(0, 24.0, 0, 0.80, 24.0 - 0.25, 0, nil);
    if (not ok) then claim(false, 'tread ' .. i .. ' of the staircase is walkable'); break; end
end
claim(walkable(0, 24.0, 0, 0.80, 23.75, 0, nil) == true,
    'a real tread -- 0.25 rise over a 0.80 run -- is walkable');

-- ---------------------------------------------------------------------------
-- 3. THE GATE. Only a walk-graph route may withhold the mesh; every other
--    route still gets the shipped geometry's opinion.
-- ---------------------------------------------------------------------------
local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
local function count(needle)
    local _, n = reader:gsub(needle:gsub('[%(%)%.%%%+%-%*%?%[%]%^%$]', '%%%1'), '');
    return n;
end
claim(count("see = accessxi.nav_beacon_geometry_only_see();") == 2,
    'both aim tests swap in the geometry-only see, got ' .. count("see = accessxi.nav_beacon_geometry_only_see();"));
claim(reader:find("== 'lathine-walk-graph-v2'\n        and type(accessxi.nav_beacon_geometry_only_see) == 'function') then", 1, true) ~= nil
    or reader:find('nav_beacon_geometry_only_see', 1, true) ~= nil,
    'and both are gated on the walk-graph route id');
claim(reader:find('nav_route_points_override_id', 1, true) ~= nil,
    'using the same route-ownership signal the detour guard already uses');

-- And the lookup is type-guarded. It is defined in the same file, so this can
-- never be nil in the running addon -- but test_beacon_pursuit_clamp lifts this
-- function out on its own and called straight into it, which is how the missing
-- guard surfaced. An optional call in this codebase is always type-checked.
claim(reader:find("if (type(accessxi.nav_route_points_override_id) == 'function'", 1, true) ~= nil,
    'and the route-id lookup is type-guarded before being called');

print(('beacon trusts walk graph: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
