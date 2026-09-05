-- Keeps the beacon's aim point to something the player can actually walk at.
--
-- The beacon aims 5 to 9 yalms ahead ALONG THE ROUTE, measured by following the
-- waypoints. Around a corner that lands past the bend, and the straight line
-- the player walks toward it passes through rock. The route is correct; the aim
-- point is not, and the player is steered into a wall by a good path.
--
-- Clamp it: walk back from the intended target toward the player and take the
-- furthest waypoint that is genuinely visible. Aiming short is a slightly
-- less efficient line. Aiming through rock is a wall.

local SIGHTLINE_MAX_STEPS = 24;   -- how far back along the route to look

-- CanSeeDestination is line of sight, not walkability -- you can see straight
-- up a cliff face, and on 2026-08-20 it returned visible=true for a leg 1.6
-- yalms away and 3.2 yalms up, which is what centred the player on a wall.
--
-- Limits calibrated against the player's own 6494 walked steps in La Theine:
-- across 3201 recorded CLIMBS the steepest was rise/run 0.64 (99.9% under
-- 0.55), while DESCENTS reached 2.24. That asymmetry is real -- you can drop
-- off a ledge you cannot climb back up -- so the test has to be asymmetric too.
local WALK_MAX_CLIMB_RATIO = 0.8;   -- 25% headroom over the steepest walked climb
local WALK_MAX_DROP_RATIO = 3.0;    -- generous; falling is survivable, walls are not
local WALK_SHORT_RUN = 0.5;         -- below this a ratio is meaningless
local WALK_MAX_STEP_UP = 0.75;      -- a kerb, not a ledge

-- FFXI's Y axis points down, so a SMALLER destination y means higher ground.
function accessxi.nav_leg_walkable(ax, ay, az, bx, by, bz, see)
    local dx = (tonumber(bx) or 0) - (tonumber(ax) or 0);
    local dz = (tonumber(bz) or 0) - (tonumber(az) or 0);
    local run = math.sqrt((dx * dx) + (dz * dz));
    local climb = (tonumber(ay) or 0) - (tonumber(by) or 0);

    if (climb > 0) then
        if (run < WALK_SHORT_RUN) then
            if (climb > WALK_MAX_STEP_UP) then
                return false;
            end
        elseif (climb > (run * WALK_MAX_CLIMB_RATIO)) then
            return false;
        end
    else
        local drop = -climb;
        if (run >= WALK_SHORT_RUN and drop > (run * WALK_MAX_DROP_RATIO)) then
            return false;
        elseif (run < WALK_SHORT_RUN and drop > 8.0) then
            return false;
        end
    end

    if (type(see) == 'function') then
        return see(ax, ay, az, bx, by, bz) == true;
    end
    return true;
end

-- THE SHIPPED MESH MUST NOT VETO A LEG THE WALK GRAPH CERTIFIED.
--
-- The two geometries disagree, and on a walk-graph route the graph is the newer
-- and stricter of them: its portals record where a body actually fits, and the
-- 2026-08-28 repair added the staircase climbs the shipped Recast bake never had.
--
-- Live 2026-08-29, walking to the La Theine Shattered Telepoint on a route that
-- now correctly climbs the stairs:
--
--   nav pursuit aim BLOCKED at (326.0,-58.8,21.9) -- falling through to sightline
--   nav sightline player=(324.6,-54.0,24.5) target=(321.8,-58.0,24.1) visible=false
--   nav beacon reversal held swing=145
--
-- That leg is a 2.6 yalm climb over a 5.0 yalm run -- ratio 0.52 against a 0.8
-- limit, so the slope test passes and it is the MESH half that refuses. The
-- player: "the beacon stops and it keeps trying to reroute me."
--
-- The rule is already written down elsewhere in this addon, for the detour
-- probe: "never while a certified walk-graph route owns navigation. Its whole
-- purpose is to stop steering by this mesh... the alternation between the two is
-- what the player hears as a moving beacon." It simply was never applied to the
-- aim tests. This is that same test with the mesh withheld -- the slope, step
-- and drop guards all still run, so a genuinely vertical leg is still refused.
function accessxi.nav_beacon_geometry_only_see()
    return function (ax, ay, az, bx, by, bz)
        return accessxi.nav_leg_walkable(ax, ay, az, bx, by, bz, nil) == true;
    end
end

