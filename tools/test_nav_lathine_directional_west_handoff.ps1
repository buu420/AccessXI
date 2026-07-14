$ErrorActionPreference = 'Stop'

$safeRouteId = 'lathine-recorded-corridor-20260712-west-via-ravine-01'
$recoveryRouteId = 'lathine-recorded-corridor-20260712-west-via-ravine-01-recovery'
$unsafeRouteId = 'lathine-recorded-corridor-20260712-zone-backbone'
$sourceOverridesPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv'
$sourceAddonOverridesPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$liveOverridesPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'

$headers = @(
    'route_id', 'zone', 'destination_name', 'destination_x', 'destination_z', 'destination_y',
    'match_radius', 'min_x', 'max_x', 'min_z', 'max_z', 'sequence',
    'waypoint_x', 'waypoint_z', 'waypoint_y', 'source', 'confidence', 'note'
)

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory = $true)][string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected'; found '$Actual'."
    }
}

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

function Distance-3D {
    param($A, $B)
    $dx = [double]$A.waypoint_x - [double]$B.waypoint_x
    $dz = [double]$A.waypoint_z - [double]$B.waypoint_z
    $dy = [double]$A.waypoint_y - [double]$B.waypoint_y
    return [Math]::Sqrt(($dx * $dx) + ($dz * $dz) + ($dy * $dy))
}

$files = @($sourceOverridesPath, $sourceAddonOverridesPath, $liveOverridesPath)
foreach ($path in $files) {
    $allRows = @(Import-Csv -LiteralPath $path -Delimiter ([char]9) -Header $headers)
    Assert-Equal @($allRows | Where-Object route_id -eq $unsafeRouteId).Count 0 `
    "Undirected full-survey backbone remains armed in $path."

    $rows = @($allRows | Where-Object route_id -eq $safeRouteId | Sort-Object { [int]$_.sequence })
    Assert-Equal $rows.Count 164 "Directional West handoff row count mismatch in $path."
    Assert-Equal $rows[0].note 'friend walk sample 3985' "Directional route start mismatch in $path."
    Assert-Equal $rows[-1].note 'ravine escape sample 323' "Recorded escape endpoint mismatch in $path."

    $friendRows = @($rows | Where-Object { $_.note -like 'friend walk sample *' })
    Assert-Equal $friendRows.Count 10 "Simplified friend-walk section count mismatch in $path."
    Assert-Equal $friendRows[-1].note 'friend walk sample 4006' "Friend-walk handoff endpoint mismatch in $path."
    for ($i = 1; $i -lt $friendRows.Count; $i++) {
        $prior = [int]($friendRows[$i - 1].note -replace '^friend walk sample ', '')
        $sample = [int]($friendRows[$i].note -replace '^friend walk sample ', '')
        if ($sample -le $prior) { throw "Friend-walk simplification reversed direction in $path." }
    }
    $escapeRows = @($rows | Where-Object { $_.note -like 'ravine escape sample *' })
    Assert-Equal $escapeRows.Count 154 "Recorded ravine-escape section count mismatch in $path."
    Assert-Equal $escapeRows[0].note 'ravine escape sample 2' "Recorded escape handoff start mismatch in $path."
    for ($i = 1; $i -lt $escapeRows.Count; $i++) {
        $prior = [int]($escapeRows[$i - 1].note -replace '^ravine escape sample ', '')
        $sample = [int]($escapeRows[$i].note -replace '^ravine escape sample ', '')
        if ($sample -le $prior) { throw "Ravine escape simplification reversed direction in $path." }
    }

    $handoffDistance = Distance-3D $friendRows[-1] $escapeRows[0]
    if ($handoffDistance -gt 1.0) {
        throw "Recorded-to-recorded handoff exceeds 1 yalm in $path. Found $handoffDistance."
    }

    $recovery = @($allRows | Where-Object route_id -eq $recoveryRouteId | Sort-Object { [int]$_.sequence })
    Assert-Equal $recovery.Count 157 "Upper-shelf recovery row count mismatch in $path."
    $recoveryShelf = @($recovery | Where-Object { $_.note -like 'upper shelf recovery sample *' })
    Assert-Equal $recoveryShelf.Count 3 "Simplified upper-shelf recovery count mismatch in $path."
    Assert-Equal $recoveryShelf[0].note 'upper shelf recovery sample 4012' "Recovery start mismatch in $path."
    Assert-Equal $recoveryShelf[-1].note 'upper shelf recovery sample 4006' "Recovery handoff endpoint mismatch in $path."
    for ($i = 1; $i -lt $recoveryShelf.Count; $i++) {
        $prior = [int]($recoveryShelf[$i - 1].note -replace '^upper shelf recovery sample ', '')
        $sample = [int]($recoveryShelf[$i].note -replace '^upper shelf recovery sample ', '')
        if ($sample -ge $prior) { throw "Upper-shelf recovery simplification reversed direction in $path." }
    }
    $recoveryEscape = @($recovery | Where-Object { $_.note -like 'ravine escape sample *' })
    Assert-Equal $recoveryEscape[0].note 'ravine escape sample 2' "Recovery-to-escape handoff mismatch in $path."
    Assert-Equal $recovery[-1].note 'ravine escape sample 323' "Recovery escape endpoint mismatch in $path."
    $recoveryHandoff = Distance-3D $recoveryShelf[-1] $recoveryEscape[0]
    if ($recoveryHandoff -gt 1.0) {
        throw "Recovery handoff exceeds 1 yalm in $path. Found $recoveryHandoff."
    }
}

$dataHashes = @($files | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } | Select-Object -Unique)
Assert-Equal $dataHashes.Count 1 'Route data copies are not byte-identical.'

$lua = Get-Content -LiteralPath $sourceLuaPath -Raw
Assert-Match $lua "west_safe\s*=\s*route_id:startswith\('lathine-recorded-corridor-20260712-west-via-'\)" `
    'Missing dedicated directional West route classification.'
Assert-Match $lua 'west_safe[\s\S]*?destination_is_west[\s\S]*?nav_lathine_recorded_corridor_candidate\([\s\S]*?player_index, 1\)' `
    'Directional West route must only follow the recordings forward toward the proven escape.'
Assert-Match $lua 'if \(west_safe and not destination_is_west\)[\s\S]*?candidates = T\{\}' `
    'Directional West route must remain unavailable for reverse or unrelated destinations.'
Assert-Match $lua 'candidate_priority\s*=\s*west_safe and 0 or 1' `
    'The proven directional West handoff must outrank unrelated corridor candidates.'

$luaHashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
Assert-Equal $luaHashes.Count 1 'Source and live Lua copies are not byte-identical.'

Write-Host 'La Theine directional West handoff checks passed'
