# La Theine Recorded Survey Graph Design

## Goal

Promote the complete friend-guided La Theine recording into first-class navigation data. AccessXI must route over the user's walked geometry, expose every recorded mark as a destination or path anchor, and continue sampling the live player position throughout navigation. It must not replace a recorded course with navmesh, obstacle, or wall targets while a recorded-survey route is active.

## Evidence and Current Gap

Session `20260712-170700-z102` contains 6,499 continuous rows: one start, 6,469 movement points, 28 marks, and one stop. Its maximum consecutive horizontal step is 3.758 yalms and maximum 3D step is 5.846 yalms. The chronological walk is 16,464.4 yalms long because it deliberately explores branches and returns through junctions.

Only seven marked cliff slices, totaling 339 samples, are currently active as recorded corridors. The 28 marks were not imported from this survey as their own destinations. The existing `Telepoint` and `Shattered Telepoint` rows predate the complete survey and do not prove that the full recorded network was integrated.

## Considered Approaches

### Continue adding corridor slices

This preserves the existing implementation but requires manual selection for every new stuck area. It leaves most of the 6,469 walked samples unused and cannot route between arbitrary recorded branches. Rejected as incomplete.

### Treat the recording as one linear route

This uses every row but replays the order in which the zone was surveyed. Routes would include deliberate branch exploration, returns, and loops; the full start-to-end course would be 16,464.4 yalms. Rejected because it recreates the user's circle problem.

### Build a walked survey graph

Selected. Every recording row becomes a graph node. Consecutive recording rows become bidirectional walked edges. When the survey later returns within 0.5 horizontal and 0.75 vertical yalms of an earlier non-adjacent row, one short reunion edge joins those visits as the same physical junction. These reunion edges never span an unrecorded course; they only remove duplicated traversal at a position the character occupied twice.

At those limits the graph contains 64 reunion edges. A shortest path from the survey start to its final mark is approximately 3,530 yalms and uses four reunion edges, each shorter than 0.5 horizontal yalm. This retains full walked geometry while removing chronological exploration loops.

## Data Files

`data/ffxi-nav-recorded-survey.tsv` stores one row per recording row:

```text
survey_id zone node_id sequence x z y event label neighbors source confidence
```

Neighbors contain only consecutive walked nodes and the bounded reunion edges. The generated file is self-contained; the live addon does not depend on the recorder log remaining present.

`data/ffxi-nav-recorded-marks.tsv` stores all 28 marks in the existing navigation-point format. Labels are normalized only for spelling and clarity. Important objects and zone lines retain recognizable names, including `Telepoint`, `Shattered Telepoint`, `Dimensional Portal`, `Survival Guide`, `Cavernous Maw`, `Jugner Forest zone line`, and `Valkurm Dunes zone line`. Stairs and each marked cliff top/bottom remain available as area anchors.

Every mark has source `live-route-recording-20260712-170700-z102`, confidence `proven`, and section `recorded-survey-20260712`.

## Runtime Architecture

A focused code module loads the graph, validates node and edge references, finds the nearest graph node in full 3D, and runs Dijkstra over precomputed adjacency using a binary minimum heap.

For a same-zone La Theine route:

1. The player must be within 6.0 horizontal and 4.5 vertical yalms of the graph.
2. The destination must also be within 6.0 horizontal and 4.5 vertical yalms of the graph.
3. Both endpoints are snapped to their nearest recorded nodes.
4. The graph returns every node in the shortest walked course; it does not geometrically simplify the course.
5. An exact destination is appended only when it lies within 1.5 horizontal and 2.0 vertical yalms of the final recorded node.
6. The route is tagged `lathine-recorded-survey-20260712` and uses precise recorded-route steering.

The West Ronfaure zone line remains on the already successful dedicated recorded corridor because the survey began at the post-zone spawn position rather than the actual zone boundary. The survey graph declines that destination so the verified West corridor and its successful three-point zone-line tail remain authoritative.

When the player is on recorded graph coverage but a non-West destination is not, the graph reports that coverage is required but unavailable. Route planning produces silence rather than inventing an unwalked tail. When the player is outside graph coverage, existing navigation remains available.

## Live Tracking

The graph selects the course; it does not freeze the player position. Existing live sampling, continuous route matching, progress tracking, and stable rejoin anchors continue to consume every player-position update. Running off the course within the verified recovery envelope produces a stable return target; reaching a later graph segment resumes from the live position. Moving outside the envelope produces no precise target.

## Safety Rules

- No graph edge may exceed the raw session's verified 6.0-yalm 3D continuity bound.
- Non-consecutive reunion edges must be at most 0.5 horizontal and 0.75 vertical yalms.
- No navmesh, dynamic obstacle, wall avoidance, or live replan target may replace an active recorded-survey target.
- A missing node, invalid neighbor, disconnected graph, or uncovered destination produces no graph route.
- The raw recording remains the provenance authority; generated graph and mark files are regression-checked against it.

## Verification

Automated tests must prove:

- All 6,499 rows, 6,469 movement samples, and 28 marks are preserved exactly.
- All consecutive edges exist bidirectionally.
- Every reunion edge obeys the 0.5/0.75 limit and no other synthetic edge exists.
- All three data copies are byte-identical.
- All 28 marks load with exact recorded coordinates and proven provenance.
- Routes between distant marked areas use graph adjacency and avoid the chronological exploration loops.
- A destination outside recorded coverage produces no graph route when the player is on the graph.
- West Ronfaure continues to use its dedicated successful corridor.
- Recorded-survey routes remain in precise steering and skip obstacle/wall substitution.
- Lua 5.1 syntax, every navigation regression, live reload, and post-reload logs are clean.
