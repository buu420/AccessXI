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

function Assert-AddonNotPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -match $Pattern) {
        throw "Forbidden trade handover native contract: $Name"
    }
}

Assert-AddonPattern 'function\s+accessxi\.is_trade_handover_menu_name\(name\)' 'trade handover menu detector'
Assert-AddonPattern "name:eq\('menu    handover',\s*true\)" 'trade handover uses native handover menu name'
Assert-AddonPattern 'function\s+accessxi\.trade_handover_slot_for_desc\(entry\)' 'trade slot resolver from native descriptor'
Assert-AddonPattern '0x1FC' 'current native trade slot descriptor base'
Assert-AddonPattern '0x19C' 'legacy native trade slot descriptor base remains supported'
Assert-AddonPattern 'function\s+accessxi\.trade_handover_slot_for_geometry\(entry\)' 'trade slot resolver from native row geometry'
Assert-AddonPattern '0x00200046' 'filled native trade slot row shape is recognized'
Assert-AddonPattern 'row_marker\s*=\s*math\.floor\(\(read_u32\(entry \+ 0x38\) or 0\) / 0x10000\)' 'native trade slot marker is read from row state'
Assert-AddonPattern 'row_marker\s*>=\s*1\s+and\s+row_marker\s*<=\s*8' 'native row marker covers all eight trade slots'
Assert-AddonPattern 'row_shape\s*==\s*0x00200068[\s\S]*return\s+slot\s+\+\s+4' 'wide native trade slot rows map to the second four slots'
Assert-AddonPattern 'geom_slot\s*=\s*accessxi\.trade_handover_slot_for_geometry\(entry\)' 'trade slot entry resolver falls back to row geometry'
Assert-AddonPattern 'function\s+accessxi\.trade_handover_control_label_for_entry\(entry\)' 'trade control label resolver'
Assert-AddonPattern 'function\s+accessxi\.trade_handover_control_geometry_label\(entry\)' 'trade control resolver from native packed geometry'
Assert-AddonPattern '0x00540037[\s\S]*return\s+''GilAmount''' 'native handover gil amount control shape is recognized'
Assert-AddonPattern '0x00A00007' 'native handover gil amount control extent is recognized'
Assert-AddonPattern 'accessxi\.trade_handover_gil_amount\s*=\s*amount' 'native money counter amount is cached for handover gil field'
Assert-AddonPattern 'tonumber\(accessxi\.trade_handover_gil_amount\)' 'handover gil field reads cached native money counter amount'
Assert-AddonNotPattern 'function\s+accessxi\.trade_handover_entry_gil_amount\(entry\)[\s\S]*trade_handover_entry_ascii_digits\(entry,\s*0x3C' 'handover gil amount must not scan stale row ascii bytes'
Assert-AddonPattern '0x00220068[\s\S]*return\s+''Cancel''' 'wide native Cancel control shape is recognized'
Assert-AddonPattern '0x00220046[\s\S]*return\s+''Okay''' 'native Okay control shape is recognized'
Assert-AddonPattern 'label\s*=\s*accessxi\.trade_handover_control_geometry_label\(entry\)[\s\S]*desc_low\s*=' 'packed button geometry is checked before descriptor fallback'
Assert-AddonPattern 'desc_low\s*==\s*0x29C' 'current native Okay descriptor is recognized'
Assert-AddonPattern 'desc_low\s*==\s*0x2B0' 'current native Cancel descriptor is recognized'
Assert-AddonPattern 'x\s*==\s*55\s+and\s+y\s*==\s*159' 'current native Cancel geometry is recognized'
Assert-AddonPattern "return 'Cancel'" 'Cancel control can be spoken'
Assert-AddonPattern 'Slot %d\. %s' 'trade item speech prefixes item text with native trade slot'
Assert-AddonPattern 'Trade slot %d\. Empty\.' 'empty trade slots are spoken by slot'
Assert-AddonPattern 'state trade handover menu="%s"' 'trade item speech logs resolved slot and item'

Write-Host 'trade handover native static checks ok'
