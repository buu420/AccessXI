-- Does the addon notice that the player TALKED TO THE NPC?
--
-- This drives the REAL modules/mission_quest_navigation.lua against the REAL
-- shipped progression module and the REAL destination catalogue. No hand-built
-- stand-in for either -- only the addon plumbing the module reads through.
--
-- It exists because the source-pattern gates were green while the feature was
-- structurally incapable of ever firing. Live 2026-08-22 the player talked to
-- Zantaviat, the outgoing trigger and his reply are both in the log one second
-- apart, and nothing completed -- for two independent reasons:
--   1. the arm passed a server id with no zone, and the catalogue matcher
--      identifies a target by zone PLUS id, so it mismatched on its first
--      test, always;
--   2. the Zantaviat action ships with `catalogue = {}` -- as do 5,965 of the
--      7,230 interaction actions in the shipped progression modules -- so
--      there was nothing to match against even once the zone was supplied.
--
--   luajit tools/test_objective_talk_detection.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi_paths = { addon_path = function(...) return ADDON .. '/' .. table.concat({...}, '/'); end };

accessxi = { mission_quest_objectives = { missions = {}, quests = {} } };
T = function (t)
    t = t or {};
    t.len = function (s) return #s end;
    t.append = function (s, v) s[#s + 1] = v end;
    t.clear = function (s) for i = #s, 1, -1 do s[i] = nil end end;
    return t;
end;
string.fmt = string.format;

-- addon plumbing the module speaks through
local logged = {};
log_line = function (text) logged[#logged + 1] = tostring(text or ''); end
speak = function () end
tick = function () return 0; end

local claims, failed = 0, 0;
local function claim(ok, text)
    claims = claims + 1;
    if (ok) then
        print(('  ok   %s'):format(text));
    else
        failed = failed + 1;
        print(('  FAIL %s'):format(text));
    end
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end

-- real destination catalogue ------------------------------------------------
local points = T{};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-destinations.tsv', 'r'));
    for line in f:lines() do
        if (line ~= '' and line:sub(1, 1) ~= '#') then
            local p = {};
            for part in (line .. '\t'):gmatch('([^\t]*)\t') do p[#p + 1] = part; end
            local zone = tonumber(p[1]) or 0;
            if (zone > 0 and trim(p[2]) ~= '') then
                local spawn = T{};
                for value in tostring(p[12] or ''):gmatch('[^,]+') do
                    local id = tonumber(trim(value));
                    if (id ~= nil) then spawn:append(id); end
                end
                points:append(T{
                    zone = zone, zone_name = '', name = trim(p[2]),
                    x = tonumber(p[3]) or 0, z = tonumber(p[4]) or 0, y = tonumber(p[5]) or 0,
                    kind = trim(p[6] or ''), source = trim(p[7] or ''),
                    confidence = trim(p[8] or ''), section = trim(p[9] or ''),
                    destination_id = trim(p[10] or ''), raw_identity = trim(p[11] or ''),
                    raw_spawn_ids = spawn, cluster_policy_version = trim(p[13] or ''),
                });
            end
        end
    end
    f:close();
end
accessxi.nav_points = points;
accessxi.nav_catalog_revision = 1;
accessxi.nav_graph_zone_name = function (zone) return ('zone%d'):format(tonumber(zone) or 0); end
accessxi.current_zone_id = function () return 149; end
-- Progress is persisted per character per world, so the cursor cannot move at
-- all without an identity. Supply one and let the real save path run.
accessxi.current_player_identity = function () return 'testchar:1'; end
accessxi.current_player_world_id = function () return 1; end
accessxi.current_objective_session_epoch = function () return 7; end

-- The real announcer, and a capture in place of speech, so the last claim below
-- checks the whole chain: talk -> arm -> reply -> step advances -> the player is
-- TOLD. Announcing was wired separately from detecting, and either half working
-- alone still leaves the mission moving in silence.
dofile(ADDON .. '/modules/objective_announcer.lua');
local announced = {};
accessxi.objective_announce = function (transition)
    announced[#announced + 1] = transition;
    return true;
end

-- real shipped guide --------------------------------------------------------
local NATIVE = "mission:San d'Oria:5";
local progression = dofile(ADDON .. '/modules/mission_quest_progression_mission_san_doria.lua');
local record = progression.objectives[NATIVE];
assert(type(record) == 'table', 'shipped progression module is missing ' .. NATIVE);
local rows = record.progression_actions;
assert(type(rows) == 'table' and #rows > 0, 'no progression actions for ' .. NATIVE);

accessxi.mission_quest_guide_index = {
    [NATIVE] = {
        kind = 'mission', context = "San d'Oria", native_id = 5, progress_id = 4,
        title = 'The Davoi Report', status = 'source-conflict',
        progression_schema_version = 2,
        progression_revision = record.progression_revision,
    },
};
-- The cursor is placed the way the addon places it: the native mission stage
-- maps to a step id. Live 2026-08-22 it sat on step-011, Talk to Zantaviat.
local ZANTAVIAT_STEP = "mission:San d'Oria:5:step-011";
accessxi.objective_guides = {
    progression_actions = function (_, key) return key == NATIVE and rows or {}; end,
    objective_destinations = function () return {}; end,
    source_route_steps = function () return {}; end,
    automatic_step_id = function (_, key, stage)
        if (key == NATIVE and trim(stage) == 'davoi-report-scout') then return ZANTAVIAT_STEP; end
        return '';
    end,
};

-- the Zantaviat step, exactly as shipped ------------------------------------
local zantaviat = nil;
for _, row in ipairs(rows) do
    if (trim(row.target) == 'Zantaviat') then zantaviat = row; break; end
end
claim(zantaviat ~= nil, 'the shipped guide has a "Talk to Zantaviat" action');
claim(zantaviat ~= nil and #(zantaviat.catalogue or {}) == 0,
    'and it ships with an EMPTY catalogue snapshot -- the condition that broke this');

local ok_load, load_err = pcall(dofile, ADDON .. '/modules/mission_quest_navigation.lua');
claim(ok_load, 'the real navigation module loads' .. (ok_load and '' or (': ' .. tostring(load_err))));
claim(type(accessxi.nav_mission_quest_note_talk_intent) == 'function',
    'and exposes the talk arm');

-- the cursor sits on the Zantaviat step -------------------------------------
accessxi.nav_mission_quest_active_items = function (category)
    if (category ~= 'mission') then return T{}; end
    return T{ T{
        objective_native_key = NATIVE, category = 'mission',
        objective_stage = 'davoi-report-scout',
    } };
end

claim(#accessxi.nav_mission_quest_active_items('mission') == 1,
    'the active mission is The Davoi Report');

local ZANTAVIAT_ID = 17388006;
local DAVOI = 149;

claim(zantaviat ~= nil and trim(zantaviat.step_id) == ZANTAVIAT_STEP,
    'and the cursor step is the one the player was standing on live');

-- 1. the live evidence, replayed exactly -------------------------------------
accessxi.nav_objective_talk_intent = nil;
local armed = accessxi.nav_mission_quest_note_talk_intent(ZANTAVIAT_ID, DAVOI, 1000);
local intent = accessxi.nav_objective_talk_intent;
claim(armed == true, 'pressing enter on Zantaviat in Davoi arms the step');
claim(type(intent) == 'table' and trim(intent.name):lower() == 'zantaviat',
    'and the arm identifies him by name from the catalogue');
claim(type(intent) == 'table' and tonumber(intent.target_server_id) == ZANTAVIAT_ID,
    'and by the exact server id the game sent');

-- 2. the bug that shipped: an id with no zone --------------------------------
accessxi.nav_objective_talk_intent = nil;
local no_zone = accessxi.nav_mission_quest_note_talk_intent(ZANTAVIAT_ID, 0, 1000);
claim(no_zone == false, 'an identity signal with no zone is refused, not silently unmatched');

-- 3. a different creature in the same zone must not arm ----------------------
accessxi.nav_objective_talk_intent = nil;
local wrong = accessxi.nav_mission_quest_note_talk_intent(17389726, DAVOI, 1000);
claim(wrong == false, 'pressing enter on some other creature in Davoi does not arm the step');

-- 4. the right creature in the wrong zone must not arm -----------------------
accessxi.nav_objective_talk_intent = nil;
local wrong_zone = accessxi.nav_mission_quest_note_talk_intent(ZANTAVIAT_ID, 230, 1000);
claim(wrong_zone == false, 'the same server id in another zone does not arm the step');

-- 5. completion needs HIS reply, shortly, and only his ----------------------
accessxi.nav_objective_talk_intent = nil;
accessxi.nav_mission_quest_note_talk_intent(ZANTAVIAT_ID, DAVOI, 1000);
local other = accessxi.nav_mission_quest_note_talk_response('Ranperre', 1500);
claim(other == false, 'another NPC speaking does not complete the step');
claim(type(accessxi.nav_objective_talk_intent) == 'table',
    'and the arm survives to wait for the right one');

accessxi.nav_objective_talk_intent = nil;
accessxi.nav_mission_quest_note_talk_intent(ZANTAVIAT_ID, DAVOI, 1000);
local stale = accessxi.nav_mission_quest_note_talk_response('Zantaviat', 1000 + 10001);
claim(stale == false, 'his reply a long time later does not complete the step');
claim(accessxi.nav_objective_talk_intent == nil, 'and the stale arm is discarded');

-- LAST, because completing the step MOVES THE CURSOR off Zantaviat --------
-- the whole point: his reply completes it
accessxi.nav_objective_talk_intent = nil;
accessxi.nav_mission_quest_note_talk_intent(ZANTAVIAT_ID, DAVOI, 1000);
local completed = accessxi.nav_mission_quest_note_talk_response('Zantaviat', 1500);
claim(completed == true, 'Zantaviat answering a second later completes the step');
claim(accessxi.nav_objective_talk_intent == nil, 'and the arm is consumed, not left to fire again');
claim(accessxi.nav_mission_quest_note_talk_response('Zantaviat', 1600) == false,
    'and him repeating himself does not advance a second step');
local said_done = false;
for _, line in ipairs(logged) do
    if (line:find('objective interaction completed', 1, true)
        and line:find('talk%-response')) then said_done = true; end
end
claim(said_done, 'and the completion is recorded with its evidence');

print('');
print('And the player is told, without pressing anything:');
local transition = announced[#announced];
claim(type(transition) == 'table', 'completing the step produced an announcement');
claim(type(transition) == 'table'
    and transition.type == accessxi.objective_announcer.TRANSITIONS.OBJECTIVE,
    'typed as an ordinary objective completion, not a mission completion');
claim(type(transition) == 'table'
    and trim(transition.instruction) == 'Click on it to receive the key item Lost document',
    'carrying the guide sentence for the step that is now current');
claim(type(transition) == 'table' and trim(transition.identity) ~= ''
    and (tonumber(transition.mission_epoch) or 0) > 0,
    'and enough identity to be said exactly once for this mission instance');
if (type(transition) == 'table') then
    local spoken = accessxi.objective_announcer.sentence(transition);
    print('         would say: ' .. tostring(spoken));
    claim(spoken:find('Objective complete.', 1, true) == 1,
        'the sentence opens with the completion, as the user asked');
    claim(spoken:find('Press I', 1, true) ~= nil or spoken:find('No route is available', 1, true) ~= nil,
        'and ends by offering the choice, never taking it');
end

print('');
-- NPC DIALOGUE ARRIVES ON MORE THAN ONE CHANNEL. Live 2026-08-23 Zantaviat
-- answered on mode 144 while the completion path only ever read 150/151, so an
-- attributable reply was discarded before it reached the arm. sol's ruling: 144
-- is accepted only INSIDE the existing zone/server-id/speaker correlation --
-- the mode is not proof by itself, and an unarmed reminder line must never
-- complete anything.
claim(accessxi.nav_mission_quest_dialogue_mode(144) == true,
    'mode 144 is an NPC dialogue channel');
claim(accessxi.nav_mission_quest_dialogue_mode(150) == true,
    'and so is mode 150, the event channel that already worked');
for _, mode in ipairs({ 0, 1, 4, 5, 6, 26, 148, 151, 200 }) do
    claim(accessxi.nav_mission_quest_dialogue_mode(mode) == false,
        ('mode %d is not an NPC dialogue channel'):format(mode));
end

print(('claims=%d failed=%d'):format(claims, failed));
os.exit(failed == 0 and 0 or 1);
