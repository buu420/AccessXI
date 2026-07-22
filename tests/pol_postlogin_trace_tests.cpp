#include "pol_trace/postlogin_trace.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace
{
    using namespace accessxi::pol_trace;

    void require(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAIL: " << message << '\n';
            std::exit(1);
        }
    }

    Snapshot event(EventKind kind, uint32_t tick, uintptr_t object, const char* label)
    {
        Snapshot value{};
        value.kind = kind;
        value.tick = tick;
        value.manager = 0x1000;
        value.object = object;
        value.requested_index = 2;
        value.stored_index = 2;
        value.trusted = true;
        copy_utf8_bounded(value.resolver_text, sizeof(value.resolver_text), label);
        return value;
    }

    void test_fifo_and_sequences()
    {
        TraceBuffer queue(4);
        require(queue.enqueue(event(EventKind::focus_shared, 10, 0x2000, "First")) == EnqueueResult::queued, "first event rejected");
        require(queue.enqueue(event(EventKind::focus_select, 20, 0x3000, "Second")) == EnqueueResult::queued, "second event rejected");
        Snapshot first{};
        Snapshot second{};
        require(queue.try_dequeue(first) && queue.try_dequeue(second), "queued events missing");
        require(first.sequence == 1 && second.sequence == 2, "sequence mismatch");
        require(first.object == 0x2000 && second.object == 0x3000, "FIFO mismatch");
    }

    void test_duplicate_window()
    {
        TraceBuffer queue(4);
        require(queue.enqueue(event(EventKind::selected_index, 100, 0x2000, "Row")) == EnqueueResult::queued, "initial event rejected");
        require(queue.enqueue(event(EventKind::selected_index, 149, 0x2000, "Row")) == EnqueueResult::duplicate, "49 ms duplicate not coalesced");
        require(queue.enqueue(event(EventKind::selected_index, 151, 0x2000, "Row")) == EnqueueResult::queued, "51 ms event incorrectly coalesced");
    }

    void test_capacity_drops_new_event_without_blocking()
    {
        TraceBuffer queue(2);
        require(queue.enqueue(event(EventKind::current_child, 1, 1, "A")) == EnqueueResult::queued, "A rejected");
        require(queue.enqueue(event(EventKind::current_child, 2, 2, "B")) == EnqueueResult::queued, "B rejected");
        require(queue.enqueue(event(EventKind::current_child, 3, 3, "C")) == EnqueueResult::full, "overflow not reported");
        require(queue.take_dropped_count() == 1, "drop count mismatch");
        require(queue.take_dropped_count() == 0, "drop count did not reset");
    }

    void test_utf8_truncation_preserves_code_points()
    {
        char output[5]{};
        copy_utf8_bounded(output, sizeof(output), "A\xE2\x82\xAC" "B");
        require(std::string(output) == "A\xE2\x82\xAC", "UTF-8 truncation split a code point");
    }

    void test_tsv_escaping_and_schema()
    {
        Snapshot value = event(EventKind::focus_select, 55, 0x2000, "A\tB\nC\\D");
        value.has_rect = true;
        value.rect = {1, 2, 3, 4};
        const std::string line = format_event(value);
        require(line.find("focus-select") != std::string::npos, "event kind missing");
        require(line.find("A\\tB\\nC\\\\D") != std::string::npos, "TSV escaping mismatch");
        require(line.find("1,2,3,4") != std::string::npos, "rectangle missing");
        require(format_schema(4335104, 0x07E88E8067FEF6CCull).find("07E88E8067FEF6CC") != std::string::npos, "fingerprint missing");
    }

    void test_reset_starts_new_sequence()
    {
        TraceBuffer queue(4);
        require(queue.enqueue(event(EventKind::focus_shared, 1, 1, "A")) == EnqueueResult::queued, "event rejected");
        queue.reset();
        require(queue.enqueue(event(EventKind::focus_shared, 2, 2, "B")) == EnqueueResult::queued, "post-reset event rejected");
        Snapshot value{};
        require(queue.try_dequeue(value) && value.sequence == 1, "reset did not restart sequence");
    }
}

int main()
{
    test_fifo_and_sequences();
    test_duplicate_window();
    test_capacity_drops_new_event_without_blocking();
    test_utf8_truncation_preserves_code_points();
    test_tsv_escaping_and_schema();
    test_reset_starts_new_sequence();
    std::cout << "ok: post-login PML trace bounds, ordering, dedupe, UTF-8, and TSV formatting\n";
    return 0;
}
