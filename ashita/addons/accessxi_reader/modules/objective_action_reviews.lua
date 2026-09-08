-- Shared handling for reviewed action destinations and distinct interactions.
-- A catalogue binding alone supplies no progress: native start/finish pairing
-- and the navigation reducer's current character/session gates still apply.
local M = {};
local data = dofile(accessxi_paths.addon_path('modules','objective_action_review_data.lua'));
local function copy(value)
    if type(value)~='table' then return value; end;
    local out={}; for k,v in pairs(value) do out[k]=copy(v); end; return out;
end;
local special={destinations=true,events=true,members=true,ingress=true,omit=true};
function M.augment_actions(native_key,actions,point_for_id)
    local review=data[native_key];
    if not review then return actions,''; end;
    local out,refusal={},nil;
    for _,old in ipairs(actions) do
        local patch=review.actions[old.action_id];
        if not (patch and patch.omit) then
            local action=copy(old);
            if patch then
                for k,v in pairs(patch) do if not special[k] then action[k]=copy(v); end; end;
                action.review_revision=review.revision;
                action.interaction_events=copy(patch.events);
                action.interaction_set=copy(patch.members);
                if patch.members then
                    action.required_count=#patch.destinations;
                    action.count_mode='distinct-interactions';
                    action.count_explicit=true;
                end;
                action.catalogue={};
                for _,id in ipairs(patch.destinations or {}) do
                    local p=point_for_id(id);
                    if not p or not tonumber(p.x) or not tonumber(p.z) or not tonumber(p.y) then
                        refusal='reviewed destination missing: '..id;
                        action.review_route_refusal='A required mission location is missing from this installation. Update AccessXI and try again.';
                        action.instruction=(action.instruction or '')..' '..action.review_route_refusal;
                        action.catalogue={};
                        break;
                    end;
                    action.catalogue[#action.catalogue+1]={destination_id=id,zone_id=p.zone,
                        zone_name=p.zone_name,
                        target_name=p.name,target_kind=p.kind,target_point={p.x,p.z,p.y},
                        raw_identity=p.raw_identity,raw_spawn_ids={tonumber(id:match(':(%d+)$'))},
                        canonical_edge_id=patch.ingress and patch.ingress.edge_id,
                        canonical_from_zone=patch.ingress and patch.ingress.from_zone};
                end;
            end;
            out[#out+1]=action;
        end;
    end;
    return out,review.revision,refusal;
end;

-- The cursor stores the actual completed identities, never just a count.
-- Canonical encoding rejects duplicates, unknown members, and malformed rows.
function M.members(action,encoded)
    local declared=type(action)=='table' and action.interaction_set;
    if type(declared)~='table' then return nil; end;
    encoded=tostring(encoded or '');
    local done,ordered={},{};
    for token in encoded:gmatch('[^,]+') do
        local id=tonumber(token);
        if not id or tostring(id)~=token or not declared[id] or done[id] then return nil; end;
        done[id]=true; ordered[#ordered+1]=token;
    end;
    table.sort(ordered);
    if table.concat(ordered,',')~=encoded then return nil; end;
    return done,#ordered;
end;

function M.event_matches(action,signal)
    if type(action.interaction_set)=='table' then
        return action.interaction_set[tonumber(signal.target_server_id)]==tonumber(signal.event_id);
    end;
    if type(action.interaction_events)=='table' then
        for _,event in ipairs(action.interaction_events) do if event==tonumber(signal.event_id) then return true; end; end;
        return false;
    end;
    return true;
end;

function M.complete_member(action,record,signal)
    if not M.event_matches(action,signal) then return nil; end;
    local same=type(record)=='table' and record.action_id==action.action_id;
    local done,count=M.members(action,same and record.progress_members or '');
    local id=tonumber(signal.target_server_id);
    if not done or done[id] then return nil; end;
    if count~=(same and tonumber(record.progress_count) or 0) then return nil; end;
    done[id]=true;
    local ordered={}; for member in pairs(done) do ordered[#ordered+1]=tostring(member); end;
    table.sort(ordered);
    return table.concat(ordered,','),count+1;
end;

if type(accessxi)=='table' then accessxi.objective_action_reviews=M; end;
return M;
