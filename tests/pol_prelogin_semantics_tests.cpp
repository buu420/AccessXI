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

    void test_focused_member_row_uses_keyboard_selection_ownership()
    {
        const FocusedMemberRowDecision keyboard_selected =
            decide_focused_member_row({ -1, 0, 0 });
        require(keyboard_selected.resolved,
            "valid keyboard-selected member row was rejected");
        require(keyboard_selected.row == 0,
            "keyboard-selected member row changed");
        require(std::string(keyboard_selected.reason) == "none",
            "valid keyboard-selected member row retained a rejection reason");

        const FocusedMemberRowDecision mouse_only =
            decide_focused_member_row({ 3, -1, 3 });
        require(!mouse_only.resolved,
            "mouse-hit or focus-anchor row was promoted without keyboard selection");
        require(std::string(mouse_only.reason) == "selected-row-unresolved",
            "missing keyboard-selected row rejection reason mismatch");

        require(!decide_focused_member_row({ -1, 10001, -1 }).resolved,
            "out-of-range keyboard-selected row was accepted");
    }

    void test_focused_member_row_must_remain_selected()
    {
        require(focused_member_row_still_selected(0, 0),
            "unchanged keyboard-selected row lost ownership");
        require(!focused_member_row_still_selected(0, 1),
            "changed keyboard-selected row retained stale ownership");
        require(!focused_member_row_still_selected(0, -1),
            "unresolved keyboard-selected row retained stale ownership");
    }

    void test_exact_owned_member_name_accepts_visible_native_text()
    {
        require(exact_owned_member_name_allowed("A"),
            "one-character exact-owned member name was rejected");
        require(exact_owned_member_name_allowed("A!?"),
            "punctuated exact-owned member name was rejected");
        require(exact_owned_member_name_allowed("Member List"),
            "exact-owned text was rejected because it resembled a static label");
        require(!exact_owned_member_name_allowed(""),
            "empty exact-owned member name was accepted");
        require(!exact_owned_member_name_allowed("   "),
            "blank exact-owned member name was accepted");
        require(!exact_owned_member_name_allowed("A\nB"),
            "control-bearing exact-owned member name was accepted");
        require(!exact_owned_member_name_allowed("123456789012345678901"),
            "overlong exact-owned member name was accepted");
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

    void test_labeled_field_focus_speech()
    {
        require(field_focus_speech("Member Name", "Zaltar") ==
                "Member Name, Zaltar",
            "a retained ordinary Add Member value was not composed with its label");
        require(field_focus_speech("PlayOnline ID", "") ==
                "PlayOnline ID, empty",
            "an empty ordinary Add Member value was not announced");
        require(field_focus_speech("", "Zaltar").empty(),
            "a value without an owned field label produced speech");

        require(masked_focus_speech("Member Password", 0) ==
                "Member Password, empty",
            "an empty labeled password field was not announced");
        require(masked_focus_speech("Confirm Password", 1) ==
                "Confirm Password, 1 character entered",
            "a singular labeled password count was not announced");
        require(masked_focus_speech("PlayOnline Password", 8) ==
                "PlayOnline Password, 8 characters entered",
            "a labeled password count was not announced");
        require(masked_focus_speech("", 8).empty(),
            "a secret count without an owned field label produced speech");
        require(masked_focus_speech("Member Password", InvalidMaskedCount).empty(),
            "an unverified labeled password count produced speech");

        require(masked_delta_speech("Member Password", 5, 6) == "star",
            "a single accepted character in a labeled password did not speak star");
        require(masked_delta_speech("Member Password", 2, 6) ==
                "Member Password, 6 characters entered",
            "a multi-character insertion lost the exact password field label");
        require(masked_delta_speech("Member Password", 6, 5).empty(),
            "a labeled password deletion produced insertion speech");
    }

    void test_set_password_native_selection_mapping()
    {
        require(add_member_set_password_value(0) == "Not set",
            "the first native Set Password row was not mapped to Not set");
        require(add_member_set_password_value(1) == "Save",
            "the second native Set Password row was not mapped to Save");
        require(add_member_set_password_value(2).empty(),
            "an unverified Set Password row produced a value");
    }

    void test_tracked_native_values_only_report_verified_transitions()
    {
        TrackedNativeValueState state;

        require(observe_tracked_native_value(state, 0x12345u, 0) ==
                TrackedNativeValueUpdate::focus,
            "the first exact native value was not treated as focus");
        require(state.object == 0x12345u && state.value == 0,
            "the first exact native value was not retained");
        require(observe_tracked_native_value(state, 0x12345u, 0) ==
                TrackedNativeValueUpdate::unchanged,
            "an unchanged exact native value produced a transition");
        require(observe_tracked_native_value(state, 0x12345u, 1) ==
                TrackedNativeValueUpdate::changed,
            "a changed value on the retained native object was not reported");
        require(observe_tracked_native_value(state, 0x23456u, 7) ==
                TrackedNativeValueUpdate::focus,
            "a different exact native object inherited stale state");

        require(observe_tracked_native_value(
                    state,
                    0,
                    InvalidMaskedCount) ==
                TrackedNativeValueUpdate::rejected,
            "an invalid native value was accepted");
        require(state.object == 0 && state.value == InvalidMaskedCount,
            "rejected native state was not cleared");
    }
}

int main()
{
    test_member_text_requires_selected_child_ownership();
    test_member_text_requires_every_relationship_link();
    test_focused_member_row_uses_keyboard_selection_ownership();
    test_focused_member_row_must_remain_selected();
    test_exact_owned_member_name_accepts_visible_native_text();
    test_masked_display_accepts_only_visible_mask_glyphs();
    test_masked_focus_and_delta_speech();
    test_labeled_field_focus_speech();
    test_set_password_native_selection_mapping();
    test_tracked_native_values_only_report_verified_transitions();
    std::cout << "ok: pre-login ownership and masked-state semantics\n";
    return 0;
}
