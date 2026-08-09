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

### Task 2: Preserve typed source actions and generalize destination records

**Files:**
- Create: `tools/objective_guides/objective_destinations.py`
- Modify: `tools/objective_guides/model.py`
- Modify: `tools/objective_guides/wikitext.py`
- Modify: `tools/objective_guides/reconcile.py`
- Modify: `tools/objective_guides/generate_lua.py`
- Modify: `tools/test_objective_guides.py`

**Interfaces:**
- Consumes: `NativeObjective`, `ReconciledObjective`, both source-specific
  `ParsedObjective` records, current nav points, zone names, edges, route-contract
  index, and reviewed overrides
- Produces: ordered source-owned action spans, candidate-level reconciled claims,
  and `ReviewedObjectiveDestination` records in
  `reconciliation.objective_destinations`

- [ ] **Step 1: Write failing parser, reconciliation, and destination tests**

Add literal fixtures for:

```python
ReviewedObjectiveDestination(
    stable_id="mission:San d'Oria:1:destination:orcish-fodder-east-ronfaure",
    source_step_ids=("mission:San d'Oria:1:step-005",),
    action="obtain",
    items=("Orcish Axe",),
    enemies=("Orcish Fodder",),
    destination_id="camp:101:orcish-fodder:<fixture-hash>",
    zone=101,
    zone_name="East Ronfaure",
    label="Orcish Fodder camp in East Ronfaure",
    target_name="Orcish Fodder",
    target_kind="enemy",
    target_point=(123.0, 45.0, -2.0),
    arrival_instruction="Defeat Orcish Fodder until you obtain an Orcish Axe.",
)
```

Assert missions and quests share the same destination type, IDs include the
native key, unknown step IDs fail, stale source revisions fail, and destination
order is deterministic. Add a paired-source fixture where one source names the
target and the other names an unrelated zone; assert they remain separate claims
and cannot become one destination. Assert all reconciled rows, including
text-only `note` rows, enter the audit/review stream exactly once.

Add literal parser/reconciliation fixtures for:

- “Trade a Scholar Stone to the Task Delegator, then talk to the Task
  Delegator” producing ordered `trade` and `talk` spans;
- “Defeat Orcish Fodder to obtain an Orcish Axe” producing a fight target plus
  attached obtain-from relation rather than competing actions;
- “Kill Badshah and re-examine the ??? to obtain...” preserving fight, examine,
  and obtain semantics in order;
- prose/wikilink zone mentions, `Touch the Disturbed Dirt at (K-9)`, and a
  sparkling `???` in Sea Serpent Grotto retaining typed zone/object/grid facts;
- `H-8` versus `H-8/H-9` retaining corroborated `H-8` and source-only `H-9`
  instead of making the entire step a conflict;
- an unpaired step in a dual-source objective retaining alignment score and
  explicit unpaired reason;
- “Protect the Elvaan and Hume NPCs,” “touch the 6 Pips,” and a warning that
  leaving a battlefield loses a required key item all remaining material
  instruction/action rows, never generic context-only notes.

- [ ] **Step 2: Run the Python suite and verify RED**

Run: `tools\test_objective_guides.ps1`

Expected: import or attribute failure because `ReviewedObjectiveDestination` and `objective_destinations` do not exist.

- [ ] **Step 3: Add the additive typed action-span model**

Add an immutable `SourceActionSpan` that retains source step/order and text
range, exact supporting clause, ordered verb/relationship, target or role,
typed NPC/object/enemy/item/transport/zone mentions, temporal zone variant,
map/grid evidence, and result/item relation. Keep the scalar `SourceStep.action`
temporarily for generated-data compatibility, but derive new routing claims
only from the spans. Do not guess entity kinds from a matching nav name.

Extract exact zone mentions from source prose/wikilinks against the authoritative
zone-name catalogue, independently of generic linked entities. Conservatively
retain named unlinked targets after direct imperatives such as touch, examine,
or click as review candidates. A literal `???` gets its own target class.

- [ ] **Step 4: Reconcile candidates rather than scalar bags**

Align ordered action spans and persist per-source provenance, alignment score,
paired/unpaired reason, and candidate-level agreement. Normalize compatible
chains such as fight-to-obtain and trade-to-talk without losing order. For
zones/maps/grids/entities, keep intersections corroborated, source-only values
explicitly single-source, and only mutually exclusive immutable identities as
conflicts. Never silently union coordinates into an automatic candidate.

- [ ] **Step 5: Add the shared immutable destination model**

Move common destination fields out of the mission-only model and add:

