# AccessXI Continuous Route Matching Implementation Plan

> **For agentic workers:** Execute inline in the existing AccessXI workspace because the required verification targets the live Ashita addon. Do not create a worktree or commit unrelated dirty changes.

**Goal:** Replace precise recorded-route waypoint playback with continuous, speed-independent position matching and steering.

**Architecture:** Add one vertical-aware route matcher over the active walked polyline. Both route progress and the steering target consume that match, so beacon and speech derive from the player's current position rather than a monotonic index.

**Tech Stack:** Lua 5.1, Ashita addon runtime, PowerShell static/runtime regression harness.

## Global Constraints

- Preserve complete recorded walk points.
- Do not invent cross-route links or mesh-only reattachments.
- False positives are worse than silence.
- Modify `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua`, then sync it to `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`.

---

### Task 1: Add failing continuous matching regressions

**Files:**
- Create: `C:\Users\buu42\AccessXI\tools\test_nav_continuous_recorded_route_matching.ps1`
- Test: `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua`

**Interfaces:**
- Produces: expected Lua helpers `accessxi.nav_route_live_match(pos, points)` and `accessxi.nav_route_target_from_match(player, points, match, lookahead)`.

- [ ] Write a Lua harness that loads the helper slice with a minimal `T` table implementation.
- [ ] Assert stale-index forward jumps, backward correction, instant speed jumps, vertical-layer selection, lateral projection recovery, and sharp-corner preservation.
- [ ] Run the PowerShell test and verify it fails because the helpers do not exist.

### Task 2: Implement the live matcher and shared target

**Files:**
- Modify: `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua`

**Interfaces:**
- `accessxi.nav_route_live_match(pos, points, preferred_segment)` returns a table containing `segment`, `point`, `t`, `horizontal`, `vertical`, and `score`, or `nil`; the optional current segment only wins a near tie.
- `accessxi.nav_route_target_from_match(player, points, match, lookahead)` returns a safe route target or `nil`.

- [ ] Project the player onto every route segment and select the lowest vertical-aware score, breaking near-ties toward the shortest remaining route.
- [ ] Change `nav_precise_route_track_index` to set the index from the live match in either direction.
- [ ] Change `nav_precise_steering_target` to consume the live match, return the projection for a lateral detour, and otherwise walk forward along the recorded polyline.
- [ ] Make both beacon and spoken precise guidance return no target when a safe match is unavailable.
- [ ] Run the focused test and verify it passes.

### Task 3: Synchronize and verify

**Files:**
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`

- [ ] Apply the same patch to the live addon and verify both Lua files have identical SHA-256 hashes.
- [ ] Run the Lua 5.1 checker against both copies.
- [ ] Run every `C:\Users\buu42\AccessXI\tools\test_nav_*.ps1` test and require zero failures.
- [ ] Reload the addon through the existing control bridge.
- [ ] Start the West Ronfaure route and inspect fresh log evidence while moving only in bounded, releasable bursts.
