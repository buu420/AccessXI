# Mission Inventory Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Advance active mission guidance when exact required items appear in carried Inventory, cancel only a superseded mission route, and never auto-start the next route.

**Architecture:** `accessxi_reader.lua` publishes an identity-bound native Inventory snapshot and refreshes it only when Missions is read or an item-related packet wakes a deferred scan. `mission_quest_navigation.lua` uses that snapshot to select the next structurally ordered guide step and to invalidate only a stale mission-owned route.

**Tech Stack:** Lua 5.1, Ashita v4 memory and event APIs, existing AccessXI mission guide modules and Lua test harnesses.

## Global Constraints

- Container `0` native memory is authoritative; chat text and packet payload item fields are not.
- The behavior is shared across structurally compatible missions and is not keyed to `Smash the Orcish Scouts` or item ID `16656` in production.
- An inventory change can cancel an obsolete mission route but cannot call any route-start function.
- No continuous polling loop is added.
- Character, World, and objective-session ownership remain mandatory.
- Existing uncommitted Task4.5 and navigation changes must be preserved.

---

### Task 1: Native carried-inventory snapshot

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Test: `tools/lua_tests/test_mission_quest_reader_runtime_integration.lua`

**Interfaces:**
- Produces: `accessxi.refresh_objective_inventory_state(reason) -> changed, available`
- Produces: `accessxi.objective_inventory_count(item_id) -> integer`
- Produces: `accessxi.objective_inventory_count_by_name(name) -> integer, item_id_or_nil`
- Produces: `accessxi.poll_objective_inventory_refresh(now) -> boolean`
- Publishes: `objective_inventory_counts`, `inventory_packet_source`, `inventory_packet_player`, `inventory_packet_identity`, `inventory_packet_session_epoch`, and `inventory_packet_key`

- [ ] **Step 1: Write the failing reader integration tests**

Add fixtures that expose an Ashita Inventory container with slots and assert:

```lua
local changed, available = accessxi.refresh_objective_inventory_state('test')
assert(changed == true and available == true)
assert(accessxi.objective_inventory_count(16656) == 1)
assert(select(1, accessxi.objective_inventory_count_by_name('Orcish Axe')) == 1)
```

Also assert failed scans do not replace the last complete snapshot, remote-container items do not count, and repeated identical scans return `changed == false`.

- [ ] **Step 2: Run the reader integration wrapper and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_mission_quest_reader_runtime_integration.ps1`

Expected: FAIL because the objective Inventory functions do not exist.

- [ ] **Step 3: Implement the native snapshot**

Implement the four interfaces as `accessxi` fields to avoid increasing the reader chunk's top-level local count. Scan slots `1..GetContainerCountMax(0)`, require valid positive item IDs/counts, build a sorted `id=count` fingerprint, and publish only after the full scan succeeds. Resolve names through `accessxi.resource_item_info_by_name` and require one valid native resource ID.

In the existing incoming packet callback, mark a refresh pending for item-related packet IDs `0x001D`, `0x001F`, `0x0037`, `0x0050`, `0x0051`, `0x0116`, and `0x0117`. In `d3d_present`, run the scan once after the pending deadline before normal navigation polling.

- [ ] **Step 4: Run the reader integration wrapper and verify GREEN**

Run the same wrapper and require its reader behavior, integrity, and manifest-pin pass lines.

---

### Task 2: Inventory-selected mission step

**Files:**
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Test: `tools/lua_tests/test_mission_quest_navigation.lua`

**Interfaces:**
- Consumes: `accessxi.refresh_objective_inventory_state(reason)` and `accessxi.objective_inventory_count_by_name(name)`
- Produces: inventory-filtered rows from `accessxi.nav_mission_quest_active_items('mission')`
- Produces: exact Gate Guard turn-in candidates through the existing nation Gate Guard references when a structurally selected next step names that role

- [ ] **Step 1: Write the failing navigation tests**

Extend the San d'Oria fixture with its ordered step-007 Gate Guard action. Assert:

```lua
inventory_counts[16656] = 0
assert(count_step(active_missions(), 'step-005') == 2)
inventory_counts[16656] = 1
local updated = active_missions()
assert(count_step(updated, 'step-005') == 0)
assert(count_step(updated, 'step-007') >= 1)
```

Add already-owned, unrelated-item, zero-count, stale identity/session, and full-set-only multi-item cases. Assert the generated turn-in row retains the exact step ID and source instruction and remains startable only through explicit `I` preparation.

- [ ] **Step 2: Run the mission navigation wrapper and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_mission_quest_navigation.ps1`

Expected: FAIL because possession does not filter the camp rows or expose step 007.

- [ ] **Step 3: Implement structural step advancement**

Before mission row construction, refresh the native snapshot. For active missions without a stronger automatic stage, group exact catalogue candidates by guide step order. Treat only `fight` or `obtain` candidates with a nonempty typed `items` set as acquisition candidates. If every required name has a positive carried count, select the next later non-note material guide step for the same native mission.

Use typed objective candidates for that next step when present. If the selected step is the exact national Gate Guard role, expand the existing exact `nation_gate_guards` references into separate candidates with that step's immutable ID and instruction. Do not use fuzzy entity matching or free-text item parsing.

- [ ] **Step 4: Run the navigation wrapper and verify GREEN**

Run the same wrapper and require both mission/quest guide and navigation pass lines.

---

### Task 3: Refresh, cancel, verify, and deploy

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Test: `tools/lua_tests/test_mission_quest_reader_runtime_integration.lua`
- Deploy: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`
- Deploy: `C:\Users\buu42\Ashita\addons\accessxi_reader\modules\mission_quest_navigation.lua`

**Interfaces:**
- Consumes: changed inventory fingerprint and fresh mission rows
- Produces: `accessxi.on_objective_inventory_changed(reason)` that cancels only a no-longer-owned mission route and refreshes an open Missions browser

- [ ] **Step 1: Write failing cancellation tests**

Assert an Axe acquisition while a camp route is active calls `nav_cancel_mission_quest_route` once, calls no route-start seam, and changes the fresh row to step 007. Assert no active route causes no cancellation/start, an ordinary route remains active, and an unchanged inventory fingerprint produces no repeated cancellation or speech.

- [ ] **Step 2: Run both focused wrappers and verify RED**

Run the reader integration and mission navigation wrappers. Expected: the new event-driven cancellation assertions fail.

- [ ] **Step 3: Implement changed-state handling**

After a successful changed scan, call the navigation owner predicate against fresh mission rows. Cancel only when the current destination or pending zone-search target is mission-owned and its immutable row is absent. Clear the cached Missions menu rows so the next browser read uses the advanced step. Speak one update only when an obsolete mission route was canceled; never call a route-start function.

- [ ] **Step 4: Run focused verification**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_mission_quest_navigation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_mission_quest_reader_runtime_integration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_lua51_syntax.ps1 -Path ashita/addons/accessxi_reader/accessxi_reader.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_lua51_syntax.ps1 -Path ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua
git diff --check -- ashita/addons/accessxi_reader/accessxi_reader.lua ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua tools/lua_tests/test_mission_quest_navigation.lua tools/lua_tests/test_mission_quest_reader_runtime_integration.lua
```

Expected: all exit `0`.

- [ ] **Step 5: Deploy exact bytes and verify hashes**

Copy the two changed addon files to `C:\Users\buu42\Ashita\addons\accessxi_reader`, then compare SHA-256 hashes between repository and live paths. Do not deploy tests or documentation.
