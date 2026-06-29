param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$AshitaPolPlugin = 'C:\Users\buu42\Ashita\polplugins\accessxi_pol_nvda.dll',
    [string]$PolExe = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

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

function Assert-Before {
    param(
        [string]$Text,
        [string]$FirstPattern,
        [string]$SecondPattern,
        [string]$Message
    )
    $first = [regex]::Match($Text, $FirstPattern)
    $second = [regex]::Match($Text, $SecondPattern)
    if (-not $first.Success -or -not $second.Success -or $first.Index -ge $second.Index) {
        throw $Message
    }
}

$disabledPlugin = "$AshitaPolPlugin.disabled"
$reloadedRoot = Join-Path $RepoRoot 'external\Reloaded-II'
$reloadedExe = Join-Path $reloadedRoot 'Reloaded-II.exe'
$loaderConfigPath = Join-Path $env:APPDATA 'Reloaded-Mod-Loader-II\ReloadedII.json'
$modRoot = Join-Path $RepoRoot 'src\AccessXI.PolReloaded'
$projectPath = Join-Path $modRoot 'AccessXI.PolReloaded.csproj'
$modConfigPath = Join-Path $modRoot 'ModConfig.json'
$modSourcePath = Join-Path $modRoot 'Mod.cs'
$speechBridgeRoot = Join-Path $RepoRoot 'src\AccessXI.PolSpeechBridge'
$speechBridgeProjectPath = Join-Path $speechBridgeRoot 'AccessXI.PolSpeechBridge.csproj'
$speechBridgeSourcePath = Join-Path $speechBridgeRoot 'Program.cs'
$nativeSourcePath = Join-Path $RepoRoot 'src\accessxi_pol.cpp'
$nativeDefPath = Join-Path $RepoRoot 'src\accessxi_pol.def'
$buildScript = Join-Path $RepoRoot 'tools\build_pol_reloaded.ps1'
$launchScript = Join-Path $RepoRoot 'tools\launch_pol_reloaded.ps1'
$deployBootloaderScript = Join-Path $RepoRoot 'tools\deploy_pol_reloaded_bootloader.ps1'
$builtModDll = Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll'
$builtModConfig = Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\ModConfig.json'
$builtSpeechBridgeExe = Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\AccessXI.PolSpeechBridge.exe'
$builtSpeechBridgeDll = Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\AccessXI.PolSpeechBridge.dll'
$stagedControllerDll = Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\nvdaControllerClient64.dll'
$prismDll = 'C:\Users\buu42\Ashita\polplugins\prism.dll'
$hooksModConfig = Join-Path $reloadedRoot 'Mods\reloaded.sharedlib.hooks\ModConfig.json'
$polDirectory = Split-Path -Parent $PolExe
$appConfigPath = Join-Path $reloadedRoot 'Apps\AccessXI.PolPreLogin\AppConfig.json'
$asiExtractRoot = Join-Path $reloadedRoot '_asi_extract'
$asiLoader32 = Join-Path $asiExtractRoot 'ASILoader32.dll'
$deployedAsiProxy = Join-Path $polDirectory 'ddraw.dll'
$unusedWinmmProxy = Join-Path $polDirectory 'winmm.dll'
$builtBootloaderAsi = Join-Path $RepoRoot 'tools\pol_asi_probe\AccessXI.PolReloadedBootstrap.asi'
$deployedBootloaderAsi = Join-Path $polDirectory 'scripts\AccessXI.PolReloadedBootstrap.asi'
$deployedBootstrapper = Join-Path $polDirectory 'scripts\Reloaded.Mod.Loader.Bootstrapper.dll'
$directBootstrapperAsi = Join-Path $polDirectory 'scripts\Reloaded.Mod.Loader.Bootstrapper.asi'
$badPortableMarker = Join-Path $polDirectory 'scripts\ReloadedPortable.txt'