-- Sight test against the loaded zone mesh, or nil when it is unavailable so
-- callers leave the aim point alone rather than clamping on bad information.
local sightline_see = nil;
function accessxi.nav_beacon_sightline_see()
    if (type(accessxi.nav_objective_native_can_see) ~= 'function') then
        return nil;
    end
    -- Everything downstream asks "can the player walk this leg", so hand back a
    -- walkability test, not a bare sightline. Using raw line of sight here is
    -- what pointed the beacon up a cliff face six fixes running.
    -- A MISSING MESH IS UNKNOWN, NOT BLOCKED.
    --
    -- The comment above says this returns nil when the mesh is unavailable "so
    -- callers leave the aim point alone rather than clamping on bad
    -- information". That path was dead: nav_mesh_probe_can_see is defined
    -- unconditionally, so the type test below always passed, and the wrapper it
    -- returns calls a probe that answers a hard false whenever no mesh is
    -- loaded. Absent data read as a wall.
    --
    -- Live 2026-08-29 in Promyvion-Holla: 16 aims refused and ZERO clamped. The
    -- clamp bisects eight times toward the player, so a real obstruction almost
    -- always lets some short prefix through and logs a clamp. Zero clamps across
    -- sixteen refusals is the signature of a test that never looked.
    --
    -- This is the same rule nav_pursuit_aim_reachable states for itself: "no
    -- test available; do not invent a refusal."
    if (type(accessxi.nav_mesh_probe_ready) == 'function'
        and not accessxi.nav_mesh_probe_ready()) then
        return nil;
    end
    if (type(accessxi.nav_mesh_probe_can_see) == 'function') then
        if (sightline_see == nil) then
            sightline_see = function(ax, ay, az, bx, by, bz)
                return accessxi.nav_leg_walkable(
                    ax, ay, az, bx, by, bz, accessxi.nav_mesh_probe_can_see);
            end
        end
        return sightline_see;
    end
    if (sightline_see == nil) then
        sightline_see = function(ax, ay, az, bx, by, bz)
            local ok, result = pcall(accessxi.nav_objective_native_can_see,
                T{ x = ax, y = ay, z = az }, T{ x = bx, y = by, z = bz });
            -- An error means unchecked, and unchecked must never read as clear.
            return ok and result == true;
        end
    end
    return sightline_see;
end

-- An obstacle you have to walk around is invisible to both a raycast and a
-- slope test. Live 2026-08-20: straight line 6.2 yalms, CanSeeDestination said
-- CLEAR, average slope a walkable 0.53 -- and the mesh's own path was 15.7
-- yalms, going NORTH first. The ratio between path length and straight-line
-- distance is what catches it, so ask the mesh how far it really is and, when
-- that is much further than it looks, steer along the mesh's first step.
local DETOUR_RATIO = 1.35;      -- beyond this the direct line is not the way
local DETOUR_SLACK = 1.5;       -- absolute allowance for ordinary corridor wiggle
local DETOUR_MIN_DISTANCE = 1.0;
-- A detour steers around the NEXT obstacle, so its question is local. Asking
-- the mesh for a path to a target hundreds of yalms away is a whole-zone
-- search on the render thread for an answer the cue cannot use -- measured
-- 2026-08-21 at 1-4 seconds a frame against a 419-yalm target.
local DETOUR_MAX_DISTANCE = 40.0;
local DETOUR_MIN_STEP = 0.75;   -- ignore path points sitting on top of the player
-- A CORNER IS SHORT AND STILL SOLID.
--
-- Live 2026-08-24 in Southern San d'Oria the beacon walked the player into a
-- wall and held them there for ten seconds. Player (8.6,39.3), aim (4.0,47.1),
-- direct 9.05 yalms -- so the length test above demanded the way round exceed
-- 9.05 * 1.35 + 1.5 = 13.7 yalms before it would call the straight line wrong.
-- Going around a building corner is barely longer than going through it, so the
-- test said "near enough straight" and aimed into the masonry.
--
-- The mesh had already answered the question: the probe came back with FIVE
-- points. A straight walk is two. Extra length measures how far round you go;
-- how far the way round has to BOW measures whether the straight line exists at
-- all, and that is the actual question. Ordinary corridor wiggle is well under
-- a yalm, and the repair pass moves points by about one, so a point sitting
-- more than this far off the direct line is geometry, not noise.
local DETOUR_MIN_OFFSET = 1.5;

