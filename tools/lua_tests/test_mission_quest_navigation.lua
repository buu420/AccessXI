local objectives_path = assert(arg[1], 'missing objectives module path')
local module_path = assert(arg[2], 'missing navigation module path')

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear() for index = #self, 1, -1 do self[index] = nil end end
T = function(values) return setmetatable(values or {}, { __index = list_methods }) end

local task2_red_failures = T{}
local function task2_expect(value, message)
    if (value ~= true) then task2_red_failures:append(message) end
end
local task2_reducer_failures = T{}
local function task2_reducer_expect(value, message)
    if (value ~= true) then task2_reducer_failures:append(message) end
end

string.fmt = function(self, ...) return string.format(self, ...) end
string.trim = function(self) return (self:gsub('^%s+', ''):gsub('%s+$', '')) end
string.eq = function(self, other, insensitive)
    if insensitive then return self:lower() == tostring(other or ''):lower() end
    return self == tostring(other or '')
end
string.contains = function(self, value) return self:find(value, 1, true) ~= nil end

bit = {}
function bit.lshift(value, shift) return (tonumber(value) or 0) * (2 ^ (tonumber(shift) or 0)) end
function bit.band(a, b)
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    local result = 0
    local place = 1
    for _ = 0, 31 do
        local aa = a % 2
        local bb = b % 2
        if aa == 1 and bb == 1 then result = result + place end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        place = place * 2
    end
    return result
end

local current_player = 'Alpha'
local current_identity = 'alpha:1001'
local current_nation = 1
local current_rank = 1
local current_rank_points = 0
local current_world_id = 1001
local current_session_epoch = 77
local objective_progress_path = os.tmpname()
os.remove(objective_progress_path)
local cancelled_objective_routes = 0
local runtime_authorize_calls = 0
local owned_key_items = {}
local objective_inventory_counts_by_name = {}
local objective_inventory_item_ids = {
    ['orcish axe'] = 16656,
    ['test crystal'] = 9999,
    ['orcish mail scales'] = 1112,
    ['fetich head'] = 1624,
    ['fetich torso'] = 1625,
    ['fetich arms'] = 1626,
    ['fetich legs'] = 1627,
}
local mission_values = {
    Bastok = 1,
    ['Rise of the Zilart'] = 2,
    ['Chains of Promathia'] = 0,
    Assault = 0,
    ['Treasures of Aht Urhgan'] = 0,
    ['Wings of the Goddess'] = 0,
    ['Seekers of Adoulin'] = 0,
    ["Rhapsodies of Vana'diel"] = 65535,
    ['The Voracious Resurgence'] = 188,
    ['A Crystalline Prophecy'] = 15,
    ["A Moogle Kupo d'Etat"] = 15,
    ['A Shantotto Ascension'] = 15,
}
local mission_value_packet_age = 10

local mission_rows = {
    ["San d'Oria"] = T{
        { label = 'Smash the Orcish Scouts', mission_id = 0, next_mission_id = 1 },
        { label = 'Bat Hunt', mission_id = 1, next_mission_id = 2 },
        { label = 'Save the Children', mission_id = 2, next_mission_id = 3 },
        { label = 'The Rescue Drill', mission_id = 3, next_mission_id = 4 },
    },
    Bastok = T{
        { label = 'The Zeruhn Report', mission_id = 0, next_mission_id = 1 },
        { label = 'A Geological Survey', mission_id = 1, next_mission_id = 2 },
        { label = 'Fetichism', mission_id = 2, next_mission_id = 3 },
    },
    ['Rise of the Zilart'] = T{
        { label = 'The New Frontier', mission_id = 1, next_mission_id = 2 },
        {
            label = "Welcome t'Norg",
            mission_id = 2,
            next_mission_id = 3,
            orders = 'Lion is waiting in the room at the end of the second-floor hallway in Norg.',
        },
        { label = "Kazham's Chieftainess", mission_id = 3, next_mission_id = 4 },
    },
    ["Rhapsodies of Vana'diel"] = T{
        { label = 'Rhapsodies of Vanadiel', mission_id = 0, next_mission_id = 1 },
    },
    ['The Voracious Resurgence'] = T{
        { label = 'False TVR mission from TalesBeginning bits', mission_id = 188, next_mission_id = 189 },
    },
}
for _, rows in pairs(mission_rows) do
    rows.count = #rows
    rows.by_mission_id = {}
    for ordinal, row in ipairs(rows) do
        row.rom_ordinal = ordinal
        rows.by_mission_id[row.mission_id] = row
    end
end

local quest_rows = {
    sandoria = {
        [2] = { id = 2, label = 'The Pickpocket', area = "San d'Oria", source = 'ROM test row 2' },
        [50] = { id = 50, label = 'Hotkey Packet Quest', area = "San d'Oria", source = 'RED cache packet row' },
        [200] = { id = 200, label = 'A Long Current Quest', area = "San d'Oria", source = 'ROM test row 200' },
    },
    aht_urhgan = {
        [100] = { id = 100, label = 'Safe Aht Urhgan Quest', area = 'Aht Urhgan', source = 'ROM test row 100' },
        [180] = { id = 180, label = 'Overlaid Mission Word', area = 'Aht Urhgan', source = 'ROM test row 180' },
    },
}

local function words_with(...)
    local words = T{ 0, 0, 0, 0, 0, 0, 0, 0 }
    for _, id in ipairs({ ... }) do
        local word_index = math.floor(id / 32) + 1
        local bit_index = id % 32
        words[word_index] = words[word_index] + (2 ^ bit_index)
    end
    return words
end

