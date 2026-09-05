"""Give Promyvion-Holla its exits, and its Memory Streams their real names.

WHY
---
Live 2026-08-29 the player entered Promyvion-Holla and reported "this zone needs
work". Two things were wrong, and the second is worse.

1. NAMES. The eleven floor-transit points were spoken as "warp 01".."warp 11".
   Every source agrees they are MEMORY STREAMS -- BG Wiki, FFXIclopedia, Square
   Enix's own 2004 patch notes ("the length of time the \"Memory Stream\" remains
   active"), and LandSandBoat's own code, which names the constant
   MEMORY_STREAM_OFFSET and comments each row 'Associated "Memory stream" NPC ID'.
   The numbers are not arbitrary either: LSB's Zone.lua registers each portal
   with a floor and a compass bearing, and every one matches the npc_list
   coordinates to under 0.09 yalms.

2. THE EXIT WAS NOT IN THE CATALOGUE AT ALL. Zone 16 shipped exactly one `area`
   row -- the Spire of Holla zone line -- and nothing for the way out or for the
   four portals back down a floor. Those five are cylindrical trigger areas in
   Zone.lua with NO entity behind them, so nothing that reads npc_list or
   zonelines can ever see them. A blind player could not select the exit.

   The log shows this live: the blocked beacon aims at 11:58:56 sit at
   (83.9, 89.1), 9.7 yalms from the exit trigger centre at (80, 80). The player
   was standing essentially on the way out with no way to ask for it.

HEIGHTS. The trigger areas are registered as x/z with a radius and no y. Every
catalogued entity in zone 16 sits between y = -0.50 and +0.04, and the player's
own walked position beside the exit was y = -1.000 -- ground they actually stood
on, which is the strongest evidence available. The exit takes that; the other
four take -0.50 from their nearest neighbours and are marked untested.

  py tools/add_promyvion_holla_transitions.py
"""

import io
import sys

TSV = r"C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv"
TAB = chr(9)

# LSB scripts/zones/Promyvion-Holla/Zone.lua onInitialize, verbatim ordering.
# Trigger 1 fires startOptionalCutscene(46) -> setPos(..., 14) = Hall of
# Transference. A scripted exit, not a zone line.
TRANSITIONS = [
    # name, x, z, y, confidence, note
    ("Exit to Hall of Transference", 80.0, 80.0, -1.000, "observed",
     "floor 1 scripted exit"),
    ("Portal down to floor 1", -120.0, 0.0, -0.500, "untested",
     "floor 2 return"),
    ("Portal down to floor 2 (west)", -160.0, 120.0, -0.500, "untested",
     "floor 3 west return"),
    ("Portal down to floor 2 (east)", 160.0, 240.0, -0.500, "untested",
     "floor 3 east return"),
    ("Portal down to floor 3", 120.0, -320.0, -0.500, "untested",
     "floor 4 return"),
]

# LSB Zone.lua portal labels, matched to npc_list coordinates to <0.09 yalms.
# A Memory Stream is transient -- it appears when a Memory Receptacle is
# defeated and lasts three minutes -- so the name says what the place IS, and
# the player still has to find one open.
STREAMS = {
    "warp 01": "Memory Stream (floor 3 west, northeast)",
    "warp 02": "Memory Stream (floor 3 west, northwest)",
    "warp 03": "Memory Stream (floor 3 west, southwest)",
    "warp 04": "Memory Stream (floor 2 northwest, leads east)",
    "warp 05": "Memory Stream (floor 2 southwest, leads west)",
    "warp 06": "Memory Stream (floor 2 southeast, leads east)",
    "warp 07": "Memory Stream (floor 2 northeast, leads west)",
    "warp 08": "Memory Stream (floor 1)",
    "warp 09": "Memory Stream (floor 3 east, northwest)",
    "warp 10": "Memory Stream (floor 3 east, northeast)",
    "warp 11": "Memory Stream (floor 3 east, southeast)",
}


def main():
    raw = io.open(TSV, encoding='utf-8', newline='').read()
    crlf = '\r\n' in raw
    lines = raw.replace('\r\n', '\n').split('\n')

    renamed, present = 0, set()
    out = []
    for line in lines:
        if line.startswith('#') or not line.strip():
            out.append(line)
            continue
        c = line.split(TAB)
        if len(c) > 7 and c[0] == '16':
            if c[1] in STREAMS:
                c[1] = STREAMS[c[1]]
                renamed += 1
                line = TAB.join(c)
            present.add(c[1])
        out.append(line)

    if renamed != len(STREAMS):
        print('RENAME FAIL: expected %d warp rows, renamed %d'
              % (len(STREAMS), renamed))
        return 1
    print('  ok  %d Memory Streams named' % renamed)

    added = 0
    for name, x, z, y, confidence, note in TRANSITIONS:
        if name in present:
            print('  --  already present: %s' % name)
            continue
        row = [
            '16', name, '%.3f' % x, '%.3f' % z, '%.3f' % y,
            'area', 'lsb-zone-script-trigger', confidence,
            'promyvion-holla-triggers-20260829',
            'area:v1:16:trigger-%d' % (added + 1),
            'lsb:scripted_trigger:promyvion_holla_%d' % (added + 1),
            '', note,
        ]
        out.append(TAB.join(row))
        added += 1
    print('  ok  %d scripted transitions added' % added)

    body = '\n'.join(out)
    if not body.endswith('\n'):
        body += '\n'
    io.open(TSV, 'w', encoding='utf-8', newline='').write(
        body if not crlf else body.replace('\n', '\r\n'))
    print('  wrote %s' % TSV)
    return 0


if __name__ == '__main__':
    sys.exit(main())
