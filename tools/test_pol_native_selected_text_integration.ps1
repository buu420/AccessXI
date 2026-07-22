param(
    [string]$RepoRoot = "C:\Users\buu42\AccessXI"
)

$ErrorActionPreference = "Stop"
$repo = [System.IO.Path]::GetFullPath($RepoRoot)
$SourcePath = Join-Path $repo 'src\accessxi_pol.cpp'
$CMakePath = Join-Path $repo 'CMakeLists.txt'
$BuildScriptPath = Join-Path $repo 'tools\build_pol_native_asi.ps1'
$OfflineScriptPath = Join-Path $repo 'tools\test_pol_native_offline.ps1'
$source = Get-Content -LiteralPath $SourcePath -Raw
$cmake = Get-Content -LiteralPath $CMakePath -Raw
$buildScript = Get-Content -LiteralPath $BuildScriptPath -Raw
$offlineScript = Get-Content -LiteralPath $OfflineScriptPath -Raw

function Require-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Function-Body {
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Function not found: $Signature" }
    $brace = $Text.IndexOf("{", $start)
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -eq "{") { $depth++ }
        elseif ($Text[$index] -eq "}") {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    throw "Unterminated function: $Signature"
}

Require-Match $source '#include\s+"pol_pml/native_selected_text\.h"' `
    "The PlayOnline hook must use the tested native selected-text decoder."
Require-Match $cmake 'add_library\(accessxi_pol_nvda[\s\S]*src/pol_pml/native_selected_text\.cpp' `
    "The production hook DLL must link the native selected-text decoder."
Require-Match $buildScript 'pol_pml_selected_text_tests' `
    "The release-stage builder must build the selected-text unit test before running CTest."
Require-Match $offlineScript 'pol_pml_selected_text_tests' `
    "The offline native harness must build the selected-text unit test from a clean tree."
Require-Match $offlineScript 'test_pol_native_selected_text_integration\.ps1' `
    "The offline native harness must run the selected-text integration contract."

$remember = Function-Body $source "void remember_current_child_candidate"
Require-Match $remember 'captured_sheet_row' `
    "Nested CPmlImage focus must not overwrite the captured CPmlSheet selection row."
Require-Match $remember 'nested_child' `
    "The current-child coalescer must preserve only the proven sheet-to-child hierarchy."
if ($remember -match 'GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT') {
    throw "Native row selection must never be inferred from keyboard input."
}

$resolver = Function-Body $source "void process_current_child_candidate"
Require-Match $resolver 'read_native_selected_control_text\s*\(\s*current_child_object\s*\)' `
    "Current-child speech must try the exact native selected-control text first."
Require-Match $resolver 'native-selected-text' `
    "Exact native selected-control text must retain its strict source identity."
Require-Match $resolver '!native_selected_text_focus[\s\S]*!geometry_label\.empty' `
    "Static geometry must not override an exact native selected-control label."

$filter = Function-Body $source "bool prelogin_pml_focus_candidate_label_allowed"
Require-Match $filter 'native-selected-text[\s\S]*prelogin_probe_candidate_label' `
    "Exact selected-control labels must use the generic native text safety filter, not the old login atlas."

Write-Host "ok"