Assert-True (Test-Path -LiteralPath $PolExe) "Missing PlayOnline target exe: $PolExe"
Assert-True (-not (Test-Path -LiteralPath $AshitaPolPlugin)) 'Ashita POL plugin is still active; disable it before testing the Reloaded-II POL path.'
Assert-True (Test-Path -LiteralPath $disabledPlugin) 'Disabled Ashita POL plugin copy is missing.'
Assert-True (Test-Path -LiteralPath $reloadedExe) "Missing Reloaded-II launcher at $reloadedExe"
Assert-True (Test-Path -LiteralPath $loaderConfigPath) "Missing Reloaded-II loader config: $loaderConfigPath"
Assert-True (Test-Path -LiteralPath $projectPath) "Missing Reloaded-II POL mod project: $projectPath"
Assert-True (Test-Path -LiteralPath $modConfigPath) "Missing Reloaded-II ModConfig: $modConfigPath"
Assert-True (Test-Path -LiteralPath $modSourcePath) "Missing Reloaded-II mod source: $modSourcePath"
Assert-True (Test-Path -LiteralPath $speechBridgeProjectPath) "Missing POL speech bridge project: $speechBridgeProjectPath"
Assert-True (Test-Path -LiteralPath $speechBridgeSourcePath) "Missing POL speech bridge source: $speechBridgeSourcePath"
Assert-True (Test-Path -LiteralPath $nativeSourcePath) "Missing native POL hook source: $nativeSourcePath"
Assert-True (Test-Path -LiteralPath $nativeDefPath) "Missing native POL hook exports: $nativeDefPath"
Assert-True (Test-Path -LiteralPath $buildScript) "Missing Reloaded-II POL build helper: $buildScript"
Assert-True (Test-Path -LiteralPath $launchScript) "Missing Reloaded-II POL launch helper: $launchScript"
Assert-True (Test-Path -LiteralPath $deployBootloaderScript) "Missing Reloaded-II POL bootloader deploy helper: $deployBootloaderScript"

$project = Get-Content -LiteralPath $projectPath -Raw
$modConfig = Get-Content -LiteralPath $modConfigPath -Raw
$modSource = Get-Content -LiteralPath $modSourcePath -Raw
$speechBridgeProject = Get-Content -LiteralPath $speechBridgeProjectPath -Raw
$speechBridgeSource = Get-Content -LiteralPath $speechBridgeSourcePath -Raw
$nativeSource = Get-Content -LiteralPath $nativeSourcePath -Raw
$nativeDef = Get-Content -LiteralPath $nativeDefPath -Raw
$buildHelper = Get-Content -LiteralPath $buildScript -Raw
$launchHelper = Get-Content -LiteralPath $launchScript -Raw
$deployHelper = Get-Content -LiteralPath $deployBootloaderScript -Raw

Assert-Contains $project '<PlatformTarget>x86</PlatformTarget>' 'Reloaded POL mod must target x86 for PlayOnline Viewer.'
Assert-Contains $project 'Reloaded\.Mod\.Interfaces' 'Reloaded POL mod must reference Reloaded mod interfaces.'
Assert-Contains $project 'Reloaded\.SharedLib\.Hooks' 'Reloaded POL mod must reference Reloaded shared hooks for native POL/PML hooks.'
Assert-Contains $project 'Reloaded\.Memory\.SigScan' 'Reloaded POL mod must reference signature scanning for Ghidra-derived POL hooks.'

Assert-Contains $modConfig '"ModId"\s*:\s*"accessxi\.pol\.prelogin"' 'ModConfig must use the stable AccessXI POL pre-login mod id.'
Assert-Contains $modConfig '"ModName"\s*:\s*"AccessXI POL Pre-Login"' 'ModConfig must expose a clear POL pre-login mod name.'
Assert-Contains $modConfig '"SupportedAppId"\s*:\s*\[\s*"pol\.exe"\s*\]' 'ModConfig must target PlayOnline Viewer pol.exe, not the FFXI/Ashita launcher.'
Assert-Contains $modConfig '"ModR2RManagedDll32"\s*:\s*""' 'ModConfig must not point Reloaded at stale x86 ReadyToRun managed DLL paths.'
Assert-Contains $modConfig '"ModR2RManagedDll64"\s*:\s*""' 'ModConfig must not point Reloaded at stale x64 ReadyToRun managed DLL paths.'
Assert-Contains $modConfig '"ModDependencies"\s*:\s*\[\s*\]' 'The no-hook startup probe must not depend on Reloaded.SharedLib.Hooks until that dependency is installed in the portable Mods folder.'

