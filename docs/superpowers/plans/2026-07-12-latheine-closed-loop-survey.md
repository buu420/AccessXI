# La Theine Closed-Loop Survey Implementation Plan

> **For agentic workers:** Execute inline in the current live session. Do not delegate, commit, reset, clean, or overwrite unrelated user changes.

**Goal:** Walk La Theine Plateau under bounded DirectInput control, collect complete live route evidence, and improve routing only where the recordings prove a safe corridor.

**Architecture:** Use the existing one-shot AXI bridge and bounded `/axi drive` pulses as the actuator, the live position sampler and route recorder as ground truth, and the current navmesh only as a proposed next waypoint source. Every movement cycle must re-read position, reject stalls/circles/menu interruptions, and preserve the full recording. Route overrides are produced only from successful walked sessions and use tight start bounds.

**Tech Stack:** Ashita v4 Lua 5.1, AccessXI Reader, FFXINav navmesh probe, PowerShell regression tests, TSV route recordings and overrides.

## Global Constraints

- Never guess a corridor from static tables.
- Current live recorder and position data are authoritative.
- Movement is foreground-only and issued in pulses of at most 500 milliseconds.
- Stop on menu/chat interruption, zoning, repeated low progress, route divergence, or unverified cliff behavior.
- Preserve complete walked paths; do not simplify shelf or ravine geometry.
- False positives and unsafe routes are worse than leaving a destination unavailable.
- Keep source and live addon/data copies byte-identical.
- Preserve all unrelated dirty-worktree changes; do not commit.

---

### Task 1: Baseline route integrity

**Files:**
- Inspect: `C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv`
- Inspect: `C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv`
- Test: `C:\Users\buu42\AccessXI\tools\test_nav_*.ps1`

- [ ] Run Lua 5.1 syntax checks for source and live addons.
- [ ] Run the route recorder, drive, La Theine escape, shelf, collision, zone-search, and zone-transition regression tests.
- [ ] Record failures before any route-data edit.

### Task 2: Closed-loop live survey

**Interfaces:**
- Consumes: `/axi drive 2|4|6|8 <50..500>`, `/axi record start|stop`, live position log entries.
- Produces: append-only session `latheine_ai_survey_*` with exact walked samples.

- [ ] Start one named recorder session from the current live position.
- [ ] Query the current navmesh path toward a known-safe La Theine connector.
- [ ] Rotate toward each proposed waypoint using short pulses and verify yaw.
- [ ] Move using bounded forward pulses, checking position and progress after each batch.
- [ ] Stop on repeated progress below 0.2 yalms, menu/chat interruption, zone change, or evidence of a loop.
- [ ] Walk to a known safe connector or stop cleanly with a marked failure note.

### Task 3: Route evidence review

- [ ] Group the new recorder rows by session and verify monotonic progress.
- [ ] Compare the walked geometry with existing recorded ravine corridors.
- [ ] Reject probe-only, stationary, stalled, incomplete, or unsafe sessions.
- [ ] Select only complete walked-safe sessions for integration.

### Task 4: Focused route repair

**Files:**
- Modify if evidence supports it: `C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv`
- Modify if evidence supports it: `C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv`
- Test: focused `C:\Users\buu42\AccessXI\tools\test_nav_lathine_*.ps1`

- [ ] Write a failing focused selector/path regression before changing route data.
- [ ] Add or tighten only the evidence-backed route rows.
- [ ] Run the focused test and confirm source/live data hashes match.

### Task 5: Final verification

- [ ] Rerun both Lua 5.1 syntax checks.
- [ ] Rerun all focused nav and recorder regression tests.
- [ ] Confirm no recorder remains active and no drive key remains held.
- [ ] Report walked sessions, accepted changes, rejected evidence, and any remaining unsafe areas.
