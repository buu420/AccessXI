param(
    [string]$SourcePath = "C:\Users\buu42\AccessXI\src\accessxi_pol.cpp"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Source file not found: $SourcePath"
}

$source = Get-Content -LiteralPath $SourcePath -Raw
if ([string]::IsNullOrWhiteSpace($source)) {
    throw "Source file is empty: $SourcePath"
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-Before {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $firstIndex = $Text.IndexOf($First, [System.StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [System.StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        throw $Message
    }
}

function Get-FunctionBody {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )

    $start = $Text.IndexOf($Signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Function signature not found: $Signature"
    }

    $brace = $Text.IndexOf("{", $start)
    if ($brace -lt 0) {
        throw "Function body not found: $Signature"
    }

    $depth = 0
    for ($i = $brace; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq "{") {
            $depth++
        }
        elseif ($Text[$i] -eq "}") {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $i - $start + 1)
            }
        }
    }

    throw "Function body did not terminate: $Signature"
}

$nativeAtlas = Get-FunctionBody $source "bool native_prelogin_atlas_label"
Assert-Contains $nativeAtlas '"Yes"' `
    "Native pre-login atlas must allow native Yes confirmation buttons."
Assert-Contains $nativeAtlas '"No"' `
    "Native pre-login atlas must allow native No confirmation buttons."
Assert-Contains $nativeAtlas '"Keyboard"' `
    "Native pre-login atlas must allow the Ghidra-confirmed startup Keyboard button."
Assert-Contains $nativeAtlas '"Log In"' `
    "Native pre-login atlas must allow the Ghidra-confirmed member Log In command."
Assert-Contains $nativeAtlas '"Settings"' `
    "Native pre-login atlas must allow the Ghidra-confirmed member/login Settings command."
Assert-Contains $nativeAtlas '"Delete"' `
    "Native pre-login atlas must allow the Ghidra-confirmed member Delete command."
Assert-Contains $nativeAtlas '"Back"' `
    "Native pre-login atlas must allow the Ghidra-confirmed member Back command."
Assert-Contains $nativeAtlas '"Enter Member Password"' `
    "Native pre-login atlas must allow the Ghidra-confirmed member password prompt."
Assert-Contains $nativeAtlas '"Member Information"' `
    "Native pre-login atlas must allow the Ghidra-confirmed member information label."
Assert-Contains $nativeAtlas '"Login Information"' `
    "Native pre-login atlas must allow the Ghidra-confirmed login information label."
Assert-Contains $nativeAtlas '"Square Enix Password"' `
    "Native pre-login atlas must allow the Ghidra-confirmed Square Enix Password field label."
Assert-Contains $nativeAtlas '"Connect to PlayOnline"' `
    "Native pre-login atlas must allow the Ghidra-confirmed Connect to PlayOnline label."
Assert-Contains $nativeAtlas '"Automatically log in at startup"' `
    "Native pre-login atlas must allow the Ghidra-confirmed automatic-login checkbox label."
Assert-Contains $nativeAtlas '"Connect"' `
    "Native pre-login atlas must allow the Ghidra-confirmed login Connect command."

$labelFilter = Get-FunctionBody $source "bool prelogin_pml_focus_candidate_label_allowed"
Assert-Before $labelFilter 'lower == "play"' 'return native_prelogin_atlas_label(label)' `
    "Broad direct/body labels such as Play must be rejected before atlas-backed focus speech."

$reloadedWorker = Get-FunctionBody $source "void run_reloaded_native_hook_iteration"
Assert-Contains $reloadedWorker 'speak_pending_prelogin_pml_focus_candidate\s*\(\s*"reloaded-native-focus"\s*\)' `
    "Reloaded native worker must drain the strict PML focus candidate path."
Assert-Contains $reloadedWorker 'speak_current_prelogin_native_focus\s*\(\s*"reloaded-native-focus"\s*\)' `
    "Reloaded native worker must retain the current native focus fallback after strict PML drain."
Assert-Before $reloadedWorker 'speak_pending_prelogin_pml_focus_candidate("reloaded-native-focus")' 'speak_current_prelogin_native_focus("reloaded-native-focus")' `
    "Reloaded worker must try strict PML focus before broader cached focus fallback."
if ($reloadedWorker -match "GetAsyncKeyState") {
    throw "Reloaded native worker must not monitor arrows, Tab, Enter, or any other keyboard state."
}

$currentFocusSampler = Get-FunctionBody $source "bool speak_current_prelogin_native_focus"
Assert-Contains $source 'PmlGlobalFocusManagerRva\s*=\s*0x004E13C8u' `
    "Startup member-list focus sampling must use the Ghidra-backed global focus manager at app.dll + 0x4E13C8."
Assert-Contains $currentFocusSampler 'app_base\s*\+\s*PmlGlobalFocusManagerRva' `
    "Current native focus sampler must read the native global focus-manager slot, not infer selection from timing or keys."
Assert-Contains $currentFocusSampler 'read_ptr_safely\s*\(\s*static_cast<const uint8_t\*>\s*\(\s*manager\s*\)\s*\+\s*0x164\s*,\s*&current_child\s*\)' `
    "Current native focus sampler must use the native manager +0x164 current-child field."
Assert-Contains $currentFocusSampler 'g_last_sampled_prelogin_focus_child' `
    "Current native focus sampler must suppress stable-focus repeats instead of polling speech continuously."
Assert-Contains $currentFocusSampler 'process_current_child_candidate\s*\(\s*snapshot\s*,\s*reason\s*\)' `
    "Current native focus sampler must reuse the strict current-child speech path."
if ($currentFocusSampler -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT|VK_RETURN|VK_TAB") {
    throw "Current native focus sampler must not monitor keys."
}

$memberNameReader = Get-FunctionBody $source "std::string read_native_prelogin_member_name"
Assert-Contains $source 'PreloginMemberNameAccessorRva\s*=\s*0x0001CFB1u' `
    "Startup member names must come from the Ghidra-backed native member-name accessor at app.dll + 0x1CFB1."
Assert-Contains $source 'PreloginMemberNameWideGlobalRva\s*=\s*0x0048E592u' `
    "Startup member-name fallback must use the Ghidra-backed native wide string global at app.dll + 0x48E592."
Assert-Contains $source 'PmlTextSetterRva\s*=\s*0x00064156u' `
    "The Ghidra-backed wide text setter RVA must remain documented so the crash-disabled hook is not rediscovered as new evidence."
Assert-Contains $memberNameReader 'reinterpret_cast<MemberNameAccessor_t>\s*\(\s*app_base\s*\+\s*PreloginMemberNameAccessorRva\s*\)' `
    "Native member-name reader must call the native member-name accessor instead of hardcoding account names."
Assert-Contains $source 'std::string\s+read_wide_text_safely\s*\(' `
    "Native member-name reader must use a bounded safe wide-string copy instead of unguarded raw pointer conversion."
Assert-Contains $memberNameReader 'read_wide_text_safely\s*\(\s*wide_name\s*,\s*32\s*\)' `
    "Native member-name reader must safely convert the returned native wide string."
Assert-Contains $memberNameReader 'app_base\s*\+\s*PreloginMemberNameWideGlobalRva' `
    "Native member-name reader must fall back to the Ghidra-proven native wide string global when the accessor result is unavailable."
Assert-Before $memberNameReader 'call_native_prelogin_member_name_accessor' 'PreloginMemberNameWideGlobalRva' `
    "Native member-name reader must prefer the accessor before using the direct global fallback."
Assert-Contains $memberNameReader 'prelogin_member_dynamic_label\s*\(\s*label\s*\)' `
    "Native member-name reader must still pass the dynamic-member allowlist."
if ($memberNameReader -match 'Brice|buu420|XQDW0533') {
    throw "Native member-name reader must not hardcode live account values."
}

$memberDynamicLabel = Get-FunctionBody $source "bool prelogin_member_dynamic_label"
Assert-Contains $memberDynamicLabel 'alnum_count\s*<\s*4' `
    "Dynamic member labels must reject tiny garbage such as the live false positives 'v t' and 'xub'."
Assert-Contains $memberDynamicLabel 'space_count' `
    "Dynamic member labels must count spaces so raw memory fragments with padded gaps cannot pass as member names."
Assert-Contains $memberDynamicLabel 'label\.find\("  "\)\s*!=\s*std::string::npos' `
    "Dynamic member labels must reject consecutive internal spaces such as the live false positive 'U  QQS'."
Assert-Contains $memberDynamicLabel 'space_count\s*>\s*1' `
    "Dynamic member labels must reject multi-gap raw memory fragments such as 'Z      4t'."
Assert-Contains $memberDynamicLabel 'shortest_space_token_alnum_count' `
    "Dynamic member labels with spaces must reject one-character trailing fragments such as the live false positive 'P9x p'."
Assert-Contains $memberDynamicLabel 'lower\.find\("get_"\)\s*==\s*0' `
    "Dynamic member labels must reject managed method-name fragments such as the live false positive 'get_Current'."
Assert-Contains $memberDynamicLabel 'lower\.find\("system\."\)' `
    "Dynamic member labels must reject managed namespace fragments from unrelated CLR memory."
Assert-Contains $memberDynamicLabel 'lower\.find\("firstw"\)' `
    "Dynamic member labels must reject native/CLR helper-symbol fragments such as the live false positive 'le32FirstW'."
Assert-Contains $memberDynamicLabel 'longest_alnum_run\s*<\s*2' `
    "Dynamic member labels must reject whitespace-separated single-letter memory fragments."
Assert-Contains $memberDynamicLabel 'std::isalnum' `
    "Dynamic member labels must count native alphanumeric characters."
Assert-Contains $memberDynamicLabel "ch != ' ' && ch != '-' && ch != '_'" `
    "Dynamic member labels must reject punctuation-heavy memory fragments such as q A u + @ f J M 1."
Assert-Contains $memberDynamicLabel 'label\.front\(\)\s*==\s*'' ''' `
    "Dynamic member labels must reject leading whitespace from raw memory fragments."
Assert-Contains $memberDynamicLabel 'label\.back\(\)\s*==\s*'' ''' `
    "Dynamic member labels must reject trailing whitespace from raw memory fragments."
Assert-Contains $memberDynamicLabel 'lower\s*==\s*"ccomponent"' `
    "Dynamic member labels must reject native class/control names such as the live false positive CComponent."
Assert-Contains $memberDynamicLabel 'lower\s*==\s*"playonline viewer"' `
    "Dynamic member labels must reject the live startup-window title false positive PlayOnline Viewer."

$startupMemberRect = Get-FunctionBody $source "bool native_prelogin_startup_member_list_focus_rect"
Assert-Contains $startupMemberRect '\{\s*0,\s*0,\s*392,\s*232,\s*"startup member list",\s*0x04B570D8u\s*\}' `
    "Startup member-list focus must be guarded by the Ghidra/live-confirmed RegularMenber_ListWnd list container geometry."
if ($startupMemberRect -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Startup member-list focus geometry must not infer selection from keys."
}

$startupMemberFocus = Get-FunctionBody $source "std::string native_prelogin_startup_member_name_from_focus"
Assert-Contains $startupMemberFocus 'native_prelogin_startup_member_list_focus_rect\s*\(\s*current_child_object\s*\)' `
    "Startup member-name recovery must require the native startup member-list focus rectangle."
Assert-Contains $source 'std::string\s+native_prelogin_startup_member_name_from_child_slots\s*\(' `
    "Startup member-name recovery must inspect the Ghidra-backed member-name child slots before falling back to stale globals."
