-- Makes a raw Detour corridor walkable for a player who cannot see.
--
-- FindClosestPath returns the corridor's portal points, which lie ON polygon
-- boundaries and can sit tens of yalms apart.  A sighted player runs roughly
-- toward the next one and slides along whatever geometry is in the way.  A
-- blind player is told "go straight 13 yalms", walks a straight line into the
-- wall the waypoint is sitting on, stops at zero clearance, and the identical
-- route is replanned forever.  Measured on the shipped La Theine mesh, routing
-- out of the west ravine: 48 waypoints, 43 of them under 0.25 yalms of wall
-- clearance, 30 legs longer than 6 yalms, one leg of 85.
--
-- Two passes fix it.  Push each waypoint up the wall-distance gradient until it
-- stands in open ground, then split any leg longer than a player can safely
-- walk blind.  Both passes only ever use positions the mesh itself accepts.
--
-- probe is injected so this is testable without the game:
--   probe.valid(x, y, z) -> boolean   position is on the navmesh
--   probe.wall(x, y, z)  -> number    yalms to the nearest wall

local REPAIR_TARGET_CLEARANCE = 1.75;   -- open enough for a player to walk
local REPAIR_MAX_LEG = 6.0;             -- longest straight line to give blind
local REPAIR_MAX_STEPS = 24;            -- gradient iterations per waypoint
local REPAIR_MAX_DRIFT = 3.0;           -- how far a waypoint may leave the corridor
local REPAIR_PROBE_ANGLES = 8;
local REPAIR_PROBE_RADII = { 0.75, 1.5 };

local function repair_distance(a, b)
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0);
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0);
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0);
    return math.sqrt((dx * dx) + (dz * dz) + (dy * dy));
end

local function repair_clone(source, x, y, z)
    local copy = T{};
    for key, value in pairs(source) do
        copy[key] = value;
    end
    copy.x = x;
    copy.y = y;
    copy.z = z;
    return copy;
end

-- Climb the wall-distance gradient until the waypoint stands clear, or until
-- no nearby on-mesh position is any better.  Never moves off the mesh, and
-- never moves vertically -- height belongs to the mesh, not to this pass.
local function repair_push_clear(point, probe)
    local x = tonumber(point.x) or 0;
    local y = tonumber(point.y) or 0;
    local z = tonumber(point.z) or 0;
    local best = tonumber(probe.wall(x, y, z)) or 0;
    if (best >= REPAIR_TARGET_CLEARANCE) then
        return point, false;
    end

    -- Clearance that keeps improving in one direction -- a corridor that widens,
    -- open floor past a doorway -- would otherwise drag the waypoint clean off
    -- the course Detour planned and into somewhere the player was never routed.
    local origin_x, origin_z = x, z;
    local function within_drift(tx, tz)
        local dx, dz = tx - origin_x, tz - origin_z;
        return math.sqrt((dx * dx) + (dz * dz)) <= REPAIR_MAX_DRIFT;
    end

    local moved = false;
    for _ = 1, REPAIR_MAX_STEPS do
        local found = false;
        local bx, bz = x, z;
        for angle = 0, REPAIR_PROBE_ANGLES - 1 do
            local theta = (angle * 2 * math.pi) / REPAIR_PROBE_ANGLES;
            for _, radius in ipairs(REPAIR_PROBE_RADII) do
                local tx = x + (math.cos(theta) * radius);
                local tz = z + (math.sin(theta) * radius);
                if (within_drift(tx, tz) and probe.valid(tx, y, tz) == true) then
                    local clearance = tonumber(probe.wall(tx, y, tz)) or 0;
                    if (clearance > best + 0.01) then
                        best, bx, bz, found = clearance, tx, tz, true;
                    end
                end
            end
        end
        if (not found) then
            break;
        end
        x, z, moved = bx, bz, true;
        if (best >= REPAIR_TARGET_CLEARANCE) then
            break;
        end
    end

    if (not moved) then
        return point, false;
    end
    return repair_clone(point, x, y, z), true;
end

-- Split legs no player could walk blind.  Interpolated points are kept only
-- when the mesh accepts them, so a split never invents walkable ground.
local function repair_split_leg(route, from, to, probe)
    local span = repair_distance(from, to);
    if (span <= REPAIR_MAX_LEG) then
        return;
    end
    local pieces = math.ceil(span / REPAIR_MAX_LEG);
    for piece = 1, pieces - 1 do
        local t = piece / pieces;
        local x = (tonumber(from.x) or 0) + (((tonumber(to.x) or 0) - (tonumber(from.x) or 0)) * t);
        local z = (tonumber(from.z) or 0) + (((tonumber(to.z) or 0) - (tonumber(from.z) or 0)) * t);
        local y = (tonumber(from.y) or 0) + (((tonumber(to.y) or 0) - (tonumber(from.y) or 0)) * t);
        -- A straight line between two corridor points can cross ground the mesh
        -- rejects.  Only keep a split the mesh vouches for; skipping one leaves
        -- a long leg, which is worse to walk but is not a waypoint in mid-air.
        if (probe.valid(x, y, z) == true) then
            route:append(repair_clone(to, x, y, z));
        end
    end
end

-- A waypoint standing in open ground is not enough.  The player walks the
-- straight line between waypoints, and around a corner that line can pass
-- through rock even when both ends are clear -- measured at 2 to 5 such legs
-- per La Theine route, and neither FindPath nor FindClosestPath removes them.
-- Bend the leg instead of cutting it: take the midpoint, push it into the open,
-- and keep it only if it restores sight to both ends.  Recurse so a corner can
-- be rounded rather than shortcut.
local REPAIR_BEND_ANGLES = 12;
local REPAIR_BEND_RADII = { 1.0, 2.0, 3.0 };
local REPAIR_BEND_DEPTH = 3;

