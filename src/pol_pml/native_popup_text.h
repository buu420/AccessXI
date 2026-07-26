#pragma once

#include "pol_pml/native_selected_text.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace accessxi::pol_pml
{
    constexpr uintptr_t CLabelVtableRva = 0x003300A4u;
    constexpr uintptr_t ModalOkVtableRva = 0x00368CA4u;
    constexpr uintptr_t ModalYesNoVtableRva = 0x00368EFCu;
    constexpr uintptr_t ModalYesNoCancelVtableRva = 0x00369154u;
    constexpr uintptr_t ModalOkCancelVtableRva = 0x00369CF4u;
    constexpr uintptr_t ModalRetryFailVtableRva = 0x0036A1A4u;
    constexpr uintptr_t NoticeWindowVtableRva = 0x0033FCDCu;
    constexpr uintptr_t ImportantNoticeVtableRva = 0x0034069Cu;
    constexpr uintptr_t CScrollTextAreaVtableRva = 0x003325D4u;

    enum class PopupOwnerKind : uint8_t
    {
        none,
        modal_ok,
        modal_yes_no,
        modal_yes_no_cancel,
        modal_ok_cancel,
        modal_retry_fail,
        notice,
        important_notice
    };

    enum class PopupSpeechMode : uint8_t
    {
        interrupt,
        queued
    };

    enum class PopupTextCandidateState : uint8_t
    {
        unknown,
        absent,
        present
    };

    enum class PopupOwnerInspectionState : uint8_t
    {
        unknown,
        unsupported,
        matched
    };

    struct PopupOwnerRegistrationSnapshot
    {
        bool valid = false;
        uintptr_t owner = 0;
        uint64_t generation = 0;
    };

    // The production bridge is x86. Pack its 32-bit owner pointer and a
    // 32-bit generation into one lock-free atomic word so a worker can never
    // pair a newly published pointer with an older generation.
    class PopupOwnerRegistration
    {
    public:
        void publish(uintptr_t owner) noexcept;
        void invalidate(uintptr_t owner) noexcept;
        PopupOwnerRegistrationSnapshot snapshot() const noexcept;
        void reset() noexcept;

    private:
        std::atomic<uint64_t> state_{ 0 };
    };

    struct PopupTextCandidate
    {
        uint32_t slot_offset = 0;
        PopupTextCandidateState state = PopupTextCandidateState::unknown;
        std::u16string text;
    };

    struct PopupTextSnapshot
    {
        bool matched = false;
        PopupOwnerInspectionState owner_state =
            PopupOwnerInspectionState::unknown;
        PopupOwnerKind owner_kind = PopupOwnerKind::none;
        PopupSpeechMode speech_mode = PopupSpeechMode::queued;
        std::array<PopupTextCandidate, 3> candidates{};
        size_t candidate_count = 0;
    };

    // Reads only the exact owner-to-CLabel relationships established for the
    // current PlayOnline app.dll by Ghidra. A recognized owner retains its
    // fixed slots even when a child is absent or invalid so the worker can
    // clear stale observation state without guessing a replacement label.
    PopupTextSnapshot inspect_popup_text(
        const MemoryView& memory,
        uintptr_t owner,
        uintptr_t app_base) noexcept;

    enum class PopupObservation : uint8_t
    {
        none,
        speak_interrupt,
        speak_queued
    };

    // Requires two identical worker polls, then suppresses repeats until the
    // text disappears, changes, the owner generation changes, or reset runs.
    class PopupTextTracker
    {
    public:
        PopupObservation observe(
            uint64_t generation,
            PopupOwnerKind owner_kind,
            uint32_t slot_offset,
            std::u16string_view text);
        PopupObservation observe(
            uint64_t generation,
            PopupOwnerKind owner_kind,
            uint32_t slot_offset,
            PopupTextCandidateState candidate_state,
            std::u16string_view text);
        void reset() noexcept;

    private:
        struct SlotState
        {
            bool used = false;
            uint32_t slot_offset = 0;
            uint8_t stable_reads = 0;
            uint8_t absent_reads = 0;
            std::u16string candidate;
            std::u16string last_spoken;
        };

        bool have_owner_ = false;
        uint64_t generation_ = 0;
        PopupOwnerKind owner_kind_ = PopupOwnerKind::none;
        std::array<SlotState, 3> slots_{};
    };
}
