param(
    [string]$AddonPath = "C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AddonPath)) {
    throw "Addon not found: $AddonPath"
}

$source = Get-Content -LiteralPath $AddonPath -Raw

function Assert-Match {
    param(
        [string]$Pattern,
        [string]$Message
    )

    if ($source -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [string]$Pattern,
        [string]$Message
    )

    if ($source -match $Pattern) {
        throw $Message
    }
}

Assert-Match 'function\s+accessxi\.ashita_console_categories\s*\(' 'Missing Ashita console accessible category model.'
Assert-Match 'function\s+accessxi\.ashita_console_command\s*\(' 'Missing /axi console accessible command handler.'
Assert-Match 'function\s+accessxi\.ashita_console_open_menu\s*\(' 'Missing interactive Ashita console menu opener.'
Assert-Match 'function\s+accessxi\.ashita_console_handle_key\s*\(' 'Missing interactive Ashita console key handler.'
Assert-Match 'function\s+accessxi\.ashita_console_activate_current\s*\(' 'Missing Ashita console activation handler.'
Assert-Match 'function\s+accessxi\.poll_ashita_console_hotkeys\s*\(' 'Missing Control+Shift+Numpad console hotkey polling.'
Assert-Match 'function\s+accessxi\.ashita_console_reload_addon\s*\(' 'Missing safe AccessXI reload action.'
Assert-Match 'accessxi\.ashita_console_open' 'Missing Ashita console open state.'
Assert-Match 'accessxi\.ashita_console_command\(args\)' '/axi console must route through the accessible console reader.'
Assert-Match "QueueCommand\(1,\s*'/ashita'\)" 'Ctrl+Shift+C should still toggle the real Ashita settings window.'
Assert-Match "/addon reload accessxi_reader" 'Missing direct AccessXI reload command action.'
Assert-Match 'VK_NUMPAD8' 'Missing Control+Shift+Numpad up key support.'
Assert-Match 'VK_NUMPAD2' 'Missing Control+Shift+Numpad down key support.'
Assert-Match 'VK_NUMPAD6' 'Missing Control+Shift+Numpad open/activate key support.'
Assert-Match 'VK_NUMPAD4' 'Missing Control+Shift+Numpad back key support.'
Assert-Match 'VK_NUMPAD0' 'Missing Control+Shift+Numpad reload key support.'

foreach ($label in @(
    'Version Information',
    'ChatManager Settings',
    'Direct3D Settings',
    'Keyboard Settings',
    'Controller (Gamepad) Settings',
    'Mouse Settings',
    'LogManager Settings',
    'Plugin & PolPlugin Manager Settings',
    'Font & Primitive Manager Settings',
    'Current Keybinds'
)) {
    Assert-Match -Pattern ([regex]::Escape($label)) -Message "Missing native Ashita settings label: $label"
}

foreach ($api in @(
    'GetSilentAliases',
    'GetInputManager',
    'GetPluginManager',
    'GetPolPluginManager',
    'GetFontManager',
    'GetPrimitiveManager'
)) {
    Assert-Match $api "Missing state-backed Ashita API usage: $api"
}

Assert-Match 'state ashita-console' 'Missing Ashita console state logging.'
Assert-Match '(?s)if\s*\(accessxi\.ashita_console_open\s+and\s+accessxi\.ashita_console_handle_key\(key\)\)\s*then\s*e\.blocked\s*=\s*true' 'Interactive Ashita console must block handled navigation keys from reaching the game.'
Assert-Match 'poll_ashita_console_hotkeys\(\)\)\s*then\s*return' 'd3d_present must give console hotkeys priority while active.'
Assert-NotMatch "local\s+text\s*=\s*ok\s+and\s+'Ashita console toggled\.'\s+or\s+'Unable to toggle Ashita console\.'" 'Console reader regressed to toggle-only speech.'

Write-Host 'ashita console accessible test passed'
