# Same-Zone Re-entry Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route safely between disconnected components of one zone by leaving through one proven entrance and re-entering through another proven entrance.

**Architecture:** A focused Lua module evaluates only two-transition `A -> B -> A` candidates against current navmesh results and owns the temporary itinerary state. The existing zone-search transition machinery executes each leg and recomputes the final route from the player's live post-zone position.

**Tech Stack:** Lua 5.1, Ashita v4 addon APIs, FFXINAV 32-bit native pathfinding, PowerShell regression harness.

## Global Constraints

- Do not guess a route from static coordinates.
- Reject the detour unless both zone transitions are evidence-backed and all three walking legs are navmesh verified.
- Preserve the existing unreachable response when no safe candidate exists.
- Preserve ordinary same-zone routes and ordinary cross-zone search behavior.
- Deploy source and dependencies to `C:\Users\buu42\Ashita\addons\accessxi_reader` after validation.

---

### Task 1: Reproduce and Specify the Detour

**Files:**
- Create: `tools/test_nav_same_zone_reentry.ps1`
- Test: `third_party/xiNavmeshes/North_Gustaberg.nav`
- Test: `third_party/xiNavmeshes/South_Gustaberg.nav`

**Interfaces:**
- Consumes: `navprobe.exe <mesh> <start-x> <start-y> <start-z> <end-x> <end-y> <end-z>`.
- Produces: a failing Lua behavior test expecting `accessxi.nav_same_zone_reentry_find(player, target)`.

- [ ] **Step 1: Write the native and Lua regression test**

  Assert literal native counts: direct North-to-Guide equals `1`; east exit, South crossing, and west-to-Guide are each greater than `1`. Load the planned module in Lua and expect edge IDs `846803578` then `913977978`.

- [ ] **Step 2: Run the test to verify RED**

  Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\test_nav_same_zone_reentry.ps1`

  Expected: failure because `modules\same_zone_reentry_navigation.lua` does not exist.

### Task 2: Implement the Evidence-Gated Planner

**Files:**
- Create: `ashita/addons/accessxi_reader/modules/same_zone_reentry_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/data/ffxi-nav-zoneline-graph.tsv`

**Interfaces:**
- Consumes: `nav_compute_mesh_route(start, destination)`, `accessxi.nav_zoneline_out_edges(zone, player)`, `accessxi.nav_zoneline_edge_rank(edge, player)`, and `nav_distance(a, b)`.
- Produces: `nav_same_zone_reentry_find`, `nav_same_zone_reentry_begin`, `nav_same_zone_reentry_current_leg`, `nav_same_zone_reentry_advance`, `nav_same_zone_reentry_active`, and `nav_same_zone_reentry_clear`.

- [ ] **Step 1: Implement minimal candidate validation**

  Iterate proven or verified `A -> B` exits and proven or verified `B -> A` re-entries. Exclude the physical reverse of the exit. Require route lengths greater than one for all three walking legs and return the lowest confidence/waypoint score.

- [ ] **Step 2: Implement two-leg state**

  Store exactly two selected edges, an index starting at one, the original zone, and a copy of the final target. Generate normal `zonesearch:` area targets so existing arrival and zoning protection remains active.

- [ ] **Step 3: Prove the module behavior GREEN**

  Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\test_nav_same_zone_reentry.ps1`

  Expected: planner and state tests pass, including unsafe-edge rejection.

### Task 3: Integrate Route Start and Zone Handoffs

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`

**Interfaces:**
- Consumes: the Task 2 module API.
- Produces: normal menu and `/axi nav` fallback into the verified itinerary; final live route after the second zone change.

- [ ] **Step 1: Load the module and clear its state with zone-search state**

  Inject the graph, mesh, distance, speech-cleaning, and logging dependencies after navigation helpers are defined. Extend `nav_clear_zone_search` without changing its existing target/wait semantics.

- [ ] **Step 2: Start a detour only after an unsafe direct-route rejection**

  Before speaking `No verified walkable route`, call `nav_same_zone_reentry_begin` for normal destinations only. If it succeeds, start the first itinerary leg and return its route announcement.

- [ ] **Step 3: Consume the explicit itinerary before ordinary zone BFS**

  In `nav_zone_search_start_next_leg`, prefer `nav_same_zone_reentry_current_leg`. After both edges are consumed, clear only itinerary state and start a fresh route to the preserved final target.

- [ ] **Step 4: Advance only on actual itinerary-leg arrival**

  In the existing `zonesearch:` arrival block, advance the matching detour step before waiting for the observed zone change. An unexpected destination or zone must abort rather than guess.

### Task 4: Validate and Deploy

**Files:**
- Deploy: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`
- Deploy: `C:\Users\buu42\Ashita\addons\accessxi_reader\modules\same_zone_reentry_navigation.lua`
- Deploy: `C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv`

**Interfaces:**
- Consumes: source tree outputs from Tasks 1-3.
- Produces: a Lua 5.1-valid live addon and log evidence of the first safe-detour leg.

- [ ] **Step 1: Run focused and regression tests**

  Run the new test, `test_nav_zone_search_command.ps1`, `test_nav_zoneline_menu_visibility.ps1`, `test_nav_mesh_endpoint_approach.ps1`, `test_nav_zone_load_settle_guard.ps1`, `test_nav_zoning_and_key_blocking.ps1`, and the Lua 5.1 syntax wrapper.

- [ ] **Step 2: Copy only changed addon files to the live installation**

  Preserve unrelated local and live files. Reload `accessxi_reader` through the existing control-file command.

- [ ] **Step 3: Verify live behavior**

  From the current North Gustaberg position, start the Survival Guide route and confirm logs show a verified same-zone re-entry plan followed by a route to the South Gustaberg east zone line, with no direct-route false positive.
