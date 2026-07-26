#include "pol_pml/native_popup_text.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>
#include <unordered_map>

namespace
{
    using namespace accessxi::pol_pml;

    void require(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAIL: " << message << '\n';
            std::exit(1);
        }
    }

    struct FakeMemory
    {
        std::unordered_map<uintptr_t, uint8_t> bytes;

        template<typename T>
        void write(uintptr_t address, const T& value)
        {
            const auto* source = reinterpret_cast<const uint8_t*>(&value);
            for (size_t index = 0; index < sizeof(T); ++index)
                bytes[address + index] = source[index];
        }

        void erase(uintptr_t address, size_t size)
        {
            for (size_t index = 0; index < size; ++index)
                bytes.erase(address + index);
        }

        void write_utf16(uintptr_t address, const std::u16string& value, bool terminate = true)
        {
            for (size_t index = 0; index < value.size(); ++index)
                write<uint16_t>(address + index * 2, static_cast<uint16_t>(value[index]));
            if (terminate)
                write<uint16_t>(address + value.size() * 2, 0);
        }

        static bool read(void* context, uintptr_t address, void* output, size_t size) noexcept
        {
            auto* memory = static_cast<FakeMemory*>(context);
            auto* destination = static_cast<uint8_t*>(output);
            for (size_t index = 0; index < size; ++index)
            {
                const auto found = memory->bytes.find(address + index);
                if (found == memory->bytes.end())
                    return false;
                destination[index] = found->second;
            }
            return true;
        }

        MemoryView view()
        {
            return MemoryView{ &FakeMemory::read, this };
        }
    };

    constexpr uintptr_t AppBase = 0x04000000u;
    constexpr uintptr_t Owner = 0x10000000u;
    constexpr uintptr_t Label1 = 0x10001000u;
    constexpr uintptr_t Label2 = 0x10002000u;
    constexpr uintptr_t Label3 = 0x10003000u;
    constexpr uintptr_t Button = 0x10004000u;
    constexpr uintptr_t Text1 = 0x20001000u;
    constexpr uintptr_t Text2 = 0x20002000u;
    constexpr uintptr_t Text3 = 0x20003000u;

    void test_owner_registration_publishes_coherent_live_owner_slots()
    {
        PopupOwnerRegistration registration;
        require(!registration.snapshot().valid, "a new owner registration must be empty");

        registration.publish(Owner);
        auto first = registration.snapshot(0);
        require(first.valid, "a published owner registration must be valid");
        require(first.owner == Owner, "the first published owner pointer must survive");
        require(first.generation == 1, "the first publication must use generation one");

        registration.publish(Label1);
        auto retained_first = registration.snapshot(0);
        auto second = registration.snapshot(1);
        require(
            retained_first.valid &&
                retained_first.owner == Owner &&
                retained_first.generation == 1,
            "publishing another popup must retain the first atomic owner pair");
        require(second.valid, "a second live owner slot must be valid");
        require(second.owner == Label1, "the second live owner pointer must survive");
        require(second.generation == 1, "a newly claimed slot must use generation one");

        registration.invalidate(Owner);
        auto invalidated_first = registration.snapshot(0);
        auto retained_second = registration.snapshot(1);
        require(
            !invalidated_first.valid &&
                invalidated_first.generation == 2,
            "destruction must atomically invalidate only the matching owner slot");
        require(
            retained_second.valid &&
                retained_second.owner == Label1 &&
                retained_second.generation == 1,
            "destruction of one popup must not invalidate another live popup");

        registration.invalidate(Label1);
        auto invalidated_second = registration.snapshot(1);
        require(!invalidated_second.valid, "destruction must invalidate the second owner");
        require(invalidated_second.generation == 2, "destruction must advance slot generation");

        registration.publish(Owner);
        auto after_invalidation = registration.snapshot(0);
        require(
            after_invalidation.valid &&
                after_invalidation.owner == Owner &&
                after_invalidation.generation == 3,
            "reusing a slot after destruction must retain monotonic generation");

        registration.reset();
        require(!registration.snapshot().valid, "reset must atomically invalidate the owner pair");
    }

    void test_owner_registration_never_tears_pointer_from_generation()
    {
        PopupOwnerRegistration registration;
        std::atomic<bool> writer_done{ false };
        std::atomic<bool> coherent{ true };
        std::thread writer([&]() {
            for (uint32_t publication = 1; publication <= 20000; ++publication)
            {
                const uintptr_t owner =
                    (publication & 1u) != 0 ? Owner : Label1;
                registration.publish(owner);
                registration.invalidate(owner);
            }
            writer_done.store(true, std::memory_order_release);
        });

        while (!writer_done.load(std::memory_order_acquire))
        {
            const auto snapshot = registration.snapshot(0);
            if (!snapshot.valid)
                continue;
            const uint32_t publication =
                (static_cast<uint32_t>(snapshot.generation) + 1u) / 2u;
            const uintptr_t expected =
                (publication & 1u) != 0 ? Owner : Label1;
            if (snapshot.owner != expected)
            {
                coherent.store(false, std::memory_order_relaxed);
                break;
            }
        }
        writer.join();
        require(
            coherent.load(std::memory_order_relaxed),
            "owner pointer and generation must come from one atomic publication");

        const auto final_snapshot = registration.snapshot();
        require(!final_snapshot.valid, "the final destroyed owner must be invalid");
        require(final_snapshot.generation == 40000, "the final slot generation must not be lost");
    }

    void test_owner_registration_retains_multiple_live_popup_instances()
    {
        PopupOwnerRegistration registration;
        registration.publish(Owner);
        registration.publish(Label1);

        const auto first = registration.snapshot();
        require(
            first.valid && first.owner == Owner,
            "publishing a second live popup must not discard the first owner");

        registration.invalidate(Owner);
        const auto second = registration.snapshot();
        require(
            second.valid && second.owner == Label1,
            "destroying one popup must leave another live popup registered");
    }

    void test_owner_registration_fails_silent_at_capacity_and_reuses_destroyed_slot()
    {
        PopupOwnerRegistration registration;
        constexpr uintptr_t OwnerStride = 0x100u;
        for (size_t index = 0;
             index < PopupOwnerRegistration::capacity();
             ++index)
        {
            require(
                registration.publish(Owner + index * OwnerStride),
                "every bounded popup owner slot must be publishable");
        }

        for (size_t index = 0;
             index < PopupOwnerRegistration::capacity();
             ++index)
        {
            const auto snapshot = registration.snapshot(index);
            require(
                snapshot.valid &&
                    snapshot.owner == Owner + index * OwnerStride &&
                    snapshot.generation == 1,
                "filling the registry must retain every live popup owner");
        }

        constexpr uintptr_t OverflowOwner = 0x11000000u;
        require(
            !registration.publish(OverflowOwner),
            "a thirty-third live popup must fail silent at the bounded capacity");

        constexpr size_t ReusedSlot = 17;
        registration.invalidate(Owner + ReusedSlot * OwnerStride);
        require(
            registration.publish(OverflowOwner),
            "a destroyed popup slot must become available to a new owner");
        const auto reused = registration.snapshot(ReusedSlot);
        require(
            reused.valid &&
                reused.owner == OverflowOwner &&
                reused.generation == 3,
            "a reused popup slot must atomically retain its monotonic generation");
    }

    void write_label(
        FakeMemory& memory,
        uintptr_t label,
        uintptr_t text,
        const std::u16string& value,
        bool terminate = true)
    {
        memory.write<uintptr_t>(label, AppBase + CLabelVtableRva);
        memory.write<uint8_t>(label + 0x18, 0x0C);
        memory.write<uintptr_t>(label + 0x184, text);
        memory.write<uintptr_t>(label + 0x188, text + (value.size() + 1) * sizeof(char16_t));
        memory.write<int16_t>(label + 0x21A, static_cast<int16_t>(value.size()));
        memory.write_utf16(text, value, terminate);
    }

    FakeMemory modal(
        uintptr_t owner_vtable_rva,
        uint32_t body_slot,
        const std::u16string& text)
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Owner, AppBase + owner_vtable_rva);
        memory.write<uint8_t>(Owner + 0x18, 0x0C);
        memory.write<uintptr_t>(Owner + body_slot, Label1);
        write_label(memory, Label1, Text1, text);
        return memory;
    }

    void require_one(
        const PopupTextSnapshot& snapshot,
        PopupOwnerKind expected_kind,
        PopupSpeechMode expected_mode,
        uint32_t expected_slot,
        const std::u16string& expected_text,
        const char* message)
    {
        require(snapshot.matched, message);
        require(snapshot.owner_kind == expected_kind, message);
        require(snapshot.speech_mode == expected_mode, message);
        require(snapshot.candidate_count == 1, message);
        require(snapshot.candidates[0].slot_offset == expected_slot, message);
        require(
            snapshot.candidates[0].state == PopupTextCandidateState::present,
            message);
        require(snapshot.candidates[0].text == expected_text, message);
    }

    void test_all_modal_classes_use_only_their_proven_body_slot()
    {
        struct Case
        {
            uintptr_t vtable;
            PopupOwnerKind kind;
            uint32_t slot;
        };
        constexpr Case cases[] = {
            { ModalOkVtableRva, PopupOwnerKind::modal_ok, 0x2B8 },
            { ModalYesNoVtableRva, PopupOwnerKind::modal_yes_no, 0x2BC },
            { ModalYesNoCancelVtableRva, PopupOwnerKind::modal_yes_no_cancel, 0x2C0 },
            { ModalOkCancelVtableRva, PopupOwnerKind::modal_ok_cancel, 0x2BC },
            { ModalRetryFailVtableRva, PopupOwnerKind::modal_retry_fail, 0x2BC },
        };

        for (const auto& value : cases)
        {
            auto memory = modal(value.vtable, value.slot, u"Are you sure?");
            memory.write<uintptr_t>(Owner + 0x2B4, Button);
            memory.write<uintptr_t>(Button, AppBase + CButtonVtableRva);
            require_one(
                inspect_popup_text(memory.view(), Owner, AppBase),
                value.kind,
                PopupSpeechMode::interrupt,
                value.slot,
                u"Are you sure?",
                "modal body did not use its exact Ghidra-proven CLabel slot");
        }
    }

    void test_all_ghidra_proven_derived_popups_keep_their_base_text_contract()
    {
        struct Case
        {
            uintptr_t vtable;
            PopupOwnerKind kind;
            PopupSpeechMode mode;
            uint32_t first_slot;
            size_t slot_count;
        };
        constexpr Case cases[] = {
            { 0x00323D24u, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x00336434u, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x0033829Cu, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x003C816Cu, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x003CA074u, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x003CA2D4u, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x003CB0F4u, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x003D492Cu, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },
            { 0x003E7F54u, PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, 0x2B8, 1 },

            { 0x00322394u, PopupOwnerKind::modal_yes_no, PopupSpeechMode::interrupt, 0x2BC, 1 },
            { 0x00338524u, PopupOwnerKind::modal_yes_no, PopupSpeechMode::interrupt, 0x2BC, 1 },
            { 0x003D3F54u, PopupOwnerKind::modal_yes_no, PopupSpeechMode::interrupt, 0x2BC, 1 },
            { 0x003DCBC4u, PopupOwnerKind::modal_yes_no, PopupSpeechMode::interrupt, 0x2BC, 1 },
            { 0x003E2A9Cu, PopupOwnerKind::modal_yes_no, PopupSpeechMode::interrupt, 0x2BC, 1 },
            { 0x003E81BCu, PopupOwnerKind::modal_yes_no, PopupSpeechMode::interrupt, 0x2BC, 1 },

            { 0x003283D4u, PopupOwnerKind::modal_yes_no_cancel, PopupSpeechMode::interrupt, 0x2C0, 1 },
            { 0x003387A4u, PopupOwnerKind::modal_yes_no_cancel, PopupSpeechMode::interrupt, 0x2C0, 1 },
            { 0x003E8424u, PopupOwnerKind::modal_yes_no_cancel, PopupSpeechMode::interrupt, 0x2C0, 1 },

            { 0x003E868Cu, PopupOwnerKind::modal_ok_cancel, PopupSpeechMode::interrupt, 0x2BC, 1 },

            { 0x00324744u, PopupOwnerKind::modal_retry_fail, PopupSpeechMode::interrupt, 0x2BC, 1 },
            { 0x003CA534u, PopupOwnerKind::modal_retry_fail, PopupSpeechMode::interrupt, 0x2BC, 1 },

            { 0x003CE96Cu, PopupOwnerKind::notice, PopupSpeechMode::queued, 0x2A8, 3 },
            { 0x003CF074u, PopupOwnerKind::notice, PopupSpeechMode::queued, 0x2A8, 3 },
            { 0x003CF2CCu, PopupOwnerKind::important_notice, PopupSpeechMode::queued, 0x2AC, 2 },
        };

        for (const auto& value : cases)
        {
            auto memory =
                modal(value.vtable, value.first_slot, u"Player-facing message");
            const auto snapshot =
                inspect_popup_text(memory.view(), Owner, AppBase);
            require(
                snapshot.matched &&
                    snapshot.owner_kind == value.kind &&
                    snapshot.speech_mode == value.mode &&
                    snapshot.candidate_count == value.slot_count &&
                    snapshot.candidates[0].slot_offset == value.first_slot &&
                    snapshot.candidates[0].state ==
                        PopupTextCandidateState::present &&
                    snapshot.candidates[0].text == u"Player-facing message",
                "a Ghidra-proven derived popup lost its inherited text contract");
        }
    }

    void test_notice_classes_use_only_proven_label_slots()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Owner, AppBase + NoticeWindowVtableRva);
        memory.write<uint8_t>(Owner + 0x18, 0x0C);
        memory.write<uintptr_t>(Owner + 0x2A8, Label1);
        memory.write<uintptr_t>(Owner + 0x2AC, Label2);
        memory.write<uintptr_t>(Owner + 0x2B0, Label3);
        write_label(memory, Label1, Text1, u"Friend");
        write_label(memory, Label2, Text2, u"Longrodvonhugen");
        write_label(memory, Label3, Text3, u"is now online.");
        memory.write<uintptr_t>(Owner + 0x2B4, Button);
        memory.write<uintptr_t>(Button, AppBase + CButtonVtableRva);

        auto snapshot = inspect_popup_text(memory.view(), Owner, AppBase);
        require(snapshot.matched, "CNotice_Window was not recognized");
        require(snapshot.owner_kind == PopupOwnerKind::notice, "wrong notice owner kind");
        require(snapshot.speech_mode == PopupSpeechMode::queued, "notice must not interrupt focus speech");
        require(snapshot.candidate_count == 3, "notice did not retain its three exact label slots");
        require(snapshot.candidates[0].slot_offset == 0x2A8 &&
                snapshot.candidates[0].state == PopupTextCandidateState::present &&
                snapshot.candidates[0].text == u"Friend",
            "first notice label was not retained");
        require(snapshot.candidates[1].slot_offset == 0x2AC &&
                snapshot.candidates[1].state == PopupTextCandidateState::present &&
                snapshot.candidates[1].text == u"Longrodvonhugen",
            "second notice label was not retained");
        require(snapshot.candidates[2].slot_offset == 0x2B0 &&
                snapshot.candidates[2].state == PopupTextCandidateState::present &&
                snapshot.candidates[2].text == u"is now online.",
            "third notice label was not retained");

        memory = FakeMemory{};
        memory.write<uintptr_t>(Owner, AppBase + ImportantNoticeVtableRva);
        memory.write<uint8_t>(Owner + 0x18, 0x0C);
        memory.write<uintptr_t>(Owner + 0x2AC, Label1);
        memory.write<uintptr_t>(Owner + 0x2B0, Label2);
        memory.write<uintptr_t>(Owner + 0x2B4, Button);
        write_label(memory, Label1, Text1, u"Important");
        write_label(memory, Label2, Text2, u"Maintenance begins soon.");
        memory.write<uintptr_t>(Button, AppBase + CScrollTextAreaVtableRva);

        snapshot = inspect_popup_text(memory.view(), Owner, AppBase);
        require(snapshot.matched, "CNotice_Important_Wnd was not recognized");
        require(snapshot.owner_kind == PopupOwnerKind::important_notice, "wrong important-notice kind");
        require(snapshot.candidate_count == 2, "unsupported rich component was treated as a label");
        require(snapshot.candidates[0].slot_offset == 0x2AC, "important notice first label slot changed");
        require(snapshot.candidates[1].slot_offset == 0x2B0, "important notice second label slot changed");
    }

    void test_unknown_or_mismatched_native_ownership_stays_silent()
    {
        auto memory = modal(ModalYesNoVtableRva, 0x2BC, u"Exit PlayOnline?");
        memory.write<uintptr_t>(Owner, AppBase + CButtonVtableRva);
        require(!inspect_popup_text(memory.view(), Owner, AppBase).matched,
            "unknown owner vtable must not produce popup text");

        memory = modal(ModalYesNoVtableRva, 0x2BC, u"Exit PlayOnline?");
        memory.write<uintptr_t>(Label1, AppBase + CButtonVtableRva);
        const auto snapshot = inspect_popup_text(memory.view(), Owner, AppBase);
        require(snapshot.matched && snapshot.candidate_count == 1,
            "recognized modal ownership should retain its known body slot");
        require(snapshot.candidates[0].state == PopupTextCandidateState::unknown &&
                snapshot.candidates[0].text.empty(),
            "a non-CLabel child must stay silent");
    }

    void test_hidden_owner_or_label_stays_silent()
    {
        auto memory = modal(ModalYesNoVtableRva, 0x2BC, u"Exit PlayOnline?");
        memory.write<uint8_t>(Owner + 0x18, 0x08);
        auto snapshot = inspect_popup_text(memory.view(), Owner, AppBase);
        require(snapshot.matched &&
                snapshot.candidates[0].state == PopupTextCandidateState::absent &&
                snapshot.candidates[0].text.empty(),
            "a hidden modal body must stay silent");

        memory = modal(ModalYesNoVtableRva, 0x2BC, u"Exit PlayOnline?");
        memory.write<uint8_t>(Label1 + 0x18, 0x04);
        snapshot = inspect_popup_text(memory.view(), Owner, AppBase);
        require(snapshot.matched &&
                snapshot.candidates[0].state == PopupTextCandidateState::absent &&
                snapshot.candidates[0].text.empty(),
            "a hidden CLabel must stay silent");
    }

    void test_malformed_or_non_player_facing_label_text_stays_silent()
    {
        auto check_empty = [](
            FakeMemory memory,
            PopupTextCandidateState expected_state,
            const char* message) {
            const auto snapshot = inspect_popup_text(memory.view(), Owner, AppBase);
            require(snapshot.matched && snapshot.candidate_count == 1, message);
            require(snapshot.candidates[0].state == expected_state, message);
            require(snapshot.candidates[0].text.empty(), message);
        };

        auto memory = modal(ModalOkVtableRva, 0x2B8, u"Continue?");
        memory.erase(Text1 + std::u16string(u"Continue?").size() * 2, 2);
        check_empty(std::move(memory), PopupTextCandidateState::unknown,
            "unterminated label text must stay silent");

        memory = modal(ModalOkVtableRva, 0x2B8, u"Continue?");
        memory.write<uintptr_t>(Label1 + 0x188, Text1 + 2);
        check_empty(std::move(memory), PopupTextCandidateState::unknown,
            "undersized label allocation must stay silent");

        memory = modal(ModalOkVtableRva, 0x2B8, u"Continue?");
        memory.write<int16_t>(Label1 + 0x21A, 513);
        check_empty(std::move(memory), PopupTextCandidateState::unknown,
            "overlong label text must stay silent");

        memory = modal(ModalOkVtableRva, 0x2B8, std::u16string{ u'O', u'K', u'\x0001' });
        check_empty(std::move(memory), PopupTextCandidateState::unknown,
            "control-containing label text must stay silent");

        memory = modal(ModalOkVtableRva, 0x2B8, std::u16string{ u'\xD800', u'A' });
        check_empty(std::move(memory), PopupTextCandidateState::unknown,
            "malformed surrogate pair must stay silent");

        memory = modal(ModalOkVtableRva, 0x2B8, u"http://example.invalid/popup.pml");
        check_empty(std::move(memory), PopupTextCandidateState::unknown,
            "resource or URL text must stay silent");

        memory = modal(ModalOkVtableRva, 0x2B8, u" \t\r\n ");
        check_empty(std::move(memory), PopupTextCandidateState::absent,
            "whitespace-only label text must stay silent");
    }

    void test_visible_multiline_text_is_normalized_without_guessing()
    {
        auto memory = modal(ModalYesNoVtableRva, 0x2BC, u"Exit PlayOnline?\r\nUnsaved changes will be lost.");
        require_one(
            inspect_popup_text(memory.view(), Owner, AppBase),
            PopupOwnerKind::modal_yes_no,
            PopupSpeechMode::interrupt,
            0x2BC,
            u"Exit PlayOnline? Unsaved changes will be lost.",
            "visible modal whitespace was not normalized");
    }

    void test_tracker_requires_stability_and_deduplicates()
    {
        PopupTextTracker tracker;
        require(
            tracker.observe(1, PopupOwnerKind::modal_yes_no, 0x2BC, u"Exit PlayOnline?") ==
                PopupObservation::none,
            "first modal poll must wait for stability");
        require(
            tracker.observe(1, PopupOwnerKind::modal_yes_no, 0x2BC, u"Exit PlayOnline?") ==
                PopupObservation::speak_interrupt,
            "second identical modal poll did not emit interrupting speech");
        require(
            tracker.observe(1, PopupOwnerKind::modal_yes_no, 0x2BC, u"Exit PlayOnline?") ==
                PopupObservation::none,
            "unchanged stable modal text repeated");
    }

    void test_tracker_emits_notice_changes_without_focus()
    {
        PopupTextTracker tracker;
        require(
            tracker.observe(7, PopupOwnerKind::notice, 0x2B0, u"Zaltar is now online.") ==
                PopupObservation::none,
            "first notice poll must wait for stability");
        require(
            tracker.observe(7, PopupOwnerKind::notice, 0x2B0, u"Zaltar is now online.") ==
                PopupObservation::speak_queued,
            "stable notice did not emit queued speech");
        require(
            tracker.observe(7, PopupOwnerKind::notice, 0x2B0, u"Zaltar is now offline.") ==
                PopupObservation::none,
            "changed notice must wait for stability");
        require(
            tracker.observe(7, PopupOwnerKind::notice, 0x2B0, u"Zaltar is now offline.") ==
                PopupObservation::speak_queued,
            "changed stable notice did not emit without a focus event");
    }

    void test_tracker_preserves_dedup_across_unknown_or_one_absent_poll()
    {
        PopupTextTracker tracker;
        tracker.observe(8, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.");
        require(
            tracker.observe(8, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::speak_queued,
            "initial notice did not emit");

        require(
            tracker.observe(
                8,
                PopupOwnerKind::notice,
                0x2B0,
                PopupTextCandidateState::unknown,
                {}) == PopupObservation::none,
            "an unknown read must stay silent");
        require(
            tracker.observe(8, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::none,
            "a transient unreadable poll cleared deduplication");

        require(
            tracker.observe(
                8,
                PopupOwnerKind::notice,
                0x2B0,
                PopupTextCandidateState::absent,
                {}) == PopupObservation::none,
            "one confirmed-absent poll must stay silent");
        require(
            tracker.observe(8, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::none,
            "one absent poll caused unchanged visible text to repeat");
    }

    void test_tracker_reset_empty_and_new_generation_allow_real_reappearance()
    {
        PopupTextTracker tracker;
        tracker.observe(9, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.");
        require(
            tracker.observe(9, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::speak_queued,
            "initial notice did not emit");

        require(
            tracker.observe(9, PopupOwnerKind::notice, 0x2B0, {}) == PopupObservation::none,
            "first empty notice poll must not emit");
        require(
            tracker.observe(9, PopupOwnerKind::notice, 0x2B0, {}) == PopupObservation::none,
            "second empty notice poll must clear without emitting");
        require(
            tracker.observe(9, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::none,
            "repopulated notice must restabilize");
        require(
            tracker.observe(9, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::speak_queued,
            "repopulated notice was incorrectly deduplicated forever");

        require(
            tracker.observe(10, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::none,
            "new generation must restabilize");
        require(
            tracker.observe(10, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::speak_queued,
            "same text on a new owner generation did not emit");

        tracker.reset();
        require(
            tracker.observe(10, PopupOwnerKind::notice, 0x2B0, u"Friend is now online.") ==
                PopupObservation::none,
            "reset did not clear pending stability");
    }
}

int main()
{
    test_owner_registration_publishes_coherent_live_owner_slots();
    test_owner_registration_never_tears_pointer_from_generation();
    test_owner_registration_retains_multiple_live_popup_instances();
    test_owner_registration_fails_silent_at_capacity_and_reuses_destroyed_slot();
    test_all_modal_classes_use_only_their_proven_body_slot();
    test_all_ghidra_proven_derived_popups_keep_their_base_text_contract();
    test_notice_classes_use_only_proven_label_slots();
    test_unknown_or_mismatched_native_ownership_stays_silent();
    test_hidden_owner_or_label_stays_silent();
    test_malformed_or_non_player_facing_label_text_stays_silent();
    test_visible_multiline_text_is_normalized_without_guessing();
    test_tracker_requires_stability_and_deduplicates();
    test_tracker_emits_notice_changes_without_focus();
    test_tracker_preserves_dedup_across_unknown_or_one_absent_poll();
    test_tracker_reset_empty_and_new_generation_allow_real_reappearance();
    std::cout << "pol_pml_popup_text_tests: ok\n";
    return 0;
}