$startupMemberChildSlots = Get-FunctionBody $source "std::string native_prelogin_startup_member_name_from_child_slots"
Assert-Contains $startupMemberChildSlots '0x2CCu' `
    "Startup member-name child-slot recovery must include the Ghidra-backed in_ECX[0xb3] member-name widget slot."
Assert-Contains $startupMemberChildSlots '0x2C0u' `
    "Startup member-name child-slot recovery must include the related in_ECX[0xb0] member-name widget slot used by member/password frames."
Assert-Contains $startupMemberChildSlots 'read_ptr_safely' `
    "Startup member-name child-slot recovery must read native child pointers safely."
Assert-Contains $startupMemberChildSlots 'best_native_pml_dynamic_text_from_object' `
    "Startup member-name child-slot recovery must read the native dynamic text from the child widget."
Assert-Contains $startupMemberChildSlots 'prelogin_member_dynamic_label' `
    "Startup member-name child-slot recovery must keep the dynamic-member false-positive guard."
if ($startupMemberChildSlots -match 'return\s+label\s*;') {
    throw "Startup member-name child-slot probing must not directly return text for speech; live proof showed these slots can expose class/control garbage like CComponent."
}
if ($startupMemberChildSlots -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Startup member-name child-slot recovery must not infer selection from keys."
}
Assert-Contains $source 'std::string\s+native_prelogin_startup_member_name_from_model_fields\s*\(' `
    "Startup member-name recovery must include the native RegularMember model-field bridge proven by REGMEMBERMODEL logging."
$startupMemberModelFields = Get-FunctionBody $source "std::string native_prelogin_startup_member_name_from_model_fields"
$startupMemberModelLink = Get-FunctionBody $source "std::string native_prelogin_dynamic_label_from_member_model_link"
$startupMemberModelRecovery = $startupMemberModelFields + "`n" + $startupMemberModelLink
Assert-Contains $startupMemberModelFields 'native_prelogin_startup_member_list_focus_rect\s*\(\s*object\s*\)' `
    "Startup RegularMember model-field recovery must require the native startup member-list focus rectangle."
Assert-Contains $startupMemberModelFields '0x2A8u' `
    "Startup RegularMember model-field recovery must inspect the Ghidra/log-proven +0x2A8 member object slot."
Assert-Contains $startupMemberModelFields '0x318u' `
    "Startup RegularMember model-field recovery must cover the bounded RegularMember model field range through +0x318."
Assert-Contains $startupMemberModelRecovery '0x0B8u' `
    "Startup RegularMember model-field recovery must inspect the live REGMEMBERMODEL +0x0B8 linked label component."
Assert-Contains $startupMemberModelRecovery '0x0B4u' `
    "Startup RegularMember model-field recovery must inspect the repeatedly proven REGMEMBERMODEL +0x0B4 linked label component."
Assert-Contains $startupMemberModelRecovery '0x124u' `
    "Startup RegularMember model-field recovery must inspect the older working REGMEMBERMODEL +0x124 linked label component."
Assert-Contains $startupMemberModelRecovery '0x128u' `
    "Startup RegularMember model-field recovery must inspect the archived REGMEMBERMODEL +0x128 linked label component."
Assert-Contains $startupMemberModelRecovery '0x18Cu' `
    "Startup RegularMember model-field recovery must inspect the archived REGMEMBERMODEL +0x18C linked label component."
if ($startupMemberModelLink -match 'best_native_pml_dynamic_text_from_object\s*\(\s*reinterpret_cast<void\*>\s*\(\s*object\s*\)\s*\)') {
    throw "Startup RegularMember model-field recovery must not accept raw model-object text; live proof showed raw models expose code-symbol false positives like get_Current and le32FirstW."
}
Assert-Contains $startupMemberModelRecovery 'read_ptr_safely' `
    "Startup RegularMember model-field recovery must read native model pointers safely."
Assert-Contains $startupMemberModelRecovery 'best_native_pml_dynamic_text_from_object' `
    "Startup RegularMember model-field recovery must decode native dynamic component text from model-linked objects."
Assert-Contains $startupMemberModelRecovery 'prelogin_member_dynamic_label' `
    "Startup RegularMember model-field recovery must keep the dynamic-member false-positive guard."
Assert-Contains $source 'std::atomic<int>\s+g_startup_member_model_probe_budget\{\s*12\s*\}' `
    "Startup RegularMember model-field probing must have a separate finite budget so root-cause logging cannot lag the startup menu."
Assert-Contains $source 'void\s+log_startup_member_model_probe\s*\(' `
    "Startup RegularMember model-field probing must be isolated in a logging-only helper."
$startupMemberModelProbe = Get-FunctionBody $source "void log_startup_member_model_probe"
Assert-Contains $startupMemberModelProbe 'g_startup_member_model_probe_budget\.fetch_sub' `
    "Startup RegularMember model-field probe must spend a finite diagnostic budget."
Assert-Contains $startupMemberModelProbe 'PRELOGIN_STARTUPMEMBER_MODEL probe' `
    "Startup RegularMember model-field probe must leave a stable log marker for the next live arrow pass."
Assert-Contains $startupMemberModelProbe '0x2A8u' `
    "Startup RegularMember model-field probe must inspect the Ghidra/log-proven +0x2A8 member object slot."
Assert-Contains $startupMemberModelProbe '0x318u' `
    "Startup RegularMember model-field probe must cover the bounded RegularMember model field range through +0x318."
Assert-Contains $startupMemberModelProbe '0x0B8u' `
    "Startup RegularMember model-field probe must inspect the live REGMEMBERMODEL +0x0B8 linked label component."
Assert-Contains $startupMemberModelProbe '0x0B4u' `
    "Startup RegularMember model-field probe must inspect the repeatedly proven REGMEMBERMODEL +0x0B4 linked label component."
Assert-Contains $startupMemberModelProbe '0x124u' `
    "Startup RegularMember model-field probe must inspect the older working REGMEMBERMODEL +0x124 linked label component."
Assert-Contains $startupMemberModelProbe '0x128u' `
    "Startup RegularMember model-field probe must inspect the archived REGMEMBERMODEL +0x128 linked label component."
Assert-Contains $startupMemberModelProbe '0x18Cu' `
    "Startup RegularMember model-field probe must inspect the archived REGMEMBERMODEL +0x18C linked label component."
Assert-Contains $startupMemberModelProbe 'prelogin_probe_candidate_label' `
    "Startup RegularMember model-field probe must log candidate text under the broad probe filter, not the speech allowlist."
if ($startupMemberModelProbe -match "append_reloaded_speech_queue|speak_prelogin_label|GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT|VK_RETURN|VK_TAB") {
    throw "Startup RegularMember model-field probe must be logging-only and must not monitor keys or speak."
}
if ($startupMemberModelRecovery -match 'Brice|buu420|Tsuzee|XQDW0533') {
    throw "Startup RegularMember model-field recovery must not hardcode live account/member names."
}
if ($startupMemberModelRecovery -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT|VK_RETURN|VK_TAB|append_reloaded_speech_queue|speak_prelogin_label") {
    throw "Startup RegularMember model-field recovery must be native-state extraction only, with no key monitoring or speech side effects."
}
Assert-Before $startupMemberFocus 'native_prelogin_startup_member_name_from_child_slots' 'read_native_prelogin_member_name' `
    "Startup member-name recovery must prefer native member-name child slots before the stale/static global accessor."
Assert-Before $startupMemberFocus 'native_prelogin_startup_member_name_from_model_fields' 'read_native_prelogin_member_name' `
    "Startup member-name recovery must prefer the RegularMember model-field bridge before the stale/static global accessor."
Assert-Contains $startupMemberFocus 'read_native_prelogin_member_name\s*\(\s*\)' `
    "Startup member-name recovery must read the native dynamic account name only after focus proof."
Assert-Contains $startupMemberFocus 'prelogin_member_dynamic_label\s*\(\s*label\s*\)' `
    "Startup member-name recovery must keep the dynamic-member false-positive guard."
if ($startupMemberFocus -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Startup member-name recovery must not infer selection from keys."
}

Assert-Contains $source 'bool\s+native_prelogin_startup_member_list_static_focus\s*\(' `
    "Startup member-name recovery must recognize the live current-child Member List container without using guessed order."
$startupMemberStaticFocus = Get-FunctionBody $source "bool native_prelogin_startup_member_list_static_focus"
Assert-Contains $startupMemberStaticFocus 'static_label\s*!=\s*"Member List"' `
    "Startup static member focus must be limited to the native Member List current-child label."
Assert-Contains $startupMemberStaticFocus 'label_source_offset\s*!=\s*0x114' `
    "Startup static member focus must require the live object-tree +0x114 label offset."
Assert-Contains $startupMemberStaticFocus 'atlas_resource\s*!=\s*0' `
    "Startup static member focus must reject atlas-geometry Member List headers and menu rows."
if ($startupMemberStaticFocus -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Startup static member focus must not infer selection from keys."
}

Assert-Contains $source 'bool\s+native_prelogin_startup_member_list_atlas_focus\s*\(' `
    "Startup member-name recovery must recognize the live atlas-backed Member List current child."
$startupMemberAtlasFocus = Get-FunctionBody $source "bool native_prelogin_startup_member_list_atlas_focus"
Assert-Contains $startupMemberAtlasFocus 'object\s*==\s*nullptr' `
    "Atlas Member List focus proof must require a real native current-child object."
Assert-Contains $startupMemberAtlasFocus 'geometry_label\s*==\s*"Member List"' `
    "Atlas Member List focus proof must be limited to the native Member List geometry label."
Assert-Contains $startupMemberAtlasFocus 'atlas_resource\s*==\s*0x04B54740u' `
    "Atlas Member List focus proof must use the Ghidra-backed RegularMember_LoginCommandMenu2_ resource."
if ($startupMemberAtlasFocus -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Atlas Member List focus proof must not infer selection from keys."
}

Assert-Contains $source 'std::string\s+native_prelogin_startup_member_name_from_atlas_member_list_focus\s*\(' `
    "Atlas Member List current-child focus must resolve through the native dynamic member-name reader."
$startupMemberAtlasName = Get-FunctionBody $source "std::string native_prelogin_startup_member_name_from_atlas_member_list_focus"
Assert-Contains $startupMemberAtlasName 'native_prelogin_startup_member_list_atlas_focus\s*\(' `
    "Atlas Member List name recovery must require the narrow atlas current-child proof."
Assert-Contains $startupMemberAtlasName 'native_prelogin_startup_member_name_from_child_slots' `
    "Atlas Member List name recovery must try native member-name child slots before the stale/static global accessor."
Assert-Contains $startupMemberAtlasName 'native_prelogin_startup_member_name_from_model_fields' `
    "Atlas Member List name recovery must try the RegularMember model-field bridge before the stale/static global accessor."
Assert-Contains $startupMemberAtlasName 'read_native_prelogin_member_name\s*\(\s*\)' `
    "Atlas Member List name recovery must call the Ghidra-backed dynamic member-name accessor."
Assert-Contains $startupMemberAtlasName 'prelogin_member_dynamic_label\s*\(\s*label\s*\)' `
    "Atlas Member List name recovery must keep the dynamic-member false-positive guard."
if ($startupMemberAtlasName -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Atlas Member List name recovery must not infer selection from keys."
}

Assert-Contains $source 'std::string\s+native_prelogin_startup_member_name_from_static_member_list_focus\s*\(' `
    "Startup Member List current-child focus must resolve through the native dynamic member-name reader."
