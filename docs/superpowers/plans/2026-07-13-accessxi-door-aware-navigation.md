# AccessXI Door-Aware Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route safely to NPCs whose exact endpoint lies on a bad mesh edge, and announce a nearby interactive door only when live game state verifies it.

**Architecture:** `nav_compute_route_with_zoneline_approach` keeps its normal exact query first, then uses a bounded current-mesh endpoint search only for non-area, non-zone destinations with an incomplete long route. Collision handling calls a separate live-entity door detector that requires Ashita entity type 3, a conservative name match, and route alignment; a short interaction wait suppresses competing guidance until movement resumes.

**Tech Stack:** Lua 5.1, Ashita v4 entity APIs, xiNavmesh, PowerShell regression harnesses, live AccessXI control bridge.

## Global Constraints

- Use live route state and the current installed navmesh; do not add guessed static shop or doorway routes.
- False-positive door prompts and unsafe direct routes are worse than silence.
- Do not automatically send Tab or Enter.
- Do not change area or zone-line endpoint behavior.
- Preserve all unrelated dirty-worktree changes and do not create a commit without explicit user authorization.

---

### Task 1: Reproduce the invalid endpoint route

**Files:**
- Create: `tools/test_nav_mesh_endpoint_approach.ps1`
- Read: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Execute: `tools/navprobe/bin/Release/net8.0/win-x86/publish/navprobe.exe`

**Interfaces:**
- Consumes: `accessxi.nav_compute_mesh_route`, `accessxi.nav_compute_route_with_zoneline_approach`, `accessxi.nav_arrival_radius`.
- Produces: A regression proving an exact one-point Aroro result is unsafe and a 1.5-yalm current-mesh approach is reachable.

- [x] **Step 1: Write the failing regression**

Assert that the source contains `nav_compute_mesh_endpoint_approach`, that the helper searches only inside `nav_arrival_radius(point)`, and that `nav_compute_route_with_zoneline_approach` invokes it when the exact query returns at most one point outside arrival range. Execute navprobe against Port Windurst and assert:

```text
exact Aroro endpoint: waypoint count = 1
1.5-yalm south approach: waypoint count > 1
```

- [x] **Step 2: Run the regression and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_mesh_endpoint_approach.ps1
```

Expected: FAIL because the endpoint approach helper does not exist.

### Task 2: Add the reachable endpoint fallback

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Test: `tools/test_nav_mesh_endpoint_approach.ps1`

**Interfaces:**
- Produces: `accessxi.nav_compute_mesh_endpoint_approach(player, point)` returning a multi-point route and approach metadata, or `nil`.

- [x] **Step 1: Implement the bounded probe**

Use radii `1.5`, `2.5`, `4.0`, and `6.0`, capped below the destination's existing arrival radius, and eight compass directions per ring. Call the existing raw mesh query for each generated endpoint. Accept only routes with more than one point and prefer the shortest route at the first successful radius.

- [x] **Step 2: Reject unverified direct fallback**

When an exact route has at most one point, the player is outside arrival range, and no bounded approach works, clear the route and store `navmesh returned no verified walkable path`. Route start must speak `No verified walkable route to <name> from here` instead of using the exact endpoint as a straight-line route.

- [x] **Step 3: Run the regression and verify GREEN**

Run the focused endpoint test and expect exit code 0.

### Task 3: Add verified live door instructions

**Files:**
- Create: `tools/test_nav_door_interaction_prompt.ps1`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Test: `tools/test_nav_collision_detection.ps1`
- Test: `tools/test_nav_live_entities.ps1`

**Interfaces:**
- Consumes: `accessxi.nav_live_entity_snapshot`, current route target, and collision state.
- Produces: `accessxi.nav_entity_is_verified_door`, `accessxi.nav_verified_door_ahead`, `accessxi.nav_door_prompt_for_collision`, and interaction-wait state.

- [x] **Step 1: Write and run the failing door regression**

Prove that type 3 plus a door term is accepted, while type 3 alone and a name alone are rejected. Prove the detector uses live snapshots and route alignment, and that no automatic key injection exists.

- [x] **Step 2: Implement conservative door detection**

Scan nearby live entities after a blocked collision. Require `entity.type == 3`, a conservative door-name pattern, a maximum twelve-yalm distance, and a maximum 4.5-yalm lateral offset from the forward route segment.

- [x] **Step 3: Implement interaction wait and guidance**

Speak the named Tab-and-Enter instruction through a helper called by collision handling. Suppress beacon and ordinary route updates until the player moves at least 2.5 yalms or the wait expires, then replan from the live position.

- [x] **Step 4: Run focused regressions and verify GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_door_interaction_prompt.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_collision_detection.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_live_entities.ps1
```

