# Complete Mission and Quest Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every playable native mission and active quest expose ordered, source-backed progress instructions and verified destinations wherever movement is required, across every nation, expansion, add-on, Rhapsodies line, and quest area.

**Architecture:** Keep native packets as the active-objective authority, then expand each objective into flat actionable step rows generated offline from pinned wiki claims, current navigation targets, and navmesh evidence. Automatic stage selection remains fail-closed; when the server hides stage state, the player chooses among ordered verified steps. A storyline-by-storyline coverage gate prevents guide text from being counted as navigation.

**Tech Stack:** Lua 5.1, Python 3 objective-guide generator, PowerShell harnesses, current AccessXI TSV navigation data, FFXINAV/navprobe, Ghidra 12.1.2, BG Wiki and FFXIclopedia MediaWiki APIs, GitHub release updater.

## Global Constraints

- Installed DAT rows and current-session packets decide objective identity and activity.
- Disk-restored packet, mission, quest, key-item, and inventory caches never authorize a route.
- Objective state and routes are owned by character plus World, never character name alone.
- Exact target identity, location, and current route evidence are required before movement starts.
- `???` is never resolved by name or proximity alone.
- Wiki grids and prose are guidance claims, not guessed XYZ paths.
- Nonmovement actions are spoken as instructions and never reported as completed on arrival.
- False positives and unsafe routes are worse than an explicit unresolved result.
- The primary checkout and user-owned untracked files remain untouched.
- The installer executable stays unchanged unless installer behavior changes.

---

### Task 1: Stop expansion mission contexts from disappearing

**Files:**
- Modify: `tools/lua_tests/test_mission_quest_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`

**Interfaces:**
- Consumes: `accessxi.current_mission_value_for_context(context) -> value, packet_age`
- Produces: one active mission row for every nonterminal packet value without passing `packet_age` to `tonumber`

- [ ] **Step 1: Write the failing multi-return regression**

Set a nonterminal `Rise of the Zilart` fixture value and keep the existing fixture function returning both value and age:

```lua
mission_values['Rise of the Zilart'] = 3
local rows = accessxi.nav_mission_quest_active_items('mission')
local zilart = assert(find(rows, 'Kazham\'s Chieftainess'))
assert(zilart.mission_context == 'Rise of the Zilart')
```

Also assert the test log has no `base out of range` context failure.

- [ ] **Step 2: Run the focused harness and verify RED**

Run: `tools\test_mission_quest_navigation.ps1`

Expected: the Zilart row is absent because the safe context wrapper catches the `tonumber` second-argument failure.

- [ ] **Step 3: Consume only the first function result**

In `active_missions`, assign the return value before conversion:

```lua
local raw_value = accessxi.current_mission_value_for_context(context)
local value = tonumber(raw_value)
```

Do not change packet freshness, terminal values, context isolation, or logging.

- [ ] **Step 4: Run the harness and verify GREEN**

Run: `tools\test_mission_quest_navigation.ps1`

Expected: `mission and quest navigation tests passed` with the expansion row present.

- [ ] **Step 5: Commit**

```powershell
git add ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua tools/lua_tests/test_mission_quest_navigation.lua
git commit -m "fix: preserve expansion mission values"
```

### Task 2: Generalize destination records to missions and quests

**Files:**
- Create: `tools/objective_guides/objective_destinations.py`
- Modify: `tools/objective_guides/reconcile.py`
- Modify: `tools/objective_guides/generate_lua.py`
- Modify: `tools/test_objective_guides.py`

**Interfaces:**
- Consumes: `NativeObjective`, `ReconciledObjective`, both matched `ParsedObjective` sources, current nav points, zone names, edges, route-evidence cache, reviewed overrides
- Produces: `ReviewedObjectiveDestination` records in `reconciliation.objective_destinations`

- [ ] **Step 1: Write failing destination-model tests**

Add literal fixtures for:

```python
ReviewedObjectiveDestination(
    stable_id="mission:San d'Oria:1:destination:orcish-fodder-east-ronfaure",
    source_step_ids=("mission:San d'Oria:1:step-005",),
    action="obtain",
    target_name="Orcish Fodder",
    target_kind="enemy",
    zone=101,
    zone_name="East Ronfaure",
    arrival_instruction="Defeat Orcish Fodder until you obtain an Orcish Axe.",
)
```

