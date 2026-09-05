-- THE QUEST HALF OF THE EXHAUSTED-CURSOR REPAIR, DRIVEN FOR REAL.
--
-- expand_active_mission_destinations and expand_active_quest_destinations share
-- the defect (an exhausted cursor answering like an objective with no cursor,
-- and the empty step filter then appending every route row the objective owns)
-- and they share the repair. tools/test_exhausted_cursor_row.lua drives the
-- mission side against the player's own progress rows; the quest side had only
-- structural claims, and this project has been bitten before by a harness that
-- proves wiring rather than reachability -- 113 green resolver claims while
-- three crashes sat inside source_route_rows, because the harness supplied the
-- very seam that was failing. sol asked for a real one. This is it.
--
-- Two quests, chosen because between them they exercise every branch:
--
--   quest:sandoria:7   "The Trader in the Forest" -- 3 compact actions, both
--                      pages have prose left, no material tail, nothing
--                      truncated. The plain postlude.
--   quest:crystal_war:31 "The Swarm" -- 3 compact actions, both pages have
--                      prose left, TWO material steps still to come and more
--                      text than the six-line cap. The wording for "automatic
--                      tracking ended but the guide did not", and the
--                      truncation disclosure.
--
-- Cursors are exhausted by writing the progress rows the game would have
-- written, in the shipped v2 format, against the shipped progression revision.
--
--   luajit tools/test_exhausted_cursor_quest.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
local SCRATCH = os.getenv('TEMP') or '.';

