-- Reviewed links between guide actions and native destinations/events.
-- Source: LandSandBoat/scripts/missions/windurst/1_2_The_Heart_of_the_Matter.lua,
-- checked 2026-09-08 against the shipped npc_list and four entrance meshes.
-- Event identities describe observable cutscenes, not hidden server variables.
local key = 'mission:Windurst:2';
local gizmos, place, collect = {}, {}, {};
-- Native ID, placement cutscene, retrieval cutscene (_5ee through _5ej).
for _,entry in ipairs({
    {17572250,58,46}, {17572251,59,47}, {17572252,60,48},
    {17572253,61,49}, {17572254,62,50}, {17572255,63,51},
}) do
    local id=entry[1];
    gizmos[#gizmos+1]='npc:v1:194:'..id;
    place[id]=entry[2];
    collect[id]=entry[3];
end;
local apururu={'npc:v1:241:17764372'};
local pore={'npc:v1:116:17253039'};
local ingress={edge_id=1664627578,from_zone=116};
return {
    [key]={revision='heart-of-matter-v1',actions={
        [key..':step-009:claim-02']={destinations=apururu,events={137}},
        -- The first outdoor stop is the charm giver, before entering the tower.
        [key..':step-018:claim-02']={destinations=pore,destination_zone_id=116,
            destination_zone_name='East Sarutabaruta',zones={'East Sarutabaruta'},
            target='Pore-Ohre',instruction='Go to Pore-Ohre outside Marguerite Tower in East Sarutabaruta (J-11).'},
        [key..':step-020:claim-01']={destinations=pore,events={46}},
        [key..':step-021:claim-01']={destinations=pore},
        [key..':step-021:claim-02']={destinations=pore,events={46}},
        [key..':step-025:claim-01']={destinations={'area:v1:116:1664627578'},
            target='Outer Horutoto Ruins',destination_zone_id=194,
            destination_zone_name='Outer Horutoto Ruins',zones={'Outer Horutoto Ruins'},
            completion_zone=194,
            instruction='Enter Outer Horutoto Ruins through Marguerite Tower beside Pore-Ohre.'},
        [key..':step-025:claim-02']={destinations=gizmos,members=place,ingress=ingress,
            target='Ancient Magical Gizmo',objects={'Ancient Magical Gizmo'},
            instruction='Place a dark Mana Orb in each of the six Ancient Magical Gizmos. Four are in the main room; two are behind the north and south Cracked Walls. Open those walls when you reach them.'},
        -- These are directions to two members of the same six-object set,
        -- not another mandatory pass through the walls after placing all six.
        [key..':step-027:claim-01']={omit=true},
        [key..':step-027:claim-02']={omit=true},
        [key..':step-028:claim-01']={destinations={'object:v1:194:17572249'},
            action='examine',relationship='examine-object',target_kind='object',
            target='Gate: Magical Gizmo',objects={'Gate: Magical Gizmo'},events={44},ingress=ingress,
            instruction='Pass through the east Cracked Wall and examine Gate: Magical Gizmo to energize the six Mana Orbs.'},
        [key..':step-030:claim-01']={destinations=gizmos,members=collect,ingress=ingress,
            target='Ancient Magical Gizmo',objects={'Ancient Magical Gizmo'},
            instruction='Retrieve a glowing Mana Orb from each of the six Ancient Magical Gizmos.'},
        [key..':step-045:claim-01']={destinations=apururu,events={143,145},
            instruction='Return to Apururu at the Manustery in Windurst Woods to finish the mission.'},
    }},
};
