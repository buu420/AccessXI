-- VERIFIED INSTRUCTIONS THE GUIDE PROSE LEAVES OUT.
--
-- The wiki paragraphs this addon reconciles are written for someone who can see
-- the screen. Where they skip a step that a sighted player simply notices, a
-- blind player is left stranded on ground the guide says nothing about.
--
-- Live 2026-08-29, Below the Arks. The guide's step-009 reads "Examine the
-- Shattered Telepoint to trigger a cutscene and enter the Hall of Transference"
-- and stops there. It never says that the Hall contains two Large Apparatus and
-- that one of them is the way into Promyvion. The player worked it out
-- themselves and reported it: "apparently you have to enter the shattered
-- telepoint, then examine the aperatus."
--
-- This table is NOT an override. Overrides re-namespace a mission's step ids,
-- and a cursor must not cross an override boundary -- adding one mid-mission
-- would throw away the progress the player has. These are additive speech only:
-- they change what is SAID about a step and never which step is current, so
-- they are safe to add to a mission somebody is standing in the middle of.
--
-- RULES FOR ADDING A ROW
--   * Quote-checkable. Every note here must be traceable to BG Wiki or
--     FFXIclopedia, and the source goes in the comment above it. A note is
--     spoken to a blind player as fact.
--   * Instructions, not lore. Say what to do and where.
--   * Never contradict the guide. This supplements; it does not correct.
--
-- Keyed by native key, then by the GUIDE step id the note belongs to.

local notes = {};

-- ---------------------------------------------------------------------------
-- Chains of Promathia
-- ---------------------------------------------------------------------------

-- BG Wiki, Below the Arks: "After examining the Shattered Telepoint and
-- entering the Hall of Transference, click on the Large Apparatus to your left
-- to enter Promyvion if this is your first time here."
--
-- FFXIclopedia, Hall of Transference: "The Large Apparatus on the right can be
-- used to teleport to Ru'Aun Gardens after completing the necessary steps." --
-- so which one matters, and picking wrong wastes a Clear Chip trip.
--
-- Confirmed against the LandSandBoat scripts as well: the mission registers
-- _0e3/_0e5/_0e7 (the left apparatus of each crag's chamber) and only those.
notes["mission:Chains of Promathia:3"] = {
    ["mission:Chains of Promathia:3:step-009"] =
        "Examining the Shattered Telepoint teleports you into the Hall of "
        .. "Transference; you cannot walk there. Inside, examine the Large "
        .. "Apparatus on your LEFT to enter Promyvion. The one on the right "
        .. "goes to Ru'Aun Gardens and needs a Clear Chip.",
};

return notes;
