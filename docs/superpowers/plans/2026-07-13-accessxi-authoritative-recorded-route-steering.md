# AccessXI Authoritative Recorded-Route Steering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep proven recorded La Theine corridors authoritative and stop live position updates from moving a safe recorded-route rejoin target while the player turns toward it.

**Architecture:** `nav_route_live_match` and `nav_route_target_from_match` retain their existing recovery envelope and sharp-corner safeguards. `nav_precise_steering_target` stores the first verified `live-route-return` projection as route-local state and returns that exact anchor until the player reaches it or safely regains a later segment. It emits no target beyond the verified envelope instead of selecting a new course.

**Tech Stack:** Lua 5.1, Ashita addon APIs, PowerShell regression harnesses, live AccessXI control bridge.

## Global Constraints

- Use live player coordinates and current recorded route data; do not add guessed static paths.
- False positives and unsafe connectors are worse than silence.
- Preserve the 6.0-horizontal/4.5-vertical maximum precise guidance envelope.
- Preserve sharp recorded turns of 45 degrees or more.
- Preserve genuine on-path backtracking without rewinding stored route progress.
- Precise recorded routes must not apply dynamic obstacle or wall target substitution.
- Preserve all unrelated dirty-worktree changes and do not create a commit without explicit user authorization.

---

### Task 1: Reproduce the moving rejoin target

**Files:**
- Create: `tools/test_nav_authoritative_recorded_route_steering.ps1`
- Read: `ashita/addons/accessxi_reader/accessxi_reader.lua:67676-67851`
- Read: `ashita/addons/accessxi_reader/accessxi_reader.lua:89190-89194`

**Interfaces:**
- Consumes: `accessxi.nav_project_to_segment`, `accessxi.nav_route_live_match`, `accessxi.nav_route_target_from_match`, and `accessxi.nav_precise_steering_target`.
- Produces: A failing Lua harness based on the live 5.2-yalm recovery sample.

- [x] **Step 1: Write the failing regression**

Use the recorded points around the live sample `(-539.226, 451.158, -0.994)`. Prove the initial safe target is the verified projection `(-543.880, 448.842)`. Move the player to `(-541.000, 452.000, -0.900)` and first prove an ordinary fresh match would move that projection. Then prove precise steering must continue to return the original exact anchor.

Add explicit cases proving:

- Reaching within 1.25 horizontal and 2.0 vertical yalms clears the anchor and resumes forward recorded lookahead.
- Safely reaching a later segment clears the older anchor.
- Moving beyond 6.0 horizontal or 4.5 vertical yalms returns `nil` without replacing the anchor.
- A sharp recorded turn is still not cut.
- A distant route match still produces no precise guidance.
- Precise beacon routes remain isolated from obstacle and wall target substitution.

- [x] **Step 2: Run the regression and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_authoritative_recorded_route_steering.ps1
```

Expected: FAIL because the second live position receives a newly recomputed projection instead of the original safe return anchor.

### Task 2: Implement a stable recorded-route return anchor

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:1132-1178`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:89190-89194`
- Test: `tools/test_nav_authoritative_recorded_route_steering.ps1`
- Test: `tools/test_nav_continuous_recorded_route_matching.ps1`
- Test: `tools/test_nav_precise_recorded_route_no_rewind.ps1`
- Test: `tools/test_nav_precise_beacon_next_target.ps1`

**Interfaces:**
- State: `nav_precise_return_target`, `nav_precise_return_points`, and `nav_precise_return_segment`.
- Produces: `accessxi.nav_precise_route_return_clear()` and stable-anchor behavior in `accessxi.nav_precise_steering_target()`.

- [x] **Step 1: Add route-local recovery state**

Initialize the target and points references to `nil` and the segment to zero. Add one helper that clears all three fields together.

- [x] **Step 2: Hold the first verified return point**

When ordinary precise matching produces `source = 'live-route-return'`, store that exact result with the active points table and matched segment. While it remains active:

- Return the exact same anchor inside 6.0 horizontal and 4.5 vertical yalms.
- Clear and resume ordinary matching after reaching within 1.25 horizontal and 2.0 vertical yalms.
- Clear and resume from a later match inside 3.25 horizontal and 2.0 vertical yalms.
- Return `nil`, while retaining the anchor, outside the 6.0/4.5 envelope.
- Clear it if the points-table identity changes.

Do not call navmesh, obstacle, wall, or route-replan functions.

- [x] **Step 3: Run focused tests and verify GREEN**

Run the new regression plus:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_continuous_recorded_route_matching.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_precise_recorded_route_no_rewind.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_precise_beacon_next_target.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_lathine_friend_walk_corridors.ps1
```

Expected: all exit 0, including unchanged sharp-corner and unsafe-silence assertions.

### Task 3: Validate and deploy the live addon

**Files:**
- Sync: `ashita/addons/accessxi_reader/accessxi_reader.lua` to `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`
- Verify: all `tools/test_nav_*.ps1`
- Inspect: `C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-menu-reader.log`

**Interfaces:**
- Consumes: Source Lua that passes focused behavior tests.
- Produces: Byte-identical live Lua and a clean live reload.

- [x] **Step 1: Validate Lua 5.1 syntax**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\check_lua51_syntax.ps1 -Path C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua -LuaDll C:\Users\buu42\AccessXI\tools\lua51\lua5.1.dll
```

Expected: `syntax ok` for the source file.

- [x] **Step 2: Sync and verify byte identity**

Copy the source Lua to the live addon and compare SHA-256 hashes. Expected: one unique hash.

- [x] **Step 3: Run the complete navigation suite**

Run every `tools/test_nav_*.ps1` under PowerShell execution-policy bypass. Expected: zero failures.

- [x] **Step 4: Reload through the control bridge**

Write `/axi console reload` to `ffxi-accessxi-control.pending.txt`, atomically move it to `ffxi-accessxi-control.txt`, and wait for the log to show `accessxi_reader loaded` after the handled control command.

- [x] **Step 5: Inspect live safety state**

Confirm `pol` is responsive and the fresh log contains no Lua error, stack traceback, or syntax failure. Do not start a route if the character is no longer in La Theine Plateau.
