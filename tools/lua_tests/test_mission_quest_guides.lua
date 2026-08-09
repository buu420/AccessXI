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
local destinations = assert(guides:mission_destinations('mission:Bastok:2'))
assert(#destinations == 2)
assert(destinations[1].stable_id == 'mission:Bastok:2:palborough-lower-amber')
assert(destinations[2].transport_id == 'palborough-mines-lift')
destinations[1].items[1] = 'caller mutation'
destinations[1].source_step_ids[1] = 'caller mutation'
destinations[1].navigation_target.reference.name = 'caller mutation'
local fresh_destinations = assert(guides:mission_destinations('mission:Bastok:2'))
assert(fresh_destinations[1].items[1] == 'Fetich Head')
assert(fresh_destinations[1].source_step_ids[1] == 'mission:Bastok:2:step-001')
assert(fresh_destinations[1].navigation_target.reference.name == 'Amber Quadav')

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
