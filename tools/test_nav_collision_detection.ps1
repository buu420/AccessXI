$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$ghidraTracePath = 'C:\Users\buu42\AccessXI\ffxi_re\out\ffxi_collision_actor_rtti_trace.txt'

function Assert-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

if (-not (Test-Path -LiteralPath $ghidraTracePath)) {
    throw 'Expected focused Ghidra collision actor RTTI trace output.'
}

$source = Get-Content -LiteralPath $addonPath -Raw
$ghidraTrace = Get-Content -LiteralPath $ghidraTracePath -Raw

Assert-Match `
    -Text $ghidraTrace `
    -Pattern 'CXiCollisionActor' `
    -Message 'Expected Ghidra trace to include native CXiCollisionActor evidence.'

Assert-Match `
    -Text $ghidraTrace `
    -Pattern 'FUN_100a4e00' `
    -Message 'Expected Ghidra trace to identify the CXiCollisionActor update/decompile path.'

Assert-Match `
    -Text $ghidraTrace `
    -Pattern '\+ 0x5e2\)\s*=\s*1' `
    -Message 'Expected Ghidra trace to show the native collision-result byte at actor offset 0x5e2.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_player_moving\(\)' `
    -Message 'Expected nav movement-intent helper backed by Ashita target state.'

$movingStart = $source.IndexOf('function accessxi.nav_player_moving()')
$movingEnd = $source.IndexOf('function accessxi.nav_collision_reset', $movingStart)
if ($movingStart -lt 0 -or $movingEnd -lt 0) {
    throw 'Could not locate nav player-moving helper block.'
}
$movingBody = $source.Substring($movingStart, $movingEnd - $movingStart)

Assert-Match `
    -Text $movingBody `
    -Pattern '(?s)GetTarget\(\).*?GetIsPlayerMoving\(\)' `
    -Message 'Nav collision detection should use Ashita GetIsPlayerMoving state.'

Assert-NotMatch `
    -Text $movingBody `
    -Pattern 'GetAsyncKeyState|VK_LEFT|VK_RIGHT|VK_UP|VK_DOWN|VK_RETURN|VK_NUMPAD' `
    -Message 'Nav movement intent must not be inferred from key monitoring.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_recent_movement_ms\s*=' `
    -Message 'Expected a bounded recent-movement window so standing still does not count as collision.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_player_movement_signal\(player,\s*now\)' `
    -Message 'Expected a native movement-signal helper for collision detection.'

$signalStart = $source.IndexOf('function accessxi.nav_player_movement_signal')
$signalEnd = $source.IndexOf('function accessxi.nav_collision_reset', $signalStart)
if ($signalStart -lt 0 -or $signalEnd -lt 0) {
    throw 'Could not locate nav movement-signal helper block.'
}
$signalBody = $source.Substring($signalStart, $signalEnd - $signalStart)

Assert-Match `
    -Text $signalBody `
    -Pattern '(?s)GetTarget\(\).*?GetIsPlayerMoving\(\)' `
    -Message 'Movement signal should still include the native Ashita moving state.'

Assert-Match `
    -Text $signalBody `
    -Pattern '(?s)GetAutoFollow\(\).*?GetIsAutoRunning\(\)' `
    -Message 'Movement signal should include native autorun state.'

Assert-Match `
    -Text $signalBody `
    -Pattern 'GetLocalMoveCount|LocalMoveCount' `
    -Message 'Movement signal should use native entity move-count changes to detect attempted movement.'

Assert-Match `
    -Text $signalBody `
    -Pattern 'nav_movement_recent_tick' `
    -Message 'Movement signal should remember recent real movement briefly for wall-impact detection.'

Assert-NotMatch `
    -Text $signalBody `
    -Pattern 'GetAsyncKeyState|VK_LEFT|VK_RIGHT|VK_UP|VK_DOWN|VK_RETURN|VK_NUMPAD' `
    -Message 'Movement signal must not inspect keys.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_collision_state\(player,\s*destination,\s*route_target,\s*destination_distance,\s*now,\s*movement_signal\)' `
    -Message 'Expected pure nav collision classifier helper.'