local function detour_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0);
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0);
    local dy = (tonumber(b.y) or 0) - (tonumber(a.y) or 0);
    return math.sqrt((dx * dx) + (dz * dz) + (dy * dy));
end

-- One component chooses the audible aim point. Everything else may VETO it, but
-- nothing may silently substitute an aim point that has not itself been checked.
--
-- The wall-escape and dynamic-obstacle stages run after the aim point has been
-- validated and replace it outright. On 2026-08-20 a verified north-east detour
-- target was swapped for a 'wall-escape' target 5.4 yalms up a ledge, and since
-- 'wall-escape' also counts as an explicit correction the beacon followed it
-- into the rock. Nine successive fixes were defeated by exactly this.
function accessxi.nav_beacon_approve_override(player, approved, proposed, see)
    if (approved == nil or proposed == approved) then
        return proposed ~= nil and proposed or approved;
    end
    if (proposed == nil) then
        return approved;   -- a veto keeps the verified target, never nothing
    end
    if (type(see) ~= 'function' or type(accessxi.nav_leg_walkable) ~= 'function') then
        return proposed;   -- nothing to judge it with; leave existing behaviour
    end
    if (accessxi.nav_leg_walkable(
            tonumber(player.x) or 0, tonumber(player.y) or 0, tonumber(player.z) or 0,
            tonumber(proposed.x) or 0, tonumber(proposed.y) or 0, tonumber(proposed.z) or 0,
            see) ~= true) then
        return approved;
    end
    return proposed;
end

-- The aim point is chosen 5 to 9 yalms ahead along the route, and when it lands
-- almost on top of the player the bearing to it swings wildly -- below 0.001 it
-- vanishes entirely and the pulse dies. That instability is why the cue used to
-- be derived from route-segment geometry instead, and that substitution is what
-- walked the player into a wall for nine fixes running: a steady angle that
-- answers a different question is worse than a jittery one that answers the
-- right question.
--
-- Fix the distance instead. Walk further along the route until the aim point is
-- far enough away to give a settled bearing -- but check every candidate the
-- same way the clamp does, because advancing blindly along the polyline can
-- step around a corner and put the aim point inside rock. Returns nil when
-- nothing qualifies, and nil means "say nothing", never "use the segment".
local AIM_MIN_DISTANCE = 2.5;
local AIM_MAX_STEPS = 24;

function accessxi.nav_beacon_extend_aim(player, target, points, index, see)
    if (player == nil or points == nil or points:len() < 1) then
        return nil;
    end
    if (type(see) ~= 'function' or type(accessxi.nav_leg_walkable) ~= 'function') then
        return nil;
    end
    local count = points:len();
    local start_index = math.max(1, math.min(math.floor(tonumber(index) or 1), count));
    for offset = 0, math.min(AIM_MAX_STEPS, count - start_index) do
        local candidate = points[start_index + offset];
        if (candidate ~= nil and detour_distance(player, candidate) >= AIM_MIN_DISTANCE
            and accessxi.nav_leg_walkable(
                tonumber(player.x) or 0, tonumber(player.y) or 0, tonumber(player.z) or 0,
                tonumber(candidate.x) or 0, tonumber(candidate.y) or 0, tonumber(candidate.z) or 0,
                see)) then
            return candidate;
        end
    end
    return nil;
end

