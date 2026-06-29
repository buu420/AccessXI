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
    -Text $source `
    -Pattern "current_item_use_action_label\s*=" `
    -Message 'Expected item use action context storage.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.current_item_use_confirmation_context" `
    -Message 'Expected a transition-backed item use confirmation context guard.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.item_use_confirmation_speech" `
    -Message 'Expected a dedicated item use/drop confirmation speech handler.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.current_item_dispose_second_confirmation_context" `
    -Message 'Expected a transition-backed second item dispose confirmation context guard.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.item_dispose_second_confirmation_speech" `
    -Message 'Expected a dedicated Rare/Ex item dispose confirmation speech handler.'

$iuseStart = $source.IndexOf('local function item_use_action_speech')
if ($iuseStart -lt 0) {
    throw 'Missing item_use_action_speech.'
}
$iuseEnd = $source.IndexOf("`nlocal function item_target_options", $iuseStart)
if ($iuseEnd -lt 0) {
    throw 'Could not locate end of item_use_action_speech.'
}
$iuseBody = $source.Substring($iuseStart, $iuseEnd - $iuseStart)

Assert-Match `
    -Text $iuseBody `
    -Pattern "current_item_use_action_label\s*=\s*label" `
    -Message 'Item use action speech should cache the accepted action label.'

Assert-Match `
    -Text $iuseBody `
    -Pattern "current_item_use_item_name\s*=\s*item_name" `
    -Message 'Item use action speech should cache the selected inventory item name.'

Assert-Match `
    -Text $iuseBody `
    -Pattern "current_item_use_action_selected\s*=\s*selected" `
    -Message 'Item use action speech should cache the selected item action row.'

Assert-Match `
    -Text $iuseBody `
    -Pattern "current_item_use_action_tick\s*=\s*tick\(\)" `
    -Message 'Item use action speech should timestamp the item action context.'

$contextStart = $source.IndexOf('function accessxi.current_item_use_confirmation_context')
if ($contextStart -lt 0) {
    throw 'Missing current_item_use_confirmation_context handler.'
}
$contextEnd = $source.IndexOf("`nfunction accessxi.item_use_confirmation_speech", $contextStart)
if ($contextEnd -lt 0) {
    throw 'Could not locate end of current_item_use_confirmation_context handler.'
}
$contextBody = $source.Substring($contextStart, $contextEnd - $contextStart)

Assert-Match `
    -Text $contextBody `
    -Pattern "current_item_use_action_label" `
    -Message 'Item use confirmation context should require cached item action state.'

Assert-Match `
    -Text $contextBody `
    -Pattern "last_menu_transition_from" `
    -Message 'Item use confirmation should be gated by the live menu transition source.'

Assert-Match `
    -Text $contextBody `
    -Pattern "last_menu_transition_to" `
    -Message 'Item use confirmation should be gated by the live menu transition target.'

Assert-Match `
    -Text $contextBody `
    -Pattern "transition_from:eq\('menu    iuse'" `
    -Message 'Item use confirmation should only claim confirmations opened from the item action menu.'

Assert-Match `
    -Text $contextBody `
    -Pattern "transition_to:eq\('menu    sortyn'" `
    -Message 'Item use confirmation should only claim the shared sortyn confirmation target.'

Assert-Match `
    -Text $contextBody `
    -Pattern "action_label:eq\('Drop'" `
    -Message 'Dispose confirmation should only speak for the native Drop action context.'

$confirmStart = $source.IndexOf('function accessxi.item_use_confirmation_speech')
if ($confirmStart -lt 0) {
    throw 'Missing item_use_confirmation_speech handler.'
}
$confirmEnd = $source.IndexOf("`nfunction accessxi.native_known_menu_speech", $confirmStart)
if ($confirmEnd -lt 0) {
    throw 'Could not locate end of item_use_confirmation_speech handler.'
}
$confirmBody = $source.Substring($confirmStart, $confirmEnd - $confirmStart)

Assert-Match `
    -Text $confirmBody `
    -Pattern "current_item_use_confirmation_context" `
    -Message 'Item use confirmation should require cached item action context.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "dat_index_row_text\('ROM\\\\97\\\\40\.DAT',\s*61,\s*'help'\)" `
    -Message 'Item dispose confirmation prompt must come from the native DAT row for Dispose of item?.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "dat_index_row_text\('ROM\\\\97\\\\37\.DAT',\s*106,\s*'label'\)" `
    -Message 'Item dispose confirmation Yes label must come from the native DAT row.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "dat_index_row_text\('ROM\\\\97\\\\37\.DAT',\s*107,\s*'label'\)" `
    -Message 'Item dispose confirmation No label must come from the native DAT row.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "state nativemenu item-use-confirmation" `
    -Message 'Item use confirmation should log accepted native/DAT-backed speech.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "state nativemenu item-use-confirmation quiet" `
    -Message 'Item use confirmation should log why it stayed silent.'

Assert-NotMatch `
    -Text $confirmBody `
    -Pattern "Merit confirmation|Sort items" `
    -Message 'Item use confirmation must not reuse merit or sort-confirmation wording.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "current_item_dispose_confirmed_item_name\s*=\s*context\.item_name" `
    -Message 'First item dispose confirmation should arm the second confirmation context after Yes.'

