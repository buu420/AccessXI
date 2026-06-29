param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'

function Assert-DoesNotContain {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

function Test-ByteSequence {
    param(
        [byte[]]$Haystack,
        [byte[]]$Needle
    )

    if ($Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) {
        return $false
    }

    for ($i = 0; $i -le $Haystack.Length - $Needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) {
                $match = $false
                break
            }
        }

        if ($match) {
            return $true
        }
    }

    return $false
}

function Assert-BinaryDoesNotContainString {
    param(
        [string]$Path,
        [string]$Needle,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encodings = @(
        [System.Text.Encoding]::ASCII,
        [System.Text.Encoding]::UTF8,
        [System.Text.Encoding]::Unicode
    )

    foreach ($encoding in $encodings) {
        if (Test-ByteSequence $bytes $encoding.GetBytes($Needle)) {
            throw $Message
        }
    }
}

$modSourcePath = Join-Path $RepoRoot 'src\AccessXI.PolReloaded\Mod.cs'
$stagedModDll = Join-Path $RepoRoot 'external\Reloaded-II\Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll'

if (-not (Test-Path -LiteralPath $modSourcePath)) {
    throw "Missing Reloaded-II managed mod source: $modSourcePath"
}

$modSource = Get-Content -LiteralPath $modSourcePath -Raw

$bannedManagedFocusStrings = @(
    'NativeMonitorLogPath',
    'StartNativeFocusLogWorker',
    'PRELOGIN_ARROWPROBE',
    'ShouldSuppressNativeQueueSpeech',
    'AccessXI_POL_RELOADED_NATIVE_FOCUS',
    'arrowprobe-speak',
    'log-tail-started'
)

foreach ($banned in $bannedManagedFocusStrings) {
    Assert-DoesNotContain $modSource ([regex]::Escape($banned)) "Managed POL mod source must not contain stale diagnostic speech path: $banned"
    Assert-BinaryDoesNotContainString $stagedModDll $banned "Staged Reloaded POL mod DLL contains stale diagnostic speech path: $banned"
}

'ok: Reloaded managed POL mod has no diagnostic-log speech tailer.'
