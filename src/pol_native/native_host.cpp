#include "pol_native/native_host.h"

#include "pol_native/diagnostics.h"
#include "pol_native/speech_worker.h"

#include <Windows.h>
#include <array>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <string>
#include <thread>
#include <utility>

namespace accessxi::pol_native
{
    namespace
    {
        std::filesystem::path module_path(HMODULE module)
        {
            if (module == nullptr)
                return {};
            std::wstring buffer(32768, L'\0');
            const DWORD copied = GetModuleFileNameW(
                module,
                buffer.data(),
                static_cast<DWORD>(buffer.size()));
            if (copied == 0 || copied >= buffer.size())
                return {};
            buffer.resize(copied);
            return std::filesystem::path(buffer);
        }

        std::string fingerprint_marker(const FileFingerprint& fingerprint)
        {
            char hash[17]{};
            std::snprintf(hash, sizeof(hash), "%016llX", static_cast<unsigned long long>(fingerprint.fnv64));
            return " size=" + std::to_string(fingerprint.size) + " fnv64=" + hash;
        }
    }

    bool fingerprint_file(const std::filesystem::path& path, FileFingerprint& result) noexcept
    {
        HANDLE file = CreateFileW(
            path.c_str(),
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
            return false;

        LARGE_INTEGER size{};
        if (!GetFileSizeEx(file, &size) || size.QuadPart < 0)
        {
            CloseHandle(file);
            return false;
        }

        uint64_t hash = 14695981039346656037ull;
        std::array<unsigned char, 32768> buffer{};
        DWORD read = 0;
        BOOL read_ok = FALSE;
        while ((read_ok = ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) && read > 0)
        {
            for (DWORD index = 0; index < read; ++index)
            {
                hash ^= static_cast<uint64_t>(buffer[index]);
                hash *= 1099511628211ull;
            }
        }
        CloseHandle(file);
        if (!read_ok)
            return false;

        result.size = static_cast<uint64_t>(size.QuadPart);
        result.fnv64 = hash;
        return true;
    }

    std::filesystem::path dependency_directory_from_asi_path(const std::filesystem::path& asi_path)
    {
        return asi_path.parent_path() / asi_path.stem();
    }

    NativeHost::NativeHost(NativeHostConfiguration configuration, Diagnostics& diagnostics)
        : configuration_(std::move(configuration)), diagnostics_(diagnostics)
    {
    }

    NativeHost::~NativeHost()
    {
        stop_for_tests();
    }

    NativeHostResult NativeHost::run() noexcept
    {
        std::lock_guard<std::mutex> guard(run_lock_);
        if (has_run_)
            return result_;
        has_run_ = true;
        result_ = run_once();
        return result_;
    }

    void NativeHost::stop_for_tests() noexcept
    {
        try
        {
            if (set_speech_sink_ != nullptr)
            {
                set_speech_sink_(nullptr, nullptr);
                set_speech_sink_ = nullptr;
            }
            if (speech_worker_ != nullptr)
            {
                speech_worker_->stop_for_tests();
                speech_worker_.reset();
            }
            if (hook_module_ != nullptr)
            {
                FreeLibrary(hook_module_);
                hook_module_ = nullptr;
            }
        }
        catch (...)
        {
        }
    }

    SpeechQueueStats NativeHost::speech_stats() const noexcept
    {
        return speech_worker_ == nullptr ? SpeechQueueStats{} : speech_worker_->stats();
    }

    unsigned int NativeHost::fatal_notification_count() const noexcept
    {
        return fatal_notifications_.load(std::memory_order_acquire);
    }

    NativeHostResult NativeHost::run_once() noexcept
    {
        try
        {
            diagnostics_.startup("ACCESSXI_POL_NATIVE worker-start");
            const std::filesystem::path asi_path = resolve_asi_path();
            if (asi_path.empty() || !asi_path.is_absolute())
                return fail(NativeHostResult::invalid_asi_path, "asi-path-invalid");

            const std::filesystem::path app_path = wait_for_app_path();
            if (app_path.empty())
                return fail(NativeHostResult::app_missing, "app-module-missing");

            FileFingerprint fingerprint{};
            if (!fingerprint_file(app_path, fingerprint))
                return fail(NativeHostResult::unsupported_app, "app-fingerprint-unavailable");
            if (fingerprint.size != configuration_.expected_app_size ||
                fingerprint.fnv64 != configuration_.expected_app_fnv64)
            {
                diagnostics_.startup(
                    "ACCESSXI_POL_NATIVE app-fingerprint-mismatch" +
                    fingerprint_marker(fingerprint));
                return fail(NativeHostResult::unsupported_app, "unsupported-app-build");
            }
            diagnostics_.startup(
                "ACCESSXI_POL_NATIVE app-fingerprint-ok" +
                fingerprint_marker(fingerprint));

            const std::filesystem::path dependency_directory = dependency_directory_from_asi_path(asi_path);
            speech_worker_ = std::make_unique<SpeechWorker>(
                dependency_directory,
                diagnostics_,
                128,
                configuration_.speech_initialization_timeout,
                configuration_.window_wait_timeout);
            if (!speech_worker_->start() ||
                !speech_worker_->wait_until_ready(configuration_.speech_ready_timeout))
            {
                return fail(NativeHostResult::speech_unavailable, "speech-worker-unavailable");
            }

            const std::filesystem::path hook_path = dependency_directory / L"accessxi_pol_native.dll";
            hook_module_ = LoadLibraryExW(
                hook_path.c_str(),
                nullptr,
                LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
            if (hook_module_ == nullptr)
                return fail(NativeHostResult::hook_unavailable, "hook-load-failed");

            set_speech_sink_ = reinterpret_cast<SetSpeechSinkV1Fn>(
                GetProcAddress(hook_module_, "AccessXI_POL_SetSpeechSinkV1"));
            auto initialize_v2 = reinterpret_cast<InitializeV2Fn>(
                GetProcAddress(hook_module_, "AccessXI_POL_InitializeV2"));
            if (set_speech_sink_ == nullptr || initialize_v2 == nullptr)
                return fail(NativeHostResult::hook_abi_mismatch, "hook-abi-mismatch");

            if (set_speech_sink_(&speech_sink_callback, speech_worker_.get()) != 1)
                return fail(NativeHostResult::hook_abi_mismatch, "speech-sink-rejected");
            diagnostics_.startup("ACCESSXI_POL_NATIVE speech-sink-registered");

            const int initialize_result = initialize_v2();
            if (initialize_result != 1 && initialize_result != 2)
            {
                diagnostics_.startup(
                    "ACCESSXI_POL_NATIVE hook-initialize-failed result=" +
                    std::to_string(initialize_result));
                return fail(NativeHostResult::hook_initialize_failed, "hook-initialize-rejected");
            }
            diagnostics_.startup(
                "ACCESSXI_POL_NATIVE hook-initialize-ok result=" +
                std::to_string(initialize_result));
            diagnostics_.startup("ACCESSXI_POL_NATIVE ready");
            return NativeHostResult::ready;
        }
        catch (...)
        {
            return fail(NativeHostResult::internal_error, "host-exception");
        }
    }

    NativeHostResult NativeHost::fail(NativeHostResult result, const char* marker) noexcept
    {
        diagnostics_.startup(std::string("ACCESSXI_POL_NATIVE failure stage=") + marker);
        show_failure_once();
        return result;
    }

    std::filesystem::path NativeHost::resolve_asi_path() const
    {
        if (!configuration_.asi_path_override.empty())
            return std::filesystem::absolute(configuration_.asi_path_override);
        return module_path(configuration_.asi_module);
    }

    std::filesystem::path NativeHost::wait_for_app_path() const
    {
        if (!configuration_.app_path_override.empty())
            return std::filesystem::absolute(configuration_.app_path_override);

        const auto deadline = std::chrono::steady_clock::now() + configuration_.app_wait_timeout;
        do
        {
            if (HMODULE app = GetModuleHandleW(L"app.dll"); app != nullptr)
                return module_path(app);
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        } while (std::chrono::steady_clock::now() < deadline);
        return {};
    }

    void NativeHost::show_failure_once() noexcept
    {
        unsigned int expected = 0;
        if (!fatal_notifications_.compare_exchange_strong(expected, 1, std::memory_order_acq_rel))
            return;
        if (!configuration_.show_failure_dialog)
            return;

        try
        {
            const std::wstring message =
                L"AccessXI could not safely start PlayOnline accessibility. "
                L"No native hooks were enabled. Details are in:\n" +
                diagnostics_.startup_log_path().wstring();
            MessageBoxW(
                nullptr,
                message.c_str(),
                L"AccessXI PlayOnline Accessibility",
                MB_OK | MB_ICONERROR);
        }
        catch (...)
        {
        }
    }

    void __stdcall NativeHost::speech_sink_callback(
        const char* utf8_text,
        int interrupt,
        void* context) noexcept
    {
        if (utf8_text == nullptr || context == nullptr)
            return;
        static_cast<SpeechWorker*>(context)->enqueue(utf8_text, interrupt != 0);
    }
}
