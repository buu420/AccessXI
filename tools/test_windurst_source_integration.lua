INTEGRATION_EMBED = true;
local h = dofile('tools/test_source_route_integration.lua');
h.set_player_zone(116);
local source_rows;
for i=1,100 do
    local name,value=debug.getupvalue(accessxi.nav_mission_quest_step_route_capability,i);
    if name=='source_route_rows' then source_rows=value; break; end
    if not name then break; end
end
assert(type(source_rows)=='function', 'production source-row seam');
local gate;
for _,row in ipairs(source_rows('mission:Windurst:1')) do
    if row.guide_step_id=='mission:Windurst:1:step-017' then
        assert(gate==nil, 'exact mission gate cannot be duplicated'); gate=row;
    end
end
h.claim(gate and gate.target_name=='Gate: Magical Gizmo' and gate.target_point[1]==420,
    'production mission rows retain the exact Lily Tower gate');
h.claim(gate and gate.canonical_edge_id==1631073146 and gate.canonical_from_zone==116,
    'production mission rows retain the exact East entrance');
h.claim(gate and type(gate.objective_via_zones)=='table' and gate.objective_via_zones[1]==116,
    'production candidate copies retain the explicitly described approach road');
h.result();
