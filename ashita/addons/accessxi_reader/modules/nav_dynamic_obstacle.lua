-- Dynamic obstacle detection and side-stepping for the navigation beacon.
--
-- Extracted from accessxi_reader.lua on 2026-08-22 so the decision logic can be
-- exercised offline (tools/test_nav_beacon_obstacle.lua) instead of only in the
-- live game. Behaviour is unchanged except for the two rules this file exists
-- to enforce: a detected obstacle is not automatically a STEERABLE one, and a
-- side-step must be a step forward along the leg.
--
-- Loaded by accessxi_reader.lua via load_code_module('nav_dynamic_obstacle').

function accessxi.nav_zone_suppresses_named_npc_obstacles(zone)
    zone = tonumber(zone) or 0;
    return zone == 230 or zone == 231 or zone == 232 or zone == 233
        or zone == 234 or zone == 235 or zone == 236 or zone == 237
        or zone == 238 or zone == 239 or zone == 240 or zone == 241
        or zone == 242 or zone == 243 or zone == 244 or zone == 245
        or zone == 246;
end


function accessxi.nav_entity_is_dynamic_obstacle_candidate(pos)
    if (pos == nil or not accessxi.nav_live_entity_valid(pos)) then
        return false;
    end

    local kind = tostring(pos.live_kind or accessxi.nav_entity_kind(pos));
    if (kind == 'enemy' and accessxi.nav_zone_suppresses_named_npc_obstacles(pos.zone)
        and not accessxi.nav_entity_name_looks_like_enemy(pos)) then
        return false;
    end
    return kind == 'player' or kind == 'enemy' or kind == 'live-nm';
end

-- DETECTED IS NOT STEERABLE. FFXI applies no collision between player
-- characters, so another player never blocks the way -- yet on 2026-08-22 a
-- player named Sacredlight standing in the Southern San d'Oria plaza produced
-- a side-step that swung the beacon 166 degrees. City NPCs are the same: a
-- sighted player walks straight past them. Both stay DETECTED so they can be
-- announced, and neither may move the aim point (sol, ruling B).
function accessxi.nav_entity_is_steerable_obstacle(pos)
    if (not accessxi.nav_entity_is_dynamic_obstacle_candidate(pos)) then
        return false;
    end
    local kind = tostring(pos.live_kind or accessxi.nav_entity_kind(pos));
    if (kind == 'player') then
        return false;
    end
    if (accessxi.nav_zone_suppresses_named_npc_obstacles(pos.zone)
        and type(accessxi.nav_entity_name_looks_like_enemy) == 'function'
        and not accessxi.nav_entity_name_looks_like_enemy(pos)) then
        return false;
    end
    return true;
end



function accessxi.nav_segment_obstacle(player, route_target)
    if (player == nil or route_target == nil) then
        return nil;
    end

    local ax = tonumber(player.x) or 0;
    local az = tonumber(player.z) or 0;
    local bx = tonumber(route_target.x) or 0;
    local bz = tonumber(route_target.z) or 0;
    local vx = bx - ax;
    local vz = bz - az;
    local segment_length = math.sqrt((vx * vx) + (vz * vz));
    local len2 = segment_length * segment_length;
    if (len2 < 0.001) then
        return nil;
    end

    local scan_ahead = math.max(5.5, math.min(13.5, segment_length + 2.0));
    local corridor_radius = 2.8;
    local warn_radius = 3.4;
    local player_index = tonumber(player.index) or -1;
    local best = nil;
    local candidates = accessxi.nav_live_entity_snapshot(80, scan_ahead + 8);
    for _, pos in ipairs(candidates) do
        if ((tonumber(pos.index) or -1) ~= player_index and accessxi.nav_live_entity_valid(pos)) then
            if (accessxi.nav_entity_is_dynamic_obstacle_candidate(pos)) then
                local wx = (tonumber(pos.x) or 0) - ax;
                local wz = (tonumber(pos.z) or 0) - az;
                local t = ((wx * vx) + (wz * vz)) / len2;
                if (t >= 0.08 and t <= 1.15) then
                    local cx = ax + (t * vx);
                    local cz = az + (t * vz);
                    local dx = (tonumber(pos.x) or 0) - cx;
                    local dz = (tonumber(pos.z) or 0) - cz;
                    local side_distance = math.sqrt((dx * dx) + (dz * dz));
                    local ahead_distance = math.sqrt(len2) * t;
                    local kind = tostring(pos.live_kind or accessxi.nav_entity_kind(pos));
                    local entity_radius = kind == 'player' and 1.4 or 1.7;
                    local collision_radius = corridor_radius + entity_radius;
                    if (ahead_distance >= 1.8 and ahead_distance <= scan_ahead and side_distance <= collision_radius) then
                        if (best == nil or ahead_distance < best.ahead) then
                            best = T{
                                entity = pos,
                                ahead = ahead_distance,
                                side = side_distance,
                                radius = collision_radius,
                                warn = side_distance <= (warn_radius + entity_radius),
                                steerable = accessxi.nav_entity_is_steerable_obstacle(pos),
                                t = t,
                                cx = cx,
                                cz = cz,
                            };
                        end
                    end
                end
            end
        end
    end

    return best;