$stateStart = $source.IndexOf('function accessxi.nav_collision_state')
$stateEnd = $source.IndexOf('function accessxi.nav_collision_watch', $stateStart)
if ($stateStart -lt 0 -or $stateEnd -lt 0) {
    throw 'Could not locate nav collision classifier block.'
}
$stateBody = $source.Substring($stateStart, $stateEnd - $stateStart)

Assert-Match `
    -Text $stateBody `
    -Pattern 'movement_signal\.active\s*~=*\s*true' `
    -Message 'Classifier should require a native movement signal before considering collision.'

Assert-Match `
    -Text $stateBody `
    -Pattern 'moved\s*[<>=]+.*?0\.[0-9]' `
    -Message 'Classifier should require sub-yalm actual movement.'

Assert-Match `
    -Text $stateBody `
    -Pattern 'route_improvement\s*[<>=]+.*?0\.[0-9]' `
    -Message 'Classifier should require little or no route progress.'

Assert-Match `
    -Text $stateBody `
    -Pattern 'nav_wall_distance\(player\)' `
    -Message 'Classifier should corroborate against navmesh wall clearance.'

Assert-Match `
    -Text $stateBody `
    -Pattern 'nav_valid_mesh_position\(ahead\)' `
    -Message 'Classifier should sample the route-ahead mesh position.'

Assert-Match `
    -Text $stateBody `
    -Pattern 'nav_normalize_angle\(target_heading \+ yaw\)' `
    -Message 'Classifier should require the player to be roughly facing the route target.'

Assert-Match `
    -Text $stateBody `
    -Pattern "state\s*=\s*'blocked'" `
    -Message 'Classifier should emit a high-confidence blocked state.'

Assert-Match `
    -Text $stateBody `
    -Pattern "state\s*=\s*'scraping'" `
    -Message 'Classifier should distinguish edge scraping from full blocking.'

Assert-NotMatch `
    -Text $stateBody `
    -Pattern 'GetAsyncKeyState|VK_LEFT|VK_RIGHT|VK_UP|VK_DOWN|VK_RETURN|VK_NUMPAD' `
    -Message 'Collision classifier must not inspect keys.'

$watchStart = $source.IndexOf('function accessxi.nav_collision_watch')
$progressStart = $source.IndexOf('function accessxi.nav_current_route_instruction', $watchStart)
if ($watchStart -lt 0 -or $progressStart -lt 0) {
    throw 'Could not locate nav collision watch block.'
}
$watchBody = $source.Substring($watchStart, $progressStart - $watchStart)

Assert-NotMatch `
    -Text $watchBody `
    -Pattern 'nav_collision_last_sound_tick.*?<\s*6500|6500.*?nav_collision_last_sound_tick' `
    -Message 'Collision cue playback should not be suppressed by the old cooldown gate.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_sound_dir\s*=' `
    -Message 'Expected a dedicated nav collision sound directory.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_freewalk_sound_ms\s*=\s*2[0-9][0-9]' `
    -Message 'Free-walk wall bump interval should be faster than the previous 320ms cadence.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_freewalk_hold_ms\s*=\s*2[0-9][0-9]' `
    -Message 'Free-walk wall bump hold should be short enough for a quicker tactile cadence.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_quiet_until\s*=' `
    -Message 'Expected a collision quiet window for zoning/loading transitions.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_require_fresh_movement\s*=\s*false' `
    -Message 'Expected zoning to require fresh real movement before collision sounds resume.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_collision_quiet\(reason,\s*duration_ms,\s*now\)' `
    -Message 'Expected a helper to silence collision sounds during zoning/loading.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_control_interrupt_active\s*=\s*false' `
    -Message 'Expected nav collision to remember when game UI/cutscene control has interrupted movement.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_collision_control_return_quiet_ms\s*=' `
    -Message 'Expected a post-control-return collision quiet duration.'

