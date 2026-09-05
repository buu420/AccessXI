-- DOES N MARK THE OBJECTIVE THE PLAYER IS ACTUALLY ON?
--
-- Live 2026-08-28: the player scrolled the mission list to "The Rites of Life"
-- (Chains of Promathia, row 13 of 23), pressed N, and the addon advanced
-- "Smash the Orcish Scouts" (row 1). Then they pressed it again, and it
-- advanced the same wrong mission a second time.
--
--   16:13:42 nav menu move The Rites of Life. Active mission. Chains of Promathia.
--   16:13:44 objective step marked done by player native="mission:San d'Oria:1" step="...step-005"
--   16:14:00 nav menu move The Rites of Life. Active mission. Chains of Promathia.
--   16:14:01 objective step marked done by player native="mission:San d'Oria:1" step="...step-007:claim-02"
--
-- Their words: "I press n but I don't know if it updated the right mission or
-- not." They could not tell, because the confirmation named no mission at all.
--
-- The hotkey read the selected row, kept only its objective_kind -- the string
-- "mission" -- and passed THAT; mark_step_done then took the head of the active
-- list. The identity was in hand one line before it was needed.
--
-- This drives the REAL modules/mission_quest_navigation.lua against the REAL
-- shipped San d'Oria progression module and the REAL append-only progress
-- store. Nothing about the selection, the persistence or the undo is
-- reimplemented here -- a hand-written stand-in for the loader would prove
-- nothing about the loader.
--
--   luajit tools/test_objective_mark_targets_selection.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

