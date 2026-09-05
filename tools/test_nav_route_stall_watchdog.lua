-- NAVIGATION MUST NEVER SIT ACTIVE AND SILENT.
--
-- Live 2026-08-26, routing to Balga's Dais: the search chose the West
-- Sarutabaruta entrance, which does not exist. The leg started, terrain mapping
-- was requested for an endpoint off the mesh and never produced a corridor, and
-- because nav_active stayed true the zone-search poll returned at its first line
-- on every pulse. The addon said "Mapping terrain for West Sarutabaruta.
-- Navigation will start automatically" and then NOTHING FOR FIFTEEN MINUTES.
-- The player opened the Areas menu and picked Giddeus by hand -- an entrance the
-- addon held in its own graph the whole time. Twice.
--
-- The invariant: while nav_active is true the route must hold usable points OR a
-- typed planner must be working on it. Anything else is a dead route wearing an
-- active flag.
--
-- Drives the REAL watchdog, lifted verbatim from the deployed accessxi_reader.lua.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');

local function lift(header)
    local from = reader:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = reader:find('\nend\n', from, true);
    if (to == nil) then return nil; end
    return reader:sub(from, to + 4);
end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

-- addon plumbing the watchdog speaks through
local clock, spoken, logged = 0, {}, {};
-- Where the player is, and what they are doing. Standing still is the signal
-- the watchdog reads, and it is exactly what a player does while fighting --
-- so both of these are load-bearing, not scaffolding.
local here = { x = 0, z = 0, y = 0, zone = 246 };
local player_status = 0;   -- 0 idle, 1 engaged, 2 dead, 4 event, 33 resting
_G.safe_call = function (fn, fallback)
    local ok, value = pcall(fn);
    if (ok) then return value; end
    return fallback;
