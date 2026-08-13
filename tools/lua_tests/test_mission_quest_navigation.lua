local objectives_path = assert(arg[1], 'missing objectives module path')
local module_path = assert(arg[2], 'missing navigation module path')

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear() for index = #self, 1, -1 do self[index] = nil end end
T = function(values) return setmetatable(values or {}, { __index = list_methods }) end

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

local quest_entries = {
    ['sandoria:current'] = { area_key = 'sandoria', mode = 'current', words = words_with(2, 200), source = 'packet_in_056', identity = current_identity, session_epoch = current_session_epoch },
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
        ["mission:San d'Oria:1"] = { status = 'guide', title = 'Smash the Orcish Scouts' },
        ["mission:San d'Oria:3"] = { status = 'guide', title = 'Save the Children' },
        ["mission:San d'Oria:4"] = { status = 'guide', title = 'The Rescue Drill' },
        ["mission:Rhapsodies of Vana'diel:1"] = { status = 'guide', title = 'Rhapsodies of Vanadiel' },
        ['mission:Bastok:2'] = { status = 'guide', title = 'A Geological Survey' },
        ['mission:Bastok:3'] = { status = 'verified-navigation', title = 'Fetichism' },
        ['quest:sandoria:2'] = { status = 'guide', title = 'The Pickpocket' },
        ['quest:sandoria:200'] = { status = 'guide', title = 'A Long Current Quest' },
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
                        route_ready = false,
                    },
                    T{
                        stable_step_id = "mission:San d'Oria:1:step-005",
                        order = 5,
                        comparison = 'corroborated',
                        action = 'fight',
                        entities = T{ 'Orcish Fodder', 'Orcish Axe' },
                        zones = T{ 'East Ronfaure', 'West Ronfaure' },
                        primary_instruction = 'Defeat Orcish Fodder until you obtain an Orcish Axe.',
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
assert(load_with_env(module_path, {
    accessxi = accessxi,
    T = T,
    bit = bit,
    log_line = function(text) logs:append(text) end,
}))

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

accessxi.last_native_inventory_item_tick = accessxi.last_native_inventory_item_tick + 1
accessxi.hotkey_cache_volatile_mission_signature = accessxi.hotkey_cache_build(
    'mission', 'volatile inventory-tick Mission hotkey build')
accessxi.hotkey_cache_volatile_quest_signature = accessxi.hotkey_cache_build(
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

objective_inventory_counts_by_name['orcish axe'] = 1
local orcish_turn_in = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(orcish_turn_in, 'Smash the Orcish Scouts') == 2,
    'an owned Orcish Axe must replace both camp rows with exact available Gate Guards')
for _, row in ipairs(orcish_turn_in) do
    if row.name == 'Smash the Orcish Scouts' then
        assert(row.objective_guide_step_id == "mission:San d'Oria:1:step-007",
            'an owned Orcish Axe did not advance to the reconciled turn-in step')
        assert(row.objective_action_instruction:find('trade the Orcish Axe', 1, true) ~= nil,
            'the advanced row lost the source-backed turn-in instruction')
        assert(row.objective_target ~= nil
            and (row.objective_target.name == 'Ambrotien' or row.objective_target.name == 'Grilau'),
            'the advanced step did not resolve an exact San d\'Orian Gate Guard')
    end
end
objective_inventory_counts_by_name['orcish axe'] = 0
local orcish_after_item_reset = accessxi.nav_mission_quest_active_items('mission')
assert(orcish_after_item_reset[1].objective_guide_step_id == "mission:San d'Oria:1:step-005"
    and orcish_after_item_reset[2].objective_guide_step_id == "mission:San d'Oria:1:step-005",
    'removing the required carried item did not restore the acquisition step')

local test_target, test_message, test_mode = accessxi.nav_mission_quest_prepare_route(orcish[1], { zone = 230 })
assert(test_mode == 'test-ready' and test_message == '' and type(test_target) == 'table',
    'a fresh typed candidate without a rooted contract must expose an explicit test route')
assert(test_target.objective_test_route == true and test_target.verified ~= true,
    'the source-backed route must not invent rooted path authorization')
assert(test_target.objective_route_contract_id == nil and test_target.objective_contract_snapshot == nil,
    'a source-backed route must never invent a rooted contract')
for _, field in ipairs({
    'objective_native_key', 'objective_guide_step_id', 'objective_candidate_id',
    'objective_action_id', 'objective_group_id', 'objective_destination_id',
    'objective_character_identity', 'objective_world_id', 'objective_session_epoch',
}) do
    assert(test_target[field] == orcish[1][field],
        'the explicit test route lost fresh owner field ' .. field)
end

local saved_inventory_key_for_progression = accessxi.inventory_packet_key
objective_inventory_counts_by_name['orcish axe'] = 1
accessxi.inventory_packet_key = 'native-inventory:orcish-axe-owned'
assert(accessxi.nav_mission_quest_route_point_is_current(test_target) == false,
    'the acquisition route remained current after its required item advanced the mission')
objective_inventory_counts_by_name['orcish axe'] = 0
accessxi.inventory_packet_key = saved_inventory_key_for_progression
assert(accessxi.nav_mission_quest_route_point_is_current(test_target) == true,
    'an unchanged mission step was treated as superseded by unrelated inventory state')

local saved_mission_packet_source = accessxi.mission_packet_source
accessxi.mission_packet_source = 'cache'
local packet_test_target, packet_test_message, packet_test_mode =
    accessxi.nav_mission_quest_prepare_route(orcish[1], { zone = 230 })
assert(packet_test_mode == 'test-ready' and type(packet_test_target) == 'table'
    and packet_test_target.objective_test_route == true and packet_test_target.verified ~= true,
    ('missing current-session mission packets must leave an explicit source-backed route available; mode=%s message=%s target=%s')
        :format(tostring(packet_test_mode), tostring(packet_test_message), type(packet_test_target)))
assert(packet_test_message == '',
    'packet freshness must not be spoken as a blocker for an explicit source-backed destination')
accessxi.mission_packet_source = saved_mission_packet_source

local saved_inventory_packet_source = accessxi.inventory_packet_source
accessxi.inventory_packet_source = ''
local auxiliary_test_target, auxiliary_test_message, auxiliary_test_mode =
    accessxi.nav_mission_quest_prepare_route(orcish[1], { zone = 230 })
assert(auxiliary_test_mode == 'test-ready' and type(auxiliary_test_target) == 'table'
    and auxiliary_test_target.objective_test_route == true and auxiliary_test_target.verified ~= true,
    'missing current-session key-item or inventory packets must leave an explicit source-backed route available')
assert(auxiliary_test_message == '',
    'auxiliary packet freshness must not be spoken as a blocker for an explicit source-backed destination')
accessxi.inventory_packet_source = saved_inventory_packet_source

orcish[1].route_ready = true
orcish[1].route_evidence = 'legacy free text'
orcish[1].navigation_target = { route_ready = true }
local legacy_target, _, legacy_mode = accessxi.nav_mission_quest_prepare_route(orcish[1], { zone = 230 })
assert(legacy_mode == 'test-ready' and legacy_target.objective_test_route == true
    and legacy_target.verified ~= true and legacy_target.objective_route_contract_id == nil,
    'legacy flags and free text must never promote a test route to verified')
accessxi.nav_destination = test_target
local completion_logs_before_owner_checks = 0
for _, line in ipairs(logs) do
    if line:find('mission active context complete attempts=', 1, true) then
        completion_logs_before_owner_checks = completion_logs_before_owner_checks + 1
    end
end
for _ = 1, 12 do
    assert(accessxi.nav_mission_quest_route_owner_mismatch() == false,
        'the active current-session typed test route was rejected for lacking a contract')
end
local completion_logs_after_owner_checks = 0
for _, line in ipairs(logs) do
    if line:find('mission active context complete attempts=', 1, true) then
        completion_logs_after_owner_checks = completion_logs_after_owner_checks + 1
    end
end
assert(completion_logs_after_owner_checks == completion_logs_before_owner_checks,
    'unchanged active-route ownership checks rebuilt every mission context')
accessxi.nav_destination.objective_candidate_id = 'candidate:changed'
assert(accessxi.nav_mission_quest_route_owner_mismatch() == true,
    'a changed active typed test route did not cancel')
accessxi.nav_destination = nil

-- Source-backed guide facts are a global explicit-navigation fallback.  The
-- first mission is also exercised without the test fixture's typed rows, and
-- the following mission proves this is not a Smash-only exception.
guide_row_mutator = function(native_key, rows)
    if native_key == "mission:San d'Oria:1" then
        for index = #rows, 1, -1 do table.remove(rows, index) end
    end
end
accessxi.mission_packet_main.nation = 0
accessxi.mission_packet_main.nation_mission = 0
local source_orcish = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(source_orcish, 'Smash the Orcish Scouts') == 2,
    'Smash must expose both source-backed Ronfaure choices without generated candidates')
