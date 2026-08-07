# Mission and Quest Navigation Implementation Plan

> Execute in `C:\Users\buu42\.codex\worktrees\AccessXI\mission-quest-nav` on branch `agent/mission-quest-nav`.

## Task 1: Lock behavior with failing tests

**Files:**

- Create `tools/test_mission_quest_navigation.ps1`

1. Build a Lua 5.1 harness with dynamic mission/quest/DAT/key-item fixtures.
2. Assert that `navigation_data.lua` contains dedicated `Missions` and `Quests` categories.
3. Assert native quest bit enumeration, nonstatic counts, area ordering, and the Aht Urhgan 0-127 boundary.
4. Assert national/expansion mission resolution and no-current sentinels.
5. Assert character switching clears prior mission/quest state.
6. Assert Geological Survey resolves Cid, I-8 geyser, then Cid for no tester, Blue, and Red stages.
7. Assert missing key-item state, contradictory state, missing Cid, and unsupported objectives block route creation.
8. Run the test and confirm it fails because the new modules/categories do not exist.

## Task 2: Add native state and objective modules

**Files:**

- Create `ashita/addons/accessxi_reader/modules/mission_quest_objectives.lua`
- Create `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Modify `ashita/addons/accessxi_reader/modules/navigation_data.lua`

1. Add the two categories without adding them to the `All` point-kind path.
2. Add the declarative Geological Survey objective rule and authoritative evidence comments.
3. Implement character-scoped state reset and packet ownership checks.
4. Implement active mission and quest enumeration from existing packet/DAT helpers.
5. Implement objective resolution, speech, route preparation, start suffix, and arrival suffix helpers.
6. Run the focused test until it passes.

## Task 3: Integrate with the live addon

**Files:**

- Modify `ashita/addons/accessxi_reader/accessxi_reader.lua`

1. Add packet-state owner fields and tag cache restore/capture with the current character.
2. Call the character guard before mission and quest packet updates.
3. Load the new modules near navigation initialization.
4. Special-case dynamic category collection and row speech.
5. Prepare/block objective routes before the ordinary menu route path; use existing zone search for cross-zone targets.
6. Preserve objective metadata in `nav_copy_point`.
7. Add a bounded destination arrival-radius override.
8. Append objective instructions on route start and arrival and use objective context in cross-zone speech.
9. Run focused tests and Lua 5.1 syntax checks.

## Task 4: Regression and route verification

1. Run existing navigation category/hotkey, zone-search, same-zone re-entry, zoning, Dangruf fount, and route-safety tests.
2. Probe the Dangruf I-8 target with `navprobe`; require a multi-waypoint route from the South Gustaberg entrance and reject a fabricated direct fallback.
3. Inspect the diff for character names, guessed stage fallbacks, static row counts, and unrelated changes.

## Task 5: Deploy for live testing

1. Copy only changed addon files into `C:\Users\buu42\Ashita\addons\accessxi_reader`.
2. Run syntax validation against the deployed addon and byte-compare deployed modules with the worktree.
3. Report what is live, what is verified offline, and what still requires in-game route testing.
