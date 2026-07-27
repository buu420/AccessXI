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
Require-Match $source '#include\s+"pol_pml/native_text_field\.h"' `
    "The PlayOnline hook must use the exact native text-field decoder."
Require-Match $cmake 'add_library\(accessxi_pol_nvda[\s\S]*src/pol_pml/native_selected_text\.cpp' `
    "The production hook DLL must link the native selected-text decoder."
Require-Match $cmake 'add_library\(accessxi_pol_nvda[\s\S]*src/pol_pml/native_text_field\.cpp' `
    "The production hook DLL must link the native text-field decoder."
Require-Match $buildScript 'pol_pml_selected_text_tests' `
    "The release-stage builder must build the selected-text unit test before running CTest."
Require-Match $buildScript 'pol_pml_text_field_tests' `
    "The release-stage builder must build the native text-field unit test before running CTest."
Require-Match $offlineScript 'pol_pml_selected_text_tests' `
    "The offline native harness must build the selected-text unit test from a clean tree."
Require-Match $offlineScript 'pol_pml_text_field_tests' `
    "The offline native harness must build the text-field unit test from a clean tree."
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
Require-Match $resolver 'read_native_text_field_snapshot\s*\(\s*current_child_object\s*\)' `
    "Current-child speech must resolve retained Add Member values from the exact focused native field."
Require-Match $resolver 'field_focus_speech\s*\(' `
    "Ordinary Add Member fields must compose their geometry-owned label with the retained native value."
Require-Match $resolver 'native_password_object[\s\S]*prelogin_add_member_password_field_label[\s\S]*masked_focus_speech[\s\S]*remember_masked_field_focus' `
    "A geometry-owned Add Member password wrapper must speak its exact label and seed the safe count tracker."
Require-Match $resolver 'if\s*\(\s*!native_password_object\s*\)[\s\S]*read_native_selected_control_text' `
    "Password controls must bypass generic selected-text discovery."
$addMemberGeometry = Function-Body $source "std::string native_prelogin_add_member_label_from_geometry"
Require-Match $addMemberGeometry '\{\s*315,\s*155,\s*461,\s*187,\s*"PlayOnline Password"' `
    "The conditionally revealed PlayOnline Password field must retain its exact Add Member geometry label."
Require-Match $resolver 'geometry_label\s*==\s*"Set Password"[\s\S]*read_native_pulldown_selection_snapshot[\s\S]*add_member_set_password_value[\s\S]*field_focus_speech\s*\(' `
    "Set Password must announce its exact native pulldown selection with the owned field label."
Require-Match $resolver 'native_pulldown_focus[\s\S]*remember_set_password_focus' `
    "The exact Set Password pulldown must seed live native selection tracking."
if ($source -match 'PasswordTextModelVtableRva|PasswordTextLengthRva') {
    throw "The hook must not retain the stale password-model constants that silently rejected the current app.dll."
}
Require-Match $resolver 'read_native_selected_control_text\s*\(\s*current_child_object\s*,\s*snapshot\.nested_child\s*\)' `
    "Current-child speech must try the exact native selected-control text with its captured nested selection proof first."
Require-Match $resolver 'native-selected-text' `
    "Exact native selected-control text must retain its strict source identity."
Require-Match $resolver '!exact_native_value_focus[\s\S]*!geometry_label\.empty' `
    "Static geometry must not override an exact native selected-control or field value."
Require-Match $source 'std::atomic<int>\s+g_silent_selected_image_log_budget\{\s*96\s*\}' `
    "Silent image diagnostics must have a dedicated finite budget that survives the login screen."
Require-Match $resolver 'label\.empty\(\)[\s\S]*log_silent_selected_image_path\s*\(\s*snapshot\s*\)' `
    "A silent selected image must emit its bounded native label path before generic diagnostics are exhausted."
Require-Match $resolver 'label\.empty\(\)[\s\S]*read_native_selected_image_caption\s*\(\s*snapshot\s*\)[\s\S]*label\.empty\(\)[\s\S]*log_silent_selected_image_path\s*\(\s*snapshot\s*\)' `
    "Current-child speech must try the exact native image getter caption before retaining the silent diagnostic path."
Require-Match $resolver 'native_image_getter_focus' `
    "Native image getter captions must retain a distinct source identity through current-child resolution."
Require-Match $resolver 'label_source[\s\S]*native-image-getter' `
    "Native image getter captions must not be relabeled as generic native selected text."
Require-Match $resolver 'candidate_source[\s\S]*native-image-getter' `
    "Native image getter source identity must survive into the queued focus candidate."

$imageGetter = Function-Body $source "std::string read_native_selected_image_getter_text"
Require-Match $imageGetter 'vtable\s*\+\s*0x124' `
    "The diagnostic getter must use the Ghidra-proven native label virtual slot."
