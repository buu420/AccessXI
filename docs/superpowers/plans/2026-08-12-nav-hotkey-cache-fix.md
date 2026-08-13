# Navigation Hotkey Cache Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Missions, Quests, and objective route-start hotkeys responsive on heavily progressed characters without weakening live character, packet, inventory, key-item, session, or progression freshness checks.

**Architecture:** Build a revisioned lookup over the static navigation catalog once, then derive and cache immutable guide source steps and source-route rows by native objective key. Cache final mission and quest rows by a stable signature containing character/world/session ownership, authoritative packet keys, inventory and key-item keys, objective-progress revision, and navigation-catalog revision; exclude volatile observation ticks.

**Tech Stack:** Lua 5.1, Ashita addon callbacks, PowerShell test runners, Git.

## Global Constraints

- Preserve current character identity, world, session epoch, 0x056 mission/quest packet, 0x055 key-item, inventory, and objective-progress gates.
- A stale cache must never authorize or retain an objective after any stable input changes.
- Repeated category movement and route start with unchanged state must perform zero additional full-catalog scans and zero additional guide source-step expansion.
- Cache invalidation must follow stable state keys and revisions, never `last_native_inventory_item_tick`.
- Do not alter collision routing, beacon behavior, or mission/quest objective selection semantics.

---

### Task 1: Reproduce the hotkey regression structurally

**Files:**
- Modify: `tools/lua_tests/test_mission_quest_navigation.lua`
- Modify if required: `tools/test_mission_quest_navigation.ps1`

**Interfaces:**
- Consumes: `accessxi.nav_mission_quest_active_items(category_key)` and the existing production mission/quest fixture.
- Produces: operation-count assertions for repeated unchanged builds and stable-key invalidation.

- [ ] **Step 1: Write the failing test**

Add counters to the objective-guide source-step and destination providers. Build Missions and Quests twice with unchanged state and assert the second call adds no provider calls. Change only `last_native_inventory_item_tick` and assert it remains a cache hit. Change `inventory_packet_key`, packet key, objective-progress revision, identity/session, and navigation-catalog revision one at a time and assert the affected category rebuilds.

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_mission_quest_navigation.ps1`

Expected: FAIL because repeated unchanged calls currently invoke guide expansion again and volatile item ticks alter the signature.

- [ ] **Step 3: Preserve the RED evidence**

Record the exact failing assertion and command in the task report before any production edit.

---

### Task 2: Add revisioned source and active-row caches

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Test: `tools/lua_tests/test_mission_quest_navigation.lua`

**Interfaces:**
- Consumes: `accessxi.nav_points`, stable mission/quest packet fields, `inventory_packet_key`, `key_items_packet_key`, character/world/session providers.
- Produces: `accessxi.nav_catalog_revision`, a module-private catalog lookup, immutable source-step/source-route caches, and final active-row caches keyed by `active_state_signature`.

- [ ] **Step 1: Add catalog revision ownership**

Increment `accessxi.nav_catalog_revision` whenever the catalog is freshly loaded or a user/recorded point is appended. Include that revision in objective active-state signatures.

- [ ] **Step 2: Index the catalog once**

Build module-private maps for normalized zone name to zone IDs, zone plus normalized entity name to points, exact referenced targets, and per-zone zone-line entries. Rebuild only when `nav_catalog_revision` changes.

- [ ] **Step 3: Reuse immutable guide derivations**

Cache sorted `objective_source_steps(native_key)` and derived `source_route_rows(native_key)` by native key plus catalog revision. Return defensive copies only at mutable API boundaries; internal selectors consume immutable cached rows directly.

- [ ] **Step 4: Cache final active rows**

After refreshing inventory, compute the stable state signature. On an exact signature hit, return the cached mission or quest rows without context expansion. On a miss, rebuild, stamp, cache, and return the result. Clear cache ownership on character/session changes and include objective-progress revision in the signature.

- [ ] **Step 5: Keep logging bounded**

Retain context failure and one completion summary; remove or gate per-context begin/done trace writes from normal category rebuilds.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_mission_quest_navigation.ps1`

Expected: PASS, including unchanged-state cache-hit and every stable invalidation assertion.

---

### Task 3: Verify, deploy, and publish the patch

**Files:**
- Verify all modified production and test files.
- Deploy through the repository's existing addon/release scripts only.

**Interfaces:**
- Consumes: completed Task 2 implementation.
- Produces: tested live addon files and a patch release artifact.

- [ ] **Step 1: Run focused integration suites**

Run the mission/quest navigation, reader runtime integration, navigation hotkey integration, collision reader integration, and Lua 5.1 syntax checks.

- [ ] **Step 2: Run repository hygiene checks**

Run `git diff --check` and review the complete scoped diff.

- [ ] **Step 3: Build/package with existing release tooling**

Build the installer package and ensure PlayOnline progress payload and collision-native payload remain present and hash-validated.

- [ ] **Step 4: Deploy after preserving backups**

Deploy the addon and PlayOnline payload through the existing scripts with POL/FFXI closed; verify deployed hashes against the package.

- [ ] **Step 5: Publish patch release**

Commit, push, merge, tag the next patch release, upload the verified ZIP/installer/setup guide, and report exact hashes.
