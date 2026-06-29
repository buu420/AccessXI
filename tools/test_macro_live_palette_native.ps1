$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

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

function Block-Between {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End,
        [Parameter(Mandatory = $true)][string]$MissingStartMessage,
        [Parameter(Mandatory = $true)][string]$MissingEndMessage
    )

    $startIndex = $Text.IndexOf($Start)
    if ($startIndex -lt 0) {
        throw $MissingStartMessage
    }
    $endIndex = $Text.IndexOf($End, $startIndex)
    if ($endIndex -lt 0) {
        throw $MissingEndMessage
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

$rowBlock = Block-Between `
    -Text $source `
    -Start 'function accessxi.macro_live_palette_row(menu_name)' `
    -End "`nfunction accessxi.macro_live_palette_header" `
    -MissingStartMessage 'Missing macro live palette row helper.' `
    -MissingEndMessage 'Could not locate end of macro live palette row helper.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.is_macro_live_palette_menu_name\(menu_name\).*?mcr1pall.*?mcr2pall.*?mcr1long.*?mcr2long" `
    -Message 'Macro live palette menu helper should include both regular and long macro palette menu names.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_title\(name\).*?is_macro_live_palette_menu_name\(name\).*?Macro Palette" `
    -Message 'Native title lookup should recognize long macro palette menu names before they fall into unsupported-menu logging.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech\(name\).*?is_macro_live_palette_menu_name\(menu_name\).*?read_current_native_menu_index\(0x4C\).*?is_macro_live_palette_menu_name\(menu_name\).*?macro_live_palette_speech" `
    -Message 'Native known-menu speech should route all live macro palette menu names through the macro live palette reader.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.log_macro_palette_menu_probe\(menu_name.*?is_macro_live_palette_menu_name\(menu_name\)" `
    -Message 'Macro palette probe should include long live macro palette menu names.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.file_last_write_time\(path\)' `
    -Message 'Macro profile selection should be able to compare native USER profile file write times.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.macro_profile_last_write_score\(profile_dir\)' `
    -Message 'Macro active profile selection should score profiles by recently written native macro/AIX files, not only macro file count.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.macro_active_profile\(\).*?macro_profile_last_write_score\(dir\).*?best_write" `
    -Message 'Macro active profile selection should prefer the most recently touched native USER profile before macro-file count.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.is_macro_edit_menu_name\(menu_name\).*?mcr1edit.*?mcr2edit.*?mcr1edlo.*?mcr2edlo" `
    -Message 'Macro edit menu helper should include the native edlo edit-menu aliases from the menu atlas.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_title\(name\).*?is_macro_edit_menu_name\(name\).*?Edit Macro Book" `
    -Message 'Native title lookup should recognize mcr1edlo/mcr2edlo as Edit Macro Book menus.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech\(name\).*?is_macro_edit_menu_name\(menu_name\).*?read_current_native_menu_index\(0x4C\).*?is_macro_edit_menu_name\(menu_name\).*?macro_edit_menu_speech" `
    -Message 'Native known-menu speech should route all macro edit menu aliases through the macro edit reader.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.macro_slot_from_menu\(menu_name,\s*selected\).*?mcr1edlo.*?return selected,\s*'Ctrl'.*?mcr2edlo.*?return selected \+ 10,\s*'Alt'" `
    -Message 'Macro edit slot mapping should treat mcr1edlo/mcr2edlo like the existing Ctrl/Alt edit menus.'

Assert-Match `
    -Text $rowBlock `
    -Pattern "(?s)mcr1pall.*?mcr1long.*?return 'Ctrl',\s*0" `
    -Message 'Ctrl macro palette row should accept both mcr1pall and mcr1long.'

Assert-Match `
    -Text $rowBlock `
    -Pattern "(?s)mcr2pall.*?mcr2long.*?return 'Alt',\s*10" `
    -Message 'Alt macro palette row should accept both mcr2pall and mcr2long.'

Write-Host 'Macro live palette native menu tests passed.'
