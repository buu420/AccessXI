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
    -Pattern 'title_config_menu_resources\s*=\s*T\{' `
    -Message 'Title config menu should have a dedicated resource-backed data block.'

Assert-NotMatch `
    -Text $nativeMenus `
    -Pattern "(?s)data\.config_family_menus\s*=\s*T\{.*?lobycwin" `
    -Message 'lobycwin must not be folded into the in-game config family.'

foreach ($case in @(
    @{ Index = 0; Dat = 'ROM\\\\97\\\\36\.DAT'; Row = 251; Name = 'current version title music' },
    @{ Index = 8; Dat = 'ROM\\\\97\\\\36\.DAT'; Row = 245; Name = 'title music volume' },
    @{ Index = 9; Dat = 'ROM\\\\97\\\\36\.DAT'; Row = 246; Name = 'logout title screen' },
    @{ Index = 10; Dat = 'ROM\\\\97\\\\36\.DAT'; Row = 247; Name = 'logout character select' },
    @{ Index = 11; Dat = 'ROM\\\\97\\\\36\.DAT'; Row = 248; Name = 'background aspect ratio' },
    @{ Index = 14; Dat = 'ROM\\\\165\\\\75\.DAT'; Row = 1092; Name = 'gamepad settings' }
)) {
    Assert-Match `
        -Text $nativeMenus `
        -Pattern ("(?s)\[{0}\]\s*=\s*\{{.*?help_dat\s*=\s*'{1}'.*?help_row\s*=\s*{2}" -f $case.Index, $case.Dat, $case.Row) `
        -Message ("Title config focus index {0} should be backed by DAT help for {1}." -f $case.Index, $case.Name)
}

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_selected\s*\(' `
    -Message 'Addon should have a dedicated native focus reader for the title config menu.'

$selectedStart = $source.IndexOf('function accessxi.title_config_menu_selected')
if ($selectedStart -lt 0) {
    throw 'Missing title_config_menu_selected helper.'
}
$selectedEnd = $source.IndexOf("`nfunction accessxi.title_config_menu_entry", $selectedStart)
if ($selectedEnd -lt 0) {
    throw 'Could not locate end of title_config_menu_selected helper.'
}
$selectedBody = $source.Substring($selectedStart, $selectedEnd - $selectedStart)

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.survival_guide_query_child_state_for_obj\(obj\)' `
    -Message 'Title config selection may use the child-backed state for supporting count evidence.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.title_config_menu_focus_record\(obj\)' `
    -Message 'Title config selection should use the selected entry descriptor record, not a guessed object cursor.'

Assert-NotMatch `
    -Text $selectedBody `
    -Pattern 'read_i32\(obj\s*\+\s*0x4C\)' `
    -Message 'Title config selection must not use obj+0x4C; live evidence showed it is the current setting value, not the row cursor.'

Assert-NotMatch `
    -Text $selectedBody `
    -Pattern 'selected\s*=\s*query_selected\s*-\s*1' `
    -Message 'Title config selection must not prefer the child query cursor; live evidence showed it stays on row 1.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'read_i32\(obj\s*\+\s*0x24\)' `
    -Message 'Title config count should use the lobycwin count field obj+0x24.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'read_i32\(obj\s*\+\s*0x6C\)' `
    -Message 'Title config title-music choice should use the native DAT help-row field obj+0x6C only when the title-music control is focused.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'read_i32\(obj\s*\+\s*0x5C\)' `
    -Message 'Title config logout destination should use the native logout state field obj+0x5C only when the logout control is focused.'

Assert-NotMatch `
    -Text $selectedBody `
    -Pattern 'read_i32\(obj\s*\+\s*0x2C\)' `
    -Message 'Title config selection must not use obj+0x2C; live arrowing showed that field stays pinned to the opening row.'

foreach ($case in @(
    @{ Y = '0x26'; Name = 'title music' },
    @{ Y = '0x4E'; Name = 'title music and sound effects volume' },
    @{ Y = '0x73'; Name = 'logout destination' },
    @{ Y = '0x9A'; Name = 'background aspect ratio' },
    @{ Y = '0xBF'; Name = 'gamepad settings' }
)) {
    Assert-Match `
        -Text $selectedBody `
        -Pattern ("record_y\s*==\s*{0}" -f $case.Y) `
        -Message ("Title config selection should map native descriptor y={0} for {1}." -f $case.Y, $case.Name)
}

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_focus_record\s*\(' `
    -Message 'Addon should have a dedicated helper for the selected title config descriptor record.'

$focusStart = $source.IndexOf('function accessxi.title_config_menu_focus_record')
if ($focusStart -lt 0) {
    throw 'Missing title_config_menu_focus_record helper.'
}
$focusEnd = $source.IndexOf("`nfunction accessxi.title_config_menu_selected", $focusStart)
if ($focusEnd -lt 0) {
    throw 'Could not locate end of title_config_menu_focus_record helper.'
}
$focusBody = $source.Substring($focusStart, $focusEnd - $focusStart)

Assert-Match `
    -Text $focusBody `
    -Pattern 'read_u32\(obj\s*\+\s*0x08\)' `
    -Message 'Title config focus helper should start from the selected native entry pointer at obj+0x08.'

Assert-Match `
    -Text $focusBody `
    -Pattern 'read_u32\(entry\s*\+\s*0x0C\)' `
    -Message 'Title config focus helper should follow the entry descriptor at entry+0x0C.'

Assert-Match `
    -Text $focusBody `
    -Pattern 'read_u32\(desc0c\s*\+\s*0x00\)' `
    -Message 'Title config focus helper should read the selected descriptor record pointer.'

Assert-Match `
    -Text $focusBody `
    -Pattern 'read_u32\(record\s*\+\s*0x04\)' `
    -Message 'Title config focus helper should read the native descriptor y-position from record+0x04.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_entry\s*\(' `
    -Message 'Addon should resolve title config focus rows through a dedicated helper.'

$entryStart = $source.IndexOf('function accessxi.title_config_menu_entry')
if ($entryStart -lt 0) {
    throw 'Missing title_config_menu_entry helper.'
}
$entryEnd = $source.IndexOf("`nfunction accessxi.title_config_menu_speech", $entryStart)
if ($entryEnd -lt 0) {
    throw 'Could not locate end of title_config_menu_entry helper.'
}
$entryBody = $source.Substring($entryStart, $entryEnd - $entryStart)

Assert-Match `
    -Text $entryBody `
    -Pattern 'accessxi\.native_menus_data\.title_config_menu_resources' `
    -Message 'Title config helper should use native_menus title_config_menu_resources.'

Assert-Match `
    -Text $entryBody `
    -Pattern 'accessxi\.dat_index_row_text\(spec\.help_dat,\s*spec\.help_row,\s*''help''\)' `
    -Message 'Title config helper should resolve DAT-backed help through dat_index_row_text.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_speech\s*\(' `
    -Message 'Addon should have a dedicated title config speech handler.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_probe_signature\s*\(' `
    -Message 'Title config should have a narrow native-field probe for identifying the live focus field.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_probe_fields\s*\(' `
    -Message 'Title config should log wider native object fields to locate the real row cursor.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_probe_field_chunks\s*\(' `
    -Message 'Title config should split native object fields into non-truncated probe chunks.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_probe_descriptor\s*\(' `
    -Message 'Title config should probe selected entry descriptor/native text chains before choosing a row signal.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.title_config_menu_probe_pointer_texts\s*\(' `
    -Message 'Title config should log pointer-backed native strings when available.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_title_config_menu_probe\s*\(' `
    -Message 'Title config should log field changes while lobycwin is open.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_title_config_menu_focus\s*\(' `
    -Message 'Title config should have a lightweight focus log for normal speech.'

Assert-Match `
    -Text $source `
    -Pattern 'querySelected=%d queryCount=%d raw=0x%08X child=0x%08X' `
    -Message 'Title config probe should log child-query state separately from the row cursor.'

Assert-Match `
    -Text $source `
    -Pattern 'state title-config probe-fields obj=0x%08X prefix="%s" part=%d fields="%s"' `
    -Message 'Title config probe should emit chunked field lines instead of only one truncated signature.'

Assert-Match `
    -Text $source `
    -Pattern 'state title-config probe-desc obj=0x%08X entry=0x%08X desc04=0x%08X desc0C=0x%08X record=0x%08X' `
    -Message 'Title config probe should emit descriptor-chain evidence for the selected entry.'

$speechStart = $source.IndexOf('function accessxi.title_config_menu_speech')
if ($speechStart -lt 0) {
    throw 'Missing title_config_menu_speech handler.'
}
$speechEnd = $source.IndexOf("`nfunction accessxi.title_lobby_menu_entry", $speechStart)
if ($speechEnd -lt 0) {
    throw 'Could not locate end of title_config_menu_speech handler.'
}
$speechBody = $source.Substring($speechStart, $speechEnd - $speechStart)

Assert-Match `
    -Text $speechBody `
    -Pattern 'accessxi\.log_title_config_menu_focus\(obj,\s*selected,\s*count,\s*entry\)' `
    -Message 'Title config speech should emit only a lightweight focus log during normal operation.'

Assert-NotMatch `
    -Text $speechBody `
    -Pattern 'accessxi\.log_title_config_menu_probe\(obj\)' `
    -Message 'Title config speech must not emit the heavy descriptor probe during normal operation.'

Assert-Match `
    -Text $speechBody `
    -Pattern 'state title-config quiet focus=%d count=%d reason="unproven-row-signal"' `
    -Message 'Title config speech should stay quiet until the real row signal is known.'

Assert-Match `
    -Text $speechBody `
    -Pattern 'state title-config focus=%d count=%d help="%s" source="%s"' `
    -Message 'Title config speech should log the focus index and resource source.'

Assert-Match `
    -Text $speechBody `
    -Pattern "return\s+\('Config\. %s'\):fmt\(accessxi\.sentence_fragment\(entry\.help\)\)" `
    -Message 'Title config speech should speak only DAT-backed help text.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)name:eq\('menu    lobycwin', true\).*?accessxi\.title_config_menu_speech\(obj\)" `
    -Message 'lobycwin must dispatch to the dedicated title config speech handler.'

Write-Host 'title config menu native/resource static checks ok'
