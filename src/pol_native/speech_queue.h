#pragma once

#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <string_view>

namespace accessxi::pol_native
{
    struct SpeechItem
    {
        std::string text;
        bool interrupt = false;
        uint64_t sequence = 0;
    };

    struct SpeechQueueStats
    {
        uint64_t accepted = 0;
        uint64_t deduplicated = 0;
        uint64_t dropped = 0;
    };

    class SpeechQueue
    {
    public:
        explicit SpeechQueue(size_t capacity = 128);

        SpeechQueue(const SpeechQueue&) = delete;
        SpeechQueue& operator=(const SpeechQueue&) = delete;

        bool enqueue(std::string_view utf8_text, bool interrupt) noexcept;
        bool wait_pop(SpeechItem& item);
        void stop() noexcept;
        SpeechQueueStats stats() const noexcept;

    private:
        const size_t capacity_;
        mutable std::mutex mutex_;
        std::condition_variable available_;
        std::deque<SpeechItem> items_;
        std::string last_accepted_text_;
        uint64_t next_sequence_ = 1;
        SpeechQueueStats stats_{};
        bool stopped_ = false;
    };
}
