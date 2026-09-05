-- Drives the REAL provider module against the REAL deployed artifact.
-- Run: luajit tests/lua/test_walk_graph_provider_real.lua <addon_dir>
--
-- Everything else in this suite runs the provider against stubs, which proves
-- the wiring and nothing about the geometry. This one loads the 31 MB artifact
-- through the real incremental loader, runs a real edge-state A*, funnels it
-- over real certified portals, and checks what comes back out is a walking
-- instruction a blind player could actually follow.
--
-- Three past mistakes on this project are why it asserts what it asserts:
-- hand-written acceptance scripts produced three false conclusions before
-- anyone ran the real loader; a route was declared verified from a file nobody
-- could find; and the first "clearance" model reported one broken stride out of
-- 6,469 while a quarter of walked ground was actually unroutable. So this test
-- refuses to conclude anything the artifact itself cannot demonstrate.

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

-- Stand up just enough of the addon for the module to run unmodified.
local accessxi = {};
_G.accessxi = accessxi;
_G.accessxi_paths = {
    addon_path = function(...)
        local parts = { ... };
        return addon .. '\\' .. table.concat(parts, '\\');
    end,
};

package.path = addon .. '\\modules\\?.lua;' .. package.path;
accessxi.walk_graph_library = assert(dofile(addon .. '\\modules\\walk_graph.lua'),
    'walk_graph library failed to load');

local chunk = assert(loadfile(addon .. '\\modules\\walk_graph_route.lua'));
local env = { T = T, accessxi = accessxi, accessxi_paths = _G.accessxi_paths,
              log_line = H.log_line, tick = H.tick };
setmetatable(env, { __index = _G });
setfenv(chunk, env);
local provider = assert(chunk(), 'provider module returned nothing');

print('\n== zone containment ==');
check('the provider declares zone 102', provider.zone() == 102, provider.zone());
check('it does not apply to another zone',
    not provider.applies({ zone = 100, x = 0, z = 0, y = 0 },
                         { zone = 100, x = 1, z = 1, y = 0 }));
check('it does not apply to a cross-zone destination',
    not provider.applies({ zone = 102, x = 0, z = 0, y = 0 },
                         { zone = 100, x = 1, z = 1, y = 0 }));
check('it applies inside La Theine',
    provider.applies({ zone = 102, x = 0, z = 0, y = 0 },
                     { zone = 102, x = 1, z = 1, y = 0 }));

print('\n== the artifact loads incrementally, inside a frame budget ==');
-- Two real positions from the recorded La Theine survey.
local START = { zone = 102, x = -638.616, z = 274.570, y = 15.160 };
local GOAL  = { zone = 102, name = 'Galaihaurat', x = -481.196, z = 220.547, y = -7.028 };

local points, mode, message = provider.begin(START, GOAL);
check('the first request reports pending while it loads', mode == 'pending',
    ('mode=%s msg=%s'):format(tostring(mode), tostring(message)));
check('pending says something rather than going quiet',
    tostring(message or '') ~= '', tostring(message));

local slices, worst, total = 0, 0, 0;
local began = os.clock();
while (not provider.is_loaded() and slices < 20000) do
    local t0 = os.clock();
    local _, m, msg = provider.poll();
    local elapsed = (os.clock() - t0) * 1000.0;
    if (elapsed > worst) then worst = elapsed; end
    slices = slices + 1;
    if (m == 'unavailable') then
        check('the artifact loaded', false, tostring(msg));
        print(('\n%d passed, %d failed\n'):fmt(pass, fail + 1));
        os.exit(1);
    end
end
total = (os.clock() - began) * 1000.0;
check('the artifact finished loading', provider.is_loaded(),
    ('after %d slices'):format(slices));
check('no single load slice blocks a 16ms frame', worst < 16.0,
    ('worst slice %.1fms over %d slices, %.0fms total'):format(worst, slices, total));
print(('        load: %d slices, worst %.1fms, %.0fms total'):format(slices, worst, total));

print('\n== a real route, funnelled over certified portals ==');
local route_points, route_mode, route_message;
route_points, route_mode, route_message = provider.begin(START, GOAL);
check('the search starts once the graph is loaded',
    route_mode == 'pending' or route_mode == 'ready',
    ('mode=%s msg=%s'):format(tostring(route_mode), tostring(route_message)));

local search_slices, search_worst = 0, 0;
began = os.clock();
while (route_mode == 'pending' and search_slices < 20000) do
    local t0 = os.clock();
    route_points, route_mode, route_message = provider.poll();
    local elapsed = (os.clock() - t0) * 1000.0;
    if (elapsed > search_worst) then search_worst = elapsed; end
    search_slices = search_slices + 1;