$quietStart = $source.IndexOf('function accessxi.nav_collision_quiet')
$quietEnd = $source.IndexOf('function accessxi.nav_reset_zone_state', $quietStart)
if ($quietStart -lt 0 -or $quietEnd -lt 0) {
    throw 'Could not locate nav collision quiet helper block.'
}
$quietBody = $source.Substring($quietStart, $quietEnd - $quietStart)

Assert-Match `
    -Text $quietBody `
    -Pattern 'nav_movement_recent_tick\s*=\s*0' `
    -Message 'Collision quiet windows should clear stale movement history.'

Assert-Match `
    -Text $quietBody `
    -Pattern 'nav_collision_require_fresh_movement\s*=\s*true' `
    -Message 'Zoning/loading quiet windows should require one fresh real movement sample before wall bumps resume.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_collision_ensure_sounds\(\)' `
    -Message 'Expected generated collision cue sound setup.'

Assert-Match `
    -Text $source `
    -Pattern "wall-bump\.wav" `
    -Message 'Blocked wall collisions should use a generated bright wall-bump cue.'

Assert-Match `
    -Text $watchBody `
    -Pattern 'nav_collision_quiet_until' `
    -Message 'Route collision watch should honor control/zoning quiet windows before playing collision sounds.'

Assert-Match `
    -Text $watchBody `
    -Pattern 'nav_collision_reset\(nil,\s*0,\s*0,\s*now\)' `
    -Message 'Quieted route collision watch should clear stale route collision anchors.'

Assert-Match `
    -Text $watchBody `
    -Pattern 'accessxi\.nav_collision_state\(player,\s*destination,\s*route_target,\s*destination_distance,\s*now,\s*accessxi\.nav_player_movement_signal\(player,\s*now\)\)' `
    -Message 'Collision watch should pass the richer movement signal into the classifier.'

Assert-Match `
    -Text $watchBody `
    -Pattern 'accessxi\.nav_collision_play_sound\(state\.state,\s*now\)' `
    -Message 'Collision watch should play a short sound cue.'

$playIndex = $watchBody.IndexOf('accessxi.nav_collision_play_sound(state.state, now)')
$firstReturnTrue = $watchBody.IndexOf('return true')
if ($playIndex -lt 0 -or ($firstReturnTrue -ge 0 -and $firstReturnTrue -lt $playIndex)) {
    throw 'Collision watch should play the sound before returning for any detected collision state.'
}

$playStart = $source.IndexOf('function accessxi.nav_collision_play_sound')
$beaconStart = $source.IndexOf('function accessxi.nav_beacon_ensure_files', $playStart)
if ($playStart -lt 0 -or $beaconStart -lt 0) {
    throw 'Could not locate nav collision sound playback block.'
}
$playBody = $source.Substring($playStart, $beaconStart - $playStart)

Assert-Match `
    -Text $playBody `
    -Pattern "local filename\s*=\s*'wall-bump\.wav'" `
    -Message 'Collision playback should use the cleaner wall-bump cue.'

Assert-NotMatch `
    -Text $playBody `
    -Pattern "thunk\.wav|scrape\.wav" `
    -Message 'Collision playback should not use the old clunk or scrape cues.'

Assert-Match `
    -Text $source `
    -Pattern "cue\s*==\s*'bump'" `
    -Message 'Expected a synthesized bright bump cue.'

$bumpStart = $source.IndexOf("if (cue == 'bump') then")
$thunkStart = $source.IndexOf("elseif (cue == 'thunk') then", $bumpStart)
if ($bumpStart -lt 0 -or $thunkStart -lt 0) {
    throw 'Could not locate synthesized wall-bump cue block.'
}
$bumpBody = $source.Substring($bumpStart, $thunkStart - $bumpStart)

Assert-Match `
    -Text $bumpBody `
    -Pattern 'local strike1' `
    -Message 'Wall-bump cue should use a polished two-strike synthesized shape.'

