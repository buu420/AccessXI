#pragma once

#include "pol_pml/native_popup_text.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace accessxi::pol_pml
{
    constexpr uintptr_t UpgradeProgressWindowVtableRva = 0x003D1DB4u;

    enum class UpdateProgressInspectionState : uint8_t
    {
        unknown,
        absent,
        present
    };

    enum class UpdateProgressField : uint8_t
    {
        stage,
        bytes_or_files_status,
        current_status,
        time_remaining,
        preparing_or_apply_percent,
        overall_percent,
        title,
        files_remaining,
        current_file,
        current_file_percent,
        count
    };

    constexpr size_t UpdateProgressFieldCount =
        static_cast<size_t>(UpdateProgressField::count);

    struct UpdateProgressSnapshot
    {
        UpdateProgressInspectionState state =
            UpdateProgressInspectionState::unknown;
        std::array<std::u16string, UpdateProgressFieldCount> fields{};
    };

    UpdateProgressSnapshot inspect_update_progress(
        const MemoryView& memory,
        uintptr_t owner,
        uintptr_t app_base) noexcept;

    enum class UpdateProgressSpeechMode : uint8_t
    {
        none,
        queued,
        interrupt
    };

    struct UpdateProgressAnnouncement
    {
        UpdateProgressSpeechMode mode = UpdateProgressSpeechMode::none;
        std::u16string text;
    };

    class UpdateProgressTracker
    {
    public:
        UpdateProgressAnnouncement observe(
            const UpdateProgressSnapshot& snapshot,
            uint32_t tick);
        void reset() noexcept;

    private:
        UpdateProgressSnapshot candidate_{};
        uint8_t stable_reads_ = 0;
        bool active_ = false;
        int last_spoken_percent_bucket_ = -1;
        uint32_t last_spoken_tick_ = 0;
        std::u16string last_stage_key_;
        std::u16string last_spoken_text_;
    };
}
