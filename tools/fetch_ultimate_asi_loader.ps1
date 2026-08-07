param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$Version = 'v9.7.2',
    [string]$ArchiveSha256 = '0F34758B30EAA0EFB59F7AE04100DB789914E1A08891B89878B8FDB189C2A7C5',
    [string]$DllSha256 = 'C7277E832F6F07AF64903A99ECEBAB2936260CBF55EDA70787C5D7B2D5B9FE60'
)

$ErrorActionPreference = 'Stop'

function Assert-UnderDirectory {
    param([string]$Path, [string]$Parent, [string]$Message)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
    if (-not $resolvedPath.StartsWith($resolvedParent + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw $Message
    }
}

$root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
$cacheRoot = Join-Path $root 'third_party\Ultimate-ASI-Loader'
$output = Join-Path $cacheRoot "$Version\x86\dinput8.dll"
Assert-UnderDirectory -Path $output -Parent $cacheRoot -Message 'Refusing to stage the ASI loader outside its repo-local cache.'

if (Test-Path -LiteralPath $output -PathType Leaf) {
    $existingHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    if ($existingHash -eq $DllSha256) {
        Get-Item -LiteralPath $output
        return
    }
    throw "Cached Ultimate ASI Loader has an unexpected hash: $existingHash"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AccessXI-UltimateAsiLoader-" + [Guid]::NewGuid().ToString('N'))
$archive = Join-Path $tempRoot 'Ultimate-ASI-Loader.zip'
$expanded = Join-Path $tempRoot 'expanded'
$url = "https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/$Version/Ultimate-ASI-Loader.zip"

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
    $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($archiveHash -ne $ArchiveSha256) {
        throw "Ultimate ASI Loader archive hash mismatch. Expected $ArchiveSha256, got $archiveHash."
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
    $sourceDll = Join-Path $expanded 'dinput8.dll'
    if (-not (Test-Path -LiteralPath $sourceDll -PathType Leaf)) {
        throw 'Official x86 loader archive did not contain dinput8.dll.'
    }
    $dllHash = (Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash
    if ($dllHash -ne $DllSha256) {
        throw "Ultimate ASI Loader DLL hash mismatch. Expected $DllSha256, got $dllHash."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
    Copy-Item -LiteralPath $sourceDll -Destination $output -Force
    Get-Item -LiteralPath $output
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Assert-UnderDirectory -Path $tempRoot -Parent ([System.IO.Path]::GetTempPath()) -Message 'Refusing to clean an unexpected download directory.'
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
