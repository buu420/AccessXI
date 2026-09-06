-- Replay the reported Windurst 1 interaction through the production modules.
local ADDON = assert(os.getenv('ACCESSXI_ADDON'), 'set ACCESSXI_ADDON to the reader under test');
INTEGRATION_EMBED = true;
local h = dofile('tools/test_source_route_integration.lua');
local evidence=io.open(ADDON..'/modules/objective_event_evidence.lua','r');
if evidence then evidence:close(); dofile(ADDON..'/modules/objective_event_evidence.lua'); end;
local search_module=io.open(ADDON..'/modules/mission_quest_search_steps.lua','r');
if search_module then search_module:close(); dofile(ADDON..'/modules/mission_quest_search_steps.lua'); end;
local NATIVE = 'mission:Windurst:1';
local requested_step = (arg and arg[1]) or '016';
local history_mode=requested_step=='history';
local migration_mode=requested_step=='migrated';
if history_mode or migration_mode then requested_step='016'; end;
local owner=history_mode and assert(arg[3], 'pass the report character identity') or 'horutototest:1';
local world=tonumber(owner:match(':(%d+)$')) or 1;
local initial_step = NATIVE .. ':step-' .. requested_step;
local journal = os.tmpname();
accessxi.objective_interaction_progress_path = journal;
accessxi.objective_progress_path = journal;
h.set_player_zone(192);
accessxi.current_player_identity = function() return owner; end;
accessxi.current_player_world_id = function() return world; end;
accessxi.current_objective_session_epoch = function() return 7; end;
local fixture_packet=accessxi.mission_packet_main;
accessxi.nav_mission_quest_sync_character('test-player-changed');
accessxi.objective_guides.automatic_step_id = function() return initial_step; end;
accessxi.mission_packet_main=fixture_packet;
accessxi.mission_packet_player=accessxi.current_player_name();
accessxi.mission_packet_source='packet_in_056';
accessxi.mission_packet_identity=owner;
accessxi.mission_packet_session_epoch=7;
accessxi.mission_packet_main.nation_mission=0;
accessxi.load_mission_rom_rows = function(context)
    if context~='Windurst' then return nil; end;
    local row={mission_id=0,rom_ordinal=1,label='The Horutoto Ruins Experiment',
        source='packet-fixture',orders=''};
    return {row,count=1,by_mission_id={[0]=row}};
end;
local messages, transitions = {}, {};
log_line = function(line) messages[#messages+1] = line; end;
accessxi.objective_announce = function(transition) transitions[#transitions+1]=transition; return true; end;
local function signal(kind, sequence, time)
    return {kind=kind, character_identity=owner, world_id=world,
        session_epoch=7, sequence=sequence, tick=time, target_server_id=17563876,
        target_name='Gate: Magical Gizmo', zone_id=192, event_id=42, menu_id=42,
        corpus_revision=tonumber(accessxi.nav_catalog_revision) or 0};
end;
local started,finished;
if migration_mode then
    local old;
    for _,action in ipairs(h.progression[NATIVE].progression_actions) do
        if action.step_id==NATIVE..':step-017' then old=action; end;
    end;
    assert(old,'released gate action');
    local f=assert(io.open(journal,'wb'));
    f:write(table.concat({'v2',owner,tostring(world),NATIVE,
        h.progression[NATIVE].progression_revision,old.step_id,tostring(old.step_order),
        old.action_id,tostring(old.action_order),'0'},'\t'),'\n'); f:close();
    dofile(ADDON..'/modules/mission_quest_navigation.lua');
    local menu=accessxi.nav_mission_quest_active_items('mission');
    h.claim(menu[1] and menu[1].objective_cursor_action_id==old.action_id,
        'a released saved cursor migrates by stable identity before the new search action');
    local migrated=false;
    for _,line in ipairs(messages) do
        if line:find('objective cursor MIGRATED',1,true) and line:find(':search-v1',1,true) then migrated=true; end;
    end;
    h.claim(migrated,'the revision migration is recorded in support diagnostics');
end;
if history_mode then
    started=accessxi.nav_mission_quest_recover_event_history({assert(arg[2])})==1;
    finished=started;
    h.claim(accessxi.nav_mission_quest_recover_event_history({arg[2]})==0,'history is consumed once');
else
    local wrong=signal('interaction-start',1,1000);
    wrong.target_server_id=17563894;
    h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong),'the other gate cannot advance the mission');
    wrong=signal('interaction-start',1,1000); wrong.event_id=41; wrong.menu_id=41;
    h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong),'another event at the correct gate cannot advance it');
    started=accessxi.nav_mission_quest_reduce_signal(signal('interaction-start',1,1000));
    local automated=signal('interaction-finish',2,160000); automated.automated=true;
    h.claim(not accessxi.nav_mission_quest_reduce_signal(automated),'an intermediate automated menu result cannot finish the cutscene');
    finished=accessxi.nav_mission_quest_reduce_signal(signal('interaction-finish',3,167000));
end;
print('Gate replay initial='..initial_step..' start='..tostring(started)..' finish='..tostring(finished));
local function upvalue(fn,name)
    for i=1,100 do local key,value=debug.getupvalue(fn,i);
        if key==name then return value; end;
        if not key then break; end;
    end;
    error('missing production seam '..name);
end;
local get_actions=upvalue(accessxi.nav_mission_quest_first_objective,'progression_actions');
local actions=get_actions(NATIVE);
local search;
for _,action in ipairs(actions or {}) do
    if action.step_id == NATIVE..':step-018' then search=action; end;
