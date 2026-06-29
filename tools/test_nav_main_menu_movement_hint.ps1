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

function Slice-Function {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End
    )

    $startIndex = $Text.IndexOf($Start)
    if ($startIndex -lt 0) {
        throw "Could not locate function start: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex)
    if ($endIndex -lt 0) {
        throw "Could not locate function end after: $Start"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

Assert-Match `
    -Text $source `
    -Pattern "nav_movement_blocking_menu_last_key\s*=\s*''" `
    -Message 'Movement-blocking menu hint should keep a dedupe key.'

Assert-Match `
    -Text $source `
    -Pattern "nav_movement_blocking_menu_last_tick\s*=\s*0" `
    -Message 'Movement-blocking menu hint should keep a throttle timestamp.'

$hintFunction = Slice-Function `
    -Text $source `
    -Start 'function accessxi.nav_note_movement_blocking_menu' `
    -End "`nfunction accessxi.nav_collision_control_interrupt_state"

Assert-Match `
    -Text $hintFunction `
    -Pattern "Press Escape to move" `
    -Message 'Movement-blocking main menu hint should give the player the direct recovery key.'

Assert-Match `
    -Text $hintFunction `
    -Pattern "speak\(text,\s*false\)" `
    -Message 'Movement-blocking main menu hint should speak without cancelling the current row speech.'

Assert-Match `
    -Text $hintFunction `
    -Pattern "nav_active\s*~=\s*true" `
    -Message 'Movement-blocking main menu hint should be scoped to active nav instead of normal menu browsing.'

$interruptFunction = Slice-Function `
    -Text $source `
    -Start 'function accessxi.nav_collision_control_interrupt_state' `
    -End "`nfunction accessxi.nav_collision_update_control_interrupt"

Assert-Match `
    -Text $interruptFunction `
    -Pattern "accessxi\.nav_note_movement_blocking_menu\(menu_name,\s*tick\(\)\)" `
    -Message 'Nav control interruption should note when the main menu is blocking movement.'

Write-Host 'nav main-menu movement hint static checks ok'
