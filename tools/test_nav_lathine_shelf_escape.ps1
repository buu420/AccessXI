$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$sourceOverridesPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv'
$liveOverridesPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$navProbePath = 'C:\Users\buu42\AccessXI\tools\navprobe\bin\Release\net8.0\win-x86\publish\navprobe.exe'
$laTheineMeshPath = 'C:\Users\buu42\AccessXI\third_party\xiNavmeshes\La_Theine_Plateau.nav'

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NoMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

function Assert-NavProbeWaypointCount {
    param(
        [string[]]$Coordinates,
        [int]$MaxCount,
        [string]$Message
    )

    $output = & $navProbePath $laTheineMeshPath @Coordinates
    if ($LASTEXITCODE -ne 0) {
        throw "navprobe failed for La Theine Plateau $($Coordinates -join ' ')"
    }
    $line = $output | Where-Object { $_ -match '^waypoints\t\d+$' } | Select-Object -First 1
    if ($null -eq $line -or $line -notmatch '^waypoints\t(\d+)$') {
        throw "navprobe did not report waypoint count for $($Coordinates -join ' ')"
    }
    if ([int]$Matches[1] -gt $MaxCount) {
        throw $Message
    }
}

function Assert-LaTheineShelfOverrides {
    param(
        [string]$Text,
        [string]$Label
    )

    foreach ($routeId in @(
        'lathine-shelf-to-west-ronfaure-zoneline',
        'lathine-shelf-to-planar-rift',
        'lathine-shelf-to-survival-guide',
        'lathine-shelf-to-jugner-zoneline'
    )) {
        Assert-Match `
            -Text $Text `
            -Pattern "(?m)^$routeId`t102`t" `
            -Message "Expected $Label route override $routeId."
    }

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label westward shelf recovery to first pull east into open ground."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t2`t-560\.000`t460\.000`t8\.000`t" `
        -Message "Expected $Label westward shelf recovery to continue through the open shelf corridor."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t3`t-560\.000`t500\.000`t2\.000`t" `
        -Message "Expected $Label westward shelf recovery to reach the lower open route before turning west."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t[0-9]+`t-621\." `
        -Message "Expected $Label westward shelf recovery to avoid the old cliff-edge -621 route points."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-planar-rift`t102`tPlanar Rift`t-440\.000`t440\.000`t-8\.000`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label Planar Rift shelf recovery to first pull east into open ground."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-survival-guide`t102`tSurvival Guide`t775\.000`t-18\.000`t28\.500`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label Survival Guide recovery to first pull east into open ground."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-survival-guide`t102`tSurvival Guide`t775\.000`t-18\.000`t28\.500`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t4`t-540\.800`t500\.000`t-4\.650`t" `
        -Message "Expected $Label Survival Guide recovery to rejoin the lower western route before crossing La Theine."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-jugner-zoneline`t102`tJugner Forest zone line`t801\.831`t-37\.618`t24\.326`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label Jugner recovery to first pull east into open ground."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-jugner-zoneline`t102`tJugner Forest zone line`t801\.831`t-37\.618`t24\.326`t4\.0`t-705\.000`t-550\.000`t320\.000`t520\.000`t4`t-540\.800`t500\.000`t-4\.650`t" `
        -Message "Expected $Label Jugner recovery to rejoin the lower western route before crossing La Theine."
}

$sourceOverrides = Get-Content -LiteralPath $sourceOverridesPath -Raw
$liveOverrides = Get-Content -LiteralPath $liveOverridesPath -Raw
$source = Get-Content -LiteralPath $addonPath -Raw

Assert-LaTheineShelfOverrides -Text $sourceOverrides -Label 'source'
Assert-LaTheineShelfOverrides -Text $liveOverrides -Label 'live'

Assert-NavProbeWaypointCount `
    -Coordinates @('-596.859', '16.048', '387.850', '-570.000', '12.000', '420.000') `
    -MaxCount 2 `
    -Message 'Expected the screenshot shelf pocket to have a direct pull-away segment to the open eastern shelf.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-679.628', '15.975', '482.464', '-570.000', '12.000', '420.000') `
    -MaxCount 2 `
    -Message 'Expected the widened cliff pocket to have a direct recovery segment back to the open eastern shelf.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-560.000', '2.000', '500.000', '-584.400', '-4.450', '545.600') `
    -MaxCount 2 `
    -Message 'Expected the lower western route to resume cleanly after the shelf recovery point.'

$commandStart = $source.IndexOf("elseif (#args >= 2 and args[2]:any('nav', 'navigation', 'dest'))")
$commandEnd = $source.IndexOf("elseif (#args >= 2 and args[2]:any('beacon', 'navbeacon'))", $commandStart)
if ($commandStart -lt 0 -or $commandEnd -lt 0) {
    throw 'Could not locate nav command block.'
}
$navCommandBody = $source.Substring($commandStart, $commandEnd - $commandStart)

Assert-Match `
    -Text $navCommandBody `
    -Pattern "args\[3\]:any\('reload', 'refresh'\)[\s\S]*?nav_route_overrides_loaded\s*=\s*false[\s\S]*?nav_route_overrides:clear\(\)" `
    -Message 'Expected /axi nav reload to refresh route overrides as well as points and zone graph data.'

Write-Host 'nav La Theine shelf escape checks passed'
