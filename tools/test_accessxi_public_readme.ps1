param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-ContainsLiteral {
    param([string]$Text, [string]$Needle, [string]$Message)
    if (-not $Text.Contains($Needle)) { throw $Message }
}

function Assert-Before {
    param([string]$Text, [string]$Earlier, [string]$Later, [string]$Message)
    $earlierIndex = $Text.IndexOf($Earlier, [StringComparison]::Ordinal)
    $laterIndex = $Text.IndexOf($Later, [StringComparison]::Ordinal)
    if ($earlierIndex -lt 0 -or $laterIndex -lt 0 -or $earlierIndex -ge $laterIndex) { throw $Message }
}

$readmePath = Join-Path $RepoRoot 'README.md'
$oldGuidePath = Join-Path $RepoRoot 'setup-guide.md'
$packageScriptPath = Join-Path $RepoRoot 'tools\package_accessxi_installer.ps1'
$buildScriptPath = Join-Path $RepoRoot 'tools\build_accessxi_installer_exe.ps1'

Assert-True (Test-Path -LiteralPath $readmePath) "Missing public README: $readmePath"
Assert-True (-not (Test-Path -LiteralPath $oldGuidePath)) 'README.md must be the only maintained root setup guide.'

$readme = Get-Content -LiteralPath $readmePath -Raw
$packageScript = Get-Content -LiteralPath $packageScriptPath -Raw
$buildScript = Get-Content -LiteralPath $buildScriptPath -Raw

foreach ($requiredText in @(
    '# AccessXI',
    '## Setup',
    '### 1. Get Final Fantasy XI and prepare your account',
    '### 2. Install the official client',
    '### 3. Update PlayOnline before installing AccessXI',
    '### 4. Install AccessXI',
    '### 5. Add your PlayOnline member',
    '### 6. Log in and start Final Fantasy XI',
    'https://github.com/buu420/AccessXI/releases/latest',
    'FFXIFullSetup_US.part1.exe',
    'FFXISetup.exe',
    'all five download files in the same folder',
    'PlayOnline ID is not your Square Enix ID',
    'Use screen-reader OCR',
    'AccessXI Ashita',
    'automatically checks the public GitHub release',
    'SHA-256',
    'complete embedded package',
    'never installs a partial or mismatched download',
    'does not replace the running installer EXE',
    '## Hotkeys',
    '| `D` | Read current debuffs. |',
    '| `B` | Read current buffs. |',
    '| `H` | Read current and maximum HP. |',
    '| `M` | Read current and maximum MP. |',
    '| `X` | Read current experience and experience to next level. |',
    '| `I` | Start a route to the selected destination, or stop the active or pending route. |',
    '| `U` | Previous navigation category. |',
    '| `O` | Next navigation category. |',
    '| `J` | Previous item in the current navigation category. |',
    '| `K` | Repeat the current navigation item. |',
    '| `L` | Next item in the current navigation category. |',
    '| `J` | Previous line of the highlighted gear details. |',
    '| `K` | Repeat the current gear-detail line. |',
    '| `L` | Next line of the highlighted gear details. |',
    '| `Home` | Previous chat category. |',
    '| `End` | Next chat category. |',
    '| `Page Up` | Previous, older message in the selected chat category. |',
    '| `Page Down` | Next, newer message in the selected chat category. |',
    '| `Alt+I` | Read the current Status, Equipment, or Check overview. |',
    '| `Alt+Shift+I` | Read the selected row details in the Status menu. |',
    '| `Ctrl+Shift+C` | Open or close AccessXI Settings. |',
    '| `Ctrl+Shift+R` | Reload the AccessXI reader addon. |',
    '| `Ctrl+Shift+Numpad 8` | Previous AccessXI Settings item. |',
    '| `Ctrl+Shift+Numpad 2` | Next AccessXI Settings item. |',
    '| `Ctrl+Shift+Numpad 6` | Open or activate the AccessXI Settings item. |',
    '| `Ctrl+Shift+Numpad 4` | Go back in AccessXI Settings. |',
    '| `Ctrl+Shift+Numpad 5` | Repeat the current AccessXI Settings item. |',
    '| `Ctrl+Shift+Numpad 0` | Reload the AccessXI reader addon. |',
    'While AccessXI Settings is open, Up and Down move between items, Right or Enter opens or activates an item, Left goes back, and Escape closes the menu.',
    '| `Print Screen` | Take a screenshot with the game interface hidden. |',
    '| `Ctrl+V` | Paste clipboard text through Ashita. |',
    '| `F11` | Toggle Ashita ambient lighting. |',
    '| `F12` | Toggle the frames-per-second display. |',
    '| `Ctrl+F1` through `Ctrl+F6` | Target alliance slots `<a10>` through `<a15>`. |',
    '| `Alt+F1` through `Alt+F6` | Target alliance slots `<a20>` through `<a25>`. |'
)) {
    Assert-ContainsLiteral $readme $requiredText "README is missing required setup or hotkey text: $requiredText"
}

Assert-True (-not $readme.Contains('[setup-guide.md]')) 'README must not send users to a redundant second root guide.'

Assert-Before $readme '### 1. Get Final Fantasy XI and prepare your account' '### 3. Update PlayOnline before installing AccessXI' 'Account and game preparation must come before the PlayOnline update.'
Assert-Before $readme '### 3. Update PlayOnline before installing AccessXI' '### 4. Install AccessXI' 'The PlayOnline update must come before AccessXI installation.'
Assert-Before $readme '### 6. Log in and start Final Fantasy XI' '## Hotkeys' 'The hotkey reference must appear below the setup walkthrough.'

Assert-ContainsLiteral $packageScript '$publicGuide = Join-Path $RepoRoot ''README.md''' 'Package builder must source the offline setup guide from README.md.'
Assert-ContainsLiteral $packageScript 'Copy-RequiredFile -Source $publicGuide -Destination (Join-Path $packageRoot ''setup-guide.md'')' 'Package builder must publish README.md under the offline setup-guide.md name.'
Assert-ContainsLiteral $buildScript '$publicGuide = Join-Path $RepoRoot ''README.md''' 'EXE build must source the published guide from README.md.'
Assert-ContainsLiteral $buildScript 'Copy-Item -LiteralPath $publicGuide -Destination $publishedSetupGuide -Force' 'EXE build must publish README.md beside the EXE as setup-guide.md.'

'ok: public README setup order, hotkeys, and installer guide synchronization are guarded.'