Assert-Contains $modSource 'AccessXI_POL_RELOADED startup' 'Reloaded POL mod must log a stable startup marker for live POL validation.'
Assert-Contains $modSource 'pol-reloaded-startup\.log' 'Reloaded POL mod must write a stable AccessXI-side startup marker for bootloader validation.'
Assert-Contains $modSource 'File\.AppendAllText' 'Reloaded POL mod must append the startup marker without relying only on Reloaded launcher logs.'
Assert-Contains $modSource 'Process\.GetCurrentProcess\(\)' 'Reloaded POL mod must log the actual injected process for validation.'
Assert-Contains $modSource 'app\.dll' 'Reloaded POL mod must check whether POL app.dll is already loaded at startup.'
Assert-Contains $modSource 'POL pre-login only' 'Reloaded POL mod source must document that Ashita still owns in-game FFXI.'
Assert-Contains $modSource 'AccessXI_POL_RELOADED_SPEAK' 'Reloaded POL mod must log a stable Prism speech marker for live POL validation.'
Assert-Contains $modSource 'pol-reloaded-speech\.log' 'Reloaded POL mod must write a stable AccessXI-side speech log for Prism validation.'
Assert-Contains $modSource 'pol-reloaded-native-speech\.queue' 'Reloaded POL mod must create the native menu speech queue.'
Assert-Contains $modSource 'StartNativeSpeechQueueWorker' 'Reloaded POL mod must start the native speech delivery bridge before native menu speech is needed.'
Assert-Contains $modSource 'RunNativeSpeechQueueWorker' 'Reloaded POL mod must tail native menu speech in-process instead of depending only on an external helper.'
Assert-Contains $modSource 'managed-queue-started' 'Reloaded POL mod must log a stable in-process native speech queue startup marker.'
Assert-Contains $modSource 'managed-queue-worker-started' 'Reloaded POL mod must log the speech queue worker apartment/context that owns Prism delivery.'
Assert-Contains $modSource 'managed-queue-speak' 'Reloaded POL mod must log every in-process native queued label before calling Prism.'
Assert-Contains $modSource 'Speech\.Speak\s*\(\s*line\s*,\s*_logger\s*\)' 'Reloaded POL mod must deliver native queued labels through the same in-process Prism path as startup speech.'
Assert-Contains $modSource 'ACCESSXI_POL_LOG_DIR' 'Reloaded POL mod must pass a portable diagnostic log directory to the native shim.'
Assert-Contains $modSource 'ACCESSXI_POL_SPEECH_QUEUE' 'Reloaded POL mod must pass the exact managed speech queue path to the native shim.'
Assert-Contains $modSource 'native-diagnostics-configured' 'Reloaded POL mod must log the native diagnostic environment used by the shim.'
Assert-Contains $modSource 'Thread\s*\(' 'Reloaded POL mod must run the in-process native queue reader on a background thread.'
Assert-Contains $modSource 'IsBackground\s*=\s*true' 'Reloaded POL native queue reader must not keep POL alive during shutdown.'
Assert-Contains $modSource 'SetApartmentState\s*\(\s*ApartmentState\.STA\s*\)' 'Reloaded POL native queue reader must run STA so Prism/Windows delivery stays on a stable UI-compatible thread.'
if ($modSource -match 'StartupSpeechText|SpeakStartupProof|startup-request|AccessXI PlayOnline loaded|QueueManagedSpeech') {
    throw 'Reloaded POL mod must not speak a startup proof; only native focus/menu labels may enter the Prism speech queue.'
}
$queueWorkerIndex = $modSource.IndexOf('StartNativeSpeechQueueWorker();')
$nativeShimIndex = $modSource.IndexOf('LoadNativeHookShim();')
Assert-True (($queueWorkerIndex -ge 0) -and ($nativeShimIndex -ge 0) -and ($queueWorkerIndex -lt $nativeShimIndex)) 'Reloaded POL mod must start the speech queue before loading the native hook shim.'
if ($modSource -match 'StartNativeSpeechQueueWorker[\s\S]{0,2200}AccessXI\.PolSpeechBridge\.exe|StartNativeSpeechQueueWorker[\s\S]{0,2200}ProcessStartInfo|StartNativeSpeechQueueWorker[\s\S]{0,2200}Process\.Start') {
    throw 'Reloaded POL mod must not route live native menu labels through the external bridge; it reported Prism success while the user heard silence.'
}
Assert-True (($queueWorkerIndex -ge 0) -and ($nativeShimIndex -ge 0) -and ($queueWorkerIndex -lt $nativeShimIndex)) 'Reloaded POL mod must start the native speech queue worker before loading the native hook shim.'
Assert-NotContainsLiteral $modSource 'C:\Users\buu42' 'Reloaded POL mod source must not contain this machine-specific user path.'
Assert-NotContainsLiteral $modSource 'C:\\Users\\buu42' 'Reloaded POL mod source must not contain escaped machine-specific user paths.'
Assert-Contains $modSource 'ModDirectory' 'Reloaded POL mod must resolve package-local files from its loaded mod directory.'
Assert-Contains $modSource 'Path\.Combine\(ModDirectory,\s*"prism\.dll"\)' 'Reloaded POL mod must first try the Prism DLL staged beside the Reloaded mod so packaged installs are portable.'
Assert-Contains $modSource 'prism-load-miss' 'Reloaded POL mod must log Prism DLL load misses for friend-machine diagnostics.'
Assert-Contains $modSource 'prism_init' 'Reloaded POL mod must load Prism through its native init export.'
Assert-Contains $modSource 'PrismBackendUia' 'Reloaded POL mod must know Prism UIA backend id for screen-reader-agnostic POL announcements.'
Assert-Contains $modSource 'PrismBackendNvda' 'Reloaded POL mod must try Prism NVDA before UIA because UIA returned success but was inaudible in live POL.'
Assert-Contains $modSource 'PrismBackendJaws' 'Reloaded POL mod must try Prism JAWS before UIA so native screen-reader APIs remain preferred.'
Assert-Contains $modSource 'prism_registry_create' 'Reloaded POL mod must be able to request Prism UIA before falling back to best-backend selection.'
Assert-Contains $modSource 'prism_backend_initialize' 'Reloaded POL mod must initialize explicitly requested Prism backends such as UIA.'
Assert-Contains $modSource 'WaitForPrismUiaHostWindow\s*\(\s*logger\s*,\s*TimeSpan\.FromSeconds\(10\)\s*\)' 'Reloaded POL mod must wait for a real PlayOnline window before requesting Prism UIA.'
Assert-Before $modSource 'WaitForPrismUiaHostWindow\s*\(\s*logger\s*,\s*TimeSpan\.FromSeconds\(10\)\s*\)' 'TryCreateBackend\s*\(\s*logger\s*,\s*PrismBackendUia\s*,\s*"UIA"\s*\)' 'Prism UIA must bind to the real POL window, not an early synthetic host or stale foreground window.'
Assert-Before $modSource 'TryCreateBackend\s*\(\s*logger\s*,\s*PrismBackendNvda\s*,\s*"NVDA"\s*\)' 'TryCreateBackend\s*\(\s*logger\s*,\s*PrismBackendJaws\s*,\s*"JAWS"\s*\)' 'Prism NVDA must be attempted before JAWS on this NVDA-backed setup.'
Assert-Before $modSource 'TryCreateBackend\s*\(\s*logger\s*,\s*PrismBackendJaws\s*,\s*"JAWS"\s*\)' 'WaitForPrismUiaHostWindow\s*\(\s*logger\s*,\s*TimeSpan\.FromSeconds\(10\)\s*\)' 'Prism JAWS must be attempted before the UIA fallback.'
Assert-Contains $modSource 'FindPrismUiaHostWindow' 'Reloaded POL mod must discover the real host window Prism will use.'
Assert-Contains $modSource 'EnumWindows' 'Reloaded POL mod must enumerate process windows when POL is visible but not foreground.'
Assert-Contains $modSource 'IsPrismUiaCandidateWindow' 'Reloaded POL mod must use Prism-compatible host-window rules before UIA initialization.'
Assert-Contains $modSource 'GetForegroundWindow' 'Reloaded POL mod must prefer the current foreground POL window when it is valid.'
Assert-Contains $modSource 'SetForegroundWindow' 'Reloaded POL mod should try to restore POL foreground focus before binding Prism UIA.'
Assert-Contains $modSource 'prism-uia-host-window-ready' 'Reloaded POL mod must log the real UIA host window used for Prism binding.'
Assert-Contains $modSource 'prism-uia-host-window-missing' 'Reloaded POL mod must log when no real UIA host window is available yet.'
Assert-Contains $modSource 'FailInitialize' 'Reloaded POL Prism initialization failures must be retryable after POL creates its real window.'
if ($modSource -match 'private\s+bool\s+Initialize\s*\([\s\S]*?_initialized\s*=\s*true;\s*\r?\n\s*_module\s*=\s*LoadPrismModule') {
    throw 'Prism initialization must not mark itself initialized before a backend is actually ready; early no-window failures must retry.'
}
if ($modSource -match 'EnsurePrismUiaHostWindow|AccessXIPrismUiaHostWindow|CreateWindowExW|RegisterClassExW|DefWindowProcW|WS_EX_NOACTIVATE|-32000|prism-uia-host-window-created') {
    throw 'Reloaded POL must not fabricate an offscreen UIA host; Prism UIA should bind to the real PlayOnline window.'
}
Assert-Contains $modSource 'TryCreateBackend\s*\(\s*logger\s*,\s*PrismBackendUia\s*,\s*"UIA"\s*\)' 'Reloaded POL mod must keep Prism UIA as a screen-reader-agnostic fallback.'
Assert-Before $modSource 'TryCreateBackend\s*\(\s*logger\s*,\s*PrismBackendUia\s*,\s*"UIA"\s*\)' '_createBest!?\(_context\)' 'Reloaded POL mod must try native screen-reader backends and UIA before using create-best fallback.'
Assert-Contains $modSource 'prism-specific-backend-unavailable name=\\\"\{name\}\\\"' 'Reloaded POL mod must log when the Prism UIA backend is unavailable before falling back.'
Assert-Contains $modSource 'prism_registry_create_best' 'Reloaded POL mod must keep Prism best-backend selection as a fallback when UIA is unavailable.'
if ($modSource -match 'PrismBackendSapi|preferred=SAPI') {
    throw 'Reloaded POL mod must not force SAPI; SAPI is acceptable only through Prism best-backend fallback when NVDA is unavailable.'
}
Assert-Contains $modSource 'prism_backend_output' 'Reloaded POL mod must speak through Prism backend output.'
Assert-Contains $modSource 'accessxi_pol_native\.dll' 'Reloaded POL mod must load the native POL hook shim from its own mod folder.'
Assert-Contains $modSource 'Assembly\.Location' 'Reloaded POL mod must resolve the native hook shim from the loaded mod assembly directory.'
Assert-Contains $modSource 'AccessXI_POL_ReloadedInitialize' 'Reloaded POL mod must call the standalone native POL hook initializer.'
Assert-Contains $modSource 'AccessXI_POL_RELOADED_NATIVE' 'Reloaded POL mod must log stable native hook shim markers.'

