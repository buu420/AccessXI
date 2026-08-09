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
- Modify: `tools/generate_nav_zoneline_destinations.py`
- Create: `tools/test_nav_destination_generator.py`
- Modify: `tools/objective_guides/objective_destinations.py`
- Modify: `tools/objective_guides/mission_destinations.py`
- Modify: `tools/objective_guides/cli.py`
- Modify: `tools/objective_guides/reconcile.py`
- Modify: `tools/objective_guides/generate_lua.py`
- Modify: `tools/objective_guides/wikitext.py`
- Modify: `tools/test_objective_guides.py`
- Create: `tools/test_nav_destination_schema.ps1`
- Create: `tools/lua_tests/test_nav_destination_schema.lua`
- Modify: `data/mission-quest-guides/reviewed-overrides.json`
- Modify: `data/ffxi-nav-destinations.tsv`
- Modify: `ashita/addons/accessxi_reader/data/ffxi-nav-destinations.tsv`

**Interfaces:**
- Consumes: Task 2 reconciled action identities/source-owned claims and the
  current navigation catalogue enriched with raw source identity
- Produces: one action-resolution ledger row per reconciled action plus zero or
  more immutable destination candidates. Ledger status is exactly one of
  `catalogue-candidate`, `instruction-only`, `context-only`, `conflict`, or
  `unresolved`, with an enum evidence reason. Task 3 cannot emit `routable`;
  only a current Task 4 contract can promote a candidate.

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

Add navigation-identity fixtures proving:

- legacy 7-column, current 9-column, and appended identity schemas all parse
  without changing the first nine fields, both in Python and through the actual
  ordinary-navigation Lua loader;
- NPC/object/area rows retain exact raw source IDs;
- enemy rows retain sorted raw spawn IDs and a versioned bounded complete-link
  cluster identity; a chain of near spawns cannot bridge an oversized camp or
  merge floors;
- missing appended identity leaves a row discoverable to ordinary navigation
  but ineligible as an immutable objective candidate.

For Orcish Scouts, assert exactly two initial zone candidate groups. West
Ronfaure is named by both objective walkthroughs; East Ronfaure is named by BG
Wiki and independently corroborated by raw game-data identities. Do not silently
add the other single-source zones without the same evidence review:

```python
self.assertEqual([group.zone_name for group in groups], ["East Ronfaure", "West Ronfaure"])
```

