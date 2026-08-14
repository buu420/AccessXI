# Task 2 report — wiki-authoritative progression RED contract

## Scope

This test-only slice is based on Task 1 commit `3d97593` and changes only:

- `tools/lua_tests/test_mission_quest_guides.lua`
- `tools/lua_tests/test_mission_quest_navigation.lua`
- `tools/lua_tests/test_mission_quest_reader_runtime_integration.lua`
- `.superpowers/sdd/2026-08-13-wiki-authoritative-objective-progression/task-2-report.md`

No reader, navigation, guide runtime, generated shard, generator, corpus, route
manifest, design/plan, or `build-collision-mhaura-repro` path belongs to this
commit. The shared Task 1 generated/corpus worktree changes were preserved
exactly and were not staged.

## Contract established

The Lua tests now require one generic, objective-local reducer over Task 1's
flat `progression_actions` rows. Each row is self-contained and retains the
canonical `step_id` and `action_id`, step/action/global ordering, top-level
action/relationship/target facts, normalized `target_key`, canonical-name
matcher arrays, result facts, count facts, `source_authority`,
`field_sources`, `source_revisions`, `source_action_span_ids`, and exact inline
`catalogue` rows. Directional travel facts include the authoritative top-level
`destination_zone_name` and `destination_zone_id` pair plus provenance for
both fields. No nested matcher or runtime join table is accepted.

`GuideState:progression_actions(native_key)` must validate the index, shard,
objective, schema/module/native/revision/authority self-pins, action IDs and
orders, relationship/target keys, and count-mode compatibility; sort by
`step_order` then `action_order`; and return a deep copy. Compact schema
version 2 is the only accepted version. Missing, future/mismatched, and
obsolete v1 index/shard pins fail closed. The count modes are:

- `single`, default `required_count=1`
- `credited-defeat`, for explicit repeated fight/defeat actions
- `inventory-gain`, for explicit repeated ordinary-item acquisition

Key items, interactions, trade/delivery, examine/use, and travel remain
`single`. A counted fixture requires 30 credited defeats. Invalid zero,
fractional, unknown, and action-incompatible count rows fail closed.

`GuideState:retain_progression_keys(active_keys)` must return a private
objective-cache count from 0 through 64, retain active keys before LRU extras,
and keep compact shard retention bounded. The fixture loads 70 objectives from
six distinct shards, retains the newest active keys, and requires the oldest
shard to load again. The active reducer path must never load full BG,
FFXIclopedia, or reconciliation modules.

The durable cursor is exactly ten tab-separated fields:

```text
v2	owner	world	native	progression_revision	step_id	step_order	action_id	action_order	progress_count
```

Partial progress identifies the current action with
`0 <= progress_count < required_count`. The accepted final unit atomically
writes the next action at count zero. A terminal objective retains its last
action with `progress_count == required_count`; reload and replay may not
resurrect it. Negative, fractional, over-required, stale-revision, and
unknown-action rows fail closed. The login generation is transient and is not
persisted.

The legacy objective-progress row remains the separate four-field shape
`owner, native, step_id, step_order`. A current positive owner/World with one
material action in that legacy step migrates forward and appends v2. An
ambiguous multi-action legacy step resets immediately before that step and
appends v2. Foreign-owner rows remain untouched.

The reducer matrix covers:

- exact current and globally unique bounded-later interaction acceptance;
  same-objective repeated and cross-objective ambiguity rejection
- cursor-entered item count increase and key-item absent-to-present only;
  pre-existing stock, loss, negative delta, and replay never complete or rewind
- outgoing `0x05C` as transport intent only, followed by exact committed-zone
  completion or an exact owned route arrival, using only the flat action's
  destination name/ID pair
- coherent native `0x056` completion/replacement, ordinary terminal v2 rows,
  independent new-key initialization, reload non-resurrection, and fail-closed
  behavior when the compact graph is unavailable
- character, World, session, progression-revision, sequence, and identity-loss
  boundaries
