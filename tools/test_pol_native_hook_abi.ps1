param([string]$RepoRoot = 'C:\Users\buu42\AccessXI')

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

function Assert-Before {
    param([string]$Text, [string]$FirstPattern, [string]$SecondPattern, [string]$Message)
    $first = [regex]::Match($Text, $FirstPattern)
    $second = [regex]::Match($Text, $SecondPattern)
    if (-not $first.Success -or -not $second.Success -or $first.Index -ge $second.Index) { throw $Message }
}

$sourcePath = Join-Path $RepoRoot 'src\accessxi_pol.cpp'
$defPath = Join-Path $RepoRoot 'src\accessxi_pol.def'
$source = Get-Content -LiteralPath $sourcePath -Raw
$exports = Get-Content -LiteralPath $defPath -Raw

Assert-Contains $exports 'AccessXI_POL_SetSpeechSinkV1=_AccessXI_POL_SetSpeechSinkV1@8' 'Native hook DLL must export the versioned x86 speech-sink ABI.'
Assert-Contains $exports 'AccessXI_POL_InitializeV2=_AccessXI_POL_InitializeV2@0' 'Native hook DLL must export the status-returning x86 initializer.'
Assert-NotContains $exports 'Reloaded' 'Native hook DLL must not export the retired framework compatibility initializer.'

Assert-Contains $source 'using\s+AccessXiPolSpeechSinkV1\s*=\s*void\s*\(__stdcall\s*\*\)\s*\(\s*const\s+char\s*\*\s*utf8_text\s*,\s*int\s+interrupt\s*,\s*void\s*\*\s*context\s*\)' 'Speech sink ABI must remain __stdcall with the reviewed V1 argument order.'
Assert-Contains $source 'AccessXI_POL_SetSpeechSinkV1\s*\(\s*AccessXiPolSpeechSinkV1\s+sink\s*,\s*void\s*\*\s*context\s*\)' 'Native hook source must implement V1 speech-sink registration.'
Assert-Contains $source 'dispatch_speech_sink_v1\s*\(\s*label\s*,\s*1\s*\)' 'Verified native labels must be dispatched through the in-process speech sink.'
Assert-NotContains $source 'AccessXI_POL_ReloadedInitialize|pol-reloaded-native-speech\.queue|g_reloaded_|append_reloaded_' 'Native hook source must not retain the retired framework queue or compatibility API.'

$v2 = [regex]::Match($source, 'AccessXI_POL_InitializeV2\s*\(\s*void\s*\)\s*\{(?<body>[\s\S]*?)\n\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $v2.Success) { throw 'Native hook source must implement AccessXI_POL_InitializeV2.' }
$v2Body = $v2.Groups['body'].Value
Assert-Before $v2Body 'GetModuleHandleW\s*\(\s*L"app\.dll"\s*\)' 'install_native_focus_event_dispatch_hooks_once\s*\(' 'V2 must find app.dll before installing hooks.'
Assert-Before $v2Body 'app_module_matches_known_updated_pol_build\s*\(' 'install_native_focus_event_dispatch_hooks_once\s*\(' 'V2 must verify the exact app.dll build before installing hooks.'
Assert-Contains $v2Body 'start_native_hook_worker_once\s*\(' 'V2 must start the native retry and polling worker.'
Assert-Contains $v2Body 'AccessXiPolInitializeAppDllMissing' 'V2 must report a missing app.dll explicitly.'
Assert-Contains $v2Body 'AccessXiPolInitializeUnsupportedBuild' 'V2 must report an unsupported app.dll explicitly.'

'ok: native PlayOnline hook ABI is direct, fail-closed, and framework-free.'
