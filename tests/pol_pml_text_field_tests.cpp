#include "pol_pml/native_text_field.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>

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
        struct Range
        {
            uintptr_t begin;
            uintptr_t end;
        };

        std::unordered_map<uintptr_t, uint8_t> bytes;
        std::vector<Range> forbidden;
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

        void forbid(uintptr_t begin, uintptr_t end)
        {
            forbidden.push_back(Range{ begin, end });
        }

        static bool read(void* context, uintptr_t address, void* output, size_t size) noexcept
        {
            auto* memory = static_cast<FakeMemory*>(context);
            for (const Range& range : memory->forbidden)
            {
                if (address < range.end &&
                    size <= UINTPTR_MAX - address &&
                    address + size > range.begin)
                {
                    memory->touched_forbidden = true;
                    return false;
                }
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

    // Layout fixture: app.dll SHA256 97F99A0A..., reviewed 2026-11-10 in Ghidra.
    // Literal addresses and fields deliberately do not derive from production constants.
    // The RVA beside each value is the function that proves it.
    constexpr uintptr_t TextFieldVtable = 0x003D3054u;          // a23da
    constexpr uintptr_t PasswordFieldVtable = 0x003D3294u;      // a1f1a
    constexpr uintptr_t TextDocumentVtable = 0x003D2A2Cu;       // a201c
    constexpr uintptr_t PasswordDocumentVtable = 0x003D2ABCu;   // a1fce
    constexpr uintptr_t FormTextVtable = 0x00494460u;           // 21d309
    constexpr uintptr_t FormPasswordVtable = 0x00494504u;       // 21d099
    constexpr uintptr_t ScrollTextFieldVtable = 0x003D17B4u;    // 998a8
    constexpr uintptr_t PmlScrollTextVtable = 0x004927E8u;      // 21c961
    constexpr uintptr_t PmlScrollPasswordVtable = 0x00492A18u;  // 21c8e4
    constexpr uintptr_t LengthGetter = 0x000A3354u;             // a3354
    constexpr uintptr_t LengthGetterSlot = 0x30u;               // a3354 refs, a3592
    constexpr uintptr_t FormInnerControl = 0x40u;               // 21f972
    constexpr uintptr_t ScrollInnerControl = 0x208u;            // 9994c, 99a8b
    constexpr uintptr_t ActiveDocument = 0x19Cu;                // a694d
    constexpr uintptr_t OwnedDocument = 0x1C8u;                 // a23da, a844d
    constexpr uintptr_t DocumentString = 0x2Cu;                 // a201c
    constexpr uintptr_t StringLength = 0x10u;                   // a201c
    constexpr uintptr_t StringCapacity = 0x14u;                 // a201c
    constexpr uintptr_t DocumentRawLength = 0x3Cu;              // a3354
    constexpr uintptr_t PasswordDocumentSize = 0xE4u;           // a1f1a allocation
    constexpr uintptr_t PasswordMaskTemplate = 0x1E2u;          // a6a0d
    constexpr size_t PasswordMaskCharacters = 32u;              // a6a0d
    constexpr char16_t DocumentSentinel = u'\x0003';            // a837f

    constexpr uintptr_t AppBase = 0x04000000;
    constexpr uintptr_t Field = 0x10000000;
    constexpr uintptr_t Wrapper = 0x11000000;
    constexpr uintptr_t Form = 0x12000000;
    constexpr uintptr_t Unmapped = 0x13000000;
    constexpr uintptr_t Model = 0x20000000;
    constexpr uintptr_t Heap = 0x30000000;

    void write_model_identity(
        FakeMemory& memory,
        uintptr_t model_vtable_rva)
    {
        const uintptr_t vtable = AppBase + model_vtable_rva;
        memory.write<uintptr_t>(Model, vtable);
        memory.write<uintptr_t>(
            vtable + LengthGetterSlot,
            AppBase + LengthGetter);
    }

    void write_field_links(FakeMemory& memory, uintptr_t field_vtable_rva)
    {
        memory.write<uintptr_t>(Field, AppBase + field_vtable_rva);
        memory.write<uintptr_t>(Field + ActiveDocument, Model);
        memory.write<uintptr_t>(Field + OwnedDocument, Model);
    }

    void write_normal_value(FakeMemory& memory, const std::u16string& value, bool heap)
    {
        write_field_links(memory, TextFieldVtable);
        write_model_identity(memory, TextDocumentVtable);

        const uint32_t raw_length = static_cast<uint32_t>(value.size() + 1);
        const uint32_t capacity = heap ? 256u : 7u;
        const uintptr_t string_field = Model + DocumentString;
        // The inline buffer and the heap pointer share the string's first word.
        const uintptr_t characters = heap ? Heap : string_field;
        if (heap)
            memory.write<uintptr_t>(string_field, Heap);

        memory.write<uint32_t>(
            string_field + StringLength,
            raw_length);
        memory.write<uint32_t>(
            string_field + StringCapacity,
            capacity);
        memory.write_utf16(characters, value, false);
        memory.write<char16_t>(
            characters + value.size() * sizeof(char16_t),
            DocumentSentinel);
        memory.write<char16_t>(
            characters + raw_length * sizeof(char16_t),
            u'\0');
    }

    void write_password_field(FakeMemory& memory, uint32_t visible_count)
    {
        write_field_links(memory, PasswordFieldVtable);
        write_model_identity(memory, PasswordDocumentVtable);
        memory.write<uint32_t>(
            Model + DocumentRawLength,
            visible_count + 1);
        for (size_t index = 0; index < PasswordMaskCharacters; ++index)
        {
            memory.write<char16_t>(
                Field + PasswordMaskTemplate +
                    index * sizeof(char16_t),
                u'*');
        }
        memory.write<char16_t>(
            Field + PasswordMaskTemplate +
                PasswordMaskCharacters * sizeof(char16_t),
            u'\0');
    }

    // Plausible secret bytes sit where the password document stores its
    // string. The reader may touch only the document's vtable (+0) and raw
    // length (+0x3C); every other byte of the document is forbidden.
    void forbid_password_document_contents(FakeMemory& memory)
    {
        memory.write_utf16(Model + DocumentString, u"hunter2");
        memory.forbid(Model + sizeof(uintptr_t), Model + DocumentRawLength);
        memory.forbid(
            Model + DocumentRawLength + sizeof(uint32_t),
            Model + PasswordDocumentSize);
    }

    void write_scroll_wrapper(FakeMemory& memory, uintptr_t wrapper_vtable_rva)
    {
        memory.write<uintptr_t>(Wrapper, AppBase + wrapper_vtable_rva);
        memory.write<uintptr_t>(Wrapper + ScrollInnerControl, Field);
    }

    // The graph the PML form constructors build (21d309, 21d099): the form
    // owns the scroll wrapper it creates, which owns the field.
    void write_pml_form(
        FakeMemory& memory,
        uintptr_t form_vtable_rva,
        uintptr_t wrapper_vtable_rva)
    {
        write_scroll_wrapper(memory, wrapper_vtable_rva);
        memory.write<uintptr_t>(Form, AppBase + form_vtable_rva);
        memory.write<uintptr_t>(Form + FormInnerControl, Wrapper);
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

    void test_empty_text_is_reported_as_empty()
    {
        FakeMemory memory;
        write_normal_value(memory, u"", false);

        const auto snapshot = read_native_text_field(memory.view(), Field, AppBase);
        require(snapshot.matched && snapshot.value.empty() &&
                snapshot.character_count == 0,
            "an exact empty CTextField was not reported as empty");
    }

    void test_scroll_text_field_resolves_only_its_exact_owned_field()
    {
        FakeMemory memory;
        write_normal_value(memory, u"Zaltar", false);
        write_scroll_wrapper(memory, ScrollTextFieldVtable);

        auto snapshot =
            read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::text &&
                snapshot.field == Field &&
                snapshot.value == u"Zaltar",
            "the exact CScrollTextField did not resolve its CTextField");

        memory.write<uintptr_t>(
            Field,
            AppBase + TextFieldVtable + 4);
        require(!read_native_text_field(
                    memory.view(),
                    Wrapper,
                    AppBase).matched,
            "a CScrollTextField with an unverified inner class was accepted");
    }

    void test_pml_form_text_resolves_through_its_native_scroll_wrapper()
    {
        FakeMemory memory;
        write_normal_value(memory, u"Zaltar", false);
        write_pml_form(memory, FormTextVtable, PmlScrollTextVtable);

        auto snapshot = read_native_text_field(memory.view(), Form, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::text &&
                snapshot.field == Field &&
                snapshot.value == u"Zaltar",
            "the native CPmlFormText -> CPmlFCScrollText -> CTextField graph did not resolve");

        snapshot = read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::text &&
                snapshot.field == Field &&
                snapshot.value == u"Zaltar",
            "a focused CPmlFCScrollText did not resolve its owned CTextField");
    }

    void test_pml_form_never_owns_a_bare_field()
    {
        // The form constructors store only the scroll wrapper they build
        // (21d309/21d099 through 21f972); tearing the wrapper down clears the
        // link to null (21d662). A form pointing straight at a field is not a
        // shape the client creates.
        FakeMemory memory;
        write_normal_value(memory, u"Zaltar", false);
        memory.write<uintptr_t>(Form, AppBase + FormTextVtable);
        memory.write<uintptr_t>(Form + FormInnerControl, Field);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormText linked straight to a bare CTextField was accepted");

        memory = {};
        write_password_field(memory, 3);
        memory.write<uintptr_t>(Form, AppBase + FormPasswordVtable);
        memory.write<uintptr_t>(Form + FormInnerControl, Field);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormPassword linked straight to a bare CPasswordField was accepted");
    }

    void test_pml_form_graph_rejects_wrong_subclass_and_mismatched_kind()
    {
        // Each case changes one class in an otherwise native graph.
        FakeMemory memory;
        write_normal_value(memory, u"Zaltar", false);

        write_pml_form(memory, FormTextVtable, ScrollTextFieldVtable);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormText owning a plain CScrollTextField was accepted");

        write_pml_form(memory, FormTextVtable, PmlScrollPasswordVtable);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormText owning a CPmlFCScrollPassword was accepted");
        require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched,
            "a CPmlFCScrollPassword owning a CTextField was accepted");

        write_pml_form(memory, FormPasswordVtable, PmlScrollPasswordVtable);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormPassword whose wrapper owns a CTextField was accepted");

        memory = {};
        write_password_field(memory, 3);

        write_pml_form(memory, FormPasswordVtable, ScrollTextFieldVtable);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormPassword owning a plain CScrollTextField was accepted");

        write_pml_form(memory, FormPasswordVtable, PmlScrollTextVtable);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormPassword owning a CPmlFCScrollText was accepted");
        require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched,
            "a CPmlFCScrollText owning a CPasswordField was accepted");

        write_pml_form(memory, FormTextVtable, PmlScrollTextVtable);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormText whose wrapper owns a CPasswordField was accepted");
    }

    void test_pml_form_graph_rejects_unknown_classes_and_malformed_links()
    {
        FakeMemory memory;
        write_normal_value(memory, u"Zaltar", false);
        write_pml_form(memory, FormTextVtable, PmlScrollTextVtable);
        require(read_native_text_field(memory.view(), Form, AppBase).matched,
            "the native graph the malformed-link cases start from did not resolve");

        memory.write<uintptr_t>(Form, AppBase + FormTextVtable + 4);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "an unverified form class resolved a field");
        memory.write<uintptr_t>(Form, AppBase + FormTextVtable);

        memory.write<uintptr_t>(Wrapper, AppBase + PmlScrollTextVtable + 4);
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a form owning an unverified scroll class resolved a field");
        require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched,
            "an unverified scroll class resolved a field");
        memory.write<uintptr_t>(Wrapper, AppBase + PmlScrollTextVtable);

        struct BrokenLink
        {
            uintptr_t target;
            const char* message;
        };

        const BrokenLink form_links[] = {
            { 0, "a form with a null wrapper link resolved a field" },
            { 0x8000, "a form link below the object floor resolved a field" },
            { Unmapped, "a form link to unreadable memory resolved a field" },
            { Form, "a form linked to itself resolved a field" },
        };
        for (const BrokenLink& link : form_links)
        {
            memory.write<uintptr_t>(Form + FormInnerControl, link.target);
            require(!read_native_text_field(memory.view(), Form, AppBase).matched,
                link.message);
        }
        memory.write<uintptr_t>(Form + FormInnerControl, Wrapper);

        // A broken field link must silence the wrapper both when it is
        // focused and when it is reached through its form.
        const BrokenLink wrapper_links[] = {
            { 0, "a scroll wrapper with a null field link resolved a field" },
            { 0x8000, "a scroll link below the object floor resolved a field" },
            { Unmapped, "a scroll link to unreadable memory resolved a field" },
            { Wrapper, "a scroll wrapper linked to itself resolved a field" },
            { Form, "a scroll wrapper linked back to its form resolved a field" },
        };
        for (const BrokenLink& link : wrapper_links)
        {
            memory.write<uintptr_t>(Wrapper + ScrollInnerControl, link.target);
            require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched &&
                    !read_native_text_field(memory.view(), Form, AppBase).matched,
                link.message);
        }
        memory.write<uintptr_t>(Wrapper + ScrollInnerControl, Field);

        // The proven graph has at most two links; a scroll wrapper nested in
        // another is never followed to a field.
        constexpr uintptr_t NestedWrapper = 0x11100000;
        memory.write<uintptr_t>(NestedWrapper, AppBase + PmlScrollTextVtable);
        memory.write<uintptr_t>(NestedWrapper + ScrollInnerControl, Field);
        memory.write<uintptr_t>(Wrapper + ScrollInnerControl, NestedWrapper);
        require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched,
            "a scroll wrapper nested in another resolved a field");
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a third ownership link was followed to a field");
    }

    void test_malformed_or_unowned_text_stays_silent()
    {
        FakeMemory memory;
        write_normal_value(memory, u"Member", false);

        memory.write<uintptr_t>(
            Field + OwnedDocument,
            Model + 0x1000);
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "mismatched active and owned models were accepted");

        memory = {};
        write_normal_value(memory, u"Member", false);
        memory.write<uintptr_t>(Model, AppBase + PasswordDocumentVtable);
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "a normal field with a password model was accepted");

        memory = {};
        write_normal_value(memory, u"Member", false);
        memory.write<uint32_t>(
            Model + DocumentString + StringLength,
            300);
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "an overlong native field value was accepted");

        memory = {};
        write_normal_value(memory, u"Member", false);
        memory.write<char16_t>(
            Model + DocumentString + 6 * sizeof(char16_t),
            u'\0');
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "a native field without its exact ETX model sentinel was accepted");

        memory = {};
        write_normal_value(memory, u"Member", false);
        memory.write<uintptr_t>(
            AppBase + TextDocumentVtable + LengthGetterSlot,
            AppBase + LengthGetter + 1);
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "a text model without the exact native length getter was accepted");
    }

    void test_password_returns_only_a_verified_count()
    {
        FakeMemory memory;
        write_password_field(memory, 7);
        forbid_password_document_contents(memory);

        auto snapshot = read_native_text_field(memory.view(), Field, AppBase);
        require(snapshot.matched && snapshot.kind == NativeTextFieldKind::password,
            "the exact CPasswordField was not recognized");
        require(snapshot.value.empty() && snapshot.character_count == 7,
            "password state exposed text or returned the wrong visible count");
        require(!memory.touched_forbidden,
            "the password path attempted to read secret character storage");

        memory.write<char16_t>(
            Field + PasswordMaskTemplate + 2 * sizeof(char16_t),
            u'x');
        require(!read_native_text_field(memory.view(), Field, AppBase).matched,
            "a password field with an invalid visible mask template was accepted");

        memory = {};
        write_password_field(memory, 5);
        forbid_password_document_contents(memory);
        write_scroll_wrapper(memory, ScrollTextFieldVtable);
        snapshot = read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::password &&
                snapshot.field == Field &&
                snapshot.character_count == 5 &&
                snapshot.value.empty(),
            "the exact CScrollTextField did not preserve password secrecy");
        require(!memory.touched_forbidden,
            "the CScrollTextField password path read secret character storage");
    }

    void test_pml_password_wrappers_expose_only_a_verified_count()
    {
        FakeMemory memory;
        write_password_field(memory, 4);
        forbid_password_document_contents(memory);
        write_pml_form(memory, FormPasswordVtable, PmlScrollPasswordVtable);

        auto snapshot = read_native_text_field(memory.view(), Form, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::password &&
                snapshot.field == Field &&
                snapshot.character_count == 4 &&
                snapshot.value.empty(),
            "the native CPmlFormPassword -> CPmlFCScrollPassword -> CPasswordField graph did not resolve its count");

        snapshot = read_native_text_field(memory.view(), Wrapper, AppBase);
        require(snapshot.matched &&
                snapshot.kind == NativeTextFieldKind::password &&
                snapshot.field == Field &&
                snapshot.character_count == 4 &&
                snapshot.value.empty(),
            "a focused CPmlFCScrollPassword did not resolve only its count");
        require(!memory.touched_forbidden,
            "a PML password wrapper read secret password document storage");

        memory.write<char16_t>(
            Field + PasswordMaskTemplate + 2 * sizeof(char16_t),
            u'x');
        require(!read_native_text_field(memory.view(), Form, AppBase).matched,
            "a CPmlFormPassword with an invalid mask template was accepted");
        require(!read_native_text_field(memory.view(), Wrapper, AppBase).matched,
            "a CPmlFCScrollPassword with an invalid mask template was accepted");
        require(!memory.touched_forbidden,
            "a rejected PML password wrapper read secret password document storage");
    }

    void test_exported_layout_matches_the_reviewed_build()
    {
        // The reader's callers consume these constants directly, so they must
        // describe the same build as the fixtures above.
        require(CTextFieldVtableRva == TextFieldVtable &&
                CPasswordFieldVtableRva == PasswordFieldVtable &&
                CTextFieldModelVtableRva == TextDocumentVtable &&
                CPasswordFieldModelVtableRva == PasswordDocumentVtable &&
                CpmlFormTextVtableRva == FormTextVtable &&
                CpmlFormPasswordVtableRva == FormPasswordVtable &&
                CScrollTextFieldVtableRva == ScrollTextFieldVtable &&
                CpmlFcScrollTextVtableRva == PmlScrollTextVtable &&
                CpmlFcScrollPasswordVtableRva == PmlScrollPasswordVtable &&
                NativeTextModelLengthGetterRva == LengthGetter,
            "an exported text-field identity does not match the reviewed app.dll");
        require(NativeFormFieldInnerControlOffset == FormInnerControl &&
                NativeScrollTextFieldInnerControlOffset == ScrollInnerControl &&
                NativeTextFieldActiveModelOffset == ActiveDocument &&
                NativeTextFieldOwnedModelOffset == OwnedDocument &&
                NativeTextModelStringOffset == DocumentString &&
                NativeTextModelRawLengthOffset == DocumentRawLength &&
                NativeTextModelLengthSlotOffset == LengthGetterSlot,
            "an exported text-field link offset does not match the reviewed app.dll");
        require(NativeWideStringInlineBufferOffset == 0 &&
                NativeWideStringLengthOffset == StringLength &&
                NativeWideStringCapacityOffset == StringCapacity &&
                NativeTextModelSentinel == DocumentSentinel &&
                NativePasswordMaskTemplateOffset == PasswordMaskTemplate &&
                NativePasswordMaskCapacity == PasswordMaskCharacters,
            "an exported text-field string layout does not match the reviewed app.dll");
    }
}

