-- Generated AccessXI compact progression facts. Do not edit by hand.
-- Full source spans and review evidence remain in data/mission-quest-guides JSON.
return {
  schema_version = 2,
  module_name = "mission_quest_progression_quest_coalition",
  source_authority = { primary = "bg", fallback = "ffxiclopedia" },
  objectives = {
    ["quest:coalition:0"] = {
      native_key = "quest:coalition:0",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "68682d55936eeeb7cfeb55206f15764c1846317103fb59fad2de8a325e08f12f",
      progression_actions = {
      },
    },
    ["quest:coalition:1"] = {
      native_key = "quest:coalition:1",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "f56704f89b2a54cfe4020c00ac7f2133b224c3ef508a6ad0baf24c021e548693",
      progression_actions = {
      },
    },
    ["quest:coalition:10"] = {
      native_key = "quest:coalition:10",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "1c68cb13709add968b891d79d237865ce10afd9f859dc6ff485e2f5599c3e5ad",
      progression_actions = {
      },
    },
    ["quest:coalition:11"] = {
      native_key = "quest:coalition:11",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "18ac1b65f34b0082264e6b7aee9e117d7b24a2af3e00b917294dd78c7c68c1fb",
      progression_actions = {
      },
    },
    ["quest:coalition:12"] = {
      native_key = "quest:coalition:12",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "de1aa8c68bdb7ec5968515c6ad234da6dbda14fb715c41532eb86bac8801efc1",
      progression_actions = {
      },
    },
    ["quest:coalition:13"] = {
      native_key = "quest:coalition:13",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "c3cff39658a825686fd4c1941964e7573a3cf9262b39281603b349a012d7ed12",
      progression_actions = {
      },
    },
    ["quest:coalition:14"] = {
      native_key = "quest:coalition:14",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "8c17a4020b638144d1504fe0efa729a1b225a3144a381e546c8d0489739dd51f",
      progression_actions = {
      },
    },
    ["quest:coalition:15"] = {
      native_key = "quest:coalition:15",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "e00d60ae2873bf9c65bd35f0da6a6c68a6be106759754a7b5025ac81bb4a895c",
      progression_actions = {
      },
    },
    ["quest:coalition:16"] = {
      native_key = "quest:coalition:16",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "949a80c0dba0b22b1785f70513fe342445c1c454e1511b39915196c07cbcf672",
      progression_actions = {
        { step_id = "quest:coalition:16:step-001", step_order = 1, action_id = "quest:coalition:16:step-001:claim-01", action_order = 1, order = 1, action = "obtain", relationship = "obtain-item", target = "Hen", target_key = "hen", target_kind = "item", npcs = {}, objects = {}, enemies = {}, items = { "Hen" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Obtain Hen", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485549 }, source_action_span_ids = { "quest:coalition:16:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:16:step-001", step_order = 1, action_id = "quest:coalition:16:step-001:claim-02", action_order = 2, order = 2, action = "trade", relationship = "trade-to", target = "", target_key = "", target_kind = "npc", npcs = {}, objects = {}, enemies = {}, items = { "them" }, key_items = {}, transports = {}, zones = { "Foret De Hennetiel" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "container from the task delegator and deliver them to the Foret de Hennetiel frontier station administrator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485549 }, source_action_span_ids = { "quest:coalition:16:ffxiclopedia:step-001:span-02" }, catalogue = {} },
        { step_id = "quest:coalition:16:step-001", step_order = 1, action_id = "quest:coalition:16:step-001:claim-03", action_order = 3, order = 3, action = "talk", relationship = "talk-to", target = "task delegator to complete the assignment", target_key = "taskdelegatortocompletetheassignment", target_kind = "npc", npcs = { "task delegator to complete the assignment" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator to complete the assignment", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485549 }, source_action_span_ids = { "quest:coalition:16:ffxiclopedia:step-001:span-03" }, catalogue = {} },
      },
    },
    ["quest:coalition:17"] = {
      native_key = "quest:coalition:17",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "37fe1e5ec04b7db0471d004e7445ed9eefbfcfb9f2c17c746987238c78bcbed7",
      progression_actions = {
        { step_id = "quest:coalition:17:step-001", step_order = 1, action_id = "quest:coalition:17:step-001:claim-01", action_order = 1, order = 1, action = "obtain", relationship = "obtain-item", target = "Mor", target_key = "mor", target_kind = "item", npcs = {}, objects = {}, enemies = {}, items = { "Mor" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Obtain Mor", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485548 }, source_action_span_ids = { "quest:coalition:17:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:17:step-001", step_order = 1, action_id = "quest:coalition:17:step-001:claim-02", action_order = 2, order = 2, action = "trade", relationship = "trade-to", target = "", target_key = "", target_kind = "npc", npcs = {}, objects = {}, enemies = {}, items = { "them" }, key_items = {}, transports = {}, zones = { "Morimar Basalt Fields" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "container from the task delegator and deliver them to the Morimar Basalt Fields frontier station administrator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485548 }, source_action_span_ids = { "quest:coalition:17:ffxiclopedia:step-001:span-02" }, catalogue = {} },
        { step_id = "quest:coalition:17:step-001", step_order = 1, action_id = "quest:coalition:17:step-001:claim-03", action_order = 3, order = 3, action = "talk", relationship = "talk-to", target = "task delegator to complete the assignment", target_key = "taskdelegatortocompletetheassignment", target_kind = "npc", npcs = { "task delegator to complete the assignment" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator to complete the assignment", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485548 }, source_action_span_ids = { "quest:coalition:17:ffxiclopedia:step-001:span-03" }, catalogue = {} },
      },
    },
    ["quest:coalition:18"] = {
      native_key = "quest:coalition:18",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "24e5f404482dd89da838ad38b17a3fc7ef339fffea32709ade3aad082ce4a4e2",
      progression_actions = {
        { step_id = "quest:coalition:18:step-001", step_order = 1, action_id = "quest:coalition:18:step-001:claim-01", action_order = 1, order = 1, action = "obtain", relationship = "obtain-item", target = "key item Yor", target_key = "keyitemyor", target_kind = "item", npcs = {}, objects = {}, enemies = {}, items = { "key item Yor" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Obtain a key item Yor", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493001 }, source_action_span_ids = { "quest:coalition:18:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:18:step-001", step_order = 1, action_id = "quest:coalition:18:step-001:claim-02", action_order = 2, order = 2, action = "trade", relationship = "trade-to", target = "", target_key = "", target_kind = "npc", npcs = {}, objects = {}, enemies = {}, items = { "it" }, key_items = {}, transports = {}, zones = { "Yorcia Weald" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "container from the task delegator and deliver it to the Yorcia Weald frontier station administrator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493001 }, source_action_span_ids = { "quest:coalition:18:ffxiclopedia:step-001:span-02" }, catalogue = {} },
        { step_id = "quest:coalition:18:step-002", step_order = 2, action_id = "quest:coalition:18:step-002:claim-01", action_order = 1, order = 3, action = "talk", relationship = "talk-to", target = "task delegator to complete the assignment", target_key = "taskdelegatortocompletetheassignment", target_kind = "npc", npcs = { "task delegator to complete the assignment" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator to complete the assignment", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493001 }, source_action_span_ids = { "quest:coalition:18:ffxiclopedia:step-002:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:19"] = {
      native_key = "quest:coalition:19",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "80a4b66dbbe031a2cfbffef0f26b21b4c58de2d494eab901e77bc8ec4cdb2ef3",
      progression_actions = {
        { step_id = "quest:coalition:19:step-001", step_order = 1, action_id = "quest:coalition:19:step-001:claim-01", action_order = 1, order = 1, action = "obtain", relationship = "obtain-item", target = "Mar", target_key = "mar", target_kind = "item", npcs = {}, objects = {}, enemies = {}, items = { "Mar" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Obtain Mar", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493002 }, source_action_span_ids = { "quest:coalition:19:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:19:step-001", step_order = 1, action_id = "quest:coalition:19:step-001:claim-02", action_order = 2, order = 2, action = "trade", relationship = "trade-to", target = "", target_key = "", target_kind = "npc", npcs = {}, objects = {}, enemies = {}, items = { "them" }, key_items = {}, transports = {}, zones = { "Marjami Ravine" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "container from the task delegator and deliver them to the Marjami Ravine frontier station administrator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493002 }, source_action_span_ids = { "quest:coalition:19:ffxiclopedia:step-001:span-02" }, catalogue = {} },
        { step_id = "quest:coalition:19:step-001", step_order = 1, action_id = "quest:coalition:19:step-001:claim-03", action_order = 3, order = 3, action = "talk", relationship = "talk-to", target = "task delegator to complete the assignment", target_key = "taskdelegatortocompletetheassignment", target_kind = "npc", npcs = { "task delegator to complete the assignment" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator to complete the assignment", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493002 }, source_action_span_ids = { "quest:coalition:19:ffxiclopedia:step-001:span-03" }, catalogue = {} },
      },
    },
    ["quest:coalition:2"] = {
      native_key = "quest:coalition:2",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "9b60495e1adddd858dfa009dc21e03ea45b7f58075706384cfa97f54dfe6dfbf",
      progression_actions = {
      },
    },
    ["quest:coalition:20"] = {
      native_key = "quest:coalition:20",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "88813794e66f67a0c99440718fce61b2cfe5da78175fd2409ac19eee43e5be7a",
      progression_actions = {
        { step_id = "quest:coalition:20:step-001", step_order = 1, action_id = "quest:coalition:20:step-001:claim-01", action_order = 1, order = 1, action = "obtain", relationship = "obtain-item", target = "KamFS building mat", target_key = "kamfsbuildingmat", target_kind = "item", npcs = {}, objects = {}, enemies = {}, items = { "KamFS building mat" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Obtain KamFS building mat", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485554 }, source_action_span_ids = { "quest:coalition:20:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:20:step-001", step_order = 1, action_id = "quest:coalition:20:step-001:claim-02", action_order = 2, order = 2, action = "trade", relationship = "trade-to", target = "", target_key = "", target_kind = "npc", npcs = {}, objects = {}, enemies = {}, items = { "them" }, key_items = {}, transports = {}, zones = { "Kamihr Drifts" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "container from the task delegator and deliver them to the Kamihr Drifts frontier station administrator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485554 }, source_action_span_ids = { "quest:coalition:20:ffxiclopedia:step-001:span-02" }, catalogue = {} },
        { step_id = "quest:coalition:20:step-001", step_order = 1, action_id = "quest:coalition:20:step-001:claim-03", action_order = 3, order = 3, action = "talk", relationship = "talk-to", target = "task delegator to complete the assignment", target_key = "taskdelegatortocompletetheassignment", target_kind = "npc", npcs = { "task delegator to complete the assignment" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator to complete the assignment", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1485554 }, source_action_span_ids = { "quest:coalition:20:ffxiclopedia:step-001:span-03" }, catalogue = {} },
      },
    },
    ["quest:coalition:21"] = {
      native_key = "quest:coalition:21",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "9bcbfbd4c0b68264da0b3044cac211726fc8ca47cae89a07c4aa35df52960cc4",
      progression_actions = {
      },
    },
    ["quest:coalition:22"] = {
      native_key = "quest:coalition:22",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "7f6bb2fed9aac9d982498d2533f7689e778e1e25df6c674b7852013f1e715646",
      progression_actions = {
      },
    },
    ["quest:coalition:23"] = {
      native_key = "quest:coalition:23",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "da1372b284348160a76672f6590f5f667cf60c3b0e6e72e354046ade30e1b8fa",
      progression_actions = {
      },
    },
    ["quest:coalition:24"] = {
      native_key = "quest:coalition:24",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "8f01195afeb5e24ad54371eac6ebc91895feb314cb41564f2649f00459735e5a",
      progression_actions = {
      },
    },
    ["quest:coalition:25"] = {
      native_key = "quest:coalition:25",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "bbfe17b566f67bf698aaf588c62a2075c6139467dfb15e98d6a3c9675bb5add3",
      progression_actions = {
      },
    },
    ["quest:coalition:26"] = {
      native_key = "quest:coalition:26",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "bc40a5d843f5287009f915c88fe02c5b92bff318917f5393dabd42b5a847e530",
      progression_actions = {
        { step_id = "quest:coalition:26:step-001", step_order = 1, action_id = "quest:coalition:26:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Frontier Bivouac", target_key = "frontierbivouac", target_kind = "npc", npcs = { "Frontier Bivouac" }, objects = {}, enemies = {}, items = { "supplies" }, key_items = {}, transports = {}, zones = { "Ceizak Battlegrounds", "Yahse Hunting Grounds" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver supplies to a Frontier Bivouac (but not the Frontier Station) in Ceizak Battlegrounds or Yahse Hunting Grounds", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1650218 }, source_action_span_ids = { "quest:coalition:26:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:27"] = {
      native_key = "quest:coalition:27",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "1839b9beba14cc074e5ab2a6b47f5eb85787ee4e0eca602ab97dea0ea25281bf",
      progression_actions = {
        { step_id = "quest:coalition:27:step-001", step_order = 1, action_id = "quest:coalition:27:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Frontier Bivouac", target_key = "frontierbivouac", target_kind = "npc", npcs = { "Frontier Bivouac" }, objects = {}, enemies = {}, items = { "supplies" }, key_items = {}, transports = {}, zones = { "Foret De Hennetiel" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver supplies to a Frontier Bivouac in Foret de Hennetiel", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1608321 }, source_action_span_ids = { "quest:coalition:27:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:28"] = {
      native_key = "quest:coalition:28",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "00eb681aaf2936dfa76ce5cf12b7813431dd1ea905728e9be79fdef9a132faa2",
      progression_actions = {
        { step_id = "quest:coalition:28:step-001", step_order = 1, action_id = "quest:coalition:28:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Frontier Bivouac", target_key = "frontierbivouac", target_kind = "npc", npcs = { "Frontier Bivouac" }, objects = {}, enemies = {}, items = { "supplies" }, key_items = {}, transports = {}, zones = { "Morimar Basalt Fields" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver supplies to a Frontier Bivouac in Morimar Basalt Fields", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1719502 }, source_action_span_ids = { "quest:coalition:28:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:29"] = {
      native_key = "quest:coalition:29",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "9b57142dd093d0899120f2c9d88435b3c87d8c8cfc69655da70ba827e0f50edc",
      progression_actions = {
        { step_id = "quest:coalition:29:step-001", step_order = 1, action_id = "quest:coalition:29:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Frontier Bivouac", target_key = "frontierbivouac", target_kind = "npc", npcs = { "Frontier Bivouac" }, objects = {}, enemies = {}, items = { "supplies" }, key_items = {}, transports = {}, zones = { "Yorcia Weald" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver supplies to a Frontier Bivouac in Yorcia Weald", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1609912 }, source_action_span_ids = { "quest:coalition:29:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:3"] = {
      native_key = "quest:coalition:3",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "15b4b7127a362dd5a0e3e64991419d0e496a4c65046c013336c2cf431302ae39",
      progression_actions = {
      },
    },
    ["quest:coalition:30"] = {
      native_key = "quest:coalition:30",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "4a56a4815f3f2c791d92c2fdce6ece00cf0725dfab2361044971c8d73bad04f7",
      progression_actions = {
        { step_id = "quest:coalition:30:step-001", step_order = 1, action_id = "quest:coalition:30:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Frontier Bivouac", target_key = "frontierbivouac", target_kind = "npc", npcs = { "Frontier Bivouac" }, objects = {}, enemies = {}, items = { "supplies" }, key_items = {}, transports = {}, zones = { "Marjami Ravine" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver supplies to a Frontier Bivouac in Marjami Ravine", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1495596 }, source_action_span_ids = { "quest:coalition:30:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:31"] = {
      native_key = "quest:coalition:31",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "0ca2a77d345e908abe16f9b3e80c8c5becec9ff7938eca5faab8ef249986f3af",
      progression_actions = {
        { step_id = "quest:coalition:31:step-001", step_order = 1, action_id = "quest:coalition:31:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Frontier Bivouac", target_key = "frontierbivouac", target_kind = "npc", npcs = { "Frontier Bivouac" }, objects = {}, enemies = {}, items = { "supplies" }, key_items = {}, transports = {}, zones = { "Kamihr Drifts" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver supplies to a Frontier Bivouac in Kamihr Drifts", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1610157 }, source_action_span_ids = { "quest:coalition:31:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:32"] = {
      native_key = "quest:coalition:32",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "b4cf5f7d27c26db1ef6bb203b0f11d9a75a3cad2b0e13e9d2d898f56613f74f5",
      progression_actions = {
        { step_id = "quest:coalition:32:step-001", step_order = 1, action_id = "quest:coalition:32:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "spools of Bloodthread" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 spools of Bloodthread to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1610580 }, source_action_span_ids = { "quest:coalition:32:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:33"] = {
      native_key = "quest:coalition:33",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "796d9e389c1a2fef469b0cd4a9011248292be63d249454c1c556c7061052780b",
      progression_actions = {
        { step_id = "quest:coalition:33:step-001", step_order = 1, action_id = "quest:coalition:33:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Chapuli Wings" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver five Chapuli Wings to the Task Delegator in Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1610303 }, source_action_span_ids = { "quest:coalition:33:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:34"] = {
      native_key = "quest:coalition:34",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "a9a7f557f02e41200938eb588fd648c0a03c3007cc3f7801aa7845bf675a4b1d",
      progression_actions = {
        { step_id = "quest:coalition:34:step-001", step_order = 1, action_id = "quest:coalition:34:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Twitherym Wings" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Deliver five Twitherym Wings to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1492550 }, source_action_span_ids = { "quest:coalition:34:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:35"] = {
      native_key = "quest:coalition:35",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "3e7c929814844e695a433fa8ef9d2b96ed25bcf6fed50b11d82f5aff40cf06e5",
      progression_actions = {
        { step_id = "quest:coalition:35:step-001", step_order = 1, action_id = "quest:coalition:35:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Craklaw Pincers" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Craklaw Pincers to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1626154 }, source_action_span_ids = { "quest:coalition:35:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:36"] = {
      native_key = "quest:coalition:36",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "af858c5553672037d9a43981cf32d4974419a003aa01307da4cd38f2ca21eb3f",
      progression_actions = {
        { step_id = "quest:coalition:36:step-001", step_order = 1, action_id = "quest:coalition:36:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Peiste Stingers" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Peiste Stingers to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1626155 }, source_action_span_ids = { "quest:coalition:36:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:37"] = {
      native_key = "quest:coalition:37",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "452b108c71594dfa56d46e770e86f94842e9a1b99a31a6fdbba46401f867ac09",
      progression_actions = {
        { step_id = "quest:coalition:37:step-001", step_order = 1, action_id = "quest:coalition:37:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Snapweed Tendrils" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Snapweed Tendrils to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1692022 }, source_action_span_ids = { "quest:coalition:37:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:38"] = {
      native_key = "quest:coalition:38",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "f48432867150655c8374109decf51256f0e894798e3fbb8c3afd8d6217a0ca6e",
      progression_actions = {
        { step_id = "quest:coalition:38:step-001", step_order = 1, action_id = "quest:coalition:38:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Tulfaire Feathers" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Tulfaire Feathers to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1691584 }, source_action_span_ids = { "quest:coalition:38:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:39"] = {
      native_key = "quest:coalition:39",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "1e2c855070c9b3a52d9fa688716474cc10b135e417638adfc66f39d17e62dd8b",
      progression_actions = {
        { step_id = "quest:coalition:39:step-001", step_order = 1, action_id = "quest:coalition:39:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Raaz Tusks" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Raaz Tusks to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1694225 }, source_action_span_ids = { "quest:coalition:39:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:4"] = {
      native_key = "quest:coalition:4",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "3640c31b7b4102f6c1ba7fcb76d123fafe2f41bf9e7c20ad80325a02a963f45c",
      progression_actions = {
      },
    },
    ["quest:coalition:40"] = {
      native_key = "quest:coalition:40",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "8b5c45d42411bdd283ba21730fc2f62b6b9d1815d3d2d5d3a157dd41d0b38774",
      progression_actions = {
        { step_id = "quest:coalition:40:step-001", step_order = 1, action_id = "quest:coalition:40:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "vials of Acuex Poison" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 vials of Acuex Poison to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1626706 }, source_action_span_ids = { "quest:coalition:40:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:41"] = {
      native_key = "quest:coalition:41",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "3970b6187f5a4ab032323f9a3ef187b3a3e146d2360c5c5b55907c9039f9c6da",
      progression_actions = {
        { step_id = "quest:coalition:41:step-001", step_order = 1, action_id = "quest:coalition:41:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Matamata Shells" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Matamata Shells to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1626153 }, source_action_span_ids = { "quest:coalition:41:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:42"] = {
      native_key = "quest:coalition:42",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "5d0dca1b3e11e1b1c1cdd5d050edc41673639fc3fdf9030d6d47a7897e39be7d",
      progression_actions = {
        { step_id = "quest:coalition:42:step-001", step_order = 1, action_id = "quest:coalition:42:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "jars of Umbril Ooze" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 jars of Umbril Ooze to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1787359 }, source_action_span_ids = { "quest:coalition:42:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:43"] = {
      native_key = "quest:coalition:43",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "ceac52347e18e938158add78c39717687a59780f6251caed8b362a3fba374e50",
      progression_actions = {
        { step_id = "quest:coalition:43:step-001", step_order = 1, action_id = "quest:coalition:43:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Slug Eyes" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Slug Eyes to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1691412 }, source_action_span_ids = { "quest:coalition:43:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:44"] = {
      native_key = "quest:coalition:44",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "b91682cd0835c66f7054df568cd7437cc7c474f4b80cc36b9a522db1e6167de2",
      progression_actions = {
        { step_id = "quest:coalition:44:step-001", step_order = 1, action_id = "quest:coalition:44:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Snoll Arms" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Snoll Arms to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1694226 }, source_action_span_ids = { "quest:coalition:44:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:45"] = {
      native_key = "quest:coalition:45",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "85855d02c2f23a4b464ff74c55d6078f0dfe99b9ee261192fb19b6e8c3118047",
      progression_actions = {
        { step_id = "quest:coalition:45:step-001", step_order = 1, action_id = "quest:coalition:45:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Dullahan Armor" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Dullahan Armor to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1560212 }, source_action_span_ids = { "quest:coalition:45:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:46"] = {
      native_key = "quest:coalition:46",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "9a91b0bbd7eefe5e299d79d4ae719706585b1acbadf372ffdc1fdb9fb753aed6",
      progression_actions = {
        { step_id = "quest:coalition:46:step-001", step_order = 1, action_id = "quest:coalition:46:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Luminicloth" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade 3 Luminicloth to the Task Delegator in the Inventors' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1499850 }, source_action_span_ids = { "quest:coalition:46:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:48"] = {
      native_key = "quest:coalition:48",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "8d7b95f710c766b28013560ad3e70087ca3d764bf6877a9998a75b7f3b8bd466",
      progression_actions = {
        { step_id = "quest:coalition:48:step-005", step_order = 5, action_id = "quest:coalition:48:step-005:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting one of the Loci, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1677764 }, source_action_span_ids = { "quest:coalition:48:ffxiclopedia:step-005:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:49"] = {
      native_key = "quest:coalition:49",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "dc9c5a6629db9cb3b8459496b1734fac5c9fdeb1cbd122dbef694dd423951214",
      progression_actions = {
        { step_id = "quest:coalition:49:step-001", step_order = 1, action_id = "quest:coalition:49:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Foret De Hennetiel" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Foret de Hennetiel from the correct distance", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1718019 }, source_action_span_ids = { "quest:coalition:49:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:49:step-006", step_order = 6, action_id = "quest:coalition:49:step-006:claim-01", action_order = 1, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After succesfully inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1718019 }, source_action_span_ids = { "quest:coalition:49:ffxiclopedia:step-006:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:5"] = {
      native_key = "quest:coalition:5",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "270c070053bb2c6ab1fcbb12c5405ac0e1a0eb91229735cc55c1b92e7de6d46f",
      progression_actions = {
      },
    },
    ["quest:coalition:50"] = {
      native_key = "quest:coalition:50",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "3a868a967f965c88db0eeefaf6842013bc68c1c857facf1298c853d0e645eae2",
      progression_actions = {
        { step_id = "quest:coalition:50:step-001", step_order = 1, action_id = "quest:coalition:50:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Morimar Basalt Fields" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Morimar Basalt Fields from the correct distance", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1678186 }, source_action_span_ids = { "quest:coalition:50:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:50:step-006", step_order = 6, action_id = "quest:coalition:50:step-006:claim-01", action_order = 1, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1678186 }, source_action_span_ids = { "quest:coalition:50:ffxiclopedia:step-006:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:51"] = {
      native_key = "quest:coalition:51",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "8b0940b5238f009bdef7869b0b8ec84f3fb3bd466bf2ee65b347726998d3de62",
      progression_actions = {
        { step_id = "quest:coalition:51:step-001", step_order = 1, action_id = "quest:coalition:51:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Yorcia Weald" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Yorcia Weald from the correct distance", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1773463 }, source_action_span_ids = { "quest:coalition:51:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:51:step-006", step_order = 6, action_id = "quest:coalition:51:step-006:claim-01", action_order = 1, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1773463 }, source_action_span_ids = { "quest:coalition:51:ffxiclopedia:step-006:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:52"] = {
      native_key = "quest:coalition:52",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "5d5c1e6c44dba87522de77ed6305849df2a4a0ff8ec5c6da831a63b7cae53d30",
      progression_actions = {
        { step_id = "quest:coalition:52:step-001", step_order = 1, action_id = "quest:coalition:52:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Marjami Ravine" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Marjami Ravine from the correct distance", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1773462 }, source_action_span_ids = { "quest:coalition:52:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:52:step-006", step_order = 6, action_id = "quest:coalition:52:step-006:claim-01", action_order = 1, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1773462 }, source_action_span_ids = { "quest:coalition:52:ffxiclopedia:step-006:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:53"] = {
      native_key = "quest:coalition:53",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "1c7ad9ba578b0ee1b6907ea71c0c7ee63f2e547a16a70553e85ab2965bfb59c5",
      progression_actions = {
        { step_id = "quest:coalition:53:step-001", step_order = 1, action_id = "quest:coalition:53:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Kamihr Drifts" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Kamihr Drifts from the correct distance", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1683749 }, source_action_span_ids = { "quest:coalition:53:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:53:step-006", step_order = 6, action_id = "quest:coalition:53:step-006:claim-01", action_order = 1, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1683749 }, source_action_span_ids = { "quest:coalition:53:ffxiclopedia:step-006:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:54"] = {
      native_key = "quest:coalition:54",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "cee813cad753ad56816204a61e6ce92edcf8561fb5078a41c1fd695732edea46",
      progression_actions = {
        { step_id = "quest:coalition:54:step-001", step_order = 1, action_id = "quest:coalition:54:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Sih Gates", "Moh Gates" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Sih Gates or Moh Gates from the correct distance", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1677832 }, source_action_span_ids = { "quest:coalition:54:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:54:step-007", step_order = 7, action_id = "quest:coalition:54:step-007:claim-01", action_order = 1, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1677832 }, source_action_span_ids = { "quest:coalition:54:ffxiclopedia:step-007:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:55"] = {
      native_key = "quest:coalition:55",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "3740dc852c2291a6a8e5633165a0c8418e2ab589fc735674abcae10eb5ff6c43",
      progression_actions = {
        { step_id = "quest:coalition:55:step-001", step_order = 1, action_id = "quest:coalition:55:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Cirdas Caverns" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Cirdas Caverns from the correct distance and angle", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1678394 }, source_action_span_ids = { "quest:coalition:55:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:55:step-007", step_order = 7, action_id = "quest:coalition:55:step-007:claim-01", action_order = 1, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1678394 }, source_action_span_ids = { "quest:coalition:55:ffxiclopedia:step-007:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:56"] = {
      native_key = "quest:coalition:56",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "1e04fb71028a110c20ccacf85380b3f3801cb48980f2376ce666b091bf523b5d",
      progression_actions = {
        { step_id = "quest:coalition:56:step-001", step_order = 1, action_id = "quest:coalition:56:step-001:claim-01", action_order = 1, order = 1, action = "examine", relationship = "examine-object", target = "Ergon Locus", target_key = "ergonlocus", target_kind = "object", npcs = {}, objects = { "Ergon Locus" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = { "Dho Gates", "Woh Gates" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Examine an Ergon Locus in Dho Gates or Woh Gates from the correct distance", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1678883 }, source_action_span_ids = { "quest:coalition:56:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:56:step-005", step_order = 5, action_id = "quest:coalition:56:step-005:claim-01", action_order = 1, order = 2, action = "use", relationship = "use-object", target = "Survey Tables to get the acceptable ranges for the time of day", target_key = "surveytablestogettheacceptablerangesforthetimeofday", target_kind = "object", npcs = {}, objects = { "Survey Tables to get the acceptable ranges for the time of day" }, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Use the Survey Tables to get the acceptable ranges for the time of day", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "ffxiclopedia", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1678883 }, source_action_span_ids = { "quest:coalition:56:ffxiclopedia:step-005:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:56:step-007", step_order = 7, action_id = "quest:coalition:56:step-007:claim-01", action_order = 1, order = 3, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "After inspecting a locus, return to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1678883 }, source_action_span_ids = { "quest:coalition:56:ffxiclopedia:step-007:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:57"] = {
      native_key = "quest:coalition:57",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "ce4054bbd6bd7d38223d1128b311c8527a88593e7d020dc33c1335be6b220985",
      progression_actions = {
        { step_id = "quest:coalition:57:step-001", step_order = 1, action_id = "quest:coalition:57:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Gnatbane" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Gnatbane to the Task Delegator in the Scouts' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493569 }, source_action_span_ids = { "quest:coalition:57:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:57:step-001", step_order = 1, action_id = "quest:coalition:57:step-001:claim-02", action_order = 2, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "talk to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493569 }, source_action_span_ids = { "quest:coalition:57:ffxiclopedia:step-001:span-02" }, catalogue = {} },
      },
    },
    ["quest:coalition:58"] = {
      native_key = "quest:coalition:58",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "730f5b153e95a17d66534a6b7ddf709bbea10d7087a2488cb243427e558289f4",
      progression_actions = {
        { step_id = "quest:coalition:58:step-001", step_order = 1, action_id = "quest:coalition:58:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Marble Nugget" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Marble Nugget to the Task Delegator in the Scouts' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1503419 }, source_action_span_ids = { "quest:coalition:58:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:58:step-001", step_order = 1, action_id = "quest:coalition:58:step-001:claim-02", action_order = 2, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "talk to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1503419 }, source_action_span_ids = { "quest:coalition:58:ffxiclopedia:step-001:span-02" }, catalogue = {} },
      },
    },
    ["quest:coalition:59"] = {
      native_key = "quest:coalition:59",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "45e2315395c22d16d43d4c561ca48bc4cc0662581d96f3dd565a7f6749506623",
      progression_actions = {
        { step_id = "quest:coalition:59:step-001", step_order = 1, action_id = "quest:coalition:59:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Guatambu Log" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Guatambu Log to the Task Delegator in the Scouts' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1538417 }, source_action_span_ids = { "quest:coalition:59:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:59:step-001", step_order = 1, action_id = "quest:coalition:59:step-001:claim-02", action_order = 2, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "talk to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1538417 }, source_action_span_ids = { "quest:coalition:59:ffxiclopedia:step-001:span-02" }, catalogue = {} },
      },
    },
    ["quest:coalition:6"] = {
      native_key = "quest:coalition:6",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "fa161565d13fc071c159fbf32664b7a9433fd51a89b6111014d53a18d5aa6e01",
      progression_actions = {
      },
    },
    ["quest:coalition:60"] = {
      native_key = "quest:coalition:60",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "f9adc467790831d65646f93fc88d467f6ff79ed5a248bb3081fe58cca8e65bb0",
      progression_actions = {
        { step_id = "quest:coalition:60:step-001", step_order = 1, action_id = "quest:coalition:60:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Wootz Ore" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Wootz Ore to the Task Delegator in the Scouts' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493579 }, source_action_span_ids = { "quest:coalition:60:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:60:step-001", step_order = 1, action_id = "quest:coalition:60:step-001:claim-02", action_order = 2, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "talk to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493579 }, source_action_span_ids = { "quest:coalition:60:ffxiclopedia:step-001:span-02" }, catalogue = {} },
      },
    },
    ["quest:coalition:61"] = {
      native_key = "quest:coalition:61",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "c2df0c74a7465ce6a15941f5f5184d7d39476d5bc7dd726fab48c8bd61f7d122",
      progression_actions = {
        { step_id = "quest:coalition:61:step-001", step_order = 1, action_id = "quest:coalition:61:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Gelid aggregate" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Gelid aggregate to the Task Delegator in the Scouts' Coalition to complete this assignment", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1555856 }, source_action_span_ids = { "quest:coalition:61:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:62"] = {
      native_key = "quest:coalition:62",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "80a1501aa6461687ecbe665ac487859f4ddd5fbc9e996dda843f37a4eded390a",
      progression_actions = {
        { step_id = "quest:coalition:62:step-001", step_order = 1, action_id = "quest:coalition:62:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Scholar Stone" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Scholar Stone to the Task Delegator in the Scouts' Coalition", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493574 }, source_action_span_ids = { "quest:coalition:62:ffxiclopedia:step-001:span-01" }, catalogue = {} },
        { step_id = "quest:coalition:62:step-001", step_order = 1, action_id = "quest:coalition:62:step-001:claim-02", action_order = 2, order = 2, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "talk to the Task Delegator", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493574 }, source_action_span_ids = { "quest:coalition:62:ffxiclopedia:step-001:span-02" }, catalogue = {} },
      },
    },
    ["quest:coalition:63"] = {
      native_key = "quest:coalition:63",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "b3ae641de4ed49963fb5d15e458e8b8f897e49bd478e96b48bf16b939044cc43",
      progression_actions = {
        { step_id = "quest:coalition:63:step-001", step_order = 1, action_id = "quest:coalition:63:step-001:claim-01", action_order = 1, order = 1, action = "trade", relationship = "trade-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = { "Vanadium Ore" }, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Trade a Vanadium Ore to the Task Delegator in the Scouts' Coalition to complete this assignment", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "ffxiclopedia", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1556256 }, source_action_span_ids = { "quest:coalition:63:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:64"] = {
      native_key = "quest:coalition:64",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "eb21344d5c10853246b4754a2932dc3821223182f4367219892b047e618888d1",
      progression_actions = {
      },
    },
    ["quest:coalition:65"] = {
      native_key = "quest:coalition:65",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "7b20a42be13b2964c2b4a98b09175b36c370953126fb4e2bc9a1075c0aa1e0af",
      progression_actions = {
      },
    },
    ["quest:coalition:66"] = {
      native_key = "quest:coalition:66",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "b48e0acb772e42dc51589614daad1a4421ad8a613ed6670376283518db728f9b",
      progression_actions = {
      },
    },
    ["quest:coalition:67"] = {
      native_key = "quest:coalition:67",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "cd48ad2a3ba4b68d9568b438afb7bec0574786bf6f24863daea286f715dd9e8f",
      progression_actions = {
      },
    },
    ["quest:coalition:68"] = {
      native_key = "quest:coalition:68",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "a9da23becea6742ff31daf0aa42ebb7222323b7bf343d0267319faa8ba359cba",
      progression_actions = {
      },
    },
    ["quest:coalition:69"] = {
      native_key = "quest:coalition:69",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "a27897ec1f05440e619f061e0285a60279011594ed6ffa39ba143d8d626a9a79",
      progression_actions = {
      },
    },
    ["quest:coalition:7"] = {
      native_key = "quest:coalition:7",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "94fbbda20ad2050e7b31152214c63926ad151f9e06c3454e0c115fee521ab797",
      progression_actions = {
      },
    },
    ["quest:coalition:70"] = {
      native_key = "quest:coalition:70",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "5964c04c0acf681c914d788459b68b52caf04e66492734294a859e1f1d6782c9",
      progression_actions = {
      },
    },
    ["quest:coalition:71"] = {
      native_key = "quest:coalition:71",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "837c5455b767bb8c4d404b2d298131a6344ce98df248aeae297f7ddd6ed15531",
      progression_actions = {
      },
    },
    ["quest:coalition:72"] = {
      native_key = "quest:coalition:72",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "d53b514708fe69fe363c0aecffbfa35a938b2945f29baabd623190fd80f2f76e",
      progression_actions = {
      },
    },
    ["quest:coalition:73"] = {
      native_key = "quest:coalition:73",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "16b4d58dccde0865c7572b138bd8f3b6f4f307628bae7de3209cd536434f0705",
      progression_actions = {
        { step_id = "quest:coalition:73:step-001", step_order = 1, action_id = "quest:coalition:73:step-001:claim-01", action_order = 1, order = 1, action = "fight", relationship = "defeat-enemy", target = "", target_key = "", target_kind = "enemy", npcs = {}, objects = {}, enemies = { "Spoutdrenched Toad", "Rustwater Toad" }, items = {}, key_items = {}, transports = {}, zones = { "Rala Waterways" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Defeat a total of five Spoutdrenched Toads and/or Rustwater Toads in Rala Waterways", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "ffxiclopedia", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1751852 }, source_action_span_ids = { "quest:coalition:73:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:74"] = {
      native_key = "quest:coalition:74",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "b09b9bf2ffd4479cffa5208b8ee9c574815aefeb396f72e238fc1bf9e8d16b03",
      progression_actions = {
        { step_id = "quest:coalition:74:step-001", step_order = 1, action_id = "quest:coalition:74:step-001:claim-01", action_order = 1, order = 1, action = "fight", relationship = "defeat-enemy", target = "Malodorous Twitherym", target_key = "malodoroustwitherym", target_kind = "enemy", npcs = {}, objects = {}, enemies = { "Malodorous Twitherym" }, items = {}, key_items = {}, transports = {}, zones = { "Sih Gates" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Defeat a total of five Malodorous Twitherym in Sih Gates", required_count = 5, count_mode = "credited-defeat", count_explicit = true, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "ffxiclopedia", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "catalogue" }, source_revisions = { ffxiclopedia = 1751853 }, source_action_span_ids = { "quest:coalition:74:ffxiclopedia:step-001:span-01" }, catalogue = { { destination_id = "camp:v1:268:malodorous-twitherym:2f9b03bc91d02d7a9423", zone_id = 268, zone_name = "Sih Gates", target_name = "Malodorous Twitherym", target_kind = "enemy", target_key = "malodoroustwitherym", target_point = { -0.224, -357.27999999999997, -0.499 }, raw_identity = "lsb:mob_spawn_points:group:8:mobname:Malodorous_Twitherym", raw_spawn_ids = { 17874989, 17874990, 17874993, 17874994 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:74:step-001:claim-01:zone:268", arrival_instruction = "Defeat Malodorous Twitherym in Sih Gates." }, { destination_id = "camp:v1:268:malodorous-twitherym:5fb93436cb43cd994d0a", zone_id = 268, zone_name = "Sih Gates", target_name = "Malodorous Twitherym", target_kind = "enemy", target_key = "malodoroustwitherym", target_point = { -218.90000000000001, -362.55000000000001, -19.23 }, raw_identity = "lsb:mob_spawn_points:group:8:mobname:Malodorous_Twitherym", raw_spawn_ids = { 17875000, 17875001, 17875048, 17875049 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:74:step-001:claim-01:zone:268", arrival_instruction = "Defeat Malodorous Twitherym in Sih Gates." }, { destination_id = "camp:v1:268:malodorous-twitherym:a2f74d8a1f0e30fb5459", zone_id = 268, zone_name = "Sih Gates", target_name = "Malodorous Twitherym", target_kind = "enemy", target_key = "malodoroustwitherym", target_point = { -117.8, -243.19999999999999, -10.49 }, raw_identity = "lsb:mob_spawn_points:group:8:mobname:Malodorous_Twitherym", raw_spawn_ids = { 17874972, 17874973, 17874974, 17874978, 17874979 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:74:step-001:claim-01:zone:268", arrival_instruction = "Defeat Malodorous Twitherym in Sih Gates." } } },
      },
    },
    ["quest:coalition:75"] = {
      native_key = "quest:coalition:75",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "5f316d6f7b9388308d7e1e7f98ba3062de8ab0ff243b097168fa39270b6e0d0e",
      progression_actions = {
        { step_id = "quest:coalition:75:step-001", step_order = 1, action_id = "quest:coalition:75:step-001:claim-01", action_order = 1, order = 1, action = "fight", relationship = "defeat-enemy", target = "Ruby Raptor", target_key = "rubyraptor", target_kind = "enemy", npcs = {}, objects = {}, enemies = { "Ruby Raptor" }, items = {}, key_items = {}, transports = {}, zones = { "Moh Gates" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Defeat a total of five Ruby Raptors in Moh Gates", required_count = 5, count_mode = "credited-defeat", count_explicit = true, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "ffxiclopedia", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "catalogue" }, source_revisions = { ffxiclopedia = 1671685 }, source_action_span_ids = { "quest:coalition:75:ffxiclopedia:step-001:span-01" }, catalogue = { { destination_id = "camp:v1:269:ruby-raptor:78805552b10c1fa6ca4a", zone_id = 269, zone_name = "Moh Gates", target_name = "Ruby Raptor", target_kind = "enemy", target_key = "rubyraptor", target_point = { 246.25, -62.978999999999999, 20.719000000000001 }, raw_identity = "lsb:mob_spawn_points:group:18:mobname:Ruby_Raptor", raw_spawn_ids = { 17879168, 17879169, 17879171, 17879172 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:75:step-001:claim-01:zone:269", arrival_instruction = "Defeat Ruby Raptor in Moh Gates." }, { destination_id = "camp:v1:269:ruby-raptor:5b0028fe258e3e61a62e", zone_id = 269, zone_name = "Moh Gates", target_name = "Ruby Raptor", target_kind = "enemy", target_key = "rubyraptor", target_point = { 53.067999999999998, -84.415999999999997, 29.940000000000001 }, raw_identity = "lsb:mob_spawn_points:group:42:mobname:Ruby_Raptor", raw_spawn_ids = { 17879112, 17879113, 17879114, 17879115 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:75:step-001:claim-01:zone:269", arrival_instruction = "Defeat Ruby Raptor in Moh Gates." }, { destination_id = "camp:v1:269:ruby-raptor:2816894ba68ff7cebbf5", zone_id = 269, zone_name = "Moh Gates", target_name = "Ruby Raptor", target_kind = "enemy", target_key = "rubyraptor", target_point = { 221.46000000000001, 5.1280000000000001, 19.364000000000001 }, raw_identity = "lsb:mob_spawn_points:group:42:mobname:Ruby_Raptor", raw_spawn_ids = { 17879155, 17879156 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:75:step-001:claim-01:zone:269", arrival_instruction = "Defeat Ruby Raptor in Moh Gates." } } },
      },
    },
    ["quest:coalition:76"] = {
      native_key = "quest:coalition:76",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "c3d695d86f02579b5c33d8e1b53f28fe69832228fce487de0783d082f5b975b9",
      progression_actions = {
        { step_id = "quest:coalition:76:step-001", step_order = 1, action_id = "quest:coalition:76:step-001:claim-01", action_order = 1, order = 1, action = "fight", relationship = "defeat-enemy", target = "Asperous Marolith", target_key = "asperousmarolith", target_kind = "enemy", npcs = {}, objects = {}, enemies = { "Asperous Marolith" }, items = {}, key_items = {}, transports = {}, zones = { "Cirdas Caverns" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Defeat a total of three Asperous Maroliths in Cirdas Caverns", required_count = 3, count_mode = "credited-defeat", count_explicit = true, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "ffxiclopedia", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "catalogue" }, source_revisions = { ffxiclopedia = 1752570 }, source_action_span_ids = { "quest:coalition:76:ffxiclopedia:step-001:span-01" }, catalogue = { { destination_id = "camp:v1:270:asperous-marolith:c24687fc8d34ccce7ec5", zone_id = 270, zone_name = "Cirdas Caverns", target_name = "Asperous Marolith", target_kind = "enemy", target_key = "asperousmarolith", target_point = { -80.870000000000005, 395.322, 29.238 }, raw_identity = "lsb:mob_spawn_points:group:13:mobname:Asperous_Marolith", raw_spawn_ids = { 17883279, 17883280 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:76:step-001:claim-01:zone:270", arrival_instruction = "Defeat Asperous Marolith in Cirdas Caverns." }, { destination_id = "camp:v1:270:asperous-marolith:9a77879dae53332956d2", zone_id = 270, zone_name = "Cirdas Caverns", target_name = "Asperous Marolith", target_kind = "enemy", target_key = "asperousmarolith", target_point = { -43.308999999999997, -90.024000000000001, 29.498999999999999 }, raw_identity = "lsb:mob_spawn_points:group:13:mobname:Asperous_Marolith", raw_spawn_ids = { 17883220, 17883221 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:76:step-001:claim-01:zone:270", arrival_instruction = "Defeat Asperous Marolith in Cirdas Caverns." }, { destination_id = "camp:v1:270:asperous-marolith:c12f8c08934cdcd4107a", zone_id = 270, zone_name = "Cirdas Caverns", target_name = "Asperous Marolith", target_kind = "enemy", target_key = "asperousmarolith", target_point = { 319.31, 365.29500000000002, 29.428999999999998 }, raw_identity = "lsb:mob_spawn_points:group:13:mobname:Asperous_Marolith", raw_spawn_ids = { 17883328, 17883329 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:76:step-001:claim-01:zone:270", arrival_instruction = "Defeat Asperous Marolith in Cirdas Caverns." }, { destination_id = "camp:v1:270:asperous-marolith:34d3996f2658e6ee7fd9", zone_id = 270, zone_name = "Cirdas Caverns", target_name = "Asperous Marolith", target_kind = "enemy", target_key = "asperousmarolith", target_point = { 302.07999999999998, -132.97999999999999, 29.492000000000001 }, raw_identity = "lsb:mob_spawn_points:group:13:mobname:Asperous_Marolith", raw_spawn_ids = { 17883342, 17883343 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:76:step-001:claim-01:zone:270", arrival_instruction = "Defeat Asperous Marolith in Cirdas Caverns." } } },
      },
    },
    ["quest:coalition:77"] = {
      native_key = "quest:coalition:77",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "dbb4946af81ee6517b53d1ee7e7fe29024d3a090769157982c227c3603b449c2",
      progression_actions = {
        { step_id = "quest:coalition:77:step-001", step_order = 1, action_id = "quest:coalition:77:step-001:claim-01", action_order = 1, order = 1, action = "fight", relationship = "defeat-enemy", target = "Unyielding Tarichuk", target_key = "unyieldingtarichuk", target_kind = "enemy", npcs = {}, objects = {}, enemies = { "Unyielding Tarichuk" }, items = {}, key_items = {}, transports = {}, zones = { "Dho Gates" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Defeat a total of three Unyielding Tarichuks in Dho Gates", required_count = 3, count_mode = "credited-defeat", count_explicit = true, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "ffxiclopedia", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "catalogue" }, source_revisions = { ffxiclopedia = 1752504 }, source_action_span_ids = { "quest:coalition:77:ffxiclopedia:step-001:span-01" }, catalogue = { { destination_id = "camp:v1:272:unyielding-tarichuk:6739a111b434d48c06ad", zone_id = 272, zone_name = "Dho Gates", target_name = "Unyielding Tarichuk", target_kind = "enemy", target_key = "unyieldingtarichuk", target_point = { -159.69999999999999, 202.119, -20.120000000000001 }, raw_identity = "lsb:mob_spawn_points:group:16:mobname:Unyielding_Tarichuk", raw_spawn_ids = { 17891365, 17891366 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:77:step-001:claim-01:zone:272", arrival_instruction = "Defeat Unyielding Tarichuk in Dho Gates." }, { destination_id = "camp:v1:272:unyielding-tarichuk:984a96b26c422d4335d0", zone_id = 272, zone_name = "Dho Gates", target_name = "Unyielding Tarichuk", target_kind = "enemy", target_key = "unyieldingtarichuk", target_point = { -457, 77.558999999999997, -39.630000000000003 }, raw_identity = "lsb:mob_spawn_points:group:16:mobname:Unyielding_Tarichuk", raw_spawn_ids = { 17891415, 17891416 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:77:step-001:claim-01:zone:272", arrival_instruction = "Defeat Unyielding Tarichuk in Dho Gates." }, { destination_id = "camp:v1:272:unyielding-tarichuk:427f0f23ec4ceeacb1ed", zone_id = 272, zone_name = "Dho Gates", target_name = "Unyielding Tarichuk", target_kind = "enemy", target_key = "unyieldingtarichuk", target_point = { -360.19999999999999, 182.09999999999999, -29.440000000000001 }, raw_identity = "lsb:mob_spawn_points:group:16:mobname:Unyielding_Tarichuk", raw_spawn_ids = { 17891393, 17891394 }, cluster_policy_version = "complete-link-v1-h120-y24", transport_id = "", battlefield_id = "", metadata_class = "", group_id = "quest:coalition:77:step-001:claim-01:zone:272", arrival_instruction = "Defeat Unyielding Tarichuk in Dho Gates." } } },
      },
    },
    ["quest:coalition:78"] = {
      native_key = "quest:coalition:78",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "0a0cea342fb58f4c742d309905f7f15b1d4a3f22a4edbc7031481502f4848c23",
      progression_actions = {
        { step_id = "quest:coalition:78:step-001", step_order = 1, action_id = "quest:coalition:78:step-001:claim-01", action_order = 1, order = 1, action = "fight", relationship = "defeat-enemy", target = "", target_key = "", target_kind = "enemy", npcs = {}, objects = {}, enemies = { "Acuex", "Wheezing Acuex" }, items = {}, key_items = {}, transports = {}, zones = { "Woh Gates" }, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Defeat a total of three Acuex (Wheezing Acuex) in Woh Gates", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "ffxiclopedia", transports = "", zones = "ffxiclopedia", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1786705 }, source_action_span_ids = { "quest:coalition:78:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:79"] = {
      native_key = "quest:coalition:79",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "e43aa3c2854e372b4fc3dd962312ccfb67c557a2dbedee213320facf4daff52a",
      progression_actions = {
        { step_id = "quest:coalition:79:step-001", step_order = 1, action_id = "quest:coalition:79:step-001:claim-01", action_order = 1, order = 1, action = "fight", relationship = "defeat-enemy", target = "Ironclad", target_key = "ironclad", target_kind = "enemy", npcs = {}, objects = {}, enemies = { "Ironclad" }, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Defeat a total of three Ironclad in Outer Ra'Kaznar", required_count = 3, count_mode = "credited-defeat", count_explicit = true, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "ffxiclopedia", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493528 }, source_action_span_ids = { "quest:coalition:79:ffxiclopedia:step-001:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:8"] = {
      native_key = "quest:coalition:8",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "577b031fc192ff2a2b380c419feaaafce5c4e1e1da51cc817698aba0b358c895",
      progression_actions = {
      },
    },
    ["quest:coalition:80"] = {
      native_key = "quest:coalition:80",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "ac899bf3f2e05538b5a1b611b443ec81952e0cb345d87240c30cfd78485511c2",
      progression_actions = {
      },
    },
    ["quest:coalition:81"] = {
      native_key = "quest:coalition:81",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "e8ac17ba57afbddde0db59e18b3ee7a775c2107a629805e781242697a4330615",
      progression_actions = {
      },
    },
    ["quest:coalition:82"] = {
      native_key = "quest:coalition:82",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "01351c27c63bbc5e6016be1abdb1910384bb8485dee1d7df0a9816c04b93400b",
      progression_actions = {
      },
    },
    ["quest:coalition:83"] = {
      native_key = "quest:coalition:83",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "73d2e044379aa480c0d325cae343e0c344a459e4e7ed2589064e253b4d06521d",
      progression_actions = {
      },
    },
    ["quest:coalition:84"] = {
      native_key = "quest:coalition:84",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "07dbd41ae94e7ab3c0d72bd3b37ee644eb51c86193aef58863e62fde15bb7e1b",
      progression_actions = {
      },
    },
    ["quest:coalition:85"] = {
      native_key = "quest:coalition:85",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "2f5e2105df4af5d9811295eb82353ca7186789238bce3a585c1f0c5299167171",
      progression_actions = {
      },
    },
    ["quest:coalition:86"] = {
      native_key = "quest:coalition:86",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "ad41d75b19384ed6b9e3dd0229e46fa1c1c381513646d182b22a5a2b3032443a",
      progression_actions = {
        { step_id = "quest:coalition:86:step-002", step_order = 2, action_id = "quest:coalition:86:step-002:claim-01", action_order = 1, order = 1, action = "travel", relationship = "travel-to", target = "", target_key = "", target_kind = "", npcs = {}, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = { "L-8" }, result_items = {}, result_relation = "", instruction = "Head to (L-8) to begin finding slugs", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "", target_kind = "", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "ffxiclopedia", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1717886 }, source_action_span_ids = { "quest:coalition:86:ffxiclopedia:step-002:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:87"] = {
      native_key = "quest:coalition:87",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "f56b62368f01e53ba4e01b3890e36f75469ce73de44295fc07e7d787bf4436f2",
      progression_actions = {
        { step_id = "quest:coalition:87:step-003", step_order = 3, action_id = "quest:coalition:87:step-003:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "task delegator when your task is complete", target_key = "taskdelegatorwhenyourtaskiscomplete", target_kind = "npc", npcs = { "task delegator when your task is complete" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator when your task is complete", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1492554 }, source_action_span_ids = { "quest:coalition:87:ffxiclopedia:step-003:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:88"] = {
      native_key = "quest:coalition:88",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "1d884f6d3ae8e7ca3ebbdd6b01efbbc0afa8dcf9309c22805dbacc9142a43295",
      progression_actions = {
        { step_id = "quest:coalition:88:step-005", step_order = 5, action_id = "quest:coalition:88:step-005:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "task delegator when your task is complete", target_key = "taskdelegatorwhenyourtaskiscomplete", target_kind = "npc", npcs = { "task delegator when your task is complete" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator when your task is complete", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1739022 }, source_action_span_ids = { "quest:coalition:88:ffxiclopedia:step-005:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:89"] = {
      native_key = "quest:coalition:89",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "6daaef9f5d8d0f1135de557cc33022def05f9794a62d6443cebca6fcbce3a8b6",
      progression_actions = {
        { step_id = "quest:coalition:89:step-004", step_order = 4, action_id = "quest:coalition:89:step-004:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "task delegator when your task is complete", target_key = "taskdelegatorwhenyourtaskiscomplete", target_kind = "npc", npcs = { "task delegator when your task is complete" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator when your task is complete", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1739023 }, source_action_span_ids = { "quest:coalition:89:ffxiclopedia:step-004:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:9"] = {
      native_key = "quest:coalition:9",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "59fc4ae921b9ce296d5e8090dc0a505192d2ac1914be7c702d1024e8b3b835a9",
      progression_actions = {
      },
    },
    ["quest:coalition:90"] = {
      native_key = "quest:coalition:90",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "1f29cbc112b76e0d03f61b6f5d24e086090e7cde3ff6d22be649bd2c2c103633",
      progression_actions = {
        { step_id = "quest:coalition:90:step-004", step_order = 4, action_id = "quest:coalition:90:step-004:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "task delegator when your task is complete", target_key = "taskdelegatorwhenyourtaskiscomplete", target_kind = "npc", npcs = { "task delegator when your task is complete" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator when your task is complete", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1493542 }, source_action_span_ids = { "quest:coalition:90:ffxiclopedia:step-004:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:91"] = {
      native_key = "quest:coalition:91",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "e70d90e6b65ae4b54410a435db677d98b710321b6bf5bc0951695feb028f22cd",
      progression_actions = {
        { step_id = "quest:coalition:91:step-004", step_order = 4, action_id = "quest:coalition:91:step-004:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "task delegator when your task is complete", target_key = "taskdelegatorwhenyourtaskiscomplete", target_kind = "npc", npcs = { "task delegator when your task is complete" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator when your task is complete", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1495842 }, source_action_span_ids = { "quest:coalition:91:ffxiclopedia:step-004:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:92"] = {
      native_key = "quest:coalition:92",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "83fb5c024cfdde523696c8e4a61bc01ed968510c448a016352766453d9decbb0",
      progression_actions = {
        { step_id = "quest:coalition:92:step-003", step_order = 3, action_id = "quest:coalition:92:step-003:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "task delegator when your task is complete", target_key = "taskdelegatorwhenyourtaskiscomplete", target_kind = "npc", npcs = { "task delegator when your task is complete" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the task delegator when your task is complete", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1542065 }, source_action_span_ids = { "quest:coalition:92:ffxiclopedia:step-003:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:93"] = {
      native_key = "quest:coalition:93",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "a75691dc5be8c84b0f34599d7c841abade0a26285a4fca009fd965ea13ad6882",
      progression_actions = {
        { step_id = "quest:coalition:93:step-008", step_order = 8, action_id = "quest:coalition:93:step-008:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the Task Delegator for your reward", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1763246 }, source_action_span_ids = { "quest:coalition:93:ffxiclopedia:step-008:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:94"] = {
      native_key = "quest:coalition:94",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "d4bede8389d6bd981e5200eea92aa46efb1d0b286e34657b16b5a966417152f2",
      progression_actions = {
        { step_id = "quest:coalition:94:step-008", step_order = 8, action_id = "quest:coalition:94:step-008:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the Task Delegator for your reward", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1786424 }, source_action_span_ids = { "quest:coalition:94:ffxiclopedia:step-008:span-01" }, catalogue = {} },
      },
    },
    ["quest:coalition:95"] = {
      native_key = "quest:coalition:95",
      progression_schema_version = 2,
      progression_module = "mission_quest_progression_quest_coalition",
      source_authority = { primary = "bg", fallback = "ffxiclopedia" },
      progression_revision = "f8786d8c90634e6f0420d240f255aaa10cec2d36e9e40e9c9ee08a10f2c46e31",
      progression_actions = {
        { step_id = "quest:coalition:95:step-008", step_order = 8, action_id = "quest:coalition:95:step-008:claim-01", action_order = 1, order = 1, action = "talk", relationship = "talk-to", target = "Task Delegator", target_key = "taskdelegator", target_kind = "npc", npcs = { "Task Delegator" }, objects = {}, enemies = {}, items = {}, key_items = {}, transports = {}, zones = {}, destination_zone_name = "", destination_zone_id = 0, grid_coordinates = {}, result_items = {}, result_relation = "", instruction = "Return to the Task Delegator for your reward", required_count = 1, count_mode = "single", count_explicit = false, material = true, source_authority = "ffxiclopedia", field_sources = { action = "ffxiclopedia", relationship = "ffxiclopedia", target = "ffxiclopedia", target_kind = "ffxiclopedia", items = "", key_items = "", result_items = "", result_relation = "", instruction = "ffxiclopedia", npcs = "ffxiclopedia", objects = "", enemies = "", transports = "", zones = "", destination_zone_name = "", grid_coordinates = "", required_count = "ffxiclopedia", count_mode = "ffxiclopedia", count_explicit = "ffxiclopedia", target_key = "ffxiclopedia", destination_zone_id = "", catalogue = "" }, source_revisions = { ffxiclopedia = 1786425 }, source_action_span_ids = { "quest:coalition:95:ffxiclopedia:step-008:span-01" }, catalogue = {} },
      },
    },
  },
}