- default single and five-unit counted fights, plus three-unit inventory gain,
  with exact partial v2 rows and relog/reload persistence
- exact local or party kill credit, target and zone matching, monotone battle
  sequence, replay dedupe, repeated/global ambiguity, and rejection of despawn,
  HP-zero observation, generic falls-to-ground messages, nonparty actors,
  unmatched enemies, wrong zones, and incoming `0x028` by itself

The route-less Arnau and Cid interaction tests require one exact action move,
one notification, exact ten-field persistence, reload survival, and replay
rejection. Wiki catalogue points are `wiki-ready`, `objective_wiki_route`, and
`wiki_authoritative`, while `verified` remains false and no rooted route
contract is invented. Missing positive World/session suppresses objective rows;
pre-existing item possession no longer advances either typed or source-backed
routes.

## Reader adapter contract

The reader test requires a production World provider backed by
`ffxi.account.get_login_world_id`, stable `name:world` ownership rather than a
transient entity ID, a generation stable across repeated calls during one
login, zero while logged out, and a strictly higher generation after relogging
the same character. Identity loss invalidates all mission, quest, key-item,
inventory, and pending-reducer transient state.

Official packet layouts were checked against Windower's current packet fields:

- outgoing `0x05C` Warp Request: X/Z/Y at `+04/+08/+0C`, target ID `+10`,
  zone `+18`, menu ID `+1A`, target index `+1C`; receipt emits one qualified
  `transport-request` and cannot complete progress
- incoming `0x029` Action Message: Actor `+04`, Target `+08`, Actor Index
  `+14`, Target Index `+16`, Message `+18`

Only Action Message IDs 6 and 97 emit kill credit. IDs 20, 113, 406, 605, and
646 are falls-to-ground variants and emit none. Incoming `0x028` may supply
battle/entity context but emits zero reducer signals, preventing a single kill
from being counted once from `0x028` and again from `0x029`.

The reader contract also requires native background dirty refresh without a
synchronous closed-menu rebuild or unrelated-route cancellation, typed `0x056`
state signals, and explicit wiki-authoritative ordinary-route dispatch.

Research sources:

- https://raw.githubusercontent.com/Windower/Lua/dev/addons/libs/packets/fields.lua
- https://raw.githubusercontent.com/Windower/Resources/master/resources_data/action_messages.lua

Ghidra 12.1.2 also opened the existing analyzed `FfxiMainUnpacked` project
read-only. It did not supersede the official packet schema; it confirmed the
native/runtime evidence boundary remained appropriate for this test-only task.

## Confirmed production REDs

Navigation command:

```powershell
& 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe' `
  'tools/lua_tests/test_mission_quest_navigation.lua' `
  'ashita/addons/accessxi_reader/modules/mission_quest_objectives.lua' `
  'ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua'
```

Exit code: `1`.

```text
Task 2 typed objective reducer REDs:
- pre-existing Orcish Axe possession completed an acquisition step without a cursor-entered delta
- production typed objective reducer API is missing for inventory-delta
- current-session Orcish Axe 0-to-1 delta did not advance the acquisition step
- single-action legacy cursor did not append the exact ten-field v2 migration row
- ambiguous multi-action legacy step was treated as fully completed
- ambiguous legacy step did not append a v2 reset immediately before that step
```

Guide command:

```powershell
& 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe' `
  'tools/lua_tests/test_mission_quest_guides.lua' `
  'ashita/addons/accessxi_reader/modules/mission_quest_guides.lua' `
  '.task2-guide-manual.tmp'
```

Exit code: `1`.

```text
Task 2 wiki-authoritative guide REDs:
- GuideState:progression_actions production seam is missing
- resolved guide step did not expose per-field BG-primary/FFXIclopedia-fallback provenance
- authoritative conflicted wiki target was not exposed as an exact finite wiki-ready route
```

Reader command:

```powershell
& 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe' `
  'tools/lua_tests/test_mission_quest_reader_runtime_integration.lua' `
  'ashita/addons/accessxi_reader/accessxi_reader.lua'
```

