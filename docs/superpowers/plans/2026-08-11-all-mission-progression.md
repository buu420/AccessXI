# All-Mission Progression Implementation Plan

**Goal:** Keep every active mission on one current actionable step and advance it from observable game state, without mission-specific runtime follow-up tables.

**Architecture:** The existing reconciled mission guides remain the ordered step graph. A single persisted cursor per character and native mission selects the first unfinished material step. A reducer accepts current-session mission, key-item, inventory, zone, event, interaction, and route-arrival signals; it completes at most one current step per causal signal, cancels only an obsolete objective route, and refreshes the mission browser. Informational steps are skipped, while unknown state is shown as an instruction instead of guessed.

## Task 1: Freeze corpus-wide behavior

- Add a real-corpus Lua test that loads all 15 mission contexts and proves every one of the 706 missions has a deterministic ordered step sequence.
- Assert one current step is selected, not every future destination.
- Assert note-only rows are skipped and a non-routable material step remains an instruction.
- Assert repeated targets separated by acquisition or battle evidence cannot cascade from one interaction.

## Task 2: Implement the generic cursor/reducer

- Replace the one-record interaction helper with a versioned persisted mission cursor.
- Classify `talk`, `trade`, `examine`, and `use` as interaction-completed actions; `travel` as confirmed-zone/arrival actions; `obtain`, `farm`, and item-producing `fight` as inventory/key-item predicates; `note` as informational; and `wait` as an instruction until a stronger state signal changes.
- Evaluate only the current step and advance at most once for each accepted event sequence.
- Preserve character, World, session, mission, step, target, and route ownership checks.

## Task 3: Feed exact client events

- Parse the existing 0x034 event-start and 0x05B/0x05C event-end lifecycle into the reducer, including zone-local actor and event identity.
- Reconcile on 0x056 mission snapshots, 0x055 key-item snapshots, native Inventory refresh, committed zone changes, and battlefield/event completion.
- Keep arbitrary server-only mission variables out of the client model; when they are not observable, use the route-owned exact interaction sequence and guide order.

## Task 4: Integrate mission rows and route cancellation

- Make active mission expansion show only the cursor-selected current step and its legitimate destination choices.
- When the current step completes, cancel an active route owned by that exact step; with no active route, only refresh the list.
- Never auto-start movement. The player continues to press `I` for the next step.
- Remove mission-specific follow-up and completion-key tables once equivalent corpus behavior is covered.

## Task 5: Verify and deploy

- Run the corpus test, mission/navigation wrapper, reader event wrapper, full-reader and module Lua 5.1 syntax checks, and scoped diff check.
- Verify representative sequences across nation, expansion, battlefield, item, key-item, repeated-NPC, repeated-door, travel, wait, and completed-mission transitions.
- Deploy exact addon bytes to the live Ashita addon and compare SHA-256 hashes.
