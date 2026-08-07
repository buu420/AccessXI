local data = {
    missions = {},
    quests = {},
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