Assert-Contains $speechBridgeProject '<PlatformTarget>x86</PlatformTarget>' 'POL speech bridge must run x86 so it can load the same Prism DLL used by POL/Ashita.'
Assert-Contains $speechBridgeSource 'pol-reloaded-native-speech\.queue' 'POL speech bridge must tail the native-backed speech queue.'
Assert-NotContainsLiteral $speechBridgeSource 'C:\Users\buu42' 'POL speech bridge source must not contain this machine-specific user path.'
Assert-NotContainsLiteral $speechBridgeSource 'C:\\Users\\buu42' 'POL speech bridge source must not contain escaped machine-specific user paths.'
Assert-Contains $speechBridgeSource 'ACCESSXI_POL_LOG_DIR' 'POL speech bridge must share the portable diagnostic log directory contract.'
Assert-Contains $speechBridgeSource 'ACCESSXI_POL_SPEECH_QUEUE' 'POL speech bridge must share the portable speech queue contract.'
Assert-Contains $speechBridgeSource 'Path\.Combine\(AppContext\.BaseDirectory,\s*"prism\.dll"\)' 'POL speech bridge must first try the Prism DLL staged beside the bridge for packaged installs.'
Assert-Contains $speechBridgeSource 'prism_init' 'POL speech bridge must create a Prism context.'
Assert-Contains $speechBridgeSource 'prism_registry_create_best' 'POL speech bridge must let Prism choose the best available screen-reader/TTS backend.'
Assert-Contains $speechBridgeSource 'prism_backend_output' 'POL speech bridge must output through Prism so speech and braille-capable backends remain available.'
Assert-Contains $speechBridgeSource 'Shutdown\(stopSpeech: false\)' 'POL speech bridge must not cancel the last accepted Prism utterance when POL exits or restarts.'
Assert-Contains $speechBridgeSource 'bridge prism-shutdown stopSpeech=' 'POL speech bridge must log whether shutdown cancels or preserves accepted Prism speech.'
Assert-Contains $speechBridgeSource 'Global\\AccessXI\.PolSpeechBridge' 'POL speech bridge must prevent duplicate bridge instances.'
Assert-Contains $speechBridgeSource 'GetProcessById\(parentPid\)' 'POL speech bridge must exit when the POL parent process exits.'
Assert-Contains $speechBridgeSource 'LatestCompleteSpeechLine' 'POL speech bridge must collapse a burst of native focus labels to the newest complete line before speaking.'
Assert-Contains $speechBridgeSource 'bridge speak-latest text=' 'POL speech bridge must leave a stable log marker when it speaks the newest queued focus label.'
if ($speechBridgeSource -match 'foreach\s*\(\s*var\s+rawLine\s+in\s+complete\.Split\(') {
    throw 'POL speech bridge must not speak every queued line in a focus burst; stale labels make menu arrowing lag behind.'
}
if ($speechBridgeSource -match 'GetAsyncKeyState|Tesseract|CaptureFromScreen|CopyFromScreen|OCR|nvdaController|FreedomSci|SpVoice|System\.Speech') {
    throw 'POL speech bridge must not use key monitoring, OCR, direct screen-reader controller DLLs, or System.Speech; it should only output native queued labels through Prism.'
}

