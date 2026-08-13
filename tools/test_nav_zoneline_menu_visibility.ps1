$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$destinationsPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv'
$sourcePointsPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-points.tsv'
$livePointsPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-points.tsv'
$graphPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-zoneline-graph.tsv'
$liveGraphPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv'
$routeOverridesPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$navProbePath = 'C:\Users\buu42\AccessXI\tools\navprobe\bin\Release\net8.0\win-x86\publish\navprobe.exe'
$westRonfaureMeshPath = 'C:\Users\buu42\AccessXI\third_party\xiNavmeshes\West_Ronfaure.nav'
$southernSanDoriaMeshPath = 'C:\Users\buu42\AccessXI\third_party\xiNavmeshes\Southern_San_dOria.nav'
$portSanDoriaMeshPath = 'C:\Users\buu42\AccessXI\third_party\xiNavmeshes\Port_San_dOria.nav'

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

function Get-NavProbeWaypointCount {
    param(
        [string]$MeshPath,
        [string[]]$Coordinates
    )

    $output = & $navProbePath $MeshPath @Coordinates
    if ($LASTEXITCODE -ne 0) {
        throw "navprobe failed for $MeshPath $($Coordinates -join ' ')"
    }
    $line = $output | Where-Object { $_ -match '^waypoints\t\d+$' } | Select-Object -First 1
    if ($null -eq $line -or $line -notmatch '^waypoints\t(\d+)$') {
        throw "navprobe did not report waypoint count for $MeshPath $($Coordinates -join ' ')"
    }
    return [int]$Matches[1]
}

function Get-NavProbeWaypoints {
    param(
        [string]$MeshPath,
        [string[]]$Coordinates
    )

    $output = & $navProbePath $MeshPath @Coordinates
    if ($LASTEXITCODE -ne 0) {
        throw "navprobe failed for $MeshPath $($Coordinates -join ' ')"
    }

    $points = @()
    foreach ($line in $output) {
        if ($line -match '^(\d+)\t(-?\d+(?:\.\d+)?)\t(-?\d+(?:\.\d+)?)\t(-?\d+(?:\.\d+)?)$') {
            $points += [pscustomobject]@{
                Index = [int]$Matches[1]
                X = [double]$Matches[2]
                Y = [double]$Matches[3]
                Z = [double]$Matches[4]
            }
        }
    }

    if ($points.Count -eq 0) {
        throw "navprobe did not report waypoints for $MeshPath $($Coordinates -join ' ')"
    }
    return $points
}

$source = Get-Content -LiteralPath $addonPath -Raw
$destinations = Get-Content -LiteralPath $destinationsPath -Raw
$sourcePoints = Get-Content -LiteralPath $sourcePointsPath -Raw
$livePoints = Get-Content -LiteralPath $livePointsPath -Raw
$graph = Get-Content -LiteralPath $graphPath -Raw
$liveGraph = Get-Content -LiteralPath $liveGraphPath -Raw
$routeOverrides = if (Test-Path -LiteralPath $routeOverridesPath) { Get-Content -LiteralPath $routeOverridesPath -Raw } else { '' }

Assert-Match `
    -Text $destinations `
    -Pattern "(?m)^100`tLa Theine Plateau zone line`t-560\.415`t-613\.176`t-10\.328`tarea`tlsb-zoneline-all`tuntested`tworld-zonelines-2026-06-20`r?$" `
    -Message 'Expected La Theine Plateau zone line destination in West Ronfaure.'

Assert-Match `
    -Text $graph `
    -Pattern "(?m)^\d+`t100`tWest Ronfaure`t[^\r\n]*`t102`tLa Theine Plateau`t" `
    -Message 'Expected zoneline graph edge from West Ronfaure to La Theine Plateau.'