Assert-Match `
    -Text $confirmBody `
    -Pattern "current_item_dispose_confirmed_tick\s*=\s*tick\(\)" `
    -Message 'First item dispose confirmation should timestamp the second confirmation context.'

$secondContextStart = $source.IndexOf('function accessxi.current_item_dispose_second_confirmation_context')
if ($secondContextStart -lt 0) {
    throw 'Missing current_item_dispose_second_confirmation_context handler.'
}
$secondContextEnd = $source.IndexOf("`nfunction accessxi.item_dispose_second_confirmation_speech", $secondContextStart)
if ($secondContextEnd -lt 0) {
    throw 'Could not locate end of current_item_dispose_second_confirmation_context handler.'
}
$secondContextBody = $source.Substring($secondContextStart, $secondContextEnd - $secondContextStart)

Assert-Match `
    -Text $secondContextBody `
    -Pattern "current_item_dispose_confirmed_item_name" `
    -Message 'Second dispose confirmation should require the item armed by the first confirmation.'

Assert-Match `
    -Text $secondContextBody `
    -Pattern "transition_from:eq\('menu    sortyn'" `
    -Message 'Second dispose confirmation should only claim confirmations opened from sortyn.'

Assert-Match `
    -Text $secondContextBody `
    -Pattern "transition_to:eq\('menu    comyn'" `
    -Message 'Second dispose confirmation should only claim the comyn target.'

$secondConfirmStart = $source.IndexOf('function accessxi.item_dispose_second_confirmation_speech')
if ($secondConfirmStart -lt 0) {
    throw 'Missing item_dispose_second_confirmation_speech handler.'
}
$secondConfirmEnd = $source.IndexOf("`nfunction accessxi.native_known_menu_speech", $secondConfirmStart)
if ($secondConfirmEnd -lt 0) {
    $secondConfirmEnd = $source.IndexOf("`nfunction accessxi.macro_paste_confirmation_speech", $secondConfirmStart)
}
if ($secondConfirmEnd -lt 0) {
    throw 'Could not locate end of item_dispose_second_confirmation_speech handler.'
}
$secondConfirmBody = $source.Substring($secondConfirmStart, $secondConfirmEnd - $secondConfirmStart)

Assert-Match `
    -Text $secondConfirmBody `
    -Pattern "current_item_dispose_second_confirmation_context" `
    -Message 'Second dispose confirmation should require the armed item context.'

Assert-Match `
    -Text $secondConfirmBody `
    -Pattern "dat_index_row_text\('ROM\\\\97\\\\38\.DAT',\s*48,\s*'help'\)" `
    -Message 'Second dispose confirmation prompt must come from the native DAT row for Really dispose of the item?.'

Assert-Match `
    -Text $secondConfirmBody `
    -Pattern "gsub\('%%s',\s*context\.item_name\)" `
    -Message 'Second dispose confirmation should substitute the native item name into the DAT prompt template.'

Assert-Match `
    -Text $secondConfirmBody `
    -Pattern "generic_comyn_selected_label" `
    -Message 'Second dispose confirmation should use the live comyn selected Yes/No state.'

Assert-Match `
    -Text $secondConfirmBody `
    -Pattern "state nativemenu item-dispose-second-confirmation" `
    -Message 'Second dispose confirmation should log accepted native/DAT-backed speech.'

Assert-Match `
    -Text $secondConfirmBody `
    -Pattern "state nativemenu item-dispose-second-confirmation quiet" `
    -Message 'Second dispose confirmation should log why it stayed silent.'

Assert-NotMatch `
    -Text $secondConfirmBody `
    -Pattern "Cipher: Darrcuiln|Rare/EX|Rare\s+EX|\bRare\b|\bEX\b" `
    -Message 'Second dispose confirmation must not hardcode screenshot item names or Rare/Ex labels.'

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
$itemUseDispatch = $sortynBlock.IndexOf('accessxi.item_use_confirmation_speech')
$meritDispatch = $sortynBlock.IndexOf('accessxi.merit_confirmation_speech')
if ($itemSortDispatch -lt 0 -or $itemUseDispatch -lt 0 -or $meritDispatch -lt 0) {
    throw 'sortyn dispatch should include item sort, item use, and merit confirmation handlers.'
}
if (-not ($itemSortDispatch -lt $itemUseDispatch -and $itemUseDispatch -lt $meritDispatch)) {
    throw 'sortyn dispatch should try item sort, then item use, then merit confirmation.'
}

$comynStart = $source.IndexOf("if (name:eq('menu    comyn'", $nativeKnownStart)
if ($comynStart -lt 0) {
    throw 'Missing comyn dispatch block.'
}
$comynEnd = $source.IndexOf("`n    if (name:eq('menu    inline'", $comynStart)
if ($comynEnd -lt 0) {
    throw 'Could not locate end of comyn dispatch block.'
}
$comynBlock = $source.Substring($comynStart, $comynEnd - $comynStart)
$disposeDispatch = $comynBlock.IndexOf('accessxi.item_dispose_second_confirmation_speech')
$genericDispatch = $comynBlock.IndexOf('accessxi.generic_comyn_confirmation_speech')
if ($disposeDispatch -lt 0 -or $genericDispatch -lt 0 -or $disposeDispatch -gt $genericDispatch) {
    throw 'comyn dispatch should try item dispose second confirmation before generic comyn confirmation.'
}

Write-Host 'item use/drop confirmation static checks ok'
