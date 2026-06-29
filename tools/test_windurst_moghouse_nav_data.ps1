$ErrorActionPreference = 'Stop'

$destinationsPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv'
$moghousePath = 'C:\Users\buu42\AccessXI\third_party\LandSandBoat-server\scripts\globals\moghouse.lua'

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

$destinations = Get-Content -LiteralPath $destinationsPath -Raw
$moghouse = Get-Content -LiteralPath $moghousePath -Raw

$expectedRows = @(
    @{
        Zone = '238'
        Constant = 'WINDURST_WATERS'
        LsbPattern = '\[xi\.zone\.WINDURST_WATERS\]\s*=\s*\{\s*\[1\]\s*=\s*\{\s*160,\s*-2\.65,\s*-53\.7,'
        Row = "238`tMog House entrance`t160.000`t-53.700`t-2.650`tarea`tlsb-moghouse-exits`tuntested`twindurst-moghouse-2026-06-21"
    },
    @{
        Zone = '239'
        Constant = 'WINDURST_WALLS'
        LsbPattern = '\[xi\.zone\.WINDURST_WALLS\]\s*=\s*\{\s*\[1\]\s*=\s*\{\s*-249,\s*-2\.65,\s*-120,'
        Row = "239`tMog House entrance`t-249.000`t-120.000`t-2.650`tarea`tlsb-moghouse-exits`tuntested`twindurst-moghouse-2026-06-21"
    },
    @{
        Zone = '240'
        Constant = 'PORT_WINDURST'
        LsbPattern = '\[xi\.zone\.PORT_WINDURST\]\s*=\s*\{\s*\[1\]\s*=\s*\{\s*198,\s*-15\.65,\s*258,'
        Row = "240`tMog House entrance`t198.000`t258.000`t-15.650`tarea`tlsb-moghouse-exits`tuntested`twindurst-moghouse-2026-06-21"
    },
    @{
        Zone = '241'
        Constant = 'WINDURST_WOODS'
        LsbPattern = '\[xi\.zone\.WINDURST_WOODS\]\s*=\s*\{\s*\[1\]\s*=\s*\{\s*-130,\s*-7\.65,\s*40,'
        Row = "241`tMog House entrance`t-130.000`t40.000`t-7.650`tarea`tlsb-moghouse-exits`tuntested`twindurst-moghouse-2026-06-21"
    }
)

foreach ($expected in $expectedRows) {
    Assert-Match `
        -Text $moghouse `
        -Pattern $expected.LsbPattern `
        -Message "Expected LSB moghouse.lua to expose $($expected.Constant) Mog House exit coordinates."

    Assert-Match `
        -Text $destinations `
        -Pattern "(?m)^$([regex]::Escape($expected.Row))`r?$" `
        -Message "Expected Windurst zone $($expected.Zone) Mog House entrance destination from LSB moghouse exits."

    $exactMatches = @($destinations -split "`r?`n" | Where-Object { $_ -eq $expected.Row })
    if ($exactMatches.Count -ne 1) {
        throw "Expected exactly one exact Windurst zone $($expected.Zone) Mog House entrance row."
    }
}

Write-Host 'windurst moghouse nav data checks ok'
