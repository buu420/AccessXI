local data = {
    missions = {},
    quests = {},
    source_verified_candidates = {},
};

-- These rows are explicit navigation choices derived from the pinned mission
-- guides and the installed LandSandBoat spawn catalogue.  They do not claim a
-- pre-approved walking path; pressing I asks the ordinary route engine to
-- calculate one from the player's current position.
data.source_verified_candidates["mission:San d'Oria:1"] = T{
    T{
        candidate_id = "mission:San d'Oria:1:step-005:claim-01:source-route:east",
        action_id = "mission:San d'Oria:1:step-005:claim-01",
        group_id = "mission:San d'Oria:1:step-005:claim-01:group:east",
        destination_id = 'camp:v1:101:orcish-fodder:6c7a4f36673f6091fd2c',
        guide_step_id = "mission:San d'Oria:1:step-005",
        guide_step_order = 5,
        action = 'fight',
        action_instruction = 'Defeat Orcish Fodder in East Ronfaure until you obtain an Orcish Axe.',
        arrival_instruction = 'Defeat Orcish Fodder in East Ronfaure until you obtain an Orcish Axe.',
        classification = 'catalogue-candidate',
        route_ready = false,
        zone = 101,
        zone_name = 'East Ronfaure',
        target_name = 'Orcish Fodder',
        target_kind = 'enemy',
        target_point = T{ 289.535, 150.856, -50.375 },
        raw_identity = 'lsb:mob_spawn_points:group:13:mobname:Orcish_Fodder',
        raw_spawn_ids = T{ 17191007 },
        cluster_policy_version = 'complete-link-v1-h120-y24',
        label = 'Orcish Fodder east camp',
        items = T{ 'Orcish Axe' },
        enemies = T{ 'Orcish Fodder' },
    },
    T{
        candidate_id = "mission:San d'Oria:1:step-005:claim-01:source-route:west",
        action_id = "mission:San d'Oria:1:step-005:claim-01",
        group_id = "mission:San d'Oria:1:step-005:claim-01:group:west",
        destination_id = 'camp:v1:100:orcish-fodder:b2999235c7bf7f4860f7',
        guide_step_id = "mission:San d'Oria:1:step-005",
        guide_step_order = 5,
        action = 'fight',
        action_instruction = 'Defeat Orcish Fodder in West Ronfaure until you obtain an Orcish Axe.',
        arrival_instruction = 'Defeat Orcish Fodder in West Ronfaure until you obtain an Orcish Axe.',
        classification = 'catalogue-candidate',
        route_ready = false,
        zone = 100,
        zone_name = 'West Ronfaure',
        target_name = 'Orcish Fodder',
        target_kind = 'enemy',
        target_point = T{ -284.394, 399.875, -60.339 },
        raw_identity = 'lsb:mob_spawn_points:group:12:mobname:Orcish_Fodder',
        raw_spawn_ids = T{ 17186951 },
        cluster_policy_version = 'complete-link-v1-h120-y24',
        label = 'Orcish Fodder west camp',
        items = T{ 'Orcish Axe' },
        enemies = T{ 'Orcish Fodder' },
    },
};

-- Retail progression evidence:
--   LandSandBoat scripts/missions/bastok/1_2_A_Geological_Survey.lua
--   LandSandBoat scripts/zones/Dangruf_Wadi/Zone.lua
--   https://www.bg-wiki.com/ffxi/Bastok_Mission_1-2
-- The three stages are distinguished only by native key-item ownership. The
-- geyser point is the center of the authoritative I-8 trigger cuboid and was
-- independently confirmed reachable from the south entrance with xiNavmesh.
data.missions['Bastok:1'] = {
    title = 'A Geological Survey',
    context = 'Bastok',
    mission_id = 1,
    required_key_items = T{ 3, 4 }, -- Blue acidity tester; Red acidity tester.
    source = 'LandSandBoat Bastok 1-2 mission script and Dangruf Wadi trigger areas; BG-Wiki Bastok Mission 1-2',
    stages = T{
        {
            key = 'return-red-tester',
            when = 'owns',
            key_item = 4,
            instruction = 'Talk to Cid in his Metalworks lab to return the Red acidity tester and finish the mission.',
            arrival_instruction = 'Talk to Cid and return the Red acidity tester to finish the mission.',
            target = {
                reference = { zone = 237, name = 'Cid', kind = 'npc' },
            },
        },
        {
            key = 'charge-blue-tester',
            when = 'owns',
            key_item = 3,
            instruction = 'At I-8, stand on the geyser until it launches you onto the ledge. Check that the Blue acidity tester becomes a Red acidity tester before leaving.',
            arrival_instruction = 'Stand on the geyser until it launches you onto the ledge, then check that the Blue acidity tester became a Red acidity tester.',
            target = {
                point = {
                    zone = 191,
                    name = 'I-8 geyser',
                    x = -133.1,
                    z = 133.2,
                    y = 3.0,
                    kind = 'object',
                    source = 'mission-objective:geological-survey:lsb-trigger-1:navprobe-south-reachable',
                    confidence = 'verified',
                    arrival_radius = 1.0,
                },
            },
        },
        {
            key = 'obtain-blue-tester',
            when = 'owns-none',
            instruction = 'Talk to Cid in his Metalworks lab to receive the Blue acidity tester.',
            arrival_instruction = 'Talk to Cid to receive the Blue acidity tester.',
            target = {
                reference = { zone = 237, name = 'Cid', kind = 'npc' },
            },
        },
    },
};

return data;
