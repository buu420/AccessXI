-- Ramps, stairs and tunnel mouths: guidance for the parts of a route that go
-- UP or DOWN rather than along.
--
-- The fault this exists to fix, live 2026-08-22: the East Ronfaure entrance to
-- King Ranperre's Tomb sits at (200, -544.6) at height -8.5, up a ramp. The
-- last route waypoints were 1.6, 3.2 and 4.4 yalms above the player but only
-- 1 to 5 yalms away horizontally. At that range the bearing to them flips with
-- every stride, and the arrival test refused to advance past any waypoint more
-- than 4 yalms above the player -- so the index stuck at waypoint 182 of 184
-- and the player circled the bottom of the ramp for two minutes.
--
-- Zone lines are nearly always ramps or tunnels, which is why "it acts really
-- weird at zone lines" is this one bug.
--
-- WHY NOT VISIBILITY. CanSeeDestination ignores the endpoint Y entirely (see
-- Imports.cs in LandSandBoat/FFXI-NavMesh-Builder), so a point on the wrong
-- floor of a stairwell reads as perfectly visible. Nothing here may use sight
-- to decide which floor the player is on; position along the run decides it,
-- and disagreement means pause rather than guess (sol, ruling C).
--
-- FFXI's Y axis points DOWN: a SMALLER y is HIGHER ground.

accessxi.nav_vertical_run_bend_cos = 0.90630779;   -- cos(25 degrees)
-- GRADE, NOT RISE. Total height change alone made a hillside look like a ramp:
-- live 2026-08-22 a 3-to-8 degree slope in King Ranperre's Tomb was detected as
-- a run, which put ordinary walking under the ramp rules -- where anything the
-- projection cannot certify PAUSES the index. The player could not centre the
-- beacon because the aim kept being withheld and resumed on open ground.
-- The real ramp at that zone line is 32 to 65 degrees. Seventeen degrees
-- separates the two by a wide margin.
accessxi.nav_vertical_run_min_grade = 0.30;        -- about 17 degrees
accessxi.nav_vertical_run_min_leg_rise = 0.35;     -- below this a leg is flat
accessxi.nav_vertical_run_min_total_rise = 2.0;    -- below this it is not a run
accessxi.nav_vertical_run_y_tolerance = 2.0;       -- sol: about two yalms
accessxi.nav_vertical_run_aim_min = 4.0;
accessxi.nav_vertical_run_aim_max = 8.0;
accessxi.nav_vertical_run_project_radius = 6.0;

