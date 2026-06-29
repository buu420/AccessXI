$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-AddonPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -notmatch $Pattern) {
        throw "Missing menu dispatch probe contract: $Name"
    }
}

Assert-AddonPattern 'last_menu_dispatch_probe_log\s*=\s*''''\s*,' 'dedupe state for central dispatch probe'
Assert-AddonPattern 'function\s+accessxi\.log_menu_dispatch_probe\(name,\s*previous_menu_name\)' 'central dispatch probe helper'
Assert-AddonPattern 'state menu-dispatch-probe' 'dispatch probe log marker'
Assert-AddonPattern 'accessxi\.survival_guide_query_child_state_for_obj\(obj\)' 'dispatch probe reads child cursor state'
Assert-AddonPattern 'read_current_native_menu_index\(0x4C\)' 'dispatch probe falls back to native cursor index'
Assert-AddonPattern 'GetWindowHelpTitle' 'dispatch probe logs live target-window help title'
Assert-AddonPattern 'GetWindowHelpString' 'dispatch probe logs live target-window help text'

$speechStart = $source.IndexOf('local function current_menu_speech(full_details)')
if ($speechStart -lt 0) {
    throw 'Missing current_menu_speech function'
}
$speechEnd = $source.IndexOf("`nend`r`n`r`nfunction accessxi.clear_chat_log_deferred_speech", $speechStart)
if ($speechEnd -lt 0) {
    $speechEnd = $source.Length
}
$speechBody = $source.Substring($speechStart, $speechEnd - $speechStart)

$rememberIndex = $speechBody.IndexOf('accessxi.remember_generic_comyn_context')
$probeIndex = $speechBody.IndexOf('accessxi.log_menu_dispatch_probe(name, previous_menu_name)')
$macroIndex = $speechBody.IndexOf('accessxi.macro_live_palette_current_speech')
$nativeIndex = $speechBody.IndexOf('accessxi.native_main_menu_speech')
$playermoSuppressIndex = $speechBody.IndexOf("name:eq('menu    playermo', true)")

if ($rememberIndex -lt 0) {
    throw 'current_menu_speech does not remember generic comyn context'
}
if ($probeIndex -lt 0) {
    throw 'current_menu_speech does not call the central dispatch probe'
}
if ($macroIndex -lt 0) {
    throw 'current_menu_speech does not call macro live palette speech'
}
if ($nativeIndex -lt 0) {
    throw 'current_menu_speech does not call native main menu speech'
}
if ($playermoSuppressIndex -lt 0) {
    throw 'current_menu_speech does not have playermo suppress branch'
}
if ($probeIndex -lt $rememberIndex) {
    throw 'dispatch probe should run after menu context is remembered'
}
if ($probeIndex -gt $macroIndex) {
    throw 'dispatch probe must run before macro/menu-specific handlers can swallow the menu'
}
if ($probeIndex -gt $nativeIndex) {
    throw 'dispatch probe must run before native_main_menu_speech'
}
if ($probeIndex -gt $playermoSuppressIndex) {
    throw 'dispatch probe must run before playermo suppression'
}

Write-Host 'menu dispatch probe static checks ok'
