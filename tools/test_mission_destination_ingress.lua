-- Real nation data regression: an interaction must retain its physical target
-- and an entrance into that target's component, even before entering its zone.
WALKTHROUGH_EMBED = true;
local h = dofile('tools/test_mission_step_resolver.lua');
local addon = assert(os.getenv('ACCESSXI_ADDON'));
local failures, passes = 0, 0;
local function check(ok, label)
    if ok then passes = passes + 1; print('ok ' .. label);
    else failures = failures + 1; print('FAIL ' .. label); end
end
local key = 'mission:Windurst:1';
local steps = dofile(addon .. '/modules/mission_quest_reconcile_mission_windurst.lua')[key].steps;
local destinations = h.progression_destinations('mission_quest_progression_mission_windurst');
for _, zone in ipairs({240, 116, 115, 192}) do
    local ctx = h.make_ctx(zone, function(id) return destinations[id] or 0; end, 'Windurst', key);
    local targets, info = h.resolver.resolve_step(steps, 17, ctx);
    check(#targets == 1 and targets[1].name == 'Gate: Magical Gizmo'
        and targets[1].zone == 192 and math.abs(targets[1].x - 420) < .01,
        'Windurst 1 from zone ' .. zone .. ' selects the Lily Tower gate');
    check(#targets == 1 and targets[1].canonical_edge_id == 1631073146
        and targets[1].canonical_from_zone == 116,
        'Windurst 1 from zone ' .. zone .. ' retains the East Sarutabaruta entrance');
    check(info.partial ~= 'zone-only' and info.kind ~= 'zone-travel-choice',
        'examining the gate is not replaced by entering a zone');
end
local binding = h.make_ctx(230).step_target_binding("mission:San d'Oria:6:step-007");
check(binding and binding.target == 'Savae E Paleade' and binding.zone == 237,
    'reviewed San d\'Oria branch contact ships with the addon');
do
    local ctx = h.make_ctx(116, nil, 'Windurst', key);
    ctx.step_target_binding = function() return nil; end;
    local targets = h.resolver.resolve_step(steps, 17, ctx);
    check(#targets == 2 and targets[1].name == 'Gate: Magical Gizmo'
        and targets[2].name == 'Gate: Magical Gizmo' and targets[1].zone == 192 and targets[2].zone == 192,
        'shared compact-action rescue preserves both physical gates when exact identity is not reviewed');
    ctx.step_target_binding = function() return { target = 'Gate: Magical Gizmo', zone = 192, destination_id = 'missing-exact-id' }; end;
    local missing, info = h.resolver.resolve_step(steps, 17, ctx);
    check(#missing == 0 and info.reason == h.resolver.REASONS.ENTITY_ABSENT,
        'missing reviewed identity cannot silently fall back to a same-name gate');
    local tower = h.resolver.resolve_step(steps, 9, h.make_ctx(116, nil, 'Windurst', key));
    check(#tower == 1 and math.abs(tower[1].x - 399.294) < .01 and tower[1].zone == 116,
        'the tower approach still has a destination after entering East Sarutabaruta');
    local spring_key='mission:Windurst:21';
    local spring_steps=dofile(addon..'/modules/mission_quest_reconcile_mission_windurst.lua')[spring_key].steps;
    local spring, spring_info=h.resolver.resolve_step(spring_steps, 5, h.make_ctx(240,nil,'Windurst',spring_key));
    check(#spring > 0 and (spring_info.ingress_unverified or 0) > 0
        and (spring[1].choice_note or ''):find('approach to this destination is unverified',1,true),
        'all-negative mesh evidence remains explicit without hiding the target from other route providers');
end
print(('Mission destination ingress: %d passed, %d failed'):format(passes, failures));
if failures > 0 then os.exit(1); end
