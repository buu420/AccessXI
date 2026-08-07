#include "pol_native/speech_queue.h"

#include <algorithm>
#include <cctype>
#include <utility>

namespace accessxi::pol_native
{
    namespace
    {
        bool is_continuation(unsigned char value)
        {
            return (value & 0xC0u) == 0x80u;
        }

        bool valid_utf8(std::string_view text)
        {
            size_t index = 0;
            while (index < text.size())
            {
                const auto first = static_cast<unsigned char>(text[index]);
                if (first == 0)
                    return false;
                if (first <= 0x7Fu)
                {
                    ++index;
                    continue;
                }

                if (first >= 0xC2u && first <= 0xDFu)
                {
                    if (index + 1 >= text.size() ||
                        !is_continuation(static_cast<unsigned char>(text[index + 1])))
                        return false;
                    index += 2;
                    continue;
                }

                if (first >= 0xE0u && first <= 0xEFu)
                {
                    if (index + 2 >= text.size())
                        return false;
                    const auto second = static_cast<unsigned char>(text[index + 1]);
                    const auto third = static_cast<unsigned char>(text[index + 2]);
                    if (!is_continuation(second) || !is_continuation(third))
                        return false;
                    if ((first == 0xE0u && second < 0xA0u) ||
                        (first == 0xEDu && second >= 0xA0u))
                        return false;
                    index += 3;
                    continue;
                }

                if (first >= 0xF0u && first <= 0xF4u)
                {
                    if (index + 3 >= text.size())
                        return false;
                    const auto second = static_cast<unsigned char>(text[index + 1]);
                    const auto third = static_cast<unsigned char>(text[index + 2]);
                    const auto fourth = static_cast<unsigned char>(text[index + 3]);
                    if (!is_continuation(second) ||
                        !is_continuation(third) ||
                        !is_continuation(fourth))
                        return false;
                    if ((first == 0xF0u && second < 0x90u) ||
                        (first == 0xF4u && second >= 0x90u))
                        return false;
                    index += 4;
                    continue;
                }

                return false;
            }
            return true;
        }

        std::string normalize_text(std::string_view text)
        {
            std::string normalized(text);
            for (char& value : normalized)
            {
                if (value == '\r' || value == '\n')
                    value = ' ';
            }

            const auto first = std::find_if_not(
                normalized.begin(),
                normalized.end(),
                [](unsigned char value) { return std::isspace(value) != 0; });
            if (first == normalized.end())
                return {};
            const auto last = std::find_if_not(
                normalized.rbegin(),
                normalized.rend(),
                [](unsigned char value) { return std::isspace(value) != 0; }).base();
            return std::string(first, last);
        }
    }

    SpeechQueue::SpeechQueue(size_t capacity)
        : capacity_(capacity == 0 ? 1 : capacity)
    {
    }

    bool SpeechQueue::enqueue(std::string_view utf8_text, bool interrupt) noexcept
    {
        try
        {
            if (!valid_utf8(utf8_text))
                return false;

            std::string normalized = normalize_text(utf8_text);
            if (normalized.empty())
                return false;

            {
                std::lock_guard<std::mutex> guard(mutex_);
                if (stopped_)
                    return false;
                if (normalized == last_accepted_text_)
                {
                    ++stats_.deduplicated;
                    return false;
                }

                if (interrupt && !items_.empty())
                {
                    stats_.dropped += static_cast<uint64_t>(items_.size());
                    items_.clear();
                }
                while (items_.size() >= capacity_)
                {
                    items_.pop_front();
                    ++stats_.dropped;
                }

                SpeechItem item{};
                item.text = std::move(normalized);
                item.interrupt = interrupt;
                item.sequence = next_sequence_++;
                last_accepted_text_ = item.text;
                items_.push_back(std::move(item));
                ++stats_.accepted;
            }
            available_.notify_one();
            return true;
        }
        catch (...)
        {
            return false;
        }
    }

    bool SpeechQueue::wait_pop(SpeechItem& item)
    {
        std::unique_lock<std::mutex> lock(mutex_);
        available_.wait(lock, [this] { return stopped_ || !items_.empty(); });
        if (items_.empty())
            return false;

        item = std::move(items_.front());
        items_.pop_front();
        return true;
    }

    void SpeechQueue::stop() noexcept
    {
        {
            std::lock_guard<std::mutex> guard(mutex_);
            stopped_ = true;
        }
        available_.notify_all();
    }

    SpeechQueueStats SpeechQueue::stats() const noexcept
    {
        std::lock_guard<std::mutex> guard(mutex_);
        return stats_;
    }
}
