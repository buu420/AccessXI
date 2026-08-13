# Chateau d'Oraguille Zone Visibility Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Always expose Chateau d'Oraguille as zone 233 and route to its real, access-gated Northern San d'Oria entrance.

**Architecture:** Add the scripted one-way gate as generator-owned topology, then extend global zone search with canonical zone-name results that reuse the existing cross-zone route state machine. The game remains authoritative for access and continuation occurs only after an observed zone change.

**Tech Stack:** Python 3 generator/tests, Lua 5.1 reader/tests, PowerShell focused runners, TSV route data.

## Global Constraints

- Never hide Chateau based on nation, rank, mission, or inferred access.
- Never route to Chateau through West Ronfaure or Bostaunieux Oubliette.
- Do not invent an unsupported Chateau-to-Northern reverse edge.
- Do not continue until the player actually enters zone 233.
- Preserve unrelated dirty-worktree changes.

---

### Task 1: Scripted Chateau ingress

**Files:**
- Modify: `tools/generate_nav_zoneline_destinations.py`
- Modify: `tools/test_nav_destination_generator.py`
- Modify: `data/ffxi-nav-zoneline-graph.tsv`
- Modify: `ashita/addons/accessxi_reader/data/ffxi-nav-zoneline-graph.tsv`
- Modify only if generator requires it: paired `ffxi-nav-destinations.tsv` files

**Interfaces:**
- Produces one graph edge from zone 231 to 233 with approach `(0,110,-2)` and landing `(0,-13,0)` in AccessXI `x,z,y` order.

- [ ] Write a generator test that independently asserts the scripted transition, its coordinates, source, access note, one-way direction, and byte-identical paired outputs.
- [ ] Run the focused generator test and confirm it fails because the transition is absent.
- [ ] Add the scripted-transition generator input and render it through the existing graph/destination identity rules.
- [ ] Regenerate the paired data files.
- [ ] Run the focused generator test and confirm it passes.

### Task 2: Runtime direct-path regression

**Files:**
- Modify or create: `tools/lua_tests/test_nav_zoneline_path.lua`
- Modify only if needed: `tools/test_nav_zone_search_command.ps1`

**Interfaces:**
- Consumes the generated graph.
- Verifies `nav_zoneline_path(231,233)` returns one direct edge.

- [ ] Add a real-graph assertion that the path contains exactly 231-to-233 and never zones 100 or 167.
- [ ] Run it before regenerated data and confirm the wrong three-edge path fails.
- [ ] Rerun after Task 1 and confirm it passes.

### Task 3: Unconditional zone-name results

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Create or modify: focused Lua zone-search behavior test and PowerShell runner.

**Interfaces:**
- Produces global zone-name search results marked for the existing `nav_zone_search_start_next_leg` flow.
- Does not consume mission/rank/access state.

- [ ] Add a focused test where exact search for `Chateau d'Oraguille` returns one selectable zone-233 result without any access state.
- [ ] Assert selection computes the one-edge gate route and waits for an observed zone change.
- [ ] Run the test and confirm it fails because current global search indexes NPCs only.
- [ ] Add the minimal canonical zone-result collection and deterministic deduplication.
- [ ] Run the focused test and confirm it passes.

### Task 4: Verification and deployment

**Files:**
- Update the route manifest only if its pinned data hashes require it.
- Deploy only changed addon runtime/data files to `C:\Users\buu42\Ashita\addons\accessxi_reader`.

**Interfaces:**
- Produces byte-identical tested live files and reports hashes.

- [ ] Run generator, zoneline path, zone-search, navigation integration, Lua 5.1 syntax, and `git diff --check` gates.
- [ ] Recompute any required manifest hash through the existing writer rather than hand editing.
- [ ] Verify POL/FFXI/Ashita are closed before deployment.
- [ ] Deploy the exact tested files and verify live/worktree SHA-256 equality.