-- Match the heavily progressed live character that exposed the hotkey stall:
-- 54 active quest bits and the production-sized 42,366-point navigation catalog.
local hotkey_scale_sandoria_ids = { 2, 200 }
for quest_id = 60, 109 do
    quest_rows.sandoria[quest_id] = {
        id = quest_id,
        label = ('Scale Quest %d'):format(quest_id),
        area = "San d'Oria",
        source = 'hotkey scale fixture',
    }
    hotkey_scale_sandoria_ids[#hotkey_scale_sandoria_ids + 1] = quest_id
end

local quest_entries = {
    ['sandoria:current'] = { area_key = 'sandoria', mode = 'current', words = words_with(unpack(hotkey_scale_sandoria_ids)), source = 'packet_in_056', identity = current_identity, session_epoch = current_session_epoch },
    ['sandoria:completed'] = { area_key = 'sandoria', mode = 'completed', words = words_with(), source = 'packet_in_056', identity = current_identity, session_epoch = current_session_epoch },
    ['aht_urhgan:current'] = { area_key = 'aht_urhgan', mode = 'current', words = words_with(100, 180), source = 'packet_in_056', identity = current_identity, session_epoch = current_session_epoch },
    ['aht_urhgan:completed'] = { area_key = 'aht_urhgan', mode = 'completed', words = words_with(), source = 'packet_in_056', identity = current_identity, session_epoch = current_session_epoch },
}

local function deep_copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[deep_copy(key)] = deep_copy(item) end
    return setmetatable(result, getmetatable(value))
end

-- Candidate inputs mirror `_objective_candidate_lua` exactly. The three
-- guide_* fields are the validated GuideState annotations derived from the
-- action ledger and exact typed-claim step; contract IDs are deliberately absent.
local function guide_candidate(spec)
    return T{
        candidate_id = spec.candidate_id,
        action_id = spec.action_id,
        source_action_span_ids = spec.source_action_span_ids or T{ spec.action_id .. ':source-01' },
        source_sites = T{ 'bg', 'ffxiclopedia' },
        source_revisions = { bg = 1001, ffxiclopedia = 2002 },
        coordinate_support = T{},
        coordinate_comparison = 'game-data',
        action = spec.action,
        items = spec.items or T{},
        enemies = spec.enemies or T{},
        result_relation = spec.result_relation or '',
        destination_id = spec.destination_id,
        zone = spec.zone,
        zone_name = spec.zone_name,
        target_name = spec.target_name,
        target_kind = spec.target_kind,
        target_point = spec.target_point,
        raw_identity = spec.raw_identity,
        raw_spawn_ids = spec.raw_spawn_ids or T{},
        cluster_policy_version = spec.cluster_policy_version or '',
        evidence_level = 'dual-source-plus-game-data',
        group_id = spec.group_id,
        metadata_class = '',
        transport_id = spec.transport_id or '',
        battlefield_id = '',
        label = spec.label,
        arrival_instruction = spec.arrival_instruction,
        route_ready = false,
        classification = 'catalogue-candidate',
        guide_step_id = spec.guide_step_id,
        guide_step_order = spec.guide_step_order,
        action_instruction = spec.arrival_instruction,
    }
end

local function guide_instruction(action_id, guide_step_id, guide_step_order, instruction)
    return T{
        candidate_id = '',
        action_id = action_id,
        source_action_span_ids = T{ action_id .. ':source-01' },
        action = 'wait',
        status = 'instruction-only',
        reason = 'complete-instruction',
        material = true,
        group_id = '',
        destination_id = '',
        guide_step_id = guide_step_id,
        guide_step_order = guide_step_order,
        action_instruction = instruction,
        instruction_only = true,
        classification = 'instruction-only',
        route_ready = false,
    }
end

local guide_rows_by_native = {
    ["mission:San d'Oria:1"] = T{
        guide_candidate({
            candidate_id = "mission:San d'Oria:1:step-005:claim-01:candidate:west",
            action_id = "mission:San d'Oria:1:step-005:claim-01",
            group_id = "mission:San d'Oria:1:step-005:claim-01:group:west",
            destination_id = 'enemy:v1:100:orcish-west', action = 'fight',
            items = T{ 'Orcish Axe' }, enemies = T{ 'Orcish Fodder' }, result_relation = 'defeat-to-obtain',
            zone = 100, zone_name = 'West Ronfaure', target_name = 'Orcish Fodder', target_kind = 'enemy',
            target_point = T{ -20, -30, 0 }, raw_identity = 'lsb:mob_spawn_points:group:2:mobname:Orcish_Fodder',
            raw_spawn_ids = T{ 2 }, cluster_policy_version = 'complete-link-v1-h120-y24',
            label = 'Orcish Fodder west camp', arrival_instruction = 'Defeat Orcish Fodder in West Ronfaure and obtain an Orcish Axe.',
            guide_step_id = "mission:San d'Oria:1:step-005", guide_step_order = 5,
        }),
        guide_candidate({
            candidate_id = "mission:San d'Oria:1:step-005:claim-01:candidate:east",
            action_id = "mission:San d'Oria:1:step-005:claim-01",
            group_id = "mission:San d'Oria:1:step-005:claim-01:group:east",
            destination_id = 'enemy:v1:101:orcish-east', action = 'fight',
            items = T{ 'Orcish Axe' }, enemies = T{ 'Orcish Fodder' }, result_relation = 'defeat-to-obtain',
            zone = 101, zone_name = 'East Ronfaure', target_name = 'Orcish Fodder', target_kind = 'enemy',
            target_point = T{ 20, 30, 0 }, raw_identity = 'lsb:mob_spawn_points:group:2:mobname:Orcish_Fodder',
            raw_spawn_ids = T{ 1 }, cluster_policy_version = 'complete-link-v1-h120-y24',
            label = 'Orcish Fodder east camp', arrival_instruction = 'Defeat Orcish Fodder in East Ronfaure and obtain an Orcish Axe.',
            guide_step_id = "mission:San d'Oria:1:step-005", guide_step_order = 5,
        }),
        guide_candidate({
            candidate_id = "mission:San d'Oria:1:step-007:claim-01:candidate:ambrotien",
            action_id = "mission:San d'Oria:1:step-007:claim-01",
            group_id = '',
            destination_id = 'npc:v1:230:ambrotien', action = 'trade',
            items = T{ 'Orcish Axe' },
            zone = 230, zone_name = "Southern San d'Oria", target_name = 'Ambrotien', target_kind = 'npc',
            target_point = T{ 93.419, -57.347, 0.999 }, raw_identity = 'lsb:npc_list:ambrotien',
            label = 'Ambrotien', arrival_instruction = 'Return to a Gate Guard and trade the Orcish Axe to finish the mission.',
            guide_step_id = "mission:San d'Oria:1:step-007", guide_step_order = 7,
        }),
        guide_candidate({
            candidate_id = "mission:San d'Oria:1:step-007:claim-01:candidate:grilau",
            action_id = "mission:San d'Oria:1:step-007:claim-01",
            group_id = '',
            destination_id = 'npc:v1:231:grilau', action = 'trade',
            items = T{ 'Orcish Axe' },
            zone = 231, zone_name = "Northern San d'Oria", target_name = 'Grilau', target_kind = 'npc',
            target_point = T{ -241.987, 57.887, 7.999 }, raw_identity = 'lsb:npc_list:grilau',
            label = 'Grilau', arrival_instruction = 'Return to a Gate Guard and trade the Orcish Axe to finish the mission.',
            guide_step_id = "mission:San d'Oria:1:step-007", guide_step_order = 7,
        }),
    },
    ["mission:San d'Oria:3"] = T{
        guide_candidate({
            candidate_id = "mission:San d'Oria:3:step-002:claim-01:candidate:arnau",
            action_id = "mission:San d'Oria:3:step-002:claim-01",
            group_id = '',
            destination_id = 'npc:v1:231:17723406', action = 'talk',
            zone = 231, zone_name = "Northern San d'Oria", target_name = 'Arnau', target_kind = 'npc',
            target_point = T{ 149.892, 141.873, -0.601 }, raw_identity = 'lsb:npc_list:17723406',
            label = 'Arnau', arrival_instruction = 'Next speak to Arnau in the Cathedral in Northern San d\'Oria.',
            guide_step_id = "mission:San d'Oria:3:step-002", guide_step_order = 2,
        }),
    },
    ["mission:San d'Oria:4"] = T{
        guide_candidate({
            candidate_id = "mission:San d'Oria:4:step-006:claim-01:candidate:galaihaurat",
            action_id = "mission:San d'Oria:4:step-006:claim-01",
            group_id = '',
            destination_id = 'npc:v1:102:17195615', action = 'talk',
            zone = 102, zone_name = 'La Theine Plateau', target_name = 'Galaihaurat', target_kind = 'npc',
            target_point = T{ -481.196, 220.547, -7.028 }, raw_identity = 'lsb:npc_list:17195615',
            raw_spawn_ids = T{ 17195615 },
            label = 'Galaihaurat', arrival_instruction = 'Talk to Galaihaurat in La Theine Plateau.',
            guide_step_id = "mission:San d'Oria:4:step-006", guide_step_order = 6,
        }),
    },
    ['mission:Bastok:3'] = T{
        guide_candidate({
            candidate_id = 'mission:Bastok:3:step-006:claim-01:candidate:onyx-upper',
            action_id = 'mission:Bastok:3:step-006:claim-01',
            group_id = 'mission:Bastok:3:step-006:claim-01:group:upper',
            destination_id = 'enemy:v1:143:onyx-upper', action = 'fight',
            items = T{ 'Fetich Head', 'Fetich Torso', 'Fetich Arms', 'Fetich Legs' },
            enemies = T{ 'Greater Quadav', 'Onyx Quadav', 'Veteran Quadav' }, result_relation = 'defeat-to-obtain',
            zone = 143, zone_name = 'Palborough Mines', target_name = 'Onyx Quadav', target_kind = 'enemy',
            target_point = T{ 220.313, 88.193, -32.280 }, raw_identity = 'lsb:mob_spawn_points:group:3:mobname:Onyx_Quadav',
            raw_spawn_ids = T{ 3 }, cluster_policy_version = 'complete-link-v1-h120-y24', transport_id = 'palborough-mines-lift',
            label = 'upper camp by elevator', arrival_instruction = 'Farm Fetich pieces from Greater Quadav, Onyx Quadav, and Veteran Quadav in the upper camp by elevator.',
            guide_step_id = 'mission:Bastok:3:step-006', guide_step_order = 6,
        }),
        guide_candidate({
            candidate_id = 'mission:Bastok:3:step-006:claim-01:candidate:amber-lower',
            action_id = 'mission:Bastok:3:step-006:claim-01',
            group_id = 'mission:Bastok:3:step-006:claim-01:group:lower',
            destination_id = 'enemy:v1:143:amber-lower', action = 'fight',
            items = T{ 'Fetich Head', 'Fetich Torso', 'Fetich Arms', 'Fetich Legs' },
            enemies = T{ 'Amber Quadav' }, result_relation = 'defeat-to-obtain',
            zone = 143, zone_name = 'Palborough Mines', target_name = 'Amber Quadav', target_kind = 'enemy',
            target_point = T{ 142, 154, -0.076 }, raw_identity = 'lsb:mob_spawn_points:group:3:mobname:Amber_Quadav',
            raw_spawn_ids = T{ 4 }, cluster_policy_version = 'complete-link-v1-h120-y24',
            label = 'lower camp', arrival_instruction = 'Farm Fetich Head, Fetich Torso, Fetich Arms, and Fetich Legs from Amber Quadav in the lower camp.',
            guide_step_id = 'mission:Bastok:3:step-006', guide_step_order = 6,
        }),
    },
    ['quest:sandoria:2'] = T{
        guide_candidate({
            candidate_id = 'quest:sandoria:2:step-001:claim-01:candidate:unrelated',
            action_id = 'quest:sandoria:2:step-001:claim-01', group_id = '',
            destination_id = 'npc:v1:230:unrelated', action = 'talk', zone = 230, zone_name = "Southern San d'Oria",
            target_name = 'Unrelated NPC', target_kind = 'npc', target_point = T{ 1, 2, 3 },
            raw_identity = 'lsb:npc_list:999', label = 'unrelated stage', arrival_instruction = 'Talk to the unrelated NPC.',
            guide_step_id = 'quest:sandoria:2:step-001', guide_step_order = 1,
        }),
        guide_candidate({
            candidate_id = 'quest:sandoria:2:step-002:claim-01:candidate:cid',
            action_id = 'quest:sandoria:2:step-002:claim-01', group_id = '',
            destination_id = 'npc:v1:237:cid', action = 'talk', zone = 237, zone_name = 'Metalworks',
            target_name = 'Cid', target_kind = 'npc', target_point = T{ -12.598, 2.430, -10.988 },
            raw_identity = 'lsb:npc_list:17772593', label = 'Cid', arrival_instruction = 'Talk to Cid.',
            guide_step_id = 'quest:sandoria:2:step-002', guide_step_order = 2,
        }),
    },
    ['quest:sandoria:200'] = T{
        guide_instruction('quest:sandoria:200:step-004:claim-01', 'quest:sandoria:200:step-004', 4, 'Wait for the second signal.'),
        guide_instruction('quest:sandoria:200:step-003:claim-01', 'quest:sandoria:200:step-003', 3, 'Wait for the first signal.'),
    },
    ['mission:Bastok:2'] = T{
        T{ stable_id = 'unsafe-legacy-row', route_ready = true, route_evidence = 'legacy free text',
            arrival_instruction = 'Legacy text must never authorize movement.' },
    },
}

local runtime_contracts = {
    ['mission:Bastok:3:step-006:claim-01:candidate:amber-lower'] = {
        contract_id = 'route:v2:lower', route_ready = true,
        candidate_id = 'mission:Bastok:3:step-006:claim-01:candidate:amber-lower',
        action_id = 'mission:Bastok:3:step-006:claim-01',
        group_id = 'mission:Bastok:3:step-006:claim-01:group:lower',
        destination_id = 'enemy:v1:143:amber-lower',
        row = deep_copy(guide_rows_by_native['mission:Bastok:3'][2]),
    },
    ['mission:Bastok:3:step-006:claim-01:candidate:onyx-upper'] = {
        contract_id = 'route:v2:upper', route_ready = true,
        candidate_id = 'mission:Bastok:3:step-006:claim-01:candidate:onyx-upper',
        action_id = 'mission:Bastok:3:step-006:claim-01',
        group_id = 'mission:Bastok:3:step-006:claim-01:group:upper',
        destination_id = 'enemy:v1:143:onyx-upper',
        row = deep_copy(guide_rows_by_native['mission:Bastok:3'][1]),
    },
    ['quest:sandoria:2:step-002:claim-01:candidate:cid'] = {
        contract_id = 'route:v2:cid', route_ready = true,
        candidate_id = 'quest:sandoria:2:step-002:claim-01:candidate:cid',
        action_id = 'quest:sandoria:2:step-002:claim-01', group_id = '',
        destination_id = 'npc:v1:237:cid',
        row = deep_copy(guide_rows_by_native['quest:sandoria:2'][2]),
    },
}
local guide_row_mutator = nil

local logs = T{}
accessxi = {
    objective_interaction_progress_path = objective_progress_path,
    mission_quest_nav_player = 'Alpha',
    mission_quest_nav_identity = current_identity,
    mission_packet_player = 'Alpha',
    mission_packet_identity = current_identity,
    mission_packet_source = 'packet_in_056',
    mission_packet_session_epoch = current_session_epoch,
    mission_packet_ahturghan = {},
    mission_packet_ahturghan_identity = current_identity,
    mission_packet_ahturghan_source = 'packet_in_056',
    mission_packet_ahturghan_complete = {},
    mission_packet_nations_complete = words_with(),
    mission_packet_nations_complete_player = 'Alpha',
    mission_packet_nations_complete_identity = current_identity,
    mission_packet_nations_complete_source = 'packet_in_056',
    mission_packet_main = { nation = 1, nation_mission = 1, port = 0xFFFF },
    quest_packet_player = 'Alpha',
    quest_packet_identity = current_identity,
    quest_packet_source = 'packet_in_056',
    quest_packet_session_epoch = current_session_epoch,
    mission_packet_cache_loaded = true,
    mission_packet_tick = 100,
    quest_packet_logs = quest_entries,
    quest_packet_cache_loaded = true,
    quest_packet_tick = 100,
    key_items_packet_player = 'Alpha',
    key_items_packet_identity = current_identity,
    key_items_packet_tables = { [0] = { flags = string.rep('\0', 64), source = 'packet_in_055', identity = current_identity, session_epoch = current_session_epoch } },
    key_items_packet_cache_loaded = true,
    inventory_packet_source = 'packet_in_inventory',
    inventory_packet_identity = current_identity,
    inventory_packet_session_epoch = current_session_epoch,
    inventory_packet_key = 'inventory:hotkey-cache:1',
    key_items_packet_key = 'key-items:hotkey-cache:1',
    mission_packet_hex = 'mission-hotkey-cache-1',
    objective_progress_revision = 1,
    nav_catalog_revision = 1,
    last_native_inventory_item_tick = 100,
    hotkey_cache_destination_calls = 0,
    hotkey_cache_source_step_calls = 0,
    hotkey_cache_mission_state_calls = 0,
    hotkey_cache_quest_state_calls = 0,
    nav_points = T{
        T{ zone = 237, name = 'Cid', x = -12.598, z = 2.430, y = -10.988, kind = 'npc', source = 'current-nav-data' },
        T{ zone = 172, name = 'Makarim', x = -60.925, z = -333.294, y = 8.471, kind = 'npc', source = 'current-nav-data' },
        T{ zone = 230, name = 'Ambrotien', x = 93.419, z = -57.347, y = 0.999, kind = 'npc', source = 'current-nav-data' },
        T{ zone = 231, name = 'Grilau', x = -241.987, z = 57.887, y = 7.999, kind = 'npc', source = 'current-nav-data' },
        T{ zone = 231, zone_name = "Northern San d'Oria", name = 'Arnau', x = 149.892, z = 141.873, y = -0.601,
            kind = 'npc', source = 'lsb-npc-list-all', destination_id = 'npc:v1:231:17723406',
            raw_identity = 'lsb:npc_list:17723406' },
        T{ zone = 140, zone_name = 'Ghelsba Outpost', name = 'Hut Door', x = -165.357, z = 77.771, y = -11.672,
            kind = 'object', source = 'lsb-npc-list-all', destination_id = 'object:v1:140:17350951',
            raw_identity = 'lsb:npc_list:17350951' },
        T{ zone = 102, zone_name = 'La Theine Plateau', name = 'Galaihaurat', x = -481.196, z = 220.547, y = -7.028,
            kind = 'npc', source = 'lsb-npc-list-all', destination_id = 'npc:v1:102:17195615',
            raw_identity = 'lsb:npc_list:17195615', raw_spawn_ids = T{ 17195615 } },
        T{ zone = 230, zone_name = "Southern San d'Oria", name = "Tales' Beginning", x = -35.660, z = 31.955, y = 0,
            kind = 'npc', source = 'lsb-npc-list-all', destination_id = 'npc:v1:230:17720021',
            raw_identity = 'lsb:npc_list:17720021', raw_spawn_ids = T{ 17720021 } },
        T{ zone = 234, zone_name = 'Bastok Mines', name = "Tales' Beginning", x = 21.308, z = -96.862, y = 0,
            kind = 'npc', source = 'lsb-npc-list-all', destination_id = 'npc:v1:234:17736073',
            raw_identity = 'lsb:npc_list:17736073', raw_spawn_ids = T{ 17736073 } },
        T{ zone = 234, name = 'Rashid', x = -8.444, z = -123.575, y = -1.000, kind = 'npc', source = 'current-nav-data' },
        T{ zone = 143, name = 'Amber Quadav', x = 142.000, z = 154.000, y = -0.076, kind = 'enemy', source = 'current-nav-data' },
        T{ zone = 143, name = 'Onyx Quadav', x = 220.313, z = 88.193, y = -32.280, kind = 'enemy', source = 'current-nav-data' },
        T{ zone = 190, zone_name = "King Ranperre's Tomb", name = 'East Ronfaure zone line z5a0',
            x = -130.011, z = 260.750, y = -3.772, kind = 'area', source = 'lsb-zoneline-all' },
        T{ zone = 190, zone_name = "King Ranperre's Tomb", name = 'Ding Bats', x = -141.134, z = 223.168, y = -0.500,
            kind = 'enemy', source = 'lsb-mob-spawn-camps', destination_id = 'camp:v1:190:ding-bats:461e4609e82a444d5389',
            raw_identity = 'lsb:mob_spawn_points:group:1:mobname:Ding_Bats', raw_spawn_ids = T{ 17555457, 17555458 },
            cluster_policy_version = 'complete-link-v1-h120-y24' },
        T{ zone = 190, zone_name = "King Ranperre's Tomb", name = 'Ding Bats', x = 12.000, z = -91.000, y = -0.377,
            kind = 'enemy', source = 'lsb-mob-spawn-camps', destination_id = 'camp:v1:190:ding-bats:389d351b7fa71b47b883',
            raw_identity = 'lsb:mob_spawn_points:group:1:mobname:Ding_Bats', raw_spawn_ids = T{ 17555523, 17555529 },
            cluster_policy_version = 'complete-link-v1-h120-y24' },
        T{ zone = 190, zone_name = "King Ranperre's Tomb", name = 'Tombstone', x = 1.000, z = -103.608, y = -1.419,
            kind = 'npc', source = 'lsb-npc-list-all', destination_id = 'npc:v1:190:17555989',
            raw_identity = 'lsb:npc_list:17555989' },
    },
    quests_menu_data = {
        quest_log_order = T{ 'sandoria', 'aht_urhgan' },
        quest_log_resources = {
            sandoria = { label = "San d'Oria" },
            aht_urhgan = { label = 'Aht Urhgan' },
        },
    },
    missions_menu_category_labels = T{
        "San d'Oria", 'Bastok', 'Windurst', 'Rise of the Zilart', 'Chains of Promathia',
        'Assault', 'Treasures of Aht Urhgan', 'Campaign', 'Wings of the Goddess',
        'Seekers of Adoulin', "Rhapsodies of Vana'diel", 'The Voracious Resurgence',
        'A Crystalline Prophecy', "A Moogle Kupo d'Etat", 'A Shantotto Ascension',
    },
    current_player_name = function() return current_player end,
    current_player_identity = function() return current_identity end,
    current_player_world_id = function() return current_world_id end,
    current_objective_session_epoch = function() return current_session_epoch end,
    current_nation_mission_rank_state = function()
        return {
            nation = current_nation,
            rank = current_rank,
            rank_points = current_rank_points,
            identity = current_identity,
        }
    end,
    nav_cancel_mission_quest_route = function()
        local destination = accessxi.nav_destination
        local pending = accessxi.nav_zone_search_target
        local objective = (type(destination) == 'table' and (destination.objective_kind == 'mission' or destination.objective_kind == 'quest'))
            or (type(pending) == 'table' and (pending.objective_kind == 'mission' or pending.objective_kind == 'quest'))
        if not objective then return false end
        cancelled_objective_routes = cancelled_objective_routes + 1
        accessxi.nav_active = false
        accessxi.nav_destination = nil
        accessxi.nav_zone_search_target = nil
        return true
    end,
    restore_mission_packet_cache_if_needed = function() end,
    restore_quest_packet_cache_if_needed = function() end,
    restore_key_items_packet_cache_if_needed = function() end,
    load_mission_rom_rows = function(context) return mission_rows[context] end,
    current_mission_value_for_context = function(context)
        accessxi.hotkey_cache_mission_state_calls = accessxi.hotkey_cache_mission_state_calls + 1
        return mission_values[context], mission_value_packet_age
    end,
    mission_rom_current_row = function(rows, value)
        local best = nil
        for _, row in ipairs(rows or {}) do
            if value >= row.mission_id and (row.next_mission_id == nil or value < row.next_mission_id) then return row end
            if value >= row.mission_id then best = row end
        end
        return best
    end,
    cop_mission_rom_current_row = function(rows, value) return accessxi.mission_rom_current_row(rows, value) end,
    missions_menu_nation_context_id = function(context)
        if context == "San d'Oria" then return 0 end
        if context == 'Bastok' then return 1 end
        if context == 'Windurst' then return 2 end
        return nil
    end,
    mission_rom_table_for_context = function(context)
        if context == 'Campaign' then return { packet = '' } end
        if context == 'The Voracious Resurgence' then return { packet = 'tales' } end
        return { packet = context }
    end,
    quest_packet_entry = function(area, mode)
        accessxi.hotkey_cache_quest_state_calls = accessxi.hotkey_cache_quest_state_calls + 1
        return quest_entries[area .. ':' .. mode]
    end,
    quest_packet_has_id = function(entry, id)
        if entry == nil then return false end
        local word = entry.words[math.floor(id / 32) + 1] or 0
        return bit.band(word, 2 ^ (id % 32)) ~= 0
    end,
    quest_rom_rows_for_area = function(area) return quest_rows[area] end,
    quest_rom_detail_for_row = function(row)
        if row ~= nil and row.label == 'A Long Current Quest' then
            return 'Client: Native Tester. Summary: Bring the requested item.', 'quest-rom-detail'
        end
        return nil, 'missing-detail-text'
    end,
    key_items_packet_has_id = function(id) return owned_key_items[id] == true end,
    objective_key_item_owned_by_name = function(name)
        local key = tostring(name or ''):lower()
        local id = ({ ['orcish hut key'] = 157 })[key]
        return id ~= nil and owned_key_items[id] == true, id
    end,
    refresh_objective_inventory_state = function() return false, true end,
    objective_inventory_count_by_name = function(name)
        local key = tostring(name or ''):lower()
        return tonumber(objective_inventory_counts_by_name[key]) or 0,
            objective_inventory_item_ids[key]
    end,
    nav_point_effective_kind = function(point) return tostring(point.kind or ''):lower() end,
    speech_name = function(value) return tostring(value or '') end,
    sentence_fragment = function(value) return tostring(value or '') end,
    escape_probe_log_text = function(value) return tostring(value or '') end,
    mission_quest_guide_index = {
        ["mission:San d'Oria:1"] = { status = 'guide', title = 'Smash the Orcish Scouts',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ["mission:San d'Oria:2"] = { status = 'guide', title = 'Bat Hunt',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ["mission:San d'Oria:3"] = { status = 'guide', title = 'Save the Children',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ["mission:San d'Oria:4"] = { status = 'guide', title = 'The Rescue Drill',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ["mission:Rhapsodies of Vana'diel:1"] = { status = 'guide', title = 'Rhapsodies of Vanadiel',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ['mission:Bastok:2'] = { status = 'guide', title = 'A Geological Survey',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ['mission:Bastok:3'] = { status = 'verified-navigation', title = 'Fetichism',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ['quest:sandoria:2'] = { status = 'guide', title = 'The Pickpocket',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
        ['quest:sandoria:200'] = { status = 'guide', title = 'A Long Current Quest',
            source_authority = { primary = 'bg', fallback = 'ffxiclopedia' } },
    },
    objective_guides = {
        automatic_step_id = function(_, native_key, stage)
            if native_key == 'quest:sandoria:2' and stage == 'report-to-cid' then
                return 'quest:sandoria:2:step-002'
            end
            return ''
        end,
        objective_destinations = function(_, native_key)
            accessxi.hotkey_cache_destination_calls = accessxi.hotkey_cache_destination_calls + 1
            local rows = deep_copy(guide_rows_by_native[native_key] or T{})
            if type(guide_row_mutator) == 'function' then
                guide_row_mutator(native_key, rows)
            end
            return rows
        end,
        mission_destinations = function(self, native_key)
            return self:objective_destinations(native_key)
        end,
        source_route_steps = function(_, native_key)
            accessxi.hotkey_cache_source_step_calls = accessxi.hotkey_cache_source_step_calls + 1
            if native_key == "mission:San d'Oria:1" then
                return T{
                    T{
                        stable_step_id = "mission:San d'Oria:1:step-001",
                        order = 1,
                        comparison = 'corroborated',
                        action = 'talk',
                        entities = T{ 'Gate Guard', "San d'Orian Gate Guard" },
                        primary_instruction = "Speak to any San d'Orian Gate Guard to begin this Mission.",
                        ffxiclopedia_instruction = "Talk to a San d'Orian Gate Guard to accept the mission.",
                        material = true,
                        typed_claims = T{
                            T{
                                stable_claim_id = "mission:San d'Oria:1:step-001:claim-01",
                                order = 1, action = 'talk', relationship = 'talk-to',
                                target = 'Gate Guard', target_kind = 'npc', material = true,
                            },
                        },
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:1:step-005",
                        order = 5,
                        comparison = 'corroborated',
                        action = 'fight',
                        entities = T{ 'Orcish Fodder', 'Orcish Axe' },
                        zones = T{ 'East Ronfaure', 'West Ronfaure' },
                        items = T{ 'Orcish Axe' },
                        primary_instruction = 'Defeat Orcish Fodder until you obtain an Orcish Axe.',
                        material = true,
                        typed_claims = T{
                            T{
                                stable_claim_id = "mission:San d'Oria:1:step-005:claim-01",
                                order = 1, action = 'fight', relationship = 'defeat-enemy',
                                target = 'Orcish Fodder', target_kind = 'enemy', material = true,
                            },
                            T{
                                stable_claim_id = "mission:San d'Oria:1:step-005:claim-02",
                                order = 2, action = 'obtain', relationship = 'obtain-item',
                                target = 'Orcish Axe', target_kind = 'item', items = T{ 'Orcish Axe' },
                                material = true,
                            },
                        },
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:1:step-007",
                        order = 7,
                        comparison = 'corroborated',
                        action = 'talk',
                        entities = T{ 'Orcish Axe', 'Gate Guard' },
                        zones = T{},
                        primary_instruction = 'Return to a Gate Guard and trade the Orcish Axe to finish the mission.',
                        material = true,
                        typed_claims = T{
                            T{
                                stable_claim_id = "mission:San d'Oria:1:step-007:claim-01",
                                order = 1, action = 'trade', relationship = 'trade-item',
                                target = 'Gate Guard', target_kind = 'npc', items = T{ 'Orcish Axe' },
                                material = true,
                            },
                        },
                        route_ready = false,
                    },
                }
            end
            if native_key == "mission:San d'Oria:3" then
                return T{
                    T{
                        stable_step_id = "mission:San d'Oria:3:step-002",
                        order = 2,
                        comparison = 'corroborated',
                        action = 'talk',
                        entities = T{ 'Arnau', "Northern San d'Oria" },
                        zones = T{ "Northern San d'Oria" },
                        primary_instruction = 'Next speak to Arnau in the Cathedral in Northern San d\'Oria.',
                        route_ready = true,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:3:step-008",
                        order = 8,
                        comparison = 'single-source',
                        action = 'obtain',
                        entities = T{ 'Orcish hut key' },
                        zones = T{},
                        key_items = T{ 'Orcish hut key' },
                        primary_instruction = 'Win the battlefield and obtain the Orcish hut key.',
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:3:step-015",
                        order = 15,
                        comparison = 'single-source',
                        action = 'travel',
                        entities = T{ 'Ghelsba Outpost', 'battlefield' },
                        zones = T{ 'Ghelsba Outpost' },
                        primary_instruction = 'Head to Ghelsba Outpost at F-10 and check the Hut Door to enter the Save the Children battlefield.',
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:3:step-025",
                        order = 25,
                        comparison = 'corroborated',
                        action = 'talk',
                        entities = T{ 'Gate Guard' },
                        zones = T{},
                        primary_instruction = 'Return to a Gate Guard to complete the Mission and receive Rank 2.',
                        route_ready = false,
                    },
                }
            end
            if native_key == "mission:San d'Oria:4" then
                return T{
                    T{
                        stable_step_id = "mission:San d'Oria:4:step-001",
                        order = 1,
                        comparison = 'single-source',
                        action = 'obtain',
                        entities = T{ 'Silent Oil' },
                        primary_instruction = 'Bring Silent Oil if desired for the cave route.',
                        route_recommendation = true,
                        optional_nonessential = true,
                        recommendation_item = 'Silent Oil',
                        recommendation_instruction = 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:4:step-002",
                        order = 2,
                        comparison = 'corroborated',
                        action = 'trade',
                        entities = T{ 'Conquest Overseer' },
                        primary_instruction = 'Trade enough crystals to unlock the mission.',
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:4:step-003",
                        order = 3,
                        comparison = 'corroborated',
                        action = 'talk',
                        entities = T{ 'Gate Guard' },
                        primary_instruction = 'Speak to any Gate Guard and accept the mission.',
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:4:step-006",
                        order = 6,
                        comparison = 'corroborated',
                        action = 'talk',
                        entities = T{ 'La Theine Plateau', 'Galaihaurat' },
                        zones = T{ 'La Theine Plateau' },
                        primary_instruction = 'Head to La Theine Plateau and speak to Galaihaurat.',
                        route_ready = false,
                    },
                }
            end
            if native_key == "mission:Rhapsodies of Vana'diel:1" then
                return T{
                    T{
                        stable_step_id = "mission:Rhapsodies of Vana'diel:1:step-001",
                        order = 1,
                        comparison = 'corroborated',
                        action = 'travel',
                        entities = T{},
                        primary_instruction = 'Zone into a starter city at level 3 or higher.',
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:Rhapsodies of Vana'diel:1:step-002",
                        order = 2,
                        comparison = 'corroborated',
                        action = 'note',
                        entities = T{ "Tales' Beginning" },
                        primary_instruction = "Interact with a Tales' Beginning to resume the postponed opening cutscene.",
                        route_ready = false,
                    },
                }
            end
            if native_key ~= "mission:San d'Oria:2" then return T{} end
            return T{
                T{
                    stable_step_id = "mission:San d'Oria:2:step-005",
                    order = 5,
                    comparison = 'corroborated',
                    action = 'fight',
                        entities = T{ 'Ding Bats', "King Ranperre's Tomb", 'Orcish Mail Scales' },
                        zones = T{},
                        items = T{ 'Orcish Mail Scales' },
                        primary_instruction = "Defeat Ding Bats in King Ranperre's Tomb and obtain Orcish Mail Scales.",
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:2:step-009",
                        order = 9,
                        comparison = 'conflict',
                        action = 'examine',
                        entities = T{},
                        zones = T{ "King Ranperre's Tomb" },
                        primary_instruction = 'Touch the Tombstone for the mission cutscene.',
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:2:step-012",
                        order = 12,
                        comparison = 'corroborated',
                        action = 'talk',
                        entities = T{ 'Gate Guard', 'Orcish Mail Scales' },
                        zones = T{},
                        primary_instruction = 'Return to a Gate Guard and trade the Orcish Mail Scales to complete the mission.',
                        route_ready = false,
                    },
            }
        end,
        route_recommendations = function(_, native_key, through_order)
            if native_key == "mission:San d'Oria:4" and tonumber(through_order) == 6 then
                return T{
                    T{
                        item = 'Silent Oil',
                        instruction = 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
                        stable_step_id = "mission:San d'Oria:4:step-001",
                        order = 1,
                    },
                }
            end
            return T{}
        end,
    },
}

local runtime_override = nil
accessxi.objective_route_runtime = {
    authorize_start = function(_, selected, fresh, player)
        runtime_authorize_calls = runtime_authorize_calls + 1
        if type(runtime_override) == 'function' then
            return runtime_override(selected, fresh, player)
        end
        local exact_fields = {
            'objective_native_key', 'objective_guide_step_id',
            'objective_candidate_id', 'objective_action_id',
            'objective_group_id', 'objective_destination_id',
            'objective_character_identity', 'objective_world_id',
            'objective_session_epoch',
        }
        for _, field in ipairs(exact_fields) do
            if tostring(selected[field] or '') ~= tostring(fresh[field] or '') then
                return nil, 'The selected objective changed. Refresh the list.', 'blocked'
            end
        end
        if fresh.objective_character_identity ~= current_identity
            or tonumber(fresh.objective_world_id) ~= current_world_id
            or tonumber(fresh.objective_session_epoch) ~= current_session_epoch then
            return nil, 'The selected objective belongs to stale character or session state.', 'blocked'
        end
        local kind = tostring(fresh.objective_kind or '')
        if kind == 'mission' and (accessxi.mission_packet_source ~= 'packet_in_056'
            or tonumber(accessxi.mission_packet_session_epoch) ~= current_session_epoch) then
            return nil, 'Current mission packet evidence is stale.', 'blocked'
        elseif kind == 'quest' then
            local entry = quest_entries[tostring(fresh.quest_area_key or '') .. ':current']
            if accessxi.quest_packet_source ~= 'packet_in_056'
                or tonumber(accessxi.quest_packet_session_epoch) ~= current_session_epoch
                or type(entry) ~= 'table' or entry.source ~= 'packet_in_056'
                or tonumber(entry.session_epoch) ~= current_session_epoch then
                return nil, 'Current quest packet evidence is stale.', 'blocked'
            end
        end
        local key_item_entry = accessxi.key_items_packet_tables[0]
        if type(key_item_entry) ~= 'table' or key_item_entry.source ~= 'packet_in_055'
            or tonumber(key_item_entry.session_epoch) ~= current_session_epoch then
            return nil, 'Current key-item evidence is stale.', 'blocked'
        end
        if accessxi.inventory_packet_source ~= 'packet_in_inventory'
            or accessxi.inventory_packet_identity ~= current_identity
            or tonumber(accessxi.inventory_packet_session_epoch) ~= current_session_epoch then
            return nil, 'Current inventory evidence is stale.', 'blocked'
        end
        if fresh.objective_instruction_only == true then
            if fresh.objective_candidate_id ~= '' or fresh.objective_group_id ~= ''
                or fresh.objective_destination_id ~= '' or fresh.objective_route_contract_id ~= nil
                or fresh.objective_classification ~= 'instruction-only'
                or tostring(fresh.objective_action_instruction or '') == '' then
                return nil, 'Instruction-only objective metadata is invalid.', 'blocked'
            end
            return fresh.objective_action_instruction, '', 'instruction'
        end
        local contract = runtime_contracts[fresh.objective_candidate_id]
        if type(contract) ~= 'table' then
            return nil, 'No rooted route contract matches this objective destination.', 'blocked'
        end
        local row = contract.row
        local point = row.target_point
        return T{
            zone = row.zone, name = row.target_name, x = point[1], z = point[2], y = point[3],
            kind = row.target_kind, source = 'rooted-route-contract', confidence = 'mesh-proven',
            destination_id = row.destination_id, raw_identity = row.raw_identity,
            raw_spawn_ids = deep_copy(row.raw_spawn_ids),
            cluster_policy_version = row.cluster_policy_version,
            objective_kind = fresh.objective_kind,
            objective_native_key = fresh.objective_native_key,
            objective_guide_step_id = fresh.objective_guide_step_id,
            objective_candidate_id = fresh.objective_candidate_id,
            objective_action_id = fresh.objective_action_id,
            objective_group_id = fresh.objective_group_id,
            objective_destination_id = fresh.objective_destination_id,
            objective_route_contract_id = contract.contract_id,
            objective_contract_snapshot = deep_copy(contract),
            objective_character_identity = fresh.objective_character_identity,
            objective_world_id = fresh.objective_world_id,
            objective_session_epoch = fresh.objective_session_epoch,
            objective_classification = fresh.objective_classification,
            objective_action_instruction = fresh.objective_action_instruction,
            objective_instruction = fresh.objective_action_instruction,
            arrival_instruction = fresh.objective_action_instruction,
            verified = true,
        }, '', 'ready'
    end,
}

local function load_with_env(path, env)
    local chunk = assert(loadfile(path))
    setfenv(chunk, setmetatable(env or {}, { __index = _G }))
    return chunk()
end

while #accessxi.nav_points < 42366 do
    local point_id = #accessxi.nav_points + 1
    accessxi.nav_points:append(T{
        zone = 1,
        zone_name = 'Scale Zone',
        name = ('Scale Point %d'):format(point_id),
        x = point_id % 100,
        z = math.floor(point_id / 100),
        y = 0,
        kind = 'npc',
        source = 'hotkey scale fixture',
    })
end
assert(#accessxi.nav_points == 42366, 'hotkey scale fixture did not match the production catalog size')

for _, entry in pairs(accessxi.mission_quest_guide_index) do
    entry.progression_revision = 'task2-progression-revision'
    entry.progression_schema_version = 2
end

local function task2_flat_target_key(value)
    return tostring(value or ''):lower():gsub('[^%w]', '')
end

accessxi.objective_guides.progression_actions = function(self, native_key)
    local actions = T{}
    for _, step in ipairs(self:source_route_steps(native_key) or T{}) do
        local claims = step.typed_claims
        if type(claims) ~= 'table' or #claims == 0 then
            claims = T{
                T{
                    stable_claim_id = step.stable_step_id .. ':claim-01',
                    order = 1,
                    action = step.action,
                    relationship = step.action,
                    target = type(step.entities) == 'table' and step.entities[1] or '',
                    target_kind = '',
                    zones = step.zones or T{},
                    items = step.items or T{},
                    key_items = step.key_items or T{},
                    count_mode = 'single',
                    required_count = 1,
                },
            }
        end
        for _, claim in ipairs(claims) do
            actions:append(T{
                step_id = step.stable_step_id,
                step_order = step.order,
                action_id = claim.stable_claim_id,
                action_order = claim.order,
                order = #actions + 1,
                action = claim.action,
                relationship = claim.relationship,
                target = claim.target,
                target_key = task2_flat_target_key(claim.target),
                target_kind = claim.target_kind,
                npcs = claim.target_kind == 'npc' and T{ claim.target } or T{},
                objects = claim.target_kind == 'object' and T{ claim.target } or T{},
                enemies = claim.target_kind == 'enemy' and T{ claim.target } or T{},
                zones = deep_copy(claim.zones or step.zones or T{}),
                items = deep_copy(claim.items or step.items or T{}),
                key_items = deep_copy(claim.key_items or step.key_items or T{}),
                transports = T{},
                grid_coordinates = T{},
                result_items = T{},
                result_relation = '',
                destination_zone_name = tostring(
                    claim.destination_zone_name or step.destination_zone_name or ''),
                destination_zone_id = tonumber(
                    claim.destination_zone_id or step.destination_zone_id) or 0,
                instruction = step.primary_instruction,
                count_mode = claim.count_mode or 'single',
                required_count = tonumber(claim.required_count) or 1,
                count_explicit = claim.count_explicit == true,
                material = true,
                source_authority = 'bg',
                field_sources = T{ action = 'bg', relationship = 'bg', target = 'bg',
                    target_key = 'bg', target_kind = 'bg', npcs = 'bg', objects = 'bg',
                    enemies = 'bg', zones = 'bg', items = 'bg', key_items = 'bg',
                    transports = 'bg', grid_coordinates = 'bg', result_items = 'bg',
                    result_relation = 'bg',
                    destination_zone_name = tostring(claim.destination_zone_name
                        or step.destination_zone_name or '') ~= '' and 'bg' or '',
                    destination_zone_id = tonumber(claim.destination_zone_id
                        or step.destination_zone_id) ~= nil
                        and tonumber(claim.destination_zone_id or step.destination_zone_id) > 0
                        and 'bg' or '',
                    instruction = 'bg', count_mode = 'default',
                    required_count = 'default', count_explicit = 'default', catalogue = '' },
                source_revisions = T{ bg = 4001, ffxiclopedia = 4002 },
                source_action_span_ids = T{
                    step.stable_step_id .. ':bg:action-' .. ('%02d'):format(claim.order),
                    step.stable_step_id .. ':ffxiclopedia:action-' .. ('%02d'):format(claim.order),
                },
                catalogue = T{},
            })
        end
    end
    return actions
end

accessxi.mission_quest_objectives = load_with_env(objectives_path, { accessxi = accessxi, T = T })
assert(type(accessxi.mission_quest_objectives) == 'table')
accessxi.mission_quest_objectives.quests['sandoria:2'] = {
    title = 'The Pickpocket',
    context = 'sandoria',
    quest_id = 2,
    required_key_items = T{},
    source = 'test fixture backed by the native current quest bit',
    stages = T{
        {
            key = 'report-to-cid',
            when = 'owns-none',
            instruction = 'Talk to Cid.',
            target = { reference = { zone = 237, name = 'Cid', kind = 'npc' } },
        },
    },
}
local function reload_navigation_module()
    assert(load_with_env(module_path, {
        accessxi = accessxi,
        T = T,
        bit = bit,
        log_line = function(text) logs:append(text) end,
    }))
end
reload_navigation_module()

local function find(items, name)
    for _, item in ipairs(items or {}) do
        if item.name == name then return item end
    end
    return nil
end

local function find_destination(items, stable_id)
    for _, item in ipairs(items or {}) do
        if item.objective_destination_id == stable_id then return item end
    end
    return nil
end

local function count_named(items, name)
    local count = 0
    for _, item in ipairs(items or {}) do
        if item.name == name then count = count + 1 end
    end
    return count
end

local function set_live_identity(identity)
    current_identity = identity
    current_world_id = tonumber(tostring(identity):match(':(%d+)$')) or 0
    accessxi.mission_quest_nav_identity = identity
    accessxi.mission_packet_identity = identity
    accessxi.mission_packet_ahturghan_identity = identity
    accessxi.mission_packet_ahturghan_complete_identity = identity
    accessxi.mission_packet_nations_complete_identity = identity
    accessxi.quest_packet_identity = identity
    accessxi.key_items_packet_identity = identity
    accessxi.inventory_packet_identity = identity
    for _, entry in pairs(quest_entries) do
        entry.identity = identity
    end
    for _, entry in pairs(accessxi.key_items_packet_tables or {}) do
        entry.identity = identity
    end
end

function accessxi.hotkey_cache_build(category_key, reason)
    local rows = accessxi.nav_mission_quest_active_items(category_key)
    assert(#rows > 0, reason .. ' produced no active rows')
    local signature = tostring(rows[1].objective_active_state_signature or '')
    assert(signature ~= '', reason .. ' did not stamp the active-state signature')
    return rows, signature
end

function accessxi.hotkey_cache_assert_rebuilt(category_key, previous_rows, previous_signature, reason)
    local rows, signature = accessxi.hotkey_cache_build(category_key, reason)
    assert(signature ~= previous_signature, reason .. ' did not rebuild the affected category')
    assert(rows ~= previous_rows, reason .. ' reused the stale active row list')
    return rows, signature
end

function accessxi.hotkey_cache_assert_state_provider_increased(category_key, before, reason)
    local after = category_key == 'mission' and accessxi.hotkey_cache_mission_state_calls
        or accessxi.hotkey_cache_quest_state_calls
    assert(after > before, reason .. ' did not re-read the affected live packet state')
    return after
end

function accessxi.set_hotkey_cache_session_epoch(epoch)
    current_session_epoch = epoch
    accessxi.mission_packet_session_epoch = epoch
    accessxi.quest_packet_session_epoch = epoch
    accessxi.inventory_packet_session_epoch = epoch
    for _, entry in pairs(quest_entries) do
        entry.session_epoch = epoch
    end
    for _, entry in pairs(accessxi.key_items_packet_tables or {}) do
        entry.session_epoch = epoch
    end
end

-- Mission and Quest hotkeys run every time the browser moves over a category.
-- The guide providers are the expensive boundary: unchanged live state must
-- reuse both category rows without another guide expansion, but each stable
-- freshness key must produce a newly stamped category result.
accessxi.hotkey_cache_missions, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_build(
    'mission', 'initial Mission hotkey build')
accessxi.hotkey_cache_quests, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_build(
    'quest', 'initial Quest hotkey build')
assert(#accessxi.hotkey_cache_missions > 0 and #accessxi.hotkey_cache_quests > 0)
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_mission_state_calls
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_quest_state_calls
accessxi.hotkey_cache_destination_baseline = accessxi.hotkey_cache_destination_calls
accessxi.hotkey_cache_source_step_baseline = accessxi.hotkey_cache_source_step_calls
assert(accessxi.hotkey_cache_destination_baseline > 0,
    'initial hotkey builds did not reach the guide destination provider')
assert(accessxi.hotkey_cache_source_step_baseline > 0,
    'initial hotkey builds did not reach the guide source-step provider')

accessxi.hotkey_cache_build('mission', 'unchanged Mission hotkey build')
accessxi.hotkey_cache_build('quest', 'unchanged Quest hotkey build')
assert(accessxi.hotkey_cache_destination_calls == accessxi.hotkey_cache_destination_baseline
    and accessxi.hotkey_cache_source_step_calls == accessxi.hotkey_cache_source_step_baseline,
    'unchanged Mission and Quest hotkey builds expanded objective guides again')
assert(accessxi.hotkey_cache_mission_state_calls == accessxi.hotkey_cache_mission_state_baseline
    and accessxi.hotkey_cache_quest_state_calls == accessxi.hotkey_cache_quest_state_baseline,
    'unchanged Mission and Quest hotkey builds re-read active packet state')
accessxi.hotkey_cache_catalog_index_baseline = accessxi.nav_objective_catalog_index_build_count
accessxi.hotkey_cache_catalog_visit_baseline = accessxi.nav_objective_catalog_index_point_visit_count
assert(accessxi.hotkey_cache_catalog_visit_baseline == #accessxi.nav_points,
    'the initial hotkey build did not index the production-sized catalog exactly once')
accessxi.hotkey_cache_prepare_item = accessxi.hotkey_cache_missions[1]
accessxi.nav_mission_quest_prepare_route(accessxi.hotkey_cache_prepare_item, { zone = 230 })
accessxi.nav_mission_quest_prepare_route(accessxi.hotkey_cache_prepare_item, { zone = 230 })
assert(accessxi.hotkey_cache_mission_state_calls == accessxi.hotkey_cache_mission_state_baseline
    and accessxi.hotkey_cache_quest_state_calls == accessxi.hotkey_cache_quest_state_baseline,
    'unchanged prepare-route calls re-read active packet state')
assert(accessxi.nav_objective_catalog_index_build_count == accessxi.hotkey_cache_catalog_index_baseline,
    'unchanged prepare-route calls rebuilt the navigation catalog index')
assert(accessxi.nav_objective_catalog_index_point_visit_count == accessxi.hotkey_cache_catalog_visit_baseline,
    'unchanged hotkey or prepare-route calls rescanned the production-sized catalog')

accessxi.last_native_inventory_item_tick = accessxi.last_native_inventory_item_tick + 1
accessxi.hotkey_cache_volatile_mission_rows, accessxi.hotkey_cache_volatile_mission_signature = accessxi.hotkey_cache_build(
    'mission', 'volatile inventory-tick Mission hotkey build')
accessxi.hotkey_cache_volatile_quest_rows, accessxi.hotkey_cache_volatile_quest_signature = accessxi.hotkey_cache_build(
    'quest', 'volatile inventory-tick Quest hotkey build')
assert(accessxi.hotkey_cache_destination_calls == accessxi.hotkey_cache_destination_baseline
    and accessxi.hotkey_cache_source_step_calls == accessxi.hotkey_cache_source_step_baseline,
    'a volatile native inventory observation tick expanded objective guides again')
assert(accessxi.hotkey_cache_mission_state_calls == accessxi.hotkey_cache_mission_state_baseline
    and accessxi.hotkey_cache_quest_state_calls == accessxi.hotkey_cache_quest_state_baseline,
    'a volatile native inventory observation tick re-read active packet state')
assert(accessxi.hotkey_cache_volatile_mission_signature == accessxi.hotkey_cache_mission_signature
    and accessxi.hotkey_cache_volatile_quest_signature == accessxi.hotkey_cache_quest_signature,
    'a volatile native inventory observation tick changed an active-state signature')
assert(accessxi.hotkey_cache_volatile_mission_rows == accessxi.hotkey_cache_missions
    and accessxi.hotkey_cache_volatile_quest_rows == accessxi.hotkey_cache_quests,
    'a volatile native inventory observation tick rebuilt an active row list')

for _, entry in pairs(accessxi.key_items_packet_tables) do
    entry.source = 'cache'
    entry.session_epoch = nil
end
accessxi.key_items_packet_source = 'cache'
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_missions, accessxi.hotkey_cache_mission_signature,
    'cached key-item freshness for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quests, accessxi.hotkey_cache_quest_signature,
    'cached key-item freshness for Quests')
for _, entry in pairs(accessxi.key_items_packet_tables) do
    entry.source = 'packet_in_055'
    entry.session_epoch = current_session_epoch
end
accessxi.key_items_packet_source = 'packet_in_055'
local same_key_before_live = accessxi.key_items_packet_key
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'same-byte live key-item freshness for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'same-byte live key-item freshness for Quests')
assert(accessxi.key_items_packet_key == same_key_before_live,
    'the key-item freshness regression changed the content key')
accessxi.hotkey_cache_missions = accessxi.hotkey_cache_mission_rows
accessxi.hotkey_cache_quests = accessxi.hotkey_cache_quest_rows

accessxi.inventory_packet_key = 'inventory:hotkey-cache:2'
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_missions, accessxi.hotkey_cache_mission_signature,
    'inventory packet key change for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quests, accessxi.hotkey_cache_quest_signature,
    'inventory packet key change for Quests')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'inventory packet key change for Missions')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'inventory packet key change for Quests')

accessxi.key_items_packet_key = 'key-items:hotkey-cache:2'
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'key-item packet key change for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'key-item packet key change for Quests')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'key-item packet key change for Missions')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'key-item packet key change for Quests')

accessxi.mission_packet_hex = 'mission-hotkey-cache-2'
accessxi.mission_packet_main.nation_mission = 2
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'mission packet payload change')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'mission packet payload change')
assert(find(accessxi.hotkey_cache_mission_rows, 'Fetichism') ~= nil,
    'mission packet payload change did not expose the decoded Mission result')
accessxi.hotkey_cache_unaffected_quest_rows = accessxi.hotkey_cache_quest_rows
accessxi.hotkey_cache_quest_rows = accessxi.hotkey_cache_build('quest', 'mission packet payload Quest cache check')
assert(accessxi.hotkey_cache_quest_rows == accessxi.hotkey_cache_unaffected_quest_rows,
    'mission packet payload change rebuilt unaffected Quest rows')
assert(accessxi.hotkey_cache_quest_state_calls == accessxi.hotkey_cache_quest_state_baseline,
    'mission packet payload change re-read unaffected Quest state')

quest_entries['sandoria:current'].words = words_with(2, 50, 200)
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'quest packet payload change')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'quest packet payload change')
assert(find(accessxi.hotkey_cache_quest_rows, 'Hotkey Packet Quest') ~= nil,
    'quest packet payload change did not expose the decoded Quest result')
accessxi.hotkey_cache_unaffected_mission_rows = accessxi.hotkey_cache_mission_rows
accessxi.hotkey_cache_mission_rows = accessxi.hotkey_cache_build('mission', 'quest packet payload Mission cache check')
assert(accessxi.hotkey_cache_mission_rows == accessxi.hotkey_cache_unaffected_mission_rows,
    'quest packet payload change rebuilt unaffected Mission rows')
assert(accessxi.hotkey_cache_mission_state_calls == accessxi.hotkey_cache_mission_state_baseline,
    'quest packet payload change re-read unaffected Mission state')

accessxi.objective_progress_revision = accessxi.objective_progress_revision + 1
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'objective-progress revision change for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'objective-progress revision change for Quests')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'objective-progress revision change for Missions')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'objective-progress revision change for Quests')

set_live_identity('alpha:1002')
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'character identity change for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'character identity change for Quests')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'character identity change for Missions')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'character identity change for Quests')

current_world_id = 1003
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'current-world change for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'current-world change for Quests')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'current-world change for Missions')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'current-world change for Quests')

accessxi.set_hotkey_cache_session_epoch(78)
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'session epoch change for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'session epoch change for Quests')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'session epoch change for Missions')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'session epoch change for Quests')

accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature = accessxi.hotkey_cache_assert_rebuilt(
    'mission', accessxi.hotkey_cache_mission_rows, accessxi.hotkey_cache_mission_signature,
    'navigation catalog revision change for Missions')
accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature = accessxi.hotkey_cache_assert_rebuilt(
    'quest', accessxi.hotkey_cache_quest_rows, accessxi.hotkey_cache_quest_signature,
    'navigation catalog revision change for Quests')
accessxi.hotkey_cache_mission_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'mission', accessxi.hotkey_cache_mission_state_baseline, 'navigation catalog revision change for Missions')
accessxi.hotkey_cache_quest_state_baseline = accessxi.hotkey_cache_assert_state_provider_increased(
    'quest', accessxi.hotkey_cache_quest_state_baseline, 'navigation catalog revision change for Quests')
assert(accessxi.nav_objective_catalog_index_build_count == accessxi.hotkey_cache_catalog_index_baseline + 1,
    'a navigation catalog revision change did not rebuild the catalog index exactly once')
assert(accessxi.nav_objective_catalog_index_point_visit_count
        == accessxi.hotkey_cache_catalog_visit_baseline + #accessxi.nav_points,
    'a navigation catalog revision change did not visit the catalog exactly once')
accessxi.nav_mission_quest_active_items('mission')
accessxi.nav_mission_quest_active_items('quest')
assert(accessxi.nav_objective_catalog_index_build_count == accessxi.hotkey_cache_catalog_index_baseline + 1,
    'stable navigation catalog revision rebuilt the catalog index again')
assert(accessxi.nav_objective_catalog_index_point_visit_count
        == accessxi.hotkey_cache_catalog_visit_baseline + #accessxi.nav_points,
    'stable navigation catalog revision rescanned the production-sized catalog')

set_live_identity('alpha:1001')
current_world_id = 1001
accessxi.set_hotkey_cache_session_epoch(77)
accessxi.inventory_packet_key = 'inventory:hotkey-cache:1'
accessxi.key_items_packet_key = 'key-items:hotkey-cache:1'
accessxi.mission_packet_hex = 'mission-hotkey-cache-1'
accessxi.mission_packet_main.nation_mission = 1
quest_entries['sandoria:current'].words = words_with(2, 200)
accessxi.objective_progress_revision = 1
accessxi.nav_catalog_revision = 1
accessxi.last_native_inventory_item_tick = 100

-- Exact Task 3 typed rows expand missions and quests through the same path.
-- Input order is intentionally reversed; the browser order is guide/data-owned.
accessxi.mission_packet_main.nation = 1
accessxi.mission_packet_main.nation_mission = 2
local typed_missions = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(typed_missions, 'Fetichism') == 2)
assert(typed_missions[1].objective_candidate_id == 'mission:Bastok:3:step-006:claim-01:candidate:amber-lower')
assert(typed_missions[2].objective_candidate_id == 'mission:Bastok:3:step-006:claim-01:candidate:onyx-upper')
local typed_lower = typed_missions[1]
assert(typed_lower.objective_native_key == 'mission:Bastok:3')
assert(typed_lower.objective_guide_step_id == 'mission:Bastok:3:step-006')
assert(typed_lower.objective_action_id == 'mission:Bastok:3:step-006:claim-01')
assert(typed_lower.objective_group_id == 'mission:Bastok:3:step-006:claim-01:group:lower')
assert(typed_lower.objective_destination_id == 'enemy:v1:143:amber-lower')
assert(typed_lower.objective_route_contract_id == nil)
assert(typed_lower.objective_character_identity == current_identity)
assert(typed_lower.objective_world_id == current_world_id)
assert(typed_lower.objective_session_epoch == current_session_epoch)
local typed_target, typed_message, typed_mode = accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })
assert(typed_mode == 'ready' and typed_message == '' and type(typed_target) == 'table')
assert(typed_target.objective_route_contract_id == 'route:v2:lower')
assert(typed_target.objective_candidate_id == typed_lower.objective_candidate_id)
assert(typed_target.objective_contract_snapshot.contract_id == typed_target.objective_route_contract_id)
typed_target.objective_contract_snapshot.contract_id = 'caller-mutation'
local isolated_target = assert((accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })))
assert(isolated_target.objective_contract_snapshot.contract_id == 'route:v2:lower',
    'returned rooted contract snapshots must be deep-copy isolated')
