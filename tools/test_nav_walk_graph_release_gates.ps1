# Executable gates for the zone-102 walk graph being ON.
#
# The switch was defaulted off for four named integration defects, and the
# banner describing them stayed stale for weeks after three of them were fixed.
# Prose cannot hold a release open; these assertions can. Each one below is a
# specific defect that actually happened, expressed as something that fails.

param([string]$Addon = 'C:\Users\buu42\Ashita\addons\accessxi_reader')

$ErrorActionPreference = 'Stop'

$live   = $Addon
$env:ACCESSXI_ADDON = $Addon
$env:ACCESSXI_ROOT = Split-Path -Parent $PSScriptRoot
$module = Join-Path $live 'modules\walk_graph_route.lua'
$main   = Join-Path $live 'accessxi_reader.lua'
$match  = Join-Path $live 'modules\walk_graph.lua'
$artifact = Join-Path $live 'data\walkgraph\zone-102.axwg'

foreach ($p in @($module, $main, $match, $artifact)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing: $p" }
}

$moduleText = Get-Content -Raw -LiteralPath $module
$mainText   = Get-Content -Raw -LiteralPath $main

function Assert([bool]$ok, [string]$what) {
    if (-not $ok) { throw "GATE FAILED: $what" }
    Write-Host "  ok  $what"
}

Write-Host 'Artifact identity (a swapped or stale graph must not load):'

$size = (Get-Item -LiteralPath $artifact).Length
$sha  = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToLower()

if ($moduleText -notmatch "local GRAPH_FILE_SIZE = (\d+);") { throw 'GRAPH_FILE_SIZE not found' }
Assert ([int64]$Matches[1] -eq $size) "pinned GRAPH_FILE_SIZE matches the deployed artifact ($size)"

if ($moduleText -notmatch "(?s)local GRAPH_SHA256 =\s*'([0-9a-f]{64})';") { throw 'GRAPH_SHA256 not found' }
Assert ($Matches[1] -eq $sha) 'pinned GRAPH_SHA256 matches the deployed artifact'

Write-Host 'Defect 1 -- a cached steering target must not skip the sightline clamp:'
Assert ($mainText -match 'if \(not walk_graph_aim\) then\s*\r?\n\s*return precise_target;') `
    'the early cached-target return is guarded by walk_graph_aim'
Assert ($mainText -match "(?s)nav_route_points_override_id\(accessxi\.nav_route_points\)\s*\r?\n?\s*== 'lathine-walk-graph-v2'\) then\s*\r?\n\s*detour = nil;") `
    'the shipped mesh is withheld as the detour source on a walk-graph route'

Write-Host 'Defect 2 -- a search that outlived its owner must not restart navigation:'
Assert ($mainText -match "nav_route_ownership_advance\('route-stop', true\)") `
    'stopping a route bumps the ownership generation'
Assert ($mainText -match 'accessxi\.nav_walk_graph_pending = nil;') `
    'the ownership advance clears any pending walk-graph request'
Assert ($mainText -match 'owner_generation') `
    'pending walk-graph requests carry an owner generation'

Write-Host 'Defect 3 -- the tracker must not jump forward across the zone:'
Assert ($mainText -match "route_id == 'lathine-walk-graph-v2'") `
    'the walk-graph route is treated as self-crossing by the live matcher'
Assert ($mainText -match 'forward_distance \+ segment_distance > 24\.0') `
    'the forward match corridor is bounded at 24 yalms'

Write-Host 'Defect 4 -- connectors must be proven, not measured:'
Assert ($moduleText -match 'local function connector_proven') `
    'connector_proven exists'
Assert ($moduleText -match 'pcall\(connector_proven,') `
    'certify_candidates actually calls it'
Assert ($moduleText -match 'tonumber\(point\.component_id\) ~= standing') `
    'a candidate on different ground from the player is refused'

Write-Host 'The invariant that makes this releasable -- no Recast fallback after a graph refusal:'
Assert ($mainText -match "wg_mode == 'no-path' or wg_mode == 'unreachable' or wg_mode == 'rejected'") `
    'typed refusals are recognised'
Assert ($mainText -match '(?s)if \(walk_graph_restricted\) then.*?return T\{\}, nil;') `
    'a graph refusal stops before the shipped navmesh rather than falling through'

Write-Host 'Waypoint spacing -- long funnel legs make the beacon thrash:'
Assert ($moduleText -match 'local MAX_LEG = 8\.0;') `
    'emitted legs are capped at 8 yalms'
Assert ($moduleText -match 'return densify\(points, route_component\);') `
    'build_points actually densifies before returning'
Assert ($moduleText -match 'local DENSIFY_CORRIDOR_VERTICAL = 2\.0;') `
    'densified points are CORRIDOR-local: a vertical bound against the leg itself exists'
Assert ($moduleText -match 'math\.abs\(ey - my\) <= DENSIFY_CORRIDOR_VERTICAL') `
    'ground beyond the corridor bound cannot vouch for a waypoint (post-repair, component is not enough)'
Assert ($moduleText -match 'max_vertical = 3\.0') `
    'the densify search band is narrowed to the corridor scale'
Assert ($moduleText -notmatch '::continue::') `
    'no goto/label syntax (the project validates against Lua 5.1)'

Write-Host 'A refusal must END navigation, not be retried forever:'
Assert ($mainText -match 'accessxi\.nav_walk_graph_refusal = T\{') `
    'a typed refusal is stamped with the destination that earned it'
Assert ($mainText -match '(?s)local refusal = accessxi\.nav_walk_graph_refusal;.*?refusal\.destination == destination.*?accessxi\.nav_active = false;') `
    'the route poll stops navigation on a refusal instead of retrying it'
Assert ($mainText -match '(?s)function accessxi\.nav_mesh_probe_path.*?refusal\.destination == accessxi\.nav_destination.*?return nil;') `
    'the synchronous mesh FindPath is refused for an already-refused destination'
Assert ($mainText -match 'accessxi\.nav_walk_graph_refusal = nil;') `
    'the refusal is cleared when route ownership changes'

$sightText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\beacon_sightline.lua')
Assert ($sightText -match 'local probe_deadline = tick\(\) \+ 120;') `
    'the detour walkability loop is time-bounded on the render thread'

Write-Host 'Zone lines are areas you walk into, not points you stand on:'
Assert ($moduleText -match 'local function is_area_destination') `
    'area destinations are recognised'
Assert ($moduleText -match 'local APPROACH_VERTICAL = 16\.0;') `
    'area goals use a widened vertical window'
Assert ($moduleText -match 'local APPROACH_RESULTS = 512;') `
    'the candidate cap is large enough to see past a stranded islet'
Assert ($moduleText -match 'certify_candidates\(goals,[\s\S]{0,200}start_component, area_goal\)') `
    'goal candidates are anchored on the PLAYER''s component, not the destination''s'

# Ordering is load-bearing: declared after certify_candidates these resolve to
# nil globals and the `and/or` idiom silently falls back to the tight limits.
$iApproach = $moduleText.IndexOf('local APPROACH_HORIZONTAL')
$iCertify  = $moduleText.IndexOf('local function certify_candidates')
Assert ($iApproach -gt 0 -and $iCertify -gt 0 -and $iApproach -lt $iCertify) `
    'APPROACH_* are declared BEFORE certify_candidates (nil-global fallback is silent)'

Write-Host 'One aim source -- the mesh may not steer a certified route:'
Assert ($mainText -match "aim_source == 'navmesh' or aim_source == 'sightline-detour'") `
    'mesh-derived aim points are rejected at the final gate'
Assert ($mainText -match "source = 'walk-graph-owned';") `
    'a rejected aim falls back to the route''s own waypoint, not to silence'
Assert ($mainText -match "(?s)function accessxi\.nav_mesh_probe_path.*?== 'lathine-walk-graph-v2'\) then\s*\r?\n\s*return nil;") `
    'the mesh probe refuses outright while a walk-graph route is active'
Assert ($mainText -match "or route_id == 'lathine-walk-graph-v2';") `
    'the walk-graph route uses the smoothed lookahead (no 2-yalm carrot)'

Write-Host 'Native path queries must not repeat at frame rate:'
Assert ($mainText -match 'accessxi\.nav_mesh_probe_memo') `
    'nav_mesh_probe_path memoizes results between frames'
Assert ($mainText -match 'return probe_remember\(nil\);') `
    'failed lookups are memoized too -- the expensive case is the failure'
Assert ($mainText -match 'nav mesh probe SLOW') `
    'a slow probe call logs its endpoints for attribution'

Write-Host 'Zone-line anchors must certify ENTRY, and cues must not lie about height:'
Assert ($moduleText -match 'local function approach_proven')
    'area anchors are certified by marching to the volume lip, not by proximity'
Assert ($moduleText -match 'route_component ~= nil')
    'densified waypoints may only snap to the route''s own component'
Assert ($mainText -match 'Height down %.0f...:fmt')
    'the vertical cue phrase maps dy>0 (lower, y is DOWN) to Height down'
Assert ($moduleText -match 'return densify\(points, route_component\);')
    'build_points densifies with the route component'
Write-Host 'Entry-layer agreement -- the march terminal must stand on the reachable layer nearest the trigger:'
Assert ($moduleText -match 'local function entry_layer_agrees') `
    'entry_layer_agrees exists'
Assert (([regex]::Matches($moduleText, 'entry_layer_agrees\(graph,')).Count -ge 4) `
    'every approach_proven terminal consults entry-layer agreement (short-circuit, ground-ends, step-break, loop-end)'

Write-Host 'Final approach -- reaching a zone-line anchor is NOT arrival:'
Assert ($mainText -match 'accessxi\.nav_final_approach = T\{ key = final_approach_key') `
    'a zone-line proximity enters final approach instead of completing'
Assert ($mainText -match 'and not final_approach_active') `
    'an active final approach suppresses the arrival branch so guidance continues'
Assert (([regex]::Matches($mainText, 'accessxi\.nav_final_approach = nil;')).Count -ge 2) `
    'final approach clears on zone change AND on route ownership change'
Assert ($mainText -match 'nav final approach begin') `
    'entering final approach is logged'
Assert ($mainText -match 'nav final approach TIMEOUT') `
    'a final approach that produces no zone change in 60s stops with an honest spoken refusal'
Assert ($mainText -match '(?s)nav final approach TIMEOUT.*?return;\r?\n\s*end\r?\n\s*end\r?\n\s*if \(destination_vertical_reached') `
    'the timeout is checked before the arrival gate so it cannot be starved'

Write-Host 'Pending means silent -- no bearing, no beacon, no mesh while the graph is still planning:'
Assert ($mainText -match "nav_beacon_exit\('walk-graph-pending', now\)") `
    'the beacon pulse exits while the walk graph is pending with no route'
# The wording changed and the contract grew a deadline. "verified" was a
# promise this build has not earned (sol): the doorways are certified against
# source geometry, but the walkable surface is not eroded by body radius.
Assert ($mainText -match "speak\('Still planning the route\. No direction is ready yet\.'\)") `
    'the heartbeat says there is no direction yet rather than promising a verified route'
Assert ($mainText -notmatch 'Still planning the verified route') `
    'and nothing still calls an unearned route verified'

# A PLAN MUST BE ABLE TO GIVE UP. On 2026-08-23 the planner heartbeat "still
# planning" for over 150 seconds with no deadline of any kind, while the beacon
# stayed suppressed -- the player heard nothing else and concluded the addon had
# died. Offline the identical request finishes in 304 polls / 1.23s of CPU.
Assert ($mainText -match 'nav walk graph TIMED OUT') `
    'a plan that has run too long gives up and says so'
Assert ($mainText -match 'if \(elapsed >= 30000\) then') `
    'and the deadline is thirty seconds from the original request'
Assert ($mainText -match 'started_tick = tick\(\),') `
    'measured from when the request was made, so a phase change cannot reset it'
Assert ($mainText -match 'nav_walk_graph_timeout_until = now \+ 60000') `
    'a timeout suppresses the planner briefly so falling through cannot re-enter it'
Assert ($mainText -match '%s Using the map to %s instead\. It may be unreliable\.') `
    'a fallthrough after timeout is disclosed rather than silently substituted'
Assert ($mainText -match 'no other route was available\. Navigation stopped\.') `
    'and when nothing else answers, navigation stops instead of retrying forever'
