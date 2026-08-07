# AccessXI Continuous Route Matching Design

## Goal

Make recorded La Theine guidance behave like live vehicle navigation: every position update determines where the player is on the proven walked route and what lies ahead toward the destination. Movement speed, skipped recorder samples, backtracking, or a small combat detour must not leave guidance attached to stale route progress.

## Root cause

The addon already samples the live player position every 200 ms, but precise recorded routes advance `nav_route_point_index` monotonically. `nav_precise_steering_target` begins at that stored index instead of projecting the current position onto the walked polyline. Once the player passes or moves beside that point, the target can remain behind the player and produce repeated turnarounds.

## Design

1. Match the current player position against every segment of the active recorded route on each precise tracking poll.
2. Score matches with both horizontal and vertical distance so overlapping upper and lower shelves do not alias. On nearly tied parallel legs, retain the current segment to prevent flapping; a materially better live match always wins.
3. Replace the stored index with the matched segment plus one, allowing progress to move forward or backward immediately.
4. When the player is close to the walked line, compute a five-yalm steering target forward from the projected position along the recorded polyline.
5. Stop lookahead at sharp recorded corners until the player reaches the corner, preserving the complete walked geometry.
6. Keep smooth forward lookahead for a lateral deviation up to 3.25 yalms. Beyond that local bound, steer to the projection first; this avoids a forward/back target jump during normal movement while keeping larger recovery conservative.
7. If no safe match exists, return no steering target. The beacon and spoken guidance remain silent rather than guessing through terrain.

The active route remains a path to the destination, but it is no longer waypoint playback. It is continuously map-matched from the player's current position, which is the first safe step toward a multi-recording navigation graph without inventing unwalked links.

## Safety constraints

- Preserve every raw recorded route point.
- Do not add mesh-only or geometric shortcuts between separate recordings.
- Reject a live match beyond 6 horizontal yalms or 4.5 vertical yalms.
- Use the same live match for beacon and spoken guidance.
- Keep generic non-recorded routes unchanged.
- Keep source and live addon copies byte-identical.

## Verification

- A stale early index must jump to the player's actual later segment.
- Moving backward must move the matched index backward.
- A large position jump must update in one poll and not depend on speed.
- A lateral detour must target the route projection before lookahead.
- Vertically overlapping route segments must select the correct layer.
- Sharp corners must not be cut.
- Lua 5.1 syntax and all `test_nav_*.ps1` checks must pass.
- After reload, live logs must show the matched segment following current position with no stale-index rear-target loop during a bounded movement test.