typed_target.objective_contract_snapshot.contract_id = 'route:v2:lower'

accessxi.mission_packet_main.nation = 0
accessxi.mission_packet_main.nation_mission = 0
local orcish = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(orcish, 'Smash the Orcish Scouts') == 2)
assert(orcish[1].objective_destination_id == 'enemy:v1:101:orcish-east')
assert(orcish[2].objective_destination_id == 'enemy:v1:100:orcish-west')

local orcish_after_item_reset
local task2_inventory_cursor_committed = false
local task2_restore_inventory_cursor
local function task2_clear_inventory_cursor()
    os.remove(objective_progress_path)
    accessxi.objective_progress_revision =
        (tonumber(accessxi.objective_progress_revision) or 0) + 1
    reload_navigation_module()
end
;(function()
local saved_orcish_inventory_packet_key = accessxi.inventory_packet_key
objective_inventory_counts_by_name['orcish axe'] = 1
accessxi.inventory_packet_key = 'inventory:orcish-axe-preexisting'
local orcish_with_preexisting_item = accessxi.nav_mission_quest_active_items('mission')
task2_reducer_expect(count_named(orcish_with_preexisting_item, 'Smash the Orcish Scouts') == 2
        and orcish_with_preexisting_item[1].objective_guide_step_id == "mission:San d'Oria:1:step-005"
        and orcish_with_preexisting_item[2].objective_guide_step_id == "mission:San d'Oria:1:step-005",
    'pre-existing Orcish Axe possession completed an acquisition step without a cursor-entered delta')
objective_inventory_counts_by_name['orcish axe'] = 0
accessxi.inventory_packet_key = saved_orcish_inventory_packet_key

objective_inventory_counts_by_name['orcish axe'] = 1
local inventory_delta = {
    kind = 'inventory-delta',
    character_identity = current_identity,
    world_id = current_world_id,
    session_epoch = current_session_epoch,
    sequence = 6001,
    inventory_sequence = 6001,
    tick = 6001,
    corpus_revision = tonumber(accessxi.nav_catalog_revision) or 0,
    progression_revision = 'task2-progression-revision',
    snapshot_complete = true,
    item_id = 16656,
    item_name = 'Orcish Axe',
    before_count = 0,
    after_count = 1,
}
local inventory_delta_accepted = false
if type(accessxi.nav_mission_quest_reduce_signal) ~= 'function' then
    task2_reducer_failures:append('production typed objective reducer API is missing for inventory-delta')
else
    local ok, accepted = pcall(accessxi.nav_mission_quest_reduce_signal, inventory_delta)
    task2_reducer_expect(ok, 'inventory-delta reducer raised a fixture-independent production error')
    inventory_delta_accepted = ok and accepted == true
end
task2_reducer_expect(inventory_delta_accepted,
    'current-session Orcish Axe 0-to-1 delta did not advance the acquisition step')
if inventory_delta_accepted then
    task2_inventory_cursor_committed = true
    local orcish_turn_in = accessxi.nav_mission_quest_active_items('mission')
    task2_reducer_expect(count_named(orcish_turn_in, 'Smash the Orcish Scouts') == 2
            and orcish_turn_in[1].objective_guide_step_id == "mission:San d'Oria:1:step-007"
            and orcish_turn_in[2].objective_guide_step_id == "mission:San d'Oria:1:step-007",
        'accepted Orcish Axe delta did not move exactly to the Gate Guard turn-in claim')
    local progress_file = io.open(objective_progress_path, 'rb')
    local progress_bytes = progress_file ~= nil and (progress_file:read('*a') or '') or ''
    if progress_file ~= nil then progress_file:close() end
    local progress_line = ''
    for candidate in progress_bytes:gmatch('[^\r\n]+') do progress_line = candidate end
    task2_reducer_expect(progress_line == table.concat({
            'v2', current_identity, tostring(current_world_id), "mission:San d'Oria:1",
            'task2-progression-revision', "mission:San d'Oria:1:step-007", '7',
            "mission:San d'Oria:1:step-007:claim-01", '1', '0',
        }, '\t'),
        'accepted Orcish Axe delta did not append the exact ten-field next-action cursor')
    reload_navigation_module()
    local orcish_after_reload = accessxi.nav_mission_quest_active_items('mission')
    task2_reducer_expect(count_named(orcish_after_reload, 'Smash the Orcish Scouts') == 2
            and orcish_after_reload[1].objective_guide_step_id == "mission:San d'Oria:1:step-007"
            and orcish_after_reload[2].objective_guide_step_id == "mission:San d'Oria:1:step-007",
        'inventory-delta cursor was not persisted across navigation-module reload')

    inventory_delta.sequence = 6002
    inventory_delta.inventory_sequence = 6002
    inventory_delta.tick = 6002
    inventory_delta.before_count = 1
    inventory_delta.after_count = 0
    objective_inventory_counts_by_name['orcish axe'] = 0
    local ok, accepted = pcall(accessxi.nav_mission_quest_reduce_signal, inventory_delta)
    task2_reducer_expect(ok, 'inventory-loss reducer raised a fixture-independent production error')
    task2_reducer_expect(not (ok and accepted == true),
        'inventory loss was accepted as forward progression')
    orcish_after_item_reset = accessxi.nav_mission_quest_active_items('mission')
    task2_reducer_expect(count_named(orcish_after_item_reset, 'Smash the Orcish Scouts') == 2
            and orcish_after_item_reset[1].objective_guide_step_id == "mission:San d'Oria:1:step-007"
            and orcish_after_item_reset[2].objective_guide_step_id == "mission:San d'Oria:1:step-007",
        'consuming the acquired item rewound the durable objective cursor')
else
    orcish_after_item_reset = accessxi.nav_mission_quest_active_items('mission')
end

-- Task 2 generic reducer contract.  These synthetic rows exercise stable
-- material claims without embedding any mission-specific follow-up table in
-- production.  The native active-objective packets remain the authority for
-- which local mission and quest may consume each signal.
local task2_reducer_sequence = 6100
local function task2_signal(kind, values)
    task2_reducer_sequence = task2_reducer_sequence + 1
    local signal = {
        kind = kind,
        character_identity = current_identity,
        world_id = current_world_id,
        session_epoch = current_session_epoch,
        sequence = task2_reducer_sequence,
        tick = task2_reducer_sequence,
        corpus_revision = tonumber(accessxi.nav_catalog_revision) or 0,
        progression_revision = 'task2-progression-revision',
    }
    for key, value in pairs(values or {}) do signal[key] = value end
    return signal
end

local function task2_reduce(signal, label)
    if type(accessxi.nav_mission_quest_reduce_signal) ~= 'function' then
        return false
    end
    local ok, accepted = pcall(accessxi.nav_mission_quest_reduce_signal, signal)
    task2_reducer_expect(ok, label .. ' raised a production reducer error')
    return ok and accepted == true
end

local function task2_progress_bytes()
    local file = io.open(objective_progress_path, 'rb')
    if file == nil then return '' end
    local bytes = file:read('*a') or ''
    file:close()
    return bytes
end

local function task2_write_progress_bytes(bytes)
    local file = assert(io.open(objective_progress_path, 'wb'))
    file:write(bytes or '')
    file:close()
end

local function task2_last_progress_line()
    local line = ''
    for candidate in task2_progress_bytes():gmatch('[^\r\n]+') do line = candidate end
    return line
end

local function task2_last_progress_line_for(native_key)
    local line = ''
    local marker = '\t' .. tostring(native_key) .. '\t'
    for candidate in task2_progress_bytes():gmatch('[^\r\n]+') do
        if candidate:find(marker, 1, true) ~= nil then line = candidate end
    end
    return line
end

local function task2_v2_progress_row(native_key, step_order, action_order, progress_count,
        overrides)
    overrides = overrides or {}
    local step_id = overrides.step_id
        or ('%s:step-%03d'):format(native_key, step_order)
    local action_id = overrides.action_id
        or ('%s:claim-%02d'):format(step_id, action_order)
    return table.concat({
        'v2',
        overrides.character_identity or current_identity,
        tostring(overrides.world_id or current_world_id),
        native_key,
        overrides.progression_revision or 'task2-progression-revision',
        step_id,
        tostring(step_order),
        action_id,
        tostring(action_order),
        tostring(progress_count),
    }, '\t')
end

task2_restore_inventory_cursor = function()
    task2_write_progress_bytes(task2_v2_progress_row(
        "mission:San d'Oria:1", 7, 1, 0) .. '\n')
    reload_navigation_module()
end

local task2_original_source_steps_for_reducer = accessxi.objective_guides.source_route_steps
local task2_original_destinations_for_reducer = accessxi.objective_guides.objective_destinations
local task2_original_automatic_step_for_reducer = accessxi.objective_guides.automatic_step_id
local task2_original_progression_actions_for_reducer = accessxi.objective_guides.progression_actions
local task2_reducer_scenario = ''

local function task2_typed_step(native_key, order, action, relationship, target, target_kind, values)
    values = values or {}
    local step_id = ('%s:step-%03d'):format(native_key, order)
    local claim_id = step_id .. ':claim-01'
    local step = T{
        stable_step_id = step_id,
        order = order,
        comparison = 'corroborated',
        action = action,
        entities = target ~= '' and T{ target } or T{},
        zones = values.zone_name ~= nil and T{ values.zone_name } or T{},
        items = values.items or T{},
        key_items = values.key_items or T{},
        primary_instruction = values.instruction or (action .. ' ' .. target),
        material = true,
        observable = values.observable ~= false,
        boundary = values.boundary or '',
        destination_zone_name = values.destination_zone_name or '',
        destination_zone_id = values.destination_zone_id,
        route_ready = values.route_ready == true,
        count_mode = values.count_mode or 'single',
        required_count = tonumber(values.required_count) or 1,
        count_explicit = values.count_explicit == true
            or (tonumber(values.required_count) or 1) > 1,
        typed_claims = T{
            T{
                stable_claim_id = claim_id,
                order = 1,
                action = action,
                relationship = relationship,
                target = target,
                target_kind = target_kind,
                items = values.items or T{},
                key_items = values.key_items or T{},
                zones = values.zone_name ~= nil and T{ values.zone_name } or T{},
                destination_zone_name = values.destination_zone_name or '',
                destination_zone_id = values.destination_zone_id,
                material = true,
                observable = values.observable ~= false,
                boundary = values.boundary or '',
                count_mode = values.count_mode or 'single',
                required_count = tonumber(values.required_count) or 1,
                count_explicit = values.count_explicit == true
                    or (tonumber(values.required_count) or 1) > 1,
            },
        },
    }
    return step
end

local function task2_cid_candidate(native_key, order)
    local step_id = ('%s:step-%03d'):format(native_key, order)
    return T{
        candidate_id = step_id .. ':claim-01:candidate:cid',
        action_id = step_id .. ':claim-01',
        group_id = '',
        destination_id = 'npc:v1:237:17772593',
        action = 'talk',
        zone = 237,
        zone_name = 'Metalworks',
        target_name = 'Cid',
        target_kind = 'npc',
        target_point = T{ -12.598, 2.430, -10.988 },
        raw_identity = 'lsb:npc_list:17772593',
        raw_spawn_ids = T{ 17772593 },
        label = 'Cid',
        arrival_instruction = 'Talk to Cid.',
        guide_step_id = step_id,
        guide_step_order = order,
        classification = 'catalogue-candidate',
    }
end

local function task2_named_candidate(native_key, order, values)
    values = values or {}
    local step_id = ('%s:step-%03d'):format(native_key, order)
    local target_name = values.target_name or 'Naji'
    local target_key = task2_flat_target_key(target_name)
    local suffix = values.suffix or target_key
    return T{
        candidate_id = step_id .. ':claim-01:candidate:' .. suffix,
        action_id = step_id .. ':claim-01',
        group_id = values.group_id or (step_id .. ':claim-01:zone:'
            .. tostring(values.zone or 237)),
        destination_id = values.destination_id
            or ('npc:v1:%d:%d'):format(values.zone or 237, values.server_id or 17772594),
        action = values.action or 'talk',
        zone = values.zone or 237,
        zone_name = values.zone_name or 'Metalworks',
        target_name = target_name,
        target_kind = values.target_kind or 'npc',
        target_point = deep_copy(values.target_point or T{ -10, 2, -10 }),
        raw_identity = values.raw_identity or ('fixture:' .. suffix),
        raw_spawn_ids = deep_copy(values.raw_spawn_ids or T{ values.server_id or 17772594 }),
        transport_id = values.transport_id or '',
        battlefield_id = values.battlefield_id or '',
        metadata_class = values.metadata_class or '',
        label = target_name,
        arrival_instruction = values.arrival_instruction or ('Interact with ' .. target_name .. '.'),
        guide_step_id = step_id,
        guide_step_order = order,
        classification = 'catalogue-candidate',
    }
end

local function task2_travel_candidate(native_key)
    local step_id = native_key .. ':step-001'
    return T{
        candidate_id = step_id .. ':claim-01:candidate:ghelsba',
        action_id = step_id .. ':claim-01',
        group_id = '',
        destination_id = 'zone:v1:140:ghelsba-outpost',
        action = 'travel',
        zone = 140,
        zone_name = 'Ghelsba Outpost',
        target_name = 'Ghelsba Outpost',
        target_kind = 'zone',
        target_point = T{ 0, 0, 0 },
        label = 'Ghelsba Outpost',
        arrival_instruction = 'Travel to Ghelsba Outpost.',
        guide_step_id = step_id,
        guide_step_order = 1,
        classification = 'catalogue-candidate',
    }
end

local function task2_enemy_candidate(native_key, order)
    local step_id = ('%s:step-%03d'):format(native_key, order)
    return T{
        candidate_id = step_id .. ':claim-01:candidate:orcish-fodder',
        action_id = step_id .. ':claim-01',
        group_id = '',
        destination_id = 'enemy:v1:100:16909060',
        action = 'fight',
        zone = 100,
        zone_name = 'West Ronfaure',
        target_name = 'Orcish Fodder',
        target_kind = 'enemy',
        target_point = T{ 10, 20, 0 },
        raw_identity = 'lsb:mob_spawn_points:task2-orcish-fodder',
        raw_spawn_ids = T{
            0x01020304, 0x01020305, 0x01020306, 0x01020307,
            0x01020308, 0x01020309, 0x01020400,
        },
        cluster_policy_version = 'complete-link-v1-h120-y24',
        label = 'Orcish Fodder',
        arrival_instruction = 'Defeat Orcish Fodder.',
        guide_step_id = step_id,
        guide_step_order = order,
        classification = 'catalogue-candidate',
    }
end

local function task2_progression_catalogue_row(candidate)
    candidate = candidate or {}
    return T{
        destination_id = candidate.destination_id or '',
        zone_id = tonumber(candidate.zone) or 0,
        zone_name = candidate.zone_name or '',
        target_name = candidate.target_name or '',
        target_kind = candidate.target_kind or '',
        target_key = task2_flat_target_key(candidate.target_name),
        target_point = deep_copy(candidate.target_point or T{}),
        raw_identity = candidate.raw_identity or '',
        raw_spawn_ids = deep_copy(candidate.raw_spawn_ids or T{}),
        cluster_policy_version = candidate.cluster_policy_version or '',
        transport_id = candidate.transport_id or '',
        battlefield_id = candidate.battlefield_id or '',
        metadata_class = candidate.metadata_class or '',
        group_id = candidate.group_id or '',
        arrival_instruction = candidate.arrival_instruction or '',
    }
end

local function task2_scenario_steps(native_key)
    local prerequisite_one = task2_typed_step(native_key, 1, 'talk', 'talk-to', 'Naji', 'npc', {
        zone_name = 'Metalworks', instruction = 'Talk to Naji before Cid.',
    })
    local cid_two = task2_typed_step(native_key, 2, 'talk', 'talk-to', 'Cid', 'npc', {
        zone_name = 'Metalworks', instruction = 'Talk to Cid.',
    })
    local wait_three = task2_typed_step(native_key, 3, 'wait', 'wait-for', '', '', {
        instruction = 'Wait for Cid to finish.', observable = false,
    })
    if native_key == 'quest:sandoria:2'
        and (task2_reducer_scenario == 'later-unique'
            or task2_reducer_scenario == 'later-repeated'
            or task2_reducer_scenario == 'later-cross-objective'
            or task2_reducer_scenario == 'later-branch-boundary'
            or task2_reducer_scenario == 'later-battlefield-boundary'
            or task2_reducer_scenario == 'later-transport-boundary'
            or task2_reducer_scenario == 'later-unobservable-boundary') then
        local first = prerequisite_one
        if task2_reducer_scenario == 'later-battlefield-boundary' then
            first = task2_typed_step(native_key, 1, 'examine', 'examine-object',
                'Battlefield Gate', 'object', {
                    zone_name = 'Ghelsba Outpost', instruction = 'Enter the battlefield.',
                })
        elseif task2_reducer_scenario == 'later-transport-boundary' then
            first = task2_typed_step(native_key, 1, 'travel', 'use-transport',
                'Airship Door', 'transport', {
                    zone_name = "Port San d'Oria", instruction = 'Board the airship.',
                })
        elseif task2_reducer_scenario == 'later-unobservable-boundary' then
            first = task2_typed_step(native_key, 1, 'wait', 'wait-for', '', '', {
                instruction = 'Wait for an unobservable prerequisite.', observable = false,
            })
        end
        local result = T{ first, cid_two, wait_three }
        if task2_reducer_scenario == 'later-repeated' then
            result:append(task2_typed_step(native_key, 4, 'talk', 'talk-to', 'Cid', 'npc', {
                zone_name = 'Metalworks', instruction = 'Talk to Cid again.',
            }))
        end
        return result
    end
    if native_key == "mission:San d'Oria:1"
        and task2_reducer_scenario == 'later-cross-objective' then
        return T{ prerequisite_one, cid_two, wait_three }
    end
    if native_key == 'quest:sandoria:2' and task2_reducer_scenario == 'current-interaction' then
        return T{
            task2_typed_step(native_key, 1, 'talk', 'talk-to', 'Cid', 'npc', {
                zone_name = 'Metalworks', instruction = 'Talk to Cid.',
            }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait for the next instruction.', observable = false,
            }),
        }
    end
    if native_key == 'quest:sandoria:2'
        and task2_reducer_scenario == 'migration-ambiguous' then
        local ambiguous = task2_typed_step(native_key, 1, 'talk', 'talk-to',
            'Cid', 'npc', {
                zone_name = 'Metalworks', instruction = 'Talk to Cid, then examine the console.',
            })
        ambiguous.typed_claims:append(T{
            stable_claim_id = native_key .. ':step-001:claim-02',
            order = 2,
            action = 'examine',
            relationship = 'examine-object',
            target = 'Control Console',
            target_kind = 'object',
            items = T{}, key_items = T{}, zones = T{ 'Metalworks' },
            material = true, observable = true, boundary = '',
            count_mode = 'single', required_count = 1,
            count_explicit = false,
        })
        return T{
            ambiguous,
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after the console.', observable = false,
            }),
        }
    end
    if native_key == 'quest:sandoria:2' and task2_reducer_scenario == 'key-item' then
        return T{
            task2_typed_step(native_key, 1, 'obtain', 'obtain-key-item',
                'Orcish Hut Key', 'key-item', {
                    key_items = T{ 'Orcish Hut Key' },
                    instruction = 'Obtain the Orcish Hut Key.',
                }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after obtaining the key item.', observable = false,
            }),
        }
    end
    if native_key == 'quest:sandoria:2' and task2_reducer_scenario == 'travel' then
        return T{
            task2_typed_step(native_key, 1, 'travel', 'travel-to',
                'Ghelsba Outpost', 'zone', {
                    zone_name = 'Ghelsba Outpost',
                    destination_zone_name = 'Ghelsba Outpost', destination_zone_id = 140,
                    instruction = 'Travel to Ghelsba Outpost.',
                }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after reaching Ghelsba Outpost.', observable = false,
            }),
        }
    end
    if native_key == 'quest:sandoria:2'
        and task2_reducer_scenario == 'transport-current' then
        return T{
            task2_typed_step(native_key, 1, 'travel', 'use-transport',
                'Airship Door', 'transport', {
                    zone_name = "Port San d'Oria",
                    destination_zone_name = 'Ghelsba Outpost', destination_zone_id = 140,
                    instruction = 'Use the Airship Door to travel to Ghelsba Outpost.',
                }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after the committed transport.', observable = false,
            }),
        }
    end
    if native_key == 'quest:sandoria:2'
        and (task2_reducer_scenario == 'kill-current'
            or task2_reducer_scenario == 'kill-counted'
            or task2_reducer_scenario == 'kill-terminal-single'
            or task2_reducer_scenario == 'kill-repeated'
            or task2_reducer_scenario == 'kill-cross-objective') then
        if task2_reducer_scenario == 'kill-terminal-single' then
            return T{
                task2_typed_step(native_key, 1, 'fight', 'defeat-enemy',
                    'Orcish Fodder', 'enemy', {
                        zone_name = 'West Ronfaure', instruction = 'Defeat Orcish Fodder.',
                    }),
            }
        end
        if task2_reducer_scenario == 'kill-current'
            or task2_reducer_scenario == 'kill-counted' then
            return T{
                task2_typed_step(native_key, 1, 'fight', 'defeat-enemy',
                    'Orcish Fodder', 'enemy', {
                        zone_name = 'West Ronfaure', instruction = 'Defeat Orcish Fodder.',
                        count_mode = task2_reducer_scenario == 'kill-counted'
                            and 'credited-defeat' or 'single',
                        required_count = task2_reducer_scenario == 'kill-counted' and 5 or 1,
                    }),
                task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                    instruction = 'Wait after the battle.', observable = false,
                }),
            }
        end
        return T{
            task2_typed_step(native_key, 1, 'wait', 'wait-for', '', '', {
                instruction = 'Wait before the battle.', observable = false,
            }),
            task2_typed_step(native_key, 2, 'fight', 'defeat-enemy',
                'Orcish Fodder', 'enemy', {
                    zone_name = 'West Ronfaure', instruction = 'Defeat Orcish Fodder.',
                }),
            task2_typed_step(native_key, 3, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after the battle.', observable = false,
            }),
            task2_reducer_scenario == 'kill-repeated'
                and task2_typed_step(native_key, 4, 'fight', 'defeat-enemy',
                    'Orcish Fodder', 'enemy', {
                        zone_name = 'West Ronfaure', instruction = 'Defeat Orcish Fodder again.',
                    }) or nil,
        }
    end
    if native_key == 'quest:sandoria:2'
        and task2_reducer_scenario == 'inventory-counted' then
        return T{
            task2_typed_step(native_key, 1, 'obtain', 'obtain-item',
                'Test Crystal', 'item', {
                    items = T{ 'Test Crystal' },
                    instruction = 'Obtain three Test Crystals.',
                    count_mode = 'inventory-gain',
                    required_count = 3,
                }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after obtaining the crystals.', observable = false,
            }),
        }
    end
    if native_key == 'quest:sandoria:2'
        and task2_reducer_scenario == 'explicit-one-single' then
        return T{
            task2_typed_step(native_key, 1, 'fight', 'defeat-enemy',
                'Orcish Fodder', 'enemy', {
                    zone_name = 'West Ronfaure', instruction = 'Defeat exactly one Orcish Fodder.',
                    count_mode = 'single', required_count = 1, count_explicit = true,
                }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after the explicit single defeat.', observable = false,
            }),
        }
    end
    if native_key == 'quest:sandoria:2'
        and (task2_reducer_scenario == 'trade-single'
            or task2_reducer_scenario == 'delivery-single') then
        local relationship = task2_reducer_scenario == 'trade-single'
            and 'trade-item' or 'deliver-item'
        return T{
            task2_typed_step(native_key, 1, 'trade', relationship, 'Cid', 'npc', {
                zone_name = 'Metalworks', items = T{ 'Test Crystal' },
                instruction = task2_reducer_scenario == 'trade-single'
                    and 'Trade three Test Crystals to Cid.'
                    or 'Deliver three Test Crystals to Cid.',
                count_mode = 'single', required_count = 1, count_explicit = true,
            }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after the server-accepted trade.', observable = false,
            }),
        }
    end
    if native_key == "mission:San d'Oria:1"
        and task2_reducer_scenario == 'kill-cross-objective' then
        return T{
            task2_typed_step(native_key, 1, 'wait', 'wait-for', '', '', {
                instruction = 'Wait before the battle.', observable = false,
            }),
            task2_typed_step(native_key, 2, 'fight', 'defeat-enemy',
                'Orcish Fodder', 'enemy', {
                    zone_name = 'West Ronfaure', instruction = 'Defeat Orcish Fodder.',
                }),
        }
    end
    if native_key == "mission:San d'Oria:1"
        and task2_reducer_scenario == 'mission-replacement' then
        return T{
            task2_typed_step(native_key, 1, 'travel', 'travel-to',
                'Ghelsba Outpost', 'zone', {
                    zone_name = 'Ghelsba Outpost',
                    destination_zone_name = 'Ghelsba Outpost', destination_zone_id = 140,
                    instruction = 'Travel to Ghelsba Outpost.',
                }),
            task2_typed_step(native_key, 2, 'wait', 'wait-for', '', '', {
                instruction = 'Wait after reaching Ghelsba Outpost.', observable = false,
            }),
        }
    end
    return nil
