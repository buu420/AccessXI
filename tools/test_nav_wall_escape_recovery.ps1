$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot '..\ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $sourcePath -Raw

$applyStart = $source.IndexOf('function accessxi.nav_apply_wall_avoidance')
$applyEnd = $source.IndexOf('function accessxi.nav_reset_progress_watch', $applyStart)
if ($applyStart -lt 0 -or $applyEnd -lt 0) {
    throw 'Could not locate wall-avoidance production block.'
}
$applyBody = $source.Substring($applyStart, $applyEnd - $applyStart)

if ($applyBody -notmatch 'nav_wall_escape_recovery_active\(now\)') {
    throw 'Low wall clearance still overrides valid navmesh waypoints without confirmed recovery state.'
}
if ($applyBody -notmatch 'return route_target') {
    throw 'Normal navmesh steering must retain the original route target outside recovery.'
}

$collisionStart = $source.IndexOf('function accessxi.nav_collision_watch')
$collisionEnd = $source.IndexOf('function accessxi.nav_freewalk_collision_reset', $collisionStart)
$collisionBody = $source.Substring($collisionStart, $collisionEnd - $collisionStart)
if ($collisionBody -notmatch "state\.state == 'blocked'[\s\S]*?nav_wall_escape_begin_recovery\(now\)") {
    throw 'A confirmed blocked collision no longer enables bounded wall-escape recovery.'
}

$progressStart = $source.IndexOf('function accessxi.nav_progress_watch')
$progressEnd = $source.IndexOf('function accessxi.nav_route_guidance_speech_enabled', $progressStart)
$progressBody = $source.Substring($progressStart, $progressEnd - $progressStart)
if ($progressBody -notmatch 'nav_wall_escape_begin_recovery\(now\)') {
    throw 'A confirmed no-progress stall no longer enables bounded wall-escape recovery.'
}

Write-Host 'nav wall escape recovery gates passed'
