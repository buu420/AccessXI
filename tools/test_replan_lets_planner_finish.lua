-- A PLAN IN FLIGHT IS NOT AN EMPTY ROUTE.
--
-- Live 2026-08-28. Routing to the Shattered Telepoint in La Theine sat in
-- phase=searching for forty-five seconds and never produced anything:
--
--   18:37:15 nav walk graph progress ... phase=searching polls=1 expansions=0 loaded=0
--   18:37:18 nav walk graph still planning destination="Shattered Telepoint"
--   18:37:22 nav walk graph progress ... phase=searching polls=1 expansions=0 loaded=0
--   ... every three seconds, forever ...
--
-- The player named it from the outside: "it'll tell me recalculating route when
-- I'm walking a straight path. A few times it told me it couldn't find a route
-- even though I was walking a straight path."
--
-- poll_nav_route re-plans whenever the route is EMPTY and three seconds have
-- passed. While the walk graph is still working the route is legitimately
-- empty, so that timer fired straight through the middle of the plan: each
-- rebuild made a new pending record with a fresh started_tick, discarding the
-- loader and the A* workspace. Since the thirty-second deadline measures
-- `now - pending.started_tick`, restarting the record reset the deadline too --
-- thirty seconds that could never elapse.
--
-- The plan needs "286 load slices plus 18 search slices, 1.23s of CPU" (the
-- deadline's own comment). At ~30 polls a second, three seconds kills it around
-- poll ninety, part way through the LOAD -- which is why expansions was always
-- 0. Not a stalled search; a search never reached.
--
-- Structural test against the deployed reader: this is a scheduling defect in a
-- 78,000-line poll loop that cannot be driven offline, so the claims pin the
-- guard, the ordering, and the escape hatches that stop it wedging.
--
--   luajit tools/test_replan_lets_planner_finish.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end
local function line_of(needle)
    local i = reader:find(needle, 1, true);
    if (i == nil) then return nil; end
    local _, n = reader:sub(1, i):gsub('\n', '');
    return n + 1;
end

-- ---------------------------------------------------------------------------
-- 1. THE GUARD EXISTS, ON THE RE-PLAN THAT WAS STARVING THE PLANNER.
-- ---------------------------------------------------------------------------
local guard = [[    if ((accessxi.nav_route_points:len() == 0)
        and type(accessxi.nav_walk_graph_pending) ~= 'table'
        and ((now - (accessxi.nav_route_last_recalc_tick or 0)) > 3000)) then]];
claim(reader:find(guard, 1, true) ~= nil,
    'the three-second re-plan stands down while a walk-graph plan is pending');

-- And there is exactly one such re-plan, so the guard is not one of several.
local _, replans = reader:gsub('now %- %(accessxi%.nav_route_last_recalc_tick or 0%)%) > 3000', '');
claim(replans == 1, 'there is exactly one three-second re-plan, got ' .. replans);

-- ---------------------------------------------------------------------------
-- 2. IT MUST NOT WEDGE. The guard waits on nav_walk_graph_pending, so every
--    path that ends a plan has to clear it -- completion, refusal, zone change,
--    ownership change, and the deadline.
-- ---------------------------------------------------------------------------
local _, cleared = reader:gsub('accessxi%.nav_walk_graph_pending = nil', '');
claim(cleared >= 8,
    'many paths clear the pending record so the guard cannot wedge, got ' .. cleared);

-- The deadline is the backstop: if a plan never finishes, THAT ends it, not a
-- three-second restart.
claim(reader:find('THE DEADLINE. Thirty seconds from the request', 1, true) ~= nil,
    'the thirty-second deadline is still the backstop');
local deadline_at = line_of('if (elapsed >= 30000) then');
claim(deadline_at ~= nil, 'and it is a real comparison, not just a comment');

-- The deadline measures elapsed from the pending record's own start, which is
-- exactly why restarting the record used to reset it.
claim(reader:find('local elapsed = now - (tonumber(pending.started_tick) or now);', 1, true) ~= nil,
    'the deadline is measured from the pending record it protects');

-- ---------------------------------------------------------------------------
-- 3. THE ORDERING THAT SENDS THE PLAYER UP THE STAIRS.
--
--    Good rows, then the proven approach, then -- only then -- a row the
--    catalogue calls bad. Getting these the wrong way round routed the player
--    to the bottom of the stairs and announced arrival.
-- ---------------------------------------------------------------------------
local good_at = line_of('local sibling = accessxi.nav_walk_graph_sibling_row(destination);');
local approach_at = line_of('sibling = accessxi.nav_walk_graph_proven_approach(player, destination);');
local bad_at = line_of('sibling = accessxi.nav_walk_graph_sibling_row(destination, true);');
claim(good_at ~= nil, 'good sibling rows are tried');
claim(approach_at ~= nil, 'the proven-mark approach is tried');
claim(bad_at ~= nil, 'a bad row remains available as a last resort');
claim(good_at ~= nil and approach_at ~= nil and good_at < approach_at,
    'good rows come before the approach');
claim(approach_at ~= nil and bad_at ~= nil and approach_at < bad_at,
    'and the approach comes before any bad row');

-- ---------------------------------------------------------------------------
-- 4. THE CLIMB. Reaching the stairs is not arrival -- the route is extended to
--    the point itself, which is what the player asked for months ago: "the
--    stairs have been mapped already, you just have to lead them up the stairs
--    to click on the point."
-- ---------------------------------------------------------------------------
claim(reader:find('nav residual handoff', 1, true) ~= nil,
    'the stairs-to-point hand-off is still wired');
claim(reader:find('So reaching the stairs is not arrival', 1, true) ~= nil,
    'and still documented as not-arrival');

print(('replan lets planner finish: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
