param(
    [string]$RecordingPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv',
    [string]$SessionId = '20260712-170700-z102'
)

$ErrorActionPreference = 'Stop'

$sourceTag = 'live-route-recording-20260712-170700-z102'
$graphPaths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-recorded-survey.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-recorded-survey.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-recorded-survey.tsv'
)
$markPaths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-recorded-marks.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-recorded-marks.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-recorded-marks.tsv'
)

$rows = @(Import-Csv -LiteralPath $RecordingPath -Delimiter "`t" |
    Where-Object { $_.session -eq $SessionId } |
    Sort-Object { [int]$_.seq })
if ($rows.Count -ne 6499) {
    throw "Expected 6499 rows for $SessionId; found $($rows.Count)."
}
if (@($rows | Where-Object event -eq 'point').Count -ne 6469) {
    throw 'Friend-walk movement count is not 6469.'
}
if (@($rows | Where-Object event -eq 'mark').Count -ne 28) {
    throw 'Friend-walk mark count is not 28.'
}
if (@($rows.zone | Select-Object -Unique).Count -ne 1 -or $rows[0].zone -ne '102') {
    throw 'Recorded survey must be one continuous La Theine session.'
}

$neighbors = @()
for ($i = 0; $i -lt $rows.Count; $i++) {
    $neighbors += ,([System.Collections.Generic.HashSet[int]]::new())
}
for ($i = 1; $i -lt $rows.Count; $i++) {
    $dx = [double]$rows[$i].x - [double]$rows[$i - 1].x
    $dz = [double]$rows[$i].z - [double]$rows[$i - 1].z
    $dy = [double]$rows[$i].y - [double]$rows[$i - 1].y
    $horizontal = [Math]::Sqrt(($dx * $dx) + ($dz * $dz))
    $threeDimensional = [Math]::Sqrt(($horizontal * $horizontal) + ($dy * $dy))
    if ($horizontal -gt 4.0 -or $threeDimensional -gt 6.0) {
        throw "Unsafe raw discontinuity between nodes $i and $($i + 1): horizontal=$horizontal threeD=$threeDimensional."
    }
    [void]$neighbors[$i - 1].Add($i + 1)
    [void]$neighbors[$i].Add($i)
}

$cellSize = 0.5
$buckets = @{}
$reunionCount = 0
for ($i = 0; $i -lt $rows.Count; $i++) {
    $x = [double]$rows[$i].x
    $z = [double]$rows[$i].z
    $y = [double]$rows[$i].y
    $bucketX = [Math]::Floor($x / $cellSize)
    $bucketZ = [Math]::Floor($z / $cellSize)
    $bestIndex = -1
    $bestDistance = [double]::PositiveInfinity

    foreach ($offsetX in -1..1) {
        foreach ($offsetZ in -1..1) {
            $key = "$($bucketX + $offsetX):$($bucketZ + $offsetZ)"
            if (-not $buckets.ContainsKey($key)) {
                continue
            }
            foreach ($candidateIndex in $buckets[$key]) {
                if (($i - $candidateIndex) -le 10) {
                    continue
                }
                $dx = $x - [double]$rows[$candidateIndex].x
                $dz = $z - [double]$rows[$candidateIndex].z
                $dy = $y - [double]$rows[$candidateIndex].y
                $horizontal = [Math]::Sqrt(($dx * $dx) + ($dz * $dz))
                $vertical = [Math]::Abs($dy)
                if ($horizontal -le 0.5 -and $vertical -le 0.75) {
                    $distance = [Math]::Sqrt(($horizontal * $horizontal) + ($vertical * $vertical))
                    if ($distance -lt $bestDistance) {
                        $bestDistance = $distance
                        $bestIndex = $candidateIndex
                    }
                }
            }
        }
    }

    if ($bestIndex -ge 0) {
        [void]$neighbors[$i].Add($bestIndex + 1)
        [void]$neighbors[$bestIndex].Add($i + 1)
        $reunionCount++
    }

    $ownKey = "${bucketX}:${bucketZ}"
    if (-not $buckets.ContainsKey($ownKey)) {
        $buckets[$ownKey] = [System.Collections.Generic.List[int]]::new()
    }
    $buckets[$ownKey].Add($i)
}
if ($reunionCount -ne 64) {
    throw "Expected 64 bounded reunion edges; generated $reunionCount."
}

function Clean-TsvField {
    param([object]$Value)
    return ([string]$Value).Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' ')
}

$graph = [System.Text.StringBuilder]::new()
[void]$graph.AppendLine("survey_id`tzone`tnode_id`tsequence`tx`tz`ty`tevent`tlabel`tneighbors`tsource`tconfidence")
for ($i = 0; $i -lt $rows.Count; $i++) {
    $neighborText = (@($neighbors[$i]) | Sort-Object) -join ','
    $fields = @(
        $SessionId,
        $rows[$i].zone,
        [string]($i + 1),
        $rows[$i].seq,
        $rows[$i].x,
        $rows[$i].z,
        $rows[$i].y,
        (Clean-TsvField $rows[$i].event),
        (Clean-TsvField $rows[$i].label),
        $neighborText,
        $sourceTag,
        'proven'
    )
    [void]$graph.AppendLine(($fields -join "`t"))
}

$markDefinitions = @(
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

$marks = [System.Text.StringBuilder]::new()
foreach ($definition in $markDefinitions) {
    $row = $rows | Where-Object { [int]$_.seq -eq $definition.Sequence } | Select-Object -First 1
    if ($null -eq $row -or $row.event -ne 'mark') {
        throw "Missing recorded mark sequence $($definition.Sequence)."
    }
    $fields = @(
        '102',
        (Clean-TsvField $definition.Name),
        $row.x,
        $row.z,
        $row.y,
        $definition.Kind,
        $sourceTag,
        'proven',
        'recorded-survey-20260712'
    )
    [void]$marks.AppendLine(($fields -join "`t"))
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
foreach ($path in $graphPaths) {
    [System.IO.File]::WriteAllText($path, $graph.ToString(), $utf8NoBom)
}
foreach ($path in $markPaths) {
    [System.IO.File]::WriteAllText($path, $marks.ToString(), $utf8NoBom)
}

Write-Host "generated recorded survey rows=$($rows.Count) marks=$($markDefinitions.Count) reunions=$reunionCount"
