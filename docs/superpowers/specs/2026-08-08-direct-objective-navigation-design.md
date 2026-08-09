# Direct Mission and Quest Navigation Design

## User-visible behavior

- Navigation remains one flat browser controlled by the existing keys.
- `O` and `U` move through categories. `Missions` is followed by `Quests`.
- `J`, `K`, and `L` move to the previous item, repeat the current item, and move to the next item.
- `I` starts GPS directly for the highlighted mission or quest, or stops an active or pending route.
- Mission and quest guide steps are not a second navigation menu and never intercept these keys.

## Category contents

- `Missions` contains native active missions plus missions that the current character is proven able to accept now.
- Initially, available-to-start detection is limited to nation gate-guard missions whose state can be derived from the live main mission packet, the live nation-completion packet, and native player nation/rank/rank-point fields. Expansion starters with incomplete client evidence remain hidden.
- `Quests` contains only quests whose current bit is set in the live or same-character display snapshot. It never includes a catalog of merely available quests.

## Routing safety

- An active objective starts GPS only when a deterministic current-stage resolver has selected an exact destination from current navigation data.
- An available nation mission routes to an exact gate-guard NPC already present uniquely in current navigation data.
- Route start requires current-session character-owned packet evidence. Cached mission, quest, completion, or key-item state may support display but cannot start a route.
- Every objective browser row is owned by the native name-and-server identity that produced it. `I` rejects a stale row after a character change, even when the new character has the same objective.
- Active and pending objective routes stop whenever their owner no longer matches or the current native identity cannot be proven. Ordinary navigation is not affected.
- Ambiguous NPC references, missing stage evidence, incomplete packet state, unsupported mission availability, and character changes fail closed with speech instead of guessing.

## Speech

- Each row identifies itself as an active mission, an available mission, or an active quest.
- A routable row says that `I` starts navigation.
- A non-routable active objective stays visible but says that no verified current destination is available.
- Speech never tells the player to open guide steps from the navigation browser.
