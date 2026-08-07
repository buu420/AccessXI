# AccessXI Authoritative Recorded-Route Steering Design

## Goal

When AccessXI has selected a proven walked La Theine corridor, that corridor is the sole route authority. Live position tracking may advance along it or safely rejoin it, but repeated position updates must not move an already verified rejoin point while the player turns toward it. Static navmesh, dynamic obstacles, and wall probes must not substitute a different steering target while the precise recorded route is active.

## Evidence

The 2026-07-13 00:57:07 West Ronfaure run selected `lathine-recorded-corridor-20260712-west-via-ravine-01`, used 85 route points, and successfully zoned at 01:00:10. During the active run there were zero obstacle substitutions, wall escapes, live replans, or route handoffs. The navmesh was called only while constructing the fixed three-point tail between the final recorded point and the zone line.

The route advanced monotonically, but the beacon changed bins 256 times in about three minutes. At the representative live sample `(-539.226, 451.158, -0.994)`, recorded progress had reached route point 53. The preferred segment's nearest projection was `(-543.880, 448.842, -0.367)`, 5.2 horizontal yalms away and behind the player's current travel. `nav_route_target_from_match` correctly rejected a direct forward shortcut because joining the route ahead would cut a 76-degree recorded corner. It therefore aimed at the safe rear projection. The defect is that every subsequent live sample recomputes that projection, so the rejoin point moves while the player turns and produces the reported correction loop.

## Selected Design

Curated recorded corridors remain authoritative. The raw full-zone survey is not converted into one chronological route because it contains branch exploration, local reversals, and intentional returns.

Precise matching keeps these rules:

- Progress never rewinds.
- A player clearly walking on an earlier recorded leg, within 1.5 horizontal and 2.0 vertical yalms, may receive guidance along that earlier leg so a real backtrack does not cut across a corner.
- A match beyond 6.0 horizontal or 4.5 vertical yalms produces no precise guidance.

Bounded recorded-route recovery becomes a stable rejoin anchor:

- When precise steering first produces `live-route-return`, copy that verified projection into route-local anchor state.
- While the same route-points table remains active and the player is 1.25 to 6.0 horizontal yalms from the anchor with at most 4.5 vertical separation, return that exact anchor without rematching it.
- When the player reaches within 1.25 horizontal and 2.0 vertical yalms of the anchor, clear it and resume continuous forward route matching.
- If the player safely reaches a later recorded segment within 3.25 horizontal and 2.0 vertical yalms, clear the older anchor and resume from that forward live position.
- If the player moves beyond 6.0 horizontal or 4.5 vertical yalms from the anchor, keep the anchor but emit no precise target. This prevents the controller from replacing it with a moving or unverified connector.
- Replacing the route-points table automatically invalidates the anchor, so a restart or replan cannot inherit stale recovery state.

This uses only the live player position and the recorded polyline. It does not ask the navmesh or obstacle probes to choose a different course.

## Data Flow

1. `nav_route_live_match` maps the current live player position to recorded geometry while respecting stored progress.
2. `nav_precise_route_track_index` advances progress monotonically.
3. `nav_route_target_from_match` validates the six-yalm/four-and-a-half-yalm recovery envelope and retains the existing sharp-corner behavior.
4. `nav_precise_steering_target` creates or reuses the route-local rejoin anchor before performing another live match.
5. On reaching the anchor or safely reaching a later segment, precise steering clears the anchor and resumes the existing continuous lookahead.
6. Both spoken guidance and the beacon consume that same precise steering target.
7. Existing `precise_override` guards continue to suppress dynamic obstacle and wall target substitution.

## Failure Behavior

- More than 6.0 horizontal yalms or 4.5 vertical yalms from the stable recovery anchor: no precise target and therefore no beacon direction.
- Sharp recorded corner inside the recovery window: retain the safe projection; never cut the corner.
- Player genuinely backtracks while remaining on an earlier recorded leg: follow that leg back toward stored progress.
- No matching recorded corridor: retain current navmesh behavior outside recorded coverage.

## Verification

Regression coverage must reproduce the live 5.2-yalm sample, prove the initial target is the verified projection, move the player enough that ordinary live projection would change, and prove the controller holds the original anchor. It must then prove that reaching the anchor resumes forward lookahead and moving beyond its verified envelope produces silence without retargeting. Additional cases must prove that a genuine on-path backtrack still follows the recorded bend, sharp corners are not cut, precise routes still skip obstacle/wall substitution, and source/live addon copies remain byte-identical.
