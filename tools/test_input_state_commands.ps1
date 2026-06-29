$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$debugModulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\debug_commands.lua'

$source = Get-Content -LiteralPath $addonPath -Raw
$debugModule = Get-Content -LiteralPath $debugModulePath -Raw

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

function Slice-Function {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End
    )

    $startIndex = $Text.IndexOf($Start)
    if ($startIndex -lt 0) {
        throw "Could not locate function start: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex)
    if ($endIndex -lt 0) {
        throw "Could not locate function end after: $Start"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.input_state_text\s*\(' `
    -Message 'Expected /axi inputstate support function.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.input_fix_text\s*\(' `
    -Message 'Expected /axi inputfix support function.'

$stateFunction = Slice-Function `
    -Text $source `
    -Start 'function accessxi.input_state_text' `
    -End "`nfunction accessxi.input_fix_text"

foreach ($pattern in @(
    'GetInputManager\(\):GetKeyboard\(\)',
    'GetInputManager\(\):GetMouse\(\)',
    'GetBlockInput\(\)',
    'GetBlockBindsDuringInput\(\)',
    'GetMenuTargetLock\(\)',
    'GetIsPlayerMoving\(\)',
    'GetIsAutoRunning\(\)',
    'nav_position_speech\(nav_cached_player_position\(\)\)',
    'accessxi\.nav_zoning_watch_active\(now\)',
    'accessxi\.nav_zone_load_settle_active\(now\)',
    'is_chat_input_open\(\)',
    'get_menu_name\(\)',
    'accessxi\.nav_active',
    "log_line\('input state "
)) {
    Assert-Match -Text $stateFunction -Pattern $pattern -Message "Input state text should include $pattern."
}

$fixFunction = Slice-Function `
    -Text $source `
    -Start 'function accessxi.input_fix_text' `
    -End "`nfunction accessxi.debug_command_context"

Assert-Match `
    -Text $fixFunction `
    -Pattern '(?s)GetInputManager\(\):GetKeyboard\(\).*?SetBlockInput\(false\)' `
    -Message 'Input fix should clear Ashita keyboard Block Input when set.'

Assert-Match `
    -Text $fixFunction `
    -Pattern '(?s)GetBlockBindsDuringInput\(\).*?SetBlockBindsDuringInput\(false\)' `
    -Message 'Input fix should clear Ashita keyboard BlockBindsDuringInput when set.'

Assert-Match `
    -Text $fixFunction `
    -Pattern '(?s)GetInputManager\(\):GetMouse\(\).*?SetBlockInput\(false\)' `
    -Message 'Input fix should clear Ashita mouse Block Input when set.'

Assert-Match `
    -Text $fixFunction `
    -Pattern "accessxi\.nav_clear_zoning_watch\('inputfix'\)" `
    -Message 'Input fix should clear any stale nav zoning watch.'

Assert-Match `
    -Text $fixFunction `
    -Pattern "accessxi\.nav_clear_zone_load_settle\('inputfix'\)" `
    -Message 'Input fix should clear any stale post-zone load settle.'

Assert-Match `
    -Text $fixFunction `
    -Pattern 'nav_collision_quiet_until\s*=\s*0' `
    -Message 'Input fix should end the nav collision quiet state.'

Assert-Match `
    -Text $fixFunction `
    -Pattern 'nav_collision_require_fresh_movement\s*=\s*false' `
    -Message 'Input fix should clear the fresh-movement requirement.'

Assert-Match `
    -Text $fixFunction `
    -Pattern 'accessxi\.input_state_text\(\)' `
    -Message 'Input fix should report the live state after attempting the conservative recovery.'

Assert-NotMatch `
    -Text $fixFunction `
    -Pattern '/mouse\s+unhook|ashita_console_queue_command' `
    -Message 'Input fix should not run broad recovery commands.'

foreach ($alias in @(
    'inputstate',
    'movementstate',
    'inputdiag',
    'stuck',
    'inputfix',
    'unblockinput',
    'fixmovement'
)) {
    Assert-Match `
        -Text $debugModule `
        -Pattern ([regex]::Escape($alias)) `
        -Message "Debug command module should own /axi $alias."
}

Assert-Match `
    -Text $debugModule `
    -Pattern 'accessxi\.input_state_text\(\)' `
    -Message '/axi inputstate should speak the current live input state.'

Assert-Match `
    -Text $debugModule `
    -Pattern 'accessxi\.input_fix_text\(\)' `
    -Message '/axi inputfix should speak the conservative recovery result.'

Write-Host 'input state command static checks ok'
