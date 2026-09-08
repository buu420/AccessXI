-- Production replay of a mission conversation whose reward arrived while the
-- durable cursor was still on an earlier travel instruction. No private log
-- content or player identity is needed: shipped guides and native events suffice.
local ADDON = assert(os.getenv('ACCESSXI_ADDON'), 'set ACCESSXI_ADDON');
INTEGRATION_EMBED = true;
local h = dofile('tools/test_source_route_integration.lua');
local reward_module = io.open(ADDON .. '/modules/objective_npc_rewards.lua', 'r');
if reward_module then reward_module:close(); dofile(ADDON .. '/modules/objective_npc_rewards.lua'); end;
local mode = (arg and arg[1]) or 'live';
local bastok = mode == 'bastok';
local history = mode == 'history';
local NATIVE = bastok and 'mission:Bastok:6' or 'mission:Windurst:2';
local context, nation, mission = bastok and 'Bastok' or 'Windurst', bastok and 1 or 2, bastok and 5 or 1;
local initial = NATIVE .. (bastok and ':step-014' or ':step-018');
local following = NATIVE .. (bastok and ':step-017' or ':step-025');
local npc, target, zone = bastok and 'Kupipi' or 'Pore-Ohre', bastok and 17768466 or 17253039, bastok and 242 or 116;
local reward_name, reward_id = bastok and 'Dark key' or 'Southeastern star charm', bastok and 34 or 112;
local owner, world, epoch = 'rewardtest:1', 1, 7;
local journal = os.tmpname();
accessxi.objective_interaction_progress_path = journal;
accessxi.objective_progress_path = journal;
accessxi.current_player_identity = function() return owner; end;
accessxi.current_player_world_id = function() return world; end;
accessxi.current_objective_session_epoch = function() return epoch; end;
local packet = accessxi.mission_packet_main;
accessxi.nav_mission_quest_sync_character('reward-test');
accessxi.objective_guides.automatic_step_id = function() return initial; end;
accessxi.mission_packet_main = packet;
accessxi.mission_packet_main.nation = nation;
accessxi.mission_packet_main.nation_mission = mission;
accessxi.mission_packet_player = accessxi.current_player_name();
accessxi.mission_packet_source = 'packet_in_056';
accessxi.mission_packet_identity = owner;
accessxi.mission_packet_session_epoch = epoch;
accessxi.load_mission_rom_rows = function(requested)
    if requested ~= context then return nil; end;
    local row = {mission_id=mission, rom_ordinal=mission+1, label=bastok and 'The Emissary' or 'The Heart of the Matter',
        source='packet-fixture', orders=''};
    return {row, count=1, by_mission_id={[mission]=row}};
end;
local owned = {};
local resources = dofile(ADDON .. '/resources/windower/key_items.lua');
accessxi.load_key_items_resource = function() return resources; end;
accessxi.objective_key_item_current_session_has_id = function(id) return owned[id] == true; end;
local reader_file = assert(io.open(ADDON .. '/accessxi_reader.lua','rb'));
local reader = reader_file:read('*a'); reader_file:close();
for _, name in ipairs({'objective_key_item_name_key', 'objective_key_item_name_index', 'objective_key_item_owned_by_name'}) do
    local start = assert(reader:find('function accessxi.' .. name .. '(',1,true));
    local finish = assert(reader:find('\nend',start,true));
    assert(loadstring(reader:sub(start,finish+4)))();
end;
local _, ambiguous = accessxi.objective_key_item_owned_by_name('letter to the consuls');
h.claim(ambiguous == nil, 'identically named native key items remain ambiguous');
local saved;
for _, action in ipairs(h.progression[NATIVE].progression_actions) do
    if action.step_id == initial then saved = action; break; end;
end;
assert(saved, 'released travel action');
local f = assert(io.open(journal, 'wb'));
f:write(table.concat({'v2', owner, tostring(world), NATIVE,
    h.progression[NATIVE].progression_revision, saved.step_id, tostring(saved.step_order),
    saved.action_id, tostring(saved.action_order), '0'}, '\t'), '\n');