end


function accessxi.nav_obstacle_avoidance_target(player, route_target)
    local obstacle = accessxi.nav_segment_obstacle(player, route_target);
    if (obstacle == nil) then
        accessxi.nav_obstacle_last_key = '';
        return nil, nil;
    end
    -- Warn about it, never steer around it (see nav_entity_is_steerable_obstacle).
    if (obstacle.steerable ~= true) then
        return nil, obstacle;
    end

    local ax = tonumber(player.x) or 0;
    local az = tonumber(player.z) or 0;
    local bx = tonumber(route_target.x) or 0;
    local bz = tonumber(route_target.z) or 0;
    local vx = bx - ax;
    local vz = bz - az;
    local length = math.sqrt((vx * vx) + (vz * vz));
    if (length < 0.001) then
        return nil, obstacle;
    end

    local nx = -vz / length;
    local nz = vx / length;
    local clearance = math.max(3.4, (tonumber(obstacle.radius) or 4.5) + 0.8);
    local left = T{
        zone = player.zone,
        x = (obstacle.cx or bx) + (nx * clearance),
        z = (obstacle.cz or bz) + (nz * clearance),
        y = player.y,
        name = 'obstacle left',
        kind = 'route',
        source = 'dynamic-obstacle',
    };
    local right = T{
        zone = player.zone,
        x = (obstacle.cx or bx) - (nx * clearance),
        z = (obstacle.cz or bz) - (nz * clearance),
        y = player.y,
        name = 'obstacle right',
        kind = 'route',
        source = 'dynamic-obstacle',
    };

    -- A SIDE-STEP MUST STILL BE A STEP FORWARD. These points are placed
    -- perpendicular to the ROUTE segment at a fixed clearance, which says
    -- nothing about where the player is actually going. Live on 2026-08-22 the
    -- accepted point was 1.9 yalms along the route but 5.0 yalms to the side --
    -- 69 degrees off the leg, heard as "turn around" -- and the player walked
    -- backwards across the plaza.
    --
    -- Two gates, because sol's forward-progress margin alone passes that point
    -- (1.9 >= 0.5). Progress along the leg AND a bearing that still resembles
    -- the leg. When neither side qualifies the honest answer is no steering at
    -- all: the warning is spoken, and contact collision owns the brush-past.
    local ux, uz = vx / length, vz / length;
    local FORWARD_MIN = 0.5;              -- sol, ruling B
    local LATERAL_RATIO = 1.7320508;      -- tan(60 deg) off the leg
    local function usable_side(candidate)
        local cx = (tonumber(candidate.x) or 0) - ax;
        local cz = (tonumber(candidate.z) or 0) - az;
        local forward = (cx * ux) + (cz * uz);
        if (forward < FORWARD_MIN) then
            return false;
        end
        local lateral = math.abs((cx * -uz) + (cz * ux));
        return lateral <= (forward * LATERAL_RATIO);
    end

    local left_ok = usable_side(left) and accessxi.nav_valid_mesh_position(left);
    local right_ok = usable_side(right) and accessxi.nav_valid_mesh_position(right);
    local left_wall = accessxi.nav_wall_distance(left) or 0;
    local right_wall = accessxi.nav_wall_distance(right) or 0;
    if (right_ok and (not left_ok or right_wall > left_wall)) then
        return right, obstacle;
    end
    if (left_ok) then
        return left, obstacle;
    end
    if (right_ok) then
        return right, obstacle;
    end
    return nil, obstacle;
end