Assert-Match `
    -Text $graph `
    -Pattern "(?m)^\d+`t102`tLa Theine Plateau`t[^\r\n]*`t100`tWest Ronfaure`t[^\r\n]*`t-559\.963`t-602\.479`t-7\.062`t" `
    -Message 'Expected reciprocal La Theine to West Ronfaure edge with West Ronfaure approach coordinate.'

Assert-Match `
    -Text $sourcePoints `
    -Pattern "(?m)^232`tNorthern San d'Oria zone line`t-108\.899`t-132\.949`t-8\.500`tarea`tlive-verified-axi-pos`tproven`tport-to-northern-2026-06-28`r?$" `
    -Message 'Expected source nav points to contain the proven Port San d''Oria to Northern San d''Oria zone line.'

Assert-Match `
    -Text $livePoints `
    -Pattern "(?m)^232`tNorthern San d'Oria zone line`t-108\.899`t-132\.949`t-8\.500`tarea`tlive-verified-axi-pos`tproven`tport-to-northern-2026-06-28`r?$" `
    -Message 'Expected live addon nav points to contain the proven Port San d''Oria to Northern San d''Oria zone line.'

Assert-Match `
    -Text $graph `
    -Pattern "(?m)^812070522`t232`tPort San d'Oria`tz6g0`t-108\.899`t-132\.949`t-8\.500`t231`tNorthern San d'Oria`tz6f7`t-125\.375`t268\.640`t11\.949`t" `
    -Message 'Expected source zoneline graph to use the proven Port San d''Oria to Northern San d''Oria trigger coordinate.'

Assert-Match `
    -Text $liveGraph `
    -Pattern "(?m)^812070522`t232`tPort San d'Oria`tz6g0`t-108\.899`t-132\.949`t-8\.500`t231`tNorthern San d'Oria`tz6f7`t-125\.375`t268\.640`t11\.949`t" `
    -Message 'Expected live zoneline graph to use the proven Port San d''Oria to Northern San d''Oria trigger coordinate.'

Assert-NotMatch `
    -Text $graph `
    -Pattern "(?m)^\d+`t101`tEast Ronfaure`t[^\r\n]*`t102`tLa Theine Plateau`t" `
    -Message 'East Ronfaure should not be treated as a direct La Theine Plateau connection.'

$exactEndpointWaypoints = Get-NavProbeWaypointCount `
    -MeshPath $westRonfaureMeshPath `
    -Coordinates @('-24.427', '-49.814', '137.750', '-560.415', '-10.328', '-613.176')
if ($exactEndpointWaypoints -ne 1) {
    throw 'Expected current La Theine zoneline endpoint to reproduce one-point mesh route.'
}

$approachWaypoints = Get-NavProbeWaypointCount `
    -MeshPath $westRonfaureMeshPath `
    -Coordinates @('-24.427', '-49.814', '137.750', '-559.963', '-7.062', '-602.479')
if ($approachWaypoints -le 1) {
    throw 'Expected reciprocal West Ronfaure approach coordinate to produce a real mesh route.'
}

$southernEntranceRoute = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('-8.705', '0.000', '37.443', '0.620', '-2.049', '54.388')
if ($southernEntranceRoute.Count -lt 3) {
    throw 'Expected Southern San d''Oria wall-side start to require an intermediate mesh waypoint.'
}
$southernEntranceEscape = $southernEntranceRoute[1]
if ([math]::Abs($southernEntranceEscape.X - -8.124) -gt 0.75 -or [math]::Abs($southernEntranceEscape.Z - 31.506) -gt 0.75) {
    throw 'Expected Southern San d''Oria wall-side route to back out through the lower walkway before the zone trigger.'
}

$southernClearFirst = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('-6.000', '-1.043', '32.000', '-5.000', '-1.329', '34.000')
if ($southernClearFirst.Count -ne 2) {
    throw 'Expected Southern San d''Oria clear-corridor first segment to stay direct on the navmesh.'
}

$southernClearSecond = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('-5.000', '-1.329', '34.000', '-4.000', '-1.609', '36.000')
if ($southernClearSecond.Count -ne 2) {
    throw 'Expected Southern San d''Oria clear-corridor second segment to stay direct on the navmesh.'
}

