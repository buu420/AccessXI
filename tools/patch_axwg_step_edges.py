"""Add the climbing edges a staircase needs, to an AXWG v2 walk graph.

WHY THIS EXISTS
---------------
The grade rule was enforced in two places -- the builder when it emits an edge,
and the loader when it opens the file -- and both judged a short rise over a
short run as though it were a hillside. That is exactly the shape of a
staircase.

Live 2026-08-28, the ramp onto the La Theine Shattered Telepoint: run 0.333,
rise 0.250, grade 0.750 = 36.9 degrees against a 33 degree limit. Every tread
failed in the CLIMBING direction only -- the descent passed the down-grade test
-- so all three La Theine telepoint platforms became one-way islands the player
could walk off and never onto. The player walked those stairs and recorded the
point at the top; the mesh had the treads and no way in.

Both rules now exempt a rise the policy already calls a legal step
(max_step_up). The builder change only affects graphs built from here on, and
the current builder has diverged 4,254 lines from the one that produced the
shipped artifact -- it yields 204,777 nodes where the shipped graph has 249,480
from the byte-identical OBJ. Rebuilding would therefore swap in a materially
different graph, which is what the pinned SHA release gate exists to prevent.

So this patches the shipped graph in place instead: it adds ONLY the reverse
edges that the step rule newly permits, reusing the portal the opposite
direction already crosses. Portals are bidirectional by construction --
Graph:portal(portal_id, from_node_id) accepts either endpoint and mirrors
left/right -- so no portal geometry is invented.

FORMAT (confirmed against modules/walk_graph.lua, which is the authority)
------------------------------------------------------------------------
  header 80B @0, policy 64B, grid 32B, nodes 32B each, edges 20B each,
  portals 48B each, grid buckets 8B each, grid entries 4B each.
  payload_crc32 is a standard CRC-32 over bytes [80, file_size).
  Node edges are CSR: first_edge must equal the running cursor, in node order.

  usage: py tools/patch_axwg_step_edges.py <in.axwg> <out.axwg>
"""

import struct
import sys
import zlib

HEADER_FMT = '<4sHHIIIIIIIIIIIIIIIIHHI'
HEADER_SIZE = 80
NODE_SIZE, EDGE_SIZE, PORTAL_SIZE = 32, 20, 48
EDGE_WALK, EDGE_STEP_DOWN = 0x01, 0x02


def rounded(v):
    return int(v + 0.5) if v >= 0 else -int(-v + 0.5)


