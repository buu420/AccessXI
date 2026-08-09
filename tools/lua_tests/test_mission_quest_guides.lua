local module_path = assert(arg[1], 'missing mission/quest guide module path')
local manual_path = assert(arg[2], 'missing manual-step test path')

local module_loader_calls = {}
local current_identity = 'alpha:1001'
local identity_changes = 0

local index = {
    ['mission:Bastok:2'] = {
        kind = 'mission',
        context = 'Bastok',
        native_id = 2,
        title = 'A Geological Survey',
        status = 'guide',
        source_modules = {
            bg = 'fixture_bg_mission_bastok',
            ffxiclopedia = 'fixture_ffxiclopedia_mission_bastok',
        },
        reconcile_module = 'fixture_reconcile_mission_bastok',
    },
    ['quest:windurst:77'] = {
        kind = 'quest',
        context = 'windurst',
        native_id = 77,
        title = 'Acting in Good Faith',
        status = 'source-conflict',
        source_modules = {
            bg = 'fixture_broken_quest_windurst',
            ffxiclopedia = 'fixture_ffxiclopedia_quest_windurst',
        },
        reconcile_module = 'fixture_reconcile_quest_windurst',
    },
    ['quest:windurst:78'] = {
        kind = 'quest',
        context = 'windurst',
        native_id = 78,
        title = 'Runtime Quest Fixture',
        status = 'guide',
        source_modules = {
            bg = 'fixture_bg_quest_runtime',
            ffxiclopedia = 'fixture_ffxiclopedia_quest_runtime',
        },
        reconcile_module = 'fixture_reconcile_quest_runtime',
    },
}

