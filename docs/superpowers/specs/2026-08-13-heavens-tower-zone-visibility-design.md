# Heavens Tower Zone Visibility Design

## Outcome

Global navigation search always exposes canonical zone 242 as `Heavens Tower`, independent of nation, rank, mission, or key-item state. Routes use the real, ordinary Windurst Walls portals in both directions. Metalworks remains the already-supported Bastok capital equivalent and is neither hidden nor duplicated.

## Authoritative topology

The navigation generator owns two scripted transitions omitted from LandSandBoat's SQL zoneline table but defined by its zone scripts:

- Scripted ID 239242086, Windurst Walls 239 to Heavens Tower 242: representative approach `(x=0,z=141,y=-16.5)` inside trigger cuboid 1; event 86 lands at `(x=0,z=-22.4,y=0)` in zone 242.
- Scripted ID 242239041, Heavens Tower 242 to Windurst Walls 239: representative approach `(x=0,z=-34,y=0)` inside exit cuboid 1; event 41 lands at `(x=0,z=135,y=-17)` in zone 239.

Neither transition carries an access requirement. The Starway Stairway inside Heavens Tower has separate nation/key-item restrictions and must not be conflated with admission to the zone.

Both IDs encode their from-zone, to-zone, and event number; neither currently collides with a SQL, override, exclusion, or scripted ID. Generator output remains the only source of truth; generated TSV files are never hand-edited.

## Search and routing

The two graph endpoints make `Heavens Tower` a first-class global zone result through the existing graph-zone search path. Exact search returns one canonical zone-242 row without consulting character access state. Selecting it uses the existing cross-zone state machine, routes to the Windurst Walls portal, and advances only after an observed zone change.

Metalworks zone 237 already has ordinary graph edges 912930426 and 812398202. Exact global search currently returns one reachable canonical row. This behavior receives a regression test but no new transition or special-case code.

## Verification

- The generator emits exactly one scripted 239-to-242 edge and one scripted 242-to-239 edge with the documented approaches, landings, event provenance, and no access note.
- The selected scripted IDs collide with no SQL, override, exclusion, or other scripted ID.
- Real-graph paths `239 -> 242` and `242 -> 239` are each exactly one edge.
- Exact global search returns one `Heavens Tower` zone result with empty nation, rank, mission, and key-item fixtures, and selection waits for the actual zone change.
- Exact global search continues to return one `Metalworks` zone-237 result using edge 912930426.
- Root/addon graph and destination mirrors remain byte-identical, and generator, zone-search, Lua 5.1 syntax, and data-integrity suites remain green.