Assert-Contains $nativeSource 'AccessXI_POL_ReloadedInitialize' 'Native POL hook source must export a standalone Reloaded initializer.'
Assert-Contains $nativeSource 'AccessXI POL Reloaded native initializing' 'Native POL hook initializer must leave a stable startup log marker.'
Assert-Contains $nativeSource 'AccessXI POL Reloaded native hook worker started' 'Native POL hook source must start a Reloaded-only hook retry worker.'
Assert-Contains $nativeSource 'g_reloaded_speech_queue_enabled' 'Native POL hook source must know when Reloaded managed speech owns delivery.'
Assert-Contains $nativeSource 'append_reloaded_speech_queue' 'Native POL hook source must queue native labels for the managed Reloaded speech path.'
Assert-Contains $nativeSource 'pol-reloaded-native-speech\.queue' 'Native POL hook source must write native labels to the Reloaded managed speech queue.'
Assert-NotContainsLiteral $nativeSource 'C:\Users\buu42' 'Native POL hook source must not contain this machine-specific user path.'
Assert-NotContainsLiteral $nativeSource 'C:\\Users\\buu42' 'Native POL hook source must not contain escaped machine-specific user paths.'
Assert-Contains $nativeSource 'ACCESSXI_POL_LOG_DIR' 'Native POL hook source must read the portable diagnostic log directory from the managed mod.'
Assert-Contains $nativeSource 'ACCESSXI_POL_SPEECH_QUEUE' 'Native POL hook source must read the exact portable speech queue path from the managed mod.'
Assert-Contains $nativeSource 'GetEnvironmentVariableW' 'Native POL hook source must use process environment instead of hardcoded developer paths.'
Assert-Contains $nativeSource 'native diagnostics' 'Native POL hook source must log resolved diagnostic paths on startup.'
if ($nativeSource -match 'kPrismBackendSapi|preferred=SAPI|prism_registry_create"\)|prism_backend_initialize') {
    throw 'Native POL hook speech must not force SAPI; Reloaded mode should queue labels to the managed NVDA-first speech path.'
}
Assert-Contains $nativeSource 'start_reloaded_native_hook_worker_once\(\)' 'Native POL hook initializer must start the Reloaded hook retry worker.'
Assert-Contains $nativeSource 'install_pml_focus_event_call_hook_once\(\)' 'Native POL hook initializer must install the Ghidra-backed PML focus event hook.'
Assert-Contains $nativeSource 'install_native_focus_event_dispatch_hooks_once\(\)' 'Native POL hook initializer must install native focus event dispatch hooks.'
if ($nativeSource -match 'AccessXI_POL_ReloadedInitialize[\s\S]*?g_keys\.start\(\)') {
    throw 'Standalone Reloaded native initializer must not start the old key monitor.'
}
Assert-Contains $nativeDef 'AccessXI_POL_ReloadedInitialize' 'Native POL exports file must expose the standalone Reloaded initializer.'