end

local function task2_scenario_progression_actions(native_key)
    local steps = task2_scenario_steps(native_key)
    if steps == nil then return nil end
    local actions = T{}
    for _, step in ipairs(steps) do
        for _, claim in ipairs(step.typed_claims or T{}) do
            local catalogue = T{}
            if claim.target_kind == 'npc' and claim.target == 'Cid' then
                catalogue:append(task2_progression_catalogue_row(
                    task2_cid_candidate(native_key, step.order)))
            elseif claim.target_kind == 'npc' and claim.target == 'Naji' then
                catalogue:append(task2_progression_catalogue_row(task2_named_candidate(
                    native_key, step.order, { target_name = 'Naji', server_id = 17772594,
                        suffix = 'naji-primary', group_id = step.stable_step_id .. ':path-a' })))
                if task2_reducer_scenario == 'later-branch-boundary' then
                    catalogue:append(task2_progression_catalogue_row(task2_named_candidate(
                        native_key, step.order, { target_name = 'Naji', server_id = 17772595,
                            suffix = 'naji-alternate', group_id = step.stable_step_id .. ':path-b',
                            destination_id = 'npc:v1:237:17772595',
                            target_point = T{ 25, 2, -15 } })))
                end
            elseif claim.target == 'Battlefield Gate' then
                catalogue:append(task2_progression_catalogue_row(task2_named_candidate(
                    native_key, step.order, { target_name = 'Battlefield Gate',
                        target_kind = 'object', zone = 140, zone_name = 'Ghelsba Outpost',
                        server_id = 17350951, battlefield_id = 'task2-battlefield',
                        suffix = 'battlefield-gate' })))
            elseif claim.target == 'Airship Door' then
                catalogue:append(task2_progression_catalogue_row(task2_named_candidate(
                    native_key, step.order, { target_name = 'Airship Door',
                        target_kind = 'transport', zone = 231,
                        zone_name = "Port San d'Oria", server_id = 17723406,
                        transport_id = 'task2-airship', suffix = 'airship-door' })))
            elseif claim.target_kind == 'zone' and claim.target == 'Ghelsba Outpost' then
                catalogue:append(task2_progression_catalogue_row(
                    task2_travel_candidate(native_key)))
            elseif claim.target_kind == 'enemy' and claim.target == 'Orcish Fodder' then
                catalogue:append(task2_progression_catalogue_row(
                    task2_enemy_candidate(native_key, step.order)))
            end
            actions:append(T{
                step_id = step.stable_step_id,
                step_order = step.order,
                action_id = claim.stable_claim_id,
                action_order = claim.order,
                order = #actions + 1,
                action = claim.action,
                relationship = claim.relationship,
                target = claim.target,
                target_key = task2_flat_target_key(claim.target),
                target_kind = claim.target_kind,
                npcs = claim.target_kind == 'npc' and T{ claim.target } or T{},
                objects = claim.target_kind == 'object' and T{ claim.target } or T{},
                enemies = claim.target_kind == 'enemy' and T{ claim.target } or T{},
                zones = deep_copy(claim.zones or T{}),
                items = deep_copy(claim.items or T{}),
                key_items = deep_copy(claim.key_items or T{}),
                transports = claim.target_kind == 'transport' and T{ claim.target } or T{},
                grid_coordinates = T{},
                result_items = claim.relationship == 'obtain-item'
                    and deep_copy(claim.items or T{}) or T{},
                result_relation = claim.relationship == 'obtain-item' and 'obtain' or '',
                destination_zone_name = tostring(claim.destination_zone_name or ''),
                destination_zone_id = tonumber(claim.destination_zone_id) or 0,
                instruction = step.primary_instruction,
                count_mode = claim.count_mode or 'single',
                required_count = tonumber(claim.required_count) or 1,
                count_explicit = claim.count_explicit == true,
                material = true,
                source_authority = 'bg',
                field_sources = T{
                    action = 'bg', relationship = 'bg', target = 'bg',
                    target_key = 'bg', target_kind = 'bg', npcs = 'bg', objects = 'bg',
                    enemies = 'bg', zones = 'bg', items = 'bg', key_items = 'bg',
                    transports = 'bg', grid_coordinates = 'bg', result_items = 'bg',
                    result_relation = 'bg',
                    destination_zone_name = tostring(claim.destination_zone_name or '') ~= ''
                        and 'bg' or '',
                    destination_zone_id = tonumber(claim.destination_zone_id) ~= nil
                        and tonumber(claim.destination_zone_id) > 0 and 'bg' or '',
                    instruction = 'bg', count_mode = 'bg',
                    required_count = 'bg', count_explicit = 'bg',
                    catalogue = #catalogue > 0 and 'catalogue' or '',
                },
                source_revisions = T{ bg = 4001, ffxiclopedia = 4002 },
                source_action_span_ids = T{
                    step.stable_step_id .. ':bg:action-' .. ('%02d'):format(claim.order),
                    step.stable_step_id .. ':ffxiclopedia:action-' .. ('%02d'):format(claim.order),
                },
                catalogue = deep_copy(catalogue),
            })
        end
    end
    return actions
end

accessxi.objective_guides.progression_actions = function(self, native_key)
    local actions = task2_scenario_progression_actions(native_key)
    if actions ~= nil then return deep_copy(actions) end
    if type(task2_original_progression_actions_for_reducer) == 'function' then
        return task2_original_progression_actions_for_reducer(self, native_key)
    end
    return T{}
end

accessxi.objective_guides.source_route_steps = function(self, native_key)
    local rows = task2_scenario_steps(native_key)
    if rows ~= nil then
        rows = deep_copy(rows)
        if (task2_reducer_scenario == 'travel'
                or task2_reducer_scenario == 'transport-current'
                or task2_reducer_scenario == 'mission-replacement')
            and rows[1] ~= nil then
            rows[1].action = 'poisoned-legacy-action'
            rows[1].entities = T{ 'Poisoned Legacy Target' }
            rows[1].zones = T{ 'Poisoned Legacy Source Zone' }
            rows[1].primary_instruction = 'Poisoned legacy route prose.'
            rows[1].destination_zone_name = 'Poisoned Legacy Destination'
            rows[1].destination_zone_id = 999
            if type(rows[1].typed_claims) == 'table' and rows[1].typed_claims[1] ~= nil then
                rows[1].typed_claims[1].action = 'poisoned-legacy-action'
                rows[1].typed_claims[1].relationship = 'poisoned-legacy-relationship'
                rows[1].typed_claims[1].target = 'Poisoned Legacy Target'
                rows[1].typed_claims[1].target_kind = 'object'
                rows[1].typed_claims[1].zones = T{ 'Poisoned Legacy Source Zone' }
                rows[1].typed_claims[1].destination_zone_name
                    = 'Poisoned Legacy Destination'
                rows[1].typed_claims[1].destination_zone_id = 999
            end
        end
        return rows
    end
    return task2_original_source_steps_for_reducer(self, native_key)
end
accessxi.objective_guides.objective_destinations = function(self, native_key)
    if native_key == 'quest:sandoria:2' then
        if task2_reducer_scenario == 'later-unique'
            or task2_reducer_scenario == 'later-cross-objective' then
            return T{ task2_cid_candidate(native_key, 2) }
        elseif task2_reducer_scenario == 'later-repeated' then
            return T{ task2_cid_candidate(native_key, 2), task2_cid_candidate(native_key, 4) }
        elseif task2_reducer_scenario == 'current-interaction' then
            return T{ task2_cid_candidate(native_key, 1) }
        elseif task2_reducer_scenario == 'trade-single'
            or task2_reducer_scenario == 'delivery-single' then
            return T{ task2_cid_candidate(native_key, 1) }
        elseif task2_reducer_scenario == 'later-branch-boundary' then
            return T{
                task2_named_candidate(native_key, 1, { target_name = 'Naji',
                    server_id = 17772594, suffix = 'naji-primary',
                    group_id = native_key .. ':step-001:path-a' }),
                task2_named_candidate(native_key, 1, { target_name = 'Naji',
                    server_id = 17772595, suffix = 'naji-alternate',
                    group_id = native_key .. ':step-001:path-b',
                    destination_id = 'npc:v1:237:17772595', target_point = T{ 25, 2, -15 } }),
                task2_cid_candidate(native_key, 2),
            }
        elseif task2_reducer_scenario == 'later-battlefield-boundary' then
            return T{
                task2_named_candidate(native_key, 1, { target_name = 'Battlefield Gate',
                    target_kind = 'object', zone = 140, zone_name = 'Ghelsba Outpost',
                    server_id = 17350951, battlefield_id = 'task2-battlefield',
                    suffix = 'battlefield-gate' }),
                task2_cid_candidate(native_key, 2),
            }
        elseif task2_reducer_scenario == 'later-transport-boundary' then
            return T{
                task2_named_candidate(native_key, 1, { target_name = 'Airship Door',
                    target_kind = 'transport', zone = 231, zone_name = "Port San d'Oria",
                    server_id = 17723406, transport_id = 'task2-airship',
                    suffix = 'airship-door' }),
                task2_cid_candidate(native_key, 2),
            }
        elseif task2_reducer_scenario == 'later-unobservable-boundary' then
            return T{ task2_cid_candidate(native_key, 2) }
        elseif task2_reducer_scenario == 'travel' then
            return T{ task2_travel_candidate(native_key) }
        elseif task2_reducer_scenario == 'transport-current' then
            return T{ task2_named_candidate(native_key, 1, {
                target_name = 'Airship Door', target_kind = 'transport', zone = 231,
                zone_name = "Port San d'Oria", server_id = 17723406,
                transport_id = 'task2-airship', suffix = 'airship-door' }) }
        elseif task2_reducer_scenario == 'kill-current'
            or task2_reducer_scenario == 'kill-counted'
            or task2_reducer_scenario == 'kill-terminal-single'
            or task2_reducer_scenario == 'explicit-one-single' then
            return T{ task2_enemy_candidate(native_key, 1) }
        elseif task2_reducer_scenario == 'kill-repeated' then
            return T{ task2_enemy_candidate(native_key, 2), task2_enemy_candidate(native_key, 4) }
        elseif task2_reducer_scenario == 'kill-cross-objective' then
            return T{ task2_enemy_candidate(native_key, 2) }
        end
    elseif native_key == "mission:San d'Oria:1" then
        if task2_reducer_scenario == 'later-cross-objective' then
            return T{ task2_cid_candidate(native_key, 2) }
        elseif task2_reducer_scenario == 'kill-cross-objective' then
            return T{ task2_enemy_candidate(native_key, 2) }
        elseif task2_reducer_scenario == 'mission-replacement' then
            return T{ task2_travel_candidate(native_key) }
        end
    end
    return task2_original_destinations_for_reducer(self, native_key)
end
accessxi.objective_guides.automatic_step_id = function(self, native_key, stage)
    if task2_scenario_steps(native_key) ~= nil then return '' end
    return task2_original_automatic_step_for_reducer(self, native_key, stage)
end

local function task2_reset_reducer_scenario(name)
    task2_reducer_scenario = name
    current_player = 'Alpha'
    current_identity = 'alpha:1001'
    current_world_id = 1001
    current_session_epoch = 77
    current_nation = 0
    accessxi.mission_quest_nav_player = current_player
    accessxi.mission_quest_nav_identity = current_identity
    accessxi.mission_packet_player = current_player
    accessxi.mission_packet_identity = current_identity
    accessxi.mission_packet_source = 'packet_in_056'
    accessxi.mission_packet_session_epoch = current_session_epoch
    accessxi.mission_packet_main = { nation = 0, nation_mission = 0, port = 0xFFFF }
    accessxi.quest_packet_player = current_player
    accessxi.quest_packet_identity = current_identity
    accessxi.quest_packet_source = 'packet_in_056'
    accessxi.quest_packet_session_epoch = current_session_epoch
    quest_entries['sandoria:current'].identity = current_identity
    quest_entries['sandoria:current'].session_epoch = current_session_epoch
    quest_entries['sandoria:current'].source = 'packet_in_056'
    quest_entries['sandoria:current'].words = words_with(2)
    quest_entries['sandoria:completed'].identity = current_identity
    quest_entries['sandoria:completed'].session_epoch = current_session_epoch
    quest_entries['sandoria:completed'].source = 'packet_in_056'
    quest_entries['sandoria:completed'].words = words_with()
    accessxi.quest_packet_logs = quest_entries
    accessxi.key_items_packet_player = current_player
    accessxi.key_items_packet_identity = current_identity
    accessxi.key_items_packet_tables = {
        [0] = {
            flags = string.rep('\0', 64), source = 'packet_in_055',
            identity = current_identity, session_epoch = current_session_epoch,
        },
    }
    accessxi.inventory_packet_source = 'packet_in_inventory'
    accessxi.inventory_packet_identity = current_identity
    accessxi.inventory_packet_session_epoch = current_session_epoch
    accessxi.nav_destination = nil
    accessxi.nav_active = false
    owned_key_items[157] = nil
    objective_inventory_counts_by_name['orcish axe'] = 0
    objective_inventory_counts_by_name['test crystal'] = 0
    os.remove(objective_progress_path)
    accessxi.nav_catalog_revision = (tonumber(accessxi.nav_catalog_revision) or 0) + 1
    accessxi.objective_progress_revision = 1
    reload_navigation_module()
end

-- Legacy objective progress is a separate four-field file from GuideState's
-- three-field manual browsing cursor.  Migrate only the current positive
-- owner/World and active topology, append a ten-field v2 record, and never
-- rewrite the legacy row in place.
task2_reset_reducer_scenario('current-interaction')
local task2_legacy_single = table.concat({
    current_identity,
    'quest:sandoria:2',
    'quest:sandoria:2:step-001',
    '1',
}, '\t') .. '\n'
task2_write_progress_bytes(task2_legacy_single)
local task2_migrated_single = accessxi.nav_mission_quest_active_items('quest')
local task2_migrated_single_item = find(task2_migrated_single, 'The Pickpocket')
task2_reducer_expect(type(task2_migrated_single_item) == 'table'
        and task2_migrated_single_item.objective_guide_step_id
            == 'quest:sandoria:2:step-002',
    'single-action legacy cursor did not resume at the next material action')
task2_reducer_expect(task2_progress_bytes() == task2_legacy_single
        .. task2_v2_progress_row('quest:sandoria:2', 2, 1, 0) .. '\n',
    'single-action legacy cursor did not append the exact ten-field v2 migration row')

task2_reset_reducer_scenario('migration-ambiguous')
local task2_legacy_ambiguous = table.concat({
    current_identity,
    'quest:sandoria:2',
    'quest:sandoria:2:step-001',
    '1',
}, '\t') .. '\n'
task2_write_progress_bytes(task2_legacy_ambiguous)
local task2_migrated_ambiguous = accessxi.nav_mission_quest_active_items('quest')
local task2_migrated_ambiguous_item = find(task2_migrated_ambiguous, 'The Pickpocket')
task2_reducer_expect(type(task2_migrated_ambiguous_item) == 'table'
        and task2_migrated_ambiguous_item.objective_guide_step_id
            == 'quest:sandoria:2:step-001',
    'ambiguous multi-action legacy step was treated as fully completed')
task2_reducer_expect(task2_progress_bytes() == task2_legacy_ambiguous
        .. task2_v2_progress_row('quest:sandoria:2', 1, 1, 0) .. '\n',
    'ambiguous legacy step did not append a v2 reset immediately before that step')

task2_reset_reducer_scenario('current-interaction')
local task2_foreign_legacy = table.concat({
    'beta:1001',
    'quest:sandoria:2',
    'quest:sandoria:2:step-001',
    '1',
}, '\t') .. '\n'
task2_write_progress_bytes(task2_foreign_legacy)
accessxi.nav_mission_quest_active_items('quest')
task2_reducer_expect(task2_progress_bytes() == task2_foreign_legacy,
    'foreign-character legacy cursor migrated into the current owner/World')

-- v2 load validation is fail-closed.  None of these malformed records may
-- become the current counted action or be normalized silently.
for _, invalid in ipairs(T{
    { label = 'negative progress_count', count = -1 },
    { label = 'noninteger progress_count', count = '1.5' },
    { label = 'progress_count above required_count', count = 6 },
    { label = 'terminal count on a nonterminal action', count = 5 },
    { label = 'progression revision mismatch', count = 2,
        overrides = { progression_revision = 'stale-task2-revision' } },
    { label = 'action ID mismatch', count = 2,
        overrides = { action_id = 'quest:sandoria:2:step-001:claim-99' } },
    { label = 'wrong durable owner', count = 2,
        overrides = { character_identity = 'beta:1001' } },
    { label = 'wrong durable World', count = 2,
        overrides = { world_id = 2002 } },
    { label = 'step ID/order mismatch', count = 2, step_order = 2,
        overrides = { step_id = 'quest:sandoria:2:step-001',
            action_id = 'quest:sandoria:2:step-001:claim-01' } },
    { label = 'action ID/order mismatch', count = 2, action_order = 2,
        overrides = { action_id = 'quest:sandoria:2:step-001:claim-01' } },
}) do
    task2_reset_reducer_scenario('kill-counted')
    local invalid_row = task2_v2_progress_row(
        'quest:sandoria:2', invalid.step_order or 1, invalid.action_order or 1,
        invalid.count, invalid.overrides) .. '\n'
    task2_write_progress_bytes(invalid_row)
    reload_navigation_module()
    local invalid_items = accessxi.nav_mission_quest_active_items('quest')
    local invalid_item = find(invalid_items, 'The Pickpocket')
    task2_reducer_expect(type(invalid_item) == 'table'
            and invalid_item.objective_guide_step_id == 'quest:sandoria:2:step-001'
            and task2_progress_bytes() == invalid_row,
        invalid.label .. ' did not fail closed at the first counted action')
end

for _, width in ipairs(T{ 9, 11 }) do
    task2_reset_reducer_scenario('kill-counted')
    local fields = T{
        'v2', current_identity, tostring(current_world_id), 'quest:sandoria:2',
        'task2-progression-revision', 'quest:sandoria:2:step-001', '1',
        'quest:sandoria:2:step-001:claim-01', '1',
    }
    if width == 11 then fields:append('2'); fields:append('unexpected-field') end
    local invalid_width_row = table.concat(fields, '\t') .. '\n'
    task2_write_progress_bytes(invalid_width_row)
    reload_navigation_module()
    local width_item = find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket')
    task2_reducer_expect(type(width_item) == 'table'
            and width_item.objective_guide_step_id == 'quest:sandoria:2:step-001'
            and task2_progress_bytes() == invalid_width_row,
        ('%d-field v2 cursor was not rejected without rewriting history'):format(width))
end

-- A malformed append after a valid cursor must not erase the latest valid
-- state.  The next accepted causal unit continues from count two to count
-- three while the invalid trailing history remains untouched.
task2_reset_reducer_scenario('kill-counted')
local task2_valid_partial_row = task2_v2_progress_row(
    'quest:sandoria:2', 1, 1, 2) .. '\n'
local task2_invalid_trailing_row = table.concat({
    'v2', current_identity, tostring(current_world_id), 'quest:sandoria:2',
    'task2-progression-revision', 'quest:sandoria:2:step-001', '1',
    'quest:sandoria:2:step-001:claim-01', '1',
}, '\t') .. '\n'
task2_write_progress_bytes(task2_valid_partial_row .. task2_invalid_trailing_row)
reload_navigation_module()
local latest_valid_item = find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket')
task2_reducer_expect(type(latest_valid_item) == 'table'
        and latest_valid_item.objective_guide_step_id == 'quest:sandoria:2:step-001',
    'invalid trailing cursor hid the latest valid current action')
local latest_valid_credit = task2_signal('kill-credit', {
    actor_server_id = 0x0A0B0C0D, actor_name = 'Alpha', actor_is_local = true,
    actor_is_party = false, target_server_id = 0x01020501,
    target_name = 'Orcish Fodder', zone_id = 100, packet_id = 0x029,
    message_id = 6, battle_sequence = 7001, causal_id = '0x029:6:01020501:7001',
})
task2_reducer_expect(task2_reduce(latest_valid_credit,
        'causal unit after invalid trailing cursor'),
    'latest valid cursor was not used after an invalid trailing row')
task2_reducer_expect(task2_last_progress_line()
        == task2_v2_progress_row('quest:sandoria:2', 1, 1, 3),
    'latest-valid cursor did not continue from partial count two')

task2_reset_reducer_scenario('')