Assert-NotMatch `
    -Text $bumpBody `
    -Pattern 'math\.floor\(t \* [0-9]+\)' `
    -Message 'Wall-bump cue should not use the harsher bitcrushed source.'

Assert-NotMatch `
    -Text $bumpBody `
    -Pattern '>=\s*0\s*and\s*1\s*or\s*-1' `
    -Message 'Wall-bump cue should not use hard square waves.'

Assert-Match `
    -Text $source `
    -Pattern "name\s*=\s*'wall-bump\.wav'.*?cue\s*=\s*'bump'" `
    -Message 'Expected wall-bump.wav to be generated from the bump cue.'

Assert-NotMatch `
    -Text $source `
    -Pattern "name\s*=\s*'wall-bump\.wav'.*?always\s*=\s*true" `
    -Message 'User-provided wall-bump.wav should not be overwritten on addon reload.'

Assert-NotMatch `
    -Text $watchBody `
    -Pattern 'speak\(' `
    -Message 'Collision watch should not speak announcements during live navigation.'

Assert-Match `
    -Text $watchBody `
    -Pattern "nav_write_route_evidence\('collision'" `
    -Message 'Collision detection should write route evidence for later path repair.'

Assert-Match `
    -Text $watchBody `
    -Pattern "log_line\(\('nav collision" `
    -Message 'Collision detection should leave a concise diagnostic log line.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_freewalk_collision_state\(player,\s*now,\s*movement_signal\)' `
    -Message 'Expected a non-route collision classifier for normal movement.'

$freeStart = $source.IndexOf('function accessxi.nav_freewalk_collision_state')
$freePollStart = $source.IndexOf('function accessxi.poll_nav_collision_sound', $freeStart)
if ($freeStart -lt 0 -or $freePollStart -lt 0) {
    throw 'Could not locate free-walk collision classifier block.'
}
$freeBody = $source.Substring($freeStart, $freePollStart - $freeStart)
$freePollEnd = $source.IndexOf('function accessxi.nav_current_route_instruction', $freePollStart)
if ($freePollEnd -lt 0) {
    throw 'Could not locate free-walk collision poll block.'
}
$freePollBody = $source.Substring($freePollStart, $freePollEnd - $freePollStart)

Assert-Match `
    -Text $freeBody `
    -Pattern 'movement_signal\.active\s*~=*\s*true' `
    -Message 'Free-walk collision detection should require a native movement signal.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'movement_signal\.moving\s*~=*\s*true.*?movement_signal\.autorun\s*~=*\s*true.*?movement_signal\.move_count_recent\s*~=*\s*true' `
    -Message 'Free-walk collision detection should not trigger from stale recent movement alone.'

Assert-NotMatch `
    -Text $freeBody `
    -Pattern 'recent_age\s*>\s*\(tonumber\(accessxi\.nav_collision_freewalk_recent_ms' `
    -Message 'Free-walk collision detection should not keep wall bumps alive from recent movement alone.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'nav_collision_freewalk_x' `
    -Message 'Free-walk collision detection should compare position against its own short anchor.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'nav_collision_freewalk_yaw' `
    -Message 'Free-walk collision detection should keep a yaw anchor so turning can be distinguished from collision.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'anchor_yaw\s*=\s*tonumber\(accessxi\.nav_collision_freewalk_yaw\)' `
    -Message 'Free-walk collision detection should measure yaw changes against its anchor.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'nav_normalize_angle\(yaw - anchor_yaw\)' `
    -Message 'Free-walk collision detection should compare current yaw to the anchor yaw.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'turn_delta.*nav_collision_freewalk_turn_radians' `
    -Message 'Free-walk collision detection should reset instead of thunking when the player is only turning.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'nav_valid_mesh_position\(ahead\)' `
    -Message 'Free-walk collision detection should sample the navmesh in front of the player.'

Assert-Match `
    -Text $freeBody `
    -Pattern 'nav_wall_distance\(player\)' `
    -Message 'Free-walk collision detection should use wall clearance as corroboration.'

Assert-NotMatch `
    -Text $freeBody `
    -Pattern 'GetAsyncKeyState|VK_LEFT|VK_RIGHT|VK_UP|VK_DOWN|VK_RETURN|VK_NUMPAD' `
    -Message 'Free-walk collision classifier must not inspect keys.'

