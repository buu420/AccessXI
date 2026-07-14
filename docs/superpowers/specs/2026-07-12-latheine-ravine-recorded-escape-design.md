# La Theine Recorded Ravine Escape Design

Date: 2026-07-12

## Goal

Convert the completed live recording `20260712-143554-z102` (`La_theine_ravine_01`) into a reusable escape prefix from the recorded La Theine ravine fall pocket. Any navigation request from that pocket to a destination outside it must first follow the complete recorded escape and then hand off to current navigation data for the requested destination.

The recorded walk is authoritative. No static-table guesses, synthesized shortcuts, or unwalked ravine connections will be added.

## Verified Recording

- Zone: `102` (La Theine Plateau)
- Events: one start, 321 movement points, one stop
- Start: `(-339.820, 375.467, 7.988)`
- Stop: `(-563.557, 663.512, 0.823)`
- Recorded distance: `793.900` yalms
- Manual marks: none
- Recorder confirmed: `323 points saved`

## Route Representation

Create a new ravine escape corridor dedicated to this recording. Preserve the complete ordered walk path: the start event and all 321 movement points. The stop event duplicates the final position closely enough that it will be retained only if its coordinate differs from the last movement point; otherwise it will not create a stationary duplicate.

Coordinates will be copied directly from the recorder TSV at recorder precision. They will not be downsampled, smoothed, averaged, or replaced with points inferred from the DAT, map, or navmesh.

Each override row will identify the live recorder session as its source and use `proven` confidence.

## Activation Scope

The escape corridor will activate for any navigation request made from a tight rectangle around the recorded starting pocket when the requested destination is outside that rectangle. The rectangle will extend no more than five yalms beyond the recorded start in either horizontal axis.

It is destination-independent: West Ronfaure, another La Theine destination, or the La Theine leg of a cross-zone route all use the same recorded escape before their normal route continues.

This intentionally does not claim that every coordinate in the wider ravine can safely connect to the first recorded point. Additional fall pockets require their own walked recordings or a verified intersection with this path.

Once selected, the escape will remain precise for its complete recorded duration so normal replanning cannot replace the walked ravine path with a wall-prone navmesh shortcut. A character already within five yalms of a later recorded segment may join at the existing nearest-segment logic; otherwise the narrow activation bounds force the route to begin at its recorded start.

## Handoff

After the last recorded point, navigation will compute a fresh tail from that endpoint to the route's current requested destination using the current navmesh, zone-line approach data, and existing route safeguards. The recorded corridor is prepended only when that tail succeeds and passes quarantine checks. A failed or quarantined tail rejects the combined route instead of appending an unverified straight segment.

The last recorded point is approximately 25 yalms from the current La Theine-side West Ronfaure zone-line destination, so West Ronfaure remains one valid handoff. It is not hard-coded as the only handoff.

The existing older La Theine recovery overrides will remain unchanged so this recording does not steal their distinct starting pockets.

## Files

Update and keep identical:

- `C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv`
- `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv`
- `C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv`

Update the route-planning logic and keep these Lua copies identical:

- `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua`
- `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`

Do not change destination coordinates, the zone-line graph, character-specific state, the route recorder, enemy tracking, or unrelated routes.

## Failure Behavior

- Outside the tight recorded-start scope, the escape prefix does not activate.
- A destination inside the same tight start pocket does not activate the escape prefix.
- Any destination outside the pocket may use the escape, including other La Theine destinations and cross-zone next hops.
- If no safe tail can be computed from the recorded endpoint to the requested destination, the combined route is rejected.
- Existing quarantine checks remain active.
- If the route cannot be validated, navigation remains silent rather than using a new broad fallback.

## Verification

Add a focused regression test that proves:

1. The source recording contains the expected session, zone, event counts, endpoints, and ordered coordinates.
2. The override contains the complete ordered recorded coordinate sequence without downsampling or reordering.
3. The activation rectangle stays within five yalms of the recorded start.
4. The escape activates for representative West Ronfaure, other La Theine, and cross-zone next-hop destinations outside the pocket.
5. It does not activate outside the recorded start pocket or for a destination inside that pocket.
6. It preserves the complete escape sequence and appends only a successfully computed, quarantine-safe tail.
7. The three route-override data copies are byte-identical.
8. Source and live Lua copies are byte-identical.

Run the focused test, existing La Theine route tests, the route-recorder test, and Lua 5.1 syntax validation. Live success still requires reloading the addon and walking the navigation route in game.

## Out of Scope

- Claiming safe recovery from unrecorded starting pockets elsewhere in the ravine
- Downsampling the walked path
- Replacing other La Theine routes
- Packaging or installer work
- Git initialization, pushing, or unrelated cleanup