Assert missions and quests share the same destination type, IDs include the native key, unknown step IDs fail, stale source revisions fail, and destination order is deterministic.

- [ ] **Step 2: Run the Python suite and verify RED**

Run: `tools\test_objective_guides.ps1`

Expected: import or attribute failure because `ReviewedObjectiveDestination` and `objective_destinations` do not exist.

- [ ] **Step 3: Add the shared immutable model**

Move common destination fields out of the mission-only model and add:

```python
@dataclass(frozen=True, slots=True)
class ReviewedObjectiveDestination:
    stable_id: str
    source_step_ids: tuple[str, ...]
    action: str
    items: tuple[str, ...]
    enemies: tuple[str, ...]
    zone: int
    zone_name: str
    label: str
    target_name: str
    target_kind: str
    target_point: tuple[float, float, float] | None
    arrival_instruction: str
    route_evidence: str
    canonical_ingress_edge_id: int = 0
    canonical_ingress_from_zone: int = 0
    transport_id: str = ""
    instruction_only: bool = False
```

Keep a temporary reader for existing `mission_destination_overrides`, but emit only the shared runtime field.

- [ ] **Step 4: Emit shared Lua destination records**

Update reconciliation modules to write `objective_destinations = { ... }` for both kinds. Preserve exact source revisions, step IDs, action, items, enemies, target reference or exact point, ingress, transport, route evidence, and instruction-only status.

- [ ] **Step 5: Run the Python suite and verify GREEN**

Run: `tools\test_objective_guides.ps1`

Expected: all existing tests plus the new shared-model tests pass.

- [ ] **Step 6: Commit**

```powershell
git add tools/objective_guides/objective_destinations.py tools/objective_guides/reconcile.py tools/objective_guides/generate_lua.py tools/test_objective_guides.py
git commit -m "feat: model objective step destinations"
```

### Task 3: Resolve every supported action class against current nav data

**Files:**
- Modify: `tools/objective_guides/objective_destinations.py`
- Modify: `tools/objective_guides/generate_lua.py`
- Modify: `tools/objective_guides/wikitext.py`
- Modify: `tools/test_objective_guides.py`

**Interfaces:**
- Consumes: independently parsed source-step claims and the current 34,567-point nav catalog
- Produces: destination candidates with `routable`, `instruction-only`, `conflict`, or `unresolved` status and explicit evidence reasons

- [ ] **Step 1: Write failing resolver tests for all action classes**

Use hand-checked fixtures to cover:

- named NPC `talk` and `trade`;
- named object/door `examine` and `use`;
- enemy `fight` and `obtain` in one and multiple source-confirmed zones;
- zone entrance `travel`;
- battlefield entrance;
- transport metadata;
- exact-coordinate and candidate-set `???` targets;
- `wait` and menu-choice instruction-only steps;
- duplicate named NPCs with no zone discriminator;
- source coordinate conflict;
- single-source target plus independent exact nav/game-data corroboration.

For Orcish Scouts, assert exactly two initial reviewed choices. West Ronfaure is
named by both objective walkthroughs; East Ronfaure is named by BG Wiki and is
independently corroborated by the current enemy-camp/game-data catalog. Do not
silently add the other single-source zones without the same evidence review:

```python
self.assertEqual(
    [(row.zone_name, row.target_name) for row in rows],
    [("East Ronfaure", "Orcish Fodder"), ("West Ronfaure", "Orcish Fodder")],
)
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides.ObjectiveDestinationTests -v`

Expected: the resolver supports only the existing mission farming override and named-NPC review path.

- [ ] **Step 3: Implement claim normalization and target classification**

Normalize zone names independently from linked entities. Select eligible nav kinds by action:

```python
ACTION_KINDS = {
    "talk": ("npc",),
    "trade": ("npc",),
    "examine": ("npc", "door", "area"),
    "use": ("npc", "door", "area"),
    "fight": ("enemy",),
    "obtain": ("enemy",),
    "travel": ("zone", "area", "door"),
}
```