Assert-Contains $buildHelper 'RELOADEDIIMODS' 'Build helper must set RELOADEDIIMODS for the portable Reloaded-II install.'
Assert-Contains $buildHelper 'dotnet build' 'Build helper must build the Reloaded-II POL mod.'
Assert-Contains $buildHelper 'cmake --build' 'Build helper must also build the native POL hook shim.'
Assert-Contains $buildHelper '\[System\.IO\.Path\]::GetFullPath' 'Build helper must resolve absolute paths before deleting the staged Reloaded mod folder.'
Assert-Contains $buildHelper 'Remove-Item -LiteralPath \$modOutputDirectory -Recurse -Force' 'Build helper must clean the staged Reloaded mod folder so stale managed DLLs cannot survive.'
Assert-Contains $buildHelper 'accessxi_pol_native\.dll' 'Build helper must stage the native POL hook shim beside the Reloaded mod DLL.'
Assert-Contains $buildHelper 'AccessXI\.PolSpeechBridge\.csproj' 'Build helper must build the external POL speech bridge.'
Assert-Contains $buildHelper 'prism\.dll' 'Build helper must verify that Prism is present for the POL speech bridge.'
Assert-Contains $buildHelper 'Copy-Item -LiteralPath \$prismDll -Destination \(Join-Path \$modOutputDirectory ''prism\.dll''\)' 'Build helper must stage Prism beside the Reloaded mod and speech bridge for portable installs.'
Assert-Contains $buildHelper 'nvdaControllerClient64\.dll' 'Build helper must know the stale direct NVDA controller DLL name so it can remove it.'
Assert-Contains $buildHelper 'Remove-Item -LiteralPath \$staleControllerDll' 'Build helper must remove stale direct NVDA controller DLLs from the POL speech bridge folder.'
Assert-Contains $launchHelper 'accessxi_pol_nvda\.dll' 'Launch helper must refuse to run if the old Ashita POL plugin is active.'
Assert-True ($launchHelper -notmatch '--launch') 'Launch helper must not use Reloaded-II --launch for POL; POL must start normally and load Reloaded through the bootloader.'
Assert-Contains $launchHelper 'PlayOnlineViewer\\pol\.exe' 'Launch helper must target the real PlayOnline Viewer exe.'

