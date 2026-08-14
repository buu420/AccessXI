# Heavens Tower Zone Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the two real Windurst Walls/Heavens Tower transitions so zone 242 is globally searchable, while preserving the existing single Metalworks result.

**Architecture:** Model both portal events as generator-owned scripted transitions, render scripted rows into both graph copies transactionally, regenerate paired destination data, and verify the real runtime zone-search/path functions. No access-state gate or runtime coordinate exception is introduced.

**Tech Stack:** Python 3, Lua 5.1, TSV navigation catalogs, PowerShell wrappers.

## Global Constraints

- Use scripted IDs `239242086` and `242239041` exactly; neither may collide with any other edge ID.
- Edge 239242086 uses approach `(0,141,-16.5)` and landing `(0,-22.4,0)` in AccessXI x/z/y order.
- Edge 242239041 uses approach `(0,-34,0)` and landing `(0,135,-17)` in AccessXI x/z/y order.
- Both edges use source `lsb-scripted-trigger`, confidence `proven`, event provenance, and an empty access note.
- Generated root/addon graph and destination copies must remain byte-identical; never patch one TSV copy by hand.
- Metalworks remains exactly one zone-237 result using canonical ingress edge 912930426.

---

### Task 1: Scripted topology generation and runtime visibility

**Files:**
- Modify: `tools/generate_nav_zoneline_destinations.py`
- Modify: `tools/test_nav_destination_generator.py`
- Create: `tools/lua_tests/test_nav_capital_zone_visibility.lua`
- Create: `tools/test_nav_capital_zone_visibility.ps1`
- Modify generated pairs: `data/ffxi-nav-zoneline-graph.tsv`, `ashita/addons/accessxi_reader/data/ffxi-nav-zoneline-graph.tsv`, `data/ffxi-nav-destinations.tsv`, `ashita/addons/accessxi_reader/data/ffxi-nav-destinations.tsv`
- Modify: `ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv`
- Modify: `tools/test_objective_route_evidence.py`

**Interfaces:**
- `apply_edge_policy(edges)` returns both scripted transitions exactly once.
- Add `_render_scripted_graph_file(existing_lines, scripted_edges) -> bytes` and `write_navigation_copies(repo_root, destination_lines, generated_destinations, edges) -> tuple[str, str]`, returning destination and graph SHA-256 values. It owns scripted graph rows while preserving all non-scripted graph evidence.
- Existing `nav_zone_search_npc_results` and `nav_zoneline_path` consume the regenerated graph unchanged.

- [ ] **Step 1: Write generator RED assertions**

Add a Python test requiring these exact `ZoneLine` tuples:

```python
(239242086, 239, 0.0, -16.5, 141.0, 242, 0.0, 0.0, -22.4,
 "Windurst Walls", "trigger-area-1", "Heavens Tower", "event-86", "")
(242239041, 242, 0.0, 0.0, -34.0, 239, 0.0, -17.0, 135.0,
 "Heavens Tower", "trigger-area-1", "Windurst Walls", "event-41", "")
```

Assert unique IDs, exact rendered graph rows, exact generated destination identities, paired byte equality, idempotent second render, and rollback if either paired replacement fails.

- [ ] **Step 2: Write runtime graph/search RED assertions**

Create a Lua harness using the real checked-in graph and extracted production loader/search/path functions. Require one-edge paths in both directions, one exact `Heavens Tower` zone-242 result with empty access-state fixtures, selection of ingress 239242086 followed by a wait for observed zone 242, and one exact `Metalworks` zone-237 result pinned to ingress 912930426.

- [ ] **Step 3: Run RED**

Run:

```powershell
py -3 -m unittest tools.test_nav_destination_generator
& .\tools\test_nav_capital_zone_visibility.ps1 -Root $PWD
```

Expected: generator and runtime assertions fail because no edge touches zone 242.

- [ ] **Step 4: Implement scripted edges and paired graph rendering**

Add both `ZoneLine` records to `SCRIPTED_TRANSITIONS`. The graph renderer removes rows whose first field is one of the current scripted IDs, preserves every other row byte-for-byte, appends all scripted rows in numeric-ID order, and validates global ID uniqueness. The paired writer stages all four outputs, replaces them only after every render validates, and restores all four originals on failure.

- [ ] **Step 5: Regenerate the checked-in pairs through the generator**

Run the generator with the worktree as `--repo-root`, the checked-in LSB SQL inputs, and `--write`. Confirm it reports two scripted graph rows and that root/addon SHA-256 values match. Compute the two final hashes, replace exactly the `destinations` and `graph` rows in `mission-quest-route-manifest.tsv`, and replace `REAL_DESTINATIONS_HASH` in `tools/test_objective_route_evidence.py` with the final destination hash.

- [ ] **Step 6: Run GREEN and adjacent topology suites**

Run:

```powershell
py -3 -m unittest tools.test_nav_destination_generator
& .\tools\test_nav_capital_zone_visibility.ps1 -Root $PWD
& .\tools\test_nav_global_zone_search.ps1 -Root $PWD
& .\tools\test_nav_chateau_zoneline_graph.ps1 -Root $PWD
& .\tools\test_nav_destination_schema.ps1 -Root $PWD
py -3 -m unittest tools.test_objective_route_evidence
git diff --check
```

Expected: all commands exit 0, both data pairs are byte-identical, and Chateau behavior is unchanged.

- [ ] **Step 7: Commit generated topology and tests**

```powershell
git add tools/generate_nav_zoneline_destinations.py tools/test_nav_destination_generator.py tools/lua_tests/test_nav_capital_zone_visibility.lua tools/test_nav_capital_zone_visibility.ps1 tools/test_objective_route_evidence.py data/ffxi-nav-zoneline-graph.tsv ashita/addons/accessxi_reader/data/ffxi-nav-zoneline-graph.tsv data/ffxi-nav-destinations.tsv ashita/addons/accessxi_reader/data/ffxi-nav-destinations.tsv ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv
git commit -m "fix: expose Heavens Tower navigation"
```