Require an exact target name plus exact zone. Named NPCs must resolve to one point. Enemy camps may resolve to several exact points, but each emitted point carries its exact coordinates and catalog-row fingerprint. `???` requires exact reviewed coordinates or a live candidate-set identity.

- [ ] **Step 4: Generate truthful action and arrival speech**

Use source items, enemies, and action without claiming completion. Keep distinct item/enemy destinations separate. Emit instruction-only records for complete nonmovement actions and omit context-only `note` rows that do not advance progress.

- [ ] **Step 5: Run focused and complete Python suites**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides.ObjectiveDestinationTests -v
tools\test_objective_guides.ps1
```

Expected: every new action-class test and the complete generator suite pass.

- [ ] **Step 6: Commit**

```powershell
git add tools/objective_guides/objective_destinations.py tools/objective_guides/generate_lua.py tools/objective_guides/wikitext.py tools/test_objective_guides.py
git commit -m "feat: resolve objective action targets"
```

### Task 4: Pin navmesh route evidence for generated destinations

**Files:**
- Create: `tools/objective_guides/route_evidence.py`
- Create: `tools/test_objective_route_evidence.py`
- Create: `data/mission-quest-guides/route-evidence.json`
- Modify: `tools/objective_guides/cli.py`
- Modify: `tools/objective_guides/objective_destinations.py`

**Interfaces:**
- Consumes: exact destination point, zone graph incoming edges, zone navmesh, and `tools/navprobe`
- Produces: mesh-hash-pinned evidence with selected ingress edge, probe endpoints, waypoint count, and destination-row hash

- [ ] **Step 1: Write failing evidence-cache tests**

Use a fake executable boundary that returns literal navprobe output. Assert evidence is rejected for a changed mesh hash, changed destination row, zero/one waypoint, failed endpoint approach, or an ingress edge for the wrong destination zone. Assert multiple valid ingresses choose the deterministic shortest verified probe.

- [ ] **Step 2: Run and verify RED**

Run: `tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence -v`

Expected: module import failure.

- [ ] **Step 3: Implement cached route probing**

Map the graph's destination zone name to `third_party/xiNavmeshes/<Zone_Name>.nav`, hash the mesh, and call:

```text
navprobe.exe <mesh> <start-x> <start-y> <start-z> <end-x> <end-y> <end-z>
```

Convert AccessXI `(x, z, y)` to navprobe `(x, y, z)`. Record only successful routes with more than one waypoint. Never infer a successful probe from process exit alone.

- [ ] **Step 4: Add CLI generation and offline reuse**

Add `routes` to the CLI actions. `routes --refresh` recomputes changed probes; normal `build --offline` accepts only matching cached evidence. Missing evidence leaves a destination unresolved.

- [ ] **Step 5: Verify the cache and existing delicate-route guards**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence -v
tools\test_nav_mesh_endpoint_approach.ps1
tools\test_nav_lathine_shelf_escape.ps1
tools\test_nav_metalworks_elevator.ps1
```

Expected: route evidence and all existing route-safety harnesses pass.

- [ ] **Step 6: Commit**

```powershell
git add tools/objective_guides/route_evidence.py tools/objective_guides/cli.py tools/objective_guides/objective_destinations.py tools/test_objective_route_evidence.py data/mission-quest-guides/route-evidence.json
git commit -m "feat: verify objective destinations against navmeshes"
```

### Task 5: Expose flat actionable steps in both runtime categories

