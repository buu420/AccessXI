param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$AshitaRoot = 'C:\Users\buu42\Ashita',
    [string]$RecordingPath = '',
    [switch]$IncludeLive
)

$ErrorActionPreference = 'Stop'

$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$AshitaRoot = [System.IO.Path]::GetFullPath($AshitaRoot)
$sessionId = '20260712-170700-z102'
$sourceTag = 'live-route-recording-20260712-170700-z102'
if ([string]::IsNullOrWhiteSpace($RecordingPath)) {
    $RecordingPath = Join-Path $AshitaRoot 'addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv'
}
$recordingPath = [System.IO.Path]::GetFullPath($RecordingPath)
$graphPaths = @(
    (Join-Path $RepoRoot 'data\ffxi-nav-recorded-survey.tsv'),
    (Join-Path $RepoRoot 'ashita\addons\accessxi_reader\data\ffxi-nav-recorded-survey.tsv')
)
$markPaths = @(
    (Join-Path $RepoRoot 'data\ffxi-nav-recorded-marks.tsv'),
    (Join-Path $RepoRoot 'ashita\addons\accessxi_reader\data\ffxi-nav-recorded-marks.tsv')
)
$sourceLuaPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = Join-Path $AshitaRoot 'addons\accessxi_reader\accessxi_reader.lua'
$modulePaths = @(
    (Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\recorded_survey_navigation.lua')
)
if ($IncludeLive) {
    $graphPaths += Join-Path $AshitaRoot 'addons\accessxi_reader\data\ffxi-nav-recorded-survey.tsv'
    $markPaths += Join-Path $AshitaRoot 'addons\accessxi_reader\data\ffxi-nav-recorded-marks.tsv'
    $modulePaths += Join-Path $AshitaRoot 'addons\accessxi_reader\modules\recorded_survey_navigation.lua'
}
$luaExe = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'

function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory = $true)][string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected'; found '$Actual'." }
}

$recorded = @(Import-Csv -LiteralPath $recordingPath -Delimiter "`t" |
    Where-Object { $_.session -eq $sessionId } |
    Sort-Object { [int]$_.seq })
Assert-Equal $recorded.Count 6499 'Complete friend-walk row count changed.'
Assert-Equal @($recorded | Where-Object event -eq 'point').Count 6469 'Complete friend-walk movement count changed.'
Assert-Equal @($recorded | Where-Object event -eq 'mark').Count 28 'Complete friend-walk mark count changed.'

foreach ($path in $graphPaths + $markPaths + $modulePaths) {
    Assert-True (Test-Path -LiteralPath $path) "Missing recorded-survey artifact: $path"
}

