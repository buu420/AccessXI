$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-AddonPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -notmatch $Pattern) {
        throw "Missing trade handover native contract: $Name"
    }
}

Assert-AddonPattern 'function\s+accessxi\.is_trade_handover_menu_name\(name\)' 'trade handover menu detector'
Assert-AddonPattern "name:eq\('menu    handover',\s*true\)" 'trade handover uses native handover menu name'
Assert-AddonPattern 'function\s+accessxi\.trade_handover_slot_for_desc\(entry\)' 'trade slot resolver from native descriptor'
Assert-AddonPattern '0x1FC' 'current native trade slot descriptor base'
Assert-AddonPattern '0x19C' 'legacy native trade slot descriptor base remains supported'
Assert-AddonPattern 'function\s+accessxi\.trade_handover_control_label_for_entry\(entry\)' 'trade control label resolver'
Assert-AddonPattern 'desc_low\s*==\s*0x29C' 'current native Okay descriptor is recognized'
Assert-AddonPattern 'desc_low\s*==\s*0x2B0' 'current native Cancel descriptor is recognized'
Assert-AddonPattern 'x\s*==\s*55\s+and\s+y\s*==\s*159' 'current native Cancel geometry is recognized'
Assert-AddonPattern "return 'Cancel'" 'Cancel control can be spoken'
Assert-AddonPattern 'Slot %d\. %s' 'trade item speech prefixes item text with native trade slot'
Assert-AddonPattern 'Trade slot %d\. Empty\.' 'empty trade slots are spoken by slot'
Assert-AddonPattern 'state trade handover menu="%s"' 'trade item speech logs resolved slot and item'

Write-Host 'trade handover native static checks ok'
