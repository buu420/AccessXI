$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-AddonPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -notmatch $Pattern) {
        throw "Missing playermo target command-id contract: $Name"
    }
}

function Assert-AddonNotPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -match $Pattern) {
        throw "Forbidden playermo target command-id contract: $Name"
    }
}

Assert-AddonPattern 'function\s+accessxi\.playermo_dynamic_command_id' 'live dynamic command id reader exists'
Assert-AddonPattern 'child\s+\+\s+0x1A\s+\+\s+\(selected\s+\*\s+2\)' 'dynamic command ids are read from the live child command list'
Assert-AddonPattern 'function\s+accessxi\.playermo_command_id_dat_entry' 'dynamic command-id mapper exists'
Assert-AddonPattern '\[5\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\76\.DAT'',\s*label_row\s*=\s*129,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*22' 'player/trust command id 5 maps to Chat via command id, not selected row'
Assert-AddonPattern '\[19\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\76\.DAT'',\s*label_row\s*=\s*10,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*38' 'player/trust command id 19 maps to Trade via command id, not selected row'
Assert-AddonPattern '\[10\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\74\.DAT'',\s*label_row\s*=\s*122,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*30' 'player/trust command id 10 maps to Check via command id, not selected row'
Assert-AddonPattern '\[26\]\s*=\s*\{\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*719' 'trust command id 26 maps to DAT-backed Release help via command id, not selected row'
Assert-AddonPattern "(?s)function\s+accessxi\.playermo_command_context_label.*?release an alter ego.*?return 'Release'" 'Release context is derived from DAT-backed help text'
Assert-AddonNotPattern 'function\s+accessxi\.playermo_native_command_help_entry' 'selected command pointer help fallback remains disabled'
Assert-AddonNotPattern 'native-playermo-command-help' 'selected command pointer help speech key remains disabled'

Write-Host 'playermo target command-id static checks ok'