def main(src, dst):
    data = bytearray(open(src, 'rb').read())
    h = struct.unpack_from(HEADER_FMT, data, 0)
    (magic, version, header_size, endian, zone, flags, node_count, edge_count,
     nodes_off, edges_off, policy_off, grid_off, grid_buckets, grid_entries,
     payload_crc, file_size, component_count, portal_count, portals_off,
     edge_rec, portal_rec, reserved) = h

    assert magic == b'AXWG' and version == 2, 'not an AXWG v2 file'
    assert header_size == HEADER_SIZE and edge_rec == EDGE_SIZE and portal_rec == PORTAL_SIZE
    assert file_size == len(data), 'file size field disagrees with the file'
    assert zlib.crc32(bytes(data[80:])) & 0xffffffff == payload_crc, 'input CRC mismatch'
    print('  in : zone=%d nodes=%d edges=%d portals=%d components=%d' % (
        zone, node_count, edge_count, portal_count, component_count))

    (max_up_grade, max_down_grade, max_step_up, max_step_down) = struct.unpack_from(
        '<ffff', data, policy_off + 16)
    max_edge_run = struct.unpack_from('<f', data, policy_off + 40)[0]
    print('  policy: max_up_grade=%.6f max_step_up=%.2f max_step_down=%.2f max_edge_run=%.2f' % (
        max_up_grade, max_down_grade if False else max_up_grade, max_step_up, max_edge_run))

    # nodes
    nx, nz, ny, ncomp, nfirst, ncount = [], [], [], [], [], []
    for i in range(node_count):
        o = nodes_off + i * NODE_SIZE
        x, z, y, first_edge, comp, _src_ref, ecount, nflags, _clear = struct.unpack_from(
            '<fffIIIHHf', data, o)
        nx.append(x); nz.append(z); ny.append(y)
        ncomp.append(comp); nfirst.append(first_edge); ncount.append(ecount)

    # edges, grouped by owning node via the CSR ranges
    edges = []
    for e in range(edge_count):
        o = edges_off + e * EDGE_SIZE
        to, cost, rise_cm, run_cm, eflags, ereserved, portal_id = struct.unpack_from(
            '<IfhHHHI', data, o)
        edges.append([to, cost, rise_cm, run_cm, eflags, ereserved, portal_id])
    edge_from = [0] * edge_count
    for i in range(node_count):
        for e in range(nfirst[i], nfirst[i] + ncount[i]):
            edge_from[e] = i

    # portals, and which directions already have an edge
    pa, pb = [], []
    for p in range(portal_count):
        o = portals_off + p * PORTAL_SIZE
        node_a, node_b = struct.unpack_from('<II', data, o)
        pa.append(node_a); pb.append(node_b)
    directions = [0] * portal_count
    for e in range(edge_count):
        frm, to, pid = edge_from[e], edges[e][0], edges[e][6]
        directions[pid] |= 1 if frm == pa[pid] else 2

    # ------------------------------------------------------------------
    # The additions: a reverse crossing the STEP rule permits and the GRADE
    # rule refused. Nothing else -- if the old rule already allowed it, the
    # builder would have emitted it, and its absence means something else
    # rejected it that this patch has no business overriding.
    # ------------------------------------------------------------------
    additions = {}
    considered = skipped_grade_ok = skipped_illegal = 0
    for p in range(portal_count):
        if directions[p] == 3 or directions[p] == 0:
            continue
        frm, to = (pa[p], pb[p]) if directions[p] == 2 else (pb[p], pa[p])
        considered += 1
        if ncomp[frm] != ncomp[to]:
            skipped_illegal += 1
            continue
        dx, dz, dy = nx[to] - nx[frm], nz[to] - nz[frm], ny[to] - ny[frm]
        horizontal = (dx * dx + dz * dz) ** 0.5
        upward = -dy                      # y inverted: positive = climbing
        if horizontal <= 0 or horizontal > max_edge_run + 0.001:
            skipped_illegal += 1
            continue
        if upward > 0:
            grade_ok = upward <= max_up_grade * horizontal + 0.0001
            step_ok = upward <= max_step_up + 0.0001
        else:
            grade_ok = -upward <= max_down_grade * horizontal + 0.0001
            step_ok = -upward <= max_step_down + 0.0001
        if grade_ok:
            # The old rule already allowed this direction; its absence is
            # somebody else's decision. Leave it alone.
            skipped_grade_ok += 1
            continue
        if not step_ok:
            skipped_illegal += 1
            continue

        # Mirror the opposite edge's cost: identical geometry, and the loader
        # requires cost >= the geometric distance.
        opposite_cost = None
        for e in range(edge_count):
            if edges[e][6] == p:
                opposite_cost = edges[e][1]
                break
        distance = (dx * dx + dz * dz + dy * dy) ** 0.5
        cost = max(opposite_cost if opposite_cost is not None else 0.0, distance)
        rise_cm = rounded(upward * 100.0)
        run_cm = rounded(horizontal * 100.0)
        eflags = EDGE_WALK | (EDGE_STEP_DOWN if rise_cm < 0 else 0)
        additions.setdefault(frm, []).append([to, cost, rise_cm, run_cm, eflags, 0, p])

    added = sum(len(v) for v in additions.values())
    print('  one-direction portals considered: %d' % considered)
    print('    already legal by grade (left alone): %d' % skipped_grade_ok)
    print('    illegal even as a step (left alone): %d' % skipped_illegal)
    print('    ADDED as a legal step             : %d' % added)
    if added == 0:
        print('  nothing to do')
        return 1

    # ------------------------------------------------------------------
    # Rebuild the edge table in CSR order.
    # ------------------------------------------------------------------
    new_edges, new_first, new_count = [], [], []
    for i in range(node_count):
        new_first.append(len(new_edges))
        for e in range(nfirst[i], nfirst[i] + ncount[i]):
            new_edges.append(edges[e])
        for extra in additions.get(i, []):
            new_edges.append(extra)
        new_count.append(len(new_edges) - new_first[i])
        assert new_count[i] <= 0xFFFF, 'node %d edge count overflows uint16' % i

    delta = (len(new_edges) - edge_count) * EDGE_SIZE
    new_portals_off = portals_off + delta
    gmin_x, gmin_z, gcell, gw, gh, gbuckets_off, gentries_off, gres = struct.unpack_from(
        '<fffIIIII', data, grid_off)

    out = bytearray()
    out += data[0:HEADER_SIZE]                       # header, patched below
    out += data[HEADER_SIZE:nodes_off]               # policy + grid
    for i in range(node_count):                      # nodes, with new CSR
        o = nodes_off + i * NODE_SIZE
        x, z, y, _fe, comp, src_ref, _ec, nflags, clear = struct.unpack_from(
            '<fffIIIHHf', data, o)
        out += struct.pack('<fffIIIHHf', x, z, y, new_first[i], comp, src_ref,
                           new_count[i], nflags, clear)
    for e in new_edges:
        out += struct.pack('<IfhHHHI', e[0], e[1], e[2], e[3], e[4], e[5], e[6])
    out += data[portals_off:]                        # portals, buckets, entries

    # grid bucket/entry offsets moved with the portals
    struct.pack_into('<fffIIIII', out, grid_off, gmin_x, gmin_z, gcell, gw, gh,
                     gbuckets_off + delta, gentries_off + delta, gres)
    struct.pack_into('<I', out, 24, len(new_edges))      # edge_count
    struct.pack_into('<I', out, 68, new_portals_off)     # portals_offset
    struct.pack_into('<I', out, 56, len(out))            # file_size
    struct.pack_into('<I', out, 52, zlib.crc32(bytes(out[80:])) & 0xffffffff)

    open(dst, 'wb').write(bytes(out))
    print('  out: edges=%d (+%d)  bytes=%d (+%d)' % (
        len(new_edges), len(new_edges) - edge_count, len(out), len(out) - len(data)))
    print('  wrote %s' % dst)
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