$graphs = @()
foreach ($path in $graphPaths) {
    $graph = @(Import-Csv -LiteralPath $path -Delimiter "`t")
    Assert-Equal $graph.Count 6499 "Recorded graph row count mismatch in $path."
    $graphs += ,$graph

    $byId = @{}
    foreach ($node in $graph) {
        $id = [int]$node.node_id
        Assert-True (-not $byId.ContainsKey($id)) "Duplicate graph node $id in $path."
        $byId[$id] = $node
    }

    $reunionEdges = @{}
    for ($i = 0; $i -lt $recorded.Count; $i++) {
        $expected = $recorded[$i]
        $node = $byId[$i + 1]
        Assert-True ($null -ne $node) "Missing graph node $($i + 1) in $path."
        Assert-Equal $node.survey_id $sessionId "Survey id mismatch for node $($i + 1) in $path."
        Assert-Equal $node.zone '102' "Zone mismatch for node $($i + 1) in $path."
        Assert-Equal $node.sequence $expected.seq "Sequence mismatch for node $($i + 1) in $path."
        Assert-Equal $node.x $expected.x "X mismatch for node $($i + 1) in $path."
        Assert-Equal $node.z $expected.z "Z mismatch for node $($i + 1) in $path."
        Assert-Equal $node.y $expected.y "Y mismatch for node $($i + 1) in $path."
        Assert-Equal $node.event $expected.event "Event mismatch for node $($i + 1) in $path."
        Assert-Equal $node.label $expected.label "Label mismatch for node $($i + 1) in $path."
        Assert-Equal $node.source $sourceTag "Source mismatch for node $($i + 1) in $path."
        Assert-Equal $node.confidence 'proven' "Confidence mismatch for node $($i + 1) in $path."

        $neighbors = @()
        if (-not [string]::IsNullOrWhiteSpace($node.neighbors)) {
            $neighbors = @($node.neighbors -split ',' | ForEach-Object { [int]$_ })
        }
        if ($i -gt 0) {
            Assert-True ($neighbors -contains $i) "Node $($i + 1) lacks its previous walked edge in $path."
        }
        if ($i -lt ($recorded.Count - 1)) {
            Assert-True ($neighbors -contains ($i + 2)) "Node $($i + 1) lacks its next walked edge in $path."
        }

        foreach ($neighborId in $neighbors) {
            Assert-True ($byId.ContainsKey($neighborId)) "Node $($i + 1) references missing neighbor $neighborId in $path."
            $reverse = @($byId[$neighborId].neighbors -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
            Assert-True ($reverse -contains ($i + 1)) "Graph edge $($i + 1)-$neighborId is not bidirectional in $path."
            if ([Math]::Abs($neighborId - ($i + 1)) -gt 1) {
                $a = $node
                $b = $byId[$neighborId]
                $horizontal = [Math]::Sqrt(
                    ([double]$a.x - [double]$b.x) * ([double]$a.x - [double]$b.x) +
                    ([double]$a.z - [double]$b.z) * ([double]$a.z - [double]$b.z))
                $vertical = [Math]::Abs([double]$a.y - [double]$b.y)
                Assert-True ($horizontal -le 0.500001) "Reunion edge $($i + 1)-$neighborId exceeds 0.5 horizontal yalms in $path."
                Assert-True ($vertical -le 0.750001) "Reunion edge $($i + 1)-$neighborId exceeds 0.75 vertical yalms in $path."
                $edgeKey = if (($i + 1) -lt $neighborId) { "$($i + 1):$neighborId" } else { "${neighborId}:$($i + 1)" }
                $reunionEdges[$edgeKey] = $true
            }
        }
    }
    Assert-Equal $reunionEdges.Count 64 "Recorded graph reunion-edge count mismatch in $path."
}

$expectedMarks = @(
    @{ Sequence = 14; Name = 'Field Manual'; Kind = 'object' },
    @{ Sequence = 25; Name = 'Cavernous Maw'; Kind = 'object' },
    @{ Sequence = 1098; Name = 'Telepoint stairs'; Kind = 'object' },
    @{ Sequence = 1109; Name = 'Telepoint'; Kind = 'npc' },
    @{ Sequence = 1274; Name = 'Survival Guide'; Kind = 'object' },
    @{ Sequence = 1456; Name = 'Chocobo Rental'; Kind = 'npc' },
    @{ Sequence = 1536; Name = 'Shattered Telepoint stairs'; Kind = 'object' },
    @{ Sequence = 1546; Name = 'Shattered Telepoint'; Kind = 'npc' },
    @{ Sequence = 1617; Name = 'Dimensional Portal stairs'; Kind = 'object' },
    @{ Sequence = 1628; Name = 'Dimensional Portal'; Kind = 'npc' },
    @{ Sequence = 2220; Name = 'Cliff path 1 bottom'; Kind = 'object' },
    @{ Sequence = 2267; Name = 'Cliff path 1 top'; Kind = 'object' },
    @{ Sequence = 3052; Name = 'Cliff path 2 bottom'; Kind = 'object' },
    @{ Sequence = 3114; Name = 'Cliff path 2 top'; Kind = 'object' },
    @{ Sequence = 3810; Name = 'Cliff path 3 bottom'; Kind = 'object' },
    @{ Sequence = 3846; Name = 'Cliff path 3 top'; Kind = 'object' },
    @{ Sequence = 4411; Name = 'Cliff path 3 first branch bottom'; Kind = 'object' },
    @{ Sequence = 4462; Name = 'Cliff path 3 first branch top'; Kind = 'object' },
    @{ Sequence = 4584; Name = 'Cliff path 3 second branch bottom'; Kind = 'object' },
    @{ Sequence = 4623; Name = 'Cliff path 3 second branch top'; Kind = 'object' },
    @{ Sequence = 5421; Name = 'Cliff path 4 bottom'; Kind = 'object' },
    @{ Sequence = 5466; Name = 'Cliff path 4 top'; Kind = 'object' },
    @{ Sequence = 6446; Name = 'Cliff path 5 bottom'; Kind = 'object' },
    @{ Sequence = 6498; Name = 'Cliff path 5 top'; Kind = 'object' }
)

foreach ($path in $markPaths) {
    $lines = @(Get-Content -LiteralPath $path | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
    Assert-Equal $lines.Count 24 "Recorded landmark destination count mismatch in $path."
    for ($i = 0; $i -lt $expectedMarks.Count; $i++) {
        $fields = $lines[$i] -split "`t"
        $expectedMark = $expectedMarks[$i]
        $recordedMark = $recorded | Where-Object { [int]$_.seq -eq $expectedMark.Sequence } | Select-Object -First 1
        Assert-Equal $fields.Count 9 "Recorded mark column count mismatch at row $($i + 1) in $path."
        Assert-Equal $fields[0] '102' "Recorded mark zone mismatch at row $($i + 1) in $path."
        Assert-Equal $fields[1] $expectedMark.Name "Recorded mark name mismatch at row $($i + 1) in $path."
        Assert-Equal $fields[2] $recordedMark.x "Recorded mark x mismatch for $($expectedMark.Name) in $path."
        Assert-Equal $fields[3] $recordedMark.z "Recorded mark z mismatch for $($expectedMark.Name) in $path."
        Assert-Equal $fields[4] $recordedMark.y "Recorded mark y mismatch for $($expectedMark.Name) in $path."
        Assert-Equal $fields[5] $expectedMark.Kind "Recorded mark kind mismatch for $($expectedMark.Name) in $path."
        Assert-Equal $fields[6] $sourceTag "Recorded mark source mismatch for $($expectedMark.Name) in $path."
        Assert-Equal $fields[7] 'proven' "Recorded mark confidence mismatch for $($expectedMark.Name) in $path."
        Assert-Equal $fields[8] 'recorded-survey-20260712' "Recorded mark section mismatch for $($expectedMark.Name) in $path."
        Assert-True ($fields[5] -ne 'area') "Survey area anchor was exported as a destination in $path."
    }
}

Assert-Equal @($graphPaths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } | Select-Object -Unique).Count 1 'Recorded graph copies are not byte-identical.'
Assert-Equal @($markPaths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } | Select-Object -Unique).Count 1 'Recorded mark copies are not byte-identical.'
Assert-Equal @($modulePaths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } | Select-Object -Unique).Count 1 'Recorded graph module copies are not byte-identical.'

