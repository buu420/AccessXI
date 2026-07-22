[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$PolRoot = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer'
)

$ErrorActionPreference = 'Stop'

function Assert-ChildPath {
    param([string]$Path, [string]$Parent, [string]$Description)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $resolvedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
    if ($resolvedPath -eq $resolvedParent -or
        -not $resolvedPath.StartsWith($resolvedParent + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes its intended parent: $resolvedPath"
    }
    return $resolvedPath
}

if (@(Get-Process -Name pol -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'PlayOnline Viewer is running. Close pol.exe before rolling back the native accessibility prototype.'
}

$polDirectory = [System.IO.Path]::GetFullPath($PolRoot).TrimEnd('\')
$polExe = Join-Path $polDirectory 'pol.exe'
$appDll = Join-Path $polDirectory 'viewer\com\app.dll'
$scriptsDirectory = Join-Path $polDirectory 'scripts'
foreach ($required in @($polExe, $appDll, $scriptsDirectory)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required rollback path is missing: $required"
    }
}

$polHashBefore = (Get-FileHash -LiteralPath $polExe -Algorithm SHA256).Hash
$appHashBefore = (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash
$nativeAsi = Assert-ChildPath (Join-Path $scriptsDirectory 'AccessXI.PolNative.asi') $scriptsDirectory 'Native ASI path'
$disabledNativeAsi = Assert-ChildPath "$nativeAsi.disabled" $scriptsDirectory 'Disabled native ASI path'
$reloadedAsi = Assert-ChildPath (Join-Path $scriptsDirectory 'AccessXI.PolReloadedBootstrap.asi') $scriptsDirectory 'Reloaded ASI path'
$disabledReloadedAsi = Assert-ChildPath "$reloadedAsi.disabled" $scriptsDirectory 'Disabled Reloaded ASI path'

if ($WhatIfPreference) {
    Write-Output "What if: disable $nativeAsi and restore $reloadedAsi from $disabledReloadedAsi"
    return
}

if (Test-Path -LiteralPath $nativeAsi -PathType Leaf) {
    if (Test-Path -LiteralPath $disabledNativeAsi -PathType Leaf) {
        $priorDisabled = Assert-ChildPath ($disabledNativeAsi + '.previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) $scriptsDirectory 'Prior disabled native ASI path'
        Move-Item -LiteralPath $disabledNativeAsi -Destination $priorDisabled
    }
    Move-Item -LiteralPath $nativeAsi -Destination $disabledNativeAsi
}

if (-not (Test-Path -LiteralPath $reloadedAsi -PathType Leaf) -and
    (Test-Path -LiteralPath $disabledReloadedAsi -PathType Leaf)) {
    Move-Item -LiteralPath $disabledReloadedAsi -Destination $reloadedAsi
}

if ((Get-FileHash -LiteralPath $polExe -Algorithm SHA256).Hash -ne $polHashBefore -or
    (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash -ne $appHashBefore) {
    throw 'Rollback changed a Square Enix binary.'
}

Write-Output 'Native PlayOnline accessibility prototype is disabled; the Reloaded bootstrap is restored when its disabled copy was present.'