$startupMemberStaticName = Get-FunctionBody $source "std::string native_prelogin_startup_member_name_from_static_member_list_focus"
Assert-Contains $startupMemberStaticName 'native_prelogin_startup_member_list_static_focus\s*\(' `
    "Static Member List name recovery must require the narrow static current-child proof."
Assert-Contains $startupMemberStaticName 'native_prelogin_startup_member_name_from_child_slots' `
    "Static Member List name recovery must try native member-name child slots before the stale/static global accessor."
Assert-Contains $startupMemberStaticName 'native_prelogin_startup_member_name_from_model_fields' `
    "Static Member List name recovery must try the RegularMember model-field bridge before the stale/static global accessor."
Assert-Contains $startupMemberStaticName 'read_native_prelogin_member_name\s*\(\s*\)' `
    "Static Member List name recovery must call the native dynamic member-name accessor."
Assert-Contains $startupMemberStaticName 'prelogin_member_dynamic_label\s*\(\s*label\s*\)' `
    "Static Member List name recovery must keep the dynamic-member false-positive guard."
if ($startupMemberStaticName -match "GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Static Member List name recovery must not infer selection from keys."
}

$currentChildResolverForStartupMember = Get-FunctionBody $source "void process_current_child_candidate"
Assert-Before $currentChildResolverForStartupMember `
    'native_prelogin_startup_member_name_from_focus(manager, current_child_object)' `
    'best_native_pml_text_from_object_tree(current_child_object, "current-child"' `
    "Startup-selected member names must be tried before static object-tree labels such as Information can claim the focus."
Assert-Before $currentChildResolverForStartupMember `
    'native_prelogin_startup_member_name_from_static_member_list_focus(manager, current_child_object, label, label_source_offset, atlas_resource)' `
    'if (!geometry_label.empty() && !add_member_value_focus && !add_member_button_focus && !member_dynamic_focus && !startup_member_atlas_focus)' `
    "Live static Member List current-child focus must try the dynamic member name before static geometry/object labels can speak."
Assert-Before $currentChildResolverForStartupMember `
    'native_prelogin_startup_member_name_from_atlas_member_list_focus(' `
    'best_native_pml_text_from_object_tree(current_child_object, "current-child"' `
    "Live atlas Member List current-child focus must try the dynamic member name before object-tree labels can claim the focus."
Assert-Contains $currentChildResolverForStartupMember 'const\s+bool\s+startup_member_focus_rect\s*=\s*native_prelogin_startup_member_list_focus_rect\s*\(\s*current_child_object\s*\)' `
    "Startup Member List focus must be tracked after the native dynamic name attempt so stale object-tree labels cannot claim the row."
Assert-Contains $currentChildResolverForStartupMember 'label\.empty\s*\(\s*\)\s*&&\s*!startup_member_atlas_focus\s*&&\s*!startup_member_focus_rect[\s\S]{0,140}best_native_pml_text_from_object_tree' `
    "Startup and atlas Member List focus must stay off the generic object-tree label path when the native member-name read is empty."
Assert-Contains $currentChildResolverForStartupMember '!startup_member_atlas_focus\)' `
    "Atlas Member List focus must not fall through to static geometry speech as Member List."
Assert-Contains $currentChildResolverForStartupMember 'label_source\s*=\s*"startup-member-dynamic"' `
    "Startup-selected member names must preserve a distinct native dynamic source."
Assert-Contains $currentChildResolverForStartupMember 'startup_member_static_focus[\s\S]{0,620}label\.clear\s*\(\s*\)' `
    "Static Member List focus must stay silent if the native dynamic member-name read is empty."

$pendingPmlFocusTrusted = Get-FunctionBody $source "bool prelogin_pending_pml_focus_candidate_trusted_for_drain"
Assert-Contains $pendingPmlFocusTrusted 'prelogin_pml_focus_candidate_label_allowed\s*\(\s*candidate\.source\.c_str\s*\(\s*\),\s*candidate\.label\s*\)' `
    "Pending PML trusted-candidate helper must reuse the strict source-plus-label focus filter."
Assert-Contains $pendingPmlFocusTrusted 'std::strcmp\s*\(\s*source_text\s*,\s*"selected-index"\s*\)\s*==\s*0[\s\S]{0,80}return\s+true' `
    "Selected-index labels must remain the only non-current-child PML drain path."
Assert-Contains $pendingPmlFocusTrusted 'std::strcmp\s*\(\s*source_text\s*,\s*"selected-member-dynamic"\s*\)\s*==\s*0[\s\S]{0,120}return\s+candidate\.focused_flag\s*&&\s*prelogin_member_dynamic_label\s*\(\s*candidate\.label\s*\)' `
    "Selected dynamic member names must drain only from the native selected-index path and the dynamic-member allowlist."
Assert-Contains $pendingPmlFocusTrusted 'std::strcmp\s*\(\s*source_text\s*,\s*"direct-fields"\s*\)\s*==\s*0[\s\S]{0,180}return\s+candidate\.current_child\s*&&\s*prelogin_setup_form_value_cell_label\s*\(\s*source_text\s*,\s*candidate\.label\s*\)' `
    "Direct-fields must stay on the narrow current-child setup value-cell path."
Assert-Contains $pendingPmlFocusTrusted 'return\s+candidate\.current_child\s*&&[\s\S]{0,520}std::strcmp\s*\(\s*source_text\s*,\s*"semantic"\s*\)\s*==\s*0' `
    "Semantic PML labels must require current-child proof before draining; unproven setup subtree labels caused random POL speech."
Assert-Contains $pendingPmlFocusTrusted 'candidate\.snapshot_current_child' `
    "Pending PML drain must preserve deferred current-child proof instead of re-reading stale manager state."
if ($pendingPmlFocusTrusted -match 'return\s+std::strcmp\s*\(\s*source_text\s*,\s*"semantic"\s*\)\s*==\s*0') {
    throw "Pending PML trusted-candidate helper must not broadly trust semantic labels."
}

$addMemberValueLabel = Get-FunctionBody $source "bool prelogin_add_member_value_label"
Assert-Contains $addMemberValueLabel '"PlayOnline Password"' `
    "Add Member value-label allowlist must include the native PlayOnline Password setting."
Assert-Contains $addMemberValueLabel '"Confirm Password"' `
    "Add Member value-label allowlist must include the native Confirm Password field."
Assert-Contains $addMemberValueLabel '"Not set"' `
    "Add Member value-label allowlist must include the native Set Password value."
Assert-Contains $addMemberValueLabel '"Do Not Use"' `
    "Add Member value-label allowlist must include the native one-time-password value."
if ($addMemberValueLabel -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Add Member value-label allowlist must not infer selection from keys."
}

$pendingPmlFocusDrain = Get-FunctionBody $source "bool speak_pending_prelogin_pml_focus_candidate"
Assert-Contains $pendingPmlFocusDrain 'const\s+bool\s+trusted_candidate\s*=\s*prelogin_pending_pml_focus_candidate_trusted_for_drain\s*\(\s*candidate\s*\)' `
    "Pending PML focus drain must decide speech from the strict trusted-candidate helper."
Assert-Contains $pendingPmlFocusDrain 'if\s*\(\s*!trusted_candidate\s*\)[\s\S]{0,300}PRELOGIN_PMLFOCUSGAIN untrusted-silent[\s\S]{0,300}return\s+true' `
    "Pending PML focus drain must consume untrusted candidates silently so broad fallback focus paths cannot speak random setup subtree labels."
Assert-Before $pendingPmlFocusDrain 'if (!trusted_candidate)' 'PRELOGIN_PMLFOCUSGAIN coalesced-speak' `
    "Pending PML focus drain must reject untrusted candidates before the speech path."
if ($pendingPmlFocusDrain -match 'candidate\.distinct_count\s*>\s*2\s*&&\s*!candidate\.current_child\s*&&\s*!g_navigation_recent') {
    throw "Pending PML focus drain still uses the old broad distinct-count guard instead of strict candidate trust."
}

$pmlFocusClaimGate = Get-FunctionBody $source "bool prelogin_pml_focus_can_claim_burst"
Assert-Contains $pmlFocusClaimGate 'selected-index' `
    "PML focus claim gate must preserve selected-index speech."
Assert-Contains $source 'bool\s+snapshot_current_child\s*=\s*false' `
    "PML focus candidates must remember when current-child proof came from the native setter snapshot."
Assert-Contains $pmlFocusClaimGate 'bool\s+snapshot_current_child' `
    "PML focus claim gate must accept snapshot current-child proof so deferred worker processing does not re-read stale manager state."
Assert-Contains $pmlFocusClaimGate 'prelogin_pml_focus_current_child\s*\(\s*manager\s*,\s*focused_object\s*\)' `
    "PML focus claim gate must keep manager +0x164 current-child proof available."
Assert-Contains $pmlFocusClaimGate 'const\s+bool\s+current_child\s*=\s*snapshot_current_child\s*\|\|\s*prelogin_pml_focus_current_child\s*\(\s*manager,\s*focused_object\s*\)' `
    "Deferred current-child snapshots must be treated as current-child proof before any live manager re-check."
Assert-Contains $pmlFocusClaimGate 'if\s*\(\s*std::strcmp\s*\(\s*source_text\s*,\s*"direct-fields"\s*\)\s*==\s*0\s*\)[\s\S]{0,120}return\s+current_child\s*&&\s*prelogin_setup_form_value_cell_label' `
    "Direct-fields must not claim PML focus without current-child proof."
Assert-Contains $pmlFocusClaimGate 'if\s*\(\s*std::strcmp\s*\(\s*source_text\s*,\s*"selected-member-dynamic"\s*\)\s*==\s*0\s*\)[\s\S]{0,160}return\s+focused_flag\s*&&\s*prelogin_member_dynamic_label\s*\(\s*label\s*\)' `
    "Selected dynamic member names must be claimable only through native selected-index focus, not broad current-child speech."
Assert-Contains $labelFilter 'std::strcmp\s*\(\s*source_text,\s*"add-member"\s*\)\s*==\s*0[\s\S]{0,140}prelogin_add_member_value_label\s*\(\s*label\s*\)' `
    "Add Member values must be allowed only through the Add Member source-aware label path."
Assert-Contains $labelFilter 'std::strcmp\s*\(\s*source_text,\s*"member-dynamic"\s*\)\s*==\s*0[\s\S]{0,140}prelogin_member_dynamic_label\s*\(\s*label\s*\)' `
    "Dynamic member names must be allowed only through the member-dynamic source-aware label path."
Assert-Contains $labelFilter 'std::strcmp\s*\(\s*source_text,\s*"selected-member-dynamic"\s*\)\s*==\s*0[\s\S]{0,140}prelogin_member_dynamic_label\s*\(\s*label\s*\)' `
    "Selected dynamic member names must use a distinct source-aware label path."
Assert-Contains $pmlFocusClaimGate 'if\s*\(\s*!snapshot_current_child\s*&&[\s\S]{0,420}reason=different-current-child' `
    "Only non-deferred focus claims should re-read live manager +0x164; deferred snapshots already captured native current-child proof."
Assert-Before $pmlFocusClaimGate 'reason=different-current-child' 'if (current_child || focused_flag)' `
    "Non-snapshot PML focus claims must still reject a different real current child before focused-flag speech."
