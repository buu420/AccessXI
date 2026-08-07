$ErrorActionPreference = 'Stop'

$paths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
)

$working = "231`tWest Ronfaure zone line`t-252.158`t43.913`t1.663`tarea`tlsb-san-doria-zoneline`tgenerated`tsan-doria"
$watchtower = "231`tWatchtower entrance`t-238.702`t105.961`t-9.433`tarea`tlsb-san-doria-zoneline`tgenerated`tsan-doria"
$oldDuplicate = "231`tWest Ronfaure zone line`t-238.702`t105.961`t-9.433`tarea`tlsb-san-doria-zoneline`tgenerated`tsan-doria"

foreach ($path in $paths) {
    $text = Get-Content -LiteralPath $path -Raw
    if (-not $text.Contains($working)) {
        throw "Missing working West Ronfaure entrance in $path"
    }
    if (-not $text.Contains($watchtower)) {
        throw "Missing Watchtower entrance in $path"
    }
    if ($text.Contains($oldDuplicate)) {
        throw "Watchtower coordinate still has duplicate West Ronfaure label in $path"
    }
}

$hashes = $paths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash }
if (($hashes | Sort-Object -Unique).Count -ne 1) {
    throw 'Destination data copies are not synchronized.'
}

Write-Host 'West Ronfaure entrance label checks ok'