Exit code: `1`.

```text
Task 2 login-safe native reader REDs:
- production current_player_world_id provider is missing
- durable objective identity was keyed by transient entity server ID instead of World
- objective session generation remained positive while local identity was absent
- identity loss did not invalidate mission, quest, key-item, and inventory transient snapshots
- identity loss did not invalidate reducer pending correlation through a typed signal
- same-identity relogin reused the prior objective session generation
- outgoing 0x05C did not feed one correctly decoded, owner-qualified transport-request
- incoming 0x029 message 6 did not feed exact masked local-player kill credit
- incoming 0x029 message 97 did not feed active-party actor/target kill credit
- closed-menu native mission change did not mark Missions dirty for the next read
- reader still lacks the explicit wiki-authoritative ordinary-route dispatch seam
- 0x056 capture does not feed typed native completion/replacement state to the reducer
```

Every direct run reaches its intended aggregate assertion. There is no Lua
load, missing fixture, or accidental parser error. To verify the guarded future
cases now, temporary uncommitted always-false reducer and raw compact-action
stubs were inserted into disposable copies of the production modules. Both
harnesses executed every guarded scenario through their aggregate failures
without a runtime/fixture exception; the disposable files were outside the
repository and are not part of the task.

## Verification

Lua 5.1 syntax command:

```powershell
& 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe' -e `
  "assert(loadfile('tools/lua_tests/test_mission_quest_navigation.lua')); assert(loadfile('tools/lua_tests/test_mission_quest_guides.lua')); assert(loadfile('tools/lua_tests/test_mission_quest_reader_runtime_integration.lua')); print('task2 lua syntax ok')"
```

Exit code: `0`.

```text
task2 lua syntax ok
```

Scoped `git diff --check` exit code: `0`.

The final scoped commit SHA is reported by the parent handoff because this
report is itself part of that commit.

## Independent-review fix round 1/5

Review of `bea3600` found that three intermediate assertions prevented a clean
checkout from executing the complete contract. This round removes those early
aborts. Each harness now records fixture-independent failures, continues
through every Task 2 scenario, and raises exactly once at its final aggregate.
No production or generated file was changed.

The strengthened compact-shard fixture is self-contained and has no matcher or
runtime join. It requires BG-primary and field-level FFXIclopedia fallback
across action/relationship, target/entity, zone, grid, item/key item, and
instruction, including mixed `field_sources`, both source revisions, an exact
finite catalogue point, and the top-level destination name/ID pair. It also
executes all invalid shard/schema/authority/revision/action/count cases and all
70 objective-cache loads even when the production APIs are absent.

The reducer matrix now additionally executes:

- immutable start/finish target server ID, zone, event/menu, owner, World,
  login generation, and progression revision
- bounded future acceptance without crossing a multi-path branch, battlefield,
  transport, unobservable action, repeated signature, global ambiguity, or
  native revision boundary
- exact transport target/menu/session/sequence correlation, request replay,
  request-alone noncompletion, and committed destination-zone completion using
  only the flat action's destination name/ID pair
- incomplete and foreign-owner/World/session Inventory snapshots, replay,
  loss, and a coherent positive delta of two units
- 9- and 11-field v2 rows, wrong durable owner/World, step/action ID-order
  mismatch, nonterminal terminal count, invalid trailing row with latest-valid
  recovery, and exact ten-field continuation
- explicit-one `single`, whole-action trade `single`, and whole-action delivery
  `single`

The reader no longer uses Task 4 source-substring checks as RED evidence. It
executes raw packet buffers for incoming `0x032` and `0x034`, outgoing `0x05B`,
outgoing `0x05C` with X/Z/Y values `1.0/-2.0/0.5`, partial and coherent
`0x056`, and absent-to-present `0x055` with replay. It also executes a complete
native Inventory count transition, the committed-zone reset body, the actual
`I` wiki-route dispatch, closed-category dirtying, exact obsolete-route
cancellation, current-route preservation, fresh reopen/rebuild, and the rule
that progression never starts movement.

### Clean-archive reproduction

An ephemeral Git tree was built from committed HEAD
`9656babd91bd1d46a36ed7f07f22af0fb54e6298` plus only the three owned Lua
harnesses. It deliberately excluded every shared uncommitted generated/corpus
file:

```text
snapshot commit: 70ee869ed5d1748a3e343febf1a2ce7c7bd86bff
tree:            07ceec8f5a0eb7d74e89169b14d97991d377cebe
clean root:      C:\Users\buu42\AppData\Local\Temp\accessxi-task2-fix1-clean-20260814-020319
```

Construction used a temporary `GIT_INDEX_FILE`, `git read-tree HEAD`, explicit
`git add` of the three harnesses, `git write-tree`, `git commit-tree`, and
`git archive`. The direct commands below were run from that exact clean root.

Navigation:

```powershell
& 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe' `
  'tools/lua_tests/test_mission_quest_navigation.lua' `
  'ashita/addons/accessxi_reader/modules/mission_quest_objectives.lua' `
  'ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua'
