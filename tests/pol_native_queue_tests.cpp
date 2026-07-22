#include "pol_native/speech_queue.h"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <future>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace
{
    using accessxi::pol_native::SpeechItem;
    using accessxi::pol_native::SpeechQueue;

    void require(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAIL: " << message << '\n';
            std::exit(1);
        }
    }

    SpeechItem pop_one(SpeechQueue& queue)
    {
        SpeechItem item{};
        require(queue.wait_pop(item), "queue unexpectedly stopped while popping");
        return item;
    }

    void test_fifo_order()
    {
        SpeechQueue queue(8);
        require(queue.enqueue("first", false), "first item should be accepted");
        require(queue.enqueue("second", false), "second item should be accepted");

        const SpeechItem first = pop_one(queue);
        const SpeechItem second = pop_one(queue);
        require(first.text == "first", "first FIFO item mismatch");
        require(second.text == "second", "second FIFO item mismatch");
        require(first.sequence < second.sequence, "sequence must increase");
    }

    void test_duplicate_coalescing()
    {
        SpeechQueue queue(8);
        require(queue.enqueue("Member List", true), "initial focus should be accepted");
        require(!queue.enqueue("Member List", true), "identical consecutive focus should coalesce");
        require(pop_one(queue).text == "Member List", "coalesced focus text mismatch");
        const auto stats = queue.stats();
        require(stats.accepted == 1, "coalesced item must not count as accepted");
        require(stats.deduplicated == 1, "deduplicated counter mismatch");
    }

    void test_interrupt_discards_stale_focus()
    {
        SpeechQueue queue(8);
        require(queue.enqueue("old one", false), "old one should be accepted");
        require(queue.enqueue("old two", false), "old two should be accepted");
        require(queue.enqueue("current", true), "current focus should be accepted");

        require(pop_one(queue).text == "current", "interrupt must retain newest focus");
        require(queue.stats().dropped == 2, "interrupt must count discarded stale focus");
    }

    void test_capacity_retains_newest_items()
    {
        SpeechQueue queue(128);
        for (int index = 0; index < 130; ++index)
            require(queue.enqueue("item-" + std::to_string(index), false), "unique capacity item rejected");

        require(queue.stats().dropped == 2, "capacity overflow counter mismatch");
        require(pop_one(queue).text == "item-2", "capacity overflow must remove oldest item");
        SpeechItem newest{};
        for (int index = 3; index < 130; ++index)
            newest = pop_one(queue);
        require(newest.text == "item-129", "capacity overflow must retain newest item");
    }

    void test_invalid_input_is_rejected()
    {
        SpeechQueue queue(8);
        require(!queue.enqueue("", true), "empty input must be rejected");
        require(!queue.enqueue("\r\n\t", true), "whitespace-only input must be rejected");
        const std::string invalid_utf8("\xC3\x28", 2);
        require(!queue.enqueue(invalid_utf8, true), "invalid UTF-8 must be rejected");
        require(queue.stats().accepted == 0, "invalid input must not affect accepted count");
    }

    void test_concurrent_producers_and_consumer()
    {
        SpeechQueue queue(1024);
        std::atomic<int> consumed{0};
        std::thread consumer([&] {
            SpeechItem item{};
            while (queue.wait_pop(item))
                consumed.fetch_add(1, std::memory_order_relaxed);
        });

        std::vector<std::thread> producers;
        for (int producer = 0; producer < 4; ++producer)
        {
            producers.emplace_back([&, producer] {
                for (int index = 0; index < 100; ++index)
                {
                    const std::string text = "producer-" + std::to_string(producer) + "-" + std::to_string(index);
                    require(queue.enqueue(text, false), "concurrent unique item rejected");
                }
            });
        }
        for (auto& producer : producers)
            producer.join();

        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
        while (consumed.load(std::memory_order_relaxed) != 400 && std::chrono::steady_clock::now() < deadline)
            std::this_thread::yield();
        queue.stop();
        consumer.join();

        require(consumed.load(std::memory_order_relaxed) == 400, "concurrent consumer count mismatch");
        require(queue.stats().accepted == 400, "concurrent accepted count mismatch");
    }

    void test_stop_wakes_consumer_and_rejects_input()
    {
        SpeechQueue queue(8);
        auto waiting = std::async(std::launch::async, [&] {
            SpeechItem item{};
            return queue.wait_pop(item);
        });
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        queue.stop();
        require(waiting.wait_for(std::chrono::seconds(1)) == std::future_status::ready, "stop must wake consumer");
        require(!waiting.get(), "stopped empty queue must return false");
        require(!queue.enqueue("late", true), "stopped queue must reject new input");
    }
}

int main()
{
    test_fifo_order();
    test_duplicate_coalescing();
    test_interrupt_discards_stale_focus();
    test_capacity_retains_newest_items();
    test_invalid_input_is_rejected();
    test_concurrent_producers_and_consumer();
    test_stop_wakes_consumer_and_rejects_input();
    std::cout << "ok: native speech queue ordering, bounds, interruption, UTF-8, and concurrency\n";
    return 0;
}
