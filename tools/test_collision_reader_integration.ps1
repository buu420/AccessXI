$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ReaderPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
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

$ComputeStart = $Reader.IndexOf('function accessxi.nav_compute_route_with_zoneline_approach(player, point)')
$ComputeEnd = $Reader.IndexOf('accessxi.nav_generated_name_is_placeholder', $ComputeStart)
if ($ComputeStart -lt 0 -or $ComputeEnd -le $ComputeStart) { throw 'Could not isolate generic route computation.' }
$Compute = $Reader.Substring($ComputeStart, $ComputeEnd - $ComputeStart)
$CollisionIndex = $Compute.IndexOf('accessxi.nav_dat_collision_route(player, point)')
$LegacyIndex = $Compute.IndexOf('nav_compute_mesh_route(player, point)')
if ($CollisionIndex -lt 0 -or $LegacyIndex -lt 0 -or $CollisionIndex -gt $LegacyIndex) {
    throw 'Collision terrain must run before the legacy generic navmesh.'
}

Write-Output 'collision reader integration tests passed'
