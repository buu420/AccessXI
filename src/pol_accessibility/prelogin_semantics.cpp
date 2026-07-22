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

    std::string masked_delta_speech(ControlRole role, size_t before, size_t after)
    {
        if (before == InvalidMaskedCount || after == InvalidMaskedCount || after <= before)
            return {};
        if (after == before + 1)
            return masked_role_label(role) == nullptr ? std::string{} : std::string("star");
        return masked_focus_speech(role, after);
    }
}
