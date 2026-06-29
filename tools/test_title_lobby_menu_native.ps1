$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$nativeMenusPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\native_menus.lua'

if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "Addon not found: $addonPath"
}
if (-not (Test-Path -LiteralPath $nativeMenusPath)) {
    throw "Native menu module not found: $nativeMenusPath"
}

$source = Get-Content -LiteralPath $addonPath -Raw
$nativeMenus = Get-Content -LiteralPath $nativeMenusPath -Raw

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

Assert-Match `
    -Text $nativeMenus `
    -Pattern 'title_lobby_menu_resources\s*=\s*T\{' `
    -Message 'Title lobby menu should have an explicit resource-backed data block.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)\[4\]\s*=\s*\{\s*label\s*=\s*'Config'.*?label_dat\s*=\s*'ROM\\\\165\\\\72\.DAT'.*?label_row\s*=\s*198.*?help_dat\s*=\s*'ROM\\\\165\\\\75\.DAT'.*?help_row\s*=\s*474" `
    -Message 'Title lobby select=4 must be Config, backed by the Config DAT label/help rows.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)\[3\]\s*=\s*\{\s*label\s*=\s*'Back'.*?label_dat\s*=\s*'ROM\\\\165\\\\72\.DAT'.*?label_row\s*=\s*199.*?help_dat\s*=\s*'ROM\\\\165\\\\71\.DAT'.*?help_row\s*=\s*102" `
    -Message 'Title lobby select=3 must be Back, backed by the Back DAT label/help rows.'

Assert-NotMatch `
    -Text $nativeMenus `
    -Pattern 'Content ID' `
    -Message 'Title lobby resource data must not include the old guessed Content ID label.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_lobby_menu_entry\s*\(' `
    -Message 'Addon should resolve title lobby rows through a dedicated title_lobby_menu_entry helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_lobby_menu_speech\s*\(' `
    -Message 'Addon should have a dedicated title lobby speech handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)name:eq\('menu    loby2win', true\).*?accessxi\.title_lobby_menu_speech\(selected\)" `
    -Message 'loby2win must dispatch to the dedicated title lobby speech handler.'

Assert-NotMatch `
    -Text $source `
    -Pattern "(?s)name:eq\('menu    loby2win', true\).*?main_menu_option_from_index" `
    -Message 'loby2win must not reuse the stale main_menu_option_from_index mapping.'

$lobbyStart = $source.IndexOf('function accessxi.title_lobby_menu_entry')
if ($lobbyStart -lt 0) {
    throw 'Missing title_lobby_menu_entry helper.'
}
$lobbyEnd = $source.IndexOf("`nfunction accessxi.title_lobby_menu_speech", $lobbyStart)
if ($lobbyEnd -lt 0) {
    throw 'Could not locate end of title_lobby_menu_entry helper.'
}
$lobbyBody = $source.Substring($lobbyStart, $lobbyEnd - $lobbyStart)

Assert-Match `
    -Text $lobbyBody `
    -Pattern 'accessxi\.native_menus_data\.title_lobby_menu_resources' `
    -Message 'Title lobby helper should use native_menus title_lobby_menu_resources.'

Assert-Match `
    -Text $lobbyBody `
    -Pattern 'accessxi\.dat_index_row_text\(spec\.label_dat,\s*spec\.label_row,\s*''label''\)' `
    -Message 'Title lobby helper should resolve DAT-backed labels through dat_index_row_text.'

Assert-Match `
    -Text $lobbyBody `
    -Pattern 'accessxi\.dat_index_row_text\(spec\.help_dat,\s*spec\.help_row,\s*''help''\)' `
    -Message 'Title lobby helper should resolve DAT-backed help through dat_index_row_text.'

Assert-NotMatch `
    -Text $lobbyBody `
    -Pattern 'Content ID' `
    -Message 'Title lobby helper must not contain the old guessed Content ID label.'

$speechStart = $source.IndexOf('function accessxi.title_lobby_menu_speech')
if ($speechStart -lt 0) {
    throw 'Missing title_lobby_menu_speech handler.'
}
$speechEnd = $source.IndexOf("`nlocal function license_speech_from_index", $speechStart)
if ($speechEnd -lt 0) {
    $speechEnd = $source.IndexOf("`nfunction", $speechStart + 1)
}
if ($speechEnd -lt 0) {
    throw 'Could not locate end of title_lobby_menu_speech handler.'
}
$speechBody = $source.Substring($speechStart, $speechEnd - $speechStart)

Assert-Match `
    -Text $speechBody `
    -Pattern 'state title-lobby select=%d label="%s" help="%s" source="%s"' `
    -Message 'Title lobby speech should log selected native/resource row evidence.'

Assert-Match `
    -Text $speechBody `
    -Pattern "\('Main menu\. %s\. %s\.'\):fmt\(entry\.label,\s*entry\.help\)" `
    -Message 'Title lobby speech should include available resource-backed footer help text.'

Assert-NotMatch `
    -Text $speechBody `
    -Pattern 'Content ID' `
    -Message 'Title lobby speech must not contain the old guessed Content ID label.'

Write-Host 'title lobby menu native/resource static checks ok'
