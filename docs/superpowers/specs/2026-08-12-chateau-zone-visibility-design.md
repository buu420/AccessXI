# Chateau d'Oraguille Zone Visibility Design
## Outcome

AccessXI always exposes Chateau d'Oraguille as zone 233, regardless of the character's nation, rank, mission, or current access. A selected cross-zone route uses the real Northern San d'Oria castle gate and never substitutes the West Ronfaure/Bostaunieux Oubliette detour.

## Route topology

The navigation data generator owns one scripted, one-way transition from Northern San d'Oria (231) to Chateau d'Oraguille (233). Its source is LandSandBoat's Northern San d'Oria scripted access trigger rather than the ordinary `zonelines.sql` table. The approach is `(x=0,z=110,y=-2)`, safely inside the documented trigger cuboid; the landing is `(x=0,z=-13,y=0)` in zone 233. No reverse transition is invented because the authoritative source does not define one.

The transition remains visible even when the character cannot enter. AccessXI routes to the gate, then waits for an actual zone change to 233. If the guards refuse entry, the route does not continue and no dungeon detour is attempted.

## Search and selection

Global zone search treats canonical graph zone names as first-class results in addition to NPC destinations. An exact search for `Chateau d'Oraguille` produces one zone result for 233 without consulting mission or rank state. Apostrophe-normalized spelling continues to work. Selecting the result uses the existing zone-search state machine and its actual-zone-change continuation.

Current-area `Areas` remains a local-exit browser; this change does not fill it with every world zone.

## Verification

- Generator output contains exactly one scripted 231-to-233 transition and no scripted reverse.
- `nav_zoneline_path(231,233)` is exactly one edge and contains neither zone 100 nor zone 167.
- Exact global zone-name search returns Chateau even with no access-state fixture.
- Selecting it starts the direct gate leg and waits for zone 233.
- Existing zone search, zoneline, Lua 5.1 syntax, and paired-data integrity checks remain green.
