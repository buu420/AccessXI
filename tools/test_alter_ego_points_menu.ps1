$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-AddonPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -notmatch $Pattern) {
        throw "Missing Alter Ego Points menu contract: $Name"
    }
}

Assert-AddonPattern "function\s+accessxi\.alter_ego_points_category_entry" 'pure category row helper'
Assert-AddonPattern "function\s+accessxi\.alter_ego_points_subcategory_entry" 'pure subcategory row helper'
Assert-AddonPattern "(?s)\[1\]\s*=\s*\{\s*label\s*=\s*'HP/MP'.*?ROM\\\\384\\\\121\.DAT:2-3" 'row 1 HP/MP from ROM\384\121.DAT'
Assert-AddonPattern "(?s)\[2\]\s*=\s*\{\s*label\s*=\s*'Attributes'.*?ROM\\\\384\\\\121\.DAT:4-5" 'row 2 Attributes from ROM\384\121.DAT'
Assert-AddonPattern "(?s)\[3\]\s*=\s*\{\s*label\s*=\s*'Skills'.*?ROM\\\\384\\\\121\.DAT:6-7" 'row 3 Skills from ROM\384\121.DAT'
Assert-AddonPattern "menu_name:eq\('menu    fp_cat'" 'menu    fp_cat dispatch'
Assert-AddonPattern "menu_name:eq\('menu    fp_cat2'" 'menu    fp_cat2 dispatch'
Assert-AddonPattern "native-cursor4c" 'fallback to proven native 0x4C cursor when fp_cat child cursor is invalid'
Assert-AddonPattern 'reason="unverified-cursor"' 'logging for rejected unverified fp_cat cursor state'
Assert-AddonPattern "(?s)Max HP.*?ROM\\\\384\\\\121\.DAT:16-17.*?Max MP.*?ROM\\\\384\\\\121\.DAT:18-19" 'HP/MP submenu rows from ROM\384\121.DAT'
Assert-AddonPattern "(?s)STR.*?ROM\\\\384\\\\121\.DAT:20-21.*?CHR.*?ROM\\\\384\\\\121\.DAT:32-33" 'Attributes submenu rows from ROM\384\121.DAT'
Assert-AddonPattern "(?s)Combat Skills.*?ROM\\\\384\\\\121\.DAT:34-35.*?Magic Skills.*?ROM\\\\384\\\\121\.DAT:36-37" 'Skills submenu rows from ROM\384\121.DAT'
Assert-AddonPattern 'reason="missing-category-context"' 'fp_cat2 refuses speech without verified category context'
Assert-AddonPattern "function\s+accessxi\.alter_ego_points_confirmation_speech" 'Alter Ego Points confirmation handler'
Assert-AddonPattern 'state nativemenu alterego-confirmation-dat' 'Alter Ego Points confirmation logging'
Assert-AddonPattern 'dat:ROM\\\\97\\\\38\.DAT:123' 'Alter Ego Points confirmation prompt source'
Assert-AddonPattern 'ROM\\\\97\\\\37\.DAT#106-107' 'Alter Ego Points Yes/No source'
Assert-AddonPattern 'reason="missing-subcategory-context"' 'merityn confirmation refuses speech without verified Alter Ego submenu context'

Write-Host 'alter ego points static checks ok'
