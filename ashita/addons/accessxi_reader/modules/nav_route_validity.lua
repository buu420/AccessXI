-- Refuses a native route until its geometry proves the sentence the beacon
-- will speak: every next waypoint is somewhere the player can walk directly.
--
-- FFXINAV does not make that promise.  In Promyvion - Holla it returned the
-- destination as one waypoint while the player's start was 133.48 yalms from
-- the nearest connected graph.  It also returned a corridor containing an
-- 89.63-yalm leg through unseen geometry.  Get_WayPoints being non-empty is an
-- API result, not evidence that a blind player can follow the result.

local function route_count(points)
    if (type(points) ~= 'table') then return 0; end
    if (type(points.len) == 'function') then
        local ok, count = pcall(points.len, points);
        if (ok) then return tonumber(count) or 0; end
    end
    return #points;
end

local function distance(first, second)
    if (type(first) ~= 'table' or type(second) ~= 'table') then return math.huge; end
    local dx = (tonumber(second.x) or 0) - (tonumber(first.x) or 0);
    local dy = (tonumber(second.y) or 0) - (tonumber(first.y) or 0);
    local dz = (tonumber(second.z) or 0) - (tonumber(first.z) or 0);
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz));
end

local function coordinate(point, name)
    if (type(point) ~= 'table') then return 0; end
    return tonumber(point[name]) or 0;
end

function accessxi.nav_route_validity_reason(points, start_point, destination, policy)
    policy = type(policy) == 'table' and policy or {};
    local count = route_count(points);
    if (count <= 0) then return ''; end

    local arrival = math.max(0.5, tonumber(policy.arrival_radius) or 4.0);
    local anchor_limit = math.max(arrival, tonumber(policy.max_anchor_snap) or 12.0);
    local endpoint_limit = math.max(arrival, tonumber(policy.max_endpoint_snap) or 12.0);
    local leg_limit = math.max(0.5, tonumber(policy.max_leg) or 6.25);
    local first, last = points[1], points[count];

    if (count == 1) then
        if (distance(start_point, destination) <= arrival
            and distance(last, destination) <= endpoint_limit) then
            return '';
        end
        return ('the mesh returned one waypoint while the player is %.1f yalms from the destination')
            :fmt(distance(start_point, destination));
    end

    local anchor_gap = distance(start_point, first);
    if (anchor_gap > anchor_limit) then
        return ('the route starts %.1f yalms from the player'):fmt(anchor_gap);
    end

    local destination_gap = distance(last, destination);
    if (destination_gap > endpoint_limit) then
        return ('the route stops %.1f yalms from the destination'):fmt(destination_gap);
    end

    if (type(policy.can_see) ~= 'function') then
        return 'the route sightline could not be verified';
    end
    if (type(policy.leg_walkable) ~= 'function') then
        return 'the route walkability could not be verified';
    end

    for index = 1, count - 1 do
        local from, to = points[index], points[index + 1];
        local span = distance(from, to);
        if (span > leg_limit) then
            return ('route leg %d is %.1f yalms, over the %.1f-yalm blind-walk limit')
                :fmt(index, span, leg_limit);
        end

        local ax, ay, az = coordinate(from, 'x'), coordinate(from, 'y'), coordinate(from, 'z');
        local bx, by, bz = coordinate(to, 'x'), coordinate(to, 'y'), coordinate(to, 'z');
        local visible_ok, visible = pcall(policy.can_see, ax, ay, az, bx, by, bz);
        if (not visible_ok or visible ~= true) then
            return ('route leg %d is not visible from end to end'):fmt(index);
        end

        -- nav_leg_walkable takes six numeric coordinates.  Passing waypoint
        -- tables silently coerces every coordinate to zero and approves the
        -- very cliff this gate exists to catch.
        local walkable_ok, walkable = pcall(
            policy.leg_walkable, ax, ay, az, bx, by, bz, policy.can_see);
        if (not walkable_ok or walkable ~= true) then
            return ('route leg %d is not walkable under the player movement policy'):fmt(index);
        end
    end

    return '';
end
