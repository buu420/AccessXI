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
$polReloadedDiagnosticTest = Join-Path $RepoRoot 'tools\test_pol_reloaded_portable_diagnostics.ps1'
$exeTest = Join-Path $RepoRoot 'tools\test_accessxi_installer_exe.ps1'
$projectFile = Join-Path $RepoRoot 'installer\AccessXIInstaller\AccessXIInstaller.csproj'
$setupGuide = Join-Path $RepoRoot 'setup-guide.md'
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
if (-not (Test-Path -LiteralPath $setupGuide)) {
    throw "Missing setup guide: $setupGuide"
}

if ($NoPayloadBuild) {
    Invoke-PowerShellScript -Name $packageScript -Command { & $packageScript -RepoRoot $RepoRoot -AshitaRoot $AshitaRoot -OutputDirectory $OutputDirectory -NoBuild }
} else {
    Invoke-PowerShellScript -Name $packageScript -Command { & $packageScript -RepoRoot $RepoRoot -AshitaRoot $AshitaRoot -OutputDirectory $OutputDirectory }
}

Invoke-PowerShellScript -Name $packageTest -Command { & $packageTest -RepoRoot $RepoRoot -PackageRoot (Join-Path $OutputDirectory 'AccessXI-Ashita-Reloaded-Installer') }
Invoke-PowerShellScript -Name $polReloadedDiagnosticTest -Command { & $polReloadedDiagnosticTest -RepoRoot $RepoRoot }

New-Item -ItemType Directory -Force -Path $publishDirectory | Out-Null
Invoke-NativeCommand -FilePath 'dotnet' -Arguments @('publish', $projectFile, '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-o', $publishDirectory, '/p:PublishSingleFile=true', '/p:EnableCompressionInSingleFile=true', '/p:IncludeNativeLibrariesForSelfExtract=true')

if (-not (Test-Path -LiteralPath $publishedSource)) {
    throw "dotnet publish did not produce expected installer exe: $publishedSource"
}

Copy-Item -LiteralPath $publishedSource -Destination $publishedExe -Force
Copy-Item -LiteralPath $setupGuide -Destination $publishedSetupGuide -Force

Invoke-PowerShellScript -Name $exeTest -Command { & $exeTest -RepoRoot $RepoRoot -PublishedExe $publishedExe }

[pscustomobject]@{
    InstallerExe = $publishedExe
    SetupGuide = $publishedSetupGuide
    PackageZip = Join-Path $OutputDirectory 'AccessXI-Ashita-Reloaded-Installer.zip'
    PublishDirectory = $publishDirectory
}