$source = Get-Content -LiteralPath $sourceLuaPath -Raw
Assert-True ($source -match "nav_recorded_marks_path\s*=\s*accessxi_paths\.addon_path\('data', 'ffxi-nav-recorded-marks\.tsv'\)") 'Main addon lacks the recorded-mark data path.'
Assert-True ($source -match "nav_recorded_survey_path\s*=\s*accessxi_paths\.addon_path\('data', 'ffxi-nav-recorded-survey\.tsv'\)") 'Main addon lacks the recorded-survey data path.'
Assert-True ($source -match "nav_load_points_file\(accessxi\.nav_recorded_marks_path, 'live-route-recording'\)") 'Recorded marks are not loaded as navigation destinations.'
Assert-True ($source -match "load_code_module\('recorded_survey_navigation'") 'Recorded-survey routing module is not loaded.'
Assert-True (-not ($source -match "load_code_module\('recorded_survey_navigation'[\s\S]*?if \(type\(accessxi\.nav_recorded_survey_load\) == 'function'\) then\s*accessxi\.nav_recorded_survey_load\(\);\s*end")) 'Recorded survey must remain lazy during addon load.'
Assert-True ($source -match "route_id:startswith\('lathine-recorded-survey-'\)") 'Recorded-survey routes are not precise overrides.'
Assert-True ($source -match "local route_id = accessxi\.nav_route_points_override_id\(points\);\s*if \(route_id:startswith\('lathine-recorded-survey-'\)\) then\s*return '';\s*end") 'Recorded-survey routes can still be replaced by a live navmesh replan.'
Assert-True ($source -match "function accessxi\.nav_lathine_live_recorded_corridor_handoff\(player, point, current_points\)[\s\S]*?current_id:startswith\('lathine-recorded-survey-'\)[\s\S]*?return empty") 'A slice corridor can still replace an active full recorded survey.'
Assert-True ($source -match "survey_authoritative\s*=\s*current_id:startswith\('lathine-recorded-survey-'\)[\s\S]*?lower_ravine_handoff\s*=\s*\(not collision_authoritative\)[\s\S]*?and\s*\(not survey_authoritative\)") 'A lower-ravine static override can still replace an active full recorded survey.'
$graphCall = $source.IndexOf('accessxi.nav_recorded_survey_route(player, point)')
$corridorCall = $source.IndexOf('accessxi.nav_lathine_recorded_corridor_route(player, point)', $graphCall + 1)
Assert-True ($graphCall -ge 0 -and $corridorCall -gt $graphCall) 'Recorded survey is not consulted before ordinary recorded corridors.'