Assert-Match `
    -Text $freePollBody `
    -Pattern 'nav_collision_quiet_until' `
    -Message 'Free-walk collision polling should honor zoning/loading quiet windows.'

Assert-Match `
    -Text $freePollBody `
    -Pattern 'accessxi\.nav_collision_update_control_interrupt\(now\)' `
    -Message 'Free-walk collision polling should silence stale movement after NPC menus and cutscene control returns.'

Assert-Match `
    -Text $freePollBody `
    -Pattern 'nav_collision_require_fresh_movement' `
    -Message 'Free-walk collision polling should keep zoning quiet active until fresh real movement is observed.'

Assert-Match `
    -Text $freePollBody `
    -Pattern '(?s)movement_signal\.actual_moved\s*==\s*true.*?nav_collision_require_fresh_movement\s*=\s*false' `
    -Message 'Fresh actual movement should release the post-zone collision quiet latch.'

Assert-Match `
    -Text $freePollBody `
    -Pattern '(?s)nav_collision_require_fresh_movement\s*==\s*true.*?nav_freewalk_collision_reset\(nil,\s*now\).*?return false' `
    -Message 'Post-zone collision quiet latch should suppress stale held-key movement.'

Assert-Match `
    -Text $freePollBody `
    -Pattern 'nav_freewalk_collision_reset\(nil,\s*now\)' `
    -Message 'Quieted free-walk polling should clear stale collision anchors.'

$zoneResetStart = $source.IndexOf('function accessxi.nav_reset_zone_state')
$pollPositionStart = $source.IndexOf('local function poll_nav_position', $zoneResetStart)
if ($zoneResetStart -lt 0 -or $pollPositionStart -lt 0) {
    throw 'Could not locate nav zone reset block.'
}
$zoneResetBody = $source.Substring($zoneResetStart, $pollPositionStart - $zoneResetStart)

Assert-Match `
    -Text $zoneResetBody `
    -Pattern "nav_collision_quiet\('zone-change'" `
    -Message 'Zone changes should start a collision quiet window.'

$arrivalIndex = $source.IndexOf("nav_write_route_evidence('arrived'")
if ($arrivalIndex -lt 0) {
    throw 'Could not locate nav route arrival block.'
}
$arrivalBody = $source.Substring($arrivalIndex, [Math]::Min(2200, $source.Length - $arrivalIndex))

Assert-Match `
    -Text $arrivalBody `
    -Pattern 'zone line' `
    -Message 'Zone-line route arrivals should be recognized before loading begins.'

Assert-Match `
    -Text $arrivalBody `
    -Pattern "nav_collision_quiet\('zone-line-arrival'" `
    -Message 'Zone-line route arrivals should silence wall bumps while the next zone loads.'

$freePollEnd = $source.IndexOf('function accessxi.nav_current_route_instruction', $freePollStart)
if ($freePollStart -lt 0 -or $freePollEnd -lt 0) {
    throw 'Could not locate free-walk collision poll block.'
}
$freePollBody = $source.Substring($freePollStart, $freePollEnd - $freePollStart)

Assert-Match `
    -Text $freePollBody `
    -Pattern 'nav_route_suppressed\(\)' `
    -Message 'Free-walk collision sounds should stay quiet while menus or chat input suppress nav.'

Assert-Match `
    -Text $freePollBody `
    -Pattern 'accessxi\.nav_player_movement_signal\(player,\s*now\)' `
    -Message 'Free-walk collision poll should use the same native movement signal.'

Assert-Match `
    -Text $freePollBody `
    -Pattern "accessxi\.nav_collision_play_sound\('blocked',\s*now\)" `
    -Message 'Free-walk collision poll should play the wall thunk cue.'

