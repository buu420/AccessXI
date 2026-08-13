[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'Release',
    [string]$BuildRoot = '',
    [string]$StageRoot = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-UnderRepo {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $resolvedPath = Resolve-FullPath $Path
    $resolvedRepo = (Resolve-FullPath $Repo).TrimEnd('\')
    if (-not $resolvedPath.StartsWith($resolvedRepo + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw $Message
    }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
$RepoRoot = (Resolve-FullPath $RepoRoot).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    $BuildRoot = Join-Path $RepoRoot 'build-collision'
}
if ([string]::IsNullOrWhiteSpace($StageRoot)) {
    $StageRoot = Join-Path $RepoRoot 'stage\collision-native'
}
$BuildRoot = Resolve-FullPath $BuildRoot
$StageRoot = Resolve-FullPath $StageRoot

Assert-UnderRepo -Path $BuildRoot -Repo $RepoRoot -Message "Collision build root escapes the repository: $BuildRoot"
Assert-UnderRepo -Path $StageRoot -Repo $RepoRoot -Message "Collision stage root escapes the repository: $StageRoot"

$cmakeLists = Join-Path $RepoRoot 'CMakeLists.txt'
$fetchDependencies = Join-Path $RepoRoot 'tools\fetch_collision_dependencies.ps1'
$manifestPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\data\collision-native-manifest.tsv'
foreach ($required in @($cmakeLists, $fetchDependencies, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required collision build input is missing: $required"
    }
}
if (-not (Get-Command cmake.exe -ErrorAction SilentlyContinue)) {
    throw 'cmake.exe is required to build collision navigation.'
}

$manifestRows = @(Import-Csv -LiteralPath $manifestPath -Delimiter "`t")
if ($manifestRows.Count -ne 1) {
    throw "Collision manifest must contain exactly one payload row: $manifestPath"
}
$manifestRow = $manifestRows[0]
$expectedRelativePath = 'third_party/collision/accessxi_collision_native.dll'
if ([string]$manifestRow.relative_path -ne $expectedRelativePath) {
    throw "Collision manifest path mismatch. Expected $expectedRelativePath, got $($manifestRow.relative_path)."
}
$expectedHash = ([string]$manifestRow.sha256).ToUpperInvariant()
if ($expectedHash -notmatch '^[0-9A-F]{64}$') {
    throw "Collision manifest SHA-256 is invalid: $($manifestRow.sha256)"
}

$recastHeader = Join-Path $RepoRoot 'external\recastnavigation\Recast\Include\Recast.h'
$bulletHeader = Join-Path $RepoRoot 'external\bullet3\src\btBulletCollisionCommon.h'
if (-not (Test-Path -LiteralPath $recastHeader -PathType Leaf) -or
    -not (Test-Path -LiteralPath $bulletHeader -PathType Leaf)) {
    & $fetchDependencies -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to fetch pinned collision dependencies (exit $LASTEXITCODE)."
    }
}

& cmake.exe -S $RepoRoot -B $BuildRoot -A Win32 -DACCESSXI_COLLISION_ONLY=ON
if ($LASTEXITCODE -ne 0) {
    throw "Collision native configure failed (cmake exit $LASTEXITCODE)."
}
& cmake.exe --build $BuildRoot --config $Configuration --target accessxi_collision_native
if ($LASTEXITCODE -ne 0) {
    throw "Collision native build failed (cmake exit $LASTEXITCODE)."
}

$builtDll = Join-Path $BuildRoot "bin\$Configuration\accessxi_collision_native.dll"
if (-not (Test-Path -LiteralPath $builtDll -PathType Leaf)) {
    throw "Collision native build did not produce its DLL: $builtDll"
}
$builtHash = (Get-FileHash -LiteralPath $builtDll -Algorithm SHA256).Hash
if ($builtHash -ne $expectedHash) {
    throw "Collision native DLL hash does not match the manifest. Expected $expectedHash, got $builtHash. Update the manifest only after reviewing the native change."
}

New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null
$stagedDll = Join-Path $StageRoot 'accessxi_collision_native.dll'
Copy-Item -LiteralPath $builtDll -Destination $stagedDll -Force
$stagedHash = (Get-FileHash -LiteralPath $stagedDll -Algorithm SHA256).Hash
if ($stagedHash -ne $expectedHash) {
    throw "Staged collision native DLL hash mismatch. Expected $expectedHash, got $stagedHash."
}

[pscustomobject]@{
    BuiltDll = $builtDll
    StagedDll = $stagedDll
    Sha256 = $stagedHash
    AbiVersion = [string]$manifestRow.abi_version
    SettingsSha256 = [string]$manifestRow.settings_sha256
}
