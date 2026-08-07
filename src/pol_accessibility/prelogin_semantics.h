#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <string_view>

namespace accessxi::pol_accessibility
{
    inline constexpr size_t InvalidMaskedCount = std::numeric_limits<size_t>::max();

    enum class ControlRole : uint8_t
    {
        unknown,
        member_list,
        selected_member,
        list_row,
        button,
        static_label,
        editable,
        password,
        one_time_password
    };

    struct MemberEvidence
    {
        std::string_view text;
        bool member_list_focused = false;
        bool selected_index_resolved = false;
        bool exact_selected_child = false;
        bool text_owned_by_selected_child = false;
    };

    struct MemberDecision
    {
        bool trusted = false;
        std::string text;
        const char* reason = "unknown";
    };

    struct FocusedMemberRowEvidence
    {
        int16_t pointer_hit_row = -1;
        int16_t keyboard_selected_row = -1;
        int16_t focus_anchor_row = -1;
    };

    struct FocusedMemberRowDecision
    {
        bool resolved = false;
        uint32_t row = 0;
        const char* reason = "unknown";
    };

    enum class TrackedNativeValueUpdate : uint8_t
    {
        rejected,
        focus,
        unchanged,
        changed
    };

    struct TrackedNativeValueState
    {
        uintptr_t object = 0;
        size_t value = InvalidMaskedCount;
    };

    MemberDecision decide_member_candidate(const MemberEvidence& evidence);
    FocusedMemberRowDecision decide_focused_member_row(
        const FocusedMemberRowEvidence& evidence) noexcept;
    bool focused_member_row_still_selected(
        uint32_t resolved_row,
        int16_t observed_keyboard_selected_row) noexcept;
    bool exact_owned_member_name_allowed(std::string_view text) noexcept;
    std::string_view add_member_set_password_value(
        uint32_t selected_index) noexcept;
    std::string field_focus_speech(
        std::string_view label,
        std::string_view value);
    size_t masked_display_count(std::u16string_view displayed) noexcept;
    std::string masked_focus_speech(ControlRole role, size_t count);
    std::string masked_focus_speech(
        std::string_view label,
        size_t count);
    std::string masked_delta_speech(ControlRole role, size_t before, size_t after);
    std::string masked_delta_speech(
        std::string_view label,
        size_t before,
        size_t after);
    TrackedNativeValueUpdate observe_tracked_native_value(
        TrackedNativeValueState& state,
        uintptr_t object,
        size_t value) noexcept;
    void reset_tracked_native_value(
        TrackedNativeValueState& state) noexcept;
}
