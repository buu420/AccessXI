# Mission Farming Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn evidence-backed mission farming and fight locations into separate, directly routeable mission-browser rows that work across verified zone transitions and required elevator travel.

**Architecture:** Extend the offline objective-guide build with a reviewed mission-destination record that validates imported source revisions, step-level evidence, exact current navigation targets, canonical ingress edges, and transport identifiers. The Lua runtime expands one active mission into stable destination rows, revalidates the selected row against live World-qualified mission state, and passes preserved route constraints to the existing live navigation engine. The existing elevator transition engine is generalized just enough to support the verified Palborough Mines lift without changing unrelated navigation behavior.

**Tech Stack:** Python 3.12 dataclasses and `unittest`; generated Lua 5.1 modules; Ashita v4 Lua; PowerShell harnesses; current AccessXI TSV navigation catalogs and FFXINAV meshes.

## Global Constraints

- Evaluate every imported mission through the destination pipeline; do not add mission-specific runtime branches.
- Only active missions may expose farming camps. Available-to-start missions continue to route only to verified starter NPCs.
- Route starts require current-session packet provenance and a matching World-qualified character identity.
- Reconcile safety per step and destination; an unrelated source conflict must not disable a safe destination.
- Keep distinct camps separate and group only enemies explicitly reviewed as co-located.
- Preserve exact enemy-to-item relationships; do not imply a drop relationship absent from the reviewed evidence.
- A generated `untested` camp is not routeable from name and coordinates alone.
- Cross-zone routing must honor a reviewed canonical final ingress and recalculate from live position after zoning or deviation.
- Elevators and other disconnected transport stages must be explicit; never fabricate a straight route edge.
- Unsupported or unsafe active missions remain visible with `No verified current destination is available.`
- Do not modify, rebuild, publish, or package the installer executable.

---

### Task 1: Generate reviewed mission-destination records

**Files:**
- Create: `tools/objective_guides/mission_destinations.py`
- Modify: `tools/objective_guides/reconcile.py`
- Modify: `tools/objective_guides/generate_lua.py`
- Modify: `tools/objective_guides/cli.py`
- Test: `tools/test_objective_guides.py`

**Interfaces:**
- Consumes: `NativeObjective`, `ReconciledObjective`, both matched `ParsedObjective` records, `reviewed_overrides["mission_destination_overrides"]`, navigation points, navigation zone names, and zoneline edge rows.
- Produces: immutable `ReviewedMissionDestination` values and a `mission_destinations` array on each generated reconciliation objective.
- Produces: `resolve_reviewed_mission_destinations(native, reconciled, bg, ffxiclopedia, reviewed_overrides, navigation_points, navigation_zone_names, navigation_edges) -> tuple[ReviewedMissionDestination, ...]`.

- [ ] **Step 1: Write failing generator tests for validation and Lua output**

Add focused fixtures to `GeneratedArtifactTests` that supply one active-style mission, two corroborated farm steps, exact enemy nav points, one exact canonical edge, and this reviewed override shape:

```python
overrides["mission_destination_overrides"] = {
    "mission:Bastok:3": [
        {
            "id": "palborough-lower-amber",
            "source_revisions": {"bg": 754820, "ffxiclopedia": 1748519},
            "source_step_ids": [
                "mission:Bastok:3:step-003",
                "mission:Bastok:3:step-006",
            ],
            "action": "farm",
            "items": ["Fetich Head", "Fetich Torso", "Fetich Arms", "Fetich Legs"],
            "enemies": ["Amber Quadav"],
            "zone": 143,
            "zone_name": "Palborough Mines",
            "camp_label": "lower camp",
            "reference": {"name": "Amber Quadav", "kind": "enemy"},
            "canonical_ingress": {"edge_id": 947466874, "from_zone": 106},
            "route_evidence": "navprobe:Palborough_Mines.nav:north-gustaberg-entry-to-lower-amber:2026-08-08",
            "arrival_instruction": "Farm the four Fetich pieces from Amber Quadav.",
        }
    ]
}
```

Assert the generated Lua contains `stable_id`, `source_step_ids`, `items`, `enemies`, exact reference, canonical edge, and arrival instruction. Add rejection tests for changed source revisions, conflicted selected steps, duplicate IDs, missing items/enemies, a nonunique nav reference, mismatched zone name, and an ingress edge that does not enter the destination zone.

- [ ] **Step 2: Run the focused generator tests and verify red state**

Run:

```powershell
& tools\.objective-guides-venv\Scripts\python.exe -m unittest `
  tools.test_objective_guides.GeneratedArtifactTests.test_reviewed_mission_destination_is_emitted `
  tools.test_objective_guides.GeneratedArtifactTests.test_reviewed_mission_destination_rejects_unsafe_evidence
```

Expected: failures because mission destination types and output do not exist.

- [ ] **Step 3: Add the focused destination model and validator**

Create `mission_destinations.py` with this immutable contract:

```python
@dataclass(frozen=True, slots=True)
class ReviewedMissionDestination:
    stable_id: str
    source_step_ids: tuple[str, ...]
    action: str
    items: tuple[str, ...]
    enemies: tuple[str, ...]
    zone: int
    zone_name: str
    camp_label: str
    target_name: str
    target_kind: str
    arrival_instruction: str
    canonical_ingress_edge_id: int = 0
    canonical_ingress_from_zone: int = 0
    transport_id: str = ""
    route_evidence: str = ""
```

The resolver must return an empty tuple for ordinary missions with no override, thereby evaluating them without promoting a guess. For each override, verify exact source revisions, selected step IDs belonging to that objective, no conflict on those selected steps, supported action in `{farm, fight, obtain}`, nonempty deduplicated items and enemies, exact zone-name agreement with the navigation catalog, exactly one target reference in that zone, and an exact ingress edge whose `from_zone` and `to_zone` match the override. A target whose current navigation confidence is `untested` must also carry a nonempty reviewed `route_evidence` identifier; the evidence is audited in the focused route fixture rather than inferred from the override itself. Reject duplicate stable IDs across the build.

- [ ] **Step 4: Preserve item evidence in reconciliation and emit destination Lua**

Add `items: tuple[str, ...]` to `ReconciledStep`, populate it from both aligned source steps, and emit it in `_reconcile_module_text`. Extend each reconciliation entry with:

```lua
mission_destinations = {
  {
    stable_id = "mission:Bastok:3:palborough-lower-amber",
    source_step_ids = { "mission:Bastok:3:step-003", "mission:Bastok:3:step-006" },
    action = "farm",
    items = { "Fetich Head", "Fetich Torso", "Fetich Arms", "Fetich Legs" },
    enemies = { "Amber Quadav" },
    zone = 143,
    zone_name = "Palborough Mines",
    camp_label = "lower camp",
    navigation_target = {
      type = "static-reference",
      reference = { zone = 143, zone_name = "Palborough Mines", name = "Amber Quadav", kind = "enemy" },
    },
    canonical_ingress_edge_id = 947466874,
    canonical_ingress_from_zone = 106,
    transport_id = "",
    route_evidence = "navprobe:Palborough_Mines.nav:north-gustaberg-entry-to-lower-amber:2026-08-08",
    arrival_instruction = "Farm the four Fetich pieces from Amber Quadav.",
    route_ready = true,
  },
}
```

Add destination review records and aggregate counts to `target-review.json` without changing objective-level conflict classification.

- [ ] **Step 5: Load complete navigation edge metadata in the CLI**

Change `_load_navigation_catalog` to return `(points, zone_names, edges)`. Preserve destination confidence and notes fields when present, and parse each graph row into the exact edge fields required by the validator. Update the one build call site and its tests.

- [ ] **Step 6: Run generator tests and commit**

Run:

```powershell
& tools\test_objective_guides.ps1
```

Expected: `Objective guide tests passed`.

Commit:

```powershell
git add tools/objective_guides tools/test_objective_guides.py
git commit -m "feat: generate reviewed mission destinations"
```

---

### Task 2: Add the source-reviewed Fetichism camp records

**Files:**
- Modify: `data/mission-quest-guides/reviewed-overrides.json`
- Modify generated: `data/mission-quest-guides/coverage.json`
- Modify generated: `data/mission-quest-guides/coverage.md`
- Modify generated: `data/mission-quest-guides/target-review.json`
- Modify generated: `ashita/addons/accessxi_reader/modules/mission_quest_reconcile_mission_bastok.lua`
- Test: `tools/test_objective_guides.py`

**Interfaces:**
- Consumes: the destination override schema from Task 1.
- Produces: two reviewed `mission:Bastok:3` destinations: lower Amber camp and upper Greater/Onyx/Veteran camp.

- [ ] **Step 1: Write failing snapshot assertions for both camps**

Add a test that loads the repository override file and asserts:

```python
rows = overrides["mission_destination_overrides"]["mission:Bastok:3"]
self.assertEqual([row["id"] for row in rows], [
    "palborough-lower-amber",
    "palborough-upper-quadav",
])
self.assertEqual(rows[1]["transport_id"], "palborough-mines-lift")
self.assertEqual(rows[0]["canonical_ingress"]["edge_id"], 947466874)
```

