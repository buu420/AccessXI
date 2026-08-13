# Mhaura Rank-2 Collision Transform Design

## Outcome

Mhaura's retail terrain reaches collision READY and produces a capsule-validated route to the Buburimu Peninsula zone line. Valid planar geometry is retained; only triangles that truly collapse after transformation are discarded.

## Root cause

Zone 249's retail model DAT contains three rank-2 instance transforms whose determinant is zero because their unused local Z axis has zero scale. Their referenced source vertices all use local `z=0`, so the transformed quads remain valid vertical collision surfaces. The current MZB parser rejects the entire zone before transforming vertices whenever `abs(determinant) < 1e-12`.

The exact retail fixture is `ROM\1\44.DAT`, SHA-256 `43ed3f17ccfdb1092af9bed77ceaf54ece101bfb94764717fd4b37992f3bdc25`. The three affected transforms produce six nondegenerate triangles of approximately four square yalms each.

## Parser contract

- Continue rejecting nonfinite transforms and nonfinite transformed vertices.
- Do not reject an instance solely because its 3-by-3 linear transform is singular.
- Transform vertices first and evaluate each referenced triangle in native space.
- Classify a triangle as collapsed only when its cross-product magnitude squared is at or below `1e-12 * max(maxEdgeSquared, 1)^2`, or when the computed geometry is nonfinite.
- Omit collapsed triangles. If every triangle in an instance collapses, roll back its unused transformed vertices so zero-area data does not pollute bounds or allocation counts.
- Preserve determinant-based winding for nonsingular transforms. For singular transforms, preserve source order unless `normal.y < -1e-6 * sqrt(normalLengthSquared)`; reverse only that downward-facing triangle so Recast sees an upward walkable floor while vertical surfaces retain source order.
- Publish a zone only after the entire parse and navigation build succeeds. Partial terrain is never usable.

An installed FFXINAV route is not a fallback for a failed or partial collision load. It may only contribute after collision READY and after every candidate segment passes the authoritative player-sized capsule checks.

## Verification

Native RED/GREEN coverage must include:

- a synthetic rank-2 planar quad whose triangles survive;
- a synthetic rank-1 or zero-scale instance whose collapsed triangles and unused vertices are omitted;
- the installed zone-249 DAT, pinned to 3,010 instances, 31,318 vertices, 34,885 triangles, bounds `(-83.787917,-1.041260,-40.0)` to `(80.0,61.357300,195.247002)`, with all six affected triangles present and nondegenerate;
- an end-to-end zone-249 route from `(-12.750,86.286,-15.791)` to the Buburimu approach `(-0.179,121.015,-8.549)`, with finite route points and every segment accepted by the loaded terrain's capsule and step checks.

All collision parser, world, Recast, context, ABI, reproducible-build, Lua lifecycle, and reader integration suites remain release gates. The rebuilt deterministic DLL, manifest hash, stage copy, and live copy must agree before launch.
