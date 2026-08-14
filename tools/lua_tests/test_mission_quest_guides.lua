local module_path = assert(arg[1], 'missing mission/quest guide module path')
local manual_path = assert(arg[2], 'missing manual-step test path')

local module_loader_calls = {}
local current_identity = 'alpha:1001'
local identity_changes = 0
local task2_guide_failures = {}

local function task2_guide_expect(value, message)
    if value ~= true then
        task2_guide_failures[#task2_guide_failures + 1] = message
    end
end

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
    ['mission:Bastok:99'] = {
        kind = 'mission',
        context = 'Bastok',
        native_id = 99,
        title = 'Optional Guidance Policy Fixture',
        status = 'guide',
        source_modules = {
            bg = 'fixture_bg_optional_policy',
            ffxiclopedia = 'fixture_ffxiclopedia_optional_policy',
        },
        reconcile_module = 'fixture_reconcile_optional_policy',
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

for _, row in pairs(index) do
    row.source_authority = { primary = 'bg', fallback = 'ffxiclopedia' }
    row.progression_schema_version = 1
    row.progression_revision = 'fixture-progression-revision'
end

local modules = {
    fixture_bg_mission_bastok = {
        ['mission:Bastok:2'] = {
            steps = {
                { order = 1, instruction = 'Talk to Cid in the Metalworks.', action = 'talk', items = { 'Blue Tester' } },
                {
                    order = 2,
                    instruction = 'BG says use the north geyser.',
                    action = 'examine',
                    entities = { 'North Geyser' },
                    zones = { 'Dangruf Wadi' },
                    grid_coordinates = { 'H-4' },
                    items = { 'Blue Tester' },
                },
                { order = 3, instruction = 'Return to Cid.', action = 'talk' },
            },
        },
    },
    fixture_ffxiclopedia_mission_bastok = {
        ['mission:Bastok:2'] = {
            steps = {
                { order = 1, instruction = 'Speak with Cid in the Metalworks.', action = 'talk' },
                {
                    order = 2,
                    instruction = 'FFXIclopedia says use the south geyser.',
                    action = 'talk',
                    entities = { 'South Geyser' },
                    zones = { 'Dangruf Wadi' },
                    grid_coordinates = { 'J-8' },
                    items = { 'Red Tester' },
                    key_items = { 'Geyser Key' },
                },
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
                    entities = { 'Cid', 'Metalworks' },
                    zones = { 'Metalworks' },
                    grid_coordinates = { 'H-8' },
                    items = { 'Blue Tester' },
                    key_items = {},
                    bg_instruction = 'Talk to Cid in the Metalworks.',
                    ffxiclopedia_instruction = 'Speak with Cid in the Metalworks.',
                    field_sources = {
                        action = 'bg',
                        entities = 'bg',
                        zones = 'bg',
                        grid_coordinates = 'bg',
                        items = 'bg',
                        instruction = 'bg',
                    },
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
                    conflicting_fields = {
                        'action', 'entities', 'grid_coordinates', 'items', 'instruction',
                    },
                    action = 'examine',
                    entities = { 'North Geyser' },
                    zones = { 'Dangruf Wadi' },
                    grid_coordinates = { 'H-4' },
                    items = { 'Blue Tester' },
                    key_items = { 'Geyser Key' },
                    bg_instruction = 'BG says use the north geyser.',
                    ffxiclopedia_instruction = 'FFXIclopedia says use the south geyser.',
                    field_sources = {
                        action = 'bg',
                        entities = 'bg',
                        zones = 'bg',
                        grid_coordinates = 'bg',
                        items = 'bg',
                        key_items = 'ffxiclopedia',
                        instruction = 'bg',
                    },
                    navigation_target = {
                        type = 'static-reference',
                        reference = {
                            zone = 191,
                            zone_name = 'Dangruf Wadi',
                            name = 'North Geyser',
                            kind = 'object',
                        },
                        arrival_instruction = 'Examine North Geyser.',
                    },
                    route_ready = false,
                },
                {
                    stable_step_id = 'mission:Bastok:2:step-003',
                    order = 3,
                    source_orders = { 3, 0 },
                    comparison = 'single-source',
                    conflicting_fields = {},
                    action = 'talk',
                    bg_instruction = 'Return to Cid.',
                    ffxiclopedia_instruction = '',
                    field_sources = {
                        action = 'bg',
                        instruction = 'bg',
                    },
                    route_ready = false,
                },
            },
        },
    },
    fixture_bg_optional_policy = {
        ['mission:Bastok:99'] = { steps = {
            { order = 1, instruction = 'Talk to the required mission NPC.', action = 'talk' },
            { order = 2, instruction = 'Optionally, obtain the Map of Test Cavern from a treasure chest.', action = 'obtain', items = { 'Map of Test Cavern' } },
            { order = 3, instruction = 'Optional shortcut: use the Survival Guide warp for the fastest route.', action = 'travel' },
            { order = 4, instruction = 'Precaution: You may want to bring Silent Oil to prevent aggro from funguars.', action = 'obtain' },
            { order = 5, instruction = 'Optional: talk to the bystander for extra dialogue.', action = 'talk' },
            { order = 6, instruction = 'Talk to the required field NPC.', action = 'talk' },
        } },
    },
    fixture_ffxiclopedia_optional_policy = {
        ['mission:Bastok:99'] = { steps = {
            { order = 1, instruction = 'Talk to the required mission NPC.', action = 'talk' },
            { order = 2, instruction = 'Optionally, obtain the Map of Test Cavern.', action = 'obtain', items = { 'Map of Test Cavern' } },
            { order = 3, instruction = 'Optional shortcut: use the Survival Guide warp.', action = 'travel' },
            { order = 4, instruction = 'Recommended: carry Silent Oil to avoid sound aggro.', action = 'obtain' },
            { order = 5, instruction = 'Optional non-essential dialogue.', action = 'talk' },
            { order = 6, instruction = 'Talk to the required field NPC.', action = 'talk' },
        } },
    },
    fixture_reconcile_optional_policy = {
        ['mission:Bastok:99'] = { steps = {
            { stable_step_id = 'mission:Bastok:99:step-001', order = 1, source_orders = { 1, 1 }, comparison = 'corroborated', action = 'talk', entities = { 'Required NPC' }, route_ready = false },
            { stable_step_id = 'mission:Bastok:99:step-002', order = 2, source_orders = { 2, 2 }, comparison = 'corroborated', action = 'obtain', entities = { 'Map of Test Cavern' }, route_ready = false },
            { stable_step_id = 'mission:Bastok:99:step-003', order = 3, source_orders = { 3, 3 }, comparison = 'corroborated', action = 'travel', entities = { 'Survival Guide' }, route_ready = false },
            { stable_step_id = 'mission:Bastok:99:step-004', order = 4, source_orders = { 4, 4 }, comparison = 'corroborated', action = 'obtain', entities = { 'Silent Oil', 'funguars' }, route_ready = false },
            { stable_step_id = 'mission:Bastok:99:step-005', order = 5, source_orders = { 5, 5 }, comparison = 'corroborated', action = 'talk', entities = { 'Bystander' }, route_ready = false },
            { stable_step_id = 'mission:Bastok:99:step-006', order = 6, source_orders = { 6, 6 }, comparison = 'corroborated', action = 'talk', entities = { 'Required field NPC' }, route_ready = true },
        } },
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

do
    local saved_authority = index['mission:Bastok:2'].source_authority
    index['mission:Bastok:2'].source_authority = nil
    local unavailable, authority_reason = isolated_guides():resolve('mission:Bastok:2')
    task2_guide_expect(unavailable == nil
        and tostring(authority_reason):lower():find('source authority', 1, true) ~= nil,
        'a guide without explicit BG-primary/FFXIclopedia-fallback authority did not fail closed')
    index['mission:Bastok:2'].source_authority = saved_authority
end

-- The reducer-facing guide seam consumes only Task 1's final compact action
-- arrays.  It must not resolve or retain the much larger source/reconciliation
-- modules merely to identify active progression actions.
do
    local compact_index = {}
    local compact_modules = {}
    local compact_objectives = {}
    local compact_loader_calls = 0
    local compact_loader_by_name = {}
    local full_loader_calls = 0
    local revision = string.rep('a', 64)
    for number = 1001, 1070 do
        local native_key = 'mission:Bastok:' .. tostring(number)
        local module_number = math.floor((number - 1001) / 12) + 1
        local progression_module = 'fixture_compact_progression_' .. tostring(module_number)
        if compact_modules[progression_module] == nil then
            compact_modules[progression_module] = {
                schema_version = 1,
                module_name = progression_module,
                source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
                objectives = {},
            }
        end
        compact_index[native_key] = {
            kind = 'mission',
            context = 'Bastok',
            native_id = number,
            title = 'Compact progression fixture ' .. tostring(number),
            status = 'guide',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
            source_modules = {
                bg = 'fixture_full_bg',
                ffxiclopedia = 'fixture_full_ffxiclopedia',
            },
            reconcile_module = 'fixture_full_reconcile',
            progression_module = progression_module,
            progression_schema_version = 1,
            progression_revision = revision,
        }
        local compact_objective = {
            native_key = native_key,
            progression_module = progression_module,
            progression_schema_version = 1,
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
            progression_revision = revision,
            progression_actions = {
                {
                    step_id = native_key .. ':step-001',
                    step_order = 1,
                    action_id = native_key .. ':step-001:claim-01',
                    action_order = 1,
                    order = 1,
                    action = 'talk',
                    relationship = 'talk-to',
                    target = 'Compact NPC ' .. tostring(number),
                    target_key = ('compactnpc%d'):format(number),
                    target_kind = 'npc',
                    npcs = { 'Compact NPC ' .. tostring(number) },
                    objects = {},
                    enemies = {},
                    zones = { 'Metalworks' },
                    items = {},
                    key_items = {},
                    transports = {},
                    grid_coordinates = {},
                    result_items = {},
                    result_relation = '',
                    field_sources = {
                        action = 'bg',
                        relationship = 'bg',
                        target = 'bg',
                        target_key = 'bg',
                        target_kind = 'bg',
                        npcs = 'bg',
                        objects = 'bg',
                        enemies = 'bg',
                        zones = 'bg',
                        items = 'bg',
                        key_items = 'bg',
                        transports = 'bg',
                        grid_coordinates = 'bg',
                        result_items = 'bg',
                        result_relation = 'bg',
                        instruction = 'bg',
                        count_mode = 'default',
                        required_count = 'default',
                        count_explicit = 'default',
                        catalogue = 'catalogue',
                    },
                    source_revisions = { bg = 4001, ffxiclopedia = 4002 },
                    source_action_span_ids = {
                        native_key .. ':bg:step-001:action-01',
                        native_key .. ':ffxiclopedia:step-001:action-01',
                    },
                    catalogue = {
                        {
                            destination_id = 'npc:v1:237:' .. tostring(17000000 + number),
                            zone_id = 237,
                            zone_name = 'Metalworks',
                            target_name = 'Compact NPC ' .. tostring(number),
                            target_kind = 'npc',
                            target_key = ('compactnpc%d'):format(number),
                            target_point = { number, number + 1, 0 },
                            raw_identity = 'fixture:npc:' .. tostring(number),
                            raw_spawn_ids = { 17000000 + number },
                            cluster_policy_version = '',
                            transport_id = '', battlefield_id = '', metadata_class = '',
                            group_id = native_key .. ':step-001:claim-01:zone:237',
                            arrival_instruction = 'Talk to the compact progression fixture.',
                        },
                    },
                    instruction = 'Talk to the compact progression fixture.',
                    count_mode = 'single',
                    required_count = 1,
                    count_explicit = false,
                    material = true,
                    source_authority = 'bg',
                },
            },
        }
        compact_objectives[native_key] = compact_objective
        compact_modules[progression_module].objectives[native_key] = compact_objective
    end
    local counted_key = 'mission:Bastok:1001'
    table.insert(compact_objectives[counted_key].progression_actions, 1, {
        step_id = counted_key .. ':step-002',
        step_order = 2,
        action_id = counted_key .. ':step-002:claim-01',
        action_order = 1,
        order = 2,
        action = 'fight',
        relationship = 'defeat-enemy',
        target = 'Thirty Test Enemies',
        target_key = 'thirtytestenemies',
        target_kind = 'enemy',
        npcs = {},
        objects = {},
        enemies = { 'Thirty Test Enemies' },
        zones = { 'Ghelsba Outpost' },
        items = {},
        key_items = {},
        transports = {},
        grid_coordinates = {},
        result_items = {},
        result_relation = '',
        field_sources = {
            action = 'bg',
            relationship = 'bg',
            target = 'bg',
            target_key = 'bg',
            target_kind = 'bg',
            npcs = 'bg', objects = 'bg', enemies = 'bg',
            zones = 'bg',
            items = 'bg', key_items = 'bg', transports = 'bg',
            grid_coordinates = 'bg', result_items = 'bg', result_relation = 'bg',
            instruction = 'bg',
            count_mode = 'bg',
            required_count = 'bg',
            count_explicit = 'bg', catalogue = 'catalogue',
        },
        source_revisions = { bg = 4001, ffxiclopedia = 4002 },
        source_action_span_ids = {
            counted_key .. ':bg:step-002:action-01',
            counted_key .. ':ffxiclopedia:step-002:action-01',
        },
        catalogue = {
            {
                destination_id = 'enemy:v1:140:task2-thirty-test-enemies',
                zone_id = 140, zone_name = 'Ghelsba Outpost',
                target_name = 'Thirty Test Enemies', target_kind = 'enemy',
                target_key = 'thirtytestenemies', target_point = { 10, 20, 0 },
                raw_identity = 'fixture:enemy:thirty-test-enemies',
                raw_spawn_ids = { 0x01020304, 0x01020305 },
                cluster_policy_version = 'complete-link-v1-h120-y24',
                transport_id = '', battlefield_id = '', metadata_class = '',
                group_id = counted_key .. ':step-002:claim-01:zone:140',
                arrival_instruction = 'Defeat thirty Test Enemies.',
            },
        },
        instruction = 'Defeat thirty Test Enemies.',
        count_mode = 'credited-defeat',
        required_count = 30,
        count_explicit = true,
        material = true,
        source_authority = 'bg',
    })
    table.insert(compact_objectives[counted_key].progression_actions, {
        step_id = counted_key .. ':step-003',
        step_order = 3,
        action_id = counted_key .. ':step-003:claim-01',
        action_order = 1,
        order = 3,
        action = 'obtain',
        relationship = 'obtain-item',
        target = 'Test Crystal',
        target_key = 'testcrystal',
        target_kind = 'item',
        npcs = {},
        objects = {},
        enemies = {},
        zones = {},
        items = { 'Test Crystal' },
        key_items = {},
        transports = {},
        grid_coordinates = {},
        result_items = { 'Test Crystal' },
        result_relation = 'obtain',
        field_sources = {
            action = 'bg',
            relationship = 'bg',
            target = 'bg',
            target_key = 'bg',
            target_kind = 'bg',
            npcs = 'bg', objects = 'bg', enemies = 'bg',
            items = 'bg',
            key_items = 'bg', transports = 'bg', zones = 'bg',
            grid_coordinates = 'bg', result_items = 'bg', result_relation = 'bg',
            instruction = 'bg',
            count_mode = 'bg',
            required_count = 'bg',
            count_explicit = 'bg', catalogue = '',
        },
        source_revisions = { bg = 4001, ffxiclopedia = 4002 },
        source_action_span_ids = {
            counted_key .. ':bg:step-003:action-01',
            counted_key .. ':ffxiclopedia:step-003:action-01',
        },
        catalogue = {},
        instruction = 'Obtain three Test Crystals.',
        count_mode = 'inventory-gain',
        required_count = 3,
        count_explicit = true,
        material = true,
        source_authority = 'bg',
    })

    local duplicate_key = 'mission:Bastok:1099'
    compact_index[duplicate_key] = {
        kind = 'mission',
        context = 'Bastok',
        native_id = 1099,
        title = 'Invalid duplicate progression fixture',
        status = 'guide',
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
        progression_module = 'fixture_compact_progression_1',
        progression_schema_version = 1,
        progression_revision = revision,
    }
    compact_objectives[duplicate_key] = {
        native_key = duplicate_key,
        progression_module = 'fixture_compact_progression_1',
        progression_schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
        progression_revision = revision,
        progression_actions = {
            {
                step_id = duplicate_key .. ':step-001', step_order = 1,
                action_id = duplicate_key .. ':step-001:claim-01', action_order = 1,
                order = 1,
                action = 'talk', relationship = 'talk-to',
                target = 'Duplicate NPC', target_key = 'duplicatenpc', target_kind = 'npc',
                npcs = { 'Duplicate NPC' }, objects = {}, enemies = {}, zones = {},
                items = {}, key_items = {}, transports = {}, grid_coordinates = {},
                result_items = {}, result_relation = '',
                field_sources = { action = 'bg', relationship = 'bg', target = 'bg',
                    target_key = 'bg', target_kind = 'bg', npcs = 'bg', objects = 'bg',
                    enemies = 'bg', zones = 'bg', items = 'bg', key_items = 'bg',
                    transports = 'bg', grid_coordinates = 'bg', result_items = 'bg',
                    result_relation = 'bg', instruction = 'bg', count_mode = 'default',
                    required_count = 'default', count_explicit = 'default', catalogue = '' },
                source_revisions = { bg = 4001, ffxiclopedia = 4002 },
                source_action_span_ids = { duplicate_key .. ':bg:step-001:action-01' },
                catalogue = {}, instruction = 'Talk once.', count_mode = 'single',
                required_count = 1, count_explicit = false, material = true,
                source_authority = 'bg',
            },
            {
                step_id = duplicate_key .. ':step-001', step_order = 1,
                action_id = duplicate_key .. ':step-001:claim-01', action_order = 1,
                order = 1,
                action = 'talk', relationship = 'talk-to',
                target = 'Duplicate NPC', target_key = 'duplicatenpc', target_kind = 'npc',
                npcs = { 'Duplicate NPC' }, objects = {}, enemies = {}, zones = {},
                items = {}, key_items = {}, transports = {}, grid_coordinates = {},
                result_items = {}, result_relation = '',
                field_sources = { action = 'bg', relationship = 'bg', target = 'bg',
                    target_key = 'bg', target_kind = 'bg', npcs = 'bg', objects = 'bg',
                    enemies = 'bg', zones = 'bg', items = 'bg', key_items = 'bg',
                    transports = 'bg', grid_coordinates = 'bg', result_items = 'bg',
                    result_relation = 'bg', instruction = 'bg', count_mode = 'default',
                    required_count = 'default', count_explicit = 'default', catalogue = '' },
                source_revisions = { bg = 4001, ffxiclopedia = 4002 },
                source_action_span_ids = { duplicate_key .. ':bg:step-001:action-01' },
                catalogue = {}, instruction = 'Talk twice.', count_mode = 'single',
                required_count = 1, count_explicit = false, material = true,
                source_authority = 'bg',
            },
        },
    }
    compact_modules.fixture_compact_progression_1.objectives[duplicate_key]
        = compact_objectives[duplicate_key]

    local missing_shard_key = 'mission:Bastok:1096'
    compact_index[missing_shard_key] = {
        kind = 'mission', context = 'Bastok', native_id = 1096,
        title = 'Missing compact shard fixture', status = 'guide',
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
        progression_module = 'fixture_missing_compact_progression',
        progression_schema_version = 1,
        progression_revision = revision,
    }
    local missing_objective_key = 'mission:Bastok:1097'
    compact_index[missing_objective_key] = {
        kind = 'mission', context = 'Bastok', native_id = 1097,
        title = 'Missing compact objective fixture', status = 'guide',
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
        progression_module = 'fixture_compact_progression_1',
        progression_schema_version = 1,
        progression_revision = revision,
    }
    local mismatched_revision_key = 'mission:Bastok:1098'
    compact_index[mismatched_revision_key] = {
        kind = 'mission', context = 'Bastok', native_id = 1098,
        title = 'Mismatched compact revision fixture', status = 'guide',
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
        progression_module = 'fixture_compact_progression_1',
        progression_schema_version = 1,
        progression_revision = revision,
    }
    compact_objectives[mismatched_revision_key] = {
        native_key = mismatched_revision_key,
        progression_module = 'fixture_compact_progression_1',
        progression_schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
        progression_revision = string.rep('b', 64),
        progression_actions = {
            {
                step_id = mismatched_revision_key .. ':step-001', step_order = 1,
                action_id = mismatched_revision_key .. ':step-001:claim-01', action_order = 1,
                order = 1,
                action = 'talk', relationship = 'talk-to',
                target = 'Revision NPC', target_key = 'revisionnpc', target_kind = 'npc',
                npcs = { 'Revision NPC' }, objects = {}, enemies = {}, zones = {},
                items = {}, key_items = {}, transports = {}, grid_coordinates = {},
                result_items = {}, result_relation = '',
                field_sources = { action = 'bg', relationship = 'bg', target = 'bg',
                    target_key = 'bg', target_kind = 'bg', npcs = 'bg', objects = 'bg',
                    enemies = 'bg', zones = 'bg', items = 'bg', key_items = 'bg',
                    transports = 'bg', grid_coordinates = 'bg', result_items = 'bg',
                    result_relation = 'bg', instruction = 'bg', count_mode = 'default',
                    required_count = 'default', count_explicit = 'default', catalogue = '' },
                source_revisions = { bg = 4001, ffxiclopedia = 4002 },
                source_action_span_ids = { mismatched_revision_key .. ':bg:step-001:action-01' },
                catalogue = {}, instruction = 'Talk to Revision NPC.', count_mode = 'single',
                required_count = 1, count_explicit = false, material = true,
                source_authority = 'bg',
            },
        },
    }
    compact_modules.fixture_compact_progression_1.objectives[mismatched_revision_key]
        = compact_objectives[mismatched_revision_key]

    local function invalid_action(native_key, values)
        values = values or {}
        local action = values.action or 'talk'
        local relationship = values.relationship or 'talk-to'
        local target_kind = values.target_kind or 'npc'
        local target = values.target or 'Invalid Fixture NPC'
        local target_key = target:lower():gsub('[^%w]', '')
        local row = {
            step_id = native_key .. ':step-001', step_order = 1,
            action_id = native_key .. ':step-001:claim-01', action_order = 1,
            order = 1,
            action = action, relationship = relationship,
            target = target, target_key = target_key, target_kind = target_kind,
            npcs = target_kind == 'npc' and { target } or {},
            objects = target_kind == 'object' and { target } or {},
            enemies = target_kind == 'enemy' and { target } or {},
            zones = values.zones or {},
            items = values.items or {},
            key_items = values.key_items or {},
            transports = values.transports or {},
            grid_coordinates = values.grid_coordinates or {},
            result_items = values.result_items or {},
            result_relation = values.result_relation or '',
            field_sources = {
                action = 'bg', relationship = 'bg', target = 'bg', target_key = 'bg',
                target_kind = 'bg', npcs = 'bg', objects = 'bg', enemies = 'bg',
                zones = 'bg', items = 'bg', key_items = 'bg', transports = 'bg',
                grid_coordinates = 'bg', result_items = 'bg', result_relation = 'bg',
                instruction = 'bg', count_mode = 'bg', required_count = 'bg',
                count_explicit = 'bg', catalogue = '',
            },
            source_revisions = { bg = 4001, ffxiclopedia = 4002 },
            source_action_span_ids = { native_key .. ':bg:step-001:action-01' },
            catalogue = {},
            instruction = 'Exercise an invalid compact schema row.',
            count_mode = values.count_mode or 'single',
            required_count = values.required_count == nil and 1 or values.required_count,
            count_explicit = values.count_explicit == true,
            material = true,
            source_authority = 'bg',
        }
        if values.omit_relationship == true then row.relationship = nil end
        if values.omit_target_key == true then row.target_key = nil end
        return row
    end

    local function add_invalid_shard(native_id, suffix, envelope, action_values)
        local native_key = 'mission:Bastok:' .. tostring(native_id)
        local module_name = 'fixture_invalid_compact_' .. suffix
        compact_index[native_key] = {
            kind = 'mission', context = 'Bastok', native_id = native_id,
            title = 'Invalid compact ' .. suffix, status = 'guide',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
            progression_module = module_name,
            progression_schema_version = 1,
            progression_revision = revision,
        }
        if envelope.module_name == nil then envelope.module_name = module_name end
        envelope.objectives = envelope.objectives or {}
        envelope.objectives[native_key] = {
            native_key = native_key,
            progression_module = module_name,
            progression_schema_version = 1,
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
            progression_revision = revision,
            progression_actions = { invalid_action(native_key, action_values) },
        }
        compact_modules[module_name] = envelope
        return native_key
    end

    local invalid_schema_missing_key = add_invalid_shard(1100, 'schema-missing', {
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    })
    local invalid_schema_mismatch_key = add_invalid_shard(1101, 'schema-mismatch', {
        schema_version = 2,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    })
    local invalid_authority_missing_key = add_invalid_shard(1102, 'authority-missing', {
        schema_version = 1,
    })
    local invalid_authority_mismatch_key = add_invalid_shard(1103, 'authority-mismatch', {
        schema_version = 1,
        source_authority = { primary = 'ffxiclopedia', fallback = 'bg' },
    })
    local invalid_count_zero_key = add_invalid_shard(1104, 'count-zero', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { required_count = 0, count_explicit = true })
    local invalid_count_fraction_key = add_invalid_shard(1105, 'count-fraction', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { required_count = 1.5, count_explicit = true })
    local invalid_count_mode_key = add_invalid_shard(1106, 'count-mode', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { action = 'talk', relationship = 'talk-to', count_mode = 'credited-defeat',
        required_count = 5, count_explicit = true })
    local invalid_inventory_mode_key = add_invalid_shard(1107, 'inventory-mode', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { action = 'fight', relationship = 'defeat-enemy', target_kind = 'enemy',
        count_mode = 'inventory-gain', required_count = 3, count_explicit = true })
    local invalid_key_item_mode_key = add_invalid_shard(1108, 'key-item-mode', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { action = 'obtain', relationship = 'obtain-key-item', target_kind = 'key-item',
        key_items = { 'Invalid Fixture Key Item' }, count_mode = 'inventory-gain',
        required_count = 3, count_explicit = true })
    local invalid_single_count_key = add_invalid_shard(1109, 'single-count', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { count_mode = 'single', required_count = 2, count_explicit = true })
    local invalid_unknown_mode_key = add_invalid_shard(1110, 'unknown-mode', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { count_mode = 'observation-count', required_count = 2, count_explicit = true })
    local invalid_relationship_key = add_invalid_shard(1111, 'relationship-missing', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { omit_relationship = true })
    local invalid_target_key = add_invalid_shard(1112, 'target-key-missing', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    }, { omit_target_key = true })
    local invalid_module_name_key = add_invalid_shard(1113, 'module-name', {
        schema_version = 1,
        module_name = 'fixture_wrong_progression_module',
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    })
    local invalid_index_schema_key = add_invalid_shard(1114, 'index-schema', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    })
    compact_index[invalid_index_schema_key].progression_schema_version = 2
    local invalid_native_pin_key = add_invalid_shard(1115, 'native-pin', {
        schema_version = 1,
        source_authority = { primary = 'bg', fallback = 'ffxiclopedia' },
    })
    compact_modules[compact_index[invalid_native_pin_key].progression_module]
        .objectives[invalid_native_pin_key].native_key = 'mission:Bastok:9999'

    local compact_guides = guide_module.new({
        index = compact_index,
        identity_provider = function() return current_identity end,
        manual_path = '',
        module_loader = function(name)
            if compact_modules[name] ~= nil then
                compact_loader_calls = compact_loader_calls + 1
                compact_loader_by_name[name] = (compact_loader_by_name[name] or 0) + 1
                return compact_modules[name]
            end
            if name == 'fixture_missing_compact_progression' then
                compact_loader_calls = compact_loader_calls + 1
                return nil
            end
            full_loader_calls = full_loader_calls + 1
            error('full source module must not load on the reducer path: ' .. tostring(name))
        end,
    })
    if type(compact_guides.progression_actions) ~= 'function' then
        task2_guide_failures[#task2_guide_failures + 1]
            = 'GuideState:progression_actions production seam is missing'
    elseif type(compact_guides.retain_progression_keys) ~= 'function' then
        task2_guide_failures[#task2_guide_failures + 1]
            = 'GuideState:retain_progression_keys bounded-cache seam is missing'
    else
        local ok, counted_actions = pcall(function()
            return compact_guides:progression_actions(counted_key)
        end)
        task2_guide_expect(ok and type(counted_actions) == 'table'
            and #counted_actions == 3,
            'compact progression schema did not expose three deterministic material actions')
        if ok and type(counted_actions) == 'table' and #counted_actions == 3 then
            task2_guide_expect(counted_actions[1].step_order == 1
                and counted_actions[1].action_order == 1
                and counted_actions[1].order == 1
                and counted_actions[1].count_mode == 'single'
                and counted_actions[1].required_count == 1
                and counted_actions[2].step_order == 2
                and counted_actions[2].action_order == 1
                and counted_actions[2].order == 2
                and counted_actions[2].action == 'fight'
                and counted_actions[2].relationship == 'defeat-enemy'
                and counted_actions[2].matcher == nil
                and counted_actions[2].target == 'Thirty Test Enemies'
                and counted_actions[2].target_key == 'thirtytestenemies'
                and counted_actions[2].enemies[1] == 'Thirty Test Enemies'
                and counted_actions[2].count_mode == 'credited-defeat'
                and counted_actions[2].required_count == 30
                and counted_actions[2].count_explicit == true
                and counted_actions[2].material == true
                and counted_actions[2].source_authority == 'bg'
                and counted_actions[2].zones[1] == 'Ghelsba Outpost'
                and counted_actions[2].field_sources.required_count == 'bg'
                and counted_actions[2].source_revisions.bg == 4001
                and counted_actions[2].source_revisions.ffxiclopedia == 4002
                and counted_actions[2].source_action_span_ids[1]
                    == counted_key .. ':bg:step-002:action-01'
                and counted_actions[2].catalogue[1].zone_id == 140
                and counted_actions[2].catalogue[1].target_name == 'Thirty Test Enemies'
                and counted_actions[2].catalogue[1].raw_spawn_ids[1] == 0x01020304
                and counted_actions[3].step_order == 3
                and counted_actions[3].order == 3
                and counted_actions[3].count_mode == 'inventory-gain'
                and counted_actions[3].required_count == 3
                and counted_actions[3].count_explicit == true
                and counted_actions[3].items[1] == 'Test Crystal'
                and counted_actions[3].result_items[1] == 'Test Crystal'
                and counted_actions[3].result_relation == 'obtain',
                'compact actions were not sorted or did not preserve single/counting semantics')
            counted_actions[1].target = 'caller mutation'
            counted_actions[2].catalogue[1].target_point[1] = 999
            counted_actions[2].source_revisions.bg = 0
            counted_actions[2].source_action_span_ids[1] = 'caller span mutation'
            counted_actions[3].items[1] = 'caller nested mutation'
            local fresh_actions = compact_guides:progression_actions(counted_key)
            task2_guide_expect(type(fresh_actions) == 'table'
                and fresh_actions[1].target == 'Compact NPC 1001'
                and fresh_actions[2].catalogue[1].target_point[1] == 10
                and fresh_actions[2].source_revisions.bg == 4001
                and fresh_actions[2].source_action_span_ids[1]
                    == counted_key .. ':bg:step-002:action-01'
                and fresh_actions[3].items[1] == 'Test Crystal',
                'progression_actions returned a mutable cache-owned action row')
        end

        local duplicate_actions, duplicate_reason
        ok, duplicate_actions, duplicate_reason = pcall(function()
            return compact_guides:progression_actions(duplicate_key)
        end)
        task2_guide_expect(ok and (duplicate_actions == nil or #duplicate_actions == 0)
            and tostring(duplicate_reason):lower():find('duplicate', 1, true) ~= nil,
            'duplicate compact action IDs/orders did not fail closed')

        for _, invalid in ipairs({
            { key = missing_shard_key, token = 'module', label = 'missing compact shard' },
            { key = missing_objective_key, token = 'objective', label = 'missing compact objective key' },
            { key = mismatched_revision_key, token = 'revision', label = 'compact revision self-pin mismatch' },
            { key = invalid_schema_missing_key, token = 'schema', label = 'missing compact schema self-pin' },
            { key = invalid_schema_mismatch_key, token = 'schema', label = 'mismatched compact schema self-pin' },
            { key = invalid_authority_missing_key, token = 'authority', label = 'missing shard authority self-pin' },
            { key = invalid_authority_mismatch_key, token = 'authority', label = 'mismatched shard authority self-pin' },
            { key = invalid_count_zero_key, token = 'count', label = 'zero required_count' },
            { key = invalid_count_fraction_key, token = 'count', label = 'fractional required_count' },
            { key = invalid_count_mode_key, token = 'count', label = 'credited-defeat on non-fight action' },
            { key = invalid_inventory_mode_key, token = 'count', label = 'inventory-gain on non-item action' },
            { key = invalid_key_item_mode_key, token = 'count', label = 'inventory-gain on key-item action' },
            { key = invalid_single_count_key, token = 'count', label = 'single mode with repeated count' },
            { key = invalid_unknown_mode_key, token = 'count', label = 'unknown count mode' },
            { key = invalid_relationship_key, token = 'relationship', label = 'missing relationship' },
            { key = invalid_target_key, token = 'target', label = 'missing normalized target key' },
            { key = invalid_module_name_key, token = 'module', label = 'mismatched shard module self-pin' },
            { key = invalid_index_schema_key, token = 'schema', label = 'index schema mismatch' },
            { key = invalid_native_pin_key, token = 'native', label = 'objective native-key self-pin mismatch' },
        }) do
            local invalid_actions, invalid_reason
            ok, invalid_actions, invalid_reason = pcall(function()
                return compact_guides:progression_actions(invalid.key)
            end)
            task2_guide_expect(ok and (invalid_actions == nil or #invalid_actions == 0)
                and tostring(invalid_reason):lower():find(invalid.token, 1, true) ~= nil,
                invalid.label .. ' did not fail closed')
        end

        for number = 1002, 1070 do
            local actions_ok, actions = pcall(function()
                return compact_guides:progression_actions(
                    'mission:Bastok:' .. tostring(number))
            end)
            task2_guide_expect(actions_ok and type(actions) == 'table' and #actions == 1,
                'compact progression action load failed for cache fixture ' .. tostring(number))
        end
        local retained_ok, retained_count = pcall(function()
            return compact_guides:retain_progression_keys({
                ['mission:Bastok:1069'] = true,
                ['mission:Bastok:1070'] = true,
            })
        end)
        task2_guide_expect(retained_ok and type(retained_count) == 'number'
            and retained_count >= 0 and retained_count <= 64,
            'progression action cache did not report a bounded retained count of at most 64')
        local active_module_name = 'fixture_compact_progression_6'
        local active_loads_before_reuse = compact_loader_by_name[active_module_name] or 0
        local active_a = compact_guides:progression_actions('mission:Bastok:1069')
        local active_b = compact_guides:progression_actions('mission:Bastok:1070')
        task2_guide_expect(type(active_a) == 'table' and #active_a == 1
                and type(active_b) == 'table' and #active_b == 1
                and (compact_loader_by_name[active_module_name] or 0)
                    == active_loads_before_reuse,
            'retain_progression_keys evicted an active objective before LRU extras')
        local oldest_module_name = 'fixture_compact_progression_1'
        local oldest_loads_before_reload = compact_loader_by_name[oldest_module_name] or 0
        local oldest_ok, oldest_actions = pcall(function()
            return compact_guides:progression_actions(counted_key)
        end)
        task2_guide_expect(oldest_ok and type(oldest_actions) == 'table'
                and #oldest_actions == 3
                and (compact_loader_by_name[oldest_module_name] or 0)
                    == oldest_loads_before_reload + 1,
            'oldest of six compact shards remained in an unbounded generic module cache')
        task2_guide_expect(full_loader_calls == 0,
            'active progression/cache path loaded a full BG/FFXIclopedia/reconciliation module')
        task2_guide_expect((compact_loader_by_name.fixture_compact_progression_6 or 0) >= 1,
            'six distinct compact shards were not exercised by the bounded-cache fixture')
    end
end

local optional_guides = isolated_guides()
local optional_objective = assert(optional_guides:open('mission:Bastok:99'))
assert(#optional_objective.steps == 3,
    'optional maps, side dialogue, and consumable pickups must not become guide steps')
assert(optional_objective.steps[1].stable_step_id == 'mission:Bastok:99:step-001')
assert(optional_objective.steps[2].stable_step_id == 'mission:Bastok:99:step-003')
assert(optional_objective.steps[3].stable_step_id == 'mission:Bastok:99:step-006')
assert(optional_objective.steps[2].primary_instruction:find('Shortcut.', 1, true) == 1,
    'an optional travel shortcut must remain visible and be labeled as a shortcut')
local optional_source_steps = optional_guides:source_route_steps('mission:Bastok:99')
assert(#optional_source_steps == 6,
    'filtering the spoken guide must retain the complete source-step record')
assert(optional_source_steps[2].optional_nonessential == true)
assert(optional_source_steps[4].route_recommendation == true)
assert(type(optional_guides.route_recommendations) == 'function',
    'guide state must expose route-time recommendations separately from objective steps')
local recommendations = optional_guides:route_recommendations('mission:Bastok:99', 6)
assert(#recommendations == 1 and recommendations[1].item == 'Silent Oil')
assert(recommendations[1].instruction
    == 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
    'Silent Oil must be a route-time use recommendation, not an acquisition objective')
assert(#optional_guides:route_recommendations('mission:Bastok:99', 5) == 0
    and #optional_guides:route_recommendations('mission:Bastok:99', 7) == 0,
    'a route recommendation must be spoken only for its first relevant route segment')
module_loader_calls = {}

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
        if native_key == 'mission:Bastok:2' and step_id == 'mission:Bastok:2:step-002'
            and type(reference) == 'table' and reference.zone == 191
            and reference.name == 'North Geyser' and reference.kind == 'object' then
            return {
                zone = 191,
                name = 'North Geyser',
                kind = 'object',
                x = 12.5,
                z = -30.25,
                mode = 'wiki-ready',
                objective_wiki_route = true,
                wiki_authoritative = true,
                verified = false,
            }
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
assert(#module_loader_calls == 1,
    'compact guide resolution must not load full BG or FFXIclopedia source modules')
assert(module_loader_calls[1] == 'fixture_reconcile_mission_bastok')
assert(guides:automatic_step_id('mission:Bastok:2', 'obtain-blue-tester') == 'mission:Bastok:2:step-001')
local source_steps = assert(guides:source_route_steps('mission:Bastok:2'))
assert(#source_steps == 3 and source_steps[1].entities[1] == 'Cid'
    and source_steps[1].zones[1] == 'Metalworks'
    and source_steps[1].grid_coordinates[1] == 'H-8'
    and source_steps[1].items[1] == 'Blue Tester',
    'source route steps must preserve the exact reconciled destination facts')
source_steps[1].entities[1] = 'caller mutation'
source_steps[1].items[1] = 'caller item mutation'
assert(guides:source_route_steps('mission:Bastok:2')[1].entities[1] == 'Cid',
    'source route steps must be deep-copy isolated')
assert(guides:source_route_steps('mission:Bastok:2')[1].items[1] == 'Blue Tester',
    'source route item requirements must be deep-copy isolated')
local authoritative_conflict = guides:source_route_steps('mission:Bastok:2')[2]
task2_guide_expect(type(authoritative_conflict) == 'table'
    and authoritative_conflict.action == 'examine',
    'BG action did not override conflicting reconciliation/FFXIclopedia actions')
task2_guide_expect(type(authoritative_conflict) == 'table'
    and #authoritative_conflict.entities == 1
    and authoritative_conflict.entities[1] == 'North Geyser',
    'BG entities were unioned with the conflicting FFXIclopedia target')
task2_guide_expect(type(authoritative_conflict) == 'table'
    and #authoritative_conflict.zones == 1
    and authoritative_conflict.zones[1] == 'Dangruf Wadi',
    'BG zone did not remain the authoritative runtime zone')
task2_guide_expect(type(authoritative_conflict) == 'table'
    and #authoritative_conflict.grid_coordinates == 1
    and authoritative_conflict.grid_coordinates[1] == 'H-4',
    'BG grid coordinate did not override the conflicting FFXIclopedia grid')
task2_guide_expect(type(authoritative_conflict) == 'table'
    and #authoritative_conflict.items == 1
    and authoritative_conflict.items[1] == 'Blue Tester',
    'BG item did not override the conflicting FFXIclopedia item')
task2_guide_expect(type(authoritative_conflict) == 'table'
    and #authoritative_conflict.key_items == 1
    and authoritative_conflict.key_items[1] == 'Geyser Key',
    'FFXIclopedia did not fill the key-item field missing from BG')
task2_guide_expect(type(authoritative_conflict) == 'table'
    and authoritative_conflict.primary_instruction == 'BG says use the north geyser.',
    'BG instruction did not remain primary during a source conflict')
local authoritative_sources = type(authoritative_conflict) == 'table'
    and authoritative_conflict.field_sources or nil
task2_guide_expect(type(authoritative_sources) == 'table'
    and authoritative_sources.action == 'bg'
    and authoritative_sources.entities == 'bg'
    and authoritative_sources.zones == 'bg'
    and authoritative_sources.grid_coordinates == 'bg'
    and authoritative_sources.items == 'bg'
    and authoritative_sources.key_items == 'ffxiclopedia'
    and authoritative_sources.instruction == 'bg',
    'resolved guide step did not expose per-field BG-primary/FFXIclopedia-fallback provenance')
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
assert(conflict_speech:find('BG says use the north geyser.', 1, true) ~= nil)
assert(conflict_speech:find('Source facts conflict.', 1, true) ~= nil)
local conflict_route = guides:route_descriptor()
task2_guide_expect(type(conflict_route) == 'table'
    and conflict_route.mode == 'wiki-ready'
    and conflict_route.objective_wiki_route == true
    and conflict_route.wiki_authoritative == true
    and conflict_route.verified ~= true
    and conflict_route.zone == 191
    and conflict_route.name == 'North Geyser'
    and conflict_route.kind == 'object'
    and type(conflict_route.x) == 'number' and conflict_route.x == conflict_route.x
    and math.abs(conflict_route.x) < math.huge
    and type(conflict_route.z) == 'number' and conflict_route.z == conflict_route.z
    and math.abs(conflict_route.z) < math.huge
    and conflict_route.objective_route_contract_id == nil,
    'authoritative conflicted wiki target was not exposed as an exact finite wiki-ready route')

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
assert(#task2_guide_failures == 0,
    'Task 2 wiki-authoritative guide REDs:\n- '
        .. table.concat(task2_guide_failures, '\n- '))
print('mission and quest guide tests passed')
