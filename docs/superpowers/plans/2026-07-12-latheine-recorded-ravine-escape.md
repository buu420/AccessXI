# La Theine Recorded Ravine Escape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the complete `20260712-143554-z102` walked path a universal escape prefix for navigation requests from its proven La Theine ravine start pocket.

**Architecture:** Store all 323 ordered recorder coordinates as a dedicated route-override corridor. Before destination-specific overrides or mesh routing, detect navigation requests from the corridor's tight start bounds, follow the recorded corridor, then append an existing override or navmesh/zone-line tail computed from the recorded endpoint. Reject the combined route if the tail fails or quarantine rules reject it.

**Tech Stack:** Lua 5.1, Ashita v4 addon APIs, tab-separated navigation data, PowerShell regression tests, AccessXI `navprobe`/Lua 5.1 validation tools.

## Global Constraints

- The live recorder session `20260712-143554-z102` is authoritative.
- Preserve the start, all 321 movement points, and the distinct stop coordinate in order; do not downsample, smooth, average, or synthesize ravine points.
- Activation bounds must stay within five yalms of start `(-339.820, 375.467)`.
- The escape applies to any destination outside the start pocket, not only West Ronfaure.
- A combined route is returned only when its computed tail succeeds and passes existing quarantine checks.
- Keep all three override-data copies byte-identical and both Lua copies byte-identical.
- Do not change destination data, zone-line graph data, recorder behavior, enemy tracking, other route definitions, installer files, or character-specific state.
- Preserve unrelated dirty-worktree changes; do not initialize, push, reset, or clean Git state.

---

## File Map

- Create `C:\Users\buu42\AccessXI\tools\test_nav_lathine_recorded_ravine_escape.ps1`: focused structural and behavioral regression test.
- Modify `C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv`: authoritative 323-point escape corridor.
- Modify `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv`: source-addon synchronized corridor.
- Modify `C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv`: live-addon synchronized corridor.
- Modify `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua`: universal prefix selection and safe-tail composition.
- Modify `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`: synchronized live logic.

---

### Task 1: Add the focused failing regression test

**Files:**
- Create: `C:\Users\buu42\AccessXI\tools\test_nav_lathine_recorded_ravine_escape.ps1`

**Interfaces:**
- Consumes: recorder TSV columns `session,event,seq,zone,x,z,y`; override TSV columns documented in its header; Lua source text.
- Produces: a single exit-zero check ending with `nav La Theine recorded ravine escape checks passed`.

- [ ] **Step 1: Write a focused test that imports recorder and override TSV files**

The test must select session `20260712-143554-z102`, assert 323 rows with counts `start=1`, `point=321`, `stop=1`, and compare every selected override waypoint coordinate to the recorder coordinate with exact three-decimal strings.

```powershell
$sessionId = '20260712-143554-z102'
$routeId = 'lathine-recorded-ravine-escape-20260712'
$recorded = @(Import-Csv -LiteralPath $recordingPath -Delimiter "`t" | Where-Object session -eq $sessionId)
$override = @(Import-Csv -LiteralPath $sourceOverridesPath -Delimiter "`t" -Header $overrideHeaders |
    Where-Object route_id -eq $routeId)
if ($recorded.Count -ne 323) { throw "Expected 323 recorded rows; found $($recorded.Count)." }
if ($override.Count -ne $recorded.Count) { throw "Expected complete recorded coordinate sequence." }
for ($i = 0; $i -lt $recorded.Count; $i++) {
    foreach ($axis in @('x', 'z', 'y')) {
        if ($override[$i].("waypoint_$axis") -ne $recorded[$i].$axis) {
            throw "Recorded coordinate mismatch at sequence $($i + 1), axis $axis."
        }
    }
}
```

The same test must assert the data-row bounds are exactly `-344.820`, `-334.820`, `370.467`, `380.467`; the source value is `live-route-recording-20260712-143554-z102`; confidence is `proven`; sequence values are `1..323`; all three data hashes match; both Lua hashes match; and Lua contains these functions and planner call:

Its behavioral source checks must also prove that the prefix is destination-independent, so a West Ronfaure waypoint, another La Theine destination, and a cross-zone next-hop waypoint are not filtered by destination name.

```powershell
Assert-Match $lua 'function accessxi\.nav_lathine_recorded_ravine_escape_route\(player, point\)'
Assert-Match $lua 'nav_route_override_points\(handoff, point\)'
Assert-Match $lua 'nav_compute_mesh_route\(handoff, point\)'
Assert-Match $lua 'local recorded_ravine_escape = accessxi\.nav_lathine_recorded_ravine_escape_route\(player, point\)'
Assert-Match $lua "route_id == 'lathine-recorded-ravine-escape-20260712'"
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_lathine_recorded_ravine_escape.ps1'
```

Expected: failure because route ID `lathine-recorded-ravine-escape-20260712` and the Lua helper do not exist.

---

### Task 2: Import the complete walked corridor

**Files:**
- Modify: `C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv`
- Modify: `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv`
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv`

**Interfaces:**
- Consumes: all 323 rows from recorder session `20260712-143554-z102`.
- Produces: route group `lathine-recorded-ravine-escape-20260712`, loaded by `nav_load_route_overrides()`.

- [ ] **Step 1: Generate the exact route rows from the recorder in memory**

