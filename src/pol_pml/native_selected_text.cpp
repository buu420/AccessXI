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
        constexpr size_t MaximumRenderedLines = 8;
        constexpr size_t MaximumRenderedFragmentsPerLine = 32;
        constexpr uintptr_t RenderedTextFragmentVtableRva = 0x003E4A1Cu;

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

        bool read_native_pointer_list(
            const MemoryView& memory,
            uintptr_t container,
            size_t maximum_count,
            std::vector<uintptr_t>& values) noexcept
        {
            values.clear();

            uintptr_t head_field = 0;
            uintptr_t count_field = 0;
            if (!add_address(container, 4, head_field) ||
                !add_address(container, 8, count_field))
            {
                return false;
            }

            uintptr_t head = 0;
            uint32_t count = 0;
            if (!read_value(memory, head_field, head) ||
                !read_value(memory, count_field, count) ||
                count == 0 || count > maximum_count || head < MinimumObjectAddress)
            {
                return false;
            }

            uintptr_t head_previous_field = 0;
            uintptr_t node = 0;
            uintptr_t head_previous = 0;
            if (!add_address(head, 4, head_previous_field) ||
                !read_value(memory, head, node) ||
                !read_value(memory, head_previous_field, head_previous) ||
                node < MinimumObjectAddress || head_previous < MinimumObjectAddress)
            {
                return false;
            }

            values.reserve(count);
            uintptr_t previous = head;
            std::vector<uintptr_t> visited_nodes;
            visited_nodes.reserve(count);
            for (uint32_t index = 0; index < count; ++index)
            {
                if (node == head || node < MinimumObjectAddress ||
                    std::find(visited_nodes.begin(), visited_nodes.end(), node) != visited_nodes.end())
                {
                    return false;
                }

                uintptr_t previous_field = 0;
                uintptr_t value_field = 0;
                if (!add_address(node, 4, previous_field) ||
                    !add_address(node, 8, value_field))
                {
                    return false;
                }

                uintptr_t next = 0;
                uintptr_t native_previous = 0;
                uintptr_t value = 0;
                if (!read_value(memory, node, next) ||
                    !read_value(memory, previous_field, native_previous) ||
                    !read_value(memory, value_field, value) ||
                    native_previous != previous || value < MinimumObjectAddress)
                {
                    return false;
                }

                visited_nodes.push_back(node);
                values.push_back(value);
                previous = node;
                node = next;
            }

            return node == head && previous == head_previous;
        }

        bool append_rendered_characters(
            const MemoryView& memory,
            uintptr_t fragment,
            std::u16string& output) noexcept
        {
            uintptr_t characters_field = 0;
            uintptr_t length_field = 0;
            if (!add_address(fragment, 0x28, characters_field) ||
                !add_address(fragment, 0x2C, length_field))
            {
                return false;
            }

            uintptr_t characters_address = 0;
            uint32_t length = 0;
            if (!read_value(memory, characters_field, characters_address) ||
                !read_value(memory, length_field, length) ||
                characters_address < MinimumObjectAddress || length == 0 ||
                length > MaximumLabelCharacters - output.size())
            {
                return false;
            }

            std::vector<char16_t> characters(length);
            if (memory.read == nullptr ||
                !address_range_fits(characters_address, characters.size() * sizeof(char16_t)) ||
                !memory.read(
                    memory.context,
                    characters_address,
                    characters.data(),
                    characters.size() * sizeof(char16_t)))
            {
                return false;
            }

            bool saw_visible_character = false;
            for (size_t index = 0; index < characters.size(); ++index)
            {
                const char16_t character = characters[index];
                if (character == u'\0' || character < 0x20 ||
                    (character >= 0x7F && character <= 0x9F))
                {
                    return false;
                }
                if (character >= 0xD800 && character <= 0xDBFF)
                {
                    if (index + 1 >= characters.size() ||
                        characters[index + 1] < 0xDC00 || characters[index + 1] > 0xDFFF)
                    {
                        return false;
                    }
                    ++index;
                    saw_visible_character = true;
                    continue;
                }
                if (character >= 0xDC00 && character <= 0xDFFF)
                    return false;
                if (character != u' ' && character != 0x00A0)
                    saw_visible_character = true;
            }
            if (!saw_visible_character)
                return false;

            output.append(characters.begin(), characters.end());
            return true;
        }

        std::u16string read_native_wide_string_field(
            const MemoryView& memory,
            uintptr_t field) noexcept
        {
            uintptr_t length_field = 0;
            uintptr_t capacity_field = 0;
            if (!add_address(field, 0x10, length_field) ||
                !add_address(field, 0x14, capacity_field))
            {
                return {};
            }

            uint32_t length = 0;
            uint32_t capacity = 0;
            if (!read_value(memory, length_field, length) ||
                !read_value(memory, capacity_field, capacity) ||
                length == 0 || length > MaximumLabelCharacters || capacity < length)
            {
                return {};
            }

            uintptr_t characters_address = field;
            if (capacity >= 8)
            {
                if (!read_value(memory, field, characters_address) ||
                    characters_address < MinimumObjectAddress)
                {
                    return {};
                }
            }

            uintptr_t terminator_address = 0;
            if (!add_address(characters_address, length * sizeof(char16_t), terminator_address))
                return {};

            char16_t terminator = 1;
            if (!read_value(memory, terminator_address, terminator) || terminator != u'\0')
                return {};

            std::u16string result(length, u'\0');
            if (memory.read == nullptr ||
                !address_range_fits(characters_address, result.size() * sizeof(char16_t)) ||
                !memory.read(
                    memory.context,
                    characters_address,
                    result.data(),
                    result.size() * sizeof(char16_t)))
            {
                return {};
            }

            bool saw_visible_character = false;
            for (size_t index = 0; index < result.size(); ++index)
            {
                const char16_t character = result[index];
                if (character == u'\0' || character < 0x20 ||
                    (character >= 0x7F && character <= 0x9F))
                {
                    return {};
                }
                if (character >= 0xD800 && character <= 0xDBFF)
                {
                    if (index + 1 >= result.size() ||
                        result[index + 1] < 0xDC00 || result[index + 1] > 0xDFFF)
                    {
                        return {};
                    }
                    ++index;
                    saw_visible_character = true;
                    continue;
                }
                if (character >= 0xDC00 && character <= 0xDFFF)
                    return {};
                if (character != u' ' && character != 0x00A0)
                    saw_visible_character = true;
            }
            return saw_visible_character ? result : std::u16string{};
        }

        std::u16string read_cpml_image_alt(
            const MemoryView& memory,
            uintptr_t image) noexcept
        {
            uintptr_t alt_field = 0;
            if (!add_address(image, 0x11C, alt_field))
                return {};
            return read_native_wide_string_field(memory, alt_field);
        }

        std::u16string read_rendered_cpml_text(
            const MemoryView& memory,
            uintptr_t object,
            uintptr_t app_base) noexcept
        {
            uintptr_t lines_container = 0;
            if (!add_address(object, 0x1CC, lines_container))
                return {};

            std::vector<uintptr_t> lines;
            if (!read_native_pointer_list(memory, lines_container, MaximumRenderedLines, lines))
                return {};

            std::u16string result;
            for (const uintptr_t line : lines)
            {
                uintptr_t fragments_container = 0;
                if (!add_address(line, 0x20, fragments_container))
                    return {};

                std::vector<uintptr_t> fragments;
                if (!read_native_pointer_list(
                        memory,
                        fragments_container,
                        MaximumRenderedFragmentsPerLine,
                        fragments))
                {
                    return {};
                }

                std::u16string line_text;
                for (const uintptr_t fragment : fragments)
                {
                    uintptr_t fragment_rva = 0;
                    if (!object_vtable_rva(memory, fragment, app_base, fragment_rva) ||
                        fragment_rva != RenderedTextFragmentVtableRva ||
                        !append_rendered_characters(memory, fragment, line_text))
                    {
                        return {};
                    }
                }

                if (line_text.empty())
                    return {};
                if (!result.empty() && result.back() != u' ' && line_text.front() != u' ')
                {
                    if (result.size() >= MaximumLabelCharacters)
                        return {};
                    result.push_back(u' ');
                }
                if (line_text.size() > MaximumLabelCharacters - result.size())
                    return {};
                result.append(line_text);
            }
            return result;
        }

        bool read_cpml_sheet_children(
            const MemoryView& memory,
            uintptr_t sheet,
            std::vector<uintptr_t>& children) noexcept
        {
            children.clear();
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
                return false;
            const size_t child_count = static_cast<size_t>(byte_count / sizeof(uintptr_t));
            if (child_count > MaximumChildren)
                return false;

            children.reserve(child_count);
            for (size_t index = 0; index < child_count; ++index)
            {
                uintptr_t child_field = 0;
                if (!add_address(begin, index * sizeof(uintptr_t), child_field))
                    return false;

                uintptr_t child = 0;
                if (!read_value(memory, child_field, child) || child < MinimumObjectAddress)
                    return false;
                children.push_back(child);
            }
            return true;
        }

        std::u16string read_cpml_sheet_row(
            const MemoryView& memory,
            uintptr_t sheet,
            uintptr_t app_base) noexcept
        {
            std::vector<uintptr_t> children;
            if (!read_cpml_sheet_children(memory, sheet, children))
                return {};

            bool saw_image = false;
            bool saw_text = false;
            std::u16string unique_label;
            for (const uintptr_t child : children)
            {
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
                    label = read_rendered_cpml_text(memory, child, app_base);
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

        std::u16string read_image_only_sheet_caption(
            const MemoryView& memory,
            uintptr_t sheet,
            uintptr_t captured_nested_child,
            uintptr_t app_base) noexcept
        {
            if (captured_nested_child < MinimumObjectAddress)
                return {};

            std::vector<uintptr_t> children;
            if (!read_cpml_sheet_children(memory, sheet, children) ||
                std::find(children.begin(), children.end(), captured_nested_child) == children.end())
            {
                return {};
            }

            for (const uintptr_t child : children)
            {
                uintptr_t child_rva = 0;
                if (!object_vtable_rva(memory, child, app_base, child_rva))
                    return {};
                if (child_rva == CpmlTextVtableRva)
                    return {};
            }

            uintptr_t nested_rva = 0;
            if (!object_vtable_rva(memory, captured_nested_child, app_base, nested_rva) ||
                nested_rva != CpmlImageVtableRva)
            {
                return {};
            }
            return read_cpml_image_alt(memory, captured_nested_child);
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

    SelectedImageInspection inspect_selected_image_path(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base,
        uintptr_t captured_nested_child) noexcept
    {
        SelectedImageInspection inspection;
        uintptr_t object_rva = 0;
        if (!object_vtable_rva(memory, object, app_base, object_rva))
            return inspection;

        if (object_rva == CpmlImageVtableRva)
        {
            inspection.image = object;
        }
        else if (object_rva == CpmlSheetVtableRva)
        {
            inspection.object_is_sheet = true;
            std::vector<uintptr_t> children;
            if (!read_cpml_sheet_children(memory, object, children))
                return inspection;

            inspection.child_count = static_cast<uint32_t>(children.size());
            for (const uintptr_t child : children)
            {
                uintptr_t child_rva = 0;
                if (!object_vtable_rva(memory, child, app_base, child_rva))
                {
                    ++inspection.other_child_count;
                    continue;
                }
                if (child_rva == CpmlImageVtableRva)
                    ++inspection.image_child_count;
                else if (child_rva == CpmlTextVtableRva)
                    ++inspection.text_child_count;
                else
                    ++inspection.other_child_count;
            }

            inspection.nested_is_direct_child =
                std::find(children.begin(), children.end(), captured_nested_child) != children.end();
            if (!inspection.nested_is_direct_child)
                return inspection;

            uintptr_t nested_rva = 0;
            if (!object_vtable_rva(memory, captured_nested_child, app_base, nested_rva) ||
                nested_rva != CpmlImageVtableRva)
            {
                return inspection;
            }
            inspection.image = captured_nested_child;
        }
        else
        {
            return inspection;
        }

        inspection.image_vtable_rva = CpmlImageVtableRva;
        inspection.matched = true;

        uintptr_t field = 0;
        if (add_address(inspection.image, 0x130, field))
            read_value(memory, field, inspection.primary_capacity_130);
        if (add_address(inspection.image, 0x14C, field))
            read_value(memory, field, inspection.alternate_capacity_14c);
        if (add_address(inspection.image, 0x154, field))
            read_value(memory, field, inspection.linked_label_object);
        if (inspection.linked_label_object >= MinimumObjectAddress)
        {
            object_vtable_rva(
                memory,
                inspection.linked_label_object,
                app_base,
                inspection.linked_label_vtable_rva);
        }

        if (add_address(inspection.image, 0x11C, field))
            inspection.primary_alt = read_native_wide_string_field(memory, field);
        if (add_address(inspection.image, 0x138, field))
            inspection.alternate_alt = read_native_wide_string_field(memory, field);
        return inspection;
    }

    std::string choose_selected_image_getter_caption(
        const std::string& primary,
        const std::string& alternate)
    {
        if (primary.empty() || primary != alternate)
            return {};

        const size_t caption_begin = primary.front() == '$' ? 1u : 0u;
        if (caption_begin == primary.size())
            return {};
        return primary.substr(caption_begin);
    }

    std::u16string read_bounded_native_image_getter_text(
        const MemoryView& memory,
        uintptr_t characters) noexcept
    {
        if (memory.read == nullptr || characters < MinimumObjectAddress)
            return {};

        std::u16string result;
        result.reserve(MaximumLabelCharacters);
        for (size_t index = 0; index <= MaximumLabelCharacters; ++index)
        {
            uintptr_t character_address = 0;
            if (!add_address(characters, index * sizeof(char16_t), character_address))
                return {};

            char16_t character = u'\0';
            if (!read_value(memory, character_address, character))
                return {};
            if (character == u'\0')
                return result.empty() ? std::u16string{} : result;
            if (index == MaximumLabelCharacters)
                return {};
            result.push_back(character);
        }
        return {};
    }

    bool selected_image_getter_caption_allowed(const std::string& caption) noexcept
    {
        if (caption.size() < 2 || caption.size() > MaximumLabelCharacters)
            return false;

        std::string lower = caption;
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char character) {
            if (character >= 'A' && character <= 'Z')
                return static_cast<char>(character - 'A' + 'a');
            return static_cast<char>(character);
        });
        return lower.find("http") == std::string::npos &&
            lower.find(".pml") == std::string::npos &&
            lower.find(".esd") == std::string::npos &&
            lower.find(".tm2") == std::string::npos &&
            lower.find('\\') == std::string::npos &&
            lower.find('/') == std::string::npos;
    }

    namespace
    {
        bool read_exact_native_pulldown_list(
            const MemoryView& memory,
            uintptr_t object,
            uintptr_t app_base,
            uintptr_t& list) noexcept
        {
            list = 0;

            uintptr_t object_rva = 0;
            if (!object_vtable_rva(memory, object, app_base, object_rva) ||
                object_rva != CPulldownVtableRva)
            {
                return false;
            }

            uintptr_t list_field = 0;
            uintptr_t combo_box_list_field = 0;
            uintptr_t combo_box_list = 0;
            if (!add_address(object, NativePulldownListOffset, list_field) ||
                !add_address(
                    object,
                    NativePulldownComboBoxListOffset,
                    combo_box_list_field) ||
                !read_value(memory, list_field, list) ||
                !read_value(
                    memory,
                    combo_box_list_field,
                    combo_box_list) ||
                list < MinimumObjectAddress ||
                combo_box_list < MinimumObjectAddress)
            {
                list = 0;
                return false;
            }

            uintptr_t list_rva = 0;
            uintptr_t combo_box_list_rva = 0;
            if (!object_vtable_rva(memory, list, app_base, list_rva) ||
                list_rva != CListVtableRva ||
                !object_vtable_rva(
                    memory,
                    combo_box_list,
                    app_base,
                    combo_box_list_rva) ||
                combo_box_list_rva != CComboBoxListVtableRva)
            {
                list = 0;
                return false;
            }

            uintptr_t owned_list_field = 0;
            uintptr_t owned_list = 0;
            if (!add_address(
                    combo_box_list,
                    NativeComboBoxListOwnedListOffset,
                    owned_list_field) ||
                !read_value(memory, owned_list_field, owned_list) ||
                owned_list != list)
            {
                list = 0;
                return false;
            }
            return true;
        }
    }

    NativePulldownSelectionSnapshot read_native_pulldown_selection(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept
    {
        NativePulldownSelectionSnapshot snapshot;
        constexpr int32_t MaximumSelectedIndex = 1023;

        uintptr_t list = 0;
        if (!read_exact_native_pulldown_list(
                memory,
                object,
                app_base,
                list))
        {
            return snapshot;
        }

        uintptr_t selection_model_field = 0;
        uintptr_t selection_model = 0;
        if (!add_address(
                list,
                NativeListSelectionModelOffset,
                selection_model_field) ||
            !read_value(memory, selection_model_field, selection_model) ||
            selection_model < MinimumObjectAddress)
        {
            return snapshot;
        }

        uintptr_t selection_model_rva = 0;
        uintptr_t selection_vtable = 0;
        if (!object_vtable_rva(
                memory,
                selection_model,
                app_base,
                selection_model_rva) ||
            selection_model_rva != CDefaultListSelectionModelVtableRva ||
            !read_value(memory, selection_model, selection_vtable))
        {
            return snapshot;
        }

        uintptr_t maximum_slot = 0;
        uintptr_t minimum_slot = 0;
        uintptr_t maximum_getter = 0;
        uintptr_t minimum_getter = 0;
        uintptr_t expected_maximum_getter = 0;
        uintptr_t expected_minimum_getter = 0;
        if (!add_address(
                selection_vtable,
                NativeListSelectionMaximumSlotOffset,
                maximum_slot) ||
            !add_address(
                selection_vtable,
                NativeListSelectionMinimumSlotOffset,
                minimum_slot) ||
            !add_address(
                app_base,
                NativeListSelectionMaximumGetterRva,
                expected_maximum_getter) ||
            !add_address(
                app_base,
                NativeListSelectionMinimumGetterRva,
                expected_minimum_getter) ||
            !read_value(memory, maximum_slot, maximum_getter) ||
            !read_value(memory, minimum_slot, minimum_getter) ||
            maximum_getter != expected_maximum_getter ||
            minimum_getter != expected_minimum_getter)
        {
            return snapshot;
        }

        uintptr_t first_index_field = 0;
        uintptr_t last_index_field = 0;
        int32_t first_index = -1;
        int32_t last_index = -1;
        if (!add_address(
                selection_model,
                NativeListSelectionFirstIndexOffset,
                first_index_field) ||
            !add_address(
                selection_model,
                NativeListSelectionLastIndexOffset,
                last_index_field) ||
            !read_value(memory, first_index_field, first_index) ||
            !read_value(memory, last_index_field, last_index) ||
            first_index < 0 ||
            first_index != last_index ||
            first_index > MaximumSelectedIndex)
        {
            return snapshot;
        }

        snapshot.matched = true;
        snapshot.selected_index = static_cast<uint32_t>(first_index);
        return snapshot;
    }

    NativePulldownHighlightSnapshot read_native_pulldown_highlight(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept
    {
        NativePulldownHighlightSnapshot snapshot;

        uintptr_t list = 0;
        if (!read_exact_native_pulldown_list(
                memory,
                object,
                app_base,
                list))
        {
            return snapshot;
        }

        uintptr_t data_model_field = 0;
        uintptr_t highlight_field = 0;
        uintptr_t data_model = 0;
        int16_t highlighted_index = -1;
        if (!add_address(
                list,
                NativeListDataModelOffset,
                data_model_field) ||
            !add_address(
                list,
                NativeListHighlightIndexOffset,
                highlight_field) ||
            !read_value(memory, data_model_field, data_model) ||
            data_model < MinimumObjectAddress ||
            !read_value(memory, highlight_field, highlighted_index) ||
            highlighted_index < -1 ||
            highlighted_index > 1)
        {
            return snapshot;
        }

        snapshot.matched = true;
        snapshot.active = highlighted_index >= 0;
        snapshot.highlighted_index =
            snapshot.active
                ? static_cast<uint32_t>(highlighted_index)
                : 0;
        return snapshot;
    }

    std::u16string read_selected_control_text(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base,
        uintptr_t captured_nested_child) noexcept
    {
        uintptr_t vtable_rva = 0;
        if (!object_vtable_rva(memory, object, app_base, vtable_rva))
            return {};
        if (vtable_rva == CpmlSheetVtableRva)
        {
            auto label = read_cpml_sheet_row(memory, object, app_base);
            if (!label.empty())
                return label;
            return read_image_only_sheet_caption(
                memory,
                object,
                captured_nested_child,
                app_base);
        }
        if (vtable_rva == CpmlImageVtableRva)
            return read_cpml_image_alt(memory, object);
        if (vtable_rva == CButtonVtableRva)
            return read_cbutton_label(memory, object);
        if (vtable_rva == CpmlFormSelectEditorVtableRva)
        {
            auto label = read_rendered_cpml_text(memory, object, app_base);
            if (!label.empty())
                return label;
            return read_literal_cpml_text(memory, object);
        }
        return {};
    }
}
