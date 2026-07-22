#pragma once

#include "pol_native/speech_queue.h"

#include <Windows.h>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <mutex>

namespace accessxi::pol_native
{
    class Diagnostics;
    class SpeechWorker;

    struct FileFingerprint
    {
        uint64_t size = 0;
        uint64_t fnv64 = 0;
    };

    bool fingerprint_file(const std::filesystem::path& path, FileFingerprint& result) noexcept;
    std::filesystem::path dependency_directory_from_asi_path(const std::filesystem::path& asi_path);

    struct NativeHostConfiguration
    {
        HMODULE asi_module = nullptr;
        std::filesystem::path asi_path_override;
        std::filesystem::path app_path_override;
        uint64_t expected_app_size = 4335104ull;
        uint64_t expected_app_fnv64 = 0x07E88E8067FEF6CCull;
        bool show_failure_dialog = true;
        std::chrono::milliseconds app_wait_timeout = std::chrono::seconds(30);
        std::chrono::milliseconds speech_ready_timeout = std::chrono::seconds(20);
        std::chrono::milliseconds speech_initialization_timeout = std::chrono::seconds(20);
        std::chrono::milliseconds window_wait_timeout = std::chrono::seconds(10);
    };

    enum class NativeHostResult
    {
        ready = 1,
        invalid_asi_path = -1,
        app_missing = -2,
        unsupported_app = -3,
        speech_unavailable = -4,
        hook_unavailable = -5,
        hook_abi_mismatch = -6,
        hook_initialize_failed = -7,
        internal_error = -8
    };

    class NativeHost
    {
    public:
        NativeHost(NativeHostConfiguration configuration, Diagnostics& diagnostics);
        ~NativeHost();

        NativeHost(const NativeHost&) = delete;
        NativeHost& operator=(const NativeHost&) = delete;

        NativeHostResult run() noexcept;
        void stop_for_tests() noexcept;
        SpeechQueueStats speech_stats() const noexcept;
        unsigned int fatal_notification_count() const noexcept;

    private:
        using SpeechSinkV1 = void (__stdcall *)(const char*, int, void*);
        using SetSpeechSinkV1Fn = int (__stdcall *)(SpeechSinkV1, void*);
        using InitializeV2Fn = int (__stdcall *)();

        NativeHostResult run_once() noexcept;
        NativeHostResult fail(NativeHostResult result, const char* marker) noexcept;
        std::filesystem::path resolve_asi_path() const;
        std::filesystem::path wait_for_app_path() const;
        void show_failure_once() noexcept;
        static void __stdcall speech_sink_callback(const char* utf8_text, int interrupt, void* context) noexcept;

        NativeHostConfiguration configuration_;
        Diagnostics& diagnostics_;
        mutable std::mutex run_lock_;
        bool has_run_ = false;
        NativeHostResult result_ = NativeHostResult::internal_error;
        std::unique_ptr<SpeechWorker> speech_worker_;
        HMODULE hook_module_ = nullptr;
        SetSpeechSinkV1Fn set_speech_sink_ = nullptr;
        std::atomic<unsigned int> fatal_notifications_{0};
    };
}
