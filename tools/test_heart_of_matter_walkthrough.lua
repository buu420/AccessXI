-- All material steps after the reported Pore-Ohre conversation, through the
-- real menu and reducer. Public game IDs; no player's log or identity required.
local ADDON = assert(os.getenv('ACCESSXI_ADDON'));
INTEGRATION_EMBED = true;
local h = dofile('tools/test_source_route_integration.lua');
local NATIVE, owner, epoch = 'mission:Windurst:2', 'towertest:1', 7;
local initial_npc=arg and arg[1]=='initial-npc';
local journal = os.tmpname();
accessxi.objective_interaction_progress_path = journal;
accessxi.objective_progress_path = journal;
accessxi.current_player_identity = function() return owner; end;
accessxi.current_player_world_id = function() return 1; end;
accessxi.current_objective_session_epoch = function() return epoch; end;
local packet = accessxi.mission_packet_main;
accessxi.nav_mission_quest_sync_character('tower-test');
accessxi.mission_packet_main = packet;
packet.nation, packet.nation_mission = 2, 1;
accessxi.mission_packet_player = accessxi.current_player_name();
accessxi.mission_packet_source = 'packet_in_056';
accessxi.mission_packet_identity, accessxi.mission_packet_session_epoch = owner, epoch;
accessxi.load_mission_rom_rows = function(context)
    if context ~= 'Windurst' then return nil; end;
    local row = {mission_id=1, rom_ordinal=2, label='The Heart of the Matter', source='native-fixture', orders=''};
    return {row, count=1, by_mission_id={[1]=row}};
end;
local initial;
for _, action in ipairs(h.progression[NATIVE].progression_actions) do
    if action.action_id == NATIVE .. (initial_npc and ':step-009:claim-02' or ':step-025:claim-01') then initial=action; end;
end;
local f = assert(io.open(journal,'wb'));
f:write(table.concat({'v2',owner,'1',NATIVE,h.progression[NATIVE].progression_revision,
    initial.step_id,tostring(initial.step_order),initial.action_id,tostring(initial.action_order),'0'},'\t'),'\n');
