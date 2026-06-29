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
    -Pattern "menus\s*=\s*T\{\s*'menu    shopmain'\s*\}.*?title\s*=\s*'Shop'" `
    -Message 'Store Buy/Sell menu should be registered as a native known Shop menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    shopbuy'\s*\}.*?title\s*=\s*'Shop'" `
    -Message 'Store purchase confirmation should be registered as a native known Shop menu.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    shopmain', true\).*?read_current_native_menu_index\(0x4C\)" `
    -Message 'Store Buy/Sell menu should use the visible native cursor index.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    shopbuy', true\).*?read_current_native_menu_index\(0x4C\)" `
    -Message 'Store purchase confirmation should use the live native 0x4C cursor index.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.is_vendor_shop_item_list_menu_name" `
    -Message 'Store merchandise list should have its own vendor-shop menu detector.'

Assert-Match `
    -Text $source `
    -Pattern "previous_menu_name:eq\('menu    shopmain', true\)" `
    -Message 'Vendor shop item list should be recognized when menu shop opens from shopmain.'

Assert-Match `
    -Text $source `
    -Pattern "vendor_shop_item_list" `
    -Message 'Vendor shop item list should keep an explicit inventory context.'

$nativeKnownStart = $source.IndexOf('function accessxi.native_known_menu_speech')
if ($nativeKnownStart -lt 0) {
    throw 'Missing native_known_menu_speech handler.'
}
$nativeKnownEnd = $source.IndexOf("`nfunction accessxi.enable_macro_palette_probe", $nativeKnownStart)
if ($nativeKnownEnd -lt 0) {
    $nativeKnownEnd = $source.Length
}
$nativeKnownBody = $source.Substring($nativeKnownStart, $nativeKnownEnd - $nativeKnownStart)

$shopmainIndex = $nativeKnownBody.IndexOf("menu_name:eq('menu    shopmain'")
$nativeQueryIndex = $nativeKnownBody.IndexOf('accessxi.native_query_label_for_selection')
if ($shopmainIndex -lt 0) {
    throw 'native_known_menu_speech does not include shopmain.'
}
if ($nativeQueryIndex -lt 0) {
    throw 'native_known_menu_speech does not call native_query_label_for_selection.'
}
if ($shopmainIndex -gt $nativeQueryIndex) {
    throw 'shopmain should be routed before the generic native row query.'
}

Assert-Match `
    -Text $nativeKnownBody `
    -Pattern "(?s)menu_name:eq\('menu    shopmain', true\).*?accessxi\.shopmain_menu_speech" `
    -Message 'shopmain should use its native text-table command handler before generic row lookup.'

Assert-Match `
    -Text $nativeKnownBody `
    -Pattern "(?s)menu_name:eq\('menu    shopbuy', true\).*?accessxi\.shopbuy_menu_speech" `
    -Message 'shopbuy should use its purchase confirmation command handler before generic row lookup.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.load_shopmain_command_rows" `
    -Message 'shopmain should have a DAT-resource fallback for command descriptions.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.load_shopbuy_command_rows" `
    -Message 'shopbuy should have a DAT-resource fallback for purchase confirmation options.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.scan_native_command_text_table" `
    -Message 'Store command menus should keep a native visible-label scanner for menus with verified row tables.'

Assert-Match `
    -Text $source `
    -Pattern "ROM\\\\165\\\\75%\.DAT" `
    -Message 'shopmain command fallback should load rows 47 and 48 from ROM\\165\\75.DAT.'

Assert-Match `
    -Text $source `
    -Pattern "tonumber\(index\)\s*==\s*47\s*and\s*1\s*or\s*\(tonumber\(index\)\s*==\s*48\s*and\s*2" `
    -Message 'shopmain command fallback should map DAT rows 47 and 48 to the first two options.'

Assert-Match `
    -Text $source `
    -Pattern "tonumber\(index\)\s*==\s*464\s*and\s*1\s*or\s*\(tonumber\(index\)\s*==\s*465\s*and\s*2" `
    -Message 'shopbuy command fallback should map DAT rows 464 and 465 to purchase and cancel options.'

Assert-NotMatch `
    -Text $nativeKnownBody `
    -Pattern "shopmain.*('Buy'|'Sell')|('Buy'|'Sell').*shopmain" `
    -Message 'Store Buy/Sell rows must not be hardcoded; they should come from native row text.'

$shopmainSpeechStart = $source.IndexOf('function accessxi.shopmain_menu_speech')
if ($shopmainSpeechStart -lt 0) {
    throw 'Missing shopmain_menu_speech handler.'
}
$shopmainSpeechEnd = $source.IndexOf("`nfunction accessxi.enable_macro_palette_probe", $shopmainSpeechStart)
if ($shopmainSpeechEnd -lt 0) {
    $shopmainSpeechEnd = $source.Length
}
$shopmainSpeechBody = $source.Substring($shopmainSpeechStart, $shopmainSpeechEnd - $shopmainSpeechStart)

Assert-Match `
    -Text $shopmainSpeechBody `
    -Pattern "read_probe_string\(candidate_table \+ \(\(row - 1\) \* 0x40\)" `
    -Message 'shopmain command labels should be read from the native text table.'

Assert-Match `
    -Text $shopmainSpeechBody `
    -Pattern "accessxi\.load_shopmain_command_rows\(\)" `
    -Message 'shopmain command handler should fall back to game DAT command rows when native pointers are blank.'