$southernClearThird = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('-4.000', '-1.609', '36.000', '-3.000', '-1.868', '39.000')
if ($southernClearThird.Count -ne 2) {
    throw 'Expected Southern San d''Oria clear-corridor third segment to stay direct on the navmesh.'
}

$southernClearFourth = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('-3.000', '-1.868', '39.000', '-2.000', '-2.332', '42.000')
if ($southernClearFourth.Count -ne 2) {
    throw 'Expected Southern San d''Oria clear-corridor fourth segment to stay direct on the navmesh.'
}

$southernClearFifth = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('-2.000', '-2.332', '42.000', '0.000', '-2.351', '48.000')
if ($southernClearFifth.Count -ne 2) {
    throw 'Expected Southern San d''Oria clear-corridor fifth segment to stay direct on the navmesh.'
}

$southernClearFinal = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('0.000', '-2.351', '48.000', '0.620', '-2.049', '54.388')
if ($southernClearFinal.Count -ne 2) {
    throw 'Expected Southern San d''Oria clear-corridor final segment to stay direct to the zone line.'
}

$portNorthernProvenRoute = Get-NavProbeWaypoints `
    -MeshPath $portSanDoriaMeshPath `
    -Coordinates @('-93.308', '-8.000', '-119.577', '-108.899', '-8.500', '-132.949')
if ($portNorthernProvenRoute.Count -ne 2) {
    throw 'Expected proven Port San d''Oria to Northern San d''Oria trigger coordinate to stay direct from the nearby approach.'
}

$southernRightWallEscape = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('21.502', '0.000', '36.738', '24.000', '-0.372', '28.000')
if ($southernRightWallEscape.Count -ne 2) {
    throw 'Expected Southern San d''Oria backed-up right-wall position to pull into the open X24 Z28 plaza waypoint.'
}

$southernRightWallWideTurnA = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('24.000', '-0.372', '28.000', '24.000', '-0.256', '24.000')
if ($southernRightWallWideTurnA.Count -ne 2) {
    throw 'Expected Southern San d''Oria right-wall route to step farther out into the plaza before crossing.'
}

$southernRightWallWideTurnB = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('24.000', '-0.256', '24.000', '16.000', '-0.255', '24.000')
if ($southernRightWallWideTurnB.Count -ne 2) {
    throw 'Expected Southern San d''Oria right-wall route to cross the plaza in smaller segments.'
}

$southernRightWallWideTurnC = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('16.000', '-0.255', '24.000', '8.000', '-0.400', '24.000')
if ($southernRightWallWideTurnC.Count -ne 2) {
    throw 'Expected Southern San d''Oria right-wall route to continue its smaller plaza crossing.'
}

$southernRightWallWideTurnD = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('8.000', '-0.400', '24.000', '0.000', '-0.469', '28.000')
if ($southernRightWallWideTurnD.Count -ne 2) {
    throw 'Expected Southern San d''Oria right-wall route to curve back toward the gate from the open plaza.'
}

$southernRightWallWideTurnE = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('0.000', '-0.469', '28.000', '0.000', '-2.218', '40.000')
if ($southernRightWallWideTurnE.Count -ne 2) {
    throw 'Expected Southern San d''Oria right-wall route to return to the center gate approach.'
}

$southernRightWallCurrentStuckEscape = Get-NavProbeWaypoints `
    -MeshPath $southernSanDoriaMeshPath `
    -Coordinates @('14.528', '0.000', '29.767', '16.000', '-0.255', '24.000')