For sequence `1..323`, generate the exact TSV rows in memory while copying `x,z,y` without numeric transformation:

```powershell
$recorded = @(Import-Csv -LiteralPath 'C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv' -Delimiter "`t" |
    Where-Object session -eq '20260712-143554-z102' |
    Sort-Object { [int]$_.seq })
$generatedRows = for ($i = 0; $i -lt $recorded.Count; $i++) {
    $sequence = $i + 1
    $row = $recorded[$i]
    @(
        'lathine-recorded-ravine-escape-20260712', '102', 'Recorded ravine escape handoff',
        '-563.557', '663.512', '0.823', '2.0',
        '-344.820', '-334.820', '370.467', '380.467',
        [string]$sequence, $row.x, $row.z, $row.y,
        'live-route-recording-20260712-143554-z102', 'proven',
        "complete walked ravine escape sequence $sequence"
    ) -join "`t"
}
$generatedRows -join "`r`n"
```

- [ ] **Step 2: Apply the same 323 rows immediately before the existing first La Theine route in all three files**

Use one `apply_patch` update per file. Do not mechanically rewrite unrelated rows or line endings.

- [ ] **Step 3: Run the focused test**

Expected: it must still fail because the Lua universal-prefix helper is absent, while the coordinate and copy assertions pass.

---

### Task 3: Compose the universal escape with a safe tail

**Files:**
- Modify: `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua` near `nav_route_override_points`, `nav_route_precise_override_active`, and `nav_compute_route_with_zoneline_approach`.
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua` at the identical locations.

**Interfaces:**
- Consumes: `player`, the current route waypoint `point`, loaded route ID `lathine-recorded-ravine-escape-20260712`, `nav_route_override_points`, `nav_compute_mesh_route`, `nav_zoneline_approach_candidates`, `nav_route_quarantine_reason`.
- Produces: `accessxi.nav_lathine_recorded_ravine_escape_route(player, point) -> T{route points}`; returns an empty table when inactive or unsafe.

- [ ] **Step 1: Add the route builder before `nav_compute_route_with_zoneline_approach`**

Implement these exact guards:

```lua
if player == nil or point == nil then return T{}; end
if (tonumber(player.zone) or 0) ~= 102 or (tonumber(point.zone) or 0) ~= 102 then return T{}; end
-- Find the loaded route by exact ID.
-- Require player x/z inside the route's min/max bounds.
-- Return empty when destination x/z is also inside those same bounds.
```

Copy the loaded corridor, determine the nearest valid recorded start index with `nav_route_override_start_index`, and set the last recorded waypoint as `handoff`. Try `nav_route_override_points(handoff, point)` first. If it returns no tail, call `nav_compute_mesh_route(handoff, point)` and then existing zone-line approach candidates when required. Append tail points starting at index 2 so the handoff is not duplicated.

Before returning, call:

```lua
local quarantine = accessxi.nav_route_quarantine_reason(points, point);
if quarantine ~= '' then
    accessxi.nav_route_last_reject_reason = quarantine;
    return T{};
end
```

Do not append the destination directly when both override and mesh/zone-line tail construction fail.

- [ ] **Step 2: Call the builder first in the normal planner**

At the beginning of `nav_compute_route_with_zoneline_approach`, before older lower-ravine and destination-specific routes:

```lua
local recorded_ravine_escape = accessxi.nav_lathine_recorded_ravine_escape_route(player, point);
if recorded_ravine_escape:len() > 1 then
    return recorded_ravine_escape, nil;
end
```

- [ ] **Step 3: Keep the combined route precise**

In `nav_route_precise_override_active`, return true for route ID `lathine-recorded-ravine-escape-20260712` so replanning cannot substitute a shortcut for the recorded sequence.

- [ ] **Step 4: Sync the exact Lua change to the live addon with `apply_patch`**

Do not copy over or overwrite unrelated source/live differences. Confirm the two files are byte-identical after the targeted edits.

- [ ] **Step 5: Run focused test and Lua syntax checks**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_lathine_recorded_ravine_escape.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\check_lua51_syntax.ps1' -Path 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua' -LuaDll 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.dll'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\check_lua51_syntax.ps1' -Path 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua' -LuaDll 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.dll'
```

Expected: all pass and both syntax checks print `syntax ok`.

---

### Task 4: Run navigation regression verification

**Files:**
- Verify only; no new production edits unless a test exposes a directly related defect.

**Interfaces:**
- Consumes: completed data and Lua changes.
- Produces: evidence that the new prefix did not break existing recorder, La Theine, zone-search, destination deduplication, or zone-settle behavior.

- [ ] **Step 1: Run focused existing checks**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_lathine_shelf_escape.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_lathine_telepoint_approach.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_route_recorder.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_zone_search_command.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_static_destination_preempts_live_duplicate.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_zone_load_settle_guard.ps1'
```

Expected: every command exits zero with its existing success message.

- [ ] **Step 2: Verify hashes and targeted diff**

Confirm one unique hash across the three override files and one unique hash across the two Lua files. Inspect a path-limited `git diff` without resetting, cleaning, staging, committing, or touching unrelated changes.

- [ ] **Step 3: Live handoff**

Tell the user to run `/addon reload accessxi_reader`, return to the recorded fall pocket, choose multiple destinations, and report the spoken/logged route result. Do not claim live success until the character walks the route.
