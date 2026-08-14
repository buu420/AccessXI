# Task 3 report — wiki-authoritative runtime progression

## Scope

This production slice changes only:

- `ashita/addons/accessxi_reader/modules/mission_quest_guides.lua`
- `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- this report and the Task 3 ledger entry

It does not wire reader packet callbacks, edit the generated corpus, add an
objective-specific exception table, start movement, deploy the addon, or touch
`build-collision-mhaura-repro`.

The corrected Task 2 fixture contract is the separate commit `2a4e14c`. Its
clean committed baseline had 119 navigation REDs, 37 guide REDs, and 27 reader
adapter REDs. During production work the navigation aggregate fell to 13;
those remaining failures exposed the three Task 2 fixture defects documented
in the Task 2 report. After that test-only correction, the production wrapper
is completely GREEN.

## Source authority and compact loading

`GuideState:progression_actions(native_key)` now consumes only Task 1's compact
schema-v2 progression shard for the selected native objective. It fails closed
unless the index, shard envelope, and objective agree on:

- schema version 2;
- module name, native key, and deterministic progression revision;
- BG as primary and FFXIclopedia as fallback;
- stable, unique, contiguous step/action/global order and action IDs;
- a complete self-contained material action, target key, provenance, count
  mode, destination pair, and finite catalogue point.

The runtime therefore uses the already reconciled field-by-field authority
from each flat action rather than loading full BG, FFXIclopedia, reconciliation,
action-span, typed-claim, or ledger modules. Returned actions are deep copies.
The per-objective LRU retains at most 64 entries, keeps active objectives before
recent extras, and releases compact shard tables after retention. Invalid or
obsolete v1 data never becomes a cursor.

Exact catalogue destinations are exposed as `wiki-ready`,
`objective_wiki_route=true`, and `wiki_authoritative=true`, while remaining
deliberately distinct from rooted/recorded `verified=true` routes. A source
instruction with no exact finite destination remains instruction-only.

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
- coherent positive `inventory-delta` and absent-to-present `key-item-delta`;
- exact local/party `kill-credit` from packet `0x029` message 6 or 97;
- `transport-request` intent followed by exact `committed-zone` evidence;
- exact owned `route-arrival`;
- coherent completed/replaced `native-objective-state`;
- `identity-loss` cancellation of all reducer transient state.

Signals are accepted only for the current stable owner, positive World, login
generation, positive tick/sequence, and current corpus/progression revision.
Matching is exact by normalized target plus zone, using a catalogue server ID
when available. A later interaction can prove wiki prerequisites only through
the bounded unique suffix rule: exactly one compatible future action globally,
no repeated compatible signature, and no branch, battlefield, transport,
unobservable action, or revision boundary.

The reducer implements `single`, `credited-defeat`, and `inventory-gain` count
semantics. Pre-existing inventory/key-item presence, negative deltas, HP zero,
despawn, generic death messages, nonparty kills, raw warp requests, incomplete
snapshots, wrong destinations, and replayed evidence do not advance or rewind.
Accepted progression invalidates the active-row cache, increments the progress
revision, notifies the existing callback, and cancels only the route owned by
the completed objective/action.

Pending interaction state is bounded to 64 immutable arms. Accepted causal IDs
are bounded to 2,048 entries. Both, the transport arm, and battle sequence are
cleared on identity loss. Progression never invokes route start or movement;
the player's existing `I` action remains the only route-start seam. The legacy
`nav_mission_quest_remember_arrival` adapter feeds this same reducer.

## Remaining Task 4 reader REDs

The production reader is intentionally outside Task 3. A current audit reaches
the final aggregate without a Lua/fixture exception and reports exactly these
27 expected adapter REDs:

```text
- production current_player_world_id provider is missing
- durable objective identity was keyed by transient entity server ID instead of World
- objective session generation remained positive while local identity was absent
- identity loss did not invalidate mission, quest, key-item, and inventory transient snapshots
- identity loss did not invalidate reducer pending correlation through a typed signal
- same-identity relogin reused the prior objective session generation
- outgoing 0x05C did not feed one correctly decoded, owner-qualified transport-request
- raw incoming 0x032 did not emit one exact owner-qualified interaction-start signal
- raw 0x032 double-dispatched through the legacy interaction bridge
- raw incoming 0x034 did not emit one exact owner-qualified interaction-start signal
- raw 0x034 double-dispatched through the legacy interaction bridge
- raw outgoing 0x05B did not emit one exact owner-qualified interaction-finish signal
- raw 0x05B double-dispatched through the legacy interaction bridge
- incoming 0x029 message 6 did not feed exact masked local-player kill credit
- incoming 0x029 message 97 did not feed active-party actor/target kill credit
- closed-menu native mission change did not mark Missions dirty for the next read
- coherent raw 0x056 mission replacement did not emit one exact native-objective signal
- committed zone-reset path did not emit one exact typed committed-zone signal
- wiki-ready mode did not dispatch only to the explicit ordinary collision-route seam
- the explicit route must identify the source-verified mission objective
- the explicit route must be logged as a source route
- source-ready mode must still dispatch only to the explicit ordinary-route seam
- packet freshness must not be announced as a source-route blocker
- production wiki-ready ordinary collision-route start seam is missing
- raw 0x055 absent-to-present transition did not emit one exact typed key-item delta
- replayed identical raw 0x055 emitted duplicate key-item progression evidence
- coherent native Inventory count increase did not emit one exact typed delta
```

The exact aggregate remains exit `1`, `failures=27`. These are the Task 4
wiring contract, not Task 3 production failures.

## Verification

Combined guide/navigation wrapper:

```powershell
& .\tools\test_mission_quest_navigation.ps1
```

Exit `0` in 24.6 seconds:

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
