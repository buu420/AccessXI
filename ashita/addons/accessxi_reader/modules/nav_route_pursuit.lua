-- ONE RULE FOR THE BEACON: aim at the point on the route a fixed distance
-- ahead of where the player actually is.
--
-- That is the whole contract the player was promised and the only one they
-- should ever have to think about: centred means walk this way; when it moves,
-- turn with it.
--
-- What this replaces. The aim used to be chosen by whichever of several
-- components answered first on a given pulse -- an indexed lookahead, a
-- sightline clamp substituting a nearer waypoint, an async mesh detour present
-- on one pulse and absent on the next, a cached precise target. Each computed a
-- different point, so the tone swung 40 to 90 degrees between pulses and no
-- amount of smoothing downstream could fix it: the aim itself was moving.
-- Measured live 2026-08-22 11:42: -54, -38, 34, 44, -72, -43, 85, -97 degrees
-- in eight seconds of ordinary walking.
--
-- Why a point ahead ALONG THE PATH is steady. The old lookahead aimed at the
-- next waypoint, which is often 1 to 5 yalms away -- and at that range a single
-- stride swings the bearing wildly. Here the aim is interpolated on the route
-- itself, always the same distance ahead, so walking slides it forward
-- smoothly instead of hopping it from waypoint to waypoint. Standing still
-- gives a bearing that does not move at all.
--
-- Obstacles and terrain are still allowed to shape the ROUTE. They are not
-- allowed to take the aim away from this rule.

accessxi.nav_route_pursuit_lookahead = 9.0;   -- yalms ahead along the path
accessxi.nav_route_pursuit_min = 4.0;         -- never aim nearer than this
accessxi.nav_route_pursuit_window = 6;        -- segments searched either side

local function point_xyz(p)
    return tonumber(p.x) or 0, tonumber(p.y) or 0, tonumber(p.z) or 0;
end

local function xz(ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az;
    return math.sqrt((dx * dx) + (dz * dz));
end

-- Where the player is ON the route: the nearest point of the polyline, as a
-- segment index plus how far along that segment (0..1). Searched in a window
-- around the current index so a route that crosses itself cannot teleport the
-- aim to a different part of the path.
function accessxi.nav_route_pursuit_project(player, points, index)
    if (player == nil or points == nil or points.len == nil) then
        return nil;
    end
    local count = points:len();
    if (count < 2) then
        return nil;
    end
    local px, py, pz = point_xyz(player);
    index = math.max(1, math.min(math.floor(tonumber(index) or 1), count));
    local window = accessxi.nav_route_pursuit_window;
    local first = math.max(1, index - window);
    local last = math.min(count - 1, index + window);

    local best_segment, best_t, best_distance = nil, 0, nil;
    local best_score, best_vertical = nil, 0;
    for step = first, last do
        local a, b = points[step], points[step + 1];
        if (a ~= nil and b ~= nil) then
            local ax, ay, az = point_xyz(a);
            local bx, by, bz = point_xyz(b);
            local dx, dz = bx - ax, bz - az;
            local len2 = (dx * dx) + (dz * dz);
            local t = 0;
            if (len2 > 0.000001) then
                t = (((px - ax) * dx) + ((pz - az) * dz)) / len2;
                t = math.max(0, math.min(1, t));
            end
            local distance = xz(px, pz, ax + (t * dx), az + (t * dz));
            -- A ROUTE OVERHEAD IS NOT WHERE THE PLAYER IS STANDING.
            --
            -- This chose the nearest leg in XZ alone, so a leg running along a
            -- platform directly above the player looked like the place they
            -- were standing. Live 2026-08-31 in La Theine, walking to the
            -- Shattered Telepoint -- whose platform sits five yalms up, y=19.1
            -- against the player at y=24.3 (smaller y is higher) -- the aim
            -- jumped 13.5 yalms onto the platform between two pulses, same
            -- route, same index, player moved 1.6 yalms:
            --
            --   19:14:13 nav pursuit aim=(325.2,-58.7,22.3) ... index=9/11
            --   19:14:16 nav pursuit aim=(338.7,-59.3,19.1) ... index=9/11
            --
            -- The addon's two other route matchers already weight height this
            -- way (accessxi_reader.lua:71953 and :72365); this one is the odd
            -- one out, and it is the one the beacon aims from.
            --
            -- SELECTION only. The returned distance is still the HORIZONTAL
            -- one, because callers log it under that name -- and one of them,
            -- nav_log_route_mutation, is the only in-log record of
            -- route-versus-player disagreement there is.
            local vertical = (ay + (t * (by - ay))) - py;
            local score = math.sqrt((distance * distance) + ((vertical * 2) ^ 2));
            if (best_score == nil or score < best_score) then
                best_segment, best_t, best_distance = step, t, distance;
                best_score, best_vertical = score, vertical;
            end
        end
    end
    if (best_segment == nil) then
        return nil;
    end
    return {
        segment = best_segment,
        t = best_t,
        distance = best_distance,
        -- How far the chosen leg runs above (negative) or below the player.
        -- Reported so a caller can see the disagreement rather than infer it.
        vertical = best_vertical,
    };
end

-- The aim: walk forward along the route from that projection by `lookahead`
-- yalms and stand there. Interpolated, so it slides rather than hops.
--
-- Returns the aim point, the distance actually achieved, and the index of the
-- waypoint the player is heading toward.
function accessxi.nav_route_pursuit_aim(player, points, index, lookahead)
    local at = accessxi.nav_route_pursuit_project(player, points, index);
    if (at == nil) then
        return nil;
    end
    local count = points:len();
    lookahead = math.max(accessxi.nav_route_pursuit_min,
        tonumber(lookahead) or accessxi.nav_route_pursuit_lookahead);

    -- Start at the projection and pay out the lookahead along the polyline.
    local a = points[at.segment];
    local b = points[at.segment + 1];
    local ax, ay, az = point_xyz(a);
    local bx, by, bz = point_xyz(b);
    local cursor_x = ax + (at.t * (bx - ax));
    local cursor_y = ay + (at.t * (by - ay));
    local cursor_z = az + (at.t * (bz - az));

    local remaining = lookahead;
    local step = at.segment;
    local target_index = math.min(at.segment + 1, count);
    while (step <= count - 1) do
        local from_x, from_y, from_z = cursor_x, cursor_y, cursor_z;
        local nx, ny, nz = point_xyz(points[step + 1]);
        local leg = xz(from_x, from_z, nx, nz);
        if (leg >= remaining) then
            local ratio = (leg > 0.000001) and (remaining / leg) or 0;
            return {
                zone = player.zone,
                x = from_x + ((nx - from_x) * ratio),
                y = from_y + ((ny - from_y) * ratio),
                z = from_z + ((nz - from_z) * ratio),
                name = 'route ahead',
                kind = 'route',
                source = 'route-pursuit',
            }, lookahead, math.min(step + 1, count);
        end
        remaining = remaining - leg;
        cursor_x, cursor_y, cursor_z = nx, ny, nz;
        step = step + 1;
        target_index = math.min(step, count);
    end

    -- The route ends before the lookahead does: aim at its end. This is the
    -- destination, so it is exactly where the player should be walking.
    return {
        zone = player.zone,
        x = cursor_x, y = cursor_y, z = cursor_z,
        name = 'route end',
        kind = 'route',
        source = 'route-pursuit',
    }, lookahead - remaining, count;
end