if ($southernRightWallCurrentStuckEscape.Count -ne 2) {
    throw 'Expected the latest stuck point to escape directly back out to the plaza route.'
}

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t" `
    -Message 'Expected a specific right-wall route override for Southern San d''Oria to Northern San d''Oria.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t1`t24\.000`t28\.000`t-0\.372`t" `
    -Message 'Expected the right-wall override to first pull into the open plaza at X24 Z28.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t2`t24\.000`t24\.000`t-0\.256`t" `
    -Message 'Expected the right-wall override to step farther out into the plaza at X24 Z24.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t3`t16\.000`t24\.000`t-0\.255`t" `
    -Message 'Expected the right-wall override to use smaller X16 Z24 crossing step.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t4`t8\.000`t24\.000`t-0\.400`t" `
    -Message 'Expected the right-wall override to use smaller X8 Z24 crossing step.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t5`t0\.000`t28\.000`t-0\.469`t" `
    -Message 'Expected the right-wall override to curve back to the gate through X0 Z28.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t7`t0\.000`t48\.000`t-2\.351`t" `
    -Message 'Expected the right-wall override to approach the zone line from the center gate corridor.'

Assert-NotMatch `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-rightwall-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t[0-9]+`t4\.000`t32\.000`t" `
    -Message 'The right-wall override should no longer use the long diagonal toward X4 Z32 from the latest stuck screenshot.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function accessxi\.nav_route_override_start_index\(player,\s*points\).*?nav_wall_distance\(player\).*?<=\s*1\.2.*?return\s+1" `
    -Message 'Route override sync should not skip ahead while the player is already scraping a wall.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t" `
    -Message 'Expected a data-driven route override for Southern San d''Oria to Northern San d''Oria.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t1`t-8\.124`t31\.506`t-1\.000`t" `
    -Message 'Expected the Southern San d''Oria override to start with the lower walkway escape point from the live wall-side navmesh route.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t2`t-6\.000`t32\.000`t-1\.043`t" `
    -Message 'Expected the Southern San d''Oria override to keep the short clear point after the lower walkway escape.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t5`t-3\.000`t39\.000`t-1\.868`t" `
    -Message 'Expected the Southern San d''Oria override to keep smaller center-corridor hops.'

Assert-Match `
    -Text $routeOverrides `
    -Pattern "(?m)^southern-sandoria-to-northern-zoneline`t230`tNorthern San d'Oria zone line`t0\.620`t54\.388`t-2\.049`t[^\r\n]*`t7`t0\.000`t48\.000`t-2\.351`t" `
    -Message 'Expected the Southern San d''Oria override to approach the zone line through the center corridor.'

$buildStart = $source.IndexOf('local function nav_build_menu_items')
$buildEnd = $source.IndexOf('local function nav_menu_item_speech', $buildStart)
if ($buildStart -lt 0 -or $buildEnd -lt 0) {
    throw 'Could not locate nav_build_menu_items block.'
}

$buildBody = $source.Substring($buildStart, $buildEnd - $buildStart)
if ($buildBody -match "effective_kind\s*~=\s*'area'\s*or\s*accessxi\.nav_area_point_reachable\(player,\s*point\)") {
    throw 'Area zone lines must not be hidden from the nav menu by route reachability filtering.'
}

Assert-Match `
    -Text $source `
    -Pattern "nav_zoneline_graph_path\s*=\s*accessxi_paths\.addon_path\('data',\s*'ffxi-nav-zoneline-graph\.tsv'\)" `
    -Message 'Expected addon to load the reciprocal zoneline graph from the live addon data folder.'

Assert-Match `
    -Text $source `
    -Pattern "nav_route_overrides_path\s*=\s*accessxi_paths\.addon_path\('data',\s*'ffxi-nav-route-overrides\.tsv'\)" `
    -Message 'Expected addon to load route overrides from the live addon data folder.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_zoneline_approach_candidates\(point\)" `
    -Message 'Expected reciprocal zoneline approach candidate helper.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_compute_route_with_zoneline_approach\(player,\s*point\)" `
    -Message 'Expected route helper that can use reciprocal zoneline approach coordinates.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_override_points\(player,\s*point\)" `
    -Message 'Expected route override helper for proven corner repairs.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_points_are_override\(points\)" `
    -Message 'Expected helper that detects active route override corridors.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_nearby_zoneline_direct_route_allowed\(player,\s*point\)" `
    -Message 'Expected nearby zone-line direct route helper.'

