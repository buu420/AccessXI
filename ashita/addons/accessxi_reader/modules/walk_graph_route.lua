-- Certified walk-graph routing for La Theine Plateau (zone 102).
--
-- La Theine is the one zone whose shipped navmesh cannot be trusted. It marks
-- 67-degree legs walkable, its corridor points sit on walls, and the twenty-odd
-- hand-authored `lathine-*` route overrides in accessxi_reader.lua exist because
-- of it. This provider replaces the ROUTE SOURCE for that zone with a graph
-- rebuilt offline from the zone's own collision geometry, and leaves every other
-- zone completely untouched -- it is never constructed outside zone 102.
--
-- What makes this graph different from the mesh it replaces:
--
--   * A node is one walkable triangle, positioned at its centroid. Triangles are
--     convex, so a straight line between two points inside one stays inside it.
--   * An edge carries a PORTAL: the oriented left/right endpoints of the piece
--     of the shared triangle edge a body actually fits through, with the floor
--     height on both sides. A scalar clearance can say a body fits SOMEWHERE
--     along an edge; only stored endpoints say WHERE.
--   * Routes are funnelled (string-pulled) over those portals, so what comes out
--     is 56 corners over 775 yalms instead of 401 centroids over 960 -- a walking
--     instruction rather than a coordinate dump.
--
-- This is the Detour corridor-vs-findStraightPath distinction. The corridor says
-- which polygons you cross; only the straight path says where to put your feet.
--
-- HONESTY ABOUT WHAT IS AND IS NOT PROVEN. The artifact's FULL_CAPSULE_CHECKED
-- and HEADROOM_CHECKED flags are deliberately zero and this module does not
-- pretend otherwise.
--
-- Proven: every PORTAL was eroded offline against the source's own steep
-- triangles, so each doorway admits the body somewhere along a known interval,
-- and the funnel's CENTERLINE provably stays inside the union of the corridor's
-- triangles, because a node is one convex triangle and a straight line between
-- two points inside a convex region stays inside it.
--
-- NOT proven, and the distinction matters: a centerline inside the surface is
-- not a BODY inside the surface. Recast erodes the entire walkable surface by
-- the agent radius precisely so that the agent can afterwards be treated as a
-- point; we eroded the doorways but not the surface between them, so a corner
-- can still pass closer to a wall than a 0.40 body fits. Overhead clearance is
-- likewise unproven.
--
-- Nor can either be proven at runtime here. The swept-capsule check this addon
-- uses elsewhere needs a loaded DAT collision context, and that preload is
-- deliberately skipped for zone 102 (see poll_nav_dat_collision_preload) with
-- both caches empty, so asking for one would trigger the cold multi-minute
-- terrain build this zone exists to avoid.
--
-- The connector legs USED to be admitted on bounded proximity -- the live point
-- within a short fixed distance of a triangle whose stored clearance admits the
-- body. That was materially weaker than a sweep: it could not rule out a thin
-- wall, a cliff edge, or a wrong vertical layer between the player and that
-- centroid, and on 2026-08-20 exactly that gap stranded a player for three
-- hours against a hillside that every distance test called close.
--
-- It is now PROVEN instead, without needing the DAT context: the connector is
-- marched at a quarter yalm and every sample must find walkable ground with
-- room for the body, each step within the graph's own limits, ending on the
-- candidate's own vertical layer. See connector_proven.
--
-- What makes that sound is a change in the artifact, not in this file. Every
-- transition in the graph is now walked against the collision model offline and
-- the refuted ones removed before shipping, so the graph is entitled to be
-- treated as the ground authority here. It was not before.
--
-- Nothing in here speaks. Speech belongs to the route lifecycle in the main file,
-- which already knows how to say something once and then heartbeat.

local walk_graph_route = {};

local ZONE = 102;
local ROUTE_ID = 'lathine-walk-graph-v2';
local GRAPH_RELATIVE_DIR = 'data';
local GRAPH_RELATIVE_SUB = 'walkgraph';
local GRAPH_FILE = 'zone-102.axwg';

-- Provenance of the accepted artifact. The SHA is recorded for humans; it is
-- NOT what the runtime checks, because hashing 31 MB in Lua on the main thread
-- would cost more than the load it is guarding.
--
-- What IS checked, after the load, is the artifact's identity: the loader
-- already verifies the file's own payload CRC32 while reading it, so pinning
-- the record counts on top of that means a swapped, truncated, stale or
-- rebuilt-with-different-settings file is refused rather than silently used to
-- route a blind player over geometry nobody verified. Rebuilding the zone
-- deliberately means updating these four numbers deliberately.
-- 2026-08-28: +627 climbing edges, added deliberately. A KERB IS A STEP, NOT A
-- SLOPE.
--
-- The grade rule was enforced twice -- by the builder when it emits an edge and
-- by the loader when it opens the file -- and both judged a short rise over a
-- short run as a hillside. That is the shape of a staircase. The ramp onto the
-- La Theine Shattered Telepoint runs 0.333 with a 0.250 rise: grade 0.750, or
-- 36.9 degrees against a 33 degree limit. Every tread failed in the CLIMBING
-- direction only -- the descent passed the down-grade test -- so all three La
-- Theine telepoint platforms were one-way islands the player could walk off and
-- never onto. The player walked those stairs and surveyed the point at the top
-- of them; the mesh held the treads and offered no way in.
--
-- Measured on this artifact, start (332.8,-31.3,24.1):
--                        before                      after
--   Shattered Telepoint  401408 expansions, no route   1369, route
--   Telepoint            401408 expansions, no route   5535, route
--   Dimensional Portal   401408 expansions, no route   6682, route
--   Shattered Tp stairs  125, route                    125, route  (unchanged)
--
-- Node and portal counts are untouched: the patch adds only the reverse
-- direction of crossings whose portal was already certified, which portals
-- support by construction -- Graph:portal(portal_id, from_node_id) takes either
-- endpoint and mirrors left/right. No portal geometry was invented. 627 of 8431
-- one-direction portals qualified; 7770 remain illegal even as a step and 34
-- were already legal by grade and left alone.
--
-- Produced by tools/patch_axwg_step_edges.py rather than a rebuild, because the
-- builder has diverged 4254 lines since this artifact was made and now yields
-- 204777 nodes from the byte-identical OBJ. Rebuilding would swap in a
-- materially different graph, which is the thing these pins exist to prevent.
local GRAPH_SHA256 =
    '08636be1e094c54c2966318fd5f5ff8585bc41c4fbe55e81aa3d1132782f377e';
local GRAPH_NODE_COUNT = 249480;
local GRAPH_EDGE_COUNT = 617836;
local GRAPH_PORTAL_COUNT = 312820;
local GRAPH_FILE_SIZE = 36714336;

-- CRC32 of the collision OBJ this graph was built from. Passed to the loader,
-- which refuses a graph built from anything else, and re-checked afterwards.
-- Record counts alone do not identify an artifact: a rebuild with different
-- settings from the same source, or the same pipeline run against different
-- terrain, can land on the same counts. The source CRC says WHICH GEOMETRY the
-- routes describe, which is the part a player's safety actually rests on.
local GRAPH_SOURCE_CRC = 0x30BA83D1;
local GRAPH_BUILDER_REVISION = 4;