function accessxi.nav_beacon_detour_target(player, target, path)
    if (player == nil or target == nil or type(path) ~= 'function') then
        return target;
    end
    accessxi.nav_beacon_detour_active = false;
    local direct = detour_distance(player, target);
    if (direct < DETOUR_MIN_DISTANCE or direct > DETOUR_MAX_DISTANCE) then
        return target;
    end

    local ok, route = pcall(path,
        tonumber(player.x) or 0, tonumber(player.y) or 0, tonumber(player.z) or 0,
        tonumber(target.x) or 0, tonumber(target.y) or 0, tonumber(target.z) or 0,
        'detour');
    if (not ok or route == nil or route:len() < 2) then
        return target;
    end

    local walked = 0;
    for step = 2, route:len() do
        walked = walked + detour_distance(route[step - 1], route[step]);
    end

    -- How far off the direct line does the mesh have to bow? Perpendicular
    -- distance from each INTERMEDIATE point to the player->target segment; the
    -- endpoints are on it by construction.
    local bowed = 0;
    do
        local px = tonumber(player.x) or 0;
        local pz = tonumber(player.z) or 0;
        local tx = tonumber(target.x) or 0;
        local tz = tonumber(target.z) or 0;
        local dx, dz = tx - px, tz - pz;
        local span = math.sqrt((dx * dx) + (dz * dz));
        if (span > 0.001) then
            for step = 2, route:len() - 1 do
                local rx = tonumber(route[step].x) or 0;
                local rz = tonumber(route[step].z) or 0;
                -- |cross product| / |segment| is the perpendicular distance.
                local offset = math.abs(((rx - px) * dz) - ((rz - pz) * dx)) / span;
                if (offset > bowed) then bowed = offset; end
            end
        end
    end

    if (walked <= ((direct * DETOUR_RATIO) + DETOUR_SLACK)
        and bowed <= DETOUR_MIN_OFFSET) then
        return target;   -- near enough straight; the direct line is the way
    end

    -- Real detour. Aim at the mesh's first meaningful step so the player is
    -- steered around the obstacle rather than into it -- but push its portal
    -- points off the walls first. The ratio above was measured on the RAW path
    -- deliberately: repair adds drift, and the question it answers is whether
    -- the direct line is wrong, not how long the way round is.
    route = accessxi.nav_beacon_repair_detour(route);
    -- Repair moves points off walls; it does not promise the player can reach
    -- them from where they stand. Being far enough away was the only test here,
    -- so a blocked first step was handed straight to the cue.
    local see = nil;
    if (type(accessxi.nav_beacon_sightline_see) == 'function') then
        see = accessxi.nav_beacon_sightline_see();
    end
    if (see == nil or type(accessxi.nav_leg_walkable) ~= 'function') then
        -- Unchecked must never read as clear. With no way to judge a candidate,
        -- keep the target the clamp already validated rather than steering at
        -- something nothing has looked at.
        return target;
    end
    -- BUDGET. Every iteration of this loop is a native walkability probe, and
    -- the loop only runs to the end when NOTHING on the way round is reachable
    -- -- which is precisely the case where it is most expensive. Measured
    -- 2026-08-21 against an unreachable destination: 33 candidates, 3.1 to 4.2
    -- SECONDS on the render thread, once every three seconds. The player
    -- described it as the game freezing, and they were right.
    --
    -- A time budget rather than a fixed count, because the honest limit is how
    -- long a frame can afford, not how many probes that happens to buy. The
    -- normal case exits on the first reachable candidate and never approaches
    -- this; giving up early costs a detour we could not have used anyway.
    local probe_deadline = tick() + 120;
    for step = 1, route:len() do
        if (tick() > probe_deadline) then
            accessxi.nav_beacon_detour_active = false;
            return target;
        end
        local candidate = route[step];
        if (detour_distance(player, candidate) >= DETOUR_MIN_STEP
            and accessxi.nav_leg_walkable(
                tonumber(player.x) or 0, tonumber(player.y) or 0, tonumber(player.z) or 0,
                tonumber(candidate.x) or 0, tonumber(candidate.y) or 0, tonumber(candidate.z) or 0,
                see)) then
            -- Route geometry must not override this: the whole point is that
            -- the direct line is wrong, and the geometry heading is derived
            -- from it. Flag it so the cue follows the detour instead.
            accessxi.nav_beacon_detour_active = true;
            return candidate;
        end
    end
    -- Nothing on the way round is reachable from here. Keep the target the
    -- clamp already validated rather than inventing one, and do not claim a
    -- detour is under way.
    return target;
end

-- FindPath hands back Detour CORRIDOR PORTAL points, which by construction lie
-- ON polygon boundaries. The stored routes are repaired at load by
-- mesh_route_repair; this live query never was -- so the one path that only runs
-- when the player is ALREADY boxed in was the one serving raw on-wall points.
--
-- Live 2026-08-20, player stuck at (24.4,20.2,16.0): the mesh's own detour had 3
-- of 7 waypoints at 0.00 wall clearance and the beacon aimed at one of them, so
-- the cue was finally honest and still unwalkable. Repaired, the first three
-- steps come back at 2.81, 3.00 and 2.95 clearance with line of sight intact.
--
-- Offline cost is 2.3ms for 112 mesh probes, but while stuck the same path is
-- recomputed every pulse, so cache it for a second.
local DETOUR_REPAIR_TTL = 1000;

