# Wiki-Authoritative Mission and Quest Progression Plan

**Goal:** Make the complete imported mission and quest corpus usable by default and automatically keep each local character on the next observable wiki step.

**Architecture:** BG Wiki is the deterministic primary walkthrough and FFXIclopedia is the fallback. Reconciled source rows provide ordered stable material action claims, with BG claim fields winning and FFXIclopedia filling missing fields. A character-scoped reducer consumes exact native interaction, inventory, key-item, zone, route-arrival, and 0x056 objective transitions, completing at most one current claim per objective per causal signal. Exact catalogue/collision validation remains the route safety boundary.

## Global constraints

- Preserve current character, World, addon-session, native-objective, step, target, zone, and event ownership checks.
- Never infer another party member's private objective state from the local client.
- Never auto-start movement; `I` remains the route-start action.
- Never inspect or route a stale objective row after its native active state changes.
- Never suppress a reconciled material action claim merely because the two wikis disagree; use BG claim fields first and FFXIclopedia claim fields only when BG lacks them.
- Advance no more than one material action claim in one objective per causal signal and make packet/menu replays idempotent.
- Keep non-observable steps as spoken current instructions instead of guessing completion.
- Retain all existing collision, zoneline, transport, route-owner, and current-session auxiliary-state checks.

## Task 1: Refresh and freeze the two-wiki corpus

- Refresh both complete MediaWiki snapshots through the existing transactional importer.
- Rebuild generated source, reconciliation, index, coverage, and integrity artifacts deterministically.
- Add corpus assertions for 706 missions, 1,138 quests, all supported contexts, stable ordering, BG-primary conflict fields, and FFXIclopedia fallback.
- Prove a second offline build produces byte-identical generated artifacts.

## Task 2: Add RED cursor/reducer regressions

- Extend the Lua navigation harness with route-less mission and quest event start/finish sequences.
- Add current-step inventory, key-item, credited-defeat, committed-zone, route-arrival, objective-completed/replaced, duplicate-packet, repeated-target, cross-character, cross-World, and cross-session cases.
- Add a real-corpus test proving deterministic material-claim selection and no conflict suppression.
- Change route tests to require wiki-ready, verified source routes rather than test-ready routes.

## Task 3: Implement source authority and generic progression

- Expose BG-primary/FFXIclopedia-fallback action, entities, zones, grids, items, key items, explicit required quantity, and instruction on every stable material action claim inside a resolved source row.
- Replace conflict suppression with deterministic primary-source routing.
- Generalize the persisted objective cursor and interaction reducer to operate on stable material action claims for both missions and quests without objective-specific follow-up tables, including persisted partial progress for counted actions.
- Reconcile the current claim from inventory/key-item state and committed zone/arrival signals.
- Keep instruction-only output for a current material step with no exact catalogue destination.

## Task 4: Wire native events and wiki-ready routing

- Feed incoming 0x032/0x034 starts and outgoing 0x05B event finishes through one exact event lifecycle adapter. Treat outgoing 0x05C only as a Warp Request correlation for transport/travel; require the expected committed zone change before advancing and never complete on 0x05C receipt.
- Feed incoming 0x029 action-message results as kill-credit only for message 6 or 97, an exact current enemy and zone, and an actor resolved to the local player or active party/alliance. Do not infer completion from HP zero, despawn, generic death text, or a nonparty actor.
- Permit route-less event matching against only the current source claim's exact catalogue target identities.
- Dispatch exact wiki/catalogue destinations as wiki-ready verified routes through the existing collision-aware source-route engine, with compatibility aliases only where old tests or saved state require them.
- Rebuild/cancel the menu or exact owned route immediately after accepted progression.

## Task 5: Verify, review, deploy, and publish

- Run focused RED/GREEN harnesses, generator tests, corpus audit, mission/quest module and reader integration suites, full Lua 5.1 syntax, navigation/collision regressions, and `git diff --check`.
- Request task-scoped and whole-branch reviews; fix all Critical/Important findings.
- Verify no FFXI/POL/Ashita process is active, back up the live addon, copy dependencies first and reader last, then compare SHA-256 and run live-file syntax checks.
- Build fresh installer assets from the verified merged commit and publish the next patch release only after package/updater/native-integrity gates pass.