Do not inherit the old single-link camp counts. On a fixed raw-spawn fixture,
assert every expected East/West raw spawn ID appears exactly once, every cluster
satisfies the versioned diameter/floor bounds, and shuffled input produces the
same clusters and IDs. Pin counts only to the output proven by that fixture.
Every resulting camp identity remains in its group; no first camp is selected.
Assert no East Ronfaure [S], Fort Ghelsba, Ghelsba Outpost, or La Theine
candidate is silently admitted. The latter two remain separately reviewable
under the same single-source-plus-independent-data rule used for East.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_nav_destination_generator -v
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides.ObjectiveDestinationTests -v
```

Expected: the resolver supports only the existing mission farming override and named-NPC review path.

- [ ] **Step 3: Add immutable navigation source identities**

Append optional fields after the existing nine TSV fields:

```text
destination_id  raw_identity  raw_spawn_ids  cluster_policy_version
```

NPC/object/area IDs derive from kind, zone, and exact raw source record ID.
Enemy camp IDs derive from zone, source mob identity/name, sorted raw spawn IDs,
and a versioned bounded complete-link policy. Preserve `mobid` before clustering
and retain every member ID. Rows without those fields remain usable by ordinary
navigation but identity-unavailable to this resolver. Regenerate repository and
addon TSV copies together and assert their hashes match.

Use an explicit static identity schema revision in canonical IDs, for example
`npc:v1:<zone>:<raw-id>`. Golden tests prove NPC/object/area IDs are stable when
coordinates or display metadata change and change when the identity-schema
revision changes. `cluster_policy_version` separately versions enemy geometry.

- [ ] **Step 4: Add the exact action-resolution ledger**

Key the ledger by Task 2 reconciled action ID, not the old scalar step. Assert:

```text
set(reconciled_action_ids) == set(ledger.action_id)
each ledger.action_id occurs exactly once
each source_action_span_id belongs to exactly one reconciled action
candidate IDs are unique
each candidate has exactly one existing parent action_id
catalogue-candidate rows have one or more children
all other statuses have zero movement children
```

No candidate may be orphaned, multiply owned, or supported by a source span
outside its parent reconciled action. Candidates are child records and never
duplicate the primary ledger row. Use
stable reason enums such as `missing-action-target`, `missing-zone`,
`no-exact-catalogue-match`, `ambiguous-static-reference`,
`dynamic-identity-required`, `source-conflict`,
`single-source-needs-independent-corroboration`,
`transport-metadata-required`, `complete-instruction`, and
`non-material-context-reason`.

- [ ] **Step 5: Implement target classification against typed claims**

Select only actual catalogue kinds by typed action:

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
explicit immutable member set. Add a `role_overrides` entry for San d'Orian gate
guards, revision-pinned to Ambrotien, Endracion, and Grilau. Enemy camps retain
every exact immutable instance in a zone group. `???` requires exact reviewed
coordinates or a current live candidate-set identity. Battlefield and transport
are typed metadata classes which may reference `object`/`area`/`npc` rows; they
are not invented TSV kinds. Global name uniqueness, fuzzy matching, coordinate
proximity, and first-row selection are never sufficient.

Dual-source target/zone/relationship agreement yields a catalogue candidate.
One source plus raw identity-pinned independent game data may yield a candidate
only when the other source does not contradict it. Preserve per-candidate source
support and partial coordinate agreement.

- [ ] **Step 6: Generate truthful action, classification, and speech**

Use source items, enemies, and action without claiming completion. Keep distinct
item/enemy destinations separate. Emit instruction-only records for complete
nonmovement actions. Emit context-only notes to the audit stream without putting
them in the navigation browser only when a source-backed non-material reason is
recorded; unresolved action-like notes remain visible and fail the coverage
gate. Protect/touch/key-item-loss examples are explicit regression fixtures.
Never silently omit a reconciled row.

Reduce `mission_destinations.py` to a compatibility adapter over the same
catalogue-only resolver (or remove its public resolver if no callers remain).
A direct regression invokes the legacy entry point and proves nonempty
`route_evidence`, `confidence`, or ingress fields cannot authorize movement.

- [ ] **Step 7: Run focused resolver, schema, and complete generator suites**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides.ObjectiveDestinationTests -v
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_nav_destination_generator -v
tools\test_nav_destination_schema.ps1
tools\test_objective_guides.ps1
```

Expected: every new action-class test, the actual Lua loader schema regression,
and the complete generator suite pass.

- [ ] **Step 8: Commit**

```powershell
git add tools/generate_nav_zoneline_destinations.py tools/test_nav_destination_generator.py tools/objective_guides/objective_destinations.py tools/objective_guides/mission_destinations.py tools/objective_guides/cli.py tools/objective_guides/reconcile.py tools/objective_guides/generate_lua.py tools/objective_guides/wikitext.py tools/test_objective_guides.py tools/test_nav_destination_schema.ps1 tools/lua_tests/test_nav_destination_schema.lua data/mission-quest-guides/reviewed-overrides.json data/ffxi-nav-destinations.tsv ashita/addons/accessxi_reader/data/ffxi-nav-destinations.tsv
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
- Create: `ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv`
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
  transition evidence, a Lua 5.1 runtime contract index, and a canonical plain
  data runtime manifest; never a free-text authorization flag

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
- a runtime manifest that contains itself, repeats/omits an artifact, contains
  rooted or parent-traversal paths, or changes bytes without changing the
  independently expected root digest;
- a coordinated replacement of policy/transition/contract module fixture bytes
  whose hashes do not match the separately expected manifest digest.

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
the Python caller passes the selected policy values in each JSONL request. Do
not duplicate magic tolerances in the probe, generator, and runtime. Accept an
explicit `--third-party-root` defaulting to `<repo>/third_party`; validate the
canonical FFXINAV/mesh paths stay below it. Never create or mutate a dependency
mirror as a test side effect.

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

Generate `ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv`
as deterministic plain data,
not executable Lua. It contains addon-relative paths and SHA-256 values for the
policy, transition, contract module, destination TSV, graph TSV, exact FFXINAV
DLL, and every referenced mesh. The manifest never contains itself. Emit its
exact SHA-256 separately for Task 5 to pin in non-generated reader code; that
pin is the pre-load drift/corruption root. Reject rooted/parent-traversal
fragments, duplicate or omitted required artifacts, and a mesh name/zone
mismatch during generation. Tests define the exact TSV canonical bytes and
prove changing any child artifact changes the rooted manifest digest. Hash the
addon-owned destination and graph TSV bytes which production will parse, and
resolve every declared path through a fixture using the actual addon-root shape.

Expose an explicit CLI `--update-runtime-pin` operation which replaces exactly
one marked manifest-digest literal in a caller-supplied reader path after every
child artifact and the final manifest have reached their deterministic bytes.
Zero or multiple markers fail without writing. Normal offline builds report the
digest but do not mutate non-generated code. A `--runtime-ready` gate additionally
requires the Task 5 route-runtime module as a hashed manifest child; Task 4 can
exercise generation before that child exists, but cannot claim runtime-ready.

The threat boundary is accidental/stale/coordinated artifact drift, not a
malicious local actor who can rewrite bootstrap code. The explicit trusted
computing base is the non-generated reader's minimal byte verifier plus
`accessxi_sha256.lua`; release/package tests pin their source-to-payload hashes,
and syntax/vector/smoke failure disables objective movement. The route-runtime
module is not bootstrap code: Task 5 adds it as a rooted manifest child before
loading it. Generated Lua never supplies its own expected hash and never
executes before its exact bytes are checked against this independently pinned
manifest.

- [ ] **Step 7: Verify the contracts and delicate-route guards**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence -v
tools\test_nav_mesh_endpoint_approach.ps1
tools\test_nav_lathine_shelf_escape.ps1
tools\test_nav_metalworks_elevator.ps1
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_policy.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_transitions.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_contracts.lua
git diff --check
```

