param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$lua = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'
$test = Join-Path $RepoRoot 'tools\test_search_player_option_menu.lua'
$module = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\menus\search_player_options.lua'
$sourcePath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$nativeMenusPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\menus\native_menus.lua'

& $lua $test $module
if ($LASTEXITCODE -ne 0) {
    throw "Search player option Lua checks failed with exit code $LASTEXITCODE."
}

$source = Get-Content -LiteralPath $sourcePath -Raw
$nativeMenus = Get-Content -LiteralPath $nativeMenusPath -Raw

if ($source -notmatch "load_menu_code_module\('search_player_options',\s*accessxi\.search_player_options_module_context\(\)\)") {
    throw 'Expected the live reader to load the tested search-player option speech module.'
}
if ($nativeMenus -notmatch "menus\s*=\s*T\{\s*'menu    scoption'\s*\},\s*title\s*=\s*'Search'") {
    throw 'Expected menu scoption to enter the known native-menu dispatcher.'
}
if ($source -notmatch "menu_name:eq\('menu    scoption', true\)[\s\S]{0,240}selected\s*=\s*read_current_native_menu_index\(0x4C\)") {
    throw 'Expected menu scoption to use its exact native cursor at object +0x4C.'
}
if ($source -notmatch "if \(menu_name:eq\('menu    scoption', true\)\) then[\s\S]{0,300}search_player_option_menu_speech\(menu_name, selected, entry\)") {
    throw 'Expected menu scoption to dispatch to the tested native-help speech function.'
}
if ($source -match "scoption[\s\S]{0,500}(fixed|static)[-_ ]?(row|count)|scoption[\s\S]{0,500}character[_-]?name") {
    throw 'Search-player option speech must not depend on static rows, fixed counts, or a character name.'
}

Write-Host 'Search player option focused checks passed'
