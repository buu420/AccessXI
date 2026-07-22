#pragma once

#include "pol_native/speech_queue.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <mutex>
#include <string_view>
#include <thread>

namespace accessxi::pol_native
{
    class Diagnostics;

    class SpeechWorker
    {
    public:
        SpeechWorker(
            std::filesystem::path dependency_directory,
            Diagnostics& diagnostics,
            size_t queue_capacity = 128,
            std::chrono::milliseconds initialization_timeout = std::chrono::seconds(20),
            std::chrono::milliseconds window_wait = std::chrono::seconds(10));
        ~SpeechWorker();

        SpeechWorker(const SpeechWorker&) = delete;
        SpeechWorker& operator=(const SpeechWorker&) = delete;

        bool start() noexcept;
        bool wait_until_ready(std::chrono::milliseconds timeout) noexcept;
        bool enqueue(std::string_view utf8_text, bool interrupt) noexcept;
        void stop_for_tests() noexcept;
        SpeechQueueStats stats() const noexcept;

    private:
        enum class State
        {
            idle,
            starting,
            ready,
            failed,
            stopped
        };

        void run() noexcept;
        void set_state(State state) noexcept;

        std::filesystem::path dependency_directory_;
        Diagnostics& diagnostics_;
        SpeechQueue queue_;
        std::chrono::milliseconds initialization_timeout_;
        std::chrono::milliseconds window_wait_;
        std::atomic<bool> started_{false};
        std::atomic<bool> stopping_{false};
        mutable std::mutex state_lock_;
        std::condition_variable state_changed_;
        State state_ = State::idle;
        std::thread worker_;
    };
}