Assert-Contains $deployHelper 'ASILoader32\.dll' 'Bootloader deploy helper must deploy the x86 Ultimate ASI Loader.'
Assert-Contains $deployHelper 'ddraw\.dll' 'Bootloader deploy helper must use POL-imported ddraw.dll as the ASI proxy.'
Assert-Contains $deployHelper 'AccessXI\.PolReloadedBootstrap\.asi' 'Bootloader deploy helper must deploy the AccessXI delayed Reloaded bootstrapper ASI.'
Assert-Contains $deployHelper 'Reloaded\.Mod\.Loader\.Bootstrapper\.dll' 'Bootloader deploy helper must stage the x86 Reloaded bootstrapper DLL for the delayed AccessXI bootloader.'
Assert-Contains $deployHelper 'AppConfig\.json' 'Bootloader deploy helper must create a native Reloaded application config for pol.exe.'
Assert-Contains $deployHelper 'ShowConsole' 'Bootloader deploy helper must keep Reloaded-II console output hidden for normal POL startup.'
Assert-Contains $deployHelper 'Backup' 'Bootloader deploy helper must preserve any existing POL-side files before replacing them.'

Assert-True (Test-Path -LiteralPath $builtModDll) "Built Reloaded-II mod DLL is missing: $builtModDll"
Assert-True (Test-Path -LiteralPath $builtModConfig) "Built Reloaded-II ModConfig is missing: $builtModConfig"
Assert-True (Test-Path -LiteralPath $builtSpeechBridgeExe) "Built POL speech bridge exe is missing: $builtSpeechBridgeExe"
Assert-True (Test-Path -LiteralPath $builtSpeechBridgeDll) "Built POL speech bridge DLL is missing: $builtSpeechBridgeDll"
Assert-True (-not (Test-Path -LiteralPath $stagedControllerDll)) "POL speech bridge must not stage a direct NVDA controller DLL: $stagedControllerDll"
Assert-True (Test-Path -LiteralPath $prismDll) "Active Prism DLL is missing: $prismDll"
$stagedPrismDll = Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\prism.dll'
Assert-True (Test-Path -LiteralPath $stagedPrismDll) "Packaged Reloaded mod Prism DLL is missing: $stagedPrismDll"
Assert-True ((Get-FileHash -LiteralPath $stagedPrismDll -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $prismDll -Algorithm SHA256).Hash) 'Packaged Reloaded mod Prism DLL must match the active Ashita Prism DLL.'
Assert-True (Test-Path -LiteralPath $hooksModConfig) "Reloaded Hooks shared-lib mod is missing: $hooksModConfig"
Assert-True (Test-Path -LiteralPath $asiLoader32) "Extracted x86 Ultimate ASI Loader is missing: $asiLoader32"
Assert-True (Test-Path -LiteralPath $builtBootloaderAsi) "Built AccessXI POL Reloaded bootloader ASI is missing: $builtBootloaderAsi"
Assert-True (Test-Path -LiteralPath $appConfigPath) "Reloaded POL app config is missing: $appConfigPath"
Assert-True (Test-Path -LiteralPath $deployedAsiProxy) "POL ddraw.dll ASI proxy is missing: $deployedAsiProxy"
Assert-True (-not (Test-Path -LiteralPath $unusedWinmmProxy)) "POL winmm.dll ASI proxy must be removed; ddraw.dll is the verified loaded proxy."
Assert-True (Test-Path -LiteralPath $deployedBootloaderAsi) "POL AccessXI delayed bootloader ASI is missing: $deployedBootloaderAsi"
Assert-True (Test-Path -LiteralPath $deployedBootstrapper) "POL Reloaded bootstrapper DLL is missing: $deployedBootstrapper"
Assert-True (-not (Test-Path -LiteralPath $directBootstrapperAsi)) "Do not deploy Reloaded.Mod.Loader.Bootstrapper.asi directly; it blocks too early in POL."
Assert-True (-not (Test-Path -LiteralPath $badPortableMarker)) "Do not deploy ReloadedPortable.txt with Ultimate ASI Loader on Reloaded-II 1.1.0+."

