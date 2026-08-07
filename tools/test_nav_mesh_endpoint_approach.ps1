$ErrorActionPreference = 'Stop'

$root = 'C:\Users\buu42\AccessXI'
$addonPath = Join-Path $root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$probePath = Join-Path $root 'tools\navprobe\bin\Release\net8.0\win-x86\publish\navprobe.exe'
$meshPath = Join-Path $root 'third_party\xiNavmeshes\Port_Windurst.nav'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

function Get-WaypointCount {
    param([string[]]$Output)
    $line = $Output | Where-Object { $_ -match '^waypoints\s+\d+' } | Select-Object -First 1
    if ($null -eq $line -or $line -notmatch '^waypoints\s+(\d+)') {
        throw 'navprobe did not report a waypoint count.'
    }
    return [int]$Matches[1]
}

if (-not (Test-Path -LiteralPath $probePath)) { throw 'Expected the built navprobe tool.' }
if (-not (Test-Path -LiteralPath $meshPath)) { throw 'Expected the installed Port Windurst navmesh.' }

$exactOutput = & $probePath $meshPath -161.728 -4 97.883 18.629 -3.326 76.404
$approachOutput = & $probePath $meshPath -161.728 -4 97.883 18.629 -3.326 74.904
$exactCount = Get-WaypointCount $exactOutput
$approachCount = Get-WaypointCount $approachOutput

if ($exactCount -ne 1) {
    throw "Expected the live Aroro endpoint regression to return one unusable point; got $exactCount."
}
if ($approachCount -le 1) {
    throw "Expected the current mesh to route to the 1.5-yalm Aroro approach; got $approachCount."
}

Assert-Match -Text $source -Pattern 'function accessxi\.nav_compute_mesh_endpoint_approach\(player, point\)' -Message 'Missing bounded mesh endpoint approach helper.'

$helperStart = $source.IndexOf('function accessxi.nav_compute_mesh_endpoint_approach(player, point)')
$helperEnd = $source.IndexOf('function accessxi.nav_area_point_reachable', $helperStart)
if ($helperStart -lt 0 -or $helperEnd -lt 0) { throw 'Could not isolate the mesh endpoint approach helper.' }
$helperBody = $source.Substring($helperStart, $helperEnd - $helperStart)

Assert-Match -Text $helperBody -Pattern 'nav_arrival_radius\(point\)' -Message 'Endpoint probes must remain inside the destination arrival radius.'
Assert-Match -Text $helperBody -Pattern '1\.5[\s\S]*?2\.5[\s\S]*?4\.0[\s\S]*?6\.0' -Message 'Expected bounded small endpoint approach rings.'
Assert-Match -Text $helperBody -Pattern 'math\.pi\s*/\s*4' -Message 'Expected eight evenly spaced candidates per approach ring.'
Assert-Match -Text $helperBody -Pattern 'nav_compute_mesh_route\(player, candidate\)' -Message 'Approaches must be derived from the current navmesh.'
Assert-Match -Text $helperBody -Pattern 'candidate_route:len\(\)\s*>\s*1' -Message 'A one-point approach must never be accepted.'
Assert-NotMatch -Text $helperBody -Pattern 'append\([^\r\n]*point\)' -Message 'The unusable exact endpoint must not be appended after the safe approach.'

$routeStart = $source.IndexOf('function accessxi.nav_compute_route_with_zoneline_approach(player, point)')
$routeEnd = $source.IndexOf('accessxi.nav_generated_name_is_placeholder', $routeStart)
if ($routeStart -lt 0 -or $routeEnd -lt 0) { throw 'Could not isolate route construction.' }
$routeBody = $source.Substring($routeStart, $routeEnd - $routeStart)

Assert-Match -Text $routeBody -Pattern 'nav_compute_mesh_route\(player, point\)[\s\S]*?nav_compute_mesh_endpoint_approach\(player, point\)' -Message 'Incomplete exact routes must try a mesh-derived endpoint approach.'
Assert-Match -Text $routeBody -Pattern "nav_point_effective_kind\(point\)[\s\S]*?kind ~= 'area'" -Message 'Area destinations must be excluded from endpoint probing.'
Assert-Match -Text $routeBody -Pattern 'navmesh returned no verified walkable path' -Message 'Failed endpoint probes must retain an explicit unsafe-route rejection reason.'

$blockStart = $source.IndexOf('function accessxi.nav_route_direct_fallback_block_reason(player, point)')
$blockEnd = $source.IndexOf('function accessxi.nav_lathine_recorded_ravine_escape_route', $blockStart)
if ($blockStart -lt 0 -or $blockEnd -lt 0) { throw 'Could not isolate direct fallback blocking.' }
$blockBody = $source.Substring($blockStart, $blockEnd - $blockStart)
Assert-Match -Text $blockBody -Pattern 'navmesh returned no verified walkable path' -Message 'A failed long mesh query must block direct steering in every zone.'
Assert-Match -Text $blockBody -Pattern 'No verified walkable route to %s from here' -Message 'Unsafe route failure should be stated without claiming the destination is globally unreachable.'

Write-Host "nav mesh endpoint approach tests passed (exact=$exactCount approach=$approachCount)"
