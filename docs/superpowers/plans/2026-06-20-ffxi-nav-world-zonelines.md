# FFXI Nav World Zonelines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand AXI nav destination coverage from the current curated zones to all locally known LSB zoneline transitions, while preserving confidence labels and avoiding guessed paths.

**Architecture:** Keep the live nav reader zone-local for now, but add a generated zone-edge graph sidecar so future work can build multi-zone route planning. Generated destination rows are `untested` and source-backed by local LSB zoneline coordinates; special gates are recorded as notes only when backed by BG Wiki or local source evidence.

**Tech Stack:** AccessXI TSV data, LandSandBoat SQL exports, Python generator run with the bundled Codex Python, existing Ashita Lua nav loader.

---

### Task 1: Add A Repeatable Zoneline Generator

**Files:**
- Create: `C:\Users\buu42\AccessXI\tools\generate_nav_zoneline_destinations.py`
- Read: `C:\Users\buu42\AccessXI\data\lsb_zonelines.sql`
- Read: `C:\Users\buu42\AccessXI\third_party\LandSandBoat-server\documentation\ZoneIDs.txt`
- Modify: `C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv`
- Create: `C:\Users\buu42\AccessXI\data\ffxi-nav-zoneline-graph.tsv`

- [x] **Step 1: Parse LSB zonelines**

Use a Python regex that reads each `INSERT INTO zonelines` row and converts LSB `x,y,z` into AXI `x,z,y`.

- [x] **Step 2: Generate destination rows**

Generate one `area` destination per `from_zone` exit with source `lsb-zoneline-all`, confidence `untested`, and section `world-zonelines-2026-06-20`.

- [x] **Step 3: Preserve existing/manual rows**

Skip generated rows when an existing area destination is already within 2 yalms of the same zone coordinate. Existing live/proven rows stay untouched.

- [x] **Step 4: Write a graph sidecar**

Write every LSB edge to `ffxi-nav-zoneline-graph.tsv` with from/to zone IDs, names, portal codes, and converted coordinates for future multi-zone routing.

- [x] **Step 5: Run generator in dry-run and write modes**

Run:

```powershell
& 'C:\Users\buu42\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'C:\Users\buu42\AccessXI\tools\generate_nav_zoneline_destinations.py' --dry-run
& 'C:\Users\buu42\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'C:\Users\buu42\AccessXI\tools\generate_nav_zoneline_destinations.py' --write
```

Expected: dry-run reports the number of parsed LSB edges and missing destination rows; write mode updates only generated outputs.

### Task 2: Add Source-Backed Restriction Notes

**Files:**
- Create: `C:\Users\buu42\AccessXI\data\ffxi-nav-route-notes.tsv`

- [x] **Step 1: Add Three Mage Gate note**

Record BG Wiki-backed access constraints for Inner Horutoto Ruins to Toraimarai Canal: party circles, Portal charm assistance, or prior Toraimarai Home Point / Survival Guide unlock.

- [x] **Step 2: Add Garlaige and Eldieme zone-level notes**

Record BG Wiki-backed zone-level notes for Garlaige Banishing Gates and Eldieme Necropolis doors without applying them as hard route blockers.

### Task 3: Verify Data Integrity

**Files:**
- Read: `C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv`
- Read: `C:\Users\buu42\AccessXI\data\ffxi-nav-zoneline-graph.tsv`

- [x] **Step 1: Count coverage**

Verify destination zone count increases from 11 to around 198.

- [x] **Step 2: Spot-check fragile rows**

Check Port San d'Oria still keeps the live-proven Mog House row at `79.626, -135.184, -16.049`.

- [x] **Step 3: Ensure Lua still parses data**

No addon code changes are required for the first pass, but if Lua is touched, run the existing Lua 5.1 syntax wrapper.
