# La Theine Recorded Survey Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert all 6,499 rows and 28 marks from the complete friend-guided La Theine survey into an authoritative walked navigation graph.

**Architecture:** A generator converts the append-only recorder session into a self-contained node/adjacency TSV and a normal navigation-mark TSV. A focused Lua code module loads and routes over that graph; the main addon loads the marks and consults the graph before ordinary La Theine corridor/navmesh planning while preserving the successful dedicated West Ronfaure route.

**Tech Stack:** PowerShell, Lua 5.1, Ashita addon APIs, TSV data, live AccessXI control bridge.

## Global Constraints

- Use only session `20260712-170700-z102` and current verified nav data; do not invent static paths.
- Preserve all 6,499 session rows and all 28 marks.
- Consecutive recorded edges are bidirectional.
- Reunion edges are limited to 0.5 horizontal and 0.75 vertical yalms.
- False positives and unsafe connectors are worse than silence.
- Live player sampling continues throughout graph navigation.
- Preserve the dedicated successful West Ronfaure recorded corridor.
- Preserve unrelated dirty-worktree changes and do not commit without explicit authorization.

---

### Task 1: Specify complete survey and mark generation

**Files:**
- Create: `tools/test_nav_lathine_recorded_survey_graph.ps1`
- Create: `tools/build_nav_lathine_recorded_survey_graph.ps1`
- Generate: `data/ffxi-nav-recorded-survey.tsv`
- Generate: `data/ffxi-nav-recorded-marks.tsv`

**Interfaces:**
- Consumes: `ffxi-nav-route-recordings.tsv`, session `20260712-170700-z102`.
- Produces: graph rows with `survey_id`, `zone`, `node_id`, `sequence`, coordinates, event, label, comma-separated neighbors, source, and confidence; normal nine-column navigation mark rows.

- [ ] **Step 1: Write the failing data regression**

Assert exact session totals, row coordinates/events/labels, 6,498 bidirectional consecutive edges, exactly 64 bounded reunion edges, 28 mark rows, important normalized labels, and byte identity across source/addon/live data paths.

- [ ] **Step 2: Run the regression and verify RED**

Run `tools/test_nav_lathine_recorded_survey_graph.ps1`. Expected: fail because the generated survey and mark files do not exist.

- [ ] **Step 3: Implement the deterministic generator**

Read and sort the selected session. Add consecutive edges. For each row, use 0.5-yalm X/Z spatial buckets to locate the nearest earlier row more than ten sequence positions away; add one reunion edge only when horizontal distance is at most 0.5 and vertical distance is at most 0.75. Emit sorted unique neighbor IDs and all normalized marks.

- [ ] **Step 4: Generate all source/addon/live data copies**

Run the generator once, then verify the data regression passes.

### Task 2: Load recorded marks as navigation destinations

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:1088-1096`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:69859-69877`
- Test: `tools/test_nav_lathine_recorded_survey_graph.ps1`

**Interfaces:**
- Adds: `accessxi.nav_recorded_marks_path`.
- Extends: `nav_load_points()` with `nav_load_points_file(accessxi.nav_recorded_marks_path, 'live-route-recording')`.

- [ ] **Step 1: Extend the failing regression**

Extract `nav_load_points` and prove it loads the recorded marks file in addition to database, discoveries, and mutable user points.

- [ ] **Step 2: Verify RED**

Expected: fail because no recorded-mark path or load call exists.

- [ ] **Step 3: Add the path and loader call**

Keep recorded marks separate from `ffxi-nav-points.tsv` so live user points are never overwritten.

- [ ] **Step 4: Verify GREEN**

Run the focused graph test and existing destination/menu tests.

### Task 3: Add the recorded-survey routing module

**Files:**
- Create: `ashita/addons/accessxi_reader/modules/recorded_survey_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:1095`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:69735-69750`
- Test: `tools/test_nav_lathine_recorded_survey_graph.ps1`

**Interfaces:**
- State: `nav_recorded_survey_path`, `nav_recorded_survey_loaded`, `nav_recorded_survey_nodes`.
- Produces: `accessxi.nav_recorded_survey_load()`, `accessxi.nav_recorded_survey_nearest(pos)`, `accessxi.nav_recorded_survey_shortest_path(start_id, destination_id)`, and `accessxi.nav_recorded_survey_route(player, point)`.
- Returns: route `T{}` plus a boolean indicating whether recorded coverage requires blocking fallback.

- [ ] **Step 1: Add failing module behavior tests**

Load the real module in a Lua 5.1 harness. Assert exact node count, bounded nearest matching, a shortest route from the survey start to final mark near 3,530 yalms, adjacency-valid output, out-of-coverage silence, and West destination decline.

- [ ] **Step 2: Verify RED**

Expected: fail because the module and functions do not exist.

- [ ] **Step 3: Implement load, heap, Dijkstra, and route assembly**

Reject invalid node/neighbor rows. Emit every graph node in the chosen path with `route_override_id = 'lathine-recorded-survey-20260712'`. Append the exact destination only inside the 1.5-horizontal/2.0-vertical final envelope.

- [ ] **Step 4: Verify GREEN**

Run the focused Lua harness and Lua 5.1 syntax checks for both the module and main addon.

### Task 4: Make the walked graph authoritative

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:68743-68768`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:69740-69780`
- Test: `tools/test_nav_lathine_recorded_survey_graph.ps1`
- Test: `tools/test_nav_authoritative_recorded_route_steering.ps1`

**Interfaces:**
- Recognizes: route IDs beginning `lathine-recorded-survey-` as precise overrides.
- Calls: `nav_recorded_survey_route` for non-West same-zone La Theine destinations before slice corridors and navmesh.

- [ ] **Step 1: Add failing integration assertions**

Prove graph routing is consulted before ordinary corridor/navmesh fallback, West remains on the dedicated corridor, and precise obstacle/wall guards cover graph IDs.

- [ ] **Step 2: Verify RED**

Expected: fail because the main planner does not call the graph and precise mode does not recognize its ID.

- [ ] **Step 3: Integrate the module**

Load it with `T`, distance, TSV parsing, field cleaning, and logging helpers. Return a graph route when present; return an empty route when covered-but-unavailable; otherwise continue existing planning.

- [ ] **Step 4: Verify GREEN**

Run focused graph, steering, corridor, Telepoint, and West-route regressions.

### Task 5: Validate and deploy

**Files:**
- Sync: main Lua, routing module, recorded survey data, and recorded marks to the live addon.
- Verify: all `tools/test_nav_*.ps1`.
- Inspect: live `ffxi-menu-reader.log`.

- [ ] **Step 1: Validate Lua 5.1 syntax**

Run the standard Lua 5.1 checker on the main addon and the new module.

- [ ] **Step 2: Verify all source/addon/live hashes**

Expect one SHA-256 per corresponding file.

- [ ] **Step 3: Run the complete navigation suite**

Expect every `test_nav_*.ps1` to exit zero.

- [ ] **Step 4: Reload through the control bridge**

Queue `/axi console reload`, verify the command is consumed, the addon loads, the graph/mark counts are logged, and no post-reload Lua errors occur.

- [ ] **Step 5: Preserve current game state**

Confirm `pol` remains responsive and do not start a route automatically.