if ($pmlFocusClaimGate -match 'if\s*\(\s*interactive\s*\)\s*return\s+true') {
    throw "Interactive PML children must not claim speech without selected/current/focused proof."
}

$selectionRangeChange = Get-FunctionBody $source "void __stdcall record_selection_model_range_change"
Assert-Contains $selectionRangeChange 'record_native_selection_interval\s*\(\s*model\s*,\s*first\s*,\s*last\s*\)' `
    "Selection-model range changes must feed the native selection interval recorder."

$selectionRegister = Get-FunctionBody $source "void record_native_selection_register"
Assert-Contains $selectionRegister 'native_post_login_surface_active\s*\(\s*\)' `
    "Native selection registration must be gated away from post-login FFXI surfaces."
Assert-Contains $selectionRegister 'SELTRUTHREG' `
    "Native selection registration should keep its diagnostic marker."

$selectionInterval = Get-FunctionBody $source "void record_native_selection_interval"
Assert-Contains $selectionInterval 'native_post_login_surface_active\s*\(\s*\)' `
    "Native selection interval must be gated away from post-login FFXI surfaces."
Assert-Contains $selectionInterval 'SELTRUTHSET|SELTRUTHMISS' `
    "Native selection interval should keep useful success/miss diagnostics."

$selectionInstaller = Get-FunctionBody $source "void install_native_selection_truth_hooks_once"
Assert-Contains $selectionInstaller 'register_target\s*=\s*app_base\s*\+\s*0x00009E62u' `
    "Native selection truth installer must keep the current register hook target explicit."
Assert-Contains $source 'SelectedIndexSetterRva\s*=\s*0x001DD903u' `
    "Native pre-login selection speech must hook the Ghidra-backed selected-index setter at 049ED903."
Assert-Contains $source 'PmlIndexedChildAtRva\s*=\s*0x00102B3Bu' `
    "Native pre-login selection speech must use the Ghidra-backed indexed child lookup used by the setter pipeline."
Assert-Contains $source 'PmlCurrentChildSetterRva\s*=\s*0x000044F1u' `
    "Native pre-login focus speech must hook the Ghidra-backed current-child setter at 048144F1."
Assert-Contains $source 'PmlTextSetterRva\s*=\s*0x00064156u' `
    "Native pre-login member-name speech must document the crash-disabled wide text setter at 04874156."
Assert-Contains $source 'KnownUpdatedAppDllSize\s*=\s*4335104ull' `
    "Native pre-login hooks must document the validated updated PlayOnline app.dll size."
Assert-Contains $source 'KnownUpdatedAppDllFnv64\s*=\s*0x07E88E8067FEF6CCull' `
    "Native pre-login hooks must document the validated updated PlayOnline app.dll fingerprint."
Assert-Contains $source 'bool\s+app_module_matches_known_updated_pol_build\s*\(' `
    "Native pre-login hooks must refuse to patch unknown or pre-update PlayOnline app.dll builds."
Assert-Contains $source 'finish-playonline-update' `
    "Native pre-login app.dll mismatch diagnostics must tell users to finish the PlayOnline update, not block AccessXI installation."
Assert-Contains $source 'g_selected_index_setter_trampoline' `
    "Native pre-login selection speech must keep a trampoline for the selected-index setter hook."
Assert-Contains $source 'g_pml_current_child_setter_trampoline' `
    "Native pre-login focus speech must keep a trampoline for the current-child setter hook."
Assert-Contains $selectionInstaller 'selected_index_target\s*=\s*app_base\s*\+\s*SelectedIndexSetterRva' `
    "Native selection truth installer must install the selected-index setter hook from the named RVA."
Assert-Contains $selectionInstaller 'current_child_target\s*=\s*app_base\s*\+\s*PmlCurrentChildSetterRva' `
    "Native selection truth installer must install the current-child setter hook from the named RVA."
Assert-Contains $selectionInstaller 'app_module_matches_known_updated_pol_build\s*\(\s*app\s*,\s*"selection-truth"\s*\)' `
    "Native selection truth installer must verify the loaded app.dll build before patching hard-coded RVAs."
Assert-Contains $selectionInstaller 'install_inline_jump\s*\(\s*selected_index_target\s*,\s*reinterpret_cast<void\*>\s*\(&hook_selected_index_setter\)\s*,\s*7\s*,\s*&g_selected_index_setter_trampoline\s*\)' `
    "Selected-index setter hook must patch complete instructions at 049ED903 without reintroducing key monitoring."
Assert-Contains $selectionInstaller 'install_inline_jump\s*\(\s*current_child_target\s*,\s*reinterpret_cast<void\*>\s*\(&hook_pml_current_child_setter\)\s*,\s*7\s*,\s*&g_pml_current_child_setter_trampoline\s*\)' `
    "Current-child setter hook must patch complete instructions at 048144F1 without reintroducing key monitoring."
if ($selectionInstaller -match 'text_setter_target|hook_pml_text_setter|g_pml_text_setter_trampoline|install_inline_jump\s*\(\s*[^,]*text_setter_target') {
    throw "Native selection truth installer must not install the app.dll +0x64156 text-setter hook; live POL validation showed that hook crashes the viewer."
}
Assert-Contains $selectionInstaller 'PRELOGIN_SELECTEDINDEX hook-installed rva=001DD903' `
    "Selected-index hook installer must leave a stable live-log marker."
Assert-Contains $selectionInstaller 'PRELOGIN_CURRENTCHILD hook-installed rva=000044F1' `
    "Current-child hook installer must leave a stable live-log marker."
Assert-Contains $selectionInstaller 'PRELOGIN_TEXTSETTER hook-disabled rva=00064156 reason=crash-stability' `
    "Wide text setter installer must leave a stable live-log marker explaining why the Ghidra-backed hook is disabled."

$focusEventInstaller = Get-FunctionBody $source "void install_pml_focus_event_call_hook_once"
Assert-Contains $focusEventInstaller 'app_module_matches_known_updated_pol_build\s*\(\s*app\s*,\s*"focus-event"\s*\)' `
    "Native focus-event installer must verify the loaded app.dll build before patching hard-coded RVAs."

$selectedIndexHook = Get-FunctionBody $source "void __fastcall hook_selected_index_setter"
Assert-Contains $selectedIndexHook 'original\s*\(\s*self\s*,\s*index\s*\)' `
    "Selected-index hook must call the original native setter before reading the updated native selection state."
Assert-Contains $selectedIndexHook 'remember_selected_index_candidate\s*\(\s*self\s*,\s*index\s*\)' `
    "Selected-index hook must route post-setter native selection changes through the selected-index candidate path."
Assert-Before $selectedIndexHook 'original(self, index)' 'remember_selected_index_candidate(self, index)' `
    "Selected-index hook must observe the state after the native setter updates it."
if ($selectedIndexHook -match "GetAsyncKeyState") {
    throw "Selected-index hook must not monitor arrows, Tab, Enter, or any other keyboard state."
}

$selectedIndexResolver = Get-FunctionBody $source "void remember_selected_index_candidate"
Assert-Contains $selectedIndexResolver 'selected_child_from_native_index\s*\(\s*model\s*,\s*stored_index\s*\)' `
    "Selected-index candidate path must resolve the native child for the actual stored index."
Assert-Contains $selectedIndexResolver 'best_native_pml_text_from_object\s*\(\s*selected_child\s*,\s*"selected-index"\s*\)' `
    "Selected-index candidate path must extract labels from the selected native child, not from guessed menu order."
Assert-Contains $selectedIndexResolver 'prelogin_member_dynamic_value_rect\s*\(\s*selected_child\s*\)' `
    "Selected-index candidate path must recognize native dynamic member value rectangles."
Assert-Contains $selectedIndexResolver 'best_native_pml_dynamic_text_from_object\s*\(\s*selected_child\s*\)' `
    "Selected-index candidate path must extract dynamic member names from the selected native child."
Assert-Contains $selectedIndexResolver 'label_source\s*=\s*"selected-member-dynamic"' `
    "Selected-index dynamic member names must keep their narrow source through the speech gate."
Assert-Contains $selectedIndexResolver 'prelogin_pml_focus_can_claim_burst\s*\(\s*label_source' `
    "Selected-index candidate path must still pass the strict native source-aware label allowlist before speech."
Assert-Contains $selectedIndexResolver 'candidate\.source\s*=\s*label_source' `
    "Queued selected-index candidates must preserve the narrowed dynamic-member source."
Assert-Contains $selectedIndexResolver 'PRELOGIN_SELECTEDINDEX' `
    "Selected-index candidate path must keep live diagnostics for user validation."
Assert-Contains $source 'std::atomic<int>\s+g_selected_index_no_label_log_budget\{\s*24\s*\}' `
    "Selected-index no-label diagnostics must be capped so dynamic member probing cannot lag arrowing."
Assert-Contains $selectedIndexResolver 'g_selected_index_no_label_log_budget\.fetch_sub' `
    "Selected-index no-label logging must spend a finite diagnostic budget."
Assert-Contains $selectedIndexResolver 'read_prelogin_object_rect\s*\(\s*selected_child,\s*&selected_rect\s*\)' `
    "Selected-index no-label diagnostics must log the native selected-child rectangle for one-pass member-name discovery."
Assert-Contains $selectedIndexResolver 'rect=%d,%d,%d,%d' `
    "Selected-index no-label diagnostics must include native rectangle coordinates."
if ($selectedIndexResolver -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Selected-index candidate path must not infer selection from key presses."
}

$currentChildHook = Get-FunctionBody $source "void __fastcall hook_pml_current_child_setter"
Assert-Contains $currentChildHook 'original\s*\(\s*self\s*,\s*new_child\s*,\s*update_context\s*\)' `
    "Current-child hook must call the original native setter before reading manager +0x164."
Assert-Contains $currentChildHook 'remember_current_child_candidate\s*\(\s*self\s*,\s*new_child\s*\)' `
    "Current-child hook must route native current-child changes through the current-child candidate path."
Assert-Before $currentChildHook 'original(self, new_child, update_context)' 'remember_current_child_candidate(self, new_child)' `
    "Current-child hook must observe the state after the native setter updates manager +0x164."
if ($currentChildHook -match "GetAsyncKeyState") {
    throw "Current-child hook must not monitor arrows, Tab, Enter, or any other keyboard state."
}

$currentChildRecorder = Get-FunctionBody $source "void remember_current_child_candidate"
Assert-Contains $source 'struct\s+PreloginCurrentChildSnapshot' `
    "Current-child focus changes must be snapshotted so the UI-thread hook can return before native label extraction."
Assert-Contains $source 'std::mutex\s+g_current_child_lock' `
    "Current-child snapshots must be protected separately from PML speech candidates."
Assert-Contains $source 'bool\s+g_pending_current_child_snapshot_valid\s*=\s*false' `
    "Current-child snapshots must have a pending flag drained by the worker thread."
Assert-Contains $currentChildRecorder 'read_ptr_safely\s*\(\s*static_cast<const uint8_t\*>\s*\(\s*manager\s*\)\s*\+\s*0x164\s*,\s*&current_child\s*\)' `
    "Current-child candidate path must read the real manager +0x164 current child."
Assert-Contains $currentChildRecorder 'g_pending_current_child_snapshot\s*=\s*snapshot' `
    "Current-child hook path must only record the latest native focus snapshot."