```python
@dataclass(frozen=True, slots=True)
class ReviewedObjectiveDestination:
    stable_id: str
    source_step_ids: tuple[str, ...]
    action: str
    items: tuple[str, ...]
    enemies: tuple[str, ...]
    destination_id: str
    zone: int
    zone_name: str
    label: str
    target_name: str
    target_kind: str
    target_point: tuple[float, float, float] | None
    arrival_instruction: str
    eligibility: str = "catalogue"
    route_contract_id: str = ""
    canonical_ingress_edge_id: int = 0
    canonical_ingress_from_zone: int = 0
    transport_id: str = ""
    instruction_only: bool = False
```

Keep a temporary reader for existing `mission_destination_overrides`, but emit
only the shared runtime field. A legacy nonempty `route_evidence` string must be
ignored for eligibility and covered by a negative test.

- [ ] **Step 6: Emit shared Lua destination records and complete review rows**

Update reconciliation modules to write `objective_destinations = { ... }` for
both kinds. Preserve exact source revisions, step IDs, action, items, enemies,
immutable destination identity, target reference or exact point, ingress,
transport, eligibility, route-contract reference, and instruction-only status.
No free-text field can authorize movement.

Emit every reconciled stable step to the review/audit artifact with its typed
claims and provisional classification. Preserve compatibility fields only for
speech/current generated data; they are never route evidence.
`Context-only` requires a machine-readable, source-backed non-material reason;
missing entities or a parser fallback can never be that reason.

- [ ] **Step 7: Run the Python suite and verify GREEN**

Run: `tools\test_objective_guides.ps1`

Expected: all existing tests plus the new shared-model tests pass.

- [ ] **Step 8: Commit**

```powershell
git add tools/objective_guides/objective_destinations.py tools/objective_guides/model.py tools/objective_guides/wikitext.py tools/objective_guides/reconcile.py tools/objective_guides/generate_lua.py tools/test_objective_guides.py
git commit -m "feat: preserve typed objective actions"
```

### Task 3: Resolve every supported action class against current nav data

**Files:**
- Modify: `tools/objective_guides/objective_destinations.py`
- Modify: `tools/objective_guides/generate_lua.py`
- Modify: `tools/objective_guides/wikitext.py`
- Modify: `tools/test_objective_guides.py`

**Interfaces:**
- Consumes: independently parsed source-step claims and the current 34,567-point nav catalog
- Produces: `catalogue-candidate`, `instruction-only`, `context-only`,
  `conflict`, or `unresolved` records with explicit evidence reasons. Task 3
  cannot emit `routable`; only a current Task 4 contract can promote movement.

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
- single-source target plus independent exact nav/game-data corroboration;
- an explicit generic-role member set for San d'Orian gate guards, with
  Ambrotien, Endracion, and Grilau kept as exact separate choices;
