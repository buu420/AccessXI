-- Generated from data/mission-quest-guides/reviewed-overrides.json by
-- tools/generate_objective_role_members.py. Do not edit by hand.
--
-- Which real NPCs fill a role the guide names instead of a person.
-- These are facts about the ROLE, not about the one step that happened
-- to be reviewed, so every step naming the role can use them.
return {
  ["gate guard"] = {
    name = "Gate Guard",
    review_basis = "Exact gate-guard member notes in the pinned BG revision and matching role claim in both pinned guide revisions",
    reviewed_step = "mission:San d'Oria:1:step-001:claim-01",
    allowed_zones = { "Northern San d'Oria", "Southern San d'Oria" },
    members = {
      { destination_id = "npc:v1:230:17719393", name = "Endracion", zone = 230 },
      { destination_id = "npc:v1:230:17719394", name = "Ambrotien", zone = 230 },
      { destination_id = "npc:v1:231:17723426", name = "Grilau", zone = 231 },
    },
  },
  ["san d'orian gate guard"] = {
    name = "San d'Orian Gate Guard",
    review_basis = "Exact gate-guard member notes in the pinned BG revision and matching role claim in both pinned guide revisions",
    reviewed_step = "mission:San d'Oria:1:step-001:claim-01",
    allowed_zones = { "Northern San d'Oria", "Southern San d'Oria" },
    members = {
      { destination_id = "npc:v1:230:17719393", name = "Endracion", zone = 230 },
      { destination_id = "npc:v1:230:17719394", name = "Ambrotien", zone = 230 },
      { destination_id = "npc:v1:231:17723426", name = "Grilau", zone = 231 },
    },
  },
}