Expected: all exit 0.

### Task 4: Validate and deploy

**Files:**
- Verify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Sync: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`
- Inspect: `C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-menu-reader.log`

**Interfaces:**
- Consumes: validated source addon.
- Produces: byte-identical live addon and a live Aroro route with multiple mesh-derived waypoints.

- [x] **Step 1: Validate Lua 5.1 syntax**

Run `tools/check_lua51_syntax.ps1` against the source file and require `syntax ok`.

- [x] **Step 2: Sync and verify byte identity**

Copy the validated source to the live addon and require matching SHA-256 hashes.

- [x] **Step 3: Reload and test Aroro**

Send `/axi console reload`, then `/axi nav route Aroro` through the existing control bridge. The live log must show a mesh-derived endpoint approach and more than one route waypoint. It must not say to go straight for the entire wall-crossing distance.

- [x] **Step 4: Inspect for runtime errors**

Check the post-reload log for Lua errors, traceback text, and failed nav initialization. Do not claim the door interaction path was live-proven until it is exercised at an actual door.

### Task 5: Correct the live Orastery door timing and route preservation

**Files:**
- Modify: `tools/test_nav_door_interaction_prompt.ps1`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Inspect: `C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-menu-reader.log`

**Interfaces:**
- Consumes: `accessxi.nav_verified_door_ahead`, the current live route target, and door interaction state.
- Produces: `accessxi.nav_door_prompt_for_route(player, destination, route_target, now)` and directional door-crossing state.

- [x] **Step 1: Write the failing Orastery regression**

Extend the door regression to require a proactive route-level prompt within six yalms, a 2.5-second audio-only pause, and stored door position/route direction. Assert that `nav_door_waiting` contains no call to `nav_compute_route_with_zoneline_approach` and does not clear merely because total movement exceeds 2.5 yalms.

- [x] **Step 2: Run the regression and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\buu42\AccessXI\tools\test_nav_door_interaction_prompt.ps1
```

Expected: FAIL because proactive door prompting and directional crossing state do not exist, and the old wait helper still replans after arbitrary movement.

- [x] **Step 3: Implement proactive prompting and route preservation**

Add `nav_door_prompt_for_route` to the normal route update after the real route target is known. Share one prompt initializer between proactive and collision fallback paths. Store `door.x`, `door.z`, and the normalized player-to-route-target direction. Pause guidance until `now + 2500`, retain a separate fifteen-second duplicate-prompt window, and clear only after the player projects at least 1.25 yalms beyond the door along the stored direction or the context expires. Never replan from door wait state.

- [x] **Step 4: Run focused and full navigation regressions**

Run the corrected door regression, then every `tools/test_nav_*.ps1`. Expected: all exit 0.

### Task 6: Reload and verify the corrected live route

**Files:**
- Sync: `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua` to `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`
- Inspect: `C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-menu-reader.log`

**Interfaces:**
- Consumes: source addon passing Lua 5.1 syntax and all navigation tests.
- Produces: byte-identical live addon with an active Aroro route ready for another door traversal.

- [x] **Step 1: Validate and sync**

Run `tools/check_lua51_syntax.ps1`, copy the source to the live addon, and require matching SHA-256 hashes.

- [x] **Step 2: Reload and restart Aroro**

Send `/axi console reload` and `/axi nav route Aroro` through the existing external control bridge. Require a multi-waypoint endpoint-approach route and no post-reload Lua errors.
