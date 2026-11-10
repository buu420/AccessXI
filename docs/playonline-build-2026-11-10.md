# PlayOnline November 2026 compatibility

The November PlayOnline update changed both function addresses and native object layouts. Updating only the compatibility fingerprint would leave invalid hooks and text reads. The reader and installer now recognize this exact x86 `viewer/com/app.dll`:

- Size: 6,560,512 bytes
- SHA256: `97f99a0ae604ba318326fa8cded93d3479f59b37045509e289a3cc5c27d95e66`
- FNV-1a 64: `F50D04B5FDA154A5`
- File version: 1.18.13; the installed `version.dat` identifies the package as 1.18.15f.

Ghidra analysis of that DLL established the new functions, RTTI identities, owner relationships, text layouts, and instruction boundaries. The analysis compared the previously reviewed runtime image with the new build. Game binaries and runtime dumps are private investigation inputs and are not distributed.

## Native hook boundaries

| Hook | RVA | Complete bytes copied |
| --- | --- | --- |
| Shared focus | `00083442` | 6 |
| Select focus | `000AB3D9` | 6 |
| Current child | `00289924` | 7 |
| Selected index | `0022AD04` | 7 |
| Seven popup constructors | See named constants in `accessxi_pol.cpp` | 7 |
| Five modal base destructors | See named constants | 10 |
| Notice base destructor | `000C020D` | 6 |
| Important-notice base destructor | `000C01E4` | 9 |

The prefixes contain complete instructions and no relative branches or calls. Runtime prologue checks accompany the exact build guard. Popup destruction still invalidates registrations before native destruction; constructors publish only after native construction completes. The previously disabled generic text-setter hook remains disabled.

## Shared layout evidence

| Native state | November field(s) | Evidence RVA |
| --- | --- | --- |
| CComponent visibility | byte `14`, both bits `0C` | `00054C93` |
| CComponent rectangle | `4C`, `50`, `54`, `58` | `0028B656` |
| Focus and current child | `148`, `14C` | `00083442`, `00289924` |
| Frame focus | `1A0` | `000AB3D9` |
| Selected child vector / index | `268`, `26C` / `274` | `0022AD04` |
| Global focus manager | global RVA `00695F9C` | `0028D4DC` |
| Member name accessor / storage | RVA `002A1926` / `0056F182` | `00270282`, `002A1926` |
| Member-table keyboard row / restore row | `236` / `238` | `000A1115`, `0009D5EB` |
| Member-table model | `1E0` | `000A0E02` |
| CLabel text bounds / length | `168`, `16C` / signed short `1FA` | `0008D574` |
| Upgrade-progress owner | global RVA `0062C770` | `001490DD` |
| PML text model / rendered lines | `214` / `1AC` | `002207CB`, `0024934E` |
| Sheet child vector | `170`, `174` | `00082C4C`, `00083024` |
| Primary / alternate image caption | `10C` / `124` | `00289CBC` |
| Text field active / owned document | `19C` / `1C8` | `000A694D`, `000A23DA` |
| Form / scroll-field inner control | `40` / `208` | `0021F972`, `0009994C` |
| Dropdown highlighted row | signed short `1F2` | `000907AF` |

The member table retains its keyboard-selected-row checks, exact model/data RTTI, and row recheck. Popup and progress fixtures use literal addresses and fields from this build, independent of production constants, and retain visibility, bounded-text, lifetime, and deduplication cases. Password readers retain masking and avoid reading password contents.

Image-only controls still use the native caption getter's two-state agreement and formatting-marker cleanup. The now-readable raw string path must not bypass those checks. Text-bearing sheets retain their rendered-text path. Form fields follow the proven form-to-scroll-to-field ownership chain; password subclasses remain excluded from generic text discovery even while their model is unavailable.

## Verification

Run `tools/test_pol_native_offline.ps1` with the physical checkout and SDK paths. `tools/test_pol_native_build.ps1` checks all 18 hook addresses and patch boundaries against the exact installed DLL. The native harnesses, source integration checks, staged x86 binary checks, and temporary-tree deployment/rollback tests cover offline behavior. None substitutes for listening to the live updated client.

The installed Ashita core and pointer/DAT configuration match official commit `4171c74c8ddb2ca2a31654f199e6c1cee40d7256`, version 4.3.2.1, checked on November 10. The public installer retains that version. Addon checks cover inventory, commands, search, Treasure Pool, trade, key items, and support logging. Live FFXI validation must follow the client update reached through PlayOnline's Play button.