local function xz_distance(ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az;
    return math.sqrt((dx * dx) + (dz * dz));
end

local function point_xyz(point)
    return tonumber(point.x) or 0, tonumber(point.y) or 0, tonumber(point.z) or 0;
end

-- A contiguous stretch of route from `index` whose height moves one way only
-- and whose horizontal direction never bends more than 25 degrees. It stops at
-- the apex (where the climb turns into a descent, or flattens out) and at the
-- first real corner, because past either the aim point stops describing the
-- thing the player is walking up.
function accessxi.nav_vertical_run_detect(points, index)
    if (points == nil or points:len() == nil) then
        return nil;
    end
    local count = points:len();
    index = math.max(1, math.min(math.floor(tonumber(index) or 1), count));
    if (count - index < 1) then
        return nil;
    end

    local direction, last = nil, index;
    local prev_dx, prev_dz, prev_len = nil, nil, nil;
    local total = 0;
    for step = index, count - 1 do
        local from_point, to_point = points[step], points[step + 1];
        if (from_point == nil or to_point == nil) then
            break;
        end
        local ax, ay, az = point_xyz(from_point);
        local bx, by, bz = point_xyz(to_point);
        local rise = ay - by;                       -- positive means climbing
        if (math.abs(rise) < accessxi.nav_vertical_run_min_leg_rise) then
            break;                                  -- flat: the run ends here
        end
        local run_dx, run_dz = bx - ax, bz - az;
        local horizontal = math.sqrt((run_dx * run_dx) + (run_dz * run_dz));
        if (horizontal > 0.001
            and (math.abs(rise) / horizontal) < accessxi.nav_vertical_run_min_grade) then
            break;                                  -- a hillside, not a ramp
        end
        local this_direction = rise > 0 and 1 or -1;
        if (direction == nil) then
            direction = this_direction;
        elseif (this_direction ~= direction) then
            break;                                  -- the apex
        end
        local dx, dz = bx - ax, bz - az;
        local len = math.sqrt((dx * dx) + (dz * dz));
        if (prev_dx ~= nil and len > 0.001 and prev_len > 0.001) then
            local cosang = ((prev_dx * dx) + (prev_dz * dz)) / (prev_len * len);
            if (cosang < accessxi.nav_vertical_run_bend_cos) then
                break;                              -- a real corner
            end
        end
        prev_dx, prev_dz, prev_len = dx, dz, len;
        total = total + math.abs(rise);
        last = step + 1;
    end

    if (direction == nil or last <= index
        or total < accessxi.nav_vertical_run_min_total_rise) then
        return nil;
    end
    return { first = index, last = last, direction = direction, rise = total };
end

-- Where to point while walking the run: far enough along that the bearing is
-- steady, never past the apex or corner the run already stops at.
function accessxi.nav_vertical_run_aim(player, points, run)
    if (player == nil or points == nil or run == nil) then
        return nil;
    end
    local px, _, pz = point_xyz(player);
    -- START AHEAD OF THE PLAYER. run.first is the waypoint BEHIND them (the leg
    -- they are walking begins there), so accumulating from it would count the
    -- distance back to a point already passed and could return that point as
    -- the aim -- a bearing pointing the way they came.
    local first_ahead = run.first;
    if (points[run.first] ~= nil and points[run.first + 1] ~= nil) then
        local ax, _, az = point_xyz(points[run.first]);
        local bx, _, bz = point_xyz(points[run.first + 1]);
        local dx, dz = bx - ax, bz - az;
        local len2 = (dx * dx) + (dz * dz);
        if (len2 > 0.000001) then
            local along = (((px - ax) * dx) + ((pz - az) * dz)) / len2;
            if (along > 0.05) then
                first_ahead = run.first + 1;        -- already past that waypoint
            end
        end
    end

    local walked, chosen = 0, nil;
    local cursor_x, cursor_z = px, pz;
    for step = first_ahead, run.last do
        local candidate = points[step];
        if (candidate ~= nil) then
            local cx, _, cz = point_xyz(candidate);
            walked = walked + xz_distance(cursor_x, cursor_z, cx, cz);
            cursor_x, cursor_z = cx, cz;
            chosen = candidate;
            if (walked >= accessxi.nav_vertical_run_aim_min) then
                return candidate, walked;
            end
        end
    end
    -- The whole remaining run is shorter than the minimum: its far end is the
    -- steadiest thing available, and it is still on the run.
    return chosen, walked;
end

-- How far along the run the player actually is, decided by their position and
-- nothing else.
--
-- Returns: new index, advanced, reason.
-- `advanced` false with reason 'ambiguous' or 'off-run' means PAUSE -- the
-- player is not demonstrably on this run, and guessing puts a blind player on
-- the wrong floor of a stairwell.
function accessxi.nav_vertical_run_progress(player, points, run, current_index)
    if (player == nil or points == nil or run == nil) then
        return current_index, false, 'no-run';
    end
    local px, py, pz = point_xyz(player);
    local tolerance = accessxi.nav_vertical_run_y_tolerance;
    local radius = accessxi.nav_vertical_run_project_radius;

    local agreeing = {};
    for step = run.first, run.last - 1 do
        local from_point, to_point = points[step], points[step + 1];
        if (from_point ~= nil and to_point ~= nil) then
            local ax, ay, az = point_xyz(from_point);
            local bx, by, bz = point_xyz(to_point);
            local dx, dz = bx - ax, bz - az;
            local len2 = (dx * dx) + (dz * dz);
            if (len2 > 0.000001) then
                local t = (((px - ax) * dx) + ((pz - az) * dz)) / len2;
                t = math.max(0, math.min(1, t));
                local projected_x, projected_z = ax + (t * dx), az + (t * dz);
                local lateral = xz_distance(px, pz, projected_x, projected_z);
                if (lateral <= radius) then
                    -- The height the route says this spot is at. A switchback
                    -- doubles back over itself, so two legs can share an XZ
                    -- footprint and differ only here.
                    local interpolated_y = ay + (t * (by - ay));
                    local mismatch = math.abs(py - interpolated_y);
                    if (mismatch <= tolerance) then
                        agreeing[#agreeing + 1] = {
                            index = step + 1, lateral = lateral,
                            mismatch = mismatch, t = t };
                    end
                end
            end
        end
    end

    if (#agreeing == 0) then
        -- Either off the run, or on a different floor of it. Both mean the
        -- route cannot say where the player is; do not move the index.
        return current_index, false, 'off-run';
    end

    -- The leg the player is most plainly standing on: nearest footprint, and
    -- when two are equally near (which is exactly what standing ON a waypoint
    -- looks like) the one further along, because they have reached that
    -- waypoint and the next one is where they are going.
    local best = agreeing[1];
    for _, entry in ipairs(agreeing) do
        if (entry.lateral < (best.lateral - 0.25)
            or (math.abs(entry.lateral - best.lateral) <= 0.25 and entry.index > best.index)) then
            best = entry;
        end
    end

    -- A vertically overlapping switchback: a leg that is NOT adjacent to the
    -- best one shares its footprint just as closely. Adjacent legs sharing a
    -- footprint are just a polyline joint and mean nothing; a distant leg
    -- doing it means the path runs back over itself and the heights are too
    -- close to tell the floors apart. Refuse rather than pick a floor.
    for _, entry in ipairs(agreeing) do
        if (math.abs(entry.index - best.index) >= 2
            and math.abs(entry.lateral - best.lateral) <= 1.0) then
            return current_index, false, 'ambiguous';
        end
    end

    local resolved = best.index;
    -- Forward only. Arc progress along the run never runs backwards, so an
    -- index that would go back means the player left the run rather than
    -- retreated along it.
    current_index = math.floor(tonumber(current_index) or run.first);
    if (resolved <= current_index) then
        return current_index, false, 'no-progress';
    end
    return resolved, true, 'projected';
end
