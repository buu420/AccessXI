#pragma once

#include "pol_pml/native_selected_text.h"

#include <cstddef>
#include <cstdint>
#include <string>

namespace accessxi::pol_pml
{
    inline constexpr uintptr_t CTextFieldVtableRva = 0x00333A94u;
    inline constexpr uintptr_t CPasswordFieldVtableRva = 0x00333CD4u;
    inline constexpr uintptr_t CTextFieldModelVtableRva = 0x00333F7Cu;
    inline constexpr uintptr_t CPasswordFieldModelVtableRva = 0x0033400Cu;
    inline constexpr uintptr_t CpmlFormTextVtableRva = 0x003D84BCu;
    inline constexpr uintptr_t CpmlFormPasswordVtableRva = 0x003D8564u;
    inline constexpr uintptr_t CScrollTextFieldVtableRva = 0x003327F4u;
    inline constexpr uintptr_t NativeTextModelLengthGetterRva = 0x00079061u;

    inline constexpr uintptr_t NativeFormFieldInnerControlOffset = 0x44u;
    inline constexpr uintptr_t NativeScrollTextFieldInnerControlOffset = 0x228u;
    inline constexpr uintptr_t NativeTextFieldActiveModelOffset = 0x1BCu;
    inline constexpr uintptr_t NativeTextFieldOwnedModelOffset = 0x1E8u;
    inline constexpr uintptr_t NativeTextModelStringOffset = 0x30u;
    inline constexpr uintptr_t NativeTextModelRawLengthOffset = 0x44u;
    inline constexpr uintptr_t NativeTextModelLengthSlotOffset = 0x30u;
    inline constexpr uintptr_t NativeWideStringInlineBufferOffset = 0x04u;
    inline constexpr uintptr_t NativeWideStringLengthOffset = 0x14u;
    inline constexpr uintptr_t NativeWideStringCapacityOffset = 0x18u;
    inline constexpr char16_t NativeTextModelSentinel = u'\x0003';
    inline constexpr uintptr_t NativePasswordMaskTemplateOffset = 0x202u;
    inline constexpr size_t NativePasswordMaskCapacity = 32u;

    enum class NativeTextFieldKind : uint8_t
    {
        none,
        text,
        password
    };

    struct NativeTextFieldSnapshot
    {
        bool matched = false;
        NativeTextFieldKind kind = NativeTextFieldKind::none;
        uintptr_t field = 0;
        std::u16string value;
        size_t character_count = 0;
    };

    // Reads only the exact CTextField/CPasswordField object graphs proven for
    // the recognized app.dll. Password character storage is never read:
    // password snapshots contain only the verified logical character count.
    NativeTextFieldSnapshot read_native_text_field(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept;
}