function accessxi.nav_beacon_repair_detour(path)
    if (path == nil or path:len() < 2
        or type(accessxi.nav_mesh_route_repair) ~= 'function'
        or type(accessxi.nav_mesh_route_repair_probe) ~= 'function') then
        return path;
    end
    local head, tail = path[1], path[path:len()];
    local key = ('%s:%.1f,%.1f,%.1f>%.1f,%.1f,%.1f'):fmt(
        tostring(head.zone),
        tonumber(head.x) or 0, tonumber(head.y) or 0, tonumber(head.z) or 0,
        tonumber(tail.x) or 0, tonumber(tail.y) or 0, tonumber(tail.z) or 0);
    local now = tick();
    if (accessxi.nav_beacon_detour_repair_key == key
        and accessxi.nav_beacon_detour_repair_cache ~= nil
        and (now - (tonumber(accessxi.nav_beacon_detour_repair_tick) or 0)) < DETOUR_REPAIR_TTL) then
        return accessxi.nav_beacon_detour_repair_cache;
    end

    local probe = accessxi.nav_mesh_route_repair_probe();
    if (probe == nil) then
        return path;
    end
    local repaired = accessxi.nav_mesh_route_repair(path, probe);
    if (repaired == nil or repaired:len() < 1) then
        return path;
    end
    -- Waypoint one is the player's own snapped position. The repair pushed it 3
    -- yalms EAST in the live case, and the consumers below take the first step
    -- more than 0.75 yalms out -- which would have aimed the player backwards,
    -- away from the route. Height and position there belong to the player.
    repaired[1] = head;

    accessxi.nav_beacon_detour_repair_key = key;
    accessxi.nav_beacon_detour_repair_tick = now;
    accessxi.nav_beacon_detour_repair_cache = repaired;
    return repaired;
end

-- These three flags describe ONE pulse's aim point. The clamp and the detour
-- each clear their own on entry, but nav_beacon_route_target can return a
-- cached precise target before either runs -- so without this they survive into
-- a pulse that never examined them. A stale 'blocked' announces "no clear line"
-- over a perfectly good target; a stale 'clamped' or 'detour_active' silently
-- disables extension and the reversal hysteresis. Start every pulse clean and
-- let that pulse's own checks set them.
function accessxi.nav_beacon_begin_pulse()
    accessxi.nav_beacon_sightline_blocked = false;
    accessxi.nav_beacon_sightline_clamped = false;
    accessxi.nav_beacon_detour_active = false;
end

-- A correction exists only because the intended aim point was unreachable, so
-- it is usually a large swing -- "turn round and go back" measured 106 degrees
-- on 2026-08-20. Smoothing that means playing the previous heading while the
-- player is already walking on it, so corrections bypass the hysteresis.
--
-- WHAT MAY BYPASS IT IS A SHORT, NAMED LIST. This used to begin with
-- `sightline_clamped or detour_active`, and both are true on most pulses of an
-- ordinary mesh route -- so the reversal hysteresis, the one thing that rejects
-- a single wild sample, was switched off almost every pulse. Measured live
-- 2026-08-22 at 11:35: a STATIONARY player, one unchanged aim point, and the
-- beacon alternating every pulse between 9 degrees (centred) and -84 degrees
-- (hard right) with no hold in between. That is the "all over the place" the
-- player reported, and it is why centring was impossible: half the tones were
-- a 93-degree lie.
--
-- Clamping and detouring are how the aim is CHOSEN. They say nothing about
-- whether a big swing is real, and they must not buy a bypass (sol, ruling A).
function accessxi.nav_beacon_urgent_correction(source)
    source = tostring(source or '');
    return source == 'live-route-return'
        or source == 'dynamic-obstacle'
        or source == 'wall-escape'
        or source == 'lathine-local-safe';
end

