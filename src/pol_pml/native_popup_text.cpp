#include "pol_pml/native_popup_text.h"

#include <algorithm>
#include <array>
#include <limits>

namespace accessxi::pol_pml
{
    static_assert(
        sizeof(uintptr_t) == sizeof(uint32_t),
        "PlayOnline owner registration is defined only for the x86 bridge");
    static_assert(
        std::atomic<uint64_t>::is_always_lock_free,
        "PlayOnline constructor callbacks require lock-free owner publication");

    namespace
    {
        constexpr uintptr_t MinimumObjectAddress = 0x10000u;
        constexpr size_t MaximumPopupCharacters = 512;

        struct OwnerDescription
        {
            PopupOwnerKind kind;
            PopupSpeechMode mode;
            std::array<uint32_t, 3> slots;
            size_t slot_count;
        };

        enum class ComponentVisibility : uint8_t
        {
            unknown,
            hidden,
            visible
        };

        bool address_range_fits(uintptr_t address, size_t size) noexcept
        {
            return size != 0 && size - 1 <= std::numeric_limits<uintptr_t>::max() - address;
        }

        bool add_address(uintptr_t base, uintptr_t offset, uintptr_t& result) noexcept
        {
            if (offset > std::numeric_limits<uintptr_t>::max() - base)
                return false;
            result = base + offset;
            return true;
        }

        template<typename T>
        bool read_value(const MemoryView& memory, uintptr_t address, T& value) noexcept
        {
            return memory.read != nullptr &&
                address_range_fits(address, sizeof(value)) &&
                memory.read(memory.context, address, &value, sizeof(value));
        }

        // CComponent's virtual visibility getter for every supported owner and
        // CLabel returns true only when both native state bits are present.
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

        bool owner_description(uintptr_t vtable_rva, OwnerDescription& result) noexcept
        {
            switch (vtable_rva)
            {
            case ModalOkVtableRva:
                result = { PopupOwnerKind::modal_ok, PopupSpeechMode::interrupt, { 0x2B8, 0, 0 }, 1 };
                return true;
            case ModalYesNoVtableRva:
                result = { PopupOwnerKind::modal_yes_no, PopupSpeechMode::interrupt, { 0x2BC, 0, 0 }, 1 };
                return true;
            case ModalYesNoCancelVtableRva:
                result = { PopupOwnerKind::modal_yes_no_cancel, PopupSpeechMode::interrupt, { 0x2C0, 0, 0 }, 1 };
                return true;
            case ModalOkCancelVtableRva:
                result = { PopupOwnerKind::modal_ok_cancel, PopupSpeechMode::interrupt, { 0x2BC, 0, 0 }, 1 };
                return true;
            case ModalRetryFailVtableRva:
                result = { PopupOwnerKind::modal_retry_fail, PopupSpeechMode::interrupt, { 0x2BC, 0, 0 }, 1 };
                return true;
            case NoticeWindowVtableRva:
                result = { PopupOwnerKind::notice, PopupSpeechMode::queued, { 0x2A8, 0x2AC, 0x2B0 }, 3 };
                return true;
            case ImportantNoticeVtableRva:
                result = { PopupOwnerKind::important_notice, PopupSpeechMode::queued, { 0x2AC, 0x2B0, 0 }, 2 };
                return true;
            default:
                return false;
            }
        }

        bool append_normalized_character(
            std::u16string& output,
            char16_t character,
            bool& saw_visible) noexcept
        {
            const bool whitespace =
                character == u' ' ||
                character == u'\t' ||
                character == u'\r' ||
                character == u'\n' ||
                character == u'\v' ||
                character == u'\f' ||
                character == 0x00A0;
            if (whitespace)
            {
                if (!output.empty() && output.back() != u' ')
                    output.push_back(u' ');
                return true;
            }

            if (character < 0x20 || (character >= 0x7F && character <= 0x9F))
                return false;

            output.push_back(character);
            saw_visible = true;
            return true;
        }

        bool player_facing_text_allowed(const std::u16string& text) noexcept
        {
            if (text.empty())
                return false;

            std::u16string lower = text;
            std::transform(lower.begin(), lower.end(), lower.begin(), [](char16_t character) {
                if (character >= u'A' && character <= u'Z')
                    return static_cast<char16_t>(character - u'A' + u'a');
                return character;
            });

            return lower.find(u"http://") == std::u16string::npos &&
                lower.find(u"https://") == std::u16string::npos &&
                lower.find(u".pml") == std::u16string::npos &&
                lower.find(u".esd") == std::u16string::npos &&
                lower.find(u".tm2") == std::u16string::npos &&
                lower.find(u'\\') == std::u16string::npos;
        }