Assert-NotMatch `
    -Text $shopmainSpeechBody `
    -Pattern "'Buy'|'Sell'" `
    -Message 'shopmain command handler must not hardcode Buy/Sell labels.'

$shopbuySpeechStart = $source.IndexOf('function accessxi.shopbuy_menu_speech')
if ($shopbuySpeechStart -lt 0) {
    throw 'Missing shopbuy_menu_speech handler.'
}
$shopbuySpeechEnd = $source.IndexOf("`nfunction accessxi.shopmain_menu_speech", $shopbuySpeechStart)
if ($shopbuySpeechEnd -lt 0) {
    throw 'Could not find end of shopbuy_menu_speech handler.'
}
$shopbuySpeechBody = $source.Substring($shopbuySpeechStart, $shopbuySpeechEnd - $shopbuySpeechStart)

$shopbuyDatFallbackIndex = $shopbuySpeechBody.IndexOf('accessxi.load_shopbuy_command_rows')
if ($shopbuyDatFallbackIndex -lt 0) {
    throw 'shopbuy command handler should keep the DAT help rows as fallback.'
}

if ($shopbuySpeechBody.IndexOf('accessxi.scan_native_command_text_table') -ge 0) {
    throw 'shopbuy command handler must not use the broad native table scan; live evidence showed it can pick unrelated text.'
}

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.shopbuy_command_label" `
    -Message 'shopbuy should have fixed command labels for the native Buy/Cancel confirmation choices.'

Assert-Match `
    -Text $shopbuySpeechBody `
    -Pattern "accessxi\.shopbuy_command_label\(visible_selected\)" `
    -Message 'shopbuy speech should use the visible Buy/Cancel command label.'

Assert-Match `
    -Text $shopbuySpeechBody `
    -Pattern "local\s+cursor4c\s*=\s*read_current_native_menu_index\(0x4C\)" `
    -Message 'shopbuy confirmation should read the live 0x4C cursor; 0x34 stayed stale in screenshot-backed evidence.'

Assert-NotMatch `
    -Text $shopbuySpeechBody `
    -Pattern "local\s+visible_selected\s*=\s*read_current_native_menu_index\(0x34\)" `
    -Message 'shopbuy confirmation must not seed the visible row from stale 0x34.'

Assert-Match `
    -Text $shopbuySpeechBody `
    -Pattern "shopbuy-native:%d:0x%08X:0x%08X:%s:%s" `
    -Message 'shopbuy speech key should include child and entry pointers so reopening the same Buy/Cancel row speaks.'

Assert-Match `
    -Text $shopbuySpeechBody `
    -Pattern "cursorSource" `
    -Message 'shopbuy logs should include the cursor source used for Buy/Cancel selection.'

Assert-Match `
    -Text $source `
    -Pattern "shopbuy-command-label" `
    -Message 'shopbuy logs should identify the fixed command-label source separately from dynamic merchandise rows.'

Assert-Match `
    -Text $source `
    -Pattern "local\s+vendor_shop_item_list_menu\s*=\s*accessxi\.is_vendor_shop_item_list_menu_name\(name,\s*previous_menu_name\)" `
    -Message 'current_menu_speech should compute the vendor shop item-list state.'

Assert-Match `
    -Text $source `
    -Pattern "local\s+inventory_menu\s*=\s*is_inventory_menu_name\(name\)\s*or\s+bazaar_item_list_menu\s*or\s+vendor_shop_item_list_menu" `
    -Message 'Vendor shop item list should route through the selected-item reader.'

Assert-Match `
    -Text $source `
    -Pattern "context_token\s*=\s*\(':vendor-shop:%d'\):fmt" `
    -Message 'Vendor shop speech keys should include a vendor-shop context token.'

Assert-Match `
    -Text $source `
    -Pattern "state inventory vendor-shop-name" `
    -Message 'Vendor shop list should speak native item names even without an inventory container slot.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)accessxi\.inventory_context == 'vendor_shop_item_list' and name ~= ''.*?return accessxi\.native_vendor_shop_item_info" `
    -Message 'Vendor shop list should bypass inventory container counts whenever a native item name is present.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_vendor_shop_item_info.*?container_name\s*=\s*'Shop'.*?count\s*=\s*0" `
    -Message 'Vendor shop item info should be shop-scoped and should not inherit current gil as quantity.'

Assert-Match `
    -Text $source `
    -Pattern "local\s+suppress_count\s*=\s*tostring\(accessxi\.inventory_context or ''\)\s*==\s*'vendor_shop_item_list'" `
    -Message 'Vendor shop selected-item speech should suppress any accidental container count.'

Assert-Match `
    -Text $source `
    -Pattern "inventory_item_info_speech\(info,\s*suppress_count\)" `
    -Message 'Vendor shop selected-item speech should pass the count-suppression flag.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.capture_vendor_shop_list_packet\(e\)" `
    -Message 'Vendor shop prices should be captured from the native server shop-list packet.'

Assert-Match `
    -Text $source `
    -Pattern "e\.id\s*~=\s*0x03C" `
    -Message 'Vendor shop price capture should be scoped to packet 0x03C.'

Assert-Match `
    -Text $source `
    -Pattern "ItemPrice" `
    -Message 'Vendor shop packet parser should use the packet ItemPrice field.'

Assert-Match `
    -Text $source `
    -Pattern "packet_u32\(data,\s*base \+ 0x00 \+ 1\)" `
    -Message 'Vendor shop packet parser should read 32-bit item prices from each GP_SHOP row.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.capture_vendor_shop_list_packet\(e\)" `
    -Message 'Vendor shop packet capture should be registered in packet_in.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.vendor_shop_price_for_item\(item_id,\s*name\)" `
    -Message 'Vendor shop item speech should look up price by selected native item id/name.'

Assert-Match `
    -Text $source `
    -Pattern "Price %s gil" `
    -Message 'Vendor shop item speech should include the packet-backed gil price.'

Write-Host 'shopmain store menu native static checks ok'
