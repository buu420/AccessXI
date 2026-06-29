$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$debugModulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\debug_commands.lua'

if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "Addon not found: $addonPath"
}

$source = Get-Content -LiteralPath $addonPath -Raw
$debugModule = if (Test-Path -LiteralPath $debugModulePath) { Get-Content -LiteralPath $debugModulePath -Raw } else { '' }

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

if ($debugModule -eq '') {
    throw 'Expected modules\debug_commands.lua to exist.'
}

Assert-Match `
    -Text $source `
    -Pattern "debug_commands\s*=\s*accessxi\.load_module_table\('debug_commands'" `
    -Message 'Main addon should load the debug command module through the existing module loader.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.debug_command_context\s*\(' `
    -Message 'Main addon should expose a narrow context object for debug commands instead of letting the module depend on locals.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.handle_axi_command\(args,\s*e,\s*source\).*?accessxi\.debug_commands\.handle\(args,\s*accessxi\.debug_command_context\(\)\)" `
    -Message 'Shared AXI command dispatcher should delegate debug/probe commands to modules\debug_commands.lua.'

Assert-Match `
    -Text $debugModule `
    -Pattern 'function\s+debug_commands\.handle\s*\(args,\s*ctx\)' `
    -Message 'Debug command module should export handle(args, ctx).'

Assert-Match `
    -Text $debugModule `
    -Pattern 'ctx\.speak' `
    -Message 'Debug command module should use ctx.speak rather than a hidden main-file local.'

Assert-Match `
    -Text $debugModule `
    -Pattern 'ctx\.log_line' `
    -Message 'Debug command module should use ctx.log_line rather than a hidden main-file local.'

Assert-Match `
    -Text $debugModule `
    -Pattern 'ctx\.tick' `
    -Message 'Debug command module should use ctx.tick rather than a hidden main-file local.'

foreach ($alias in @(
    'missiontext',
    'keyitemprobe',
    'friendprobe',
    'currencyprobe',
    'equipprobe',
    'chattrace',
    'sgscan',
    'menudump'
)) {
    Assert-Match `
        -Text $debugModule `
        -Pattern ([regex]::Escape($alias)) `
        -Message "Debug command module should own /axi $alias."
}

$commandStart = $source.IndexOf('function accessxi.handle_axi_command')
if ($commandStart -lt 0) {
    throw 'Missing shared AXI command handler.'
}
$commandEnd = $source.IndexOf('function accessxi.dispatch_axi_command_text', $commandStart)
if ($commandEnd -lt 0) {
    throw 'Could not locate end of shared AXI command handler.'
}
$commandBody = $source.Substring($commandStart, $commandEnd - $commandStart)

foreach ($alias in @(
    'missiontext',
    'keyitemprobe',
    'friendprobe',
    'currencyprobe',
    'equipprobe',
    'chattrace',
    'sgscan',
    'menudump'
)) {
    Assert-NotMatch `
        -Text $commandBody `
        -Pattern ([regex]::Escape($alias)) `
        -Message "Main command handler should not contain probe alias /axi $alias."
}

Assert-Match `
    -Text $commandBody `
    -Pattern "'nav', 'navigation', 'dest'" `
    -Message 'Normal navigation commands should remain in the main command handler for now.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)ashita\.events\.register\('command'.*?accessxi\.handle_axi_command\(args,\s*e,\s*'event'\)" `
    -Message 'Command event wrapper should route through the shared AXI command handler.'

Write-Host 'debug command module boundary static checks ok'
