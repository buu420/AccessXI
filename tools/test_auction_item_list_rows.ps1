# THE AUCTION ROW LIST MUST MATCH THE SCREEN, ROW FOR ROW.
#
# The auction list's own text cannot be read -- labelPtr is null and the native
# query returns nothing for `menu auclist` -- so the addon rebuilds the list
# from packet 0x095 and counts rows to find the cursor. A row it gets wrong
# displaces every row below it, and the player hears one item's name while the
# cursor sits on another.
#
# Live 2026-08-23: the player selected screen row 69, heard "Prism Powder", and
# reached Poison Potion. sol's census of that capture: 89 packet records -- 54
# non-stackable, 16 stackable with zero stacks, 19 with stacks -- so the screen
# has 89 + 16 + 19 = 124 rows while the addon was building 108, having dropped
# every zero-availability stack row.
#
#   luajit is not needed: this asserts the shipped source states the rule.

$ErrorActionPreference = 'Stop'

$live = if ($env:ACCESSXI_ADDON) { $env:ACCESSXI_ADDON } else { Join-Path $env:USERPROFILE 'Ashita\addons\accessxi_reader' }
$reader = Join-Path $live 'accessxi_reader.lua'
if (-not (Test-Path -LiteralPath $reader)) {
    throw "accessxi_reader.lua not found at $reader"
}
$text = Get-Content -Raw -LiteralPath $reader

$checks = 0
function Assert-Rule {
    param([bool]$Ok, [string]$What)
    $script:checks++
    if (-not $Ok) { throw "AUCTION ROW RULE FAILED: $What" }
    Write-Host "  ok  $What"
}

Write-Host 'The auction row list is rebuilt exactly:'

# The tri-state the parser decodes: -1 not stackable, 0 stackable with none
# listed, >0 that many listed. Zero must still produce a row.
Assert-Rule ($text -match 'if \(stack_amount >= 4294967295\) then\r?\n\s*stack_amount = -1;') `
    'the packet decodes a non-stackable item as -1, distinct from zero'
Assert-Rule ($text -match 'if \(stack_count >= 0\) then') `
    'a stackable item with NO stacks listed still gets its stack row'
Assert-Rule ($text -notmatch 'local stack_count = tonumber\(row\.stack\) or 0;\r?\n\s*display_rows:append') `
    'and a missing stack field defaults to not-stackable, never to zero'

# Dropping a row shifts everything after it, which is the same bug by another
# route. Nothing may be filtered out of the positional list.
Assert-Rule ($text -notmatch 'local item_id = tonumber\(row\.id\) or 0;\r?\n\s*if \(is_valid_inventory_item_id\(item_id\)\) then\r?\n\s*local single_count') `
    'no row is dropped from the display list for being unnameable'
Assert-Rule ($text -match "name = \('Unknown auction item, ID %d'\):fmt") `
    'an unnameable row is announced by its id and keeps its position'

# Stack SIZE is fixed metadata; the packet count is current availability.
# Prism Powder hid this because both were 12.
Assert-Rule ($text -match 'local stack_size = tonumber\(resource_info ~= nil and resource_info\.stack or 0\) or 0;') `
    'the bracket reads the item stack SIZE from the resource table'
Assert-Rule ($text -notmatch 'if \(display_count > 0\) then\r?\n\s*raw_label = \(.%s \[%d\].\):fmt\(raw_label, display_count\);') `
    'and never decorates the name with how many happen to be listed right now'

Write-Host ''
Write-Host "ok: auction item list row rules hold ($checks checks)."
