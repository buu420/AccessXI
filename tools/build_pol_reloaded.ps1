param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$reloadedRoot = Join-Path $RepoRoot 'external\Reloaded-II'
$modsRoot = Join-Path $reloadedRoot 'Mods'
$modOutputDirectory = Join-Path $modsRoot 'AccessXI.PolReloaded'
$projectPath = Join-Path $RepoRoot 'src\AccessXI.PolReloaded\AccessXI.PolReloaded.csproj'
$speechBridgeProjectPath = Join-Path $RepoRoot 'src\AccessXI.PolSpeechBridge\AccessXI.PolSpeechBridge.csproj'
$prismDll = 'C:\Users\buu42\Ashita\polplugins\prism.dll'
$nativeBuildRoot = Join-Path $RepoRoot 'build'
$nativeBuiltDll = Join-Path $nativeBuildRoot "bin\$Configuration\accessxi_pol_nvda.dll"

if (-not (Test-Path -LiteralPath (Join-Path $reloadedRoot 'Reloaded-II.exe'))) {
    throw "Reloaded-II is missing from $reloadedRoot"
}
if (-not (Test-Path -LiteralPath $projectPath)) {
    throw "Reloaded POL project is missing: $projectPath"
}
if (-not (Test-Path -LiteralPath $speechBridgeProjectPath)) {
    throw "POL speech bridge project is missing: $speechBridgeProjectPath"
}
if (-not (Test-Path -LiteralPath $prismDll)) {
    throw "Prism DLL for POL speech bridge is missing: $prismDll"
}
if (-not (Test-Path -LiteralPath $nativeBuildRoot)) {
    throw "Native POL hook build directory is missing: $nativeBuildRoot"
}

New-Item -ItemType Directory -Force -Path $modsRoot | Out-Null
$env:RELOADEDIIMODS = $modsRoot

$resolvedModsRoot = [System.IO.Path]::GetFullPath($modsRoot).TrimEnd('\')
$resolvedModOutputDirectory = [System.IO.Path]::GetFullPath($modOutputDirectory).TrimEnd('\')
$modsRootWithSeparator = $resolvedModsRoot + '\'
if ($resolvedModOutputDirectory -ieq $resolvedModsRoot -or -not $resolvedModOutputDirectory.StartsWith($modsRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean unexpected Reloaded mod output directory: $resolvedModOutputDirectory"
}
if (Test-Path -LiteralPath $modOutputDirectory) {
    Remove-Item -LiteralPath $modOutputDirectory -Recurse -Force
}

cmake --build $nativeBuildRoot --config $Configuration --target accessxi_pol_nvda
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
if (-not (Test-Path -LiteralPath $nativeBuiltDll)) {
    throw "Native POL hook build completed but DLL was not produced: $nativeBuiltDll"
}

dotnet build $projectPath -c $Configuration
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$builtDll = Join-Path $modOutputDirectory 'AccessXI.PolReloaded.dll'
if (-not (Test-Path -LiteralPath $builtDll)) {
    throw "Build completed but the Reloaded mod DLL was not copied to $builtDll"
}

dotnet build $speechBridgeProjectPath -c $Configuration -o $modOutputDirectory
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$speechBridgeExe = Join-Path $modOutputDirectory 'AccessXI.PolSpeechBridge.exe'
if (-not (Test-Path -LiteralPath $speechBridgeExe)) {
    throw "Build completed but the POL speech bridge exe was not copied to $speechBridgeExe"
}
$speechBridgeDll = Join-Path $modOutputDirectory 'AccessXI.PolSpeechBridge.dll'
if (-not (Test-Path -LiteralPath $speechBridgeDll)) {
    throw "Build completed but the POL speech bridge DLL was not copied to $speechBridgeDll"
}
$staleControllerDll = Join-Path $modOutputDirectory 'nvdaControllerClient64.dll'
if (Test-Path -LiteralPath $staleControllerDll) {
    Remove-Item -LiteralPath $staleControllerDll -Force
}
Copy-Item -LiteralPath $prismDll -Destination (Join-Path $modOutputDirectory 'prism.dll') -Force

$nativeStageDll = Join-Path $modOutputDirectory 'accessxi_pol_native.dll'
Copy-Item -LiteralPath $nativeBuiltDll -Destination $nativeStageDll -Force
if (-not (Test-Path -LiteralPath $nativeStageDll)) {
    throw "Native POL hook DLL was not staged to $nativeStageDll"
}

Get-FileHash -LiteralPath $builtDll -Algorithm SHA256
Get-FileHash -LiteralPath $speechBridgeExe -Algorithm SHA256
Get-FileHash -LiteralPath $speechBridgeDll -Algorithm SHA256
Get-FileHash -LiteralPath $nativeStageDll -Algorithm SHA256
Get-FileHash -LiteralPath $prismDll -Algorithm SHA256
Get-FileHash -LiteralPath (Join-Path $modOutputDirectory 'prism.dll') -Algorithm SHA256
