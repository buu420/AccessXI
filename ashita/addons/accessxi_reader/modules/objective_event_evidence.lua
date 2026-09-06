-- Reviewed event identities can prove a stage even when an earlier approach
-- instruction was not observable. They never reveal a random search outcome.
local M = {};
local events = {
    {
        native_key='mission:Windurst:1', step_id='mission:Windurst:1:step-017',
        action_id='mission:Windurst:1:step-017:claim-01',
        zone_id=192, target_server_id=17563876, event_id=42,
        nation=2, nation_mission=0,
        speaker='Ajido-Marujido',
        dialogue='Your job is to find the broken sphere and take it back to the Orastery.',
        source='LandSandBoat/scripts/missions/windurst/1_1_The_Horutoto_Ruins_Experiment.lua; retail support capture 2026-09-06',
    },
};

function M.match(native_key, action_id, signal)
    for _, event in ipairs(events) do
        if event.native_key == native_key and event.action_id == action_id
            and event.zone_id == tonumber(signal.zone_id)
            and event.target_server_id == tonumber(signal.target_server_id)
            and event.event_id == tonumber(signal.event_id) then
            return event;
        end;
    end;
end;

function M.get(native_key, action_id)
    for _,event in ipairs(events) do
        if event.native_key==native_key and (not action_id or event.action_id==action_id) then
            return event;
        end;
    end;
end;

local function timestamp(line)
    local y,m,d,h,mi,s=line:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d) ');
    if not y then return nil; end;
    return os.time({year=tonumber(y),month=tonumber(m),day=tonumber(d),
        hour=tonumber(h),min=tonumber(mi),sec=tonumber(s)});
end;

-- Read only our structured breadcrumbs. Never evaluate the serialized context.
-- Legacy logs lack the finish event/mode fields, so recovery additionally needs
-- the exact NPC instruction between an exact trigger/start and matching end.
function M.recover(text, identity)
    identity=tostring(identity or ''):lower();
    if identity == '' then return {}; end;
    local active, pending, proved = {}, {}, {};
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        if line:find(' support session ',1,true) then
            active, pending = {}, {};
        end;
        local owner=line:match(' support context reason=%S+ %{identity="([^"]*)"');
        if owner then
            local mission=line:match(',mission=(%b{})');
            local packet=mission and mission:match('packet=(%b{})');
            local live=mission and mission:find('source="packet_in_056"',1,true);
            for i,event in ipairs(events) do
                local mission_owner=mission and mission:match('identity="([^"]*)"');
                local valid=owner:lower()==identity and mission_owner
                    and mission_owner:lower()==identity and live and packet;
                local same=valid and tonumber(packet:match('[{,]nation=(%d+)'))==event.nation
                    and tonumber(packet:match('[{,]nation_mission=(%d+)'))==event.nation_mission;
                active[i]=same and true or false;
                if not same then pending[i]=nil; end;
                if valid and not same then proved[i]=nil; end;
            end;
        end;
        local now=timestamp(line);
        local packet,dir,target,a,b=line:match(' objective packet trace id=(0x%x+) dir=(%a+) len=%d+ target=(%d+) a=(%d+) b=(%d+)');
        target,a,b=tonumber(target),tonumber(a),tonumber(b);
        for i,event in ipairs(events) do
            local arm=pending[i];
            if arm and (not now or now<arm.time or now-arm.time>1200) then
                pending[i]=nil; arm=nil;
            end;
            if active[i] and now then
                if packet=='0x001A' and dir=='out' and a==0 then
                    pending[i]=target==event.target_server_id and {time=now} or nil;
                elseif packet=='0x0032' and dir=='in' then
                    if arm and target==event.target_server_id
                        and a==event.zone_id and b==event.event_id then
                        arm.started=true;
                    else pending[i]=nil; end;
                elseif packet=='0x0034' and dir=='in' then
                    pending[i]=nil;
                elseif arm and arm.started and line:find(' npc text mode=150 "'..event.speaker..' : ',1,true)
                    and line:find(event.dialogue,1,true) then
                    arm.dialogue=true;
                elseif packet=='0x005B' and dir=='out' then
                    if arm and arm.started and arm.dialogue and target==event.target_server_id then
                        proved[i]={native_key=event.native_key,step_id=event.step_id,
                            action_id=event.action_id,zone_id=event.zone_id,
                            target_server_id=event.target_server_id,event_id=event.event_id,
                            identity=identity,observed_at=now};
                    end;
                    pending[i]=nil;
                end;
            end;
        end;
    end;
    local result={};
    for i in ipairs(events) do if proved[i] then result[#result+1]=proved[i]; end; end;
    return result;
end;

function M.read_history(paths, identity)
    local parts={};
    local scan={files=0,bytes=0,unreadable=0,truncated=0};
    for _,path in ipairs(paths or {}) do
        local f=io.open(path,'rb');
        if f then
            local size=f:seek('end') or 0;
            local start=math.max(0,size-8*1024*1024);
            f:seek('set',start);
            if start>0 then f:read('*l'); scan.truncated=scan.truncated+1; end;
            local content=f:read('*a');
            if content then
                parts[#parts+1]=content;
                scan.files=scan.files+1;
                scan.bytes=scan.bytes+#content;
            else scan.unreadable=scan.unreadable+1; end;
            f:close();
        else scan.unreadable=scan.unreadable+1; end;
    end;
    return M.recover(table.concat(parts,'\n'),identity),scan;
end;

if type(accessxi)=='table' then accessxi.objective_event_evidence=M; end;
return M;
