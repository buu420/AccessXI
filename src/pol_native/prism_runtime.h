#pragma once

#include <Windows.h>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <string>

namespace accessxi::pol_native
{
    class Diagnostics;

    class PrismRuntime
    {
    public:
        explicit PrismRuntime(Diagnostics& diagnostics);
        ~PrismRuntime();

        PrismRuntime(const PrismRuntime&) = delete;
        PrismRuntime& operator=(const PrismRuntime&) = delete;

        bool load(const std::filesystem::path& absolute_prism_path) noexcept;
        bool initialize(std::chrono::milliseconds window_wait) noexcept;
        int output(const char* utf8_text, bool interrupt) noexcept;
        void reset() noexcept;
        bool ready() const noexcept;

    private:
        using PrismContext = void;
        using PrismBackend = void;
        using PrismBackendId = uint64_t;

        using InitFn = PrismContext* (__cdecl *)(void* config);
        using ShutdownFn = void (__cdecl *)(PrismContext* context);
        using RegistryCreateFn = PrismBackend* (__cdecl *)(PrismContext* context, PrismBackendId id);
        using RegistryCreateBestFn = PrismBackend* (__cdecl *)(PrismContext* context);
        using BackendInitializeFn = int (__cdecl *)(PrismBackend* backend);
        using BackendFreeFn = void (__cdecl *)(PrismBackend* backend);
        using BackendNameFn = const char* (__cdecl *)(PrismBackend* backend);
        using BackendOutputFn = int (__cdecl *)(PrismBackend* backend, const char* text, bool interrupt);
        using BackendStopFn = int (__cdecl *)(PrismBackend* backend);

        bool resolve_exports() noexcept;
        bool try_backend(PrismBackendId id, const char* name) noexcept;
        bool try_best_backend() noexcept;
        bool wait_for_process_window(std::chrono::milliseconds timeout) noexcept;
        void unload() noexcept;

        Diagnostics& diagnostics_;
        HMODULE module_ = nullptr;
        PrismContext* context_ = nullptr;
        PrismBackend* backend_ = nullptr;
        std::string backend_name_;

        InitFn init_ = nullptr;
        ShutdownFn shutdown_ = nullptr;
        RegistryCreateFn registry_create_ = nullptr;
        RegistryCreateBestFn registry_create_best_ = nullptr;
        BackendInitializeFn backend_initialize_ = nullptr;
        BackendFreeFn backend_free_ = nullptr;
        BackendNameFn backend_name_export_ = nullptr;
        BackendOutputFn backend_output_ = nullptr;
        BackendStopFn backend_stop_ = nullptr;
    };
}