**Files:**
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_guides.lua`
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Modify: `tools/lua_tests/test_mission_quest_guides.lua`
- Modify: `tools/lua_tests/test_mission_quest_navigation.lua`

**Interfaces:**
- Consumes: `GuideState:objective_destinations(native_key)`
- Produces: flat mission and quest menu rows whose `I` behavior is route start, route stop, or truthful instruction repeat

- [ ] **Step 1: Write failing Lua behavior tests**

Assert:

- Orcish Scouts expands to East and West Ronfaure kill rows;
- Fetichism retains separate lower and upper Palborough rows;
- an active quest expands exactly like a mission;
- order and counts are data-driven;
- a live-state-selected stage suppresses unrelated manual choices;
- instruction-only `I` does not start navigation;
- stale character, World, mission, quest, key-item, or inventory state blocks route start;
- changing characters cancels objective-owned routes only.

- [ ] **Step 2: Run and verify RED**

Run: `tools\test_mission_quest_navigation.ps1`

Expected: no shared quest expansion and no instruction-only row handling.

- [ ] **Step 3: Add shared guide access**

Replace `GuideState:mission_destinations` with `GuideState:objective_destinations`, retaining a compatibility alias for the existing generated build during migration. Return copied records so menu code cannot mutate guide state.

- [ ] **Step 4: Expand active objectives**

Generalize `expand_active_mission_destinations` into `expand_active_objective_destinations`. Preserve native identity fields, attach destination and guide-step IDs, and create stable speech labels. For exact points, copy source coordinates; for references, re-resolve the current unique target before starting.

- [ ] **Step 5: Implement `I` semantics**

Re-fetch the current active objective and exact destination by stable ID. Require current-session route evidence. Return `ready` only for verified movement; return an `instruction` mode with the complete action for instruction-only rows; return `blocked` for changed or unresolved evidence.

- [ ] **Step 6: Run focused tests and Lua syntax**

Run:

```powershell
tools\test_mission_quest_navigation.ps1
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_guides.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/accessxi_reader.lua
```

Expected: focused behavior and Lua 5.1 syntax pass.

- [ ] **Step 7: Commit**

```powershell
git add ashita/addons/accessxi_reader/accessxi_reader.lua ashita/addons/accessxi_reader/modules/mission_quest_guides.lua ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua tools/lua_tests/test_mission_quest_guides.lua tools/lua_tests/test_mission_quest_navigation.lua
git commit -m "feat: navigate ordered mission and quest steps"
```

### Task 6: Refresh both wiki corpora and regenerate all native contexts

**Files:**
- Modify: `data/mission-quest-guides/source-snapshot.json`
- Modify: `data/mission-quest-guides/reviewed-overrides.json`
- Modify: `data/mission-quest-guides/coverage.json`
- Modify: `data/mission-quest-guides/coverage.md`
- Modify: `data/mission-quest-guides/target-review.json`
- Modify: generated `ashita/addons/accessxi_reader/modules/mission_quest_*.lua`

**Interfaces:**
- Consumes: current installed FFXI DATs, BG Wiki API, FFXIclopedia API, reviewed overrides, route-evidence cache
- Produces: deterministic current source snapshot, generated Lua modules, and full coverage matrix

- [ ] **Step 1: Refresh complete source snapshots**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli all --repo-root . --ffxi-root 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI' --refresh
```

The importer must complete both sites atomically. A partial site refresh is discarded.

- [ ] **Step 2: Review source revision and match changes**

Run `git diff -- data/mission-quest-guides/source-snapshot.json data/mission-quest-guides/coverage.json`. Resolve changed exact matches through source-page evidence; never reuse a stale target override after its pinned revision changes.

