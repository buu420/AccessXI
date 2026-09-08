-- A retained key item alone cannot date a conversation. Recovery requires the
-- player's native mission, their triggered event, its final end, and the reward.
local M = dofile(assert(os.getenv('ACCESSXI_ADDON')) .. '/modules/objective_event_evidence.lua');
assert(type(M.recover_rewards) == 'function', 'NPC reward history recovery is available');
local owner = 'rewardtest:1';
local context = 'support context reason=automatic {identity="rewardtest:1",mission={identity="rewardtest:1",packet={nation=2,nation_mission=1},session=7,source="packet_in_056"},session=7}';
local lines = {
    '2026-09-07 18:01:47 ' .. context,
    '2026-09-07 18:01:48 objective packet trace id=0x001A dir=out len=512 target=17253039 a=0 b=0 c=0 d=0',
    '2026-09-07 18:01:49 objective event result kind=interaction-start target=17253039 zone=116 event=46 automated=false accepted=false',
    '2026-09-07 18:03:01 objective event result kind=interaction-finish target=17253039 zone=116 event=46 automated=false accepted=false',
    '2026-09-07 18:03:02 objective key item obtained name="Southeastern star charm"',
};
local function recover(values, identity, nation, mission)
    return M.recover_rewards(table.concat(values,'\n'), identity or owner, nation or 2, mission or 1);
end;
local proved = recover(lines);
assert(#proved == 1 and proved[1].target_server_id == 17253039
    and proved[1].event_id == 46 and proved[1].zone_id == 116
    and proved[1].key_item_name == 'Southeastern star charm',
    'the observed NPC event plus its reward survives an earlier reducer rejection');
assert(#recover(lines, 'another:1') == 0, 'another character cannot supply the proof');
assert(#recover(lines, owner, 0) == 0, 'a different nation cannot supply the proof');
assert(#recover(lines, owner, 2, 2) == 0, 'a different mission cannot supply the proof');
for missing=1,#lines do
    local copy={}; for i,line in ipairs(lines) do if i~=missing then copy[#copy+1]=line; end; end;
    assert(#recover(copy) == 0, 'all required breadcrumbs are present: ' .. missing);
end;
local function changed(index, pattern, replacement)
    local copy={}; for i,line in ipairs(lines) do copy[i]=line; end;
    copy[index]=copy[index]:gsub(pattern,replacement);
    return recover(copy);
end;
assert(#changed(3, 'event=46', 'event=47') == 0, 'a different event cannot finish the arm');
assert(#changed(4, 'target=17253039', 'target=17253040') == 0, 'another NPC cannot finish the arm');
assert(#changed(4, 'automated=false', 'automated=true') == 0, 'an intermediate menu result is not a final end');
assert(#changed(5, '18:03:02', '18:10:02') == 0, 'a late unrelated reward is not joined to the NPC');
assert(#changed(5, 'objective key item obtained', 'chat text') == 0, 'chat is not acquisition evidence');
local copy={}; for i,line in ipairs(lines) do copy[i]=line; end;
copy[#copy+1]='2026-09-07 18:03:04 ' .. context:gsub('nation_mission=1','nation_mission=2');
assert(#recover(copy) == 0, 'leaving the mission invalidates its previous proof');
copy={}; for i,line in ipairs(lines) do copy[i]=line; end;
table.insert(copy,4,'2026-09-07 18:02:00 support session version=test');
assert(#recover(copy) == 0, 'a reload cannot join an old event start to a new reward');
copy={}; for _,line in ipairs(lines) do copy[#copy+1]=line; end;
for i=2,#lines do copy[#copy+1]=lines[i]:gsub('18:0','18:1'):gsub('17253039','17253040'); end;
local repeated = recover(copy);
assert(#repeated == 2 and repeated[1].target_server_id == 17253039
    and repeated[2].target_server_id == 17253040
    and repeated[2].observed_at > repeated[1].observed_at,
    'repeated item names keep each actual issuer and acquisition order');
if arg and arg[1] then
    local actual, scan = M.read_reward_history({arg[1]}, assert(arg[2], 'report owner'), 2, 1);
    local pore = 0;
    for _, proof in ipairs(actual) do
        if proof.target_server_id == 17253039 and proof.event_id == 46
            and proof.key_item_name == 'Southeastern star charm' then pore = pore + 1; end;
    end;
    assert(pore == 1,
        'the private support report contains the same completed conversation and reward');
    print('Private report: one Pore-Ohre reward proof, bytes=' .. scan.bytes);
end;
print('NPC reward history: native owner, mission, trigger, event end and reward guards passed');
