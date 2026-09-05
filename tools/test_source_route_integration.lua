-- THE PRODUCTION SEAM, driven for real.
--
-- Every other offline test builds a context by hand and calls the resolver
-- through it. That is why three crashes shipped inside source_route_rows while
-- 113 resolver claims stayed green: make_ctx supplies stand-ins for the very
-- closures that were failing, and a harness cannot test the seam it supplies.
--
-- So this file loads the REAL modules in the real order, hands them the REAL
-- shipped data, and calls the public entry the mission menu calls. Nothing
-- about the navigation module is reimplemented here. If a helper is unreachable
-- from where it is used, or a closure reads a nil global, this raises -- which
-- is the whole point.
--
--   luajit tools/test_source_route_integration.lua

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

accessxi = {};
T = function (t)
    t = t or {};
    t.len = function (s) return #s; end
    t.append = function (s, v) s[#s + 1] = v; end
    return t;
end
string.fmt = string.format;
log_line = function () end
bit = bit or { band = function (a) return a; end, bor = function (a) return a; end };

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1; print('  ok  ' .. text);
    else failures = failures + 1; print('  FAIL ' .. text); end
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end

-- The addon's own module loader, reduced to what it does: run the file with a
-- shared environment. Load order matches accessxi_reader.lua.
local function load_code_module(name)
    local chunk, err = loadfile(ADDON .. '/modules/' .. name .. '.lua');
    assert(chunk ~= nil, name .. ': ' .. tostring(err));
    return chunk();
end

-- ---------------------------------------------------------------- real data
local function split_tsv(line)
    local parts = {};
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do parts[#parts + 1] = part; end
    return parts;
end

local nav_points = T{};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-destinations.tsv', 'r'));
    for line in f:lines() do
        if (line ~= '' and not line:match('^#')) then
            local p = split_tsv(line);
            local zone = tonumber(p[1]);
            if (zone and zone > 0 and trim(p[2]) ~= '') then
                nav_points:append({
                    zone = zone, name = trim(p[2]),
                    x = tonumber(p[3]), z = tonumber(p[4]), y = tonumber(p[5]),
                    kind = trim(p[6]), source = trim(p[7]), confidence = trim(p[8]),
                    -- column 9 is the dataset tag, not a zone name.
                    zone_name = '',
                    destination_id = trim(p[10] or ''), raw_identity = trim(p[11] or ''),
                });
            end
        end
    end
    f:close();
end
accessxi.nav_points = nav_points;

local zone_names = {};
local edges = T{};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv', 'r'));
    local header = nil;
    for line in f:lines() do
        if (line ~= '' and not line:match('^#')) then
            local p = split_tsv(line);
            if (header == nil) then header = p;
            else
                local e = {};
                for i, key in ipairs(header) do e[key] = p[i]; end
                e.id = tonumber(e.zoneline_id);
                e.from_zone, e.to_zone = tonumber(e.from_zone), tonumber(e.to_zone);
                e.from_x, e.from_z, e.from_y = tonumber(e.from_x), tonumber(e.from_z), tonumber(e.from_y);
                e.to_x, e.to_z, e.to_y = tonumber(e.to_x), tonumber(e.to_z), tonumber(e.to_y);
                if (e.id and e.from_zone and e.to_zone) then
                    edges:append(e);
                    if (zone_names[e.from_zone] == nil and trim(e.from_name) ~= '') then
                        zone_names[e.from_zone] = trim(e.from_name);
                    end
                    if (zone_names[e.to_zone] == nil and trim(e.to_name) ~= '') then
                        zone_names[e.to_zone] = trim(e.to_name);
                    end
                end
            end
        end
    end
    f:close();
end
accessxi.nav_zoneline_edges = edges;
accessxi.nav_load_zoneline_graph = function () end
accessxi.nav_transport_edge_available = function () return true; end
accessxi.nav_graph_zone_name = function (zone)
    return zone_names[tonumber(zone) or 0] or ('zone ' .. tostring(zone));
end
accessxi.nav_zoneline_edge_rank = function (edge)
    local c = tostring(edge and edge.confidence or ''):lower();
    if (c:find('proven', 1, true)) then return 0; end
    if (c:find('verified', 1, true)) then return 2; end
    if (c:find('generated', 1, true)) then return 6; end
    if (c:find('untested', 1, true)) then return 8; end
    return 50;
end
accessxi.nav_zoneline_out_edges = function (zone)
    local out = T{};
    for _, e in ipairs(edges) do
        if (e.from_zone == zone) then out:append(e); end
    end
    return out;
end
accessxi.nav_zone_id_for_name = function (value)
    local key = trim(value):lower();
    local found, count = 0, 0;
    for zone, name in pairs(zone_names) do
        if (trim(name):lower() == key) then found = zone; count = count + 1; end
    end
    return count == 1 and found or 0;
end

-- The guide, backed by the shipped reconcile and progression modules.
local reconciled, progression = {}, {};
do
    local function each_module(pattern, sink)
        local pipe = io.popen('dir /b "' .. ADDON:gsub('/', '\\') .. '\\modules\\' .. pattern .. '"');
        for name in (pipe and pipe:lines() or function () return nil; end) do
            local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. (name:gsub('%.lua$', '')) .. '.lua');
            if (ok and type(tbl) == 'table') then sink(tbl); end
        end
        if (pipe) then pipe:close(); end
    end
    each_module('mission_quest_reconcile_mission_*.lua', function (tbl)
        for key, entry in pairs(tbl) do
            if (type(entry) == 'table' and type(entry.steps) == 'table') then
                reconciled[key] = entry;
            end
        end
    end);
    each_module('mission_quest_progression_mission_*.lua', function (tbl)
        local objectives = type(tbl.objectives) == 'table' and tbl.objectives or tbl;
        for key, entry in pairs(objectives) do
            if (type(entry) == 'table' and type(entry.progression_actions) == 'table') then
                progression[key] = entry;
            end
        end
    end);
end

-- The guide index, which is where the module reads each objective's revision.
-- Built from the shipped progression modules, not invented.
accessxi.mission_quest_guide_index = {};
for key, entry in pairs(progression) do
    accessxi.mission_quest_guide_index[key] = {
        progression_revision = trim(entry.progression_revision),
        progression_module = trim(entry.progression_module),
    };
end

-- The REAL GuideState, so source_step_readings is the shipped one rather than
-- a stand-in. Falls back to the stub table below only if it cannot construct.
local real_guide = nil;
do
    local ok_index, guide_index = pcall(dofile, ADDON .. '/modules/mission_quest_guide_index.lua');
    local ok_module, guides = pcall(dofile, ADDON .. '/modules/mission_quest_guides.lua');
    if (ok_module and type(guides) == 'table' and type(guides.new) == 'function') then
        real_guide = guides.new({
            index = ok_index and guide_index or {},
            module_loader = function (name)
                local loaded, data = pcall(dofile, ADDON .. '/modules/' .. name .. '.lua');
                return (loaded and type(data) == 'table') and data or nil;
            end,
            identity_provider = function () return 'integration'; end,
            logger = function () end,
        });
    end
end

accessxi.objective_guides = {
    source_step_readings = function (_, native_key, step_id)
        if (real_guide == nil) then return {}; end
        local ok, value = pcall(real_guide.source_step_readings, real_guide, native_key, step_id);
        return (ok and type(value) == 'table') and value or {};
    end,
    source_route_steps = function (_, native_key)
        local entry = reconciled[trim(native_key)];
        if (entry == nil) then return nil; end
        local steps = T{};
        for _, step in ipairs(entry.steps) do steps:append(step); end
        return steps;
    end,
    progression_actions = function (_, native_key)
        local entry = progression[trim(native_key)];
        if (entry == nil) then return nil; end
        local actions = T{};
        for _, action in ipairs(entry.progression_actions) do actions:append(action); end
        return actions;
    end,
    progression_revision = function (_, native_key)
        local entry = progression[trim(native_key)];
        return entry ~= nil and trim(entry.progression_revision) or '';
    end,
    objective_destinations = function () return nil; end,
    route_recommendations = function () return nil; end,
    retain_progression_keys = function () end,
    current_native_key = function () return ''; end,
    automatic_step_id = function () return ''; end,
    is_open = function () return false; end,
    open = function () end,
    close = function () end,
};

local player_zone = 230;
accessxi.current_zone_id = function () return player_zone; end

-- CHARACTER AND MISSION STATE IS INPUT, not mechanism. Supplying "who the
-- player is and which mission is active" is the same as supplying the
-- catalogue: it is data the game would give us. What must NOT be supplied is
-- any part of how the module answers -- no zone_path, no declared_result_names,
-- no primary_actions_for_step. Those are the seams under test.
local PLAYER = 'Integrationtester';
accessxi.current_player_identity = function () return PLAYER:lower() .. '@1'; end
accessxi.current_player_world_id = function () return 1; end
accessxi.current_objective_session_epoch = function () return 1; end
accessxi.nav_mission_quest_sync_character = function () end
accessxi.current_player_name = function () return PLAYER; end
accessxi.player_name = function () return PLAYER; end

-- A Windurst character partway through Windurst mission 2 -- the mission whose
-- final step this session repaired.
accessxi.mission_packet_player = PLAYER;
accessxi.mission_packet_identity = PLAYER:lower() .. '@1';
accessxi.mission_packet_source = 'packet_in_056';
accessxi.mission_packet_main = {
    port = 0xFFFF,
    nation = 2,
    nation_mission = 2,
    rov = 65535,
    tales = 0,
    zilart = 65535,
    cop = 65535,
    toau = 65535,
    wotg = 65535,
    soa = 65535,
    addons = 0,
};

-- The ROM row the game would supply for the active mission. Label and ordinal
-- only; everything downstream of it is the module's own work.
accessxi.load_mission_rom_rows = function (context)
    if (trim(context) ~= 'Windurst') then return nil; end
    local rows = { count = 1, by_mission_id = {} };
    local row = {
        mission_id = 2,
        rom_ordinal = 2,
        label = 'The Heart of the Matter',
        source = 'integration-fixture',
        orders = '',
    };
    rows[1] = row;
    rows.by_mission_id[2] = row;
    return rows;
end

-- ------------------------------------------------------------ real modules
load_code_module('nav_zoneline_router');
load_code_module('objective_announcer');
load_code_module('mission_quest_step_resolver');
load_code_module('mission_quest_navigation');

claim(type(accessxi.mission_step_resolver) == 'table',
    'the resolver module loaded and published itself');
claim(type(accessxi.nav_zoneline_path) == 'function',
    'the road chooser is reachable from the router module, not the monolith');

-- ---------------------------------------------------------------- claims
-- NOT YET COMPUTED IS NOT NO ROUTE. Asked FIRST, before anything has populated
-- the route cache -- which is the state the announcement finds itself in the
-- instant a mission becomes active. Live 2026-08-23 this told the player
-- "No route is available for this objective" about a step whose route was
-- computed five seconds later.
do
    local cold, cold_zone, cold_choice = accessxi.nav_mission_quest_step_route_capability(
        'mission:Windurst:2', 'mission:Windurst:2:step-045');
    claim(cold ~= nil and cold ~= accessxi.objective_announcer.ROUTE.UNAVAILABLE,
        ('a route is reported on a COLD cache, not called unavailable (%s)'):format(tostring(cold)));
    local cold_spoken = accessxi.objective_announcer.route_suffix(cold, cold_zone, cold_choice);
    claim(cold_spoken:find('No route is available', 1, true) == nil,
        'and the player is never told there is no route to a step that has one');
end

-- Everything below drives the module's own public entry. No internal is poked
-- and no seam is replaced.
local items = accessxi.nav_mission_quest_active_items('mission');

claim(type(items) == 'table' and #items > 0,
    ('the mission category builds its items through the real module (%d)')
        :format(type(items) == 'table' and #items or -1));

claim((tonumber(accessxi.nav_objective_source_route_compute_count) or 0) > 0,
    'and source_route_rows actually ran -- the seam the resolver harness stands in for');

-- THE CRASH THIS EXISTS TO CATCH. declared_result_names, the travel-zone
-- persistence and nav_mission_quest_first_objective each called a helper
-- declared below them, which in Lua 5.1 is a global read and nil at runtime.
-- Every one of those paths is exercised by the call above; if any of them
-- resolves to nil again this file raises rather than passing.
local instruction, first_step = accessxi.nav_mission_quest_first_objective('mission:Windurst:2');
claim(trim(instruction) ~= '' and trim(first_step) ~= '',
    ('the first objective reads its compact actions (%s)'):format(trim(first_step)));

-- The step this session repaired, answered through the production path.
local capability, zone_name, choice =
    accessxi.nav_mission_quest_step_route_capability(
        'mission:Windurst:2', 'mission:Windurst:2:step-045');

claim(capability ~= nil and capability ~= accessxi.objective_announcer.ROUTE.UNAVAILABLE,
    ('"speak to Apururu" is routable through the real module (%s)'):format(tostring(capability)));

claim(capability == accessxi.objective_announcer.ROUTE.CHOICE
        and type(choice) == 'table'
        and (tonumber(choice.count) or 0) > 1,
    ('and it is offered as a choice, not silently picked (%d places)')
        :format(type(choice) == 'table' and (tonumber(choice.count) or 0) or -1));

local spoken = accessxi.objective_announcer.route_suffix(capability, zone_name, choice);
claim(spoken:find('Press I to choose from', 1, true) ~= nil
        and spoken:find('Press I to start navigation', 1, true) == nil,
    ('and what the player hears says so: "%s"'):format(spoken));

-- A refusal must still carry the guide's own sentence.
local refused = 0;
for _, item in ipairs(items) do
    local key = trim(item.objective_native_key);
    if (key ~= '') then
        for _, step in ipairs(reconciled[key] and reconciled[key].steps or {}) do
            local refusal = accessxi.nav_mission_quest_step_refusal(key, trim(step.stable_step_id));
            if (type(refusal) == 'table') then
                refused = refused + 1;
                if (trim(refusal.instruction) == '' and trim(step.primary_instruction) ~= '') then
                    refused = -1000000;
                end
            end
        end
    end
end
claim(refused >= 0,
    'every recorded refusal still carries the guide sentence for its step');

print('');
print(('claims=%d failed=%d'):format(passes + failures, failures));
if (not INTEGRATION_EMBED) then
    os.exit(failures == 0 and 0 or 1);
end

return {
    claim = claim,
    reconciled = reconciled,
    progression = progression,
    zone_names = zone_names,
    set_player_zone = function (zone) player_zone = zone; end,
    result = function ()
        print('');
        print(('claims=%d failed=%d'):format(passes + failures, failures));
        os.exit(failures == 0 and 0 or 1);
    end,
};
