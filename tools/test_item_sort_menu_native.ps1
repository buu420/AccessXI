$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$nativeMenusPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\native_menus.lua'
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
    -Pattern "menus\s*=\s*T\{\s*'menu    itmsort2'\s*\}.*?title\s*=\s*'Sort'" `
    -Message 'Item sort submenu should be registered as a native known menu with the visible Sort title.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    blusortw'\s*\}.*?title\s*=\s*'Sort'" `
    -Message 'Blue Magic spell sort submenu should be registered as a native known Sort menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    mgcsortw'\s*\}.*?title\s*=\s*'Sort'" `
    -Message 'Normal magic spell sort submenu should be registered as a native known Sort menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    sortyn'\s*\}.*?title\s*=\s*'Confirmation'" `
    -Message 'The shared sortyn confirmation menu should not be registered as merit-specific.'

Assert-NotMatch `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    sortyn'\s*\}.*?title\s*=\s*'Merit confirmation'" `
    -Message 'sortyn is reused by item sorting and must not have a fixed merit title.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.item_sort_menu_speech" `
    -Message 'Expected a dedicated dynamic item sort submenu speech handler.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.current_item_sort_confirmation_context" `
    -Message 'Expected a transition-backed item sort confirmation context guard.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.item_sort_confirmation_speech" `
    -Message 'Expected a dedicated item sort confirmation speech handler.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.current_merit_confirmation_context" `
    -Message 'Expected merit confirmation to have a fresh merit-context guard.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)menu_name:eq\('menu    itmsort2'.*?menu_name:eq\('menu    blusortw'.*?menu_name:eq\('menu    mgcsortw'" `
    -Message 'Sort handler/dispatcher should identify item, Blue Magic, and normal magic sort menus.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    itmsort2'.*?menu_name:eq\('menu    blusortw'.*?menu_name:eq\('menu    mgcsortw'.*?read_current_native_menu_index\(0x4C\)" `
    -Message 'Item and magic sort submenus should use the native cursor path used by dynamic command-like menus.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    itmsort2'.*?menu_name:eq\('menu    blusortw'.*?menu_name:eq\('menu    mgcsortw'.*?accessxi\.item_sort_menu_speech" `
    -Message 'native_known_menu_speech should dispatch item and magic sort menus before generic fallback handling.'

$handlerStart = $source.IndexOf('function accessxi.item_sort_menu_speech')
if ($handlerStart -lt 0) {
    throw 'Missing item_sort_menu_speech handler.'
}
$handlerEnd = $source.IndexOf("`nfunction accessxi.item_sort_confirmation_speech", $handlerStart)
if ($handlerEnd -lt 0) {
    $handlerEnd = $source.IndexOf("`nfunction accessxi.native_known_menu_speech", $handlerStart)
}
if ($handlerEnd -lt 0) {
    throw 'Could not locate end of item_sort_menu_speech handler.'
}
$handlerBody = $source.Substring($handlerStart, $handlerEnd - $handlerStart)

Assert-Match `
    -Text $handlerBody `
    -Pattern "accessxi\.native_query_label_for_selection\(child,\s*selected,\s*count,\s*'plain'\)" `
    -Message 'Item sort rows must come from the live native row query.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "read_u32\(entry\s*\+\s*0x44\)" `
    -Message 'Item sort handler should accept the selected native entry label pointer.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "read_u32\(entry\s*\+\s*0x40\)" `
    -Message 'Item sort handler should accept the selected native entry help pointer.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "state nativemenu item-sort-native" `
    -Message 'Item sort handler should log accepted native row text.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "(?s)menu_name:eq\('menu    blusortw', true\).*?menu_name:eq\('menu    mgcsortw', true\).*?current_blue_magic_sort_category_label\s*=\s*accessxi\.magic_current_category_label\(\).*?current_blue_magic_sort_category_tick\s*=\s*tick\(\)" `
    -Message 'Magic sort menus should cache the current native Magic category for returning to the spell list.'

$missingLabelBranch = $handlerBody.IndexOf("if (label == '') then")
$magicCategoryCache = $handlerBody.IndexOf('current_blue_magic_sort_category_label')
if ($missingLabelBranch -lt 0 -or $magicCategoryCache -lt 0 -or $magicCategoryCache -gt $missingLabelBranch) {
    throw 'Magic sort menus should cache the native Magic category before any missing row text can return silent.'
}

Assert-Match `
    -Text $handlerBody `
    -Pattern "current_item_sort_label\s*=\s*label" `
    -Message 'Item sort handler should cache the accepted native row label for the following confirmation.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "current_item_sort_help\s*=\s*help" `
    -Message 'Item sort handler should cache the accepted native row help for the following confirmation.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "current_item_sort_tick\s*=\s*tick\(\)" `
    -Message 'Item sort handler should timestamp the native row context.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "state nativemenu item-sort-native-missing" `
    -Message 'Item sort handler should log missing native row text.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "no fixed-row fallback" `
    -Message 'Item sort handler should explicitly refuse fixed-row fallback behavior.'

Assert-NotMatch `
    -Text $handlerBody `
    -Pattern "Auto|Manual|Recycle" `
    -Message 'Item sort handler must not hardcode current screenshot row labels.'

$confirmStart = $source.IndexOf('function accessxi.item_sort_confirmation_speech')
if ($confirmStart -lt 0) {
    throw 'Missing item_sort_confirmation_speech handler.'
}
$confirmEnd = $source.IndexOf("`nfunction accessxi.native_known_menu_speech", $confirmStart)
if ($confirmEnd -lt 0) {
    throw 'Could not locate end of item_sort_confirmation_speech handler.'
}
$confirmBody = $source.Substring($confirmStart, $confirmEnd - $confirmStart)

$contextStart = $source.IndexOf('function accessxi.current_item_sort_confirmation_context')
if ($contextStart -lt 0) {
    throw 'Missing current_item_sort_confirmation_context handler.'
}
$contextEnd = $source.IndexOf("`nfunction accessxi.item_sort_confirmation_speech", $contextStart)
if ($contextEnd -lt 0) {
    throw 'Could not locate end of current_item_sort_confirmation_context handler.'
}
$contextBody = $source.Substring($contextStart, $contextEnd - $contextStart)

Assert-Match `
    -Text $contextBody `
    -Pattern "transition_from:eq\('menu    itmsort2', true\)" `
    -Message 'Item sort confirmation should accept inventory item-sort transitions.'

Assert-Match `
    -Text $contextBody `
    -Pattern "transition_from:eq\('menu    blusortw', true\)" `
    -Message 'Item sort confirmation should accept Blue Magic sort-menu transitions.'

Assert-Match `
    -Text $contextBody `
    -Pattern "transition_from:eq\('menu    mgcsortw', true\)" `
    -Message 'Item sort confirmation should accept normal magic sort-menu transitions.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "current_item_sort_confirmation_context" `
    -Message 'Item sort confirmation should require the cached item sort context.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "last_menu_transition_from" `
    -Message 'Item sort confirmation should be gated by the live menu transition source.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "last_menu_transition_to" `
    -Message 'Item sort confirmation should be gated by the live menu transition target.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "dat_index_row_text\('ROM\\\\97\\\\40\.DAT',\s*60,\s*'help'\)" `
    -Message 'Item sort confirmation prompt must come from the native DAT row for Sort items?.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "dat_index_row_text\('ROM\\\\97\\\\37\.DAT',\s*106,\s*'label'\)" `
    -Message 'Item sort confirmation Yes label must come from the native DAT row.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "dat_index_row_text\('ROM\\\\97\\\\37\.DAT',\s*107,\s*'label'\)" `
    -Message 'Item sort confirmation No label must come from the native DAT row.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "state nativemenu item-sort-confirmation" `
    -Message 'Item sort confirmation should log accepted native/DAT-backed speech.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "state nativemenu item-sort-confirmation quiet" `
    -Message 'Item sort confirmation should log why it stayed silent.'

Assert-NotMatch `
    -Text $confirmBody `
    -Pattern "Auto|Manual|Recycle|Merit confirmation" `
    -Message 'Item sort confirmation must not hardcode screenshot rows or merit-specific text.'

$nativeKnownStart = $source.IndexOf('function accessxi.native_known_menu_speech')
if ($nativeKnownStart -lt 0) {
    throw 'Missing native_known_menu_speech handler.'
}
$sortynStart = $source.IndexOf("if (menu_name:eq('menu    sortyn'", $nativeKnownStart)
if ($sortynStart -lt 0) {
    throw 'Missing sortyn dispatch block.'
}
$sortynEnd = $source.IndexOf("`n    if (menu_name:eq('menu    merityn'", $sortynStart)
if ($sortynEnd -lt 0) {
    throw 'Could not locate end of sortyn dispatch block.'
}
$sortynBlock = $source.Substring($sortynStart, $sortynEnd - $sortynStart)
$itemSortDispatch = $sortynBlock.IndexOf('accessxi.item_sort_confirmation_speech')
$meritDispatch = $sortynBlock.IndexOf('accessxi.merit_confirmation_speech')
if ($itemSortDispatch -lt 0 -or $meritDispatch -lt 0 -or $itemSortDispatch -gt $meritDispatch) {
    throw 'sortyn dispatch should try item sort confirmation before merit confirmation.'
}

$currentMenuStart = $source.IndexOf('local function current_menu_speech')
if ($currentMenuStart -lt 0) {
    throw 'Missing current_menu_speech handler.'
}
$currentMenuEnd = $source.IndexOf("`nfunction accessxi.clear_chat_log_deferred_speech", $currentMenuStart)
if ($currentMenuEnd -lt 0) {
    throw 'Could not locate end of current_menu_speech handler.'
}
$currentMenuBody = $source.Substring($currentMenuStart, $currentMenuEnd - $currentMenuStart)

Assert-Match `
    -Text $currentMenuBody `
    -Pattern "(?s)transition_from.*?eq\('menu    blusortw', true\).*?transition_from.*?eq\('menu    mgcsortw', true\).*?current_blue_magic_sort_category_label.*?magic_category_list_active\s*=\s*true.*?magic_category_list_label\s*=\s*blue_magic_sort_category_label" `
    -Message 'Returning from magic sort to the spell list should preserve the native Magic category context.'

$meritStart = $source.IndexOf('function accessxi.merit_confirmation_speech')
if ($meritStart -lt 0) {
    throw 'Missing merit_confirmation_speech handler.'
}
$meritEnd = $source.IndexOf("`nfunction accessxi.job_point_confirmation_speech", $meritStart)
if ($meritEnd -lt 0) {
    throw 'Could not locate end of merit_confirmation_speech handler.'
}
$meritBody = $source.Substring($meritStart, $meritEnd - $meritStart)

Assert-Match `
    -Text $meritBody `
    -Pattern "current_merit_confirmation_context" `
    -Message 'Merit confirmation should require a fresh merit option context before speaking.'

Assert-Match `
    -Text $meritBody `
    -Pattern 'missing-merit-context' `
    -Message 'Merit confirmation should log and stay silent when the context is not a merit option.'

Assert-NotMatch `
    -Text $meritBody `
    -Pattern 'this merit' `
    -Message 'Merit confirmation must not invent a placeholder merit label.'

Write-Host 'item sort native submenu static checks ok'