int main(int argc, char** argv)
{
    struct NamedTest
    {
        const char* name;
        void (*run)();
    };
    const NamedTest tests[] = {
        { "inline_and_heap_text_values_are_retained", test_inline_and_heap_text_values_are_retained },
        { "empty_text_is_reported_as_empty", test_empty_text_is_reported_as_empty },
        { "scroll_text_field_resolves_only_its_exact_owned_field", test_scroll_text_field_resolves_only_its_exact_owned_field },
        { "pml_form_text_resolves_through_its_native_scroll_wrapper", test_pml_form_text_resolves_through_its_native_scroll_wrapper },
        { "pml_form_never_owns_a_bare_field", test_pml_form_never_owns_a_bare_field },
        { "pml_form_graph_rejects_wrong_subclass_and_mismatched_kind", test_pml_form_graph_rejects_wrong_subclass_and_mismatched_kind },
        { "pml_form_graph_rejects_unknown_classes_and_malformed_links", test_pml_form_graph_rejects_unknown_classes_and_malformed_links },
        { "malformed_or_unowned_text_stays_silent", test_malformed_or_unowned_text_stays_silent },
        { "password_returns_only_a_verified_count", test_password_returns_only_a_verified_count },
        { "pml_password_wrappers_expose_only_a_verified_count", test_pml_password_wrappers_expose_only_a_verified_count },
        { "exported_layout_matches_the_reviewed_build", test_exported_layout_matches_the_reviewed_build },
    };

    // An optional test name runs that test alone, so each can be watched failing.
    const char* only = argc > 1 ? argv[1] : nullptr;
    bool ran = false;
    for (const NamedTest& test : tests)
    {
        if (only != nullptr && std::strcmp(only, test.name) != 0)
            continue;
        test.run();
        ran = true;
    }
    require(ran, "no test has the requested name");
    std::cout << "ok: PlayOnline text fields require exact ownership and secrets expose only counts\n";
    return 0;
}
