#include "pol_native/speech_worker.h"

#include "pol_native/diagnostics.h"
#include "pol_native/prism_runtime.h"

#include <chrono>
#include <filesystem>
#include <string>
#include <thread>

namespace accessxi::pol_native
{
    SpeechWorker::SpeechWorker(
        std::filesystem::path dependency_directory,
        Diagnostics& diagnostics,
        size_t queue_capacity,
        std::chrono::milliseconds initialization_timeout,
        std::chrono::milliseconds window_wait)
        : dependency_directory_(std::move(dependency_directory)),
          diagnostics_(diagnostics),
          queue_(queue_capacity),
          initialization_timeout_(initialization_timeout),
          window_wait_(window_wait)
    {
    }

    SpeechWorker::~SpeechWorker()
    {
        stop_for_tests();
    }

    bool SpeechWorker::start() noexcept
    {
        bool expected = false;
        if (!started_.compare_exchange_strong(expected, true))
            return false;

        try
        {
            set_state(State::starting);
            worker_ = std::thread([this] { run(); });
            return true;
        }
        catch (...)
        {
            set_state(State::failed);
            return false;
        }
    }

    bool SpeechWorker::wait_until_ready(std::chrono::milliseconds timeout) noexcept
    {
        try
        {
            std::unique_lock<std::mutex> lock(state_lock_);
            state_changed_.wait_for(lock, timeout, [this] {
                return state_ == State::ready || state_ == State::failed || state_ == State::stopped;
            });
            return state_ == State::ready;
        }
        catch (...)
        {
            return false;
        }
    }

    bool SpeechWorker::enqueue(std::string_view utf8_text, bool interrupt) noexcept
    {
        return queue_.enqueue(utf8_text, interrupt);
    }

    void SpeechWorker::stop_for_tests() noexcept
    {
        stopping_.store(true, std::memory_order_release);
        queue_.stop();
        try
        {
            if (worker_.joinable() && worker_.get_id() != std::this_thread::get_id())
                worker_.join();
        }
        catch (...)
        {
        }
    }

    SpeechQueueStats SpeechWorker::stats() const noexcept
    {
        return queue_.stats();
    }

    void SpeechWorker::run() noexcept
    {
        diagnostics_.startup("ACCESSXI_POL_NATIVE worker-start");
        PrismRuntime runtime(diagnostics_);
        const std::filesystem::path prism_path = dependency_directory_ / L"prism.dll";
        if (!runtime.load(prism_path))
        {
            set_state(State::failed);
            return;
        }

        const auto initialization_deadline = std::chrono::steady_clock::now() + initialization_timeout_;
        while (!stopping_.load(std::memory_order_acquire) &&
               std::chrono::steady_clock::now() < initialization_deadline)
        {
            if (runtime.initialize(window_wait_))
                break;
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

        if (!runtime.ready())
        {
            diagnostics_.startup("ACCESSXI_POL_NATIVE prism-initialize-timeout");
            set_state(State::failed);
            return;
        }

        set_state(State::ready);
        SpeechItem item{};
        while (queue_.wait_pop(item))
        {
            int result = runtime.output(item.text.c_str(), item.interrupt);
            if (result != 0)
            {
                diagnostics_.speech(
                    "ACCESSXI_POL_NATIVE output-failed sequence=" +
                    std::to_string(item.sequence) +
                    " result=" +
                    std::to_string(result) +
                    " retry=1");
                runtime.reset();
                if (runtime.initialize(window_wait_))
                    result = runtime.output(item.text.c_str(), item.interrupt);
            }

            if (result == 0)
            {
                diagnostics_.speech(
                    "ACCESSXI_POL_NATIVE output-ok sequence=" +
                    std::to_string(item.sequence) +
                    " interrupt=" +
                    (item.interrupt ? "1" : "0"));
            }
            else
            {
                diagnostics_.speech(
                    "ACCESSXI_POL_NATIVE output-dropped sequence=" +
                    std::to_string(item.sequence) +
                    " result=" +
                    std::to_string(result));
            }
        }

        set_state(State::stopped);
    }

    void SpeechWorker::set_state(State state) noexcept
    {
        try
        {
            {
                std::lock_guard<std::mutex> guard(state_lock_);
                state_ = state;
            }
            state_changed_.notify_all();
        }
        catch (...)
        {
        }
    }
}
