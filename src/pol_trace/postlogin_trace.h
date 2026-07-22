#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace accessxi::pol_trace
{
    constexpr size_t TraceTextCapacity = 241;
    constexpr size_t TraceSourceCapacity = 32;
    constexpr size_t TraceCandidateCapacity = 24;

    enum class EventKind : uint8_t
    {
        focus_shared,
        focus_select,
        current_child,
        selected_index
    };

    enum class EnqueueResult : uint8_t
    {
        queued,
        duplicate,
        full
    };

    struct Rect
    {
        int32_t left = 0;
        int32_t top = 0;
        int32_t right = 0;
        int32_t bottom = 0;
    };

    struct Candidate
    {
        uint32_t offset = 0;
        char source[TraceSourceCapacity]{};
        char text[TraceTextCapacity]{};
    };

    struct Snapshot
    {
        uint64_t sequence = 0;
        uint32_t tick = 0;
        EventKind kind = EventKind::focus_shared;
        uint32_t event_code = 0;
        uintptr_t manager = 0;
        uintptr_t requested_child = 0;
        uintptr_t object = 0;
        uint32_t requested_index = 0;
        uint32_t stored_index = 0;
        uintptr_t focus_160 = 0;
        uintptr_t focus_164 = 0;
        uintptr_t focus_1c0 = 0;
        uintptr_t vtable = 0;
        uintptr_t vtable_rva = 0;
        Rect rect{};
        bool has_rect = false;
        bool trusted = false;
        bool redacted = false;
        char resolver_text[TraceTextCapacity]{};
        uint8_t candidate_count = 0;
        Candidate candidates[TraceCandidateCapacity]{};
    };

    void copy_utf8_bounded(char* destination, size_t capacity, std::string_view value);
    const char* event_kind_name(EventKind kind) noexcept;
    std::string escape_tsv(std::string_view value);
    std::string format_schema(uint64_t app_size, uint64_t app_fnv64);
    std::string format_session(std::string_view action, uint64_t session, uint32_t tick, std::string_view reason);
    std::string format_event(const Snapshot& value);
    std::string format_dropped(uint64_t count);

    class TraceBuffer
    {
    public:
        explicit TraceBuffer(size_t capacity);

        TraceBuffer(const TraceBuffer&) = delete;
        TraceBuffer& operator=(const TraceBuffer&) = delete;

        EnqueueResult enqueue(Snapshot value);
        bool try_dequeue(Snapshot& value);
        uint64_t take_dropped_count() noexcept;
        void reset();

    private:
        bool duplicate_locked(const Snapshot& value) const noexcept;

        std::mutex mutex_;
        std::vector<Snapshot> storage_;
        size_t head_ = 0;
        size_t tail_ = 0;
        size_t size_ = 0;
        uint64_t next_sequence_ = 0;
        bool have_last_ = false;
        Snapshot last_{};
        std::atomic<uint64_t> dropped_{0};
    };
}