Assert-Contains $currentChildRecorder 'g_pending_current_child_snapshot_valid\s*=\s*true' `
    "Current-child hook path must leave heavy processing for the worker."
if ($currentChildRecorder -match 'native_prelogin_add_member_inner_textbox_child[\s\S]{0,160}return') {
    throw "Current-child hook path must not discard focused Add Member textbox children before worker-side native geometry can classify them."
}
if ($currentChildRecorder -match 'native_prelogin_atlas_label_from_geometry|best_native_pml_text_from_object_tree|native_prelogin_add_member_form_context|log_current_child_detail|speak_pending_prelogin_pml_focus_candidate|speak_prelogin_label|append_reloaded_speech_queue') {
    throw "Current-child hook path must not perform native label extraction, form-tree scans, logging, or speech on POL's UI thread."
}

$currentChildResolver = Get-FunctionBody $source "void process_current_child_candidate"
Assert-Contains $source 'uintptr_t\s+g_last_processed_prelogin_current_child\s*=\s*0' `
    "Current-child handling must remember the last processed native child so wrapper duplicate events do not rescan the same field."
Assert-Contains $source 'DWORD\s+g_last_processed_prelogin_current_child_tick\s*=\s*0' `
    "Current-child duplicate suppression must be time-bounded by native focus event timing."
Assert-Contains $currentChildResolver 'current_child\s*==\s*g_last_processed_prelogin_current_child[\s\S]{0,260}now\s*-\s*g_last_processed_prelogin_current_child_tick\)\s*<=\s*150[\s\S]{0,80}return' `
    "Current-child handling must skip same-native-child wrapper duplicates before expensive Add Member scans."
Assert-Before $currentChildResolver 'current_child == g_last_processed_prelogin_current_child' 'native_prelogin_atlas_label_from_geometry(current_child_object, &atlas_resource)' `
    "Current-child duplicate suppression must run before geometry and object-tree extraction."
Assert-Contains $currentChildResolver 'const\s+bool\s+current_child_is_tiny\s*=\s*native_prelogin_add_member_inner_textbox_child\s*\(\s*current_child_object\s*\)' `
    "Current-child handling must remember tiny Add Member children so value spam stays blocked while native Register button text can still be inspected."
if ($currentChildResolver -match 'if\s*\(\s*native_prelogin_add_member_inner_textbox_child\s*\(\s*current_child_object\s*\)\s*\)[\s\S]{0,80}return') {
    throw "Tiny Add Member children must not be blanket-suppressed before native Register button text can be inspected."
}
Assert-Contains $currentChildResolver 'best_native_pml_text_from_object_tree\s*\(\s*current_child_object\s*,\s*"current-child"\s*,\s*&label_source_offset\s*\)' `
    "Current-child candidate path must extract labels from the real native current child or its bounded native children."
Assert-Contains $currentChildResolver 'native_prelogin_atlas_label_from_geometry\s*\(\s*current_child_object\s*,\s*&atlas_resource\s*\)' `
    "Current-child candidate path may only use the native atlas geometry bridge after manager +0x164 identifies the current child."
Assert-Contains $currentChildResolver 'if\s*\(\s*!geometry_label\.empty\s*\(\s*\)\s*&&\s*!add_member_value_focus\s*&&\s*!add_member_button_focus\s*&&\s*!member_dynamic_focus\s*&&\s*!startup_member_atlas_focus\s*\)' `
    "Exact focused geometry must keep the atlas-geometry source even when object text matches, except for proven Add Member values, buttons, or dynamic member values."
Assert-Contains $currentChildResolver 'if\s*\(\s*!label\.empty\s*\(\s*\)\s*&&\s*label\s*!=\s*geometry_label\s*\)' `
    "Focused geometry conflict logging should remain limited to real object-text disagreements."
Assert-Contains $currentChildResolver 'PRELOGIN_ATLASGEOM prefer-focused-geometry' `
    "Geometry/object-text conflicts must leave a stable diagnostic marker."
Assert-Contains $currentChildResolver 'prelogin_pml_focus_can_claim_burst\s*\(\s*candidate_source' `
    "Current-child candidate path must still pass the strict native focus gate before speech using the narrowed source."
Assert-Contains $currentChildResolver 'prelogin_pml_focus_can_claim_burst\s*\(\s*candidate_source,\s*manager,\s*current_child_object,\s*label,\s*true,\s*true\s*\)' `
    "Deferred current-child candidates must pass snapshot proof to the focus gate instead of re-reading stale manager state."
Assert-Before $currentChildResolver 'native_prelogin_atlas_label_from_geometry(current_child_object, &atlas_resource)' 'prelogin_pml_focus_can_claim_burst(candidate_source' `
    "Native atlas geometry must still pass the strict current-child focus gate before speech."
Assert-Contains $currentChildResolver 'sourceOffset=%03X' `
    "Current-child diagnostics must log the native pointer offset that provided the label."
Assert-Contains $currentChildResolver 'log_current_child_detail\s*\(\s*manager,\s*requested_child,\s*current_child_object,\s*"no-label"\s*\)' `
    "Current-child failures must keep a bounded diagnostic path for native object-layout discovery."
Assert-Contains $currentChildResolver 'PRELOGIN_CURRENTCHILD' `
    "Current-child candidate path must keep live diagnostics for user validation."
if ($currentChildResolver -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Current-child candidate path must not infer selection from key presses."
}

$atlasGeometryResolver = Get-FunctionBody $source "std::string native_prelogin_atlas_label_from_geometry"
Assert-Contains $atlasGeometryResolver 'read_prelogin_object_rect\s*\(\s*object,\s*&rect\s*\)' `
    "Native atlas geometry bridge must use the runtime current-child rectangle, not guessed menu order."
Assert-Contains $atlasGeometryResolver 'rect_matches_exactly_or_nearly\s*\(\s*rect,\s*entry\s*\)' `
    "Native atlas geometry bridge must require exact-or-near exact geometry proof."
Assert-Contains $atlasGeometryResolver 'PRELOGIN_ATLASGEOM ambiguous' `
    "Native atlas geometry bridge must stay silent when the same rectangle maps to different labels."
Assert-Contains $atlasGeometryResolver 'return\s+\{\}' `
    "Native atlas geometry bridge must have silent failure paths."
Assert-Contains $atlasGeometryResolver '\{\s*278,\s*54,\s*465,\s*78,\s*"Connection check",\s*0x04B59AE8u\s*\}' `
    "Network Settings value-cell focus at 278,54,465,78 must speak the native Connection check row label."
Assert-Contains $atlasGeometryResolver '\{\s*278,\s*114,\s*465,\s*138,\s*"Proxy server",\s*0x04B59B88u\s*\}' `
    "Network Settings value-cell focus at 278,114,465,138 must speak the native Proxy server row label."
Assert-Contains $atlasGeometryResolver '\{\s*164,\s*152,\s*268,\s*176,\s*"Yes",\s*0x00000000u\s*\}' `
    "Confirmation Yes must have exact focused geometry proof so sibling No text cannot claim it."
Assert-Contains $atlasGeometryResolver '\{\s*268,\s*152,\s*372,\s*176,\s*"No",\s*0x00000000u\s*\}' `
    "Confirmation No must have exact focused geometry proof alongside Yes."
Assert-Contains $atlasGeometryResolver 'native_prelogin_add_member_label_from_geometry\s*\(\s*object,\s*rect,\s*resource\s*\)' `
    "Add Member login fields must use a context-checked geometry helper, not the global coordinate table."
if ($atlasGeometryResolver -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Native atlas geometry bridge must not infer selection from key presses."
}

$addMemberContext = Get-FunctionBody $source "bool native_prelogin_add_member_form_context"
$addMemberContextUncached = Get-FunctionBody $source "bool native_prelogin_add_member_form_context_uncached"
Assert-Contains $source 'bool\s+native_prelogin_form_root_has_rect\s*\(' `
    "Add Member field context must have a bounded native form-root geometry proof helper."
Assert-Contains (Get-FunctionBody $source "bool native_prelogin_form_root_has_rect") 'read_prelogin_object_rect\s*\(' `
    "Add Member form-root proof must inspect native object rectangles, not guessed row order."
Assert-Contains (Get-FunctionBody $source "bool native_prelogin_form_root_has_rect") 'offset\s*<=\s*0x340' `
    "Add Member form-root proof must keep the native child pointer walk bounded."
Assert-Contains $source 'bool\s+native_prelogin_add_member_form_root_has_required_rects\s*\(' `
    "Add Member field context must prove the Add Member screen by its native focused-field rectangle constellation."
Assert-Contains (Get-FunctionBody $source "bool native_prelogin_add_member_form_root_has_required_rects") 'bottom_hits\s*>=\s*2' `
    "Add Member form-root proof must require bottom-screen fields so login/password screens cannot claim it."
Assert-Contains $addMemberContextUncached 'native_prelogin_add_member_form_root_has_required_rects\s*\(' `
    "Add Member field context must use native screen-shape proof rather than broad text timing."
Assert-Contains $source 'struct\s+AddMemberContextCacheEntry' `
    "Add Member form-context checks must use a tiny native-state cache so focus bursts do not rescan the form tree several times per arrow."
Assert-Contains $source 'constexpr\s+DWORD\s+AddMemberContextCacheTtlMs\s*=\s*60000' `
    "Add Member form-context cache must survive normal arrowing through the members form, not only a sub-second wrapper burst."
Assert-Contains $source 'bool\s+native_prelogin_add_member_form_context_uncached\s*\(' `
    "The expensive Add Member form-context proof must stay isolated behind a cacheable uncached helper."
Assert-Contains $addMemberContext 'g_add_member_context_cache' `
    "Add Member form-context checks must consult the cache before walking parent links and child rectangles."
Assert-Contains $addMemberContext 'now\s*-\s*entry\.tick\)\s*<=\s*AddMemberContextCacheTtlMs' `
    "Add Member form-context checks must use the longer cache window so revisiting fields does not rescan native parent trees."
Assert-Contains $addMemberContext 'native_prelogin_add_member_form_context_uncached\s*\(\s*object\s*\)' `
    "Add Member form-context checks must populate the cache from the original native proof, not guessed labels."
if ($addMemberContext -match '"Add Member"') {
    throw "Add Member field context must not depend on the literal Add Member label; live focused field parents do not expose it reliably."
}
Assert-Contains $addMemberContextUncached '0x154|0x158' `
    "Add Member field context must inspect native parent links from the focused control."
Assert-Contains $addMemberContextUncached 'depth\s*<\s*6' `
    "Add Member field context must walk enough native parent hops to classify inner text-box descendants."
if (($addMemberContext + $addMemberContextUncached) -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Add Member field context must not infer selection from key presses."
}

$addMemberGeometry = Get-FunctionBody $source "std::string native_prelogin_add_member_label_from_geometry"
Assert-Contains $addMemberGeometry 'native_prelogin_add_member_form_context\s*\(\s*object\s*\)' `
    "Add Member field geometry must stay silent unless the focused control belongs to the Add Member form."
Assert-Contains $addMemberGeometry '\{\s*29,\s*69,\s*61,\s*101,\s*"Member Name",\s*0x04B59408u\s*\}' `
    "Focused Add Member edit-control rectangle 29,69,61,101 must map to native Member Name; live logs showed this current-child rect was previously silent."