-- WHICH TONE THE PLAYER HEARS.
--
-- The pan bins are `floor((pan + 1) * 6 + 0.5)` over `pan = -sin(delta)`, which
-- makes the CENTRE bin only about 4.8 degrees wide. The player hears a tone
-- roughly twice a second and covers three to four yalms between them, so
-- holding a 4.8-degree window is not something a person can do -- they turn,
-- overshoot, hear the other side, turn back. That is the "I can't centre it,
-- I feel like I'm zig zagging" they reported, and it is a property of the TONE,
-- not of the aim: the aim point was measured sliding smoothly the whole time.
--
-- So centre is given a deadband. Inside it the player hears "walk this way",
-- which is exactly the contract they set for the beacon. Simulating a player
-- who can only steer by the bin they hear: 15 degrees halves the number of
-- tone changes (96 -> 46) while holding mean heading error under 10 degrees --
-- about 0.6 yalms of drift per pulse, which the route aim corrects
-- continuously anyway. Wider buys no further steadiness and only adds error.
accessxi.nav_beacon_centre_deadband = 15 * math.pi / 180;

function accessxi.nav_beacon_bin_for_delta(delta)
    local pan = -math.sin(delta);
    if (pan < -1) then
        pan = -1;
    elseif (pan > 1) then
        pan = 1;
    end
    local ahead = math.cos(delta) >= 0;
    if (ahead and math.abs(accessxi.nav_normalize_angle(delta))
        <= accessxi.nav_beacon_centre_deadband) then
        return 'front', 6, 0;
    end
    local bin = math.floor(((pan + 1) * 6) + 0.5);
    if (bin < 0) then
        bin = 0;
    elseif (bin > 12) then
        bin = 12;
    end
    return (math.cos(delta) < -0.35) and 'rear' or 'front', bin, pan;
end

-- The reversal hysteresis itself. A single sample that swings 90 degrees or
-- more from the last one is held for exactly one pulse: if the next sample
-- agrees with it, the turn is real and plays; if it does not, it was noise and
-- the player never hears it.
--
-- Live 2026-08-22 11:35, with the bypass above wrongly enabled, a stationary
-- player heard 9 degrees and -84 degrees alternating every pulse from ONE
-- unchanged aim point. Fed through here, the -84 samples are held and the
-- player hears a steady 9 -- while a genuine turn still lands on the second
-- consecutive sample.
accessxi.nav_beacon_reversal_limit = 90 * math.pi / 180;

function accessxi.nav_beacon_smoothed_heading(heading, urgent_correction)
    local previous_heading = tonumber(accessxi.nav_beacon_previous_delta);
    if (urgent_correction) then
        accessxi.nav_beacon_pending_delta = nil;
        accessxi.nav_beacon_reversal_holds = 0;
    elseif (previous_heading ~= nil) then
        local swing = math.abs(accessxi.nav_normalize_angle(heading - previous_heading));
        if (swing >= accessxi.nav_beacon_reversal_limit) then
            local pending = tonumber(accessxi.nav_beacon_pending_delta);
            local holds = (tonumber(accessxi.nav_beacon_reversal_holds) or 0) + 1;
            -- A second sample that AGREES with the held one means the turn is
            -- real. Two disagreeing samples in a row mean the aim is genuinely
            -- unstable, and a stale angle would be worse than an honest one.
            local confirmed = pending ~= nil
                and math.abs(accessxi.nav_normalize_angle(heading - pending))
                    < accessxi.nav_beacon_reversal_limit;
            if (confirmed or holds > 1) then
                accessxi.nav_beacon_pending_delta = nil;
                accessxi.nav_beacon_reversal_holds = 0;
            else
                accessxi.nav_beacon_pending_delta = heading;
                accessxi.nav_beacon_reversal_holds = holds;
                log_line(('nav beacon reversal held swing=%.0f holds=%d'):fmt(
                    swing * 180 / math.pi, holds));
                heading = previous_heading;
            end
        else
            accessxi.nav_beacon_pending_delta = nil;
            accessxi.nav_beacon_reversal_holds = 0;
        end
    end
    accessxi.nav_beacon_previous_delta = heading;
    return heading;
end