end
_G.GetPlayerEntity = function () return { Status = player_status }; end
_G.nav_cached_player_position = function () return here; end
_G.tick = function () return clock; end
_G.speak = function (text) spoken[#spoken + 1] = tostring(text or ''); end
_G.log_line = function (text) logged[#logged + 1] = tostring(text or ''); end
local Tmt = {}; Tmt.__index = {
    append = function (s, v) s[#s + 1] = v; return s; end,
    len = function (s) return #s; end,
};
_G.T = function (t) return setmetatable(t or {}, Tmt); end
accessxi.speech_name = function (v) return tostring(v or ''); end
accessxi.escape_probe_log_text = function (v) return tostring(v or ''); end
accessxi.nav_graph_zone_name = function (z) return 'zone' .. tostring(z); end

for _, header in ipairs({
    'function accessxi.nav_route_plan_deadline_ms()',
    'function accessxi.nav_route_exclude_edge(edge_id, reason, scope)',
    'function accessxi.nav_route_clear_excluded_edges(reason)',
    'function accessxi.nav_route_stall_watchdog(now)',
}) do
    local src = lift(header);
    claim(src ~= nil, 'lifted: ' .. header);
    if (src ~= nil) then assert(load(src, header))(); end
end
claim(type(accessxi.nav_route_stall_watchdog) == 'function', 'the real watchdog loaded');

local DEADLINE = accessxi.nav_route_plan_deadline_ms();
claim(DEADLINE >= 5000 and DEADLINE <= 60000,
    'the plan deadline is a sane number of milliseconds, got ' .. tostring(DEADLINE));

-- Park the player still and idle, then let the anchor age past the stillness
-- window, which is what the watchdog now actually requires.
local function stand_still(ms)
    accessxi.nav_route_stall_watchdog(clock);      -- plants the anchor
    clock = clock + (ms or 15000);
end

local function reset(opts)
    opts = opts or {};
    clock = 100000;
    spoken, logged = {}, {};
    here = { x = 0, z = 0, y = 0, zone = 246 };
    player_status = opts.status or 0;
    accessxi.nav_route_watchdog_anchor = nil;
    accessxi.nav_final_approach = opts.final_approach or nil;
    accessxi.nav_active = opts.active ~= false;
    accessxi.nav_zone_search_target = opts.no_target and nil or { name = 'Balga\'s Dais' };
    accessxi.nav_route_points = T(opts.points or {});
    accessxi.nav_walk_graph_pending = opts.pending or nil;
    accessxi.nav_dat_collision_pending = nil;
    accessxi.nav_route_current_edge_id = opts.edge_id or 1731670906;
    accessxi.nav_route_current_edge_name = 'zone115 to zone146';
    accessxi.nav_route_leg_started_tick = opts.started or clock;
    accessxi.nav_route_excluded_edges = {};
end

-- 1. Quiet cases. The watchdog must not fire on a healthy route.
reset({ active = false });
claim(accessxi.nav_route_stall_watchdog(clock) == false, 'inactive navigation is not stalled');

reset({ no_target = true });
claim(accessxi.nav_route_stall_watchdog(clock) == false, 'no zone search target is not stalled');

reset({ points = { 'a', 'b', 'c' } });
claim(accessxi.nav_route_stall_watchdog(clock) == false, 'a route with points is not stalled');

-- 2. PATIENCE. A planner inside its deadline is left alone.
reset({ pending = { started_tick = 100000 } });
clock = 100000 + DEADLINE - 1;
claim(accessxi.nav_route_stall_watchdog(clock) == false,
    'a planner one millisecond inside its deadline is left to work');
claim(accessxi.nav_active == true, 'and navigation stays active');
claim(#spoken == 0, 'and nothing is spoken');

-- 3. THE REGRESSION. A planner past its deadline is a dead route.
reset({ pending = { started_tick = 100000 } });
clock = 100000 + DEADLINE + 1;
stand_still(15000);
claim(accessxi.nav_route_stall_watchdog(clock) == true,
    'a planner past its deadline is stalled');
claim(accessxi.nav_active == false, 'navigation is stopped rather than left silent');
claim(#spoken == 1, 'and the player is told, got ' .. #spoken .. ' utterances');
claim(spoken[1] ~= nil and spoken[1]:find('another route', 1, true) ~= nil,
    'the speech says it is looking for another way: "' .. tostring(spoken[1]) .. '"');
claim(accessxi.nav_route_excluded_edges[1731670906] ~= nil,
    'the offending edge is excluded');
claim(accessxi.nav_route_excluded_edges[1731670906].scope == 'session',
    'a blown plan deadline excludes for the session, got '
    .. tostring(accessxi.nav_route_excluded_edges[1731670906].scope));
claim(accessxi.nav_walk_graph_pending == nil, 'the dead planner is cleared');
claim(tonumber(accessxi.nav_zone_search_last_replan_tick) == 0,
    'and the re-plan timer is released so the next pulse searches again');

-- 4. An empty route with NO planner at all is dead immediately after a grace.
reset({ started = 100000 });
clock = 100000 + 500;
claim(accessxi.nav_route_stall_watchdog(clock) == false,
    'a route empty for half a second is merely between plans');
reset({ started = 100000 });
clock = 100000 + 3000;
stand_still(15000);
claim(accessxi.nav_route_stall_watchdog(clock) == true,
    'a route empty and unattended, with the player going nowhere, is dead');
claim(accessxi.nav_route_excluded_edges[1731670906].scope == 'zone-visit',
    'no planner at all is a weaker claim against the edge, got '
    .. tostring(accessxi.nav_route_excluded_edges[1731670906].scope));

-- 4b. THE REGRESSION. A route that is MOVING the player must never be killed.
--
-- Live 2026-08-27, At the Heavens' Door: the player walked ninety yalms across
-- Port Jeuno on a 29-point route, consumed every waypoint, and was on the
-- straight run in when this fired and stopped them twenty-eight yalms from the
-- zone line. An empty waypoint list is not a dead route.
reset({ started = 100000 });
accessxi.nav_route_stall_watchdog(clock);          -- plant the anchor
clock = clock + 15000;
here = { x = 0, z = 40, y = 0, zone = 246 };       -- forty yalms further on
claim(accessxi.nav_route_stall_watchdog(clock) == false,
    'a player who is still travelling is never stalled');
claim(accessxi.nav_active == true, 'and their route survives');
claim(#spoken == 0, 'and nothing is said to them');

-- The anchor must follow them, or the second window would fire on the spot
-- they had already left.
clock = clock + 15000;
here = { x = 0, z = 80, y = 0, zone = 246 };
claim(accessxi.nav_route_stall_watchdog(clock) == false,
    'and it keeps re-anchoring as they go');

-- 4c. A PLAYER WHO IS BUSY IS NOT A PLAYER WHO IS STUCK. They level in the
--     zones they navigate, so fighting mid-route is the normal case.
for _, state in ipairs({ { 1, 'engaged' }, { 2, 'dead' }, { 4, 'in an event' },
                         { 33, 'resting' } }) do
    reset({ started = 100000, status = state[1] });
    stand_still(20000);
    claim(accessxi.nav_route_stall_watchdog(clock) == false,
        'a player ' .. state[2] .. ' is never stalled');
    claim(accessxi.nav_active == true, 'and keeps their route while ' .. state[2]);
end

-- 4d. Standing still ISN'T enough on its own -- it has to last.
reset({ started = 100000 });
accessxi.nav_route_stall_watchdog(clock);
clock = clock + 4000;
claim(accessxi.nav_route_stall_watchdog(clock) == false,
    'four seconds of stillness is not a stall');

-- 4e. The final approach has its own timeout and must not be pre-empted.
reset({ started = 100000, final_approach = { destination = 'x' } });
stand_still(20000);
claim(accessxi.nav_route_stall_watchdog(clock) == false,
    'the final approach is left to its own timeout');

-- 5. Exclusion is recorded once, not once per pulse.
reset({});
accessxi.nav_route_excluded_edges = {};
claim(accessxi.nav_route_exclude_edge(42, 'x', 'session') == true, 'a new edge is excluded');
claim(accessxi.nav_route_exclude_edge(42, 'y', 'session') == false,
    'the same edge is not excluded twice -- otherwise the log grows every pulse');
claim(accessxi.nav_route_exclude_edge(0, 'x', 'session') == false, 'edge id zero is ignored');
accessxi.nav_route_clear_excluded_edges('test');
claim(next(accessxi.nav_route_excluded_edges) == nil, 'clearing empties the set');

-- 6. THE CHOKE POINT. Every path search must consult the exclusions, or the
--    watchdog would keep excluding an edge the planner keeps re-picking.
claim(reader:find('local excluded = accessxi.nav_route_excluded_edges;', 1, true) ~= nil,
    'nav_zoneline_out_edges reads the exclusion set');
claim(reader:find('or excluded[tonumber(edge.id) or 0] == nil)', 1, true) ~= nil,
    'and filters on it');
local out_at = reader:find('function accessxi.nav_zoneline_out_edges(zone, player)', 1, true);
local filter_at = reader:find('local excluded = accessxi.nav_route_excluded_edges;', 1, true);
claim(out_at ~= nil and filter_at ~= nil and filter_at > out_at,
    'the filter is inside the out-edges function, not somewhere decorative');

-- 7. A search that spends its alternatives must SAY so, not repeat "no route".
claim(reader:find('Every known way in from %s was tried and none could be planned', 1, true) ~= nil,
    'an exhausted search reports that it tried and failed, distinctly from never knowing a route');

-- 8. The leg records which edge it rides, or the watchdog has nothing to blame.
claim(reader:find('accessxi.nav_route_current_edge_id = tonumber(edge.id) or 0;', 1, true) ~= nil,
    'the leg start records its edge id');

-- 9. And a fresh destination starts with a clean slate.
-- Line endings are CRLF in the deployed file, so match the lines separately
-- and assert proximity rather than embedding a newline.
local clear_at = reader:find('accessxi.nav_clear_zone_search = function ()', 1, true);
local reset_at = clear_at ~= nil
    and reader:find('accessxi.nav_route_excluded_edges = {};', clear_at, true) or nil;
local edge_at = clear_at ~= nil
    and reader:find('accessxi.nav_route_current_edge_id = 0;', clear_at, true) or nil;
claim(clear_at ~= nil and reset_at ~= nil and edge_at ~= nil
    and (reset_at - clear_at) < 200 and (edge_at - clear_at) < 200,
    'clearing the zone search clears the exclusions with it');

print(('nav route stall watchdog: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
