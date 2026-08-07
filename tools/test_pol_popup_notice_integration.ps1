param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath($RepoRoot)
$sourcePath = Join-Path $repo 'src\accessxi_pol.cpp'
$modulePath = Join-Path $repo 'src\pol_pml\native_popup_text.cpp'
$cmakePath = Join-Path $repo 'CMakeLists.txt'

foreach ($path in @($sourcePath, $modulePath, $cmakePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required popup integration file is missing: $path"
    }
}

$source = Get-Content -LiteralPath $sourcePath -Raw
$module = Get-Content -LiteralPath $modulePath -Raw
$cmake = Get-Content -LiteralPath $cmakePath -Raw

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

function Assert-Before {
    param([string]$Text, [string]$First, [string]$Second, [string]$Message)
    $firstIndex = $Text.IndexOf($First, [System.StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [System.StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        throw $Message
    }
}

function Function-Body {
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Function not found: $Signature" }
    $brace = $Text.IndexOf('{', $start)
    if ($brace -lt 0) { throw "Function body not found: $Signature" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    throw "Unterminated function: $Signature"
}

Assert-Contains $source '#include\s+"pol_pml/native_popup_text\.h"' `
    'The PlayOnline hook must use the unit-tested strict popup reader.'
Assert-Contains $cmake 'add_library\s*\(\s*accessxi_pol_hook[\s\S]*?src/pol_pml/native_popup_text\.cpp' `
    'The production hook DLL must link the strict popup reader.'

$constants = @{
    ModalOkConstructorRva = '000D1842'
    ModalYesNoConstructorRva = '000D1B45'
    ModalYesNoCancelConstructorRva = '000D1E5E'
    ModalOkCancelConstructorRva = '000D2B16'
    ModalRetryFailConstructorRva = '000D32FB'
    NoticeWindowConstructorRva = '000A6485'
    ImportantNoticeConstructorRva = '000A9CCB'
}
foreach ($entry in $constants.GetEnumerator()) {
    Assert-Contains $source (
        [regex]::Escape($entry.Key) + '\s*=\s*0x' + $entry.Value + 'u'
    ) "Missing Ghidra-proven popup constructor constant $($entry.Key)."
}
Assert-Contains $source 'PopupConstructorPatchSize\s*=\s*7' `
    'Popup constructors must steal only the two complete non-relative entry instructions.'

$destructorConstants = @{
    ModalOkBaseDestructorRva = '000BD4F0'
    ModalYesNoBaseDestructorRva = '000BD55E'
    ModalYesNoCancelBaseDestructorRva = '000BD5CC'
    ModalOkCancelBaseDestructorRva = '000BDA4E'
    ModalRetryFailBaseDestructorRva = '000BDB2A'
    NoticeWindowBaseDestructorRva = '000A6668'
    ImportantNoticeBaseDestructorRva = '000A6AC0'
}
foreach ($entry in $destructorConstants.GetEnumerator()) {
    Assert-Contains $source (
        [regex]::Escape($entry.Key) + '\s*=\s*0x' + $entry.Value + 'u'
    ) "Missing Ghidra-proven popup base-destructor constant $($entry.Key)."
}
Assert-Contains $source 'PopupEhBaseDestructorPatchSize\s*=\s*7' `
    'EH-prologue popup base destructors must steal their complete seven-byte prefix.'
Assert-Contains $source 'PopupNoticeBaseDestructorPatchSize\s*=\s*6' `
    'The notice base destructor must steal only its complete first six-byte instruction.'

Assert-Contains $source 'g_popup_notice_hooks_installed' `
    'Popup hook installation needs an idempotent state guard.'
Assert-Contains $source 'g_popup_owner_registry' `
    'Each popup owner kind needs an atomic registration slot.'
Assert-Contains $source 'g_popup_text_trackers' `
    'Worker-side popup stability and deduplication state is missing.'
Assert-Contains $source 'std::atomic<void\*>\s+g_modal_ok_constructor_trampoline' `
    'Popup constructor trampolines must be atomically published before their entry jumps become callable.'

$publish = Function-Body $source 'void publish_popup_owner'
Assert-Contains $publish '\.publish\s*\(' `
    'Popup owner publication must use the unit-tested coherent atomic registration pair.'
Assert-NotContains $publish 'inspect_popup_text|dispatch_speech|speak_|log_line|append_|Sleep|mutex|lock_guard|vector' `
    'The constructor publication path must remain atomic-only.'

$hooks = @(
    @{ Signature = 'void* __fastcall hook_modal_ok_constructor'; Kind = 'modal_ok' },
    @{ Signature = 'void* __fastcall hook_modal_yes_no_constructor'; Kind = 'modal_yes_no' },
    @{ Signature = 'void* __fastcall hook_modal_yes_no_cancel_constructor'; Kind = 'modal_yes_no_cancel' },
    @{ Signature = 'void* __fastcall hook_modal_ok_cancel_constructor'; Kind = 'modal_ok_cancel' },
    @{ Signature = 'void* __fastcall hook_modal_retry_fail_constructor'; Kind = 'modal_retry_fail' },
    @{ Signature = 'void* __fastcall hook_notice_window_constructor'; Kind = 'notice' },
    @{ Signature = 'void* __fastcall hook_important_notice_constructor'; Kind = 'important_notice' }
)
foreach ($hook in $hooks) {
    $body = Function-Body $source $hook.Signature
    Assert-Contains $body '\.load\s*\(\s*std::memory_order_acquire\s*\)' `
        "$($hook.Signature) must acquire its trampoline after the installer publishes it."
    Assert-Contains $body 'original\s*\(\s*self\s*\)' `
        "$($hook.Signature) must call its original constructor."
    Assert-Contains $body (
        'publish_popup_owner\s*\(\s*accessxi::pol_pml::PopupOwnerKind::' +
        [regex]::Escape($hook.Kind) +
        '\s*,\s*self\s*\)'
    ) "$($hook.Signature) must publish only its exact owner kind."
    Assert-Before $body 'original(self)' 'publish_popup_owner' `
        "$($hook.Signature) must publish only after construction completes."
    Assert-NotContains $body 'inspect_popup_text|dispatch_speech|speak_popup|log_line|append_|Sleep|best_native|object_tree|mutex|lock_guard' `
        "$($hook.Signature) performs worker-owned work on PlayOnline's UI thread."
}

$destructorHooks = @(
    @{ Signature = 'void __fastcall hook_modal_ok_base_destructor'; Kind = 'modal_ok' },
    @{ Signature = 'void __fastcall hook_modal_yes_no_base_destructor'; Kind = 'modal_yes_no' },
    @{ Signature = 'void __fastcall hook_modal_yes_no_cancel_base_destructor'; Kind = 'modal_yes_no_cancel' },
    @{ Signature = 'void __fastcall hook_modal_ok_cancel_base_destructor'; Kind = 'modal_ok_cancel' },
    @{ Signature = 'void __fastcall hook_modal_retry_fail_base_destructor'; Kind = 'modal_retry_fail' },
    @{ Signature = 'void __fastcall hook_notice_window_base_destructor'; Kind = 'notice' },
    @{ Signature = 'void __fastcall hook_important_notice_base_destructor'; Kind = 'important_notice' }
)
foreach ($hook in $destructorHooks) {
    $body = Function-Body $source $hook.Signature
    Assert-Contains $body '\.load\s*\(\s*std::memory_order_acquire\s*\)' `
        "$($hook.Signature) must acquire its exact original destructor."
    Assert-Contains $body (
        'invalidate_popup_owner\s*\(\s*accessxi::pol_pml::PopupOwnerKind::' +
        [regex]::Escape($hook.Kind) +
        '\s*,\s*self\s*\)'
    ) "$($hook.Signature) must invalidate only its exact owner kind."
    Assert-Before $body 'invalidate_popup_owner' 'original(self' `
        "$($hook.Signature) must revoke the owner before native destruction starts."
    Assert-NotContains $body 'inspect_popup_text|dispatch_speech|speak_popup|log_line|append_|Sleep|best_native|object_tree|mutex|lock_guard' `
        "$($hook.Signature) performs worker-owned work on PlayOnline's UI thread."
}

$atomicInstaller = Function-Body $source 'bool install_inline_jump_atomic'
Assert-Before $atomicInstaller 'thread_quiescence.acquire' 'trampoline.store' `
    'Popup patching must quiesce other threads before publishing a callable trampoline.'
Assert-Before $atomicInstaller 'trampoline.store' 'bytes[0]' `
    'A popup trampoline must be published before the constructor entry becomes callable as a jump.'
Assert-Contains $atomicInstaller 'std::memory_order_release' `
    'Popup trampoline publication must use release ordering.'

$threadQuiescence = Function-Body $source 'class ScopedPopupPatchThreadQuiescence'
Assert-Contains $threadQuiescence 'CreateToolhelp32Snapshot\s*\(\s*TH32CS_SNAPTHREAD' `
    'Popup patching must enumerate the current process threads.'
Assert-Contains $threadQuiescence 'SuspendThread\s*\(' `
    'Popup patching must stop other callers while constructor bytes change.'
Assert-Contains $threadQuiescence 'GetThreadContext\s*\(' `
    'Popup patching must reject a target whose entry bytes are already executing.'
Assert-Contains $threadQuiescence 'ResumeThread\s*\(' `
    'Popup patching must always release threads after the bounded patch.'

$retryReadiness = Function-Body $source 'bool popup_lifecycle_prologues_ready'
foreach ($trampoline in @(
    'g_modal_ok_constructor_trampoline',
    'g_modal_yes_no_constructor_trampoline',
    'g_modal_yes_no_cancel_constructor_trampoline',
    'g_modal_ok_cancel_constructor_trampoline',
    'g_modal_retry_fail_constructor_trampoline',
    'g_notice_window_constructor_trampoline',
    'g_important_notice_constructor_trampoline',
    'g_modal_ok_base_destructor_trampoline',
    'g_modal_yes_no_base_destructor_trampoline',
    'g_modal_yes_no_cancel_base_destructor_trampoline',
    'g_modal_ok_cancel_base_destructor_trampoline',
    'g_modal_retry_fail_base_destructor_trampoline',
    'g_notice_window_base_destructor_trampoline',
    'g_important_notice_base_destructor_trampoline'
)) {
    Assert-Contains $retryReadiness ([regex]::Escape($trampoline)) `
        "Popup hook retry validation does not preserve the already-installed trampoline $trampoline."
}

$installer = Function-Body $source 'void install_popup_notice_hooks_once'
Assert-Before $installer 'app_module_matches_known_updated_pol_build' 'install_inline_jump' `
    'Popup hooks must pass the exact app.dll fingerprint gate before patching code.'
Assert-Before $installer 'popup_lifecycle_prologues_ready' 'install_inline_jump' `
    'Popup hooks must verify all unpacked lifecycle prologues before patching.'
Assert-Contains $installer 'PopupConstructorPatchSize' `
    'Popup hooks must use the Ghidra-verified seven-byte entry boundary.'
Assert-Contains $installer 'install_inline_jump_atomic\s*\(' `
    'Popup constructors and base destructors must use the trampoline-first atomic installer.'
Assert-NotContains $installer 'install_vtable_hook_atomic\s*\(' `
    'A base-vtable slot cannot observe destruction through derived popup vtables.'
foreach ($entry in $destructorConstants.GetEnumerator()) {
    Assert-Before $installer ([regex]::Escape($entry.Key)) 'if (!destructors_ready)' `
        "Base-destructor invalidation hook $($entry.Key) must be attempted before the destructor gate."
}
Assert-Before $installer 'if (!destructors_ready)' 'ModalOkConstructorRva' `
    'No constructor may be hooked until every matching base-destructor hook is installed.'
foreach ($entry in $constants.GetEnumerator()) {
    Assert-Contains $installer ([regex]::Escape($entry.Key)) `
        "Popup hook installer does not use $($entry.Key)."
}
foreach ($entry in $destructorConstants.GetEnumerator()) {
    Assert-Contains $installer ([regex]::Escape($entry.Key)) `
        "Popup hook installer does not use $($entry.Key)."
}

$processor = Function-Body $source 'void process_popup_notice_text'
Assert-Contains $processor 'native_post_login_surface_active\s*\(\s*\)' `
    'Popup polling must stop after FFXI loads.'
Assert-Contains $processor 'inspect_popup_text\s*\(' `
    'Popup polling must use the strict exact-owner reader.'
Assert-Contains $processor 'g_popup_text_trackers' `
    'Popup polling must use worker-side stability and deduplication.'
Assert-Contains $processor 'PopupOwnerRegistration::capacity\s*\(\s*\)' `
    'Popup polling must inspect every bounded live-owner slot.'
Assert-Contains $processor '\.snapshot\s*\(\s*owner_slot\s*\)' `
    'Popup polling must consume each coherent owner-and-generation publication.'
Assert-Contains $processor 'g_popup_text_trackers\s*\[\s*index\s*\]\s*\[\s*owner_slot\s*\]' `
    'Each simultaneous popup owner needs independent stability and deduplication state.'
Assert-Contains $processor 'registration_after_inspection' `
    'Popup polling must revalidate the exact owner registration after native memory reads.'
Assert-Before $processor 'registration_after_inspection' 'tracker.observe' `
    'Popup polling must revalidate owner lifetime before mutating deduplication or speaking.'
Assert-Contains $processor 'speak_popup_notice_text\s*\(' `
    'Only tracker-approved popup observations may reach speech.'
Assert-NotContains $processor 'best_native_pml_text_from_object|best_native_pml_text_from_object_tree' `
    'Popup speech must never fall back to an arbitrary PML object scan.'

$speaker = Function-Body $source 'void speak_popup_notice_text'
Assert-Contains $speaker 'dispatch_speech_sink_v1\s*\(' `
    'Popup text must use the active Prism-compatible speech sink.'
Assert-Contains $speaker 'speak_interrupt' `
    'Modal bodies and notices must retain their distinct interruption policy.'



$reset = Function-Body $source 'void reset_popup_notice_state'
Assert-Contains $reset 'g_popup_text_trackers' `
    'Popup reset must clear worker-side stability and deduplication.'
Assert-Contains $reset 'g_popup_owner_registry' `
    'Popup reset must invalidate all registered native owners.'

$runtimeReset = Function-Body $source 'void reset_prelogin_runtime_speech_state'
Assert-Contains $runtimeReset 'reset_popup_notice_state\s*\(' `
    'The existing PlayOnline runtime reset must clear popup state.'

$iteration = Function-Body $source 'void run_native_hook_iteration'
Assert-Contains $iteration 'install_popup_notice_hooks_once\s*\(' `
    'The native worker must install exact popup constructor hooks.'
Assert-Contains $iteration 'process_popup_notice_text\s*\(' `
    'The native worker must poll registered popup text.'
Assert-Before $iteration 'process_popup_notice_text' 'process_queued_current_child_candidate' `
    'Popup bodies must be processed before ordinary queued focus speech.'

Assert-Contains $source 'PRELOGIN_TEXTSETTER hook-disabled rva=00064156 reason=crash-stability' `
    'The crash-prone generic PML text-setter hook must remain disabled.'
Assert-NotContains $module 'OCR|DrawText|best_native_pml_text_from_object' `
    'The pure popup reader must not acquire guessed or rendered global text.'

'ok: popup and notice speech tracks exact derived owners, all bounded live instances, visible labels, stable text, and base-destructor lifetime.'