f:close();
local transitions, messages = {}, {};
accessxi.objective_announce = function(t) transitions[#transitions+1]=t; return true; end;
log_line = function(line) messages[#messages+1]=line; end;
accessxi.escape_probe_log_text = function(s) return s; end;
local function upvalue(fn,name)
    for i=1,100 do local k,v=debug.getupvalue(fn,i); if k==name then return v; end; if not k then break; end; end;
    error('missing production seam '..name);
end;
local active;
local function reload()
    dofile(ADDON..'/modules/mission_quest_navigation.lua');
    active=upvalue(accessxi.nav_mission_quest_reduce_signal,'reducer_active_objectives');
end;
local function current() local rows=active(); return rows[1] and rows[1].action; end;
local function is_action(suffix) return current() and current().action_id==NATIVE..suffix; end;
local player={zone=116,x=260.488,z=-456.192,y=-17.25};
local sequence=100;
local function signal(kind,id,event)
    sequence=sequence+1;
    return {kind=kind,character_identity=owner,world_id=1,session_epoch=epoch,
        sequence=sequence,tick=sequence*1000,zone_id=player.zone,
        target_server_id=id,target_name=id==17572249 and 'Gate: Magical Gizmo'
            or id==17764372 and 'Apururu' or 'Ancient Magical Gizmo',event_id=event,menu_id=event,
        corpus_revision=tonumber(accessxi.nav_catalog_revision) or 0};
end;
local function event(id,number)
    local start=accessxi.nav_mission_quest_reduce_signal(signal('interaction-start',id,number));
    local finish=accessxi.nav_mission_quest_reduce_signal(signal('interaction-finish',id,number));
    return start and finish;
end;
local function menu_ids()
    local rows=accessxi.nav_mission_quest_active_items('mission'); local ids={};
    for _,row in ipairs(rows) do
        local point,message=accessxi.nav_mission_quest_prepare_route(row,player);
        h.claim(type(point)=='table','I prepares '..tostring(row.objective_action_id)..': '..tostring(message));
        if point then ids[point.destination_id]=true; end;
    end;
    return rows,ids;
end;
local function expect_one(id,label)
    local rows,ids=menu_ids(); h.claim(#rows==1 and ids[id],label);
end;
reload(); h.set_player_zone(player.zone);
if arg and arg[1]=='missing-location' then
    local augment=accessxi.objective_action_reviews.augment_actions;
    accessxi.objective_action_reviews.augment_actions=function(native,actions,lookup)
        return augment(native,actions,function(id)
            if id=='area:v1:116:1664627578' then return nil; end;
            return lookup(id);
        end);
    end;
    reload();
    local rows=accessxi.nav_mission_quest_active_items('mission');
    h.claim(#rows==1 and rows[1].objective_instruction_only,'missing data leaves the reviewed objective as instructions');
    local point,message=accessxi.nav_mission_quest_prepare_route(rows[1],player);
    h.claim(not point and message:find('missing from this installation',1,true),'I explains the missing installed location');
    h.claim(current().instruction:find('Marguerite Tower',1,true),'the useful tower context survives missing data');
    h.claim(current().review_revision=='heart-of-matter-v1','missing data cannot silently revert to the old guide');
    os.remove(journal);h.result();
end;
if arg and arg[1]=='unreachable' then
    h.set_player_zone(9999);
    local route=accessxi.nav_mission_quest_step_route_capability(NATIVE,initial.step_id,initial.action_id);
    h.claim(route==accessxi.objective_announcer.ROUTE.UNAVAILABLE,'an unconnected current zone cannot promise a route');
    h.set_player_zone(116);
    local route,zone=accessxi.nav_mission_quest_step_route_capability(NATIVE,initial.step_id,initial.action_id);
    h.claim(route==accessxi.objective_announcer.ROUTE.FULL and zone=='East Sarutabaruta','a reachable entrance names its actual zone');
    os.remove(journal);h.result();
end;
if initial_npc then
    player.zone=241;h.set_player_zone(241);
    expect_one('npc:v1:241:17764372','the initial conversation uses the Manustery Apururu');
    accessxi.nav_mission_quest_note_talk_intent(17764372,241,100000);
    h.claim(not accessxi.nav_mission_quest_note_talk_response('Apururu',101000),
        'ordinary dialogue cannot replace the mission cutscene');
    h.claim(not event(17764372,866),'the Trust cutscene cannot complete the initial conversation');
    h.claim(is_action(':step-009:claim-02'),'unrelated dialogue leaves Apururu current');
    h.claim(event(17764372,137),'the Mana Orb mission cutscene completes the initial conversation');
    expect_one('npc:v1:116:17253039','the next stop is Pore-Ohre before entering the tower');
    os.remove(journal);h.result();
end;
expect_one('area:v1:116:1664627578','the saved released cursor routes through Marguerite Tower');
h.claim(is_action(':step-025:claim-01'),'merely offering the entrance does not complete entry');
local entry=accessxi.nav_mission_quest_active_items('mission')[1];
accessxi.nav_destination=accessxi.nav_mission_quest_prepare_route(entry,player);
local arrived=signal('route-arrival',0,0);
arrived.objective_native_key=NATIVE;arrived.action_id=initial.action_id;
arrived.destination_id='area:v1:116:1664627578';
h.claim(not accessxi.nav_mission_quest_reduce_signal(arrived),'reaching the outside mouth does not claim that the player entered');
accessxi.nav_destination=nil;
local wrong=signal('committed-zone',0,0); wrong.zone_id=192;
h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong),'entering Lily Tower cannot complete Marguerite entry');
player={zone=194,x=580.018,z=-637.011,y=-25.626}; h.set_player_zone(194);
h.claim(accessxi.nav_mission_quest_reduce_signal(signal('committed-zone',0,0)),'entering Outer Horutoto completes the entry action');
h.claim(is_action(':step-025:claim-02'),'entry makes the six orb placements current');
if arg and arg[1]=='manual-mark' then
    h.claim(event(17572250,58),'one native placement is saved before the manual recovery');
    h.claim(accessxi.nav_mission_quest_mark_step_done('mission',NATIVE),'N marks the entire displayed objective done');
    h.claim(is_action(':step-028:claim-01'),'N advances to the gate without an anonymous partial count');
    reload();
    h.claim(is_action(':step-028:claim-01'),'the manual completion survives reload');
    local undone,reason=accessxi.nav_objective_undo_last_mark();
    h.claim(undone,'the manual completion can be undone: '..tostring(reason));
    reload();
    h.claim(is_action(':step-025:claim-02'),'undo restores the placement objective after reload');
    local rows,ids=menu_ids();
    h.claim(#rows==5 and not ids['npc:v1:194:17572250'],'undo preserves the earlier native placement');
    h.claim(not event(17572250,58),'undo does not spend the native placement twice');
    os.remove(journal);h.result();
end;
-- Continue even on the released failure so the test reports all missing links.
local order={55,50,54,51,53,52};
for phase=1,2 do
    local suffix=phase==1 and ':step-025:claim-02' or ':step-030:claim-01';
    local event_base=phase==1 and 58 or 46;
    local rows,ids=menu_ids();
    h.claim(#rows==6,'phase '..phase..' starts with all six gizmos');
    for id=17572250,17572255 do h.claim(ids['npc:v1:194:'..id],'phase '..phase..' includes native gizmo '..id); end;
    h.claim(not event(17572249,44),'the energizing gate cannot replace unfinished gizmos');
    local wrong=signal('interaction-start',17572250,event_base);
    wrong.character_identity='other:1';
    h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong),'another character cannot count a gizmo');
    wrong.character_identity=owner; wrong.session_epoch=epoch-1;
    h.claim(not accessxi.nav_mission_quest_reduce_signal(wrong),'an old session cannot count a gizmo');
    h.claim(not event(17572250,phase==1 and 46 or 58),'the other orb phase cannot count a gizmo');
    for n,ending in ipairs(order) do
        local id=17572200+ending;
        local event_id=event_base+ending-50;
        if n==2 then
            accessxi.objective_interaction_progress_path=journal..'/missing/progress.tsv';
            h.claim(not event(id,event_id),'a failed journal write cannot spend a member completion');
            accessxi.objective_interaction_progress_path=journal;
        end;
        h.claim(event(id,event_id),'phase '..phase..' completes member '..ending..' in player-chosen order');
        if n<6 then
            h.claim(is_action(suffix),'one gizmo does not complete the whole set');
            local latest=transitions[#transitions];
            h.claim(latest and latest.type=='objective-progress' and latest.completed_count==n,
                'partial progress announces the real count without claiming the phase complete');
            local spoken=accessxi.objective_announcer.sentence(latest);
            h.claim(spoken:find(n..' of 6 complete',1,true) and not spoken:find('Objective complete.',1,true),
                'the actual spoken sentence reports partial progress');
            if n==2 then
                local prior={}; for k,v in pairs(latest) do prior[k]=v; end; prior.completed_count=1;
                h.claim(accessxi.objective_announcer.dedup_key(latest)~=accessxi.objective_announcer.dedup_key(prior),
                    'the next completed member is not suppressed as duplicate speech');
            end;
            h.claim(not event(id,event_id),'repeating a completed gizmo is not another completion');
            if n==3 then reload(); end;
            local remaining,remaining_ids=menu_ids();
            h.claim(#remaining==6-n,'only unfinished gizmos remain, including after reload');
            h.claim(not remaining_ids['npc:v1:194:'..id],'the just-completed gizmo is removed');
        end;
    end;
    if phase==1 then
        h.claim(is_action(':step-028:claim-01'),'all placements lead to the energizing gate');
        expect_one('object:v1:194:17572249','energizing uses the correct Marguerite gate');
        h.claim(event(17572249,44),'the gate cutscene advances to orb retrieval');
    end;
end;
h.claim(is_action(':step-045:claim-01'),'all six retrieved orbs lead back to Apururu');
expect_one('npc:v1:241:17764372','return goes to the Manustery Apururu');
player.zone=241;h.set_player_zone(241);
h.claim(not event(17764372,866),'an unrelated Trust conversation cannot finish the return');
h.claim(event(17764372,143),'the mission return conversation finishes the last objective');
local logged=false;
for _,line in ipairs(messages) do if line:find('objective member completed',1,true) then logged=true; end; end;
h.claim(logged,'support diagnostics include per-gizmo completion evidence');
os.remove(journal);
h.result();
