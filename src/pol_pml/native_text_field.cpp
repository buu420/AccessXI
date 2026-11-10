#include "pol_pml/native_text_field.h"

#include <limits>
#include <vector>

namespace accessxi::pol_pml
{
    namespace
    {
        constexpr uintptr_t MinimumObjectAddress = 0x10000u;
        constexpr size_t MaximumFieldCharacters = 256u;
        constexpr uint32_t MaximumNativeCapacity = 4096u;

        bool address_range_fits(uintptr_t address, size_t size) noexcept
        {
            return size != 0 &&
                size - 1 <= std::numeric_limits<uintptr_t>::max() - address;
        }

        bool add_address(uintptr_t base, uintptr_t offset, uintptr_t& result) noexcept
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

        bool object_vtable_rva(
            const MemoryView& memory,
            uintptr_t object,
            uintptr_t app_base,
            uintptr_t& rva) noexcept
        {
            if (object < MinimumObjectAddress ||
                app_base < MinimumObjectAddress)
            {
                return false;
            }

            uintptr_t vtable = 0;
            if (!read_value(memory, object, vtable) || vtable < app_base)
                return false;
            rva = vtable - app_base;
            return true;
        }

        bool valid_utf16(std::u16string_view value) noexcept
        {
            for (size_t index = 0; index < value.size(); ++index)
            {
                const char16_t character = value[index];
                if (character == u'\0' || character < 0x20 ||
                    (character >= 0x7F && character <= 0x9F))
                {
                    return false;
                }
                if (character >= 0xD800 && character <= 0xDBFF)
                {
                    if (index + 1 >= value.size() ||
                        value[index + 1] < 0xDC00 ||
                        value[index + 1] > 0xDFFF)
                    {
                        return false;
                    }
                    ++index;
                    continue;
                }
                if (character >= 0xDC00 && character <= 0xDFFF)
                    return false;
            }
            return true;
        }

        // Reads the control an owner holds at a proven offset and identifies
        // its exact class.
        bool read_owned_control(
            const MemoryView& memory,
            uintptr_t owner,
            uintptr_t offset,
            uintptr_t app_base,
            uintptr_t& control,
            uintptr_t& control_rva) noexcept
        {
            uintptr_t control_field = 0;
            return add_address(owner, offset, control_field) &&
                read_value(memory, control_field, control) &&
                object_vtable_rva(memory, control, app_base, control_rva);
        }

        // Every scroll wrapper owns its field at +0x208 (9994c). A plain
        // CScrollTextField may own either field class; each PML wrapper is
        // built around exactly one (21c961, 21c8e4).
        bool resolve_scroll_wrapper(
            const MemoryView& memory,
            uintptr_t wrapper,
            uintptr_t wrapper_rva,
            uintptr_t app_base,
            uintptr_t& field,
            NativeTextFieldKind& kind) noexcept
        {
            uintptr_t field_rva = 0;
            if (!read_owned_control(
                    memory,
                    wrapper,
                    NativeScrollTextFieldInnerControlOffset,
                    app_base,
                    field,
                    field_rva))
            {
                return false;
            }

            const bool plain_wrapper = wrapper_rva == CScrollTextFieldVtableRva;
            if (field_rva == CTextFieldVtableRva &&
                (plain_wrapper || wrapper_rva == CpmlFcScrollTextVtableRva))
            {
                kind = NativeTextFieldKind::text;
                return true;
            }
            if (field_rva == CPasswordFieldVtableRva &&
                (plain_wrapper || wrapper_rva == CpmlFcScrollPasswordVtableRva))
            {
                kind = NativeTextFieldKind::password;
                return true;
            }
            return false;
        }

