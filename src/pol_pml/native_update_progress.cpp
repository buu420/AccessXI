#include "pol_pml/native_update_progress.h"

#include <algorithm>
#include <array>
#include <limits>

namespace accessxi::pol_pml
{
    namespace
    {
        constexpr uintptr_t MinimumObjectAddress = 0x10000u;
        constexpr size_t MaximumProgressCharacters = 512;
        constexpr uint32_t RoutineSpeechFloorMs = 5000;
        constexpr uint32_t ProgressHeartbeatMs = 60000;

        constexpr std::array<uint32_t, UpdateProgressFieldCount> OwnerSlots{
            0x2ACu, 0x2B0u, 0x2B4u, 0x2B8u, 0x2BCu, 0x2C0u,
            0x2C4u, 0x2C8u, 0x2CCu, 0x2D0u
        };

        enum class ComponentVisibility : uint8_t
        {
            unknown,
            hidden,
            visible
        };

        enum class LabelState : uint8_t
        {
            unknown,
            absent,
            present
        };

        struct LabelSnapshot
        {
            LabelState state = LabelState::unknown;
            std::u16string text;
        };

        bool address_range_fits(uintptr_t address, size_t size) noexcept
        {
            return size != 0 &&
                size - 1 <= std::numeric_limits<uintptr_t>::max() - address;
        }

        bool add_address(
            uintptr_t base,
            uintptr_t offset,
            uintptr_t& result) noexcept
        {
            if (offset > std::numeric_limits<uintptr_t>::max() - base)
                return false;
            result = base + offset;
            return true;
        }

        template<typename T>
        bool read_value(
            const MemoryView& memory,
            uintptr_t address,
            T& value) noexcept
        {
            return memory.read != nullptr &&
                address_range_fits(address, sizeof(value)) &&
                memory.read(memory.context, address, &value, sizeof(value));
        }

        ComponentVisibility component_visibility(
            const MemoryView& memory,
            uintptr_t object) noexcept
        {
            uintptr_t flags_field = 0;
            uint8_t flags = 0;
            if (!add_address(object, 0x18, flags_field) ||
                !read_value(memory, flags_field, flags))
            {
                return ComponentVisibility::unknown;
            }
            return (flags & 0x0C) == 0x0C
                ? ComponentVisibility::visible
                : ComponentVisibility::hidden;
        }

        bool append_normalized_character(
            std::u16string& output,
            char16_t character,
            bool& saw_visible) noexcept
        {
            const bool whitespace =
                character == u' ' || character == u'\t' ||
                character == u'\r' || character == u'\n' ||
                character == u'\v' || character == u'\f' ||
                character == 0x00A0;
            if (whitespace)
            {
                if (!output.empty() && output.back() != u' ')
                    output.push_back(u' ');
                return true;
            }
            if (character < 0x20 ||
                (character >= 0x7F && character <= 0x9F))
            {
                return false;
            }
            output.push_back(character);
            saw_visible = true;
            return true;
        }

