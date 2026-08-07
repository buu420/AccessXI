#include "pol_native/diagnostics.h"
#include "pol_native/native_host.h"
#include "pol_native/startup_latch.h"

#include <Windows.h>
#include <atomic>
#include <memory>

namespace
{
    HMODULE g_asi_module = nullptr;
    accessxi::pol_native::StartupLatch g_startup_latch;
    std::atomic<bool> g_process_detaching{false};
    accessxi::pol_native::NativeHost* g_live_host = nullptr;
    accessxi::pol_native::Diagnostics* g_live_diagnostics = nullptr;

    DWORD WINAPI native_host_thread(void*)
    {
        auto diagnostics = std::make_unique<accessxi::pol_native::Diagnostics>();
        accessxi::pol_native::NativeHostConfiguration configuration{};
        configuration.asi_module = g_asi_module;
        auto host = std::make_unique<accessxi::pol_native::NativeHost>(configuration, *diagnostics);
        if (host->run() == accessxi::pol_native::NativeHostResult::ready &&
            !g_process_detaching.load(std::memory_order_acquire))
        {
            g_live_diagnostics = diagnostics.release();
            g_live_host = host.release();
        }
        return 0;
    }

    void schedule_startup_once() noexcept
    {
        if (!g_startup_latch.try_start())
            return;
        HANDLE thread = CreateThread(nullptr, 0, native_host_thread, nullptr, 0, nullptr);
        if (thread != nullptr)
            CloseHandle(thread);
    }
}

extern "C" __declspec(dllexport) void InitializeASI()
{
    schedule_startup_once();
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_asi_module = module;
        DisableThreadLibraryCalls(module);
        schedule_startup_once();
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        g_process_detaching.store(true, std::memory_order_release);
    }
    return TRUE;
}
