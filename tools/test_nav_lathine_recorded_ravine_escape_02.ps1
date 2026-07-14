$ErrorActionPreference = 'Stop'

$sessionId = '20260712-150854-z102'
$routeId = 'lathine-recorded-ravine-escape-20260712-150854'
$recordingPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv'
$sourceOverridesPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv'
$sourceAddonOverridesPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$liveOverridesPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$headers = @('route_id','zone','destination_name','destination_x','destination_z','destination_y','match_radius','min_x','max_x','min_z','max_z','sequence','waypoint_x','waypoint_z','waypoint_y','source','confidence','note')

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected'; found '$Actual'."
    }
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$recorded = @(Import-Csv -LiteralPath $recordingPath -Delimiter "`t" |
    Where-Object session -eq $sessionId |
    Sort-Object { [int]$_.seq })
Assert-Equal $recorded.Count 235 'Second recorded-ravine row count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'start').Count 1 'Second recording start count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'point').Count 233 'Second recording movement count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'stop').Count 1 'Second recording stop count mismatch.'
Assert-Equal $recorded[0].x '-628.024' 'Second recording start x mismatch.'
Assert-Equal $recorded[0].z '290.753' 'Second recording start z mismatch.'
Assert-Equal $recorded[0].y '15.072' 'Second recording start y mismatch.'
Assert-Equal $recorded[-1].x '-564.031' 'Second recording stop x mismatch.'
Assert-Equal $recorded[-1].z '656.332' 'Second recording stop z mismatch.'
Assert-Equal $recorded[-1].y '0.746' 'Second recording stop y mismatch.'

$routeRows = @(Import-Csv -LiteralPath $sourceOverridesPath -Delimiter "`t" -Header $headers |
    Where-Object route_id -eq $routeId |
    Sort-Object { [int]$_.sequence })
if ($routeRows.Count -eq 0) {
    throw "Missing second recorded-ravine route '$routeId'."
}
Assert-Equal $routeRows.Count $recorded.Count 'Second complete walked sequence was not preserved.'

for ($i = 0; $i -lt $recorded.Count; $i++) {
    $sequence = [string]($i + 1)
    Assert-Equal $routeRows[$i].sequence $sequence "Second route sequence mismatch at $sequence."
    Assert-Equal $routeRows[$i].waypoint_x $recorded[$i].x "Second route x mismatch at $sequence."
    Assert-Equal $routeRows[$i].waypoint_z $recorded[$i].z "Second route z mismatch at $sequence."
    Assert-Equal $routeRows[$i].waypoint_y $recorded[$i].y "Second route y mismatch at $sequence."
    Assert-Equal $routeRows[$i].min_x '-633.024' "Second route minimum x mismatch at $sequence."
    Assert-Equal $routeRows[$i].max_x '-623.024' "Second route maximum x mismatch at $sequence."
    Assert-Equal $routeRows[$i].min_z '285.753' "Second route minimum z mismatch at $sequence."
    Assert-Equal $routeRows[$i].max_z '295.753' "Second route maximum z mismatch at $sequence."
    Assert-Equal $routeRows[$i].destination_x '-564.031' "Second handoff x mismatch at $sequence."
    Assert-Equal $routeRows[$i].destination_z '656.332' "Second handoff z mismatch at $sequence."
    Assert-Equal $routeRows[$i].destination_y '0.746' "Second handoff y mismatch at $sequence."
    Assert-Equal $routeRows[$i].source 'live-route-recording-20260712-150854-z102' "Second route provenance mismatch at $sequence."
    Assert-Equal $routeRows[$i].confidence 'proven' "Second route confidence mismatch at $sequence."
}

$dataHashes = @($sourceOverridesPath,$sourceAddonOverridesPath,$liveOverridesPath) |
    ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } |
    Select-Object -Unique
Assert-Equal $dataHashes.Count 1 'Route-data copies diverged while adding the second recording.'

$luaHashes = @($sourceLuaPath,$liveLuaPath) |
    ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } |
    Select-Object -Unique
Assert-Equal $luaHashes.Count 1 'Source and live Lua copies diverged.'

$lua = Get-Content -LiteralPath $sourceLuaPath -Raw
Assert-Match $lua "tostring\(override\.id or ''\):startswith\('lathine-recorded-ravine-escape-'\)" 'Expected start-pocket selection across all recorded ravine corridors.'
Assert-Match $lua "route_id:startswith\('lathine-recorded-ravine-escape-'\)" 'Expected precise routing across all recorded ravine corridors.'
Assert-Match $lua "local route_id = tostring\(escape\.id or ''\)" 'Expected the route builder to preserve the selected recording ID dynamically.'

Write-Host 'nav La Theine recorded ravine escape 02 checks passed'
