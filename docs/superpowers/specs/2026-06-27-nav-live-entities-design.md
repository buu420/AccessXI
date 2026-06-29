# AccessXI Nav Live Entities Design

## Goal

Make AccessXI navigation less noisy and more trustworthy by using the live entities the FFXI client has loaded nearby. The first win is to stop saying or acting like an obstacle exists unless the addon can confirm a real nearby entity in the route corridor. The same live entity view should also improve enemy warnings and make NM detection more useful.

This is scoped to entities the local client can see. It will not try to know every monster or player in the full zone if the game client has not loaded them.

## Current Behavior

The route system currently has two separate signals:

- Dynamic entity obstacle detection scans the Ashita entity table and may steer the beacon around an entity ahead of the route.
- Progress blocking says "Possible obstacle" when the player has not moved closer to the destination for several seconds, even when no entity has been confirmed.

Those two concepts sound too similar. The progress warning can make it feel like a real object or monster is present when the addon only knows that movement did not improve.

Enemy detection already uses nearby live entities through `nav_live_enemies`, but enemy classification is heuristic-heavy. NM menu entries are mainly static "NM spawn" destinations, so they should not be treated as live NM detection.

## Design

Add a small live entity snapshot layer around the existing Ashita entity reads. It should classify nearby loaded entities as player, enemy, npc, object, nm-candidate, or unknown, and store enough evidence for the rest of nav to make conservative choices.

The snapshot should include:

- Entity index and server id.
- Name, distance, position, type, spawn flags, hp percent, status, claim, and name color.
- Whether the entity is currently valid for navigation purposes.
- A short-lived seen cache so disappearances can be detected without pretending to know the whole zone.

Dynamic obstacle avoidance should only steer around entities that pass the live validity checks and are actually in the forward route corridor. It should ignore invalid positions, dead or despawned entries, the player, party/player-like entities unless configured later, obvious objects that are not collision risks, and stale cache entries.

Progress blocking should stop saying "Possible obstacle" unless a confirmed live obstacle was detected during the current progress-watch window. If no live obstacle was seen, it should use clearer language such as:

- "No forward progress. Near wall." when wall clearance is low.
- "No forward progress. Route refreshed." when the route was recalculated.
- "No forward progress. Try turning until the beacon moves off-center." when there is no wall or entity evidence.

Enemy warning should read from the same snapshot layer so it benefits from better validity checks. It should avoid warning for dead entities, stale entries, friendly NPCs, obvious objects, or player entries.

NM support should be split into two meanings:

- "NM Spawns" remains static marked spawn destinations.
- "Live NM candidates" are nearby loaded enemies whose names match either a known NM-name list or a current-zone static NM spawn entry. If no NM name evidence exists for a zone, the system should say "No live NM candidates nearby" instead of pretending the static spawn list is live detection.

## Data Flow

1. Poll the Ashita entity table at a modest rate during nav/enemy warning work.
2. Build a normalized nearby snapshot for the current zone.
3. Update a short-lived seen cache keyed by zone, entity index, server id, and normalized name.
4. Feed the snapshot to dynamic obstacle detection, nav menu live categories, enemy warning, and NM candidate detection.
5. Log concise evidence when a route is changed because of a live obstacle or when a live entity appears/disappears near the player.

## Commands And Speech

Existing commands should keep working. New or clarified speech can be added later if useful, but the implementation pass should prioritize behavior:

- Obstacle speech only for confirmed live obstacles.
- No-progress speech for movement failure without entity proof.
- Enemy warning from live, valid nearby enemies.
- NM candidate speech that clearly says "live candidate" versus "spawn point."

## Error Handling

If the entity manager is unavailable, the snapshot should be empty and nav should continue using route and wall data only. If fields are missing or weird, the entity should be treated as unknown unless enough evidence proves it is safe to classify. Silence is better than false enemy or obstacle warnings.

## Testing

Add static tests that verify:

- The dynamic obstacle path consumes the live snapshot layer instead of raw broad entity scans.
- Progress blocking does not say "Possible obstacle" without a confirmed live obstacle.
- Enemy warning and live nav categories use the same live validity/classification helpers.
- NM spawn points and live NM candidates are separate labels.

Run the existing Lua 5.1 syntax checker after edits:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\buu42\AccessXI\tools\check_lua51_syntax.ps1" -Path "C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua"
```

## Non-Goals

- No OCR or screen-position guessing.
- No whole-zone spawn tracking beyond what the client has loaded.
- No static obstacle tables as a substitute for live entity proof.
- No installer rebuild during probing unless the user asks for packaging.