-- The poll runs on d3d_present, so the whole budget is one 16ms frame shared
-- with the game. Cold load measured 1027ms on 32-bit LuaJIT, so 4ms/frame
-- spreads it over roughly four seconds without a visible hitch. A full-zone
-- search measured 89ms, so 3ms/frame finishes in well under half a second.
local LOAD_BUDGET_MS = 4;
local SEARCH_BUDGET_MS = 3;
local SEARCH_SLICE_EXPANSIONS = 768;
local SEARCH_EXPANSION_CAP = 400000;
-- BOUND THE POLL BY WORK, NOT ONLY BY A CLOCK. The search loop below was
-- bounded solely by `repeat ... until now_ms() >= deadline`, and now_ms() is
-- os.clock(). Whatever that clock's granularity is inside pol.exe, one call
-- could run far past its 3ms intent: on 2026-08-24 a search that converges in
-- 85 slices offline instead reported "did not converge", meaning it had burned
-- all 400,000 expansions, and the frame watchdog had already caught a 514ms
-- route phase. A fixed slice ceiling makes each call cost the same live as it
-- does offline, so the behaviour stops depending on the clock at all.
--
-- 8 slices = 6,144 expansions per call. At the ~29Hz this is polled at, a
-- converging search (85 slices) finishes in about 0.4s, and an impossible one
-- reaches the cap in about 2.3s instead of stalling a frame.
local SEARCH_MAX_SLICES_PER_POLL = 8;

-- Candidate gathering is generous so the search has somewhere to start from,
-- but only a candidate inside the tighter certified bounds may anchor a funnel.
local CANDIDATE_HORIZONTAL = 6.0;
local CANDIDATE_VERTICAL = 4.0;
local CANDIDATE_RESULTS = 24;
local CERTIFY_HORIZONTAL = 3.0;
local CERTIFY_VERTICAL = 2.25;

-- Widened bounds for an AREA destination -- a zone line. Its coordinate is a
-- trigger volume, and the collision model routinely ends before it, so the
-- point itself often sits off the walkable ground entirely. Ordelle's Caves
-- z2u6 is at y=20.6; the nearest ground the player is RECORDED WALKING is 1.17
-- yalms away horizontally and TWELVE yalms above it.
--
-- The result cap is large deliberately. Candidates come back ordered by 3D
-- distance, and the stranded islet sitting AT the trigger's own level ranks
-- ahead of every useful node. Measured at z2u6: the first candidate on the
-- player's own component is rank 253 of 432. Cost is one query at route start.
--
-- DECLARED HERE, above certify_candidates, and that placement is load-bearing.
-- Declared below it these resolved to nil globals, and `area_goal and
-- APPROACH_VERTICAL or CERTIFY_VERTICAL` silently collapsed to the tight 2.25
-- limit -- code that reads as working while doing the opposite, and it refused
-- a zone line the player had walked to that morning.
local APPROACH_HORIZONTAL = 16.0;
local APPROACH_VERTICAL = 16.0;
local APPROACH_RESULTS = 512;
-- How close the certified ground must march to the trigger's XZ before the
-- last unsupported hop into the zoning volume is accepted. The volume itself
-- has no floor of ours -- the trigger point routinely sits past the last
-- collision triangle -- so the proof is "ground carries you to the lip".
local APPROACH_ENTER_HORIZONTAL = 1.5;
-- And how far the lip may sit vertically from the trigger. The trigger's own y
-- is unreliable in the fine (it sits inside the volume, often deeper along a
-- descending tunnel), so this is generous -- but it must exist: without it the
-- proof short-circuited for ground 1.17 yalms from the z2u6 trigger in XZ and
-- TWELVE yalms above it. A twelve-yalm drop is not an entrance.
--
-- 9.0 is fitted to two measured populations and says so. Jugner and West
-- Ronfaure carry genuine lsb Y error of 7-8 yalms at enterable lips; the
-- Ordelle roofs sit 10.3 and 12.0 above mouths that are NOT enterable from
-- there. The bound must pass the first and refuse the second. Sol's full
-- entry-layer-agreement semantics replace this number in the offline arc.
local APPROACH_ENTER_VERTICAL = 9.0;

-- Fallback body radius, used only if the artifact somehow fails to declare one.
-- The real value is READ FROM THE GRAPH'S OWN POLICY, because that is the radius
-- its portals were actually eroded against and anything else is a different
-- body than the one the file was certified for.
--
-- This was 0.40 first, copied from the addon's DAT capsule sweep. The artifact
-- declares 0.70. Filtering candidates at 0.40 would admit nodes a 0.70 body
-- does not fit in -- quietly relaxing the certification by reading a number off
-- the wrong component.
local FALLBACK_BODY_RADIUS = 0.70;

local function body_radius(graph)
    local declared = tonumber(graph ~= nil and graph.agent_radius);
    if (declared ~= nil and declared == declared and declared > 0) then
        return declared;
    end
    return FALLBACK_BODY_RADIUS;
end

local state = {
    enabled = nil,
    mode = 'idle',
    graph = nil,
    loader = nil,
    load_error = nil,
    load_started_tick = 0,
    search = nil,
    request = nil,
    last_reason = '',
    last_reason_kind = '',
};

local function now_ms()
    if (type(os.clock) == 'function') then
        return os.clock() * 1000.0;
    end
    return 0;
end

local function finite(value)
    value = tonumber(value);
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge;
end

local function point_zone(point)
    return math.floor(tonumber(point ~= nil and point.zone) or 0);
end

-- Declared here rather than beside the loading code below because release()
-- needs it to cancel an in-flight load, and a Lua local is only visible to
-- functions defined after it.
local function walk_graph_module()
    if (type(accessxi) == 'table'
        and type(accessxi.walk_graph_library) == 'table') then
        return accessxi.walk_graph_library;
    end
    return nil;
end

--------------------------------------------------------------------------------
-- Session switch
--------------------------------------------------------------------------------

-- ON as of 2026-08-21. It was defaulted off for four named integration
-- defects; all four are now closed, and each is closed in code that says so at
-- the site rather than here:
--
--   1. the beacon returned a CACHED steering target before this route's
--      sightline clamp ran, bypassing native-mesh suppression
--      -> nav_beacon_route_target now carries the cached precise target down
--         as a candidate and validates it once, like any other. The early
--         return is guarded by walk_graph_aim.
--   2. pending searches were not bound to route ownership, so a stale one
--      could restart navigation after the player stopped it
--      -> nav_route_ownership_advance bumps a generation on route-stop,
--         zone-change and every route start, clears nav_walk_graph_pending and
--         cancels this provider; poll_nav_walk_graph drops a mismatched result.
--   3. the live position tracker was not arc-bounded for this route id and
--      could jump forward across the zone (11 aliasing corners in a real
--      31-corner route, 28-50 yalms apart)
--      -> nav_route_live_match treats 'lathine-walk-graph-v2' as self-crossing:
--         one segment of backward hysteresis, monotone committed progress, and
--         a 24-yalm forward corridor.
--   4. connector certification was PROXIMITY, not proof
--      -> certify_candidates now requires the candidate to be on the same
--         component as the ground under the player's feet AND proves the
--         connector by marching it. See connector_proven.
--
-- What made 4 fixable is a change in the artifact, not in this file: every
-- transition is now walked against the collision model offline and the refuted
-- ones removed, so the graph may be trusted as the ground authority at runtime.
--
-- What is still known to be imperfect, recorded so nobody has to rediscover it:
-- 8 of 6498 recorded walked strides (0.12%) are split across components, and
-- 4.6% of recorded positions sit outside the largest component. Both are the
-- residue of doorway erosion at a 0.70 body radius, which is the format's
-- minimum; the player's own closest measured approach to a wall taller than
-- themselves is 0.620, so that radius is marginally stricter than observed
-- play. It is left strict.
--
-- Rollback while on is one command: `/axi nav walkgraph off` restores the
-- previous La Theine behaviour and releases the graph.
local DEFAULT_ENABLED = true;
local function settings_path()
    if (type(accessxi_paths) ~= 'table'
        or type(accessxi_paths.addon_path) ~= 'function') then
        return nil;
    end
    local ok, path = pcall(accessxi_paths.addon_path, 'data', 'nav-walkgraph-mode.txt');
    if (not ok or type(path) ~= 'string' or path == '') then
        return nil;
    end
    return path;