- every text-only note classified once rather than omitted.

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
    "examine": ("npc", "object", "area"),
    "use": ("npc", "object", "area"),
    "fight": ("enemy",),
    "obtain": ("enemy",),
    "travel": ("area", "object"),
}
```

Require an exact target name plus exact zone from the same typed source claim.
Named NPCs must resolve to one point unless a revision-pinned role expands to an
explicit member set. Enemy camps may resolve to several exact points, but each
emitted point carries its exact coordinates and catalog-row fingerprint. `???`
requires exact reviewed coordinates or a live candidate-set identity. Global
name uniqueness, fuzzy matching, and first-row selection are never sufficient.

- [ ] **Step 4: Generate truthful action and arrival speech**

Use source items, enemies, and action without claiming completion. Keep distinct
item/enemy destinations separate. Emit instruction-only records for complete
nonmovement actions. Emit context-only notes to the audit stream without putting
them in the navigation browser only when a source-backed non-material reason is
recorded; unresolved action-like notes remain visible and fail the coverage
gate. Protect/touch/key-item-loss examples are explicit regression fixtures.
Never silently omit a reconciled row.

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

### Task 4: Pin directed route contracts for generated destinations

**Files:**
- Modify: `tools/navprobe/Program.cs`
- Create: `tools/objective_guides/route_evidence.py`
- Create: `tools/test_objective_route_evidence.py`
- Create: `data/mission-quest-guides/route-proof-policy.json`
- Create: `data/mission-quest-guides/route-evidence-v2.jsonl`
- Create: `data/mission-quest-guides/route-transitions.json`
- Create: `data/mission-quest-guides/route-transition-evidence-v2.jsonl`
- Create: `ashita/addons/accessxi_reader/modules/mission_quest_route_transitions.lua`
- Create: `ashita/addons/accessxi_reader/modules/mission_quest_route_policy.lua`
- Create: `ashita/addons/accessxi_reader/modules/mission_quest_route_contracts.lua`
- Modify: `tools/objective_guides/cli.py`
- Modify: `tools/objective_guides/objective_destinations.py`
- Modify: `tools/objective_guides/generate_lua.py`

**Interfaces:**
- Consumes: immutable destination instance, exact target-zone directed ingress,
  zone mesh, FFXINAV binary, transition registry, and exact-path probe protocol
- Produces: hash-bound directed local-leg evidence plus separately referenced
  transition evidence, and a Lua 5.1 runtime contract index; never a free-text
  authorization flag

- [ ] **Step 1: Write failing probe, evidence, and transition tests**

Use a fake JSONL probe boundary and literal responses. Assert rejection for:

- invalid start or `end_valid=false` even when the process exits `0` and returns
  one waypoint;
- zero/one waypoint, `FindClosestPath` fallback, snapped endpoints, non-finite
  or malformed waypoints, excessive segment length, excessive endpoint error,
  or inadequate endpoint clearance;
- changed mesh, FFXINAV, policy, destination-row, ingress-row, or transition hash;
- an ingress pointing at the wrong zone or an unproven reverse direction;
- a direct mesh line across a declared door, lift, ferry, one-way drop, or zone
  trigger without its transition contract;
- transition metadata with missing, stale, reverse-only, wrong-interaction, or
  wrong-post-state observed evidence;
- ambiguous same-name destination instances or a camp cluster spanning floors or
  exceeding its maximum diameter.

Assert multiple valid directed ingresses remain distinct evidence records and
that deterministic selection chooses the shortest eligible contract. Assert
shuffled input produces byte-identical output, duplicate probes coalesce, and a
worker failure rejects only that worker's unresolved legs. Store versioned
acceptance thresholds and cross-language literal pass/reject fixtures in the
route-proof policy so Python and Lua tests exercise the same predicate.

- [ ] **Step 2: Run and verify RED**

Run: `tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence -v`

Expected: module or exact-protocol failure.

- [ ] **Step 3: Add an exact JSONL probe mode**

Keep any existing diagnostic CLI compatibility, but add a long-lived batch mode
that loads one mesh per worker and calls only `FindPath`. It reports endpoint
validity, whether fallback was used, exact waypoints, endpoint errors, minimum
wall clearance, path length, mesh hash, and FFXINAV hash. `FindClosestPath` is
never called in proof mode. Exit status represents tool/protocol health only;
the JSON `status` field represents reachability.

Convert AccessXI `(x, z, y)` to navprobe `(x, y, z)` at the boundary.
Read every acceptance threshold from the committed versioned route-proof policy;
do not duplicate magic tolerances in the probe, generator, and runtime.

- [ ] **Step 4: Implement immutable destination and evidence identities**

NPC/object identities derive from their stable source IDs. Camp identities
derive from zone, source mob identity, sorted raw spawn IDs, and a versioned
bounded complete-link clustering policy. Preserve duplicate camps separately.

Each sorted JSONL local-leg evidence record pins schema/policy, destination ID, directed
ingress edge and target-zone endpoint, mesh hash, FFXINAV hash, probe protocol,
destination-row hash, ingress-row hash, transition-registry hash, and acceptance
observations. Missing or changed inputs make the record stale, never verified.

- [ ] **Step 5: Model stateful transitions separately**

Add reviewed transition definitions for the already verified Metalworks
elevators and Palborough lift first. Store directional observed proof in the
separate transition-evidence JSONL: exact pre/post anchors, interaction identity,
expected live state change, trace/source identity, policy and input hashes, and
timeout result. A definition without matching current `transition-proven`
evidence remains blocked. Doors, geysers, ferries, airships, battlefields,
ordinary zonelines, and other stateful crossings require the same evidence
boundary. A raw mesh path cannot bypass the registry.

- [ ] **Step 6: Add CLI generation and offline reuse**

Add `routes` to the CLI actions. `routes --refresh` recomputes only changed
hash-keyed legs, batching by loaded zone mesh; normal `build --offline` accepts
only matching evidence and complete transition contracts. Keep rejected records
with concise reasons for the review queue. Missing evidence leaves the
destination catalogue-only or unresolved. Generate a sorted
`mission_quest_route_contracts.lua` containing every accepted contract, its
expected external hashes, exact destination fields, authorized directed graph
prefix, local legs, and transition-proof references. Missing or duplicate
contract IDs fail generation. Also generate the addon-owned
`mission_quest_route_transitions.lua` containing only definitions with matching
current directional proof. The runtime never reads top-level repository JSON;
missing or stale addon transition modules fail closed. Generate
`mission_quest_route_policy.lua` from the same policy and literal fixtures used
by Python; byte/hash drift between the two representations fails the build.

- [ ] **Step 7: Verify the contracts and delicate-route guards**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence -v
tools\test_nav_mesh_endpoint_approach.ps1
tools\test_nav_lathine_shelf_escape.ps1
tools\test_nav_metalworks_elevator.ps1
```

