-- Faithful stub of the Ashita addon environment that accessxi.load_code_module
-- builds, so navigation modules can be exercised outside the game.
-- Mirrors accessxi_reader.lua:1527-1555 (setfenv with __index = _G).

local H = {};

local T_methods = {};
T_methods.__index = T_methods;
function T_methods:len() return #self; end
function T_methods:append(v) self[#self + 1] = v; return self; end
function T_methods:clear() for i = #self, 1, -1 do self[i] = nil; end return self; end
function T_methods:contains(v)
    for _, x in ipairs(self) do if (x == v) then return true; end end
    return false;
end

function H.T(t) return setmetatable(t or {}, T_methods); end

-- Ashita string extensions used by the navigation modules.
function string.fmt(s, ...) return string.format(s, ...); end
function string.contains(s, sub) return s:find(sub, 1, true) ~= nil; end

H.log = {};
function H.log_line(text) H.log[#H.log + 1] = tostring(text); end

-- Ashita's millisecond clock. Advances on every read so throttled code paths
-- in tests behave like they do in game rather than freezing on one instant.
H.tick_ms = 0;
function H.tick() H.tick_ms = H.tick_ms + 1; return H.tick_ms; end

-- verbatim from accessxi_reader.lua:71526
function H.nav_split_tsv(line)
    local parts = H.T{};
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do parts:append(part); end
    return parts;
end

function H.nav_clean_field(text)
    if (text == nil) then return ''; end
    return (tostring(text):gsub('[\t\r\n]', ' '):gsub('^%s+', ''):gsub('%s+$', ''));
end

-- verbatim from accessxi_reader.lua:69509
function H.nav_distance(a, b)
    if (a == nil or b == nil) then return 0; end
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0);
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0);
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz;
end

-- Loads a module exactly the way the addon does.
function H.load_module(path, survey_path, mesh_route_stub)
    local accessxi = {
        nav_recorded_survey_nodes = H.T{},
        nav_recorded_survey_loaded = false,
        nav_recorded_survey_load_error = '',
        nav_recorded_survey_path = survey_path,
        nav_route_last_reject_reason = '',
        nav_route_overrides = H.T{},
        nav_load_route_overrides = function() end,
        nav_lathine_recorded_corridor_candidate = function() return nil; end,
        nav_recorded_survey_zoneline_edge_priority = function() return 0; end,
    };
    local env = {
        T = H.T,
        accessxi = accessxi,
        log_line = H.log_line,
        tick = H.tick,
        nav_distance = H.nav_distance,
        nav_split_tsv = H.nav_split_tsv,
        nav_clean_field = H.nav_clean_field,
        nav_compute_mesh_route = mesh_route_stub or function() return H.T{}; end,
        nav_compute_closest_mesh_route = function() return H.T{}; end,
        nav_lathine_direct_target_safe = function() return false; end,
    };
    setmetatable(env, { __index = _G });
    local chunk = assert(loadfile(path));
    setfenv(chunk, env);
    chunk();
    return accessxi, env;
end

return H;