f:close();
dofile(ADDON .. '/modules/mission_quest_navigation.lua');
h.set_player_zone(zone);
local messages, transitions = {}, {};
log_line = function(line) messages[#messages+1] = line; end;
accessxi.objective_announce = function(transition) transitions[#transitions+1] = transition; return true; end;
local function upvalue(fn, name)
    for i=1,100 do
        local key, value = debug.getupvalue(fn, i);
        if key == name then return value; end;
        if not key then break; end;
    end;
    error('missing production seam ' .. name);
end;
local active = upvalue(accessxi.nav_mission_quest_reduce_signal, 'reducer_active_objectives');
local function current_step() local rows=active(); return rows[1] and rows[1].action.step_id; end;
local function signal(kind, sequence, tick)
    return {kind=kind, sequence=sequence, tick=tick,
        character_identity=owner, world_id=world, session_epoch=epoch,
        target_server_id=target, target_name=npc, zone_id=zone,
        event_id=46, menu_id=46, corpus_revision=tonumber(accessxi.nav_catalog_revision) or 0};
end;
local menu = accessxi.nav_mission_quest_active_items('mission');
print('Replay cursor=' .. tostring(current_step()) .. ' menu=' .. tostring(menu[1] and menu[1].objective_action_id));
h.claim(current_step() == initial, 'replay starts at the saved cursor');
local capability = accessxi.nav_mission_quest_step_route_capability(NATIVE, bastok and initial or NATIVE .. ':step-020');
h.claim(capability ~= accessxi.objective_announcer.ROUTE.UNAVAILABLE,
    'the shipped Pore-Ohre instruction can be routed independently of the stale cursor');
accessxi.nav_mission_quest_reduce_signal(signal('interaction-start', 1, 1000));
accessxi.nav_mission_quest_reduce_signal(signal('interaction-finish', 2, 73000));
h.claim(current_step() == initial, 'an unreviewed conversation alone does not prove its promised reward');
local acquired = signal('key-item-delta', 3, 74000);
acquired.key_item_id, acquired.key_item_name = reward_id, reward_name;
acquired.before_owned, acquired.after_owned, acquired.snapshot_complete = false, true, true;
local wrong = {}; for key,value in pairs(acquired) do wrong[key]=value; end;
wrong.character_identity = 'someoneelse:1';
h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong), 'another character cannot complete the conversation');
wrong.character_identity = owner; wrong.session_epoch = epoch - 1;
h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong), 'an old session cannot complete the conversation');
wrong.session_epoch = epoch; wrong.snapshot_complete = false;
h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong), 'an incomplete key item packet cannot complete it');
wrong.snapshot_complete = true; wrong.key_item_name = 'Unrelated key item';
h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong), 'a different key item cannot complete it');
wrong.key_item_name = reward_name; wrong.key_item_id = reward_id + 1;
h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong), 'a matching display name with a different native ID cannot complete it');
if not bastok and not history then
    local fields = {action=saved.action, target=saved.target, target_kind=saved.target_kind,
        relationship=saved.relationship};
    for _, barrier in ipairs({'fight', 'trade', 'talk', 'wait', 'select', 'use', 'transport'}) do
        saved.action = barrier == 'transport' and 'travel' or barrier;
        saved.relationship = barrier == 'transport' and 'use-transport' or fields.relationship;
        saved.target_kind = barrier == 'transport' and 'transport' or fields.target_kind;
        h.claim(not accessxi.nav_mission_quest_reduce_signal(acquired),
            'the reward cannot skip an earlier ' .. barrier .. ' action');
    end;
    for key,value in pairs(fields) do saved[key]=value; end;
    local actions = h.progression[NATIVE].progression_actions;
    local extra = {}; for key,value in pairs(actions[#actions]) do extra[key]=value; end;
    extra.step_id, extra.action_id = NATIVE .. ':step-999', NATIVE .. ':step-999:claim-01';
    extra.step_order, extra.order, extra.action_order = 999, 999, 1;
    extra.action, extra.relationship, extra.target = 'obtain', 'obtain-item', reward_name;
    extra.key_items = {reward_name};
    actions[#actions+1] = extra;
    h.claim(not accessxi.nav_mission_quest_reduce_signal(acquired),
        'the same reward on a separate later action remains ambiguous');
    actions[#actions] = nil;
    accessxi.objective_interaction_progress_path = journal .. '/missing-directory/progress.tsv';
    h.claim(not accessxi.nav_mission_quest_reduce_signal(acquired), 'a failed progress write does not spend the reward');
    h.claim(current_step() == initial, 'a failed write leaves the original step available to retry');
    accessxi.objective_interaction_progress_path = journal;
end;
if history then
    dofile(ADDON .. '/modules/objective_event_evidence.lua');
    local path = os.tmpname();
    local log = assert(io.open(path,'wb'));
    log:write('2026-09-07 18:01:47 support context reason=automatic {identity="rewardtest:1",mission={identity="rewardtest:1",packet={nation=2,nation_mission=1},session=7,source="packet_in_056"},session=7}\n',
        '2026-09-07 18:01:48 objective packet trace id=0x001A dir=out len=512 target=17253039 a=0 b=0 c=0 d=0\n',
        '2026-09-07 18:01:49 objective event result kind=interaction-start target=17253039 zone=116 event=46 automated=false accepted=false\n',
        '2026-09-07 18:03:01 objective event result kind=interaction-finish target=17253039 zone=116 event=46 automated=false accepted=false\n',
        '2026-09-07 18:03:02 objective key item obtained name="Southeastern star charm"\n');
    log:close();
    local recover = accessxi.nav_mission_quest_recover_npc_reward_history;
    h.claim(type(recover)=='function' and recover({path})==0, 'history cannot replace an unread native key item snapshot');
    accessxi.key_items_packet_player = accessxi.current_player_name();
    accessxi.key_items_packet_identity = owner;
    accessxi.key_items_packet_tables = {[0]={source='packet_in_055', identity=owner, session_epoch=epoch, flags=string.rep('\0',64)}};
    h.claim(recover({path})==0, 'a past reward no longer held does not supply current proof');
    owned[112] = true;
    accessxi.key_items_packet_tables[0].session_epoch = epoch - 1;
    h.claim(recover({path})==0, 'a stale ownership snapshot cannot repair the cursor');
    accessxi.key_items_packet_tables[0].session_epoch = epoch;
    h.claim(recover({path})==1, 'a recorded completed NPC conversation plus its still-held reward repairs the cursor');
    h.claim(recover({path})==0, 'history recovery is consumed once');
    os.remove(path);
else
    h.claim(accessxi.nav_mission_quest_reduce_signal(acquired),
        'the actual key item reward advances through travel and duplicate NPC instructions');
end;
h.claim(current_step() == following, 'the next material mission instruction is current');
h.claim(not accessxi.nav_mission_quest_reduce_signal(acquired), 'duplicate acquisition is consumed once');
menu = accessxi.nav_mission_quest_active_items('mission');
local pore = false;
for _, item in ipairs(menu) do
    if tostring(item.objective_action_id):find(':step-020:',1,true)
        or tostring(item.objective_action_id):find(':step-021:',1,true) then pore=true; end;
end;
h.claim(not pore, 'the Missions menu stops offering the completed conversation');
dofile(ADDON .. '/modules/mission_quest_navigation.lua');
active = upvalue(accessxi.nav_mission_quest_reduce_signal, 'reducer_active_objectives');
h.claim(current_step() == following, 'the corrected cursor survives a reader reload');
os.remove(journal);
h.result();
