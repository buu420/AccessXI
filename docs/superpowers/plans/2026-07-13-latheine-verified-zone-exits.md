# La Theine Verified Zone Exits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make La Theine Plateau expose exactly two verified Ordelle's Caves zone lines plus Valkurm Dunes, West Ronfaure, and Jugner Forest, without losing any walked survey geometry.

**Architecture:** Keep the 6,499-node recorded survey as route topology, but stop publishing its `area` marks as independent menu destinations. Apply an explicit evidence policy to the zoneline generator: retain and prove Ordelle `z2u6` and `z2u8`, exclude the unmatched `z2ua` transition in both directions, and generate the same policy into the destination and graph files.

**Tech Stack:** PowerShell regression tests, Python 3 data generator, TSV navigation data, Lua 5.1 addon runtime.

## Global Constraints

- Use live walked recordings and current navigation data; do not guess routes from static tables.
- False positives and unsafe routes are worse than silence.
- Preserve all recorded-survey nodes and edges.
- Keep source-addon and live-addon data byte-identical after the edit.
- Do not initialize or push a Git repository.

---

### Task 1: Lock the visible-exit contract with a failing regression test

**Files:**
- Create: `C:\Users\buu42\AccessXI\tools\test_nav_lathine_verified_zone_exits.ps1`

**Interfaces:**
- Consumes: `ffxi-nav-zoneline-graph.tsv`, `ffxi-nav-destinations.tsv`, `ffxi-nav-recorded-marks.tsv`, and `ffxi-nav-recorded-survey.tsv` from source and live addon locations.
- Produces: A regression contract requiring five visible exits, two proven Ordelle graph edges (`z2u6`, `z2u8`), no `z2ua` pair, no recorded `area` destinations, and preserved survey mark nodes.

- [ ] **Step 1: Write the failing test**

  Parse each TSV structurally. Assert exact destination names, proof provenance, graph exclusions, byte-identical copies, zero `area` rows in recorded marks, and the continued presence of survey sequences 800, 845, 1288, and 1969.

- [ ] **Step 2: Run the test to verify it fails**

  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_lathine_verified_zone_exits.ps1`

  Expected: FAIL because `z2ua` and the recorded `area` marks are still present and the two retained Ordelle edges are still untested.

### Task 2: Make the generator preserve the verified policy

**Files:**
- Modify: `C:\Users\buu42\AccessXI\tools\generate_nav_zoneline_destinations.py`

**Interfaces:**
- Consumes: raw LandSandBoat zoneline edges.
- Produces: `apply_edge_policy(edges)` and override-backed destination fields shared by graph and destination generation.

- [ ] **Step 1: Add the minimal edge policy**

  Exclude zoneline IDs `1635070586` and `878982522`. Override IDs `913650298` and `947204730` with source `live-mark-aligned-navmesh-20260713`, confidence `proven`, and note `user-confirmed-ordelle-line-2026-07-13`.

- [ ] **Step 2: Apply overrides to generated destinations**

  Use the same coordinates, source, confidence, and section evidence that `write_graph` uses, so regeneration cannot reintroduce an unverified duplicate or downgrade proof.

### Task 3: Stop survey anchors from becoming destinations

**Files:**
- Modify: `C:\Users\buu42\AccessXI\tools\build_nav_lathine_recorded_survey_graph.ps1`
- Modify: `C:\Users\buu42\AccessXI\tools\test_nav_lathine_recorded_survey_graph.ps1`
- Modify: all three copies of `ffxi-nav-recorded-marks.tsv`

**Interfaces:**
- Consumes: raw `mark` events in `ffxi-nav-route-recordings.tsv`.
- Produces: navigation marks for NPC/object landmarks only; `area` evidence remains in `ffxi-nav-recorded-survey.tsv`.

- [ ] **Step 1: Remove the four `area` definitions from the mark export**

  Exclude survey sequences 800, 845, 1288, and 1969 from `ffxi-nav-recorded-marks.tsv` while leaving those nodes untouched in the survey graph.

- [ ] **Step 2: Update the existing recorded-survey regression**

  Require 24 exported landmark destinations and explicitly require the four route/zone anchors to remain in the full survey graph.

### Task 4: Publish and verify the exact data set

**Files:**
- Modify: all three copies of `ffxi-nav-zoneline-graph.tsv`
- Modify: all three copies of `ffxi-nav-destinations.tsv`

**Interfaces:**
- Produces: exactly five La Theine zone-line destinations and a symmetric graph with the invalid `z2ua` pair absent.

- [ ] **Step 1: Apply the generated policy to all data copies**

  Retain Ordelle `z2u6` and `z2u8` as proven, remove `z2ua`, and preserve the Valkurm, West Ronfaure, and Jugner Forest entries.

- [ ] **Step 2: Run focused regressions**

  Run the new exit test, the recorded-survey test, the Valkurm correction test, zoneline menu visibility, zone search, and La Theine route tests.

- [ ] **Step 3: Validate and reload**

  Run the Lua 5.1 syntax wrapper, verify source/live hashes, reload `accessxi_reader`, and inspect the fresh log for a clean data load.