        LabelSnapshot read_exact_label(
            const MemoryView& memory,
            uintptr_t label,
            uintptr_t app_base) noexcept
        {
            LabelSnapshot result;
            if (label == 0)
            {
                result.state = LabelState::absent;
                return result;
            }
            if (label < MinimumObjectAddress ||
                app_base < MinimumObjectAddress)
            {
                return result;
            }

            uintptr_t vtable = 0;
            if (!read_value(memory, label, vtable) ||
                vtable < app_base ||
                vtable - app_base != CLabelVtableRva)
            {
                return result;
            }

            const ComponentVisibility visibility =
                component_visibility(memory, label);
            if (visibility == ComponentVisibility::unknown)
                return result;
            if (visibility == ComponentVisibility::hidden)
            {
                result.state = LabelState::absent;
                return result;
            }

            uintptr_t begin_field = 0;
            uintptr_t end_field = 0;
            uintptr_t length_field = 0;
            if (!add_address(label, 0x184, begin_field) ||
                !add_address(label, 0x188, end_field) ||
                !add_address(label, 0x21A, length_field))
            {
                return result;
            }

            uintptr_t begin = 0;
            uintptr_t end = 0;
            int16_t length = 0;
            if (!read_value(memory, begin_field, begin) ||
                !read_value(memory, end_field, end) ||
                !read_value(memory, length_field, length))
            {
                return result;
            }
            if (length == 0)
            {
                result.state = LabelState::absent;
                return result;
            }
            if (begin < MinimumObjectAddress || end < begin || length < 0 ||
                static_cast<size_t>(length) > MaximumProgressCharacters)
            {
                return result;
            }

            const uintptr_t byte_count = end - begin;
            const size_t required_bytes =
                (static_cast<size_t>(length) + 1) * sizeof(char16_t);
            if ((byte_count & 1u) != 0 ||
                byte_count < required_bytes ||
                !address_range_fits(begin, required_bytes))
            {
                return result;
            }

            std::array<char16_t, MaximumProgressCharacters + 1> characters{};
            if (!memory.read(
                    memory.context,
                    begin,
                    characters.data(),
                    required_bytes) ||
                characters[static_cast<size_t>(length)] != u'\0')
            {
                return result;
            }

            std::u16string normalized;
            normalized.reserve(static_cast<size_t>(length));
            bool saw_visible = false;
            for (size_t index = 0; index < static_cast<size_t>(length); ++index)
            {
                const char16_t character = characters[index];
                if (character == u'\0')
                    return result;
                if (character >= 0xD800 && character <= 0xDBFF)
                {
                    if (index + 1 >= static_cast<size_t>(length) ||
                        characters[index + 1] < 0xDC00 ||
                        characters[index + 1] > 0xDFFF)
                    {
                        return result;
                    }
                    normalized.push_back(character);
                    normalized.push_back(characters[++index]);
                    saw_visible = true;
                    continue;
                }
                if (character >= 0xDC00 && character <= 0xDFFF)
                    return result;
                if (!append_normalized_character(
                        normalized,
                        character,
                        saw_visible))
                {
                    return result;
                }
            }
            while (!normalized.empty() && normalized.back() == u' ')
                normalized.pop_back();
            if (!saw_visible)
            {
                result.state = LabelState::absent;
                return result;
            }

            result.state = LabelState::present;
            result.text = std::move(normalized);
            return result;
        }

        bool equal_snapshots(
            const UpdateProgressSnapshot& left,
            const UpdateProgressSnapshot& right) noexcept
        {
            return left.state == right.state && left.fields == right.fields;
        }

        const std::u16string& field(
            const UpdateProgressSnapshot& snapshot,
            UpdateProgressField selected) noexcept
        {
            return snapshot.fields[static_cast<size_t>(selected)];
        }

        void append_unique(
            std::u16string& output,
            const std::u16string& part)
        {
            if (part.empty())
                return;
            if (output.find(part) != std::u16string::npos)
                return;
            if (!output.empty())
                output += u". ";
            output += part;
        }

        int percent_value(const std::u16string& text) noexcept
        {
            const size_t marker = text.find(u'%');
            if (marker == std::u16string::npos || marker == 0)
                return -1;
            size_t begin = marker;
            while (begin > 0 && text[begin - 1] >= u'0' && text[begin - 1] <= u'9')
                --begin;
            if (begin == marker)
                return -1;
            int value = 0;
            for (size_t index = begin; index < marker; ++index)
            {
                value = value * 10 + static_cast<int>(text[index] - u'0');
                if (value > 100)
                    return -1;
            }
            return value;
        }

        const std::u16string& progress_percent_text(
            const UpdateProgressSnapshot& snapshot) noexcept
        {
            const auto& overall = field(
                snapshot,
                UpdateProgressField::overall_percent);
            if (percent_value(overall) >= 0)
                return overall;
            return field(
                snapshot,
                UpdateProgressField::preparing_or_apply_percent);
        }

        std::u16string stage_key(const UpdateProgressSnapshot& snapshot)
        {
            std::u16string result;
            append_unique(result, field(snapshot, UpdateProgressField::title));
            append_unique(result, field(snapshot, UpdateProgressField::stage));
            return result;
        }

        std::u16string full_announcement(
            const UpdateProgressSnapshot& snapshot)
        {
            std::u16string result = u"Version update";
            append_unique(result, field(snapshot, UpdateProgressField::title));
            append_unique(result, field(snapshot, UpdateProgressField::stage));
            append_unique(result, progress_percent_text(snapshot));
            append_unique(result, field(snapshot, UpdateProgressField::bytes_or_files_status));
            append_unique(result, field(snapshot, UpdateProgressField::files_remaining));
            append_unique(result, field(snapshot, UpdateProgressField::current_status));
            append_unique(result, field(snapshot, UpdateProgressField::current_file));
            append_unique(result, field(snapshot, UpdateProgressField::current_file_percent));
            append_unique(result, field(snapshot, UpdateProgressField::time_remaining));
            return result;
        }

