# Current-Zone Collision Preload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare collision terrain silently after entering a zone so normal route selection does not absorb the native build delay.

**Architecture:** Add a begin-only `State:preload(zone)` API to the collision module, then call it once from the reader after zoning settles and a valid current-zone position exists. Route queries continue through the existing `State:route` safety path; a pending menu start gives truthful preparation speech instead of claiming the beacon is active.

**Tech Stack:** Lua 5.1, LuaJIT FFI, Ashita `d3d_present`, native ABI-3 collision worker, PowerShell regression runners.

## Global Constraints

- Preload must never call `AXI_FindPath`, FFXINAV, route speech, or beacon playback.
- Reuse one native generation for the current zone and cancel it on zone changes.
- Skip zone 102 because La Theine already uses its immediate installed navmesh.
- Never guide along an unvalidated temporary route.
- Preserve existing native ABI and package manifest.

---

### Task 1: Begin-only collision lifecycle

**Files:**
- Modify: `tools/lua_tests/test_collision_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/modules/collision_navigation.lua`

**Interfaces:**
- Produces: `State:preload(zone) -> boolean|nil, "pending"|"ready"|"busy"|"error", string`
- Preserves: `State:route(player, destination)` and `State:poll(player)` contracts.

- [ ] **Step 1: Write the failing lifecycle test**

Add a fresh fake-native fixture that calls `state:preload(244)` twice and asserts one `begin_load`, zero `find_path`, no pending destination, then marks native READY and asserts `state:route(player, destination)` reuses that generation and performs one path query.

- [ ] **Step 2: Run the focused test to verify RED**

Run: `tools\test_collision_navigation.ps1`

Expected: FAIL because `State:preload` does not exist.

- [ ] **Step 3: Implement the minimal begin-only API**

Add `State:preload(zone)` with positive-zone validation, shutdown handling, same-zone generation reuse, pending-route protection, and `_begin(zone, nil)` without assigning `pending_destination`.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run: `tools\test_collision_navigation.ps1`

Expected: PASS with exactly one begin and one later query.

### Task 2: Silent stable-zone preload and truthful pending speech

**Files:**
- Modify: `tools/lua_tests/test_collision_reader_lifecycle.lua`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`

**Interfaces:**
- Consumes: `State:preload(zone)` from Task 1.
- Produces: `accessxi.poll_nav_dat_collision_preload(now)` and reader state keyed by current zone.

- [ ] **Step 1: Write failing reader lifecycle cases**

Exercise the real extracted preload poll with a stable player in zone 244. Assert one silent preload call across repeated polls, no route activation, no destination, and no speech. Change to zone 245 and assert one new call. Set zone 102 and assert no call. Exercise menu start while `nav_dat_collision_pending` is populated and assert speech contains “Safe route” and does not contain “Beacon active”.

- [ ] **Step 2: Run the focused reader test to verify RED**

Run: `tools\test_collision_reader_integration.ps1`

Expected: FAIL because the reader preload poll and truthful menu branch are absent.

- [ ] **Step 3: Implement minimal reader orchestration**

Add per-zone attempted state, reset it in `nav_reset_zone_state`, call preload immediately after settled position polling, and add a pending return immediately after menu route computation. Log preload lifecycle without speaking.

- [ ] **Step 4: Run focused reader tests to verify GREEN**

Run: `tools\test_collision_reader_integration.ps1`

Expected: PASS for lifecycle, route integration, beacon, and collision safety suites.

### Task 3: Verification and deployment

**Files:**
- Verify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Verify: `ashita/addons/accessxi_reader/modules/collision_navigation.lua`

**Interfaces:**
- Consumes: both implemented tasks.
- Produces: deployed live addon files with matching SHA-256 hashes.

- [ ] **Step 1: Run Lua and regression gates**

Run the collision navigation wrapper, collision reader integration wrapper, mission/quest reader runtime integration wrapper, zone-reset tests, Lua 5.1 syntax checks for both production files, and `git diff --check`.

- [ ] **Step 2: Review the production diff**

Confirm no native ABI, DLL, manifest, route-safety, HRTF, or PlayOnline file changed.

- [ ] **Step 3: Commit the implementation**

Commit only the design, plan, focused tests, reader, and collision module with message `fix: preload current-zone collision terrain`.

- [ ] **Step 4: Deploy safely**

Confirm POL/FFXI/Ashita are closed or use the established addon reload boundary. Back up and copy the collision module first and reader last, then compare deployed SHA-256 hashes to the committed files.
