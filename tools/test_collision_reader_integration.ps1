$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ReaderPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$LuaPath = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'
$LifecycleHarness = Join-Path $RepoRoot 'tools\lua_tests\test_collision_reader_lifecycle.lua'
$HybridRouteHarness = Join-Path $RepoRoot 'tools\lua_tests\test_collision_route_hybrid.lua'
$SegmentSteeringHarness = Join-Path $RepoRoot 'tools\lua_tests\test_dat_collision_segment_steering.lua'
$BeaconTurnCueHarness = Join-Path $RepoRoot 'tools\lua_tests\test_nav_beacon_route_turn_cue.lua'
$BeaconPlaybackHarness = Join-Path $RepoRoot 'tools\lua_tests\test_nav_beacon_playback.lua'
$BeaconHrtfAssets = Join-Path $RepoRoot 'tools\test_nav_beacon_hrtf_assets.ps1'
$BeaconAudioMode = Join-Path $RepoRoot 'tools\test_nav_beacon_audio_mode.ps1'
$LaTheineDispatchHarness = Join-Path $RepoRoot 'tools\lua_tests\test_lathine_collision_fallback_dispatch.lua'
$RecordedSurveyHarness = Join-Path $RepoRoot 'tools\lua_tests\test_lathine_recorded_survey_wall_fallback.lua'
$RecordedSurveyModule = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\recorded_survey_navigation.lua'
$RecordedSurveyGraph = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\data\ffxi-nav-recorded-survey.tsv'
$Reader = Get-Content -LiteralPath $ReaderPath -Raw

function Require-Literal([string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle)) { throw $Message }
}

Require-Literal $Reader 'function accessxi.nav_dat_collision_bootstrap()' `
    'Reader does not bootstrap collision navigation.'
Require-Literal $Reader 'accessxi.nav_dat_collision_route(player, point)' `
    'Generic same-zone routes do not call collision navigation.'
Require-Literal $Reader 'function accessxi.poll_nav_dat_collision(now)' `
    'Reader does not poll asynchronous collision terrain.'
Require-Literal $Reader "accessxi.nav_dat_collision_state:cancel('zone-change')" `
    'Zone reset does not cancel collision terrain work.'
Require-Literal $Reader 'accessxi.nav_dat_collision_state:shutdown()' `
    'Addon unload does not destroy the collision context.'
Require-Literal $Reader 'accessxi.nav_recorded_survey_zoneline_edge_priority(edge)' `
    'Recorded walked entrances do not influence zone-line selection.'

$ComputeStart = $Reader.IndexOf('function accessxi.nav_compute_route_with_zoneline_approach(player, point)')
$ComputeEnd = $Reader.IndexOf('accessxi.nav_generated_name_is_placeholder', $ComputeStart)
if ($ComputeStart -lt 0 -or $ComputeEnd -le $ComputeStart) { throw 'Could not isolate generic route computation.' }
$Compute = $Reader.Substring($ComputeStart, $ComputeEnd - $ComputeStart)
$CollisionIndex = $Compute.IndexOf('accessxi.nav_dat_collision_route(player, point)')
$LegacyIndex = if ($CollisionIndex -ge 0) {
    $Compute.IndexOf('nav_compute_mesh_route(player, point)', $CollisionIndex)
} else { -1 }
if ($CollisionIndex -lt 0 -or $LegacyIndex -lt 0 -or $CollisionIndex -gt $LegacyIndex) {
    throw 'Collision terrain must run before the legacy generic navmesh.'
}

& $LuaPath $LifecycleHarness $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "Collision reader lifecycle harness failed with exit code $LASTEXITCODE."
}

& $LuaPath $HybridRouteHarness $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "Collision route hybrid harness failed with exit code $LASTEXITCODE."
}

& $LuaPath $SegmentSteeringHarness $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "Collision segment steering harness failed with exit code $LASTEXITCODE."
}

& $LuaPath $BeaconTurnCueHarness $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "Navigation beacon turn-cue harness failed with exit code $LASTEXITCODE."
}

& $LuaPath $BeaconPlaybackHarness $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "Navigation beacon playback harness failed with exit code $LASTEXITCODE."
}

& $BeaconHrtfAssets
if ($LASTEXITCODE -ne 0) {
    throw "Navigation beacon HRTF asset checks failed with exit code $LASTEXITCODE."
}

& $BeaconAudioMode
if ($LASTEXITCODE -ne 0) {
    throw "Navigation beacon audio-mode checks failed with exit code $LASTEXITCODE."
}

& $LuaPath $LaTheineDispatchHarness $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "La Theine fast navmesh dispatch harness failed with exit code $LASTEXITCODE."
}

& $LuaPath $RecordedSurveyHarness $RecordedSurveyModule $RecordedSurveyGraph $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "La Theine recorded entrance harness failed with exit code $LASTEXITCODE."
}

Write-Output 'collision reader integration tests passed'
