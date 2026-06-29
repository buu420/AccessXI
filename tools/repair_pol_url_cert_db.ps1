param(
    [string]$PolRoot = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer'
)

$ErrorActionPreference = 'Stop'

$sourceDirectory = Join-Path $PolRoot 'default\usr\all\url'
$destinationDirectory = Join-Path $PolRoot 'usr\all\url'
$knownInstallerKeyPaths = @('cert.db', 'rdthosts.bin', 'cache\dcfat0.bin')
$repairedFiles = @()

if (-not (Test-Path -LiteralPath $sourceDirectory)) {
    throw "Missing source URL directory: $sourceDirectory"
}

foreach ($relativePath in $knownInstallerKeyPaths) {
    $source = Join-Path $sourceDirectory $relativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing source URL file: $source"
    }
}

$resolvedSourceDirectory = ([System.IO.Path]::GetFullPath($sourceDirectory)).TrimEnd('\')
New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse -Force) {
    $relativePath = $sourceFile.FullName.Substring($resolvedSourceDirectory.Length).TrimStart('\')
    if ($relativePath -eq '') {
        continue
    }

    $destination = Join-Path $destinationDirectory $relativePath
    if (-not (Test-Path -LiteralPath $destination)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destination -Force
        $repairedFiles += $relativePath
    }

    if (-not (Test-Path -LiteralPath $destination)) {
        throw "Repair failed; destination URL file is still missing: $destination"
    }
}

Write-Output ('ok: repaired POL URL files: ' + (($repairedFiles | ForEach-Object { $_ }) -join ', '))
