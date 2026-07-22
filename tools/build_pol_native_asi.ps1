param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$Configuration = 'Release',
    [string]$PrismDll = 'C:\Users\buu42\AccessXI\external\Reloaded-II\Mods\AccessXI.PolReloaded\prism.dll',
    [string]$AshitaSdk = 'C:\Users\buu42\Ashita\plugins\sdk'
)

$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([scriptblock]$Command, [string]$Failure)
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Failure (exit $LASTEXITCODE)"
    }
}

$repo = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
$build = Join-Path $repo 'build'
$stage = Join-Path $repo 'stage\pol-native'
$dependencyStage = Join-Path $stage 'AccessXI.PolNative'
$builtAsi = Join-Path $build "bin\$Configuration\AccessXI.PolNative.asi"
$builtHook = Join-Path $build "bin\$Configuration\accessxi_pol_nvda.dll"

if (-not (Test-Path -LiteralPath (Join-Path $repo 'CMakeLists.txt'))) {
    throw "AccessXI repository root is invalid: $repo"
}
if (-not (Test-Path -LiteralPath $PrismDll -PathType Leaf)) {
    throw "Verified x86 Prism DLL is missing: $PrismDll"
}
if (-not (Test-Path -LiteralPath (Join-Path $AshitaSdk 'Ashita.h') -PathType Leaf)) {
    throw "Ashita v4 SDK is missing: $AshitaSdk"
}

$env:ASHITA4_SDK_PATH = [System.IO.Path]::GetFullPath($AshitaSdk)
Invoke-Checked { cmake -S $repo -B $build -A Win32 } 'Win32 CMake configuration failed'
Invoke-Checked {
    cmake --build $build --config $Configuration --target accessxi_pol_nvda accessxi_pol_native_asi pol_native_queue_tests pol_native_speech_worker_tests pol_native_host_tests
} 'Native PlayOnline build failed'
Invoke-Checked { ctest --test-dir $build -C $Configuration --output-on-failure } 'Native PlayOnline tests failed'

$resolvedStage = [System.IO.Path]::GetFullPath($stage).TrimEnd('\')
$repoPrefix = $repo + '\'
if (-not $resolvedStage.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    $resolvedStage -ne [System.IO.Path]::GetFullPath((Join-Path $repo 'stage\pol-native')).TrimEnd('\')) {
    throw "Refusing to clean unexpected stage directory: $resolvedStage"
}
if (Test-Path -LiteralPath $resolvedStage) {
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dependencyStage | Out-Null

if (-not (Test-Path -LiteralPath $builtAsi -PathType Leaf)) {
    throw "ASI build output is missing: $builtAsi"
}
if (-not (Test-Path -LiteralPath $builtHook -PathType Leaf)) {
    throw "Hook build output is missing: $builtHook"
}

Copy-Item -LiteralPath $builtAsi -Destination (Join-Path $stage 'AccessXI.PolNative.asi') -Force
Copy-Item -LiteralPath $builtHook -Destination (Join-Path $dependencyStage 'accessxi_pol_native.dll') -Force
Copy-Item -LiteralPath $PrismDll -Destination (Join-Path $dependencyStage 'prism.dll') -Force

Get-FileHash -LiteralPath (Join-Path $stage 'AccessXI.PolNative.asi') -Algorithm SHA256
Get-FileHash -LiteralPath (Join-Path $dependencyStage 'accessxi_pol_native.dll') -Algorithm SHA256
Get-FileHash -LiteralPath (Join-Path $dependencyStage 'prism.dll') -Algorithm SHA256
