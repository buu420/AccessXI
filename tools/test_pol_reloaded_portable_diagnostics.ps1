param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContainsLiteral {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )
    if ($Text.Contains($Needle)) {
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
    foreach ($encoding in @([System.Text.Encoding]::ASCII, [System.Text.Encoding]::UTF8, [System.Text.Encoding]::Unicode)) {
        if (Test-ByteSequence -Haystack $bytes -Needle ($encoding.GetBytes($Needle))) {
            throw $Message
        }
    }
}

$managedSourcePath = Join-Path $RepoRoot 'src\AccessXI.PolReloaded\Mod.cs'
$bridgeSourcePath = Join-Path $RepoRoot 'src\AccessXI.PolSpeechBridge\Program.cs'
$nativeSourcePath = Join-Path $RepoRoot 'src\accessxi_pol.cpp'
$stagedReloadedMod = Join-Path $RepoRoot 'external\Reloaded-II\Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll'
$stagedSpeechBridgeDll = Join-Path $RepoRoot 'external\Reloaded-II\Mods\AccessXI.PolReloaded\AccessXI.PolSpeechBridge.dll'
$stagedSpeechBridgeExe = Join-Path $RepoRoot 'external\Reloaded-II\Mods\AccessXI.PolReloaded\AccessXI.PolSpeechBridge.exe'
$stagedNativeShim = Join-Path $RepoRoot 'external\Reloaded-II\Mods\AccessXI.PolReloaded\accessxi_pol_native.dll'

foreach ($path in @($managedSourcePath, $bridgeSourcePath, $nativeSourcePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing source file: $path"
    }
}

$managed = Get-Content -LiteralPath $managedSourcePath -Raw
$bridge = Get-Content -LiteralPath $bridgeSourcePath -Raw
$native = Get-Content -LiteralPath $nativeSourcePath -Raw

foreach ($source in @(
    @{ Name = 'Reloaded managed mod'; Text = $managed },
    @{ Name = 'POL speech bridge'; Text = $bridge },
    @{ Name = 'native POL shim'; Text = $native }
)) {
    Assert-NotContainsLiteral $source.Text 'C:\Users\buu42' "$($source.Name) must not contain this machine's literal user path."
    Assert-NotContainsLiteral $source.Text 'C:\\Users\\buu42' "$($source.Name) must not contain this machine's escaped user path."
    Assert-NotContainsLiteral $source.Text 'C:/Users/buu42' "$($source.Name) must not contain this machine's slash-normalized user path."
}

Assert-Contains $managed 'ACCESSXI_POL_LOG_DIR' 'Reloaded managed mod must pass a portable diagnostic log directory to the native shim.'
Assert-Contains $managed 'ACCESSXI_POL_SPEECH_QUEUE' 'Reloaded managed mod must pass the exact managed speech queue path to the native shim.'
Assert-Contains $managed 'pol-reloaded-startup\.log' 'Reloaded managed mod must keep a stable startup diagnostic log.'
Assert-Contains $managed 'pol-reloaded-speech\.log' 'Reloaded managed mod must keep a stable speech diagnostic log.'
Assert-Contains $managed 'native-diagnostics-configured' 'Reloaded managed mod must log the native diagnostic environment it configured.'
Assert-Contains $managed 'Path\.Combine\(ModDirectory,\s*"prism\.dll"\)' 'Reloaded managed mod must load package-local Prism first.'
Assert-Contains $managed 'prism-load-miss' 'Reloaded managed mod must log failed Prism DLL candidates for friend-machine diagnosis.'
Assert-NotContainsLiteral $managed 'SetForegroundWindow' 'Reloaded managed mod must not foreground the Prism UIA host window during POL startup.'
Assert-NotContainsLiteral $managed 'prism-uia-host-window-foreground' 'Reloaded managed mod must not log or perform Prism UIA host foreground activation during POL startup.'

Assert-Contains $bridge 'ACCESSXI_POL_LOG_DIR' 'POL speech bridge must share the same portable diagnostic log directory contract.'
Assert-Contains $bridge 'ACCESSXI_POL_SPEECH_QUEUE' 'POL speech bridge must share the same portable speech queue contract.'
Assert-Contains $bridge 'Path\.Combine\(AppContext\.BaseDirectory,\s*"prism\.dll"\)' 'POL speech bridge must load package-local Prism first.'

Assert-Contains $native 'ACCESSXI_POL_LOG_DIR' 'Native POL shim must read the portable diagnostic log directory from the managed mod.'
Assert-Contains $native 'ACCESSXI_POL_SPEECH_QUEUE' 'Native POL shim must read the exact portable speech queue path from the managed mod.'
Assert-Contains $native 'GetEnvironmentVariableW' 'Native POL shim must use process environment to avoid hardcoded user paths.'
Assert-Contains $native 'pol-monitor\.log' 'Native POL shim must keep a stable native diagnostic log filename.'
Assert-Contains $native 'pol-reloaded-native-speech\.queue' 'Native POL shim must keep a stable native speech queue filename.'
Assert-Contains $native 'native diagnostics' 'Native POL shim must log which diagnostic paths it is using.'

foreach ($binary in @($stagedReloadedMod, $stagedSpeechBridgeDll, $stagedSpeechBridgeExe, $stagedNativeShim)) {
    Assert-BinaryDoesNotContainString $binary 'C:\Users\buu42' "Staged Reloaded binary must not contain this machine's literal user path: $binary"
    Assert-BinaryDoesNotContainString $binary 'C:\\Users\\buu42' "Staged Reloaded binary must not contain this machine's escaped user path: $binary"
}

'ok: Reloaded POL diagnostics are portable and instrumented.'
