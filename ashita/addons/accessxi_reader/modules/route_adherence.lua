-- Records how closely the player actually follows the beacon.
--
-- Why this exists. Choosing how far to keep a route back from a cliff edge is a
-- guess unless we know how far the player drifts from the line while following
-- it. Nothing already on disk can answer that: the route-evidence file stores a
-- position and ONE steering target at a handful of event moments, and the survey
-- recorder stores positions and yaw with no route at all. Measuring the survey
-- against a route generated afterwards would measure how much the two routers
-- disagree, which is a different question and would quietly flatter whichever
-- setback we then chose.
--
-- So the route geometry is written down at the moment it is installed, and the
-- player's position is sampled against THAT route while they walk it. Cross-track
-- distance is computed here, against the waypoints actually in force at the time.
--
-- OFF by default. It writes a file and nothing else -- it never steers, never
-- changes a route, and never speaks.
--
-- Rows are one of:
--   route   a route was installed or replaced. Carries every waypoint.
--   sample  the player's position against the route in force.

local M = {};

local SAMPLE_MS = 200;          -- fine enough to see a drift, coarse enough to stay small
local MAX_WAYPOINTS = 512;      -- a runaway route should truncate, and say so

local enabled = false;
local generation = 0;
local last_signature = nil;
local last_sample = 0;
local route_cache = nil;        -- the waypoints as logged, for cross-track
local path = nil;
local wrote_header = false;

local function file_path()
    if (path == nil) then
        path = accessxi_paths.addon_path('data', 'nav-route-adherence.tsv');
    end
    return path;
end

local function tsv(s)
    s = tostring(s or '');
    s = s:gsub('[\t\r\n]', ' ');
    return s;
end

local function write(line)
    local f = io.open(file_path(), 'a');
    if (f == nil) then return false; end
    if (not wrote_header) then
        local existing = io.open(file_path(), 'r');
        local empty = true;
        if (existing ~= nil) then
            empty = existing:read(1) == nil;
            existing:close();
        end
        if (empty) then
            f:write('kind\ttime\tgeneration\tzone\troute_id\tindex\tcount\t'
                .. 'player_x\tplayer_z\tplayer_y\tplayer_yaw\t'
                .. 'aim_x\taim_z\tcross_track\talong_route\tbearing_error\tnote\n');
        end
        wrote_header = true;
    end
    f:write(line);
    f:close();
    return true;
end

-- Enough of the route to notice it changed, without holding a copy to compare.
local function signature(points)
    if (points == nil or points:len() == 0) then return nil; end
    local n = points:len();
    local a, b = points[1], points[n];
    return ('%d:%.2f,%.2f:%.2f,%.2f:%s'):fmt(
        n, tonumber(a.x) or 0, tonumber(a.z) or 0,
        tonumber(b.x) or 0, tonumber(b.z) or 0,
        tostring(a.route_override_id or ''));
end