Expected: exact evidence tests and all existing route-safety harnesses pass.
Also run a bounded native integration fixture against the worktree-local ignored
dependencies: invalid end with process exit `0`, exact `FindPath` zero
waypoints, and one known valid two-plus-waypoint leg. If dependencies are absent,
report that prerequisite explicitly while keeping all pure Python tests active.

- [ ] **Step 8: Commit**

```powershell
git add tools/navprobe/Program.cs tools/objective_guides/route_evidence.py tools/objective_guides/cli.py tools/objective_guides/objective_destinations.py tools/objective_guides/generate_lua.py tools/test_objective_route_evidence.py data/mission-quest-guides/route-proof-policy.json data/mission-quest-guides/route-evidence-v2.jsonl data/mission-quest-guides/route-transitions.json data/mission-quest-guides/route-transition-evidence-v2.jsonl ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv ashita/addons/accessxi_reader/modules/mission_quest_route_policy.lua ashita/addons/accessxi_reader/modules/mission_quest_route_transitions.lua ashita/addons/accessxi_reader/modules/mission_quest_route_contracts.lua
git commit -m "feat: verify objective route contracts"
```

### Task 5: Expose flat actionable steps in both runtime categories

**Files:**
- Create: `ashita/addons/accessxi_reader/modules/accessxi_sha256.lua`
- Create: `ashita/addons/accessxi_reader/modules/mission_quest_route_runtime.lua`
- Modify: `ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv`
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_guides.lua`
- Modify: `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/modules/metalworks_elevator_navigation.lua`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Create: `tools/lua_tests/test_accessxi_sha256.lua`
- Create: `tools/test_accessxi_sha256.ps1`
- Create: `tools/lua_tests/test_mission_quest_route_runtime.lua`
- Create: `tools/test_mission_quest_route_runtime.ps1`
- Modify: `tools/lua_tests/test_mission_quest_guides.lua`
- Modify: `tools/lua_tests/test_mission_quest_navigation.lua`
- Modify: `tools/test_nav_metalworks_elevator.ps1`

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
- the manifest hash is pinned outside generated artifacts; manifest bytes are
  checked before parsing, and each generated Lua file is read, hashed, and
  loaded from those same accepted bytes before any module code can execute;
- a mismatched generated-Lua fixture which would set a flag if executed is
  rejected with the flag still unset;
- ordinary-navigation-first native loading is recorded as trusted only when the
  integrity observer was already active; same-mesh reuse, DLL/mesh replacement
  after load, or a failed exact stat blocks objective use without breaking
  ordinary navigation;
- a missing runtime contract index, missing contract ID, or legacy free-text
  `route_evidence` blocks movement;
- the objective-only zone BFS rejects every `observed`/`untested` prefix edge,
  including an unproven edge before a proven final ingress;
- the separate objective BFS handles reverse-only edges, cycles, and shuffled
  input deterministically, revalidates every directed prefix edge, and never
  calls the permissive ordinary BFS;
- an exact ingress and proven post-transition anchor work, while an arbitrary
  same-floor start, disconnected component, or wrong floor cannot reuse an
  ingress proof or bypass a required lift/door/transport stage;
- the Lua exact-leg predicate consumes the generated policy and rejects invalid
  start/end, zero/one waypoint, fallback use, non-finite/malformed/wrong-zone
  waypoints, excessive segment length, endpoint error, inadequate clearance,
  and transition-corridor crossings using the same literal fixtures as Python;
- native spies prove an objective leg calls `IsValidPosition` and clearance
  checks, then exactly one `FindPath`, immediately consumes `Get_WayPoints`, and
  calls `FindClosestPath` zero times; a control ordinary route retains the
  existing permissive helper;
- same-name/different-World change during selection or an active route clears
  the selection and cancels objective-owned routes only, leaving ordinary
  navigation untouched.
- an objective elevator/lift stage is bound to owner name/native World ID,
  session epoch, objective/stage/destination/contract identity, transition
  direction/revision/hash, exact pre/post anchors, and expected live state;
  wrong interaction/state/anchor, timeout, or any mid-transition identity/hash
  change cancels only the objective route while ordinary elevator behavior is
  unchanged.

- [ ] **Step 2: Run and verify RED**

Run:

```powershell
tools\test_accessxi_sha256.ps1
tools\test_mission_quest_route_runtime.ps1
tools\test_mission_quest_navigation.ps1
tools\test_nav_metalworks_elevator.ps1
```

Expected: the SHA/runtime harnesses are missing, no shared quest expansion or
instruction-only row handling exists, and the elevator lacks objective-owned
authorization state.

- [ ] **Step 3: Add shared guide access**

Replace `GuideState:mission_destinations` with `GuideState:objective_destinations`, retaining a compatibility alias for the existing generated build during migration. Return copied records so menu code cannot mutate guide state.

- [ ] **Step 4: Expand active objectives**

Generalize `expand_active_mission_destinations` into `expand_active_objective_destinations`. Preserve native identity fields, attach destination and guide-step IDs, and create stable speech labels. For exact points, copy source coordinates; for references, re-resolve the current unique target before starting.

- [ ] **Step 5: Load and validate the runtime contract index**

Pin the exact Task 4 manifest SHA-256 in a non-generated reader constant. Read
the plain manifest bytes once, hash them, and parse that same accepted string.
For each generated Lua artifact,
read its exact bytes once, compare those bytes to the rooted manifest, then
`loadstring` and execute only that accepted byte string; never call `loadfile`
first. Reject malformed/duplicate/missing manifest rows and schema/revision
drift. A missing/malformed/stale policy, transition, contract, or manifest
blocks objective movement.

After the route-runtime module and the single reader marker exist, execute the
first real pin checkpoint explicitly:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli manifest --repo-root . --runtime-ready --update-runtime-pin ashita/addons/accessxi_reader/accessxi_reader.lua
```

