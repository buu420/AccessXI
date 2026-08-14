# Task 4 report — native reader progression adapters

## Scope

Task 4 changes only `ashita/addons/accessxi_reader/accessxi_reader.lua`, this
report, and its shared-ledger entry. It does not edit the compact guide loader,
navigation reducer, generated corpus, parser, or route corpus, and it never
starts movement without the player's existing `I` action.

## Native ownership and causal adapters

The durable objective owner is now the exact lowercased character name plus
the numeric login World ID from `ffxi.account`; transient entity server IDs are
not persisted as World. A login-local monotonic session generation returns
zero while identity is absent. Identity loss or change clears mission, quest,
key-item, and carried-Inventory snapshots and sends one typed `identity-loss`
signal so reducer arms cannot survive a relog.

Raw packet and native-state evidence now enters the shared typed reducer once:

- outgoing `0x05C`, incoming `0x032`/`0x034`, and outgoing `0x05B` produce
  exact transport or interaction lifecycle signals without the legacy bridge;
- incoming `0x029` messages 6/97 produce replay-safe kill credit only for an
  exact local/party actor and a resolved target entity; `0x028` remains
  context-only;
- coherent main `0x056` replacement produces one native mission-state signal,
  while a committed zone reset—not the warp request—produces committed-zone
  evidence bound to the stored transport request sequence;
- complete same-owner/session `0x055` absent-to-present transitions produce
  exact key-item deltas and identical replay is silent;
- complete native carried-Inventory snapshots produce exact positive count
  deltas after a baseline; partial, failed, identical, and loss-only snapshots
  produce no acquisition evidence.

All signals carry the current character, World, session generation, corpus
revision, positive tick, and session-local monotonic sequence. Unknown resource
names fail closed.

## Source-verified route seam

`wiki-ready` objectives are dispatched only to
`nav_start_wiki_objective_route`. The seam preserves source-route flags through
point copies and reuses ordinary collision routing in-zone or ordinary zone
search cross-zone. Speech and logs identify the route as source verified.
Instruction-only and blocked modes still start no route; rooted `ready` routes
retain their separate authorization path.

## Verification

The committed Task 2 reader contract moved from exactly 27 REDs to zero. The
focused wrapper exits `0` with:

```text
mission and quest reader I-handler integration tests passed
mission and quest reader integrity tests passed
mission and quest reader runtime pin test passed
```

The repository 32-bit Lua 5.1 syntax checker reports `syntax ok` for the reader.
The scoped and staged diff checks are clean. The final Task 4 commit SHA is
reported in the parent handoff because a commit cannot contain its own SHA.