do
    local interaction_values = {
        target_server_id = 17772593,
        target_name = 'Cid',
        zone_id = 237,
        event_id = 45001,
        menu_id = 45001,
    }

    task2_reset_reducer_scenario('later-unique')
    task2_reducer_expect(task2_reduce(task2_signal('interaction-start', interaction_values),
        'globally unique later interaction start'),
        'globally unique later Cid interaction was not armed')
    local changed_revision_finish = task2_signal('interaction-finish', interaction_values)
    changed_revision_finish.progression_revision = 'replacement-task2-revision'
    task2_reducer_expect(not task2_reduce(changed_revision_finish,
            'later interaction finish after native revision change'),
        'bounded future correlation crossed a native progression-revision boundary')
    task2_reducer_expect(task2_progress_bytes() == '',
        'revision-mismatched future finish wrote objective progress')
    task2_reset_reducer_scenario('later-unique')
    task2_reducer_expect(task2_reduce(task2_signal('interaction-start', interaction_values),
        'globally unique later interaction restart after revision boundary'),
        'fresh unique future interaction was not armed after revision-boundary reset')
    task2_reducer_expect(task2_reduce(task2_signal('interaction-finish', interaction_values),
        'globally unique later interaction finish'),
        'globally unique later Cid interaction did not reconcile wiki prerequisites')
    local unique_later_bytes = task2_progress_bytes()
    task2_reducer_expect(task2_last_progress_line()
            == task2_v2_progress_row('quest:sandoria:2', 3, 1, 0),
        'unique later interaction did not atomically persist the next current action')
    task2_reducer_expect(not task2_reduce(task2_signal('interaction-finish', interaction_values),
            'replayed later interaction finish'),
        'replayed later interaction advanced the same objective again')
    task2_reducer_expect(task2_progress_bytes() == unique_later_bytes,
        'replayed later interaction mutated persisted cursor state')

    task2_reset_reducer_scenario('later-repeated')
    task2_reducer_expect(not task2_reduce(task2_signal('interaction-start', interaction_values),
            'same-objective repeated-target start'),
        'same-objective repeated Cid target was treated as a unique future match')
    task2_reducer_expect(not task2_reduce(task2_signal('interaction-finish', interaction_values),
            'same-objective repeated-target finish'),
        'same-objective repeated Cid target advanced without unique correlation')
    task2_reducer_expect(task2_progress_bytes() == '',
        'ambiguous repeated target wrote objective progress')

    task2_reset_reducer_scenario('later-cross-objective')
    task2_reducer_expect(not task2_reduce(task2_signal('interaction-start', interaction_values),
            'cross-objective ambiguous start'),
        'one Cid event armed two compatible active objectives')
    task2_reducer_expect(not task2_reduce(task2_signal('interaction-finish', interaction_values),
            'cross-objective ambiguous finish'),
        'cross-objective ambiguous Cid event advanced an arbitrary objective')
    task2_reducer_expect(task2_progress_bytes() == '',
        'cross-objective ambiguous target wrote objective progress')

    for _, boundary in ipairs(T{
        { scenario = 'later-branch-boundary', label = 'branch' },
        { scenario = 'later-battlefield-boundary', label = 'battlefield' },
        { scenario = 'later-transport-boundary', label = 'transport' },
        { scenario = 'later-unobservable-boundary', label = 'unobservable action' },
    }) do
        task2_reset_reducer_scenario(boundary.scenario)
        task2_reducer_expect(not task2_reduce(task2_signal(
                'interaction-start', interaction_values), boundary.label .. ' boundary start'),
            'bounded future scan crossed an intervening ' .. boundary.label .. ' boundary')
        task2_reducer_expect(not task2_reduce(task2_signal(
                'interaction-finish', interaction_values), boundary.label .. ' boundary finish'),
            'finish without a valid arm crossed an intervening ' .. boundary.label .. ' boundary')
        task2_reducer_expect(task2_progress_bytes() == '',
            boundary.label .. ' boundary wrote suffix-fast-forward progress')
    end

    task2_reset_reducer_scenario('current-interaction')
    for _, mismatch in ipairs(T{
        { character_identity = '', label = 'missing character' },
        { character_identity = 'beta:1001', label = 'character' },
        { world_id = 0, label = 'zero World' },
        { world_id = 2002, label = 'World' },
        { session_epoch = 76, label = 'session' },
        { session_epoch = 0, label = 'zero session' },
    }) do
        local signal = task2_signal('interaction-start', interaction_values)
        signal.character_identity = mismatch.character_identity or signal.character_identity
        signal.world_id = mismatch.world_id or signal.world_id
        signal.session_epoch = mismatch.session_epoch ~= nil and mismatch.session_epoch or signal.session_epoch
        task2_reducer_expect(not task2_reduce(signal, mismatch.label .. ' mismatched start'),
            mismatch.label .. ' mismatched interaction start was accepted')
    end
    local stale_progression_start = task2_signal('interaction-start', interaction_values)
    stale_progression_start.progression_revision = 'stale-task2-progression-revision'
    task2_reducer_expect(not task2_reduce(stale_progression_start,
            'progression-revision mismatched start'),
        'stale progression_revision interaction start was accepted')
    task2_reducer_expect(task2_reduce(task2_signal('interaction-start', interaction_values),
        'owned current interaction start'), 'owned current interaction was not armed')
    for _, mismatch in ipairs(T{
        { character_identity = '', label = 'missing character' },
        { character_identity = 'beta:1001', label = 'character' },
        { world_id = 0, label = 'zero World' },
        { world_id = 2002, label = 'World' },
        { session_epoch = 78, label = 'session' },
        { target_server_id = 17772594, label = 'target server ID' },
        { zone_id = 238, label = 'zone' },
        { event_id = 45002, label = 'event' },
        { menu_id = 45002, label = 'menu' },
        { progression_revision = 'replacement-task2-revision', label = 'native revision' },
    }) do
        local signal = task2_signal('interaction-finish', interaction_values)
        signal.character_identity = mismatch.character_identity or signal.character_identity
        signal.world_id = mismatch.world_id or signal.world_id
        signal.session_epoch = mismatch.session_epoch or signal.session_epoch
        signal.target_server_id = mismatch.target_server_id or signal.target_server_id
        signal.zone_id = mismatch.zone_id or signal.zone_id
        signal.event_id = mismatch.event_id or signal.event_id
        signal.menu_id = mismatch.menu_id or signal.menu_id
        signal.progression_revision = mismatch.progression_revision or signal.progression_revision
        task2_reducer_expect(not task2_reduce(signal, mismatch.label .. ' mismatched finish'),
            mismatch.label .. ' mismatched interaction finish was accepted')
    end
    task2_reducer_expect(task2_reduce(task2_signal('interaction-finish', interaction_values),
        'owned current interaction finish'), 'owned current interaction did not advance')

    task2_reset_reducer_scenario('key-item')
    owned_key_items[157] = true
    accessxi.key_items_packet_key = 'key-items:task2-preexisting'
    accessxi.nav_mission_quest_active_items('quest')
    task2_reducer_expect(task2_progress_bytes() == '',
        'pre-existing key-item presence completed a cursor-entered acquisition claim')
    local key_values = {
        key_item_id = 157,
        key_item_name = 'Orcish Hut Key',
        before_owned = true,
        after_owned = true,
        snapshot_complete = true,
    }
    task2_reducer_expect(not task2_reduce(task2_signal('key-item-delta', key_values),
            'pre-existing key-item snapshot'),
        'unchanged pre-existing key-item ownership was accepted as acquisition')
    owned_key_items[157] = false
    key_values.before_owned = false
    key_values.after_owned = true
    for _, mismatch in ipairs(T{
        { character_identity = '', label = 'missing character' },
        { character_identity = 'beta:1001', label = 'character' },
        { world_id = 0, label = 'zero World' },
        { world_id = 2002, label = 'World' },
        { session_epoch = 0, label = 'zero session' },
        { session_epoch = 76, label = 'session' },
    }) do
        local signal = task2_signal('key-item-delta', key_values)
        signal.character_identity = mismatch.character_identity or signal.character_identity
        signal.world_id = mismatch.world_id or signal.world_id
        signal.session_epoch = mismatch.session_epoch or signal.session_epoch
        task2_reducer_expect(not task2_reduce(signal, mismatch.label .. ' mismatched key-item delta'),
            mismatch.label .. ' mismatched key-item delta was accepted')
    end
    owned_key_items[157] = true
    task2_reducer_expect(task2_reduce(task2_signal('key-item-delta', key_values),
        'owned key-item absent-to-present delta'),
        'current-session key-item absent-to-present delta did not advance')
    local key_progress_bytes = task2_progress_bytes()
    task2_reducer_expect(task2_last_progress_line()
            == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
        'accepted key-item delta did not atomically persist the next current action')
    reload_navigation_module()
    task2_reducer_expect(task2_progress_bytes() == key_progress_bytes,
        'key-item cursor was not stable across navigation-module reload')
    key_values.before_owned = true
    key_values.after_owned = false
    owned_key_items[157] = false
    task2_reducer_expect(not task2_reduce(task2_signal('key-item-delta', key_values),
            'key-item loss delta'), 'key-item loss was accepted as progression')
    task2_reducer_expect(task2_progress_bytes() == key_progress_bytes,
        'key-item loss rewound or rewrote the durable cursor')

    local function task2_expect_flat_destination_pair(native_key, expected_name,
            expected_id, label)
        local flat_actions = accessxi.objective_guides:progression_actions(native_key)
        local flat = type(flat_actions) == 'table' and flat_actions[1] or nil
        task2_reducer_expect(type(flat) == 'table'
                and flat.destination_zone_name == expected_name
                and flat.destination_zone_id == expected_id
                and type(flat.field_sources) == 'table'
                and flat.field_sources.destination_zone_name == 'bg'
                and flat.field_sources.destination_zone_id == 'bg',
            label .. ' flat action omitted the authoritative destination name/ID pair')
        local legacy_steps = accessxi.objective_guides:source_route_steps(native_key)
        local legacy = type(legacy_steps) == 'table' and legacy_steps[1] or nil
        local legacy_claim = type(legacy) == 'table'
            and type(legacy.typed_claims) == 'table' and legacy.typed_claims[1] or nil
        task2_reducer_expect(type(legacy) == 'table'
                and legacy.action == 'poisoned-legacy-action'
                and legacy.entities[1] == 'Poisoned Legacy Target'
                and legacy.zones[1] == 'Poisoned Legacy Source Zone'
                and legacy.destination_zone_name == 'Poisoned Legacy Destination'
                and legacy.destination_zone_id == 999
                and type(legacy_claim) == 'table'
                and legacy_claim.action == 'poisoned-legacy-action'
                and legacy_claim.target == 'Poisoned Legacy Target'
                and legacy_claim.zones[1] == 'Poisoned Legacy Source Zone'
                and legacy_claim.destination_zone_name == 'Poisoned Legacy Destination'
                and legacy_claim.destination_zone_id == 999,
            label .. ' did not poison legacy destination fields for seam isolation')
    end

    task2_reset_reducer_scenario('travel')
    task2_expect_flat_destination_pair(
        'quest:sandoria:2', 'Ghelsba Outpost', 140, 'travel')
    local transport_request = task2_signal('transport-request', {
        target_server_id = 17350951,
        zone_id = 140,
        menu_id = 32001,
        destination_x = 0,
        destination_z = 0,
        destination_y = 0,
    })
    task2_reduce(transport_request, '0x05C transport request')
    task2_reducer_expect(task2_progress_bytes() == '',
        '0x05C Warp Request alone completed the travel claim')
    task2_reducer_expect(not task2_reduce(task2_signal('committed-zone', {
            from_zone_id = 231, zone_id = 141,
            transport_sequence = transport_request.sequence,
        }), 'wrong committed destination'),
        'wrong committed zone completed the travel claim')
    task2_reducer_expect(task2_reduce(task2_signal('committed-zone', {
            from_zone_id = 231, zone_id = 140,
            transport_sequence = transport_request.sequence,
        }), 'expected committed destination'),
        'expected committed zone did not complete the travel claim')
    task2_reducer_expect(task2_last_progress_line()
            == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
        'committed travel did not atomically persist the next current action')

    -- A transport request arms correlation only for the exact current target,
    -- menu, owner, World, and login generation.  Neither the request nor a
    -- replay completes the action; the matching committed zone does.
    task2_reset_reducer_scenario('transport-current')
    task2_expect_flat_destination_pair(
        'quest:sandoria:2', 'Ghelsba Outpost', 140, 'transport')
    local exact_transport = task2_signal('transport-request', {
        target_server_id = 17723406,
        target_name = 'Airship Door',
        zone_id = 231,
        menu_id = 32001,
        destination_x = 12.25,
        destination_z = -3.5,
        destination_y = 1.75,
    })
    for _, mismatch in ipairs(T{
        { target_server_id = 17723407, label = 'target' },
        { character_identity = 'beta:1001', label = 'owner' },
        { world_id = 2002, label = 'World' },
        { session_epoch = 76, label = 'session' },
    }) do
        local request = deep_copy(exact_transport)
        for field, value in pairs(mismatch) do
            if field ~= 'label' then request[field] = value end
        end
        request.sequence = request.sequence + 100
        request.tick = request.tick + 100
        task2_reducer_expect(not task2_reduce(request,
                mismatch.label .. ' mismatched transport request'),
            mismatch.label .. ' mismatched 0x05C transport request was armed')
    end
    task2_reducer_expect(task2_reduce(exact_transport, 'exact 0x05C transport request'),
        'exact current transport target/menu request was not armed')
    task2_reducer_expect(task2_progress_bytes() == '',
        'exact 0x05C transport request completed before committed zoning')
    task2_reducer_expect(not task2_reduce(exact_transport, 'replayed 0x05C transport request'),
        'replayed 0x05C transport request was accepted twice')
    for _, mismatch in ipairs(T{
        { target_server_id = 17723407, label = 'target' },
        { session_epoch = 76, label = 'session' },
        { transport_sequence = exact_transport.sequence + 1, label = 'sequence' },
    }) do
        local committed = task2_signal('committed-zone', {
            from_zone_id = 231, zone_id = 140,
            target_server_id = 17723406, menu_id = 32001,
            transport_sequence = exact_transport.sequence,
        })
        for field, value in pairs(mismatch) do
            if field ~= 'label' then committed[field] = value end
        end
        task2_reducer_expect(not task2_reduce(committed,
                mismatch.label .. ' mismatched committed transport'),
            mismatch.label .. ' mismatch completed an armed transport')
    end
    task2_reducer_expect(task2_reduce(task2_signal('committed-zone', {
            from_zone_id = 231, zone_id = 140,
            target_server_id = 17723406, menu_id = 32001,
            transport_sequence = exact_transport.sequence,
        }), 'exact committed transport zone'),
        'matching committed zone did not complete the armed transport')
    task2_reducer_expect(task2_last_progress_line()
            == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
        'committed transport did not atomically persist the next current action')

    task2_reset_reducer_scenario('travel')
    accessxi.nav_destination = {
        objective_native_key = 'quest:sandoria:2',
        objective_guide_step_id = 'quest:sandoria:2:step-001',
        objective_action_id = 'quest:sandoria:2:step-001:claim-01',
        objective_destination_id = 'zone:v1:140:ghelsba-outpost',
        objective_character_identity = current_identity,
        objective_world_id = current_world_id,
        objective_session_epoch = current_session_epoch,
    }
    task2_reducer_expect(not task2_reduce(task2_signal('route-arrival', {
            objective_native_key = 'quest:sandoria:2',
            action_id = 'quest:sandoria:2:step-999:claim-01',
            destination_id = 'zone:v1:140:ghelsba-outpost', zone_id = 140,
        }), 'wrong-step route arrival'),
        'wrong-step route arrival completed the travel claim')
    task2_reducer_expect(task2_reduce(task2_signal('route-arrival', {
            objective_native_key = 'quest:sandoria:2',
            action_id = 'quest:sandoria:2:step-001:claim-01',
            destination_id = 'zone:v1:140:ghelsba-outpost', zone_id = 140,
        }), 'exact owned route arrival'),
        'exact owned route arrival did not complete the travel-only claim')

    local native_cursor_bytes = task2_progress_bytes()
    quest_entries['sandoria:current'].words = words_with()
    task2_reducer_expect(not task2_reduce(task2_signal('native-objective-state', {
            category = 'quest', previous_native_key = 'quest:sandoria:2',
            current_native_key = '', previous_state = 'active', current_state = 'missing',
            scope_complete = false,
        }), 'partial quest disappearance'),
        'partial 0x056 source disappearance was treated as quest completion')
    task2_reducer_expect(task2_progress_bytes() == native_cursor_bytes,
        'partial 0x056 source disappearance pruned the quest cursor')
    quest_entries['sandoria:completed'].words = words_with(2)
    task2_reducer_expect(task2_reduce(task2_signal('native-objective-state', {
            category = 'quest', previous_native_key = 'quest:sandoria:2',
            current_native_key = '', previous_state = 'active', current_state = 'completed',
            scope_complete = true,
        }), 'coherent quest completion'),
        'coherent 0x056 quest active-to-completed transition was rejected')
    task2_reducer_expect(task2_last_progress_line_for('quest:sandoria:2')
            == task2_v2_progress_row('quest:sandoria:2', 2, 1, 1),
        'coherent quest completion did not append the exact terminal ten-field cursor')
    reload_navigation_module()
    task2_reducer_expect(find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket') == nil,
        'reloading a terminal quest cursor resurrected an active material action')

    task2_reset_reducer_scenario('mission-replacement')
    task2_expect_flat_destination_pair(
        "mission:San d'Oria:1", 'Ghelsba Outpost', 140, 'mission replacement')
    task2_reducer_expect(task2_reduce(task2_signal('committed-zone', {
            from_zone_id = 231, zone_id = 140,
        }), 'mission setup committed zone'),
        'mission replacement fixture did not establish an old mission cursor')
    task2_reducer_expect(task2_progress_bytes():find("mission:San d'Oria:1", 1, true) ~= nil,
        'mission replacement fixture did not persist the old cursor')
    accessxi.mission_packet_main.nation_mission = 1
    task2_reducer_expect(task2_reduce(task2_signal('native-objective-state', {
            category = 'mission', previous_native_key = "mission:San d'Oria:1",
            current_native_key = "mission:San d'Oria:2", previous_state = 'active',
            current_state = 'replaced', scope_complete = true,
        }), 'coherent mission replacement'),
        'coherent 0x056 mission native-key replacement was rejected')
    task2_reducer_expect(task2_last_progress_line_for("mission:San d'Oria:1")
            == task2_v2_progress_row("mission:San d'Oria:1", 2, 1, 1),
        'mission replacement did not append the old objective terminal ten-field cursor')
    task2_reducer_expect(task2_last_progress_line_for("mission:San d'Oria:2")
            == task2_v2_progress_row("mission:San d'Oria:2", 5, 1, 0),
        'mission replacement did not initialize the new native key independently')
    reload_navigation_module()
    local replacement_items = accessxi.nav_mission_quest_active_items('mission')
    task2_reducer_expect(find(replacement_items, 'Smash the Orcish Scouts') == nil
            and type(find(replacement_items, 'Bat Hunt')) == 'table'
            and find(replacement_items, 'Bat Hunt').objective_guide_step_id
                == "mission:San d'Oria:2:step-005",
        'mission replacement reload resurrected the terminal old action or lost the new cursor')

    task2_reset_reducer_scenario('mission-replacement')
    task2_reducer_expect(task2_reduce(task2_signal('committed-zone', {
            from_zone_id = 231, zone_id = 140,
        }), 'missing-graph setup committed zone'),
        'missing-graph replacement fixture did not establish an old mission cursor')
    local missing_graph_bytes = task2_progress_bytes()
    accessxi.mission_packet_main.nation_mission = 998
    task2_reducer_expect(not task2_reduce(task2_signal('native-objective-state', {
            category = 'mission', previous_native_key = "mission:San d'Oria:1",
            current_native_key = "mission:San d'Oria:999", previous_state = 'active',
            current_state = 'replaced', scope_complete = true,
        }), 'replacement with unavailable graph'),
        '0x056 replacement forged progress for an unavailable compact graph')
    task2_reducer_expect(task2_progress_bytes() == missing_graph_bytes,
        'unavailable replacement graph mutated append-only durable progress')

    local function task2_isolate_kill_quest()
        current_nation = 1
        accessxi.mission_packet_main.nation = 1
        accessxi.mission_packet_main.nation_mission = 1
        accessxi.nav_catalog_revision = (tonumber(accessxi.nav_catalog_revision) or 0) + 1
        reload_navigation_module()
    end
    local function task2_change_login_generation(epoch)
        current_session_epoch = epoch
        accessxi.mission_packet_session_epoch = epoch
        accessxi.quest_packet_session_epoch = epoch
        accessxi.key_items_packet_session_epoch = epoch
        accessxi.inventory_packet_session_epoch = epoch
        for _, entry in pairs(accessxi.quest_packet_logs or {}) do
            entry.session_epoch = epoch
        end
        for _, entry in pairs(accessxi.key_items_packet_tables or {}) do
            entry.session_epoch = epoch
        end
        accessxi.nav_catalog_revision = (tonumber(accessxi.nav_catalog_revision) or 0) + 1
        reload_navigation_module()
    end
    local kill_values = {
        actor_server_id = 0x0A0B0C0D,
        actor_name = 'Alpha',
        actor_is_local = true,
        actor_is_party = false,
        target_server_id = 0x01020304,
        target_name = 'Orcish Fodder',
        zone_id = 100,
        packet_id = 0x029,
        message_id = 6,
        battle_sequence = 9001,
    }

    task2_reset_reducer_scenario('kill-current')
    task2_isolate_kill_quest()
    task2_reducer_expect(not task2_reduce(task2_signal('enemy-despawn', {
            target_server_id = kill_values.target_server_id,
            target_name = kill_values.target_name,
            zone_id = kill_values.zone_id,
            battle_sequence = 8991,
        }), 'mere enemy despawn'),
        'mere matching-enemy despawn completed defeat-enemy')
    task2_reducer_expect(not task2_reduce(task2_signal('enemy-health', {
            target_server_id = kill_values.target_server_id,
            target_name = kill_values.target_name,
            zone_id = kill_values.zone_id,
            current_hp = 0,
            battle_sequence = 8992,
        }), 'zero-HP observation'),
        'zero-HP observation without actor credit completed defeat-enemy')
    local falls_values = deep_copy(kill_values)
    falls_values.message_id = 20
    falls_values.credit_kind = 'falls-to-ground'
    falls_values.battle_sequence = 8993
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', falls_values),
            'generic falls-to-ground message'),
        'generic falls-to-ground message was treated as credited defeat')
    local nonparty_values = deep_copy(kill_values)
    nonparty_values.actor_server_id = 0x0E0F1011
    nonparty_values.actor_name = 'Other Player'
    nonparty_values.actor_is_local = false
    nonparty_values.actor_is_party = false
    nonparty_values.battle_sequence = 8994
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', nonparty_values),
            'nonparty kill credit'),
        'nonparty actor credit completed the local objective')
    local unmatched_kill = deep_copy(kill_values)
    unmatched_kill.target_server_id = 0x01020305
    unmatched_kill.target_name = 'Orcish Grappler'
    unmatched_kill.battle_sequence = 8995
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', unmatched_kill),
            'unmatched target kill credit'),
        'unmatched enemy target completed defeat-enemy')
    local wrong_zone_kill = deep_copy(kill_values)
    wrong_zone_kill.zone_id = 101
    wrong_zone_kill.battle_sequence = 8996
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', wrong_zone_kill),
            'wrong-zone kill credit'),
        'wrong-zone enemy kill completed defeat-enemy')
    for _, mismatch in ipairs(T{
        { character_identity = '', label = 'missing character', battle_sequence = 8996 },
        { character_identity = 'beta:1001', label = 'character', battle_sequence = 8997 },
        { world_id = 0, label = 'zero World', battle_sequence = 8998 },
        { world_id = 2002, label = 'World', battle_sequence = 8999 },
        { session_epoch = 0, label = 'zero session', battle_sequence = 9000 },
        { session_epoch = 76, label = 'session', battle_sequence = 9001 },
    }) do
        local signal = task2_signal('kill-credit', kill_values)
        signal.character_identity = mismatch.character_identity or signal.character_identity
        signal.world_id = mismatch.world_id or signal.world_id
        signal.session_epoch = mismatch.session_epoch or signal.session_epoch
        signal.battle_sequence = mismatch.battle_sequence
        task2_reducer_expect(not task2_reduce(signal, mismatch.label .. ' mismatched kill credit'),
            mismatch.label .. ' mismatched kill credit was accepted')
    end
    task2_reducer_expect(task2_reduce(task2_signal('kill-credit', kill_values),
        'credited local kill'),
        'exact local-player credited defeat did not complete defeat-enemy')
    local kill_cursor_bytes = task2_progress_bytes()
    task2_reducer_expect(task2_last_progress_line()
            == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
        'default single credited defeat did not persist the next current action with count zero')
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', kill_values),
            'replayed battle sequence'),
        'replayed battle sequence completed defeat-enemy twice')
    local stale_battle_values = deep_copy(kill_values)
    stale_battle_values.battle_sequence = 9000
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', stale_battle_values),
            'non-monotone battle sequence'),
        'non-monotone battle sequence was accepted')
    task2_reducer_expect(task2_progress_bytes() == kill_cursor_bytes,
        'kill replay or stale battle sequence rewrote the cursor')

    task2_reset_reducer_scenario('kill-current')
    task2_isolate_kill_quest()
    local party_kill_values = deep_copy(kill_values)
    party_kill_values.actor_server_id = 0x0E0F1011
    party_kill_values.actor_name = 'Party Member'
    party_kill_values.actor_is_local = false
    party_kill_values.actor_is_party = true
    party_kill_values.message_id = 97
    party_kill_values.battle_sequence = 9101
    task2_reducer_expect(task2_reduce(task2_signal('kill-credit', party_kill_values),
        'credited party kill'),
        'exact party-member credited message 97 did not complete defeat-enemy')

    -- A counted wiki fight consumes only unique 0x029-derived credited defeats.
    -- Partial counts are durable but remain on the same current action until
    -- the fifth accepted unit atomically selects the next action with count 0.
    do
        task2_reset_reducer_scenario('kill-counted')
        task2_isolate_kill_quest()
        local action_context_only = deep_copy(kill_values)
        action_context_only.packet_id = 0x028
        action_context_only.battle_sequence = 9390
        task2_reducer_expect(not task2_reduce(task2_signal('combat-action', action_context_only),
                '0x028 context-only action'),
            'incoming 0x028 action context incremented the counted defeat action')

        local counted_nonparty = deep_copy(kill_values)
        counted_nonparty.actor_server_id = 0x22223333
        counted_nonparty.actor_is_local = false
        counted_nonparty.actor_is_party = false
        counted_nonparty.battle_sequence = 9391
        task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', counted_nonparty),
                'counted nonparty kill'),
            'nonparty credit incremented the counted defeat action')
        local counted_unmatched = deep_copy(kill_values)
        counted_unmatched.target_name = 'Orcish Grappler'
        counted_unmatched.target_server_id = 0x02030405
        counted_unmatched.battle_sequence = 9392
        task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', counted_unmatched),
                'counted unmatched enemy'),
            'unmatched enemy credit incremented the counted defeat action')
        task2_reducer_expect(task2_progress_bytes() == '',
            'rejected counted-defeat evidence wrote partial progress')

        for count = 1, 4 do
            local credited = deep_copy(kill_values)
            credited.target_server_id = 0x01020304 + count
            credited.battle_sequence = 9400 + count
            credited.causal_id = ('0x029:6:%08X:%d'):format(
                credited.target_server_id, credited.battle_sequence)
            local signal = task2_signal('kill-credit', credited)
            task2_reducer_expect(task2_reduce(signal,
                    'counted credited defeat ' .. tostring(count)),
                ('credited defeat %d of 5 was not accepted as partial progress'):format(count))
            task2_reducer_expect(task2_last_progress_line()
                    == task2_v2_progress_row('quest:sandoria:2', 1, 1, count),
                ('credited defeat %d of 5 did not persist exact current-action count'):format(count))
            local partial_bytes = task2_progress_bytes()
            task2_reducer_expect(not task2_reduce(signal,
                    'replayed counted credited defeat ' .. tostring(count)),
                ('replayed credited defeat %d incremented the counted action twice'):format(count))
            task2_reducer_expect(task2_progress_bytes() == partial_bytes,
                ('replayed credited defeat %d rewrote durable partial progress'):format(count))
            if count == 2 then
                task2_change_login_generation(78)
                task2_reducer_expect(task2_last_progress_line()
                        == task2_v2_progress_row('quest:sandoria:2', 1, 1, 2),
                    'two-of-five credited-defeat progress did not survive relog/reload')
            end
        end
        local final_credit = deep_copy(kill_values)
        final_credit.target_server_id = 0x01020309
        final_credit.battle_sequence = 9405
        final_credit.causal_id = '0x029:6:01020309:9405'
        task2_reducer_expect(task2_reduce(task2_signal('kill-credit', final_credit),
                'fifth counted credited defeat'),
            'fifth credited defeat did not complete the counted action')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
            'fifth credited defeat did not atomically persist next action/count zero')
    end

    -- Multi-item acquisition counts only cursor-entered positive inventory
    -- deltas.  Pre-existing stock, loss, and replay do not contribute.
    do
        task2_reset_reducer_scenario('inventory-counted')
        objective_inventory_counts_by_name['test crystal'] = 5
        accessxi.inventory_packet_key = 'inventory:task2:test-crystal:preexisting-5'
        accessxi.nav_mission_quest_active_items('quest')
        task2_reducer_expect(task2_progress_bytes() == '',
            'pre-existing counted inventory stock wrote progress')
        local first_gain = task2_signal('inventory-delta', {
            snapshot_complete = true,
            item_id = 9999,
            item_name = 'Test Crystal',
            before_count = 5,
            after_count = 6,
            inventory_sequence = 9501,
        })
        for _, mismatch in ipairs(T{
            { snapshot_complete = false, label = 'incomplete snapshot' },
            { character_identity = 'beta:1001', label = 'owner' },
            { world_id = 2002, label = 'World' },
            { session_epoch = 76, label = 'session' },
            { item_name = 'Wrong Crystal', label = 'item' },
        }) do
            local rejected = deep_copy(first_gain)
            for field, value in pairs(mismatch) do
                if field ~= 'label' then rejected[field] = value end
            end
            rejected.sequence = rejected.sequence + 100
            rejected.tick = rejected.tick + 100
            rejected.inventory_sequence = rejected.inventory_sequence + 100
            task2_reducer_expect(not task2_reduce(rejected,
                    mismatch.label .. ' counted inventory delta'),
                mismatch.label .. ' inventory delta incremented objective progress')
        end
        task2_reducer_expect(task2_progress_bytes() == '',
            'rejected inventory owner/session/completeness evidence wrote progress')
        task2_reducer_expect(task2_reduce(first_gain, 'first counted inventory gain'),
            'first cursor-entered item gain was not accepted')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 1, 1, 1),
            'first item gain did not persist one-of-three current-action count')
        local first_gain_bytes = task2_progress_bytes()
        task2_reducer_expect(not task2_reduce(first_gain, 'replayed counted inventory gain'),
            'replayed item delta incremented the counted acquisition twice')
        task2_reducer_expect(task2_progress_bytes() == first_gain_bytes,
            'replayed item delta rewrote counted acquisition progress')
        task2_reducer_expect(not task2_reduce(task2_signal('inventory-delta', {
                snapshot_complete = true,
                item_id = 9999,
                item_name = 'Test Crystal',
                before_count = 6,
                after_count = 5,
                inventory_sequence = 9502,
            }), 'negative counted inventory delta'),
            'negative item delta incremented or rewound the counted acquisition')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 1, 1, 1),
            'negative item delta changed the persisted counted acquisition')
        task2_reducer_expect(task2_reduce(task2_signal('inventory-delta', {
                snapshot_complete = true,
                item_id = 9999,
                item_name = 'Test Crystal',
                before_count = 5,
                after_count = 6,
                inventory_sequence = 9503,
            }), 'second counted inventory gain'),
            'second cursor-entered item gain was not accepted')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 1, 1, 2),
            'second item gain did not persist two-of-three current-action count')
        task2_change_login_generation(79)
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 1, 1, 2),
            'two-of-three inventory-gain progress did not survive relog/reload')
        task2_reducer_expect(task2_reduce(task2_signal('inventory-delta', {
                snapshot_complete = true,
                item_id = 9999,
                item_name = 'Test Crystal',
                before_count = 6,
                after_count = 7,
                inventory_sequence = 9504,
            }), 'third counted inventory gain'),
            'third cursor-entered item gain did not complete the acquisition')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
            'third item gain did not atomically persist next action/count zero')

        task2_reset_reducer_scenario('inventory-counted')
        local two_item_gain = task2_signal('inventory-delta', {
            snapshot_complete = true,
            item_id = 9999,
            item_name = 'Test Crystal',
            before_count = 0,
            after_count = 2,
            inventory_sequence = 9551,
        })
        task2_reducer_expect(task2_reduce(two_item_gain,
                'positive two-item inventory delta'),
            'positive inventory delta greater than one was not accepted')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 1, 1, 2),
            'positive two-item delta did not persist exactly two causal units')
        task2_reducer_expect(not task2_reduce(two_item_gain,
                'replayed positive two-item inventory delta'),
            'replayed positive multi-item delta incremented twice')
        task2_reducer_expect(task2_reduce(task2_signal('inventory-delta', {
                snapshot_complete = true,
                item_id = 9999,
                item_name = 'Test Crystal',
                before_count = 2,
                after_count = 3,
                inventory_sequence = 9552,
            }), 'final unit after positive two-item delta'),
            'final item after a positive two-item delta did not complete the acquisition')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
            'multi-item inventory accumulation did not move atomically to the next action')
    end

    -- A terminal default-single action retains its completed count so reload
    -- and replay cannot reopen it despite there being no next action row.
    do
        task2_reset_reducer_scenario('kill-terminal-single')
        task2_isolate_kill_quest()
        local terminal_credit = deep_copy(kill_values)
        terminal_credit.target_server_id = 0x01020400
        terminal_credit.battle_sequence = 9601
        terminal_credit.causal_id = '0x029:6:01020400:9601'
        local terminal_signal = task2_signal('kill-credit', terminal_credit)
        task2_reducer_expect(task2_reduce(terminal_signal, 'terminal default-single defeat'),
            'default required_count=1 terminal defeat was not accepted')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 1, 1, 1),
            'terminal default-single action did not retain progress_count==required_count')
        local terminal_bytes = task2_progress_bytes()
        task2_change_login_generation(80)
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 1, 1, 1),
            'terminal completed count did not survive relog/reload')
        local terminal_replay = task2_signal('kill-credit', terminal_credit)
        task2_reducer_expect(not task2_reduce(terminal_replay, 'terminal defeat replay'),
            'terminal completed action reopened on replay')
        task2_reducer_expect(task2_progress_bytes() == terminal_bytes,
            'terminal replay rewrote append-only cursor state')
    end

    task2_reset_reducer_scenario('explicit-one-single')
    task2_isolate_kill_quest()
    local explicit_one_credit = deep_copy(kill_values)
    explicit_one_credit.target_server_id = 0x01020401
    explicit_one_credit.battle_sequence = 9651
    explicit_one_credit.causal_id = '0x029:6:01020401:9651'
    task2_reducer_expect(task2_reduce(task2_signal('kill-credit', explicit_one_credit),
            'explicit one default-single defeat'),
        'an explicit required_count=1 single action was not completed by one exact signal')
    task2_reducer_expect(task2_last_progress_line()
            == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
        'explicit-one single action did not move atomically to the next action')

    for _, single_interaction in ipairs(T{
        { scenario = 'trade-single', label = 'trade' },
        { scenario = 'delivery-single', label = 'delivery' },
    }) do
        task2_reset_reducer_scenario(single_interaction.scenario)
        local accepted_trade = deep_copy(interaction_values)
        accepted_trade.event_id = single_interaction.scenario == 'trade-single' and 45101 or 45102
        accepted_trade.menu_id = accepted_trade.event_id
        task2_reducer_expect(task2_reduce(task2_signal('interaction-start', accepted_trade),
                'server-accepted ' .. single_interaction.label .. ' start'),
            single_interaction.label .. ' single action was not armed')
        task2_reducer_expect(task2_reduce(task2_signal('interaction-finish', accepted_trade),
                'server-accepted ' .. single_interaction.label .. ' finish'),
            'one accepted ' .. single_interaction.label .. ' did not complete the whole single action')
        task2_reducer_expect(task2_last_progress_line()
                == task2_v2_progress_row('quest:sandoria:2', 2, 1, 0),
            single_interaction.label .. ' single action was incorrectly treated as item-count progress')
    end

    task2_reset_reducer_scenario('kill-repeated')
    task2_isolate_kill_quest()
    kill_values.battle_sequence = 9201
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', kill_values),
            'same-objective repeated enemy kill'),
        'ambiguous repeated later enemy signature completed an arbitrary claim')
    task2_reducer_expect(task2_progress_bytes() == '',
        'same-objective repeated enemy ambiguity wrote progress')

    task2_reset_reducer_scenario('kill-cross-objective')
    kill_values.battle_sequence = 9301
    task2_reducer_expect(not task2_reduce(task2_signal('kill-credit', kill_values),
            'cross-objective enemy ambiguity'),
        'one credited kill advanced an arbitrary globally ambiguous objective')
    task2_reducer_expect(task2_progress_bytes() == '',
        'cross-objective enemy ambiguity wrote progress')

    task2_reset_reducer_scenario('current-interaction')
    task2_reducer_expect(task2_reduce(task2_signal('interaction-start', interaction_values),
        'identity-loss setup interaction'), 'identity-loss fixture did not arm interaction')
    task2_reduce(task2_signal('identity-loss', {
        owner_present = false,
    }), 'identity-loss invalidation')
    task2_reducer_expect(not task2_reduce(task2_signal('interaction-finish', interaction_values),
            'finish after identity loss'),
        'identity loss left an old interaction correlation armed')
    task2_reducer_expect(task2_progress_bytes() == '',
        'identity-loss invalidation completed the pending objective')