- [ ] **Step 3: Generate route evidence and rebuild offline**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli routes --repo-root . --refresh
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli build --repo-root . --ffxi-root 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI' --offline
```

- [ ] **Step 4: Verify deterministic regeneration**

Hash generated data and Lua modules, rerun the same offline build, and assert the hashes do not change.

- [ ] **Step 5: Commit the refreshed corpus**

```powershell
git add data/mission-quest-guides ashita/addons/accessxi_reader/modules/mission_quest_*.lua
git commit -m "data: refresh complete objective guidance"
```

### Task 7: Drive every storyline and quest area to zero silent gaps

**Files:**
- Create: `tools/objective_guides/audit.py`
- Create: `tools/test_objective_coverage.py`
- Modify: `data/mission-quest-guides/reviewed-overrides.json`
- Modify: `data/mission-quest-guides/coverage.json`
- Modify: `data/mission-quest-guides/coverage.md`

**Interfaces:**
- Consumes: native classification, reconciled material steps, generated destinations and instructions
- Produces: per-context counts and a nonzero exit when any playable objective has no actionable entry or any material step disappears silently

- [ ] **Step 1: Write failing corpus-gate tests**

Assert the audit fails for a playable objective with zero actionable records, guide-only steps counted as navigation, a missing storyline, an unclassified native row, a stale override, or a silently omitted conflict. Assert it accepts explicitly classified instruction-only and conflict rows without treating them as routes.

- [ ] **Step 2: Run and verify RED**

Run: `tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_coverage -v`

Expected: audit module import failure.

- [ ] **Step 3: Implement the matrix and hard gate**

The mission matrix must contain exactly:

```text
San d'Oria; Bastok; Windurst; Rise of the Zilart; Chains of Promathia;
Assault; Treasures of Aht Urhgan; Campaign; Wings of the Goddess;
Seekers of Adoulin; Rhapsodies of Vana'diel; The Voracious Resurgence;
A Crystalline Prophecy; A Moogle Kupo d'Etat; A Shantotto Ascension
```

The quest matrix must contain exactly:

```text
sandoria; bastok; windurst; jeuno; other_areas; outlands; aht_urhgan;
crystal_war; abyssea; adoulin; coalition
```

For each context emit native, playable, routed, instruction-only, conflict,
unresolved, and no-actionable counts. Exit nonzero for a missing context,
unclassified row, unresolved material step, or playable no-actionable row.

- [ ] **Step 4: Resolve the generated review queue in fixed context order**

Process the mission matrix in the order above, then the quest matrix. For each
remaining row, compare both pinned source steps, current nav points, route probe,
and game-data identity. Add a revision-pinned override only when that evidence
resolves the exact target. Classify actual client sentinels with their native
record offsets and exclusion reason. Preserve real source conflicts visibly.

- [ ] **Step 5: Run the complete hard gate**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_coverage -v
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.audit --repo-root .
```

Expected: every required context is present, no playable objective has zero actionable entries, no material step is silently omitted, and no unresolved material step remains.

- [ ] **Step 6: Commit**

```powershell
git add tools/objective_guides/audit.py tools/test_objective_coverage.py data/mission-quest-guides/reviewed-overrides.json data/mission-quest-guides/coverage.json data/mission-quest-guides/coverage.md ashita/addons/accessxi_reader/modules/mission_quest_*.lua
git commit -m "data: complete mission and quest navigation coverage"
```

### Task 8: Validate, deploy, publish, and verify the updater payload

**Files:**
- Sync: `ashita/addons/accessxi_reader` to `C:\Users\buu42\Ashita\addons\accessxi_reader`
- Build: new `AccessXI-Ashita-Installer.zip`
- Publish: next GitHub release from merged `main`

**Interfaces:**
- Consumes: the complete tested branch
- Produces: live deployed addon and public latest-release payload consumed by the existing updater

- [ ] **Step 1: Run all focused and broad validation**

Run objective-guide, coverage, mission/quest runtime, zone search, transport,
navmesh, route-safety, hotkey, Lua 5.1, installer package, updater, public hygiene,
and `git diff --check` suites. Any failure blocks deployment.

- [ ] **Step 2: Sync only the canonical addon**

Use the repository deployment script or exact file copy from
`ashita/addons/accessxi_reader` to the live Ashita addon. Compare SHA-256 hashes
for every changed file. Do not modify unrelated addons.

- [ ] **Step 3: Reload and inspect the live log**

Verify the new build identifier loads, expansion contexts produce no `tonumber`
failure, Orcish Scouts exposes both confirmed kill choices, and objective rows
start or truthfully block according to current-session evidence.

- [ ] **Step 4: Package and test the updater payload**

Build a new `AccessXI-Ashita-Installer.zip`, retain the existing installer EXE
byte-for-byte, run package/updater/public-hygiene checks, and compare packaged
addon hashes to the tested repository files.

- [ ] **Step 5: Merge and release**

Push the branch, merge it to public `main`, publish the next non-prerelease tag,
and attach the new ZIP, unchanged EXE, and setup guide.

- [ ] **Step 6: Verify GitHub latest release**

Confirm the latest-release API returns the new tag, merged commit, exact asset
names, uploaded states, sizes, and SHA-256 digests. Download or compare the ZIP
digest so the updater path is proven, not assumed.