Also assert all four Fetich item names appear on both rows, the lower row contains only Amber Quadav, and the upper row contains Greater, Onyx, and Veteran Quadav.

- [ ] **Step 2: Run the focused test and verify red state**

Run the new unittest by its exact method name. Expected: failure because the overrides are absent.

- [ ] **Step 3: Add revision-locked reviewed overrides**

Add two records under `mission_destination_overrides["mission:Bastok:3"]` using BG revision `754820` and FFXIclopedia revision `1748519`.

Use current nav references:

```json
{"name": "Amber Quadav", "kind": "enemy"}
```

for the lower camp and:

```json
{"name": "Onyx Quadav", "kind": "enemy"}
```

for the co-located upper camp. Both use canonical North Gustaberg ingress edge `947466874`; only the upper row uses `transport_id: "palborough-mines-lift"`. Record the already-run FFXINAV probe identities for the North Gustaberg entry to the lower and upper camps in each row's `route_evidence` field, and add a regression assertion that the route-evidence strings are present.

- [ ] **Step 4: Regenerate from committed snapshots without network access**

Run:

```powershell
& tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli build `
  --repo-root . `
  --offline
```

Expected: deterministic generated files with exactly two Fetichism destination records and no raw source cache added to Git.

- [ ] **Step 5: Verify generated scope and commit**

Run the full objective guide tests, `git diff --check`, and inspect `git diff --stat` to ensure only reviewed overrides and expected generated objective artifacts changed.

Commit:

```powershell
git add data/mission-quest-guides ashita/addons/accessxi_reader/modules/mission_quest_reconcile_mission_bastok.lua tools/test_objective_guides.py
git commit -m "data: review Fetichism farming camps"
```

---

### Task 3: Expand active missions into stable farming rows