end

function walk_graph_route.enabled()
    if (state.enabled ~= nil) then
        return state.enabled;
    end
    state.enabled = DEFAULT_ENABLED;
    local path = settings_path();
    if (path ~= nil) then
        local file = io.open(path, 'r');
        if (file ~= nil) then
            local line = file:read('*l');
            file:close();
            line = tostring(line or ''):lower():gsub('%s', '');
            if (line == 'off' or line == 'disabled' or line == '0' or line == 'false') then
                state.enabled = false;
            elseif (line == 'on' or line == 'enabled' or line == '1' or line == 'true') then
                state.enabled = true;
            end
        end
    end
    return state.enabled;
end

function walk_graph_route.set_enabled(value)
    local wanted = value and true or false;
    local path = settings_path();
    if (path ~= nil) then
        local file = io.open(path, 'w');
        if (file == nil) then
            return nil, 'Could not save the La Theine walk graph setting.';
        end
        file:write(wanted and 'on' or 'off', '\n');
        file:close();
    end
    state.enabled = wanted;
    if (not wanted) then
        -- Turning it off must actually let go. Leaving a loaded graph and an
        -- installed route alive would make "off" a lie.
        walk_graph_route.release('switch-off');
    end
    return wanted, '';
end

function walk_graph_route.zone()
    return ZONE;
end

function walk_graph_route.route_id()
    return ROUTE_ID;
end

function walk_graph_route.graph_path()
    if (type(accessxi_paths) ~= 'table'
        or type(accessxi_paths.addon_path) ~= 'function') then
        return nil;
    end
    local ok, path = pcall(accessxi_paths.addon_path,
        GRAPH_RELATIVE_DIR, GRAPH_RELATIVE_SUB, GRAPH_FILE);
    if (not ok or type(path) ~= 'string' or path == '') then
        return nil;
    end
    return path;
end

function walk_graph_route.expected_sha256()
    return GRAPH_SHA256;
end

-- Applies to this zone only. Every caller is expected to have already checked
-- that both the player and the destination are in it, but a provider that can be
-- reached from anywhere is a provider that will eventually be reached from
-- somewhere else, so re-check here rather than trusting the call site.
function walk_graph_route.applies(player, destination)
    return player ~= nil and destination ~= nil
        and point_zone(player) == ZONE
        and point_zone(destination) == ZONE;
end

function walk_graph_route.status()
    return state.mode, state.last_reason, state.last_reason_kind;
end

function walk_graph_route.is_loaded()
    return state.graph ~= nil;
end

-- WHAT THE PLANNER HAS ACTUALLY DONE, so a stall can be attributed instead of
-- argued about. On 2026-08-23 a plan to Shattered Telepoint heartbeat "still
-- planning" for over 150 seconds. Offline, from the player's exact position,
-- the identical request finishes in 304 polls -- 286 load slices plus 18
-- search slices, 1.23s of CPU, a 232-point route. So either the poll was not
-- reaching this module anything like once a frame, or a phase was not
-- advancing. NOTHING IN THE LOG COULD TELL THOSE APART: sol read the evidence
-- as starvation down to one slice per 7.5s, I read the beacon roll-up as a
-- healthy 29Hz, and both readings fit every line we had. The largest gap
-- between polls is the datum that separates them, so it is now recorded.
function walk_graph_route.progress()
    local phase = 'idle';
    if (state.search ~= nil) then
        phase = 'searching';
    elseif (state.graph ~= nil) then
        phase = 'ready';
    elseif (state.loader ~= nil) then
        phase = 'loading';
    end
    local expansions = 0;
    if (type(state.request) == 'table') then
        expansions = tonumber(state.request.expansions) or 0;
    end
    local loaded = 0;
    if (state.loader ~= nil) then
        loaded = tonumber(state.loader._read_offset) or 0;
    end
    local anchor = '';
    if (type(state.request) == 'table') then
        anchor = tostring(state.request.anchor_note or '');
    end
    return phase, expansions, loaded, tostring(state.mode or ''), anchor;
end

-- True while an A* is in flight. The caller uses this to tell "the graph is
-- ready but nothing has been asked of it yet" from "a search is running", so a
-- request parked during the load is re-issued against a live position rather
-- than the stale one it arrived with.
function walk_graph_route.is_searching()
    return state.search ~= nil;
end

-- A load is in flight. Distinct from is_loaded: between them they say whether
-- anything is held at all, which is what the caller needs in order to release
-- on zone exit without calling release every frame from every other zone.
function walk_graph_route.is_loading()
    return state.loader ~= nil;
end


local function set_reason(kind, message)
    state.last_reason_kind = tostring(kind or '');
    state.last_reason = tostring(message or '');
end

-- Discard the graph and every derived search. Called on zone change out of La
-- Theine so ~90 MiB is not held for a zone the player has left, and by the
-- session switch so turning the feature off actually releases it.
function walk_graph_route.release(reason)
    if (state.loader ~= nil) then
        local library = walk_graph_module();
        if (library ~= nil and type(library.cancel_load) == 'function') then
            pcall(library.cancel_load, state.loader);
        end
    end
    state.search = nil;
    state.request = nil;
    state.loader = nil;
    state.graph = nil;
    state.load_error = nil;
    state.mode = 'idle';
    set_reason('released', reason or 'released');
    collectgarbage('step');
end

function walk_graph_route.cancel(reason)
    state.search = nil;
    state.request = nil;
    if (state.graph ~= nil) then
        state.mode = 'ready';
    elseif (state.loader ~= nil) then
        state.mode = 'loading';
    else
        state.mode = 'idle';
    end
    set_reason('cancelled', reason or 'cancelled');
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

