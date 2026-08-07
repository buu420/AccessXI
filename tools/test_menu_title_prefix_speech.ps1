$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$mainMenuModulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\main_menu.lua'
$genericQueryModulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\generic_query.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$mainMenuModule = if (Test-Path -LiteralPath $mainMenuModulePath) { Get-Content -LiteralPath $mainMenuModulePath -Raw } else { '' }
$genericQueryModule = if (Test-Path -LiteralPath $genericQueryModulePath) { Get-Content -LiteralPath $genericQueryModulePath -Raw } else { '' }
$menuSpeechSource = $source + "`n" + $mainMenuModule + "`n" + $genericQueryModule

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

Assert-Match `
    -Text $source `
    -Pattern 'current_menu_speech_title\s*=\s*''''[,\r\n]' `
    -Message 'Menu speech should track the current native title separately from the spoken row text.'

Assert-Match `
    -Text $source `
    -Pattern 'menu_title_prefix_spoken_key\s*=\s*''''[,\r\n]' `
    -Message 'Menu title prefix suppression should remember which title was already announced for this menu entry.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.menu_row_speech_without_repeated_title\s*\(' `
    -Message 'Expected a central helper that removes repeated menu title prefixes from row speech.'

$helperStart = $source.IndexOf('function accessxi.menu_row_speech_without_repeated_title')
if ($helperStart -lt 0) {
    throw 'Missing menu title prefix helper.'
}
$helperEnd = $source.IndexOf("`nfunction ", $helperStart + 1)
if ($helperEnd -lt 0) {
    throw 'Could not locate end of menu title prefix helper.'
}
$helperBody = $source.Substring($helperStart, $helperEnd - $helperStart)

Assert-Match `
    -Text $helperBody `
    -Pattern 'current_menu_speech_title' `
    -Message 'Menu title prefix helper should use the title captured by the native menu handler.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'last_menu_transition_tick' `
    -Message 'Menu title prefix helper should allow the title to speak once per menu entry, not once forever.'

Assert-Match `
    -Text $helperBody `
    -Pattern "title\s*\.\.\s*'\.'" `
    -Message 'Menu title prefix helper should strip only an exact title prefix, not guess the first sentence.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'state menu-title-prefix suppressed' `
    -Message 'Suppressed menu title prefixes should remain visible in debug logs.'

Assert-Match `
    -Text $menuSpeechSource `
    -Pattern "(?s)function\s+accessxi\.native_main_menu_speech.*?current_menu_speech_title\s*=\s*'Main menu'" `
    -Message 'Main menu speech should expose Main menu as the title prefix source.'

Assert-Match `
    -Text $menuSpeechSource `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?current_menu_speech_title\s*=\s*title" `
    -Message 'Native known menu speech should expose its resolved title prefix source.'

Assert-Match `
    -Text $menuSpeechSource `
    -Pattern "(?s)function\s+accessxi\.generic_query_menu_speech.*?current_menu_speech_title\s*=\s*title" `
    -Message 'Generic query/NPC menu speech should expose the live window title prefix source.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local\s+(?:ok_roe_text,\s*)?roe_text\s*=\s*(?:pcall\(\s*)?current_menu_speech(?:\s*\))?.*?roe_text\s*=\s*accessxi\.menu_row_speech_without_repeated_title\(roe_text,\s*menu_name,\s*roe_key\)" `
    -Message 'Records of Eminence fast-path row speech should use the central repeated-title suppressor.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local\s+(?:ok_text,\s*)?text\s*=\s*(?:pcall\(\s*)?current_menu_speech(?:\s*\))?.*?text\s*=\s*accessxi\.menu_row_speech_without_repeated_title\(text,\s*menu_name,\s*key\)" `
    -Message 'Normal menu row speech should use the central repeated-title suppressor before speaking/logging.'

Write-Host 'menu title prefix speech static checks ok'