Assert ((([regex]::Matches($mainText, 'walk_graph_restricted = true')).Count) -eq 1) `
    'exactly one branch may restrict what answers after the walk graph'
Assert ($mainText -match "wg_mode == 'no-path' or wg_mode == 'unreachable' or wg_mode == 'rejected'\) then\r?\n\s*walk_graph_restricted = true;") `
    'and it is the certified refusal branch -- a timeout is not evidence about connectivity'

# The datum that settles WHY it stalled. sol read the log as starvation to one
# slice per 7.5s; the beacon roll-up reads as a healthy 29Hz. Both fit every
# line we had, so the gap between consecutive polls is now recorded.
Assert ($mainText -match 'nav walk graph progress destination=') `
    'the planner reports its phase and progress while pending'
Assert ($mainText -match 'anchor=\[%s\]') `
    'and names the ground it anchored to -- same coordinates and artifact converged offline, so the anchors are the next suspect'

Write-Host 'A budget is not a proof -- running out of expansions must not silence every other provider:'
# 2026-08-24: the search reported no-path with "the search did not converge" --
# an expansion-cap exhaustion. no-path sets walk_graph_restricted, which blocks
# the navmesh AND the recorded overrides, so the player got no route at all in
# a zone where the same search converges offline in 91 slices with a 230-point
# route. The cap was never the limit; treating it as evidence hid the real bug.
Assert ($moduleText -match "reject\('budget'") `
    'exhausting the expansion budget is classified as a budget result'
Assert ($moduleText -notmatch 'The search did not converge') `
    'and is no longer dressed up as a proof that no path exists'
Assert ($mainText -match "if \(wg_mode == 'budget'\) then") `
    'the route builder handles a budget result distinctly'
Assert ($mainText -notmatch "wg_mode == 'budget' or wg_mode == 'no-path'") `
    'and never folds it in with the certified refusals that do restrict'
Assert ($mainText -match 'I could not finish planning a safe route\.') `
    'the fallthrough after a budget result is disclosed, not silently substituted'

Write-Host 'A refusal to one catalogue row is not a refusal to the place:'
# Shattered Telepoint has TWO rows in La Theine, 7 yalms apart horizontally and
# 5 apart in height, and they are not equivalent to the planner:
#   (334.0,-56.6,24.1) -> converges, 230 points, 66k expansions
#   (340.0,-60.0,19.1) -> genuine no-path, confirmed with the cap raised to 8M
# The picker aimed at the second, so the player was told there was no walkable
# way to a place that routes fine from the row next to it.
Assert ($mainText -match 'function accessxi\.nav_walk_graph_sibling_row\(destination, allow_bad\)') `
    'the planner can try another catalogue row for the same place'
# A confidence=bad row is opt-in. The caller reaches the proven-mark approach
# ONLY when the sibling lookup returns nil, so handing back a row the catalogue
# calls wrong -- which happens to sit on walkable ground -- routed the player to
# the bottom of the La Theine telepoint stairs and announced arrival. Good rows,
# then the approach, then a bad row.
Assert ($mainText -match 'sibling = accessxi\.nav_walk_graph_proven_approach\(player, destination\)') `
    'and falls back to a proven mark when no good row routes'
Assert ($mainText -match 'sibling = accessxi\.nav_walk_graph_sibling_row\(destination, true\)') `
    'and a bad row remains available only as a last resort'
