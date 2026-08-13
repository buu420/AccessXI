[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$DllPath = '',
    [string]$ManifestPath = ''
)

$ErrorActionPreference = 'Stop'

function Read-UInt16 {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset -lt 0 -or ($Offset + 2) -gt $Bytes.Length) {
        throw "PE uint16 read is out of bounds at $Offset."
    }
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-UInt32 {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset -lt 0 -or ($Offset + 4) -gt $Bytes.Length) {
        throw "PE uint32 read is out of bounds at $Offset."
    }
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Convert-RvaToFileOffset {
    param(
        [byte[]]$Bytes,
        [int]$SectionTableOffset,
        [int]$SectionCount,
        [uint32]$Rva
    )

    for ($index = 0; $index -lt $SectionCount; $index++) {
        $section = $SectionTableOffset + ($index * 40)
        $virtualSize = Read-UInt32 $Bytes ($section + 8)
        $virtualAddress = Read-UInt32 $Bytes ($section + 12)
        $rawSize = Read-UInt32 $Bytes ($section + 16)
        $rawOffset = Read-UInt32 $Bytes ($section + 20)
        $span = [Math]::Max([uint64]$virtualSize, [uint64]$rawSize)
        if ([uint64]$Rva -ge [uint64]$virtualAddress -and
            [uint64]$Rva -lt ([uint64]$virtualAddress + $span)) {
            return [int]([uint64]$rawOffset + ([uint64]$Rva - [uint64]$virtualAddress))
        }
    }
    throw ('PE RVA 0x{0:X8} is not contained in a section.' -f $Rva)
}

function Get-PeDebugTypes {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x100 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "Collision DLL is not a valid PE image: $Path"
    }
    $peOffset = [int](Read-UInt32 $bytes 0x3C)
    if ((Read-UInt32 $bytes $peOffset) -ne 0x00004550) {
        throw "Collision DLL has no PE signature: $Path"
    }
    $sectionCount = [int](Read-UInt16 $bytes ($peOffset + 6))
    $optionalSize = [int](Read-UInt16 $bytes ($peOffset + 20))
    $optionalOffset = $peOffset + 24
    $magic = Read-UInt16 $bytes $optionalOffset
    $dataDirectoryOffset = switch ($magic) {
        0x10B { $optionalOffset + 96 }
        0x20B { $optionalOffset + 112 }
        default { throw ('Unsupported PE optional-header magic 0x{0:X4}.' -f $magic) }
    }
    $debugDirectory = $dataDirectoryOffset + (6 * 8)
    $debugRva = Read-UInt32 $bytes $debugDirectory
    $debugSize = Read-UInt32 $bytes ($debugDirectory + 4)
    if ($debugRva -eq 0 -or $debugSize -lt 28 -or ($debugSize % 28) -ne 0) {
        return @()
    }
    $sectionTable = $optionalOffset + $optionalSize
    $debugOffset = Convert-RvaToFileOffset $bytes $sectionTable $sectionCount $debugRva
    $types = @()
    for ($offset = 0; $offset -lt $debugSize; $offset += 28) {
        $types += [uint32](Read-UInt32 $bytes ($debugOffset + $offset + 12))
    }
    return @($types)
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($DllPath)) {
    $DllPath = Join-Path $RepoRoot 'stage\collision-native\accessxi_collision_native.dll'
}
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\data\collision-native-manifest.tsv'
}
if (-not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
    throw "Collision DLL is missing: $DllPath"
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Collision manifest is missing: $ManifestPath"
}

$debugTypes = @(Get-PeDebugTypes -Path $DllPath)
if ($debugTypes -notcontains 16) {
    throw 'Collision Release DLL is not reproducibly linked: IMAGE_DEBUG_TYPE_REPRO is absent.'
}

$rows = @(Import-Csv -LiteralPath $ManifestPath -Delimiter "`t")
if ($rows.Count -ne 1) {
    throw 'Collision manifest must contain exactly one payload row.'
}
$expectedHash = ([string]$rows[0].sha256).ToUpperInvariant()
$actualHash = (Get-FileHash -LiteralPath $DllPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Reproducible collision DLL hash mismatch. Expected $expectedHash, got $actualHash."
}

Write-Output "Collision native reproducibility checks passed: $actualHash"