local modules = {
    fixture_bg_mission_bastok = {
        ['mission:Bastok:2'] = {
            steps = {
                { order = 1, instruction = 'Talk to Cid in the Metalworks.', action = 'talk' },
                { order = 2, instruction = 'BG says use the north geyser.', action = 'wait' },
                { order = 3, instruction = 'Return to Cid.', action = 'talk' },
            },
        },
    },
    fixture_ffxiclopedia_mission_bastok = {
        ['mission:Bastok:2'] = {
            steps = {
                { order = 1, instruction = 'Speak with Cid in the Metalworks.', action = 'talk' },
                { order = 2, instruction = 'FFXIclopedia says use the south geyser.', action = 'wait' },
            },
        },
    },
    fixture_reconcile_mission_bastok = {
        ['mission:Bastok:2'] = {
            dynamic_candidate_comparison = 'none',
            dynamic_candidate_grid = {},
            default_step_id = 'mission:Bastok:2:step-003',
            automatic_stages = {
                ['obtain-blue-tester'] = 'mission:Bastok:2:step-001',
            },
            mission_destinations = {
                {
                    stable_id = 'mission:Bastok:2:palborough-lower-amber',
                    source_step_ids = { 'mission:Bastok:2:step-001' },
                    action = 'farm',
                    items = { 'Fetich Head', 'Fetich Torso', 'Fetich Arms', 'Fetich Legs' },
                    enemies = { 'Amber Quadav' },
                    zone = 143,
                    zone_name = 'Palborough Mines',
                    camp_label = 'lower camp',
                    navigation_target = {
                        type = 'static-reference',
                        reference = {
                            zone = 143,
                            zone_name = 'Palborough Mines',
                            name = 'Amber Quadav',
                            kind = 'enemy',
                        },
                    },
                    canonical_ingress_edge_id = 947466874,
                    canonical_ingress_from_zone = 106,
                    transport_id = '',
                    route_evidence = 'navprobe:lower',
                    arrival_instruction = 'Farm the four Fetich pieces from Amber Quadav.',
                    route_ready = true,
                },
                {
                    stable_id = 'mission:Bastok:2:palborough-upper-quadav',
                    source_step_ids = { 'mission:Bastok:2:step-001' },
                    action = 'farm',
                    items = { 'Fetich Head', 'Fetich Torso', 'Fetich Arms', 'Fetich Legs' },
                    enemies = { 'Greater Quadav', 'Onyx Quadav', 'Veteran Quadav' },
                    zone = 143,
                    zone_name = 'Palborough Mines',
                    camp_label = 'upper camp by elevator',
                    navigation_target = {
                        type = 'static-reference',
                        reference = {
                            zone = 143,
                            zone_name = 'Palborough Mines',
                            name = 'Onyx Quadav',
                            kind = 'enemy',
                        },
                    },
                    canonical_ingress_edge_id = 947466874,
                    canonical_ingress_from_zone = 106,
                    transport_id = 'palborough-mines-lift',
                    route_evidence = 'navprobe:upper',
                    arrival_instruction = 'Farm the four Fetich pieces from the upper Quadav camp.',
                    route_ready = true,
                },
            },
            steps = {
                {
                    stable_step_id = 'mission:Bastok:2:step-001',
                    order = 1,
                    source_orders = { 1, 1 },
                    comparison = 'corroborated',
                    conflicting_fields = {},
                    action = 'talk',
                    route_ready = true,
                    navigation_target = {
                        type = 'static-reference',
                        reference = {
                            zone = 237,
                            zone_name = 'Metalworks',
                            name = 'Cid',
                            kind = 'npc',
                        },
                        arrival_instruction = 'Talk to Cid.',
                    },
                },
                {
                    stable_step_id = 'mission:Bastok:2:step-002',
                    order = 2,
                    source_orders = { 2, 2 },
                    comparison = 'conflict',
                    conflicting_fields = { 'grid_coordinates' },
                    action = 'wait',
                    route_ready = false,
                },
                {
                    stable_step_id = 'mission:Bastok:2:step-003',
                    order = 3,
                    source_orders = { 3, 0 },
                    comparison = 'single-source',
                    conflicting_fields = {},
                    action = 'talk',
                    route_ready = false,
                },
            },
        },
    },
    fixture_ffxiclopedia_quest_windurst = {
        ['quest:windurst:77'] = { steps = { { order = 1, instruction = 'Inspect the brazier.', action = 'examine' } } },
    },
    fixture_reconcile_quest_windurst = {
        ['quest:windurst:77'] = {
            steps = {
                {
                    stable_step_id = 'quest:windurst:77:step-001',
                    order = 1,
                    source_orders = { 1, 1 },
                    comparison = 'conflict',
                    conflicting_fields = { 'result' },
                    action = 'examine',
                    route_ready = false,
                },
            },
        },
    },
    fixture_bg_quest_runtime = {
        ['quest:windurst:78'] = { steps = { { order = 1, instruction = 'Defeat Test Enemy.', action = 'fight' } } },
    },
    fixture_ffxiclopedia_quest_runtime = {
        ['quest:windurst:78'] = { steps = { { order = 1, instruction = 'Defeat Test Enemy.', action = 'fight' } } },
    },
    fixture_reconcile_quest_runtime = {
        ['quest:windurst:78'] = {
            -- New typed candidates own the menu. A coexisting compatibility
            -- field must be fallback-only, never concatenated or promoted.
            mission_destinations = {
                {
                    stable_id = 'unsafe-legacy-row',
                    route_ready = true,
                    route_evidence = 'legacy free text',
                },
            },
            action_resolution_ledger = {
                {
                    action_id = 'quest:windurst:78:step-001:claim-01',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-001:action-01',
                        'quest:windurst:78:ffxiclopedia:step-001:action-01',
                    },
                    action = 'fight',
                    status = 'catalogue-candidate',
                    reason = 'dual-source-exact-catalogue-match',
                    candidate_ids = {
                        'quest:windurst:78:step-001:claim-01:candidate:east',
                        'quest:windurst:78:step-001:claim-01:candidate:west',
                    },
                    instruction = '',
                    material = true,
                    route_ready = false,
                },
            },
            objective_destination_candidates = {
                {
                    candidate_id = 'quest:windurst:78:step-001:claim-01:candidate:east',
                    action_id = 'quest:windurst:78:step-001:claim-01',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-001:action-01',
                        'quest:windurst:78:ffxiclopedia:step-001:action-01',
                    },
                    source_sites = { 'bg', 'ffxiclopedia' },
                    source_revisions = { bg = 1001, ffxiclopedia = 2002 },
                    coordinate_support = {},
                    coordinate_comparison = 'game-data',
                    action = 'fight',
                    items = { 'Test Charm' },
                    enemies = { 'Test Enemy' },
                    result_relation = 'defeat-to-obtain',
                    destination_id = 'enemy:v1:115:test-east',
                    zone = 115,
                    zone_name = 'West Sarutabaruta',
                    target_name = 'Test Enemy',
                    target_kind = 'enemy',
                    target_point = { 10, 20, 0 },
                    raw_identity = 'lsb:mob_spawn_points:group:1:mobname:Test_Enemy',
                    raw_spawn_ids = { 1 },
                    cluster_policy_version = 'complete-link-v1-h120-y24',
                    evidence_level = 'dual-source-plus-game-data',
                    group_id = 'quest:windurst:78:step-001:claim-01:group:east',
                    metadata_class = '',
                    transport_id = '',
                    battlefield_id = '',
                    label = 'Test Enemy east camp',
                    arrival_instruction = 'Defeat Test Enemy in the east camp.',
                    route_ready = false,
                },
                {
                    candidate_id = 'quest:windurst:78:step-001:claim-01:candidate:west',
                    action_id = 'quest:windurst:78:step-001:claim-01',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-001:action-01',
                        'quest:windurst:78:ffxiclopedia:step-001:action-01',
                    },
                    source_sites = { 'bg', 'ffxiclopedia' },
                    source_revisions = { bg = 1001, ffxiclopedia = 2002 },
                    coordinate_support = {},
                    coordinate_comparison = 'game-data',
                    action = 'fight',
                    items = { 'Test Charm' },
                    enemies = { 'Test Enemy' },
                    result_relation = 'defeat-to-obtain',
                    destination_id = 'enemy:v1:115:test-west',
                    zone = 115,
                    zone_name = 'West Sarutabaruta',
                    target_name = 'Test Enemy',
                    target_kind = 'enemy',
                    target_point = { -10, -20, 0 },
                    raw_identity = 'lsb:mob_spawn_points:group:1:mobname:Test_Enemy',
                    raw_spawn_ids = { 2 },
                    cluster_policy_version = 'complete-link-v1-h120-y24',
                    evidence_level = 'dual-source-plus-game-data',
                    group_id = 'quest:windurst:78:step-001:claim-01:group:west',
                    metadata_class = '',
                    transport_id = '',
                    battlefield_id = '',
                    label = 'Test Enemy west camp',
                    arrival_instruction = 'Defeat Test Enemy in the west camp.',
                    route_ready = false,
                },
            },
            objective_destination_groups = {
                {
                    group_id = 'quest:windurst:78:step-001:claim-01:group:east',
                    action_id = 'quest:windurst:78:step-001:claim-01',
                    zone = 115,
                    zone_name = 'West Sarutabaruta',
                    candidate_ids = { 'quest:windurst:78:step-001:claim-01:candidate:east' },
                    evidence_level = 'dual-source-plus-game-data',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-001:action-01',
                        'quest:windurst:78:ffxiclopedia:step-001:action-01',
                    },
                    route_ready = false,
                },
                {
                    group_id = 'quest:windurst:78:step-001:claim-01:group:west',
                    action_id = 'quest:windurst:78:step-001:claim-01',
                    zone = 115,
                    zone_name = 'West Sarutabaruta',
                    candidate_ids = { 'quest:windurst:78:step-001:claim-01:candidate:west' },
                    evidence_level = 'dual-source-plus-game-data',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-001:action-01',
                        'quest:windurst:78:ffxiclopedia:step-001:action-01',
                    },
                    route_ready = false,
                },
            },
            steps = {
                {
                    stable_step_id = 'quest:windurst:78:step-001',
                    order = 1,
                    source_orders = { 1, 1 },
                    comparison = 'corroborated',
                    conflicting_fields = {},
                    action = 'fight',
                    typed_claims = {
                        {
                            stable_claim_id = 'quest:windurst:78:step-001:claim-01',
                            order = 1,
                            action = 'fight',
                            relationship = 'defeat-to-obtain',
                            target = 'Test Enemy',
                            target_kind = 'enemy',
                            comparison = 'corroborated',
                            alignment_score = 12,
                            alignment_reason = 'compatible-action-target',
                            unpaired_reason = '',
                            bg_span_order = 1,
                            ffxiclopedia_span_order = 1,
                            candidates = {},
                        },
                    },
                    route_ready = false,
                },
            },
        },
    },
}

