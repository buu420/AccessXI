param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$AshitaRoot = 'C:\Users\buu42\Ashita',
    [string]$OutputDirectory = '',
    [switch]$NoPayloadBuild
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Invoke-PowerShellScript {
    param(
        [scriptblock]$Command,
        [string]$Name
    )

    & $Command
    if (-not $?) {
        throw "PowerShell script failed: $Name"
    }
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$RepoRoot = Resolve-FullPath $RepoRoot
$AshitaRoot = Resolve-FullPath $AshitaRoot
if ($OutputDirectory -eq '') {
    $OutputDirectory = Join-Path $RepoRoot 'dist'
}
$OutputDirectory = Resolve-FullPath $OutputDirectory

$packageScript = Join-Path $RepoRoot 'tools\package_accessxi_installer.ps1'
$packageTest = Join-Path $RepoRoot 'tools\test_accessxi_installer_package.ps1'
$publicReadmeTest = Join-Path $RepoRoot 'tools\test_accessxi_public_readme.ps1'
$nativeStructureTest = Join-Path $RepoRoot 'tools\test_pol_native_asi_structure.ps1'
$legacyCleanupTest = Join-Path $RepoRoot 'tools\test_legacy_accessxi_cleanup.ps1'
$nativeMigrationTest = Join-Path $RepoRoot 'tools\test_accessxi_installer_native_migration.ps1'
$exeTest = Join-Path $RepoRoot 'tools\test_accessxi_installer_exe.ps1'
$publicReleaseTest = Join-Path $RepoRoot 'tools\test_public_release_hygiene.ps1'
$projectFile = Join-Path $RepoRoot 'installer\AccessXIInstaller\AccessXIInstaller.csproj'
$publicGuide = Join-Path $RepoRoot 'README.md'
$publishDirectory = Join-Path $OutputDirectory 'AccessXIInstallerExe'
$publishedSource = Join-Path $publishDirectory 'AccessXIInstaller.exe'
$publishedExe = Join-Path $OutputDirectory 'AccessXI Installer.exe'
$publishedSetupGuide = Join-Path $OutputDirectory 'setup-guide.md'

if (-not (Test-Path -LiteralPath $packageScript)) {
    throw "Missing package script: $packageScript"
}
if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "Missing installer exe project: $projectFile"
}
if (-not (Test-Path -LiteralPath $publicGuide)) {
    throw "Missing public setup guide: $publicGuide"
}

if ($NoPayloadBuild) {
    Invoke-PowerShellScript -Name $packageScript -Command { & $packageScript -RepoRoot $RepoRoot -AshitaRoot $AshitaRoot -OutputDirectory $OutputDirectory -NoBuild }
} else {
    Invoke-PowerShellScript -Name $packageScript -Command { & $packageScript -RepoRoot $RepoRoot -AshitaRoot $AshitaRoot -OutputDirectory $OutputDirectory }
}

Invoke-PowerShellScript -Name $packageTest -Command { & $packageTest -RepoRoot $RepoRoot -PackageRoot (Join-Path $OutputDirectory 'AccessXI-Ashita-Installer') }
Invoke-PowerShellScript -Name $publicReadmeTest -Command { & $publicReadmeTest -RepoRoot $RepoRoot }
Invoke-PowerShellScript -Name $nativeStructureTest -Command { & $nativeStructureTest -RepoRoot $RepoRoot }
Invoke-PowerShellScript -Name $legacyCleanupTest -Command { & $legacyCleanupTest -RepoRoot $RepoRoot }
Invoke-PowerShellScript -Name $nativeMigrationTest -Command { & $nativeMigrationTest -RepoRoot $RepoRoot }

New-Item -ItemType Directory -Force -Path $publishDirectory | Out-Null
Invoke-NativeCommand -FilePath 'dotnet' -Arguments @('publish', $projectFile, '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-o', $publishDirectory, '/p:PublishSingleFile=true', '/p:EnableCompressionInSingleFile=true', '/p:IncludeNativeLibrariesForSelfExtract=true')

if (-not (Test-Path -LiteralPath $publishedSource)) {
    throw "dotnet publish did not produce expected installer exe: $publishedSource"
}

Copy-Item -LiteralPath $publishedSource -Destination $publishedExe -Force
Copy-Item -LiteralPath $publicGuide -Destination $publishedSetupGuide -Force

Invoke-PowerShellScript -Name $exeTest -Command { & $exeTest -RepoRoot $RepoRoot -PublishedExe $publishedExe }
Invoke-PowerShellScript -Name $publicReleaseTest -Command { & $publicReleaseTest -RepoRoot $RepoRoot -PackageRoot (Join-Path $OutputDirectory 'AccessXI-Ashita-Installer') }

[pscustomobject]@{
    InstallerExe = $publishedExe
    SetupGuide = $publishedSetupGuide
    PackageZip = Join-Path $OutputDirectory 'AccessXI-Ashita-Installer.zip'
    PublishDirectory = $publishDirectory
}