Assert-Contains $addMemberGeometry '\{\s*315,\s*71,\s*461,\s*103,\s*"Member Name",\s*0x04B59408u\s*\}' `
    "Focused Add Member rectangle 315,71,461,103 must map to native Member Name."
Assert-Contains $addMemberGeometry '\{\s*315,\s*99,\s*461,\s*131,\s*"PlayOnline ID",\s*0x04B59548u\s*\}' `
    "Focused Add Member rectangle 315,99,461,131 must map to native PlayOnline ID."
Assert-Contains $addMemberGeometry '\{\s*311,\s*131,\s*495,\s*155,\s*"Set Password",\s*0x04B59598u\s*\}' `
    "Focused Add Member rectangle 311,131,495,155 must map to native Set Password."
Assert-Contains $addMemberGeometry '\{\s*315,\s*209,\s*461,\s*241,\s*"Member Password",\s*0x04B59318u\s*\}' `
    "Focused Add Member rectangle 315,209,461,241 must map to native Member Password."
Assert-Contains $addMemberGeometry '\{\s*315,\s*237,\s*461,\s*269,\s*"Confirm Password",\s*0x00000000u\s*\}' `
    "Focused Add Member rectangle 315,237,461,269 must map to native Confirm Password."
Assert-Contains $addMemberGeometry '\{\s*315,\s*291,\s*461,\s*323,\s*"Square Enix ID",\s*0x04B595E8u\s*\}' `
    "Focused Add Member rectangle 315,291,461,323 must map to native Square Enix ID."
Assert-Contains $addMemberGeometry '\{\s*424,\s*305,\s*534,\s*329,\s*"What is a Square Enix ID",\s*0x00000000u\s*\}' `
    "Focused Add Member right-side rectangle 424,305,534,329 must map to the native What is a Square Enix ID control."
Assert-Contains $addMemberGeometry '\{\s*311,\s*323,\s*495,\s*347,\s*"One-Time Password",\s*0x04B59638u\s*\}' `
    "Focused Add Member rectangle 311,323,495,347 must map to native One-Time Password."
if ($addMemberGeometry -match 'Please enter your Square Enix ID|Enter your name and PlayOnline ID|Set password for extra security') {
    throw "Add Member focused-field geometry must not speak explanatory body/help text."
}
if ($addMemberGeometry -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Add Member field geometry must not infer selection from key presses."
}

$currentChildDetail = Get-FunctionBody $source "void log_current_child_detail"
Assert-Contains $currentChildDetail 'g_current_child_detail_budget\.fetch_sub' `
    "Current-child diagnostics must be capped so probing does not create live POL lag."
Assert-Contains $currentChildDetail 'PRELOGIN_CURRENTCHILDDETAIL' `
    "Current-child diagnostics must leave a stable marker for live log validation."
if ($currentChildDetail -match "append_reloaded_speech_queue|speak_prelogin_label|GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Current-child diagnostics must be logging-only and must not monitor keys."
}
Assert-Contains $source 'std::atomic<int>\s+g_current_child_no_label_budget\{\s*2\s*\}' `
    "Current-child no-label diagnostics must be capped separately so Add Member probing cannot lag arrowing."
Assert-Contains $currentChildResolver 'g_current_child_no_label_budget\.fetch_sub' `
    "Current-child no-label logging must spend its own finite diagnostic budget."
Assert-Contains $source 'std::atomic<int>\s+g_current_child_rejected_log_budget\{\s*6\s*\}' `
    "Current-child rejected diagnostics must be capped so repeated Add Member child suppression does not lag arrowing."
Assert-Contains $currentChildResolver 'g_current_child_rejected_log_budget\.fetch_sub' `
    "Current-child rejected logging must spend a finite diagnostic budget."
Assert-Contains $source 'std::atomic<int>\s+g_startup_member_probe_budget\{\s*6\s*\}' `
    "Startup member-name probing must be capped so the POL startup menu does not lag while gathering native layout evidence."
Assert-Contains $source 'void\s+log_startup_member_probe\s*\(' `
    "Startup member-name probing must be isolated in a logging-only helper."
$startupMemberProbe = Get-FunctionBody $source "void log_startup_member_probe"
Assert-Contains $startupMemberProbe 'g_startup_member_probe_budget\.fetch_sub' `
    "Startup member-name probe must spend a finite diagnostic budget."
Assert-Contains $startupMemberProbe 'PRELOGIN_STARTUPMEMBER_PROBE' `
    "Startup member-name probe must leave a stable log marker for the next user arrow pass."
Assert-Contains $startupMemberProbe 'log_member_source\s*\(\s*"accessor"' `
    "Startup member-name probe must log the raw native member-name accessor result for root-cause evidence."
Assert-Contains $startupMemberProbe 'log_member_source\s*\(\s*"global"' `
    "Startup member-name probe must log the raw native member-name global fallback for root-cause evidence."
Assert-Contains $startupMemberProbe 'log_startup_member_model_probe\s*\(\s*reinterpret_cast<void\*>\s*\(\s*current\s*\)\s*\)' `
    "Startup member-name probe must include RegularMember model-field evidence in the same native focus-proofed pass."
Assert-Contains $startupMemberProbe 'read_prelogin_object_rect\s*\(' `
    "Startup member-name probe must record native object rectangles rather than guessed row order."
Assert-Contains $startupMemberProbe 'read_native_pml_string_field' `
    "Startup member-name probe must inspect direct native string fields."
Assert-Contains $startupMemberProbe 'read_native_pml_wide_string_field' `
    "Startup member-name probe must inspect direct native wide-string fields."
Assert-Contains $startupMemberProbe 'read_native_pml_c_string_pointer' `
    "Startup member-name probe must inspect pointer-backed native string fields."
Assert-Contains $startupMemberProbe 'read_native_pml_wide_string_pointer' `
    "Startup member-name probe must inspect pointer-backed native wide-string fields."
Assert-Contains $startupMemberProbe 'child_text_budget' `
    "Startup member-name probe must reserve a child text budget so noisy parent widgets cannot starve the candidate child object."
Assert-Contains $currentChildResolver 'startup_member_focus_rect[\s\S]{0,260}log_startup_member_probe\s*\(\s*manager,\s*current_child_object\s*\)' `
    "Startup member-name probe must run only after native startup member-list focus proof."
if ($startupMemberProbe -match "append_reloaded_speech_queue|speak_prelogin_label|GetAsyncKeyState|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT|VK_RETURN|VK_TAB") {
    throw "Startup member-name probe must be logging-only and must not monitor keys or speak."
}

if ($source -match 'hook_pml_text_setter|remember_pml_text_setter_label|native_prelogin_startup_member_name_from_text_cache|g_pml_text_setter_trampoline') {
    throw "Crash-disabled text-setter cache/hook code must not remain wired into the POL pre-login speech path."
}
Assert-Contains $source 'bool\s+native_prelogin_add_member_current_child_speech_allowed\s*\(' `
    "Add Member current-child speech must have a dedicated guard so inner text-box children cannot spam stale labels."
$addMemberCurrentChildGuard = Get-FunctionBody $source "bool native_prelogin_add_member_current_child_speech_allowed"
Assert-Contains $addMemberCurrentChildGuard 'std::strcmp\s*\(\s*label_source\s*,\s*"atlas-geometry"\s*\)\s*==\s*0' `
    "Add Member current-child guard must keep exact focused-field geometry speech."
Assert-Contains $addMemberCurrentChildGuard 'native_prelogin_add_member_form_root_has_required_rects\s*\(\s*manager\s*\)' `
    "Add Member current-child guard must distinguish the real form root from nested field children."
Assert-Contains $addMemberCurrentChildGuard 'label\s*==\s*"Add Member"[\s\S]{0,120}return\s+false' `
    "Add Member current-child guard must keep the form title from speaking as a focused field."
Assert-Contains $addMemberCurrentChildGuard 'native_prelogin_add_member_form_context\s*\(\s*manager\s*\)' `
    "Add Member current-child guard must recognize nested field managers by native form context."
Assert-Contains $addMemberCurrentChildGuard 'native_prelogin_add_member_form_context\s*\(\s*current_child_object\s*\)' `
    "Add Member current-child guard must recognize nested focused children by native form context."
Assert-Contains $source 'bool\s+native_prelogin_add_member_button_object_tree_label\s*\(' `
    "Add Member object-tree speech must be restricted to native button-shaped controls."
Assert-Contains $source 'bool\s+prelogin_add_member_button_label\s*\(' `
    "Add Member Register/Cancel labels must have a dedicated native button-label helper."
Assert-Contains $source 'bool\s+native_prelogin_add_member_inner_textbox_child\s*\(' `
    "Add Member value-label speech must reject tiny inner text-box children that expose stale labels."
Assert-Contains $source 'bool\s+prelogin_add_member_field_geometry_label\s*\(' `
    "Add Member field labels must be recognized separately from value labels so exact field geometry can beat stale object-tree text."
$addMemberFieldGeometryLabel = Get-FunctionBody $source "bool prelogin_add_member_field_geometry_label"
Assert-Contains $addMemberFieldGeometryLabel '"PlayOnline ID"' `
    "Add Member field-geometry labels must include PlayOnline ID; logs showed its exact field rectangle was displaced by stale Confirm Password text."
Assert-Contains $addMemberFieldGeometryLabel '"Member Password"' `
    "Add Member field-geometry labels must include Member Password; visible focused fields must not be skipped by stale value text."
Assert-Contains $addMemberFieldGeometryLabel '"What is a Square Enix ID"' `
    "Add Member field-geometry labels must include the right-side What is a Square Enix ID control so stale Register object text cannot claim it."
$addMemberButtonLabel = Get-FunctionBody $source "bool prelogin_add_member_button_label"
Assert-Contains $addMemberButtonLabel '"Register"' `
    "Add Member button labels must include native Register."
Assert-Contains $addMemberButtonLabel '"Cancel"' `
    "Add Member button labels must include native Cancel."
$addMemberButtonGuard = Get-FunctionBody $source "bool native_prelogin_add_member_button_object_tree_label"
Assert-Contains $addMemberButtonGuard 'read_prelogin_object_rect\s*\(\s*object,\s*&rect\s*\)' `
    "Add Member button object-tree speech must be backed by the focused object's native rectangle."
Assert-Contains $addMemberButtonGuard 'label\s*==\s*"Register"' `
    "Add Member button guard must allow Register only by native button geometry."
Assert-Contains $addMemberButtonGuard 'label\s*==\s*"Cancel"' `
    "Add Member button guard must allow Cancel only by native button geometry."
Assert-Contains $addMemberButtonGuard 'rect\.top\s*>=\s*360' `
    "Add Member button guard must still require native button-shaped geometry for normal object-tree button speech."
Assert-Contains $addMemberCurrentChildGuard 'return\s+native_prelogin_add_member_button_object_tree_label\s*\(\s*current_child_object,\s*label\s*\)' `
    "Add Member non-geometry object-tree speech must be limited to proven button controls."
Assert-Contains $addMemberCurrentChildGuard 'std::strcmp\s*\(\s*label_source\s*,\s*"add-member"\s*\)\s*==\s*0[\s\S]{0,180}prelogin_add_member_value_label\s*\(\s*label\s*\)' `
    "Add Member value labels must use the dedicated Add Member source instead of broad object-tree speech."
Assert-Contains $addMemberCurrentChildGuard '!current_child_is_tiny' `
    "Add Member value labels must stay silent on tiny inner text-box children that previously leaked stale labels."