Assert-Match `
    -Text $freePollBody `
    -Pattern "log_line\(\('nav collision freewalk" `
    -Message 'Free-walk collision poll should log concise diagnostics.'

Assert-NotMatch `
    -Text $freePollBody `
    -Pattern 'speak\(' `
    -Message 'Free-walk collision poll should not speak announcements.'

$presentStart = $source.IndexOf("ashita.events.register('d3d_present'")
$presentEnd = $source.IndexOf('end);', $presentStart)
if ($presentStart -lt 0 -or $presentEnd -lt 0) {
    throw 'Could not locate d3d_present poll block.'
}
$presentBody = $source.Substring($presentStart, $presentEnd - $presentStart)

Assert-Match `
    -Text $presentBody `
    -Pattern 'accessxi\.poll_nav_collision_sound\(\)' `
    -Message 'd3d_present should poll free-walk collision sounds even when no route is active.'

$routeStart = $source.IndexOf('local function poll_nav_route()')
$routeEnd = $source.IndexOf("ashita.events.register('load'", $routeStart)
if ($routeStart -lt 0 -or $routeEnd -lt 0) {
    throw 'Could not locate poll_nav_route block.'
}
$routeBody = $source.Substring($routeStart, $routeEnd - $routeStart)

Assert-Match `
    -Text $routeBody `
    -Pattern 'accessxi\.nav_collision_update_control_interrupt\(now\)' `
    -Message 'Route polling should track menu/cutscene control transitions even while nav is suppressed.'

Assert-Match `
    -Text $routeBody `
    -Pattern 'accessxi\.nav_collision_watch\(player,\s*destination,\s*route_target,\s*destination_distance,\s*now\)' `
    -Message 'Route polling should run the collision watch before the slower progress watchdog.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_collision_control_interrupt_state\(\)' `
    -Message 'Expected a live control-interrupt detector for menus, chat input, NPC windows, and cutscenes.'

$controlStart = $source.IndexOf('function accessxi.nav_collision_control_interrupt_state')
$controlEnd = $source.IndexOf('function accessxi.nav_player_moving', $controlStart)
if ($controlStart -lt 0 -or $controlEnd -lt 0) {
    throw 'Could not locate nav collision control-interrupt block.'
}
$controlBody = $source.Substring($controlStart, $controlEnd - $controlStart)

Assert-Match `
    -Text $controlBody `
    -Pattern 'get_menu_name\(\)' `
    -Message 'Control-interrupt detector should use the live menu name instead of a static table.'

Assert-Match `
    -Text $controlBody `
    -Pattern 'GetIsMenuOpen\(\)' `
    -Message 'Control-interrupt detector should use the live Ashita target menu-open flag.'

Assert-Match `
    -Text $controlBody `
    -Pattern "control-interrupt:" `
    -Message 'Active game-control interruptions should start a collision quiet window.'

Assert-Match `
    -Text $controlBody `
    -Pattern "control-return:" `
    -Message 'Returning from game-control interruptions should start a fresh-movement collision quiet latch.'

Assert-Match `
    -Text $controlBody `
    -Pattern 'nav_collision_quiet\(' `
    -Message 'Control-interrupt tracking should reuse the collision quiet helper.'

$progressStart = $source.IndexOf('function accessxi.nav_progress_watch')
$progressEnd = $source.IndexOf('function accessxi.nav_route_guidance_speech_enabled', $progressStart)
if ($progressStart -lt 0 -or $progressEnd -lt 0) {
    throw 'Could not locate nav progress watch block.'
}
$progressBody = $source.Substring($progressStart, $progressEnd - $progressStart)

Assert-Match `
    -Text $progressBody `
    -Pattern 'nav_collision_quiet_until' `
    -Message 'Route progress watchdog should honor control/zoning quiet windows.'

Assert-Match `
    -Text $progressBody `
    -Pattern 'nav_reset_progress_watch\(nil,\s*0,\s*now\)' `
    -Message 'Quieted route progress watchdog should clear stale progress anchors.'

Write-Host 'nav collision detection checks ok'
