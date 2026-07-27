#include "pol_accessibility/prelogin_semantics.h"

namespace accessxi::pol_accessibility
{
    namespace
    {
        const char* masked_role_label(ControlRole role) noexcept
        {
            switch (role)
            {
            case ControlRole::password:
                return "Password";
            case ControlRole::one_time_password:
                return "One-time password";
            default:
                return nullptr;
            }
        }
    }

    MemberDecision decide_member_candidate(const MemberEvidence& evidence)
    {
        if (!evidence.member_list_focused)
            return { false, {}, "member-list-not-focused" };
        if (!evidence.selected_index_resolved)
            return { false, {}, "selected-index-unresolved" };
        if (!evidence.exact_selected_child)
            return { false, {}, "different-selected-child" };
        if (!evidence.text_owned_by_selected_child)
            return { false, {}, "text-not-owned-by-selected-child" };
        if (evidence.text.empty())
            return { false, {}, "empty" };
        return { true, std::string(evidence.text), "none" };
    }

    FocusedMemberRowDecision decide_focused_member_row(
        const FocusedMemberRowEvidence& evidence) noexcept
    {
        if (evidence.keyboard_selected_row < 0 ||
            evidence.keyboard_selected_row > 10000)
        {
            return { false, 0, "selected-row-unresolved" };
        }

        return {
            true,
            static_cast<uint32_t>(evidence.keyboard_selected_row),
            "none"
        };
    }

    bool focused_member_row_still_selected(
        uint32_t resolved_row,
        int16_t observed_keyboard_selected_row) noexcept
    {
        return observed_keyboard_selected_row >= 0 &&
            observed_keyboard_selected_row <= 10000 &&
            resolved_row == static_cast<uint32_t>(observed_keyboard_selected_row);
    }

    bool exact_owned_member_name_allowed(std::string_view text) noexcept
    {
        if (text.empty() || text.size() > 20)
            return false;

        bool have_visible_byte = false;
        for (const char character : text)
        {
            const auto byte = static_cast<unsigned char>(character);
            if (byte < 0x20 || byte == 0x7F)
                return false;
            if (byte != 0x20)
                have_visible_byte = true;
        }
        return have_visible_byte;
    }

    std::string_view add_member_set_password_value(
        uint32_t selected_index) noexcept
    {
        switch (selected_index)
        {
        case 0:
            return "Not set";
        case 1:
            return "Save";
        default:
            return {};
        }
    }

    std::string field_focus_speech(
        std::string_view label,
        std::string_view value)
    {
        if (label.empty())
            return {};
        std::string speech(label);
        speech += ", ";
        speech += value.empty() ? "empty" : value;
        return speech;
    }

    size_t masked_display_count(std::u16string_view displayed) noexcept
    {
        for (const char16_t character : displayed)
        {
            if (character != u'*' && character != u'\u2022' && character != u'\u25CF')
                return InvalidMaskedCount;
        }
        return displayed.size();
    }

    std::string masked_focus_speech(ControlRole role, size_t count)
    {
        const char* label = masked_role_label(role);
        if (label == nullptr || count == InvalidMaskedCount)
            return {};
        if (count == 0)
            return std::string(label) + ", empty";
        return std::string(label) + ", " + std::to_string(count) +
            (count == 1 ? " character entered" : " characters entered");
    }

    std::string masked_focus_speech(
        std::string_view label,
        size_t count)
    {
        if (label.empty() || count == InvalidMaskedCount)
            return {};
        if (count == 0)
            return std::string(label) + ", empty";
        return std::string(label) + ", " + std::to_string(count) +
            (count == 1 ? " character entered" : " characters entered");
    }

    std::string masked_delta_speech(ControlRole role, size_t before, size_t after)
    {
        if (before == InvalidMaskedCount || after == InvalidMaskedCount || after <= before)
            return {};
        if (after == before + 1)
            return masked_role_label(role) == nullptr ? std::string{} : std::string("star");
        return masked_focus_speech(role, after);
    }

    std::string masked_delta_speech(
        std::string_view label,
        size_t before,
        size_t after)
    {
        if (label.empty() ||
            before == InvalidMaskedCount ||
            after == InvalidMaskedCount ||
            after <= before)
        {
            return {};
        }
        if (after == before + 1)
            return "star";
        return masked_focus_speech(label, after);
    }

    TrackedNativeValueUpdate observe_tracked_native_value(
        TrackedNativeValueState& state,
        uintptr_t object,
        size_t value) noexcept
    {
        if (object < 0x10000u || value == InvalidMaskedCount)
        {
            reset_tracked_native_value(state);
            return TrackedNativeValueUpdate::rejected;
        }

        if (state.object != object ||
            state.value == InvalidMaskedCount)
        {
            state.object = object;
            state.value = value;
            return TrackedNativeValueUpdate::focus;
        }

        if (state.value == value)
            return TrackedNativeValueUpdate::unchanged;

        state.value = value;
        return TrackedNativeValueUpdate::changed;
    }

    void reset_tracked_native_value(
        TrackedNativeValueState& state) noexcept
    {
        state.object = 0;
        state.value = InvalidMaskedCount;
    }
}