        PopupTextCandidate read_clabel_text(
            const MemoryView& memory,
            uintptr_t label,
            uintptr_t app_base) noexcept
        {
            PopupTextCandidate result;
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
                result.state = PopupTextCandidateState::absent;
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
                result.state = PopupTextCandidateState::absent;
                return result;
            }
            if (begin < MinimumObjectAddress ||
                end < begin ||
                length < 0 ||
                static_cast<size_t>(length) > MaximumPopupCharacters)
            {
                return result;
            }

            const uintptr_t byte_count = end - begin;
            const size_t required_bytes = (static_cast<size_t>(length) + 1) * sizeof(char16_t);
            if ((byte_count & 1u) != 0 ||
                byte_count < required_bytes ||
                !address_range_fits(begin, required_bytes))
            {
                return result;
            }

            std::array<char16_t, MaximumPopupCharacters + 1> characters{};
            if (memory.read == nullptr ||
                !memory.read(memory.context, begin, characters.data(), required_bytes) ||
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
                if (!append_normalized_character(normalized, character, saw_visible))
                    return result;
            }

            while (!normalized.empty() && normalized.back() == u' ')
                normalized.pop_back();
            if (!saw_visible)
            {
                result.state = PopupTextCandidateState::absent;
                return result;
            }
            if (!player_facing_text_allowed(normalized))
                return result;

