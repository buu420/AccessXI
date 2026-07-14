param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$PublishedExe = 'C:\Users\buu42\AccessXI\dist\AccessXI Installer.exe'
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

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -match $Pattern) {
        throw $Message
    }
}

$projectRoot = Join-Path $RepoRoot 'installer\AccessXIInstaller'
$projectFile = Join-Path $projectRoot 'AccessXIInstaller.csproj'
$programFile = Join-Path $projectRoot 'Program.cs'
$manifestFile = Join-Path $projectRoot 'app.manifest'
$buildScript = Join-Path $RepoRoot 'tools\build_accessxi_installer_exe.ps1'
$setupGuide = Join-Path $RepoRoot 'setup-guide.md'

Assert-True (Test-Path -LiteralPath $projectFile) "Missing installer exe project: $projectFile"
Assert-True (Test-Path -LiteralPath $programFile) "Missing installer exe Program.cs: $programFile"
Assert-True (Test-Path -LiteralPath $manifestFile) "Missing installer exe manifest: $manifestFile"
Assert-True (Test-Path -LiteralPath $buildScript) "Missing installer exe build script: $buildScript"
Assert-True (Test-Path -LiteralPath $setupGuide) "Missing setup guide: $setupGuide"

$projectSource = Get-Content -LiteralPath $projectFile -Raw
$programSource = Get-Content -LiteralPath $programFile -Raw
$manifestSource = Get-Content -LiteralPath $manifestFile -Raw
$buildSource = Get-Content -LiteralPath $buildScript -Raw

Assert-Contains $projectSource '<OutputType>WinExe</OutputType>' 'Installer exe must be a Windows app.'
Assert-Contains $projectSource '<UseWindowsForms>true</UseWindowsForms>' 'Installer exe must use WinForms for destination selection.'
Assert-Contains $projectSource 'AccessXI-Ashita-Reloaded-Installer\.zip' 'Installer exe project must embed the packaged AccessXI payload zip.'
Assert-Contains $projectSource '<LogicalName>Payload\.AccessXI-Ashita-Reloaded-Installer\.zip</LogicalName>' 'Installer exe payload resource name must be stable.'
Assert-Contains $projectSource '<ApplicationManifest>app\.manifest</ApplicationManifest>' 'Installer exe must use an application manifest.'

Assert-Contains $manifestSource 'requestedExecutionLevel\s+level="requireAdministrator"' 'Installer exe must request elevation so it can deploy POL-side loader files.'

