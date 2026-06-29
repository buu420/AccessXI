$ErrorActionPreference = 'Stop'

$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\main_menu.lua'
$source = Get-Content -LiteralPath $modulePath -Raw

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

function Assert-NoMatch {
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
    -Pattern "current_speech_key\s*=\s*\('main-menu-entry:%s:%d:%d:%d:%s:%s'\):fmt\(" `
    -Message 'Main-menu speech key should be based on stable row identity, not volatile entry pointers.'

Assert-NoMatch `
    -Text $source `
    -Pattern "current_speech_key\s*=\s*\('main-menu-entry:%s:%d:%d:%d:0x%08X:0x%08X:%s:%s'\)" `
    -Message 'Main-menu speech key must not include volatile entry or label pointer values.'

Assert-Match `
    -Text $source `
    -Pattern "main_menu_last_state_key" `
    -Message 'Main-menu verbose state logging should be deduped with a stable state key.'

Assert-Match `
    -Text $source `
    -Pattern "if \(state_key ~= tostring\(accessxi\.main_menu_last_state_key or ''\)\) then" `
    -Message 'Main-menu row state should only log when the meaningful row state changes.'

Write-Host 'main menu stable row identity static checks ok'