accessxi = { mission_quest_objectives = { missions = {}, quests = {} } };
T = function (t)
    t = t or {};
    t.len = function (s) return #s end;
    t.append = function (s, v) s[#s + 1] = v end;
    t.clear = function (s) for i = #s, 1, -1 do s[i] = nil end end;
    return t;
end;
string.fmt = string.format;

local logged = {};
log_line = function (text) logged[#logged + 1] = tostring(text or ''); end
speak = function () end
tick = function () return 0; end

local claims, failed = 0, 0;
local function claim(ok, text)
    claims = claims + 1;
    if (ok) then print(('  ok   %s'):format(text));
    else failed = failed + 1; print(('  FAIL %s'):format(text)); end
end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end

-- ---------------------------------------------------------------------------
-- The real shipped guide for the two missions involved.
-- ---------------------------------------------------------------------------
local progression = dofile(ADDON .. '/modules/mission_quest_progression_mission_san_doria.lua');
local HEAD = "mission:San d'Oria:1";      -- Smash the Orcish Scouts -- the wrongly advanced one
local BROWSED = "mission:San d'Oria:5";   -- The Davoi Report -- stands in for the browsed row

local head_rows = progression.objectives[HEAD].progression_actions;
local browsed_rows = progression.objectives[BROWSED].progression_actions;
assert(type(head_rows) == 'table' and #head_rows >= 3, 'shipped guide changed shape for ' .. HEAD);
assert(type(browsed_rows) == 'table' and #browsed_rows >= 2, 'shipped guide changed shape for ' .. BROWSED);

accessxi.mission_quest_guide_index = {
    [HEAD] = { kind = 'mission', context = "San d'Oria", native_id = 1, progress_id = 0,
        title = 'Smash the Orcish Scouts', progression_schema_version = 2,
        progression_revision = progression.objectives[HEAD].progression_revision },
    [BROWSED] = { kind = 'mission', context = "San d'Oria", native_id = 5, progress_id = 4,
        title = 'The Davoi Report', progression_schema_version = 2,
        progression_revision = progression.objectives[BROWSED].progression_revision },
};
accessxi.objective_guides = {
    progression_actions = function (_, key)
        local record = progression.objectives[key];
        return type(record) == 'table' and record.progression_actions or {};
    end,
    objective_destinations = function () return {}; end,
    source_route_steps = function () return {}; end,
    automatic_step_id = function () return ''; end,
    current_native_key = function () return ''; end,       -- guide closed
    is_open = function () return false; end,
};
accessxi.objective_title_for_native_key = function (key)
    local record = accessxi.mission_quest_guide_index[trim(key)];
    return type(record) == 'table' and record.title or trim(key);
end

accessxi.nav_points = T{};
accessxi.nav_catalog_revision = 1;
accessxi.nav_graph_zone_name = function (zone) return ('zone%d'):format(tonumber(zone) or 0); end
accessxi.current_zone_id = function () return 230; end
accessxi.current_player_identity = function () return 'testchar:1'; end
accessxi.current_player_world_id = function () return 1; end
accessxi.current_objective_session_epoch = function () return 7; end

local STORE = os.getenv('TEMP') .. '/accessxi-marktest-' .. tostring(os.time()) .. '.tsv';
accessxi.objective_interaction_progress_path = STORE;
do local f = io.open(STORE, 'wb'); if (f ~= nil) then f:close(); end end

local function row(native_key, title)
    return {
        objective_kind = 'mission', kind = 'mission',
        objective_native_key = native_key,
        name = title, mission_context = "San d'Oria",
        objective_available = true, objective_status = 'ok',
    };
end

local ok_load, load_err = pcall(dofile, ADDON .. '/modules/mission_quest_navigation.lua');
claim(ok_load, 'the real navigation module loads' .. (ok_load and '' or (': ' .. tostring(load_err))));

-- The active list, in the order the reducer produces: HEAD first. That order is
-- the whole hazard -- it is what "the first active objective" resolved to.
--
-- Installed AFTER the load on purpose: the module defines this name itself, so
-- a stub set beforehand is silently replaced by the real builder.
accessxi.nav_mission_quest_active_items = function (category)
    if (category ~= 'mission') then return T{}; end
    return T{ row(HEAD, 'Smash the Orcish Scouts'), row(BROWSED, 'The Davoi Report') };
end
claim(type(accessxi.nav_objective_intent) == 'function', 'and exposes the intent resolver');
claim(type(accessxi.nav_objective_undo_last_mark) == 'function', 'and exposes the undo');

-- ---------------------------------------------------------------------------
-- 1. THE LIVE BUG. The player is on the SECOND row; the mark must land there.
-- ---------------------------------------------------------------------------
accessxi.nav_menu_items = T{ row(HEAD, 'Smash the Orcish Scouts'), row(BROWSED, 'The Davoi Report') };
accessxi.nav_menu_index = 2;

local key, source = accessxi.nav_objective_intent('mark-step-done');
claim(key == BROWSED, 'the intent resolver names the BROWSED row, got ' .. tostring(key));
claim(source == 'browser', 'and says where that came from, got ' .. tostring(source));

local ok, spoken = accessxi.nav_mission_quest_mark_step_done('mission', BROWSED);
claim(ok == true, 'the mark succeeds');
claim(tostring(spoken):find('Davoi', 1, true) ~= nil,
    'and the speech NAMES the mission it moved: ' .. tostring(spoken):sub(1, 90));
claim(tostring(spoken):find('Orcish Scouts', 1, true) == nil,
    'and does not name the mission it did not move');

local moved_head = false;
for _, line in ipairs(logged) do
    if (line:find('marked done by player', 1, true) and line:find(HEAD, 1, true)) then
        moved_head = true;
    end
end
claim(not moved_head, 'the head-of-list mission was NOT touched');

-- ---------------------------------------------------------------------------
-- 2. THE OLD CALLING CONVENTION MUST NOT RESURRECT THE BUG.
--    Passing only the category is exactly what the hotkey used to do.
-- ---------------------------------------------------------------------------
accessxi.nav_menu_index = 2;
local ok2, spoken2 = accessxi.nav_mission_quest_mark_step_done('mission');
claim(ok2 == true, 'a kind-only call still works');
claim(tostring(spoken2):find('Davoi', 1, true) ~= nil,
    'and resolves to the browsed row rather than the head: ' .. tostring(spoken2):sub(1, 70));

-- ---------------------------------------------------------------------------
-- 3. REFUSALS. A wrong guess is unrecoverable; a refusal is not.
-- ---------------------------------------------------------------------------
accessxi.nav_menu_items = T{ { kind = 'destination', name = 'Some camp' } };
accessxi.nav_menu_index = 1;
local rkey, _, why = accessxi.nav_objective_intent('mark-step-done');
claim(trim(rkey) == '', 'a highlighted non-objective row refuses rather than falling through');
claim(tostring(why):find('not a mission or quest', 1, true) ~= nil,
    'and says why: ' .. tostring(why):sub(1, 70));

local ok3, spoken3 = accessxi.nav_mission_quest_mark_step_done('mission');
claim(ok3 == false, 'and the mark refuses too');
claim(tostring(spoken3) ~= '', 'with something spoken, never silence');

accessxi.nav_menu_items = T{};
accessxi.nav_menu_index = 0;
local akey, _, awhy = accessxi.nav_objective_intent('mark-step-done');
claim(trim(akey) == '', 'two active objectives and no selection refuses');
claim(tostring(awhy):find('cannot tell', 1, true) ~= nil,
    'and asks the player to choose: ' .. tostring(awhy):sub(1, 70));

-- ---------------------------------------------------------------------------
-- 4. UNDO. The cursor is monotonic -- resolved_progress_record keeps the
--    FARTHEST record it can find -- so a reversal has to remove history, not
--    append an earlier row. Two marks were made above; undo must take back the
--    LAST one, and it must be the one on the objective it actually moved.
-- ---------------------------------------------------------------------------
local uok, utext = accessxi.nav_objective_undo_last_mark();
claim(uok == true, 'the last manual mark can be undone');
claim(tostring(utext):find('Davoi', 1, true) ~= nil,
    'and names what it took back: ' .. tostring(utext):sub(1, 70));

local undo_rows, mark_rows = 0, 0;
do
    local f = io.open(STORE, 'r');
    if (f ~= nil) then
        for line in f:lines() do
            if (line:sub(1, 8) == 'v3-undo\t') then undo_rows = undo_rows + 1; end
            if (line:sub(1, 8) == 'v3-mark\t') then mark_rows = mark_rows + 1; end
        end
        f:close();
    end
end
claim(mark_rows >= 2, 'every manual mark was journalled, got ' .. mark_rows);
claim(undo_rows == 1, 'and the undo was recorded on disk, got ' .. undo_rows);

-- ---------------------------------------------------------------------------
-- 5. THE REPAIR, THROUGH THE REAL LOADER.
--
--    The player's own store, copied so their file is untouched. San d'Oria 1
--    holds three cursor rows -- the genuine step-005 state, then the two the
--    defect wrote -- plus the mark/undo pairs appended to reverse them. If the
--    repair works, the mission's current step is "Go outside the city and kill
--    Orcish Fodder", not "trade them the Orcish Axe".
--
--    Re-running dofile rebuilds the module's private state, so this is a true
--    cold load of that file and not a continuation of the state above.
-- ---------------------------------------------------------------------------
local LIVE = ADDON .. '/data/ffxi-objective-interaction-progress.tsv'
local COPY = os.getenv('TEMP') .. '/accessxi-repaircheck-' .. tostring(os.time()) .. '.tsv';
do
    local src = io.open(LIVE, 'rb');
    if (src ~= nil) then
        local body = src:read('*a'); src:close();
        local dst = io.open(COPY, 'wb'); dst:write(body); dst:close();
    end
end

accessxi.objective_interaction_progress_path = COPY;
accessxi.current_player_identity = function () return 'longrodvonhugen:127'; end
accessxi.current_player_world_id = function () return 127; end
accessxi.nav_menu_items = T{ row(HEAD, 'Smash the Orcish Scouts') };
accessxi.nav_menu_index = 1;

local ok_reload = pcall(dofile, ADDON .. '/modules/mission_quest_navigation.lua');
claim(ok_reload, 'the module cold-loads against the player\'s own store');

accessxi.nav_mission_quest_active_items = function (category)
    if (category ~= 'mission') then return T{}; end
    return T{ row(HEAD, 'Smash the Orcish Scouts') };
end

local rok, rtext = accessxi.nav_mission_quest_mark_step_done('mission', HEAD);
claim(rok == true, 'San d\'Oria 1 has a current step after the repair');
claim(tostring(rtext):find('Orcish Fodder', 1, true) ~= nil,
    'and it is step-005, the state before the wrong presses: ' .. tostring(rtext):sub(1, 100));
claim(tostring(rtext):find('trade them the Orcish Axe', 1, true) == nil,
    'not the step the defect left it on');

-- ---------------------------------------------------------------------------
-- 6. A MISSION THAT WAS NEVER ACCEPTED HAS NO STEP TO MARK.
--
--    This is what hid the damage. The player had never started "Smash the
--    Orcish Scouts"; N advanced its cursor twice and the browse row never
--    changed a word, because an available mission always speaks its acceptance
--    step whatever the saved cursor says. The store moved and nothing said so.
--    Their report: "I never started the mission so I noticed it didn't actually
--    update the steps even when I pressed n."
-- ---------------------------------------------------------------------------
local UNSTARTED = "mission:San d'Oria:2";
accessxi.mission_quest_guide_index[UNSTARTED] = {
    kind = 'mission', context = "San d'Oria", native_id = 2, progress_id = 1,
    title = 'Bat Hunt', progression_schema_version = 2,
    progression_revision = progression.objectives[UNSTARTED].progression_revision,
};

local function available_row(native_key, title)
    local r = row(native_key, title);
    r.mission_availability = 'available-to-start';
    return r;
end

accessxi.nav_mission_quest_active_items = function (category)
    if (category ~= 'mission') then return T{}; end
    return T{ available_row(UNSTARTED, 'Bat Hunt') };
end
accessxi.nav_menu_items = T{ available_row(UNSTARTED, 'Bat Hunt') };
accessxi.nav_menu_index = 1;

local nok, ntext = accessxi.nav_mission_quest_mark_step_done('mission', UNSTARTED);
claim(nok == false, 'a mission that was never accepted refuses the mark');
claim(tostring(ntext):find('have not started', 1, true) ~= nil,
    'and says so plainly: ' .. tostring(ntext):sub(1, 80));
claim(tostring(ntext):find('Bat Hunt', 1, true) ~= nil,
    'naming which mission it means');

-- and the refusal is auditable
local refused = false;
for _, line in ipairs(logged) do
    if (line:find('reason=not-accepted', 1, true)) then refused = true; end
end
claim(refused, 'the refusal is in the log, not just the speech');

-- An ACTIVE mission with the same shape still marks, so the guard is about
-- acceptance and not about missions in general.
accessxi.nav_mission_quest_active_items = function (category)
    if (category ~= 'mission') then return T{}; end
    local r = row(BROWSED, 'The Davoi Report');
    r.mission_availability = 'active';
    return T{ r };
end
accessxi.nav_menu_items = T{ row(BROWSED, 'The Davoi Report') };
accessxi.nav_menu_index = 1;
local aok = accessxi.nav_mission_quest_mark_step_done('mission', BROWSED);
claim(aok == true, 'an accepted mission still marks normally');

print(('objective mark targets selection: %d claims, %d failed'):format(claims, failed));
os.remove(STORE);
os.remove(COPY);
os.exit(failed == 0 and 0 or 1);