-- The loader contract this module is written against:
--
--   walk_graph.begin_load(path, expected_zone, expected_source_crc)
--       -> job           on success
--       -> nil, message  on failure
--   walk_graph.step_load(job, budget_ms)
--       -> 'pending'
--       -> 'ready',  graph
--       -> 'failed', nil, reason
--   walk_graph.cancel_load(job)
--
-- The budget is a soft allowance: one bounded operation may overrun it
-- slightly, so ask for less than the frame can afford.
--
-- A synchronous whole-file load is deliberately NOT used as a fallback. It
-- measured 1027ms, which inside d3d_present is a one-second freeze, and it
-- materialises the whole 31 MB artifact as a single Lua string on top of the
-- FFI buffer -- a doubled peak in a 32-bit address space that has been
-- fragmenting since the player logged in. If the incremental entry point is
-- missing, this provider reports unavailable and the zone keeps its old
-- behaviour.
local function begin_load()
    local library = walk_graph_module();
    if (library == nil) then
        state.load_error = 'The walk-graph library is not installed.';
        return false;
    end
    if (type(library.begin_load) ~= 'function'
        or type(library.step_load) ~= 'function') then
        state.load_error =
            'The walk-graph library has no incremental loader; refusing to block the frame.';
        return false;
    end
    local path = walk_graph_route.graph_path();
    if (path == nil) then
        state.load_error = 'The La Theine walk-graph path could not be resolved.';
        return false;
    end
    -- Cheapest possible identity check, and the one that catches the most
    -- likely accident: a half-copied or replaced artifact. Costs one seek.
    local probe = io.open(path, 'rb');
    if (probe == nil) then
        state.load_error = 'The La Theine walk graph is not installed.';
        return false;
    end
    local size = probe:seek('end');
    probe:close();
    if (tonumber(size) ~= GRAPH_FILE_SIZE) then
        state.load_error = ('The La Theine walk graph is not the verified build (%s bytes, expected %d).')
            :format(tostring(size), GRAPH_FILE_SIZE);
        return false;
    end
    local ok, loader, message = pcall(library.begin_load, path, ZONE, GRAPH_SOURCE_CRC);
    if (not ok) then
        state.load_error = 'The La Theine walk graph failed to open: ' .. tostring(loader);
        return false;
    end
    if (loader == nil) then
        state.load_error = 'The La Theine walk graph failed to open: ' .. tostring(message);
        return false;
    end
    state.loader = loader;
    state.mode = 'loading';
    set_reason('loading', 'Preparing the verified La Theine route.');
    return true;
end

-- Refuse a graph that is not the artifact this module was pinned to. The loader
-- has already checked the file's own payload CRC by the time we get here, so a
-- mismatch on these means a DIFFERENT file, not a damaged one.
local function identity_matches(graph)
    return tonumber(graph.node_count) == GRAPH_NODE_COUNT
        and tonumber(graph.edge_count) == GRAPH_EDGE_COUNT
        and tonumber(graph.portal_count) == GRAPH_PORTAL_COUNT
        and tonumber(graph.source_obj_crc32) == GRAPH_SOURCE_CRC
        and tonumber(graph.builder_revision) == GRAPH_BUILDER_REVISION;
end

local function abandon_load(message)
    state.loader = nil;
    state.graph = nil;
    state.load_error = message;
    state.mode = 'unavailable';
    set_reason('unavailable', message);
    return 'failed', message;
end

local function step_load(budget_ms)
    local library = walk_graph_module();
    if (state.loader == nil or library == nil) then
        return 'failed', state.load_error or 'no loader';
    end
    local ok, status, graph, reason = pcall(library.step_load, state.loader, budget_ms);
    if (not ok) then
        return abandon_load('The La Theine walk graph failed to load: ' .. tostring(status));
    end
    if (status == 'pending') then
        return 'pending';
    end
    if (status == 'ready' and type(graph) == 'table') then
        if (not identity_matches(graph)) then
            return abandon_load(
                ('The La Theine walk graph is not the verified build (%s nodes, %s edges, %s doorways).'):format(
                    tostring(graph.node_count), tostring(graph.edge_count),
                    tostring(graph.portal_count)));
        end
        state.loader = nil;
        state.graph = graph;
        state.mode = 'ready';
        set_reason('ready', '');
        return 'ready';
    end
    return abandon_load(
        'The La Theine walk graph failed to load: ' .. tostring(reason or graph or status));
end

-- Begin loading without asking for a route. Called on entry to La Theine so the
-- artifact is warm before the player asks for anything.
--
-- poll() deliberately does NOT start a load. It drives one that already exists.
-- Keeping the two separate is what lets "standing in La Theine" and "asking for
-- a route" differ: without an explicit prewarm the caller's zone-entry branch
-- called poll() and got 'idle' back forever, so the advertised warm-up never
-- actually happened and the first route paid the full second of load.
function walk_graph_route.prewarm()
    if (state.graph ~= nil or state.loader ~= nil or state.mode == 'unavailable') then
        return false;
    end
    return begin_load();
end

--------------------------------------------------------------------------------
-- Connector certification
--------------------------------------------------------------------------------

-- A candidate may anchor a funnel only when the live point is close enough to
-- the certified triangle that the leg between them is short, and the triangle
-- itself is wide enough to hold the body.
--
-- This is bounded proximity, not a swept capsule, and the name says so. The
-- honest reading is: "the player is standing within CERTIFY_HORIZONTAL of the
-- centroid of a triangle that was certified walkable offline and whose stored
-- clearance admits the body." That is materially weaker than a sweep and it is
-- the strongest claim available in a zone where the sweep is switched off.
-- A candidate describes the CONNECTOR: a short leg from the live point (the
-- player, or the destination) to a certified triangle's centroid. So its x,z,y
-- are the LIVE point's, not the node's, and connector_cost is what that leg
-- costs. Graph:candidates already measured that distance; reusing it keeps the
-- number the loader re-derives and the number we claim identical.
--
-- Candidates that cannot form a legal connector are dropped here rather than
-- passed on, because the loader rejects the whole batch on the first bad one --
-- a single degenerate candidate would otherwise make an entirely routable
-- position look unreachable.
-- Prove the connector by WALKING it, rather than measuring how near it is.
--
-- The old rule admitted a node because it was within 3.0 horizontally and 2.25
-- vertically. Near is not reachable, and the difference is not academic: on
-- 2026-08-20 a player spent three hours pinned in one spot because the beacon
-- aimed at a point 6 yalms up a hillside, which by any distance test is close.
--
-- A swept capsule is unavailable here and the existing comment explains why --
-- it needs a loaded DAT collision context, and zone 102 deliberately skips
-- that preload to avoid a cold multi-minute terrain build. So the proof uses
-- the GRAPH as the ground authority instead, which is now sound to do: every
-- transition in the artifact has been walked against the collision model
-- offline at a quarter yalm and the refuted ones removed before it shipped.
--
-- The test marches from the live position to the candidate node and requires,
-- at every sample, walkable ground with room for the body, with each step
-- obeying the graph's own step limits in the direction of travel. A thin wall,
-- a cliff rim, or a wrong vertical layer all break support and fail the
-- candidate, which is exactly what proximity could not see.
local CONNECTOR_STEP = 0.25;
-- Sized to the MESH, not to the body. A node is a triangle's centroid and the
-- median triangle here is 1.91 yalms across, so a sample taken between two
-- centroids is legitimately over a yalm from either. At 0.75 the proof reported
-- "no ground" while standing in the middle of an open field, which would have
-- refused every route in the zone.
--
-- Widening this does not weaken the test, because horizontal reach is not what
-- the test rests on. A wall between the player and the candidate shows up as
-- ground only at a very different HEIGHT, and that is caught by the vertical
-- band and by the step limits between consecutive samples -- neither of which
-- is relaxed.
local CONNECTOR_SUPPORT_HORIZONTAL = 2.50;
local CONNECTOR_SUPPORT_VERTICAL = 0.60;
local CONNECTOR_MAX_PROOFS = 8;

-- Measured at the spot that started all of this: standing at (19.9, 27.7) the
-- nearest node is 2.15 yalms away, so a window of 1.75 found nothing anywhere
-- along the connector and refused every route in the zone. 2.50 clears the
-- observed spacing with margin.

