#include "pol_pml/native_selected_text.h"

#include <algorithm>
#include <limits>
#include <vector>

namespace accessxi::pol_pml
{
    namespace
    {
        constexpr uintptr_t MinimumObjectAddress = 0x10000u;
        constexpr size_t MaximumChildren = 64;
        constexpr size_t MaximumTokenRecords = 64;
        constexpr size_t MaximumTokenRecordBytes = 512;
        constexpr size_t MaximumTokenStreamBytes = 4096;
        constexpr size_t MaximumLabelCharacters = 120;

        bool address_range_fits(uintptr_t address, size_t size) noexcept
        {
            return size != 0 && size - 1 <= std::numeric_limits<uintptr_t>::max() - address;
        }

        template<typename T>
        bool read_value(const MemoryView& memory, uintptr_t address, T& value) noexcept
        {
            return memory.read != nullptr &&
                address_range_fits(address, sizeof(value)) &&
                memory.read(memory.context, address, &value, sizeof(value));
        }

        bool add_address(uintptr_t base, uintptr_t offset, uintptr_t& result) noexcept
        {
            if (offset > std::numeric_limits<uintptr_t>::max() - base)
                return false;
            result = base + offset;
            return true;
        }

        bool object_vtable_rva(
            const MemoryView& memory,
            uintptr_t object,
            uintptr_t app_base,
            uintptr_t& rva) noexcept
        {
            if (object < MinimumObjectAddress || app_base < MinimumObjectAddress)
                return false;

            uintptr_t vtable = 0;
            if (!read_value(memory, object, vtable) || vtable < app_base)
                return false;
            rva = vtable - app_base;
            return true;
        }

        std::u16string read_literal_cpml_text(
            const MemoryView& memory,
            uintptr_t object) noexcept
        {
            uintptr_t model_field = 0;
            if (!add_address(object, 0x244, model_field))
                return {};

            uintptr_t model = 0;
            if (!read_value(memory, model_field, model) || model < MinimumObjectAddress)
                return {};

            uintptr_t stream_field = 0;
            if (!add_address(model, 4, stream_field))
                return {};

            uintptr_t stream = 0;
            if (!read_value(memory, stream_field, stream) || stream < MinimumObjectAddress)
                return {};

            std::u16string result;
            size_t consumed = 0;
            for (size_t record_index = 0; record_index < MaximumTokenRecords; ++record_index)
            {
                uintptr_t record = 0;
                if (!add_address(stream, consumed, record))
                    return {};

                uintptr_t record_size_field = 0;
                if (!add_address(record, 2, record_size_field))
                    return {};

                uint16_t type = 0;
                uint16_t record_bytes = 0;
                if (!read_value(memory, record, type) || !read_value(memory, record_size_field, record_bytes))
                    return {};

                // The native renderer exits its token switch when type >= 0x29.
                if (type >= 0x29)
                    return result;

                // Speaking only literal type-0 records avoids inventing the
                // value of variables, controls, images, or formatting tokens.
                if (type != 0 || record_bytes < 6 || (record_bytes & 1) != 0 ||
                    record_bytes > MaximumTokenRecordBytes ||
                    consumed + record_bytes > MaximumTokenStreamBytes)
                {
                    return {};
                }

                const size_t character_capacity = (record_bytes - 4) / 2;
                std::vector<char16_t> characters(character_capacity);
                uintptr_t payload = 0;
                if (!add_address(record, 4, payload))
                    return {};
                if (memory.read == nullptr ||
                    !address_range_fits(payload, character_capacity * sizeof(char16_t)) ||
                    !memory.read(memory.context, payload, characters.data(), character_capacity * sizeof(char16_t)))
                {
                    return {};
                }

                const auto terminator = std::find(characters.begin(), characters.end(), u'\0');
                if (terminator == characters.end())
                    return {};

                result.append(characters.begin(), terminator);
                if (result.size() > MaximumLabelCharacters)
                    return {};

                consumed += record_bytes;
            }
            return {};
        }

