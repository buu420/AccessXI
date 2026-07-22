#include "pol_accessibility/prelogin_semantics.h"

#include <cstdlib>
#include <iostream>

namespace
{
    using namespace accessxi::pol_accessibility;

    void require(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAIL: " << message << '\n';
            std::exit(1);
        }
    }

    void test_member_text_requires_selected_child_ownership()
    {
        const MemberEvidence unrelated{ "Rich", true, true, false, false };
        const MemberDecision rejected = decide_member_candidate(unrelated);
        require(!rejected.trusted, "name-like text without selected-child ownership was trusted");
        require(rejected.text.empty(), "rejected member candidate retained speech text");
        require(std::string(rejected.reason) == "different-selected-child", "member rejection reason mismatch");

        const MemberEvidence owned{ "Actual Member", true, true, true, true };
        const MemberDecision accepted = decide_member_candidate(owned);
        require(accepted.trusted, "selected child-owned member text was rejected");
        require(accepted.text == "Actual Member", "selected member text changed");
        require(std::string(accepted.reason) == "none", "accepted member candidate retained a rejection reason");
    }

    void test_member_text_requires_every_relationship_link()
    {
        require(!decide_member_candidate({ "Member", false, true, true, true }).trusted,
            "member text without member-list focus was trusted");
        require(!decide_member_candidate({ "Member", true, false, true, true }).trusted,
            "member text without a resolved index was trusted");
        require(!decide_member_candidate({ "Member", true, true, true, false }).trusted,
            "member text not owned by the selected child was trusted");
        require(!decide_member_candidate({ "", true, true, true, true }).trusted,
            "empty member text was trusted");
    }

    void test_masked_display_accepts_only_visible_mask_glyphs()
    {
        require(masked_display_count(u"******") == 6, "asterisk display length was not preserved");
        require(masked_display_count(u"\u2022\u2022\u2022") == 3, "bullet display length was not preserved");
        require(masked_display_count(u"\u25CF\u25CF") == 2, "black-circle display length was not preserved");
        require(masked_display_count(u"") == 0, "empty masked display was not accepted");
        require(masked_display_count(u"secret") == InvalidMaskedCount, "unmasked content was accepted");
        require(masked_display_count(u"***x") == InvalidMaskedCount, "mixed masked and raw content was accepted");
    }

    void test_masked_focus_and_delta_speech()
    {
        require(masked_focus_speech(ControlRole::password, 0) == "Password, empty",
            "empty password focus speech mismatch");
        require(masked_focus_speech(ControlRole::one_time_password, 6) ==
                "One-time password, 6 characters entered",
            "one-time-password count speech mismatch");
        require(masked_focus_speech(ControlRole::password, 1) ==
                "Password, 1 character entered",
            "singular password count speech mismatch");
        require(masked_focus_speech(ControlRole::unknown, 6).empty(),
            "unknown control role produced masked speech");
        require(masked_focus_speech(ControlRole::password, InvalidMaskedCount).empty(),
            "unverified masked count produced focus speech");

        require(masked_delta_speech(ControlRole::password, 5, 6) == "star",
            "single accepted character did not speak star");
        require(masked_delta_speech(ControlRole::password, 2, 6) ==
                "Password, 6 characters entered",
            "multi-character insertion did not speak the resulting count");
        require(masked_delta_speech(ControlRole::password, 6, 6).empty(),
            "unchanged masked state produced speech");
        require(masked_delta_speech(ControlRole::password, 6, 5).empty(),
            "decreasing masked state produced insertion speech");
        require(masked_delta_speech(ControlRole::password, InvalidMaskedCount, 1).empty(),
            "unverified prior masked state produced delta speech");
    }
}

int main()
{
    test_member_text_requires_selected_child_ownership();
    test_member_text_requires_every_relationship_link();
    test_masked_display_accepts_only_visible_mask_glyphs();
    test_masked_focus_and_delta_speech();
    std::cout << "ok: pre-login ownership and masked-state semantics\n";
    return 0;
}