Assert-Contains $programSource 'FolderBrowserDialog' 'Installer exe must let users choose the AccessXI installation destination.'
Assert-Contains $programSource 'OpenFileDialog' 'Installer exe must let users choose PlayOnline pol.exe when auto-detection is wrong.'
Assert-Contains $programSource 'GetDefaultPolExeCandidates' 'Installer exe must derive default PlayOnline candidates from this machine.'
Assert-Contains $programSource 'playOnlineDetectedOnLaunch' 'Installer exe must remember whether PlayOnline was detected at startup.'
Assert-Contains $programSource 'ExitBecausePlayOnlineMissing' 'Installer exe must exit when PlayOnline is not detected.'
Assert-Contains $programSource 'Install PlayOnline Viewer and Final Fantasy XI first' 'Installer exe must tell users to install PlayOnline before AccessXI.'
Assert-Contains $programSource 'DetectPlayOnlineViewerVersion' 'Installer exe must recognize both updated and pre-update PlayOnline Viewer installs.'
Assert-Contains $programSource 'PlayOnlineViewerState' 'Installer exe must classify PlayOnline as updated or update-needed instead of blocking unknown versions.'
Assert-Contains $programSource 'UpdateSafe' 'Installer exe must allow installation in update-safe mode for pre-update PlayOnline.'
Assert-Contains $programSource 'AccessXI will install in update-safe mode' 'Installer exe must tell users that pre-update PlayOnline can be updated safely after installing.'
Assert-NotContains $programSource 'ValidatePlayOnlineUpdatedBeforeInstall' 'Installer exe must not hard-block AccessXI installation just because PlayOnline still needs its first update.'
Assert-Contains $programSource 'KnownUpdatedPlayOnlineAppDllSize\s*=\s*4335104' 'Installer exe must document the validated updated PlayOnline app.dll size.'
Assert-Contains $programSource 'KnownUpdatedPlayOnlineAppDllFnv64\s*=\s*0x07E88E8067FEF6CCUL' 'Installer exe must document the validated updated PlayOnline app.dll fingerprint.'
Assert-Contains $programSource 'PlayOnlineViewer.*viewer.*com.*app\.dll' 'Installer exe must validate the updated viewer/com/app.dll beside pol.exe.'
Assert-Contains $programSource 'SpecialFolder\.ProgramFilesX86' 'Installer exe must use Windows known folders for default PlayOnline candidates.'
Assert-NotContains $programSource '@"C:\\Program Files' 'Installer exe must not hard-code Program Files PlayOnline candidates.'
Assert-Contains $programSource 'Payload\.AccessXI-Ashita-Reloaded-Installer\.zip' 'Installer exe must extract its embedded payload zip.'
Assert-Contains $programSource 'install_accessxi\.ps1' 'Installer exe must invoke the existing installer script.'
Assert-Contains $programSource '-InstallRoot' 'Installer exe must pass the selected installation destination to install_accessxi.ps1.'
Assert-Contains $programSource '-PolExe' 'Installer exe must pass the selected PlayOnline executable to install_accessxi.ps1.'
Assert-Contains $programSource 'ExecutionPolicy' 'Installer exe must bypass PowerShell execution-policy prompts for the packaged installer script.'
Assert-Contains $programSource 'Ashita-cli\.exe' 'Installer exe must report the direct Ashita-cli.exe launch target after installation.'
Assert-Contains $programSource 'AccessXI Ashita' 'Installer exe must preserve the expected launcher/shortcut label.'
Assert-Contains $programSource 'ProgressBarStyle\.Continuous' 'Installer exe must use a determinate progress bar instead of an indefinite marquee.'
Assert-NotContains $programSource 'ProgressBarStyle\.Marquee' 'Installer exe must not use the old marquee progress indicator.'
Assert-Contains $programSource 'SetStep' 'Installer exe must expose named installation steps in the UI.'
Assert-Contains $programSource 'progressBar\.Value' 'Installer exe must update progress percentage during installation.'
Assert-Contains $programSource 'Finish' 'Installer exe must end in a Finish button state like a normal installer.'
Assert-Contains $programSource 'AccessXI installation is complete' 'Installer exe must have an explicit completion state.'
Assert-Contains $programSource 'InstallState' 'Installer exe must track install state so the Close button becomes Finish after success.'
Assert-Contains $programSource 'completionLabel\.Text\s*=\s*complete\s*\?\s*CompletionMessage\s*:\s*string\.Empty' 'Installer completion help must be assigned only by the finish-state transition.'
Assert-Contains $programSource 'completionLabel\.Visible\s*=\s*complete' 'Installer completion help must become visible only when the Finish button state is active.'
Assert-NotContains $programSource 'AppendLog\(CompletionMessage\)' 'Installer completion help must not be emitted into the install log before the Finish state.'
Assert-Contains $programSource 'DetectMissingVisualCppRedistributables' 'Installer exe must detect missing Visual C++ runtimes before installing.'
Assert-Contains $programSource 'RegistryHive\.LocalMachine' 'Installer exe must inspect machine-wide Visual C++ runtime registration.'
Assert-Contains $programSource 'VisualStudio\\14\.0\\VC\\Runtimes' 'Installer exe must check the standard Visual C++ v14 runtime registry keys.'
Assert-Contains $programSource 'DetectMissingDotNetDesktopRuntimes' 'Installer exe must detect missing .NET Desktop Runtimes before installing.'
Assert-Contains $programSource 'Microsoft\.WindowsDesktop\.App' 'Installer exe must check the .NET Windows Desktop shared runtime used by Reloaded-II.'
Assert-Contains $programSource 'ProgramFilesX86' 'Installer exe must inspect the x86 dotnet runtime folder used by the POL-side Reloaded loader.'
Assert-Contains $programSource 'AskPrerequisiteInstallChoice' 'Installer exe must ask after Install is clicked before running bundled dependency installers.'
Assert-Contains $programSource 'MessageBoxButtons\.YesNoCancel' 'Installer exe must let the user run dependencies, continue without them, or cancel.'
Assert-Contains $programSource 'RunPrerequisiteInstallers' 'Installer exe must run bundled dependency installers before install_accessxi.ps1.'
Assert-Contains $programSource 'openSetupGuideCheckBox' 'Installer exe must show a checked setup-guide option on the finish screen.'
Assert-Contains $programSource 'OpenSetupGuideAfterFinish' 'Installer exe Finish button must open the setup guide when requested.'
Assert-Contains $programSource 'setup-guide\.md' 'Installer exe must open the installed setup guide.'
Assert-NotContains $programSource 'HttpClient' 'Installer exe must not download dependency installers during setup.'
Assert-NotContains $programSource 'DownloadPrerequisitesAsync|CopyDownloadedPrerequisites|Use bundled offline installers' 'Installer exe must not offer the old download-versus-bundled dependency flow.'
Assert-Contains $programSource '-SkipVisualCppRedistributables' 'Installer exe must tell the script the wrapper handled or skipped redist installation.'
Assert-Contains $programSource '-SkipDotNetDesktopRuntimes' 'Installer exe must tell the script the wrapper handled or skipped .NET Desktop Runtime installation.'
Assert-Contains $programSource 'Use the AccessXI Ashita desktop shortcut to start the game' 'Installer exe must keep the helpful completion message on the finish screen.'
Assert-NotContains $programSource 'Use the AccessXI Ashita desktop shortcut or AccessXI\.cmd' 'Installer exe completion help must not recommend the batch launcher that can give focus back to the caller during POL startup.'
Assert-Contains $programSource '%USERPROFILE%\\\\AccessXI\\\\logs' 'Installer exe completion message must tell support users where PlayOnline diagnostics are written.'

