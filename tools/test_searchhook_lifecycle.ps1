param(
    [string]$SourcePath = "C:\Users\buu42\Documents\Codex\2026-05-29\we-are-building-an-ashita-pol\work\accessxi_searchhook.cpp"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Source not found: $SourcePath"
}

$source = Get-Content -LiteralPath $SourcePath -Raw

function Assert-Contains {
    param(
        [string]$Needle,
        [string]$Message
    )
    if (-not $source.Contains($Needle)) {
        throw $Message
    }
}

function Assert-Matches {
    param(
        [string]$Pattern,
        [string]$Message
    )
    if ($source -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Contains "static volatile LONG g_shutting_down = 0;" "missing global shutdown flag"
Assert-Contains "static volatile LONG g_inflight_hooks = 0;" "missing in-flight hook counter"
Assert-Contains "static volatile LONG g_module_pinned = 0;" "missing module pin guard"
Assert-Contains "struct HookCallGuard" "missing hook call guard"
Assert-Contains "InterlockedIncrement(&g_inflight_hooks)" "hook guard must increment in-flight counter"
Assert-Contains "InterlockedDecrement(&g_inflight_hooks)" "hook guard must decrement in-flight counter"
Assert-Matches "static void pin_searchhook_module\(\)[\s\S]*GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS \| GET_MODULE_HANDLE_EX_FLAG_PIN[\s\S]*GetModuleHandleExA\([\s\S]*accessxi_searchhook_init" "searchhook must pin its own DLL by function address so patched POL imports cannot jump into an unloaded module"

Assert-Matches "hook_send[\s\S]*auto original = g_send;[\s\S]*if \(original == nullptr\)[\s\S]*return SOCKET_ERROR;[\s\S]*HookCallGuard guard;[\s\S]*if \(!searchhook_is_shutting_down\(\)" "send hook must snapshot original, guard in-flight, and skip processing during shutdown"
Assert-Matches "hook_recv[\s\S]*auto original = g_recv;[\s\S]*if \(original == nullptr\)[\s\S]*return SOCKET_ERROR;[\s\S]*HookCallGuard guard;[\s\S]*const int ret = original\(s, buf, len, flags\);[\s\S]*if \(!searchhook_is_shutting_down\(\) && ret > 0" "recv hook must use local original and suppress processing during shutdown"
Assert-Matches "hook_recvfrom[\s\S]*auto original = g_recvfrom;[\s\S]*if \(original == nullptr\)[\s\S]*return SOCKET_ERROR;[\s\S]*HookCallGuard guard;[\s\S]*const int ret = original\(s, buf, len, flags, from, fromlen\);[\s\S]*if \(!searchhook_is_shutting_down\(\) && ret > 0" "recvfrom hook must use local original and suppress processing during shutdown"
Assert-Matches "hook_wsarecv[\s\S]*auto original = g_wsarecv;[\s\S]*if \(original == nullptr\)[\s\S]*return SOCKET_ERROR;[\s\S]*HookCallGuard guard;[\s\S]*const int ret = original\(s, buffers, buffer_count, bytes_received, flags, overlapped, completion\);[\s\S]*if \(searchhook_is_shutting_down\(\)\)" "WSARecv hook must use local original and return before processing during shutdown"

Assert-Matches "hook_draw_text_a[\s\S]*auto original = g_draw_text_a;[\s\S]*if \(original == nullptr\)[\s\S]*return 0;[\s\S]*HookCallGuard guard;[\s\S]*if \(!searchhook_is_shutting_down\(\)\)[\s\S]*append_render_trace" "DrawTextA hook must use local original and suppress tracing during shutdown"
Assert-Matches "hook_text_out_a[\s\S]*auto original = g_text_out_a;[\s\S]*if \(original == nullptr\)[\s\S]*return FALSE;[\s\S]*HookCallGuard guard;[\s\S]*if \(!searchhook_is_shutting_down\(\)\)[\s\S]*append_render_trace" "TextOutA hook must use local original and suppress tracing during shutdown"
Assert-Matches "hook_ext_text_out_w[\s\S]*auto original = g_ext_text_out_w;[\s\S]*if \(original == nullptr\)[\s\S]*return FALSE;[\s\S]*HookCallGuard guard;[\s\S]*if \(!searchhook_is_shutting_down\(\)\)[\s\S]*append_render_trace" "ExtTextOutW hook must use local original and suppress tracing during shutdown"

Assert-Matches "accessxi_searchhook_init[\s\S]*InterlockedExchange\(&g_shutting_down, 0\);" "init must clear shutdown flag before installing hooks"
Assert-Matches "accessxi_searchhook_init[\s\S]*pin_searchhook_module\(\);[\s\S]*write_iat_slot\(g_recv_slot, reinterpret_cast<ULONG_PTR>\(&hook_recv\)\)" "init must pin the DLL before installing any IAT hooks"
Assert-Matches "accessxi_searchhook_shutdown[\s\S]*InterlockedExchange\(&g_shutting_down, 1\);[\s\S]*write_iat_slot\(g_recv_slot, g_recv_original\)" "shutdown must mark shutting down before restoring IAT"
Assert-Matches "accessxi_searchhook_shutdown[\s\S]*for \(int wait = 0; wait < 500; \+\+wait\)[\s\S]*InterlockedCompareExchange\(&g_inflight_hooks, 0, 0\)[\s\S]*Sleep\(1\);[\s\S]*g_recv = nullptr;" "shutdown must wait for in-flight hooks before clearing originals"
Assert-Matches "DllMain[\s\S]*DisableThreadLibraryCalls\(module\)" "DllMain should disable thread attach callbacks"
Assert-Matches "DllMain[\s\S]*DLL_PROCESS_DETACH[\s\S]*InterlockedExchange\(&g_shutting_down, 1\)" "process detach should flip shutdown flag"

if ($source.Contains('write_iat_slot(g_recvfrom_slot, reinterpret_cast<ULONG_PTR>(&hook_recvfrom))')) {
    throw "recvfrom must not be patched; search results are proven on recv, and stale recvfrom jumps crash after DLL unload"
}
if ($source.Contains('write_iat_slot(g_wsarecv_slot, reinterpret_cast<ULONG_PTR>(&hook_wsarecv))')) {
    throw "WSARecv must not be patched for searchhook; keep the packet hook surface to recv/send only"
}

Write-Host "ok"
