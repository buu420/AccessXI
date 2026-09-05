-- AN EXHAUSTED CURSOR MUST NOT REPLAY THE STEPS ALREADY DONE.
--
-- Live 2026-08-29, Chains of Promathia, "Below the Arks". The player pressed N
-- twice in eight seconds and ran the guide's compact actions off the end:
--
--   15:49:10  mark step done ... "Marked done: Examine the Shattered Telepoint
--             to trigger a cutscene and. Next: enter the Hall of Transference."
--   15:49:18  mark step done ... "Marked done: enter the Hall of Transference.
--             That was the last step recorded for this objective."
--   15:49:20  objective announce type="final-objective"
--             "Objective complete. No further guide objectives."
--
-- From 15:49:21 onward the Missions browse read them THIS, as rows 13-15 of 27:
--
--   Below the Arks ... Objective choice: Head to Ru'Lude Gardens and speak with
--   Pherimociel at (G-6) in the palace for a cutscene which begins this mission.
--   Below the Arks ... Objective choice: Head to any one of the three crags ...
--
-- Both are steps they had finished -- the Pherimociel one on 2026-08-28 at
-- 16:49. Their words: "I don't even know what I'm supposed to do cause it's
-- showing like all the previous steps."
--
-- WHY. progression_cursor returns action=nil once the last action's count
-- reaches its required_count. append_current_progression_rows answers
-- (handled=true, action=nil), so expand_active_mission_destinations leaves
-- selected_step nil, finds no replacements, and calls
-- append_source_route_replacements(item, replacements, nil) -- whose loop is
--
--     if (selected_step_id == '' or clean(destination.guide_step_id) == selected_step_id)
--
-- and with no selected step that condition is TRUE FOR EVERY ROW. The empty
-- filter did not mean "nothing selected, say so"; it meant "append the whole
-- mission". Exhausted and never-had-a-cursor took the same branch.
--
-- This drives the REAL modules against the REAL shipped guide, the REAL
-- progression module and the player's OWN progress rows, copied verbatim out of
-- data/ffxi-objective-interaction-progress.tsv. Nothing about the cursor, the
-- row builder or the persistence is reimplemented.
--
--   luajit tools/test_exhausted_cursor_row.lua
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
local logged = {};
log_line = function (text) logged[#logged + 1] = tostring(text or ''); end
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

-- ---------------------------------------------------------------------------
-- THE PLAYER'S OWN PROGRESS ROWS. Copied, not invented: these four v2 rows and
-- the v3-mark are lifted verbatim from the shipped progress file, which is why
-- the cursor lands exactly where it landed live. The copy is read-only; the
-- module only ever appends, and it appends to the temp path, never the real one.
-- ---------------------------------------------------------------------------
local IDENTITY = 'longrodvonhugen:127';
local WORLD = 127;
local KEY = 'mission:Chains of Promathia:3';
local PROGRESS = SCRATCH .. '/accessxi-exhausted-cursor-progress.tsv';
-- All of their rows EXCEPT the last, which is the one their second N wrote.
-- That puts the cursor on "enter the Hall of Transference" -- where they were
-- standing at 15:49:10 -- so this file presses N for itself and watches the
-- state they landed in happen, rather than assuming it.
local FINAL_ROW = 'mission:Chains of Promathia:3:step-009:claim-03';
do
    local source = assert(io.open(ADDON .. '/data/ffxi-objective-interaction-progress.tsv', 'r'));
    local kept, held, out = 0, 0, {};
    for line in source:lines() do
        local f = split_tsv(line);
        if (trim(f[4]) == KEY and trim(f[2]):lower() == IDENTITY) then
            kept = kept + 1;
            -- the v2 row that COMPLETES the last action, count 1 of 1
            if (trim(f[1]) == 'v2' and trim(f[8]) == FINAL_ROW and trim(f[10]) == '1') then
                held = held + 1;
            else
                out[#out + 1] = line;
            end
        end
    end
    source:close();
    local sink = assert(io.open(PROGRESS, 'w'));
    sink:write(table.concat(out, '\n') .. '\n');
    sink:close();
    claim(kept >= 4, ('the player\'s own CoP:3 progress rows are in hand, got %d'):format(kept));
    claim(held == 1, ('and the row their last N wrote is held back, got %d'):format(held));
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
claim(type(reconciled[KEY]) == 'table' and #reconciled[KEY].steps == 15,
    ('the shipped reconciled guide for Below the Arks has its 15 merged steps, got %d')
        :format(type(reconciled[KEY]) == 'table' and #reconciled[KEY].steps or -1));
claim(type(progression[KEY]) == 'table' and #progression[KEY].progression_actions == 5,
    ('and its compact progression stops after 5 actions, got %d')
        :format(type(progression[KEY]) == 'table' and #progression[KEY].progression_actions or -1));

-- The REAL guide index, not one rebuilt from the progression modules. It is
-- what accessxi_reader.lua publishes, and it is the only place that declares
-- which of the two wiki pages is authoritative for an objective
-- (source_authority = { primary = 'bg', fallback = 'ffxiclopedia' }) -- which
-- decides the order the postlude rows are read in.
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
            identity_provider = function () return 'exhausted-cursor'; end,
            logger = function () end,
        });
    end
end
claim(real_guide ~= nil, 'and the real GuideState constructed, so the readings are the shipped ones');

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

-- -------------------------------------------------- who the player is, really
local announced = {};
accessxi.objective_announce = function (transition)
    announced[#announced + 1] = transition;
end

local PLAYER = 'Longrodvonhugen';
accessxi.current_zone_id = function () return 16; end          -- Promyvion - Holla
accessxi.current_player_identity = function () return IDENTITY; end
accessxi.current_player_world_id = function () return WORLD; end
accessxi.current_objective_session_epoch = function () return 1788033930; end
accessxi.nav_mission_quest_sync_character = function () end
accessxi.current_player_name = function () return PLAYER; end
accessxi.player_name = function () return PLAYER; end

accessxi.mission_packet_player = PLAYER;
accessxi.mission_packet_identity = IDENTITY;
accessxi.mission_packet_source = 'packet_in_056';
accessxi.mission_packet_main = {
    port = 0xFFFF, nation = 0, nation_mission = 65535,
    rov = 65535, tales = 0, zilart = 65535,
    cop = 2, toau = 65535, wotg = 65535, soa = 65535, addons = 0,
};

-- Only Chains of Promathia is offered, so nothing else can mask the rows.
accessxi.missions_menu_category_labels = T{ 'Chains of Promathia' };
accessxi.missions_menu_nation_context_id = function () return nil; end
accessxi.mission_rom_table_for_context = function (context)
    return trim(context) == 'Chains of Promathia' and { packet = 'cop' } or nil;
end
accessxi.current_mission_value_for_context = function (context)
    return trim(context) == 'Chains of Promathia' and 2 or nil;
end
accessxi.load_mission_rom_rows = function (context)
    if (trim(context) ~= 'Chains of Promathia') then return nil; end
    local row = {
        mission_id = 2, rom_ordinal = 3, label = 'Below the Arks',
        source = 'exhausted-cursor-fixture',
        orders = 'Something is afoot. Travel to the Grand Duke Palace to learn details of recent events.',
    };
    return { count = 1, by_mission_id = { [2] = row }, [1] = row };
end

-- ------------------------------------------------------------ real modules
local function load_code_module(name)
    local chunk, err = loadfile(ADDON .. '/modules/' .. name .. '.lua');
    assert(chunk ~= nil, name .. ': ' .. tostring(err));
    return chunk();
end
load_code_module('nav_zoneline_router');
load_code_module('objective_announcer');
load_code_module('mission_quest_step_resolver');
-- The hand-written step notes are loaded by the reader in the game, so the
-- harness has to supply them or the claim below would pass on an empty table.
accessxi.mission_quest_step_notes = dofile(ADDON .. '/modules/mission_quest_step_notes.lua');

load_code_module('mission_quest_navigation');

-- ---------------------------------------------------------------- the claims
-- 0. WHAT THE PLAYER DID. One press of N on the row they were browsing, which
--    completes the guide's last compact action for this mission.
local before = accessxi.nav_mission_quest_active_items('mission');
local offered_hall = false;
for index, item in ipairs(before or {}) do
    if (accessxi.nav_mission_quest_item_speech(item, index, #before)
        :find('enter the Hall of Transference', 1, true) ~= nil) then
        offered_hall = true;
    end
end
claim(offered_hall, 'before the mark, the browse offers "enter the Hall of Transference"');

local marked, mark_speech = accessxi.nav_mission_quest_mark_step_done('mission', KEY);
claim(marked == true, ('N marks the last recorded step, got %s'):format(tostring(marked)));
mark_speech = tostring(mark_speech or '');
claim(mark_speech:find('That was the last step recorded for this objective', 1, true) ~= nil,
    'and says it was the last one recorded');
-- THE HALF THAT WAS MISSING. Saying "that was the last step recorded" and
-- stopping is true and useless: the guide goes on, and its next sentence is the
-- answer to the question the player asked eight minutes later.
claim(mark_speech:find('complete each of the three Promyvions', 1, true) ~= nil,
    ('and reads the guide on from there: "%s"'):format(mark_speech:sub(1, 240)));

-- 0b. AND THE ANNOUNCEMENT, through the real announcer.
local final_transition = nil;
for _, transition in ipairs(announced) do
    if (trim(transition.type) == 'final-objective') then final_transition = transition; end
end
claim(final_transition ~= nil, 'the last-step announcement fired');
if (final_transition ~= nil) then
    local announcer = dofile(ADDON .. '/modules/objective_announcer.lua');
    local sentence = announcer.sentence(final_transition);
    claim(sentence:find('Objective complete', 1, true) == nil,
        ('it no longer claims the objective completed: "%s"'):format(sentence:sub(1, 200)));
    claim(sentence:find('No further guide objectives', 1, true) == nil,
        'nor that the guide is finished, when only the cursor is');
    claim(sentence:find('complete each of the three Promyvions', 1, true) ~= nil,
        'and it reads what the guide actually says next');
    claim(sentence:find('Waiting for the mission to update', 1, true) ~= nil,
        'while still waiting on the server for the mission itself');
end

local items = accessxi.nav_mission_quest_active_items('mission');
claim(type(items) == 'table' and #items > 0,
    ('the Missions category builds through the real module (%d rows)')
        :format(type(items) == 'table' and #items or -1));

-- Every row the browse would read aloud, exactly as the menu reads it.
local spoken = {};
for index, item in ipairs(items or {}) do
    spoken[index] = accessxi.nav_mission_quest_item_speech(item, index, #items);
end

-- 1. THE CURSOR REALLY IS EXHAUSTED. Not a supposition about the fixture: the
--    module itself must agree, or every claim below is about a different state.
local instruction, step_id = accessxi.nav_mission_quest_first_objective(KEY);
claim(trim(step_id) ~= '', 'the objective still has compact actions to read');

-- 2. THE DEFECT. No row may offer a step whose action the player has already
--    marked done. Both sentences below are lifted from the live 15:49 log.
local DONE = {
    ['Pherimociel'] = "Head to Ru'Lude Gardens and speak with Pherimociel",
    ['the crags'] = 'Head to any one of the three crags',
    ['the telepoint'] = 'Examine the Shattered Telepoint to trigger a cutscene and',
    ['the Hall'] = 'enter the Hall of Transference',
};
for label, sentence in pairs(DONE) do
    local offered = 0;
    for _, text in ipairs(spoken) do
        if (text:find('Objective choice: ' .. sentence, 1, true) ~= nil
            or text:find('Current objective: ' .. sentence, 1, true) ~= nil) then
            offered = offered + 1;
        end
    end
    claim(offered == 0,
        ('%s is finished, so no row offers it as the objective (got %d)'):format(label, offered));
end

-- 3. AND SILENCE IS NOT THE ANSWER EITHER. An objective with nothing left to
--    route must still say something -- in this project a player told nothing is
--    worse off than a player told the wrong thing, because they cannot even
--    tell that anything is wrong.
claim(#items > 0, 'the objective still occupies a row rather than vanishing');
local says_finished = false;
for _, text in ipairs(spoken) do
    if (text:lower():find('no further', 1, true) ~= nil
        or text:lower():find('recorded step', 1, true) ~= nil
        or text:lower():find('every recorded', 1, true) ~= nil) then
        says_finished = true;
    end
end
claim(says_finished,
    'and a row says the guide has no further recorded step for it');

-- 4. THE ANSWER THE PLAYER NEEDED. BG Wiki's page does say what to do next --
--    "You must now complete each of the three Promyvions" -- and it is in the
--    shipped corpus as merged step-004. It must reach them.
local says_promyvions = false;
for _, text in ipairs(spoken) do
    if (text:find('complete each of the three Promyvions', 1, true) ~= nil) then
        says_promyvions = true;
    end
end
claim(says_promyvions,
    "and the guide's own answer -- complete each of the three Promyvions -- is read out");

local says_walkthrough = false;
for _, text in ipairs(spoken) do
    if (text:find('The Mothercrystals', 1, true) ~= nil) then says_walkthrough = true; end
end
claim(says_walkthrough,
    'along with where the walkthrough for them is, the next mission');

-- WHERE THE WORK STILL IS. The player: "The promathia mission should show you
-- the shattered telepoint destinations or at least mention you need to zone to
-- the 3 destinations where the shattered telepoints are." The last tracked step
-- names all three crags; once the cursor exhausted, nothing said them, because
-- every postlude row is instruction-only and has no destination of its own.
local places_row = nil;
for _, text in ipairs(spoken) do
    if (text:find('Places for this step:', 1, true) ~= nil) then places_row = text; end
end
claim(places_row ~= nil, 'the postlude names the places its last tracked step points at');
for _, zone in ipairs({ 'Tahrongi Canyon', 'Konschtat Highlands', 'La Theine Plateau' }) do
    claim(places_row ~= nil and places_row:find(zone, 1, true) ~= nil,
        ('including %s'):format(zone));
end
-- It says WHERE, never how many are done. The mod cannot observe which crags
-- have been used, and a count it cannot see is a count it must not claim.
for _, forbidden in ipairs({ 'of 3', '1 of three', 'cleared', 'remaining' }) do
    local claimed = false;
    for _, text in ipairs(spoken) do
        if (text:find('Places for this step', 1, true) ~= nil
            and text:find(forbidden, 1, true) ~= nil) then claimed = true; end
    end
    claim(not claimed, ('and never claims progress it cannot see ("%s")'):format(forbidden));
end

-- AND THE NOTE WRITTEN FOR THIS EXACT STEP. modules/mission_quest_step_notes.lua
-- exists to carry instructions the guide omits; the postlude threw it away.
local says_apparatus = false;
for _, text in ipairs(spoken) do
    if (text:find('Large Apparatus on your LEFT', 1, true) ~= nil) then says_apparatus = true; end
end
claim(says_apparatus,
    'and the hand-written note for the step is spoken -- which apparatus to examine');
-- ...once. The supplement would also re-read the lines under the step, which in
-- a postlude are the same lines the page continuation just read.
local apparatus_rows = 0;
for _, text in ipairs(spoken) do
    local from = 1;
    while (true) do
        local at = text:find('Large Apparatus on your LEFT', from, true);
        if (at == nil) then break; end
        apparatus_rows = apparatus_rows + 1;
        from = at + 1;
    end
end
claim(apparatus_rows <= 2,
    ('and not repeated within a row, got %d occurrences across %d rows'):format(
        apparatus_rows, #spoken));

-- 5. NOT A NEW DUMP. Replacing three stale rows with fifteen fresh ones is not
--    a fix. The objective gets a small, bounded number of rows.
local cop_rows = 0;
for _, item in ipairs(items or {}) do
    if (trim(item.objective_native_key) == KEY) then cop_rows = cop_rows + 1; end
end
claim(cop_rows >= 1 and cop_rows <= 3,
    ('and Below the Arks occupies between 1 and 3 rows, got %d'):format(cop_rows));

-- 6. THE QUEST PATH TOO. expand_active_mission_destinations and
--    expand_active_quest_destinations share the defect and the repair, and only
--    the mission one is driven above -- a quest fixture needs the quest packet,
--    the quest log order and a per-area packet entry, none of which this file
--    supplies. This is a structural guard, not a behavioural one: it catches
--    the repair being made on one side only, which is exactly how this project
--    shipped 'one gate applied to half the decision' before.
do
    local module = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
    local calls = 0;
    for _ in module:gmatch('accessxi%.objective_append_guide_postlude_rows%(') do
        calls = calls + 1;
    end
    claim(calls == 3,
        ('the postlude builder is defined once and called from BOTH expanders, got %d mentions')
            :format(calls));
    -- FOUR STATES, named at the cursor. The row builder must not have to infer
    -- "the cursor finished" from "the action came back nil", because an index
    -- that no longer points into the action list comes back nil too, and
    -- reading somebody the END of the guide when they have merely lost their
    -- place walks them past the step they are on.
    for _, state in ipairs({ 'unavailable', 'exhausted', 'invalid', 'active' }) do
        claim(module:find((", '%s';"):format(state), 1, true) ~= nil,
            ('the cursor names the %s state for itself'):format(state));
    end
    claim(module:find("objective cursor INVALID native=", 1, true) ~= nil,
        'and a cursor that lost its place is logged with what it was holding');
    claim(module:find("progression_state == 'exhausted' or progression_state == 'invalid'", 1, true) ~= nil,
        'while neither of them may reach the whole-mission fallback');
    -- AND THE FALLBACK IS GATED ON THE STATE, NOT ON THE ROW COUNT. Relying on
    -- the postlude always returning a row would put the dump one empty builder
    -- away from coming back.
    local gates = 0;
    for _ in module:gmatch('#replacements == 0 and not cursor_exhausted') do gates = gates + 1; end
    claim(gates == 2,
        ('both fallback call sites are gated on the exhausted state, got %d'):format(gates));
    local unguarded = 0;
    for _ in module:gmatch('if %(#replacements == 0%) then') do
        unguarded = unguarded + 1;
    end
    claim(unguarded == 0,
        ('and no call site reaches it ungated, got %d'):format(unguarded));
end

print('');
for index, text in ipairs(spoken) do
    print(('  row %d: %s'):format(index, text));
end

print('');
print(('exhausted cursor row: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
