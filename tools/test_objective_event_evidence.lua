local addon=assert(os.getenv('ACCESSXI_ADDON'));
local M=dofile(addon..'/modules/objective_event_evidence.lua');
local key='mission:Windurst:1';
local signal={zone_id=192,target_server_id=17563876,event_id=42};
assert(M.match(key,key..':step-017:claim-01',signal), 'reviewed gate event');
signal.target_server_id=17563894;
assert(not M.match(key,key..':step-017:claim-01',signal), 'other gate');
signal.target_server_id=17563876; signal.event_id=41;
assert(not M.match(key,key..':step-017:claim-01',signal), 'other event');
local context='support context reason=automatic {identity="tester:101",mission={identity="tester:101",packet={nation=2,nation_mission=0},session=7,source="packet_in_056"},session=7}';
local lines={
 '2026-09-06 04:32:26 '..context,
 '2026-09-06 04:32:26 objective packet trace id=0x001A dir=out len=512 target=17563876 a=0 b=0 c=0 d=0',
 '2026-09-06 04:32:27 objective packet trace id=0x0032 dir=in len=512 target=17563876 a=192 b=42 c=0 d=0',
 '2026-09-06 04:34:57 npc text mode=150 "Ajido-Marujido : I think one of those Mana Orbs was broken when my experiment failed just now. Your job is to find the broken sphere and take it back to the Orastery."',
 '2026-09-06 04:35:13 objective packet trace id=0x005B dir=out len=512 target=17563876 a=0 b=228 c=0 d=0',
};
local function recover(copy,identity)
 return M.recover(table.concat(copy,'\n')..'\n',identity or 'tester:101');
end;
assert(#recover(lines)==1, 'legacy report with exact target, event, dialogue, end');
assert(#recover(lines,'other:101')==0, 'other character');
assert(#recover(lines,'tester:102')==0, 'other world');
for missing=1,#lines do
 local copy={}; for i,line in ipairs(lines) do if i~=missing then copy[#copy+1]=line; end; end;
 assert(#recover(copy)==0, 'missing evidence '..missing);
end;
local copy={}; for i,line in ipairs(lines) do copy[i]=line; end;
copy[4]=copy[4]:gsub('npc text mode=150','chat text mode=0');
assert(#recover(copy)==0,'player chat is not stage evidence');
copy[4]=lines[4]; copy[5]=copy[5]:gsub('17563876','17563894');
assert(#recover(copy)==0,'another object finish');
copy[5]=lines[5]:gsub('04:35:13','05:35:13');
assert(#recover(copy)==0,'stale finish');
copy[5]=lines[5]; copy[6]='2026-09-06 04:36:00 '..context:gsub('nation_mission=0','nation_mission=65535');
assert(#recover(copy)==0,'mission left or abandoned after proof');
copy={}; for i,line in ipairs(lines) do copy[i]=line; end;
copy[1]=copy[1]:gsub('mission={identity="tester:101"','mission={identity="other:101"');
assert(#recover(copy)==0,'a cached mission for another character cannot validate the current owner');
local journal=os.tmpname();
local f=assert(io.open(journal,'wb')); f:write(table.concat(lines,'\n')..'\n'); f:close();
local recovered,scan=M.read_history({journal..'.absent',journal},'tester:101');
assert(#recovered==1 and scan.files==1 and scan.bytes>0 and scan.unreadable==1 and scan.truncated==0,
    'history diagnostics distinguish missing files from a successful proof');
os.remove(journal);
if arg[1] then
 local f=assert(io.open(arg[1],'rb')); local report=f:read('*a'); f:close();
 local actual=M.recover(report,assert(arg[2],'pass the report character identity'));
 assert(#actual==1 and actual[1].step_id==key..':step-017','actual private report');
 print('Actual report: one completed gate cutscene recovered for its owner');
end;
print('Objective event evidence: exact event and bounded history recovery passed');