**Files:**
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_guides.lua`
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Test: `tools/lua_tests/test_mission_quest_guides.lua`
- Test: `tools/lua_tests/test_mission_quest_navigation.lua`
- Test: `tools/test_mission_quest_navigation.ps1`

**Interfaces:**
- Consumes: `reconciliation.mission_destinations` from Task 1.
- Produces: `GuideState:mission_destinations(native_key) -> table`.
- Produces: mission browser rows carrying `objective_destination_id`, `objective_items_text`, `objective_enemies_text`, `objective_camp_label`, `objective_canonical_edge_id`, `objective_canonical_from_zone`, and `objective_transport_id`.

- [ ] **Step 1: Write failing guide-loader tests**

Extend the guide fixture reconciliation with two mission destinations and assert:

```lua
local destinations = assert(state:mission_destinations('mission:Bastok:3'))
assert(#destinations == 2)
assert(destinations[1].stable_id == 'mission:Bastok:3:palborough-lower-amber')
assert(destinations[2].transport_id == 'palborough-mines-lift')
```

Verify returned records are copies so mutating a caller result does not corrupt the cached guide.

- [ ] **Step 2: Write failing mission-browser tests**

Add two destination records to the Lua navigation harness and activate `Fetichism`. Assert:

```lua
local rows = accessxi.nav_mission_quest_active_items('mission')
assert(count_named(rows, 'Fetichism') == 2)
assert(find_destination(rows, 'palborough-lower-amber').objective_available == true)
assert(find_destination(rows, 'palborough-upper-quadav').objective_transport_id == 'palborough-mines-lift')
assert(accessxi.nav_mission_quest_item_speech(lower, 1, #rows):find('Amber Quadav', 1, true))
assert(accessxi.nav_mission_quest_item_speech(upper, 2, #rows):find('Greater Quadav', 1, true))
```

Also assert an ordinary unsupported mission still has one unavailable row, an available-to-start mission is not expanded, stale packet provenance blocks `I`, and same-name characters on different Worlds cannot reuse a destination row.

- [ ] **Step 3: Run the mission/quest harness and verify red state**

Run:

```powershell
& tools\test_mission_quest_navigation.ps1
```

Expected: failure at the new destination assertions.

- [ ] **Step 4: Expose copied destination records from the guide loader**

In `GuideState:resolve`, normalize and retain `reconciliation.mission_destinations`. Implement `mission_destinations(native_key)` so it returns a fresh array of shallow records plus fresh `items`, `enemies`, `source_step_ids`, and `navigation_target.reference` tables.

- [ ] **Step 5: Expand only active mission rows**

After `active_missions` builds native rows, replace an active mission row only when its guide returns at least one route-ready destination. Build each replacement by copying native ownership and mission identity, resolving the exact current nav reference, and applying destination metadata. If every destination fails runtime resolution, retain the original generic row.

Use stable identity in `same_item`:

```lua
if kind == 'mission' and clean(a.objective_destination_id) ~= '' then
    return clean(a.objective_destination_id) == clean(b.objective_destination_id)
        and clean(a.mission_context) == clean(b.mission_context)
        and tonumber(a.mission_id) == tonumber(b.mission_id)
end
```

Update speech to say the mission title, action, complete reviewed item list, complete reviewed enemy list, zone/camp label, navigation availability, and row count at the end. Do not say `Current objective` when exact server stage is unavailable; say `Mission destination`.

- [ ] **Step 6: Revalidate and prepare the exact highlighted destination**

`nav_mission_quest_prepare_route` must rebuild the current list, match the stable destination ID, require live `packet_in_056` ownership, and return only that fresh target. Extend both point-copy functions to preserve every scalar destination metadata field through pending cross-zone routes and active routes.

- [ ] **Step 7: Run Lua tests and commit**

Run:

```powershell
& tools\test_mission_quest_navigation.ps1
& tools\check_lua51_syntax.ps1 -Path ashita\addons\accessxi_reader\modules\mission_quest_guides.lua
& tools\check_lua51_syntax.ps1 -Path ashita\addons\accessxi_reader\modules\mission_quest_navigation.lua
& tools\check_lua51_syntax.ps1 -Path ashita\addons\accessxi_reader\accessxi_reader.lua
```

Expected: both behavior harnesses pass and all three files report `syntax ok`.

Commit:

```powershell
git add ashita/addons/accessxi_reader tools/lua_tests tools/test_mission_quest_navigation.ps1
git commit -m "feat: expose mission farming destinations"
```

---

### Task 4: Enforce the canonical destination ingress

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Test: `tools/test_nav_zone_search_command.ps1`
- Test: `tools/test_mission_quest_navigation.ps1`

**Interfaces:**
- Consumes: optional `objective_canonical_edge_id` and `objective_canonical_from_zone` preserved on a pending target.
- Produces: `accessxi.nav_zoneline_path(from_zone, to_zone, final_edge_id)` with backward-compatible two-argument behavior.

- [ ] **Step 1: Write failing canonical-ingress path tests**

Extend the zone-search harness with a graph containing two entries into zone `143`: one from `106` and one from `144`. Assert the ordinary two-argument path still chooses normal BFS order, while:

```lua
local path = accessxi.nav_zoneline_path(236, 143, 947466874)
assert(path:len() > 0)
assert(path[path:len()].id == 947466874)
assert(path[path:len()].from_zone == 106)
assert(path[path:len()].to_zone == 143)
```

Also assert an unknown edge ID returns an empty path and never silently falls back.

- [ ] **Step 2: Run the zone-search harness and verify red state**

Run `tools\test_nav_zone_search_command.ps1`. Expected: canonical-edge assertion fails.

- [ ] **Step 3: Add backward-compatible final-edge routing**

When `final_edge_id` is nonzero, locate exactly one edge with that ID and destination zone, verify its `from_zone`, compute an unconstrained prefix to that source zone, then append the reviewed edge. If the current zone already equals the edge's source zone, return a one-edge path. If validation fails, return an empty path.

Pass the pending target's canonical edge into every `nav_zone_search_start_next_leg` path calculation. Preserve normal same-zone final routing and all existing same-zone re-entry safeguards.

- [ ] **Step 4: Run zone search and mission route tests, then commit**

Run:

```powershell
& tools\test_nav_zone_search_command.ps1
& tools\test_mission_quest_navigation.ps1
```

Commit:

```powershell
git add ashita/addons/accessxi_reader/accessxi_reader.lua tools/test_nav_zone_search_command.ps1 tools/test_mission_quest_navigation.ps1
git commit -m "feat: honor objective zone ingress"
```

---

### Task 5: Add verified Palborough Mines elevator continuation

**Files:**
- Modify: `ashita/addons/accessxi_reader/modules/metalworks_elevator_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Modify: `tools/test_nav_metalworks_elevator.ps1`

**Interfaces:**
- Consumes: a same-zone destination and current live player position.
- Produces: `accessxi.nav_verified_elevator_route(player, destination)` while retaining `nav_metalworks_elevator_route` as a compatibility alias.
- Preserves: existing `nav_transport_transition`, start suffix, waiting beacon, live floor-change detection, and continuation APIs.

- [ ] **Step 1: Add failing Palborough elevator behavior tests**

Extend the existing elevator harness with verified Palborough fixtures:

```lua
local lower = { zone = 143, x = 182.401, z = 64.408, y = 0.902 }
local upper = { zone = 143, x = 182.401, z = 64.408, y = -32.207 }
local upper_camp = { zone = 143, name = 'Onyx Quadav', x = 220.313, z = 88.193, y = -32.280, objective_transport_id = 'palborough-mines-lift' }
local route = accessxi.nav_verified_elevator_route(lower_player, upper_camp)
assert(route:len() > 1)
assert(accessxi.nav_transport_transition.elevator_id == 'palborough-mines-lift')
```

Assert the prompt names the Elevator Lever and tells the player to press Enter and select the affirmative option, the beacon targets the platform while waiting, the route resumes only after live upper-floor position evidence, and a destination without the Palborough transport ID is not forced through that lift.

- [ ] **Step 2: Run the elevator harness and verify red state**

Run `tools\test_nav_metalworks_elevator.ps1`. Expected: missing `nav_verified_elevator_route` or Palborough route failure.

- [ ] **Step 3: Generalize the existing verified elevator engine**

Keep the current Metalworks definitions unchanged. Add a reviewed Palborough definition with:

```lua
id = 'palborough-mines-lift'
zone = 143
platform = { x = 179.030, z = 62.612, y = -19.222 }
lower = { x = 182.401, z = 64.408, y = 0.902 }
upper = { x = 182.401, z = 64.408, y = -32.207 }
```

The Palborough route is eligible only when the destination carries `objective_transport_id = 'palborough-mines-lift'`. Its prompt must reflect the visible lever interaction. Generalize zone checks and state matching without weakening Metalworks trigger-corridor rejection. Expose `nav_verified_elevator_route`, retain the old function as an alias, and have route computation call the new function.

- [ ] **Step 4: Run transport, mission, and syntax tests, then commit**

Run:

```powershell
& tools\test_nav_metalworks_elevator.ps1
& tools\test_mission_quest_navigation.ps1
& tools\check_lua51_syntax.ps1 -Path ashita\addons\accessxi_reader\modules\metalworks_elevator_navigation.lua
& tools\check_lua51_syntax.ps1 -Path ashita\addons\accessxi_reader\accessxi_reader.lua
```

Commit:

```powershell
git add ashita/addons/accessxi_reader/modules/metalworks_elevator_navigation.lua ashita/addons/accessxi_reader/accessxi_reader.lua tools/test_nav_metalworks_elevator.ps1
git commit -m "feat: navigate the Palborough lift"
```

---

### Task 6: Full verification and addon-only deployment

**Files:**
- Verify all modified and generated files.
- Deploy only changed addon files to `C:\Users\buu42\Ashita\addons\accessxi_reader`.
- Do not modify installer projects, installer artifacts, GitHub releases, or `.exe` files.

**Interfaces:**
- Consumes: all previous task commits.
- Produces: a verified worktree and byte-identical installed addon files for later in-game testing.

- [ ] **Step 1: Run the complete focused suite**

Run:

```powershell
& tools\test_objective_guides.ps1
& tools\test_mission_quest_navigation.ps1
& tools\test_nav_zone_search_command.ps1
& tools\test_nav_metalworks_elevator.ps1
```

Expected: every harness reports its pass message and exits zero.

- [ ] **Step 2: Run Lua 5.1 syntax checks on every changed Lua file**

Derive the changed Lua list from `git diff origin/main --name-only -- '*.lua'`, then invoke `tools\check_lua51_syntax.ps1` once per file. Expected: `syntax ok` for every file.

- [ ] **Step 3: Audit generated and repository state**

Run:

```powershell
git diff origin/main --check
git status --short --branch
git diff origin/main --stat
git log --oneline origin/main..HEAD
```

Confirm no installer, setup executable, release archive, source-cache content, or unrelated file appears.

- [ ] **Step 4: Deploy changed addon files and byte-compare**

Copy only paths under `ashita/addons/accessxi_reader` that differ from `origin/main` into the installed addon root, preserving their relative paths. Do not delete unrelated installed logs, settings, recordings, or user data. For every copied file, compare SHA-256 between worktree and installed destination and require equality.

- [ ] **Step 5: Record the verification commit**

If verification requires no source correction, leave the prior commits unchanged. If a test-driven correction was necessary, commit only that correction with:

```powershell
git add <exact corrected files>
git commit -m "fix: harden mission farming navigation"
```

Report the branch, commit list, exact deployed files, test evidence, and the remaining requirement for live in-game validation. Do not claim that runtime behavior is confirmed until someone tests it in FFXI.