$directHelperStart = $source.IndexOf('function accessxi.nav_nearby_zoneline_direct_route_allowed')
$directHelperEnd = $source.IndexOf('function accessxi.nav_zoneline_approach_candidates', $directHelperStart)
if ($directHelperStart -lt 0 -or $directHelperEnd -lt 0) {
    throw 'Could not locate nav_nearby_zoneline_direct_route_allowed block.'
}
$directHelperBody = $source.Substring($directHelperStart, $directHelperEnd - $directHelperStart)
Assert-Match `
    -Text $directHelperBody `
    -Pattern "nav_wall_distance\(player\)[\s\S]*?wall\s*<=\s*1\.2[\s\S]*?return\s+false" `
    -Message 'Nearby zone-line direct routing must not fire while the player is scraping a wall.'

$routeHelperStart = $source.IndexOf('function accessxi.nav_compute_route_with_zoneline_approach')
$routeHelperEnd = $source.IndexOf('accessxi.nav_generated_name_is_placeholder', $routeHelperStart)
if ($routeHelperStart -lt 0 -or $routeHelperEnd -lt 0) {
    throw 'Could not locate nav_compute_route_with_zoneline_approach block.'
}
$routeHelperBody = $source.Substring($routeHelperStart, $routeHelperEnd - $routeHelperStart)
$overrideRouteIndex = $routeHelperBody.IndexOf('accessxi.nav_route_override_points(player, point)')
$directRouteIndex = $routeHelperBody.IndexOf('accessxi.nav_nearby_zoneline_direct_route_allowed(player, point)')
$meshRouteIndex = $routeHelperBody.IndexOf('nav_compute_mesh_route(player, point)')
if ($overrideRouteIndex -lt 0 -or $directRouteIndex -lt 0 -or $overrideRouteIndex -gt $directRouteIndex) {
    throw 'Proven route overrides should run before nearby direct zone-line guidance.'
}
if ($directRouteIndex -lt 0 -or $meshRouteIndex -lt 0 -or $directRouteIndex -gt $meshRouteIndex) {
    throw 'Nearby clear zone lines should use direct guidance before mesh routing can pick wall-edge waypoints.'
}
Assert-Match `
    -Text $routeHelperBody `
    -Pattern "accessxi\.nav_route_override_points\(player,\s*point\)[\s\S]*?return\s+override_route,\s*nil" `
    -Message 'Route helper should return proven override corridors before mesh routing.'
Assert-Match `
    -Text $routeHelperBody `
    -Pattern "accessxi\.nav_nearby_zoneline_direct_route_allowed\(player,\s*point\)[\s\S]*?return\s+T\{\}" `
    -Message 'Nearby clear zone-line direct guidance should return an empty mesh route.'

$overrideStartIndexStart = $source.IndexOf('function accessxi.nav_route_override_start_index')
$overrideStartIndexEnd = $source.IndexOf('function accessxi.nav_route_override_points', $overrideStartIndexStart)
if ($overrideStartIndexStart -lt 0 -or $overrideStartIndexEnd -lt 0) {
    throw 'Could not locate nav_route_override_start_index block.'
}
$overrideStartIndexBody = $source.Substring($overrideStartIndexStart, $overrideStartIndexEnd - $overrideStartIndexStart)
Assert-Match `
    -Text $overrideStartIndexBody `
    -Pattern "best_t\s*<=\s*0\.15[\s\S]*?nav_distance\(player,\s*points\[best_segment\]\)[\s\S]*?return\s+best_segment" `
    -Message 'Override routing must not skip the first off-wall waypoint when the player is beside, but not at, that waypoint.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_waypoint_arrival_radius\(destination\)" `
    -Message 'Expected route waypoint arrival radius helper.'