```

Exit `1`, final aggregate at line 4571, with 119 genuine production-seam REDs.
The exact first failures were:

```text
Task 2 complete wiki-authoritative progression REDs:
- a fresh exact wiki candidate without a rooted contract must expose a wiki-ready route
- wiki-ready route did not preserve authoritative source semantics and an exact finite catalogue point
- pre-existing Orcish Axe possession completed an acquisition step without a cursor-entered delta
- production typed objective reducer API is missing for inventory-delta
- current-session Orcish Axe 0-to-1 delta did not advance the acquisition step
- single-action legacy cursor did not append the exact ten-field v2 migration row
```

The same final aggregate contained the new latest-valid, transport, counted
Inventory, explicit-one, trade, and delivery REDs. Its exact final twelve lines
prove the previously hidden route-less scenarios executed:

```text
- route-less mission 0x032/0x034 start was not accepted for the current exact Arnau step
- route-less mission matching 0x05B finish did not advance the current wiki cursor
- route-less mission interaction did not emit exactly one progression notification
- route-less mission finish did not move exactly one material action from Arnau to the Orcish hut key
- route-less mission finish did not persist the exact ten-field next-action cursor
- route-less mission cursor was not persisted across navigation-module reload
- route-less quest 0x032/0x034 start was not accepted for the current exact Cid step
- route-less quest matching 0x05B finish did not advance the current wiki cursor
- route-less quest interaction did not emit exactly one progression notification
- route-less quest finish did not move exactly one material action from Cid to the wait instruction
- route-less quest finish did not persist the exact ten-field next-action cursor
- route-less quest cursor was not persisted across navigation-module reload
```

Guide:

```powershell
& 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe' `
  'tools/lua_tests/test_mission_quest_guides.lua' `
  'ashita/addons/accessxi_reader/modules/mission_quest_guides.lua' `
  "$env:TEMP\task2-guide-clean-progress.tsv"
```

Exit `1`, final aggregate at line 1865, with 35 genuine REDs. Exact leading
and compact/cache failures:

```text
Task 2 wiki-authoritative guide REDs:
- a guide without explicit BG-primary/FFXIclopedia-fallback authority did not fail closed
- GuideState:progression_actions production seam is missing
- GuideState:retain_progression_keys bounded-cache seam is missing
- compact progression schema did not expose three deterministic material actions
- compact progression row did not preserve BG-primary and field-level FFXIclopedia fallback
- mixed-authority compact action did not expose one exact finite wiki-ready catalogue point
- duplicate compact action IDs/orders did not fail closed
- one or more of 69 compact cache-fixture objectives failed to load
- progression action cache did not report a bounded retained count of at most 64
- retain_progression_keys evicted an active objective before LRU extras
- oldest of six compact shards remained in an unbounded generic module cache
- six distinct compact shards were not exercised by the bounded-cache fixture
```

Reader:

```powershell
& 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe' `
  'tools/lua_tests/test_mission_quest_reader_runtime_integration.lua' `
  'ashita/addons/accessxi_reader/accessxi_reader.lua'
```

