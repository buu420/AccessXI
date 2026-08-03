# Same-Zone Re-entry Navigation Design

## Problem

At the live North Gustaberg position `(1.769, -75.402, -0.502)`, FFXINAV returns one waypoint for the Survival Guide at `(-582.687, 52.281, 40.107)`. The destination is valid, but the two points occupy disconnected components of `North_Gustaberg.nav`. Existing navigation rejects that incomplete direct path and never considers leaving and re-entering the same zone.

The current meshes verify a safe route composed of three walking legs:

1. North Gustaberg east component to the east South Gustaberg zone line: 2 waypoints.
2. South Gustaberg east arrival to its west North Gustaberg zone line: 21 waypoints.
3. North Gustaberg west arrival to the Survival Guide: 28 waypoints.

The east transition was traversed in the current live session. The west transition was reached and traversed in prior live route evidence, and its direction into North Gustaberg is corroborated by the official FFXI forum route. The four paired graph edges will therefore be promoted from `untested` to `proven` instead of trusting unrelated untested graph rows.

## Decision

Add a generic one-neighbor same-zone re-entry planner. It is a fallback only after the normal same-zone route and endpoint probes fail. It may choose `A -> B -> A` only when:

- both transition edges are marked `verified` or `proven`;
- the exit and re-entry are different physical zone lines;
- the live mesh returns more than one waypoint for the current-position-to-exit leg;
- the neighboring-zone mesh returns more than one waypoint from the exit arrival to the re-entry departure; and
- the original-zone mesh returns more than one waypoint from the re-entry arrival to the final destination.

The planner ranks candidates by transition confidence, then total verified waypoint count. If any condition fails, the existing unreachable response remains unchanged.

## Runtime Flow

The planner stores the final destination plus exactly two graph edges and reuses the existing zone-search handoff:

1. Guide the player to the first zone line and wait for an observed zone change.
2. Guide from the live position in the neighboring zone to the second zone line and wait again.
3. After re-entering the original zone, discard the detour state and compute a fresh live route to the final destination.

Stopping navigation, starting another route, an unexpected zone, or a failed runtime leg clears the detour. Ordinary cross-zone searches and ordinary reachable same-zone routes retain their current behavior.

## Files

- `ashita/addons/accessxi_reader/modules/same_zone_reentry_navigation.lua`: candidate validation, ranking, and two-leg state.
- `ashita/addons/accessxi_reader/accessxi_reader.lua`: module loading and integration with route start, zone handoff, and state clearing.
- `ashita/addons/accessxi_reader/data/ffxi-nav-zoneline-graph.tsv`: evidence-backed confidence for the two North/South Gustaberg entrances in both directions.
- `tools/test_nav_same_zone_reentry.ps1`: native mesh regression plus Lua state-machine behavior.

## Validation

The regression test must first prove the direct North Gustaberg path is still incomplete and all three detour legs are currently walkable. The Lua test must prove selection of the east-exit/west-re-entry pair, two-step handoff, rejection of the same physical entrance, rejection of unverified edges, and rejection when any walking leg is missing. Existing zone-search, zoning-watch, endpoint-approach, and Lua 5.1 checks must remain green before deployment.