local function repair_bend_leg(route, from, to, probe, depth)
    if (depth <= 0 or probe.see == nil
        or probe.see(from.x, from.y, from.z, to.x, to.y, to.z) == true) then
        return 0;
    end

    local mx = ((tonumber(from.x) or 0) + (tonumber(to.x) or 0)) / 2;
    local mz = ((tonumber(from.z) or 0) + (tonumber(to.z) or 0)) / 2;
    local my = ((tonumber(from.y) or 0) + (tonumber(to.y) or 0)) / 2;

    local best, best_clearance = nil, -1;
    for angle = 0, REPAIR_BEND_ANGLES - 1 do
        local theta = (angle * 2 * math.pi) / REPAIR_BEND_ANGLES;
        for _, radius in ipairs(REPAIR_BEND_RADII) do
            local tx = mx + (math.cos(theta) * radius);
            local tz = mz + (math.sin(theta) * radius);
            if (probe.valid(tx, my, tz) == true
                and probe.see(from.x, from.y, from.z, tx, my, tz) == true
                and probe.see(tx, my, tz, to.x, to.y, to.z) == true) then
                local clearance = tonumber(probe.wall(tx, my, tz)) or 0;
                if (clearance > best_clearance) then
                    best_clearance = clearance;
                    best = repair_clone(to, tx, my, tz);
                end
            end
        end
    end
    if (best ~= nil) then
        route:append(best);
        return 1;
    end

    -- Nowhere on that arc restores sight. Split and try each half.
    local middle = repair_clone(to, mx, my, mz);
    local fixed = repair_bend_leg(route, from, middle, probe, depth - 1);
    route:append(middle);
    return fixed + repair_bend_leg(route, middle, to, probe, depth - 1);
end

function accessxi.nav_mesh_route_repair(points, probe)
    if (points == nil or points:len() < 2
        or type(probe) ~= 'table'
        or type(probe.valid) ~= 'function' or type(probe.wall) ~= 'function') then
        return points;
    end

    local cleared = T{};
    local moved = 0;
    for _, point in ipairs(points) do
        local repaired, was_moved = repair_push_clear(point, probe);
        if (was_moved) then
            moved = moved + 1;
        end
        cleared:append(repaired);
    end

    local split = T{};
    for index, point in ipairs(cleared) do
        if (index > 1) then
            repair_split_leg(split, cleared[index - 1], point, probe);
        end
        split:append(point);
    end

    local route = T{};
    local bent = 0;
    for index, point in ipairs(split) do
        if (index > 1) then
            bent = bent + repair_bend_leg(route, split[index - 1], point, probe, REPAIR_BEND_DEPTH);
        end
        route:append(point);
    end

    accessxi.nav_mesh_route_repair_last_moved = moved;
    accessxi.nav_mesh_route_repair_last_bent = bent;
    return route;
end

-- Wraps the live navmesh so the repair can run against the loaded zone mesh.
-- Returns nil when the mesh is unavailable, so callers skip repair rather than
-- failing the route.
function accessxi.nav_mesh_route_repair_probe()
    -- Preferred: raw-coordinate probes that reuse one FFI struct. The wrapper
    -- path below allocates a table and pays a pcall per call, which at a few
    -- thousand calls per route is the difference between a pause and a stall.
    if (type(accessxi.nav_mesh_probe_valid) == 'function'
        and type(accessxi.nav_mesh_probe_wall) == 'function') then
        -- Walkability, not bare line of sight: a leg can be perfectly visible
        -- and still be a cliff face the player cannot climb.
        return {
            valid = accessxi.nav_mesh_probe_valid,
            wall = accessxi.nav_mesh_probe_wall,
            see = (type(accessxi.nav_mesh_probe_can_see) == 'function'
                and type(accessxi.nav_leg_walkable) == 'function')
                and function(ax, ay, az, bx, by, bz)
                    return accessxi.nav_leg_walkable(
                        ax, ay, az, bx, by, bz, accessxi.nav_mesh_probe_can_see);
                end
                or nil,
        };
    end

    if (type(accessxi.nav_objective_native_is_valid_position) ~= 'function'
        or type(accessxi.nav_objective_native_get_distance_to_wall) ~= 'function') then
        return nil;
    end
    local zone = tonumber(accessxi.nav_mesh_zone) or 0;
    local function at(x, y, z)
        return T{ zone = zone, x = x, y = y, z = z };
    end
    return {
        valid = function(x, y, z)
            local ok, result = pcall(accessxi.nav_objective_native_is_valid_position, at(x, y, z));
            return ok and result == true;
        end,
        wall = function(x, y, z)
            local ok, result = pcall(accessxi.nav_objective_native_get_distance_to_wall, at(x, y, z));
            if (not ok) then
                return 0;
            end
            return tonumber(result) or 0;
        end,
        -- Absent on older builds; the repair simply skips bending without it.
        see = type(accessxi.nav_objective_native_can_see) == 'function'
            and function(ax, ay, az, bx, by, bz)
                local ok, result = pcall(
                    accessxi.nav_objective_native_can_see, at(ax, ay, az), at(bx, by, bz));
                -- Treat an error as "cannot see" so a failure never claims a
                -- leg is walkable when it has not been checked.
                return ok and result == true;
            end
            or nil,
    };
end