-- Distance from a point to the polyline, and how far along it that lands.
-- Both are what "following the route" actually means: one is the error we are
-- trying to size, the other says where on the route the error was made.
local function cross_track(points, px, pz)
    if (points == nil or #points < 2) then return nil, nil; end
    local best, best_along, along = nil, nil, 0.0;
    for i = 2, #points do
        local a, b = points[i - 1], points[i];
        local dx, dz = b.x - a.x, b.z - a.z;
        local len2 = (dx * dx) + (dz * dz);
        local t = 0.0;
        if (len2 > 1e-12) then
            t = ((px - a.x) * dx + (pz - a.z) * dz) / len2;
            if (t < 0.0) then t = 0.0; elseif (t > 1.0) then t = 1.0; end
        end
        local qx, qz = a.x + dx * t, a.z + dz * t;
        local d = math.sqrt(((px - qx) ^ 2) + ((pz - qz) ^ 2));
        if (best == nil or d < best) then
            best = d;
            best_along = along + (math.sqrt(len2) * t);
        end
        along = along + math.sqrt(len2);
    end
    return best, best_along;
end

local function log_route(points, zone)
    generation = generation + 1;
    route_cache = {};
    local n = points:len();
    local truncated = n > MAX_WAYPOINTS;
    local limit = truncated and MAX_WAYPOINTS or n;
    for i = 1, limit do
        local p = points[i];
        route_cache[#route_cache + 1] = {
            x = tonumber(p.x) or 0, z = tonumber(p.z) or 0, y = tonumber(p.y) or 0,
        };
    end
    local id = tostring(points[1].route_override_id or '');
    write(('route\t%s\t%d\t%d\t%s\t%d\t%d\t\t\t\t\t\t\t\t\t\t%s\n'):fmt(
        os.date('%Y-%m-%d %H:%M:%S'), generation, tonumber(zone) or 0,
        tsv(id), 0, n, truncated and ('TRUNCATED at ' .. MAX_WAYPOINTS) or ''));
    for i = 1, limit do
        local p = route_cache[i];
        write(('waypoint\t%s\t%d\t%d\t%s\t%d\t%d\t%.3f\t%.3f\t%.3f\t\t\t\t\t\t\t\n'):fmt(
            os.date('%Y-%m-%d %H:%M:%S'), generation, tonumber(zone) or 0,
            tsv(id), i, n, p.x, p.z, p.y));
    end
end

function M.enabled() return enabled; end

function M.set_enabled(v)
    enabled = v == true;
    if (not enabled) then
        last_signature = nil;
        route_cache = nil;
    end
    return enabled;
end

function M.path() return file_path(); end

-- Called every frame. Does nothing unless switched on and a route is active.
function M.poll(now, player)
    if (not enabled) then return; end
    if (player == nil or accessxi.nav_active ~= true) then
        last_signature = nil;
        return;
    end

    local points = accessxi.nav_route_points;
    local sig = signature(points);
    if (sig == nil) then
        last_signature = nil;
        return;
    end
    if (sig ~= last_signature) then
        last_signature = sig;
        local ok = pcall(log_route, points, player.zone);
        if (not ok) then route_cache = nil; end
    end

    if ((now - last_sample) < SAMPLE_MS) then return; end
    last_sample = now;

    local px, pz = tonumber(player.x) or 0, tonumber(player.z) or 0;
    local off, along = cross_track(route_cache, px, pz);

    -- Where the beacon is actually pointing, and how far the player's facing is
    -- from it. That difference is the steering signal they are reacting to, so a
    -- drift that coincides with a large bearing error is a turn being taken wide
    -- rather than the route being followed badly.
    local aim_x, aim_z, bearing = nil, nil, nil;
    local ok, aim = pcall(accessxi.nav_beacon_route_target, player);
    if (ok and aim ~= nil) then
        aim_x, aim_z = tonumber(aim.x), tonumber(aim.z);
        local yaw = tonumber(player.yaw);
        if (yaw ~= nil and aim_x ~= nil and aim_z ~= nil) then
            local want = math.atan2(aim_x - px, aim_z - pz);
            local d = want - yaw;
            while (d > math.pi) do d = d - (math.pi * 2); end
            while (d < -math.pi) do d = d + (math.pi * 2); end
            bearing = d * 180.0 / math.pi;
        end
    end

    write(('sample\t%s\t%d\t%d\t%s\t%d\t%d\t%.3f\t%.3f\t%.3f\t%s\t%s\t%s\t%s\t%s\t%s\t\n'):fmt(
        os.date('%Y-%m-%d %H:%M:%S'), generation, tonumber(player.zone) or 0,
        tsv(points[1] ~= nil and points[1].route_override_id or ''),
        tonumber(accessxi.nav_route_point_index) or 0,
        points:len(),
        px, pz, tonumber(player.y) or 0,
        player.yaw ~= nil and ('%.4f'):fmt(player.yaw) or '',
        aim_x ~= nil and ('%.3f'):fmt(aim_x) or '',
        aim_z ~= nil and ('%.3f'):fmt(aim_z) or '',
        off ~= nil and ('%.3f'):fmt(off) or '',
        along ~= nil and ('%.3f'):fmt(along) or '',
        bearing ~= nil and ('%.1f'):fmt(bearing) or ''));
end

return M;
