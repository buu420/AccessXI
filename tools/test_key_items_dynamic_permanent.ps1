$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$lua = Join-Path $root 'tools\lua51\lua5.1.exe'
$test = Join-Path $root 'tools\test_key_items_dynamic_permanent.lua'
$module = Join-Path $root 'ashita\addons\accessxi_reader\modules\key_items_dynamic_rows.lua'
$sourcePath = Join-Path $root 'ashita\addons\accessxi_reader\accessxi_reader.lua'

& $lua $test $module
if ($LASTEXITCODE -ne 0) {
    throw "Dynamic permanent key-items Lua checks failed with exit code $LASTEXITCODE."
}

$source = Get-Content -LiteralPath $sourcePath -Raw
if ($source -notmatch "load_module_table\('key_items_dynamic_rows'") {
    throw 'Expected the live reader to load the dynamic key-items resolver.'
}
if ($source -match 'dat_rows:len\(\)\s*==\s*native_total') {
    throw 'Permanent key-item resolution must not require a dynamic list to equal a native row total.'
}
if ($source -match 'rows:len\(\)\s*==\s*native_total') {
    throw 'Selected key-item speech must not depend on a fixed or exact total row count.'
}
if ($source -match 'if \(count ~= 10') {
    throw 'Key Items category detection must not assume ten visible rows means the category screen.'
}
if ($source -match 'index > 9') {
    throw 'Key Items category selection must not assume a fixed last category index.'
}
if ($source -notmatch 'read_i32\(child \+ 0x90\)') {
    throw 'Expected Key Items view identity to use the native evitem state field.'
}
if ($source -notmatch 'classify_native_view') {
    throw 'Expected Key Items dispatch to use the native evitem view classifier.'
}

Write-Host 'Dynamic permanent key-items integration checks passed'
