param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$AppDll = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\viewer\com\app.dll'
)

$ErrorActionPreference = 'Stop'
$bytes = [IO.File]::ReadAllBytes($AppDll)
if ((Get-FileHash -LiteralPath $AppDll -Algorithm SHA256).Hash -ne '97F99A0AE604BA318326FA8CDED93D3479F59B37045509E289A3CC5C27D95E66') {
    throw 'This native ABI fixture requires the reviewed November 2026 app.dll.'
}
$pe = [BitConverter]::ToUInt32($bytes, 0x3C)
if ([BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x14C) { throw 'Expected x86 app.dll.' }
$count = [BitConverter]::ToUInt16($bytes, $pe + 6)
$sectionStart = $pe + 24 + [BitConverter]::ToUInt16($bytes, $pe + 20)
function Read-Rva([uint32]$Rva, [int]$Length) {
    for ($i = 0; $i -lt $count; ++$i) {
        $s = $sectionStart + $i * 40
        $start = [BitConverter]::ToUInt32($bytes, $s + 12)
        $size = [BitConverter]::ToUInt32($bytes, $s + 16)
        if ($Rva -ge $start -and $Rva + $Length -le $start + $size) {
            $offset = [BitConverter]::ToUInt32($bytes, $s + 20) + $Rva - $start
            return ,([byte[]]$bytes[$offset..($offset + $Length - 1)])
        }
    }
    throw ('RVA {0:X8} is not backed by file data.' -f $Rva)
}

# Independent Ghidra disassembly fixtures. Each prefix ends at a complete
# instruction boundary and contains no relative call or branch to relocate.
$hooks = @(
    @('PmlSharedFocusEventRva', 0x83442, '55 8B EC 8B 45 08', 'FocusEventPatchSize', 6),
    @('PmlSelectFocusEventRva', 0xAB3D9, '55 8B EC 8B 55 08', 'FocusEventPatchSize', 6),
    @('PmlCurrentChildSetterRva', 0x289924, '6A 40 B8 07 43 3B 10', 'CurrentChildPatchSize', 7),
    @('SelectedIndexSetterRva', 0x22AD04, '55 8B EC 56 8B 75 08', 'SelectedIndexPatchSize', 7),
    @('ModalOkConstructorRva', 0xDAD07, '6A 24 B8 37 7F 38 10', 'PopupConstructorPatchSize', 7),
    @('ModalYesNoConstructorRva', 0xDB573, '6A 24 B8 52 81 38 10', 'PopupConstructorPatchSize', 7),
    @('ModalYesNoCancelConstructorRva', 0xDB849, '6A 24 B8 05 82 38 10', 'PopupConstructorPatchSize', 7),
    @('ModalOkCancelConstructorRva', 0xDAFC7, '6A 24 B8 EC 7F 38 10', 'PopupConstructorPatchSize', 7),
    @('ModalRetryFailConstructorRva', 0xDB29D, '6A 24 B8 9F 80 38 10', 'PopupConstructorPatchSize', 7),
    @('NoticeWindowConstructorRva', 0xB5DAB, '6A 08 B8 E7 07 38 10', 'PopupConstructorPatchSize', 7),
    @('ImportantNoticeConstructorRva', 0xB5A74, '6A 24 B8 90 07 38 10', 'PopupConstructorPatchSize', 7),
    @('ModalOkBaseDestructorRva', 0xEC6E1, '56 8B F1 57 8B 8E 84 02 00 00', 'PopupModalBaseDestructorPatchSize', 10),
    @('ModalYesNoBaseDestructorRva', 0xEC798, '56 8B F1 57 8B 8E 84 02 00 00', 'PopupModalBaseDestructorPatchSize', 10),
    @('ModalYesNoCancelBaseDestructorRva', 0xEC7D5, '56 8B F1 57 8B 8E 84 02 00 00', 'PopupModalBaseDestructorPatchSize', 10),
    @('ModalOkCancelBaseDestructorRva', 0xEC71E, '56 8B F1 57 8B 8E 84 02 00 00', 'PopupModalBaseDestructorPatchSize', 10),
    @('ModalRetryFailBaseDestructorRva', 0xEC75B, '56 8B F1 57 8B 8E 84 02 00 00', 'PopupModalBaseDestructorPatchSize', 10),
    @('NoticeWindowBaseDestructorRva', 0xC020D, 'C7 01 40 21 3E 10', 'PopupNoticeBaseDestructorPatchSize', 6),
    @('ImportantNoticeBaseDestructorRva', 0xC01E4, '56 8B F1 8D 8E 80 02 00 00', 'PopupImportantBaseDestructorPatchSize', 9)
)
$source = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\accessxi_pol.cpp') -Raw
foreach ($h in $hooks) {
    $m = [regex]::Match($source, ('constexpr uintptr_t {0} = (0x[0-9a-fA-F]+)u;' -f $h[0]))
    if (-not $m.Success -or [Convert]::ToUInt32($m.Groups[1].Value.Substring(2), 16) -ne $h[1]) {
        throw "Native target $($h[0]) does not match the reviewed new function."
    }
    $m = [regex]::Match($source, ('constexpr size_t {0} = ([0-9]+);' -f $h[3]))
    if (-not $m.Success -or [int]$m.Groups[1].Value -ne $h[4]) {
        throw "Native patch boundary $($h[3]) does not match the reviewed instructions."
    }
    $actual = [BitConverter]::ToString((Read-Rva $h[1] $h[4])).Replace('-', ' ')
    if ($actual -ne $h[2]) { throw "Native prefix changed at $($h[0]): $actual" }
}
'ok: 18 native hook targets and complete instruction boundaries match the exact November app.dll.'