Exit `1`, final aggregate at line 2109, with 27 genuine REDs. Exact executable
adapter failures added by this round:

```text
- outgoing 0x05C did not feed one correctly decoded, owner-qualified transport-request
- raw incoming 0x032 did not emit one exact owner-qualified interaction-start signal
- raw 0x032 double-dispatched through the legacy interaction bridge
- raw incoming 0x034 did not emit one exact owner-qualified interaction-start signal
- raw 0x034 double-dispatched through the legacy interaction bridge
- raw outgoing 0x05B did not emit one exact owner-qualified interaction-finish signal
- raw 0x05B double-dispatched through the legacy interaction bridge
- coherent raw 0x056 mission replacement did not emit one exact native-objective signal
- committed zone-reset path did not emit one exact typed committed-zone signal
- raw 0x055 absent-to-present transition did not emit one exact typed key-item delta
- replayed identical raw 0x055 emitted duplicate key-item progression evidence
- coherent native Inventory count increase did not emit one exact typed delta
```

All negative boundary fixtures also ran: because current production lacks the
reducer/adapters, their required rejection is already true and therefore they
correctly do not appear as failures. Reaching the final aggregate after those
calls proves they are executable and not hidden behind a missing-API branch.

### Fix-round verification

The verified 32-bit Lua 5.1 syntax checker returned exit `0` for all three
files in the clean archive:

```text
syntax ok: C:\Users\buu42\AppData\Local\Temp\accessxi-task2-fix1-clean-20260814-020319\tools\lua_tests\test_mission_quest_navigation.lua
syntax ok: C:\Users\buu42\AppData\Local\Temp\accessxi-task2-fix1-clean-20260814-020319\tools\lua_tests\test_mission_quest_guides.lua
syntax ok: C:\Users\buu42\AppData\Local\Temp\accessxi-task2-fix1-clean-20260814-020319\tools\lua_tests\test_mission_quest_reader_runtime_integration.lua
```

Scoped `git diff --check` over the three harnesses and this report returned
exit `0`. The final commit SHA is reported in the handoff because a Git commit
cannot contain its own resulting SHA.

## Independent-review fix round 2/5

Review of `ab2d6c2` found that the reducer-facing compact fixtures still used
the obsolete schema-v1 self-pin and that travel rows exposed only the numeric
destination. Every valid compact index entry, shard envelope, and objective
pin now uses schema version 2. Missing schema, unsupported version 3, obsolete
v1 shard, obsolete v1 index, and index/shard mismatch remain separate
executable fail-closed cases; v1 is never accepted as a valid fixture.

Every flat action fixture now contains `destination_zone_name` and
`destination_zone_id` together with both `field_sources`. The mixed-authority
guide row selects BG-primary action/relationship, zone, and item facts while
using FFXIclopedia fallback for target/entity, grid, key item, instruction, and
both destination fields. It has no matcher or runtime join and retains one
exact finite catalogue point.

Navigation travel, transport, and mission-replacement rows copy the explicit
destination pair from the flat action only. Their parallel legacy
`source_route_steps` action, relationship, target, zones, instruction, and
destination pair are deliberately poisoned. Matching committed-zone REDs can
therefore become green only through the flat compact row, not source-route
prose or a runtime destination heuristic. The generator-only
negative/prohibited destination boundary remains outside the runtime reducer.

### Direct working-tree REDs

The three direct commands documented above all reached their final aggregate:

```text
navigation exit=1 failures=119 line=4645
first=- a fresh exact wiki candidate without a rooted contract must expose a wiki-ready route
last=- route-less quest cursor was not persisted across navigation-module reload

guides exit=1 failures=34 line=1900
first=- GuideState:progression_actions production seam is missing
last=- authoritative conflicted wiki target was not exposed as an exact finite wiki-ready route

reader exit=1 failures=27 line=2109
first=- production current_player_world_id provider is missing
last=- coherent native Inventory count increase did not emit one exact typed delta
```

