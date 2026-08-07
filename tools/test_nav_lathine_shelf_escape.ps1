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

function Assert-NavProbePathContains {
    param(
        [string[]]$Coordinates,
        [string]$Pattern,
        [string]$Message
    )

    $output = & $navProbePath $laTheineMeshPath @Coordinates
    if ($LASTEXITCODE -ne 0) {
        throw "navprobe failed for La Theine Plateau $($Coordinates -join ' ')"
    }
    $text = $output -join "`n"
    if ($text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-LaTheineShelfOverrides {
    param(
        [string]$Text,
        [string]$Label
    )

    foreach ($routeId in @(
        'lathine-fallen-pocket-to-west-ronfaure-zoneline',
        'lathine-wall-pocket-to-west-ronfaure-zoneline',
        'lathine-lower-pocket-to-west-ronfaure-zoneline',
        'lathine-mid-pocket-to-west-ronfaure-zoneline',
        'lathine-exit-pocket-to-west-ronfaure-zoneline',
        'lathine-upper-west-pocket-to-west-ronfaure-zoneline',
        'lathine-lower-corridor-to-west-ronfaure-zoneline',
        'lathine-ravine-to-west-ronfaure-zoneline',
        'lathine-recorded-corridor-20260712-west-via-ravine-01',
        'lathine-shelf-to-planar-rift',
        'lathine-shelf-to-survival-guide',
        'lathine-shelf-to-jugner-zoneline',
        'lathine-shelf-to-huge-wasp-west-camp',
        'lathine-corridor-shoulder-to-west-ronfaure-zoneline'
    )) {
        Assert-Match `
            -Text $Text `
            -Pattern "(?m)^$routeId`t102`t" `
            -Message "Expected $Label route override $routeId."
    }

    $fallenIndex = $Text.IndexOf("lathine-fallen-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $shoulderIndex = $Text.IndexOf("lathine-corridor-shoulder-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $lowerIndex = $Text.IndexOf("lathine-lower-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $wallIndex = $Text.IndexOf("lathine-wall-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $midIndex = $Text.IndexOf("lathine-mid-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $exitIndex = $Text.IndexOf("lathine-exit-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $upperIndex = $Text.IndexOf("lathine-upper-west-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $corridorIndex = $Text.IndexOf("lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    $ravineIndex = $Text.IndexOf("lathine-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line")
    if ($shoulderIndex -lt 0 -or $fallenIndex -lt 0 -or $wallIndex -lt 0 -or $lowerIndex -lt 0 -or $midIndex -lt 0 -or $exitIndex -lt 0 -or $upperIndex -lt 0 -or $corridorIndex -lt 0 -or $ravineIndex -lt 0) {
        throw "Expected $Label staged La Theine pocket overrides, lower-corridor override, and the walked fallen-pocket escape to exist."
    }
    if (($shoulderIndex -gt $fallenIndex) -or ($fallenIndex -gt $wallIndex) -or ($wallIndex -gt $lowerIndex) -or ($lowerIndex -gt $midIndex) -or ($midIndex -gt $upperIndex) -or ($upperIndex -gt $corridorIndex) -or ($corridorIndex -gt $exitIndex) -or ($exitIndex -gt $ravineIndex)) {
        throw "Expected $Label corridor shoulder escape, walked fallen-pocket escape, staged pocket overrides, and lower-corridor override to appear before wider recovery routes because first matching override wins."
    }

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t" `
        -Message "Expected $Label broad shelf-to-West Ronfaure override to be removed because it kept cutting the lower corridor into the wall."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-corridor-shoulder-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-655\.000`t-625\.000`t420\.000`t455\.000`t1`t-635\.726`t421\.025`t16\.907`t" `
        -Message "Expected $Label corridor-shoulder recovery to catch the live x=-639,z=439 loop start before navmesh can pull it into the west pocket."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-corridor-shoulder-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-655\.000`t-625\.000`t420\.000`t455\.000`t2`t-630\.011`t415\.070`t16\.500`t" `
        -Message "Expected $Label corridor-shoulder recovery to continue toward the walked lower-corridor branch instead of looping through the fallen pocket."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-corridor-shoulder-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-655\.000`t-625\.000`t420\.000`t455\.000`t3`t-624\.777`t409\.617`t16\.500`t" `
        -Message "Expected $Label corridor-shoulder recovery to join the lower-corridor branch before the west passage."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-corridor-shoulder-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-669\.600`t463\.200`t" `
        -Message "Expected $Label corridor-shoulder recovery not to use the navmesh target that pulled the live start into a circle."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-corridor-shoulder-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-674\.828`t466\.164`t" `
        -Message "Expected $Label corridor-shoulder recovery not to walk back into the fallen pocket loop."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-690\.000`t-640\.000`t450\.000`t500\.000`t1`t-674\.828`t466\.164`t16\.450`t" `
        -Message "Expected $Label fallen-pocket recovery to begin with the recorded reload position from the walked route."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-(fallen|wall|lower|mid|upper-west)-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-672\.342`t484\.567`t10\.098`t" `
        -Message "Expected $Label pocket recoveries to avoid the live-disproved -672.342,484.567 descent that repeatedly pinned the character against the wall."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-(fallen|wall|lower|mid|upper-west)-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-592\.951`t392\.547`t13\.765`t" `
        -Message "Expected $Label pocket recoveries to avoid the live-disproved -592.951,392.547 lower descent that circled against the shelf wall."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-690\.000`t-640\.000`t450\.000`t500\.000`t2`t-672\.401`t463\.070`t16\.521`t" `
        -Message "Expected $Label fallen-pocket recovery to back out along the walked corridor instead of turning into the failed lower-pocket descent."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-690\.000`t-640\.000`t450\.000`t500\.000`t11`t-624\.777`t409\.617`t16\.500`t" `
        -Message "Expected $Label fallen-pocket recovery to branch from the walked corridor before the live-failed lower descent."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-690\.000`t-640\.000`t450\.000`t500\.000`t12`t-621\.600`t460\.800`t3\.950`t" `
        -Message "Expected $Label fallen-pocket recovery to take the west passage around the wall from the walked corridor."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-690\.000`t-640\.000`t450\.000`t500\.000`t[0-9]+`t-605\.825`t376\.274`t16\.241`t" `
        -Message "Expected $Label fallen-pocket recovery to avoid the -605,376 lower descent that forced the later wall cut."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-690\.000`t-640\.000`t450\.000`t500\.000`t[0-9]+`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label fallen-pocket recovery not to use the -570,420 shelf shortcut that the live client drove into a wall."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-(fallen|wall|lower|mid|upper-west)-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-560\.000`t460\.000`t8\.000`t" `
        -Message "Expected $Label pocket recoveries not to use the live-failed -560,460 diagonal from the lower-corridor wall."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-wall-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-685\.000`t-660\.000`t450\.000`t470\.000`t1`t-669\.600`t463\.200`t15\.750`t" `
        -Message "Expected $Label wall-pocket recovery to start with the live stuck screenshot escape step."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-wall-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-685\.000`t-660\.000`t450\.000`t470\.000`t2`t-672\.401`t463\.070`t16\.521`t" `
        -Message "Expected $Label wall-pocket recovery to join the backtrack corridor instead of the failed lower-pocket descent."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-660\.000`t470\.000`t490\.000`t1`t-675\.588`t479\.784`t15\.290`t" `
        -Message "Expected $Label lower-pocket recovery to begin with the live navmesh escape step instead of the broad shelf shortcut."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-660\.000`t470\.000`t490\.000`t2`t-674\.828`t466\.164`t16\.450`t" `
        -Message "Expected $Label lower-pocket recovery to retreat to the walked pocket point instead of dropping into the bad descent."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-660\.000`t470\.000`t490\.000`t12`t-624\.777`t409\.617`t16\.500`t" `
        -Message "Expected $Label lower-pocket recovery to branch from the walked corridor before the live-failed lower descent."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-mid-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-685\.000`t-670\.000`t490\.000`t505\.000`t1`t-677\.200`t490\.400`t15\.950`t" `
        -Message "Expected $Label mid-pocket recovery to step back around the wall lip before aiming at the lower corridor."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-mid-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-685\.000`t-670\.000`t490\.000`t505\.000`t2`t-677\.200`t486\.000`t14\.950`t" `
        -Message "Expected $Label mid-pocket recovery to use the second small wall-lip step from navprobe."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-exit-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-670\.000`t-650\.000`t490\.000`t520\.000`t1`t-660\.000`t526\.000`t6\.150`t" `
        -Message "Expected $Label exit-pocket recovery to head out through the lower exit instead of walking backward into the wall pocket."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-upper-west-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-705\.000`t-680\.000`t505\.000`t520\.000`t1`t-675\.588`t479\.784`t15\.290`t" `
        -Message "Expected $Label upper-west pocket recovery to catch the z=508 starting spot before the broad shelf route."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-(wall|lower|mid|exit|upper-west)-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t[^\r\n]+`t[0-9]+`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label staged pocket recoveries not to use the broad shelf shortcut that drove into the wall."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-(wall|lower|mid|exit|upper-west)-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t[^\r\n]+`t[0-9]+`t-592\.951`t392\.547`t13\.765`t" `
        -Message "Expected $Label staged pocket recoveries not to use the live-disproved -592.951,392.547 lower descent."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t1`t-605\.825`t376\.274`t16\.241`t" `
        -Message "Expected $Label lower-corridor recovery to first back out of the live wall impact point."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t6`t-624\.777`t409\.617`t16\.500`t" `
        -Message "Expected $Label lower-corridor recovery to return through the walked corridor before turning north."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t7`t-621\.600`t460\.800`t3\.950`t" `
        -Message "Expected $Label lower-corridor recovery to take the west passage around the wall."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t[0-9]+`t-560\.000`t460\.000`t8\.000`t" `
        -Message "Expected $Label lower-corridor recovery not to use the live-failed -560,460 diagonal."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t[0-9]+`t-675\.588`t479\.784`t15\.290`t" `
        -Message "Expected $Label lower-corridor recovery not to join the failed lower-pocket corridor."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t[0-9]+`t-674\.828`t466\.164`t16\.450`t" `
        -Message "Expected $Label lower-corridor recovery not to walk out to the west pocket before the failed descent."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t[0-9]+`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label lower-corridor recovery not to use the -570,420 shelf shortcut that stalled in live testing."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-lower-corridor-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-625\.000`t-585\.000`t350\.000`t420\.000`t[0-9]+`t-614\.961`t417\.745`t9\.587`t" `
        -Message "Expected $Label lower-corridor recovery not to use the native -614.961,417.745 wall leg that stalled in live testing."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-(planar-rift|survival-guide|jugner-zoneline|huge-wasp-west-camp)`t102`t[^\r\n]+`t320\.000`t520\.000`t" `
        -Message "Expected $Label broad shelf overrides not to catch the lower ledge around z=348 from the latest screenshot."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-720\.000`t-650\.000`t500\.000`t560\.000`t1`t-680\.000`t520\.000`t15\.644`t" `
        -Message "Expected $Label ravine recovery to first pull south-east to the live-probed open ledge instead of the wall strip."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-720\.000`t-650\.000`t500\.000`t560\.000`t2`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label ravine recovery to rejoin the known open shelf route instead of following the bad ravine mesh north."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-720\.000`t-650\.000`t500\.000`t560\.000`t6`t-584\.400`t545\.600`t-4\.450`t" `
        -Message "Expected $Label ravine recovery to rejoin the lower west route before the West Ronfaure approach."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-720\.000`t-650\.000`t500\.000`t560\.000`t[0-9]+`t-682\.800`t535\.600`t" `
        -Message "Expected $Label ravine recovery to avoid the wall-hugging -682.8,535.6 point that still stalled in live testing."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-720\.000`t-650\.000`t500\.000`t560\.000`t[0-9]+`t-697\.409`t535\.283`t" `
        -Message "Expected $Label ravine recovery to avoid the raw navmesh wall-edge waypoint from the screenshot."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-720\.000`t-650\.000`t500\.000`t560\.000`t[0-9]+`t-695\.188`t539\.151`t" `
        -Message "Expected $Label ravine recovery to avoid the second raw wall-edge waypoint from the screenshot."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-gully-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-455\.000`t-380\.000`t190\.000`t250\.000`t1`t-391\.600`t208\.000`t10\.950`t" `
        -Message "Expected $Label westward gully recovery to pull the current screenshot pocket back to the known central route."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-gully-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-455\.000`t-380\.000`t190\.000`t250\.000`t2`t-396\.000`t255\.600`t8\.750`t" `
        -Message "Expected $Label westward gully recovery to continue north on the observed central corridor instead of the bad cliff-facing mesh leg."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-gully-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-455\.000`t-380\.000`t190\.000`t250\.000`t10`t-478\.800`t454\.000`t-7\.450`t" `
        -Message "Expected $Label westward gully recovery to rejoin the lower cross-valley route before the west zone line approach."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-planar-rift`t102`tPlanar Rift`t-440\.000`t440\.000`t-8\.000`t4\.0`t-705\.000`t-550\.000`t380\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label Planar Rift shelf recovery to first pull east into open ground."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-survival-guide`t102`tSurvival Guide`t775\.000`t-18\.000`t28\.500`t4\.0`t-705\.000`t-550\.000`t380\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label Survival Guide recovery to first pull east into open ground."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-survival-guide`t102`tSurvival Guide`t775\.000`t-18\.000`t28\.500`t4\.0`t-705\.000`t-550\.000`t380\.000`t520\.000`t4`t-540\.800`t500\.000`t-4\.650`t" `
        -Message "Expected $Label Survival Guide recovery to rejoin the lower western route before crossing La Theine."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-jugner-zoneline`t102`tJugner Forest zone line`t801\.831`t-37\.618`t24\.326`t4\.0`t-705\.000`t-550\.000`t380\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label Jugner recovery to first pull east into open ground."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-jugner-zoneline`t102`tJugner Forest zone line`t801\.831`t-37\.618`t24\.326`t4\.0`t-705\.000`t-550\.000`t380\.000`t520\.000`t4`t-540\.800`t500\.000`t-4\.650`t" `
        -Message "Expected $Label Jugner recovery to rejoin the lower western route before crossing La Theine."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-huge-wasp-west-camp`t102`tHuge Wasp`t-771\.501`t443\.928`t16\.512`t4\.0`t-760\.000`t-550\.000`t380\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label west Huge Wasp camp route to first pull away from the wall pocket."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-huge-wasp-west-camp`t102`tHuge Wasp`t-771\.501`t443\.928`t16\.512`t4\.0`t-760\.000`t-550\.000`t380\.000`t520\.000`t2`t-680\.000`t440\.000`t17\.000`t" `
        -Message "Expected $Label west Huge Wasp camp route to re-enter the camp approach through the clear shelf."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-huge-wasp-west-camp`t102`tHuge Wasp`t-771\.501`t443\.928`t16\.512`t4\.0`t-760\.000`t-550\.000`t380\.000`t520\.000`t[0-9]+`t-807\.200`t476\.000`t16\.150`t" `
        -Message "Expected $Label west Huge Wasp camp route to follow the navmesh loop around the cliff instead of the wall-edge shortcut."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-huge-wasp-west-camp`t102`tHuge Wasp`t-771\.501`t443\.928`t16\.512`t4\.0`t-760\.000`t-550\.000`t380\.000`t520\.000`t[0-9]+`t-739\." `
        -Message "Expected $Label west Huge Wasp camp route to avoid the live stuck wall-edge waypoint near X -739."
}

function Assert-LaTheineShelfOverrides {
    param(
        [string]$Text,
        [string]$Label
    )

    foreach ($routeId in @(
        'lathine-fallen-ravine-to-west-ronfaure-zoneline',
        'lathine-open-shelf-via-f6-to-ordelle-z2u6',
        'lathine-exit-pocket-to-west-ronfaure-zoneline',
        'lathine-recorded-corridor-20260712-west-via-ravine-01',
        'lathine-current-shelf-pocket-to-west-ronfaure-zoneline',
        'lathine-shelf-to-planar-rift',
        'lathine-shelf-to-survival-guide',
        'lathine-shelf-to-jugner-zoneline',
        'lathine-shelf-to-huge-wasp-west-camp'
    )) {
        Assert-Match `
            -Text $Text `
            -Pattern "(?m)^$routeId`t102`t" `
            -Message "Expected $Label route override $routeId."
    }

    foreach ($routeId in @(
        'lathine-corridor-shoulder-to-west-ronfaure-zoneline',
        'lathine-fallen-pocket-to-west-ronfaure-zoneline',
        'lathine-wall-pocket-to-west-ronfaure-zoneline',
        'lathine-lower-pocket-to-west-ronfaure-zoneline',
        'lathine-mid-pocket-to-west-ronfaure-zoneline',
        'lathine-upper-west-pocket-to-west-ronfaure-zoneline',
        'lathine-lower-corridor-to-west-ronfaure-zoneline',
        'lathine-ravine-to-west-ronfaure-zoneline',
        'lathine-gully-to-west-ronfaure-zoneline'
    )) {
        Assert-NoMatch `
            -Text $Text `
            -Pattern "(?m)^$routeId`t102`tWest Ronfaure zone line`t" `
            -Message "Expected $Label poisoned route override $routeId to be removed after live collision evidence disproved it."
    }

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-[^\r\n]+west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-621\.600`t460\.800`t3\.950`t" `
        -Message "Expected $Label La Theine West Ronfaure routes not to contain the live-disproved -621.600,460.800 wall target."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-[^\r\n]+west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-614\.961`t417\.745`t9\.587`t" `
        -Message "Expected $Label La Theine West Ronfaure routes not to contain the native -614.961,417.745 wall leg that stalled in live testing."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-670\.000`t-585\.000`t200\.000`t350\.000`t1`t-592\.600`t347\.900`t15\.700`t" `
        -Message "Expected $Label lower-ravine recovery to begin at the first live recorded escape mark."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-670\.000`t-585\.000`t200\.000`t350\.000`t4`t-648\.300`t278\.400`t16\.000`t" `
        -Message "Expected $Label lower-ravine recovery to include the second live recorded escape mark."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-670\.000`t-585\.000`t200\.000`t350\.000`t5`t-650\.400`t280\.000`t15\.350`t" `
        -Message "Expected $Label lower-ravine recovery to take the DAT/navmesh shoulder around the live-collided drop."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-670\.000`t-585\.000`t200\.000`t350\.000`t6`t-656\.400`t281\.200`t14\.350`t" `
        -Message "Expected $Label lower-ravine recovery to keep stepping around the height change instead of cutting through the wall."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-670\.000`t-585\.000`t200\.000`t350\.000`t8`t-646\.400`t269\.200`t10\.350`t" `
        -Message "Expected $Label lower-ravine recovery to descend through the DAT/navmesh shoulder before the lower mark."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t5`t-652\.032`t266\.965`t9\.992`t" `
        -Message "Expected $Label lower-ravine recovery not to retain the live-collided straight drop as sequence 5."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-670\.000`t-585\.000`t200\.000`t350\.000`t10`t-634\.132`t269\.628`t9\.577`t" `
        -Message "Expected $Label lower-ravine recovery to stop at the open lower-shelf DAT handoff before the route system computes the rest."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-fallen-ravine-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t[^\r\n]+`t-620\.600`t212\.900`t-8\.170`t" `
        -Message "Expected $Label fallen-ravine recovery not to route through the wrong lower-floor detour at -620,212."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-current-shelf-pocket-to-west-ronfaure-zoneline`t102`tWest Ronfaure zone line`t-558\.569`t688\.049`t-7\.049`t4\.0`t-660\.000`t-635\.000`t425\.000`t450\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label current shelf-pocket recovery to pull east from the live x=-647,z=435 refusal before trying the West Ronfaure approach."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-shelf-to-ordelle-z2u8`t102`tOrdelle's Caves zone line z2u8`t" `
        -Message "Expected $Label not to install a lower-ravine rescue override for z2u8, which is H-7 rather than the F-7 ravine cave."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-(shelf|wall-pocket)-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t" `
        -Message "Expected $Label not to install the live-disproved shelf-to-z2u6 route overrides."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t-276\.649`t99\.618`t20\.594`t4\.0`t-585\.000`t-550\.000`t405\.000`t520\.000`t1`t-570\.000`t420\.000`t12\.000`t" `
        -Message "Expected $Label Ordelle z2u6 recovery to only catch the actual upper shelf, not the fallen lower-ravine pocket."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t-276\.649`t99\.618`t20\.594`t4\.0`t-585\.000`t-550\.000`t405\.000`t520\.000`t2`t-560\.000`t460\.000`t8\.000`t" `
        -Message "Expected $Label Ordelle z2u6 recovery to continue through the open shelf corridor before the ravine entry."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t-276\.649`t99\.618`t20\.594`t4\.0`t-585\.000`t-550\.000`t405\.000`t520\.000`t3`t-286\.485`t287\.821`t9\.307`t" `
        -Message "Expected $Label Ordelle z2u6 recovery to route through Equesobillot at the F-6 ravine entry."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t-276\.649`t99\.618`t20\.594`t4\.0`t-585\.000`t-550\.000`t405\.000`t520\.000`t10`t-338\.800`t264\.400`t37\.150`t" `
        -Message "Expected $Label Ordelle z2u6 recovery to turn through the F-7 cave approach after the F-6 descent."

    Assert-Match `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t-276\.649`t99\.618`t20\.594`t4\.0`t-585\.000`t-550\.000`t405\.000`t520\.000`t28`t-266\.000`t103\.200`t20\.950`t" `
        -Message "Expected $Label Ordelle z2u6 recovery to use the final F-7 cave approach before the zone line."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t-276\.649`t99\.618`t20\.594`t4\.0`t-610\.000`t-550\.000`t380\.000`t520\.000`t" `
        -Message "Expected $Label Ordelle z2u6 recovery not to retain the broad wall-pocket bounds that can catch a fallen route."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t[^\r\n]+`t-597\.806`t392\.732`t15\.582`t" `
        -Message "Expected $Label Ordelle z2u6 recovery not to include the live-disproved shelf shortcut point."

    Assert-NoMatch `
        -Text $Text `
        -Pattern "(?m)^lathine-open-shelf-via-f6-to-ordelle-z2u6`t102`tOrdelle's Caves zone line z2u6`t[^\r\n]+`t-592\.951`t392\.547`t13\.765`t" `
        -Message "Expected $Label Ordelle z2u6 recovery not to include the live-disproved lower shelf descent point."
}

$sourceOverrides = Get-Content -LiteralPath $sourceOverridesPath -Raw
$liveOverrides = Get-Content -LiteralPath $liveOverridesPath -Raw
$source = Get-Content -LiteralPath $addonPath -Raw

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_points_override_id\(points\)" `
    -Message 'Expected route override helpers to expose the active override id for route behavior checks.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_quarantine_reason\(points, destination\)" `
    -Message 'Expected route quarantine checks to reject live-disproved La Theine wall paths before guidance starts.'

Assert-Match `
    -Text $source `
    -Pattern "x = -592\.951,[\s\S]*?y = 13\.765,[\s\S]*?z = 392\.547,[\s\S]*?destination = '',[\s\S]*?except_destination = `"Ordelle's Caves zone line z2u6`"" `
    -Message 'Expected the lower shelf quarantine to allow the actual F-7 Ordelle ravine entrance z2u6 while blocking wrong exits.'

Assert-Match `
    -Text $source `
    -Pattern "destination = `"Ordelle's Caves zone line z2u6`",[\s\S]*?x = -597\.806,[\s\S]*?y = 15\.582,[\s\S]*?z = 392\.732,[\s\S]*?reason = 'live-disproved La Theine shelf shortcut to Ordelle z2u6; use the F-6 ravine entry before F-7'" `
    -Message 'Expected a z2u6-specific quarantine for the live-disproved shelf shortcut into the wall.'

Assert-Match `
    -Text $source `
    -Pattern "destination = `"Ordelle's Caves zone line z2u6`",[\s\S]*?x = -592\.951,[\s\S]*?y = 13\.765,[\s\S]*?z = 392\.547,[\s\S]*?reason = 'live-disproved La Theine shelf descent to Ordelle z2u6; use the F-6 ravine entry before F-7'" `
    -Message 'Expected a z2u6-specific quarantine for the live-disproved lower shelf descent.'

Assert-NoMatch `
    -Text $source `
    -Pattern "destination = 'west ronfaure zone line',[\s\S]*?x = -697\.409,[\s\S]*?y = 15\.380,[\s\S]*?z = 535\.283,[\s\S]*?reason = 'live-recorded through-rock shelf waypoint rejected on 2026-07-12'" `
    -Message 'An incomplete survey must not hard-block the reachable upper West Ronfaure shelf.'

Assert-NoMatch `
    -Text $source `
    -Pattern "destination = 'west ronfaure zone line',[\s\S]*?x = -695\.188,[\s\S]*?y = 9\.558,[\s\S]*?z = 539\.151,[\s\S]*?reason = 'live-recorded lower through-rock waypoint rejected on 2026-07-12'" `
    -Message 'An incomplete survey must not hard-block the reachable lower West Ronfaure shelf.'

Assert-NoMatch `
    -Text $source `
    -Pattern "lathine-(shelf|wall-pocket)-to-ordelle-z2u6" `
    -Message 'Expected the live-disproved Ordelle z2u6 route override ids to be removed from route behavior code.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_quarantine_reason\(points, destination\)[\s\S]*source:sub\(-6\) ~= ':start'[\s\S]*nav_route_quarantine_match\(point, destination\)" `
    -Message 'Expected quarantine checks to ignore the route start so a recovery route can pull away from a live wall pocket.'

Assert-Match `
    -Text $source `
    -Pattern "local rule_y\s*=\s*tonumber\(rule\.y\)" `
    -Message 'Expected route quarantine checks to support optional Y filtering so same X/Z points on different ledges are not over-blocked.'

Assert-Match `
    -Text $source `
    -Pattern "nav route override rejected destination=.*quarantine" `
    -Message 'Expected route overrides to log and skip quarantined La Theine routes instead of selecting the first matching bad route.'

Assert-Match `
    -Text $source `
    -Pattern "navmesh route rejected zone=.*quarantine" `
    -Message 'Expected navmesh routes to be filtered when they include live-disproved La Theine wall waypoints.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_direct_fallback_block_reason\(player, point\)" `
    -Message 'Expected known-unsafe route rejections to block direct beacon fallback in the La Theine ravine.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_precise_override_active\(player, points\)[\s\S]*lathine-open-shelf-via-f6-to-ordelle-z2u6[\s\S]*px >= -585[\s\S]*px <= -550[\s\S]*pz >= 405[\s\S]*pz <= 520" `
    -Message 'Expected the Ordelle z2u6 F-6 recovery route to stay precise only on the actual upper shelf.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_precise_override_active\(player, points\)[\s\S]*lathine-fallen-ravine-to-west-ronfaure-zoneline[\s\S]*px >= -670[\s\S]*px <= -585[\s\S]*pz >= 200[\s\S]*pz <= 410" `
    -Message 'Expected the fallen lower-ravine route to stay in precise waypoint mode while climbing back toward the West Ronfaure route.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_precise_override_active\(player, points\)[\s\S]*lathine-fallen-pocket-to-west-ronfaure-zoneline[\s\S]*px >= -690[\s\S]*px <= -570[\s\S]*pz >= 360[\s\S]*pz <= 500[\s\S]*lathine-corridor-shoulder-to-west-ronfaure-zoneline[\s\S]*px >= -655[\s\S]*px <= -625[\s\S]*pz >= 420[\s\S]*pz <= 455[\s\S]*lathine-lower-corridor-to-west-ronfaure-zoneline[\s\S]*px >= -635[\s\S]*px <= -585[\s\S]*pz >= 350[\s\S]*pz <= 535[\s\S]*lathine-wall-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-lower-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-mid-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-exit-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-upper-west-pocket-to-west-ronfaure-zoneline[\s\S]*px >= -705[\s\S]*px <= -640[\s\S]*pz >= 450[\s\S]*pz <= 535" `
    -Message 'Expected staged La Theine pocket, shoulder, and lower-corridor escapes to keep precise waypoint mode through the west passage, including the live-failed x=-639,z=439 loop start.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_override_requires_full_start\(points\)[\s\S]*lathine-open-shelf-via-f6-to-ordelle-z2u6[\s\S]*lathine-fallen-pocket-to-west-ronfaure-zoneline" `
    -Message 'Expected route overrides that start from wall pockets to keep their recorded escape from the start.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_position_delta\(pos, points\)" `
    -Message 'Expected live route tracking to compute both horizontal and vertical distance from the active route.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_lathine_lower_ravine_position\(pos\)[\s\S]*local py = tonumber\(pos\.y\);[\s\S]*if \(py == nil\) then[\s\S]*return false;[\s\S]*px >= -670[\s\S]*px <= -585[\s\S]*pz >= 200[\s\S]*pz <= 350[\s\S]*py <= 12\.5" `
    -Message 'Expected La Theine lower-ravine detection to require a real lower Y layer, so missing height cannot be treated as y=0 and select the lower-ravine route.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_override_matches\(player, point, override\)[\s\S]*local route_id = tostring\(override\.id or ''\)[\s\S]*lathine-fallen-ravine-to-west-ronfaure-zoneline[\s\S]*not accessxi\.nav_lathine_lower_ravine_position\(player\)[\s\S]*return false" `
    -Message 'Expected the generic route override matcher to reject the fallen-ravine West route from the upper shelf layer.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_live_replan_reason\(player, destination, points, delta\)[\s\S]*lathine lower ravine live position[\s\S]*route drift from live position[\s\S]*route layer changed" `
    -Message 'Expected live route tracking to force replans from generic live 3D drift, not only a hard-coded ravine case.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_lathine_lower_ravine_recovery_route\(player, point\)[\s\S]*lathine-fallen-ravine-to-west-ronfaure-zoneline[\s\S]*handoff[\s\S]*-634\.132[\s\S]*nav_compute_mesh_route\(handoff, point\)[\s\S]*nav lower ravine recovery route" `
    -Message 'Expected lower-ravine recovery to hand off at the open lower shelf before routing onward to any destination.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_compute_route_with_zoneline_approach\(player, point\)[\s\S]*nav_lathine_lower_ravine_recovery_route\(player, point\)[\s\S]*nav_route_override_points\(player, point\)" `
    -Message 'Expected route computation to try the live-position lower-ravine recovery before selecting the broad fallen-ravine override.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_override_requires_full_start\(points\)[\s\S]*lathine-fallen-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-corridor-shoulder-to-west-ronfaure-zoneline[\s\S]*lathine-lower-corridor-to-west-ronfaure-zoneline[\s\S]*lathine-wall-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-lower-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-mid-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-exit-pocket-to-west-ronfaure-zoneline[\s\S]*lathine-upper-west-pocket-to-west-ronfaure-zoneline" `
    -Message 'Expected staged La Theine pocket and shoulder overrides to keep their recorded escape from the start.'

$fullStartStart = $source.IndexOf('function accessxi.nav_route_override_requires_full_start(points)')
$fullStartEnd = $source.IndexOf('function accessxi.nav_route_override_start_index(player, points)', $fullStartStart)
if ($fullStartStart -lt 0 -or $fullStartEnd -lt 0) {
    throw 'Could not locate nav_route_override_requires_full_start body.'
}
$fullStartBody = $source.Substring($fullStartStart, $fullStartEnd - $fullStartStart)

Assert-NoMatch `
    -Text $fullStartBody `
    -Pattern "lathine-fallen-ravine-to-west-ronfaure-zoneline" `
    -Message 'Expected fallen-ravine recovery refreshes not to force waypoint 1 after the player is already on the lower route.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_route_override_start_index\(player, points\)[\s\S]*nav_project_to_segment\(player, points\[i\], points\[i \+ 1\]\)[\s\S]*best_segment > 0 and best_distance <= 5\.0[\s\S]*nav_route_override_requires_full_start\(points\)" `
    -Message 'Expected route override refreshes to resume from the live nearest segment before falling back to full-start behavior.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_sync_route_index\(pos\)[\s\S]*nav_route_precise_override_active\(pos, accessxi\.nav_route_points\)[\s\S]*return;[\s\S]*nav_nearest_route_segment" `
    -Message 'Expected precise route overrides to skip nearest-segment route index sync so tight La Theine waypoint recoveries cannot jump over corners.'

$pollStart = $source.IndexOf('local function poll_nav_route()')
if ($pollStart -lt 0) {
    throw 'Could not locate poll_nav_route.'
}
$pollBody = $source.Substring($pollStart, [Math]::Min(18000, $source.Length - $pollStart))

Assert-Match `
    -Text $pollBody `
    -Pattern "local precise_override\s*=\s*accessxi\.nav_route_precise_override_active\(player, accessxi\.nav_route_points\)" `
    -Message 'Expected poll_nav_route to detect precise route overrides before choosing guidance targets.'

Assert-Match `
    -Text $pollBody `
    -Pattern "nav_route_points_are_override\(accessxi\.nav_route_points\)[\s\S]*handoff_id ~= ''[\s\S]*handoff_id ~= current_id[\s\S]*nav route override handoff destination=.*id=" `
    -Message 'Expected poll_nav_route to hand off from one override to another when live position selects a better route.'

Assert-Match `
    -Text $pollBody `
    -Pattern "nav_route_live_replan_reason\(player, destination, accessxi\.nav_route_points, route_delta\)[\s\S]*nav live replan reason=" `
    -Message 'Expected poll_nav_route to force a live replan when the player has fallen below the current route.'

Assert-Match `
    -Text $pollBody `
    -Pattern "vertical_route_distance > 7\.0[\s\S]*nav route adjusted offroute=.*vertical=.*below=" `
    -Message 'Expected off-route correction to account for 3D route layer changes, not only horizontal drift.'

Assert-Match `
    -Text $pollBody `
    -Pattern "if \(route_count > 1 and precise_override\)[\s\S]*?nav_precise_steering_target\([\s\S]*?elseif \(route_count > 1\)[\s\S]*?nav_indexed_lookahead_target" `
    -Message 'Expected precise route overrides to use bounded recorded-polyline steering while generic routes retain indexed lookahead.'

Assert-Match `
    -Text $pollBody `
    -Pattern "if \(not precise_override\)[\s\S]*?nav_apply_dynamic_obstacle" `
    -Message 'Expected precise route overrides to skip dynamic obstacle target substitution inside the tight escape pocket.'

Assert-NoMatch `
    -Text $pollBody `
    -Pattern "route_target = accessxi\.nav_apply_dynamic_obstacle\(player, route_target\);\s*if \(not precise_override\)" `
    -Message 'Expected dynamic obstacle substitution to be inside the precise-route guard, not before it.'

Assert-Match `
    -Text $pollBody `
    -Pattern "if \(not precise_override\)[\s\S]*?nav_apply_wall_avoidance" `
    -Message 'Expected precise route overrides to skip wall avoidance so the lower-pocket escape does not circle.'

Assert-LaTheineShelfOverrides -Text $sourceOverrides -Label 'source'
Assert-LaTheineShelfOverrides -Text $liveOverrides -Label 'live'

Assert-NavProbeWaypointCount `
    -Coordinates @('-668.159', '16.500', '455.347', '-674.828', '16.450', '466.164') `
    -MaxCount 2 `
    -Message 'Expected the fallen-pocket route to be able to reach the recorded walked starting point from the latest stuck start.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-674.828', '16.450', '466.164', '-624.777', '16.500', '409.617') `
    -MaxCount 2 `
    -Message 'Expected the recorded fallen-pocket reload position to be able to reach the walked corridor branch.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-647.370', '16.244', '434.725', '-570.000', '12.000', '420.000') `
    -MaxCount 1 `
    -Message 'Expected the current shelf-pocket refusal position to have a direct eastward pull-away to the open shelf route.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-611.420', '16.212', '367.879', '-570.000', '12.000', '420.000') `
    -MaxCount 1 `
    -Message 'Expected the live lower-ravine position to have a direct pull-away to the same open shelf recovery point.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-596.199', '15.646', '392.753', '-570.000', '12.000', '420.000') `
    -MaxCount 1 `
    -Message 'Expected the live Ordelle wall-pocket start to have a direct pull-away to the open shelf recovery point.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-570.000', '12.000', '420.000', '-560.000', '8.000', '460.000') `
    -MaxCount 1 `
    -Message 'Expected the Ordelle recovery open-shelf hop to stay direct before heading to the F-6 ravine.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-560.000', '8.000', '460.000', '-286.485', '9.307', '287.821') `
    -MaxCount 1 `
    -Message 'Expected the open shelf to connect to Equesobillot at the F-6 ravine entry.'

Assert-NavProbePathContains `
    -Coordinates @('-596.199', '15.646', '392.753', '-60.125', '27.231', '148.001') `
    -Pattern '592\.951\s+13\.765\s+392\.547' `
    -Message 'Expected navprobe to expose the live-disproved lower shelf descent inside the raw Ordelle z2u8 mesh route.'

Assert-NavProbePathContains `
    -Coordinates @('-611.420', '16.212', '367.879', '-276.649', '20.594', '99.618') `
    -Pattern '592\.951\s+13\.765\s+392\.547' `
    -Message 'Expected the raw z2u6 navmesh from the live pocket to expose the live-disproved shelf descent so quarantine can reject it.'

Assert-NavProbePathContains `
    -Coordinates @('-286.485', '9.307', '287.821', '-276.649', '20.594', '99.618') `
    -Pattern '338\.8\s+37\.15\s+264\.4[\s\S]*262\s+21\.35\s+105\.6' `
    -Message 'Expected the F-6 Equesobillot route to use the F-7 Ordelle cave approach corridor.'

Assert-NavProbePathContains `
    -Coordinates @('-648.284', '16.012', '278.405', '-620.600', '-7.900', '212.900') `
    -Pattern '656\.4\s+14\.35\s+281\.2[\s\S]*646\.4\s+10\.35\s+269\.2[\s\S]*633\.2\s+7\.35\s+264\.4' `
    -Message 'Expected DAT/navmesh routing to step around the live-collided lower-ravine drop instead of cutting straight down.'

Assert-NavProbePathContains `
    -Coordinates @('-650.399', '15.537', '279.420', '-620.600', '-7.900', '212.900') `
    -Pattern '656\.4\s+14\.35\s+281\.2[\s\S]*646\.4\s+10\.35\s+269\.2[\s\S]*633\.2\s+7\.35\s+264\.4' `
    -Message 'Expected DAT/navmesh routing from the exact live stuck position to recover through the same lower-ravine shoulder.'

Assert-NavProbePathContains `
    -Coordinates @('-634.132', '9.577', '269.628', '-558.569', '-7.049', '688.049') `
    -Pattern '628\.4\s+9\.75\s+284\.8[\s\S]*596\s+10\.75\s+314\.8[\s\S]*592\.4\s+-1\.65\s+595\.2' `
    -Message 'Expected DAT/navmesh routing from the open lower-shelf handoff to reach West Ronfaure without the wrong -620,212 floor detour.'

Assert-NavProbePathContains `
    -Coordinates @('-634.132', '9.577', '269.628', '-276.649', '20.594', '99.618') `
    -Pattern '345\.878\s+2\.736\s+376\.292[\s\S]*338\.8\s+37\.15\s+264\.4[\s\S]*262\s+21\.35\s+105\.6' `
    -Message 'Expected DAT/navmesh routing from the open lower-shelf handoff to reach Ordelle z2u6 through the real F-6/F-7 approach.'

Assert-NavProbePathContains `
    -Coordinates @('-624.777', '16.500', '409.617', '-621.600', '3.950', '460.800') `
    -Pattern '614\.961\s+9\.587\s+417\.745' `
    -Message 'Expected navprobe to expose the live-disproved -614.961,417.745 wall leg inside the old -624.777 to -621.600 shortcut.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-593.871', '15.224', '363.640', '-595.600', '15.550', '366.400') `
    -MaxCount 2 `
    -Message 'Expected the lower ledge screenshot point to stay on the native lower route before the broad shelf override can apply.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-582.000', '6.750', '380.800', '-570.000', '12.000', '420.000') `
    -MaxCount 2 `
    -Message 'Expected the lower ledge route to rejoin the open shelf only after reaching the safe z=380 edge.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-596.859', '16.048', '387.850', '-605.825', '16.241', '376.274') `
    -MaxCount 2 `
    -Message 'Expected the screenshot shelf pocket to backtrack toward the safe lower descent instead of using the broad direct shelf shortcut.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-598.200', '15.886', '359.363', '-605.825', '16.241', '376.274') `
    -MaxCount 2 `
    -Message 'Expected the live lower-corridor start to reach the safe lower descent before the west approach.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-613.255', '16.537', '382.068', '-605.825', '16.241', '376.274') `
    -MaxCount 2 `
    -Message 'Expected the old broad-override handoff position to recover to the safe lower descent instead of cutting to the shelf shortcut.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-594.610', '15.170', '401.837', '-605.825', '16.241', '376.274') `
    -MaxCount 2 `
    -Message 'Expected the earlier wall-stuck screenshot point to recover to the safe lower descent.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-616.083', '15.279', '415.614', '-605.825', '16.241', '376.274') `
    -MaxCount 2 `
    -Message 'Expected the latest native-leg stall point to recover to the safe lower descent.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-426.804', '8.788', '220.242', '-391.600', '10.950', '208.000') `
    -MaxCount 2 `
    -Message 'Expected the current gully screenshot pocket to have a direct pull-away segment back to the central route.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-679.628', '15.975', '482.464', '-570.000', '12.000', '420.000') `
    -MaxCount 2 `
    -Message 'Expected the widened cliff pocket to have a direct recovery segment back to the open eastern shelf.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-739.434', '22.708', '385.728', '-570.000', '12.000', '420.000') `
    -MaxCount 2 `
    -Message 'Expected the current Huge Wasp wall pocket to have a direct pull-away segment to the open eastern shelf.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-697.489', '16.039', '531.750', '-680.000', '15.644', '520.000') `
    -MaxCount 2 `
    -Message 'Expected the original ravine screenshot pocket to have a direct pull-away segment to the open ledge.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-689.300', '15.462', '530.356', '-680.000', '15.644', '520.000') `
    -MaxCount 2 `
    -Message 'Expected the second live stuck pocket to have a direct pull-away segment to the open ledge.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-680.000', '15.644', '520.000', '-570.000', '12.000', '420.000') `
    -MaxCount 2 `
    -Message 'Expected the open ledge recovery point to rejoin the known open shelf route cleanly.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-560.000', '2.000', '500.000', '-584.400', '-4.450', '545.600') `
    -MaxCount 2 `
    -Message 'Expected the lower western route to resume cleanly after the shelf recovery point.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-682.408', '16.328', '490.577', '-675.588', '15.290', '479.784') `
    -MaxCount 2 `
    -Message 'Expected the lower-pocket start to have a direct first escape step.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-674.614', '15.168', '481.805', '-675.588', '15.290', '479.784') `
    -MaxCount 2 `
    -Message 'Expected the live lower-pocket wall point to have a direct escape step.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-675.588', '15.290', '479.784', '-674.828', '16.450', '466.164') `
    -MaxCount 3 `
    -Message 'Expected lower-pocket escape step one to retreat to the walked pocket point.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-674.828', '16.450', '466.164', '-672.401', '16.521', '463.070') `
    -MaxCount 2 `
    -Message 'Expected pocket recovery to continue onto the walked backtrack corridor.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-666.689', '15.987', '460.969', '-669.600', '15.750', '463.200') `
    -MaxCount 2 `
    -Message 'Expected the latest wall-stuck screenshot point to have a short first escape step.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-669.600', '15.750', '463.200', '-672.401', '16.521', '463.070') `
    -MaxCount 2 `
    -Message 'Expected wall-pocket escape step one to join the walked backtrack corridor.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-672.401', '16.521', '463.070', '-667.732', '16.390', '457.104') `
    -MaxCount 3 `
    -Message 'Expected wall-pocket escape step two to backtrack along the walked corridor.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-667.732', '16.390', '457.104', '-662.666', '16.500', '450.630') `
    -MaxCount 2 `
    -Message 'Expected wall-pocket escape to continue back along the walked corridor.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-677.200', '15.950', '490.400', '-677.200', '14.950', '486.000') `
    -MaxCount 3 `
    -Message 'Expected mid-pocket wall-lip recovery to have a small backward step around the obstruction.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-666.000', '7.750', '500.000', '-660.000', '6.150', '526.000') `
    -MaxCount 2 `
    -Message 'Expected the exit-pocket route to go forward to the lower exit instead of backward into the wall pocket.'

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

Assert-NavProbeWaypointCount `
    -Coordinates @('-639.139', '15.945', '439.502', '-635.726', '16.907', '421.025') `
    -MaxCount 2 `
    -Message 'Expected the live post-reload loop start to have a direct first shoulder-recovery step.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-635.211', '16.861', '420.655', '-635.726', '16.907', '421.025') `
    -MaxCount 2 `
    -Message 'Expected the latest lower-corridor shoulder position to stay on the shoulder recovery instead of handing off to the west-pocket loop.'

Assert-NavProbeWaypointCount `
    -Coordinates @('-654.582', '15.710', '451.220', '-635.726', '16.907', '421.025') `
    -MaxCount 2 `
    -Message 'Expected the live navmesh handoff point to be caught by the shoulder route before the fallen-pocket loop.'

Write-Host 'nav La Theine shelf escape checks passed'