Reparse the one marker and independently hash the exact addon-owned manifest
bytes in the focused harness. `--runtime-ready` also proves the route-runtime
module is a rooted child before the reader may load it.

Add a bundled streaming SHA-256 implementation using LuaJIT's bit operations.
Its dedicated plain-Lua harness supplies the complete deterministic bit shim and
runs the NIST empty, `abc`, long-message, million-`a`, binary `00..ff`, and every
0..63 block-remainder vector. Test missing/partial/synthetic read failures and
cache hits/invalidations. Define an injected production `accessxi_file_stat`
which returns file-size high/low and FILETIME high/low as exact 32-bit words.
Stat before and after streaming; cache only by canonical full path plus all four
words, never cache failures or a file that changes during the read. At live
addon load, smoke-test LuaJIT `bit` and the `abc` vector; failure leaves ordinary
navigation available but disables objective movement for that session.

Install the integrity observer before any navigation load. Immediately before
the first existing `ffi.load`, record canonical DLL path, rooted digest, and
exact stat identity; immediately before every `LoadMesh`, do the same for that
mesh. If ordinary navigation reaches either seam without a working rooted
observer, record the loaded identity as untrusted for objective use rather than
retroactively blessing it. Recheck recorded stat identity before every
objective native call, including the existing same-mesh fast path. Hash only
the active contract's DLL/mesh, destination TSV, graph TSV, and generated
artifacts—not the full mesh directory. Compare current destination, ingress,
and transition fields exactly to the accepted contract index.

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

Implement `accessxi.nav_objective_proven_zoneline_path` separately from ordinary
`nav_zoneline_path`. Filter adjacency before enqueue: only exact directed rows
whose current row/hash is `proven`, or whose reviewed transition contract is
currently eligible, may enter the queue. Use deterministic ordering and a
visited set, then revalidate every prefix and final edge against the same
contract snapshot. Objective code never calls the ordinary BFS; ordinary
navigation remains unchanged.