The working-tree guide count reflects concurrent uncommitted production work;
none of those production/generated files is included in Task 2.

### Clean-archive reproduction

A temporary index over committed parent `ab2d6c223a97be38d30a8c3fed514f9596570b6e`
added only the three owned harness paths, then `git write-tree`, `git
commit-tree`, and `git archive` produced:

```text
snapshot: 50e9e30382eb4de815207789439083a7cc846213
tree:     4d11176ab82cc9b108a35033de759944b9a02f3b
root:     C:\Users\buu42\AppData\Local\Temp\accessxi-task2-fix2-clean-20260814-023439
```

Running the exact direct commands from that archive produced:

```text
navigation exit=1 failures=119 line=4645
first=- a fresh exact wiki candidate without a rooted contract must expose a wiki-ready route
last=- route-less quest cursor was not persisted across navigation-module reload

guides exit=1 failures=37 line=1900
first=- a guide without explicit BG-primary/FFXIclopedia-fallback authority did not fail closed
last=- authoritative conflicted wiki target was not exposed as an exact finite wiki-ready route

reader exit=1 failures=27 line=2109
first=- production current_player_world_id provider is missing
last=- coherent native Inventory count increase did not emit one exact typed delta
```

The clean guide aggregate includes these new schema-v2 contract failures:

```text
- missing compact schema self-pin did not fail closed
- mismatched compact schema self-pin did not fail closed
- obsolete v1 compact shard did not fail closed
- index schema mismatch did not fail closed
- obsolete v1 compact index did not fail closed
```

All three clean-archive harnesses passed the verified 32-bit Lua 5.1 syntax
checker. The scoped `git diff --check` result is recorded immediately before
the fix-round commit.

## Independent-review fix round 3/5

Post-reboot Task 3 GREEN work reduced the navigation aggregate from 119 REDs
to 13 and exposed three defects in the test contract rather than safe
production behavior. This test-only round corrects those fixtures without
adding a runtime schema field or weakening any matcher.

- The final route-less quest IIFE called `task2_cid_candidate` and
  `task2_progression_catalogue_row`, which were local to an earlier, already
  closed IIFE. It now owns one self-contained exact Cid compact catalogue row,
  so the quest start/finish sequence executes instead of raising an accidental
  global-function error.
- The inventory test proved and persisted the San d'Orian mission step-007
  cursor, but later reducer isolation deleted the shared progress file and
  reloaded the navigation module before testing currentness. The fixture now
  constructs the old step-005 route snapshot, explicitly restores the exact
  ten-field step-007 row, reloads, then proves step 005 is stale and step 007 is
  current. Restoration is scoped around those two exact currentness snapshots:
  the fixture removes the row before packet-freshness checks and again after
  the step-007 route checks, so unrelated source-route scenarios begin from
  their documented baseline.
- Compact schema v2 carries transport target, zone, server ID, transport ID,
  and destination zone, but no event/menu ID. The transport request no longer
  requires production to distinguish an invented `32001` catalogue menu from
  `32002`. Target, owner, World, login generation, request replay, transport
  sequence, committed target, and destination mismatches remain executable.
  The request still carries a positive menu and the committed signal must
  correlate the same stored menu; immutable interaction lifecycle tests retain
  their explicit event/menu mismatch coverage.

### Clean-commit RED reproduction

A temporary index over committed HEAD added only the corrected navigation
harness, then `git write-tree`, `git commit-tree`, and `git archive` produced:

```text
snapshot: 6b2b086d0e949d0e4b624b7bac390ff5548f2780
tree:     b5439f796bea87d11d89f640701764bcb0e5193c
root:     C:\Users\buu42\AppData\Local\Temp\accessxi-task2-fix3b-04d7fc9882e94c16a40d8e62a4c7f240
```

The direct navigation wrapper reached its one final aggregate at line 4675:

```text
exit=1
failures=119
first=- a fresh exact wiki candidate without a rooted contract must expose a wiki-ready route
last=- route-less quest cursor was not persisted across navigation-module reload
```