Require-Match $imageGetter 'call_native_selected_image_getter' `
    "The diagnostic getter must cross the live native call boundary through its protected wrapper."
Require-Match $imageGetter 'read_bounded_native_image_getter_text' `
    "The native getter must use the unit-tested 120-character caption reader."
if ($imageGetter -match 'read_wide_text_safely\s*\(\s*native_text\s*,\s*63\s*\)') {
    throw "The native image getter must not retain the 63-character buffer that hid the live banner caption."
}
$imageGetterCall = Function-Body $source "const wchar_t* call_native_selected_image_getter"
Require-Match $imageGetterCall '__try[\s\S]*__except' `
    "The diagnostic virtual getter must be protected against invalid live objects."

$imageCaption = Function-Body $source "std::string read_native_selected_image_caption"
Require-Match $imageCaption 'inspect_selected_image_path' `
    "Native image speech must retain the unit-tested exact sheet-to-image hierarchy proof."
Require-Match $imageCaption 'read_native_selected_image_getter_text\s*\([^,]+,\s*0\s*\)' `
    "Native image speech must read the primary getter state."
Require-Match $imageCaption 'read_native_selected_image_getter_text\s*\([^,]+,\s*1\s*\)' `
    "Native image speech must read the alternate getter state."
Require-Match $imageCaption 'choose_selected_image_getter_caption' `
    "Native image speech must require the unit-tested caption agreement and PML-marker cleanup."
Require-Match $imageCaption 'selected_image_getter_caption_allowed' `
    "Native image speech must use its unit-tested 120-character resource-safe caption filter."
Require-Match $imageCaption 'useful_text' `
    "Native image speech must retain the generic text-quality checks."
if ($imageCaption -match 'prelogin_probe_candidate_label') {
    throw "Native image captions must not be sent through the unrelated 80-character generic probe ceiling."
}

$imageDiagnostic = Function-Body $source "void log_silent_selected_image_path"
Require-Match $imageDiagnostic 'inspect_selected_image_path' `
    "Silent image diagnostics must use the unit-tested exact hierarchy inspection."
Require-Match $imageDiagnostic 'PRELOGIN_SILENTIMAGE' `
    "Silent image diagnostics need a stable searchable log identity."
Require-Match $imageDiagnostic 'primaryAlt=.*alternateAlt=.*getter0=.*getter1=' `
    "The diagnostic must compare both raw captions with both native getter states."
if ($imageDiagnostic -match 'dispatch_speech|speak_prelogin|speech_sink') {
    throw "Silent image diagnostics must never speak unverified values."
}

$filter = Function-Body $source "bool prelogin_pml_focus_candidate_label_allowed"
Require-Match $filter 'native-selected-text[\s\S]*prelogin_probe_candidate_label' `
    "Exact selected-control labels must use the generic native text safety filter, not the old login atlas."
Require-Match $filter 'native-image-getter[\s\S]*selected_image_getter_caption_allowed' `
    "Native image getter captions must retain their 120-character resource-safe filter at every focus gate."

$addMemberGate = Function-Body $source "bool native_prelogin_add_member_current_child_speech_allowed"
Require-Match $addMemberGate 'native-image-getter' `
    "Native image getter captions must be recognized as exact native evidence by add-member isolation."

$maskedPoll = Function-Body $source "void poll_masked_field_state"
Require-Match $maskedPoll 'retained\.state\.object[\s\S]*read_native_text_field_snapshot[\s\S]*snapshot\.field\s*!=\s*retained\.state\.object' `
    "Password edits must reread the exact retained CPasswordField and reject a changed native owner."
Require-Match $maskedPoll 'observe_tracked_native_value[\s\S]*masked_delta_speech' `
    "Password edits must speak only verified count transitions."
if ($maskedPoll -match 'PmlGlobalFocusManagerRva|manager_value|\+\s*0x164') {
    throw "Password polling must not use the CPolWinApp global as a focus manager."
}

$setPasswordPoll = Function-Body $source "void poll_set_password_state"
Require-Match $setPasswordPoll 'retained\.state\.object[\s\S]*read_native_pulldown_highlight_snapshot[\s\S]*highlight\.active[\s\S]*highlighted_index[\s\S]*read_native_pulldown_selection_snapshot[\s\S]*add_member_set_password_value' `
    "Set Password changes must prefer the exact live CPulldown row and fall back to the committed value only after the dropdown closes."
Require-Match $setPasswordPoll 'observe_tracked_native_value[\s\S]*TrackedNativeValueUpdate::changed[\s\S]*speak_prelogin_label' `
    "Set Password must announce only a changed, accepted native selection."
if ($setPasswordPoll -match 'GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT') {
    throw "Set Password changes must never be inferred from keyboard input."
}

$worker = Function-Body $source "void run_reloaded_native_hook_iteration"
Require-Match $worker 'poll_masked_field_state\s*\(\s*\)[\s\S]*poll_set_password_state\s*\(\s*\)' `
    "The native worker must poll both retained Add Member controls while transient overlays own focus."

Write-Host "ok"