$moduleSource = Get-Content -LiteralPath $modulePaths[0] -Raw
$graphPathForLua = $graphPaths[0] -replace '\\', '\\'
$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value end
function list_methods:clear() for i = #self, 1, -1 do self[i] = nil end end
function list_methods:contains(value) for _, item in ipairs(self) do if item == value then return true end end return false end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
string.fmt = string.format

accessxi = {
    nav_recorded_survey_path = '$graphPathForLua',
    nav_recorded_survey_loaded = false,
    nav_recorded_survey_nodes = T({}),
}

local function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz
end
local function survey_test_distance_3d(a, b)
    local horizontal = nav_distance(a, b)
    local dy = (tonumber(b.y) or 0) - (tonumber(a.y) or 0)
    return math.sqrt((horizontal * horizontal) + (dy * dy))
end
local function nav_split_tsv(line)
    local parts = T({})
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do parts:append(part) end
    return parts
end
local function nav_clean_field(value) return tostring(value or '') end
local function log_line(_) end

$moduleSource

accessxi.nav_recorded_survey_load()
assert(accessxi.nav_recorded_survey_nodes:len() == 6499, 'Lua module did not load all graph nodes')
local west_anchor = accessxi.nav_recorded_survey_nodes[3985]
local west_anchor_fallback = accessxi.nav_recorded_survey_nodes[4479]
accessxi.nav_route_overrides = T({
    {
        id = 'lathine-recorded-corridor-20260712-west-via-test',
        waypoints = T({
            { zone = 102, x = west_anchor.x, z = west_anchor.z, y = west_anchor.y, name = 'recorded west anchor' },
            { zone = 102, x = -563.557, z = 663.512, y = 0.823, name = 'recorded west exit' },
        }),
    },
    {
        id = 'lathine-recorded-corridor-20260712-west-via-test-fallback',
        waypoints = T({
            { zone = 102, x = west_anchor_fallback.x, z = west_anchor_fallback.z, y = west_anchor_fallback.y, name = 'recorded west fallback anchor' },
            { zone = 102, x = -563.557, z = 663.512, y = 0.823, name = 'recorded west exit' },
        }),
    },
})
function accessxi.nav_load_route_overrides() end
local west_corridor_calls = 0
function accessxi.nav_lathine_recorded_corridor_candidate(player, point, corridor, player_index, direction)
    west_corridor_calls = west_corridor_calls + 1
    assert(player_index == 1 and direction == 1, 'West survey did not follow the recorded corridor forward')
    return T({
        corridor.waypoints[1],
        corridor.waypoints[2],
        { zone = point.zone, x = point.x, z = point.z, y = point.y, name = point.name },
    })