The clean snapshot harness passed the verified 32-bit Lua 5.1 syntax checker.
No production, generated corpus, reader, guide, or Task 1 file is part of this
fix round. The final scoped commit SHA is reported by the parent handoff because
this report is itself part of that commit.

## Independent-review fix round 4/5

Task 3's critical review exposed two obsolete acquisition fixtures and required
new executable runtime boundaries.  The San d'Orian Orcish Axe and Orcish Mail
Scales graphs now model the material action exactly as compact schema v2 does:
one current `obtain` / `obtain-item` action whose enemy catalogue supplies the
route context.  The expected positive Inventory delta behavior is unchanged,
and each graph now proves that enemy kill credit cannot complete its item-
acquisition action.

The additional review matrix covers instruction-only compact actions with an
empty target/key, strict catalogue keys, internal objective/shard LRU bounds,
all 1,806 real compact index entries, deduplicated active-key retention,
canonical acquisition-only evidence, global future item/key-item uniqueness
and barriers, zero-action native-state permutations, stale/replaced interaction
and transport arms, revision/native-activity revalidation, committed-zone tick
ordering, and wrong-zone invalidation.  A collective four-piece Fetich action
also proves that duplicate gains cannot stand in for distinct set members, its
numeric ten-field cursor resumes after a same-character new-session relog, and
terminal completion
requires all four members in the complete current Inventory snapshot.

### Clean committed-production RED reproduction

A temporary index over committed Task 3 production added only the two Lua
harnesses and their wrapper, then `git write-tree`, `git commit-tree`, and
`git archive` produced:

```text
snapshot: 961609044bdcd1679d03789bacf9127018da779f
tree:     5ad8ff12b4a4d930fa64c90d12b4f0dbb0b15891
root:     C:\Users\buu42\AppData\Local\Temp\accessxi-task2-fix4-clean-9616090
```

The direct navigation harness reached one final aggregate at line 5350 with
48 failures.  The first was missing active-key retention and the last was the
nonempty-to-empty native replacement writing the wrong cursor set.  The guide
harness reached one final aggregate at line 2088 with three top-level failures:
instruction-only empty-target loading, bounded objective/shard insertion, and
the real-index audit.  The latter intentionally summarizes every rejected
native key in one failure; Task 1 regeneration had not yet stabilized the
generated corpus for this round.

Both changed Lua harnesses passed the verified 32-bit Lua 5.1 syntax checker.
Against the concurrent Task 3 follow-up production, navigation narrowed to
exactly five REDs, all in the new distinct-Fetich set semantics.  No production,
generated corpus, reader, Task 1 Python, or corpus file is part of this test-
only round.

Post-commit contract audit found one inverted expectation in the new global-
uniqueness matrix: a current acquisition plus a matching foreign future action
must reject the evidence globally, not prefer the current objective.  The
corrected harness reaches the same final aggregate with exactly four focused
RED messages against the in-progress runtime (acceptance and cursor-write
failures for ordinary item and key-item evidence).  This correction changes no
production code and does not weaken current-action identity checks.

A final arm-lifecycle audit added a shared-arm construction: one exact Cid
start matches a live mission and quest, then native completion or replacement
of the mission must consume the entire immutable arm before its finish can
advance the still-active quest.  Clean snapshot
`31a2eb2ed9ef55942d8b1d67366c10b50ce530f8` (tree
`e093ff8c50a6b339cbc01790694f6d5c53d88eda`) reaches one aggregate at line
5385 with 54 REDs; the four new terminal messages prove both completion and
replacement otherwise leave the shared arm live and write foreign quest
progress.  The in-progress Task 3 runtime passes the strengthened harness.

The cache audit also changes one loaded index entry's progression revision
without rebuilding `GuideState`.  Returning the old cached actions is a single
focused RED at line 2101; the loader must re-read the index self-pin on every
access, fail closed while it disagrees with the cached shard objective, and
recover after the exact revision is restored.
