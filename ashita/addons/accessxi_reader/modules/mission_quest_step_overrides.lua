-- REVIEWED STEP OVERRIDES.
--
-- The scraped guide corpus resolves some native mission ids through a WIKI
-- REDIRECT, so several distinct missions collapse onto one page. Measured over
-- data/mission-quest-guides/source-snapshot.json: 3,889 pages, 450 carrying
-- aliases, and exactly EIGHT that collapse two or more genuinely different
-- missions. One of them is
--
--     canonical_title "Journey Abroad"
--     aliases         { "Journey to Bastok", "Journey to Windurst" }
--
-- which is why San d'Oria native ids 6, 7, 8, 9 and 10 all carry the SAME
-- fifteen steps. Live 2026-08-25 the player finished Journey Abroad, the game
-- moved them to id 7 "Journey to Bastok", and the addon replayed id 6's text --
-- routing them to Windurst and back to San d'Oria while they were meant to be
-- fetching mythril sand out of Palborough Mines.
--
-- These are the real sequences, taken from the LandSandBoat mission scripts and
-- checked against this addon's own retail-derived catalogue: every entity named
-- below EXISTS in data/ffxi-nav-destinations.tsv, and the three NPCs that could
-- be cross-checked agree on position to three decimals in x and z
-- (Savae E Paleade 23.724/-43.360, Grohm -18.084/-27.576, Pius 99.916/-12.537).
-- Nothing here is invented; where a name resolves to several rows -- seven
-- Mythril Seams, two Refiner Levers -- the step offers them all rather than
-- silently choosing.
--
-- The traversal is a STATE MACHINE, not a list. Bastok first runs
-- 6 -> 7 -> 6 -> 10 -> 6 -> complete, and id 6 means three different things
-- along the way. Never derive the next mission as current + 1.
--
-- STEP IDS ARE NAMESPACED, AND THAT IS LOAD-BEARING.
--
-- Every id below carries ":reviewed:". The scraped page for this native key
-- generates ids of the form "mission:San d'Oria:7:step-004" too, and
-- mapped_previous_progress_record() carries a saved cursor ACROSS a revision
-- change by matching step_id and action_id as STRINGS. Live 2026-08-25 the
-- player's cursor sat on the collapsed page's step-004, "Halver will instruct
-- you to visit two other Nations"; the instant this override took effect that
-- id matched the override's own step-004, "trade the gravel to the Refiner
-- Lid", and the addon sent them to Palborough Mines having skipped Pius, Grohm
-- and the Mythril Seam entirely. An id that means two different things in two
-- different tables is worse than no override at all.
--
-- Keyed by native_key. Steps replace the reconciled ones entirely.

local function step(order, id, action, entities, zones, text, completion_evidence)
    return {
        stable_step_id = id,
        order = order,
        -- WHAT PROVES THIS STEP IS DONE, when the action itself cannot say.
        --
        -- A defeat COUNT cannot tell two enemies apart, so it can never
        -- distinguish "both essential mobs died" from "the same one died
        -- twice", nor one kill before a wipe from one kill after it. A
        -- battlefield's reward key item can: it is granted only on a genuine
        -- win. Naming it here keeps the step reading as the fight it is --
        -- "Defeat the Black Dragon and the Searcher" -- while moving the proof
        -- somewhere that cannot be satisfied early. A separate later step would
        -- not do: the fight step would still advance on its own and the player
        -- would hear it complete while the Searcher was alive.
        completion_evidence = completion_evidence,
        source_orders = { 0, 0 },
        comparison = 'reviewed-override',
        agreed_fields = {},
        conflicting_fields = {},
        action = action,
        entities = entities,
        zones = zones,
        grid_coordinates = {},
        bg_instruction = text,
        ffxiclopedia_instruction = text,
        route_ready = false,
    };
end

local SANDORIA_6 = "mission:San d'Oria:6";
local SANDORIA_7 = "mission:San d'Oria:7";
local SANDORIA_8 = "mission:San d'Oria:8";
local SANDORIA_9 = "mission:San d'Oria:9";
local SANDORIA_10 = "mission:San d'Oria:10";

