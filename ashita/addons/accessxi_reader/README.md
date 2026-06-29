# AccessXI Reader

AccessXI Reader is an Ashita v4 addon that makes Final Fantasy XI more usable with speech. It reads many native game menus, chat history, targets, status screens, merchant and trade windows, and provides a spoken navigation browser with route beacons.

This README is for the addon itself. For first-time PlayOnline, account, and installer setup, use the main AccessXI setup guide.

## Loading the Addon

Install the folder as:

```text
Ashita\addons\accessxi_reader
```

Then load it in Ashita:

```text
/addon load accessxi_reader
```

The AccessXI Ashita profile normally loads the addon automatically.

## Quick Start

1. Log in to FFXI and wait for AccessXI Reader to load.
2. Use the normal FFXI menus. Supported menus should speak as you move.
3. If a supported menu is open but did not speak, type `/axi read`.
4. Open the Records of Eminence tutorial path in-game: Quests, Records of Eminence, Tutorial, Basics.
5. When an objective or guide tells you to find an NPC in your current zone, type `/axi nav search <name>`.
6. When an NPC is in another mapped zone, type `/axi zonesearch <name>`.
7. In navigation search results, use `Ctrl+Numpad1` and `Ctrl+Numpad3` to choose a result, then `Ctrl+Numpad Plus` to start the route.

Final Fantasy XI changes over time, and AccessXI should follow the live in-game text whenever possible. Treat the in-game Records of Eminence objective list as the source of truth when it disagrees with an old guide.

## Where Do I Start

For a brand new character, the safest beginner flow is:

1. Start with Records of Eminence.
2. Go to Tutorial, then Basics.
3. Activate the first available objective.
4. If the objective asks you to talk to a named NPC, use AccessXI navigation:

```text
/axi nav search Rolandienne
```

Use `/axi nav search <name>` when you are already in the same area. If the NPC is somewhere else and the zone is mapped, use:

```text
/axi zonesearch Rolandienne
```

The zone search command opens selectable results. It should not immediately start running. Review the result with `Ctrl+Numpad1` and `Ctrl+Numpad3`, then press `Ctrl+Numpad Plus` when you want the route.

Good early priorities:

- Complete the Records of Eminence Tutorial and Basics objectives.
- Unlock and summon Trust magic as soon as the game points you to it.
- Touch Home Points, Survival Guides, and other travel unlocks when you find them.
- Use `/axi nav search <name>` any time a guide says "find", "speak to", or "go to" a named NPC or destination in your current zone.
- Use `/axi zonesearch <npc name>` when you know the NPC name but not the zone path.

Useful external references:

- [Official FFXI Adventuring Primer](https://www.playonline.com/ff11us/contguide/)
- [Official FFXI Windows download and install page](https://www.playonline.com/ff11us/download/media/install_win.html)
- [BG Wiki New Player Leveling Guide](https://www.bg-wiki.com/ffxi/New_Player_Leveling_Guide)
- [BG Wiki Records of Eminence overview](https://www.bg-wiki.com/ffxi/Category:Records_of_Eminence)

## Main Commands

All AccessXI commands can use `/axi`, `/accessxi`, or `/ax`.

```text
/axi read
/axi menu
```

Reads the currently supported menu.

```text
/axi console
/axi ashita
/axi sidebar
```

Opens the accessible Ashita settings reader.

```text
/axi check
/axi checksummary
/axi checkstats
/axi checkinfo
```

Speaks a safe character, status, equipment, or inspect summary when available.

```text
/axi target
/axi look
/axi inspect
/axi readtarget
```

Speaks the current target or nearest target information.

## Navigation Commands

```text
/axi nav
/axi navigation
/axi dest
```

Opens the navigation browser for the current zone.

```text
/axi nav search <name>
/axi nav find <name>
/axi nav filter <name>
```

Searches the navigation browser. Use this for destinations in your current zone or in the loaded navigation data. Results are selectable with the navigation keys.

```text
/axi zonesearch <npc name>
/axi zsearch <npc name>
```

Searches mapped NPCs across zones. This is the command to try when a guide names an NPC but the NPC is not in your current zone. It opens a selectable result list. Choose the result, then start routing with `Ctrl+Numpad Plus`.

```text
/axi nav route <name>
/axi nav goto <name>
/axi route <name>
```

Starts a route to a named destination without opening the browser first.

```text
/axi nav stop
/axi stoproute
/axi stopnav
```

Stops the active route.

```text
/axi beacon
/axi navbeacon
/axi beacon off
```

Turns the navigation beacon on or off.

```text
/axi nav nearby
/axi nearby
```

Speaks nearby known destinations and live entities.

```text
/axi nav points
/axi points
```

Speaks known destinations for the current navigation data.

```text
/axi nav pos
/axi pos
/axi where
```

Speaks your current position.

```text
/axi nav clearance
/axi clearance
/axi wall
```

Speaks nearby wall clearance when available.

```text
/axi nav reload
```

Reloads navigation points, zone lines, and route overrides.

```text
/axi enemies
/axi mobs
/axi enemywarn
/axi enemywarn off
/axi enemywarn range <yalms>
```

Speaks visible nearby enemies or configures enemy warning speech.

## Navigation Browser Keys

These keys work when the game is in focus and chat input is closed.

| Key | Action |
| --- | --- |
| `Ctrl+Numpad7` | Previous navigation category |
| `Ctrl+Numpad9` | Next navigation category |
| `Ctrl+Numpad1` | Previous destination or search result |
| `Ctrl+Numpad3` | Next destination or search result |
| `Ctrl+Numpad Plus` | Start route to the selected destination or result |

Navigation categories are All, Areas, NPCs, Objects, Enemies, NM Spawns, Live NM, and Players.

## Chat Reader Keys

These keys work when the game is in focus and chat input is closed.

| Key | Action |
| --- | --- |
| `Home` | Previous chat category |
| `End` | Next chat category |
| `Page Up` | Read one older chat line |
| `Page Down` | Read one newer chat line |

Chat categories are All, Tell, Linkshell, Party, Say, Shout and Yell, Unity, Combat, System, and Other.

## Ashita Settings Reader Keys

Open the accessible Ashita settings reader with:

```text
/axi console
```

The bundled AccessXI profile also binds this to `Ctrl+Shift+C`.

While the accessible settings reader is open:

| Key | Action |
| --- | --- |
| `Up` | Previous row |
| `Down` | Next row |
| `Right` | Open or activate current row |
| `Enter` | Open or activate current row |
| `Left` | Back |
| `Escape` | Close |
| `Ctrl+Shift+Numpad8` | Previous row |
| `Ctrl+Shift+Numpad2` | Next row |
| `Ctrl+Shift+Numpad6` | Open or activate current row |
| `Ctrl+Shift+Numpad4` | Back |
| `Ctrl+Shift+Numpad5` | Read current row |
| `Ctrl+Shift+Numpad0` | Reload AccessXI Reader |

## Status Keys

These keys work when the relevant status, equipment, or inspect menu is open.

| Key | Action |
| --- | --- |
| `Alt+I` | Speak status, equipment, or inspect overview |
| `Alt+Shift+I` | Speak selected status detail |

## Bundled Profile Binds

The AccessXI Ashita profile includes these additional binds:

| Key | Action |
| --- | --- |
| `Ctrl+Shift+C` | Open `/axi console` |
| `Ctrl+Shift+R` | Reload `accessxi_reader` |
| `Print Screen` | Take an Ashita screenshot with the UI hidden |
| `Ctrl+V` | Paste through Ashita paste support |
| `F11` | Toggle ambient sound |
| `F12` | Toggle FPS display |
| `Ctrl+F1` through `Ctrl+F6` | Target alliance members `<a10>` through `<a15>` |
| `Alt+F1` through `Alt+F6` | Target alliance members `<a20>` through `<a25>` |

## Mapping and Debug Commands

Most players will not need these, but they are useful while improving routes.

```text
/axi nav capture
/axi nav prove
/axi nav bad
/axi nav here <name>
/axi nav audit
/axi nav checklist
/axi nav marktarget <name>
/axi nav marktargetnm <name>
/axi nav marknm <name>
/axi nav mark <name>
```

Use these only when intentionally capturing, correcting, or auditing navigation data.

## Navigation Notes

- `/axi nav search` and `/axi zonesearch` are intentionally different commands.
- `/axi zonesearch` currently searches known NPCs across mapped zones. It is not a global search for every object, enemy, or quest objective.
- Route quality depends on the mapped data for the current zone and nearby zone lines.
- If a route sounds wrong, stop it with `/axi stoproute`.
- The beacon is guidance, not a guarantee that every corner, door, elevation change, or event state is currently passable.

## Repository Notes

This folder is the repository copy of the live AccessXI Ashita addon.

The live test copy currently lives at:

```text
C:\Users\buu42\Ashita\addons\accessxi_reader
```

Before committing release work, sync the live `accessxi_reader.lua`, `modules`, `data`, `resources`, and `sounds` folders into this folder. Do not commit live logs, backup Lua files, generated DLLs, or the large third-party navmesh payloads here.