end
local start = { zone = 102, x = -559.850, z = 677.532, y = 0.000, name = 'survey start' }
local finish = { zone = 102, x = 476.342, z = -373.660, y = 23.860, name = 'Cliff path 5 top' }
local route, required, collision_required = accessxi.nav_recorded_survey_route(start, finish)
assert(required == false and collision_required == true and route:len() == 0,
    'ordinary La Theine destination did not yield to full-zone DAT collision terrain')

local current_route, current_route_required, current_collision_required =
    accessxi.nav_recorded_survey_route(
        { zone = 102, x = -434.488, z = 211.434, y = 8.005, name = 'current live start' },
        { zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' })
assert(current_route_required == false and current_collision_required == true
    and current_route:len() == 0,
    'ordinary La Theine destination reused the alternate 4412-to-3904 survey wall path')

local wall_route, wall_route_required, collision_required = accessxi.nav_recorded_survey_route(
    { zone = 102, x = -433.269, z = 224.810, y = 8.088, name = 'live wall position' },
    { zone = 102, x = -481.196, z = 220.547, y = -7.028, name = 'Galaihaurat' })
assert(wall_route_required == false and collision_required == true and wall_route:len() == 0,
    'recorded survey accepted the unsafe reverse 3924-to-3923 wall crossing instead of yielding to DAT terrain')

local missing, missing_required, missing_collision_required = accessxi.nav_recorded_survey_route(start,
    { zone = 102, x = 0, z = 1000, y = 0, name = 'unrecorded destination' })
assert(missing_required == false and missing_collision_required == true and missing:len() == 0,
    'covered player did not yield an unrecorded destination to collision terrain')
local outside, outside_required, outside_collision_required = accessxi.nav_recorded_survey_route(
    { zone = 102, x = 0, z = 1000, y = 0, name = 'outside' }, finish)
assert(outside_required == false and outside_collision_required == true and outside:len() == 0,
    'non-West La Theine destination did not yield consistently to collision terrain')
local west_player = { zone = 102, x = 15.375, z = -288.323, y = 24.309, name = 'live stuck position' }
local west, west_required = accessxi.nav_recorded_survey_route(west_player,
    { zone = 102, x = -558.569, z = 688.049, y = -7.049, name = 'West Ronfaure zone line' })
assert(west_required == true and west:len() > 10,
    'recorded survey did not own the exact live West Ronfaure failure')
assert(west_corridor_calls == 1,
    ('West survey searched %d proven exits instead of stopping at the first connected route'):format(west_corridor_calls))
assert(west[1].survey_node_id == 2225,
    ('West survey matched the wrong shelf node %s'):format(tostring(west[1].survey_node_id)))
local saw_anchor = false
for _, waypoint in ipairs(west) do
    assert(waypoint.route_override_id == 'lathine-recorded-survey-20260712',
        'West route lost authoritative survey identity')
    if waypoint.survey_node_id == 3985 then saw_anchor = true end
end
assert(saw_anchor, 'West survey did not connect to the walked West escape anchor')
assert(math.abs(west[west:len()].x - -558.569) < 0.001 and math.abs(west[west:len()].z - 688.049) < 0.001,
    'West survey lost the existing successful zone-line tail')

print('recorded survey Lua graph behavior ok')
"@

$tempLua = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + '.lua')
try {
    [System.IO.File]::WriteAllText($tempLua, $harness, (New-Object System.Text.UTF8Encoding($false)))
    $output = & $luaExe $tempLua
    $luaExitCode = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $tempLua -Force -ErrorAction SilentlyContinue
}
if ($luaExitCode -ne 0) { throw "Recorded survey Lua regression failed: $output" }

if ($IncludeLive) {
    Assert-Equal @((Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash, (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash | Select-Object -Unique).Count 1 'Source and live main Lua copies are not byte-identical.'
}

Write-Host 'La Theine recorded survey graph checks passed'
Write-Host $output
