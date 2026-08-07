# AccessXI Door-Aware Navigation Design

## Goal

Prevent AccessXI from treating an unusable one-point navmesh result as a straight walkable route, and give a door-interaction instruction only when a live, targetable door is actually blocking a valid route.

## Evidence

The Port Windurst route from the live player position `(-190.293, 98.550, -4.000)` to Aroro `(18.629, 76.404, -3.326)` returned one navmesh point: the destination itself. AccessXI accepted that incomplete result and told the player to go straight for about 210 yalms, ending at the wall shown in `Zaltar_2026.07.13_182006.png`.

The same installed Port Windurst mesh returns a complete route when the endpoint is moved only 1.5 yalms south of Aroro. Aroro's normal eight-yalm arrival radius already accepts that approach, so the route can follow current mesh geometry without adding a guessed waypoint or static shop path.

Ashita's official SDK identifies entity type 3 as a broad category containing doors, lights, unique objects, bridges, and similar entities. Type 3 alone is therefore not safe evidence that an obstacle is a door. A door prompt must require both live type 3 and a door-like live entity name.

## Selected Design

### Reachable endpoint approach

- Keep the exact destination as the semantic route destination.
- If the exact navmesh query returns at most one point while the player is outside the destination's normal arrival radius, probe small rings around the endpoint.
- Probe only points within the existing arrival radius, using the current installed mesh.
- Accept only a candidate for which the mesh returns more than one route point.
- Prefer the smallest successful radius, then the shortest valid route.
- Do not append the unusable exact endpoint; arriving at the mesh-derived approach point already satisfies the destination radius.
- If no candidate is reachable, report that no verified walkable route is available. Do not fall back to a long straight line.
- Do not apply endpoint probing to area destinations or zone-line routes, whose exact crossing geometry has separate handling.

### Verified door prompt

- Inspect the current live entity table on each normal route update once the route target is available; do not wait for the slower fully-blocked collision state.
- Require entity type 3 and a non-empty name containing a conservative door term such as `door`, `gate`, `entrance`, `hatch`, `postern`, `portcullis`, or `flap`.
- Require the entity to be nearby and geometrically aligned with the current route target.
- Speak: `Door ahead: <name>. Press Tab until <name> is targeted, then press Enter to open it.`
- Prompt proactively within six yalms. Keep the confirmed-blocked path as a fallback if a door first becomes visible slightly later.
- Pause beacon and ordinary route speech for 2.5 seconds so the instruction is intelligible, then resume the existing route through the doorway.
- Store the door position and route direction at prompt time. Treat the door as passed only when the live player position crosses at least 1.25 yalms beyond the door along that direction.
- Sideways or backward movement must not count as passing through and must never trigger a navmesh replan.
- Never send Tab or Enter automatically, because the live target order can contain NPCs, players, and other objects.

## Live Orastery Correction

The first live run proved the initial collision-only trigger and movement-based replan were wrong:

- At `18:54:39`, `Door:Orastery` was already targetable, but the door prompt had not fired because the fully-blocked classifier had not matured.
- The prompt did not fire until `18:55:14`, after the player had already opened the first door manually.
- At `18:55:25`, the old wait logic saw 2.5 yalms of movement and assumed the player had passed through. The movement was sideways/deeper inside, not across the route.
- The immediate navmesh replan then selected the doorway behind the player and produced repeated turn-around guidance.

The correction separates interaction audio from route state: a short audio pause is allowed, but the current verified route remains intact. Only directional plane crossing clears the door context; it does not force a replan.

## Failure Behavior

- Long one-point mesh result with no reachable endpoint approach: silence except for an explicit `No verified walkable route` message.
- Type 3 entity without a door-like name: no door prompt.
- Door-like name without type 3: no door prompt.
- Verified door outside the route corridor: no door prompt.
- Ordinary wall with no verified live door entity: keep normal collision behavior; never tell the player to press Enter on it.
- Sideways movement after a door prompt: resume the existing beacon after the brief audio pause; do not replan or claim the door was passed.

## Verification

- A regression must prove the exact Aroro mesh query returns one point and a bounded nearby approach returns a multi-point route.
- A regression must prove incomplete long routes cannot fall through to direct steering.
- A regression must prove door recognition requires both type and name, plus route alignment.
- Existing collision tests must continue to prove the collision watcher does not directly spam speech.
- Lua 5.1 syntax validation and byte identity between source and live addon are required before reload.