assert(source_orcish[1].objective_destination_id == 'camp:v1:101:orcish-fodder:6c7a4f36673f6091fd2c')
assert(source_orcish[2].objective_destination_id == 'camp:v1:100:orcish-fodder:b2999235c7bf7f4860f7')
assert(source_orcish[1].objective_destination_zone_name == 'East Ronfaure'
    and source_orcish[2].objective_destination_zone_name == 'West Ronfaure')

local saved_source_inventory_key = accessxi.inventory_packet_key
objective_inventory_counts_by_name['orcish axe'] = 1
accessxi.inventory_packet_key = 'source-backed:orcish-axe-owned'
local source_orcish_turn_in = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(source_orcish_turn_in, 'Smash the Orcish Scouts') == 2
    and source_orcish_turn_in[1].objective_guide_step_id == "mission:San d'Oria:1:step-007"
    and source_orcish_turn_in[2].objective_guide_step_id == "mission:San d'Oria:1:step-007",
    'owned items did not advance source-backed mission rows when generated candidates were absent')
objective_inventory_counts_by_name['orcish axe'] = 0
accessxi.inventory_packet_key = saved_source_inventory_key
guide_row_mutator = nil

-- The live reader does not expose the old test-only world/session accessors.
-- Source-backed destinations still need to reach the ordinary route engine;
-- character identity and a fresh rebuild of the active row own this path.
local saved_world_provider = accessxi.current_player_world_id
local saved_epoch_provider = accessxi.current_objective_session_epoch
accessxi.current_player_world_id = nil
accessxi.current_objective_session_epoch = nil
guide_row_mutator = function(native_key, rows)
    if native_key == "mission:San d'Oria:1" then
        for index = #rows, 1, -1 do table.remove(rows, index) end
    end
