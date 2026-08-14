# Task 3 report — wiki-authoritative runtime progression

## Scope

This production slice changes only:

- `ashita/addons/accessxi_reader/modules/mission_quest_guides.lua`
- `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- this report and the Task 3 ledger entry

It does not wire reader packet callbacks, edit the generated corpus, add an
objective-specific exception table, start movement, deploy the addon, or touch
`build-collision-mhaura-repro`.

The corrected Task 2 fixture contract and every later critical-review
regression are separate test-only commits. The original clean committed
baseline had 119 navigation REDs, 37 guide REDs, and 27 reader adapter REDs.
The strengthened critical-review snapshot reaches one 59-RED navigation
aggregate on the committed pre-follow-up runtime, while the current production
passes the same complete synthetic matrix. Exact snapshot IDs and the final
GREEN commands are recorded below.

## Source authority and compact loading

`GuideState:progression_actions(native_key)` now consumes only Task 1's compact
schema-v2 progression shard for the selected native objective. It fails closed
unless the index, shard envelope, and objective agree on:

- schema version 2;
- module name, native key, and deterministic progression revision;
- BG as primary and FFXIclopedia as fallback;
- stable, unique, contiguous step/action/global order and action IDs;
- a complete self-contained material action with either an exact target/key
  pair or a nonempty authoritative instruction and instruction provenance;
- count mode, destination pair, source spans/revisions, and every finite
  catalogue point, whose own target/key remains strict even for an
  instruction-only action.

The runtime therefore uses the already reconciled field-by-field authority
from each flat action rather than loading full BG, FFXIclopedia, reconciliation,
action-span, typed-claim, or ledger modules. Returned actions are deep copies.
Independent objective-action and shard-envelope LRUs each enforce their
64-entry bound on every insertion. Production active-list reads pass a
deduplicated set of native keys to the retention seam, keep active objectives
before recent extras, and release compact shard tables after retention. Cache
hits re-read the current index self-pin, so a changed module or progression
revision cannot reuse stale actions. Invalid or obsolete v1 data never becomes
a cursor.

Exact catalogue destinations are exposed as `wiki-ready`,
`objective_wiki_route=true`, and `wiki_authoritative=true`, while remaining
deliberately distinct from rooted/recorded `verified=true` routes. A source
instruction with no exact finite destination remains instruction-only. Each
compact-v2 action is a complete catalogue snapshot: an intentionally empty
catalogue cannot be repopulated from the independently cached legacy
objective-destination graph, even when that graph contains the same action ID.

## Durable cursor and migration

The durable cursor is an append-only exact ten-field record:

```text
v2\towner\tworld\tnative\tprogression_revision\tstep_id\tstep_order\taction_id\taction_order\tprogress_count
```

The loader retains the latest valid record for the exact stable character,
positive World, native key, and current progression revision. Malformed,
wrong-owner, wrong-World, stale-revision, unknown-action, ID/order mismatch,
fractional, negative, over-count, and invalid-terminal records fail closed.
Windows writes use binary append mode so every new row is exactly LF-terminated.

Four-field legacy rows remain readable. For the current owner/World and active
objective, an exact single-action legacy step migrates past that action; an
ambiguous multi-action step resets immediately before the step. Foreign legacy
rows are left untouched. Accepted counted progress is persisted on the current
action; the final unit atomically persists the next action at count zero. The
terminal action remains persisted at its required count, so reload/replay cannot
reopen a completed objective.

## Generic typed reducer

`accessxi.nav_mission_quest_reduce_signal(signal)` is the single production
entry point for these typed causal signals:

- immutable `interaction-start` / matching `interaction-finish` correlation;
- coherent positive `inventory-delta` and absent-to-present `key-item-delta`
  only for canonical `obtain` / `obtain-item` actions;
- exact local/party `kill-credit` from packet `0x029` message 6 or 97;
- `transport-request` intent followed by exact `committed-zone` evidence;
- exact owned `route-arrival`;
- coherent completed/replaced `native-objective-state`;
- `identity-loss` cancellation of all reducer transient state.

Signals are accepted only for the current stable owner, positive World, login
generation, positive tick/sequence, and current corpus/progression revision.
Interaction and transport matching requires the exact normalized target, zone,
and catalogue-backed server ID. A later interaction can prove wiki
prerequisites only through the bounded unique suffix rule: exactly one
compatible future action globally,
no repeated compatible signature, and no branch, battlefield, transport,
unobservable action, or revision boundary. Inventory and key-item evidence is
also globally unique before either a current or future match is accepted: a
same-step, later, cross-objective, or current-plus-foreign duplicate rejects
the whole signal. Item names mentioned by trade, delivery, talk, or wait rows
are requirement context and cannot act as acquisition evidence. An enemy
catalogue on an obtain action supplies route context but never turns a kill
into item evidence.

The reducer implements `single`, `credited-defeat`, and `inventory-gain` count
semantics. A counted multi-item action whose required count equals its exact
distinct item set persists the number of members present in a complete native
Inventory snapshot. Repeated gains of one member cannot impersonate another;
partial numeric progress survives same-character relog; and a four-piece
Fetich-style action completes only while all four distinct pieces are present.
Pre-existing inventory/key-item presence, negative deltas, HP zero, despawn,
generic death messages, nonparty kills, raw warp requests, incomplete
snapshots, wrong destinations, and replayed evidence do not advance or rewind.
Accepted progression invalidates the active-row cache, increments the progress
revision, notifies the existing callback, and cancels only the route owned by
the completed objective/action.

Pending interaction state is bounded to 64 immutable arms. Each arm snapshots
the objective, current and matched action indices/IDs, accepted partial count,
and progression revision. Finish/commit re-reads native activity and the
current compact graph immediately before advancing; completion or replacement
purges every arm that mentions that objective. Interaction finish sequence
must be newer than its start. A transport arm may be replaced only by a newer
otherwise-exact request, committed evidence must name the exact armed request
sequence with a nonolder tick and newer causal sequence, and a wrong positive
destination consumes the stale arm. Valid zero-action graphs remain coherent
through empty/nonempty native replacement permutations without a cursor write
or crash.

Accepted causal IDs are bounded to 2,048 entries. Event arms, the transport
arm, and battle sequence are cleared on identity loss. Progression never
invokes route start or movement; the player's existing `I` action remains the
only route-start seam. The legacy `nav_mission_quest_remember_arrival` adapter
feeds this same reducer.

## Critical-review RED/GREEN evidence

The monotonic-sequence test-only commit is
`5547389ebacaf54db9a5ce436860823f15516389`; the final self-contained-catalogue
regression commit is `647e044e705485ddf3a19ed814169c28cacca08b`. A synthetic
Git archive containing every committed test but the committed pre-follow-up
runtime is:

```text
snapshot: 3d9daeb4abf11d8fcd4ab85caa9e14e1117d61cc
tree:     439c80a21c54fd5d8b6a40844ea8b43730f753d4
root:     C:\Users\buu42\AppData\Local\Temp\accessxi-task3-catalogue-red
```

It reaches one final navigation aggregate with exactly 59 REDs. The new
sequence regressions prove that the old runtime accepted and persisted an
interaction finish at its arm's start sequence, accepted a committed zone at
its transport request sequence, and consequently rejected the later valid
commit. The three additional catalogue REDs prove that it repopulated an empty
compact-v2 catalogue from poisoned legacy data, armed that interaction, and
wrote progress. The current production turns that complete harness GREEN. The
same test file and both production modules are Lua 5.1 syntax GREEN, the rooted
route-runtime adjacency wrapper remains GREEN, and the scoped diff check is
clean.

The final stable-corpus walk exposed one additional loader boundary: 224
objectives contained 361 punctuation-only target actions (`???` 360 times and
`'` once), for which normalization intentionally produces no target key. They
now load only as authoritative instruction barriers. Alphanumeric targets
without a normalized key, keys without a target, and catalogue destinations
without a normalized target key remain rejected.