Expected: exact evidence tests and all existing route-safety harnesses pass.

- [ ] **Step 8: Commit**

```powershell
git add tools/navprobe/Program.cs tools/objective_guides/route_evidence.py tools/objective_guides/cli.py tools/objective_guides/objective_destinations.py tools/objective_guides/generate_lua.py tools/test_objective_route_evidence.py data/mission-quest-guides/route-proof-policy.json data/mission-quest-guides/route-evidence-v2.jsonl data/mission-quest-guides/route-transitions.json data/mission-quest-guides/route-transition-evidence-v2.jsonl ashita/addons/accessxi_reader/modules/mission_quest_route_policy.lua ashita/addons/accessxi_reader/modules/mission_quest_route_transitions.lua ashita/addons/accessxi_reader/modules/mission_quest_route_contracts.lua
git commit -m "feat: verify objective route contracts"
```

### Task 5: Expose flat actionable steps in both runtime categories

**Files:**
- Create: `ashita/addons/accessxi_reader/modules/accessxi_sha256.lua`
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
- matching disk-restored mission `0x056`, key-item `0x055`, quest, or inventory
  values still block without current-session packet provenance and session epoch;
- changed destination, mesh, DLL, policy, ingress, or transition hashes block route start;
- a missing runtime contract index, missing contract ID, or legacy free-text
  `route_evidence` blocks movement;
- the objective-only zone BFS rejects every `observed`/`untested` prefix edge,
  including an unproven edge before a proven final ingress;
- an exact ingress and proven post-transition anchor work, while an arbitrary
  same-floor start, disconnected component, or wrong floor cannot reuse an
  ingress proof or bypass a required lift/door/transport stage;
- the Lua exact-leg predicate consumes the generated policy and rejects invalid
  start/end, zero/one waypoint, fallback use, non-finite/malformed/wrong-zone
  waypoints, excessive segment length, endpoint error, inadequate clearance,
  and transition-corridor crossings using the same literal fixtures as Python;
- same-name/different-World change during selection or an active route clears
  the selection and cancels objective-owned routes only, leaving ordinary
  navigation untouched.

- [ ] **Step 2: Run and verify RED**

Run: `tools\test_mission_quest_navigation.ps1`

Expected: no shared quest expansion and no instruction-only row handling.

- [ ] **Step 3: Add shared guide access**

Replace `GuideState:mission_destinations` with `GuideState:objective_destinations`, retaining a compatibility alias for the existing generated build during migration. Return copied records so menu code cannot mutate guide state.

- [ ] **Step 4: Expand active objectives**

Generalize `expand_active_mission_destinations` into `expand_active_objective_destinations`. Preserve native identity fields, attach destination and guide-step IDs, and create stable speech labels. For exact points, copy source coordinates; for references, re-resolve the current unique target before starting.

- [ ] **Step 5: Load and validate the runtime contract index**

Load the generated Lua 5.1 contract module fail-closed. Add a bundled streaming
SHA-256 implementation using LuaJIT's bit operations and test it against fixed
vectors. Cache hashes for the current add-on session, but hash the actual loaded
FFXINAV DLL, zone mesh, destination TSV, graph TSV, and generated transition
artifact before authorizing their contracts. Compare current destination,
ingress, and transition fields exactly to the contract index. Packaging tests
must prove the installed copies and generated policy, transition, and contract
modules are the tested copies. A missing/malformed/stale transition module or
policy revision blocks movement.

- [ ] **Step 6: Implement `I` semantics and contract enforcement**

Re-fetch the current active objective and exact immutable destination by stable
ID. Re-resolve and validate its complete route contract at start and before
every transition. Return `ready` only for a current directed local leg plus all
required transition stages; return an `instruction` mode with the complete
action for instruction-only rows; return `blocked` for changed, stale,
ambiguous, or unresolved evidence. Suspend ordinary replanning while a
transition is in progress, and resume only after its expected post-state and
post-anchor are observed. Never substitute a direct mesh route for a required
transition.