        // A field is reached in at most two proven links: from itself, from
        // a scroll wrapper, or from a PML form through the scroll wrapper its
        // constructor built (21d309, 21d099). A form never owns a bare field;
        // the only other write to that link clears it (21d662).
        bool resolve_exact_field(
            const MemoryView& memory,
            uintptr_t object,
            uintptr_t app_base,
            uintptr_t& field,
            NativeTextFieldKind& kind) noexcept
        {
            uintptr_t object_rva = 0;
            if (!object_vtable_rva(memory, object, app_base, object_rva))
                return false;

            if (object_rva == CTextFieldVtableRva)
            {
                field = object;
                kind = NativeTextFieldKind::text;
                return true;
            }
            if (object_rva == CPasswordFieldVtableRva)
            {
                field = object;
                kind = NativeTextFieldKind::password;
                return true;
            }

            if (object_rva == CScrollTextFieldVtableRva ||
                object_rva == CpmlFcScrollTextVtableRva ||
                object_rva == CpmlFcScrollPasswordVtableRva)
            {
                return resolve_scroll_wrapper(
                    memory,
                    object,
                    object_rva,
                    app_base,
                    field,
                    kind);
            }

            uintptr_t expected_wrapper_rva = 0;
            if (object_rva == CpmlFormTextVtableRva)
                expected_wrapper_rva = CpmlFcScrollTextVtableRva;
            else if (object_rva == CpmlFormPasswordVtableRva)
                expected_wrapper_rva = CpmlFcScrollPasswordVtableRva;
            else
                return false;

            uintptr_t wrapper = 0;
            uintptr_t wrapper_rva = 0;
            return read_owned_control(
                    memory,
                    object,
                    NativeFormFieldInnerControlOffset,
                    app_base,
                    wrapper,
                    wrapper_rva) &&
                wrapper_rva == expected_wrapper_rva &&
                resolve_scroll_wrapper(
                    memory,
                    wrapper,
                    wrapper_rva,
                    app_base,
                    field,
                    kind);
        }

        bool read_exact_model(
            const MemoryView& memory,
            uintptr_t field,
            uintptr_t app_base,
            NativeTextFieldKind kind,
            uintptr_t& model,
            uint32_t& raw_length) noexcept
        {
            uintptr_t active_field = 0;
            uintptr_t owned_field = 0;
            if (!add_address(
                    field,
                    NativeTextFieldActiveModelOffset,
                    active_field) ||
                !add_address(
                    field,
                    NativeTextFieldOwnedModelOffset,
                    owned_field))
            {
                return false;
            }

            uintptr_t owned_model = 0;
            if (!read_value(memory, active_field, model) ||
                !read_value(memory, owned_field, owned_model) ||
                model < MinimumObjectAddress ||
                model != owned_model)
            {
                return false;
            }

            const uintptr_t expected_model_rva =
                kind == NativeTextFieldKind::password
                    ? CPasswordFieldModelVtableRva
                    : CTextFieldModelVtableRva;
            uintptr_t model_rva = 0;
            if (!object_vtable_rva(
                    memory,
                    model,
                    app_base,
                    model_rva) ||
                model_rva != expected_model_rva)
            {
                return false;
            }

            uintptr_t model_vtable = 0;
            uintptr_t length_slot = 0;
            uintptr_t length_getter = 0;
            if (!read_value(memory, model, model_vtable) ||
                !add_address(
                    model_vtable,
                    NativeTextModelLengthSlotOffset,
                    length_slot) ||
                !read_value(memory, length_slot, length_getter) ||
                length_getter != app_base + NativeTextModelLengthGetterRva)
            {
                return false;
            }

            uintptr_t raw_length_field = 0;
            if (!add_address(
                    model,
                    NativeTextModelRawLengthOffset,
                    raw_length_field) ||
                !read_value(memory, raw_length_field, raw_length) ||
                raw_length == 0 ||
                raw_length > MaximumFieldCharacters + 1)
            {
                return false;
            }
            return true;
        }

        bool exact_password_mask_template(
            const MemoryView& memory,
            uintptr_t field) noexcept
        {
            uintptr_t template_address = 0;
            if (!add_address(
                    field,
                    NativePasswordMaskTemplateOffset,
                    template_address))
            {
                return false;
            }

            for (size_t index = 0; index < NativePasswordMaskCapacity; ++index)
            {
                uintptr_t character_address = 0;
                char16_t character = u'\0';
                if (!add_address(
                        template_address,
                        index * sizeof(char16_t),
                        character_address) ||
                    !read_value(memory, character_address, character) ||
                    character != u'*')
                {
                    return false;
                }
            }

            uintptr_t terminator_address = 0;
            char16_t terminator = 1;
            return add_address(
                    template_address,
                    NativePasswordMaskCapacity * sizeof(char16_t),
                    terminator_address) &&
                read_value(memory, terminator_address, terminator) &&
                terminator == u'\0';
        }

