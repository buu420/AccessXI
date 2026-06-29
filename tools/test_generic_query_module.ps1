$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\generic_query.lua'

if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "Addon not found: $addonPath"
}

$source = Get-Content -LiteralPath $addonPath -Raw
$module = if (Test-Path -LiteralPath $modulePath) { Get-Content -LiteralPath $modulePath -Raw } else { '' }

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

if ($module -eq '') {
    throw 'Expected modules\menus\generic_query.lua to exist.'
}

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.generic_query_module_context\s*\(' `
    -Message 'Main addon should expose a narrow context object for the generic query menu module.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.load_menu_code_module\('generic_query',\s*accessxi\.generic_query_module_context\(\)\)" `
    -Message 'Main addon should load modules\menus\generic_query.lua through the existing code-module loader.'

Assert-NotMatch `
    -Text $source `
    -Pattern 'function\s+accessxi\.generic_query_menu_speech\s*\(' `
    -Message 'Generic query/NPC menu reader should not remain in the main addon file.'

Assert-Match `
    -Text $source `
    -Pattern 'accessxi\.generic_query_menu_speech\(name,\s*'''',\s*obj\)' `
    -Message 'current_menu_speech should continue dispatching to accessxi.generic_query_menu_speech.'

Assert-Match `
    -Text $module `
    -Pattern 'function\s+accessxi\.generic_query_menu_speech\s*\(menu_name,\s*title,\s*obj\)' `
    -Message 'Generic query module should install accessxi.generic_query_menu_speech.'

foreach ($dependency in @(
    'safe_call',
    'read_u8',
    'read_u32',
    'read_probe_string',
    'read_current_native_menu_index',
    'log_line',
    'log_state',
    'tick'
)) {
    Assert-Match `
        -Text $source `
        -Pattern ([regex]::Escape($dependency)) `
        -Message "Generic query module context should expose $dependency."

    Assert-Match `
        -Text $module `
        -Pattern ("ctx\.{0}" -f [regex]::Escape($dependency)) `
        -Message "Generic query module should take $dependency from its context."
}

Assert-Match `
    -Text $module `
    -Pattern 'state generic-query' `
    -Message 'Generic query module should preserve the existing debug log evidence.'

Assert-Match `
    -Text $module `
    -Pattern 'current_menu_speech_title\s*=\s*title' `
    -Message 'Generic query module should preserve title-prefix tracking.'

Assert-Match `
    -Text $module `
    -Pattern 'generic-query:%s:%s' `
    -Message 'Generic query module should preserve current speech key shape.'

Write-Host 'generic query module boundary static checks ok'
