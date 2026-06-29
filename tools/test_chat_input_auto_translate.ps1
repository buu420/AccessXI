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

$stateStart = $source.IndexOf('local function current_chat_input_state()')
$stateEnd = $source.IndexOf('local function chat_input_speech', $stateStart)
if ($stateStart -lt 0 -or $stateEnd -lt 0) {
    throw 'Could not locate current_chat_input_state block.'
}
$stateBody = $source.Substring($stateStart, $stateEnd - $stateStart)

$speechStart = $source.IndexOf('local function chat_input_speech')
$speechEnd = $source.IndexOf('function accessxi.remember_chat_input_state', $speechStart)
if ($speechStart -lt 0 -or $speechEnd -lt 0) {
    throw 'Could not locate chat_input_speech block.'
}
$speechBody = $source.Substring($speechStart, $speechEnd - $speechStart)

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.clean_chat_input_display_text\(text\)' `
    -Message 'Expected a display cleaner that can parse auto-translate text before chat input speech.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.chat_input_auto_translate_phrase\(state\)' `
    -Message 'Expected a helper that extracts the selected auto-translate phrase from chat input display text.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.chat_input_auto_translate_speech\(previous_state,\s*state\)' `
    -Message 'Expected a helper that speaks auto-translate display changes separately from raw typing.'

Assert-Match `
    -Text $stateBody `
    -Pattern "local display = accessxi\.clean_chat_input_display_text\(safe_call\(function \(\) return chat:GetInputTextDisplay\(\); end, ''\)\)" `
    -Message 'Expected current_chat_input_state to clean display text through the auto-translate-aware cleaner.'

Assert-Match `
    -Text $source `
    -Pattern "text = text:gsub\('\^f\(\.\+\)ffd\$', '%1'\)" `
    -Message 'Expected fallback cleanup for the live f...ffd auto-translate display wrapper.'

Assert-Match `
    -Text $speechBody `
    -Pattern 'accessxi\.chat_input_auto_translate_speech\(previous_state,\s*state\)[\s\S]*?if \(auto_translate_active\) then[\s\S]*?return auto_translate_text,\s*auto_translate_key' `
    -Message 'Expected chat_input_speech to handle auto-translate display changes before raw text/caret speech.'

Assert-Match `
    -Text $source `
    -Pattern "auto-translate:%d:%s:%s:%d" `
    -Message 'Expected auto-translate speech key to include display text so arrowed candidates can speak.'

Write-Host 'chat input auto-translate checks ok'