local function module_loader(name)
    module_loader_calls[#module_loader_calls + 1] = name
    if name == 'fixture_broken_quest_windurst' then
        error('intentional corrupt source chunk')
    end
    return modules[name]
end

local seed = assert(io.open(manual_path, 'w'))
seed:write('alpha\tmission:Bastok:2\t99\n')
seed:write('alpha:1001\tmission:Bastok:2\t2\n')
seed:close()

local guide_module = assert(loadfile(module_path))()
assert(type(guide_module) == 'table' and type(guide_module.new) == 'function')
local function isolated_guides()
    return guide_module.new({
        index = index,
        module_loader = module_loader,
        identity_provider = function() return current_identity end,
        manual_path = '',
    })
end
local guides = guide_module.new({
    index = index,
    module_loader = module_loader,
    identity_provider = function() return current_identity end,
    manual_path = manual_path,
    route_resolver = function(native_key, step_id, step)
        local reference = type(step) == 'table'
            and type(step.navigation_target) == 'table'
            and step.navigation_target.reference or nil
        if native_key == 'mission:Bastok:2' and step_id == 'mission:Bastok:2:step-001'
            and type(reference) == 'table' and reference.zone == 237
            and reference.name == 'Cid' and reference.kind == 'npc' then
            return { zone = 237, name = 'Cid', kind = 'npc', verified = true }
        end
        return nil
    end,
    on_character_change = function() identity_changes = identity_changes + 1 end,
})

assert(guides:is_open() == false)
assert(guides:index_entry('mission:Bastok:2').title == 'A Geological Survey')
assert(#module_loader_calls == 0)

local opened, reason = guides:open('mission:Bastok:2')
assert(opened ~= nil, tostring(reason))
assert(guides:is_open() == true)
assert(guides:step_count() == 3)
assert(guides:current_index() == 2)
assert(#module_loader_calls == 3)
assert(module_loader_calls[1] == 'fixture_bg_mission_bastok')
assert(module_loader_calls[2] == 'fixture_ffxiclopedia_mission_bastok')
assert(module_loader_calls[3] == 'fixture_reconcile_mission_bastok')
assert(guides:automatic_step_id('mission:Bastok:2', 'obtain-blue-tester') == 'mission:Bastok:2:step-001')
local destinations = assert(guides:objective_destinations('mission:Bastok:2'))
assert(#destinations == 2)
assert(destinations[1].stable_id == 'mission:Bastok:2:palborough-lower-amber')
assert(destinations[2].transport_id == 'palborough-mines-lift')
destinations[1].items[1] = 'caller mutation'
destinations[1].source_step_ids[1] = 'caller mutation'
destinations[1].navigation_target.reference.name = 'caller mutation'
local fresh_destinations = assert(guides:objective_destinations('mission:Bastok:2'))
assert(fresh_destinations[1].items[1] == 'Fetich Head')
assert(fresh_destinations[1].source_step_ids[1] == 'mission:Bastok:2:step-001')
assert(fresh_destinations[1].navigation_target.reference.name == 'Amber Quadav')
local compatibility_destinations = assert(guides:mission_destinations('mission:Bastok:2'))
assert(#compatibility_destinations == 2)
compatibility_destinations[2].enemies[1] = 'compatibility caller mutation'
assert(guides:objective_destinations('mission:Bastok:2')[2].enemies[1] == 'Greater Quadav')

local quest_destinations = assert(guides:objective_destinations('quest:windurst:78'))
assert(#quest_destinations == 2)
for _, destination in ipairs(quest_destinations) do
    assert(destination.stable_id ~= 'unsafe-legacy-row')
end
assert(quest_destinations[1].candidate_id == 'quest:windurst:78:step-001:claim-01:candidate:east')
assert(quest_destinations[1].action_id == 'quest:windurst:78:step-001:claim-01')
assert(quest_destinations[1].group_id == 'quest:windurst:78:step-001:claim-01:group:east')
assert(quest_destinations[1].guide_step_id == 'quest:windurst:78:step-001')
assert(quest_destinations[1].action_instruction == 'Defeat Test Enemy in the east camp.')
assert(quest_destinations[1].arrival_instruction == 'Defeat Test Enemy in the east camp.')
assert(quest_destinations[1].route_ready == false)
assert(quest_destinations[2].label == 'Test Enemy west camp')
quest_destinations[1].items[1] = 'caller mutation'
quest_destinations[1].source_revisions.bg = 9999
quest_destinations[1].target_point[1] = 9999
local fresh_quest_destinations = assert(guides:objective_destinations('quest:windurst:78'))
assert(fresh_quest_destinations[1].items[1] == 'Test Charm')
assert(fresh_quest_destinations[1].source_revisions.bg == 1001)
assert(fresh_quest_destinations[1].target_point[1] == 10)
assert(#guides:mission_destinations('quest:windurst:78') == 2)

local runtime_reconciliation = modules.fixture_reconcile_quest_runtime['quest:windurst:78']
local saved_candidates = runtime_reconciliation.objective_destination_candidates
runtime_reconciliation.objective_destination_candidates = {}
assert(#isolated_guides():objective_destinations('quest:windurst:78') == 0,
    'an explicitly empty typed candidate table must not resurrect legacy rows')
runtime_reconciliation.objective_destination_candidates = saved_candidates

local function assert_only_west(rows, reason)
    assert(#rows == 1, reason)
    assert(rows[1].candidate_id == 'quest:windurst:78:step-001:claim-01:candidate:west', reason)
end

local ledger = runtime_reconciliation.action_resolution_ledger
local saved_candidate_ids = ledger[1].candidate_ids
ledger[1].candidate_ids = {}
assert(#isolated_guides():objective_destinations('quest:windurst:78') == 0,
    'orphan candidates without a ledger owner must fail closed')
ledger[1].candidate_ids = saved_candidate_ids

ledger[2] = {
    action_id = ledger[1].action_id,
    source_action_span_ids = {
        'quest:windurst:78:bg:step-001:action-01',
        'quest:windurst:78:ffxiclopedia:step-001:action-01',
    },
    action = 'fight',
    status = 'catalogue-candidate',
    reason = 'dual-source-exact-catalogue-match',
    candidate_ids = { 'quest:windurst:78:step-001:claim-01:candidate:east' },
    instruction = '',
    material = true,
    route_ready = false,
}
assert_only_west(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'a candidate owned by multiple ledger rows must fail closed')
ledger[2] = nil

local saved_action = saved_candidates[1].action
saved_candidates[1].action = 'examine'
assert_only_west(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'candidate and ledger action mismatch must fail closed')
saved_candidates[1].action = saved_action

local saved_span_ids = saved_candidates[1].source_action_span_ids
saved_candidates[1].source_action_span_ids = { 'quest:windurst:78:bg:step-999:action-01' }
assert_only_west(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'candidate source spans outside its ledger owner must fail closed')
saved_candidates[1].source_action_span_ids = saved_span_ids

local saved_arrival_instruction = saved_candidates[1].arrival_instruction
saved_candidates[1].arrival_instruction = ''
assert_only_west(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'a typed candidate without its candidate-specific action instruction must fail closed')
saved_candidates[1].arrival_instruction = saved_arrival_instruction

runtime_reconciliation.steps[2] = {
    stable_step_id = 'quest:windurst:78:step-002',
    order = 2,
    source_orders = { 1, 1 },
    comparison = 'corroborated',
    conflicting_fields = {},
    action = 'fight',
    typed_claims = {
        {
            stable_claim_id = 'quest:windurst:78:step-001:claim-01',
            order = 1,
            action = 'fight',
            relationship = 'defeat-to-obtain',
            target = 'Test Enemy',
            target_kind = 'enemy',
            comparison = 'corroborated',
            alignment_score = 12,
            alignment_reason = 'compatible-action-target',
            unpaired_reason = '',
            bg_span_order = 1,
            ffxiclopedia_span_order = 1,
            candidates = {},
        },
    },
    route_ready = false,
}
assert(#isolated_guides():objective_destinations('quest:windurst:78') == 0,
    'an action mapped to multiple guide steps must fail closed')
runtime_reconciliation.steps[2] = nil

local conflict_speech = guides:repeat_step()
assert(conflict_speech:find('Step 2 of 3', 1, true) ~= nil)
assert(conflict_speech:find('Sources disagree', 1, true) ~= nil)
assert(conflict_speech:find('BG says use the north geyser.', 1, true) ~= nil)
assert(conflict_speech:find('FFXIclopedia says use the south geyser.', 1, true) ~= nil)
assert(guides:route_descriptor() == nil)

local moved = guides:move(1)
assert(moved:find('Step 3 of 3', 1, true) ~= nil)
assert(guides:current_index() == 3)
guides:close('test')
assert(guides:is_open() == false)

local reopened = assert(guides:open('mission:Bastok:2'))
assert(reopened ~= nil)
assert(guides:current_index() == 3)
guides:close('automatic')
assert(guides:open('mission:Bastok:2', 'mission:Bastok:2:step-001') ~= nil)
assert(guides:current_index() == 1)
local route = guides:route_descriptor()
assert(type(route) == 'table' and route.name == 'Cid')

current_identity = 'alpha:2002'
assert(guides:sync_identity() == true)
assert(guides:is_open() == false)
assert(identity_changes == 1)
assert(guides:open('mission:Bastok:2') ~= nil)
assert(guides:current_index() == 3)

local missing, missing_reason = guides:resolve('quest:windurst:77')
assert(missing == nil)
assert(tostring(missing_reason):find('source chunk unavailable', 1, true) ~= nil)
assert(guides:resolve('mission:Bastok:2') ~= nil)

guides:close('done')
os.remove(manual_path)
print('mission and quest guide tests passed')
