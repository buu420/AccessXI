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
        ['quest:windurst:78'] = { steps = {
            { order = 1, instruction = 'Defeat Test Enemy.', action = 'fight' },
            { order = 2, instruction = 'Wait for the test signal.', action = 'wait' },
            { order = 3, instruction = 'Talk to Test Guide.', action = 'talk' },
        } },
    },
    fixture_ffxiclopedia_quest_runtime = {
        ['quest:windurst:78'] = { steps = {
            { order = 1, instruction = 'Defeat Test Enemy.', action = 'fight' },
            { order = 2, instruction = 'Wait for the test signal.', action = 'wait' },
            { order = 3, instruction = 'Talk to Test Guide.', action = 'talk' },
        } },
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
                {
                    action_id = 'quest:windurst:78:step-002:claim-01',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-002:action-01',
                        'quest:windurst:78:ffxiclopedia:step-002:action-01',
                    },
                    action = 'wait',
                    status = 'instruction-only',
                    reason = 'complete-instruction',
                    candidate_ids = {},
                    instruction = 'Wait for the test signal.',
                    material = true,
                    route_ready = false,
                },
                {
                    action_id = 'quest:windurst:78:step-003:claim-01',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-003:action-01',
                        'quest:windurst:78:ffxiclopedia:step-003:action-01',
                    },
                    action = 'talk',
                    status = 'catalogue-candidate',
                    reason = 'dual-source-exact-catalogue-match',
                    candidate_ids = {
                        'quest:windurst:78:step-003:claim-01:candidate:guide',
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
                {
                    candidate_id = 'quest:windurst:78:step-003:claim-01:candidate:guide',
                    action_id = 'quest:windurst:78:step-003:claim-01',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-003:action-01',
                        'quest:windurst:78:ffxiclopedia:step-003:action-01',
                    },
                    source_sites = { 'bg', 'ffxiclopedia' },
                    source_revisions = { bg = 1001, ffxiclopedia = 2002 },
                    coordinate_support = {},
                    coordinate_comparison = 'game-data',
                    action = 'talk',
                    items = {},
                    enemies = {},
                    result_relation = '',
                    destination_id = 'npc:v1:115:3003',
                    zone = 115,
                    zone_name = 'West Sarutabaruta',
                    target_name = 'Test Guide',
                    target_kind = 'npc',
                    target_point = { 30, 40, 0 },
                    raw_identity = 'lsb:npc_list:3003',
                    raw_spawn_ids = {},
                    cluster_policy_version = '',
                    evidence_level = 'dual-source-plus-game-data',
                    group_id = 'quest:windurst:78:step-003:claim-01:group:guide',
                    metadata_class = '',
                    transport_id = '',
                    battlefield_id = '',
                    label = 'Test Guide',
                    arrival_instruction = 'Talk to Test Guide in West Sarutabaruta.',
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
                {
                    group_id = 'quest:windurst:78:step-003:claim-01:group:guide',
                    action_id = 'quest:windurst:78:step-003:claim-01',
                    zone = 115,
                    zone_name = 'West Sarutabaruta',
                    candidate_ids = { 'quest:windurst:78:step-003:claim-01:candidate:guide' },
                    evidence_level = 'dual-source-plus-game-data',
                    source_action_span_ids = {
                        'quest:windurst:78:bg:step-003:action-01',
                        'quest:windurst:78:ffxiclopedia:step-003:action-01',
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
                {
                    stable_step_id = 'quest:windurst:78:step-002',
                    order = 2,
                    source_orders = { 2, 2 },
                    comparison = 'corroborated',
                    conflicting_fields = {},
                    action = 'wait',
                    typed_claims = {
                        {
                            stable_claim_id = 'quest:windurst:78:step-002:claim-01',
                            order = 1,
                            action = 'wait',
                            relationship = 'instruction',
                            target = '',
                            target_kind = '',
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
                {
                    stable_step_id = 'quest:windurst:78:step-003',
                    order = 3,
                    source_orders = { 3, 3 },
                    comparison = 'corroborated',
                    conflicting_fields = {},
                    action = 'talk',
                    typed_claims = {
                        {
                            stable_claim_id = 'quest:windurst:78:step-003:claim-01',
                            order = 1,
                            action = 'talk',
                            relationship = 'talk',
                            target = 'Test Guide',
                            target_kind = 'npc',
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
assert(#quest_destinations == 4)
for _, destination in ipairs(quest_destinations) do
    assert(destination.stable_id ~= 'unsafe-legacy-row')
end
assert(quest_destinations[1].candidate_id == 'quest:windurst:78:step-001:claim-01:candidate:east')
assert(quest_destinations[1].action_id == 'quest:windurst:78:step-001:claim-01')
assert(quest_destinations[1].group_id == 'quest:windurst:78:step-001:claim-01:group:east')
assert(quest_destinations[1].guide_step_id == 'quest:windurst:78:step-001')
assert(quest_destinations[1].action_instruction == 'Defeat Test Enemy in the east camp.')
assert(quest_destinations[1].classification == 'catalogue-candidate')
assert(quest_destinations[1].arrival_instruction == 'Defeat Test Enemy in the east camp.')
assert(quest_destinations[1].route_ready == false)
assert(quest_destinations[2].label == 'Test Enemy west camp')
assert(quest_destinations[3].instruction_only == true)
assert(quest_destinations[3].classification == 'instruction-only')
assert(quest_destinations[3].candidate_id == '')
assert(quest_destinations[3].destination_id == '')
assert(quest_destinations[3].action_id == 'quest:windurst:78:step-002:claim-01')
assert(quest_destinations[3].guide_step_id == 'quest:windurst:78:step-002')
assert(quest_destinations[3].guide_step_order == 2)
assert(quest_destinations[3].action_instruction == 'Wait for the test signal.')
assert(quest_destinations[3].route_ready == false)
assert(quest_destinations[3].group_id == '')
assert(quest_destinations[3].objective_route_contract_id == nil)
assert(quest_destinations[4].candidate_id == 'quest:windurst:78:step-003:claim-01:candidate:guide')
assert(quest_destinations[4].guide_step_order == 3)
quest_destinations[1].items[1] = 'caller mutation'
quest_destinations[1].source_revisions.bg = 9999
quest_destinations[1].target_point[1] = 9999
local fresh_quest_destinations = assert(guides:objective_destinations('quest:windurst:78'))
assert(fresh_quest_destinations[1].items[1] == 'Test Charm')
assert(fresh_quest_destinations[1].source_revisions.bg == 1001)
assert(fresh_quest_destinations[1].target_point[1] == 10)
assert(#guides:mission_destinations('quest:windurst:78') == 4)

local runtime_reconciliation = modules.fixture_reconcile_quest_runtime['quest:windurst:78']
local saved_candidates = runtime_reconciliation.objective_destination_candidates
runtime_reconciliation.objective_destination_candidates = {}
local empty_typed_rows = isolated_guides():objective_destinations('quest:windurst:78')
assert(#empty_typed_rows == 1 and empty_typed_rows[1].instruction_only == true,
    'an explicitly empty typed candidate table must not resurrect legacy rows')
runtime_reconciliation.objective_destination_candidates = saved_candidates

local function assert_no_instruction_only(rows, reason)
    assert(#rows == 3, reason)
    for _, row in ipairs(rows) do
        assert(row.instruction_only ~= true, reason)
    end
end

local instruction_ledger = runtime_reconciliation.action_resolution_ledger[2]
for field, invalid in pairs({
    status = 'catalogue-candidate',
    reason = 'unreviewed-prose',
    instruction = '',
    material = false,
    route_ready = true,
}) do
    local saved = instruction_ledger[field]
    instruction_ledger[field] = invalid
    assert_no_instruction_only(
        isolated_guides():objective_destinations('quest:windurst:78'),
        'invalid instruction-only ledger field must fail closed: ' .. field)
    instruction_ledger[field] = saved
end
local saved_instruction_candidate_ids = instruction_ledger.candidate_ids
instruction_ledger.candidate_ids = { 'quest:windurst:78:step-002:claim-01:candidate:invented' }
assert_no_instruction_only(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'instruction-only rows must have exactly zero candidate IDs')
instruction_ledger.candidate_ids = saved_instruction_candidate_ids
local saved_instruction_spans = instruction_ledger.source_action_span_ids
instruction_ledger.source_action_span_ids = {
    'quest:windurst:78:bg:step-002:action-01',
    'quest:windurst:78:bg:step-002:action-01',
}
assert_no_instruction_only(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'instruction-only source span ownership must be nonempty and unique')
instruction_ledger.source_action_span_ids = saved_instruction_spans
local saved_instruction_action = instruction_ledger.action
instruction_ledger.action = 'travel'
assert_no_instruction_only(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'instruction-only ledger action must match its exact typed claim')
instruction_ledger.action = saved_instruction_action

local candidates_before_shuffle = runtime_reconciliation.objective_destination_candidates
runtime_reconciliation.objective_destination_candidates = {
    candidates_before_shuffle[3], candidates_before_shuffle[2], candidates_before_shuffle[1],
}
local shuffled_destinations = isolated_guides():objective_destinations('quest:windurst:78')
assert(#shuffled_destinations == 4)
assert(shuffled_destinations[1].candidate_id == 'quest:windurst:78:step-001:claim-01:candidate:east')
assert(shuffled_destinations[2].candidate_id == 'quest:windurst:78:step-001:claim-01:candidate:west')
assert(shuffled_destinations[3].instruction_only == true)
assert(shuffled_destinations[4].candidate_id == 'quest:windurst:78:step-003:claim-01:candidate:guide')
runtime_reconciliation.objective_destination_candidates = candidates_before_shuffle

local function assert_only_west_for_first_action(rows, reason)
    local east = 0
    local west = 0
    for _, row in ipairs(rows) do
        if row.candidate_id == 'quest:windurst:78:step-001:claim-01:candidate:east' then east = east + 1 end
        if row.candidate_id == 'quest:windurst:78:step-001:claim-01:candidate:west' then west = west + 1 end
    end
    assert(east == 0 and west == 1, reason)
end

local ledger = runtime_reconciliation.action_resolution_ledger
local saved_candidate_ids = ledger[1].candidate_ids
ledger[1].candidate_ids = {}
local orphan_rows = isolated_guides():objective_destinations('quest:windurst:78')
assert(#orphan_rows == 2 and orphan_rows[1].instruction_only == true,
    'orphan candidates without a ledger owner must fail closed')
ledger[1].candidate_ids = saved_candidate_ids

local saved_ledger_four = ledger[4]
ledger[4] = {
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
assert_only_west_for_first_action(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'a candidate owned by multiple ledger rows must fail closed')
ledger[4] = saved_ledger_four

local saved_action = saved_candidates[1].action
saved_candidates[1].action = 'examine'
assert_only_west_for_first_action(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'candidate and ledger action mismatch must fail closed')
saved_candidates[1].action = saved_action

local saved_span_ids = saved_candidates[1].source_action_span_ids
saved_candidates[1].source_action_span_ids = { 'quest:windurst:78:bg:step-999:action-01' }
assert_only_west_for_first_action(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'candidate source spans outside its ledger owner must fail closed')
saved_candidates[1].source_action_span_ids = saved_span_ids

local saved_arrival_instruction = saved_candidates[1].arrival_instruction
saved_candidates[1].arrival_instruction = ''
assert_only_west_for_first_action(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'a typed candidate without its candidate-specific action instruction must fail closed')
saved_candidates[1].arrival_instruction = saved_arrival_instruction

local saved_step_four = runtime_reconciliation.steps[4]
runtime_reconciliation.steps[4] = {
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
local multiply_mapped_rows = isolated_guides():objective_destinations('quest:windurst:78')
local saw_first_action = false
for _, row in ipairs(multiply_mapped_rows) do
    if row.action_id == 'quest:windurst:78:step-001:claim-01' then saw_first_action = true end
end
assert(saw_first_action == false, 'an action mapped to multiple guide steps must fail closed')
runtime_reconciliation.steps[4] = saved_step_four

runtime_reconciliation.steps[4] = {
    stable_step_id = 'quest:windurst:78:step-099',
    order = 99,
    source_orders = { 1, 1 },
    comparison = 'corroborated',
    conflicting_fields = {},
    action = 'wait',
    typed_claims = {
        {
            stable_claim_id = 'quest:windurst:78:step-002:claim-01',
            order = 1,
            action = 'wait',
            relationship = 'instruction',
            target = '',
            target_kind = '',
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
assert_no_instruction_only(
    isolated_guides():objective_destinations('quest:windurst:78'),
    'instruction-only action mapped to multiple guide steps must fail closed')
runtime_reconciliation.steps[4] = saved_step_four

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
