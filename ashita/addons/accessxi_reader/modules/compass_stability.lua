-- Keeps the spoken compass heading from chattering on a sector boundary.
--
-- The compass reports one of eight 45 degree sectors, so every boundary sits
-- 22.5 degrees from a sector centre.  A player walking a straight line whose
-- heading happens to lie on one of those boundaries crosses back and forth on
-- ordinary walking wobble.  With no angular hysteresis that produced 21 spoken
-- announcements in 27 seconds on 2026-08-20 -- alternating southwest, south,
-- southeast -- each one interrupting the last, and starving the navigation
-- beacon, which polls later in the same frame.
--
-- Time throttles cannot fix this: the heading really is changing sector, just
-- barely, and it stays changed long enough to satisfy any dwell requirement.
-- The fix has to be angular.  Once a heading is announced, hold it until the
-- player turns clear of that sector by a margin -- a Schmitt trigger.

local COMPASS_SECTORS = {
    'east', 'northeast', 'north', 'northwest',
    'west', 'southwest', 'south', 'southeast',
};
local COMPASS_SECTOR_ARC = math.pi / 4;             -- 45 degrees
local COMPASS_RELEASE_MARGIN = 8 * math.pi / 180;   -- past the boundary before switching

local function compass_normalize_yaw(yaw)
    yaw = tonumber(yaw);
    if (yaw == nil) then
        return nil;
    end
    -- Callers hand us radians, but a few paths still carry degrees.
    if (math.abs(yaw) > (math.pi * 2.1)) then
        yaw = yaw * math.pi / 180;
    end
    return (-yaw) % (math.pi * 2);
end

local function compass_sector_index(angle)
    local index = math.floor((angle + (COMPASS_SECTOR_ARC / 2)) / COMPASS_SECTOR_ARC) + 1;
    while (index > #COMPASS_SECTORS) do
        index = index - #COMPASS_SECTORS;
    end
    while (index < 1) do
        index = index + #COMPASS_SECTORS;
    end
    return index;
end

local function compass_index_of(direction)
    direction = tostring(direction or ''):lower();
    for index, name in ipairs(COMPASS_SECTORS) do
        if (name == direction) then
            return index;
        end
    end
    return 0;
end

local function compass_angle_between(a, b)
    local two_pi = math.pi * 2;
    local delta = math.abs((a - b) % two_pi);
    if (delta > math.pi) then
        delta = two_pi - delta;
    end
    return delta;
end

-- The unsmoothed sector, matching accessxi.nav_compass_direction.
function accessxi.nav_compass_direction_raw(yaw)
    local angle = compass_normalize_yaw(yaw);
    if (angle == nil) then
        return 'unknown';
    end
    return COMPASS_SECTORS[compass_sector_index(angle)];
end

-- The sector to speak, given what was last spoken.  Holds the current heading
-- until the player has turned past its boundary by COMPASS_RELEASE_MARGIN.
function accessxi.nav_compass_direction_stable(yaw, current)
    local angle = compass_normalize_yaw(yaw);
    if (angle == nil) then
        return 'unknown';
    end

    local raw = COMPASS_SECTORS[compass_sector_index(angle)];
    local current_index = compass_index_of(current);
    if (current_index == 0 or raw == current) then
        return raw;
    end

    -- Still within the held sector plus its release margin: keep speaking it.
    local current_centre = (current_index - 1) * COMPASS_SECTOR_ARC;
    local from_centre = compass_angle_between(angle, current_centre);
    if (from_centre <= ((COMPASS_SECTOR_ARC / 2) + COMPASS_RELEASE_MARGIN)) then
        return COMPASS_SECTORS[current_index];
    end
    return raw;
end