function accessxi.nav_beacon_clamp_to_sightline(player, points, index, target, see, path)
    -- Both flags describe THIS call and nothing else, so clear them on entry.
    -- The caller withholds the aim point entirely while 'blocked' is set, which
    -- makes a stale true permanent silence with the way ahead wide open -- the
    -- worst outcome this mod has, worse than a crash.
    accessxi.nav_beacon_sightline_clamped = false;
    accessxi.nav_beacon_sightline_blocked = false;
    if (player == nil or target == nil or type(see) ~= 'function'
        or points == nil or points:len() < 1) then
        return target;
    end

    local function visible(candidate)
        if (candidate == nil) then
            return false;
        end
        return see(
            tonumber(player.x) or 0, tonumber(player.y) or 0, tonumber(player.z) or 0,
            tonumber(candidate.x) or 0, tonumber(candidate.y) or 0, tonumber(candidate.z) or 0) == true;
    end

    -- Every search below picks a SUBSTITUTE for the intended target, and a
    -- substitute at the player's own feet is useless: the bearing to it is
    -- noise, and clamped targets are never extended, so there is no way out.
    -- The intended target itself is exempt -- arriving at it is normal.
    -- SEEING IT IS NOT REACHING IT.
    --
    -- This asked only whether the player could SEE a candidate. You can see up
    -- a bank you cannot climb, and the whole reason this addon has asymmetric
    -- slope limits is that sight and walkability are different questions.
    --
    -- Live 2026-08-27 walking to Davoi: the pursuit aim was correctly refused
    -- as blocked and fell through to here, and this picked a substitute it
    -- reported as visible=true 6.3 yalms away while the player stood pinned at
    -- the foot of a rise, position unchanged across three pulses. The aim it
    -- had rejected sat 8.7 yalms ABOVE them -- y -16.7 against their y -8.0 --
    -- and the substitute was up the same rise.
    --
    -- nav_leg_walkable asks both questions: it applies the step and climb rules
    -- and then the sight test, so a candidate has to be reachable on foot and
    -- not merely in view.
    local function reachable(candidate)
        if (candidate == nil) then
            return false;
        end
        return accessxi.nav_leg_walkable(
            tonumber(player.x) or 0, tonumber(player.y) or 0, tonumber(player.z) or 0,
            tonumber(candidate.x) or 0, tonumber(candidate.y) or 0,
            tonumber(candidate.z) or 0, see) == true;
    end

    local function usable(candidate)
        return candidate ~= nil
            and detour_distance(player, candidate) >= DETOUR_MIN_STEP
            and reachable(candidate);
    end

    -- ACCESSXI_SIGHTLINE_PROBE_BEGIN (temporary)
    -- Reports what the beacon is actually aiming at and whether the mesh says
    -- that line is walkable, so "it steered me into a wall" can be checked
    -- rather than inferred. Throttled to one line a second.
    local probe_now = tick();
    if ((probe_now - (tonumber(accessxi.nav_sightline_probe_tick) or 0)) >= 1000) then
        accessxi.nav_sightline_probe_tick = probe_now;
        local clear = visible(target);
        log_line(('nav sightline player=(%.1f,%.1f,%.1f) target=(%.1f,%.1f,%.1f) dist=%.1f visible=%s index=%s count=%d'):fmt(
            tonumber(player.x) or 0, tonumber(player.z) or 0, tonumber(player.y) or 0,
            tonumber(target.x) or 0, tonumber(target.z) or 0, tonumber(target.y) or 0,
            math.sqrt(((tonumber(player.x) or 0) - (tonumber(target.x) or 0)) ^ 2
                + ((tonumber(player.z) or 0) - (tonumber(target.z) or 0)) ^ 2),
            tostring(clear), tostring(index), points:len()));
    end
    -- ACCESSXI_SIGHTLINE_PROBE_END

    if (visible(target)) then
        accessxi.nav_beacon_sightline_clamped = false;
        return target;
    end

    local count = points:len();

    -- A CERTIFIED route is dense (legs of eight yalms) and already walkable, so
    -- the question here is small: which of the next few waypoints can the
    -- player see. The furthest-visible rule below was written for sparse
    -- routes; on a dense one 24 steps is 190 yalms, and on 2026-08-21 it aimed
    -- the beacon at waypoint 31, 154 yalms away over the obstacle, then 13
    -- yalms BEHIND the player, front and rear flipping every second while they
    -- stood against a wall. Here: forward only, three steps, sixteen yalms of
    -- arc, stopping before the first real bend, nearest visible wins. Nothing
    -- visible means no normal target -- an occluded route-owned waypoint is
    -- still an unsafe walking instruction, and the obstacle recovery owns it.
    local first_point = points[1];
    local certified = first_point ~= nil
        and tostring(first_point.route_override_id or first_point.source or '') == 'lathine-walk-graph-v2';
    if (certified) then
        local CERTIFIED_CLAMP_STEPS = 3;
        local CERTIFIED_CLAMP_ARC = 16.0;
        local CERTIFIED_BEND_COS = 0.90630779;   -- cos(25 deg)
        local start_index = math.max(1, math.min(math.floor(tonumber(index) or 1), count));
        local arc = 0;
        local prev_dx, prev_dz, prev_len = nil, nil, nil;
        for offset = 0, math.min(CERTIFIED_CLAMP_STEPS, count - start_index) do
            local candidate = points[start_index + offset];
            if (candidate == nil) then
                break;
            end
            if (offset > 0) then
                local prior = points[start_index + offset - 1];
                local dx = (tonumber(candidate.x) or 0) - (tonumber(prior.x) or 0);
                local dz = (tonumber(candidate.z) or 0) - (tonumber(prior.z) or 0);
                local len = math.sqrt((dx * dx) + (dz * dz));
                arc = arc + len;
                if (arc > CERTIFIED_CLAMP_ARC) then
                    break;
                end
                if (prev_dx ~= nil and len > 0.001 and prev_len > 0.001) then
                    local cosang = ((prev_dx * dx) + (prev_dz * dz)) / (prev_len * len);
                    if (cosang < CERTIFIED_BEND_COS) then
                        break;   -- the bend is at 'prior'; nothing past it
                    end
                end
                prev_dx, prev_dz, prev_len = dx, dz, len;
            end
            if (usable(candidate)) then
                accessxi.nav_beacon_sightline_clamped = true;
                accessxi.nav_beacon_sightline_blocked = false;
                return candidate;
            end
        end
        accessxi.nav_beacon_sightline_clamped = false;
        accessxi.nav_beacon_sightline_blocked = true;
        return nil;
    end

    -- The intended target is behind geometry. Take the furthest waypoint from
    -- here that is not, searching backwards from the target toward the player.
    local start_index = math.max(1, math.min(math.floor(tonumber(index) or 1), count));
    local best = nil;
    for offset = 0, math.min(SIGHTLINE_MAX_STEPS, count - start_index) do
        local candidate = points[start_index + offset];
        if (usable(candidate)) then
            best = candidate;
        elseif (best ~= nil) then
            -- Sight is lost from here on; the last visible waypoint is the
            -- furthest safe thing to aim at.
            break;
        end
    end
    if (best ~= nil) then
        accessxi.nav_beacon_sightline_clamped = true;
        accessxi.nav_beacon_sightline_blocked = false;
        return best;
    end

    -- Nothing ahead on the route is visible. Look back along it: the player has
    -- usually drifted off, and an earlier waypoint is the way to rejoin.
    for offset = 1, math.min(SIGHTLINE_MAX_STEPS, start_index - 1) do
        local candidate = points[start_index - offset];
        if (usable(candidate)) then
            accessxi.nav_beacon_sightline_clamped = true;
            accessxi.nav_beacon_sightline_blocked = false;
            return candidate;
        end
    end

    -- No waypoint in either direction is reachable in a straight line. The mesh
    -- still knows the way round -- on 2026-08-20 the detour ran north before
    -- doubling back -- so ask it and aim at the first step the player can
    -- actually see. Aiming at the blocked waypoint just points them at rock,
    -- which is what centring the beacon then walks them into.
    if (type(path) == 'function') then
        local ok, detour = pcall(path,
            tonumber(player.x) or 0, tonumber(player.y) or 0, tonumber(player.z) or 0,
            tonumber(target.x) or 0, tonumber(target.y) or 0, tonumber(target.z) or 0,
            'sightline');
        if (ok and detour ~= nil and detour:len() > 1) then
            -- Raw FindPath output hugs the polygon boundaries. Aiming at one of
            -- those is what the player walks into, so repair before choosing.
            detour = accessxi.nav_beacon_repair_detour(detour);
            for step = 1, detour:len() do
                -- Step one is the player's own snapped position. Handing that
                -- back is a "target" a fraction of a yalm away: the bearing to
                -- it is noise, and because clamped targets are never extended
                -- there is no way out of it.
                if (usable(detour[step])) then
                    accessxi.nav_beacon_sightline_clamped = true;
                    accessxi.nav_beacon_sightline_blocked = false;
                    return detour[step];
                end
            end
        end
    end

    -- Genuinely boxed in. Record it so the caller can say so out loud rather
    -- than centring the player on a wall in silence.
    accessxi.nav_beacon_sightline_clamped = true;
    accessxi.nav_beacon_sightline_blocked = true;
    return points[start_index] or target;
end
