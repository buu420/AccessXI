#include "pol_pml/native_text_field.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
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
        uintptr_t forbidden_begin = 0;
        uintptr_t forbidden_end = 0;
        bool touched_forbidden = false;

        template<typename T>
        void write(uintptr_t address, const T& value)
        {
            const auto* source = reinterpret_cast<const uint8_t*>(&value);
            for (size_t index = 0; index < sizeof(T); ++index)
                bytes[address + index] = source[index];
        }

        void write_utf16(uintptr_t address, const std::u16string& value, bool terminate = true)
        {
            for (size_t index = 0; index < value.size(); ++index)
                write<char16_t>(address + index * sizeof(char16_t), value[index]);
            if (terminate)
                write<char16_t>(address + value.size() * sizeof(char16_t), u'\0');
        }

        static bool read(void* context, uintptr_t address, void* output, size_t size) noexcept
        {
            auto* memory = static_cast<FakeMemory*>(context);
            if (memory->forbidden_begin != 0 &&
                address < memory->forbidden_end &&
                size <= UINTPTR_MAX - address &&
                address + size > memory->forbidden_begin)
            {
                memory->touched_forbidden = true;
                return false;
            }

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

    constexpr uintptr_t AppBase = 0x04000000;
    constexpr uintptr_t Field = 0x10000000;
    constexpr uintptr_t Wrapper = 0x11000000;
    constexpr uintptr_t Model = 0x20000000;
    constexpr uintptr_t Heap = 0x30000000;

    void write_model_identity(
        FakeMemory& memory,
        uintptr_t model_vtable_rva)
    {
        const uintptr_t vtable = AppBase + model_vtable_rva;
        memory.write<uintptr_t>(Model, vtable);
        memory.write<uintptr_t>(
            vtable + NativeTextModelLengthSlotOffset,
            AppBase + NativeTextModelLengthGetterRva);
    }

    void write_field_links(FakeMemory& memory, uintptr_t field_vtable_rva)
    {
        memory.write<uintptr_t>(Field, AppBase + field_vtable_rva);
        memory.write<uintptr_t>(Field + NativeTextFieldActiveModelOffset, Model);
        memory.write<uintptr_t>(Field + NativeTextFieldOwnedModelOffset, Model);
    }

    void write_normal_value(FakeMemory& memory, const std::u16string& value, bool heap)
    {
        write_field_links(memory, CTextFieldVtableRva);
        write_model_identity(memory, CTextFieldModelVtableRva);

        const uint32_t raw_length = static_cast<uint32_t>(value.size() + 1);
        const uint32_t capacity = heap ? 256u : 7u;
        const uintptr_t string_field = Model + NativeTextModelStringOffset;
        const uintptr_t characters = heap
            ? Heap
            : string_field + NativeWideStringInlineBufferOffset;
        if (heap)
            memory.write<uintptr_t>(string_field + NativeWideStringInlineBufferOffset, Heap);

        memory.write<uint32_t>(
            string_field + NativeWideStringLengthOffset,
            raw_length);
        memory.write<uint32_t>(
            string_field + NativeWideStringCapacityOffset,
            capacity);
        memory.write_utf16(characters, value, false);
        memory.write<char16_t>(
            characters + value.size() * sizeof(char16_t),
            NativeTextModelSentinel);
        memory.write<char16_t>(
            characters + raw_length * sizeof(char16_t),
            u'\0');
    }

    void write_password_field(FakeMemory& memory, uint32_t visible_count)
    {
        write_field_links(memory, CPasswordFieldVtableRva);
        write_model_identity(memory, CPasswordFieldModelVtableRva);
        memory.write<uint32_t>(
            Model + NativeTextModelRawLengthOffset,
            visible_count + 1);
        for (size_t index = 0; index < NativePasswordMaskCapacity; ++index)
        {
            memory.write<char16_t>(
                Field + NativePasswordMaskTemplateOffset +
                    index * sizeof(char16_t),
                u'*');
        }
        memory.write<char16_t>(
            Field + NativePasswordMaskTemplateOffset +
                NativePasswordMaskCapacity * sizeof(char16_t),
            u'\0');
    }

    void test_inline_and_heap_text_values_are_retained()
    {
        FakeMemory memory;
        write_normal_value(memory, u"Zaltar", false);
        auto snapshot = read_native_text_field(memory.view(), Field, AppBase);
        require(snapshot.matched && snapshot.kind == NativeTextFieldKind::text,
            "an exact inline CTextField was not recognized");
        require(snapshot.value == u"Zaltar" && snapshot.character_count == 6,
            "the retained inline field value changed");

        memory = {};
        write_normal_value(memory, u"LONGRODVONHUGEN", true);
        snapshot = read_native_text_field(memory.view(), Field, AppBase);
        require(snapshot.matched && snapshot.value == u"LONGRODVONHUGEN",
            "the retained heap field value changed");
    }

    void test_empty_text_and_exact_wrapper_are_supported()
    {
        FakeMemory memory;
        write_normal_value(memory, u"", false);

        auto snapshot = read_native_text_field(memory.view(), Field, AppBase);
        require(snapshot.matched && snapshot.value.empty() &&
                snapshot.character_count == 0,
            "an exact empty CTextField was not reported as empty");

        memory.write<uintptr_t>(Wrapper, AppBase + CpmlFormTextVtableRva);
        memory.write<uintptr_t>(Wrapper + NativeFormFieldInnerControlOffset, Field);
        snapshot = read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched && snapshot.field == Field &&
                snapshot.kind == NativeTextFieldKind::text,
            "the exact CPmlFormText wrapper did not resolve its owned field");

        memory.write<uintptr_t>(Wrapper, AppBase + CpmlFormTextVtableRva + 4);
        require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched,
            "an unverified wrapper resolved an inner text field");
    }

    void test_scroll_text_field_resolves_only_its_exact_owned_field()
    {
        FakeMemory memory;
        write_normal_value(memory, u"Zaltar", false);
        memory.write<uintptr_t>(
            Wrapper,
            AppBase + CScrollTextFieldVtableRva);
        memory.write<uintptr_t>(
            Wrapper + NativeScrollTextFieldInnerControlOffset,
            Field);

        auto snapshot =
            read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::text &&
                snapshot.field == Field &&
                snapshot.value == u"Zaltar",
            "the exact CScrollTextField did not resolve its CTextField");

        memory.write<uintptr_t>(
            Field,
            AppBase + CTextFieldVtableRva + 4);
        require(!read_native_text_field(
                    memory.view(),
                    Wrapper,
                    AppBase).matched,
            "a CScrollTextField with an unverified inner class was accepted");
    }

    void test_malformed_or_unowned_text_stays_silent()
    {
        FakeMemory memory;
        write_normal_value(memory, u"Member", false);

        memory.write<uintptr_t>(
            Field + NativeTextFieldOwnedModelOffset,
            Model + 0x1000);
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "mismatched active and owned models were accepted");

        memory = {};
        write_normal_value(memory, u"Member", false);
        memory.write<uintptr_t>(Model, AppBase + CPasswordFieldModelVtableRva);
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "a normal field with a password model was accepted");

        memory = {};
        write_normal_value(memory, u"Member", false);
        memory.write<uint32_t>(
            Model + NativeTextModelStringOffset + NativeWideStringLengthOffset,
            300);
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "an overlong native field value was accepted");

        memory = {};
        write_normal_value(memory, u"Member", false);
        memory.write<char16_t>(
            Model + NativeTextModelStringOffset +
                NativeWideStringInlineBufferOffset + 6 * sizeof(char16_t),
            u'\0');
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "a native field without its exact ETX model sentinel was accepted");
    }

    void test_password_returns_only_a_verified_count()
    {
        FakeMemory memory;
        write_password_field(memory, 7);

        // Seed plausible secret bytes where the normal model would store text.
        // The password path must not even attempt to read this range.
        memory.write_utf16(
            Model + NativeTextModelStringOffset +
                NativeWideStringInlineBufferOffset,
            u"hunter2");
        memory.forbidden_begin =
            Model + NativeTextModelStringOffset +
                NativeWideStringInlineBufferOffset;
        memory.forbidden_end = Model + NativeTextModelRawLengthOffset;

        auto snapshot = read_native_text_field(memory.view(), Field, AppBase);
        require(snapshot.matched && snapshot.kind == NativeTextFieldKind::password,
            "the exact CPasswordField was not recognized");
        require(snapshot.value.empty() && snapshot.character_count == 7,
            "password state exposed text or returned the wrong visible count");
        require(!memory.touched_forbidden,
            "the password path attempted to read secret character storage");

        memory = {};
        write_password_field(memory, 3);
        memory.write<uintptr_t>(Wrapper, AppBase + CpmlFormPasswordVtableRva);
        memory.write<uintptr_t>(Wrapper + NativeFormFieldInnerControlOffset, Field);
        snapshot = read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched && snapshot.field == Field &&
                snapshot.character_count == 3,
            "the exact CPmlFormPassword wrapper did not resolve its count");

        memory.write<char16_t>(
            Field + NativePasswordMaskTemplateOffset + 2 * sizeof(char16_t),
            u'x');
        require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched,
            "a password field with an invalid visible mask template was accepted");

        memory = {};
        write_password_field(memory, 5);
        memory.write<uintptr_t>(
            Wrapper,
            AppBase + CScrollTextFieldVtableRva);
        memory.write<uintptr_t>(
            Wrapper + NativeScrollTextFieldInnerControlOffset,
            Field);
        snapshot = read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::password &&
                snapshot.field == Field &&
                snapshot.character_count == 5 &&
                snapshot.value.empty(),
            "the exact CScrollTextField did not preserve password secrecy");
    }
}

int main()
{
    test_inline_and_heap_text_values_are_retained();
    test_empty_text_and_exact_wrapper_are_supported();
    test_scroll_text_field_resolves_only_its_exact_owned_field();
    test_malformed_or_unowned_text_stays_silent();
    test_password_returns_only_a_verified_count();
    std::cout << "ok: PlayOnline text fields require exact ownership and secrets expose only counts\n";
    return 0;
}
