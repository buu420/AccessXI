#include "pol_trace/postlogin_trace.h"

#include <algorithm>
#include <cstring>
#include <iomanip>
#include <sstream>

namespace accessxi::pol_trace
{
    namespace
    {
        bool is_utf8_continuation(unsigned char byte) noexcept
        {
            return (byte & 0xC0u) == 0x80u;
        }

        std::string hex_value(uint64_t value, size_t width)
        {
            std::ostringstream output;
            output << std::uppercase << std::hex << std::setfill('0') << std::setw(static_cast<int>(width)) << value;
            return output.str();
        }

        bool same_text(const char* left, const char* right) noexcept
        {
            return std::strncmp(left, right, TraceTextCapacity) == 0;
        }
    }

    void copy_utf8_bounded(char* destination, size_t capacity, std::string_view value)
    {
        if (destination == nullptr || capacity == 0)
            return;

        destination[0] = 0;
        if (value.empty() || capacity == 1)
            return;

        size_t count = std::min(value.size(), capacity - 1);
        if (count < value.size() && is_utf8_continuation(static_cast<unsigned char>(value[count])))
        {
            while (count > 0 && is_utf8_continuation(static_cast<unsigned char>(value[count])))
                --count;
        }

        if (count > 0)
            std::memcpy(destination, value.data(), count);
        destination[count] = 0;
    }

    const char* event_kind_name(EventKind kind) noexcept
    {
        switch (kind)
        {
        case EventKind::focus_shared:
            return "focus-shared";
        case EventKind::focus_select:
            return "focus-select";
        case EventKind::current_child:
            return "current-child";
        case EventKind::selected_index:
            return "selected-index";
        }
        return "unknown";
    }

    std::string escape_tsv(std::string_view value)
    {
        std::string output;
        output.reserve(value.size());
        for (const unsigned char byte : value)
        {
            switch (byte)
            {
            case '\\':
                output += "\\\\";
                break;
            case '\t':
                output += "\\t";
                break;
            case '\r':
                output += "\\r";
                break;
            case '\n':
                output += "\\n";
                break;
            default:
                if (byte < 0x20u || byte == 0x7Fu)
                {
                    output += "\\x";
                    output += hex_value(byte, 2);
                }
                else
                {
                    output.push_back(static_cast<char>(byte));
                }
                break;
            }
        }
        return output;
    }

    std::string format_schema(uint64_t app_size, uint64_t app_fnv64)
    {
        return "SCHEMA\tversion=1\tapp_size=" + std::to_string(app_size) + "\tapp_fnv64=" + hex_value(app_fnv64, 16);
    }

    std::string format_session(std::string_view action, uint64_t session, uint32_t tick, std::string_view reason)
    {
        return "SESSION\taction=" + escape_tsv(action) +
            "\tsession=" + std::to_string(session) +
            "\ttick=" + std::to_string(tick) +
            "\treason=" + escape_tsv(reason);
    }

    std::string format_event(const Snapshot& value)
    {
        const size_t pointer_width = sizeof(uintptr_t) * 2;
        std::ostringstream output;
        output << "EVENT"
               << "\tsequence=" << value.sequence
               << "\ttick=" << value.tick
               << "\tkind=" << event_kind_name(value.kind)
               << "\tevent_code=" << hex_value(value.event_code, 8)
               << "\tmanager=" << hex_value(value.manager, pointer_width)
               << "\trequested_child=" << hex_value(value.requested_child, pointer_width)
               << "\tobject=" << hex_value(value.object, pointer_width)
               << "\trequested_index=" << value.requested_index
               << "\tstored_index=" << value.stored_index
               << "\tfocus160=" << hex_value(value.focus_160, pointer_width)
               << "\tfocus164=" << hex_value(value.focus_164, pointer_width)
               << "\tfocus1c0=" << hex_value(value.focus_1c0, pointer_width)
               << "\tvtable=" << hex_value(value.vtable, pointer_width)
               << "\tvtable_rva=" << hex_value(value.vtable_rva, pointer_width)
               << "\trect=";

        if (value.has_rect)
        {
            output << value.rect.left << ',' << value.rect.top << ',' << value.rect.right << ',' << value.rect.bottom;
        }
        else
        {
            output << "none";
        }

        output << "\ttrusted=" << (value.trusted ? 1 : 0)
               << "\tredacted=" << (value.redacted ? 1 : 0)
               << "\tresolver=" << escape_tsv(value.resolver_text);

        const size_t candidate_count = std::min<size_t>(value.candidate_count, TraceCandidateCapacity);
        for (size_t index = 0; index < candidate_count; ++index)
        {
            const Candidate& candidate = value.candidates[index];
            output << "\tcandidate="
                   << hex_value(candidate.offset, 3) << ':'
                   << escape_tsv(candidate.source) << ':'
                   << escape_tsv(candidate.text);
        }
        return output.str();
    }

    std::string format_dropped(uint64_t count)
    {
        return "DROPPED\tcount=" + std::to_string(count);
    }

    TraceBuffer::TraceBuffer(size_t capacity)
        : storage_(std::max<size_t>(capacity, 1))
    {
    }

    bool TraceBuffer::duplicate_locked(const Snapshot& value) const noexcept
    {
        if (!have_last_)
            return false;
        if (static_cast<uint32_t>(value.tick - last_.tick) > 50u)
            return false;
        return value.kind == last_.kind &&
            value.manager == last_.manager &&
            value.object == last_.object &&
            value.requested_index == last_.requested_index &&
            value.stored_index == last_.stored_index &&
            value.trusted == last_.trusted &&
            same_text(value.resolver_text, last_.resolver_text);
    }

    EnqueueResult TraceBuffer::enqueue(Snapshot value)
    {
        std::unique_lock<std::mutex> guard(mutex_, std::try_to_lock);
        if (!guard.owns_lock())
        {
            dropped_.fetch_add(1, std::memory_order_relaxed);
            return EnqueueResult::full;
        }

        if (duplicate_locked(value))
            return EnqueueResult::duplicate;

        if (size_ == storage_.size())
        {
            dropped_.fetch_add(1, std::memory_order_relaxed);
            return EnqueueResult::full;
        }

        value.sequence = ++next_sequence_;
        storage_[tail_] = value;
        tail_ = (tail_ + 1) % storage_.size();
        ++size_;
        last_ = value;
        have_last_ = true;
        return EnqueueResult::queued;
    }

    bool TraceBuffer::try_dequeue(Snapshot& value)
    {
        std::lock_guard<std::mutex> guard(mutex_);
        if (size_ == 0)
            return false;

        value = storage_[head_];
        head_ = (head_ + 1) % storage_.size();
        --size_;
        return true;
    }

    uint64_t TraceBuffer::take_dropped_count() noexcept
    {
        return dropped_.exchange(0, std::memory_order_acq_rel);
    }

    void TraceBuffer::reset()
    {
        std::lock_guard<std::mutex> guard(mutex_);
        head_ = 0;
        tail_ = 0;
        size_ = 0;
        next_sequence_ = 0;
        have_last_ = false;
        last_ = {};
        dropped_.store(0, std::memory_order_release);
    }
}