end;
h.claim(started==true and finished==true, 'the observed gate cutscene advances past the preceding approach instruction');
h.claim(search~=nil, 'the six-gizmo search is a material action between the gate and return');
local active=upvalue(accessxi.nav_mission_quest_reduce_signal,'reducer_active_objectives');
local function current_step() return active()[1].action.step_id; end;
h.claim(current_step()==NATIVE..':step-018','gate completion makes search current');
h.claim(transitions[#transitions] and transitions[#transitions].step_id==NATIVE..':step-018',
    'the announcement names the search after catching up over an approach instruction');
local source_rows=upvalue(accessxi.nav_mission_quest_step_route_capability,'source_route_rows');
local menu=accessxi.nav_mission_quest_active_items('mission');
h.claim(#menu==6,'the actual Missions menu exposes six search selections');
local search_speech=accessxi.nav_mission_quest_item_speech(menu[1],1,#menu);
h.claim(not search_speech:find('Port Windurst',1,true),
    'the next city heading is not announced as a gizmo search instruction');
for _,item in ipairs(menu) do
    local point=accessxi.nav_mission_quest_prepare_route(item,{zone=192,x=420,z=-30.375,y=-1.660});
    h.claim(type(point)=='table' and point.objective_guide_step_id==NATIVE..':step-018'
        and point.destination_id==item.objective_destination_id,
        'the menu prepares the selected search destination '..tostring(item.objective_destination_id));
end;
local found={};
for _,row in ipairs(source_rows(NATIVE)) do
    if row.guide_step_id==NATIVE..':step-018' then
        found[tonumber(row.destination_id:match(':(%d+)$'))]=true;
    end;
end;
local count=0; for _ in pairs(found) do count=count+1; end;
h.claim(count==6,'all six search destinations reach the production source rows');
for id=17563868,17563873 do h.claim(found[id],'search identity '..id); end;
local capability,zone,choice=accessxi.nav_mission_quest_step_route_capability(NATIVE,NATIVE..':step-018');
local suffix=accessxi.objective_announcer.route_suffix(capability,zone,choice);
h.claim(suffix:find('Search 6 locations',1,true)~=nil,'speech describes places to search');
h.claim(suffix:find('Cracked Mana Orb',1,true)~=nil,'search speech names the required key item');
for index=1,6 do
    local start=signal('interaction-start',index*2+10,200000+index*10000);
    start.target_server_id=17563867+index; start.target_name='Ancient Magical Gizmo';
    start.event_id=47+index*2; start.menu_id=start.event_id;
    h.claim(accessxi.nav_mission_quest_reduce_signal(start),'gizmo interaction '..index..' recognized');
    local finish={}; for key,value in pairs(start) do finish[key]=value; end;
    finish.kind='interaction-finish'; finish.sequence=start.sequence+1; finish.tick=start.tick+5000;
    accessxi.nav_mission_quest_reduce_signal(finish);
    h.claim(current_step()==NATIVE..':step-018','empty gizmo '..index..' does not finish the search');
end;
local acquired=signal('key-item-delta',100,400000);
acquired.key_item_id=10; acquired.key_item_name='Unrelated Orb';
acquired.before_owned=false; acquired.after_owned=true;
acquired.snapshot_complete=true;
h.claim(not accessxi.nav_mission_quest_reduce_signal(acquired),'an unrelated key item does not finish the search');
acquired.sequence=101; acquired.key_item_name='Cracked Mana Orb';
h.claim(accessxi.nav_mission_quest_reduce_signal(acquired),'obtaining the Cracked Mana Orb finishes the search');
h.claim(current_step()==NATIVE..':step-021','the return follows the key item');
local returned={};
for _,row in ipairs(source_rows(NATIVE)) do
    if row.guide_step_id==NATIVE..':step-021' then returned[#returned+1]=row; end;
end;
h.claim(#returned==1 and returned[1].destination_id=='npc:v1:240:17760273',
    'return goes to the real Orastery contact from the report');
h.claim(not accessxi.nav_mission_quest_note_talk_intent(17760266,240,409000),
    'the other actor with the same name cannot finish the return');
h.claim(accessxi.nav_mission_quest_note_talk_intent(17760273,240,410000),
    'the resolved return contact is recognized by the same exact identity');
h.set_player_zone(115);
local approaches=0;
for _,row in ipairs(source_rows(NATIVE)) do
    if row.guide_step_id==NATIVE..':step-018' then
        approaches=approaches+1;
        h.claim(row.canonical_edge_id==1631073146 and row.canonical_from_zone==116,
            'search target '..row.destination_id..' retains the connected Lily entrance');
    end;
end;
h.claim(approaches==6,'all six remain selectable when returning from outside the ruins');
local f=assert(io.open(ADDON..'/accessxi_reader.lua','r')); local reader=f:read('*a'); f:close();
local a=assert(reader:find('function accessxi.nav_point_effective_kind(point)',1,true));
local b=assert(reader:find('\nfunction accessxi.nav_point_matches_category',a,true));
local env=setmetatable({accessxi={},nav_normalized_kind=function(value) return value; end},{__index=_G});
local classify=assert(loadstring(reader:sub(a,b-1))); setfenv(classify,env); classify();
local classified=0;
for _,point in ipairs(accessxi.nav_points) do
    if found[tonumber(tostring(point.destination_id):match(':(%d+)$'))] then
        classified=classified+1;
        h.claim(env.accessxi.nav_point_effective_kind(point)=='object',
            'catalogued gizmo '..point.destination_id..' appears under Objects');
    end;
end;
h.claim(classified==6,'all six gizmos have an object category');
os.remove(journal);
h.result();
