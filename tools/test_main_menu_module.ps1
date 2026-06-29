$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\main_menu.lua'

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
    throw 'Expected modules\menus\main_menu.lua to exist.'
}

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.main_menu_module_context\s*\(' `
    -Message 'Main addon should expose a narrow context object for the native main menu module.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.load_menu_code_module\('main_menu',\s*accessxi\.main_menu_module_context\(\)\)" `
    -Message 'Main addon should load modules\menus\main_menu.lua through the existing code-module loader.'

Assert-NotMatch `
    -Text $source `
    -Pattern 'local\s+function\s+native_main_menu_speech\s*\(' `
    -Message 'Native main menu reader should not remain as a local function in the main addon file.'

Assert-Match `
    -Text $source `
    -Pattern 'accessxi\.native_main_menu_speech\(name\)' `
    -Message 'current_menu_speech should dispatch to the module-installed accessxi.native_main_menu_speech.'

Assert-Match `
    -Text $module `
    -Pattern 'function\s+accessxi\.native_main_menu_speech\s*\(name\)' `
    -Message 'Main menu module should install accessxi.native_main_menu_speech.'

foreach ($dependency in @(
    'get_current_menu_object_ptr',
    'read_current_native_menu_index',
    'read_u32',
    'read_probe_string',
    'log_state',
    'tick'
)) {
    Assert-Match `
        -Text $source `
        -Pattern ([regex]::Escape($dependency)) `
        -Message "Main menu module context should expose $dependency."

    Assert-Match `
        -Text $module `
        -Pattern ("ctx\.{0}" -f [regex]::Escape($dependency)) `
        -Message "Main menu module should take $dependency from its context."
}

Assert-Match `
    -Text $module `
    -Pattern 'state mainmenu entry' `
    -Message 'Main menu module should preserve the existing debug log evidence.'

Assert-Match `
    -Text $module `
    -Pattern 'main-menu-dat-mog-house' `
    -Message 'Main menu module should preserve Mog House DAT-backed label handling.'

Assert-Match `
    -Text $module `
    -Pattern 'Main menu\. %s %s' `
    -Message 'Main menu module should preserve row speech format before central title-prefix suppression.'

Write-Host 'main menu module boundary static checks ok'
