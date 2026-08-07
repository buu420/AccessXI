# Mission and Quest Navigation Design

## Goal

Add dynamic `Missions` and `Quests` categories to the AccessXI navigation browser. The categories reflect the current character's native active mission and quest state. A row can start navigation only when AccessXI has an explicit, source-backed objective for the exact current stage.

The first verified staged objective is Bastok Mission 1-2, `A Geological Survey`.

## Safety boundary

- Native packet state and installed-client DAT titles determine which missions and quests are active.
- Character ownership is mandatory and uses the native player name plus server ID. Legacy, blank-ID, or mismatched caches are rejected, including same-name characters on different Worlds.
- Persisted mission, quest, and key-item caches may support existing menu display behavior, but never objective routing. Objective lists and stage resolution require complete, matching live-session packet evidence.
- Copied objective targets retain their character owner. A character change cancels active or pending mission/quest navigation without disturbing an ordinary route.
- Objective routing is opt-in per exact mission or quest stage. An active row without a verified objective remains readable but cannot start a route.
- Static guide text is not converted into coordinates automatically.
- Route construction continues through the existing navmesh, recorded-route, zone-graph, and safe same-zone re-entry systems. The feature does not add straight-line fallbacks.
- Dynamic mission and quest rows do not enter `All`; they appear only in their named categories.

## Native state model

### Missions

Use the addon's existing incoming `0x056` mission packet capture and installed mission DAT parser. The category resolves the current row for:

- the character's current nation;
- supported expansion mission contexts with a nonzero, nonterminal current value;
- Aht Urhgan mission fields carried in port `0x0080`.

`65535` and packed add-on value `15` are terminal/no-current sentinels. Zero-valued expansion contexts are omitted because zero cannot be proven active without additional native evidence. National mission zero remains valid and is resolved by exact mission ID. The Voracious Resurgence is omitted until its separate native mission packet is captured; the existing main-packet field named `tales` is the `TalesBeginning` expansion-start bitfield, not a current TVR mission ID.

### Quests

Use current quest-log bitsets from `0x056` ports and titles from the existing installed DAT parser. Enumerate every set bit with a valid native row. The dynamic category waits for a complete current-log snapshot for every native quest area; it does not mix restored and live packet entries. The Aht Urhgan log is limited to IDs 0 through 127 because the upper four words are shared with mission state in retail protocol handling.

An active quest is not removed merely because its completed bit is also set; repeatable quests can legitimately be present in both logs.

## Objective registry

Objective definitions live separately from the state engine. Each definition identifies an exact mission/quest ID and contains deterministic stage predicates, destination evidence, instructions, and a confidence/source note.

For `A Geological Survey` (`Bastok`, mission ID 1):

1. Red acidity tester owned: route to the existing current-nav-data entry for Cid in Metalworks; tell the player to return the results.
2. Blue acidity tester owned: route to the center of the authoritative I-8 Dangruf Wadi geyser trigger; tell the player to stand on the geyser until it launches them to the ledge and verify the tester becomes red.
3. Neither tester owned, with key-item table 0 definitely available: route to Cid; tell the player to obtain the Blue acidity tester.
4. Key-item ownership unavailable or contradictory: expose the active mission but block route start as an unverified stage.

Cid's coordinates are resolved from the current loaded navigation data, not duplicated in the objective registry. The geyser is an explicit objective-only point based on the server trigger cuboid and an offline navmesh reachability probe. It uses a one-yalm arrival radius so navigation does not stop before the narrow trigger.

## Navigation integration

- Add `Missions` and `Quests` as real navigation categories and rebuild them on every category/item action.
- Use objective-specific row speech: active title, position, area/context, and either the current instruction or an explicit lack of a verified route.
- On route start, convert a supported row into its resolved objective point.
- For another zone, feed the exact point into the existing zone-search target flow. For the same zone, use the ordinary verified route path.
- Preserve objective metadata when copying route points so start and arrival speech can explain the interaction.
- Allow a bounded per-destination arrival radius; leave all existing destinations unchanged.
- Prefix cross-zone speech with `Mission objective` or `Quest objective` when appropriate.

## Verification

A Lua 5.1 behavioral harness will cover:

- category presence and isolation from `All`;
- native active quest bit enumeration with changing list sizes;
- the Aht Urhgan 127-ID safety boundary;
- native mission resolution, including national mission ID zero and terminal sentinels;
- same-name, different-server-ID character-switch clearing and objective-only route cancellation;
- rejection of restored mission, quest, and key-item caches for objective routing;
- preservation of objective instructions on ordinary and same-zone re-entry starts;
- all three Geological Survey stages;
- blocked routing when stage state or current nav data is unavailable;
- precise geyser target/instructions and objective metadata preservation.

Repository validation also includes the Lua 5.1 syntax wrapper, relevant existing navigation tests, an offline Dangruf navmesh probe, and live-addon deployment comparison.
