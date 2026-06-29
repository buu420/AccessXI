$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$itemsPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\resources\windower\items.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$items = Get-Content -LiteralPath $itemsPath -Raw

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
    -Text $items `
    -Pattern '\[4767\]\s*=\s*\{[^}]*en="Stone"[^}]*enl="scroll of Stone"' `
    -Message 'The Windower item resource should expose scroll of Stone as the long label for item 4767.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.load_windower_items_resource" `
    -Message 'The reader should load Windower items.lua so item long labels are available.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.resource_path\('windower', 'items\.lua'\)" `
    -Message 'Windower item resources should be loaded through the relative addon resource path.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local\s+function\s+resource_item_info\(id\).*?long_name\s*=\s*long_name" `
    -Message 'resource_item_info should preserve the Windower long item name.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.resource_item_info_name_matches\(resource_info, name\).*?resource_info\.long_name" `
    -Message 'Resource name matching should accept both short native names and long item labels.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.resource_item_speech_name\(resource_info, fallback_name\)" `
    -Message 'The reader should have one helper that chooses the spoken item label.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_vendor_shop_item_info.*?accessxi\.resource_item_speech_name\(resource_info, name\)" `
    -Message 'Vendor shop item speech should use the long item label when available.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.get_native_selected_inventory_item_info.*?accessxi\.resource_item_speech_name\(resource_info, name\)" `
    -Message 'Inventory speech should use the long item label when available.'

Assert-Match `
    -Text $source `
    -Pattern 'visibleName="%s"\s+nameSource="%s"' `
    -Message 'Inventory logs should keep the native visible name and chosen speech-name source.'

Write-Host 'inventory scroll long-name checks passed'
