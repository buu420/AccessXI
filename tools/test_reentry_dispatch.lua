-- Execute the actual reader's refusal dispatch blocks. A valid planner is
-- useless if the synchronous/async provider-return paths never call it.
local addon = assert(os.getenv('ACCESSXI_ADDON'));
local f=assert(io.open(addon..'/accessxi_reader.lua','r')); local source=f:read('*a'); f:close();
local function block(start_text, end_text)
    local a=assert(source:find(start_text,1,true)); local b=assert(source:find(end_text,a,true));
    return source:sub(a,b-1);
end
local blocks={
    block('local provider_text = nav_clean_field(accessxi.nav_route_last_reject_reason);',"nav_write_route_evidence('unreachable', player, item"),
    block('local collision_text = nav_clean_field(accessxi.nav_route_last_reject_reason);','accessxi.nav_active = false;'),
    block('-- A terrain request can fail asynchronously,','if (type(nav_route_stop)'),
};
for i,code in ipairs(blocks) do
    for _,active in ipairs({false,true}) do
      for _,is_leg in ipairs({false,true}) do
        local calls=0;
        local state={nav_route_last_reject_reason='one point is not a route',
            nav_same_zone_reentry_active=function() return active; end,
            nav_same_zone_reentry_start=function() calls=calls+1; return 'Recovery route'; end};
        local point={source=is_leg and 'zonesearch:123:116:192' or 'mission-source'};
        local env=setmetatable({accessxi=state,nav_clean_field=tostring,speak=function() end,
            pending={owner_destination=point},destination=point,player={},item=point,point=point}, {__index=_G});
        local chunk=assert(loadstring('return function() '..code..' return "fallthrough" end'));
        setfenv(chunk,env); local result=chunk()();
        assert(calls==((active or is_leg) and 0 or 1), 'dispatch '..i..' active='..tostring(active));
        assert(not (active or is_leg) or result=='fallthrough', 're-entry must not recurse or replace a zone search final target');
      end
    end
end
print('Reentry dispatch: synchronous menu, synchronous command, and async terrain recovery passed');
