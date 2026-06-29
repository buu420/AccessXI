$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "Addon not found: $addonPath"
}

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

function Assert-NotMatch {
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
    -Pattern "function accessxi\.chat_input_auto_translate_phrase\(state\)" `
    -Message 'chat_input_auto_translate_phrase helper should exist.'

Assert-Match `
    -Text $source `
    -Pattern "local display = accessxi\.clean_chat_input_display_text\(safe_call\(function \(\) return chat:GetInputTextDisplay\(\); end, ''\)\)" `
    -Message 'current_chat_input_state should preserve a display value cleaned for auto-translate text.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local function chat_input_speech\(state, just_opened\).*?accessxi\.chat_input_auto_translate_speech\(previous_state,\s*state\)" `
    -Message 'chat_input_speech should check auto-translate display changes before raw typing.'

Assert-Match `
    -Text $source `
    -Pattern "local\s+key\s*=\s*\('%d:%s:%d'\):fmt\(state\.status or 0,\s*state\.raw\s*or\s*''\s*,\s*state\.caret or 0\)" `
    -Message 'normal chat_input_speech key should still use raw text.'

Assert-Match `
    -Text $source `
    -Pattern "local\s+text_key\s*=\s*\('%d:%s'\):fmt\(state\.status or 0,\s*state\.raw\s*or\s*''\)" `
    -Message 'normal chat_input_speech text-key should still use raw text.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.chat_input_last_text_key\s*=\s*\('%d:%s'\):fmt\(state\.status or 0,\s*state\.raw\s*or\s*''\)" `
    -Message 'chat input memory should remember raw text keys for ordinary typing.'

Assert-Match `
    -Text $source `
    -Pattern "auto-translate:%d:%s:%s:%d" `
    -Message 'auto-translate speech key should include display text so arrowed candidates can speak.'

Assert-NotMatch `
    -Text $source `
    -Pattern "local function chat_input_spoken_text" `
    -Message 'The auto-translate fix should not use the broad spoken-text keying helper.'

Write-Host 'chat input auto-translate live checks ok'
