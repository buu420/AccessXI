#pragma once

#include <atomic>

namespace accessxi::pol_native
{
    class StartupLatch
    {
    public:
        bool try_start() noexcept
        {
            bool expected = false;
            return started_.compare_exchange_strong(
                expected,
                true,
                std::memory_order_acq_rel,
                std::memory_order_acquire);
        }

    private:
        std::atomic<bool> started_{false};
    };
}