## Verification

Combined guide/navigation wrapper:

```powershell
& .\tools\test_mission_quest_navigation.ps1
```

Exit `0` in 38.985 seconds against all 1,806 stable compact objectives:

```text
mission and quest guide tests passed
mission and quest navigation tests passed
```

Route runtime and route-policy wrapper:

```powershell
& .\tools\test_mission_quest_route_runtime.ps1
```

Exit `0`:

```text
mission and quest route runtime tests passed
mission and quest route runtime wrapper tests passed
```

Reader integrity, excluding the expected Task 4 adapter RED harness:

```powershell
& .\tools\lua51\lua5.1.exe `
  .\tools\lua_tests\test_mission_quest_reader_integrity.lua `
  .\ashita\addons\accessxi_reader\accessxi_reader.lua
```

Exit `0`: `mission and quest reader integrity tests passed`.

Legacy-adjacent navigation gates all exited `0`:

- navigation hotkeys: `Navigation hotkey checks passed` and
  `Navigation hotkey focused checks passed`;
- hotkey integration: `Navigation hotkey integration checks passed`;
- zone search: canonical path, presentation dedup, and command checks passed;
- zoning/key blocking: `nav zoning and key blocking checks ok`.

The repository's 32-bit Lua 5.1 syntax wrapper returned `syntax ok` for both
modified production modules. The final scoped and whole-working-tree
`git diff --check` results are recorded immediately before commit.

The final Task 3 commit SHA is reported in the parent handoff because a Git
commit cannot contain its own resulting SHA. Deployment remains held for Task
4, independent review, whole-branch verification, and the user's release gate.