        std::u16string routine_announcement(
            const UpdateProgressSnapshot& snapshot)
        {
            std::u16string result = u"Version update";
            append_unique(result, progress_percent_text(snapshot));
            append_unique(result, field(snapshot, UpdateProgressField::bytes_or_files_status));
            append_unique(result, field(snapshot, UpdateProgressField::files_remaining));
            append_unique(result, field(snapshot, UpdateProgressField::time_remaining));
            return result;
        }
    }

    UpdateProgressSnapshot inspect_update_progress(
        const MemoryView& memory,
        uintptr_t owner,
        uintptr_t app_base) noexcept
    {
        UpdateProgressSnapshot result;
        if (owner == 0)
        {
            result.state = UpdateProgressInspectionState::absent;
            return result;
        }
        if (owner < MinimumObjectAddress || app_base < MinimumObjectAddress)
            return result;

        uintptr_t vtable = 0;
        if (!read_value(memory, owner, vtable))
            return result;
        if (vtable < app_base ||
            vtable - app_base != UpgradeProgressWindowVtableRva)
        {
            result.state = UpdateProgressInspectionState::absent;
            return result;
        }

        const ComponentVisibility visibility =
            component_visibility(memory, owner);
        if (visibility == ComponentVisibility::unknown)
            return result;
        if (visibility == ComponentVisibility::hidden)
        {
            result.state = UpdateProgressInspectionState::absent;
            return result;
        }

        bool found_text = false;
        for (size_t index = 0; index < OwnerSlots.size(); ++index)
        {
            uintptr_t child_field = 0;
            uintptr_t child = 0;
            if (!add_address(owner, OwnerSlots[index], child_field) ||
                !read_value(memory, child_field, child))
            {
                return result;
            }
            const LabelSnapshot label =
                read_exact_label(memory, child, app_base);
            if (label.state == LabelState::unknown)
                return result;
            if (label.state == LabelState::present)
            {
                result.fields[index] = label.text;
                found_text = true;
            }
        }
        if (!found_text)
        {
            result.state = UpdateProgressInspectionState::absent;
            return result;
        }
        result.state = UpdateProgressInspectionState::present;
        return result;
    }

    UpdateProgressAnnouncement UpdateProgressTracker::observe(
        const UpdateProgressSnapshot& snapshot,
        uint32_t tick)
    {
        if (snapshot.state == UpdateProgressInspectionState::absent)
        {
            reset();
            return {};
        }
        if (snapshot.state != UpdateProgressInspectionState::present)
            return {};

        if (!equal_snapshots(candidate_, snapshot))
        {
            candidate_ = snapshot;
            stable_reads_ = 1;
            return {};
        }
        if (stable_reads_ < 2)
            ++stable_reads_;
        if (stable_reads_ < 2)
            return {};

        const std::u16string current_stage_key = stage_key(snapshot);
        const std::u16string& percent_text = progress_percent_text(snapshot);
        const int percent = percent_value(percent_text);
        const int percent_bucket = percent >= 0 ? percent / 5 : -1;

        if (!active_)
        {
            active_ = true;
            last_spoken_percent_bucket_ = percent_bucket;
            last_spoken_tick_ = tick;
            last_stage_key_ = current_stage_key;
            last_spoken_text_ = full_announcement(snapshot);
            return { UpdateProgressSpeechMode::interrupt, last_spoken_text_ };
        }

        const bool phase_changed = current_stage_key != last_stage_key_;
        const bool complete = percent >= 100 && last_spoken_percent_bucket_ < 20;
        const bool milestone =
            percent_bucket >= 0 && percent_bucket > last_spoken_percent_bucket_;
        const uint32_t elapsed = tick - last_spoken_tick_;
        const bool heartbeat = elapsed >= ProgressHeartbeatMs;

        if (!phase_changed && !complete &&
            !(milestone && elapsed >= RoutineSpeechFloorMs) && !heartbeat)
        {
            return {};
        }

        const bool urgent = phase_changed || complete;
        std::u16string announcement = urgent
            ? full_announcement(snapshot)
            : routine_announcement(snapshot);
        if (announcement.empty())
            return {};

        last_spoken_percent_bucket_ = percent_bucket;
        last_spoken_tick_ = tick;
        last_stage_key_ = current_stage_key;
        last_spoken_text_ = announcement;
        return {
            urgent
                ? UpdateProgressSpeechMode::interrupt
                : UpdateProgressSpeechMode::queued,
            std::move(announcement)
        };
    }

    void UpdateProgressTracker::reset() noexcept
    {
        candidate_ = {};
        stable_reads_ = 0;
        active_ = false;
        last_spoken_percent_bucket_ = -1;
        last_spoken_tick_ = 0;
        last_stage_key_.clear();
        last_spoken_text_.clear();
    }
}