return {
    -- Journey Abroad. THE SAME NATIVE ID MEANS THREE DIFFERENT THINGS.
    --
    -- Retail's 0x056 gives us `nation_mission` and nothing else -- no status
    -- byte for nation missions. Verified live 2026-08-25 on this player's own
    -- history, the field walks 4 -> 5 -> 6, so committing to a branch is
    -- plainly visible. Coming BACK is not: the field reads 5 (native id 6)
    -- whether you have chosen no nation yet, finished one half, or finished
    -- both and owe Halver a report.
    --
    -- Key items separate them without any stored history, which matters because
    -- a player installing this mod mid-mission has no history to read. Halver
    -- grants Letter to the Consuls (key item 5) and it is deleted the moment you
    -- commit to a nation; the second half grants Kindred Report (29), which
    -- Halver takes back. When the key-item table has not arrived we say so by
    -- saying LESS -- the default below offers both nations and claims nothing
    -- about which is finished. Never a confident wrong answer.
    --
    -- One entry per nation, both visible, each completing on its own: the
    -- player asked for exactly this, and it is also what their mission log
    -- shows a sighted player.
    [SANDORIA_6] = {
        title = 'Journey Abroad',
        source = 'lsb:2_3_0_Journey_Abroad',
        variants = {
            {
                state = 'report',
                when = { key_item_held = 29 },
                steps = {
                    step(1, SANDORIA_6 .. ':reviewed:report:step-001', 'talk',
                        { 'Halver', "Chateau d'Oraguille" }, { "Chateau d'Oraguille" },
                        "Both halves are done and you are carrying the Kindred Report. Return to Halver in Chateau d'Oraguille to finish Journey Abroad."),
                },
            },
            {
                state = 'choose',
                when = { key_item_held = 5 },
                steps = {
                    step(1, SANDORIA_6 .. ':reviewed:choose:step-001', 'talk',
                        { 'Savae E Paleade', 'Metalworks' }, { 'Metalworks' },
                        'Bastok: deliver the letter to Savae E Paleade in the Metalworks. Both nations must be visited before Halver will see you again, and you may take them in either order. Whichever you do SECOND is a different, shorter mission that ends in a rank 2 battlefield rather than an errand.'),
                    step(2, SANDORIA_6 .. ':reviewed:choose:step-002', 'talk',
                        { 'Mourices', 'Windurst Woods' }, { 'Windurst Woods' },
                        'Windurst: deliver the letter to Mourices in Windurst Woods. Both nations must be visited before Halver will see you again, and you may take them in either order. Whichever you do SECOND is a different, shorter mission that ends in a rank 2 battlefield rather than an errand.'),
                },
            },
            {
                -- A second half is recorded complete, so both are. Bits 8 and 9
                -- are the SECOND-nation missions; reaching either means the
                -- first was already finished.
                state = 'report-bits',
                when = { nation_mission_any_complete = { { 0, 8 }, { 0, 9 } } },
                steps = {
                    step(1, SANDORIA_6 .. ':reviewed:report-bits:step-001', 'talk',
                        { 'Halver', "Chateau d'Oraguille" }, { "Chateau d'Oraguille" },
                        "Your record shows both halves of Journey Abroad are complete. Return to Halver in Chateau d'Oraguille to finish the mission."),
                },
            },
            {
                -- Bastok's half is recorded done and no second half is; the
                -- Windurst half remains. Both entries stay listed: these bits
                -- are permanent, so they may annotate a choice but must never
                -- remove one.
                state = 'second-windurst',
                when = {
                    nation_mission_complete = { { 0, 6 } },
                    nation_mission_incomplete = { { 0, 8 }, { 0, 9 } },
                },
                steps = {
                    step(1, SANDORIA_6 .. ':reviewed:second-windurst:step-001', 'talk',
                        { 'Mourices', 'Windurst Woods' }, { 'Windurst Woods' },
                        'Windurst is the half you have left. Speak to Mourices in Windurst Woods. As your second nation this is the battlefield version: Kupipi in Heavens Tower gives you the Dark Key, you clear the rank 2 battlefield at Balga\'s Dais against the Black Dragon and the Searcher, then you report back to Mourices.'),
                    step(2, SANDORIA_6 .. ':reviewed:second-windurst:step-002', 'talk',
                        { 'Savae E Paleade', 'Metalworks' }, { 'Metalworks' },
                        'Bastok: Savae E Paleade in the Metalworks. Your completed-mission record already shows this half done, so you should not need it. It is listed anyway because those bits are permanent -- if you ran this chain under a previous allegiance they would still be set.'),
                },
            },
            {
                -- Mirror: Windurst's half is recorded done, Bastok remains.
                state = 'second-bastok',
                when = {
                    nation_mission_complete = { { 0, 7 } },
                    nation_mission_incomplete = { { 0, 8 }, { 0, 9 } },
                },
                steps = {
                    step(1, SANDORIA_6 .. ':reviewed:second-bastok:step-001', 'talk',
                        { 'Savae E Paleade', 'Metalworks' }, { 'Metalworks' },
                        'Bastok is the half you have left. Speak to Savae E Paleade in the Metalworks. As your second nation this is the battlefield version: Pius and Grohm in the Metalworks send you on, you clear the rank 2 battlefield at Waughroon Shrine against the Dark Dragon and the Seeker, then you report back to Savae E Paleade.'),
                    step(2, SANDORIA_6 .. ':reviewed:second-bastok:step-002', 'talk',
                        { 'Mourices', 'Windurst Woods' }, { 'Windurst Woods' },
                        'Windurst: Mourices in Windurst Woods. Your completed-mission record already shows this half done, so you should not need it. It is listed anyway because those bits are permanent -- if you ran this chain under a previous allegiance they would still be set.'),
                },
            },
            {
                state = 'second',
                when = { key_item_absent = { 5, 29 } },
                steps = {
                    step(1, SANDORIA_6 .. ':reviewed:second:step-001', 'talk',
                        { 'Savae E Paleade', 'Metalworks' }, { 'Metalworks' },
                        'Bastok: Savae E Paleade in the Metalworks. One of the two halves is already finished -- skip whichever of these two you have done. The remaining one is the battlefield version: talk to your contact, then clear a rank 2 battlefield, then report back to them.'),
                    step(2, SANDORIA_6 .. ':reviewed:second:step-002', 'talk',
                        { 'Mourices', 'Windurst Woods' }, { 'Windurst Woods' },
                        'Windurst: Mourices in Windurst Woods. One of the two halves is already finished -- skip whichever of these two you have done. The remaining one is the battlefield version: talk to your contact, then clear a rank 2 battlefield, then report back to them.'),
                },
            },
        },
        -- No key-item table yet: offer both and claim nothing about progress.
        steps = {
            step(1, SANDORIA_6 .. ':reviewed:step-001', 'talk',
                { 'Savae E Paleade', 'Metalworks' }, { 'Metalworks' },
                'Bastok: Savae E Paleade in the Metalworks. Both nations must be visited before Halver will see you again, and you may take them in either order. Whichever you do SECOND is a different, shorter mission that ends in a rank 2 battlefield rather than an errand.'),
            step(2, SANDORIA_6 .. ':reviewed:step-002', 'talk',
                { 'Mourices', 'Windurst Woods' }, { 'Windurst Woods' },
                'Windurst: Mourices in Windurst Woods. Both nations must be visited before Halver will see you again, and you may take them in either order. Whichever you do SECOND is a different, shorter mission that ends in a rank 2 battlefield rather than an errand.'),
            step(3, SANDORIA_6 .. ':reviewed:step-003', 'talk',
                { 'Halver', "Chateau d'Oraguille" }, { "Chateau d'Oraguille" },
                "When both halves are done you will be carrying the Kindred Report; take it to Halver in Chateau d'Oraguille."),
        },
    },

    -- Journey to Bastok, first nation.
    [SANDORIA_7] = {
        title = 'Journey to Bastok',
        source = 'lsb:2_3_1_Journey_to_Bastok',
        steps = {
            step(1, SANDORIA_7 .. ':reviewed:step-001', 'talk', { 'Pius', 'Metalworks' }, { 'Metalworks' },
                'Talk to Pius in the Metalworks.'),
            step(2, SANDORIA_7 .. ':reviewed:step-002', 'talk', { 'Grohm', 'Metalworks' }, { 'Metalworks' },
                'Talk to Grohm in the Metalworks. He gives you three Pickaxes.'),
            step(3, SANDORIA_7 .. ':reviewed:step-003', 'trade', { 'Mythril Seam', 'Palborough Mines' }, { 'Palborough Mines' },
                'In Palborough Mines, trade a Pickaxe to a Mythril Seam to obtain a Chunk of Mine Gravel. It succeeds a little under half the time, so bring all three Pickaxes. Skip this if you already hold an Onz of Mythril Sand.'),
            step(4, SANDORIA_7 .. ':reviewed:step-004', 'trade', { 'Refiner Lid', 'Palborough Mines' }, { 'Palborough Mines' },
                'Trade the Chunk of Mine Gravel to the Refiner Lid on the upper refinery floor.'),
            step(5, SANDORIA_7 .. ':reviewed:step-005', 'examine', { 'Refiner Lever', 'Palborough Mines' }, { 'Palborough Mines' },
                'Trigger the Refiner Lever beside the lid, on the upper refinery floor.'),
            step(6, SANDORIA_7 .. ':reviewed:step-006', 'examine', { 'Refiner Lever', 'Palborough Mines' }, { 'Palborough Mines' },
                'Go down to the lower refinery floor and trigger the other Refiner Lever. You receive the Onz of Mythril Sand.'),
            step(7, SANDORIA_7 .. ':reviewed:step-007', 'trade', { 'Savae E Paleade', 'Metalworks' }, { 'Metalworks' },
                'Return to the Metalworks and trade the Onz of Mythril Sand to Savae E Paleade. This finishes the Bastok half. The Windurst half comes next: Kupipi in Heavens Tower, then Uu Zhoumo in Giddeus, then two Parana Shields to Mourices in Windurst Woods.'),
        },
    },

    -- Journey to Windurst, first nation.
    [SANDORIA_8] = {
        title = 'Journey to Windurst',
        source = 'lsb:2_3_2_Journey_to_Windurst',
        steps = {
            step(1, SANDORIA_8 .. ':reviewed:step-001', 'travel', { 'Heavens Tower' }, { 'Heavens Tower' },
                'Enter Heavens Tower in Windurst Walls. Zoning in starts the cutscene.'),
            step(2, SANDORIA_8 .. ':reviewed:step-002', 'talk', { 'Kupipi', 'Heavens Tower' }, { 'Heavens Tower' },
                'Talk to Kupipi in Heavens Tower to receive the key item Shield Offering.'),
            step(3, SANDORIA_8 .. ':reviewed:step-003', 'examine', { 'Uu Zhoumo', 'Giddeus' }, { 'Giddeus' },
                'Travel to Giddeus and trigger Uu Zhoumo. The Shield Offering is consumed.'),
            step(4, SANDORIA_8 .. ':reviewed:step-004', 'obtain', { 'Parana Shield' }, {},
                'Obtain two Parana Shields. Any source will do.'),
            step(5, SANDORIA_8 .. ':reviewed:step-005', 'trade', { 'Mourices', 'Windurst Woods' }, { 'Windurst Woods' },
                'Trade exactly two Parana Shields to Mourices in Windurst Woods. This finishes the Windurst half. The Bastok half comes next: Pius and Grohm in the Metalworks, mythril sand out of Palborough Mines, then back to Savae E Paleade.'),
        },
    },

    -- Journey to Bastok, second nation.
    [SANDORIA_9] = {
        title = 'Journey to Bastok',
        source = 'lsb:2_3_3_Journey_to_Bastok2',
        steps = {
            step(1, SANDORIA_9 .. ':reviewed:step-001', 'talk', { 'Pius', 'Metalworks' }, { 'Metalworks' },
                'Talk to Pius in the Metalworks.'),
            step(2, SANDORIA_9 .. ':reviewed:step-002', 'talk', { 'Grohm', 'Metalworks' }, { 'Metalworks' },
                'Talk to Grohm in the Metalworks.'),
            step(3, SANDORIA_9 .. ':reviewed:step-003', 'travel', { 'Burning Circle', 'Waughroon Shrine' }, { 'Waughroon Shrine' },
                'Enter the rank 2 battlefield at Waughroon Shrine through the Burning Circle.'),
            -- Proved by the Kindred Crest, which the battlefield grants only
            -- on a genuine win (LSB 2_3_3_Journey_to_Bastok2.lua:124).
            step(4, SANDORIA_9 .. ':reviewed:step-004', 'fight', { 'Dark Dragon', 'Seeker' }, { 'Waughroon Shrine' },
                'Defeat the Dark Dragon and the Seeker. Winning awards the key item Kindred Crest; nothing before that proves the fight is over, so do not leave early.',
                'key-item:Kindred Crest'),
            step(5, SANDORIA_9 .. ':reviewed:step-005', 'talk', { 'Savae E Paleade', 'Metalworks' }, { 'Metalworks' },
                'Talk to Savae E Paleade in the Metalworks. This returns you to Journey Abroad with the Kindred Report.'),
        },
    },

    -- Journey to Windurst, second nation.
    [SANDORIA_10] = {
        title = 'Journey to Windurst',
        source = 'lsb:2_3_4_Journey_to_Windurst2',
        steps = {
            step(1, SANDORIA_10 .. ':reviewed:step-001', 'talk', { 'Kupipi', 'Heavens Tower' }, { 'Heavens Tower' },
                'Talk to Kupipi in Heavens Tower to receive the Dark Key.'),
            step(2, SANDORIA_10 .. ':reviewed:step-002', 'travel', { 'Burning Circle', "Balga's Dais" }, { "Balga's Dais" },
                "Enter the rank 2 battlefield at Balga's Dais through the Burning Circle."),
            -- LSB grants the crest at 2_3_4_Journey_to_Windurst2.lua:30.
            step(3, SANDORIA_10 .. ':reviewed:step-003', 'fight', { 'Black Dragon', 'Searcher' }, { "Balga's Dais" },
                'Defeat the Black Dragon and the Searcher. Winning awards the key item Kindred Crest; nothing before that proves the fight is over, so do not leave early.',
                'key-item:Kindred Crest'),
            step(4, SANDORIA_10 .. ':reviewed:step-004', 'talk', { 'Mourices', 'Windurst Woods' }, { 'Windurst Woods' },
                'Talk to Mourices in Windurst Woods. This returns you to Journey Abroad with the Kindred Report.'),
        },
    },
};