end

task2_reducer_scenario = ''
accessxi.objective_guides.source_route_steps = task2_original_source_steps_for_reducer
accessxi.objective_guides.objective_destinations = task2_original_destinations_for_reducer
accessxi.objective_guides.automatic_step_id = task2_original_automatic_step_for_reducer
accessxi.objective_guides.progression_actions = task2_original_progression_actions_for_reducer
current_nation = 0
accessxi.mission_packet_main = { nation = 0, nation_mission = 0, port = 0xFFFF }
quest_entries['sandoria:current'].words = words_with(2, 200)
quest_entries['sandoria:completed'].words = words_with()
os.remove(objective_progress_path)
accessxi.nav_catalog_revision = (tonumber(accessxi.nav_catalog_revision) or 0) + 1
reload_navigation_module()
end)()

local test_target, test_message, test_mode = accessxi.nav_mission_quest_prepare_route(orcish[1], { zone = 230 })
task2_expect(test_mode == 'wiki-ready' and test_message == '' and type(test_target) == 'table',
    'a fresh exact wiki candidate without a rooted contract must expose a wiki-ready route')
task2_expect(type(test_target) == 'table' and test_target.objective_wiki_route == true
        and test_target.wiki_authoritative == true and test_target.verified ~= true
        and tonumber(test_target.zone) ~= nil and tonumber(test_target.zone) > 0
        and tonumber(test_target.x) ~= nil and test_target.x == test_target.x
        and tonumber(test_target.z) ~= nil and test_target.z == test_target.z,
    'wiki-ready route did not preserve authoritative source semantics and an exact finite catalogue point')
assert(test_target.objective_route_contract_id == nil and test_target.objective_contract_snapshot == nil,
    'a source-backed route must never invent a rooted contract')
for _, field in ipairs({
    'objective_native_key', 'objective_guide_step_id', 'objective_candidate_id',
    'objective_action_id', 'objective_group_id', 'objective_destination_id',
    'objective_character_identity', 'objective_world_id', 'objective_session_epoch',
}) do
    assert(test_target[field] == orcish[1][field],
        'the explicit wiki route lost fresh owner field ' .. field)
end

if task2_inventory_cursor_committed then
    assert(type(task2_restore_inventory_cursor) == 'function')
    task2_restore_inventory_cursor()
    task2_reducer_expect(accessxi.nav_mission_quest_route_point_is_current(test_target) == false,
        'the committed durable cursor left the completed acquisition route current')
    task2_clear_inventory_cursor()
end

for _, failure in ipairs(task2_reducer_failures) do
    task2_red_failures:append(failure)
end

local saved_mission_packet_source = accessxi.mission_packet_source
accessxi.mission_packet_source = 'cache'
local packet_test_target, packet_test_message, packet_test_mode =
    accessxi.nav_mission_quest_prepare_route(orcish[1], { zone = 230 })
task2_expect(packet_test_mode == 'wiki-ready' and type(packet_test_target) == 'table'
    and packet_test_target.objective_wiki_route == true
    and packet_test_target.wiki_authoritative == true and packet_test_target.verified ~= true,
    ('missing current-session mission packets must leave an explicit source-backed route available; mode=%s message=%s target=%s')
        :format(tostring(packet_test_mode), tostring(packet_test_message), type(packet_test_target)))
task2_expect(packet_test_message == '',
    'packet freshness must not be spoken as a blocker for an explicit source-backed destination')
accessxi.mission_packet_source = saved_mission_packet_source

local saved_inventory_packet_source = accessxi.inventory_packet_source
accessxi.inventory_packet_source = ''
local auxiliary_test_target, auxiliary_test_message, auxiliary_test_mode =
    accessxi.nav_mission_quest_prepare_route(orcish[1], { zone = 230 })
task2_expect(auxiliary_test_mode == 'wiki-ready' and type(auxiliary_test_target) == 'table'
    and auxiliary_test_target.objective_wiki_route == true
    and auxiliary_test_target.wiki_authoritative == true and auxiliary_test_target.verified ~= true,
    'missing current-session key-item or inventory packets must leave an explicit source-backed route available')
task2_expect(auxiliary_test_message == '',
    'auxiliary packet freshness must not be spoken as a blocker for an explicit source-backed destination')
accessxi.inventory_packet_source = saved_inventory_packet_source

if task2_inventory_cursor_committed then
    task2_restore_inventory_cursor()
end
orcish_after_item_reset[1].route_ready = true
orcish_after_item_reset[1].route_evidence = 'legacy free text'
orcish_after_item_reset[1].navigation_target = { route_ready = true }
local legacy_target, _, legacy_mode = accessxi.nav_mission_quest_prepare_route(
    orcish_after_item_reset[1], { zone = 230 })
task2_expect(legacy_mode == 'wiki-ready' and type(legacy_target) == 'table'
    and legacy_target.objective_wiki_route == true
    and legacy_target.wiki_authoritative == true and legacy_target.verified ~= true
    and legacy_target.objective_route_contract_id == nil,
    'legacy flags and free text must not invent rooted-contract verification for a wiki-authoritative route')
accessxi.nav_destination = legacy_target
local completion_logs_before_owner_checks = 0
for _, line in ipairs(logs) do
    if line:find('mission active context complete attempts=', 1, true) then
        completion_logs_before_owner_checks = completion_logs_before_owner_checks + 1
    end
end
for _ = 1, 12 do
    assert(accessxi.nav_mission_quest_route_owner_mismatch() == false,
        'the active current-session typed wiki route was rejected for lacking a contract')
end
local completion_logs_after_owner_checks = 0
for _, line in ipairs(logs) do
    if line:find('mission active context complete attempts=', 1, true) then
        completion_logs_after_owner_checks = completion_logs_after_owner_checks + 1
    end
end
assert(completion_logs_after_owner_checks == completion_logs_before_owner_checks,
    'unchanged active-route ownership checks rebuilt every mission context')
if type(accessxi.nav_destination) == 'table' then
    accessxi.nav_destination.objective_candidate_id = 'candidate:changed'
    task2_expect(accessxi.nav_mission_quest_route_owner_mismatch() == true,
        'a changed active typed wiki route did not cancel')
else
    task2_expect(false,
        'wiki-ready fixture did not provide an owned route for exact-currentness mutation')
end
accessxi.nav_destination = nil
if task2_inventory_cursor_committed then
    task2_clear_inventory_cursor()
end

-- Source-backed guide facts are a global explicit-navigation fallback.  The
-- first mission is also exercised without the test fixture's typed rows, and
-- the following mission proves this is not a Smash-only exception.
guide_row_mutator = function(native_key, rows)
    if native_key == "mission:San d'Oria:1" then
        for index = #rows, 1, -1 do table.remove(rows, index) end
    end
end
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
accessxi.mission_packet_main.nation = 0
accessxi.mission_packet_main.nation_mission = 0
local source_orcish = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(source_orcish, 'Smash the Orcish Scouts') == 2,
    'source-backed Orcish Fodder camps disappeared when generated candidates were absent')
assert(source_orcish[1].objective_destination_id == 'camp:v1:101:orcish-fodder:6c7a4f36673f6091fd2c')
assert(source_orcish[2].objective_destination_id == 'camp:v1:100:orcish-fodder:b2999235c7bf7f4860f7')
assert(source_orcish[1].objective_destination_zone_name == 'East Ronfaure'
    and source_orcish[2].objective_destination_zone_name == 'West Ronfaure')

local saved_source_inventory_key = accessxi.inventory_packet_key
objective_inventory_counts_by_name['orcish axe'] = 1
accessxi.inventory_packet_key = 'source-backed:orcish-axe-owned'
local source_orcish_preexisting = accessxi.nav_mission_quest_active_items('mission')
task2_expect(count_named(source_orcish_preexisting, 'Smash the Orcish Scouts') == 2
    and source_orcish_preexisting[1].objective_guide_step_id == "mission:San d'Oria:1:step-005"
    and source_orcish_preexisting[2].objective_guide_step_id == "mission:San d'Oria:1:step-005",
    'pre-existing item stock completed a source-backed acquisition without a typed delta')
objective_inventory_counts_by_name['orcish axe'] = 0
accessxi.inventory_packet_key = saved_source_inventory_key
guide_row_mutator = nil

-- Durable objective ownership requires a positive production World and a
-- positive login generation.  Zero is an unavailable identity boundary, not
-- an optional value that source routes or native deltas may bypass.
local saved_world_provider = accessxi.current_player_world_id
local saved_epoch_provider = accessxi.current_objective_session_epoch
accessxi.current_player_world_id = function() return 0 end
accessxi.current_objective_session_epoch = saved_epoch_provider
guide_row_mutator = function(native_key, rows)
    if native_key == "mission:San d'Oria:1" then
        for index = #rows, 1, -1 do table.remove(rows, index) end
    end
end
local live_source_orcish = accessxi.nav_mission_quest_active_items('mission')
task2_expect(count_named(live_source_orcish, 'Smash the Orcish Scouts') == 0,
    'objective rows were exposed without a positive production World provider')
accessxi.current_player_world_id = saved_world_provider
accessxi.current_objective_session_epoch = function() return 0 end
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
live_source_orcish = accessxi.nav_mission_quest_active_items('mission')
task2_expect(count_named(live_source_orcish, 'Smash the Orcish Scouts') == 0,
    'objective rows were exposed without a positive login generation provider')
guide_row_mutator = nil

accessxi.current_player_world_id = saved_world_provider
accessxi.current_objective_session_epoch = saved_epoch_provider

accessxi.mission_packet_main.nation_mission = 1
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
local saved_source_route_steps = accessxi.objective_guides.source_route_steps
local failed_source_provider_calls = 0
accessxi.objective_guides.source_route_steps = function(self, native_key)
    if native_key == "mission:San d'Oria:2" then
        failed_source_provider_calls = failed_source_provider_calls + 1
        error('transient source guide failure')
    end
    return saved_source_route_steps(self, native_key)
end
accessxi.nav_mission_quest_active_items('mission')
assert(failed_source_provider_calls > 0,
    'the transient source-guide fixture never exercised Bat Hunt guide derivation')
local retry_source_provider_calls = 0
accessxi.objective_guides.source_route_steps = function(self, native_key)
    if native_key == "mission:San d'Oria:2" then
        retry_source_provider_calls = retry_source_provider_calls + 1
    end
    return saved_source_route_steps(self, native_key)
end
local bat_hunt = accessxi.nav_mission_quest_active_items('mission')
accessxi.objective_guides.source_route_steps = saved_source_route_steps
assert(retry_source_provider_calls > 0,
    'an incomplete active mission build was cached instead of retrying the provider with unchanged state')
assert(count_named(bat_hunt, 'Bat Hunt') == 2,
    'the shared source resolver must expose exact Ding Bats destinations for the next mission')
assert(bat_hunt[1].objective_guide_step_id == "mission:San d'Oria:2:step-005")
assert(bat_hunt[1].objective_destination_zone_name == "King Ranperre's Tomb")
assert(bat_hunt[1].objective_target.x == -141.134 and bat_hunt[1].objective_target.z == 223.168,
    'Bat Hunt must put the entrance Ding Bats camp first instead of routing through the Tomb to a deeper camp')
local saved_bat_hunt_inventory_key = accessxi.inventory_packet_key
objective_inventory_counts_by_name['orcish mail scales'] = 1
accessxi.inventory_packet_key = 'inventory:orcish-mail-scales-owned'
local bat_hunt_preexisting_scales = accessxi.nav_mission_quest_active_items('mission')
task2_expect(count_named(bat_hunt_preexisting_scales, 'Bat Hunt') == 2
        and bat_hunt_preexisting_scales[1].objective_guide_step_id
            == "mission:San d'Oria:2:step-005"
        and bat_hunt_preexisting_scales[2].objective_guide_step_id
            == "mission:San d'Oria:2:step-005",
    'pre-existing Orcish Mail Scales completed Bat Hunt without a cursor-entered inventory delta')
objective_inventory_counts_by_name['orcish mail scales'] = 0
accessxi.inventory_packet_key = saved_bat_hunt_inventory_key
local bat_scales_delta = {
    kind = 'inventory-delta',
    character_identity = current_identity,
    world_id = current_world_id,
    session_epoch = current_session_epoch,
    sequence = 9801,
    tick = 9801,
    corpus_revision = tonumber(accessxi.nav_catalog_revision) or 0,
    progression_revision = 'task2-progression-revision',
    snapshot_complete = true,
    item_id = 1112,
    item_name = 'Orcish Mail Scales',
    before_count = 0,
    after_count = 1,
    inventory_sequence = 9801,
}
objective_inventory_counts_by_name['orcish mail scales'] = 1
accessxi.inventory_packet_key = 'inventory:orcish-mail-scales-delta-0-1'
local bat_scales_delta_ok, bat_scales_delta_result = false, false
if type(accessxi.nav_mission_quest_reduce_signal) == 'function' then
    bat_scales_delta_ok, bat_scales_delta_result = pcall(
        accessxi.nav_mission_quest_reduce_signal, bat_scales_delta)
end
local bat_scales_delta_accepted = bat_scales_delta_ok
    and bat_scales_delta_result == true
task2_expect(bat_scales_delta_accepted,
    'cursor-entered Orcish Mail Scales 0-to-1 delta did not advance Bat Hunt')
local bat_hunt_after_scales = accessxi.nav_mission_quest_active_items('mission')
if bat_scales_delta_accepted then
assert(count_named(bat_hunt_after_scales, 'Bat Hunt') == 1,
    'accepted Orcish Mail Scales delta must replace the Ding Bats camps with one exact mission Tombstone')
assert(bat_hunt_after_scales[1].objective_guide_step_id == "mission:San d'Oria:2:step-009",
    'owned Orcish Mail Scales did not advance Bat Hunt to the Tombstone cutscene step')
assert(bat_hunt_after_scales[1].objective_destination_id == 'npc:v1:190:17555989'
    and bat_hunt_after_scales[1].objective_target.x == 1.000
    and bat_hunt_after_scales[1].objective_target.z == -103.608,
    'Bat Hunt did not select the authoritative upper Tombstone used by the mission script')
assert(bat_hunt_after_scales[1].objective_action_instruction:find('Tombstone', 1, true) ~= nil,
    'the advanced Bat Hunt row lost the source-backed Tombstone instruction')

local tombstone_target, tombstone_message, tombstone_mode =
    accessxi.nav_mission_quest_prepare_route(bat_hunt_after_scales[1], { zone = 190 })
assert(tombstone_mode == 'wiki-ready' and tombstone_message == ''
    and type(tombstone_target) == 'table',
    'the source-backed Tombstone step did not produce an exact interaction target')
assert(accessxi.nav_mission_quest_remember_arrival(tombstone_target, 1000) == true,
    'arrival at the selected source-backed interaction was not retained')
assert(accessxi.nav_mission_quest_observe_interaction_text(
    'menu    rem4li2', 'Different target', 17555988,
    'This wrong-target line must not complete the step.', 1100) == false,
    'a mismatched interaction target completed the selected objective step')
assert(accessxi.nav_mission_quest_observe_event_menu('', 1200) == false,
    'closing an unaccepted event menu completed the selected objective step')
assert(accessxi.nav_mission_quest_observe_interaction_text(
    'menu    rem4li2', 'Tombstone', 17555989,
    'Rochefogne : Hm...', 1300) == true,
    'the exact selected Tombstone cutscene was not accepted as live progress evidence')
assert(accessxi.nav_mission_quest_observe_event_menu('menu    rem4li2', 1400) == false,
    'the objective advanced before the interaction menu completed')
assert(accessxi.nav_mission_quest_observe_event_menu('', 1500) == true,
    'closing the completed Tombstone cutscene did not advance the objective')

local bat_hunt_after_cutscene = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(bat_hunt_after_cutscene, 'Bat Hunt') == 2,
    'the completed Tombstone cutscene did not expose the exact available Gate Guards')
for _, row in ipairs(bat_hunt_after_cutscene) do
    if row.name == 'Bat Hunt' then
        assert(row.objective_guide_step_id == "mission:San d'Oria:2:step-012",
            'Bat Hunt did not advance to the next source-guide step after the cutscene')
        assert(row.objective_action_instruction:find('Orcish Mail Scales', 1, true) ~= nil,
            'the automatic next step lost its wiki-backed turn-in instruction')
        assert(row.objective_target ~= nil
            and (row.objective_target.name == 'Ambrotien'
                or row.objective_target.name == 'Grilau'),
            'the automatic turn-in step did not resolve an exact San d\'Orian Gate Guard')
    end
end
local progress_file = assert(io.open(objective_progress_path, 'r'))
local progress_bytes = assert(progress_file:read('*a'))
progress_file:close()
assert(progress_bytes:find(table.concat({
    'v2', 'alpha:1001', '1001', "mission:San d'Oria:2",
    'task2-progression-revision', "mission:San d'Oria:2:step-012", '12',
    "mission:San d'Oria:2:step-012:claim-01", '1', '0',
}, '\t'), 1, true) ~= nil,
    'completed interaction did not persist the exact ten-field next-action cursor')
assert(load_with_env(module_path, {
    accessxi = accessxi,
    T = T,
    bit = bit,
    log_line = function(text) logs:append(text) end,
}), 'navigation module could not be reloaded for persisted-progress verification')
local bat_hunt_after_reload = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(bat_hunt_after_reload, 'Bat Hunt') == 2
    and bat_hunt_after_reload[1].objective_guide_step_id == "mission:San d'Oria:2:step-012"
    and bat_hunt_after_reload[2].objective_guide_step_id == "mission:San d'Oria:2:step-012",
    'persisted interaction progress was lost after an addon-module reload')
objective_inventory_counts_by_name['orcish mail scales'] = 0
accessxi.inventory_packet_key = saved_bat_hunt_inventory_key
accessxi.mission_packet_source = 'cache'
local bat_target, bat_message, bat_mode = accessxi.nav_mission_quest_prepare_route(
    bat_hunt_after_cutscene[1], { zone = 230 })
assert(bat_mode == 'wiki-ready' and type(bat_target) == 'table' and bat_message == '',
    'the next mission source destination must start without current-session packet evidence')
accessxi.mission_packet_source = saved_mission_packet_source
end
objective_inventory_counts_by_name['orcish mail scales'] = 0
accessxi.inventory_packet_key = saved_bat_hunt_inventory_key
accessxi.mission_packet_source = saved_mission_packet_source

current_nation = 0
accessxi.mission_packet_main.nation = 0
accessxi.mission_packet_main.nation_mission = 2
local save_children = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(save_children, 'Save the Children') == 1,
    'Save the Children must initially expose only the exact Arnau objective')
local arnau = assert(find(save_children, 'Save the Children'))
assert(arnau.objective_guide_step_id == "mission:San d'Oria:3:step-002"
    and arnau.objective_destination_id == 'npc:v1:231:17723406',
    'Save the Children did not begin at the exact Arnau interaction')
local arnau_target, arnau_message, arnau_mode =
    accessxi.nav_mission_quest_prepare_route(arnau, { zone = 231 })
local arnau_compatibility_ready = arnau_mode == 'wiki-ready'
    and arnau_message == '' and type(arnau_target) == 'table'
task2_expect(arnau_compatibility_ready,
    'the exact Arnau objective did not produce a source-backed route')
if arnau_compatibility_ready then
assert(accessxi.nav_mission_quest_remember_arrival(arnau_target, 2000) == true,
    'arrival at Arnau was not retained for mission progression')
assert(accessxi.nav_mission_quest_observe_interaction_text(
    'menu    target', 'Arnau', 17723406,
    'Pieuje : Once you know, notify a Temple Knight. Now, go!', 2100) == true,
    'the exact Arnau text was not buffered when it arrived before the event menu')
assert(accessxi.nav_mission_quest_observe_event_menu('menu    rem4li2', 2150) == false,
    'the objective advanced before the late native event menu opened')
assert(accessxi.nav_mission_quest_observe_event_menu('', 2200) == true,
    'closing the completed Arnau cutscene did not advance Save the Children')

local save_children_after_arnau = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(save_children_after_arnau, 'Save the Children') == 1,
    'Save the Children did not replace Arnau with one exact next objective')
local hut_door = assert(find(save_children_after_arnau, 'Save the Children'))
assert(hut_door.objective_guide_step_id == "mission:San d'Oria:3:step-015"
    and hut_door.objective_destination_id == 'object:v1:140:17350951'
    and hut_door.objective_target ~= nil
    and hut_door.objective_target.name == 'Hut Door'
    and hut_door.objective_target.zone == 140,
    'the Arnau cutscene did not advance to the exact Ghelsba Outpost Hut Door')
assert(hut_door.objective_action_instruction:find('Hut Door', 1, true) ~= nil,
    'the next Save the Children objective lost its source-backed Hut Door instruction')

-- Save the Children's first Hut Door interaction only opens the battlefield.
-- The exact retail/LSB mission state does not advance to the Gate Guard until
-- the battlefield has awarded key item 157 (Orcish hut key) and the player
-- checks the same door again for the rescue cutscene.
local hut_target, hut_message, hut_mode =
    accessxi.nav_mission_quest_prepare_route(hut_door, { zone = 140 })
assert(hut_mode == 'wiki-ready' and hut_message == ''
    and type(hut_target) == 'table'
    and hut_target.objective_guide_step_id == "mission:San d'Oria:3:step-015",
    'the exact Hut Door objective did not produce a source-backed route')
assert(type(hut_target.objective_completion_key_items) == 'table'
    and hut_target.objective_completion_key_items[1] == 'Orcish hut key',
    'the Hut Door route did not inherit its skipped battlefield key-item prerequisite')
assert(accessxi.nav_mission_quest_remember_arrival(hut_target, 2300) == true,
    'arrival at the Hut Door was not retained for mission progression')
owned_key_items[157] = nil
assert(accessxi.nav_mission_quest_observe_interaction_text(
    'menu    rem4li2', 'Hut Door', 17350951,
    'Fodderchief Vokdek : Smells like people...', 2400) == false,
    'the pre-battle Hut Door interaction advanced Save the Children too early')
assert(accessxi.nav_mission_quest_observe_event_menu('', 2500) == false,
    'closing the pre-battle Hut Door interaction advanced Save the Children')
local save_children_before_rescue = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(save_children_before_rescue, 'Save the Children') == 1
    and assert(find(save_children_before_rescue, 'Save the Children')).objective_guide_step_id
        == "mission:San d'Oria:3:step-015",
    'Save the Children did not remain on the Hut Door before the battlefield win')

owned_key_items[157] = true
assert(accessxi.nav_mission_quest_observe_event_packet(
    'start', 17350951, 140, 32001, 2600) == true,
    'the exact post-battle Hut Door event packet was not accepted')
