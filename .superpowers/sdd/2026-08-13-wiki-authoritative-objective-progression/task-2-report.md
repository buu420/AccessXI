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
`catalogue` rows. No nested matcher or runtime join table is accepted.

`GuideState:progression_actions(native_key)` must validate the index, shard,
objective, schema/module/native/revision/authority self-pins, action IDs and
orders, relationship/target keys, and count-mode compatibility; sort by
`step_order` then `action_order`; and return a deep copy. The only count modes
are:

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
  completion or an exact owned route arrival
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
finite catalogue point, and top-level `destination_zone_id`. It also executes
all invalid shard/schema/authority/revision/action/count cases and all 70
objective-cache loads even when the production APIs are absent.

The reducer matrix now additionally executes:

- immutable start/finish target server ID, zone, event/menu, owner, World,
  login generation, and progression revision
- bounded future acceptance without crossing a multi-path branch, battlefield,
  transport, unobservable action, repeated signature, global ambiguity, or
  native revision boundary
- exact transport target/menu/session/sequence correlation, request replay,
  request-alone noncompletion, and committed destination-zone completion using
  only the flat action's `destination_zone_id`
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
