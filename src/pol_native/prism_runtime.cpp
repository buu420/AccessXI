#include "pol_native/prism_runtime.h"

#include "pol_native/diagnostics.h"

#include <Windows.h>
#include <array>
#include <chrono>
#include <filesystem>
#include <sstream>
#include <string>
#include <thread>

namespace accessxi::pol_native
{
    namespace
    {
        constexpr uint64_t PrismBackendNvda = 0x89CC19C5C4AC1A56ull;
        constexpr uint64_t PrismBackendJaws = 0xAC3D60E9BD84B53Eull;
        constexpr uint64_t PrismBackendUia = 0x6238F019DB678F8Eull;
        constexpr int PrismOk = 0;

        bool is_current_process_window(HWND window)
        {
            if (window == nullptr || !IsWindowVisible(window) || GetWindow(window, GW_OWNER) != nullptr)
                return false;
            DWORD process_id = 0;
            GetWindowThreadProcessId(window, &process_id);
            return process_id == GetCurrentProcessId();
        }

        BOOL CALLBACK find_window_callback(HWND window, LPARAM parameter)
        {
            if (!is_current_process_window(window))
                return TRUE;
            *reinterpret_cast<HWND*>(parameter) = window;
            return FALSE;
        }

        HWND find_process_window()
        {
            const HWND foreground = GetForegroundWindow();
            if (is_current_process_window(foreground))
                return foreground;

            HWND result = nullptr;
            EnumWindows(find_window_callback, reinterpret_cast<LPARAM>(&result));
            return result;
        }

        std::string windows_error(const char* stage)
        {
            return std::string(stage) + " error=" + std::to_string(GetLastError());
        }
    }

    PrismRuntime::PrismRuntime(Diagnostics& diagnostics)
        : diagnostics_(diagnostics)
    {
    }

    PrismRuntime::~PrismRuntime()
    {
        unload();
    }