Assert ($mainText.IndexOf('sibling = accessxi.nav_walk_graph_proven_approach(player, destination)') -lt `
        $mainText.IndexOf('sibling = accessxi.nav_walk_graph_sibling_row(destination, true)')) `
    'and the approach is tried BEFORE any bad row'
Assert ($mainText -notmatch 'local function nav_walk_graph_sibling_row') `
    'and it lives on the accessxi table -- this chunk is at Lua 5.1 ceiling of 200 main-function locals'
Assert ($mainText -match 'nav walk graph retrying sibling row destination=') `
    'a sibling retry is logged'
Assert ($mainText -match "if \(mode == 'budget' or mode == 'unreachable' or mode == 'no-path'\) then\r?\n\s*local sibling = accessxi\.nav_walk_graph_sibling_row\(destination\);") `
    'and even a certified no-path tries the other rows before refusing the place'
Assert ($mainText -match 'nav_walk_graph_tried_rows') `
    'rows already tried are remembered so the retry cannot loop'
Assert ($mainText -match 'function accessxi\.nav_walk_graph_fall_through\(player, destination, now, lead\)') `
    'one shared fallthrough serves the deadline and every non-proof refusal'
Assert ($mainText -match "if \(mode == 'budget' or mode == 'unreachable' or mode == 'unavailable'\) then") `
    'the pending path falls through on a non-proof refusal instead of stopping navigation'

Write-Host 'Lead them the rest of the way -- do not retarget to a different spot:'
# The height snap was MY invention and the player's own trace refuted it. Walked
# positions in zone 102: Telepoint closest 0.0 yalms at y=19.1 (102 samples);
# Dimensional Portal 0.3 at 19.1; Shattered Telepoint 0.3 at 24.0 and 2.1 at
# 19.1. They have stood on the y=19.1 ground the walk graph calls unreachable
# and walked the whole range 19.1..24.4 to get there. So the catalogued
# coordinate is right and the GRAPH is wrong; snapping the goal up to the rim
# aimed somewhere they never asked for -- "it missed the stairs to climb to get
# to the telepoint". The stairs objects are mapped and route fine; only the last
# stretch onto the point is missing, so hand off and keep guiding.
Assert ($mainText -notmatch 'point = accessxi\.nav_row_matching_player_height\(player, point\);') `
    'the goal is no longer retargeted to the player height'
Assert ($mainText -match 'nav residual handoff from=') `
    'reaching the stand-in hands off to the real point instead of ending the route'
Assert ($mainText -match "source = 'residual-handoff',") `
    'the real point is appended to the route so guidance continues'
Assert ($mainText -match 'At %s\. Continuing to %s\.%s I could not verify this last stretch\.') `
    'the hand-off is announced and the unverified leg is disclosed'
Assert ($mainText -match "drop < 0 and 'down' or 'up'") `
    'and the player is told which way the steps go'
Assert (([regex]::Matches($mainText, 'accessxi\.nav_residual_handoff_key = nil;')).Count -ge 2) `
    'the hand-off latch resets with route ownership so it can fire for the next destination'

Write-Host 'Ground the player has stood on is the best evidence we have:'
# The Telepoint, Shattered Telepoint and Dimensional Portal npc rows are ALL
# catalogued at y ~= 19.1 while their platform is y ~= 24, and all three refuse
# however wide the approach envelope is opened (the 16-yalm area envelope fails
# exactly as the 4-yalm one does -- measured). The player's own proven recorded
# marks 21-23 yalms away route in 7, 28 and 27 points.
Assert ($mainText -match 'function accessxi\.nav_walk_graph_proven_approach\(player, destination\)') `
    'an unreachable destination can be approached by the nearest proven recorded mark'
Assert ($mainText -match "nav_clean_field\(row\.confidence\):lower\(\) == 'proven'") `
    'and only ground the player actually walked qualifies'
Assert ($mainText -match 'if \(gap <= 30\.0\) then') `
    'within thirty yalms, so the mark is the same structure and not the next landmark'
Assert ($mainText -match 'cannot be reached directly\. Routing to %s, %d yalms from it\.') `
    'and the player is told the target is a little further on'
Assert ($mainText -match 'nav walk graph approaching by proven mark target=') `
    'the stand-in is logged with the gap it covers'

Write-Host 'Arriving somewhere else is not arriving:'
# 2026-08-24: the height substitution moved the Shattered Telepoint goal up from
# y=19.1 to y=24.1, the route ran, and it said "Arrived at Shattered Telepoint"
# while standing on the RIM of a sunken hollow with the telepoint five yalms
# below. The player: "it missed the stairs to climb to get to the telepoint."
#
# Measured from the rim: the west steps are reachable only down to y=22.4
# (16 points); y=20.4, the hollow floor at 19.4, and the telepoint row itself
# are all severed -- while every one of them is LABELLED component 54, the same
# as the rim. The component ids claim connectivity the edges do not provide.
# We cannot route down there yet, but we must not call the rim an arrival.
Assert ($mainText -match 'moved\.residual_label = nav_clean_field\(point\.name\);') `
    'a height substitution records the place it moved away from'
Assert ($mainText -match 'approach\.residual_label = nav_clean_field\(destination\.name\);') `
    'and so does an approach by proven mark'
Assert ($mainText -match 'is about %d yalms away%s\. I could not verify a route to it from here\.') `
    'arrival says how far the real target still is and that no route to it was verified'
Assert ($mainText -match "vertical < 0 and 'below' or 'above'") `
    'including whether it is above or below, which is the part the rim hid'
Assert ($mainText -match 'nav arrival residual target=') `
    'and the residual is logged'
# No compass word: the only bearing helper takes FFXI player yaw and does not
# share a convention with a world-space delta. A confidently wrong direction is
# worse for a blind player than no direction at all.
Assert ($mainText -notmatch 'residual[^\r\n]*nav_compass_direction') `
    'no compass direction is guessed for the residual'

Write-Host 'A provider failing is not a place being unreachable:'
# 2026-08-24, Chateau d'Oraguille: the player picked Halver from 34 indexed NPCs
# and got no route, because the terrain provider answered "MZB contains no
# referenced collision geometry" -- this zone having no DAT collision to read,
# not Halver being unreachable. The zone's navmesh was loaded and sitting there.
Assert ($mainText -match 'nav_dat_collision_zone_unsupported') `
    'a zone with no collision geometry is remembered rather than retried'
Assert ($mainText -match 'collision terrain unavailable zone=') `
    'and the capability failure is logged distinctly from a real refusal'
Assert ($mainText -match 'This zone has no verified terrain data\.') `
    'the terrain provider falls through to the map instead of ending navigation'
Assert ($mainText -notmatch "speak\(text\);\r?\n\s*log_line\('collision terrain route stopped") `
    'and the internal MZB reason is never read out loud'
# The half that was missing the first time: recording the zone is useless if
# nothing reads it, and the caller treated 'error' as FINAL -- returning an empty
# route without falling through to nav_compute_mesh_route on the very next line.
Assert ($mainText -match "return T\{\}, 'unsupported', '';") `
    'a zone flagged as having no collision data skips the terrain provider outright'
Assert ($mainText -match "collision_mode = 'unsupported';") `
    'and the first capability failure drops to the mesh rather than returning empty'
Assert ($mainText -match 'collision terrain unsupported zone=') `
    'the substitution is logged'
Assert ($mainText -match 'function accessxi\.nav_dat_collision_route_attempt\(player, point\)') `
    'the real attempt sits behind the unsupported-zone guard'

Write-Host 'A key item that arrives must advance the step:'
# 2026-08-24, The Davoi Report. The player obtained the Lost document -- the
# 0x055 packet arrived, the game said "Obtained key item: Lost document." -- and
# the step did not move. previous_complete demanded that the PREVIOUS snapshot of
# that same table also arrived as a packet in this same session, but the server
# sends 0x055 for a table only when it CHANGES, so the packet delivering a key
# item is routinely the first for its table. One 0x055 for table 0 that whole
# hour: the one carrying it. "key-item-delta" appeared ZERO times in a
# 956,000-line log -- the path had never once fired.
Assert ($mainText -match 'previous_from_cache') `
    'a restored key-item cache counts as a baseline for the delta'
Assert ($mainText -match '\(previous_from_packet or previous_from_cache\)') `
    'so the first packet of a session can still produce an acquisition'
Assert ($mainText -notmatch "previous_complete = #previous_flags == 64\r?\n\s*and tostring\(accessxi\.key_items_packet_source or ''\) == 'packet_in_055'") `
    'and the in-session-packet-only requirement is gone'
Assert ($mainText -match 'before_owned = false, after_owned = true') `
    'only a false to true transition is ever emitted, so a stale baseline cannot invent an acquisition'

Write-Host 'And a second, independent witness for it:'
# A missed completion can never be re-observed, so this class gets two witnesses.
Assert ($mainText -match "Obtained key item:%s\*\(\.-\)") `
    'the game saying "Obtained key item" is read as completion evidence'
Assert ($mainText -match 'objective key item obtained name=') `
    'and it is logged'
Assert ($mainText -match "kind = 'key-item-delta',\r?\n\s*key_item_id = 0,") `
    'the chat witness feeds the same reducer path as the packet'

Write-Host 'Both detour call sites obey the same hold:'
# 2026-08-25, stuck in Valkurm Dunes at (90.0,-115.5). nav_beacon_route_target
# guards its detour with nav_beacon_detour_permitted and a two-second hold; the
# guidance path called the detour EVERY PULSE with no check and no mode note.
# Within one second: pursuit delta +114 (forward, up a bank), detour delta -138
# (backward), pursuit again. Speech comes from one and the tone from the other.
$detourCalls = ([regex]::Matches($mainText, 'accessxi\.nav_beacon_detour_target\(')).Count
$permitCalls = ([regex]::Matches($mainText, 'accessxi\.nav_beacon_detour_permitted\(')).Count
Assert ($detourCalls -ge 2) 'both detour call sites are present'
Assert ($permitCalls -ge $detourCalls - 1) 'and every applying site is gated by the permission check'
Assert (([regex]::Matches($mainText, 'nav_beacon_aim_mode_note\(')).Count -ge 3) `
    'each site records which producer supplied the aim so the next pulse can hold it'

Write-Host 'One poll costs the same live as it does offline:'
# The search loop was bounded only by `until now_ms() >= deadline`, and now_ms()
# is os.clock(). Whatever its granularity is inside pol.exe, a single call could
# run far past its 3ms intent -- the frame watchdog caught a 514ms route phase,
# and a search that needs 91 slices instead burned all 400,000 expansions.
Assert ($moduleText -match 'local SEARCH_MAX_SLICES_PER_POLL = 8;') `
    'a poll may run at most eight slices however the clock behaves'
Assert ($moduleText -match 'until now_ms\(\) >= deadline or slices >= SEARCH_MAX_SLICES_PER_POLL;') `
    'and the loop is bounded by that count as well as by the clock'
Assert ($mainText -match 'max_gap=%dms') `
    'including the largest gap between polls, which separates starvation from a stuck phase'
Assert ($mainText -match '(?s)nav_walk_graph_pending ~= nil and route_count <= 1\).*?return;\r?\n\s*end\r?\n\s*accessxi\.nav_walk_graph_planning_notice_tick = 0;\r?\n\s*local route_target = destination;') `
    'the pending guard returns BEFORE the straight-line destination cue is built'
Assert ($sightText -match 'local DETOUR_MAX_DISTANCE = 40\.0;') `
    'a mesh detour is never asked for a target more than 40 yalms away'
Assert ($sightText -match 'direct > DETOUR_MAX_DISTANCE') `
    'the detour bound is enforced'

Write-Host 'Certified-route sightline clamp -- near, forward, bounded:'
Assert ($sightText -match 'local CERTIFIED_CLAMP_STEPS = 3;') 'forward search is three waypoints'
Assert ($sightText -match 'local CERTIFIED_CLAMP_ARC = 16\.0;') 'forward arc is capped at 16 yalms'
Assert ($sightText -match 'local CERTIFIED_BEND_COS = 0\.90630779;') 'the search stops before a 25-degree bend'
Assert ($sightText -match '(?s)if \(certified\) then.*?accessxi\.nav_beacon_sightline_blocked = true;\r?\n\s*return nil;\r?\n\s*end') `
    'nothing visible on a certified route yields NO target, never an occluded or rear waypoint'

Write-Host 'One aim producer, held by mode, in every zone:'
Assert ($mainText -match "if \(accessxi\.nav_beacon_aim_mode_for\(precise_source\) == 'correction'\) then\r?\n\s*precise_aim = precise_target;") `
    'the precise cache supplies corrections only'
Assert ($mainText -match 'accessxi\.nav_beacon_aim_hold_ms = 2000') 'the producer hold is two seconds'
Assert ($mainText -match 'function accessxi\.nav_beacon_aim_mode_held\(now\)') `
    'the hold is queried as a mode, not as a frozen coordinate'
Assert ($mainText -match "if \(source == 'live-route-return' or source == 'wall-escape'\r?\n\s*or source == 'dynamic-obstacle'\) then\r?\n\s*return 'correction';") `
    'return-to-route, wall escape and obstacle steering are the interrupting corrections'
Assert ($mainText -match "if \(source == 'sightline-detour'\) then\r?\n\s*return 'detour';") `
    'the async mesh detour is its own producer mode'
Assert ($mainText -match 'function accessxi\.nav_beacon_detour_permitted\(now, leg_blocked\)') `
    'the detour asks permission before taking the aim'
Assert ($mainText -match 'return leg_blocked == true;') `
    'a held normal aim is only interrupted by the detour when its leg is blocked'
Assert ($mainText -match 'accessxi\.nav_beacon_aim_mode_note\(\r?\n\s*accessxi\.nav_beacon_aim_mode_for\(aim\.source\), tick\(\)\);') `
    'exactly one aim leaves the beacon per pulse and its producer is recorded'
Assert ($mainText -match '\(tonumber\(accessxi\.nav_beacon_aim_mode_generation\) or -1\) ~= generation') `
    'a route ownership change ends the hold immediately'
Assert ($mainText -match 'if \(not speech_correction\) then') 'speech uses the indexed lookahead unless correcting'

Write-Host 'ONE aim rule -- the point on the route a fixed distance ahead:'
$pursuitText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\nav_route_pursuit.lua')
Assert ($pursuitText -match 'function accessxi\.nav_route_pursuit_aim\(player, points, index, lookahead\)') `
    'the aim rule exists as one testable function'
Assert ($pursuitText -match 'accessxi\.nav_route_pursuit_lookahead = 9\.0;') `
    'the aim is a fixed distance ahead ALONG the path, not the next waypoint'
Assert ($pursuitText -match 'accessxi\.nav_route_pursuit_window = 6;') `
    'the projection is windowed so a self-crossing route cannot teleport the aim'
Assert ($mainText -match 'if \(route_count > 1 and type\(accessxi\.nav_route_pursuit_aim\) == .function.\) then') `
    'the beacon applies the aim rule BEFORE any of the producer machinery'
Assert ($mainText -match '(?s)local reachable = accessxi\.nav_pursuit_aim_reachable\(player, pursuit_aim\);\s*if \(reachable ~= nil\) then.*?return reachable;') `
    'and returns the reachable clamp so a pursuit aim cannot bypass terrain validation'
Assert ($mainText -match "log_line\(\('nav pursuit aim=") `
    'the chosen aim is logged when it changes'

Write-Host 'Centred must be something a person can hold:'
$sightText4 = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\beacon_sightline.lua')
Assert ($sightText4 -match 'accessxi\.nav_beacon_centre_deadband = 15 \* math\.pi / 180;') `
    'the centre tone spans 15 degrees, not the 4.8 the raw pan bins gave'
Assert ($sightText4 -match 'function accessxi\.nav_beacon_bin_for_delta\(delta\)') `
    'bin selection is in the module so the live delta sequence can be replayed against it'
Assert ($sightText4 -match "return 'front', 6, 0;") `
    'inside the deadband the player hears centre, which is the whole contract'
Assert ($mainText -match 'local prefix, bin, pan = accessxi\.nav_beacon_bin_for_delta\(delta\);') `
    'the beacon uses that one implementation'
Assert ($mainText -notmatch '(?s)function accessxi\.nav_beacon_file_for_delta.*?local bin = math\.floor') `
    'the nav beacon has no inline bin maths of its own (the enemy beacon keeps its own, deliberately)'

Write-Host 'The reversal hysteresis may only be bypassed by a NAMED correction:'
$sightText3 = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\beacon_sightline.lua')
Assert ($sightText3 -notmatch 'nav_beacon_sightline_clamped == true\r?\n\s*or accessxi\.nav_beacon_detour_active == true') `
    'clamping and detouring no longer buy a bypass -- they are how the aim is chosen, not evidence a swing is real'
Assert ($sightText3 -match "return source == 'live-route-return'\r?\n\s*or source == 'dynamic-obstacle'\r?\n\s*or source == 'wall-escape'\r?\n\s*or source == 'lathine-local-safe';") `
    'the bypass list is exactly the four named corrections'
Assert ($sightText3 -match 'function accessxi\.nav_beacon_smoothed_heading\(heading, urgent_correction\)') `
    'the hysteresis itself lives in the module so it can be replayed offline'
Assert ($sightText3 -match 'accessxi\.nav_beacon_reversal_limit = 90 \* math\.pi / 180;') `
    'a swing of 90 degrees or more is what gets held'
Assert ($mainText -match 'heading = accessxi\.nav_beacon_smoothed_heading\(heading, urgent_correction\);') `
    'the beacon poll uses that one implementation, not a copy of it'
Assert ($mainText -notmatch 'local reversal_limit = 90 \* math\.pi / 180;') `
    'the inline duplicate of the hysteresis is gone'

Write-Host 'Dynamic obstacles -- detected is not steerable, and a side-step goes forward:'
$obstacleText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\nav_dynamic_obstacle.lua')
Assert ($obstacleText -match 'function accessxi\.nav_entity_is_steerable_obstacle\(pos\)') `
    'steerability is a separate question from detection'
Assert ($obstacleText -match "if \(kind == 'player'\) then\r?\n\s*return false;") `
    'another player character never moves the aim point'
Assert ($obstacleText -match 'if \(obstacle\.steerable ~= true\) then\r?\n\s*return nil, obstacle;') `
    'a non-steerable obstacle is still returned for announcement, with no steering point'
Assert ($obstacleText -match 'local FORWARD_MIN = 0\.5;') 'a side-step must advance at least half a yalm along the leg'
Assert ($obstacleText -match 'local LATERAL_RATIO = 1\.7320508;') 'a side-step must stay within 60 degrees of the leg'
Assert ($obstacleText -match 'return lateral <= \(forward \* LATERAL_RATIO\);') 'both gates are applied to each side'

Write-Host 'A talk with no menu still completes the step:'
$navTalk = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\mission_quest_navigation.lua')
Assert ($navTalk -match 'function accessxi\.nav_mission_quest_note_talk_intent\(target_server_id, zone_id, now\)') `
    'pressing enter on a creature arms the step it belongs to'
Assert ($mainText -match '\(tonumber\(e\.id\) or -1\) == 0x001A') `
    'armed from the OUTGOING interaction packet, not from rendered text'
Assert ($mainText -match '\(tonumber\(category\) or -1\) == 0') `
    'and only for category 0, an actual trigger'
Assert ($mainText -match 'pcall\(accessxi\.nav_mission_quest_note_talk_intent, target, zone_id, tick\(\)\);') `
    'and the arm is told WHICH ZONE -- a server id is only unique inside one'
Assert ($navTalk -match "log_line\(\('objective talk arm rejected reason=missing-zone") `
    'an identity signal with no zone says so, instead of silently matching nothing forever'
Assert ($navTalk -match 'local function action_identity_points\(action, zone_id\)') `
    'identity can be looked up in the same catalogue the router used'
Assert ($navTalk -match 'if \(#catalogue == 0\) then') `
    'but only when the compact snapshot is empty -- a populated one stays authoritative'
Assert ($navTalk -match "index\.points_by_zone_entity\[\('%d\t%s'\):fmt\(zone_id, name_key\)\]") `
    'and the lookup never leaves the zone the interaction happened in'
Assert ($navTalk -match "and \(point\.target_name or point\.name\) or ''\);") `
    'the armed name reads both field spellings -- a blank name can never be attributed'
Assert ($navTalk -match 'function accessxi\.nav_mission_quest_note_talk_response\(speaker, now\)') `
    'the NPC reply is the second half of the evidence'
Assert ($navTalk -match 'if \(not advance_objective_match\(objective, objective\.index, 1\)\) then
?
\s*return false;
?
\s*end
?
\s*accessxi\.nav_objective_talk_intent = nil;') `
    'and the arm is spent only after the advance is saved, never before'
Assert ($navTalk -match "speaker:lower\(\) ~= clean\(armed\.name\):lower\(\)") `
    'the reply must come from the creature that was armed, not any NPC'
Assert ($navTalk -match '\(now - \(tonumber\(armed\.tick\) or 0\)\) > 10000') `
    'and shortly after -- a stale arm expires rather than completing later'
Assert ($navTalk -match "clean\(action\.action_id\) == armed\.action_id") `
    'and only while that same step is still the current one'
Assert ($navTalk -match 'local is_interaction = verb ==') `
    'the interaction test is inlined, not a nil global from a later local'

Write-Host 'Obstacles announce; they never take the aim and never stop the beacon:'
Assert ($mainText -match "speak\(\('%s ahead, %d yalms\.'\):fmt\(name,") `
    'an obstacle on the route is ANNOUNCED with its distance, while there is still room to walk round'
Assert ($mainText -match 'if \(obstacle\.steerable == true and \(tonumber\(obstacle\.ahead\) or 0\) >= 3\.0\) then') `
    'only real hazards are announced, and only while still ahead -- not players, not city NPCs'
Assert ($mainText -match '\(now - \(tonumber\(spoken\[name\]\) or 0\)\) > 12000') `
    'the same creature is not announced again for twelve seconds'
Assert ($mainText -match '\(now - \(tonumber\(accessxi\.nav_obstacle_spoken_tick\) or 0\)\) > 2500') `
    'and no more than one announcement every 2.5 seconds overall'
Assert ($mainText -match 'accessxi\.nav_obstacle_spoken = nil;') `
    'what was announced is forgotten on zone change'
Assert ($mainText -match 'if \(obstacle\.steerable == true and avoid == nil\) then') `
    'a steerable obstacle with no way round it is still recognised'
Assert ($mainText -match "speak\(\('%s is in the way\. Step around it\.'\):fmt\(name\)\);") `
    'and is announced -- the part the player asked to keep'
Assert ($mainText -match 'if \(type\(state\) ~= .table. or tostring\(state\.key or ..\) ~= block_key\) then') `
    'announced ONCE per obstruction, not every pulse'
Assert ($mainText -match 'return route_target, obstacle;') `
    'the obstacle never substitutes its own point for the route aim'
Assert ($mainText -notmatch 'return avoid or route_target, obstacle;') `
    'the old side-step substitution is gone -- it caused the zig-zag'
Assert ($mainText -notmatch "accessxi\.nav_beacon_exit\('obstacle-blocked', now\);") `
    'an obstruction never ends a beacon pulse'
Assert ($mainText -notmatch 'accessxi\.nav_obstacle_blocking\(tick\(\)\)\) then') `
    'and never suppresses the bearing -- the player would rather hear the route'

Write-Host 'Zone-line router -- the road the guide names:'
$routerText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\nav_zoneline_router.lua')
Assert ($routerText -match 'function accessxi\.nav_zoneline_shortest_path\(from_zone, to_zone\)') `
    'the plain shortest chain is still computed'
Assert ($routerText -match 'function accessxi\.nav_zoneline_preferred_set\(preferred_zones, from_zone, to_zone\)') `
    'the guide preference is scored as a set'
Assert ($routerText -match 'zone ~= from_zone and zone ~= to_zone') `
    'the current and destination zones do not score as via-zones'
Assert ($routerText -match 'function accessxi\.nav_zoneline_preferred_path\(from_zone, to_zone, preferred, max_edges\)') `
    'the preferring search is bounded by edge count'
# THE ENTRY POINT MOVED OUT OF THE MONOLITH. The router module exists so the
# choice of road can be tested offline, but the function every caller actually
# invokes stayed in accessxi_reader.lua -- so every harness hand-mirrored it,
# and the missing fourth argument hid behind that mirror for months.
Assert ($routerText -match 'function accessxi\.nav_zoneline_path\(from_zone, to_zone, final_edge_id, preferred_zones\)') `
    'and the road chooser itself lives here, callable by the harnesses'
Assert ($mainText -notmatch 'function accessxi\.nav_zoneline_path\(') `
    'with nothing left behind in the monolith'
Assert ($routerText -match 'accessxi\.nav_zoneline_preferred_path\(\r?\n\s*from_zone, to_zone, preferred, shortest:len\(\) \+ 2\)') `
    'the search runs the full graph to two edges longer than shortest, not a restricted node set'
Assert ($routerText -match 'if \(next_zone ~= to_zone and not preferred\[next_zone\]\) then\r?\n\s*unnamed = unnamed \+ 1;') `
    'roads are scored by how many zones the guide did NOT name'
Assert ($routerText -match 'if \(unnamed < best_unnamed') `
    'and the fewest-unnamed road wins whatever the edge counts'
Assert ($routerText -match 'NO GUIDE ROAD given=') `
    'a missing guide road is logged, never silently replaced by any shortest chain'
Assert ($mainText -match 'function accessxi\.nav_zone_id_for_name\(name\)') `
    'guide zone names resolve to ids from the zone-line graph itself'
$resolverText2 = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\mission_quest_step_resolver.lua')
Assert ($resolverText2 -match 'function M\.named_via_zones\(step, ctx\)') `
    'the resolver collects the zones the guide step names'
Assert ($resolverText2 -match 'ctx\.zone_path\(\r?\n\s*player_zone,\r?\n\s*dest_zone,\r?\n\s*tonumber\(edge\.id\) or 0,\r?\n\s*via\)') `
    'and passes them to the router'

Assert ($resolverText2 -match 'function M\.named_via_zones\(step, ctx\)') `
    'the resolver exposes the zones a step names'
$navText2 = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\mission_quest_navigation.lua')
Assert ($navText2 -match 'point\.objective_via_zones = via;') `
    'every target for a step carries the road the guide named'
Assert ($navText2 -match 'objective_via_zones = point\.objective_via_zones,') `
    'and it survives the module target copy'
Assert ($mainText -match 'objective_via_zones = type\(point\.objective_via_zones\) == .table. and point\.objective_via_zones or nil,') `
    'and the main target copy'
Assert ($mainText -match 'player\.zone, target\.zone, canonical_edge_id, guide_road\);') `
    'the ZONE SEARCH chain uses the recovered guide road, not just the resolver path'

Assert ($navText2 -match 'roads\[clean\(step\.stable_step_id\)\] = via;') `
    'the guide road is ALSO published against the step id, which every target copy carries'
Assert ($mainText -match 'guide_road = roads\[step_id\];') `
    'and the zone search recovers it from there when a copy dropped the field'
Assert ($mainText -match 'nav road recovered step=') `
    'a recovery is logged, so a silently dropped field can never look like success again'

Write-Host 'Vertical runs -- ramps and stairwells advance by projection, never by nearness:'
$runText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\nav_vertical_run.lua')
Assert ($runText -match 'accessxi\.nav_vertical_run_bend_cos = 0\.90630779;') 'a run stops at a 25-degree bend'
Assert ($runText -match 'accessxi\.nav_vertical_run_min_grade = 0\.30;') `
    'a run must be STEEP -- a hillside is not a ramp, and must not fall under ramp rules'
Assert ($runText -match '\(math\.abs\(rise\) / horizontal\) < accessxi\.nav_vertical_run_min_grade') `
    'the grade test is applied per leg, not to the total rise'
Assert ($runText -match 'local first_ahead = run\.first;') `
    'the run aim starts AHEAD of the player, never at the waypoint already passed'
Assert ($runText -match 'accessxi\.nav_vertical_run_y_tolerance = 2\.0;') 'height must agree within about two yalms'
Assert ($runText -match 'accessxi\.nav_vertical_run_aim_min = 4\.0;') 'the aim is at least four yalms along the run'
Assert ($runText -match "return current_index, false, 'ambiguous';") `
    'an overlapping switchback refuses rather than guessing a floor'
Assert ($runText -match "return current_index, false, 'off-run';") `
    'a player whose height disagrees with the route does not advance'
Assert ($runText -match "return current_index, false, 'no-progress';") 'the run index never runs backwards'
Assert ($mainText -match 'accessxi\.nav_vertical_run_progress\(\r?\n\s*pos, accessxi\.nav_route_points, run, current\)') `
    'the route index consults the run before the ordinary arrival test'
Assert ($mainText -match "tostring\(accessxi\.nav_vertical_run_reason or ''\) == 'projected'") `
    'the beacon only aims up a run when the player is demonstrably on it'
Assert ($mainText -match 'if \(aim ~= nil and vertical_run_aim == nil\r?\n\s*and type\(accessxi\.nav_beacon_clamp_to_sightline\)') `
    'sight never clamps a run aim -- CanSeeDestination ignores endpoint Y'

Write-Host 'Transport refusals are logged per edge, not through one shared key:'
Assert ($mainText -match 'function accessxi\.nav_transport_refusal_log_once\(edge, reason, availability, text, volatile\)') `
    'transport refusal logging is keyed state'
Assert ($mainText -match "local key = \('%d:%s:%s:%s:%s'\):fmt\(") `
    'the key carries edge, reason, availability, identity and revision'
Assert ($mainText -match "accessxi\.nav_transport_refusal_log_once\(\r?\n\s*edge, 'needs-key-item', availability,") `
    'a key-item refusal can log again when the key-item state changes'

Write-Host 'Bump recovery keeps the certified route:'
Assert ($mainText -match 'nav_precise_recovery_match_lost_since = 0;') 'a locally matched player retains the route'
Assert ($mainText -match 'rh >= 0\.75 and rh <= 4\.0 and rv <= 3\.0') 'return cues are bounded 4 horizontal / 3 vertical'
Assert ($mainText -match '\(now - lost_since\) < 1750') 'a replan waits for the match to be lost continuously'
Assert ($mainText -match "replan_gap = current_route_id == 'lathine-walk-graph-v2' and 5000 or 1000") `
    'walk-graph full replans are rate-limited to one per five seconds'

Write-Host 'Speech that carries information:'
Assert ($mainText -match '\(now - last_tick\) < 6000\) then\r?\n\s*return;') 'identical cues are suppressed for six seconds'
Assert ($mainText -match 'heartbeat_due = \(now - \(tonumber\(accessxi\.nav_route_guidance_last_tick\) or 0\)\) >= 8000') `
    'a heartbeat re-speaks by eight seconds'
Assert ($mainText -notmatch "local key = \('%s:%d:%d:%d:%d'\):fmt\(destination\.name or '', accessxi\.nav_route_point_index") `
    'the waypoint index is no longer part of the speech key'
Assert ($mainText -match 'function accessxi\.nav_walk_graph_turn_count') 'route-ready speech counts real bends, not waypoints'
Assert ($mainText -match 'accessxi\.nav_recorded_corridor_unavailable_key = corridor_key;') 'recorded-corridor failures log transitions only'

$probesText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\debug_probes.lua')
$navText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\mission_quest_navigation.lua')
$resolverPath = Join-Path $live 'modules\mission_quest_step_resolver.lua'
Write-Host 'Pointer validity is readability, not an address range (pol.exe is LARGEADDRESSAWARE):'
Assert ($mainText -match 'function accessxi\.pointer_pages_readable\(addr, size\)') 'a page-readability gate exists'
Assert ($mainText -match 'ptr < 0x01000000 or ptr > 0xFFFFFFFC') 'is_probe_pointer spans the whole 32-bit space'
Assert ($mainText -notmatch 'return ptr >= 0x01000000 and ptr < 0x7FFF0000;') 'the old 2 GB validity bound is gone'
Assert ($mainText -match 'readable = mem_state == 0x1000 and accessxi\.memory_page_readable\(protect\);') 'MEM_COMMIT plus a readable protection class is required'
Assert ($mainText -match '(?s)local function read_u32\(addr\).*?accessxi\.pointer_pages_readable\(addr, 4\).*?pcall\(ashita\.memory\.read_uint32, addr\)') 'read_u32 is gated before the native read'
Assert ($mainText -match '(?s)local function read_probe_string\(ptr, length\).*?accessxi\.pointer_pages_readable\(ptr, length\)') 'string reads check every page they touch'
Assert ($mainText -match "accessxi\.pointer_page_cache_clear\('zone-change'\);") 'the page cache is dropped on zone change'
Assert ($mainText -match 'accessxi\.frame_counter = \(accessxi\.frame_counter or 0\) \+ 1;') 'page answers are scoped to the current frame'
Assert ($probesText -match '< 5000\) then\r?\n\s*return;') 'auto menu dumps are rate-limited to one per five seconds'

Write-Host 'A zone trigger above the floor is never the walking target:'
Assert ($mainText -match 'function accessxi\.nav_zoneline_ground_sibling\(point\)') 'a ground-level sibling row is looked up'
Assert ($mainText -match 'function accessxi\.nav_zoneline_direct_leg_vetoed\(from_point, destination\)') 'the direct final leg has a veto'
Assert ($mainText -match 'return nav_distance\(from_point, destination\) < 6\.0\r?\n\s*and dy > 3\.0;') 'the veto is vertical > 3 over horizontal < 6'
Assert ($mainText -match "source = projected and 'zoneline-final-projected' or 'zoneline-final',") 'a vetoed final point is projected to walking height'
Assert ($mainText -match "'The entrance is on a different level\. Safe final approach unavailable\.'") 'an unreachable level is spoken, not aimed'
Assert ($mainText -match '(?s)function accessxi\.nav_nearby_zoneline_direct_route_allowed.*?nav_zoneline_direct_leg_vetoed\(player, point\)\) then\r?\n\s*return false;') 'direct nearby aiming is refused across levels'
Assert ($mainText -match 'or accessxi\.nav_point_is_zoneline\(destination\)\) then') 'every zone trigger gets final-approach semantics, not only names containing zone line'

Write-Host 'Every mission step resolves or names its refusal:'
Assert (Test-Path -LiteralPath $resolverPath) 'the step resolver module exists'
$resolverText = Get-Content -Raw -LiteralPath $resolverPath
Assert ($resolverText -match 'function M\.resolve_step\(steps, index, ctx\)') 'resolve_step is the single entry point'
Assert ($resolverText -match 'function M\.inherit_zone\(steps, index, ctx\)') 'zone context is inherited from the preceding zone-changing step'
Assert ($resolverText -match 'return nil, M\.REASONS\.ZONE_CONTEXT_AMBIGUOUS;') 'inheritance stops at an ambiguous zone-changing step'
Assert ($resolverText -match "reason = M\.REASONS\.EXIT_SQUARE_UNRESOLVED,\r?\n\s*all_edges = all,") 'an exit square over several entrances returns every entrance for the player to choose'
Assert ($resolverText -match "info\.partial = 'unbound-square';") 'an unbound square is partial credit, never full'
Assert ($resolverText -match "info\.partial = 'zone-only';") 'a zone-only positional step is partial credit'
Assert ($resolverText -match 'function M\.is_modifier_term\(key\)') 'modifiers come from a closed registry'
Assert ($resolverText -notmatch "'the ' \};") 'the article "the" is not an honorific'
Assert ($resolverText -match "if \(#points == 0 and PERSON_ACTIONS\[action\]\) then") 'honorifics are stripped only for steps addressing a person, inside a context'
Assert ($resolverText -match "if \(type\(ctx\.default_zone_group\) == 'table'\r?\n\s*and next\(zone_ids\) == nil\) then") 'the nation group never overrides an inherited zone'
Assert ($navText -match "label = \('%s in %s'\):fmt\(spoken,") 'speech keeps the guide name when routing through a catalogue alias'
Assert ($resolverText -match "base_kind = 'catalogue-unique';") 'a name with no guide context still defaults to the unique-catalogue kind'
Assert ($resolverText -match "if \(#physical > 1\) then\r?\n\s*info\.ambiguity = M\.REASONS\.ENTITY_DUPLICATED;") `
    'and several physical candidates are a recorded ambiguity, never a silent pick'
Assert ($resolverText -match 'No route for %s: %s\. Press K for instructions\.') 'refusal speech names the failure'

Write-Host 'A route it cannot build never silences what the guide says:'
Assert ($resolverText -match 'function M\.guide_sentence\(instruction\)') `
    'the guide has its own sentence, separate from any route we manage to build'
Assert ($resolverText -match "return \('Guide: %s'\):format\(instruction\);") `
    'attributed to the page -- it is guidance, not live state we observed'
Assert ($resolverText -match "return \('No route for %s: %s\. %s Press K for instructions\.'\):format\(") `
    'and a refusal carries it, instead of ending at the failure'
Assert ($navText -match 'info\.instruction = clean\(step\.primary_instruction\);') `
    'the refusal record picks the sentence up from the step it is refusing'
Assert ($navText -match 'local function with_guide\(message\)') `
    'every blocked answer in prepare_route goes through one place'
Assert ($navText -notmatch "return nil, \('No exact source-backed destination is available for %s\. Press G for the source guide\.'\):fmt\(title\), 'blocked';") `
    'no blocked branch is left speaking the failure alone'

Write-Host 'The guide the addon tells you to press G for is actually reachable:'
$hotkeyText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\navigation_hotkeys.lua')
# The exact order matters only at its tail: current_key returns the FIRST key
# down, so G must stay last. N was added before it for the same reason.
Assert ($hotkeyText -match "KEY_ORDER = \{ 'I', 'U', 'O', 'J', 'K', 'L', 'N', 'G' \}") `
    'G is read, and read last so it takes precedence from nothing that already worked'
Assert ($hotkeyText -match 'G = 0x47,') 'bound to the G key'
Assert ($hotkeyText -match "G = 'open_guide',") 'and it opens the guide'
Assert ($mainText -match "G = accessxi\.quick_status_key_down\(tonumber\(vk\.G\) or 0x47\),") `
    'the poll actually samples it -- binding it without sampling would change nothing'
Assert ($mainText -match "elseif \(action == 'open_guide'\) then") `
    'the nav menu has somewhere to dispatch it'
Assert ($mainText -match 'local text, reason = accessxi\.nav_mission_quest_open_guide\(item\);') `
    'reaching the step browser that was already written and had no caller'
Assert ($mainText -match 'speak\(accessxi\.objective_guides:move\(-1\)\);') `
    'and J/L walk the GUIDE steps while it is open, not the menu rows'
Assert ($mainText -match 'speak\(accessxi\.objective_guides:repeat_step\(\)\);') `
    'with K repeating the step being read'
Assert ($mainText -match "accessxi\.objective_guides:close\('step-view-closed'\);") `
    'and G again closes it'

Write-Host 'An entity we cannot place never costs the player the zone the guide named:'
Assert ($resolverText -match 'function M\.step_named_zones\(step, ctx\)') `
    'the zones THIS STEP wrote are separable from the ones it inherited'
Assert ($resolverText -match 'function M\.guide_zone_fallback\(step, ctx, ids, spoken\)') `
    'and they can still be routed to when the thing inside them is unplaceable'
Assert ($resolverText -match 'local GUIDE_ZONE_ACTIONS = \{') `
    'only for actions a zone can answer'
Assert ($resolverText -notmatch "GUIDE_ZONE_ACTIONS = \{[^}]*note = true") `
    'never a note -- standing in Giddeus does not satisfy "Yagudo Caulk drops from Yagudos in Giddeus"'
Assert ($resolverText -match "info\.partial = 'zone-only';") `
    'the promise stays exactly as large as the guide -- zone-only forces the spoken caveat'
Assert ($resolverText -match "M\.guide_zone_fallback\(\r?\n\s*step,\r?\n\s*ctx,\r?\n\s*nation_ids,\r?\n\s*districts\);") `
    'a nation reads its districts from nation_ids, never from zone_ids, which may hold a default group the guide never named'
Assert ($resolverText -match "The guide names %d places for this step: %s\.") `
    'every zone the guide listed is spoken -- we never silently pick one of several'
Assert ($resolverText -match "\('the guide does not say where %s is for this step'\)\r?\n\s*:format\(") `
    'an INHERITED zone is never attributed to the guide in the refusal'

Write-Host 'A refusal says what we cannot do, never what the world does not contain:'
Assert ($resolverText -notmatch 'is not in the %s catalogue') `
    'the player never hears the word catalogue'
Assert ($resolverText -notmatch "' is not in the catalogue'") `
    'nor that a Gate Guard, which plainly exists, is not in the world'
Assert ($resolverText -match "I have no indexed location for %s") `
    'it is our index that is short, and the sentence says so'
Assert ($resolverText -match 'function M\.no_destination_detail\(step\)') `
    'and a map square the guide printed is not "no destination"'
Assert ($resolverText -match "the guide gives only map square %s for this step") `
    'it is read out -- 6,474 steps carry one'
Assert ($resolverText -notmatch "elseif \(#absent > 0 and next\(zone_ids\) ~= nil\) then") `
    'and the entity-absent branch that could never execute is gone'

Write-Host 'The mission category tells the player what changed:'
$announcerText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\objective_announcer.lua')
Assert ($navText -match 'accessxi\.objective_announce\(\{') `
    'a completed step is announced -- this module used to contain no speech at all'
Assert ($navText -notmatch '(?s)notify_objective_progress = function\(objectives\).{0,300}^\s*local first = objectives\[1\];\r?\n\s*if \(type\(first\) == .table.\r?\n\s*and type\(accessxi\.on_objective_interaction_progress_changed\)') `
    'the silent version of notify_objective_progress is gone'
Assert ($announcerText -match "return 'Press I to start navigation\.';") `
    'a routable step offers the key'
Assert ($announcerText -match "'Press I to navigate to %s\. The guide does not say where inside it\.'") `
    'a zone-only step offers the zone and says the guide stops there'
Assert ($announcerText -match "return 'No route is available for this objective\.';") `
    'and a step with no route never promises a key that cannot deliver'
Assert ($announcerText -match "Waiting for the %s to update\.'\):format\(noun\)") `
    'running out of guide steps waits for the server, and says which of mission or quest it is waiting on'
Assert ($announcerText -match "return join\(\{ 'Recorded steps complete\.', stopped, continuation,") `
    'it reports only what it knows -- the recorded steps ran out -- and reads the guide on'
Assert ($announcerText -notmatch "'No further guide objectives") `
    'and never claims the GUIDE is finished when only the cursor is -- live 2026-08-29 Below the Arks had four BG Wiki sentences left'
Assert ($announcerText -notmatch "FINAL_OBJECTIVE\) then[\s\S]{0,120}'Objective complete") `
    'nor that the OBJECTIVE is, which the cursor cannot know either'
Assert ($announcerText -notmatch "FINAL_OBJECTIVE[\s\S]{0,600}Mission complete") `
    'and it never claims the mission finished on its own evidence'
Assert ($announcerText -match "'Active mission changed from %s to %s\.'") `
    'an unproven replacement reports what was observed'
Assert ($mainText -notmatch 'local succeeded = previous_nation == current_nation') `
    'succession is no longer nation-only arithmetic -- every storyline goes through the tracker'
Assert ($announcerText -notmatch 'nav_route_start|Starting route|auto_start') `
    'nothing here starts a route -- the player decides when'

Write-Host 'It says a change once, and never swallows a different one:'
Assert ($announcerText -match 'function M\.dedup_key\(transition\)') `
    'transitions are deduped by what they mean'
Assert ($announcerText -match 'tostring\(tonumber\(transition\.mission_epoch\) or 0\),') `
    'scoped to the mission instance, so repeating a mission may be announced again'
Assert ($announcerText -match 'clean\(transition\.identity\):lower\(\),') `
    'and to the character, so another one never inherits what this one was told'
Assert ($mainText -match 'accessxi\.objective_announcements\[key\] == true') `
    'the same transition is spoken once however many times the reducer recomputes it'
Assert ($announcerText -match 'M\.COALESCE_MS = 1500;') `
    'related evidence within a moment becomes one richer sentence'
Assert ($mainText -match 'announcer\.outranks\(transition, pending\.transition\)') `
    'and the richer description is the one that survives'
Assert ($mainText -match "speak\(text, false\);") `
    'an announcement QUEUES behind the NPC line that caused it -- it never talks over it'
Assert ($mainText -match 'accessxi\.poll_objective_announcements\(\);') `
    'released from the frame loop, so the window is real time'
Assert ($mainText -match "accessxi\.reset_objective_announcements\('character-changed'\);") `
    'and a different character starts from a silent baseline'

Write-Host 'Zoning into the place the guide named finishes the step:'
Assert ($navText -match 'function accessxi\.nav_objective_travel_destination_zones\(native_key, action\)') `
    'a travel step has a SET of zones that satisfy it, not one field'
Assert ($navText -match 'local single = tonumber\(action\.destination_zone_id\) or 0;') `
    'the single extracted id still counts'
Assert ($navText -match 'index\.zone_ids_by_name\[source_name_key\(name\)\]') `
    'and so does every zone NAME written on the step -- "Mhaura or Selbina" means either'
Assert ($navText -match 'accessxi\.nav_objective_travel_zones\[clean\(native_key\)\]') `
    'and the destinations the router resolved, kept where a zone change cannot wipe them'
Assert ($navText -match "clean\(recorded\.revision\) == clean\(progression_revision\(native_key\)\)") `
    'a record from a different guide revision is discarded, never trusted'
Assert ($navText -match 'if \(accepted\[destination\] == true\) then') `
    'the zone the player entered is checked against that whole set'
Assert ($navText -notmatch 'destination > 0 and destination == tonumber\(action\.destination_zone_id\)\r?\n\s*and advance_objective_match') `
    'the single-field test that could never match 53% of travel steps is gone'
Assert ($navText -match "log_line\(\('objective travel arrived native=") `
    'and an arrival that completes a step says so in the log'
# Ordering used to be the fix for this: keep every caller below the helper. It
# held for one caller and then quietly failed for three more added later
# (declared_result_names, nav_mission_quest_first_objective, and the travel-zone
# persistence), because nothing enforced it for new code. The helpers are now
# FORWARD DECLARED, so order cannot break them at all, and the bytecode gate
# above proves it for every module rather than for one hand-picked pair.
Assert ($navText -match '(?m)^local progression_actions;
?
local progression_revision;') `
    'the progression helpers are forward declared, so a caller above them is not a nil global'
Assert ($navText -match '(?m)^function progression_revision\(native_key\)' -and $navText -match '(?m)^function progression_actions\(native_key\)') `
    'and their definitions assign those locals rather than creating globals'
Assert ($mainText -match "accessxi\.load_code_module\('mission_quest_step_resolver'") 'the addon loads the resolver'
Assert ($navText -match 'local resolved, info = resolver\.resolve_step\(steps, step_index, resolver_ctx\);') 'source_route_rows hands empty steps to the resolver'
Assert ($navText -match 'function accessxi\.nav_mission_quest_step_refusal\(native_key, step_id\)') 'refusals are recorded per step'
Assert ($navText -match 'instruction_route_message = accessxi\.mission_step_resolver\.refusal_speech\(
?
\s*title, step_refusal, guide_instruction\);') 'prepare_route speaks the recorded refusal, with the guide sentence'
Assert ($navText -match 'objective_canonical_edge_id = reviewed\.canonical_edge_id,') 'a zone-travel row binds its zone-line edge through to the zone search'
$luajit = 'C:\Users\buu42\AppData\Local\Programs\LuaJIT\bin\luajit.exe'
$harness = Join-Path $PSScriptRoot 'test_mission_step_resolver.lua'
# --missions: the road is honoured in the census now, and scoring it is a
# bounded-depth search per entrance. The gate reads only the MISSIONS ONLY
# line, so asking for the quest corpus as well costs minutes for nothing.
$harnessOut = (& $luajit $harness --missions 2>&1 | Out-String)
Assert ($LASTEXITCODE -eq 0 -and $harnessOut -match '(\d+) claims passed, 0 failed') "the Davoi Report regression passes ($($Matches[1]) claims)"
if ($harnessOut -match 'MISSIONS ONLY steps=(\d+) routable-before=(\d+) routable-after=(\d+)') {
    Assert ([int]$Matches[3] -gt [int]$Matches[2]) "mission routability increased ($($Matches[2]) -> $($Matches[3]) of $($Matches[1]) steps)"
}

Write-Host 'A duplicated name is a choice, and the choice is the player''s:'
Assert ($resolverText -match 'function M\.finalize_entity_candidates\(') `
    'one finalizer decides every entity candidate set, so the six resolution paths cannot diverge'
Assert ($resolverText -match 'function M\.dedupe_entity_points\(points, ctx\)') `
    'the same physical point listed by two sources is one candidate, not two'
Assert ($resolverText -match "target\.entity_choice_stage = 'zone';") `
    'a remote zone contributes ONE staging choice; its physical points are offered after arrival'
Assert ($resolverText -match 'info\.unreachable_choices = unreachable;') `
    'and candidates we cannot reach are recorded rather than quietly dropped from the count'
Assert ($resolverText -notmatch "info\.reason = M\.REASONS\.ENTITY_DUPLICATED;") `
    'a duplicated name is never a terminal refusal any more'
Assert ($navText -notmatch 'per_name_zone\[bucket\] <= 4') `
    'and no cap silently drops the fifth candidate -- the list cursor already scrolls'
$catalogText = $navText
Assert ($catalogText -match 'index\.points_by_base\[base_key\]:append\(point\);') `
    'the unnumbered base name is indexed across zones, so "a Home Point" has candidates to offer'
Assert ($catalogText -match 'points_for_entity_base = function \(key\)') `
    'and the resolver can reach that index'
Assert ($navText -match "if \(#targets == 0 and resolver_ctx == nil\r?\n\s*and source_mode == 'ordinary'\) then") `
    'the legacy zone-and-entity lookup no longer answers ahead of the resolver, nor for a note'

Write-Host 'The resolver harness is an oracle, not a second opinion:'
$harnessText = Get-Content -Raw -LiteralPath $harness
Assert ($harnessText -match "pcall\(dofile, ADDON \.\. '/modules/nav_zoneline_router\.lua'\)") `
    'it loads the REAL road router instead of rolling its own shortest-path search'
# It no longer mirrors the road at all. Mirroring was the defect: the mirror
# dropped the fourth argument, and later steered the prefix through the
# destination, and both hid behind green claims. nav_zoneline_path now lives in
# the router module, so the harness calls the shipped one.
Assert ($harnessText -match 'return accessxi\.nav_zoneline_path\(\r?\n\s*from_zone, to_zone, final_edge_id, preferred_zones\);') `
    'and its zone_path is a call to the shipped road chooser, not a copy of it'
Assert ($harnessText -notmatch 'local prefix = zone_path\(') `
    'with no hand-written mirror of the prefix search left to drift'
Assert ($harnessText -match "the shortest chain to East Ronfaure goes through King Ranperre") `
    'with a claim that fails when the road is dropped -- an oracle has to be able to fail'

$guidesText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\mission_quest_guides.lua')
Write-Host 'The beacon does not go quiet at a door:'
# The door wait used to return out of both the beacon pulse and the guidance
# pulse, so a player standing at a closed door heard NOTHING for up to fifteen
# seconds -- while the prompt they had just been given promised "Navigation
# will resume with the beacon through the doorway". Live 2026-08-23 at the
# Mayor's Residence the prompt fired five times in a minute, four of them
# timing out, and the player rerouted repeatedly.
Assert ($mainText -match "source = 'door-wait',") `
    'while waiting, the beacon aims at the door itself'
Assert ($mainText -match 'local door_x = tonumber\(accessxi\.nav_door_x\);') `
    'using the position the wait already recorded'
Assert ($mainText -match "speak\(\('Open %s to continue\.'\):fmt\(") `
    'and the player is reminded what to do rather than left in silence'
Assert ($mainText -match 'accessxi\.nav_door_reminder_tick') `
    'throttled, so a reminder never becomes chatter'
# THIS GATE USED TO ASSERT THE BUG. nav_door_waiting() is true ONLY while
# now < nav_door_pause_until, so a branch inside it that ALSO required the pause
# to be over could never run -- the whole door fix was dead code, shipped and
# reported as working (sol caught it). The pause IS the window that needs a
# beacon: the seconds right after the prompt when the player is turning to find
# the door.
Assert ($mainText -notmatch "if \(door_x == nil or door_z == nil
?
\s*or now < \(tonumber\(accessxi\.nav_door_pause_until\)") `
    'the door beacon branch does not gate itself on a condition that makes it unreachable'
Assert ($mainText -match "accessxi\.nav_door_last_spoken_key") `
    'and the twenty-word door instruction is spoken once, not on every fifteen-second re-prompt'

Write-Host 'A stuck player leaves a trace:'
# The freewalk collision detector watches someone walking on their own and says
# nothing while a route is running. Live 2026-08-23 the player walked Jugner
# Forest twice and Valkurm Dunes once, got stuck in both, and the log held 240
# and 190 position samples with NOT ONE navigation event in either zone. There
# was nothing to look at afterwards.
Assert ($mainText -match "log_line\(\('nav route stalled zone=%d player=") `
    'a route that stops making progress records where it happened'
Assert ($mainText -match 'accessxi\.nav_route_stall_x') `
    'measured as the PLAYER not moving, which a waypoint advance cannot fake'
Assert ($mainText -match 'if \(moved > 3\.0\) then') `
    'so ordinary walking resets it and only real stillness is reported'

Write-Host 'Not yet computed is not the same as no route:'
# The capability reads a cache source_route_rows fills, and a mission that has
# just become active has nothing in it. Live 2026-08-23, arriving in Mhaura
# accepted "Emissary from the Seas"; the announcement asked at 17:21:31 and was
# told there was no route, and the route was computed at 17:21:36.
Assert ($navText -match 'pcall\(source_route_rows, native_key\);') `
    'the capability computes the routes before it reports none'
Assert ($navText -match '(?s)pcall\(source_route_rows, native_key\);.*?nav_mission_quest_step_refusal\(native_key, step_id\)') `
    'and does it before consulting the refusal record, which the same pass writes'

Write-Host 'A yes/no the player cannot hear is the worst thing this can do:'
# The generic comyn confirmation used to answer only for socialme and menuwind
# -- Shut Down and Log Out -- and return nil for everything else. Live
# 2026-08-23 an auction bid confirmation arrived with sourceMenu="menu auc3",
# failed both names, and was silently dropped while the captured context held
# "pinch of prism powder. Bid. Place...". It is the LAST handler in the comyn
# chain, so speaking can never pre-empt a more specific reading.
Assert ($mainText -notmatch "if \(not source_menu:eq\('menu    socialme', true\) and not source_menu:eq\('menu    menuwind', true\)\) then
?
\s*return nil;") `
    'no confirmation is dropped for arriving from an unlisted menu'
Assert ($mainText -match "if \(source_menu:eq\('menu    socialme', true\) or source_menu:eq\('menu    menuwind', true\)\) then") `
    'while Shut Down and Log Out keep their own exact wording'
$disposeIdx = $mainText.IndexOf('local item_dispose_second_confirm = accessxi.item_dispose_second_confirmation_speech(name);')
$genericIdx = $mainText.IndexOf('local generic_comyn_confirm = accessxi.generic_comyn_confirmation_speech(name);')
Assert ($disposeIdx -gt 0 -and $genericIdx -gt 0 -and $genericIdx -gt $disposeIdx) `
    'and the generic reading stays LAST, so a specific handler always wins'

Write-Host 'The auction list is rebuilt row for row:'
$auctionRules = Join-Path $PSScriptRoot 'test_auction_item_list_rows.ps1'
Assert (Test-Path -LiteralPath $auctionRules) 'the auction row rules exist'
$auctionOut = (& pwsh -NoProfile -File $auctionRules 2>&1 | Out-String)
Assert ($LASTEXITCODE -eq 0 -and $auctionOut -match 'auction item list row rules hold') `
    'and they hold -- a zero-availability stack row is still a row, and nothing is dropped'

Write-Host 'A disagreement between the two pages is not a reason to hide the step:'
# 1,451 reconciled steps are flagged comparison="conflict", every one naming
# exactly one conflicting field: target_identity -- the pages WORDING the target
# differently, not disagreeing about the world. Both guards refused them and the
# census excluded them, so 632 mission steps were invisible as well as
# unroutable. sol's contract: read each page on its own terms, never the merged
# union, which can name a place neither page stated.
Assert ($resolverText -match 'function M\.resolve_source_conflict_step\(steps, index, ctx\)') `
    'a conflicted step is resolved, not refused on sight'
Assert ($resolverText -match "info\.ambiguity = 'source-conflict';") `
    'and the disagreement is recorded rather than hidden'
Assert ($resolverText -match '(?s)if \(type\(readings\) ~= .table. or next\(readings\) == nil\) then.*?M\.REASONS\.SOURCE_CONFLICT') `
    'but with no per-page reading it still refuses rather than resolving the merge'
Assert ($guidesText -match 'function GuideState:source_step_readings\(native_key, stable_step_id\)') `
    'the guide can hand back each page own structured reading'
Assert ($navText -match 'source_readings = function \(step_id\)') `
    'and navigation supplies them to the resolver'
Assert ($navText -notmatch "clean\(step\.comparison\):lower\(\) ~= 'conflict'") `
    'with the second guard -- skipping the step outright -- gone'

Write-Host 'An NPC reply is recognised on either dialogue channel:'
# Live 2026-08-23 Zantaviat answered on chat mode 144 while the completion path
# only ever read 150/151, so an attributable reply was discarded before it
# reached the arm. sol's ruling: 144 counts only INSIDE the existing
# zone/server-id/speaker correlation -- the mode is not proof by itself, and an
# unarmed reminder line must never complete anything.
Assert ($navText -match 'local NPC_DIALOGUE_MODES = \{ \[144\] = true, \[150\] = true \};') `
    'the NPC dialogue channels are a named set in the module, not a number in the monolith'
Assert ($mainText -match 'accessxi\.nav_mission_quest_dialogue_mode\(mid\)') `
    'and the reader asks for them rather than hard-coding 150 and 151'
Assert ($mainText -match '(?s)nav_mission_quest_dialogue_mode\(mid\).*?nav_mission_quest_note_talk_response') `
    'a reply on either channel still has to match the armed target to complete anything'

Write-Host 'A step the game already took can still be moved past:'
# A mission step completes ONCE. If the addon was not watching at that moment
# the game never offers it again -- talking to the NPC a second time gets their
# reminder line, not the event -- so no detection can ever advance the cursor.
# Live 2026-08-23 the objective still read "Talk to the NPC Zantaviat" a day
# after that conversation actually happened, and every route led back to an NPC
# with nothing left to say. The recovery existed with NO CALLER.
$hotkeyText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\navigation_hotkeys.lua')
Assert ($navText -match 'function accessxi\.nav_mission_quest_mark_step_done\(category, native_key\)') `
    'the addon marks the selected native objective rather than the first mission in the category'
Assert ($hotkeyText -match "N = 'mark_step_done',") `
    'and a key reaches it -- N, because H is the quick-status key'
Assert ($hotkeyText -match "navigation\.KEY_ORDER = \{ 'I', 'U', 'O', 'J', 'K', 'L', 'N', 'G' \}") `
    'which is polled with the other navigation keys'
Assert ($mainText -match "elseif \(action == 'mark_step_done'\) then") `
    'and the reader acts on it rather than naming a key nothing reads'

Write-Host 'The production seam is driven for real, not through a stand-in:'
# A harness that supplies a seam cannot test it. The resolver suite builds its
# context by hand, which is why three crashes inside source_route_rows shipped
# while 113 of its claims stayed green. This one loads the real modules, hands
# them the real shipped data, and calls the entry the mission menu calls.
# Verified to FAIL when the forward declarations are removed again.
$integration = Join-Path $PSScriptRoot 'test_source_route_integration.lua'
Assert (Test-Path -LiteralPath $integration) 'the production-seam integration test exists'
$integrationOut = (& $luajit $integration 2>&1 | Out-String)
Assert ($LASTEXITCODE -eq 0 -and $integrationOut -match 'claims=(\d+) failed=0') `
    "the real source_route_rows builds rows and answers for its steps ($(if ($integrationOut -match 'claims=(\d+)') { $Matches[1] } else { '?' }) claims)"
Assert ($integrationOut -match 'source_route_rows actually ran') `
    'and the run is proven to have reached it, not merely to have loaded'

Write-Host 'No local is read as a global above its own declaration:'
# THE HARNESS CANNOT CATCH THIS CLASS, because it supplies its own version of
# the very seam that breaks -- declared_result_names was raising in the game
# while 113 claims passed offline. In Lua 5.1 a local's scope begins AFTER its
# declaration, so a call above it compiles to a GLOBAL read and is nil at
# runtime. Read out of the compiled bytecode, which cannot be fooled by how the
# source reads.
$auditOut = (& 'py' (Join-Path $PSScriptRoot 'audit_lua_forward_scope.py') '--modules' 2>&1 | Out-String)
Assert ($auditOut -match 'forward-scope clashes \(and uncompilable files\): 0') `
    "no module calls a local helper declared below the call site ($($auditOut.Trim() -split "`n" | Select-Object -Last 1))"

Write-Host 'An inherited zone is route history, not evidence about this target:'
# A hand-written registry of exceptional places was built and then deliberately
# removed. It never rescued a step -- the structural rule below already does
# that -- it only narrowed a working choice, and a stale precision entry would
# route to the wrong but still-routable NPC, which no coverage gate can see
# (sol). Precision data that cannot fail loudly is worse than an honest choice.
Assert (-not (Test-Path -LiteralPath (Join-Path $live 'modules\mission_quest_reviewed_bindings.lua'))) `
    'no hand-written binding registry ships'
Assert ($navText -notmatch 'reviewed_binding_for_step') `
    'and nothing supplies one'
Assert ($resolverText -match 'function M\.current_step_primary_evidence\(') `
    'the current step can prove exactly one target from its compact action'
Assert ($resolverText -match "\['talk-to'\] = 'talk',") `
    'and only through a direct relationship -- talk-to, trade-to, deliver-to, examine-object, use-object'
Assert ($resolverText -match 'function M\.resolve_inherited_compact_primary\(') `
    'a proven target may override an inherited zone that does not contain it'
Assert ($resolverText -match "GENERIC_PRIMARY_TARGETS = \{
?
\s*\['\?\?\?'\] = true,") `
    'a generic marker never counts as a proven target'
Assert ($resolverText -match 'function primary_is_generic_role\(' -or $resolverText -match 'local function primary_is_generic_role\(') `
    'nor does a role, nor a name the guide made indefinite'
Assert ($resolverText -match 'and not M\.is_result_item\(') `
    'nor a reward the step declares'
Assert ($navText -match 'primary_actions_for_step = function \(step_id\)') `
    'the compact actions reach the resolver, indexed once per objective'
Assert ($resolverText -notmatch 'M\.resolve_reviewed_primary_binding') `
    'and no inert staging for one is left behind looking live'

Write-Host 'A note is read, not walked:'
Assert ($resolverText -match "function M\.resolve_note_step\(steps, index, ctx\)") `
    'a note has its own resolution path'
Assert ($resolverText -match "if \(action == 'note'\) then\r?\n\s*return M\.resolve_note_step\(") `
    'and it is taken BEFORE the step is classified, so entities are never flattened against zones'
Assert ($resolverText -match "info\.kind = 'note-information';") `
    'a note with no binding is information, not a refusal'
Assert ($resolverText -match "function M\.explicit_note_route_options\(step\)") `
    'only an explicit annotation binds a note to a place'
Assert ($resolverText -match "and clean\(step\.action\):lower\(\) == 'note'\) then\r?\n\s*return nil;") `
    'and raw note zones can never become a road for the router to score'
Assert ($navText -match "local allow_resolver = source_mode == 'ordinary'") `
    'navigation asks the note source mode what may answer for the step'
Assert ($navText -match 'resolver\.point_with_attached_notes\(') `
    'and advice the guide attached to another step is spoken with that step'

Write-Host 'One search for every destination, not one per entrance:'
Assert ($resolverText -match 'function M\.choose_entry_edges\(') `
    'reachability is asked once for the whole fan-out'
Assert ($resolverText -match 'function accessxi\.nav_zoneline_entry_edge_shortest_tree\(' -or $routerText -match 'function accessxi\.nav_zoneline_entry_edge_shortest_tree\(') `
    'answered by one breadth-first tree from where the player stands'
Assert ($resolverText -match 'and not square\r?\n\s*and #remote > 0') `
    'but never when an unbound square makes every entrance a choice -- that list must not depend on which path we found'
Assert ($resolverText -match 'legacy_entry_edge_candidates\(') `
    'and a provider that cannot answer falls back to the search that always worked'
Assert ($routerText -match 'local prefix_preferred = preferred_zones;') `
    'the road is stripped of the destination before the prefix search'
Assert ($routerText -match 'accessxi\.nav_zoneline_path\(from_zone, final_from_zone, 0, prefix_preferred\);') `
    'so a road is never steered THROUGH the place it leads to, only for the conflict check to discard it'
Assert ($harnessText -match 'zone_id_for_name = function \(value\)') `
    'and the harness can express a road at all, which it could not before'

Write-Host 'Stage one of a choice is not a route:'
$announcerText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\objective_announcer.lua')
Assert ($announcerText -match "CHOICE = 'choice',") `
    'the capability has a fourth value: full, zone-only, choice, unavailable'
Assert ($announcerText -match 'function M\.choice_suffix\(choice\)') `
    'and a choice has its own sentence'
Assert ($announcerText -match "'Press I to choose from %d %s\.'") `
    'which says how many places the key will offer'
Assert ($announcerText -match "%d other indexed place%s cannot currently be routed from here\.") `
    'and admits the candidates that cannot be reached at all'
Assert ($navText -match 'return announcer\.ROUTE\.CHOICE, clean\(resolution\.zone_name\), \{') `
    'the capability lookup reports a choice with its count and stage'
Assert (([regex]::Matches($navText + $mainText, 'route_choice = route_choice,')).Count -ge 2) `
    'and both announcement sites carry it through to speech'

Write-Host 'A switchback is spoken as a ramp, and the lookahead waits for the level:'
Assert ($mainText -match 'function accessxi\.nav_hairpin_ahead\(from_pos, route_target, next_target\)') 'stacked opposing legs are detected'
Assert ($mainText -match 'if \(far > 4\.0 or math\.abs\(dy\) < 2\.0\) then
?
\s*return nil;') 'a hairpin is within 4 horizontal and at least 2 vertical'
Assert ($mainText -match "phrase = \('%s the ramp %\.0f yalms, then turn around\.'\):fmt\(") 'the approach cue says climb or go down the ramp, then turn around'
Assert ($mainText -match '(?s)if \(approach_length <= 0\.75\) then.*?return math\.abs\(\(tonumber\(player\.y\) or 0\) - \(tonumber\(route_target\.y\) or 0\)\) <= 1\.0;') 'the lookahead crosses the turn only on the apex level'

Write-Host 'Rulings after review -- the cursor stays the authority, nations are a choice:'
Assert ($resolverText -match 'function M\.blocking_prerequisite\(actions, completed_order, candidate_step_id, owned_fn\)') 'an unmet acquisition before a travel step is detectable'
Assert ($navText -match '(?s)local function next_routable_progress_step.*?resolver\.blocking_prerequisite\(\r?\n\s*actions, completed_order, step_id, acquisition_row_items_owned\);') 'the projection consults live inventory before jumping to a travel step'
Assert ($navText -notmatch '(?s)held\[clean\(blocking\.step_id\)\] = refusal;.*?return nil;') `
    'a missing prerequisite NEVER selects no step -- the user rule: only mission unavailability may block'
Assert ($navText -match 'advisory\.advisory = true;') `
    'it becomes advice carried on the step'
Assert ($navText -match 'function accessxi\.nav_mission_quest_step_advisory\(native_key, step_id\)') `
    'which is looked up separately from refusals'
Assert ($navText -match 'and blocks\[native_key\]\[step_id\]\.advisory ~= true\) then') `
    'so it can never block the route through the refusal path'
Assert ($navText -match "suffix = suffix \.\. \(' Note: %s\.'\):fmt\(advisory:gsub\('%\.\$', ''\)\);") `
    'and the player HEARS it when the route starts -- the guide says get X first'
Assert ($resolverText -match 'if \(next\(needs\) == nil\) then\r?\n\s*return nil;') 'sequence is not requiredness: only an explicit item link can block'
Assert ($resolverText -notmatch "== 'silent oil'") 'no item is special-cased in the resolver'
Assert ($navText -match "objective prerequisite noted native=") 'the prerequisite is recorded with the step it belongs to -- noted, not held'
Assert ($navText -match '(?s)function accessxi\.nav_mission_quest_step_refusal.*?prerequisite_refusals.*?source_route_refusals') 'a prerequisite block outranks the resolver reason in speech'
Assert ($navText -match '\["windurst"\] = \{ 238, 239, 240, 241 \},') 'Windurst has four ordinary districts'
Assert ($navText -match '(?s)NATION_DISTRICT_ZONES = \{\s*\["san d''oria"\] = \{ 230, 231, 232 \},') 'Chateau d''Oraguille is not an ordinary district'
Assert ($resolverText -match "info\.kind = #targets > 1 and 'zone-travel-choice' or 'zone-travel';") 'a bare nation name lists district entrances as a choice'
$wgText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\walk_graph.lua')
Assert ($wgText -match 'is NOT a per-portal guarantee of 1\.5 yalms') 'the hazard-margin pin says what it promises'
Assert ($wgText -match 'local PORTAL_HAZARD_MARGIN_TRIMMED = 0x10;') 'the loader knows the trimmed-portal flag'
Assert ($wgText -match "tonumber\(policy\.builder_revision\) ~= 4") 'the loader pins builder revision 4'
Assert ($wgText -match "tonumber\(policy\.policy_flags\) ~= 3") 'the loader pins PORTAL_CAPACITY|HAZARD_MARGIN'

Write-Host 'Transports are typed edges: an anchor, a transit zone, availability, completion on the zone change:'
$transportPath = Join-Path $live 'data\ffxi-nav-transport-edges.tsv'
Assert (Test-Path -LiteralPath $transportPath) 'the transport edge table exists'
$transportRows = @(Get-Content -LiteralPath $transportPath | Where-Object { $_ -match '^\d' })
Assert ($transportRows.Count -ge 30) "the transport table carries rows ($($transportRows.Count))"
Assert (($transportRows | Where-Object { $_ -notmatch "`t(always|key_item:[^`t]+|unlock:[^`t]+)`t" }).Count -eq 0) 'every transport row declares availability (always, a named key item, or an unproven unlock)'
Assert (($transportRows | Where-Object { $_ -match "^910000(112|137|111|136)`t" }).Count -eq 0) 'the false Xarcabard and Beaucedine Maw identities are gone'
Assert (($transportRows | Where-Object { $_ -match "`tmaw`t" -and $_ -match "`t\d+`t[^`t]+ \[S\]`t" -and $_ -notmatch "unlock:" -and $_ -match "^9100001" }).Count -eq 0) 'no present-to-past Maw is offered as always available'
Assert ($resolverText -match 'function M\.prior_instances\(\r?\n\s*steps,\r?\n\s*index,\r?\n\s*entity_keys,\r?\n\s*ctx\)') 'return-home is a mission-local back-reference'
Assert ($resolverText -match "info\.kind = 'return-to-prior';" -and $resolverText -match "info\.kind = 'return-to-prior-choice';") `
    'a return routes to the instance an earlier step bound -- or offers them all when several bound'
Assert ($resolverText -match 'info\.equivalent_choices = equivalent;') `
    'and says whether the guide own wording ("a" or "any") makes those choices equivalent'

Write-Host 'A role is a job, not a missing NPC:'
$roleText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\objective_role_members.lua')
Assert ($roleText -match '\["gate guard"\] = \{') `
    'the roles the guide names instead of people are available to every step'
Assert ($roleText -match 'name = "Ambrotien"' -and $roleText -match 'name = "Endracion"' -and $roleText -match 'name = "Grilau"') `
    'with the members the reviewed guide named for them'
Assert ($roleText -match 'review_basis = "Exact gate-guard member notes') `
    'and the basis on which those members were admitted'
Assert ($roleText -match 'Do not edit by hand') `
    'generated from the reviewed overrides, not typed from memory'
Assert ($resolverText -match 'function M\.role_targets\(step, entity_keys, ctx\)') `
    'the resolver asks whether an absent entity is really a role'
Assert ($resolverText -match "kind = #targets > 1 and 'role-choice' or 'role',") `
    'and offers every member -- nothing is picked for the player'
Assert ($navText -match 'role_members = role_members_for,') `
    'the runtime supplies them'
Assert ($navText -match 'point_for_destination_id = point_for_destination_id,') `
    'and resolves each member to its catalogue point by exact destination id'
$rolePos = $resolverText.IndexOf('local role_targets, role_info =')
$zonePos = $resolverText.IndexOf('if (GUIDE_ZONE_ACTIONS[action]) then')
Assert ($rolePos -gt 0 -and $zonePos -gt 0 -and $rolePos -lt $zonePos) `
    'the role is tried BEFORE falling back to the zone -- it names real people, the zone only names a place'
Assert ($resolverText -match 'function M\.indefinite_target\(step, entity_keys\)') `
    '"a Gate Guard" and "Halver" are told apart by the guide own wording'

Write-Host 'What you come away with is not where you go:'
Assert ($resolverText -match 'function M\.is_result_item\(step, label, ctx\)') `
    'a reward the guide names is separable from a destination'
Assert ($resolverText -match "for _, field in ipairs\(\{ 'items', 'key_items', 'result_items' \}\) do") `
    'declared outright, it needs no reading'
Assert ($resolverText -match "local ITEM_LABEL_PATTERNS = \{ 'key%s\+items\?%s\+', 'items\?%s\+' \};") `
    'otherwise the guide own label is read -- "key item X"'
Assert ($resolverText -match "'to%s\+spawn%s\+', 'spawns\?%s\+'") `
    'and what the guide says you SPAWN is a result too -- the Dreamrose is the place, not the cactuar'
Assert ($resolverText -match "prose:find\('%f\[%a\]' \.\. prefix \.\. needle \.\. '%f\[%A\]'\)") `
    'the label must sit immediately before the name, on a word boundary both sides'
Assert ($resolverText -match 'if \(key ~= .. and not hint\s+and \(catalogued or not M\.is_result_item\(step, value, ctx\)\)\) then') `
    'a reward never becomes an entity to route to -- unless the catalogue says it IS a place'
Assert ($resolverText -match 'local catalogued = key ~= .. and ctx\.points_for_entity ~= nil') `
    'the catalogue is evidence; a label is only a description'
Assert ($resolverText -match 'if \(type\(ctx\) == .table. and type\(ctx\.declared_result_names\) == .function.\) then') `
    'and the guide DECLARATION is consulted before any prose is read'
Assert ($navText -match 'declared_result_names = function \(step_id\)') `
    'supplied from the compact progression action, where those fields are actually populated'
Assert ($resolverText -match "'war', 'mnk', 'whm', 'blm'") `
    'job ABBREVIATIONS are advice too -- "Suparna (WAR) and Suparna Fledgling (WHM)" put WAR and WHM in a mission entity list'

Write-Host 'Every storyline reports its progress, not only the three nations:'
$trackerText = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\mission_progress_tracker.lua')
Assert ($trackerText -match 'function M\.native_key_for_progress\(index, context, progress_id\)') `
    'a progress value names its mission by LOOKUP -- Zilart ids run 1,3,5 against progress 0,2,4 and no offset survives that'
Assert ($trackerText -match "if \(count > 1\) then\s+return '', 0, false;") `
    'a value naming more than one mission names none -- we do not pick'
Assert ($trackerText -match 'function M\.is_direct_successor\(index, context, previous_id, native_id\)') `
    'and only the NEXT mission in the guide ordering counts as a completion'
Assert ($trackerText -match 'if \(id > previous_id and id < native_id\) then\r?\n\s*return false;') `
    'asked of the ordering, not the numbers, because the numbers have gaps'
Assert ($trackerText -match 'if \(before ~= nil and tonumber\(before\) ~= tonumber\(value\)\) then') `
    'a storyline seen for the first time is a baseline, not a change'
Assert ($mainText -match 'function accessxi\.mission_progress_snapshot\(\)') `
    'the runtime reads every storyline the game reports'
Assert ($mainText -match 'accessxi\.current_mission_value_for_context, context') `
    'through the accessor that already handled all sixteen, including the acp/mkd/asa bitfields'
Assert ($mainText -match 'if \(key ~= .. and unmeasured == nil and \(not is_nation or context == own_nation\)\) then') `
    'and a nation appears only if it is the player own -- one field, three contexts, two would be fiction'
Assert ($mainText -match "pcall\(accessxi\.detect_mission_progress_changes, 'packet-main'\);") `
    'checked when the main mission packet arrives'
Assert ($mainText -match "pcall\(accessxi\.detect_mission_progress_changes, 'packet-ahturghan'\);") `
    'and when the Aht Urhgan packet does -- Assault, ToAU, Wings and Campaign live only there'
Assert ($mainText -match "log_line\(\('mission progress baseline reason=") `
    'the first comparison of a session is a silent baseline, and says so in the log'
Assert ($mainText -match "\['The Voracious Resurgence'\] = 'tales is a bitfield, not a mission counter',") `
    'a field that is not a mission counter is excluded by name, with its reason -- naming the wrong mission beats naming none is FALSE'
Assert ($mainText -match 'local unmeasured = type\(accessxi\.mission_progress_unmeasured_contexts\)') `
    'and the snapshot honours that exclusion'
Assert ($mainText -match 'local succeeded = previous_key ~= ..\r?\n\s*and accessxi\.mission_is_direct_successor\(context, previous_id, current_id\);') `
    'succession is proven before anything is called a completion'
Assert (($transportRows | Where-Object { $_ -match "`tairship`t" -and $_ -notmatch "key_item:airship pass" }).Count -eq 0) 'every airship row is gated on an airship pass key item'
Assert ($mainText -match "accessxi_paths\.addon_path\('data', 'ffxi-nav-transport-edges\.tsv'\)") 'the zone-line loader reads the transport table'
Assert ($mainText -match 'function accessxi\.nav_transport_edge_available\(edge\)') 'availability is a live key-item check'
Assert ($mainText -match "local key_item = availability:match\('\^key_item:\(\.\+\)\$'\);") 'key_item availability names the key item'
Assert ($mainText -match "(?s)function accessxi\.nav_zoneline_out_edges.*?and accessxi\.nav_transport_edge_available\(edge\).*?and \(type\(excluded\) ~= 'table'.*?table\.insert\(edges, edge\);") 'unavailable transports and previously rejected edges are excluded from the search'
Assert ($mainText -match "leg\.via_zone = tonumber\(edge\.transport\.via_zone\) or 0;") 'a transport leg knows its transit zone'
Assert ($mainText -match 'if \(waiting_via_zone > 0 and player_zone == waiting_via_zone\) then\r?\n\s*-- aboard the airship or ship: the leg completes at the far dock\r?\n\s*return false;') 'being aboard is not an unexpected zone change'
Assert ($mainText -match "text = \('At the %s\. %s'\):fmt\(destination\.name or 'dock', nav_clean_field\(destination\.transport_instruction\)\);") 'arrival at the anchor speaks how to board'
Assert ($mainText -match "transport_instruction = nav_clean_field\(point\.transport_instruction or ''\),") 'the boarding instruction survives the point copy to arrival'

Write-Host 'The beacon never pathfinds; the native context is budgeted, not looped:'
Assert ($mainText -match '(?s)function accessxi\.nav_mesh_probe_path.*?slots\[producer\] = T\{.*?return nil;\r?\nend') 'a probe miss records a request and computes nothing'
Assert ($mainText -match 'function accessxi\.nav_mesh_probe_fulfil\(now\)') 'the coordinator fulfils probe requests'
Assert ($mainText -match '< 250\) then\r?\n\s*return false;') 'at most one fulfilled probe per 250 ms'
Assert ($mainText -match "accessxi\.nav_mesh_probe_fulfil\(now\);") 'the present callback drives the coordinator, not the beacon pulse'
Assert ($mainText -match 'function accessxi\.nav_native_call_end\(started, export, label\)') 'every native search export call is counted and timed with its ordinal'
Assert ($mainText -match "accessxi\.nav_native_call_end\(fallback_started, 'FindPath', 'route-fallback'\);") 'the fallback FindPath consumes its own budget unit'
Assert ($mainText -match "nav native probe fulfilled producer=") 'a fulfilled request is logged'
Assert ($mainText -match "nav native probe memo hit hits=") 'memo consumption is logged'
Assert ($mainText -match "private_kb=%d->%d") 'a recycle logs private bytes before and after'
Assert ($mainText -match "slots\[producer\] = T\{") 'each producer owns one latest-value request slot'
Assert ($mainText -match "w\.generation = generation;   -- same ask: keep its queue position") 'a repeated ask keeps its queue position, it is not re-queued'
Assert ($mainText -match '\(tonumber\(w\.tick\) or 0\) < \(tonumber\(wanted\.tick\) or 0\)') 'the coordinator serves the oldest producer first'
$sightText2 = Get-Content -Raw -LiteralPath (Join-Path $live 'modules\beacon_sightline.lua')
Assert (($sightText2 -match "'detour'\);") -and ($sightText2 -match "'sightline'\);")) 'both producers name themselves'
Assert ($mainText -match 'if \(ordinal < 900\) then\r?\n\s*return;') 'the recycle budget is 900 completed sequences'
Assert ($mainText -match 'if \(accessxi\.nav_native_recycled_in_zone ~= true\) then\r?\n\s*if \(idle\) then') 'a recycle happens once per zone and only while the coordinator is idle'
Assert ($mainText -match "speak\('Mesh navigation is paused until you change zones\.'\);") 'a second exhausted budget disables native pathfinding and says so'
Assert ($mainText -match "ffxinav\.unload\(handle\)") 'the recycle is unload()+LoadMesh() on the same context, as the bench proved'
Assert ($mainText -match 'bool unload\(void\* pFfxiNavClassObject\);') 'unload is declared to ffi'
Assert ($mainText -match 'accessxi\.nav_native_zone_reset\(\);') 'the budget resets on zone change'

Write-Host 'The switch:'
Assert ($moduleText -match 'local DEFAULT_ENABLED = true;') 'the walk graph is enabled by default'

Write-Host ''
Write-Host 'All walk-graph release gates passed.'