Assert-Contains $buildSource 'package_accessxi_installer\.ps1' 'Exe build must refresh the packaged payload before embedding it.'
Assert-Contains $buildSource 'Invoke-PowerShellScript' 'Exe build must check PowerShell script invocations with PowerShell success state.'
Assert-Contains $buildSource 'Invoke-NativeCommand' 'Exe build must check native dotnet publish with LASTEXITCODE.'
Assert-Contains $buildSource 'dotnet publish' 'Exe build must publish the installer project.'
Assert-Contains $buildSource 'test_pol_reloaded_portable_diagnostics\.ps1' 'Exe build must run the Reloaded portable diagnostics guard before embedding the payload.'
Assert-Contains $buildSource 'PublishSingleFile=true' 'Exe build must produce a single runnable installer exe.'
Assert-Contains $buildSource 'AccessXI Installer\.exe' 'Exe build must publish a user-facing AccessXI Installer.exe.'
Assert-Contains $buildSource 'setup-guide\.md' 'Exe build must publish setup-guide.md beside AccessXI Installer.exe.'

if (Test-Path -LiteralPath $PublishedExe) {
    $exe = Get-Item -LiteralPath $PublishedExe
    Assert-True ($exe.Length -gt 40000000) 'Published installer exe must be larger than the embedded payload zip.'
    $publishedGuide = Join-Path (Split-Path -Parent $PublishedExe) 'setup-guide.md'
    Assert-True (Test-Path -LiteralPath $publishedGuide) 'Published installer folder must include setup-guide.md beside the EXE.'
}

'ok: AccessXI installer exe structure is guarded.'