accessxi = {};
T = function (t)
    t = t or {};
    t.len = function (s) return #s; end
    t.append = function (s, v) s[#s + 1] = v; end
    t.clear = function (s) for i = #s, 1, -1 do s[i] = nil; end end
    return t;
end
string.fmt = string.format;
bit = bit or require('bit');
log_line = function () end
speak = function () end
tick = function () return 0; end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
local function split_tsv(line)
    local parts = {};
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do parts[#parts + 1] = part; end
    return parts;
end

local IDENTITY = 'questfixture:1';
local WORLD = 1;
local PLAIN = 'quest:sandoria:7';          -- The Trader in the Forest
local GAPPED = 'quest:crystal_war:31';     -- The Swarm

-- --------------------------------------------------------- the shipped guide
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
    each_module('mission_quest_reconcile_quest_*.lua', function (tbl)
        for key, entry in pairs(tbl) do
            if (type(entry) == 'table' and type(entry.steps) == 'table') then
                reconciled[key] = entry;
            end
        end
    end);
    each_module('mission_quest_progression_quest_*.lua', function (tbl)
        local objectives = type(tbl.objectives) == 'table' and tbl.objectives or tbl;
        for key, entry in pairs(objectives) do
            if (type(entry) == 'table' and type(entry.progression_actions) == 'table') then
                progression[key] = entry;
            end
        end
    end);
end
for _, key in ipairs({ PLAIN, GAPPED }) do
    claim(type(reconciled[key]) == 'table' and type(progression[key]) == 'table',
        ('the shipped guide and progression for %s both loaded'):format(key));
end

-- --------------------------------------- exhaust both cursors, the real way
-- The rows the game itself would have written: v2, the shipped revision, the
-- LAST action's identity, and a progress_count equal to its required_count.
-- That is the only shape resolved_progress_record accepts as terminal.
local PROGRESS = SCRATCH .. '/accessxi-exhausted-quest-progress.tsv';
do
    local rows = {};
    for _, key in ipairs({ PLAIN, GAPPED }) do
        local entry = progression[key];
        local last = entry.progression_actions[#entry.progression_actions];
        rows[#rows + 1] = table.concat({
            'v2', IDENTITY, tostring(WORLD), key,
            trim(entry.progression_revision),
            trim(last.step_id), tostring(tonumber(last.step_order) or 0),
            trim(last.action_id), tostring(tonumber(last.action_order) or 0),
            tostring(tonumber(last.required_count) or 1),
        }, '\t');
    end
    local sink = assert(io.open(PROGRESS, 'w'));
    sink:write(table.concat(rows, '\n') .. '\n');
    sink:close();
end
accessxi.objective_interaction_progress_path = PROGRESS;

-- ---------------------------------------------------------------- real data
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

local real_guide = nil;
do
    local ok_index, guide_index = pcall(dofile, ADDON .. '/modules/mission_quest_guide_index.lua');
    accessxi.mission_quest_guide_index = (ok_index and type(guide_index) == 'table')
        and guide_index or {};
    local ok_module, guides = pcall(dofile, ADDON .. '/modules/mission_quest_guides.lua');
    if (ok_module and type(guides) == 'table' and type(guides.new) == 'function') then
        real_guide = guides.new({
            index = ok_index and guide_index or {},
            module_loader = function (name)
                local loaded, data = pcall(dofile, ADDON .. '/modules/' .. name .. '.lua');
                return (loaded and type(data) == 'table') and data or nil;
            end,
            identity_provider = function () return 'quest-fixture'; end,
            logger = function () end,
        });
    end
end
claim(real_guide ~= nil, 'and the real GuideState constructed');

accessxi.objective_guides = {
    source_step_readings = function (_, native_key, step_id)
        if (real_guide == nil) then return {}; end
        local ok, value = pcall(real_guide.source_step_readings, real_guide, native_key, step_id);
        return (ok and type(value) == 'table') and value or {};
    end,
    -- THE REAL GuideState, not the reconcile module's own rows.
    --
    -- Returning entry.steps directly is what let a shipped defect through on
    -- 2026-08-29: GuideState does not hand the navigation module the reconciled
    -- row, it hands a PROJECTION of it, and the projection was dropping
    -- source_orders. The harness passed with two postlude pages while the live
    -- addon logged pages=0. A harness cannot test the seam it supplies.
    source_route_steps = function (_, native_key)
        if (real_guide == nil) then return nil; end
        local ok, value = pcall(real_guide.source_route_steps, real_guide, native_key);
        if (not ok or type(value) ~= 'table' or #value == 0) then return nil; end
        local steps = T{};
        for _, step in ipairs(value) do steps:append(step); end
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

-- ------------------------------------------------ who the player is, and the
-- quest log the game would be reporting. Only the two areas under test are
-- offered, so nothing else can mask or reorder the rows.
local PLAYER = 'Questfixture';
accessxi.current_zone_id = function () return 230; end
accessxi.current_player_identity = function () return IDENTITY; end
accessxi.current_player_world_id = function () return WORLD; end
accessxi.current_objective_session_epoch = function () return 1; end
accessxi.nav_mission_quest_sync_character = function () end
accessxi.current_player_name = function () return PLAYER; end
accessxi.player_name = accessxi.current_player_name;

accessxi.quest_packet_player = PLAYER;
accessxi.quest_packet_identity = IDENTITY;
accessxi.quest_packet_source = 'packet_in_056';
accessxi.quests_menu_data = {
    quest_log_order = T{ 'sandoria', 'crystal_war' },
    quest_log_resources = {
        sandoria = { label = "San d'Oria" },
        crystal_war = { label = 'Crystal War' },
    },
};
local ACCEPTED = { sandoria = { [7] = true }, crystal_war = { [31] = true } };
accessxi.quest_packet_entry = function (area_key, which)
    return {
        source = 'packet_in_056', identity = IDENTITY,
        area = trim(area_key), which = trim(which),
    };
end
accessxi.quest_packet_has_id = function (entry, quest_id)
    if (trim(entry.which) ~= 'current') then return false; end
    local accepted = ACCEPTED[trim(entry.area)] or {};
    return accepted[tonumber(quest_id) or -1] == true;
end
accessxi.quest_rom_rows_for_area = function (area_key)
    area_key = trim(area_key);
    if (area_key == 'sandoria') then
        return { [7] = { label = 'The Trader in the Forest', area = "San d'Oria",
                         source = 'quest-fixture' } };
    end
    if (area_key == 'crystal_war') then
        return { [31] = { label = 'The Swarm', area = 'Crystal War',
                          source = 'quest-fixture' } };
    end
    return nil;
end
accessxi.quest_rom_detail_for_row = function () return ''; end

-- ------------------------------------------------------------ real modules
local function load_code_module(name)
    local chunk, err = loadfile(ADDON .. '/modules/' .. name .. '.lua');
    assert(chunk ~= nil, name .. ': ' .. tostring(err));
    return chunk();
end
load_code_module('nav_zoneline_router');
load_code_module('objective_announcer');
load_code_module('mission_quest_step_resolver');
load_code_module('mission_quest_navigation');

-- ---------------------------------------------------------------- the claims
local items = accessxi.nav_mission_quest_active_items('quest');
claim(type(items) == 'table' and #items > 0,
    ('the Quests category builds through the real module (%d rows)')
        :format(type(items) == 'table' and #items or -1));

local rows_for, spoken_for = {}, {};
for index, item in ipairs(items or {}) do
    local key = trim(item.objective_native_key);
    rows_for[key] = (rows_for[key] or 0) + 1;
    spoken_for[key] = spoken_for[key] or {};
    local speech = accessxi.nav_mission_quest_item_speech(item, index, #items);
    spoken_for[key][#spoken_for[key] + 1] = speech;
end

-- 1. NO COMPLETED STEP IS OFFERED AS THE OBJECTIVE. The whole defect.
for _, key in ipairs({ PLAIN, GAPPED }) do
    local offered = 0;
    for _, action in ipairs(progression[key].progression_actions) do
        local sentence = trim(action.instruction);
        if (sentence ~= '') then
            for _, speech in ipairs(spoken_for[key] or {}) do
                if (speech:find('Objective choice: ' .. sentence, 1, true) ~= nil
                    or speech:find('Current objective: ' .. sentence, 1, true) ~= nil) then
                    offered = offered + 1;
                end
            end
        end
    end
    claim(offered == 0,
        ('%s offers none of its %d completed steps as the objective (got %d)')
            :format(key, #progression[key].progression_actions, offered));
    claim((rows_for[key] or 0) >= 1 and (rows_for[key] or 0) <= 2,
        ('and occupies 1 or 2 rows rather than a dump, got %d'):format(rows_for[key] or 0));
end

-- 2. BOTH PAGES ARE READ, SEPARATELY AND ATTRIBUTED. Never merged into one
--    synthetic reading neither wiki wrote.
for _, key in ipairs({ PLAIN, GAPPED }) do
    local bg, ffx = 0, 0;
    for _, speech in ipairs(spoken_for[key] or {}) do
        if (speech:find('BG Wiki continues:', 1, true) ~= nil) then bg = bg + 1; end
        if (speech:find('FFXIclopedia continues:', 1, true) ~= nil) then ffx = ffx + 1; end
    end
    claim(bg == 1 and ffx == 1,
        ('%s reads each page in its own row (bg=%d ffxiclopedia=%d)'):format(key, bg, ffx));
end
claim((spoken_for[PLAIN] or {})[1] ~= nil
    and spoken_for[PLAIN][1]:find('BG Wiki continues:', 1, true) ~= nil,
    'and the declared primary source is read first');

-- 3. THE TWO STATES SOUND DIFFERENT, BECAUSE THEY ARE DIFFERENT.
--    The Trader in the Forest has nothing but prose left; The Swarm still has
--    material steps the compact progression never covered.
local function any(key, needle)
    for _, speech in ipairs(spoken_for[key] or {}) do
        if (speech:find(needle, 1, true) ~= nil) then return true; end
    end
    return false;
end
claim(any(PLAIN, 'No further automatically tracked step'),
    'a quest whose guide simply stops says tracking has no further step');
claim(not any(PLAIN, 'Automatic tracking ends here'),
    'and does not claim the guide has untracked steps it does not have');
claim(any(GAPPED, 'Automatic tracking ends here, and the guide still has steps it does not track'),
    'while a quest with material steps left says exactly that');
claim(not any(GAPPED, 'No further automatically tracked step'),
    'and never implies its guide has run out');

-- 4. TRUNCATION IS DISCLOSED. The six-line cap bites on 295 pages across the
--    corpus; silently dropping guidance is the failure this project treats as
--    worse than a crash.
claim(any(GAPPED, 'More guide text follows. Press G to read it.'),
    'a capped reading says there is more and names the key that reads it');
claim(not any(PLAIN, 'More guide text follows'),
    'and an uncapped one does not invent a promise');

-- 5. NOTHING CLAIMS COMPLETION. The cursor knows only that IT ran out.
for _, key in ipairs({ PLAIN, GAPPED }) do
    claim(not any(key, 'Objective complete'), ('%s never says the objective completed'):format(key));
    claim(not any(key, 'Quest complete'), ('nor that the quest did (%s)'):format(key));
end

print('');
for _, key in ipairs({ PLAIN, GAPPED }) do
    print(key);
    for _, speech in ipairs(spoken_for[key] or {}) do
        print('  ' .. speech:sub(1, 400));
    end
end

print('');
print(('exhausted cursor quest: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