Objective-owned same-zone movement uses a separately named and injected
`accessxi.nav_compute_exact_objective_leg`. Keep ordinary
`nav_compute_mesh_route` behavior unchanged. The exact helper checks
`IsValidPosition` and clearance for both endpoints, calls `FindPath` exactly
once and never `FindClosestPath`, consumes that call's waypoints immediately,
requires at least two finite points, then applies the complete generated policy:
requested endpoint error, finite/path-zone-valid waypoints, maximum segment
length, clearance, and transition-corridor classification. Python and Lua run
the same versioned literal pass/reject fixtures. An arbitrary current position
needs its own accepted dynamic exact leg or a proven current-start anchor; it
cannot inherit canonical-ingress evidence.

Add an objective-only mode to `metalworks_elevator_navigation.lua` rather than
reusing its generic state anonymously. It receives the exact helper and a full
authorization snapshot: owner name/native World ID, session epoch,
objective/stage/destination/contract IDs, transition direction/revision/hash,
exact pre/post anchors, expected live state, and timeout. Revalidate on every
poll, suspend only the objective replanner, and resume only after both post-state
and post-anchor. Any mismatch cancels only the objective route. Objective mode
never calls the permissive path helper; ordinary Metalworks/Palborough elevator
behavior remains unchanged.

- [ ] **Step 7: Run focused tests and Lua syntax**

Run:

```powershell
tools\test_accessxi_sha256.ps1
tools\test_mission_quest_route_runtime.ps1
tools\test_mission_quest_navigation.ps1
tools\test_nav_metalworks_elevator.ps1
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_guides.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/accessxi_sha256.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_runtime.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_policy.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_transitions.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/mission_quest_route_contracts.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/modules/metalworks_elevator_navigation.lua
tools\check_lua51_syntax.ps1 ashita/addons/accessxi_reader/accessxi_reader.lua
git diff --check
```

Expected: focused behavior and Lua 5.1 syntax pass.

- [ ] **Step 8: Commit**

```powershell
git add ashita/addons/accessxi_reader/accessxi_reader.lua ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv ashita/addons/accessxi_reader/modules/accessxi_sha256.lua ashita/addons/accessxi_reader/modules/mission_quest_route_runtime.lua ashita/addons/accessxi_reader/modules/mission_quest_guides.lua ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua ashita/addons/accessxi_reader/modules/metalworks_elevator_navigation.lua tools/lua_tests/test_accessxi_sha256.lua tools/test_accessxi_sha256.ps1 tools/lua_tests/test_mission_quest_route_runtime.lua tools/test_mission_quest_route_runtime.ps1 tools/lua_tests/test_mission_quest_guides.lua tools/lua_tests/test_mission_quest_navigation.lua tools/test_nav_metalworks_elevator.ps1
git commit -m "feat: navigate ordered mission and quest steps"
```

### Task 6: Refresh both wiki corpora and regenerate all native contexts