assert(accessxi.nav_mission_quest_observe_event_packet(
    'finish', 17350950, 140, 32001, 2650) == false,
    'a different event target advanced the selected mission step')
assert(accessxi.nav_mission_quest_observe_event_packet(
    'finish', 17350951, 140, 32001, 2700) == true,
    'the exact completed Hut Door event packet did not advance the mission')
owned_key_items[157] = nil
local save_children_after_rescue = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(save_children_after_rescue, 'Save the Children') == 2,
    'the completed rescue did not expose the exact available San d\'Orian Gate Guards')
for _, row in ipairs(save_children_after_rescue) do
    if row.name == 'Save the Children' then
        assert(row.objective_guide_step_id == "mission:San d'Oria:3:step-025",
            'the completed rescue did not advance to the reconciled Gate Guard step')
        assert(row.objective_action_instruction:find('Gate Guard', 1, true) ~= nil,
            'the Gate Guard follow-up lost its source-backed completion instruction')
    end
end
end
current_nation = 1
accessxi.mission_packet_main.nation = 1
accessxi.mission_packet_main.nation_mission = 1

local typed_quests = accessxi.nav_mission_quest_active_items('quest')
assert(count_named(typed_quests, 'The Pickpocket') == 1,
    'the live automatic stage must suppress unrelated candidate groups')
local cid = assert(find(typed_quests, 'The Pickpocket'))
assert(cid.objective_candidate_id == 'quest:sandoria:2:step-002:claim-01:candidate:cid')
assert(cid.objective_guide_step_id == 'quest:sandoria:2:step-002')
assert(cid.objective_group_id == '', 'ordinary typed NPC candidates legitimately have no group')
assert(select(3, accessxi.nav_mission_quest_prepare_route(cid, { zone = 230 })) == 'ready')
local saved_automatic_step_id = accessxi.objective_guides.automatic_step_id
accessxi.objective_guides.automatic_step_id = function() return '' end
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
local unmapped_pickpocket = assert(find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket'))
assert(type(unmapped_pickpocket.objective_candidate_id) == 'string'
    and unmapped_pickpocket.objective_candidate_id ~= '',
    'an exact source-backed current target must survive a missing optional guide-step mapping')
task2_expect(select(3, accessxi.nav_mission_quest_prepare_route(
        unmapped_pickpocket, { zone = 230 })) == 'wiki-ready',
    'an unmapped exact wiki candidate did not retain wiki-ready route semantics')
accessxi.objective_guides.automatic_step_id = function() error('intentional mapping failure') end
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
local failed_mapping_pickpocket = assert(find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket'))
assert(type(failed_mapping_pickpocket.objective_candidate_id) == 'string'
    and failed_mapping_pickpocket.objective_candidate_id ~= '',
    'an exact source-backed current target must survive an optional guide mapping failure')
accessxi.objective_guides.automatic_step_id = saved_automatic_step_id

guide_row_mutator = function(native_key, rows)
    if native_key == 'quest:sandoria:2' then
        for _, row in ipairs(rows) do
            if row.candidate_id == 'quest:sandoria:2:step-002:claim-01:candidate:cid' then
                row.group_id = 'invented-group'
            end
        end
    end
end
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
assert(select(3, accessxi.nav_mission_quest_prepare_route(cid, { zone = 230 })) == 'blocked',
    'an empty-group typed candidate cannot be rebound to a different group')
guide_row_mutator = nil
local instruction_rows = T{}
for _, row in ipairs(typed_quests) do
    if row.name == 'A Long Current Quest' then instruction_rows:append(row) end
end
assert(#instruction_rows == 2)
assert(instruction_rows[1].objective_guide_step_id == 'quest:sandoria:200:step-003')
assert(instruction_rows[2].objective_guide_step_id == 'quest:sandoria:200:step-004')
assert(instruction_rows[1].objective_candidate_id == '')
assert(instruction_rows[1].objective_destination_id == '')
local instruction_payload, instruction_message, instruction_mode = accessxi.nav_mission_quest_prepare_route(
    instruction_rows[1], { zone = 230 })
assert(instruction_mode == 'instruction' and instruction_message == '')
assert(instruction_payload == 'Wait for the first signal.')

accessxi.mission_packet_main.nation = 1
accessxi.mission_packet_main.nation_mission = 2
runtime_override = function() return 'candidate text', '', 'instruction' end
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'blocked',
    'runtime instruction mode cannot promote a typed movement candidate')
runtime_override = function() return { zone = 230, name = 'Invented target' }, '', 'ready' end
assert(select(3, accessxi.nav_mission_quest_prepare_route(instruction_rows[1], { zone = 230 })) == 'blocked',
    'runtime ready mode cannot promote a validated instruction-only row')
runtime_override = nil

for _, field in ipairs({ 'action_id', 'guide_step_id', 'action_instruction', 'status' }) do
    guide_row_mutator = function(native_key, rows)
        if native_key == 'quest:sandoria:200' then
            for _, row in ipairs(rows) do
                if row.guide_step_id == 'quest:sandoria:200:step-003' then
                    row[field] = tostring(row[field] or '') .. ':changed'
                end
            end
        end
    end
    accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
    assert(select(3, accessxi.nav_mission_quest_prepare_route(instruction_rows[1], { zone = 230 })) == 'blocked',
        'changed instruction-only ownership must block: ' .. field)
end
guide_row_mutator = nil

local function task2_expect_wiki_ready(item, player, label)
    task2_expect(select(3, accessxi.nav_mission_quest_prepare_route(item, player))
            == 'wiki-ready',
        label .. ' did not preserve wiki-ready route semantics')
end

accessxi.mission_packet_source = 'cache'
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'stale mission packet source')
accessxi.mission_packet_source = 'packet_in_056'
accessxi.mission_packet_session_epoch = current_session_epoch - 1
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'prior-session mission packet')
accessxi.mission_packet_session_epoch = current_session_epoch
quest_entries['sandoria:current'].source = 'cache'
task2_expect_wiki_ready(cid, { zone = 230 }, 'stale quest packet source')
quest_entries['sandoria:current'].source = 'packet_in_056'
accessxi.quest_packet_session_epoch = current_session_epoch - 1
task2_expect_wiki_ready(cid, { zone = 230 }, 'prior-session quest packet')
accessxi.quest_packet_session_epoch = current_session_epoch
accessxi.key_items_packet_tables[0].source = 'cache'
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'stale key-item packet source')
accessxi.key_items_packet_tables[0].source = 'packet_in_055'
accessxi.key_items_packet_tables[0].identity = 'alpha:9999'
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'foreign-owner key-item packet')
accessxi.key_items_packet_tables[0].identity = current_identity
accessxi.key_items_packet_tables[0].session_epoch = current_session_epoch - 1
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'prior-session key-item packet')
accessxi.key_items_packet_tables[0].session_epoch = current_session_epoch
local saved_key_item_tables = accessxi.key_items_packet_tables
accessxi.key_items_packet_tables = {}
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'missing key-item packet tables')
accessxi.key_items_packet_tables = saved_key_item_tables
accessxi.inventory_packet_source = 'cache'
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'stale inventory packet source')
accessxi.inventory_packet_source = 'packet_in_inventory'
accessxi.inventory_packet_identity = 'alpha:9999'
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'foreign-owner inventory packet')
accessxi.inventory_packet_identity = current_identity
accessxi.inventory_packet_session_epoch = current_session_epoch - 1
task2_expect_wiki_ready(typed_lower, { zone = 234 }, 'prior-session inventory packet')
accessxi.inventory_packet_session_epoch = current_session_epoch
local saved_contract_id = runtime_contracts[typed_lower.objective_candidate_id].contract_id
runtime_contracts[typed_lower.objective_candidate_id].contract_id = ''
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'blocked')
runtime_contracts[typed_lower.objective_candidate_id].contract_id = saved_contract_id

-- The browser row is an immutable ownership snapshot. A same-title active row
-- cannot retarget when any owner/session/contract identity has changed.
local stale_lower = typed_lower
accessxi.mission_packet_main.nation = 1
accessxi.mission_packet_main.nation_mission = 2
current_world_id = 2002
local stale_payload, stale_reason, stale_mode = accessxi.nav_mission_quest_prepare_route(stale_lower, { zone = 234 })
assert(stale_payload == nil and stale_mode == 'blocked' and stale_reason ~= '')
current_world_id = 1001
current_session_epoch = 78
accessxi.mission_packet_session_epoch = current_session_epoch
accessxi.quest_packet_session_epoch = current_session_epoch
accessxi.inventory_packet_session_epoch = current_session_epoch
for _, entry in pairs(quest_entries) do entry.session_epoch = current_session_epoch end
for _, entry in pairs(accessxi.key_items_packet_tables) do entry.session_epoch = current_session_epoch end
stale_payload, stale_reason, stale_mode = accessxi.nav_mission_quest_prepare_route(stale_lower, { zone = 234 })
assert(stale_payload == nil and stale_mode == 'blocked' and stale_reason ~= '')
local refreshed_lower = assert(find_destination(
    accessxi.nav_mission_quest_active_items('mission'), 'enemy:v1:143:amber-lower'))
assert(select(3, accessxi.nav_mission_quest_prepare_route(refreshed_lower, { zone = 234 })) == 'ready')

for _, field in ipairs({
    'candidate_id', 'action_id', 'group_id', 'destination_id', 'guide_step_id',
}) do
    guide_row_mutator = function(native_key, rows)
        if native_key == 'mission:Bastok:3' then
            for _, row in ipairs(rows) do
                if row.destination_id == 'enemy:v1:143:amber-lower' then
                    row[field] = tostring(row[field]) .. ':changed'
                end
            end
        end
    end
    accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
    assert(select(3, accessxi.nav_mission_quest_prepare_route(refreshed_lower, { zone = 234 })) == 'blocked',
        'changed typed objective identity must block: ' .. field)
end
guide_row_mutator = nil
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1

local saved_runtime = accessxi.objective_route_runtime
accessxi.objective_route_runtime = nil
task2_expect_wiki_ready(refreshed_lower, { zone = 234 }, 'missing rooted-route runtime')
accessxi.objective_route_runtime = saved_runtime
runtime_override = function() error('intentional runtime failure') end
task2_expect_wiki_ready(refreshed_lower, { zone = 234 }, 'throwing rooted-route runtime')
runtime_override = function() return {}, '', 'invented-mode' end
task2_expect_wiki_ready(refreshed_lower, { zone = 234 }, 'invalid rooted-route runtime mode')
runtime_override = nil

-- Restore the baseline fixture state for the older ordinary-navigation
-- regressions below.
current_session_epoch = 77
accessxi.mission_packet_session_epoch = current_session_epoch
accessxi.quest_packet_session_epoch = current_session_epoch
accessxi.inventory_packet_session_epoch = current_session_epoch
for _, entry in pairs(quest_entries) do entry.session_epoch = current_session_epoch end
for _, entry in pairs(accessxi.key_items_packet_tables) do entry.session_epoch = current_session_epoch end
accessxi.mission_packet_main.nation = 1
accessxi.mission_packet_main.nation_mission = 1

