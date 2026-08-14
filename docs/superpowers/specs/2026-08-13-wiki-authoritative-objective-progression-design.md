# Wiki-Authoritative Mission and Quest Progression Design

## Goal

Mission and quest navigation must present one current actionable walkthrough step and update it automatically from the local character's game activity. The player must not have to validate each objective manually before the imported walkthrough becomes usable.

## Source policy

- The revisioned BG Wiki and FFXIclopedia snapshots are accepted as the walkthrough authority.
- BG Wiki is the deterministic primary source when both sites describe an action claim. FFXIclopedia supplies missing objectives or missing claim fields.
- A disagreement is not a reason to hide the step. The runtime uses the primary-source action, targets, zones, items, and instruction while the full guide may still explain both sources.
- Generated wiki destinations that resolve to an exact installed navigation-catalog target may start through the ordinary collision-aware route engine. They are no longer labeled or dispatched as test routes.
- Character, World, addon-session, objective identity, current-step identity, and exact target ownership remain mandatory. Wiki authority does not permit stale cross-character state or guessed coordinates.

## Progression model

The reconciled wiki rows form an ordered graph of stable material action claims. Each source row may carry one or more stable claim IDs with source-specific action, target, zone, item, key-item, explicit required quantity, and instruction facts. Each active mission or quest has one persisted, character-qualified cursor naming the current material claim and its accepted partial count. Completing a nonterminal claim atomically moves the cursor to the next claim with count zero; a completed terminal claim remains recorded at its required count so replay cannot reopen it. Informational and optional recommendation rows do not become the current action. When both sources contribute a claim, BG claim fields win deterministically and FFXIclopedia fields fill only missing values.

The append-only cursor record is `v2`, stable owner, positive World, native objective key, progression revision, step ID, step order, action ID, action order, and progress count. Login generation remains transient and is never persisted. Explicit repeated defeat and inventory-acquisition quantities use `credited-defeat` and `inventory-gain`; every uncounted or interaction-proven action uses `single` with a required count of one. A server-accepted trade proves the complete trade action rather than consuming its named item quantity one unit at a time.

A reducer evaluates only the current material claim and advances it at most once per objective for one causal signal:

- a matching NPC/object event start and finish, even when no AccessXI route armed the interaction;
- a matching visible interaction followed by the native event-menu close;
- acquisition of the current step's named item or key item from current-session native state;
- a credited defeat of the current step's exact enemy from the native action-message packet, when the credited actor is the local player or an active party/alliance member;
- a committed zone change that reaches the current travel step's wiki destination;
- arrival at the exact selected destination for a travel-only step;
- an authoritative 0x056 transition that removes/completes the active quest or replaces the active mission.

The reducer may advance multiple distinct active objectives when one exact interaction genuinely satisfies each current step, but never more than one step within the same objective for that signal. A counted action advances only after its explicit authoritative quantity is reached; partial progress is persisted across relogin. Fight quantities count distinct credited defeats, and obtain or collect quantities count positive native inventory deltas. A server-accepted trade or delivery interaction proves the whole trade action even when the instruction names an item quantity. Repeated NPCs, doors, item checks, kills, or packet replays are deduplicated by causal identity and cursor order.

Steps whose completion is not observable remain spoken as the current instruction. They are not silently skipped. Normal guide movement remains available as a viewing tool but does not falsify completion state.

## Native event boundary

- Incoming 0x032/0x034 starts and outgoing 0x05B event finishes feed the exact interaction reducer with target server ID, zone, event ID, packet direction, and tick. Outgoing 0x05C is a Warp Request (X/Z/Y, target ID, zone, and menu ID): it may only arm/correlate a transport or travel step, and cannot complete it.
- Incoming 0x029 action-message results feed fight progression only for the exact credited-defeat messages (`actor defeats target` or `target was defeated by actor`), an exact current enemy and zone, and a credited actor that resolves to the local player or an active party/alliance member. HP zero, despawn, generic falls-to-ground messages, unresolved names, and nonparty kills never complete an action.
- 0x055 key-item and native inventory refreshes request state reconciliation only after current identity/session ownership is established.
- 0x056 mission and quest snapshots rebuild active-objective identity and prune cursors only from coherent current/completed state.
- A 0x05C-correlated transport or travel step completes only after the expected zone change is committed through the existing zone reset path; the prior route-owned interaction is discarded afterward.
- No party member's personal mission state is inferred from the local client's packets.

## Route behavior

Wiki targets still have to resolve to a finite, exact catalogue destination. Collision, zoneline, transport, and live-route validation remain unchanged. The player must still press `I`; progression never starts movement automatically.

When a current step completes, only a route owned by that exact objective and step is cancelled. The mission or quest list is rebuilt immediately and announces that the objective updated when its visible selection changed.

## Rejected alternatives

1. **0x056-only progression:** safe but insufficient; most intra-objective talks, fights, trades, and cutscenes do not change the mission/quest list bitfield.
2. **Blind route-arrival progression:** broad but incorrect; reaching an NPC or zone does not prove the sighted interaction, trade, fight, or cutscene completed.
3. **Per-objective reviewed contracts:** precise but recreates the one-at-a-time workflow the user explicitly rejected and currently covers only a tiny fraction of the imported corpus.

## Acceptance

- All 706 missions and 1,138 quests resolve to a deterministic ordered cursor when source steps exist.
- Both-source conflicts remain usable with BG-primary, FFXIclopedia-fallback semantics.
- Route-less exact interaction completion advances the current material claim for missions and quests.
- Item, key-item, credited-defeat, travel, 0x056 completion/replacement, replay deduplication, repeated-target, character, World, and session cases are covered.
- Existing route safety, collision, zoning, inventory, key-item, menu, and Lua 5.1 suites remain green.
- The refreshed snapshots and generated modules are deterministic and the deployed live addon hashes match the verified build.
