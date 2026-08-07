# West Ronfaure Entrance Labels

## Problem

Northern San d'Oria contains two generated navigation destinations named `West Ronfaure zone line`. AccessXI deduplicates static destinations by zone, name, and kind, so only the nearer coordinate appears.

The destination currently visible to Zaltar is the wrong one for traveling onward to La Theine: `(-238.702, 105.961, -9.433)`. It leads through the watchtower-side transition and lands where the La Theine navmesh route is unavailable.

The working entrance used by Longrodvonhugen is currently hidden by that duplicate: `(-252.158, 43.913, 1.663)`. It must remain named `West Ronfaure zone line` and become visible again.

## Design

- Rename the currently visible, wrong-for-La-Theine transition at `(-238.702, 105.961, -9.433)` to `Watchtower entrance`.
- Keep the currently hidden, proven transition at `(-252.158, 43.913, 1.663)` named `West Ronfaure zone line`.
- Giving the two coordinates distinct names prevents `nav_menu_static_key` from collapsing them, so both destinations appear in the Northern San d'Oria navigation browser.
- Apply the label change to the source data, source-addon data, and live-addon data copies of `ffxi-nav-destinations.tsv`.
- Do not change coordinates, routing logic, graph topology, route overrides, or character-specific state.
- Add a focused regression test that requires both labels and coordinates in all three data copies and rejects the old duplicate name at the watchtower coordinate.

## Verification

- Run the new West Ronfaure entrance-label test.
- Run the existing static-destination duplicate-suppression and zoneline-menu tests.
- Confirm the three destination files remain synchronized.
- No Lua edit is planned, so Lua syntax validation is unnecessary unless implementation scope changes.
