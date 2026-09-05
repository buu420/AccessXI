package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;
local A = [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
local accessxi = H.load_module(A .. [[\modules\mesh_route_repair.lua]], '', nil);

-- Count probe calls, and mimic what the LIVE probe costs per call: a table
-- allocation plus a pcall plus a wrapper, on top of the native Detour query.
local calls = 0;
local function live_like_probe()
    local function inner_valid(point) return math.abs(point.z) <= 400; end
    local function inner_wall(point) return math.min(math.abs(point.z) * 0.05, 10.0); end
    return {
        valid = function(x, y, z)
            calls = calls + 1;
            local ok, r = pcall(inner_valid, T{ zone = 102, x = x, y = y, z = z });
            return ok and r == true;
        end,
        wall = function(x, y, z)
            calls = calls + 1;
            local ok, r = pcall(inner_wall, T{ zone = 102, x = x, y = y, z = z });
            if (not ok) then return 0; end
            return tonumber(r) or 0;
        end,
    };
end

-- A route shaped like the real one measured on La Theine: 48 waypoints, nearly
-- all pinned against a wall, with long legs.
local route = T{};
for i = 1, 48 do
    route:append(T{ zone = 102, x = i * 12.0, z = 0.15, y = 0, kind = 'route', source = 'navmesh' });
end

local probe = live_like_probe();
local t0 = os.clock();
local out = accessxi.nav_mesh_route_repair(route, probe);
local ms = (os.clock() - t0) * 1000;
print(('repair of a 48-waypoint wall-hugging route:'):fmt());
print(('  probe calls : %d'):fmt(calls));
print(('  lua overhead: %.1f ms  (table alloc + pcall only, no Detour)'):fmt(ms));
print(('  output      : %d waypoints'):fmt(out:len()));
-- Native Detour cost measured by navprobe: 1445 probes in 31.7 ms.
print(('  + native Detour at 0.022 ms/probe: %.0f ms'):fmt(calls * 0.022));
print(('  ESTIMATED TOTAL IN GAME: %.0f ms'):fmt(ms + calls * 0.022));
