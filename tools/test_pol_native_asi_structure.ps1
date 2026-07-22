param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$StageRoot = '',
    [string]$PrismDll = 'C:\Users\buu42\AccessXI\external\Reloaded-II\Mods\AccessXI.PolReloaded\prism.dll'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Find-Dumpbin {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "vswhere is missing: $vswhere"
    }
    $installation = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($installation)) {
        throw 'Visual Studio C++ Build Tools installation was not found.'
    }
    $candidate = Get-ChildItem -LiteralPath (Join-Path $installation 'VC\Tools\MSVC') -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'bin\Hostx64\x86\dumpbin.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'x86 dumpbin.exe was not found.'
    }
    return $candidate
}

if ([string]::IsNullOrWhiteSpace($StageRoot)) {
    $StageRoot = Join-Path $RepoRoot 'stage\pol-native'
}

$stage = [System.IO.Path]::GetFullPath($StageRoot)
$asi = Join-Path $stage 'AccessXI.PolNative.asi'
$dependencyDirectory = Join-Path $stage 'AccessXI.PolNative'
$hook = Join-Path $dependencyDirectory 'accessxi_pol_native.dll'
$stagedPrism = Join-Path $dependencyDirectory 'prism.dll'

Assert-True (Test-Path -LiteralPath $asi -PathType Leaf) "Native ASI is missing: $asi"
Assert-True (Test-Path -LiteralPath $hook -PathType Leaf) "Native hook DLL is missing: $hook"
Assert-True (Test-Path -LiteralPath $stagedPrism -PathType Leaf) "Staged Prism DLL is missing: $stagedPrism"
Assert-True (Test-Path -LiteralPath $PrismDll -PathType Leaf) "Source Prism DLL is missing: $PrismDll"

$unexpectedFiles = Get-ChildItem -LiteralPath $stage -Recurse -File |
    Where-Object { $_.FullName -notin @($asi, $hook, $stagedPrism) }
Assert-True (@($unexpectedFiles).Count -eq 0) 'Native prototype stage must contain only the ASI, hook DLL, and Prism DLL.'

$dumpbin = Find-Dumpbin
foreach ($binary in @($asi, $hook, $stagedPrism)) {
    $headers = (& $dumpbin /headers $binary 2>&1 | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "dumpbin /headers failed for $binary"
    Assert-True ($headers -match '(?im)^\s*14C machine \(x86\)') "Binary is not x86 Machine 14C: $binary"
    Assert-True ($headers -notmatch '(?im)^\s*[1-9A-F][0-9A-F]* \[[1-9A-F][0-9A-F]*\] RVA \[size\] of COM Descriptor Directory') "Native binary unexpectedly contains a CLR descriptor: $binary"
}

$asiExports = (& $dumpbin /exports $asi 2>&1 | Out-String)
Assert-True ($asiExports -match '(?m)\sInitializeASI\s*$') 'ASI must export undecorated InitializeASI.'

$hookExports = (& $dumpbin /exports $hook 2>&1 | Out-String)
Assert-True ($hookExports -match '(?m)\sAccessXI_POL_SetSpeechSinkV1\s*$') 'Hook DLL is missing AccessXI_POL_SetSpeechSinkV1.'
Assert-True ($hookExports -match '(?m)\sAccessXI_POL_InitializeV2\s*$') 'Hook DLL is missing AccessXI_POL_InitializeV2.'

$asiDependents = (& $dumpbin /dependents $asi 2>&1 | Out-String)
Assert-True ($asiDependents -notmatch '(?i)Reloaded|mscoree|coreclr|hostfxr|prism\.dll|accessxi_pol_native\.dll') 'ASI must dynamically load its private dependencies and must not import Reloaded or the CLR.'

$productionSource = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'src\pol_native') -File |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
    Out-String
Assert-True (-not $productionSource.Contains('C:\Users\buu42')) 'Native host production source contains a machine-specific user path.'
Assert-True ($productionSource -match 'DllMain[\s\S]*?schedule_startup_once\s*\(\s*\)') 'DllMain must schedule the shared idempotent startup path.'
Assert-True ($productionSource -match 'InitializeASI[\s\S]*?schedule_startup_once\s*\(\s*\)') 'InitializeASI must schedule the shared idempotent startup path.'

$sourcePrismHash = (Get-FileHash -LiteralPath $PrismDll -Algorithm SHA256).Hash
$stagedPrismHash = (Get-FileHash -LiteralPath $stagedPrism -Algorithm SHA256).Hash
Assert-True ($sourcePrismHash -eq $stagedPrismHash) 'Staged Prism DLL does not match the selected verified x86 Prism DLL.'

$binaryBytes = [System.IO.File]::ReadAllBytes($asi) + [System.IO.File]::ReadAllBytes($hook)
$binaryAscii = [System.Text.Encoding]::ASCII.GetString($binaryBytes)
$binaryUnicode = [System.Text.Encoding]::Unicode.GetString($binaryBytes)
Assert-True (-not $binaryAscii.Contains('C:\Users\buu42')) 'Native binaries contain a compiled machine-specific ASCII path.'
Assert-True (-not $binaryUnicode.Contains('C:\Users\buu42')) 'Native binaries contain a compiled machine-specific Unicode path.'

'ok: native PlayOnline ASI stage is x86, unmanaged, private, portable, and exports the reviewed ABI.'