Objective-owned same-zone movement uses an exact runtime path helper:
`IsValidPosition` for both endpoints, `FindPath` only, at least two finite
waypoints, and the complete generated policy predicate: endpoint error and
clearance, finite/path-zone-valid waypoints, maximum segment length, and
transition-corridor classification. It never calls the ordinary
`FindClosestPath` fallback. Python and Lua run the same versioned literal
pass/reject fixtures. An arbitrary current position needs its own accepted
dynamic exact leg or a proven current-start anchor; it cannot inherit
canonical-ingress evidence.

- [ ] **Step 7: Run focused tests and Lua syntax**

Run:

```powershell
tools\test_mission_quest_navigation.ps1
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_guides.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/accessxi_sha256.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_policy.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_transitions.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_contracts.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/accessxi_reader.lua
```

Expected: focused behavior and Lua 5.1 syntax pass.

- [ ] **Step 8: Commit**

```powershell
git add ashita/addons/accessxi_reader/accessxi_reader.lua ashita/addons/accessxi_reader/modules/accessxi_sha256.lua ashita/addons/accessxi_reader/modules/mission_quest_guides.lua ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua tools/lua_tests/test_mission_quest_guides.lua tools/lua_tests/test_mission_quest_navigation.lua
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

Assert the audit fails for a playable objective with zero actionable records,
guide-only steps counted as navigation, a missing storyline, an unclassified
native row, a stale override, a reconciled row missing from the audit, a silent
conflict, or an automatic entry with a missing/stale runtime contract. Assert it
accepts explicitly classified instruction-only, context-only, and conflict rows
without treating them as routes, but assert a material conflict blocks the
`complete` release claim. Every reconciled stable step must appear exactly once.
Reject `context-only` without an allowed machine-readable non-material reason
and reject action-like protect/touch/key-item-loss fixtures misclassified as
context.

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

For each context emit native classification and source coverage, material-step
counts by routable/instruction-only/context-only/conflict/unresolved,
target-evidence-complete, same-zone-routable, cross-zone-routable,
automatic-stage-supported, and no-actionable counts. Exit nonzero for a missing
context, unclassified row, omitted reconciled row, unresolved material step, or
material conflict, or playable no-actionable row. One accepted target cannot
hide other unresolved or conflicted steps in the same objective.

- [ ] **Step 4: Resolve the generated review queue to a fixed point**

Process the mission matrix in the order above, then the quest matrix. For each
remaining row, compare both pinned source steps, current nav points, route probe,
and game-data identity. Add a revision-pinned override only when that evidence
resolves the exact target. Classify actual client sentinels with their native
record offsets and exclusion reason. Preserve real source conflicts visibly.

After every override/classification batch, rerun `routes --refresh`, rebuild the
generated Lua offline, and rerun the audit. Continue until another iteration
produces byte-identical corpus, evidence, runtime contracts, and audit artifacts.
The gate must prove every override appears in the current output and every
automatic entry resolves a current runtime contract.

- [ ] **Step 5: Run the complete hard gate**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_coverage -v
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli routes --repo-root . --refresh
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli build --repo-root . --ffxi-root 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI' --offline
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.audit --repo-root .
```

Expected: every required context is present, no playable objective has zero
actionable entries, every reconciled row is classified exactly once, every
automatic entry has a current runtime contract, no material step is silently
omitted, and no unresolved or conflicted material step remains. A second
fixed-point iteration must make no changes.

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
and `git diff --check` suites. Include fixed SHA-256 vectors, installed-file hash
mismatch rejection, runtime contract/index lookup, exact objective-path mode,
and legacy free-text non-promotion. Any failure blocks deployment.

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
addon hashes to the tested repository files. Assert the ZIP includes the exact
tested SHA-256 module, runtime contract index, transition and route-policy Lua
modules, destination TSV, graph TSV, FFXINAV DLL, and every
referenced zone mesh; no contract may reference an absent or hash-mismatched
packaged file.

- [ ] **Step 5: Merge and release**

Push the branch, merge it to public `main`, publish the next non-prerelease tag,
and attach the new ZIP, unchanged EXE, and setup guide.

- [ ] **Step 6: Verify GitHub latest release**

Confirm the latest-release API returns the new tag, merged commit, exact asset
names, uploaded states, sizes, and SHA-256 digests. Download or compare the ZIP
digest so the updater path is proven, not assumed.
