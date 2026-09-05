-- AN ENTRANCE NAMES ITS ZONE IN target, AND THE ARRIVAL MUST COUNT.
--
-- Live 2026-08-29, Below the Arks. The player examined the Shattered Telepoint,
-- was teleported into the Hall of Transference, examined the Large Apparatus and
-- entered Promyvion-Holla. The mission did not move. Their report: "the mission
-- didn't update, apparently you have to enter the shattered telepoint, then
-- examine the aperatus."
--
-- Two separate causes, both fixed here.
--
-- 1. accessxi.nav_objective_travel_destination_zones merged three sources --
--    destination_zone_id, zones, and a recorded per-step table -- and never read
--    action.target. Action 5 of that step is
--
--      action=travel relationship=enter-through target_kind=entrance
--      target="Hall of Transference"
--      destination_zone_id=0  destination_zone_name=""  zones={}
--
--    so it accepted NO zone and could never complete on arrival. Eleven actions
--    corpus-wide are in that state; ten after excluding transport.
--
-- 2. An arrival is tested against whatever action the cursor is on AT THAT
--    MOMENT. The player zoned into the Hall while the cursor still sat two
--    actions back on a talk, so the evidence was tested against a talk step and
--    discarded. Arrivals are now remembered so the cursor can catch up.
--
--   luajit tools/test_entrance_arrival_completes.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};
_G.T = function (t)
    t = t or {};
    t.len = function (s) return #s end;
    t.append = function (s, v) s[#s + 1] = v end;
    return t;
end
_G.log_line = function () end
_G.speak = function () end
_G.tick = function () return 0; end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end

-- THE REAL RESOLVER, LIFTED. A stub built by this harness would only prove the
-- harness agrees with itself; the whole failure was that the deployed function
-- indexes zoneline edges ONLY, so a zone with no zonelines is nameless -- 134
-- of the game's 297, Hall of Transference among them.
local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
local function lift(header)
    local from = reader:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = reader:find('\nend\n', from, true);
    if (to == nil) then return nil; end
    return reader:sub(from, to + 4);
end

_G.accessxi_paths = { addon_path = function (...)
    return ADDON .. '/' .. table.concat({ ... }, '/');
end };
_G.nav_clean_field = function (v) return trim(v); end

-- The zoneline edges the real function reads, parsed from the shipped TSV.
accessxi.nav_zoneline_edges = {};
accessxi.nav_load_zoneline_graph = function ()
    if (#accessxi.nav_zoneline_edges > 0) then return; end
    local f = io.open(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv', 'r');
    if (f == nil) then return; end
    for line in f:lines() do
        if (line ~= '' and line:sub(1, 1) ~= '#' and line:sub(1, 11) ~= 'zoneline_id') then
            local c = {};
            for field in (line .. '	'):gmatch('([^	]*)	') do c[#c + 1] = field; end
            if (#c > 8) then
                accessxi.nav_zoneline_edges[#accessxi.nav_zoneline_edges + 1] = {
                    from_zone = tonumber(c[2]), from_name = c[3],
                    to_zone = tonumber(c[8]), to_name = c[9],
                };
            end
        end
    end
    f:close();
end

local src = lift('function accessxi.nav_zone_id_for_name(name)');
claim(src ~= nil, 'the real zone-name resolver is in the deployed reader');
if (src == nil) then
    print(('entrance arrival completes: %d passed, %d failed'):format(passed, failed));
    os.exit(1);
end
assert(load(src, 'zoneid'))();

claim(accessxi.nav_zone_id_for_name('La Theine Plateau') == 102,
    'it still resolves a zone that HAS zonelines, got '
    .. tostring(accessxi.nav_zone_id_for_name('La Theine Plateau')));
claim(accessxi.nav_zone_id_for_name('Hall of Transference') == 14,
    'and now resolves one that has NONE, got '
    .. tostring(accessxi.nav_zone_id_for_name('Hall of Transference')));
claim(accessxi.nav_zone_id_for_name('Not A Real Zone') == 0,
    'and still answers 0 for a name that is not a zone');

-- Enough plumbing for the module to load; the function under test needs no more.
accessxi.mission_quest_guide_index = {};
accessxi.objective_guides = {
    progression_actions = function () return {}; end,
    objective_destinations = function () return {}; end,
    source_route_steps = function () return {}; end,
    automatic_step_id = function () return ''; end,
    current_native_key = function () return ''; end,
    is_open = function () return false; end,
};
accessxi.nav_points = T{};
accessxi.nav_graph_zone_name = function (z) return 'zone' .. tostring(z); end
accessxi.current_zone_id = function () return 16; end
accessxi.current_player_identity = function () return 'testchar:1'; end
accessxi.current_player_world_id = function () return 1; end
accessxi.current_objective_session_epoch = function () return 7; end
accessxi.objective_interaction_progress_path = os.getenv('TEMP') .. '/entrance-test.tsv';
do local f = io.open(accessxi.objective_interaction_progress_path, 'wb'); if f then f:close(); end end

local ok_load, err = pcall(dofile, ADDON .. '/modules/mission_quest_navigation.lua');
claim(ok_load, 'the real navigation module loads' .. (ok_load and '' or (': ' .. tostring(err))));
claim(type(accessxi.nav_objective_travel_destination_zones) == 'function',
    'and exposes the travel destination resolver');

-- ---------------------------------------------------------------------------
-- THE REAL SHIPPED ACTION. Not a hand-built stand-in.
-- ---------------------------------------------------------------------------
local prog = dofile(ADDON .. '/modules/mission_quest_progression_mission_chains_of_promathia.lua');
local record = prog.objectives["mission:Chains of Promathia:3"];
claim(type(record) == 'table', 'the shipped Below the Arks progression exists');

local enter, examine = nil, nil;
for _, a in ipairs(record.progression_actions or {}) do
    if (trim(a.relationship):lower() == 'enter-through') then enter = a; end
    if (trim(a.relationship):lower() == 'examine-object') then examine = a; end
end
claim(enter ~= nil, 'it still has an enter-through action');
if (enter ~= nil) then
    claim(trim(enter.target) == 'Hall of Transference',
        'whose target is the Hall of Transference, got "' .. trim(enter.target) .. '"');
    claim((tonumber(enter.destination_zone_id) or 0) == 0 and #(enter.zones or {}) == 0,
        'and which names its zone NOWHERE ELSE -- the whole reason this failed');

    local zones = accessxi.nav_objective_travel_destination_zones(
        "mission:Chains of Promathia:3", enter);
    claim(type(zones) == 'table' and zones[14] == true,
        'arriving in the Hall of Transference (14) now completes it');
end

-- ---------------------------------------------------------------------------
-- THE FALSE POSITIVE THAT MUST NOT BE RESCUED. "Manaclipper" collides with a
-- zone name, but boarding a boat is not arriving anywhere.
-- ---------------------------------------------------------------------------
local boat = {
    step_id = 'test:boat:step-001', action = 'travel',
    relationship = 'board-transport', target = 'Manaclipper',
    destination_zone_id = 0, zones = {},
};
local boat_zones = accessxi.nav_objective_travel_destination_zones('quest:test:1', boat);
local boat_count = 0;
for _ in pairs(type(boat_zones) == 'table' and boat_zones or {}) do boat_count = boat_count + 1; end
claim(boat_count == 0, 'a board-transport target is NOT treated as arrival, got ' .. boat_count);

local used = {
    step_id = 'test:boat:step-002', action = 'travel',
    relationship = 'use-transport', target = 'Manaclipper',
    destination_zone_id = 0, zones = {},
};
local used_zones = accessxi.nav_objective_travel_destination_zones('quest:test:1', used);
local used_count = 0;
for _ in pairs(type(used_zones) == 'table' and used_zones or {}) do used_count = used_count + 1; end
claim(used_count == 0, 'nor a use-transport target, got ' .. used_count);

-- An examine action must not gain a zone either -- it is not a travel.
if (examine ~= nil) then
    local ez = accessxi.nav_objective_travel_destination_zones(
        "mission:Chains of Promathia:3", examine);
    local ec = 0;
    for _ in pairs(type(ez) == 'table' and ez or {}) do ec = ec + 1; end
    claim(ec == 0, 'and an examine action gains no zone, got ' .. ec);
end

-- ---------------------------------------------------------------------------
-- THE CATCH-UP. Bounded, travel-only, and only on zones actually visited.
-- ---------------------------------------------------------------------------
local nav = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
claim(nav:find('accessxi.objective_zones_visited[destination] = tonumber(signal.tick) or 0;', 1, true) ~= nil,
    'an arrival is recorded when it happens');
claim(nav:find('while (caught < 4) do', 1, true) ~= nil,
    'the catch-up is bounded -- an unbounded one swallows steps');
claim(nav:find("if (clean(current.action):lower() ~= 'travel'", 1, true) ~= nil,
    'and only travel steps may be caught up');
claim(nav:find('objective progress CAUGHT UP', 1, true) ~= nil,
    'and it says so, so an unexpected jump is one grep');

-- ---------------------------------------------------------------------------
-- THE NOTE. The guide never mentions the Large Apparatus; the player had to
-- work it out. Additive speech only -- it must not be an override, because a
-- cursor cannot cross an override boundary and this mission is in progress.
-- ---------------------------------------------------------------------------
local notes = dofile(ADDON .. '/modules/mission_quest_step_notes.lua');
claim(type(notes) == 'table', 'the step notes table loads');
local cop = type(notes) == 'table' and notes["mission:Chains of Promathia:3"] or nil;
claim(type(cop) == 'table', 'and carries a note for Below the Arks');
local note = type(cop) == 'table' and cop["mission:Chains of Promathia:3:step-009"] or '';
claim(tostring(note):find('Large Apparatus', 1, true) ~= nil,
    'naming the Large Apparatus the guide leaves out');
claim(tostring(note):find('LEFT', 1, true) ~= nil,
    'and which of the two it is -- the right one wants a Clear Chip');
claim(type(accessxi.objective_step_note) == 'function', 'the note lookup exists');
claim(accessxi.mission_quest_step_notes == nil
    or type(accessxi.mission_quest_step_notes) == 'table',
    'and the table is loaded through the addon, not required here');

os.remove(accessxi.objective_interaction_progress_path);
print(('entrance arrival completes: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