end
local live_source_orcish = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(live_source_orcish, 'Smash the Orcish Scouts') == 2,
    'live source routes disappeared when optional world/session accessors were absent')
local live_source_target, live_source_message, live_source_mode =
    accessxi.nav_mission_quest_prepare_route(live_source_orcish[1], { zone = 230 })
assert(live_source_mode == 'test-ready' and live_source_message == ''
    and type(live_source_target) == 'table',
    'a live source route did not reach explicit ordinary-route preparation')
guide_row_mutator = nil

local saved_live_inventory_source = accessxi.inventory_packet_source
local saved_live_inventory_epoch = accessxi.inventory_packet_session_epoch
local saved_live_inventory_key = accessxi.inventory_packet_key
objective_inventory_counts_by_name['orcish axe'] = 1
accessxi.inventory_packet_source = 'native-inventory'
accessxi.inventory_packet_session_epoch = 0
accessxi.inventory_packet_key = 'native-inventory:epoch-zero:orcish-axe'
local live_inventory_orcish = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(live_inventory_orcish, 'Smash the Orcish Scouts') == 2
    and live_inventory_orcish[1].objective_guide_step_id == "mission:San d'Oria:1:step-007"
    and live_inventory_orcish[2].objective_guide_step_id == "mission:San d'Oria:1:step-007",
    'the live native Inventory snapshot was ignored when the optional session epoch accessor was absent')
objective_inventory_counts_by_name['orcish axe'] = 0
accessxi.inventory_packet_source = saved_live_inventory_source
accessxi.inventory_packet_session_epoch = saved_live_inventory_epoch
accessxi.inventory_packet_key = saved_live_inventory_key
accessxi.current_player_world_id = saved_world_provider
accessxi.current_objective_session_epoch = saved_epoch_provider

accessxi.mission_packet_main.nation_mission = 1
local bat_hunt = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(bat_hunt, 'Bat Hunt') == 2,
    'the shared source resolver must expose exact Ding Bats destinations for the next mission')
assert(bat_hunt[1].objective_guide_step_id == "mission:San d'Oria:2:step-005")
assert(bat_hunt[1].objective_destination_zone_name == "King Ranperre's Tomb")
assert(bat_hunt[1].objective_target.x == -141.134 and bat_hunt[1].objective_target.z == 223.168,
    'Bat Hunt must put the entrance Ding Bats camp first instead of routing through the Tomb to a deeper camp')