$waypointRadiusStart = $source.IndexOf('function accessxi.nav_route_waypoint_arrival_radius')
$waypointRadiusEnd = $source.IndexOf('function accessxi.nav_first_route_index', $waypointRadiusStart)
if ($waypointRadiusStart -lt 0 -or $waypointRadiusEnd -lt 0) {
    throw 'Could not locate nav_route_waypoint_arrival_radius block.'
}
$waypointRadiusBody = $source.Substring($waypointRadiusStart, $waypointRadiusEnd - $waypointRadiusStart)
Assert-Match `
    -Text $waypointRadiusBody `
    -Pattern "name:contains\('zone line'\)[\s\S]*?return\s+2" `
    -Message 'Zone-line mesh waypoints need a tight arrival radius so wall escape waypoints are not skipped.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_first_route_index\(from_pos,\s*points,\s*destination\)[\s\S]*?nav_route_waypoint_arrival_radius\(destination\)" `
    -Message 'First route index should use the destination-specific waypoint radius.'

$syncRouteStart = $source.IndexOf('function accessxi.nav_sync_route_index')
$syncRouteEnd = $source.IndexOf('local function nav_route_phrase', $syncRouteStart)
if ($syncRouteStart -lt 0 -or $syncRouteEnd -lt 0) {
    throw 'Could not locate nav_sync_route_index block.'
}
$syncRouteBody = $source.Substring($syncRouteStart, $syncRouteEnd - $syncRouteStart)
Assert-Match `
    -Text $syncRouteBody `
    -Pattern "nav_nearest_route_segment\(\s*pos,\s*accessxi\.nav_route_points(?:,\s*first_segment,\s*last_segment)?\)[\s\S]*?nav_route_points_are_override\(accessxi\.nav_route_points\)[\s\S]*?segment_distance[\s\S]*?>\s*3\.0[\s\S]*?return" `
    -Message 'Override route index sync must not jump ahead when the player is clearly off the tight corridor.'

$pollRouteStart = $source.IndexOf('local function poll_nav_route')
$pollRouteEnd = $source.IndexOf('local function load_step', $pollRouteStart)
if ($pollRouteStart -lt 0 -or $pollRouteEnd -lt 0) {
    throw 'Could not locate poll_nav_route block.'
}
$pollRouteBody = $source.Substring($pollRouteStart, $pollRouteEnd - $pollRouteStart)
Assert-Match `
    -Text $pollRouteBody `
    -Pattern "accessxi\.nav_route_points:len\(\)\s*>\s*1[\s\S]*?not\s+accessxi\.nav_route_points_are_override\(accessxi\.nav_route_points\)[\s\S]*?accessxi\.nav_nearby_zoneline_direct_route_allowed\(player,\s*destination\)[\s\S]*?accessxi\.nav_route_points:clear\(\)[\s\S]*?accessxi\.nav_route_point_index\s*=\s*1" `
    -Message 'Route polling should clear stale mesh waypoints for direct guidance, but preserve active override corridors.'

Assert-Match `
    -Text $pollRouteBody `
    -Pattern "real_waypoint_distance\s*<=\s*accessxi\.nav_route_waypoint_arrival_radius\(destination\)" `
    -Message 'Route polling should use the tight zone-line waypoint radius before advancing.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function accessxi\.nav_area_point_direct_route_allowed\(player,\s*point\).*?nav_distance\(player,\s*point\).*?<=\s*35" `
    -Message 'Direct zoneline fallback should only be allowed near the zoneline.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function accessxi\.nav_area_point_direct_route_allowed\(player,\s*point\).*?name:contains\('mog house'\).*?source:contains\('live-verified'\).*?confidence:contains\('proven'\).*?nav_distance\(player,\s*point\).*?<=\s*35" `
    -Message 'Nearby proven Mog House entrances should be allowed as direct area routes when mesh reachability fails.'