        bool read_normal_value(
            const MemoryView& memory,
            uintptr_t model,
            uint32_t raw_length,
            std::u16string& value) noexcept
        {
            uintptr_t string_field = 0;
            uintptr_t length_field = 0;
            uintptr_t capacity_field = 0;
            if (!add_address(
                    model,
                    NativeTextModelStringOffset,
                    string_field) ||
                !add_address(
                    string_field,
                    NativeWideStringLengthOffset,
                    length_field) ||
                !add_address(
                    string_field,
                    NativeWideStringCapacityOffset,
                    capacity_field))
            {
                return false;
            }

            uint32_t string_length = 0;
            uint32_t capacity = 0;
            if (!read_value(memory, length_field, string_length) ||
                !read_value(memory, capacity_field, capacity) ||
                string_length != raw_length ||
                capacity < raw_length ||
                capacity > MaximumNativeCapacity)
            {
                return false;
            }

            uintptr_t inline_or_pointer = 0;
            if (!add_address(
                    string_field,
                    NativeWideStringInlineBufferOffset,
                    inline_or_pointer))
            {
                return false;
            }

            uintptr_t characters = inline_or_pointer;
            if (capacity >= 8)
            {
                if (!read_value(memory, inline_or_pointer, characters) ||
                    characters < MinimumObjectAddress)
                {
                    return false;
                }
            }

            const size_t visible_length = raw_length - 1;
            value.assign(visible_length, u'\0');
            if (!value.empty() &&
                (memory.read == nullptr ||
                 !address_range_fits(
                     characters,
                     value.size() * sizeof(char16_t)) ||
                 !memory.read(
                     memory.context,
                     characters,
                     value.data(),
                     value.size() * sizeof(char16_t))))
            {
                value.clear();
                return false;
            }
            if (!valid_utf16(value))
            {
                value.clear();
                return false;
            }

            uintptr_t model_sentinel_address = 0;
            uintptr_t native_terminator_address = 0;
            char16_t model_sentinel = 1;
            char16_t native_terminator = 1;
            if (!add_address(
                    characters,
                    visible_length * sizeof(char16_t),
                    model_sentinel_address) ||
                !add_address(
                    characters,
                    raw_length * sizeof(char16_t),
                    native_terminator_address) ||
                !read_value(
                    memory,
                    model_sentinel_address,
                    model_sentinel) ||
                !read_value(
                    memory,
                    native_terminator_address,
                    native_terminator) ||
                model_sentinel != NativeTextModelSentinel ||
                native_terminator != u'\0')
            {
                value.clear();
                return false;
            }
            return true;
        }
    }

    NativeTextFieldSnapshot read_native_text_field(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept
    {
        NativeTextFieldSnapshot snapshot;
        if (memory.read == nullptr)
            return snapshot;

        uintptr_t field = 0;
        NativeTextFieldKind kind = NativeTextFieldKind::none;
        if (!resolve_exact_field(
                memory,
                object,
                app_base,
                field,
                kind))
        {
            return snapshot;
        }

        uintptr_t model = 0;
        uint32_t raw_length = 0;
        if (!read_exact_model(
                memory,
                field,
                app_base,
                kind,
                model,
                raw_length))
        {
            return snapshot;
        }

        snapshot.kind = kind;
        snapshot.field = field;
        snapshot.character_count = raw_length - 1;
        if (kind == NativeTextFieldKind::password)
        {
            if (!exact_password_mask_template(memory, field))
                return {};
        }
        else if (!read_normal_value(
                     memory,
                     model,
                     raw_length,
                     snapshot.value))
        {
            return {};
        }

        snapshot.matched = true;
        return snapshot;
    }
}
