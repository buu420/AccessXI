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

            uintptr_t expected_inner_rva = 0;
            uintptr_t inner_control_offset =
                NativeFormFieldInnerControlOffset;
            if (object_rva == CScrollTextFieldVtableRva)
            {
                inner_control_offset =
                    NativeScrollTextFieldInnerControlOffset;
            }
            else if (object_rva == CpmlFormTextVtableRva)
            {
                expected_inner_rva = CTextFieldVtableRva;
                kind = NativeTextFieldKind::text;
            }
            else if (object_rva == CpmlFormPasswordVtableRva)
            {
                expected_inner_rva = CPasswordFieldVtableRva;
                kind = NativeTextFieldKind::password;
            }
            else
            {
                return false;
            }

            uintptr_t inner_field_address = 0;
            if (!add_address(
                    object,
                    inner_control_offset,
                    inner_field_address) ||
                !read_value(memory, inner_field_address, field) ||
                field < MinimumObjectAddress)
            {
                return false;
            }

            uintptr_t inner_rva = 0;
            if (!object_vtable_rva(
                    memory,
                    field,
                    app_base,
                    inner_rva))
            {
                return false;
            }

            if (object_rva == CScrollTextFieldVtableRva)
            {
                if (inner_rva == CTextFieldVtableRva)
                {
                    kind = NativeTextFieldKind::text;
                    return true;
                }
                if (inner_rva == CPasswordFieldVtableRva)
                {
                    kind = NativeTextFieldKind::password;
                    return true;
                }
                return false;
            }
            return inner_rva == expected_inner_rva;
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