        std::u16string read_cpml_sheet_row(
            const MemoryView& memory,
            uintptr_t sheet,
            uintptr_t app_base) noexcept
        {
            uintptr_t begin_field = 0;
            uintptr_t end_field = 0;
            if (!add_address(sheet, 0x18C, begin_field) ||
                !add_address(sheet, 0x190, end_field))
            {
                return {};
            }

            uintptr_t begin = 0;
            uintptr_t end = 0;
            if (!read_value(memory, begin_field, begin) ||
                !read_value(memory, end_field, end) ||
                begin < MinimumObjectAddress || end < begin)
            {
                return {};
            }

            const uintptr_t byte_count = end - begin;
            if (byte_count == 0 || byte_count % sizeof(uintptr_t) != 0)
                return {};
            const size_t child_count = static_cast<size_t>(byte_count / sizeof(uintptr_t));
            if (child_count > MaximumChildren)
                return {};

            bool saw_image = false;
            bool saw_text = false;
            std::u16string unique_label;
            for (size_t index = 0; index < child_count; ++index)
            {
                uintptr_t child_field = 0;
                if (!add_address(begin, index * sizeof(uintptr_t), child_field))
                    return {};

                uintptr_t child = 0;
                if (!read_value(memory, child_field, child) ||
                    child < MinimumObjectAddress)
                {
                    return {};
                }

                uintptr_t child_rva = 0;
                if (!object_vtable_rva(memory, child, app_base, child_rva))
                    return {};
                if (child_rva == CpmlImageVtableRva)
                {
                    saw_image = true;
                    continue;
                }
                if (child_rva != CpmlTextVtableRva)
                    continue;

                saw_text = true;
                auto label = read_literal_cpml_text(memory, child);
                if (label.empty())
                    return {};
                if (unique_label.empty())
                    unique_label = std::move(label);
                else if (unique_label != label)
                    return {};
            }

            if (!saw_image || !saw_text)
                return {};
            return unique_label;
        }

        std::u16string read_cbutton_label(
            const MemoryView& memory,
            uintptr_t button) noexcept
        {
            uintptr_t begin_field = 0;
            uintptr_t end_field = 0;
            uintptr_t length_field = 0;
            if (!add_address(button, 0x184, begin_field) ||
                !add_address(button, 0x188, end_field) ||
                !add_address(button, 0x21A, length_field))
            {
                return {};
            }

            uintptr_t begin = 0;
            uintptr_t end = 0;
            int16_t length = 0;
            if (!read_value(memory, begin_field, begin) ||
                !read_value(memory, end_field, end) ||
                !read_value(memory, length_field, length) ||
                begin < MinimumObjectAddress || end < begin ||
                length <= 0 || static_cast<size_t>(length) > MaximumLabelCharacters)
            {
                return {};
            }

            const uintptr_t byte_count = end - begin;
            if ((byte_count & 1) != 0 || byte_count / 2 < static_cast<uintptr_t>(length + 1))
                return {};

            std::vector<char16_t> characters(static_cast<size_t>(length) + 1);
            if (memory.read == nullptr ||
                !address_range_fits(begin, characters.size() * sizeof(char16_t)) ||
                !memory.read(memory.context, begin, characters.data(), characters.size() * sizeof(char16_t)) ||
                characters.back() != u'\0')
            {
                return {};
            }
            return std::u16string(characters.begin(), characters.end() - 1);
        }
    }

    SheetFocusEventDisposition classify_sheet_focus_event(
        bool have_pending_sheet_row,
        uintptr_t pending_sheet_row,
        uintptr_t pending_nested_child,
        bool incoming_is_sheet_row,
        uintptr_t incoming_manager,
        uintptr_t incoming_child) noexcept
    {
        if (!have_pending_sheet_row || incoming_is_sheet_row)
            return SheetFocusEventDisposition::replace;
        if (pending_sheet_row != 0 && incoming_manager == pending_sheet_row)
            return SheetFocusEventDisposition::capture_nested_child;
        if (pending_nested_child != 0 &&
            incoming_manager == pending_nested_child &&
            incoming_child == pending_nested_child)
        {
            return SheetFocusEventDisposition::preserve;
        }
        return SheetFocusEventDisposition::replace;
    }

    std::u16string read_selected_control_text(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept
    {
        uintptr_t vtable_rva = 0;
        if (!object_vtable_rva(memory, object, app_base, vtable_rva))
            return {};
        if (vtable_rva == CpmlSheetVtableRva)
            return read_cpml_sheet_row(memory, object, app_base);
        if (vtable_rva == CButtonVtableRva)
            return read_cbutton_label(memory, object);
        return {};
    }
}