    bool PrismRuntime::load(const std::filesystem::path& absolute_prism_path) noexcept
    {
        try
        {
            if (!absolute_prism_path.is_absolute())
            {
                diagnostics_.startup("ACCESSXI_POL_NATIVE prism-load-rejected reason=non-absolute");
                return false;
            }

            module_ = LoadLibraryExW(
                absolute_prism_path.c_str(),
                nullptr,
                LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
            if (module_ == nullptr)
            {
                diagnostics_.startup("ACCESSXI_POL_NATIVE " + windows_error("prism-load-failed"));
                return false;
            }
            if (!resolve_exports())
            {
                diagnostics_.startup("ACCESSXI_POL_NATIVE prism-export-missing");
                unload();
                return false;
            }
            diagnostics_.startup("ACCESSXI_POL_NATIVE prism-load-ok");
            return true;
        }
        catch (...)
        {
            diagnostics_.startup("ACCESSXI_POL_NATIVE prism-load-exception");
            unload();
            return false;
        }
    }

    bool PrismRuntime::initialize(std::chrono::milliseconds window_wait) noexcept
    {
        try
        {
            reset();
            if (module_ == nullptr || init_ == nullptr)
                return false;

            context_ = init_(nullptr);
            if (context_ == nullptr)
            {
                diagnostics_.startup("ACCESSXI_POL_NATIVE prism-context-failed");
                return false;
            }

            if (try_backend(PrismBackendNvda, "NVDA"))
                return true;
            if (try_backend(PrismBackendJaws, "JAWS"))
                return true;

            if (wait_for_process_window(window_wait))
            {
                diagnostics_.startup("ACCESSXI_POL_NATIVE prism-uia-host-window-ready");
                if (try_backend(PrismBackendUia, "UIA"))
                    return true;
            }
            else
            {
                diagnostics_.startup("ACCESSXI_POL_NATIVE prism-uia-host-window-missing");
            }

            if (try_best_backend())
                return true;

            reset();
            return false;
        }
        catch (...)
        {
            diagnostics_.startup("ACCESSXI_POL_NATIVE prism-initialize-exception");
            reset();
            return false;
        }
    }

    int PrismRuntime::output(const char* utf8_text, bool interrupt) noexcept
    {
        if (backend_ == nullptr || backend_output_ == nullptr || utf8_text == nullptr)
            return -1;
        try
        {
            return backend_output_(backend_, utf8_text, interrupt);
        }
        catch (...)
        {
            return -1;
        }
    }

    void PrismRuntime::reset() noexcept
    {
        try
        {
            if (backend_ != nullptr)
            {
                if (backend_stop_ != nullptr)
                    backend_stop_(backend_);
                if (backend_free_ != nullptr)
                    backend_free_(backend_);
                backend_ = nullptr;
            }
            if (context_ != nullptr)
            {
                if (shutdown_ != nullptr)
                    shutdown_(context_);
                context_ = nullptr;
            }
            backend_name_.clear();
        }
        catch (...)
        {
            backend_ = nullptr;
            context_ = nullptr;
            backend_name_.clear();
        }
    }

    bool PrismRuntime::ready() const noexcept
    {
        return backend_ != nullptr;
    }

    bool PrismRuntime::resolve_exports() noexcept
    {
        init_ = reinterpret_cast<InitFn>(GetProcAddress(module_, "prism_init"));
        shutdown_ = reinterpret_cast<ShutdownFn>(GetProcAddress(module_, "prism_shutdown"));
        registry_create_ = reinterpret_cast<RegistryCreateFn>(GetProcAddress(module_, "prism_registry_create"));
        registry_create_best_ = reinterpret_cast<RegistryCreateBestFn>(GetProcAddress(module_, "prism_registry_create_best"));
        backend_initialize_ = reinterpret_cast<BackendInitializeFn>(GetProcAddress(module_, "prism_backend_initialize"));
        backend_free_ = reinterpret_cast<BackendFreeFn>(GetProcAddress(module_, "prism_backend_free"));
        backend_name_export_ = reinterpret_cast<BackendNameFn>(GetProcAddress(module_, "prism_backend_name"));
        backend_output_ = reinterpret_cast<BackendOutputFn>(GetProcAddress(module_, "prism_backend_output"));
        backend_stop_ = reinterpret_cast<BackendStopFn>(GetProcAddress(module_, "prism_backend_stop"));
        return init_ != nullptr &&
            shutdown_ != nullptr &&
            registry_create_ != nullptr &&
            registry_create_best_ != nullptr &&
            backend_initialize_ != nullptr &&
            backend_free_ != nullptr &&
            backend_name_export_ != nullptr &&
            backend_output_ != nullptr &&
            backend_stop_ != nullptr;
    }

    bool PrismRuntime::try_backend(PrismBackendId id, const char* name) noexcept
    {
        PrismBackend* candidate = registry_create_(context_, id);
        if (candidate == nullptr)
        {
            diagnostics_.startup(std::string("ACCESSXI_POL_NATIVE prism-backend-create-failed name=") + name);
            return false;
        }
        const int result = backend_initialize_(candidate);
        if (result != PrismOk)
        {
            diagnostics_.startup(
                std::string("ACCESSXI_POL_NATIVE prism-backend-unavailable name=") +
                name +
                " result=" +
                std::to_string(result));
            backend_free_(candidate);
            return false;
        }

        backend_ = candidate;
        const char* reported_name = backend_name_export_(backend_);
        backend_name_ = reported_name == nullptr || reported_name[0] == 0 ? name : reported_name;
        diagnostics_.startup(std::string("ACCESSXI_POL_NATIVE prism-ready backend=") + backend_name_);
        return true;
    }

    bool PrismRuntime::try_best_backend() noexcept
    {
        PrismBackend* candidate = registry_create_best_(context_);
        if (candidate == nullptr)
        {
            diagnostics_.startup("ACCESSXI_POL_NATIVE prism-best-create-failed");
            return false;
        }
        const int result = backend_initialize_(candidate);
        if (result != PrismOk)
        {
            diagnostics_.startup("ACCESSXI_POL_NATIVE prism-best-unavailable result=" + std::to_string(result));
            backend_free_(candidate);
            return false;
        }

        backend_ = candidate;
        const char* reported_name = backend_name_export_(backend_);
        backend_name_ = reported_name == nullptr || reported_name[0] == 0 ? "best" : reported_name;
        diagnostics_.startup(std::string("ACCESSXI_POL_NATIVE prism-ready backend=") + backend_name_);
        return true;
    }

    bool PrismRuntime::wait_for_process_window(std::chrono::milliseconds timeout) noexcept
    {
        const auto deadline = std::chrono::steady_clock::now() + timeout;
        do
        {
            if (find_process_window() != nullptr)
                return true;
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        } while (std::chrono::steady_clock::now() < deadline);
        return find_process_window() != nullptr;
    }

    void PrismRuntime::unload() noexcept
    {
        reset();
        if (module_ != nullptr)
        {
            FreeLibrary(module_);
            module_ = nullptr;
        }
        init_ = nullptr;
        shutdown_ = nullptr;
        registry_create_ = nullptr;
        registry_create_best_ = nullptr;
        backend_initialize_ = nullptr;
        backend_free_ = nullptr;
        backend_name_export_ = nullptr;
        backend_output_ = nullptr;
        backend_stop_ = nullptr;
    }
}