objective_inventory_counts_by_name['orcish mail scales'] = 1
local bat_hunt_after_scales = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(bat_hunt_after_scales, 'Bat Hunt') == 1,
    'owned Orcish Mail Scales must replace the Ding Bats camps with one exact mission Tombstone')
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
assert(tombstone_mode == 'test-ready' and tombstone_message == ''
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
assert(progress_bytes:find(
    "alpha:1001\tmission:San d'Oria:2\tmission:San d'Oria:2:step-009\t9",
    1, true) ~= nil,
    'completed interaction progress was not persisted for zoning or addon reload')
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
accessxi.mission_packet_source = 'cache'
local bat_target, bat_message, bat_mode = accessxi.nav_mission_quest_prepare_route(
    bat_hunt_after_cutscene[1], { zone = 230 })
assert(bat_mode == 'test-ready' and type(bat_target) == 'table' and bat_message == '',
    'the next mission source destination must start without current-session packet evidence')
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
assert(arnau_mode == 'test-ready' and arnau_message == ''
    and type(arnau_target) == 'table',
    'the exact Arnau objective did not produce a source-backed route')
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
assert(hut_mode == 'test-ready' and hut_message == ''
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
local unmapped_pickpocket = assert(find(accessxi.nav_mission_quest_active_items('quest'), 'The Pickpocket'))
assert(type(unmapped_pickpocket.objective_candidate_id) == 'string'
    and unmapped_pickpocket.objective_candidate_id ~= '',
    'an exact source-backed current target must survive a missing optional guide-step mapping')
assert(select(3, accessxi.nav_mission_quest_prepare_route(unmapped_pickpocket, { zone = 230 })) == 'test-ready')
accessxi.objective_guides.automatic_step_id = function() error('intentional mapping failure') end
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
    assert(select(3, accessxi.nav_mission_quest_prepare_route(instruction_rows[1], { zone = 230 })) == 'blocked',
        'changed instruction-only ownership must block: ' .. field)
end
guide_row_mutator = nil

accessxi.mission_packet_source = 'cache'
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.mission_packet_source = 'packet_in_056'
accessxi.mission_packet_session_epoch = current_session_epoch - 1
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.mission_packet_session_epoch = current_session_epoch
quest_entries['sandoria:current'].source = 'cache'
assert(select(3, accessxi.nav_mission_quest_prepare_route(cid, { zone = 230 })) == 'test-ready')
quest_entries['sandoria:current'].source = 'packet_in_056'
accessxi.quest_packet_session_epoch = current_session_epoch - 1
assert(select(3, accessxi.nav_mission_quest_prepare_route(cid, { zone = 230 })) == 'test-ready')
accessxi.quest_packet_session_epoch = current_session_epoch
accessxi.key_items_packet_tables[0].source = 'cache'
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.key_items_packet_tables[0].source = 'packet_in_055'
accessxi.key_items_packet_tables[0].identity = 'alpha:9999'
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.key_items_packet_tables[0].identity = current_identity
accessxi.key_items_packet_tables[0].session_epoch = current_session_epoch - 1
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.key_items_packet_tables[0].session_epoch = current_session_epoch
local saved_key_item_tables = accessxi.key_items_packet_tables
accessxi.key_items_packet_tables = {}
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.key_items_packet_tables = saved_key_item_tables
accessxi.inventory_packet_source = 'cache'
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.inventory_packet_source = 'packet_in_inventory'
accessxi.inventory_packet_identity = 'alpha:9999'
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
accessxi.inventory_packet_identity = current_identity
accessxi.inventory_packet_session_epoch = current_session_epoch - 1
assert(select(3, accessxi.nav_mission_quest_prepare_route(typed_lower, { zone = 234 })) == 'test-ready')
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
    assert(select(3, accessxi.nav_mission_quest_prepare_route(refreshed_lower, { zone = 234 })) == 'blocked',
        'changed typed objective identity must block: ' .. field)
end
guide_row_mutator = nil

local saved_runtime = accessxi.objective_route_runtime
accessxi.objective_route_runtime = nil
assert(select(3, accessxi.nav_mission_quest_prepare_route(refreshed_lower, { zone = 234 })) == 'test-ready')
accessxi.objective_route_runtime = saved_runtime
runtime_override = function() error('intentional runtime failure') end
assert(select(3, accessxi.nav_mission_quest_prepare_route(refreshed_lower, { zone = 234 })) == 'test-ready')
runtime_override = function() return {}, '', 'invented-mode' end
assert(select(3, accessxi.nav_mission_quest_prepare_route(refreshed_lower, { zone = 234 })) == 'test-ready')
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
mission_value_packet_age = 60
logs:clear()
local rows = accessxi.nav_mission_quest_active_items('mission')
local zilart = assert(find(rows, "Kazham's Chieftainess"))
assert(zilart.mission_context == 'Rise of the Zilart')
for _, line in ipairs(logs) do
    assert(line:find('base out of range', 1, true) == nil)
end
mission_values['Rise of the Zilart'] = 2
mission_value_packet_age = 10
local native_mission_load_mission_rom_rows = accessxi.load_mission_rom_rows
mission_values['Chains of Promathia'] = 1
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
assert(chain_survivor_mode == 'test-ready' and type(chain_survivor_target) == 'table'
    and chain_survivor_message == '')
accessxi.load_mission_rom_rows = native_mission_load_mission_rom_rows
mission_values['Chains of Promathia'] = 0
local survey_after_failure = assert(find(missions, 'A Geological Survey'))
local failure_target, failure_message, failure_mode = accessxi.nav_mission_quest_prepare_route(survey_after_failure, { zone = 106 })
assert(failure_mode == 'test-ready' and type(failure_target) == 'table' and failure_message == '')

accessxi.mission_packet_source = 'cache'
missions = accessxi.nav_mission_quest_active_items('mission')
local cached_survey = assert(find(missions, 'A Geological Survey'))
assert(find(missions, "Welcome t'Norg") ~= nil)
local cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_survey, { zone = 106 })
assert(type(cached_target) == 'table' and cached_mode == 'test-ready' and cached_message == '')
accessxi.mission_packet_source = 'packet_in_056'
cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_survey, { zone = 106 })
assert(type(cached_target) == 'table' and cached_mode == 'test-ready' and cached_message == '')
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
assert(type(stale_target) == 'table' and stale_target.objective_test_route == true
    and stale_target.verified ~= true and stale_mode == 'test-ready' and stale_message == '')
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
assert(starter_mode == 'test-ready' and starter_message == '' and type(starter_target) == 'table',
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
assert(starter_mode == 'test-ready' and starter_message == '' and type(starter_target) == 'table')
assert(starter_target.name == 'Ambrotien' or starter_target.name == 'Grilau',
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
assert(rescue_route_mode == 'test-ready' and rescue_route_message == ''
    and rescue_route.objective_route_recommendation == rescue_after_accept.objective_route_recommendation,
    'route preparation dropped the route-time Silent Oil recommendation')
local rescue_start_suffix = accessxi.nav_mission_quest_start_suffix(rescue_route)
assert(rescue_start_suffix:find(rescue_route.objective_route_recommendation, 1, true) ~= nil,
    'route start speech omitted the Silent Oil recommendation')
assert(accessxi.nav_mission_quest_arrival_suffix(rescue_route)
        :find(rescue_route.objective_route_recommendation, 1, true) == nil,
    'route recommendation was delayed until arrival instead of route start')

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
accessxi.mission_packet_main.tales = 0
assert(find(accessxi.nav_mission_quest_active_items('mission'), 'Rhapsodies of Vanadiel') == nil,
    'RoV was advertised without a live active or postponed-start packet state')
mission_values["Rhapsodies of Vana'diel"] = 110
local active_rov = assert(find(
    accessxi.nav_mission_quest_active_items('mission'), 'Rhapsodies of Vanadiel'))
assert(active_rov.mission_availability == 'active',
    'a decoded nonterminal RoV mission value was not exposed as active')
mission_values["Rhapsodies of Vana'diel"] = 65535

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
assert(type(cached_target) == 'table' and cached_target.objective_test_route == true
    and cached_target.verified ~= true and cached_mode == 'test-ready' and cached_message == '')
accessxi.quest_packet_source = 'packet_in_056'
quest_entries['aht_urhgan:current'].source = 'packet_in_056'
cached_target, cached_message, cached_mode = accessxi.nav_mission_quest_prepare_route(cached_pickpocket, { zone = 106 })
assert(type(cached_target) == 'table' and cached_target.objective_test_route == true
    and cached_target.verified ~= true and cached_mode == 'test-ready' and cached_message == '')
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
assert(select(3, accessxi.nav_mission_quest_prepare_route(fresh_mission_row, { zone = 106 })) == 'test-ready')
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
assert(mode == 'test-ready' and type(target) == 'table' and message == '',
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
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_stage == 'return-red-tester')
assert(survey.objective_target.zone == 237 and survey.objective_target.name == 'Cid')

-- Contradictory or unavailable ownership and missing nav points never guess.
owned_key_items[3] = true
missions = accessxi.nav_mission_quest_active_items('mission')
survey = assert(find(missions, 'A Geological Survey'))
assert(survey.objective_available == false and survey.objective_status == 'stage-unverified')
target, message, mode = accessxi.nav_mission_quest_prepare_route(survey, { zone = 191 })
assert(target == nil and mode == 'blocked' and message ~= '')

owned_key_items[3] = nil
owned_key_items[4] = nil
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

os.remove(objective_progress_path)
return true