$appConfig = Get-Content -LiteralPath $appConfigPath -Raw | ConvertFrom-Json
Assert-True ($appConfig.AppId -eq 'pol.exe') 'Reloaded app config AppId must be pol.exe.'
Assert-True ($appConfig.AppName -eq 'PlayOnline Viewer') 'Reloaded app config AppName must identify PlayOnline Viewer.'
Assert-True ([System.IO.Path]::GetFullPath($appConfig.AppLocation) -ieq [System.IO.Path]::GetFullPath($PolExe)) 'Reloaded app config AppLocation must match the real pol.exe path.'
Assert-True ([System.IO.Path]::GetFullPath($appConfig.WorkingDirectory) -ieq [System.IO.Path]::GetFullPath($polDirectory)) 'Reloaded app config WorkingDirectory must be the PlayOnlineViewer folder.'
Assert-True (@($appConfig.EnabledMods) -contains 'accessxi.pol.prelogin') 'Reloaded app config must enable the AccessXI POL pre-login mod.'

$loaderConfig = Get-Content -LiteralPath $loaderConfigPath -Raw | ConvertFrom-Json
Assert-True ($loaderConfig.ShowConsole -eq $false) 'Reloaded-II ShowConsole must be false so POL starts without a terminal window.'

$asiHash = (Get-FileHash -LiteralPath $asiLoader32 -Algorithm SHA256).Hash
$deployedAsiHash = (Get-FileHash -LiteralPath $deployedAsiProxy -Algorithm SHA256).Hash
Assert-True ($asiHash -eq $deployedAsiHash) 'Deployed ddraw.dll must match the extracted x86 Ultimate ASI Loader.'

$bootstrapperSource = Join-Path $reloadedRoot 'Loader\X86\Bootstrapper\Reloaded.Mod.Loader.Bootstrapper.dll'
$bootstrapperHash = (Get-FileHash -LiteralPath $bootstrapperSource -Algorithm SHA256).Hash
$deployedBootstrapperHash = (Get-FileHash -LiteralPath $deployedBootstrapper -Algorithm SHA256).Hash
Assert-True ($bootstrapperHash -eq $deployedBootstrapperHash) 'Staged bootstrapper DLL must match Reloaded-II x86 bootstrapper.'

$bootloaderHash = (Get-FileHash -LiteralPath $builtBootloaderAsi -Algorithm SHA256).Hash
$deployedBootloaderHash = (Get-FileHash -LiteralPath $deployedBootloaderAsi -Algorithm SHA256).Hash
Assert-True ($bootloaderHash -eq $deployedBootloaderHash) 'Deployed AccessXI bootloader ASI must match the built AccessXI bootloader.'

'ok: AccessXI POL Reloaded-II bootloader scaffold is present and the Ashita POL plugin is disabled.'
