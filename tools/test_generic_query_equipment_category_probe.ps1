$ErrorActionPreference = 'Stop'

$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\generic_query.lua'

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Generic query module not found: $modulePath"
}

$module = Get-Content -LiteralPath $modulePath -Raw

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
    -Text $module `
    -Pattern 'function\s+accessxi\.generic_query_equipment_category_probe\s*\(' `
    -Message 'Generic query should have a narrow selected-row probe for Rolandienne equipment category rows.'

Assert-Match `
    -Text $module `
    -Pattern 'state generic-query equipment-category-probe' `
    -Message 'Equipment category probe must emit a recognizable state log line.'

Assert-Match `
    -Text $module `
    -Pattern 'generic_query_direct_label_for_child\(child,\s*selected,\s*count\)[\s\S]*?direct_node' `
    -Message 'Generic query speech should keep the selected row node returned by direct label scanning.'

Assert-Match `
    -Text $module `
    -Pattern 'generic_query_equipment_category_probe\([^)]*direct_node' `
    -Message 'Generic query speech should pass the selected row node into the equipment category probe.'

Assert-Match `
    -Text $module `
    -Pattern 'native_query_node_debug\(node,\s*''selected''\)' `
    -Message 'Probe should include native_query_node_debug for the selected row node.'

foreach ($offset in @('0x00', '0x04', '0x10', '0x38', '0x88', '0x100', '0x104', '0x108')) {
    Assert-Match `
        -Text $module `
        -Pattern ([regex]::Escape($offset)) `
        -Message "Probe should include selected row offset $offset."
}

Write-Host 'generic query equipment category probe static checks ok'
