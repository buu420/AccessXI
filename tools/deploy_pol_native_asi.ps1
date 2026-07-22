[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$PolRoot = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer',
    [string]$StageRoot = 'C:\Users\buu42\AccessXI\stage\pol-native',
    [string]$BackupRoot = "$env:USERPROFILE\AccessXI\backups\pol-native"
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

if (-not ('AccessXiPolNativeFingerprint' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;

public static class AccessXiPolNativeFingerprint
{
    public static ulong Compute(string path)
    {
        ulong hash = 14695981039346656037UL;
        byte[] buffer = new byte[32768];
        using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        {
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int index = 0; index < read; index++)
                {
                    hash ^= buffer[index];
                    hash *= 1099511628211UL;
                }
            }
        }
        return hash;
    }
}
'@
}

if (@(Get-Process -Name pol -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'PlayOnline Viewer is running. Close pol.exe before deploying the native accessibility prototype.'
}

$polDirectory = [System.IO.Path]::GetFullPath($PolRoot).TrimEnd('\')
$stageDirectory = [System.IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
$polExe = Join-Path $polDirectory 'pol.exe'
$appDll = Join-Path $polDirectory 'viewer\com\app.dll'
$asiProxy = Join-Path $polDirectory 'ddraw.dll'
$scriptsDirectory = Join-Path $polDirectory 'scripts'
$stageAsi = Join-Path $stageDirectory 'AccessXI.PolNative.asi'
$stageHook = Join-Path $stageDirectory 'AccessXI.PolNative\accessxi_pol_native.dll'
$stagePrism = Join-Path $stageDirectory 'AccessXI.PolNative\prism.dll'

foreach ($required in @($polExe, $appDll, $asiProxy, $stageAsi, $stageHook, $stagePrism)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required deployment file is missing: $required"
    }
}

$appInfo = Get-Item -LiteralPath $appDll
$appFnv64 = [AccessXiPolNativeFingerprint]::Compute($appDll)
if ($appInfo.Length -ne 4335104 -or $appFnv64 -ne [UInt64]0x07E88E8067FEF6CC) {
    throw ('PlayOnline app.dll is not the reviewed supported build. size={0} fnv64={1:X16}' -f $appInfo.Length, $appFnv64)
}

$polHashBefore = (Get-FileHash -LiteralPath $polExe -Algorithm SHA256).Hash
$appHashBefore = (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash

$nativeAsi = Assert-ChildPath (Join-Path $scriptsDirectory 'AccessXI.PolNative.asi') $scriptsDirectory 'Native ASI path'
$nativeDependencies = Assert-ChildPath (Join-Path $scriptsDirectory 'AccessXI.PolNative') $scriptsDirectory 'Native dependency path'
$reloadedAsi = Assert-ChildPath (Join-Path $scriptsDirectory 'AccessXI.PolReloadedBootstrap.asi') $scriptsDirectory 'Reloaded ASI path'
$disabledReloadedAsi = Assert-ChildPath "$reloadedAsi.disabled" $scriptsDirectory 'Disabled Reloaded ASI path'

if ($WhatIfPreference) {
    Write-Output "What if: disable $reloadedAsi, deploy $nativeAsi, and replace $nativeDependencies from $stageDirectory"
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backupSession = Join-Path ([System.IO.Path]::GetFullPath($BackupRoot)) ("$timestamp-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$previousDirectory = Join-Path $backupSession 'previous'
New-Item -ItemType Directory -Force -Path $previousDirectory | Out-Null

if (Test-Path -LiteralPath $nativeAsi -PathType Leaf) {
    Copy-Item -LiteralPath $nativeAsi -Destination (Join-Path $previousDirectory 'AccessXI.PolNative.asi') -Force
}
if (Test-Path -LiteralPath $nativeDependencies -PathType Container) {
    Copy-Item -LiteralPath $nativeDependencies -Destination (Join-Path $previousDirectory 'AccessXI.PolNative') -Recurse -Force
}
if (Test-Path -LiteralPath $reloadedAsi -PathType Leaf) {
    Copy-Item -LiteralPath $reloadedAsi -Destination (Join-Path $previousDirectory 'AccessXI.PolReloadedBootstrap.asi') -Force
}
if (Test-Path -LiteralPath $disabledReloadedAsi -PathType Leaf) {
    Copy-Item -LiteralPath $disabledReloadedAsi -Destination (Join-Path $previousDirectory 'AccessXI.PolReloadedBootstrap.asi.disabled') -Force
}

if (Test-Path -LiteralPath $reloadedAsi -PathType Leaf) {
    if (Test-Path -LiteralPath $disabledReloadedAsi -PathType Leaf) {
        Remove-Item -LiteralPath $disabledReloadedAsi -Force
    }
    Move-Item -LiteralPath $reloadedAsi -Destination $disabledReloadedAsi
}

if (Test-Path -LiteralPath $nativeAsi -PathType Leaf) {
    Remove-Item -LiteralPath $nativeAsi -Force
}
if (Test-Path -LiteralPath $nativeDependencies -PathType Container) {
    $null = Assert-ChildPath $nativeDependencies $scriptsDirectory 'Native dependency cleanup path'
    Remove-Item -LiteralPath $nativeDependencies -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $nativeDependencies | Out-Null
Copy-Item -LiteralPath $stageAsi -Destination $nativeAsi -Force
Copy-Item -LiteralPath $stageHook -Destination (Join-Path $nativeDependencies 'accessxi_pol_native.dll') -Force
Copy-Item -LiteralPath $stagePrism -Destination (Join-Path $nativeDependencies 'prism.dll') -Force

$manifest = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    polRoot = $polDirectory
    stageRoot = $stageDirectory
    polSha256Before = $polHashBefore
    appSha256Before = $appHashBefore
    appSize = [Int64]$appInfo.Length
    appFnv64 = ('{0:X16}' -f $appFnv64)
    nativeAsiSha256 = (Get-FileHash -LiteralPath $nativeAsi -Algorithm SHA256).Hash
    nativeHookSha256 = (Get-FileHash -LiteralPath (Join-Path $nativeDependencies 'accessxi_pol_native.dll') -Algorithm SHA256).Hash
    prismSha256 = (Get-FileHash -LiteralPath (Join-Path $nativeDependencies 'prism.dll') -Algorithm SHA256).Hash
    reloadedBootstrapDisabled = (Test-Path -LiteralPath $disabledReloadedAsi -PathType Leaf)
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupSession 'manifest.json') -Encoding UTF8

if ((Get-FileHash -LiteralPath $nativeAsi -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $stageAsi -Algorithm SHA256).Hash) {
    throw 'Deployed native ASI hash does not match the staged prototype.'
}
if ((Get-FileHash -LiteralPath (Join-Path $nativeDependencies 'accessxi_pol_native.dll') -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $stageHook -Algorithm SHA256).Hash) {
    throw 'Deployed native hook DLL hash does not match the staged prototype.'
}
if ((Get-FileHash -LiteralPath (Join-Path $nativeDependencies 'prism.dll') -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $stagePrism -Algorithm SHA256).Hash) {
    throw 'Deployed Prism DLL hash does not match the staged prototype.'
}
if ((Get-FileHash -LiteralPath $polExe -Algorithm SHA256).Hash -ne $polHashBefore -or
    (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash -ne $appHashBefore) {
    throw 'Deployment changed a Square Enix binary; stop and restore from backup.'
}

Write-Output "Native PlayOnline accessibility prototype deployed. Backup manifest: $(Join-Path $backupSession 'manifest.json')"