end
local search_total = (os.clock() - began) * 1000.0;

check('a route came back', route_mode == 'ready' and route_points ~= nil,
    ('mode=%s msg=%s'):format(tostring(route_mode), tostring(route_message)));

if (route_mode == 'ready' and route_points ~= nil) then
    check('no search slice blocks a 16ms frame', search_worst < 16.0,
        ('worst %.1fms over %d slices, %.0fms total'):format(
            search_worst, search_slices, search_total));
    print(('        search: %d slices, worst %.1fms, %.0fms total, %d corners')
        :format(search_slices, search_worst, search_total, route_points:len()));

    check('it is a funnel, not a centroid chain',
        route_points:len() > 2 and route_points:len() < 200,
        route_points:len());

    local tagged, mislabelled = true, nil;
    for i = 1, route_points:len() do
        local p = route_points[i];
        if (p.route_override_id ~= 'lathine-walk-graph-v2') then
            tagged = false; mislabelled = i; break;
        end
    end
    check('every corner is tagged as the walk graph', tagged, mislabelled);

    check('every corner is in La Theine',
        (function()
            for i = 1, route_points:len() do
                if (route_points[i].zone ~= 102) then return false; end
            end
            return true;
        end)());

    local finite_ok = true;
    for i = 1, route_points:len() do
        local p = route_points[i];
        if (type(p.x) ~= 'number' or type(p.z) ~= 'number' or type(p.y) ~= 'number'
            or p.x ~= p.x or p.z ~= p.z or p.y ~= p.y) then
            finite_ok = false; break;
        end
    end
    check('every corner has finite coordinates', finite_ok);

    -- The route must actually go where it was asked to go, and start where the
    -- player actually is. A route that begins somewhere else is exactly the
    -- failure that walked a blind player into terrain.
    local first, last = route_points[1], route_points[route_points:len()];
    local d0 = math.sqrt((first.x - START.x) ^ 2 + (first.z - START.z) ^ 2);
    local d1 = math.sqrt((last.x - GOAL.x) ^ 2 + (last.z - GOAL.z) ^ 2);
    check('it starts at the player', d0 < 0.001, ('%.3f yalms away'):format(d0));
    check('it ends at the destination', d1 < 0.001, ('%.3f yalms away'):format(d1));

    -- Consecutive corners must be distinct, or the beacon is handed a bearing
    -- computed from a zero-length vector -- pure noise to steer by.
    local degenerate = nil;
    for i = 2, route_points:len() do
        local a, b = route_points[i - 1], route_points[i];
        if (math.abs(a.x - b.x) < 1e-6 and math.abs(a.z - b.z) < 1e-6) then
            degenerate = i; break;
        end
    end
    check('no two consecutive corners are the same point', degenerate == nil, degenerate);

    local walked = 0;
    for i = 2, route_points:len() do
        local a, b = route_points[i - 1], route_points[i];
        walked = walked + math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2);
    end
    local straight = math.sqrt((GOAL.x - START.x) ^ 2 + (GOAL.z - START.z) ^ 2);
    check('the route is longer than the straight line but not absurd',
        walked > straight and walked < straight * 8,
        ('walked %.1f vs straight %.1f'):format(walked, straight));
    print(('        route: %.1f yalms over %d corners (straight line %.1f)')
        :format(walked, route_points:len(), straight));
end

print('\n== a destination off the mapped surface is refused, out loud ==');
local _, off_mode, off_message = provider.begin(START,
    { zone = 102, name = 'Nowhere', x = 99999, z = 99999, y = 0 });
check('an unmappable destination is rejected',
    off_mode == 'unreachable' or off_mode == 'no-path',
    ('mode=%s'):format(tostring(off_mode)));
check('the rejection carries something to say',
    tostring(off_message or '') ~= '', tostring(off_message));

print('\n== turning it off releases the graph ==');
provider.set_enabled(false);
check('the graph is released', not provider.is_loaded());
check('an in-flight load is released too', not provider.is_loading());
check('the switch reads back off', provider.enabled() == false);
provider.set_enabled(true);
check('the switch reads back on', provider.enabled() == true);

-- The switch PERSISTS to disk, so a test that flips it changes what the real
-- addon does next time the player launches. Leaving it on would silently enable
-- a feature that is deliberately defaulted off. Remove the file so the shipped
-- default decides, and prove the removal took.
local settings = addon .. [[\data\nav-walkgraph-mode.txt]];
os.remove(settings);
local leftover = io.open(settings, 'r');
if (leftover ~= nil) then leftover:close(); end
check('the test leaves no setting behind to re-enable it', leftover == nil, settings);

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