            result.state = PopupTextCandidateState::present;
            result.text = std::move(normalized);
            return result;
        }
    }

    void PopupOwnerRegistration::publish(uintptr_t owner) noexcept
    {
        if (owner == 0)
            return;

        uint64_t observed = state_.load(std::memory_order_relaxed);
        for (;;)
        {
            uint32_t generation =
                static_cast<uint32_t>(observed >> 32) + 1u;
            if (generation == 0)
                generation = 1;

            const uint64_t desired =
                (static_cast<uint64_t>(generation) << 32) |
                static_cast<uint32_t>(owner);
            if (state_.compare_exchange_weak(
                    observed,
                    desired,
                    std::memory_order_release,
                    std::memory_order_relaxed))
            {
                return;
            }
        }
    }

    void PopupOwnerRegistration::invalidate(uintptr_t owner) noexcept
    {
        if (owner == 0)
            return;

        uint64_t observed = state_.load(std::memory_order_relaxed);
        for (;;)
        {
            if (static_cast<uintptr_t>(
                    static_cast<uint32_t>(observed)) != owner)
            {
                return;
            }

            uint32_t generation =
                static_cast<uint32_t>(observed >> 32) + 1u;
            if (generation == 0)
                generation = 1;
            const uint64_t desired =
                static_cast<uint64_t>(generation) << 32;
            if (state_.compare_exchange_weak(
                    observed,
                    desired,
                    std::memory_order_release,
                    std::memory_order_relaxed))
            {
                return;
            }
        }
    }

    PopupOwnerRegistrationSnapshot
    PopupOwnerRegistration::snapshot() const noexcept
    {
        const uint64_t state = state_.load(std::memory_order_acquire);
        PopupOwnerRegistrationSnapshot result;
        result.owner = static_cast<uintptr_t>(
            static_cast<uint32_t>(state));
        result.generation = static_cast<uint32_t>(state >> 32);
        result.valid = result.owner != 0 && result.generation != 0;
        return result;
    }

    void PopupOwnerRegistration::reset() noexcept
    {
        state_.store(0, std::memory_order_release);
    }

    PopupTextSnapshot inspect_popup_text(
        const MemoryView& memory,
        uintptr_t owner,
        uintptr_t app_base) noexcept
    {
        PopupTextSnapshot snapshot;
        if (owner < MinimumObjectAddress ||
            app_base < MinimumObjectAddress)
        {
            return snapshot;
        }

        uintptr_t owner_vtable = 0;
        if (!read_value(memory, owner, owner_vtable))
            return snapshot;
        if (owner_vtable < app_base)
        {
            snapshot.owner_state = PopupOwnerInspectionState::unsupported;
            return snapshot;
        }

        const uintptr_t owner_vtable_rva = owner_vtable - app_base;
        OwnerDescription description{};
        if (!owner_description(owner_vtable_rva, description))
        {
            snapshot.owner_state = PopupOwnerInspectionState::unsupported;
            return snapshot;
        }

        snapshot.matched = true;
        snapshot.owner_state = PopupOwnerInspectionState::matched;
        snapshot.owner_kind = description.kind;
        snapshot.speech_mode = description.mode;
        snapshot.candidate_count = description.slot_count;
        const ComponentVisibility owner_visibility =
            component_visibility(memory, owner);
        for (size_t index = 0; index < description.slot_count; ++index)
        {
            const uint32_t slot = description.slots[index];
            snapshot.candidates[index].slot_offset = slot;
            if (owner_visibility == ComponentVisibility::unknown)
                continue;
            if (owner_visibility == ComponentVisibility::hidden)
            {
                snapshot.candidates[index].state =
                    PopupTextCandidateState::absent;
                continue;
            }

            uintptr_t child_field = 0;
            uintptr_t child = 0;
            if (!add_address(owner, slot, child_field) ||
                !read_value(memory, child_field, child))
            {
                continue;
            }
            if (child == 0)
            {
                snapshot.candidates[index].state =
                    PopupTextCandidateState::absent;
                continue;
            }

            PopupTextCandidate child_candidate =
                read_clabel_text(memory, child, app_base);
            child_candidate.slot_offset = slot;
            snapshot.candidates[index] = std::move(child_candidate);
        }
        return snapshot;
    }

    PopupObservation PopupTextTracker::observe(
        uint64_t generation,
        PopupOwnerKind owner_kind,
        uint32_t slot_offset,
        std::u16string_view text)
    {
        return observe(
            generation,
            owner_kind,
            slot_offset,
            text.empty()
                ? PopupTextCandidateState::absent
                : PopupTextCandidateState::present,
            text);
    }

    PopupObservation PopupTextTracker::observe(
        uint64_t generation,
        PopupOwnerKind owner_kind,
        uint32_t slot_offset,
        PopupTextCandidateState candidate_state,
        std::u16string_view text)
    {
        if (owner_kind == PopupOwnerKind::none)
        {
            reset();
            return PopupObservation::none;
        }

        if (!have_owner_ || generation_ != generation || owner_kind_ != owner_kind)
        {
            reset();
            have_owner_ = true;
            generation_ = generation;
            owner_kind_ = owner_kind;
        }

        SlotState* state = nullptr;
        for (auto& slot : slots_)
        {
            if (slot.used && slot.slot_offset == slot_offset)
            {
                state = &slot;
                break;
            }
        }
        if (state == nullptr)
        {
            for (auto& slot : slots_)
            {
                if (!slot.used)
                {
                    slot.used = true;
                    slot.slot_offset = slot_offset;
                    state = &slot;
                    break;
                }
            }
        }
        if (state == nullptr)
            return PopupObservation::none;

        if (candidate_state == PopupTextCandidateState::unknown)
        {
            state->stable_reads = 0;
            state->absent_reads = 0;
            state->candidate.clear();
            return PopupObservation::none;
        }

        if (candidate_state == PopupTextCandidateState::absent ||
            text.empty())
        {
            state->stable_reads = 0;
            state->candidate.clear();
            if (state->absent_reads < 2)
                ++state->absent_reads;
            if (state->absent_reads >= 2)
                state->last_spoken.clear();
            return PopupObservation::none;
        }
        state->absent_reads = 0;

        if (state->candidate != text)
        {
            state->candidate.assign(text);
            state->stable_reads = 1;
            return PopupObservation::none;
        }

        if (state->stable_reads < 2)
            ++state->stable_reads;
        if (state->stable_reads < 2 || state->last_spoken == text)
            return PopupObservation::none;

        state->last_spoken.assign(text);
        switch (owner_kind)
        {
        case PopupOwnerKind::modal_ok:
        case PopupOwnerKind::modal_yes_no:
        case PopupOwnerKind::modal_yes_no_cancel:
        case PopupOwnerKind::modal_ok_cancel:
        case PopupOwnerKind::modal_retry_fail:
            return PopupObservation::speak_interrupt;
        case PopupOwnerKind::notice:
        case PopupOwnerKind::important_notice:
            return PopupObservation::speak_queued;
        default:
            return PopupObservation::none;
        }
    }

    void PopupTextTracker::reset() noexcept
    {
        have_owner_ = false;
        generation_ = 0;
        owner_kind_ = PopupOwnerKind::none;
        for (auto& slot : slots_)
        {
            slot.used = false;
            slot.slot_offset = 0;
            slot.stable_reads = 0;
            slot.absent_reads = 0;
            slot.candidate.clear();
            slot.last_spoken.clear();
        }
    }
}