Assert-Contains $currentChildResolver 'native_prelogin_add_member_current_child_speech_allowed\s*\(\s*manager,\s*current_child_object,\s*label_source,\s*label,\s*current_child_is_tiny\s*\)' `
    "Current-child resolver must apply the Add Member inner-child spam guard before queueing speech."
Assert-Contains $currentChildResolver 'best_native_pml_text_from_object_tree\s*\(\s*current_child_object,\s*"add-member"' `
    "Current-child resolver must use the Add Member-only native value-label path for controls outside exact geometry."
Assert-Contains $currentChildResolver 'prelogin_add_member_value_label\s*\(\s*label\s*\)' `
    "Current-child resolver must retag native Add Member value labels before the Add Member speech guard."
Assert-Contains $currentChildResolver 'const\s+bool\s+add_member_field_geometry_focus\s*=\s*add_member_context\s*&&[\s\S]{0,160}!geometry_label\.empty\s*\(\s*\)\s*&&[\s\S]{0,160}prelogin_add_member_field_geometry_label\s*\(\s*geometry_label\s*\)' `
    "Exact Add Member field geometry must override stale object-tree/value labels before value-label preservation."
Assert-Contains $currentChildResolver 'label\s*=\s*geometry_label[\s\S]{0,120}label_source\s*=\s*"atlas-geometry"' `
    "Exact Add Member field geometry must speak the focused native field label."
Assert-Before $currentChildResolver 'prelogin_add_member_field_geometry_label(geometry_label)' 'bool add_member_value_candidate' `
    "Add Member field geometry must be resolved before stale value-label classification can claim the focus."
Assert-Contains $currentChildResolver '(?:const\s+)?bool\s+add_member_value_candidate\s*=\s*add_member_context\s*&&\s*prelogin_add_member_value_label\s*\(\s*label\s*\)' `
    "Current-child resolver must still identify Add Member value labels when exact field geometry did not already claim the focus."
Assert-Contains $currentChildResolver '(?:const\s+)?bool\s+add_member_value_focus\s*=\s*add_member_value_candidate\s*&&\s*!current_child_is_tiny' `
    "Current-child resolver must only preserve Add Member value labels from proven non-textbox focused controls."
Assert-Contains $currentChildResolver 'add_member_value_candidate\s*=\s*add_member_context\s*&&\s*prelogin_add_member_value_label\s*\(\s*label\s*\)' `
    "Current-child resolver must refresh Add Member value classification after the Add Member-only native scan."
Assert-Contains $currentChildResolver 'add_member_value_focus\s*=\s*add_member_value_candidate\s*&&\s*!current_child_is_tiny' `
    "Current-child resolver must refresh Add Member value focus proof after the Add Member-only native scan."
Assert-Contains $currentChildResolver 'add_member_button_focus' `
    "Current-child resolver must preserve native Add Member button labels separately from value labels."
Assert-Contains $currentChildResolver 'label_source_offset\s*==\s*0x114' `
    "Tiny native Register text children must require the observed native text offset before speaking, so stale field children stay silent."
Assert-Contains $currentChildResolver 'label_source\s*=\s*"add-member-button"' `
    "Native Add Member Register/Cancel button labels must keep a narrowed source through the speech guard."
Assert-Contains $currentChildResolver 'if\s*\(\s*!geometry_label\.empty\s*\(\s*\)\s*&&\s*!add_member_value_focus\s*&&\s*!add_member_button_focus\s*&&\s*!member_dynamic_focus\s*&&\s*!startup_member_atlas_focus\s*\)' `
    "Non-field focused geometry may still override object text when no proven Add Member value or dynamic member value has claimed the focus."
Assert-Contains $currentChildResolver 'std::strcmp\s*\(\s*label_source,\s*"add-member"\s*\)\s*==\s*0[\s\S]{0,180}std::strcmp\s*\(\s*label_source,\s*"add-member-button"\s*\)\s*==\s*0[\s\S]{0,180}std::strcmp\s*\(\s*label_source,\s*"member-dynamic"\s*\)\s*==\s*0[\s\S]{0,120}\?\s*label_source\s*:\s*"current-child"' `
    "Add Member and dynamic member labels must keep their narrowed source through the final native focus claim."
Assert-Contains $currentChildResolver 'candidate\.source\s*=\s*candidate_source' `
    "Queued current-child candidates must use the narrowed Add Member source when the label came from that path."
Assert-Contains $currentChildResolver 'candidate\.snapshot_current_child\s*=\s*true' `
    "Queued deferred current-child candidates must carry snapshot current-child proof through the pending drain."
Assert-Before $currentChildResolver 'const bool add_member_field_geometry_focus' 'bool add_member_value_candidate' `
    "Exact Add Member field geometry must run before value-label preservation."
Assert-Before $currentChildResolver 'native_prelogin_add_member_current_child_speech_allowed(manager, current_child_object, label_source, label, current_child_is_tiny)' 'prelogin_pml_focus_can_claim_burst(candidate_source' `
    "Add Member inner-child guard must run before the broad current-child burst claim."
Assert-Contains $source 'bool\s+process_queued_current_child_candidate\s*\(' `
    "Reloaded worker must drain deferred current-child snapshots outside POL's focus setter."
$queuedCurrentChild = Get-FunctionBody $source "bool process_queued_current_child_candidate"
Assert-Contains $queuedCurrentChild 'g_pending_current_child_snapshot_valid\s*=\s*false' `
    "Deferred current-child processing must consume the latest snapshot exactly once."
Assert-Contains $queuedCurrentChild 'process_current_child_candidate\s*\(\s*snapshot,\s*reason\s*\)' `
    "Deferred current-child processing must route through the same strict native focus resolver."
$reloadedWorker = Get-FunctionBody $source "void run_reloaded_native_hook_iteration"
Assert-Before $reloadedWorker 'process_queued_current_child_candidate("reloaded-native-current-child")' 'speak_pending_prelogin_pml_focus_candidate("reloaded-native-focus")' `
    "Reloaded worker must resolve deferred current-child snapshots before draining speech candidates."
if ($addMemberCurrentChildGuard -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT|append_reloaded_speech_queue|speak_prelogin_label") {
    throw "Add Member current-child spam guard must be native-state filtering only, with no key monitoring or speech side effects."
}
if ($addMemberButtonGuard -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT|append_reloaded_speech_queue|speak_prelogin_label") {
    throw "Add Member button object-tree guard must be native-state filtering only, with no key monitoring or speech side effects."
}
Assert-Contains $source 'std::atomic<int>\s+g_current_child_candidate_log_budget\{\s*10\s*\}' `
    "Current-child candidate diagnostics must be capped so live arrowing is not slowed by probe logging."
Assert-Contains $currentChildResolver 'g_current_child_candidate_log_budget\.fetch_sub' `
    "Current-child candidate logging must spend a finite diagnostic budget."
Assert-Contains $source 'std::atomic<int>\s+g_pml_coalesced_log_budget\{\s*10\s*\}' `
    "PML coalesced-speak diagnostics must be capped so duplicate focus events do not lag arrowing."
Assert-Contains $pendingPmlFocusDrain 'g_pml_coalesced_log_budget\.fetch_sub' `
    "PML coalesced-speak logging must spend a finite diagnostic budget."
Assert-Contains $source 'std::atomic<int>\s+g_atlas_geometry_conflict_log_budget\{\s*10\s*\}' `
    "Atlas geometry conflict diagnostics must be capped because focus geometry can fire repeatedly per arrow."
Assert-Contains $currentChildResolver 'g_atlas_geometry_conflict_log_budget\.fetch_sub' `
    "Atlas geometry conflict logging must spend a finite diagnostic budget."

$speechQueue = Get-FunctionBody $source "void speak_prelogin_label"
Assert-Contains $source 'DWORD\s+g_last_spoken_prelogin_tick\s*=\s*0' `
    "Pre-login speech de-dup must track a tiny time window for wrapper/child focus duplicates."
if ($source -match 'prelogin_cross_object_duplicate_cooldown_ms') {
    throw "Pre-login speech must not use cross-object same-label cooldowns; live testing showed that masks real focus changes and skips options."
}
Assert-Contains $speechQueue 'GetTickCount\s*\(\s*\)' `
    "Pre-login speech de-dup must timestamp speech attempts without inspecting keyboard state."
Assert-Contains $speechQueue 'label\s*==\s*g_last_spoken_prelogin_label[\s\S]{0,260}focused_object\s*==\s*g_last_spoken_prelogin_object' `
    "Pre-login speech de-dup must keep suppressing the same label from the same native object."
Assert-Contains $speechQueue 'now\s*-\s*g_last_spoken_prelogin_tick\)\s*<=\s*100' `
    "Pre-login speech de-dup must only suppress same-label wrapper/child duplicates inside a tiny native focus burst."
if ($speechQueue -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Pre-login speech de-dup must not infer movement from keys."
}

$treeResolver = Get-FunctionBody $source "std::string best_native_pml_text_from_object_tree"
$objectTextResolver = Get-FunctionBody $source "std::string best_native_pml_text_from_object"
$nativeCandidateStruct = Get-FunctionBody $source "struct PreloginNativeTextCandidate"
Assert-Contains $nativeCandidateStruct 'source_rank' `
    "Native text candidates must retain whether a label came from the focused object's direct string field or a lower-confidence pointer."
Assert-Contains $nativeCandidateStruct 'offset' `
    "Native text candidates must retain the native field offset so confidence is not lost before sorting."
Assert-Contains $source 'bool\s+prelogin_ambiguous_command_cluster\s*\(' `
    "Native object text extraction must reject same-confidence ambiguous command clusters instead of choosing the shortest label."
$ambiguousCommandCluster = Get-FunctionBody $source "bool prelogin_ambiguous_command_cluster"
if ($ambiguousCommandCluster -match '"Log In"[\s\S]{0,160}"Settings"[\s\S]{0,160}"Delete"[\s\S]{0,160}"Back"') {
    throw "Member command clusters must not silence Log In, Settings, Delete, and Back; RegularMember_LoginCommandMenu_W is handled by native atlas geometry."
}
Assert-Contains $ambiguousCommandCluster '"Settings"[\s\S]{0,160}"Connect"[\s\S]{0,120}"Cancel"' `
    "Password command clusters must still be recognized when same-confidence labels conflict."
Assert-Contains $ambiguousCommandCluster 'source_rank\s*!=\s*best_source_rank' `
    "Command-cluster ambiguity must ignore lower-confidence sibling/body labels so focused Connect is not silenced by stale Cancel text."
Assert-Contains $ambiguousCommandCluster '>\s*1' `
    "Ambiguous command cluster detection must require more than one cluster label before rejecting speech."
if ($ambiguousCommandCluster -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT|append_reloaded_speech_queue|speak_prelogin_label") {
    throw "Ambiguous command cluster detection must be native text-set filtering only, with no key monitoring or speech side effects."
}
Assert-Contains $objectTextResolver 'std::vector<PreloginNativeTextCandidate>\s+candidates' `
    "Native object text extraction must keep candidate source confidence instead of collapsing labels into plain strings."
Assert-Contains $objectTextResolver 'best_source_rank' `
    "Native object text extraction must compute the best native source rank before checking command ambiguity."
Assert-Contains $objectTextResolver 'prelogin_ambiguous_command_cluster\s*\(\s*candidates\s*,\s*best_source_rank\s*\)' `
    "Native object text extraction must detect only same-confidence command-cluster ambiguity before sorting candidates."
