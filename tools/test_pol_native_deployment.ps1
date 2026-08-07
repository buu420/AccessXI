param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$InstalledPolRoot = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-ExpectFailure {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -match $Pattern) {
            return
        }
        throw "$Message Unexpected error: $($_.Exception.Message)"
    }
    throw $Message
}

$deployScript = Join-Path $RepoRoot 'tools\deploy_pol_native_asi.ps1'
$rollbackScript = Join-Path $RepoRoot 'tools\rollback_pol_native_asi.ps1'
$stage = Join-Path $RepoRoot 'stage\pol-native'
Assert-True (Test-Path -LiteralPath $deployScript -PathType Leaf) "Deployment script is missing: $deployScript"
Assert-True (Test-Path -LiteralPath $rollbackScript -PathType Leaf) "Rollback script is missing: $rollbackScript"
Assert-True (Test-Path -LiteralPath (Join-Path $stage 'AccessXI.PolNative.asi') -PathType Leaf) 'Build the native prototype stage before testing deployment.'

$testRoot = Join-Path $env:TEMP "accessxi-pol-native-deployment-$PID"
if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

function New-FakePolTree {
    param([string]$Name)
    $root = Join-Path $testRoot $Name
    $scripts = Join-Path $root 'scripts'
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'viewer\com'), $scripts | Out-Null
    Copy-Item -LiteralPath (Join-Path $InstalledPolRoot 'pol.exe') -Destination (Join-Path $root 'pol.exe')
    Copy-Item -LiteralPath (Join-Path $InstalledPolRoot 'viewer\com\app.dll') -Destination (Join-Path $root 'viewer\com\app.dll')
    Copy-Item -LiteralPath (Join-Path $InstalledPolRoot 'ddraw.dll') -Destination (Join-Path $root 'ddraw.dll')
    [System.IO.File]::WriteAllText((Join-Path $scripts 'AccessXI.PolNative.asi'), 'older-native-prototype')
    New-Item -ItemType Directory -Force -Path (Join-Path $scripts 'AccessXI.PolNative') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $scripts 'AccessXI.PolNative\old.txt'), 'older dependency')
    return $root
}

try {
    $root = New-FakePolTree 'normal'
    $backupRoot = Join-Path $testRoot 'backups'
    $polHashBefore = (Get-FileHash -LiteralPath (Join-Path $root 'pol.exe') -Algorithm SHA256).Hash
    $appHashBefore = (Get-FileHash -LiteralPath (Join-Path $root 'viewer\com\app.dll') -Algorithm SHA256).Hash

    & $deployScript -PolRoot $root -StageRoot $stage -BackupRoot $backupRoot -WhatIf
    Assert-True ((Get-Content -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative.asi') -Raw) -eq 'older-native-prototype') '-WhatIf changed the existing native ASI.'
    Assert-True (-not (Test-Path -LiteralPath $backupRoot)) '-WhatIf created a backup directory.'

    & $deployScript -PolRoot $root -StageRoot $stage -BackupRoot $backupRoot
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative.asi') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $stage 'AccessXI.PolNative.asi') -Algorithm SHA256).Hash) 'Deployed native ASI hash mismatch.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative\accessxi_pol_native.dll') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $stage 'AccessXI.PolNative\accessxi_pol_native.dll') -Algorithm SHA256).Hash) 'Deployed hook DLL hash mismatch.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative\prism.dll') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $stage 'AccessXI.PolNative\prism.dll') -Algorithm SHA256).Hash) 'Deployed Prism hash mismatch.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative\old.txt'))) 'Deployment retained a stale private dependency.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'pol.exe') -Algorithm SHA256).Hash -eq $polHashBefore) 'Deployment changed pol.exe.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'viewer\com\app.dll') -Algorithm SHA256).Hash -eq $appHashBefore) 'Deployment changed app.dll.'

    $manifests = @(Get-ChildItem -LiteralPath $backupRoot -Recurse -Filter manifest.json -File)
    Assert-True ($manifests.Count -eq 1) 'Deployment must write exactly one backup manifest.'
    $manifest = Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
    Assert-True ($manifest.polSha256Before -eq $polHashBefore) 'Manifest pol.exe hash mismatch.'
    Assert-True ($manifest.appSha256Before -eq $appHashBefore) 'Manifest app.dll hash mismatch.'
    Assert-True (Test-Path -LiteralPath (Join-Path $manifests[0].DirectoryName 'previous\AccessXI.PolNative.asi')) 'Previous native ASI was not backed up.'
    Assert-True (Test-Path -LiteralPath (Join-Path $manifests[0].DirectoryName 'previous\AccessXI.PolNative\old.txt')) 'Previous native dependency directory was not backed up.'

    & $deployScript -PolRoot $root -StageRoot $stage -BackupRoot $backupRoot
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative.asi') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $stage 'AccessXI.PolNative.asi') -Algorithm SHA256).Hash) 'Second deployment changed native ASI content.'

    & $rollbackScript -PolRoot $root
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative.asi'))) 'Rollback left native ASI active.'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'scripts\AccessXI.PolNative.asi.disabled')) 'Rollback did not preserve disabled native ASI.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'pol.exe') -Algorithm SHA256).Hash -eq $polHashBefore) 'Rollback changed pol.exe.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $root 'viewer\com\app.dll') -Algorithm SHA256).Hash -eq $appHashBefore) 'Rollback changed app.dll.'
    & $rollbackScript -PolRoot $root

    $badRoot = New-FakePolTree 'bad-fingerprint'
    Add-Content -LiteralPath (Join-Path $badRoot 'viewer\com\app.dll') -Value 'corrupt'
    Invoke-ExpectFailure {
        & $deployScript -PolRoot $badRoot -StageRoot $stage -BackupRoot (Join-Path $testRoot 'bad-backups')
    } 'fingerprint|supported' 'Deployment accepted an unreviewed app.dll.'

    $blocker = Join-Path $testRoot 'pol.exe'
    Copy-Item -LiteralPath "$env:SystemRoot\System32\cmd.exe" -Destination $blocker
    $blockerProcess = Start-Process -FilePath $blocker -ArgumentList '/c', 'ping -n 20 127.0.0.1 >nul' -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 100
        Invoke-ExpectFailure {
            & $deployScript -PolRoot (New-FakePolTree 'running-process') -StageRoot $stage -BackupRoot (Join-Path $testRoot 'process-backups')
        } 'running|close' 'Deployment did not reject a running pol.exe process.'
    }
    finally {
        if (-not $blockerProcess.HasExited) {
            Stop-Process -Id $blockerProcess.Id -Force
        }
    }

    'ok: native PlayOnline deployment is bounded, reversible, idempotent, process-safe, and preserves Square Enix binaries.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