$arrivalStart = $source.IndexOf('function accessxi.nav_arrival_radius')
$arrivalEnd = $source.IndexOf('function accessxi.nav_route_lookahead_distance', $arrivalStart)
if ($arrivalStart -lt 0 -or $arrivalEnd -lt 0) {
    throw 'Could not locate nav_arrival_radius block.'
}
$arrivalBody = $source.Substring($arrivalStart, $arrivalEnd - $arrivalStart)

Assert-Match `
    -Text $arrivalBody `
    -Pattern "name:contains\('mog house'\)[\s\S]*?return\s+2" `
    -Message 'Mog House entrances must use a tight arrival radius so nav does not stop before the door trigger.'

$menuStart = $source.IndexOf('local function nav_menu_start_route')
$routeStart = $source.IndexOf('local function nav_route_start', $menuStart)
$routeStop = $source.IndexOf('nav_route_stop = function', $routeStart)
if ($menuStart -lt 0 -or $routeStart -lt 0 -or $routeStop -lt 0) {
    throw 'Could not locate nav route start blocks.'
}

$menuStartBody = $source.Substring($menuStart, $routeStart - $menuStart)
$routeStartBody = $source.Substring($routeStart, $routeStop - $routeStart)
$startHelperStart = $source.IndexOf('function accessxi.nav_start_route_to_point')
$startHelperEnd = $source.IndexOf('function accessxi.nav_find_zone_search_npc', $startHelperStart)
if ($startHelperStart -lt 0 -or $startHelperEnd -lt 0) {
    throw 'Could not locate shared nav route start helper.'
}
$startHelperBody = $source.Substring($startHelperStart, $startHelperEnd - $startHelperStart)

if ($menuStartBody -match "accessxi\.nav_route_points\s*=\s*nav_compute_mesh_route\(player,\s*item\)") {
    throw 'Menu route start should use zoneline approach-aware route computation.'
}
if ($menuStartBody -match "accessxi\.nav_point_effective_kind\(item\)\s*==\s*'area'\s*and\s*not\s*accessxi\.nav_area_point_reachable\(player,\s*item\)") {
    throw 'Menu route start must not reject same-zone zone lines solely because mesh reachability failed.'
}
if ($startHelperBody -match "accessxi\.nav_route_points\s*=\s*nav_compute_mesh_route\(player,\s*point\)") {
    throw 'Command route start should use zoneline approach-aware route computation.'
}
if ($startHelperBody -match "accessxi\.nav_point_effective_kind\(point\)\s*==\s*'area'\s*and\s*not\s*accessxi\.nav_area_point_reachable\(player,\s*point\)") {
    throw 'Command route start must not reject same-zone zone lines solely because mesh reachability failed.'
}

Assert-Match `
    -Text $menuStartBody `
    -Pattern "accessxi\.nav_compute_route_with_zoneline_approach\(player,\s*item\)" `
    -Message 'Menu route start should compute route with reciprocal zoneline approach support.'

Assert-Match `
    -Text $startHelperBody `
    -Pattern "accessxi\.nav_compute_route_with_zoneline_approach\(player,\s*point\)" `
    -Message 'Command route start should compute route with reciprocal zoneline approach support.'

Assert-Match `
    -Text $routeStartBody `
    -Pattern "accessxi\.nav_start_route_to_point\(point,\s*'command'\)" `
    -Message 'Command route start should call the shared zoneline-aware route helper.'

Assert-Match `
    -Text $menuStartBody `
    -Pattern "accessxi\.nav_beacon_enabled[\s\S]*?Starting route to %s\. %d waypoints\. Beacon active" `
    -Message 'Menu route start should avoid spoken next-step directions when beacon audio is active.'

Assert-Match `
    -Text $startHelperBody `
    -Pattern "accessxi\.nav_beacon_enabled[\s\S]*?Starting route to %s\. %d waypoints\. Beacon active" `
    -Message 'Command route start should avoid spoken next-step directions when beacon audio is active.'

Write-Host 'nav zoneline menu visibility checks ok'