**Files:**
- Modify: `data/mission-quest-guides/source-snapshot.json`
- Modify: `data/mission-quest-guides/reviewed-overrides.json`
- Modify: `data/mission-quest-guides/coverage.json`
- Modify: `data/mission-quest-guides/coverage.md`
- Modify: `data/mission-quest-guides/target-review.json`
- Modify: `data/mission-quest-guides/route-evidence-v2.jsonl`
- Modify: `data/mission-quest-guides/route-transitions.json` when transition review changes
- Modify: `data/mission-quest-guides/route-transition-evidence-v2.jsonl` when transition review changes
- Modify: `ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv`
- Modify: generated `ashita/addons/accessxi_reader/modules/mission_quest_*.lua`
- Modify: the marked manifest-digest literal in `ashita/addons/accessxi_reader/accessxi_reader.lua`

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
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli manifest --repo-root . --runtime-ready --update-runtime-pin ashita/addons/accessxi_reader/accessxi_reader.lua
```

- [ ] **Step 4: Verify deterministic regeneration**

Hash generated data, manifest, Lua modules, and the pinned reader, rerun the same
offline build plus explicit pin update, and assert the hashes do not change.
Reparse the reader marker and prove it equals the exact manifest bytes.

- [ ] **Step 5: Commit the refreshed corpus**

```powershell
git add data/mission-quest-guides ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv ashita/addons/accessxi_reader/modules/mission_quest_*.lua ashita/addons/accessxi_reader/accessxi_reader.lua
git commit -m "data: refresh complete objective guidance"
```

### Task 7: Drive every storyline and quest area to zero silent gaps

**Files:**
- Create: `tools/objective_guides/audit.py`
- Create: `tools/test_objective_coverage.py`
- Modify: `data/mission-quest-guides/reviewed-overrides.json`
- Modify: `data/mission-quest-guides/coverage.json`
- Modify: `data/mission-quest-guides/coverage.md`
- Modify: `data/mission-quest-guides/target-review.json`
- Modify: `data/mission-quest-guides/route-evidence-v2.jsonl`
- Modify: `data/mission-quest-guides/route-transitions.json` when transition review changes
- Modify: `data/mission-quest-guides/route-transition-evidence-v2.jsonl` when transition review changes
- Modify: `ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv`
- Modify: generated `ashita/addons/accessxi_reader/modules/mission_quest_*.lua`
- Modify: the marked manifest-digest literal in `ashita/addons/accessxi_reader/accessxi_reader.lua`

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
generated Lua offline, regenerate the runtime-ready addon manifest, update the
single reader pin, and rerun the audit. Continue until another iteration
produces byte-identical corpus, evidence, runtime contracts, manifest, reader
pin, and audit artifacts.
The gate must prove every override appears in the current output and every
automatic entry resolves a current runtime contract.

- [ ] **Step 5: Run the complete hard gate**

Run:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_coverage -v
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli routes --repo-root . --refresh
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli build --repo-root . --ffxi-root 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI' --offline
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli manifest --repo-root . --runtime-ready --update-runtime-pin ashita/addons/accessxi_reader/accessxi_reader.lua
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.audit --repo-root .
```

Expected: every required context is present, no playable objective has zero
actionable entries, every reconciled row is classified exactly once, every
automatic entry has a current runtime contract, no material step is silently
omitted, and no unresolved or conflicted material step remains. A second
fixed-point iteration must make no changes.

- [ ] **Step 6: Commit**

```powershell
git add tools/objective_guides/audit.py tools/test_objective_coverage.py data/mission-quest-guides/reviewed-overrides.json data/mission-quest-guides/coverage.json data/mission-quest-guides/coverage.md data/mission-quest-guides/target-review.json data/mission-quest-guides/route-evidence-v2.jsonl data/mission-quest-guides/route-transitions.json data/mission-quest-guides/route-transition-evidence-v2.jsonl ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv ashita/addons/accessxi_reader/modules/mission_quest_*.lua ashita/addons/accessxi_reader/accessxi_reader.lua
git commit -m "data: complete mission and quest navigation coverage"
```

### Task 8: Validate, deploy, publish, and verify the updater payload

**Files:**
- Modify: `tools/package_accessxi_installer.ps1`
- Modify: `tools/test_accessxi_installer_package.ps1`
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
start or truthfully block according to current-session evidence. Require the
one-time production LuaJIT `bit` plus SHA-256 `abc` smoke result in the live log;
failure blocks objective movement and release.

- [ ] **Step 4: Package and test the updater payload**

Build a new `AccessXI-Ashita-Installer.zip`, retain the existing installer EXE
byte-for-byte, run package/updater/public-hygiene checks, and compare packaged
addon hashes to the tested repository files. Assert the ZIP includes the exact
tested SHA-256 and route-runtime modules, independently rooted plain manifest,
runtime contract index, transition and route-policy Lua modules, destination
TSV, graph TSV, FFXINAV DLL, and every referenced zone mesh. Extend the package
manifest and test to SHA-256-compare source versus payload for each artifact.
Parse every declared relative path, reject rooted/traversal/canonical escape,
and require the reader's pinned manifest digest to match the packaged manifest.
No contract may reference an absent or hash-mismatched packaged file.

- [ ] **Step 5: Commit package-integrity changes**

```powershell
git add tools/package_accessxi_installer.ps1 tools/test_accessxi_installer_package.ps1
git commit -m "build: verify objective route payload integrity"
```

- [ ] **Step 6: Merge and release**

Push the branch, merge it to public `main`, publish the next non-prerelease tag,
and attach the new ZIP, unchanged EXE, and setup guide.

- [ ] **Step 7: Verify GitHub latest release**

Confirm the latest-release API returns the new tag, merged commit, exact asset
names, uploaded states, sizes, and SHA-256 digests. Download or compare the ZIP
digest so the updater path is proven, not assumed.