Assert-Before $objectTextResolver 'prelogin_ambiguous_command_cluster(candidates, best_source_rank)' 'std::sort(candidates.begin(), candidates.end()' `
    "Same-confidence ambiguous command clusters must be rejected before sorting can choose Back or Cancel."
if ($objectTextResolver -match 'std::vector<std::string>\s+candidates') {
    throw "Native object text extraction must not collapse labels into a plain string set before confidence-based selection."
}
if ($objectTextResolver -match 'left\.size\s*\(\s*\)\s*!=\s*right\.size\s*\(\s*\)[\s\S]{0,100}left\.size\s*\(\s*\)\s*<\s*right\.size\s*\(\s*\)') {
    throw "Native object text extraction must not choose command labels by shortest text; that made Cancel/Back win over focused controls."
}
Assert-Contains $treeResolver 'bool\s+direct_ambiguous\s*=\s*false' `
    "Bounded native child resolver must track whether the focused object itself exposed an ambiguous command cluster."
Assert-Contains $treeResolver 'best_native_pml_text_from_object\s*\(\s*object\s*,\s*source_text\s*,\s*&direct_ambiguous\s*\)' `
    "Bounded native child resolver must ask the focused object extractor for ambiguity proof."
Assert-Contains $treeResolver 'if\s*\(\s*direct_ambiguous\s*\)[\s\S]{0,80}return\s+\{\}' `
    "If the focused object itself exposes multiple command labels, the tree resolver must stay silent instead of walking to a sibling label."
Assert-Contains $treeResolver 'offset\s*<=\s*0x220' `
    "Bounded native child resolver must keep the pointer walk narrow to avoid broad fallback speech."
Assert-Contains $treeResolver 'read_ptr_safely\s*\(\s*reinterpret_cast<const void\*>\s*\(\s*base\s*\+\s*offset\s*\)\s*,\s*&child\s*\)' `
    "Bounded native child resolver must walk real native pointer fields from the focused object."
Assert-Contains $treeResolver 'best_native_pml_text_from_object\s*\(\s*reinterpret_cast<void\*>\s*\(\s*child\s*\)\s*,\s*source_text\s*,\s*&child_ambiguous\s*\)' `
    "Bounded native child resolver must extract labels from native child objects while preserving ambiguity proof, not guessed order."
if ($treeResolver -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Bounded native child resolver must not infer selection from key presses."
}

Assert-Contains $objectTextResolver 'read_native_pml_c_string_pointer\s*\(\s*pointer\s*\)' `
    "Native object text resolver must inspect pointer-backed native C-string fields before falling back to geometry."
Assert-Contains $objectTextResolver 'read_native_pml_wide_string_pointer\s*\(\s*pointer\s*\)' `
    "Native object text resolver must inspect pointer-backed native wide-string fields before falling back to geometry."
Assert-Contains $objectTextResolver 'add_unique_allowed_candidate\s*\(\s*&candidates,\s*source_text,\s*value,\s*static_cast<uint32_t>\(offset\),\s*1\s*\)' `
    "Pointer-backed native labels must still pass the same strict source-aware allowlist at lower confidence than direct fields."
if ($objectTextResolver -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Native object text resolver must not infer selection from key presses."
}

$dynamicTextResolver = Get-FunctionBody $source "std::string best_native_pml_dynamic_text_from_object"
Assert-Contains $dynamicTextResolver 'prelogin_member_dynamic_label\s*\(\s*value\s*\)' `
    "Dynamic member text extraction must use the narrow dynamic-member label filter."
Assert-Contains $dynamicTextResolver 'read_native_pml_c_string_pointer\s*\(\s*pointer\s*\)' `
    "Dynamic member text extraction must inspect pointer-backed native C-string fields."
Assert-Contains $dynamicTextResolver 'read_native_pml_wide_string_pointer\s*\(\s*pointer\s*\)' `
    "Dynamic member text extraction must inspect pointer-backed native wide-string fields."
if ($dynamicTextResolver -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Dynamic member text resolver must not infer selection from key presses."
}

Assert-Contains $source 'bool\s+native_prelogin_object_tree_has_dynamic_member_value\s*\(' `
    "Regular member screen detection must be backed by native dynamic value rectangles, not guessed screen names."
$memberDynamicTreePresence = Get-FunctionBody $source "bool native_prelogin_object_tree_has_dynamic_member_value"
Assert-Contains $memberDynamicTreePresence 'prelogin_member_dynamic_value_rect\s*\(\s*object\s*\)' `
    "Regular member screen detection must accept the focused dynamic member value object itself."
Assert-Contains $memberDynamicTreePresence 'prelogin_member_dynamic_value_rect\s*\(\s*reinterpret_cast<void\*>\s*\(\s*child\s*\)\s*\)' `
    "Regular member screen detection must scan native child objects for the dynamic member value rectangle."
if ($memberDynamicTreePresence -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Regular member dynamic tree detection must not infer selection from key presses."
}

Assert-Contains $source 'std::string\s+best_native_pml_dynamic_text_from_object_tree\s*\(' `
    "Current-child member-name recovery must inspect focused native trees for a dynamic member value child."
$dynamicTreeResolver = Get-FunctionBody $source "std::string best_native_pml_dynamic_text_from_object_tree"
Assert-Contains $dynamicTreeResolver 'prelogin_member_dynamic_value_rect\s*\(\s*object\s*\)' `
    "Dynamic member tree extraction must read the focused object when it is the value cell."
Assert-Contains $dynamicTreeResolver 'prelogin_member_dynamic_value_rect\s*\(\s*reinterpret_cast<void\*>\s*\(\s*child\s*\)\s*\)' `
    "Dynamic member tree extraction must only read dynamic text from native child value-cell rectangles."
Assert-Contains $dynamicTreeResolver 'best_native_pml_dynamic_text_from_object\s*\(\s*reinterpret_cast<void\*>\s*\(\s*child\s*\)\s*\)' `
    "Dynamic member tree extraction must reuse the narrow native dynamic text decoder on the value child."
if ($dynamicTreeResolver -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Dynamic member tree resolver must not infer selection from key presses."
}

Assert-Contains $source 'bool\s+native_prelogin_member_access_context\s*\(' `
    "Dynamic member names must be spoken only in the proven regular-member native screen context."
$memberAccessContext = Get-FunctionBody $source "bool native_prelogin_member_access_context"
Assert-Contains $memberAccessContext 'native_prelogin_object_tree_has_dynamic_member_value\s*\(\s*object\s*\)' `
    "Regular member context must require a native dynamic member value cell."
Assert-Contains $memberAccessContext '"Login Information"[\s\S]{0,220}"Member Information"[\s\S]{0,220}"PlayOnline ID"[\s\S]{0,220}"Square Enix ID"' `
    "Regular member context must be corroborated by native regular-member labels."
if ($memberAccessContext -match "GetAsyncKeyState|arrow|VK_UP|VK_DOWN|VK_LEFT|VK_RIGHT") {
    throw "Regular member context detection must not infer selection from key presses."
}

$atlasGeometryText = Get-FunctionBody $source "std::string native_prelogin_atlas_label_from_geometry"
Assert-Contains $atlasGeometryText '0x04B575F0u' `
    "Native atlas geometry must include the Ghidra-confirmed regular-member Login Information resource."
Assert-Contains $atlasGeometryText '0x04B575A0u' `
    "Native atlas geometry must include the Ghidra-confirmed regular-member Member Information resource."
Assert-Contains $atlasGeometryText '0x04B57410u' `
    "Native atlas geometry must include the Ghidra-confirmed regular-member PlayOnline ID resource."
Assert-Contains $atlasGeometryText '0x04B57370u' `
    "Native atlas geometry must include the Ghidra-confirmed regular-member Square Enix ID resource."
Assert-Contains $atlasGeometryText '0x04B7B910u' `
    "Native atlas geometry must include the Ghidra-confirmed Square Enix Password resource."
Assert-Contains $atlasGeometryText '\{\s*318,\s*49,\s*464,\s*81,\s*"Square Enix Password"' `
    "Native atlas geometry must label the focused right-side Square Enix Password entry cell from the live current-child rectangle."
if ($atlasGeometryText -match '\{\s*6,\s*0,\s*196,\s*44,\s*"Log In",\s*0x04B54BA8u\s*\}') {
    throw "Member command Log In must not use the stale 6,0,196,44 rect; live current-child proof shows it at 6,32,196,76."
}
Assert-Contains $atlasGeometryText '\{\s*6,\s*32,\s*196,\s*76,\s*"Log In",\s*0x04B54BA8u\s*\}' `
    "Native atlas geometry must label the Ghidra-confirmed member command Log In row from the live current-child rect."
Assert-Contains $atlasGeometryText '\{\s*6,\s*64,\s*196,\s*108,\s*"Settings",\s*0x04B54B38u\s*\}' `
    "Native atlas geometry must label the Ghidra-confirmed member command Settings row from the live current-child rect."
Assert-Contains $atlasGeometryText '\{\s*6,\s*96,\s*196,\s*140,\s*"Delete",\s*0x04B54AC8u\s*\}' `
    "Native atlas geometry must label the Ghidra-confirmed member command Delete row from the live current-child rect."
Assert-Contains $atlasGeometryText '\{\s*6,\s*128,\s*196,\s*172,\s*"Back",\s*0x04B54A58u\s*\}' `
    "Native atlas geometry must label the Ghidra-confirmed member command Back row from the live current-child rect."
if ($atlasGeometryText -match '0x04B59408u|0x04B59548u|0x04B595E8u|0x04B59638u') {
    throw "Native atlas global geometry table must not claim Add Member text fields by Add Member coordinates; those fields require Add Member context proof."
}

$dynamicMemberRect = Get-FunctionBody $source "bool prelogin_member_dynamic_value_rect"
Assert-Contains $dynamicMemberRect '\{\s*104,\s*122,\s*429,\s*146,\s*"member dynamic value"' `
    "Dynamic member value detection must include the Ghidra-confirmed regular-member dynamic value rectangle."
Assert-Contains $dynamicMemberRect '\{\s*104,\s*114,\s*428,\s*138,\s*"member dynamic value"' `
    "Dynamic member value detection must include the alternate Ghidra-confirmed regular-member dynamic value rectangle."

$currentChildResolverForDynamic = Get-FunctionBody $source "void process_current_child_candidate"
Assert-Contains $currentChildResolverForDynamic 'native_prelogin_member_access_context\s*\(\s*current_child_object\s*\)' `
    "Current-child handling must only try tree-based dynamic member text in the proven regular-member screen context."
Assert-Contains $currentChildResolverForDynamic 'best_native_pml_dynamic_text_from_object_tree\s*\(\s*current_child_object\s*\)' `
    "Current-child handling must extract dynamic member names from a focused native value tree."
Assert-Before $currentChildResolverForDynamic 'best_native_pml_dynamic_text_from_object_tree(current_child_object)' 'best_native_pml_text_from_object_tree(current_child_object, "current-child"' `
    "Dynamic member value cells must be tried before static object-tree labels such as Member Information can claim the focus."
if ($selectionInstaller -match 'set_interval_target\s*=' -or
    $selectionInstaller -match 'add_interval_target\s*=' -or
    $selectionInstaller -match 'remove_interval_target\s*=') {
    throw "Native selection truth installer must not re-enable the older interval double hooks."
}

Write-Host "ok"
