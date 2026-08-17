param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
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

function Assert-Equal {
    param(
        [string]$Expected,
        [string]$Actual,
        [string]$Message
    )
    if ($Expected -ne $Actual) {
        throw "$Message Expected='$Expected'; Actual='$Actual'."
    }
}

$installerScript = Join-Path $RepoRoot 'installer\install_accessxi.ps1'
Assert-True (Test-Path -LiteralPath $installerScript -PathType Leaf) "Missing installer script: $installerScript"

# install_accessxi.ps1 performs a real install when executed, so load only its function
# definitions and exercise the detection helpers directly.
$parseTokens = $null
$parseErrors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseFile($installerScript, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "install_accessxi.ps1 failed to parse: $($parseErrors[0].Message)"
}

$functionDefinitions = $installerAst.FindAll(
    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
    $false)
Assert-True ($functionDefinitions.Count -gt 0) 'install_accessxi.ps1 defines no functions.'
. ([scriptblock]::Create((($functionDefinitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")))

$steamLibraryRoot = 'D:\SteamLibrary'
$steamViewerRoot = 'C:\Program Files (x86)\Steam\steamapps\common\FFXINA\SquareEnix\PlayOnlineViewer'

# The Steam release lives under steamapps\common, which no Program Files probe can reach.
$candidates = @(Get-DefaultPolExeCandidates `
    -RegistryViewerRoots @() `
    -SteamLibraryRoots @($steamLibraryRoot) `
    -ProgramFilesRoots @('C:\Program Files (x86)'))
# [System.IO.Path]::Combine because D: is deliberately an unmounted drive here.
$expectedSteamCandidate = [System.IO.Path]::Combine($steamLibraryRoot, 'steamapps\common\FFXINA\SquareEnix\PlayOnlineViewer\pol.exe')
Assert-True ($candidates -contains $expectedSteamCandidate) `
    "The Steam FFXI layout must be probed for pol.exe. Candidates: $($candidates -join '; ')"

# The registry records the viewer folder that actually exists, so it must win over the guesses.
$candidates = @(Get-DefaultPolExeCandidates `
    -RegistryViewerRoots @($steamViewerRoot) `
    -SteamLibraryRoots @($steamLibraryRoot) `
    -ProgramFilesRoots @('C:\Program Files (x86)'))
Assert-True ($candidates.Count -gt 0) 'Expected at least one pol.exe candidate.'
Assert-Equal (Join-Path $steamViewerRoot 'pol.exe') $candidates[0] `
    'The PlayOnline Viewer folder reported by the registry must be probed first.'

# Steam escapes path separators in libraryfolders.vdf.
$libraryFoldersVdf = @"
"libraryfolders"
{
    "0"
    {
        "path"		"C:\\Program Files (x86)\\Steam"
        "label"		""
    }
    "1"
    {
        "path"		"D:\\SteamLibrary"
    }
}
"@
$libraryRoots = @(Get-SteamLibraryRootsFromVdf -LibraryFoldersVdf $libraryFoldersVdf)
Assert-Equal '2' ([string]$libraryRoots.Count) 'Every Steam library folder must be discovered.'
Assert-True ($libraryRoots -contains 'C:\Program Files (x86)\Steam') 'The default Steam library must be parsed with unescaped separators.'
Assert-True ($libraryRoots -contains 'D:\SteamLibrary') 'Secondary Steam libraries on other drives must be parsed.'

# FFXI sits beside PlayOnlineViewer in the Steam layout too, so the Ashita boot path stays correct.
Assert-Equal 'C:\Program Files (x86)\Steam\steamapps\common\FFXINA\SquareEnix\FINAL FANTASY XI' `
    (Get-FfxiInstallRootFromPolExe -PolExe (Join-Path $steamViewerRoot 'pol.exe')) `
    'A Steam pol.exe must resolve to the Steam copy of the FFXI install root.'

# End to end against a fake Steam library on disk.
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("AccessXISteamDetection-" + [guid]::NewGuid().ToString('N'))
try {
    $fakeViewer = Join-Path $sandbox 'SteamLibrary\steamapps\common\FFXINA\SquareEnix\PlayOnlineViewer'
    New-Item -ItemType Directory -Force -Path $fakeViewer | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeViewer 'pol.exe') -Value 'fake-pol' -Encoding ASCII

    $found = Find-DefaultPolExe `
        -RegistryViewerRoots @() `
        -SteamLibraryRoots @((Join-Path $sandbox 'SteamLibrary')) `
        -ProgramFilesRoots @((Join-Path $sandbox 'NoSuchProgramFiles'))
    Assert-Equal (Join-Path $fakeViewer 'pol.exe') $found 'Find-DefaultPolExe must locate a Steam library install.'

    # An unknown depot folder name still has to resolve.
    $unknownViewer = Join-Path $sandbox 'SteamLibrary\steamapps\common\FFXI Unknown Depot\SquareEnix\PlayOnlineViewer'
    New-Item -ItemType Directory -Force -Path $unknownViewer | Out-Null
    Set-Content -LiteralPath (Join-Path $unknownViewer 'pol.exe') -Value 'fake-pol' -Encoding ASCII
    Remove-Item -Recurse -Force (Join-Path $sandbox 'SteamLibrary\steamapps\common\FFXINA')

    $found = Find-DefaultPolExe `
        -RegistryViewerRoots @() `
        -SteamLibraryRoots @((Join-Path $sandbox 'SteamLibrary')) `
        -ProgramFilesRoots @((Join-Path $sandbox 'NoSuchProgramFiles'))
    Assert-Equal (Join-Path $unknownViewer 'pol.exe') $found 'Find-DefaultPolExe must scan steamapps\common for unknown depot folder names.'

    # Nothing installed must stay an empty result rather than a wrong guess.
    $found = Find-DefaultPolExe `
        -RegistryViewerRoots @() `
        -SteamLibraryRoots @((Join-Path $sandbox 'NoSuchLibrary')) `
        -ProgramFilesRoots @((Join-Path $sandbox 'NoSuchProgramFiles'))
    Assert-Equal '' $found 'Find-DefaultPolExe must return an empty string when no pol.exe exists.'
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $sandbox -ErrorAction SilentlyContinue
}

Write-Host 'ok: AccessXI installer detects Steam, registry, and Program Files PlayOnline layouts.'
