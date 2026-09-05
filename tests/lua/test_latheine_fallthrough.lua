-- Exercises the real nav_compute_route_with_zoneline_approach source, sliced out
-- of the addon monolith and run against stubs.
-- Run: luajit tests/lua/test_latheine_fallthrough.lua <addon_dir>

local addon = (...) or arg[1] or [[C:\Users\buu42\Ashita\addons\accessxi_reader]];
package.path = './?.lua;' .. package.path;
local H = require('ashita_harness');
local T = H.T;

local MONOLITH = addon .. [[\accessxi_reader.lua]];

local pass, fail = 0, 0;
local function check(name, ok, detail)
    if (ok) then pass = pass + 1; print('  PASS  ' .. name);
    else fail = fail + 1; print('  FAIL  ' .. name .. '  -> ' .. tostring(detail)); end
end

-- Locate the function by name and take it up to its matching column-0 'end',
-- so the test survives edits that shift line numbers.
local function slice()
    local out, capturing = {}, false;
    for line in io.lines(MONOLITH) do
        if (not capturing) then
            if (line:find('^function accessxi%.nav_compute_route_with_zoneline_approach')) then
                capturing = true; out[#out + 1] = line;
            end
        else
            out[#out + 1] = line;
            if (line == 'end') then break; end
        end
    end
    assert(#out > 0, 'nav_compute_route_with_zoneline_approach not found');
    return table.concat(out, '\n');
end

-- calls[name] counts how many times each downstream provider was consulted.
local function build(calls, opts)
    local none = function() return T{}; end
    local accessxi = {
        nav_route_last_reject_reason = '',
        escape_probe_log_text = function(s) return tostring(s or ''); end,
        nav_point_is_zoneline = function(p)
            return tostring(p and p.name or ''):lower():find('zone line', 1, true) ~= nil;
        end,
        -- the survey yields to collision terrain (collision_required = true)
        nav_recorded_survey_route = function() return T{}, false, true; end,
        nav_zoneline_approach_candidates = function() return T{}; end,
        nav_append_final_zoneline_point = function() end,
        nav_nearby_zoneline_direct_route_allowed = function() return false; end,
        nav_lathine_recorded_ravine_escape_required = function() return false; end,
        nav_point_effective_kind = function() return 'npc'; end,
        nav_arrival_radius = function() return 3.0; end,
        nav_compute_mesh_endpoint_approach = function() return T{}; end,
        nav_transport_clear = function() end,
        nav_dangruf_fount_drop_clear = function() end,
        nav_dangruf_fount_drop_route = none,
        nav_verified_elevator_route = function() return T{}, false; end,
        nav_dat_collision_route = function()
            calls.dat = (calls.dat or 0) + 1; return T{}, 'error', 'dat unavailable';
        end,
        nav_dat_collision_zoneline_approach = function() return T{}, 'error', ''; end,
    };
    local function counted(key, ret)
        return function() calls[key] = (calls[key] or 0) + 1; return ret and ret() or T{}; end;
    end
    accessxi.nav_lathine_recorded_corridor_route = function()
        calls.corridor = (calls.corridor or 0) + 1; return T{}, false;
    end
    accessxi.nav_lathine_recorded_ravine_escape_route = counted('ravine');
    accessxi.nav_lathine_lower_ravine_recovery_route = counted('lower_ravine');
    accessxi.nav_route_override_points = counted('override', opts and opts.override or nil);

    local env = {
        T = T, accessxi = accessxi, log_line = H.log_line,
        nav_distance = H.nav_distance, nav_clean_field = H.nav_clean_field,
        nav_compute_mesh_route = function()
            calls.mesh = (calls.mesh or 0) + 1; return T{};   -- mesh has no answer
        end,
    };
    setmetatable(env, { __index = _G });
    local chunk = assert(loadstring(slice(), 'route_fn'));
    setfenv(chunk, env);
    chunk();
    return accessxi, calls;
end

local PLAYER = { zone = 102, x = -638.616, z = 274.570, y = 15.160 };

print('\n== non-zoneline destination, survey yielded, mesh empty ==');
local calls = {};
local accessxi = build(calls);
local route = accessxi.nav_compute_route_with_zoneline_approach(PLAYER,
    { zone = 102, name = 'Galaihaurat', x = -481.196, z = 220.547, y = -7.028 });

check('verified route overrides are consulted', (calls.override or 0) > 0,
    ('override=%d corridor=%d ravine=%d lower=%d mesh=%d')
        :fmt(calls.override or 0, calls.corridor or 0, calls.ravine or 0,
             calls.lower_ravine or 0, calls.mesh or 0));
check('recorded corridor is consulted', (calls.corridor or 0) > 0, calls.corridor or 0);
check('ravine escape is consulted', (calls.ravine or 0) > 0, calls.ravine or 0);

print('\n== an override that has an answer must win ==');
local calls2 = {};
local a2 = build(calls2, { override = function()
    return T{ { zone = 102, x = 1, z = 1, y = 0 }, { zone = 102, x = 2, z = 2, y = 0 } };
end });
local r2 = a2.nav_compute_route_with_zoneline_approach(PLAYER,
    { zone = 102, name = 'Galaihaurat', x = -481.196, z = 220.547, y = -7.028 });
check('override route is returned to the caller', r2 ~= nil and r2:len() > 1,
    r2 and r2:len() or 'nil');

print(('\n%d passed, %d failed\n'):fmt(pass, fail));
os.exit(fail == 0 and 0 or 1);