local function connector_proven(graph, px, pz, py, node_point, radius)
    local dx = node_point.x - px;
    local dz = node_point.z - pz;
    local len = math.sqrt((dx * dx) + (dz * dz));
    if (len < 1e-6) then
        -- Standing on it. The only thing left to check is the vertical layer.
        return math.abs(node_point.y - py) <= CONNECTOR_SUPPORT_VERTICAL;
    end

    local step_up = tonumber(graph.max_step_up) or 0.5;
    local step_down = tonumber(graph.max_step_down) or 0.5;
    local steps = math.ceil(len / CONNECTOR_STEP);
    local previous_y = py;

    for index = 1, steps do
        local t = index / steps;
        local sx = px + (dx * t);
        local sz = pz + (dz * t);
        -- Look for support around the height we are ACTUALLY at, not around a
        -- straight line to the target. A chord through a hillside would other-
        -- wise keep finding ground near it while the real walk never could.
        local found = graph:candidates(sx, sz, previous_y, {
            max_horizontal = CONNECTOR_SUPPORT_HORIZONTAL,
            max_vertical = CONNECTOR_SUPPORT_VERTICAL,
            max_results = 4,
            minimum_node_clearance = radius,
        });
        if (type(found) ~= 'table' or #found < 1) then
            return false;
        end

        local best_y, best_gap = nil, nil;
        for _, entry in ipairs(found) do
            local ey = tonumber(entry.y);
            if (ey ~= nil and ey == ey) then
                local gap = math.abs(ey - previous_y);
                if (best_gap == nil or gap < best_gap) then best_gap = gap; best_y = ey; end
            end
        end
        if (best_y == nil) then return false; end

        -- y points DOWN, so shrinking y is a climb.
        local climb = previous_y - best_y;
        if (climb > step_up or -climb > step_down) then
            return false;
        end
        previous_y = best_y;
    end

    -- Arriving on some ground is not arriving on the node we are about to
    -- anchor a route to. Require the walk to end on that node's own layer.
    return math.abs(previous_y - node_point.y) <= CONNECTOR_SUPPORT_VERTICAL;
end

-- Which piece of ground is the player actually standing on. Anchoring to a node
-- in a different component means anchoring to terrain that has no walkable
-- connection to their feet -- the hillside case, where a point six yalms up is
-- close by every distance test and reachable by none.
local function standing_component(graph, candidates)
    local best, best_cost = nil, nil;
    for _, candidate in ipairs(candidates) do
        local cost = tonumber(candidate.distance);
        if (cost ~= nil and cost == cost and (best_cost == nil or cost < best_cost)) then
            best_cost = cost; best = candidate;
        end
    end
    if (best == nil) then return nil; end
    local point = graph:point(best.node_id);
    return point ~= nil and tonumber(point.component_id) or nil;
end

-- `required_component` exists because "the ground under my feet" is the right
-- anchor for a START and the WRONG one for a GOAL. Deriving it from the goal's
-- own nearest node anchors to whatever happens to lie closest to the
-- destination coordinate -- which for a zone line is routinely a stranded
-- islet, and certifying against that rejects the very ground the player has to
-- arrive on. A goal candidate is useful when it is on the player's ground.
-- A zone-line anchor must have a certified ENTRY: ground that carries the body
-- from the anchor to the lip of the zoning volume, each step within policy.
-- "On the player's component and near the line" -- the previous rule -- is not
-- that, and it anchored a live route on the ROOF of the Ordelle cave mouth:
-- same component, 5 yalms from the trigger in XZ, ten yalms above the tunnel
-- the trigger actually sits in. The player orbited the roof for seventy
-- seconds while the guidance flapped. Near is not enterable.
--
-- The proof marches from the anchor toward the trigger's XZ, requiring
-- same-component graph ground under every step and policy-legal rises between
-- steps. The trigger point itself is exempt from support -- it routinely sits
-- past the last collision triangle, inside the volume -- so the march passes
-- when it carries the body to within APPROACH_ENTER_HORIZONTAL of the line.
-- Ground that ends earlier than that is a cliff edge above the mouth, and the
-- candidate is refused. (Ruling: codex review 2026-08-21 -- "reaches the last
-- supported point before the trigger; then crosses into the trigger volume".)
-- The march's terminal must stand on the REACHABLE layer nearest the trigger.
-- Reachable means the route's own component: at z2u6 a severed ledge sits
-- seven centimetres closer to the trigger's stored Y than the true entry
-- floor, so judged over every component the wrong layer wins. Judged over
-- reachable ground only, the entry floor is the only candidate.
local APPROACH_LAYER_AGREE = 1.0;
local function entry_layer_agrees(graph, terminal_y, tx, tz, ty, required_component)
    local ok, found = pcall(graph.candidates, graph, tx, tz, terminal_y, {
        max_horizontal = APPROACH_ENTER_HORIZONTAL,
        max_vertical = 40.0,
        max_results = 24,
        minimum_node_clearance = 0,
    });
    if (not ok or type(found) ~= 'table') then
        return true;
    end
    local best = nil;
    for _, entry in ipairs(found) do
        local ey = tonumber(entry.y);
        if (ey ~= nil and ey == ey) then
            local p = graph:point(entry.node_id);
            if (p ~= nil and (required_component == nil
                or tonumber(p.component_id) == required_component)) then
                if (best == nil or math.abs(ey - ty) < math.abs(best - ty)) then
                    best = ey;
                end
            end
        end
    end
    -- No reachable ground at the trigger's own XZ: the terminal is already
    -- the last supported point, and the vertical bound is the only judge.
    if (best == nil) then
        return true;
    end
    return math.abs(terminal_y - best) <= APPROACH_LAYER_AGREE;
end
local function approach_proven(graph, from_point, tx, tz, ty, radius, required_component)
    local px = tonumber(from_point.x) or 0;
    local pz = tonumber(from_point.z) or 0;
    local dx, dz = tx - px, tz - pz;
    local len = math.sqrt((dx * dx) + (dz * dz));
    local trigger_dy = math.abs((tonumber(from_point.y) or 0) - ty);
    if (len <= APPROACH_ENTER_HORIZONTAL) then
        return trigger_dy <= APPROACH_ENTER_VERTICAL
            and entry_layer_agrees(graph, tonumber(from_point.y) or 0, tx, tz, ty, required_component);
    end
    local step_up = tonumber(graph.max_step_up) or 0.5;
    local step_down = tonumber(graph.max_step_down) or 0.5;
    local steps = math.ceil(len / CONNECTOR_STEP);
    local previous_y = tonumber(from_point.y) or 0;
    for index = 1, steps do
        local t = index / steps;
        local sx, sz = px + (dx * t), pz + (dz * t);
        local remaining = len * (1.0 - t);
        local found = graph:candidates(sx, sz, previous_y, {
            max_horizontal = CONNECTOR_SUPPORT_HORIZONTAL,
            max_vertical = CONNECTOR_SUPPORT_VERTICAL,
            max_results = 6,
            minimum_node_clearance = radius,
        });
        local best_y, best_gap = nil, nil;
        for _, entry in ipairs(type(found) == 'table' and found or {}) do
            local ey = tonumber(entry.y);
            if (ey ~= nil and ey == ey) then
                local p = graph:point(entry.node_id);
                if (p ~= nil and (required_component == nil
                    or tonumber(p.component_id) == required_component)) then
                    local gap = math.abs(ey - previous_y);
                    if (best_gap == nil or gap < best_gap) then
                        best_gap = gap; best_y = ey;
                    end
                end
            end
        end
        if (best_y == nil) then
            -- Ground ends here. That is the lip of the volume only if we are
            -- already at it; anywhere earlier it is a drop the body cannot take.
            return remaining <= APPROACH_ENTER_HORIZONTAL
                and math.abs(previous_y - ty) <= APPROACH_ENTER_VERTICAL
                and entry_layer_agrees(graph, previous_y, tx, tz, ty, required_component);
        end
        local climb = previous_y - best_y;
        if (climb > step_up or -climb > step_down) then
            return remaining <= APPROACH_ENTER_HORIZONTAL
                and math.abs(previous_y - ty) <= APPROACH_ENTER_VERTICAL
                and entry_layer_agrees(graph, previous_y, tx, tz, ty, required_component);
        end
        previous_y = best_y;
    end
    -- Terminal-layer proof: ground that carries all the way to the trigger's
    -- XZ is still a ROOF if it arrives on the wrong layer. Marching over the
    -- z2u6 mouth completed every step on plateau ground twelve yalms above
    -- the tunnel and hit a bare 'return true' here.
    return math.abs(previous_y - ty) <= APPROACH_ENTER_VERTICAL
        and entry_layer_agrees(graph, previous_y, tx, tz, ty, required_component);
end
local function certify_candidates(candidates, x, z, y, graph, required_component, area_goal)
    if (type(candidates) ~= 'table') then
        return {};
    end
    -- Nearest first, so the proof budget is spent on the candidates a route
    -- would actually want to anchor to.
    local ordered = {};
    for _, candidate in ipairs(candidates) do ordered[#ordered + 1] = candidate; end
    table.sort(ordered, function (a, b)
        return (tonumber(a.distance) or 1e9) < (tonumber(b.distance) or 1e9);
    end);

    local radius = body_radius(graph);
    local standing = required_component
        or (graph ~= nil and standing_component(graph, ordered) or nil);
    local certified = {};
    local proofs = 0;
    local limit_h = area_goal and APPROACH_HORIZONTAL or CERTIFY_HORIZONTAL;
    local limit_v = area_goal and APPROACH_VERTICAL or CERTIFY_VERTICAL;

    for _, candidate in ipairs(ordered) do
        if (proofs >= CONNECTOR_MAX_PROOFS) then break; end
        local horizontal = tonumber(candidate.horizontal) or 999999;
        local vertical = tonumber(candidate.vertical) or 999999;
        local cost = tonumber(candidate.distance);
        local node_id = tonumber(candidate.node_id);
        -- A connector straight up or down has no horizontal walk in it, which
        -- is not a step anybody can take; the loader refuses it and so do we.
        -- An area anchor is exempt: there is no connector to walk.
        local walkable_connector = area_goal or horizontal > 1e-6 or vertical < 1e-6;
        if (node_id ~= nil
            and horizontal <= limit_h and vertical <= limit_v
            and finite(cost) and cost >= 0 and walkable_connector) then
            local point = graph ~= nil and graph:point(node_id) or nil;
            local proven = false;
            -- Same piece of ground the player is standing on, first. This is the
            -- cheap half of the proof and it is the half that catches the
            -- hillside: a node the player cannot walk to at all is in another
            -- component however near it looks.
            --
            -- It costs a table lookup, so it must NOT spend the proof budget.
            -- It did, and that refused Ordelle's Caves: candidates are ordered
            -- by 3D distance, the stranded islet at the trigger's own level is
            -- nearer than the real ground twelve yalms above it, and eight
            -- islet nodes exhausted the budget before the ground the player
            -- actually walks in on was ever considered.
            if (point ~= nil and standing ~= nil
                and tonumber(point.component_id) ~= standing) then
                point = nil;
            end
            if (point ~= nil) then
                proofs = proofs + 1;
                if (area_goal) then
                    -- The anchor must certify ENTRY, not proximity: the march
                    -- from this candidate to the lip of the zoning volume, on
                    -- the player's own ground. See approach_proven.
                    local ok, verdict = pcall(approach_proven, graph, point, x, z, y, radius, standing);
                    proven = ok and verdict == true;
                else
                    local ok, verdict = pcall(connector_proven, graph, x, z, y, point, radius);
                    proven = ok and verdict == true;
                end
            end
            if (proven) then
                certified[#certified + 1] = {
                    node_id = node_id,
                    connector_cost = cost,
                    connector_certified = true,
                    connector_proof = area_goal and 'area-anchor' or 'walked-support',
                    x = x, z = z, y = y,
                };
            end
        end
    end
    return certified;
end

local function gather(graph, x, z, y, horizontal, vertical, results)
    local ok, candidates = pcall(graph.candidates, graph, x, z, y, {
        max_horizontal = horizontal or CANDIDATE_HORIZONTAL,
        max_vertical = vertical or CANDIDATE_VERTICAL,
        max_results = results or CANDIDATE_RESULTS,
        minimum_node_clearance = body_radius(graph),
    });
    if (not ok or type(candidates) ~= 'table') then
        return nil;
    end
    return candidates;
end

-- A zone line is somewhere you WALK INTO, not somewhere you stand. Its recorded
-- coordinate is a trigger volume, and the collision model routinely ends before
-- it -- so the point itself often sits off the walkable ground entirely.
--
-- Ordelle's Caves z2u6 is the case that proved it. Its coordinate is
-- (-276.6, 99.6, y=20.6); the nearest ground the player is RECORDED WALKING is
-- 11 yalms away at y=8.4. Twelve yalms apart vertically. A 4-yalm vertical
-- window finds only a 348-node island stranded at the trigger's own level and
-- never the ground the player actually arrives on, so the route was refused to
-- a zone line the player had walked to that same day.
local function is_area_destination(destination)
    if (type(accessxi) == 'table'
        and type(accessxi.nav_point_is_zoneline) == 'function') then
        local ok, verdict = pcall(accessxi.nav_point_is_zoneline, destination);
        if (ok and verdict == true) then
            return true;
        end
    end
    if (tostring(destination ~= nil and destination.kind or '') == 'area') then
        return true;
    end
    local name = tostring(destination ~= nil and destination.name or ''):lower();
    return name:find('zone line', 1, true) ~= nil;
end


--------------------------------------------------------------------------------
-- Request lifecycle
--------------------------------------------------------------------------------

-- Typed rejection kinds. The caller uses these to decide which fallbacks remain
-- permissible; a graph that PROVES no route exists is stronger evidence than the
-- mesh that has been wrong here all along, and must not be overruled by it.
--   'unavailable'  graph absent, disabled, or corrupt -- old behaviour is fine
--   'no-path'      graph proved these components do not connect
--   'unreachable'  live position or destination is not on certified ground
--   'rejected'     a route existed but failed certification
local function reject(kind, message)
    state.search = nil;
    state.request = nil;
    state.mode = state.graph ~= nil and 'ready' or state.mode;
    set_reason(kind, message);
    return nil, kind, message;
end

function walk_graph_route.begin(player, destination)
    if (not walk_graph_route.applies(player, destination)) then
        return reject('unavailable', 'The walk graph does not cover this zone.');
    end
    if (state.graph == nil) then
        if (state.mode == 'unavailable') then
            return nil, 'unavailable', state.load_error or 'The La Theine walk graph is unavailable.';
        end
        if (state.loader == nil and not begin_load()) then
            state.mode = 'unavailable';
            return nil, 'unavailable', state.load_error or 'The La Theine walk graph is unavailable.';
        end
        state.request = {
            player = { x = tonumber(player.x) or 0, z = tonumber(player.z) or 0, y = tonumber(player.y) or 0 },
            destination = destination,
        };
        return nil, 'pending', 'Planning a La Theine route. No direction is ready yet. Navigation will start automatically.';
    end

    local graph = state.graph;
    local starts = gather(graph, tonumber(player.x) or 0, tonumber(player.z) or 0, tonumber(player.y) or 0);
    if (starts == nil or #starts == 0) then
        return reject('unreachable',
            'I cannot verify a safe route from here. You are not standing on mapped ground.');
    end
    local area_goal = is_area_destination(destination);
    local goals = gather(graph,
        tonumber(destination.x) or 0, tonumber(destination.z) or 0, tonumber(destination.y) or 0,
        area_goal and APPROACH_HORIZONTAL or nil,
        area_goal and APPROACH_VERTICAL or nil,
        area_goal and APPROACH_RESULTS or nil);
    if (goals == nil or #goals == 0) then
        return reject('unreachable',
            'I cannot verify a safe route to that destination.');
    end

    local certified_starts = certify_candidates(starts,
        tonumber(player.x) or 0, tonumber(player.z) or 0, tonumber(player.y) or 0,
        state.graph);
    if (#certified_starts == 0) then
        return reject('unreachable',
            'I cannot verify a safe route from here. You are too far from mapped ground.');
    end

    -- Anchor the goal on the player's OWN ground. Without this the goal is
    -- certified against whatever lies nearest the destination coordinate, which
    -- at a zone line is routinely a stranded islet -- and the route is refused
    -- to somewhere the player walked in from that morning.
    local start_component = nil;
    do
        local first = graph:point(certified_starts[1].node_id);
        start_component = first ~= nil and tonumber(first.component_id) or nil;
    end
    local certified_goals = certify_candidates(goals,
        tonumber(destination.x) or 0, tonumber(destination.z) or 0,
        tonumber(destination.y) or 0, state.graph, start_component, area_goal);
    if (#certified_goals == 0) then
        return reject('unreachable',
            'I cannot verify a safe route to that destination from where you are standing.');
    end

    local ok, search, message = pcall(graph.begin_route, graph, certified_starts, certified_goals);
    if (not ok or search == nil) then
        return reject('unavailable',
            'The La Theine walk graph could not start a search: ' .. tostring(message or search));
    end

    state.search = search;
    state.request = {
        player = { x = tonumber(player.x) or 0, z = tonumber(player.z) or 0, y = tonumber(player.y) or 0 },
        destination = destination,
        start_anchor = certified_starts[1],
        goal_anchor = certified_goals[1],
        -- The component the route lives on. densify() snaps interpolated
        -- heights to graph ground, and without this it snapped waypoints onto
        -- a SEVERED tunnel floor 6.7 yalms below the route -- points on real
        -- ground the player could never stand on. Foreign ground is worse
        -- than no ground.
        start_component = start_component,
        expansions = 0,
    };
    state.mode = 'searching';
    set_reason('searching', '');
    do
        local goal_node = state.graph:point(certified_goals[1].node_id);
        state.request.anchor_note = ('start=(%.1f,%.1f,%.1f) component=%s -> goal=(%.1f,%.1f,%.1f) component=%s starts=%d goals=%d'):format(
            tonumber(player.x) or 0, tonumber(player.z) or 0, tonumber(player.y) or 0,
            tostring(start_component),
            tonumber(destination.x) or 0, tonumber(destination.z) or 0,
            tonumber(destination.y) or 0,
            tostring(goal_node ~= nil and goal_node.component_id or nil),
            #certified_starts, #certified_goals);
    end
    return nil, 'pending', '';
end

-- The funnel returns the pulled string: as few corners as possible, which is
-- exactly right as a path and wrong as a set of waypoints. Measured on a real
-- route to the Valkurm zone line the legs ran to 63.2 yalms, median 10.5.
--
-- Everything downstream assumes waypoints are close together. Progress matching
-- allows 24 yalms of forward route arc, so a 63-yalm leg consumes the entire
-- window and the tracker cannot reach the next segment. Drift is measured only
-- against the three segments around the tracked index, so once the index lags
-- on a long leg the player's distance from those particular segments explodes
-- past the 18-yalm replan threshold -- and a replan resets the index, which
-- starts it again. On 2026-08-21 that loop reinstalled the route ten times in
-- four minutes, each install re-announcing and re-aiming: heard as a beacon
-- that will not hold still. The player's actual drift from the route over that
-- whole walk was median 1.11 and never worse than 4.44 yalms. They were
-- following it correctly the entire time.
--
-- Subdividing a funnel leg invents nothing. The leg is a straight line the
-- string was already pulled through certified portals; this only puts marks
-- along it. Heights are snapped to the graph's own ground where it has some,
-- so an intermediate waypoint on a slope does not claim a height taken from
-- the far end of a long leg.
local MAX_LEG = 8.0;
-- How far the graph ground under a densified point may sit from the leg's own
-- interpolated height before it stops being THIS corridor. Legs are at most
-- MAX_LEG long and their corners sit exactly on certified ground, so honest
-- mid-leg deviation is bounded by the climb the leg itself makes; ground
-- beyond that is a different storey.
local DENSIFY_CORRIDOR_VERTICAL = 2.0;

local function densify(points, route_component)
    local count = points:len();
    if (count < 2) then return points; end
    local graph = state.graph;
    local out = T{};
    out:append(points[1]);
    for index = 2, count do
        local a, b = points[index - 1], points[index];
        local dx, dz = b.x - a.x, b.z - a.z;
        local run = math.sqrt((dx * dx) + (dz * dz));
        local pieces = math.ceil(run / MAX_LEG);
        if (pieces > 1) then
            for step = 1, pieces - 1 do
                local t = step / pieces;
                local mx, mz = a.x + (dx * t), a.z + (dz * t);
                local my = a.y + ((b.y - a.y) * t);
                -- The graph's own ground under this point, NOT the straight line
                -- between the corners. A leg that crosses a slope leaves the
                -- linear height yalms out -- measured against the collision
                -- model, 11 of 121 interpolated points were off by up to 4.85,
                -- while every real corner was exact. The band has to be wide
                -- enough to find the ground the guess missed, which is the whole
                -- reason the guess was wrong.
                local snapped = nil;
                if (graph ~= nil) then
                    local ok, found = pcall(graph.candidates, graph, mx, mz, my, {
                        max_horizontal = 2.5, max_vertical = 3.0,
                        max_results = 8, minimum_node_clearance = 0,
                    });
                    if (ok and type(found) == 'table' and #found > 0) then
                        local gap = nil;
                        for _, entry in ipairs(found) do
                            local ey = tonumber(entry.y);
                            if (ey ~= nil and ey == ey) then
                                -- Only the route's OWN component may vouch for a
                                -- waypoint. Without this, a leg passing over the
                                -- Ordelle cave mouth had its midpoints snapped
                                -- onto the severed tunnel floor 6.7 yalms below
                                -- -- real ground, unreachable from the route,
                                -- and the player orbited above it. Foreign
                                -- ground is worse than no ground: no ground
                                -- drops the point, foreign ground aims at it.
                                -- CORRIDOR-LOCAL, not merely component-local.
                                -- The offline repair merged the tunnel floor
                                -- into the main component, so "same component"
                                -- no longer separates the route's own ground
                                -- from real ground stacked beneath it. The
                                -- corridor is the leg the funnel certified:
                                -- ground more than DENSIFY_CORRIDOR_VERTICAL
                                -- from the leg's own height is another storey,
                                -- and a beacon aimed at another storey is the
                                -- orbit at the cave mouth all over again.
                                local eligible = math.abs(ey - my) <= DENSIFY_CORRIDOR_VERTICAL;
                                if (eligible and route_component ~= nil) then
                                    local p = graph:point(entry.node_id);
                                    eligible = p ~= nil
                                        and tonumber(p.component_id) == route_component;
                                end
                                if (eligible) then
                                    local d = math.abs(ey - my);
                                    if (gap == nil or d < gap) then gap = d; snapped = ey; end
                                end
                            end
                        end
                    end
                end
                -- No ground the graph will vouch for. Emit nothing here: a
                -- longer leg is a nuisance, a waypoint hanging in the air is a
                -- direction to walk off something.
                if (snapped ~= nil) then
                my = snapped;
                out:append(T{
                    zone = ZONE,
                    name = ('Waypoint %d'):fmt(out:len() + 1),
                    x = mx, z = mz, y = my,
                    kind = 'route',
                    source = ROUTE_ID,
                    route_override_id = ROUTE_ID,
                    -- Deliberately carries no portal id or y_from/y_to. This is
                    -- a mark along a leg, not a doorway, and nothing downstream
                    -- should mistake it for one.
                    walk_graph_interpolated = true,
                });
                end
            end
        end
        out:append(b);
    end
    return out;
end

local function build_points(funnel, destination, route_component)
    local points = T{};
    local corners = funnel ~= nil and funnel.corners or nil;
    if (type(corners) ~= 'table' or #corners < 2) then
        return nil;
    end
    for index, corner in ipairs(corners) do
        -- A corner is one of two things. The start/goal connectors and the two
        -- graph anchors sit on a single surface and carry a plain y. Everything
        -- between them is a PORTAL endpoint, and a portal deliberately does not
        -- have one height: it has the floor on the near side (y_from) and the
        -- floor on the far side (y_to). The format keeps both precisely so
        -- nobody invents a single ledge height, which is how a route ends up
        -- describing ground that is not there.
        --
        -- A waypoint is somewhere the player walks TOWARD, and while they are
        -- walking toward a doorway they are standing on the near side of it. So
        -- the approach height is y_from. y_to is the floor they arrive on after
        -- stepping through, and it is carried alongside rather than discarded,
        -- so nothing downstream mistakes one height for the whole story.
        local y = corner.y;
        if (y == nil) then y = corner.y_from; end
        if (not finite(corner.x) or not finite(corner.z) or not finite(y)) then
            return nil;
        end
        points:append(T{
            zone = ZONE,
            name = index == #corners
                and tostring(destination ~= nil and destination.name or 'Destination')
                or ('Waypoint %d'):fmt(index),
            x = tonumber(corner.x),
            z = tonumber(corner.z),
            y = tonumber(y),
            kind = 'route',
            source = ROUTE_ID,
            route_override_id = ROUTE_ID,
            walk_graph_y_from = tonumber(corner.y_from),
            walk_graph_y_to = tonumber(corner.y_to),
            walk_graph_portal_id = tonumber(corner.portal_id),
        });
    end
    if (points:len() < 2) then
        return nil;
    end
    return densify(points, route_component);
end

local function finish_route(route)
    local graph, request = state.graph, state.request;
    if (graph == nil or request == nil) then
        return reject('unavailable', 'The La Theine walk graph lost its request.');
    end
    local start_point = {
        x = request.player.x, z = request.player.z, y = request.player.y,
        connector_certified = true,
    };
    local destination = request.destination;
    local goal_point = {
        x = tonumber(destination.x) or 0,
        z = tonumber(destination.z) or 0,
        y = tonumber(destination.y) or 0,
        connector_certified = true,
    };
    local ok, funnel, message = pcall(graph.funnel, graph, route, start_point, goal_point);
    if (not ok or funnel == nil) then
        return reject('rejected',
            'I cannot verify a safe route from here: ' .. tostring(message or funnel));
    end
    local points = build_points(funnel, destination,
        request ~= nil and request.start_component or nil);
    if (points == nil) then
        return reject('rejected', 'I cannot verify a safe route from here.');
    end
    state.search = nil;
    state.request = nil;
    state.mode = 'ready';
    set_reason('ready', '');
    return points, 'ready', '';
end

-- Drive the load and the search under a frame budget. Returns the same tri-state
-- the seam uses: points+'ready', nil+'pending', or nil+<typed kind>+message.
function walk_graph_route.poll()
    if (state.graph == nil) then
        if (state.loader == nil) then
            return nil, state.mode == 'unavailable' and 'unavailable' or 'idle',
                state.load_error or '';
        end
        local status, message = step_load(LOAD_BUDGET_MS);
        if (status == 'pending') then
            return nil, 'pending', '';
        end
        if (status ~= 'ready') then
            return nil, 'unavailable', message or state.load_error or '';
        end
        -- The graph is now available, but the search is NOT restarted here.
        -- Loading takes about four seconds spread across frames, and the
        -- position that arrived with the original request is four seconds old
        -- by the time it finishes. Anchoring a funnel to where the player was
        -- standing when they asked would start the route somewhere they have
        -- already walked away from. The caller re-issues with a live position
        -- instead; see accessxi.poll_nav_walk_graph.
        return nil, 'pending', '';
    end

    if (state.search == nil) then
        return nil, state.mode == 'ready' and 'idle' or state.mode, state.last_reason;
    end

    local deadline = now_ms() + SEARCH_BUDGET_MS;
    local slices = 0;
    repeat
        slices = slices + 1;
        local ok, status, route, message = pcall(state.search.step, state.search, SEARCH_SLICE_EXPANSIONS);
        if (not ok) then
            return reject('unavailable', 'The La Theine walk graph search failed: ' .. tostring(status));
        end
        state.request.expansions = (state.request.expansions or 0) + SEARCH_SLICE_EXPANSIONS;
        if (status == 'ready' and route ~= nil) then
            return finish_route(route);
        end
        if (status == 'no-path') then
            return reject('no-path',
                'I cannot verify a safe route from here. There is no walkable way to that destination.');
        end
        if (status ~= 'pending') then
            return reject('unavailable',
                'The La Theine walk graph search failed: ' .. tostring(message or status));
        end
        if ((state.request.expansions or 0) >= SEARCH_EXPANSION_CAP) then
            -- A BUDGET IS NOT A PROOF.
            --
            -- This used to reject as 'no-path', and the caller treats no-path
            -- as PROOF that two places do not connect -- it sets
            -- walk_graph_restricted and blocks the navmesh and the recorded
            -- overrides from answering, on the grounds that a proof outranks a
            -- mesh that has been confidently wrong in this zone. That is right
            -- for a real proof and wrong here: running out of expansions says
            -- only that the search stopped, and on 2026-08-24 it cost the
            -- player every route in the zone -- the walk graph gave up and
            -- nothing else was allowed to answer, so "still doesn't route".
            --
            -- Offline, from that player's exact position, this same search
            -- converges in 85 slices with a 230-point route. So the cap was
            -- never the real limit, and treating the cap as evidence buried
            -- the actual defect underneath a confident refusal.
            return reject('budget',
                'I could not finish planning a safe route from here.');
        end
    until now_ms() >= deadline or slices >= SEARCH_MAX_SLICES_PER_POLL;
    return nil, 'pending', '';
end

if (type(accessxi) == 'table') then
    accessxi.walk_graph_route = walk_graph_route;
end

return walk_graph_route;