-- Native active mission rows, including exact nation mission ID zero.
local missions = accessxi.nav_mission_quest_active_items('mission')
assert(find(missions, 'A Geological Survey') ~= nil)
assert(find(missions, 'A Geological Survey').objective_native_key == 'mission:Bastok:2')
assert(find(missions, 'A Geological Survey').guide_available == true)
assert(find(missions, 'A Geological Survey').mission_availability == 'active')
assert(find(missions, 'A Geological Survey').objective_character_identity == current_identity)
assert(find(missions, "Welcome t'Norg") ~= nil)
local welcome = assert(find(missions, "Welcome t'Norg"))
assert(welcome.objective_native_details:find('second-floor hallway', 1, true) ~= nil)
assert(accessxi.nav_mission_quest_item_speech(welcome, 1, #missions):find('Native mission orders:', 1, true) ~= nil)
assert(find(missions, 'False TVR mission from TalesBeginning bits') == nil)
mission_values['Rise of the Zilart'] = 3
accessxi.mission_packet_hex = 'mission:zilart:3'
mission_value_packet_age = 60
logs:clear()
local rows = accessxi.nav_mission_quest_active_items('mission')
local zilart = assert(find(rows, "Kazham's Chieftainess"))
assert(zilart.mission_context == 'Rise of the Zilart')
for _, line in ipairs(logs) do
    assert(line:find('base out of range', 1, true) == nil)
end
mission_values['Rise of the Zilart'] = 2
accessxi.mission_packet_hex = 'mission:zilart:2'
mission_value_packet_age = 10
local native_mission_load_mission_rom_rows = accessxi.load_mission_rom_rows
mission_values['Chains of Promathia'] = 1
accessxi.mission_packet_hex = 'mission:cop:1'
accessxi.load_mission_rom_rows = function(context)
    if context == 'Chains of Promathia' then
        error('intentional mission context failure "quoted" ' .. string.rep('x', 180))
    end
    return native_mission_load_mission_rom_rows(context)
end
logs:clear()
missions = accessxi.nav_mission_quest_active_items('mission')
assert(find(missions, 'A Geological Survey') ~= nil)
assert(find(missions, "Welcome t'Norg") ~= nil)
local saw_chain_failure = false
local saw_mission_summary = false
local chain_failure_line = nil
for _, line in ipairs(logs) do
    if line:find('mission active context failure context="Chains of Promathia"', 1, true) then
        saw_chain_failure = true
        chain_failure_line = line
    end
    if line:find('mission active context complete attempts=', 1, true) then
        saw_mission_summary = true
    end
end
assert(saw_chain_failure == true)
assert(saw_mission_summary == true)
assert(chain_failure_line ~= nil)
local chain_failure_reason = chain_failure_line:match('reason="(.*)"$')
assert(chain_failure_reason ~= nil)
assert(chain_failure_reason:find('intentional mission context failure', 1, true) == 1)
assert(chain_failure_reason:find('"') == nil)
assert(chain_failure_reason:find(" 'quoted' ", 1, true) ~= nil)
assert(chain_failure_reason:sub(-3) == '...')
assert(#chain_failure_reason == 99)
local chain_survivor = assert(find(missions, 'A Geological Survey'))
local chain_survivor_target, chain_survivor_message, chain_survivor_mode = accessxi.nav_mission_quest_prepare_route(chain_survivor, { zone = 106 })
task2_expect(chain_survivor_mode == 'wiki-ready' and type(chain_survivor_target) == 'table'
        and chain_survivor_message == '',
    'a surviving exact wiki destination lost wiki-ready semantics during another-context failure')
accessxi.load_mission_rom_rows = native_mission_load_mission_rom_rows
mission_values['Chains of Promathia'] = 0
accessxi.mission_packet_hex = 'mission:cop:0'
local survey_after_failure = assert(find(missions, 'A Geological Survey'))
local failure_target, failure_message, failure_mode = accessxi.nav_mission_quest_prepare_route(survey_after_failure, { zone = 106 })
task2_expect(failure_mode == 'wiki-ready' and type(failure_target) == 'table'
        and failure_message == '',
    'the recovered exact wiki destination did not remain wiki-ready')

accessxi.mission_packet_source = 'cache'
missions = accessxi.nav_mission_quest_active_items('mission')
local cached_survey = assert(find(missions, 'A Geological Survey'))
assert(find(missions, "Welcome t'Norg") ~= nil)
local cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_survey, { zone = 106 })
task2_expect(type(cached_target) == 'table' and cached_mode == 'wiki-ready'
        and cached_message == '',
    'cached mission packets incorrectly blocked an exact wiki-ready route')
accessxi.mission_packet_source = 'packet_in_056'
cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_survey, { zone = 106 })
task2_expect(type(cached_target) == 'table' and cached_mode == 'wiki-ready'
        and cached_message == '',
    'fresh mission packets did not expose the exact wiki-ready route')
accessxi.mission_packet_identity = 'alpha:9999'
assert(#accessxi.nav_mission_quest_active_items('mission') == 0)
accessxi.mission_packet_identity = current_identity

-- A source-reviewed farming mission expands into one stable browser row per
-- distinct routeable camp. The exact highlighted row is revalidated before I
-- starts its route, including current-session and World-qualified ownership.
accessxi.mission_packet_main.nation_mission = 2
missions = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(missions, 'Fetichism') == 2)
local lower_fetich = assert(find_destination(missions, 'enemy:v1:143:amber-lower'))
local upper_fetich = assert(find_destination(missions, 'enemy:v1:143:onyx-upper'))
assert(lower_fetich.objective_available == true)
assert(lower_fetich.objective_items_text == 'Fetich Head, Fetich Torso, Fetich Arms, and Fetich Legs')
assert(lower_fetich.objective_enemies_text == 'Amber Quadav')
assert(lower_fetich.objective_destination_label == 'lower camp')
assert(upper_fetich.objective_transport_id == 'palborough-mines-lift')
assert(upper_fetich.objective_enemies_text == 'Greater Quadav, Onyx Quadav, and Veteran Quadav')
local lower_speech = accessxi.nav_mission_quest_item_speech(lower_fetich, 1, #missions)
assert(lower_speech:find('Objective choice:', 1, true) ~= nil)
assert(lower_speech:find('Fetich Head, Fetich Torso, Fetich Arms, and Fetich Legs', 1, true) ~= nil)
assert(lower_speech:find('Amber Quadav', 1, true) ~= nil)
assert(lower_speech:find('Palborough Mines lower camp', 1, true) ~= nil)
local lower_count_suffix = ('1 of %d.'):fmt(#missions)
assert(lower_speech:sub(-#lower_count_suffix) == lower_count_suffix)
local upper_speech = accessxi.nav_mission_quest_item_speech(upper_fetich, 2, #missions)
assert(upper_speech:find('Greater Quadav, Onyx Quadav, and Veteran Quadav', 1, true) ~= nil)
assert(upper_speech:find('upper camp by elevator', 1, true) ~= nil)

local lower_target, lower_message, lower_mode = accessxi.nav_mission_quest_prepare_route(lower_fetich, { zone = 234 })
assert(lower_mode == 'ready' and lower_target ~= nil and lower_message == '')
assert(lower_target.zone == 143 and lower_target.name == 'Amber Quadav')
assert(lower_target.objective_destination_id == lower_fetich.objective_destination_id)
assert(lower_target.objective_route_contract_id == 'route:v2:lower')

accessxi.mission_packet_source = 'cache'
local stale_target, stale_message, stale_mode = accessxi.nav_mission_quest_prepare_route(lower_fetich, { zone = 234 })
task2_expect(type(stale_target) == 'table' and stale_target.objective_wiki_route == true
    and stale_target.wiki_authoritative == true and stale_target.verified ~= true
    and stale_mode == 'wiki-ready' and stale_message == '',
    'packet freshness incorrectly changed an exact catalogue route from wiki-ready')
accessxi.mission_packet_source = 'packet_in_056'

local other_world_row = lower_fetich
set_live_identity('alpha:2002')
local fresh_other_world_row = assert(find_destination(
    accessxi.nav_mission_quest_active_items('mission'),
    'enemy:v1:143:amber-lower'))
stale_target, stale_message, stale_mode = accessxi.nav_mission_quest_prepare_route(other_world_row, { zone = 234 })
assert(stale_target == nil and stale_mode == 'blocked' and stale_message:find('another character', 1, true) ~= nil)
assert(select(3, accessxi.nav_mission_quest_prepare_route(fresh_other_world_row, { zone = 234 })) == 'ready')
set_live_identity('alpha:1001')
accessxi.mission_packet_main.nation_mission = 1

local unsupported_welcome = assert(find(accessxi.nav_mission_quest_active_items('mission'), "Welcome t'Norg"))
assert(count_named(accessxi.nav_mission_quest_active_items('mission'), "Welcome t'Norg") == 1)
assert(unsupported_welcome.objective_available == false)

-- When there is no active nation mission, only source-backed gate-guard
-- missions currently available to this character are added. Their route goes
-- directly to the nearest exact guard in the player's current city zone.
accessxi.mission_packet_main.nation_mission = 65535
missions = accessxi.nav_mission_quest_active_items('mission')
local available_zeruhn = assert(find(missions, 'The Zeruhn Report'))
assert(find(missions, 'A Geological Survey') == nil)
assert(available_zeruhn.mission_availability == 'available-to-start')
assert(available_zeruhn.objective_available == true)
assert(type(available_zeruhn.objective_destination_id) == 'string'
    and available_zeruhn.objective_destination_id ~= '')
local available_speech = accessxi.nav_mission_quest_item_speech(available_zeruhn, 1, #missions)
assert(available_speech:find('Available mission.', 1, true) ~= nil)
assert(available_speech:find('Press I to start navigation.', 1, true) ~= nil)
assert(available_speech:find('open steps', 1, true) == nil)
local starter_target, starter_message, starter_mode = accessxi.nav_mission_quest_prepare_route(
    available_zeruhn,
    { zone = 234, x = -20, z = -120, y = -1 })
task2_expect(starter_mode == 'wiki-ready' and starter_message == ''
        and type(starter_target) == 'table',
    'available missions with an exact gate-guard target must remain explicitly routeable')

-- Once the dedicated Bastok 1-1 completion bit is live, the ordinary mask
-- advances to the next currently startable mission.
accessxi.mission_packet_nations_complete = T{ 0, 0, 1, 0, 0, 0, 0, 0 }
missions = accessxi.nav_mission_quest_active_items('mission')
local available_survey = assert(find(missions, 'A Geological Survey'))
assert(find(missions, 'The Zeruhn Report') == nil)
assert(available_survey.mission_availability == 'available-to-start')
accessxi.mission_packet_nations_complete = words_with()

current_rank_points = 65535
assert(find(accessxi.nav_mission_quest_active_items('mission'), 'The Zeruhn Report') == nil)
current_rank_points = 0
assert(find(accessxi.nav_mission_quest_active_items('mission'), 'The Zeruhn Report') ~= nil,
    'a rank-points change reused stale available-mission rows')

-- Cached, mismatched, incomplete, or contradictory completion evidence never
-- creates an available mission row or a route.
accessxi.mission_packet_nations_complete_source = 'cache'
assert(find(accessxi.nav_mission_quest_active_items('mission'), 'A Geological Survey') == nil)
accessxi.mission_packet_nations_complete_source = 'packet_in_056'
accessxi.mission_packet_nations_complete_identity = 'alpha:9999'
assert(find(accessxi.nav_mission_quest_active_items('mission'), 'A Geological Survey') == nil)
accessxi.mission_packet_nations_complete_identity = current_identity
accessxi.mission_packet_nations_complete = T{ 0, 0, 3, 0, 0, 0, 0, 0 }
assert(find(accessxi.nav_mission_quest_active_items('mission'), 'A Geological Survey') == nil)
accessxi.mission_packet_nations_complete = words_with()

-- San d'Oria's native-style rank-1 mask offers both repeatable/skippable
-- choices. Save the Children stays hidden until required mission 1-2 is done.
current_nation = 0
accessxi.mission_packet_main.nation = 0
accessxi.mission_packet_nations_complete = words_with()
missions = accessxi.nav_mission_quest_active_items('mission')
local smash = assert(find(missions, 'Smash the Orcish Scouts'))
assert(find(missions, 'Bat Hunt') ~= nil)
assert(find(missions, 'Save the Children') == nil)
starter_target, starter_message, starter_mode = accessxi.nav_mission_quest_prepare_route(
    smash,
    { zone = 231, x = -240, z = 58, y = 8 })
task2_expect(starter_mode == 'wiki-ready' and starter_message == '' and type(starter_target) == 'table',
    'an available nation mission did not expose its exact wiki-ready acceptance route')
task2_expect(type(starter_target) == 'table'
        and (starter_target.name == 'Ambrotien' or starter_target.name == 'Grilau'),
    'an available nation mission did not route to its exact Gate Guard acceptance step')
accessxi.mission_packet_nations_complete = T{ 1, 0, 0, 0, 0, 0, 0, 0 }
missions = accessxi.nav_mission_quest_active_items('mission')
assert(find(missions, 'Smash the Orcish Scouts') ~= nil)
assert(find(missions, 'Bat Hunt') ~= nil)
assert(find(missions, 'Save the Children') == nil)

-- A nation mission that the current 0x056 packet says is active has already
-- passed its source-backed Gate Guard acceptance step.  The active cursor must
-- therefore begin at the first post-acceptance destination, including after an
-- addon reload where no interaction callback survived.
current_rank = 3
accessxi.mission_packet_nations_complete = words_with(1)
missions = accessxi.nav_mission_quest_active_items('mission')
local available_rescue = assert(find(missions, 'The Rescue Drill'))
assert(available_rescue.mission_availability == 'available-to-start')
assert(available_rescue.objective_guide_step_id == "mission:San d'Oria:4:step-003",
    'the available Rescue Drill route did not own its exact Gate Guard acceptance step')
assert(available_rescue.objective_target ~= nil
    and (available_rescue.objective_target.name == 'Ambrotien'
        or available_rescue.objective_target.name == 'Grilau'),
    'the available Rescue Drill did not resolve an exact San d\'Orian Gate Guard')

accessxi.mission_packet_main.nation_mission = 3
missions = accessxi.nav_mission_quest_active_items('mission')
local rescue_after_accept = assert(find(missions, 'The Rescue Drill'))
assert(rescue_after_accept.mission_availability == 'active')
assert(rescue_after_accept.objective_guide_step_id == "mission:San d'Oria:4:step-006",
    'the authoritative active mission packet left Rescue Drill on its acceptance step')
assert(rescue_after_accept.objective_destination_id == 'npc:v1:102:17195615'
    and rescue_after_accept.objective_target.name == 'Galaihaurat',
    'Rescue Drill did not advance to its first post-acceptance objective')
assert(rescue_after_accept.objective_route_recommendation
    == 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
    'the optional Silent Oil preparation was not converted into route-time guidance')
local rescue_route, rescue_route_message, rescue_route_mode = accessxi.nav_mission_quest_prepare_route(
    rescue_after_accept,
    { zone = 102, x = -400, z = 200, y = -7 })
task2_expect(rescue_route_mode == 'wiki-ready' and rescue_route_message == ''
        and type(rescue_route) == 'table'
        and rescue_route.objective_route_recommendation == rescue_after_accept.objective_route_recommendation,
    'route preparation dropped the route-time Silent Oil recommendation')
if type(rescue_route) == 'table' then
    local rescue_start_suffix = accessxi.nav_mission_quest_start_suffix(rescue_route)
    task2_expect(rescue_start_suffix:find(rescue_route.objective_route_recommendation, 1, true) ~= nil,
        'route start speech omitted the Silent Oil recommendation')
    task2_expect(accessxi.nav_mission_quest_arrival_suffix(rescue_route)
            :find(rescue_route.objective_route_recommendation, 1, true) == nil,
        'route recommendation was delayed until arrival instead of route start')
end

-- TalesBeginning bit 6 is the native postponed-opening state for Rhapsodies.
-- It must expose the first RoV mission at an exact Tales' Beginning instead of
-- treating terminal rov=65535 as if no startable mission existed.
accessxi.mission_packet_main.tales = 0x40
accessxi.mission_packet_main.rov = 65535
accessxi.nav_current_position = { zone = 230, x = 0, z = 0, y = 0 }
missions = accessxi.nav_mission_quest_active_items('mission')
local available_rov = assert(find(missions, 'Rhapsodies of Vanadiel'))
assert(available_rov.mission_availability == 'available-to-start')
assert(available_rov.objective_native_key == "mission:Rhapsodies of Vana'diel:1")
assert(available_rov.objective_guide_step_id == "mission:Rhapsodies of Vana'diel:1:step-002")
assert(available_rov.objective_target ~= nil
    and available_rov.objective_target.name == "Tales' Beginning"
    and available_rov.objective_target.zone == 230,
    'postponed RoV did not choose the exact Tales\' Beginning in the current starter city')
accessxi.nav_current_position = { zone = 234, x = 0, z = 0, y = 0 }
local available_rov_bastok = assert(find(
    accessxi.nav_mission_quest_active_items('mission'), 'Rhapsodies of Vanadiel'))
assert(available_rov_bastok.objective_target ~= nil
    and available_rov_bastok.objective_target.name == "Tales' Beginning"
    and available_rov_bastok.objective_target.zone == 234,
    'a zone change reused the stale postponed RoV starter-city target')
accessxi.mission_packet_main.tales = 0
assert(find(accessxi.nav_mission_quest_active_items('mission'), 'Rhapsodies of Vanadiel') == nil,
    'RoV was advertised without a live active or postponed-start packet state')
mission_values["Rhapsodies of Vana'diel"] = 110
accessxi.mission_packet_hex = 'mission:rov:110'
local active_rov = assert(find(
    accessxi.nav_mission_quest_active_items('mission'), 'Rhapsodies of Vanadiel'))
assert(active_rov.mission_availability == 'active',
    'a decoded nonterminal RoV mission value was not exposed as active')
mission_values["Rhapsodies of Vana'diel"] = 65535
accessxi.mission_packet_hex = 'mission:rov:terminal'

current_rank = 1
current_nation = 1
accessxi.mission_packet_main.nation = 1
accessxi.mission_packet_main.nation_mission = 65535
accessxi.mission_packet_nations_complete = words_with()

mission_values.Bastok = 0
accessxi.mission_packet_main.nation_mission = 0
missions = accessxi.nav_mission_quest_active_items('mission')
assert(find(missions, 'The Zeruhn Report') ~= nil)
local makarim_step = {
    stable_step_id = 'mission:Bastok:1:step-007',
    comparison = 'corroborated',
    action = 'talk',
    route_ready = true,
    primary_instruction = 'Speak to Makarim in Zeruhn Mines.',
    navigation_target = {
        type = 'static-reference',
        reference = { zone = 172, zone_name = 'Zeruhn Mines', name = 'Makarim', kind = 'npc' },
        arrival_instruction = 'Talk to Makarim.',
    },
}
local manual_target = accessxi.nav_mission_quest_guide_route_descriptor(
    'mission:Bastok:1',
    makarim_step.stable_step_id,
    makarim_step)
assert(manual_target == nil, 'legacy guide route_ready/static references must never authorize movement')

-- Retained legacy and immutable rows at the exact same physical point are one
-- logical target. Distinct same-name points remain ambiguous and fail closed.
accessxi.nav_points:append(T{
    zone = 172,
    name = 'Makarim',
    x = -60.925,
    z = -333.294,
    y = 8.471,
    kind = 'npc',
    source = 'exact-geometry-duplicate-test-point',
})
local duplicate_target = accessxi.nav_mission_quest_guide_route_descriptor(
    'mission:Bastok:1',
    makarim_step.stable_step_id,
    makarim_step)
assert(duplicate_target == nil)
accessxi.nav_points[#accessxi.nav_points] = nil

accessxi.nav_points:append(T{
    zone = 172,
    name = 'Makarim',
    x = -61.5,
    z = -334.0,
    y = 8.5,
    kind = 'npc',
    source = 'duplicate-test-point',
})
assert(accessxi.nav_mission_quest_guide_route_descriptor(
    'mission:Bastok:1',
    makarim_step.stable_step_id,
    makarim_step) == nil)
accessxi.nav_points[#accessxi.nav_points] = nil
local unsafe_step = {}
for key, value in pairs(makarim_step) do unsafe_step[key] = value end
unsafe_step.action = 'fight'
assert(accessxi.nav_mission_quest_guide_route_descriptor(
    'mission:Bastok:1',
    unsafe_step.stable_step_id,
    unsafe_step) == nil)
accessxi.mission_packet_source = 'cache'
assert(accessxi.nav_mission_quest_guide_route_descriptor(
    'mission:Bastok:1',
    makarim_step.stable_step_id,
    makarim_step) == nil)
accessxi.mission_packet_source = 'packet_in_056'
mission_values.Bastok = 1
accessxi.mission_packet_main.nation_mission = 1

-- Quest rows come from every set current bit and change with packet state.
local quests = accessxi.nav_mission_quest_active_items('quest')
assert(#quests == 4)
for _, quest in ipairs(quests) do
    assert(quest.quest_availability ~= 'available-to-start')
end
assert(quests[1].name == 'The Pickpocket')
assert(quests[1].objective_native_key == 'quest:sandoria:2')
assert(quests[1].guide_available == true)
assert(quests[1].objective_character_identity == current_identity)
assert(quests[2].name == 'A Long Current Quest')
assert(quests[2].objective_native_details:find('Bring the requested item', 1, true) ~= nil)
assert(accessxi.nav_mission_quest_item_speech(quests[2], 2, #quests):find('Native quest details:', 1, true) ~= nil)
assert(quests[3].name == 'A Long Current Quest')
assert(quests[4].name == 'Safe Aht Urhgan Quest')
assert(find(quests, 'Overlaid Mission Word') == nil)

-- Retail may leave a quest bit present on both the current and completed
-- 0x056 pages.  The native quest log classifies that row as Completed, so it
-- must not be expanded into active navigation choices.
quest_entries['sandoria:completed'].words = words_with(2)
local completed_overlap = accessxi.nav_mission_quest_active_items('quest')
assert(find(completed_overlap, 'The Pickpocket') == nil,
    'a completed quest must not remain in the active Quest browser')
assert(#completed_overlap == 3,
    'a completed quest must contribute no duplicate J/L navigation rows')
quest_entries['sandoria:completed'].words = words_with()

accessxi.quest_packet_source = 'cache'
for _, entry in pairs(quest_entries) do entry.source = 'cache' end
quests = accessxi.nav_mission_quest_active_items('quest')
assert(#quests == 4)
local cached_pickpocket = assert(find(quests, 'The Pickpocket'))
assert(find(quests, 'Safe Aht Urhgan Quest') ~= nil)
cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_pickpocket, { zone = 106 })
task2_expect(type(cached_target) == 'table' and cached_target.objective_wiki_route == true
    and cached_target.wiki_authoritative == true and cached_target.verified ~= true
    and cached_mode == 'wiki-ready' and cached_message == '',
    'cached native quest state did not expose a non-rooted authoritative wiki route')
accessxi.quest_packet_source = 'packet_in_056'
quest_entries['aht_urhgan:current'].source = 'packet_in_056'
cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_pickpocket, { zone = 106 })
task2_expect(type(cached_target) == 'table' and cached_target.objective_wiki_route == true
    and cached_target.wiki_authoritative == true and cached_target.verified ~= true
    and cached_mode == 'wiki-ready' and cached_message == '',
    'partially refreshed quest state did not expose a non-rooted authoritative wiki route')
quest_entries['sandoria:current'].source = 'packet_in_056'
cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_pickpocket, { zone = 106 })
assert(cached_target ~= nil and cached_mode == 'ready' and cached_message == '')
for _, entry in pairs(quest_entries) do entry.source = 'packet_in_056' end

-- Browser rows are owned by the character that produced them. Even when a
-- second character has the exact same active mission and quest, pressing I on
-- the first character's stale rows must fail closed instead of retargeting.
local stale_mission_row = assert(find(accessxi.nav_mission_quest_active_items('mission'), 'A Geological Survey'))
local stale_quest_row = assert(find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket'))
set_live_identity('alpha:2002')
local fresh_mission_row = assert(find(accessxi.nav_mission_quest_active_items('mission'), 'A Geological Survey'))
local fresh_quest_row = assert(find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket'))
assert(fresh_mission_row.objective_character_identity == current_identity)
assert(fresh_quest_row.objective_character_identity == current_identity)
local stale_target, stale_message, stale_mode = accessxi.nav_mission_quest_prepare_route(stale_mission_row, { zone = 106 })
assert(stale_target == nil and stale_mode == 'blocked' and stale_message:find('another character', 1, true) ~= nil)
stale_target, stale_message, stale_mode = accessxi.nav_mission_quest_prepare_route(stale_quest_row, { zone = 106 })
assert(stale_target == nil and stale_mode == 'blocked' and stale_message:find('another character', 1, true) ~= nil)
task2_expect(select(3, accessxi.nav_mission_quest_prepare_route(
        fresh_mission_row, { zone = 106 })) == 'wiki-ready',
    'the current character mission row did not remain wiki-ready after rejecting a stale row')
assert(select(3, accessxi.nav_mission_quest_prepare_route(fresh_quest_row, { zone = 106 })) == 'ready')
set_live_identity('alpha:1001')

quest_entries['sandoria:current'].identity = 'alpha:9999'
assert(#accessxi.nav_mission_quest_active_items('quest') == 0)
quest_entries['sandoria:current'].identity = current_identity
quest_entries['sandoria:current'].words = words_with(2)
quests = accessxi.nav_mission_quest_active_items('quest')
assert(#quests == 2 and find(quests, 'A Long Current Quest') == nil)
quest_entries['sandoria:current'].words = words_with(2, 200)
assert(#accessxi.nav_mission_quest_active_items('all') == 0)

-- Geological Survey: no tester -> Cid; Blue -> precise I-8 geyser; Red -> Cid.
missions = accessxi.nav_mission_quest_active_items('mission')
local survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_available == true)
assert(survey.objective_stage == 'obtain-blue-tester')
assert(survey.objective_target.zone == 237 and survey.objective_target.name == 'Cid')
assert(survey.objective_instruction:find('Blue acidity tester', 1, true) ~= nil)
local row_speech = accessxi.nav_mission_quest_item_speech(survey, 1, #missions)
assert(row_speech:find('Objective choice', 1, true) ~= nil)
assert(row_speech:find('Press I to start navigation.', 1, true) ~= nil)
assert(row_speech:find('open steps', 1, true) == nil)

owned_key_items[3] = true
accessxi.key_items_packet_key = 'key-items:geological-survey:blue-owned'
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_stage == 'charge-blue-tester')
assert(survey.objective_target.zone == 191)
assert(math.abs(survey.objective_target.x - -133.1) < 0.01)
assert(math.abs(survey.objective_target.z - 133.2) < 0.01)
assert(math.abs(survey.objective_target.y - 3.0) < 0.01)
assert(survey.objective_target.arrival_radius == 1.0)
assert(survey.objective_instruction:lower():find('stand on the geyser', 1, true) ~= nil)
assert(survey.objective_instruction:lower():find('launch', 1, true) ~= nil)
local target, message, mode = accessxi.nav_mission_quest_prepare_route(survey, { zone = 106 })
task2_expect(mode == 'wiki-ready' and type(target) == 'table' and message == '',
    'an exact current source-backed mission target must remain explicitly routeable')
accessxi.nav_destination = typed_target
assert(accessxi.nav_mission_quest_route_owner_mismatch() == false)
local saved_route_contract = deep_copy(accessxi.nav_destination.objective_contract_snapshot)
for field, invalid in pairs({
    contract_id = 'route:v2:other',
    route_ready = false,
    candidate_id = 'other-candidate',
    action_id = 'other-action',
    group_id = 'other-group',
    destination_id = 'other-destination',
}) do
    accessxi.nav_destination.objective_contract_snapshot[field] = invalid
    assert(accessxi.nav_mission_quest_route_owner_mismatch() == true,
        'mutated rooted contract snapshot must cancel: ' .. field)
    accessxi.nav_destination.objective_contract_snapshot = deep_copy(saved_route_contract)
end
accessxi.nav_destination.objective_contract_snapshot = nil
assert(accessxi.nav_mission_quest_route_owner_mismatch() == true)
accessxi.nav_destination.objective_contract_snapshot = deep_copy(saved_route_contract)
current_identity = 'alpha:9999'
assert(accessxi.nav_mission_quest_route_owner_mismatch() == true)
current_identity = ''
assert(accessxi.nav_mission_quest_route_owner_mismatch() == true)
accessxi.nav_destination = { kind = 'npc', name = 'Ordinary destination' }
assert(accessxi.nav_mission_quest_route_owner_mismatch() == false)
current_identity = 'alpha:1001'
accessxi.nav_destination = nil

owned_key_items[3] = nil
owned_key_items[4] = true
accessxi.key_items_packet_key = 'key-items:geological-survey:red-owned'
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_stage == 'return-red-tester')
assert(survey.objective_target.zone == 237 and survey.objective_target.name == 'Cid')

-- Contradictory or unavailable ownership and missing nav points never guess.
owned_key_items[3] = true
accessxi.key_items_packet_key = 'key-items:geological-survey:contradictory'
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_available == false and survey.objective_status == 'stage-unverified')
target, message, mode = accessxi.nav_mission_quest_prepare_route(survey, { zone = 191 })
assert(target == nil and mode == 'blocked' and message ~= '')

owned_key_items[3] = nil
owned_key_items[4] = nil
accessxi.key_items_packet_key = 'key-items:geological-survey:none'
accessxi.key_items_packet_tables = {}
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_available == false and survey.objective_status == 'stage-unverified')

-- A persisted same-character key-item cache may be stale after reload and must
-- never choose an objective stage before a live-session 0x055 snapshot arrives.
accessxi.key_items_packet_tables = { [0] = { flags = string.rep('\0', 64), source = 'cache', identity = current_identity } }
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_available == false and survey.objective_status == 'stage-unverified')
target, message, mode = accessxi.nav_mission_quest_prepare_route(survey, { zone = 191 })
assert(target == nil and mode == 'blocked' and message ~= '')

accessxi.key_items_packet_tables[0].source = 'packet_in_055'
accessxi.key_items_packet_tables[0].identity = current_identity
accessxi.key_items_packet_tables[0].session_epoch = current_session_epoch
accessxi.nav_points = T{}
accessxi.nav_catalog_revision = accessxi.nav_catalog_revision + 1
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_available == false and survey.objective_status == 'destination-unavailable')

local unsupported = find(missions, "Welcome t'Norg")
target, message, mode = accessxi.nav_mission_quest_prepare_route(unsupported, { zone = 191 })
assert(target == nil and mode == 'blocked')

-- A same-name character with another server ID clears state and cancels only
-- the copied mission/quest route before any prior-character target can run.
accessxi.nav_active = true
accessxi.nav_destination = { objective_kind = 'mission', objective_character_identity = current_identity }
current_identity = 'alpha:2002'
assert(accessxi.nav_mission_quest_sync_character('test-switch') == true)
assert(accessxi.mission_quest_nav_player == 'Alpha')
assert(accessxi.mission_quest_nav_identity == 'alpha:2002')
assert(cancelled_objective_routes == 1)
assert(accessxi.nav_active == false and accessxi.nav_destination == nil)
assert(next(accessxi.mission_packet_main) == nil)
assert(next(accessxi.mission_packet_nations_complete) == nil)
assert(accessxi.mission_packet_nations_complete_player == '')
assert(accessxi.mission_packet_nations_complete_identity == '')
assert(accessxi.mission_packet_nations_complete_source == '')
assert(next(accessxi.quest_packet_logs) == nil)
assert(accessxi.mission_packet_player == '')
assert(accessxi.mission_packet_identity == '')
assert(accessxi.quest_packet_player == '')
assert(accessxi.quest_packet_identity == '')
assert(#accessxi.nav_mission_quest_active_items('mission') == 0)
assert(#accessxi.nav_mission_quest_active_items('quest') == 0)

-- Ordinary navigation must survive the same character-state boundary.
accessxi.nav_active = true
accessxi.nav_destination = { kind = 'npc', name = 'Ordinary destination' }
current_identity = 'alpha:3003'
assert(accessxi.nav_mission_quest_sync_character('test-ordinary-switch') == true)
assert(cancelled_objective_routes == 1)
assert(accessxi.nav_active == true and accessxi.nav_destination.name == 'Ordinary destination')

-- A pending cross-zone objective with no active leg must also be torn down.
accessxi.nav_active = false
accessxi.nav_destination = nil
accessxi.nav_zone_search_target = { objective_kind = 'quest', objective_character_identity = current_identity }
current_identity = 'alpha:4004'
assert(accessxi.nav_mission_quest_sync_character('test-pending-switch') == true)
assert(cancelled_objective_routes == 2)
assert(accessxi.nav_zone_search_target == nil)

-- Task 2 RED: exact live event packets must advance the ordered wiki cursor
-- even when the player reached the NPC without an AccessXI-owned route.  A
-- route is optional player guidance, not the authority for local activity.
-- These expectations fail on the old pending-arrival-only reducer, while the
-- final replay assertion protects the intended one-causal-signal boundary.
;(function()
local task2_progress_notifications = 0
accessxi.on_objective_interaction_progress_changed = function()
    task2_progress_notifications = task2_progress_notifications + 1
end

local function task2_route_less_cid_catalogue()
    return T{
        destination_id = 'npc:v1:237:17772593', zone_id = 237,
        zone_name = 'Metalworks', target_name = 'Cid', target_kind = 'npc',
        target_key = 'cid', target_point = T{ -12.598, 2.430, -10.988 },
        raw_identity = 'lsb:npc_list:17772593', raw_spawn_ids = T{ 17772593 },
        cluster_policy_version = '', transport_id = '', battlefield_id = '',
        metadata_class = '', group_id = '', arrival_instruction = 'Talk to Cid.',
    }
end

local task2_original_source_route_steps = accessxi.objective_guides.source_route_steps
local task2_original_progression_actions = accessxi.objective_guides.progression_actions
accessxi.objective_guides.source_route_steps = function(self, native_key)
    if native_key == 'quest:sandoria:2' then
        return T{
            T{
                stable_step_id = 'quest:sandoria:2:step-001', order = 1,
                action = 'fight', entities = T{ 'Goblin Thug' }, zones = T{ 'Bastok Markets' },
                primary_instruction = 'Defeat the Goblin Thug.', material = true,
            },
            T{
                stable_step_id = 'quest:sandoria:2:step-002', order = 2,
                action = 'talk', entities = T{ 'Cid' }, zones = T{ 'Metalworks' },
                primary_instruction = 'Talk to Cid.', material = true,
            },
            T{
                stable_step_id = 'quest:sandoria:2:step-003', order = 3,
                action = 'wait', entities = T{}, zones = T{},
                primary_instruction = 'Wait for Cid to finish examining the evidence.', material = true,
            },
        }
    end
    return task2_original_source_route_steps(self, native_key)
end
accessxi.objective_guides.progression_actions = function(self, native_key)
    local function action(step_order, action, relationship, target, target_kind, zone)
        local step_id = ('%s:step-%03d'):format(native_key, step_order)
        local catalogue = T{}
        if target == 'Arnau' then
            catalogue:append(T{
                destination_id = 'npc:v1:231:17723406', zone_id = 231,
                zone_name = "Northern San d'Oria", target_name = 'Arnau',
                target_kind = 'npc', target_key = 'arnau',
                target_point = T{ 149.892, 141.873, -0.601 },
                raw_identity = 'lsb:npc_list:17723406', raw_spawn_ids = T{ 17723406 },
                cluster_policy_version = '', transport_id = '', battlefield_id = '',
                metadata_class = '',
                group_id = step_id .. ':claim-01:zone:231',
                arrival_instruction = 'Talk to Arnau.',
            })
        elseif target == 'Cid' then
            catalogue:append(task2_route_less_cid_catalogue())
        end
        return T{
            step_id = step_id,
            step_order = step_order,
            action_id = step_id .. ':claim-01',
            action_order = 1,
            order = step_order,
            action = action,
            relationship = relationship,
            target = target,
            target_key = task2_flat_target_key(target),
            target_kind = target_kind,
            npcs = target_kind == 'npc' and T{ target } or T{},
            objects = target_kind == 'object' and T{ target } or T{},
            enemies = target_kind == 'enemy' and T{ target } or T{},
            zones = zone ~= nil and T{ zone } or T{},
            items = T{}, key_items = T{}, transports = T{}, grid_coordinates = T{},
            result_items = T{}, result_relation = '',
            destination_zone_name = '', destination_zone_id = 0,
            instruction = action .. ' ' .. target,
            count_mode = 'single',
            required_count = 1,
            count_explicit = false,
            material = true,
            source_authority = 'bg',
            field_sources = T{ action = 'bg', relationship = 'bg', target = 'bg',
                target_key = 'bg', target_kind = 'bg', npcs = 'bg', objects = 'bg',
                enemies = 'bg', zones = 'bg', items = 'bg', key_items = 'bg',
                transports = 'bg', grid_coordinates = 'bg', result_items = 'bg',
                result_relation = 'bg', destination_zone_name = '',
                destination_zone_id = '', instruction = 'bg', count_mode = 'default',
                required_count = 'default', count_explicit = 'default',
                catalogue = #catalogue > 0 and 'catalogue' or '' },
            source_revisions = T{ bg = 4001, ffxiclopedia = 4002 },
            source_action_span_ids = T{
                step_id .. ':bg:action-01', step_id .. ':ffxiclopedia:action-01',
            },
            catalogue = catalogue,
        }
    end
    if native_key == "mission:San d'Oria:3" then
        return T{
            action(2, 'talk', 'talk-to', 'Arnau', 'npc', "Northern San d'Oria"),
            action(8, 'obtain', 'obtain-key-item', 'Orcish Hut Key', 'key-item', nil),
        }
    end
    if native_key == 'quest:sandoria:2' then
        return T{
            action(1, 'fight', 'defeat-enemy', 'Goblin Thug', 'enemy', 'Bastok Markets'),
            action(2, 'talk', 'talk-to', 'Cid', 'npc', 'Metalworks'),
            action(3, 'wait', 'wait-for', '', '', nil),
        }
    end
    if type(task2_original_progression_actions) == 'function' then
        return task2_original_progression_actions(self, native_key)
    end
    return T{}
end

local function task2_route_progress_last_line()
    local file = io.open(objective_progress_path, 'rb')
    if file == nil then return '' end
    local bytes = file:read('*a') or ''
    file:close()
    local line = ''
    for candidate in bytes:gmatch('[^\r\n]+') do line = candidate end
    return line
end

local function task2_route_expected_v2(native_key, step_order)
    local step_id = ('%s:step-%03d'):format(native_key, step_order)
    return table.concat({
        'v2', current_identity, tostring(current_world_id), native_key,
        'task2-progression-revision', step_id, tostring(step_order),
        step_id .. ':claim-01', '1', '0',
    }, '\t')
end

local function task2_reload_navigation_module()
    reload_navigation_module()
end

local function task2_restore_live_objective_fixture()
    current_player = 'Alpha'
    current_identity = 'alpha:1001'
    current_world_id = 1001
    current_session_epoch = 77
    current_nation = 0
    mission_values["San d'Oria"] = 2
    accessxi.mission_quest_nav_player = current_player
    accessxi.mission_quest_nav_identity = current_identity
    accessxi.mission_packet_player = current_player
    accessxi.mission_packet_identity = current_identity
    accessxi.mission_packet_source = 'packet_in_056'
    accessxi.mission_packet_session_epoch = current_session_epoch
    accessxi.mission_packet_main = { nation = 0, nation_mission = 2, port = 0xFFFF }
    accessxi.mission_packet_nations_complete = words_with()
    accessxi.mission_packet_nations_complete_player = current_player
    accessxi.mission_packet_nations_complete_identity = current_identity
    accessxi.mission_packet_nations_complete_source = 'packet_in_056'
    accessxi.quest_packet_player = current_player
    accessxi.quest_packet_identity = current_identity
    accessxi.quest_packet_source = 'packet_in_056'
    accessxi.quest_packet_session_epoch = current_session_epoch
    for _, entry in pairs(quest_entries) do
        entry.identity = current_identity
        entry.session_epoch = current_session_epoch
        entry.source = 'packet_in_056'
    end
    quest_entries['sandoria:current'].words = words_with(2, 200)
    quest_entries['sandoria:completed'].words = words_with()
    accessxi.quest_packet_logs = quest_entries
    accessxi.key_items_packet_player = current_player
    accessxi.key_items_packet_identity = current_identity
    accessxi.key_items_packet_tables = {
        [0] = {
            flags = string.rep('\0', 64),
            source = 'packet_in_055',
            identity = current_identity,
            session_epoch = current_session_epoch,
        },
    }
    accessxi.inventory_packet_source = 'packet_in_inventory'
    accessxi.inventory_packet_identity = current_identity
    accessxi.inventory_packet_session_epoch = current_session_epoch
    accessxi.nav_active = false
    accessxi.nav_destination = nil
    accessxi.nav_zone_search_target = nil
    accessxi.nav_points = T{
        T{
            zone = 231, name = 'Arnau', x = 149.892, z = 141.873, y = -0.601,
            kind = 'npc', destination_id = 'npc:v1:231:17723406',
            raw_identity = 'lsb:npc_list:17723406', raw_spawn_ids = T{ 17723406 },
        },
        T{
            zone = 237, name = 'Cid', x = -12.598, z = 2.430, y = -10.988,
            kind = 'npc', destination_id = 'npc:v1:237:17772593',
            raw_identity = 'lsb:npc_list:17772593', raw_spawn_ids = T{ 17772593 },
        },
    }
    accessxi.nav_catalog_revision = (tonumber(accessxi.nav_catalog_revision) or 0) + 1
    accessxi.objective_progress_revision = 1
    os.remove(objective_progress_path)
    task2_reload_navigation_module()
end

task2_restore_live_objective_fixture()
local task2_mission = assert(find(accessxi.nav_mission_quest_active_items('mission'), 'Save the Children'))
task2_expect(task2_mission.objective_guide_step_id == "mission:San d'Oria:3:step-002",
    'Task 2 mission fixture did not establish Arnau as the current wiki step')
local function task2_observe_event_packet(label, ...)
    if type(accessxi.nav_mission_quest_observe_event_packet) ~= 'function' then
        task2_expect(false, label .. ' production event adapter seam is missing')
        return false
    end
    local ok, accepted = pcall(accessxi.nav_mission_quest_observe_event_packet, ...)
    task2_expect(ok, label .. ' raised a production event adapter error')
    return ok and accepted == true
end

local task2_mission_start = task2_observe_event_packet(
    'route-less mission start', 'start', 17723406, 231, 42001, 10000)
local task2_mission_finish = task2_observe_event_packet(
    'route-less mission finish', 'finish', 17723406, 231, 42001, 10100)
local task2_mission_replay = task2_observe_event_packet(
    'route-less mission replay', 'finish', 17723406, 231, 42001, 10200)
task2_expect(task2_mission_start,
    'route-less mission 0x032/0x034 start was not accepted for the current exact Arnau step')
task2_expect(task2_mission_finish,
    'route-less mission matching 0x05B finish did not advance the current wiki cursor')
task2_expect(not task2_mission_replay,
    'replayed mission 0x05B finish advanced the same wiki step again')
task2_expect(task2_progress_notifications == 1,
    'route-less mission interaction did not emit exactly one progression notification')
local task2_mission_after = find(accessxi.nav_mission_quest_active_items('mission'), 'Save the Children')
task2_expect(type(task2_mission_after) == 'table'
        and task2_mission_after.objective_guide_step_id == "mission:San d'Oria:3:step-008",
    'route-less mission finish did not move exactly one material action from Arnau to the Orcish hut key')
task2_expect(task2_route_progress_last_line()
        == task2_route_expected_v2("mission:San d'Oria:3", 8),
    'route-less mission finish did not persist the exact ten-field next-action cursor')
task2_reload_navigation_module()
local task2_mission_after_reload = find(
    accessxi.nav_mission_quest_active_items('mission'), 'Save the Children')
task2_expect(type(task2_mission_after_reload) == 'table'
        and task2_mission_after_reload.objective_guide_step_id == "mission:San d'Oria:3:step-008",
    'route-less mission cursor was not persisted across navigation-module reload')

task2_restore_live_objective_fixture()
task2_progress_notifications = 0
local task2_quest = assert(find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket'))
task2_expect(task2_quest.objective_guide_step_id == 'quest:sandoria:2:step-002',
    'Task 2 quest fixture did not establish Cid as the current wiki step')
local task2_quest_start = task2_observe_event_packet(
    'route-less quest start', 'start', 17772593, 237, 42002, 11000)
local task2_quest_finish = task2_observe_event_packet(
    'route-less quest finish', 'finish', 17772593, 237, 42002, 11100)
local task2_quest_replay = task2_observe_event_packet(
    'route-less quest replay', 'finish', 17772593, 237, 42002, 11200)
task2_expect(task2_quest_start,
    'route-less quest 0x032/0x034 start was not accepted for the current exact Cid step')
task2_expect(task2_quest_finish,
    'route-less quest matching 0x05B finish did not advance the current wiki cursor')
task2_expect(not task2_quest_replay,
    'replayed quest 0x05B finish advanced the same wiki step again')
task2_expect(task2_progress_notifications == 1,
    'route-less quest interaction did not emit exactly one progression notification')
local task2_quest_after = find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket')
task2_expect(type(task2_quest_after) == 'table'
        and task2_quest_after.objective_guide_step_id == 'quest:sandoria:2:step-003',
    'route-less quest finish did not move exactly one material action from Cid to the wait instruction')
task2_expect(task2_route_progress_last_line()
        == task2_route_expected_v2('quest:sandoria:2', 3),
    'route-less quest finish did not persist the exact ten-field next-action cursor')
task2_reload_navigation_module()
local task2_quest_after_reload = find(
    accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket')
task2_expect(type(task2_quest_after_reload) == 'table'
        and task2_quest_after_reload.objective_guide_step_id == 'quest:sandoria:2:step-003',
    'route-less quest cursor was not persisted across navigation-module reload')

accessxi.objective_guides.progression_actions = task2_original_progression_actions

assert(#task2_red_failures == 0,
    'Task 2 complete wiki-authoritative progression REDs:\n- '
        .. table.concat(task2_red_failures, '\n- '))
end)()

os.remove(objective_progress_path)
return true
