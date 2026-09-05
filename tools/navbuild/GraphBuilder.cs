// Builds a walkability graph directly from FFXI's collision triangles.
//
// Why this exists: the shipped navmeshes mark cliff faces walkable. Measured on
// 2026-08-20 against these very triangles, the route out of the player's stuck
// position in La Theine had legs at 66.9 and 68.1 degrees, with continuous
// floor -- real ground, but a cliff, and the mesh called it a path. The player
// (blind, steering by an audio beacon) walked into it repeatedly.
//
// Detour compounds it: FindPath returns corridor PORTAL points and does not
// string-pull, so even a correct corridor cannot be checked leg by leg -- the
// straight line between distant portals crosses terrain the real path curves
// around. We have been treating corridors as paths.
//
// So: keep the triangles a player can stand on, connect the ones they can
// actually step between, and search that. Every edge in this graph is a step
// somebody could really take.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace NavBuild
{
    internal static class GraphBuilder
    {
        // FFXI's Y axis points DOWN, so a SMALLER y is HIGHER ground.
        private const int Magic = 0x47585541;   // "AUXG"
        private const int Version = 1;
        // Past this we stop measuring and call the ground open; nothing the agent
        // needs to know lives beyond three yalms of room.
        private const float ClearanceCap = 3.0f;
        // Capsule height for headroom. Geometry above this does not narrow a doorway.
        private const double AgentHeight = 1.8;

        internal sealed class Options
        {
            public double MaxSlopeDeg = 33.0;   // a FLOOR from walked data, not a proven limit
            public double MaxStepUp = 0.50;     // a kerb at a shared edge, not a ledge
            public double MaxStepDown = 0.50;   // supported descent, still touching ground
            // Unsupported drops are DISABLED in v1. The 2.24 descent ratio in the
            // walked data comes from 2-second samples -- the same smoothing that
            // hid the steep climbs -- so it says nothing about what fall the
            // player survives or would accept being sent over. Enable only with
            // controlled evidence.
            public double MaxDrop = 0.0;
            public double AgentRadius = 0.70;   // matches the Recast bake we are replacing

            // Erode the REGION by this radius instead of certifying each doorway
            // on its own. Zero keeps the per-doorway rule.
            //
            // Per-doorway certification asks "can the body's centre cross THIS
            // edge at least a radius clear of every wall". For a real gateway
            // that is the right question. For an internal edge of continuous
            // ground it is not a question at all -- the edge is an artefact of
            // how the surface was cut into triangles, and the body crossing that
            // ground has no obligation to cross that particular edge. Asking it
            // anyway blocked 28,869 doorways and left the zone in 34,244 pieces
            // with 5.4% of WALKED positions outside the main one.
            //
            // Eroding the region instead states the constraint once, where it
            // belongs: the body's centre stays this far from a wall, everywhere.
            // Whatever ground survives is connected by plain geometric
            // continuity, because a body standing anywhere on it already fits.
            public double RegionErode = 0.0;

            // The longest horizontal run a single transition may claim. The
            // format records this and the loader enforces it, so it has to be
            // true of what is written. Seam joins can pair centroids further
            // apart than shared-edge neighbours ever were, so the limit is now
            // applied where transitions are filtered rather than asserted at
            // write time and discovered by the loader.
            public double MaxEdgeRun = 4.0;

            // The old rule: a doorway certified to zero capacity kills the
            // crossing. Kept only so the damage can be re-measured; the
            // collision-model filter replaced it.
            public bool DoorwayVeto = false;

            // Diagnostic box (game-frame XZ): log every stage decision that
            // touches an edge or portal whose geometry falls inside it.
            public bool HasDiag = false;
            public double DiagX0, DiagZ0, DiagX1, DiagZ1;

            // Named start/goal pairs routed on the finished graph and then walked
            // against the collision model, leg by leg. These are regressions, not
            // statistics: a zone can pass every aggregate and still fail the one
            // crossing a player is standing on.
            public List<(string Name, double SX, double SZ, double SY,
                         double GX, double GZ, double GY)> Probes = new();
            public int ZoneId = 0;
            public string SurveyPath = "";
            // Written before erosion, read by stage 3. See WriteBaseline.
            public string BaselinePath = "";
            public string DestinationsPath = "";
            // One row per destination the walked ground cannot reach, with the
            // evidence for why. See ReportControlTopology.
            public string TriagePath = "";
            // Run both side tests and print the comparison. Off by default: the
            // centroid one is superseded and only kept to show what it cost.
            public bool SideTestAB = false;
            // (wall radius, rim radius) pairs to measure. Empty = do not erode.
            // Measurement only -- nothing downstream reads the result yet.
            public List<(double Wall, double Rim)> ErodeRadii = new List<(double, double)>();
            public double WeldTolerance = 0.01;   // yalms; seams wider than this split the graph
            // Diagnostic only: reproduce the old first-owner wiring, which connects
            // every later owner of an edge to whichever triangle claimed it first.
            // Unsound -- it invents links -- but needed to isolate WHICH change
            // costs connectivity rather than guessing.
            public bool PermissivePortals = false;
            // 1 = the old edge-clearance layout, 2 = portal table with certified
            // safe intervals. v1 is kept only so the two can be compared.
            public int FormatVersion = 2;

            // Grade limits as rise/run, derived from MaxSlopeDeg unless overridden.
            // A shared-edge neighbour has no step, so grade is the only bound.
            public double MaxUpGrade = Math.Tan(33.0 * Math.PI / 180.0);
            public double MaxDownGrade = Math.Tan(33.0 * Math.PI / 180.0);
        }

        private struct Tri
        {
            public int A, B, C;
            public float Cx, Cy, Cz;   // centroid
            public float SlopeDeg;
        }

        // A doorway between two standable faces, and the part of it a body can
        // actually occupy.
        //
        // This exists because a scalar cannot steer anybody. "Something fits
        // somewhere along this edge" does not tell the beacon WHERE to send the
        // player, and a route through triangle centres is not a walking
        // instruction -- the centre-to-centre line can cross terrain the real
        // path curves around. That is the same mistake as treating a Detour
        // corridor as a path, which is what started all of this.
        private sealed class Portal
        {
            public int A, B;                    // node ids, A < B
            public int P, Q;                    // canonical endpoints of the shared edge
            public int A0, A1, B0, B1;          // each face's own raw verts at P and Q
            public float LeftX, LeftZ;          // certified safe interval, travelling A -> B
            public float RightX, RightZ;
            public float LeftYA, LeftYB;        // each owner's surface height at each end
            public float RightYA, RightYB;
            public int CapacityCm;
            public int Flags;
            public int Extra;                   // safe components beyond the one serialized

            // The span of the canonical edge the two faces ACTUALLY share, and
            // where each face's own raw endpoints sit along it. Certification has
            // to erode this, not the whole welded edge: the welded edge is a
            // canonical label, and the doorway is only where both surfaces are
            // really present. Interpolating owner heights over a blind 0..1 gets
            // them from the wrong place for the same reason.
            public double OverlapLo, OverlapHi;
            public double SA0, SA1, SB0, SB1;
        }

        [Flags]
        private enum PortalFlag
        {
            SafeIntervalCertified = 0x01,
            WallEroded            = 0x02,
            HeadroomChecked       = 0x04,
            FullCapsuleChecked    = 0x08,
            HazardMarginTrimmed   = 0x10,   // narrowed away from a lateral slide hazard by radius + 1.5
        }

        // ---------------------------------------------------------------
        // Pinned cases.
        //
        // Every one of these is a bug that actually happened here, or a bug the
        // check that was supposed to catch it could not see. They are pinned so
        // that fixing one cannot quietly reintroduce another, and so the geometry
        // routines are exercised on shapes small enough to work out by hand.
        //
        // Run: navbuild selftest
        // ---------------------------------------------------------------
        public static int SelfTest()
        {
            int pass = 0, fail = 0;
            void Check(string name, bool ok, string detail = "")
            {
                if (ok) { pass++; Console.WriteLine($"  PASS  {name}"); }
                else { fail++; Console.WriteLine($"  FAIL  {name}   {detail}"); }
            }
            static List<(double X, double Z)> Square(double x0, double z0, double x1, double z1)
                => new List<(double X, double Z)> { (x0, z0), (x1, z0), (x1, z1), (x0, z1) };

            Console.WriteLine("\n== polygon-to-segment distance: the cases a vertex-only check cannot see ==");

            // A segment straight through the middle of a cell. Every cell corner
            // is far from it; the true distance is zero. The vertex-only verifier
            // reported this as clearance of 1.0 and called the cell clean.
            var unit = Square(0, 0, 2, 2);
            Check("a segment crossing the cell has distance zero",
                  PolySegDistance(unit, -1, 1, 3, 1) == 0.0,
                  PolySegDistance(unit, -1, 1, 3, 1).ToString("F4"));

            // A segment lying wholly inside the cell. Nearest corner is 0.5 away.
            Check("a segment contained in the cell has distance zero",
                  PolySegDistance(unit, 0.9, 1.0, 1.1, 1.0) == 0.0,
                  PolySegDistance(unit, 0.9, 1.0, 1.1, 1.0).ToString("F4"));

            // A segment clipping one corner only -- crosses two edges near (2,2).
            Check("a segment clipping one corner has distance zero",
                  PolySegDistance(unit, 1.5, 2.5, 2.5, 1.5) == 0.0);

            // Genuine clearance, measured corner-to-segment.
            Check("a segment beside the cell measures the gap",
                  Math.Abs(PolySegDistance(unit, 3.0, 0.0, 3.0, 2.0) - 1.0) < 1e-9,
                  PolySegDistance(unit, 3.0, 0.0, 3.0, 2.0).ToString("F6"));

            // Clearance attained from a SEGMENT ENDPOINT to a cell EDGE, not from
            // a cell vertex. Checking only one direction misses this.
            Check("clearance from a segment endpoint to a cell edge is found",
                  Math.Abs(PolySegDistance(unit, 1.0, 3.0, 1.0, 5.0) - 1.0) < 1e-9,
                  PolySegDistance(unit, 1.0, 3.0, 1.0, 5.0).ToString("F6"));

            Console.WriteLine("\n== the circumscribed obstacle really does contain the stadium ==");
            {
                var ob = new List<(double X, double Z)>();
                const double R = 0.70;
                ObstacleFor(0.0, 0.0, 3.0, 0.0, R, ob);
                bool convexCcw = SignedArea(ob) > 0.0;
                Check("the obstacle is convex and counter-clockwise", convexCcw,
                      SignedArea(ob).ToString("F4"));

                // Every point within R of the segment must be inside it, or the
                // erosion leaves ground it claimed to remove.
                bool contains = true; double worst = 0.0;
                for (int i = 0; i <= 360; i += 3)
                {
                    double a = i * Math.PI / 180.0;
                    foreach (double s in new[] { 0.0, 1.5, 3.0 })
                    {
                        double px = s + Math.Cos(a) * R * 0.999;
                        double pz = Math.Sin(a) * R * 0.999;
                        if (!PointInConvex(ob, px, pz))
                        { contains = false; worst = Math.Max(worst, R); }
                    }
                }
                Check("every point within the radius is inside the obstacle", contains);

                // And it must not be wildly larger, or we erode ground for free.
                double far = 0.0;
                foreach (var p in ob)
                    far = Math.Max(far, PointSegDist(p.X, p.Z, 0, 0, 3, 0, out _));
                double bound = R / Math.Cos(Math.PI / ErosionFacets);
                Check("and no further out than the circumscribed bound", far <= bound + 1e-9,
                      $"reached {far:F4}, bound {bound:F4}");
            }

            Console.WriteLine("\n== convex subtraction ==");
            {
                // Cutting a bar across the middle must leave exactly two pieces
                // and the arithmetic must add up.
                var pieces = new List<List<(double X, double Z)>>();
                SubtractConvex(Square(0, 0, 4, 4), Square(-1, 1.5, 5, 2.5), pieces, 1e-9);
                double area = 0.0;
                foreach (var p in pieces) area += PolyArea(p);
                Check("a bar across the middle leaves two pieces", pieces.Count == 2,
                      pieces.Count.ToString());
                Check("and the surviving area is what is left over",
                      Math.Abs(area - 12.0) < 1e-9, area.ToString("F6"));

                // An obstacle covering everything must leave nothing.
                pieces.Clear();
                SubtractConvex(Square(0, 0, 4, 4), Square(-1, -1, 5, 5), pieces, 1e-9);
                double area2 = 0.0;
                foreach (var p in pieces) area2 += PolyArea(p);
                Check("an obstacle covering the cell leaves nothing", area2 < 1e-9,
                      area2.ToString("F6"));

                // An obstacle that misses must leave the cell whole.
                pieces.Clear();
                SubtractConvex(Square(0, 0, 4, 4), Square(9, 9, 10, 10), pieces, 1e-9);
                double area3 = 0.0;
                foreach (var p in pieces) area3 += PolyArea(p);
                Check("an obstacle that misses leaves the cell whole",
                      Math.Abs(area3 - 16.0) < 1e-9, area3.ToString("F6"));

                // An obstacle biting a corner leaves a non-convex remainder, so it
                // must come back as more than one convex piece, still summing.
                pieces.Clear();
                SubtractConvex(Square(0, 0, 4, 4), Square(3, 3, 5, 5), pieces, 1e-9);
                double area4 = 0.0;
                foreach (var p in pieces) area4 += PolyArea(p);
                Check("a corner bite leaves convex pieces that still sum",
                      Math.Abs(area4 - 15.0) < 1e-9, area4.ToString("F6"));
            }

            Console.WriteLine("\n== the layer rules, on the shapes that fooled them ==");
            {
                const double H = 1.8, StepUp = 0.50, StepDown = 0.50;
                // Written here the way the VERIFIER derives it, over the
                // difference between boundary height and surface height.
                static bool WallInLayer(double dLo, double dHi, double rise, double h, double step)
                    => dHi >= -h && dLo < rise - step;   // STRICT: a wall must rise MORE than a step
                static bool RimInLayer(double dLo, double dHi, double stepDown)
                    => dHi >= -stepDown && dLo <= stepDown;

                // The 0.50 riser the player stands ON TOP OF. From up here the
                // boundary sits 0.50 below (game y is down, so +0.50), and the
                // thing rises exactly to your feet. It is a step, not a wall.
                Check("a 0.50 riser you are standing on top of is not a wall",
                      !WallInLayer(0.50, 0.50, 0.50, H, StepUp));

                // The same riser seen from the floor below: it rises 0.50 above
                // you. Still a step you walk up.
                Check("a 0.50 riser seen from below is still a step",
                      !WallInLayer(0.0, 0.0, 0.50, H, StepUp));

                // A 0.51 riser is over the step limit and does obstruct.
                Check("a 0.51 riser does obstruct", WallInLayer(0.0, 0.0, 0.51, H, StepUp));

                // The arch overhead: its base is 20 yalms above your feet, so the
                // difference is -20. Nothing of it reaches your body.
                Check("an arch 20 yalms overhead does not obstruct",
                      !WallInLayer(-20.0, -20.0, 4.5, H, StepUp));

                // A tall wall standing on your own floor obstructs.
                Check("a tall wall on your own floor obstructs",
                      WallInLayer(0.0, 0.0, 3.0, H, StepUp));

                // A rim on your own footing matters; one on a ledge below does not.
                Check("a rim at your footing matters", RimInLayer(0.0, 0.0, StepDown));
                Check("a rim two yalms below does not", !RimInLayer(2.0, 2.0, StepDown));

                // A sloped floor: the surface climbs 1.2 across the cell while the
                // boundary sits flat, so the DIFFERENCE spans a range. It must be
                // caught if any part of that range is in the band -- this is the
                // case a single-point test at the wrong end silently drops.
                Check("a sloped cell is caught when only part of it is in layer",
                      RimInLayer(-1.2, 0.3, StepDown));
                Check("and not caught when none of it is",
                      !RimInLayer(-3.0, -1.2, StepDown));
            }

            Console.WriteLine($"\n{pass} passed, {fail} failed\n");
            return fail == 0 ? 0 : 1;
        }

        public static int Run(string objPath, string outPath, Options opt)
        {
            var vx = new List<float>(700_000);
            var vy = new List<float>(700_000);
            var vz = new List<float>(700_000);
            var tris = new List<Tri>(600_000);

            // Triangles too steep to stand on are still the only evidence we have
            // for where a WALL is. Discarding them left the builder unable to tell
            // a wall from a cliff rim, and clearance -- which exists precisely to
            // keep the player off walls -- had to guess from the shape of the
            // walkable set alone. It guessed badly.
            var steep = new List<(int A, int B, int C)>(200_000);

            var seenFaces = new HashSet<((long, long, long), (long, long, long), (long, long, long))>(600_000);
            long duplicateFaces = 0;

            var inv = CultureInfo.InvariantCulture;
            using (var reader = new StreamReader(objPath))
            {
                string? line;
                while ((line = reader.ReadLine()) != null)
                {
                    if (line.Length < 2) continue;
                    if (line[0] == 'v' && line[1] == ' ')
                    {
                        var p = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                        if (p.Length < 4) continue;
                        vx.Add(float.Parse(p[1], inv));
                        vy.Add(float.Parse(p[2], inv));
                        vz.Add(float.Parse(p[3], inv));
                    }
                    else if (line[0] == 'f' && line[1] == ' ')
                    {
                        var p = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                        if (p.Length < 4) continue;
                        int a = FaceIndex(p[1]), b = FaceIndex(p[2]), c = FaceIndex(p[3]);
                        if (a < 0 || b < 0 || c < 0) continue;
                        if (a >= vx.Count || b >= vx.Count || c >= vx.Count) continue;

                        // Drop duplicated faces BEFORE anything else looks at the
                        // mesh. This zone ships 19074 extra copies of triangles it
                        // already has, and every downstream stage was being wrecked
                        // by them: a face and its own copy share all three edges, so
                        // an ordinary two-face join appears as a four-owner fan, and
                        // the copy also registers as a neighbour lying on the SAME
                        // side of the shared edge as the original. That accounted
                        // for 29602 of 29721 fans and 14033 of 14052 same-side
                        // rejections -- almost the entire population of both.
                        //
                        // Match on RAW coordinates, winding-independent, at export
                        // precision. Not on welded ids: the 0.25 weld is coarse
                        // enough to fuse genuinely distinct faces, and de-duplicating
                        // through it would delete real ground.
                        var k1 = VKey(vx[a], vy[a], vz[a]);
                        var k2 = VKey(vx[b], vy[b], vz[b]);
                        var k3 = VKey(vx[c], vy[c], vz[c]);
                        SortKeys(ref k1, ref k2, ref k3);
                        if (!seenFaces.Add((k1, k2, k3))) { duplicateFaces++; continue; }

                        double ux = vx[b] - vx[a], uy = vy[b] - vy[a], uz = vz[b] - vz[a];
                        double wx = vx[c] - vx[a], wy = vy[c] - vy[a], wz = vz[c] - vz[a];
                        double nx = uy * wz - uz * wy;
                        double ny = uz * wx - ux * wz;
                        double nz = ux * wy - uy * wx;
                        double len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
                        if (len < 1e-9) continue;

                        // Angle of the surface normal away from vertical.
                        double slope = Math.Acos(Math.Min(1.0, Math.Abs(ny) / len)) * 180.0 / Math.PI;
                        if (slope > opt.MaxSlopeDeg) { steep.Add((a, b, c)); continue; }   // cannot stand here

                        // Convert to GAME coordinates here, once, so nothing
                        // downstream has to remember. The collision OBJ is in
                        // game space with Y and Z NEGATED -- verified on 40
                        // walked samples, mean error 0.04 yalms. Reading it raw
                        // still finds triangles, just elsewhere in the zone, so
                        // the mistake is silent: it produced a cliff measured at
                        // the wrong location and a graph that matched only 4% of
                        // the player's real positions.
                        tris.Add(new Tri
                        {
                            A = a, B = b, C = c,
                            Cx =  (vx[a] + vx[b] + vx[c]) / 3f,
                            Cy = -(vy[a] + vy[b] + vy[c]) / 3f,
                            Cz = -(vz[a] + vz[b] + vz[c]) / 3f,
                            SlopeDeg = (float)slope,
                        });
                    }
                }
            }

            Console.WriteLine($"graph: vertices={vx.Count} standable_triangles={tris.Count} " +
                              $"steep_triangles={steep.Count} duplicate_faces={duplicateFaces} (slope <= {opt.MaxSlopeDeg:F0} deg)");

            // Weld vertices by POSITION before looking for shared edges. The DAT
            // export duplicates them -- 690473 vertices for 556974 faces, where a
            // fully shared mesh would have roughly half as many as faces -- so
            // triangles that physically touch often carry different indices.
            // Index-based adjacency silently missed them: the first build found
            // 1.49 edges per node where a connected surface should approach 3,
            // and consequently called 82% of the zone too narrow to stand in.
            // Tolerance matters more than it looks. FFXI zone collision is
            // assembled from many separate models, and abutting pieces do not
            // share exact vertices -- anything further apart than the tolerance
            // leaves a seam, and a seam splits the graph into islands the player
            // can walk across but the search cannot.
            //
            // Assign each vertex to its NEAREST representative, which bounds a
            // cluster to twice the tolerance. Determinism comes from processing in
            // an order derived from GEOMETRY -- sorted by position -- rather than
            // the order faces happen to appear in the OBJ, so shuffling the file
            // cannot change the result. The previous first-match-and-overwrite
            // version lost 217 representatives, left 1806 vertices with more than
            // one eligible representative, and in 719 cases welded to something
            // other than the nearest, by up to 0.199989 yalms.
            //
            // Transitive closure is the obvious alternative and it is WRONG here:
            // union-find over every within-tolerance pair chains, so a-b and b-c
            // merge a with c however far apart they are. Tried at 0.25 it produced
            // clusters spanning 2.459 yalms -- wider than a typical triangle --
            // fusing unrelated ground into single points.
            double weldTol = Math.Max(1e-4, opt.WeldTolerance);
            var canon = new int[vx.Count];
            var order = new int[vx.Count];
            for (int i = 0; i < vx.Count; i++) order[i] = i;
            Array.Sort(order, (a, b) =>
            {
                int c = vx[a].CompareTo(vx[b]); if (c != 0) return c;
                c = vy[a].CompareTo(vy[b]);     if (c != 0) return c;
                c = vz[a].CompareTo(vz[b]);     if (c != 0) return c;
                return a.CompareTo(b);
            });

            var buckets = new Dictionary<(int, int, int), List<int>>(vx.Count);
            double tol2 = weldTol * weldTol;
            long ambiguous = 0;
            foreach (int i in order)
            {
                int kx = (int)Math.Floor(vx[i] / weldTol);
                int ky = (int)Math.Floor(vy[i] / weldTol);
                int kz = (int)Math.Floor(vz[i] / weldTol);
                int best = -1; double bestD = double.MaxValue; int within = 0;
                // Neighbouring cells too: two points a millimetre apart can still
                // land either side of a cell boundary and never meet.
                for (int ox = -1; ox <= 1; ox++)
                for (int oy = -1; oy <= 1; oy++)
                for (int oz = -1; oz <= 1; oz++)
                {
                    if (!buckets.TryGetValue((kx + ox, ky + oy, kz + oz), out var reps)) continue;
                    foreach (int c in reps)
                    {
                        double dx = vx[i] - vx[c], dy = vy[i] - vy[c], dz = vz[i] - vz[c];
                        double d = dx * dx + dy * dy + dz * dz;
                        if (d > tol2) continue;
                        within++;
                        // Nearest wins; equal distances resolve to the lower index
                        // so the choice never depends on enumeration order.
                        if (d < bestD || (d == bestD && c < best)) { bestD = d; best = c; }
                    }
                }
                if (within > 1) ambiguous++;
                if (best >= 0) canon[i] = best;
                else
                {
                    canon[i] = i;
                    var key = (kx, ky, kz);
                    if (!buckets.TryGetValue(key, out var list)) buckets[key] = list = new List<int>(2);
                    list.Add(i);
                }
            }
            if (ambiguous > 0)
                Console.WriteLine($"graph: WARNING {ambiguous} vertices had more than one representative " +
                                  $"within {weldTol:F3}; nearest was taken");

            // Report the widest cluster so a tolerance that fuses real ground
            // cannot creep in silently.
            var clusterMin = new Dictionary<int, (float x, float y, float z, float X, float Y, float Z)>();
            foreach (int i in Enumerable.Range(0, vx.Count))
            {
                int r = canon[i];
                if (!clusterMin.TryGetValue(r, out var b2))
                    clusterMin[r] = (vx[i], vy[i], vz[i], vx[i], vy[i], vz[i]);
                else
                    clusterMin[r] = (Math.Min(b2.x, vx[i]), Math.Min(b2.y, vy[i]), Math.Min(b2.z, vz[i]),
                                     Math.Max(b2.X, vx[i]), Math.Max(b2.Y, vy[i]), Math.Max(b2.Z, vz[i]));
            }
            double worstSpan = 0;
            foreach (var b3 in clusterMin.Values)
            {
                double sx = b3.X - b3.x, sy = b3.Y - b3.y, sz = b3.Z - b3.z;
                worstSpan = Math.Max(worstSpan, Math.Sqrt(sx * sx + sy * sy + sz * sz));
            }
            Console.WriteLine($"graph: welded {vx.Count} vertices to {clusterMin.Count} distinct positions " +
                              $"(tol={weldTol:F3}, widest cluster spans {worstSpan:F3})");

            // Which shared edges are WALLS. A steep triangle hinged on an edge
            // either rises above it -- a wall your body cannot occupy -- or falls
            // away below it -- a cliff face, whose top edge is a rim you can stand
            // on and walk along. Those are opposite facts about the same geometry,
            // and clearance must only be seeded by the first.
            //
            // The discriminator is the steep triangle's OPPOSITE vertex, not its
            // centroid: the shared edge is the hinge, so the third corner is what
            // says which way the surface swings. y is DOWN, so above means less.
            //
            // Height threshold is MaxStepUp for the same reason the walk filter
            // uses it: something you can step over is not a wall, it is a kerb,
            // and treating every rock as a wall reintroduces the bug this fixes.
            var wallEdges = new HashSet<long>(steep.Count * 2);
            foreach (var (sa, sb, sc) in steep)
            {
                MarkWall(wallEdges, canon, vy, sa, sb, sc, opt.MaxStepUp);
                MarkWall(wallEdges, canon, vy, sb, sc, sa, opt.MaxStepUp);
                MarkWall(wallEdges, canon, vy, sc, sa, sb, opt.MaxStepUp);
            }
            Console.WriteLine($"graph: wall_edges={wallEdges.Count} " +
                              $"(steep faces rising >= {opt.MaxStepUp:F2} above a shared edge)");

            // Every welded vertex that any wall edge touches. A doorway is
            // narrowed by its walled ENDS, so this is what the gate width below
            // is measured against.
            var wallVerts = new HashSet<int>(wallEdges.Count);
            foreach (long key in wallEdges)
            {
                wallVerts.Add((int)(key >> 32));
                wallVerts.Add((int)(key & 0xFFFFFFFF));
            }

            // Adjacency by shared edge. Two standable triangles that share an edge
            // are candidates; whether the player can actually make that step is
            // decided below, and deliberately ASYMMETRIC -- you can drop off a
            // ledge you could never climb back up.
            //
            // Collect ALL owners of each welded edge first, then decide. Keeping
            // a single owner and wiring every later triangle to it invented
            // connections: 30283 edge keys here have more than two standable
            // owners, one of them 21, and 51237 of those first-owner links passed
            // the safety filter. At least 110 joined triangles lying on the SAME
            // side of the supposed doorway -- geometry you cannot walk through
            // because there is nothing to walk between.
            //
            // Every PAIR of owners is then judged on its own evidence, and every
            // pair that proves itself is kept -- see the gates below. Requiring
            // exactly two owners and discarding the rest was tried and is wrong:
            // after de-duplication the ~121 surviving multi-owner edges are the
            // seams where the zone's separate models join, about a hundred edges
            // carrying a third of the zone's connectivity.
            var edgeOwners = new Dictionary<long, List<int>>(tris.Count * 2);
            long collapsedEdges = 0;
            for (int i = 0; i < tris.Count; i++)
            {
                var t = tris[i];
                AddOwner(edgeOwners, canon[t.A], canon[t.B], i, ref collapsedEdges);
                AddOwner(edgeOwners, canon[t.B], canon[t.C], i, ref collapsedEdges);
                AddOwner(edgeOwners, canon[t.C], canon[t.A], i, ref collapsedEdges);
            }

            // The accept gap is fixed at 0.25 by review. Widening it to a body
            // radius bought 0.11 of a percentage point on the strict stride gate
            // and cost four times the ambiguity, and -- the deciding argument --
            // a body radius does not prove that unsupported space is continuous
            // ground. A seam removes a boundary from erosion outright, so the
            // rule has to be about evidence of support, not about what the body
            // happens to fit through.
            const double AcceptGap = 0.25;

            // Classify the boundary BEFORE adjacency is built, because it is the
            // better description of what joins what and the graph should be built
            // from it rather than compared against it afterwards.
            //
            // This used to run near the end, purely as a report, and that was the
            // defect: it measured a graph we did not ship. Welded-EDGE-KEY
            // adjacency requires two faces to name the identical edge, so a
            // T-junction -- three edges for one physical join -- severed ground
            // this classifier calls continuous, and left 36,965 components where
            // the same geometry read per-interval gives 10,335.
            var boundary = ClassifyBoundaries(tris, steep, canon, vx, vy, vz, edgeOwners,
                                              AcceptGap, opt, false);

            var neighbours = new List<int>[tris.Count];
            for (int i = 0; i < tris.Count; i++) neighbours[i] = new List<int>(3);
            long portalsFan = 0, portalsSameSide = 0, portalsOk = 0;
            long portalsWallEdge = 0, portalsNoOverlap = 0, portalsVertical = 0;
            var portalList = new List<Portal>(300_000);
            var portalOf = new Dictionary<long, List<int>>(300_000);
            foreach (var kv in edgeOwners)
            {
                var owners = kv.Value;
                if (opt.PermissivePortals && owners.Count > 2)
                {
                    for (int oi = 1; oi < owners.Count; oi++)
                    { neighbours[owners[0]].Add(owners[oi]); neighbours[owners[oi]].Add(owners[0]); portalsOk++; }
                    continue;
                }
                if (owners.Count < 2) continue;
                int p = (int)(kv.Key >> 32), q = (int)(kv.Key & 0xFFFFFFFF);

                // A physical collision surface can genuinely BRANCH, so do not try
                // to choose one pair of faces per edge -- test every pair and keep
                // every one that proves itself. Picking the single most-continuous
                // pair by dihedral angle sounds principled and is not: it rebuilds
                // the severed graph exactly, 50.4% / 58.7%, because 19 of the 20
                // four-owner seams here have TIED best pairings. There is no unique
                // answer to find, so inventing a tie-break just discards a real
                // branch at random.
                if (owners.Count > 2) portalsFan++;

                // Gate: the shared line is itself a wall. Then these faces are
                // opposite sides of it, not two ends of a doorway.
                if (wallEdges.Contains(kv.Key))
                {
                    if (InDiag(opt, (vx[p] + vx[q]) * 0.5, (-vz[p] - vz[q]) * 0.5))
                        Console.WriteLine($"diag: REJECT wall-edge ({vx[p]:F2},{-vz[p]:F2})-({vx[q]:F2},{-vz[q]:F2}) owners={owners.Count}");
                    portalsWallEdge++; continue;
                }

                double ex = vx[q] - vx[p], ez = -vz[q] - (-vz[p]);
                double elen = Math.Sqrt(ex * ex + ez * ez);
                if (elen < 1e-9) continue;

                for (int oa = 0; oa < owners.Count; oa++)
                for (int ob = oa + 1; ob < owners.Count; ob++)
                {
                    int a = owners[oa], b = owners[ob];

                    // Gate: the two faces open on OPPOSITE sides of the shared
                    // line, in XZ because that is the plane the body moves in.
                    // Normalize by edge length first -- the raw cross product
                    // scales with it, so a bare != 0 means different things on a
                    // 3-yalm edge and a 3-centimetre one. This is perpendicular
                    // distance in yalms.
                    int ra = Opposite(tris[a], canon, p, q), rb = Opposite(tris[b], canon, p, q);
                    if (ra < 0 || rb < 0) { portalsSameSide++; continue; }
                    const double SideEps = 0.005;
                    double na = (ex * (-vz[ra] - (-vz[p])) - ez * (vx[ra] - vx[p])) / elen;
                    double nb = (ex * (-vz[rb] - (-vz[p])) - ez * (vx[rb] - vx[p])) / elen;
                    if (Math.Abs(na) < SideEps || Math.Abs(nb) < SideEps
                        || (na > 0) == (nb > 0)) { portalsSameSide++; continue; }

                    // Gate: the two faces' own edges must genuinely OVERLAP, not
                    // merely hash to the same canonical key. Welding is allowed to
                    // repair a seam; it is not allowed to invent a shared doorway
                    // between segments that only landed in the same bucket.
                    if (!RawEdge(tris[a], canon, p, q, out int a0, out int a1) ||
                        !RawEdge(tris[b], canon, p, q, out int b0, out int b1))
                    { portalsNoOverlap++; continue; }

                    double sa0 = ((vx[a0] - vx[p]) * ex + (-vz[a0] - (-vz[p])) * ez) / (elen * elen);
                    double sa1 = ((vx[a1] - vx[p]) * ex + (-vz[a1] - (-vz[p])) * ez) / (elen * elen);
                    double sb0 = ((vx[b0] - vx[p]) * ex + (-vz[b0] - (-vz[p])) * ez) / (elen * elen);
                    double sb1 = ((vx[b1] - vx[p]) * ex + (-vz[b1] - (-vz[p])) * ez) / (elen * elen);
                    // Keep the ORIENTED positions: which raw end sits where along the
                    // canonical edge is how each surface height is looked up later.
                    // Sorting is only for computing the overlap span.
                    double oa0 = sa0, oa1 = sa1, ob0 = sb0, ob1 = sb1;
                    if (sa0 > sa1) (sa0, sa1) = (sa1, sa0);
                    if (sb0 > sb1) (sb0, sb1) = (sb1, sb0);
                    double lo = Math.Max(sa0, sb0), hi = Math.Min(sa1, sb1);
                    // Numerically positive overlap, nothing more. The question
                    // this gate answers is "do these two faces physically touch",
                    // which is topology; whether a BODY fits through the result is
                    // capacity, and belongs to the eroded safe interval.
                    //
                    // A 0.05 minimum was wrong in meaning, not just in value: all
                    // 17 pairs it rejected carried the identical raw edge on both
                    // faces. They were real portals 0.022 to 0.045 yalms long, and
                    // refusing them stranded two components on the grounds that a
                    // genuine doorway was small.
                    if ((hi - lo) * elen <= 1e-6) { portalsNoOverlap++; continue; }

                    // Gate: across that overlap the two surfaces must agree in
                    // HEIGHT to within the step policy. Two faces can share a line
                    // in plan view and be a storey apart.
                    double ya0 = -vy[a0], ya1 = -vy[a1], yb0 = -vy[b0], yb1 = -vy[b1];
                    double dLo = Math.Abs(Lerp(ya0, ya1, sa0, sa1, lo) - Lerp(yb0, yb1, sb0, sb1, lo));
                    double dHi = Math.Abs(Lerp(ya0, ya1, sa0, sa1, hi) - Lerp(yb0, yb1, sb0, sb1, hi));
                    double step = Math.Max(opt.MaxStepUp, opt.MaxStepDown);
                    if (dLo > step || dHi > step)
                    {
                        if (InDiag(opt, tris[a].Cx, tris[a].Cz) || InDiag(opt, tris[b].Cx, tris[b].Cz))
                            Console.WriteLine($"diag: REJECT vertical {a}<->{b} dLo={dLo:F2} dHi={dHi:F2} c=({tris[a].Cx:F2},{tris[a].Cz:F2})/({tris[b].Cx:F2},{tris[b].Cz:F2})");
                        portalsVertical++; continue;
                    }

                    neighbours[a].Add(b);
                    neighbours[b].Add(a);
                    portalsOk++;
                    if (InDiag(opt, tris[a].Cx, tris[a].Cz) || InDiag(opt, tris[b].Cx, tris[b].Cz))
                        Console.WriteLine($"diag: ACCEPT candidate {a}<->{b} edge=({vx[p]:F2},{-vz[p]:F2})-({vx[q]:F2},{-vz[q]:F2}) c=({tris[a].Cx:F2},{tris[a].Cz:F2},{tris[a].Cy:F2})/({tris[b].Cx:F2},{tris[b].Cz:F2},{tris[b].Cy:F2})");

                    // Keep the doorway itself, not just the fact of adjacency.
                    // FFXINAV only ever hands back XYZ waypoints, so portal
                    // identity cannot be recovered later -- if it is not recorded
                    // here it is gone.
                    int lo2 = Math.Min(a, b), hi2 = Math.Max(a, b);
                    bool flip = lo2 != a;
                    portalList.Add(new Portal
                    {
                        A = lo2, B = hi2, P = p, Q = q,
                        A0 = flip ? b0 : a0, A1 = flip ? b1 : a1,
                        B0 = flip ? a0 : b0, B1 = flip ? a1 : b1,
                        OverlapLo = lo, OverlapHi = hi,
                        SA0 = flip ? ob0 : oa0, SA1 = flip ? ob1 : oa1,
                        SB0 = flip ? oa0 : ob0, SB1 = flip ? oa1 : ob1,
                    });
                    long pkey = ((long)lo2 << 32) | (uint)hi2;
                    if (!portalOf.TryGetValue(pkey, out var plist))
                        portalOf[pkey] = plist = new List<int>(1);
                    plist.Add(portalList.Count - 1);
                }
            }
            Console.WriteLine($"graph: portal_candidates={edgeOwners.Count} accepted={portalsOk} " +
                              $"fan_edges={portalsFan} rejected_same_side={portalsSameSide} " +
                              $"rejected_wall_edge={portalsWallEdge} rejected_no_overlap={portalsNoOverlap} " +
                              $"rejected_vertical={portalsVertical} collapsed_edges={collapsedEdges}");

            // Now add the joins the edge-key rule could not see. For each pair the
            // interval classifier found sharing ground, if the pair has no portal
            // yet, build one from the seam itself: the surviving interval IS the
            // doorway, in world coordinates, with each surface's own height at
            // both ends. These are the T-junctions -- one physical join that the
            // two faces describe with different edges.
            //
            // The width recorded here is GEOMETRIC. It says the ground is
            // continuous across that stretch, not that a body fits; erosion and
            // the transition gate decide that, and both run after this.
            // Widest classified seam per pair, kept for the whole build. Two uses:
            // creating a doorway where the edge-key pass found none, and -- after
            // certification -- repairing a pair whose welded doorway certified to
            // nothing, so its edges still name a real gap instead of being left
            // for the funnel to guess at from centroids.
            var seamBest = new Dictionary<long, SeamLink>(300_000);
            {
                long added = 0, already = 0, degenerate = 0;
                var seamOf = new Dictionary<long, int>(200_000);
                foreach (var lk in boundary.Links)
                {
                    int a = lk.A, b = lk.B;
                    if (a == b || a < 0 || b < 0 || a >= tris.Count || b >= tris.Count) continue;
                    long pkey = ((long)Math.Min(a, b) << 32) | (uint)Math.Max(a, b);
                    if (!seamBest.TryGetValue(pkey, out var prevBest) || lk.Width > prevBest.Width)
                        seamBest[pkey] = lk;
                    if (portalOf.ContainsKey(pkey)) { already++; continue; }

                    // Keep only the widest seam for a pair. Several intervals on
                    // one boundary are the same doorway seen in pieces, and
                    // emitting each as its own portal would let the funnel pick a
                    // sliver when a wide way through was available.
                    if (seamOf.TryGetValue(pkey, out int prior))
                    {
                        if (portalList[prior].CapacityCm >= (int)Math.Round(lk.Width * 100)) continue;
                        portalList[prior] = MakeSeamPortal(a, b, lk);
                        continue;
                    }
                    var made = MakeSeamPortal(a, b, lk);
                    if (made.CapacityCm <= 0) { degenerate++; continue; }

                    portalList.Add(made);
                    seamOf[pkey] = portalList.Count - 1;
                    portalOf[pkey] = new List<int>(1) { portalList.Count - 1 };
                    neighbours[a].Add(b);
                    neighbours[b].Add(a);
                    added++;
                }
                Console.WriteLine($"graph: seam_joins_added={added} already_had_a_portal={already} " +
                                  $"degenerate={degenerate} (from {boundary.Links.Count} classified seams)");
            }
            {
                // How non-manifold is this mesh, really? A blanket "exactly two
                // owners" rule discards every one of these, so it matters whether
                // they are a handful of oddities or a structural feature of the
                // source data.
                var fanHist = new SortedDictionary<int, int>();
                int loneOwner = 0;
                foreach (var kv in edgeOwners)
                {
                    int n = kv.Value.Count;
                    if (n == 1) { loneOwner++; continue; }
                    if (n <= 2) continue;
                    fanHist.TryGetValue(n, out int c);
                    fanHist[n] = c + 1;
                }
                var parts = new List<string>();
                foreach (var kv in fanHist) if (kv.Key <= 8) parts.Add($"{kv.Key}:{kv.Value}");
                int big = 0, maxOwners = 0;
                foreach (var kv in fanHist) { if (kv.Key > 8) big += kv.Value; maxOwners = Math.Max(maxOwners, kv.Key); }
                Console.WriteLine($"graph: owners_per_edge {string.Join(" ", parts)} >8:{big} max:{maxOwners} " +
                                  $"| mesh_boundary_edges(1 owner)={loneOwner}");

                // Is a single-owner edge really the rim of the world, or is it a
                // T-JUNCTION -- an edge whose middle another triangle's corner
                // lands on? Abutting models meet that way constantly: one long
                // edge against two short ones that share no endpoint with it, so
                // the two surfaces touch physically and share no edge KEY at all.
                // That is invisible to every rule above and would look like a
                // missing link no matter how carefully portals are validated.
                var vgrid = new Dictionary<(int, int), List<int>>(200_000);
                const double TCell = 1.0;
                var seenVert = new HashSet<int>();
                for (int i = 0; i < tris.Count; i++)
                {
                    var t = tris[i];
                    foreach (int raw in new[] { t.A, t.B, t.C })
                    {
                        int cv = canon[raw];
                        if (!seenVert.Add(cv)) continue;
                        var key = ((int)Math.Floor(vx[cv] / TCell), (int)Math.Floor(-vz[cv] / TCell));
                        if (!vgrid.TryGetValue(key, out var lst)) vgrid[key] = lst = new List<int>(4);
                        lst.Add(cv);
                    }
                }
                long tJunctions = 0;
                const double OnEdge = 0.05;      // yalms off the line to still count as on it
                foreach (var kv in edgeOwners)
                {
                    if (kv.Value.Count != 1) continue;
                    int p = (int)(kv.Key >> 32), q = (int)(kv.Key & 0xFFFFFFFF);
                    double px = vx[p], pz = -vz[p], qx = vx[q], qz = -vz[q];
                    double ex = qx - px, ez = qz - pz;
                    double elen2 = ex * ex + ez * ez;
                    if (elen2 < 1e-9) continue;
                    double elen = Math.Sqrt(elen2);
                    bool found = false;
                    int gx0 = (int)Math.Floor(Math.Min(px, qx) / TCell), gx1 = (int)Math.Floor(Math.Max(px, qx) / TCell);
                    int gz0 = (int)Math.Floor(Math.Min(pz, qz) / TCell), gz1 = (int)Math.Floor(Math.Max(pz, qz) / TCell);
                    for (int gx = gx0 - 1; gx <= gx1 + 1 && !found; gx++)
                    for (int gz = gz0 - 1; gz <= gz1 + 1 && !found; gz++)
                    {
                        if (!vgrid.TryGetValue((gx, gz), out var lst)) continue;
                        foreach (int m in lst)
                        {
                            if (m == p || m == q) continue;
                            double mx = vx[m] - px, mz = -vz[m] - pz;
                            double s = (mx * ex + mz * ez) / elen2;
                            if (s <= 0.02 || s >= 0.98) continue;          // strictly inside
                            double perp = Math.Abs(ex * mz - ez * mx) / elen;
                            if (perp > OnEdge) continue;
                            found = true; break;
                        }
                    }
                    if (found) tJunctions++;
                }
                Console.WriteLine($"graph: single_owner_edges_with_a_vertex_on_them(T-junctions)={tJunctions} " +
                                  $"of {loneOwner} ({100.0 * tJunctions / Math.Max(1, loneOwner):F1}%)");
            }

            // Directed edges: keep i->j only if the step up is small enough.
            var outEdges = new List<int>[tris.Count];
            long kept = 0, rejectedClimb = 0, rejectedDrop = 0, duplicates = 0;
            for (int i = 0; i < tris.Count; i++)
            {
                outEdges[i] = new List<int>(3);
                foreach (int j in neighbours[i])
                {
                    // These two triangles SHARE AN EDGE -- they are geometrically
                    // continuous, so the step between them is zero by definition.
                    // The thing to bound is the GRADE, not a step height.
                    //
                    // Testing centroid height difference against a 0.5 step limit
                    // was wrong and wrecked the graph: centroids sit ~3 yalms
                    // apart, so ordinary 33-degree hillside separates them by up
                    // to 1.95 yalms and every slope in the zone got rejected.
                    // That produced 25380 disconnected islands, the largest
                    // holding 14.8% of nodes. Step limits belong to STACKED
                    // surfaces that overlap in XZ, which shared-edge neighbours
                    // never are.
                    double dx = tris[j].Cx - tris[i].Cx, dz = tris[j].Cz - tris[i].Cz;
                    double run = Math.Sqrt(dx * dx + dz * dz);
                    double climb = tris[i].Cy - tris[j].Cy;   // y down: + is climbing
                    double grade = run > 0.05 ? climb / run : (climb > 0 ? 999 : -999);
                    bool dg = InDiag(opt, tris[i].Cx, tris[i].Cz) || InDiag(opt, tris[j].Cx, tris[j].Cz);
                    // A KERB IS A STEP, NOT A SLOPE.
                    //
                    // MaxStepUp is documented at the top of this file as "a kerb
                    // at a shared edge, not a ledge" -- and until now nothing at
                    // a shared edge ever consulted it. The grade test alone
                    // decided every crossing, so a short rise over a short run
                    // was judged as though it were a hillside.
                    //
                    // That is precisely the shape of a staircase. Live
                    // 2026-08-28, the ramp onto the La Theine Shattered
                    // Telepoint: run 0.333, rise 0.250, grade 0.750 = 36.9
                    // degrees against a 33 degree limit. Every step of it
                    // failed, in the climbing direction only -- the descent
                    // passed the down-grade test -- so all three La Theine
                    // telepoint platforms became ONE-WAY islands you can walk
                    // off and never onto. 594 nodes in this zone sit within one
                    // legal step-up of reachable ground with no edge to cross on.
                    //
                    // The player walked those stairs and recorded the point at
                    // the top of them. The mesh had the treads; it had no way in.
                    //
                    // So: a climb within MaxStepUp is a STEP and the grade limit
                    // does not apply to it. The hillside fix the comment above
                    // describes is untouched -- a long run with a big climb still
                    // fails on grade, because its rise exceeds a step. Applied to
                    // the drop as well, or allowing a climb the descent still
                    // refuses would manufacture a fresh one-way island.
                    if (grade > opt.MaxUpGrade && climb > opt.MaxStepUp) { if (dg) Console.WriteLine($"diag: EDGE reject climb {i}->{j} grade={grade:F3} climb={climb:F3}"); rejectedClimb++; continue; }
                    if (-grade > opt.MaxDownGrade && -climb > opt.MaxStepDown) { if (dg) Console.WriteLine($"diag: EDGE reject drop {i}->{j} grade={grade:F3} climb={climb:F3}"); rejectedDrop++; continue; }
                    // A non-manifold seam can list the same neighbour twice. Two
                    // records for one crossing is not two ways through.
                    if (outEdges[i].Contains(j)) { duplicates++; continue; }
                    outEdges[i].Add(j);
                    kept++;
                    if (dg) Console.WriteLine($"diag: EDGE keep {i}->{j} grade={grade:F3}");
                }
            }
            Console.WriteLine($"graph: directed_edges={kept} rejected_climb={rejectedClimb} " +
                              $"rejected_drop={rejectedDrop} duplicates={duplicates}");

            // Per-crossing clearance: the width of the DOORWAY, not the distance
            // from a wall to the centroid.
            //
            // Requiring the centroid to stand clear of walls is a stricter test
            // than asking whether a body can get through, and it fails in a way
            // that looks like terrain. A triangle hinged on a wall has its
            // centroid at a third of its depth, so ordinary open ground beside a
            // cliff scored ~0.67 and was cut at a 0.70 threshold. Measured
            // against the player's own recording, that severed 24% of the ground
            // they had actually walked, across 122 crossings that the recording
            // shows were made ON FOOT, on grades between 0.07 and 0.52.
            //
            // What a body actually has to fit through is the shared edge between
            // two triangles. Its usable width is reduced by whichever of its ends
            // is pinned to a wall, because the centre of a capsule cannot come
            // closer than its radius to one:
            //   neither end walled -> unobstructed
            //   one end walled     -> the far end is a full edge-length clear
            //   both ends walled   -> the widest point is the middle
            // Capacity is a property of the PORTAL, so compute it once per shared
            // edge and hand the same answer to both directions. Deriving it
            // per-direction let one physical doorway serialize as 61cm one way
            // and 300cm the other.
            var portalGate = new Dictionary<long, float>((int)Math.Min(kept, int.MaxValue));
            var gate = new float[tris.Count][];
            // Which certified doorway each directed edge crosses. Parallel entries
            // for the same neighbour are different components of one split opening.
            var outPortal = new List<int>[tris.Count];
            var sharedA = new int[3];
            var sharedB = new int[3];
            long rejectedWallPortal = 0, rejectedDegenerate = 0, rejectedUnidentified = 0;
            for (int i = 0; i < tris.Count; i++)
            {
                gate[i] = new float[outEdges[i].Count];
                var ti = tris[i];
                sharedA[0] = canon[ti.A]; sharedA[1] = canon[ti.B]; sharedA[2] = canon[ti.C];
                for (int k = 0; k < outEdges[i].Count; k++)
                {
                    int jj = outEdges[i][k];

                    // A seam doorway already knows its own width, measured on the
                    // stretch of ground the two surfaces genuinely share. Deriving
                    // it from welded vertices instead is impossible for these
                    // pairs by construction -- they do not share two, which is why
                    // the edge-key pass never saw the join at all.
                    {
                        long skey = ((long)Math.Min(i, jj) << 32) | (uint)Math.Max(i, jj);
                        if (portalOf.TryGetValue(skey, out var spids))
                        {
                            int best = -1;
                            foreach (int pid in spids)
                                if (portalList[pid].P < 0 &&
                                    (best < 0 || portalList[pid].CapacityCm > portalList[best].CapacityCm))
                                    best = pid;
                            if (best >= 0) { gate[i][k] = portalList[best].CapacityCm / 100f; continue; }
                        }
                    }

                    var tj = tris[jj];
                    sharedB[0] = canon[tj.A]; sharedB[1] = canon[tj.B]; sharedB[2] = canon[tj.C];

                    int p = -1, q = -1, shared = 0;
                    for (int a = 0; a < 3; a++)
                    for (int b = 0; b < 3; b++)
                        if (sharedA[a] == sharedB[b])
                        {
                            if (p < 0) { p = sharedA[a]; shared = 1; }
                            else if (sharedA[a] != p && q < 0) { q = sharedA[a]; shared = 2; }
                            else if (sharedA[a] != p && sharedA[a] != q) shared = 3;
                        }

                    // Two standable triangles sharing all three welded vertices
                    // are the same surface twice over, not a doorway between two
                    // places. Meeting at a single vertex is not a doorway either.
                    if (shared == 3) { gate[i][k] = 0f; rejectedDegenerate++; continue; }
                    if (p < 0 || q < 0) { gate[i][k] = 0f; rejectedUnidentified++; continue; }

                    long key = EdgeKey(p, q);
                    if (portalGate.TryGetValue(key, out float cached)) { gate[i][k] = cached; continue; }

                    float w;
                    if (wallEdges.Contains(key))
                    {
                        // THE PORTAL IS ITSELF A WALL. A steep face stands on the
                        // very line these two triangles share, so crossing here
                        // means walking through it -- they are opposite sides of
                        // the same wall, not two ends of a doorway.
                        //
                        // The endpoint formula got this catastrophically wrong: it
                        // saw both ends walled, returned len/2, and declared a
                        // 4-yalm wall to be 2 yalms of clear passage. 1610 edges
                        // in the previous build, 716 of them passing the 70cm
                        // filter, and the router really did route through one.
                        // Reducing a wall to two point obstacles and calling the
                        // middle safe is the same mistake as treating a corridor
                        // as a path.
                        w = 0f;
                        rejectedWallPortal++;
                    }
                    else
                    {
                        double gx = vx[p] - vx[q], gz = -vz[p] - (-vz[q]);
                        double len = Math.Sqrt(gx * gx + gz * gz);
                        int walled = (wallVerts.Contains(p) ? 1 : 0) + (wallVerts.Contains(q) ? 1 : 0);
                        double raw = walled == 0 ? ClearanceCap : (walled == 1 ? len : len * 0.5);
                        w = (float)Math.Min(raw, ClearanceCap);
                    }
                    portalGate[key] = w;
                    gate[i][k] = w;
                }
            }
            Console.WriteLine($"graph: portals={portalGate.Count} rejected_wall_portal={rejectedWallPortal} " +
                              $"rejected_degenerate={rejectedDegenerate} rejected_unidentified={rejectedUnidentified}");

            // Certify each doorway: which part of it can a body actually occupy.
            //
            // Test against the SOURCE STEEP TRIANGLES, never against their base
            // edges. Reducing a wall to the line where it meets the floor is
            // exactly what let a 4-yalm wall lying along a doorway serialize as
            // two yalms of clear passage, and it is blind to overhangs, leaning
            // faces and walls running parallel to the opening.
            {
                const double Eps = 1e-4;
                double R = opt.AgentRadius;
                double epsY = Math.Max(1e-4, opt.WeldTolerance);
                var scell = new Dictionary<(int, int), List<int>>(200_000);
                const double SCell = 4.0;
                var sBounds = new (float x0, float z0, float x1, float z1, float yLo, float yHi)[steep.Count];
                for (int i = 0; i < steep.Count; i++)
                {
                    var (sa, sb, sc) = steep[i];
                    float x0 = Math.Min(vx[sa], Math.Min(vx[sb], vx[sc]));
                    float x1 = Math.Max(vx[sa], Math.Max(vx[sb], vx[sc]));
                    float z0 = Math.Min(-vz[sa], Math.Min(-vz[sb], -vz[sc]));
                    float z1 = Math.Max(-vz[sa], Math.Max(-vz[sb], -vz[sc]));
                    float yLo = Math.Min(-vy[sa], Math.Min(-vy[sb], -vy[sc]));
                    float yHi = Math.Max(-vy[sa], Math.Max(-vy[sb], -vy[sc]));
                    sBounds[i] = (x0, z0, x1, z1, yLo, yHi);
                    for (int gx = (int)Math.Floor(x0 / SCell); gx <= (int)Math.Floor(x1 / SCell); gx++)
                    for (int gz = (int)Math.Floor(z0 / SCell); gz <= (int)Math.Floor(z1 / SCell); gz++)
                    {
                        if (!scell.TryGetValue((gx, gz), out var lst)) scell[(gx, gz)] = lst = new List<int>(4);
                        lst.Add(i);
                    }
                }

                long certified = 0, emptied = 0, extraComponents = 0;
                var blocked = new List<(double lo, double hi)>(16);
                var spawned = new List<(Portal src, (double lo, double hi) comp,
                                        double spanLo, double spanHi, double spanLen)>(4096);
                foreach (var pt in portalList)
                {
                    // Seam doorways carry no canonical edge -- the two faces do
                    // not share one, which is the whole reason the edge-key pass
                    // missed them. Their interval came out of the classifier
                    // already wall-subtracted and already in world coordinates,
                    // so there is nothing here to re-derive. Erosion narrows them
                    // later, exactly as it narrows these.
                    if (pt.P < 0 || pt.Q < 0) { certified++; continue; }

                    double x0 = vx[pt.P], z0 = -vz[pt.P];
                    double x1 = vx[pt.Q], z1 = -vz[pt.Q];
                    double edgeLen = Math.Sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0));
                    if (edgeLen < 1e-6) { pt.CapacityCm = 0; continue; }

                    // Body envelope over the whole doorway. y points DOWN, so the
                    // top of the body is the SMALLER number. Using the envelope of
                    // the entire segment rather than a per-position one considers
                    // slightly more geometry, which errs toward refusing passage.
                    double floorLo = Math.Min(Math.Min(-vy[pt.A0], -vy[pt.A1]),
                                              Math.Min(-vy[pt.B0], -vy[pt.B1]));
                    double floorHi = Math.Max(Math.Max(-vy[pt.A0], -vy[pt.A1]),
                                              Math.Max(-vy[pt.B0], -vy[pt.B1]));
                    double bodyTop = floorLo - AgentHeight;
                    double bodyBottom = floorHi;

                    blocked.Clear();
                    // Only the span both faces really share is a doorway. The
                    // canonical edge is a label, not the geometry.
                    double spanLo = Math.Max(0.0, pt.OverlapLo), spanHi = Math.Min(1.0, pt.OverlapHi);
                    if (spanHi - spanLo <= 0) { pt.CapacityCm = 0; emptied++; continue; }
                    double spanLen = (spanHi - spanLo) * edgeLen;
                    double ox0 = x0 + (x1 - x0) * spanLo, oz0 = z0 + (z1 - z0) * spanLo;
                    double ox1 = x0 + (x1 - x0) * spanHi, oz1 = z0 + (z1 - z0) * spanHi;
                    double bx0 = Math.Min(ox0, ox1) - R - Eps, bx1 = Math.Max(ox0, ox1) + R + Eps;
                    double bz0 = Math.Min(oz0, oz1) - R - Eps, bz1 = Math.Max(oz0, oz1) + R + Eps;
                    bool dgp = InDiag(opt, (ox0 + ox1) * 0.5, (oz0 + oz1) * 0.5);
                    if (dgp) Console.WriteLine($"diag: CERT portal {pt.A}<->{pt.B} span=({ox0:F2},{oz0:F2})-({ox1:F2},{oz1:F2}) len={spanLen:F2} floorHi={floorHi:F2}");
                    var seen = new HashSet<int>();
                    for (int gx = (int)Math.Floor(bx0 / SCell); gx <= (int)Math.Floor(bx1 / SCell); gx++)
                    for (int gz = (int)Math.Floor(bz0 / SCell); gz <= (int)Math.Floor(bz1 / SCell); gz++)
                    {
                        if (!scell.TryGetValue((gx, gz), out var lst)) continue;
                        foreach (int si in lst)
                        {
                            if (!seen.Add(si)) continue;
                            var sb2 = sBounds[si];
                            // Geometry entirely above the head or below the feet
                            // does not narrow the doorway.
                            if (sb2.yHi < bodyTop - epsY || sb2.yLo > bodyBottom + epsY) continue;
                            // Nor does geometry the body simply STEPS OVER. The
                            // wall marking already draws this line -- a steep
                            // face is a wall only where it rises more than a step
                            // above the ground it meets -- but this erosion did
                            // not, and blocked on any steep face in the vertical
                            // band including ones standing a centimetre proud.
                            // That is what emptied 28,869 doorways and cut off
                            // 5.4% of ground the player is recorded walking.
                            // y is DOWN, so "above" is a SMALLER number.
                            if (sb2.yLo > floorHi - opt.MaxStepUp) continue;
                            if (sb2.x1 < bx0 || sb2.x0 > bx1 || sb2.z1 < bz0 || sb2.z0 > bz1) continue;
                            var (sa, sbv, sc) = steep[si];
                            if (BlockedSpan(ox0, oz0, ox1, oz1,
                                            vx[sa], -vz[sa], vx[sbv], -vz[sbv], vx[sc], -vz[sc],
                                            R, out double blo, out double bhi))
                            {
                                if (dgp) Console.WriteLine($"diag: CERT blocker steep#{si} y[{sb2.yLo:F2},{sb2.yHi:F2}] tri=({vx[sa]:F2},{-vz[sa]:F2})({vx[sbv]:F2},{-vz[sbv]:F2})({vx[sc]:F2},{-vz[sc]:F2}) blocks[{blo:F2},{bhi:F2}]");
                                blocked.Add((blo, bhi));
                            }
                        }
                    }

                    // Subtract the blocked spans and keep the widest survivor.
                    blocked.Sort((u, v2) => u.lo.CompareTo(v2.lo));
                    double cursor = 0.0;
                    // EVERY surviving component is a real way through. Keeping only
                    // the widest is safe but incomplete, and can discard the one
                    // component that lines up with the neighbouring doorways -- an
                    // obstacle standing in a gateway leaves a way past on each side
                    // and the route may need either.
                    var comps2 = new List<(double lo, double hi)>(4);
                    void Consider(double lo3, double hi3)
                    {
                        if ((hi3 - lo3) * spanLen < 0.05) return;   // slivers are not doorways
                        comps2.Add((lo3, hi3));
                    }
                    foreach (var (blo, bhi) in blocked)
                    {
                        if (blo > cursor) Consider(cursor, blo);
                        cursor = Math.Max(cursor, bhi);
                        if (cursor >= 1.0) break;
                    }
                    if (cursor < 1.0) Consider(cursor, 1.0);

                    if (comps2.Count == 0) { if (dgp) Console.WriteLine($"diag: CERT EMPTIED {pt.A}<->{pt.B}"); pt.CapacityCm = 0; emptied++; continue; }
                    // Widest first, ties to the lower parameter, so the ordering
                    // never depends on enumeration order.
                    comps2.Sort((u, v2) =>
                    {
                        int c = (v2.hi - v2.lo).CompareTo(u.hi - u.lo);
                        return c != 0 ? c : u.lo.CompareTo(v2.lo);
                    });
                    if (comps2.Count > 1) { pt.Extra = comps2.Count - 1; extraComponents++; }
                    for (int ci = 1; ci < comps2.Count; ci++) spawned.Add((pt, comps2[ci], spanLo, spanHi, spanLen));
                    double bestLo = comps2[0].lo, bestHi = comps2[0].hi;
                    double bestLen = (bestHi - bestLo) * spanLen;

                    // bestLo/bestHi parameterise the SHARED SPAN; convert back to
                    // the canonical edge before evaluating anything against it.
                    double cLo = spanLo + (spanHi - spanLo) * bestLo;
                    double cHi = spanLo + (spanHi - spanLo) * bestHi;
                    pt.LeftX  = (float)(x0 + (x1 - x0) * cLo);
                    pt.LeftZ  = (float)(z0 + (z1 - z0) * cLo);
                    pt.RightX = (float)(x0 + (x1 - x0) * cHi);
                    pt.RightZ = (float)(z0 + (z1 - z0) * cHi);
                    // Each owner's height read at ITS OWN oriented positions along
                    // the canonical edge. A blind 0..1 assumes both faces start and
                    // end where the canonical edge does, which is exactly what the
                    // overlap span exists to say is not true.
                    pt.LeftYA  = (float)Lerp(-vy[pt.A0], -vy[pt.A1], pt.SA0, pt.SA1, cLo);
                    pt.LeftYB  = (float)Lerp(-vy[pt.B0], -vy[pt.B1], pt.SB0, pt.SB1, cLo);
                    pt.RightYA = (float)Lerp(-vy[pt.A0], -vy[pt.A1], pt.SA0, pt.SA1, cHi);
                    pt.RightYB = (float)Lerp(-vy[pt.B0], -vy[pt.B1], pt.SB0, pt.SB1, cHi);
                    // Measure the span between the SERIALIZED endpoints, not the
                    // doubles they came from. The file only carries the floats, so
                    // a width computed before that rounding is a claim about
                    // numbers the reader will never see -- 5010 portals overclaimed
                    // their own serialized width by a centimetre that way.
                    // Floor, never round: shrink the claim inward, never outward.
                    pt.CapacityCm = SpanCm(pt);
                    // HEADROOM_CHECKED stays CLEAR. The pass filters obstacles by
                    // their height range but never tests a ceiling, so claiming it
                    // would assert something nothing here has verified. (I told sol
                    // this flag was already clear; it was not. Saying so did not
                    // make it true.)
                    pt.Flags = (int)(PortalFlag.SafeIntervalCertified | PortalFlag.WallEroded);
                    if (dgp) Console.WriteLine($"diag: CERT done {pt.A}<->{pt.B} capacity={pt.CapacityCm}cm comps={comps2.Count}");
                    certified++;
                }
                // Emit the additional components as portals in their own right.
                foreach (var (src, comp, sLo, sHi, sLen) in spawned)
                {
                    double cLo = sLo + (sHi - sLo) * comp.lo;
                    double cHi = sLo + (sHi - sLo) * comp.hi;
                    double ex2 = vx[src.Q] - vx[src.P], ez2 = -vz[src.Q] - (-vz[src.P]);
                    var extra = new Portal
                    {
                        A = src.A, B = src.B, P = src.P, Q = src.Q,
                        A0 = src.A0, A1 = src.A1, B0 = src.B0, B1 = src.B1,
                        OverlapLo = src.OverlapLo, OverlapHi = src.OverlapHi,
                        SA0 = src.SA0, SA1 = src.SA1, SB0 = src.SB0, SB1 = src.SB1,
                        LeftX  = (float)(vx[src.P] + ex2 * cLo),
                        LeftZ  = (float)(-vz[src.P] + ez2 * cLo),
                        RightX = (float)(vx[src.P] + ex2 * cHi),
                        RightZ = (float)(-vz[src.P] + ez2 * cHi),
                        LeftYA  = (float)Lerp(-vy[src.A0], -vy[src.A1], src.SA0, src.SA1, cLo),
                        LeftYB  = (float)Lerp(-vy[src.B0], -vy[src.B1], src.SB0, src.SB1, cLo),
                        RightYA = (float)Lerp(-vy[src.A0], -vy[src.A1], src.SA0, src.SA1, cHi),
                        RightYB = (float)Lerp(-vy[src.B0], -vy[src.B1], src.SB0, src.SB1, cHi),
                        Flags = (int)(PortalFlag.SafeIntervalCertified | PortalFlag.WallEroded),
                    };
                    extra.CapacityCm = SpanCm(extra);
                    if (extra.CapacityCm <= 0) continue;   // rounded away to nothing
                    portalList.Add(extra);
                    long ekey = ((long)src.A << 32) | (uint)src.B;
                    if (!portalOf.TryGetValue(ekey, out var elist)) portalOf[ekey] = elist = new List<int>(1);
                    elist.Add(portalList.Count - 1);
                    certified++;
                }
                Console.WriteLine($"graph: portals_certified={certified} fully_blocked={emptied} " +
                                  $"split_doorways={extraComponents} extra_components_kept={spawned.Count}");

                // Repair the pairs whose only doorway certified to nothing. The
                // crossing itself survives now -- the collision model decides
                // that -- but a zero-capacity portal is dropped when the file is
                // written, and an edge naming no portal leaves the funnel with
                // nothing to pull against but centroids. A centroid chain is the
                // original bug: it walks the middle of every triangle, which is
                // not where the gap is.
                //
                // The classified seam already knows where these two surfaces
                // really meet and how much of that meeting survived the wall
                // subtraction, so use it. It is a narrower claim than a certified
                // doorway and is flagged as such: the interval is real geometry,
                // it has simply not been eroded to the body.
                {
                    long repaired = 0;
                    foreach (var kv in seamBest)
                    {
                        if (portalOf.TryGetValue(kv.Key, out var pids))
                        {
                            bool anyLive = false;
                            foreach (int pid in pids) if (portalList[pid].CapacityCm >= MinSafeSpanCm) { anyLive = true; break; }
                            if (anyLive) continue;
                        }
                        else continue;   // no portal at all is the seam-join case, handled earlier

                        int a = (int)(kv.Key >> 32), b = (int)(kv.Key & 0xFFFFFFFF);
                        var repair = MakeSeamPortal(a, b, kv.Value);
                        bool dgr = InDiag(opt, tris[a].Cx, tris[a].Cz) || InDiag(opt, tris[b].Cx, tris[b].Cz);
                        if (repair.CapacityCm <= 0) { if (dgr) Console.WriteLine($"diag: REPAIR degenerate {a}<->{b}"); continue; }

                        // Erode it to the body, exactly as a welded doorway is
                        // eroded, against the same walls. The format has no way
                        // to say "an interval that has not been certified", and
                        // it is right not to: the funnel pulls the path through
                        // whatever is written here, so an un-eroded interval
                        // would invite the body to pass at the very edge of the
                        // gap. If nothing survives, the pair keeps no doorway
                        // and its edges are withdrawn above.
                        double ox0 = repair.LeftX, oz0 = repair.LeftZ;
                        double ox1 = repair.RightX, oz1 = repair.RightZ;
                        double segLen = Math.Sqrt((ox1 - ox0) * (ox1 - ox0) + (oz1 - oz0) * (oz1 - oz0));
                        if (segLen < 1e-6) continue;

                        double fLo = Math.Min(Math.Min(repair.LeftYA, repair.LeftYB),
                                              Math.Min(repair.RightYA, repair.RightYB));
                        double fHi = Math.Max(Math.Max(repair.LeftYA, repair.LeftYB),
                                              Math.Max(repair.RightYA, repair.RightYB));
                        double bTop = fLo - AgentHeight, bBot = fHi;

                        blocked.Clear();
                        double qx0 = Math.Min(ox0, ox1) - R - Eps, qx1 = Math.Max(ox0, ox1) + R + Eps;
                        double qz0 = Math.Min(oz0, oz1) - R - Eps, qz1 = Math.Max(oz0, oz1) + R + Eps;
                        var seenR = new HashSet<int>();
                        for (int gx = (int)Math.Floor(qx0 / SCell); gx <= (int)Math.Floor(qx1 / SCell); gx++)
                        for (int gz = (int)Math.Floor(qz0 / SCell); gz <= (int)Math.Floor(qz1 / SCell); gz++)
                        {
                            if (!scell.TryGetValue((gx, gz), out var lst)) continue;
                            foreach (int si in lst)
                            {
                                if (!seenR.Add(si)) continue;
                                var sb3 = sBounds[si];
                                if (sb3.yHi < bTop - epsY || sb3.yLo > bBot + epsY) continue;
                                if (sb3.yLo > fHi - opt.MaxStepUp) continue;   // steppable, not a wall
                                if (sb3.x1 < qx0 || sb3.x0 > qx1 || sb3.z1 < qz0 || sb3.z0 > qz1) continue;
                                var (ra, rb, rc) = steep[si];
                                if (BlockedSpan(ox0, oz0, ox1, oz1,
                                                vx[ra], -vz[ra], vx[rb], -vz[rb], vx[rc], -vz[rc],
                                                R, out double blo2, out double bhi2))
                                {
                                    if (dgr) Console.WriteLine($"diag: REPAIR blocker steep#{si} y[{sb3.yLo:F2},{sb3.yHi:F2}] blocks[{blo2:F2},{bhi2:F2}]");
                                    blocked.Add((blo2, bhi2));
                                }
                            }
                        }

                        blocked.Sort((u, v3) => u.lo.CompareTo(v3.lo));
                        double cur = 0.0, bestLo = -1, bestHi = -1;
                        void Take(double lo4, double hi4)
                        {
                            if (hi4 - lo4 > bestHi - bestLo) { bestLo = lo4; bestHi = hi4; }
                        }
                        foreach (var (blo3, bhi3) in blocked)
                        {
                            if (blo3 > cur) Take(cur, Math.Min(blo3, 1.0));
                            cur = Math.Max(cur, bhi3);
                            if (cur >= 1.0) break;
                        }
                        if (cur < 1.0) Take(cur, 1.0);
                        if (bestLo < 0 || (bestHi - bestLo) * segLen * 100.0 < MinSafeSpanCm)
                        { if (dgr) Console.WriteLine($"diag: REPAIR failed {a}<->{b} segLen={segLen:F2} bestSurvivor={(bestLo < 0 ? 0 : (bestHi - bestLo) * segLen):F2}"); continue; }

                        repair.LeftX  = (float)(ox0 + (ox1 - ox0) * bestLo);
                        repair.LeftZ  = (float)(oz0 + (oz1 - oz0) * bestLo);
                        repair.RightX = (float)(ox0 + (ox1 - ox0) * bestHi);
                        repair.RightZ = (float)(oz0 + (oz1 - oz0) * bestHi);
                        // Capture the originals FIRST. Interpolating the right end
                        // from an already-overwritten left end reads the new value
                        // as if it were the old one and skews every height on the
                        // portal toward the eroded end.
                        double oLYA = repair.LeftYA, oRYA = repair.RightYA;
                        double oLYB = repair.LeftYB, oRYB = repair.RightYB;
                        repair.LeftYA  = (float)Lerp2(oLYA, oRYA, bestLo);
                        repair.LeftYB  = (float)Lerp2(oLYB, oRYB, bestLo);
                        repair.RightYA = (float)Lerp2(oLYA, oRYA, bestHi);
                        repair.RightYB = (float)Lerp2(oLYB, oRYB, bestHi);
                        repair.CapacityCm = SpanCm(repair);
                        if (repair.CapacityCm < MinSafeSpanCm) { if (dgr) Console.WriteLine($"diag: REPAIR rounded-away {a}<->{b}"); continue; }
                        repair.Flags = (int)(PortalFlag.SafeIntervalCertified | PortalFlag.WallEroded);

                        portalList.Add(repair);
                        pids.Add(portalList.Count - 1);
                        repaired++;
                        if (dgr) Console.WriteLine($"diag: REPAIR ok {a}<->{b} capacity={repair.CapacityCm}cm");
                    }
                    Console.WriteLine($"graph: doorways_repaired_from_seam={repaired}");
                }

                // RESCUE BY WALKING: an emptied doorway is not yet a refused
                // crossing. Interval subtraction erodes with each steep face's
                // bounding box, and a face at the standing-limit margin -- a
                // 45.4-degree, 0.67-yalm bank the march policy climbs without
                // noticing -- can blanket a doorway it does not physically bar.
                // That is what severed the walked Ordelle entrance ramp: four
                // doorways on continuous 0.5-grade ground emptied by one bank.
                //
                // The body is the arbiter, not the subtraction. Search the local
                // collision surface for a continuous centre path between the two
                // centroids that the full agent radius can sweep: ground support
                // at every stride, the march step policy at every stride, and a
                // radius of daylight from every unambiguous wall. If such a path
                // exists AND crosses this doorway, the doorway earns a portal
                // centred where the body really crossed, one radius each way. If
                // the path crosses somewhere else, this pair stays withdrawn --
                // the route belongs to the doorways the path actually used. If no
                // path exists, the refusal was right, and no tessellation
                // accident may undo it.
                {
                    long rescueTried = 0, rescueOk = 0, rescueNoPath = 0, rescueDetour = 0, rescueTiny = 0;
                    var rescueMesh = new MeshIndex(tris, steep, vx, vy, vz);

                    // Certified for both directions at once, so the tighter of
                    // the two march allowances applies throughout.
                    double allowStep = Math.Min(Math.Max(opt.MaxStepUp, 0.25 * opt.MaxUpGrade),
                                                Math.Max(opt.MaxStepDown, 0.25 * opt.MaxDownGrade));

                    // A wall for BODY CLEARANCE is unambiguous vertical geometry
                    // taller than a step: 60 degrees or steeper AND rising more
                    // than a step top to bottom. Faces between the standing limit
                    // and 60 degrees are terrain at the calibration margin; the
                    // march policy governs whether they can be walked, and
                    // treating them as walls is precisely what emptied these
                    // doorways. The certification gate above keeps its stricter
                    // rule -- this classification exists only here, where a path
                    // is proven by walking rather than assumed by subtraction.
                    const double HardWallCos = 0.5;   // cos(60 deg)
                    var hardWall = new bool[steep.Count];
                    for (int si = 0; si < steep.Count; si++)
                    {
                        var (ha, hb, hc) = steep[si];
                        double hux = vx[hb] - vx[ha], huy = -vy[hb] - (-vy[ha]), huz = -vz[hb] - (-vz[ha]);
                        double hwx = vx[hc] - vx[ha], hwy = -vy[hc] - (-vy[ha]), hwz = -vz[hc] - (-vz[ha]);
                        double hnx = huy * hwz - huz * hwy, hny = huz * hwx - hux * hwz, hnz = hux * hwy - huy * hwx;
                        double hnl = Math.Sqrt(hnx * hnx + hny * hny + hnz * hnz);
                        double vert = hnl > 1e-12 ? Math.Abs(hny) / hnl : 1.0;
                        hardWall[si] = vert < HardWallCos && (sBounds[si].yHi - sBounds[si].yLo) >= opt.MaxStepUp;
                    }

                    // Point-to-triangle distance in plan view. Vertical faces
                    // project to slivers or lines, so the inside test rarely
                    // fires and the edge distances carry the answer.
                    static double PointTriXZ(double px, double pz,
                                             double x1, double z1, double x2, double z2, double x3, double z3)
                    {
                        static double Seg(double px2, double pz2, double sx, double sz, double ex, double ez)
                        {
                            double dx2 = ex - sx, dz2 = ez - sz;
                            double l2 = dx2 * dx2 + dz2 * dz2;
                            double t2 = l2 > 1e-18 ? ((px2 - sx) * dx2 + (pz2 - sz) * dz2) / l2 : 0.0;
                            t2 = Math.Max(0.0, Math.Min(1.0, t2));
                            double cx = sx + dx2 * t2, cz = sz + dz2 * t2;
                            return Math.Sqrt((px2 - cx) * (px2 - cx) + (pz2 - cz) * (pz2 - cz));
                        }
                        double s1 = (x2 - x1) * (pz - z1) - (z2 - z1) * (px - x1);
                        double s2 = (x3 - x2) * (pz - z2) - (z3 - z2) * (px - x2);
                        double s3 = (x1 - x3) * (pz - z3) - (z1 - z3) * (px - x3);
                        if ((s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0)) return 0.0;
                        return Math.Min(Seg(px, pz, x1, z1, x2, z2),
                               Math.Min(Seg(px, pz, x2, z2, x3, z3), Seg(px, pz, x3, z3, x1, z1)));
                    }

                    // Barycentric height of a triangle's plane at a plan-view
                    // point, and whether the point lies inside its plan-view
                    // footprint. Both in the GAME frame.
                    bool InTriXZ(in Tri t3, double px, double pz, out double planeY)
                    {
                        double x1 = vx[t3.A], z1 = -vz[t3.A], y1 = -vy[t3.A];
                        double x2 = vx[t3.B], z2 = -vz[t3.B], y2 = -vy[t3.B];
                        double x3 = vx[t3.C], z3 = -vz[t3.C], y3 = -vy[t3.C];
                        double det = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3);
                        planeY = t3.Cy;
                        if (Math.Abs(det) < 1e-12) return false;
                        double l1 = ((z2 - z3) * (px - x3) + (x3 - x2) * (pz - z3)) / det;
                        double l2 = ((z3 - z1) * (px - x3) + (x1 - x3) * (pz - z3)) / det;
                        double l3 = 1.0 - l1 - l2;
                        const double InEps = -0.02;
                        if (l1 < InEps || l2 < InEps || l3 < InEps) return false;
                        planeY = l1 * y1 + l2 * y2 + l3 * y3;
                        return true;
                    }

                    const double Grid = 0.25;
                    const double Band = 1.0;   // tighter than the validator's 2.5: a rescue must not hop layers

                    bool DiskClear(double px, double pz, double py)
                    {
                        double headY = py - AgentHeight;
                        double stepY = py - opt.MaxStepUp;
                        for (int gx = (int)Math.Floor((px - R) / SCell); gx <= (int)Math.Floor((px + R) / SCell); gx++)
                        for (int gz = (int)Math.Floor((pz - R) / SCell); gz <= (int)Math.Floor((pz + R) / SCell); gz++)
                        {
                            if (!scell.TryGetValue((gx, gz), out var lst)) continue;
                            foreach (int si in lst)
                            {
                                if (!hardWall[si]) continue;
                                var hb2 = sBounds[si];
                                // y is DOWN. The wall matters only where it rises
                                // more than a step above the feet and reaches
                                // below the head.
                                if (hb2.yLo > stepY) continue;
                                if (hb2.yHi < headY) continue;
                                if (hb2.x1 < px - R || hb2.x0 > px + R || hb2.z1 < pz - R || hb2.z0 > pz + R) continue;
                                var (wa, wb, wc) = steep[si];
                                if (PointTriXZ(px, pz, vx[wa], -vz[wa], vx[wb], -vz[wb], vx[wc], -vz[wc]) < R)
                                    return false;
                            }
                        }
                        return true;
                    }

                    foreach (var kvp in portalOf)
                    {
                        var pids2 = kvp.Value;
                        bool live2 = false;
                        foreach (int pid in pids2) if (portalList[pid].CapacityCm >= MinSafeSpanCm) { live2 = true; break; }
                        if (live2) continue;

                        int ta = (int)(kvp.Key >> 32), tb = (int)(kvp.Key & 0xFFFFFFFF);
                        double ax2 = tris[ta].Cx, az2 = tris[ta].Cz, ay2 = tris[ta].Cy;
                        double bx2 = tris[tb].Cx, bz2 = tris[tb].Cz, by2 = tris[tb].Cy;
                        double runx = bx2 - ax2, runz = bz2 - az2;
                        double run2 = Math.Sqrt(runx * runx + runz * runz);
                        if (run2 < 1e-6 || run2 > opt.MaxEdgeRun) continue;
                        rescueTried++;
                        bool dgw = InDiag(opt, ax2, az2) || InDiag(opt, bx2, bz2);

                        // The doorway's RAW geometry: world endpoints of the widest
                        // uneroded interval this pair ever had, with both sides'
                        // heights at each end.
                        int rawPid = -1; double rawLen = -1;
                        foreach (int pid in pids2)
                        {
                            var cnd = portalList[pid];
                            double l3;
                            if (cnd.P >= 0)
                            {
                                double exq = vx[cnd.Q] - vx[cnd.P], ezq = -vz[cnd.Q] - (-vz[cnd.P]);
                                l3 = (Math.Min(1.0, cnd.OverlapHi) - Math.Max(0.0, cnd.OverlapLo))
                                     * Math.Sqrt(exq * exq + ezq * ezq);
                            }
                            else
                            {
                                double dxq = cnd.RightX - cnd.LeftX, dzq = cnd.RightZ - cnd.LeftZ;
                                l3 = Math.Sqrt(dxq * dxq + dzq * dzq);
                            }
                            if (l3 > rawLen) { rawLen = l3; rawPid = pid; }
                        }
                        if (rawPid < 0 || rawLen * 100.0 < MinSafeSpanCm)
                        { rescueTiny++; if (dgw) Console.WriteLine($"diag: RESCUE raw-interval-tiny {ta}<->{tb}"); continue; }
                        var raw = portalList[rawPid];
                        double wx0, wz0, wx1, wz1, yA0, yA1, yB0, yB1;
                        double sLo2 = 0, sHi2 = 0;
                        if (raw.P >= 0)
                        {
                            double dxA = vx[raw.P], dzA = -vz[raw.P];
                            double dxB = vx[raw.Q], dzB = -vz[raw.Q];
                            sLo2 = Math.Max(0.0, raw.OverlapLo); sHi2 = Math.Min(1.0, raw.OverlapHi);
                            wx0 = dxA + (dxB - dxA) * sLo2; wz0 = dzA + (dzB - dzA) * sLo2;
                            wx1 = dxA + (dxB - dxA) * sHi2; wz1 = dzA + (dzB - dzA) * sHi2;
                            yA0 = Lerp(-vy[raw.A0], -vy[raw.A1], raw.SA0, raw.SA1, sLo2);
                            yA1 = Lerp(-vy[raw.A0], -vy[raw.A1], raw.SA0, raw.SA1, sHi2);
                            yB0 = Lerp(-vy[raw.B0], -vy[raw.B1], raw.SB0, raw.SB1, sLo2);
                            yB1 = Lerp(-vy[raw.B0], -vy[raw.B1], raw.SB0, raw.SB1, sHi2);
                        }
                        else
                        {
                            wx0 = raw.LeftX; wz0 = raw.LeftZ; wx1 = raw.RightX; wz1 = raw.RightZ;
                            yA0 = raw.LeftYA; yA1 = raw.RightYA; yB0 = raw.LeftYB; yB1 = raw.RightYB;
                        }

                        // Local free-space search on a quarter-yalm lattice.
                        double gx0b = Math.Min(Math.Min(ax2, bx2), Math.Min(wx0, wx1)) - (R + 0.5);
                        double gz0b = Math.Min(Math.Min(az2, bz2), Math.Min(wz0, wz1)) - (R + 0.5);
                        double gx1b = Math.Max(Math.Max(ax2, bx2), Math.Max(wx0, wx1)) + (R + 0.5);
                        double gz1b = Math.Max(Math.Max(az2, bz2), Math.Max(wz0, wz1)) + (R + 0.5);
                        int nxg = (int)Math.Ceiling((gx1b - gx0b) / Grid) + 1;
                        int nzg = (int)Math.Ceiling((gz1b - gz0b) / Grid) + 1;
                        if ((long)nxg * nzg > 8192) { rescueNoPath++; continue; }

                        // The doorway's supporting line splits the box in two.
                        // Flood free space on EACH side separately -- a flood
                        // confined to its own side cannot sneak around through a
                        // neighbouring doorway and claim this one -- then walk
                        // the doorway itself and find where the two floods meet
                        // with a full radius of daylight. That meeting run IS the
                        // crossing; its centre is where the beacon may aim.
                        double segX = wx1 - wx0, segZ = wz1 - wz0;
                        double segLen2 = Math.Sqrt(segX * segX + segZ * segZ);
                        if (segLen2 < 1e-9)
                        { rescueTiny++; if (dgw) Console.WriteLine($"diag: RESCUE degenerate-doorway {ta}<->{tb}"); continue; }
                        double SidePerp(double px, double pz)
                            => (segX * (pz - wz0) - segZ * (px - wx0)) / segLen2;
                        double sideA2 = SidePerp(tris[ta].Cx, tris[ta].Cz) >= 0 ? 1.0 : -1.0;
                        const double SideSlack = 0.05;

                        var cellY = new double[nxg * nzg];
                        var sideOf = new sbyte[nxg * nzg];   // 0 unvisited, 1 = A flood, 2 = B flood
                        var frontier = new Queue<int>();
                        const double PlaneAgree = 0.5;

                        void Flood(int who, in Tri seedTri, double sideSign)
                        {
                            frontier.Clear();
                            for (int sx3 = 0; sx3 < nxg; sx3++)
                            for (int sz3 = 0; sz3 < nzg; sz3++)
                            {
                                double spx = gx0b + sx3 * Grid, spz = gz0b + sz3 * Grid;
                                if (SidePerp(spx, spz) * sideSign < -SideSlack) continue;
                                if (!InTriXZ(seedTri, spx, spz, out double sPlane)) continue;
                                if (!rescueMesh.Surface(spx, spz, sPlane, Band, out double sy2)) continue;
                                if (Math.Abs(sy2 - sPlane) > PlaneAgree) continue;
                                if (!DiskClear(spx, spz, sy2)) continue;
                                int sc3 = sx3 * nzg + sz3;
                                if (sideOf[sc3] != 0) continue;
                                cellY[sc3] = sy2; sideOf[sc3] = (sbyte)who;
                                frontier.Enqueue(sc3);
                            }
                            while (frontier.Count > 0)
                            {
                                int cur = frontier.Dequeue();
                                int cix = cur / nzg, ciz = cur % nzg;
                                double cy2 = cellY[cur];
                                for (int dir = 0; dir < 4; dir++)
                                {
                                    int tx2 = cix + (dir == 0 ? 1 : dir == 1 ? -1 : 0);
                                    int tz2 = ciz + (dir == 2 ? 1 : dir == 3 ? -1 : 0);
                                    if (tx2 < 0 || tx2 >= nxg || tz2 < 0 || tz2 >= nzg) continue;
                                    int nc = tx2 * nzg + tz2;
                                    if (sideOf[nc] != 0) continue;
                                    double npx = gx0b + tx2 * Grid, npz = gz0b + tz2 * Grid;
                                    if (SidePerp(npx, npz) * sideSign < -SideSlack) continue;
                                    if (!rescueMesh.Surface(npx, npz, cy2, Band, out double ny3)) continue;
                                    if (Math.Abs(cy2 - ny3) > allowStep) continue;
                                    if (!DiskClear(npx, npz, ny3)) continue;
                                    cellY[nc] = ny3; sideOf[nc] = (sbyte)who;
                                    frontier.Enqueue(nc);
                                }
                            }
                        }
                        Flood(1, tris[ta], sideA2);
                        Flood(2, tris[tb], -sideA2);

                        // Walk the doorway. A sample passes when a cell of each
                        // flood stands within half a body of it, its own footing
                        // agrees with the doorway floor, and the disk is clear.
                        bool NearFlood(int who, double px, double pz, double py)
                        {
                            for (int gx2 = (int)Math.Round((px - gx0b) / Grid) - 2; gx2 <= (int)Math.Round((px - gx0b) / Grid) + 2; gx2++)
                            for (int gz2 = (int)Math.Round((pz - gz0b) / Grid) - 2; gz2 <= (int)Math.Round((pz - gz0b) / Grid) + 2; gz2++)
                            {
                                if (gx2 < 0 || gx2 >= nxg || gz2 < 0 || gz2 >= nzg) continue;
                                int cc = gx2 * nzg + gz2;
                                if (sideOf[cc] != who) continue;
                                double cpx = gx0b + gx2 * Grid, cpz = gz0b + gz2 * Grid;
                                double dh2 = Math.Sqrt((cpx - px) * (cpx - px) + (cpz - pz) * (cpz - pz));
                                if (dh2 <= 0.40 && Math.Abs(cellY[cc] - py) <= Math.Max(opt.MaxStepUp, opt.MaxStepDown) + 0.01)
                                    return true;
                            }
                            return false;
                        }
                        int nSamples = Math.Max(2, (int)Math.Ceiling(segLen2 / 0.125) + 1);
                        double runLo = -1, runHi = -1, bestRunLo = -1, bestRunHi = -1;
                        for (int sIdx = 0; sIdx <= nSamples; sIdx++)
                        {
                            double tS = (double)sIdx / nSamples;
                            double spx2 = wx0 + segX * tS, spz2 = wz0 + segZ * tS;
                            double floorS = 0.5 * (Lerp2(yA0, yA1, tS) + Lerp2(yB0, yB1, tS));
                            bool pass = rescueMesh.Surface(spx2, spz2, floorS, Band, out double syS)
                                        && Math.Abs(syS - floorS) <= PlaneAgree
                                        && DiskClear(spx2, spz2, syS)
                                        && NearFlood(1, spx2, spz2, syS)
                                        && NearFlood(2, spx2, spz2, syS);
                            if (pass)
                            {
                                if (runLo < 0) runLo = tS;
                                runHi = tS;
                            }
                            if (!pass || sIdx == nSamples)
                            {
                                if (runLo >= 0 && (bestRunLo < 0 || runHi - runLo > bestRunHi - bestRunLo))
                                { bestRunLo = runLo; bestRunHi = runHi; }
                                runLo = -1; runHi = -1;
                            }
                        }
                        if (bestRunLo < 0)
                        {
                            rescueDetour++;
                            if (dgw) Console.WriteLine($"diag: RESCUE no-crossing-here {ta}<->{tb}");
                            continue;
                        }
                        double tCross = 0.5 * (bestRunLo + bestRunHi);

                        // One radius each way from the proven crossing, clamped to
                        // the raw interval. This is what was PROVEN, no more.
                        double rLo = Math.Max(0.0, tCross - R / Math.Max(segLen2, 1e-9));
                        double rHi = Math.Min(1.0, tCross + R / Math.Max(segLen2, 1e-9));
                        if ((rHi - rLo) * segLen2 * 100.0 < MinSafeSpanCm)
                        {
                            rescueTiny++;
                            if (dgw) Console.WriteLine($"diag: RESCUE interval-too-small {ta}<->{tb}");
                            continue;
                        }

                        var walkPortal = new Portal
                        {
                            A = raw.A, B = raw.B, P = raw.P, Q = raw.Q,
                            A0 = raw.A0, A1 = raw.A1, B0 = raw.B0, B1 = raw.B1,
                            OverlapLo = raw.OverlapLo, OverlapHi = raw.OverlapHi,
                            SA0 = raw.SA0, SA1 = raw.SA1, SB0 = raw.SB0, SB1 = raw.SB1,
                            LeftX  = (float)(wx0 + segX * rLo),
                            LeftZ  = (float)(wz0 + segZ * rLo),
                            RightX = (float)(wx0 + segX * rHi),
                            RightZ = (float)(wz0 + segZ * rHi),
                            LeftYA  = (float)Lerp2(yA0, yA1, rLo),
                            LeftYB  = (float)Lerp2(yB0, yB1, rLo),
                            RightYA = (float)Lerp2(yA0, yA1, rHi),
                            RightYB = (float)Lerp2(yB0, yB1, rHi),
                            Flags = (int)(PortalFlag.SafeIntervalCertified | PortalFlag.WallEroded),
                        };
                        walkPortal.CapacityCm = SpanCm(walkPortal);
                        if (walkPortal.CapacityCm < MinSafeSpanCm)
                        {
                            rescueTiny++;
                            if (dgw) Console.WriteLine($"diag: RESCUE rounded-away {ta}<->{tb}");
                            continue;
                        }
                        portalList.Add(walkPortal);
                        pids2.Add(portalList.Count - 1);
                        rescueOk++;
                        if (dgw) Console.WriteLine($"diag: RESCUE ok {ta}<->{tb} tCross={tCross:F2} capacity={walkPortal.CapacityCm}cm");
                    }
                    Console.WriteLine($"graph: doorways_rescued_by_walking={rescueOk} tried={rescueTried} " +
                                      $"no_path={rescueNoPath} crossed_elsewhere={rescueDetour} interval_too_small={rescueTiny}");
                }

                // Lateral slide-hazard margin.
                //
                // Live 2026-08-21 20:23, La Theine switchback at (-296,344): the
                // funnel pinned the upper leg 0.95 yalms from the lip of a 44-47
                // degree bank (the radius erosion's exact limit). A 1.3-yalm drift
                // put a blind player on the bank; they slid four yalms to the lower
                // leg; the route replanned eight times in two minutes and said
                // "Turn around" three times. The doorway was real. The corridor had
                // no margin from ground a body cannot stand on.
                //
                // Ruling (sol): 33-45 degree ground is valid terrain when it is the
                // route's own support surface and a slide hazard when it forms a
                // lateral corridor boundary; trim portal intervals beside such
                // hazards by a tracking margin beyond the radius, zone-wide; do not
                // delete topology because the terrain is steep. So: every portal
                // interval is narrowed away from any face steeper than the climb
                // grade (walkable 33-45 AND the steep set) that lies at or below the
                // doorway floor and is not one of the doorway's own faces, by
                // radius + HazardMargin. A doorway that cannot afford the margin
                // keeps a body width centred on whatever survived -- a narrow
                // ledge is still the only way along it, and centring is the most a
                // builder can do there.
                {
                    const double HazardMargin = 1.5;     // beyond AgentRadius; observed drift was 1.3
                    const double HazardSlopeDeg = 33.0;  // the climb grade: steeper beside the path is a slide
                    double reach = opt.AgentRadius + HazardMargin;
                    double minKeepLen = 2.0 * opt.AgentRadius;
                    double epsH = Math.Max(1e-4, opt.WeldTolerance);
                    const double HCell = 4.0;
                    var hz = new List<(int a, int b, int c, int owner, float x0, float z0, float x1, float z1, float yLo, float yHi)>(steep.Count + 50_000);
                    for (int i = 0; i < tris.Count; i++)
                    {
                        if (tris[i].SlopeDeg <= HazardSlopeDeg) continue;
                        var tw = tris[i];
                        hz.Add((tw.A, tw.B, tw.C, i,
                            Math.Min(vx[tw.A], Math.Min(vx[tw.B], vx[tw.C])), Math.Min(-vz[tw.A], Math.Min(-vz[tw.B], -vz[tw.C])),
                            Math.Max(vx[tw.A], Math.Max(vx[tw.B], vx[tw.C])), Math.Max(-vz[tw.A], Math.Max(-vz[tw.B], -vz[tw.C])),
                            Math.Min(-vy[tw.A], Math.Min(-vy[tw.B], -vy[tw.C])), Math.Max(-vy[tw.A], Math.Max(-vy[tw.B], -vy[tw.C]))));
                    }
                    foreach (var (sa, sb, sc) in steep)
                    {
                        hz.Add((sa, sb, sc, -1,
                            Math.Min(vx[sa], Math.Min(vx[sb], vx[sc])), Math.Min(-vz[sa], Math.Min(-vz[sb], -vz[sc])),
                            Math.Max(vx[sa], Math.Max(vx[sb], vx[sc])), Math.Max(-vz[sa], Math.Max(-vz[sb], -vz[sc])),
                            Math.Min(-vy[sa], Math.Min(-vy[sb], -vy[sc])), Math.Max(-vy[sa], Math.Max(-vy[sb], -vy[sc]))));
                    }
                    var hcell = new Dictionary<(int, int), List<int>>(200_000);
                    for (int i = 0; i < hz.Count; i++)
                    {
                        var h = hz[i];
                        for (int gx = (int)Math.Floor(h.x0 / HCell); gx <= (int)Math.Floor(h.x1 / HCell); gx++)
                        for (int gz = (int)Math.Floor(h.z0 / HCell); gz <= (int)Math.Floor(h.z1 / HCell); gz++)
                        {
                            if (!hcell.TryGetValue((gx, gz), out var lst)) hcell[(gx, gz)] = lst = new List<int>(4);
                            lst.Add(i);
                        }
                    }

                    long hzExamined = 0, hzTrimmed = 0, hzNarrowedToBody = 0;
                    double hzTrimTotal = 0.0;
                    var hzBlocked = new List<(double lo, double hi)>(16);
                    var hzSeen = new HashSet<int>();
                    foreach (var pt in portalList)
                    {
                        if (pt.CapacityCm < MinSafeSpanCm) continue;
                        double lx = pt.LeftX, lz = pt.LeftZ, rx = pt.RightX, rz = pt.RightZ;
                        double len = Math.Sqrt((rx - lx) * (rx - lx) + (rz - lz) * (rz - lz));
                        if (len < 1e-6) continue;
                        hzExamined++;
                        double floorLo = Math.Min(Math.Min(pt.LeftYA, pt.LeftYB), Math.Min(pt.RightYA, pt.RightYB));
                        double bodyTop = floorLo - AgentHeight;
                        double bx0 = Math.Min(lx, rx) - reach, bx1 = Math.Max(lx, rx) + reach;
                        double bz0 = Math.Min(lz, rz) - reach, bz1 = Math.Max(lz, rz) + reach;
                        bool dgh = InDiag(opt, (lx + rx) * 0.5, (lz + rz) * 0.5);
                        hzBlocked.Clear();
                        hzSeen.Clear();
                        for (int gx = (int)Math.Floor(bx0 / HCell); gx <= (int)Math.Floor(bx1 / HCell); gx++)
                        for (int gz = (int)Math.Floor(bz0 / HCell); gz <= (int)Math.Floor(bz1 / HCell); gz++)
                        {
                            if (!hcell.TryGetValue((gx, gz), out var lst)) continue;
                            foreach (int hzi in lst)
                            {
                                if (!hzSeen.Add(hzi)) continue;
                                var h = hz[hzi];
                                // The doorway's own faces are the support surface, never a hazard to themselves.
                                if (h.owner >= 0 && (h.owner == pt.A || h.owner == pt.B)) continue;
                                // Overhead geometry does not narrow a doorway.
                                if (h.yHi < bodyTop - epsH) continue;
                                // Ground that RISES more than a step above the doorway floor is a
                                // wall or a climb, handled by the radius erosion; a slide is ground
                                // that falls away from the floor. y is DOWN: higher = smaller.
                                if (h.yLo < floorLo - opt.MaxStepUp) continue;
                                if (h.x1 < bx0 || h.x0 > bx1 || h.z1 < bz0 || h.z0 > bz1) continue;
                                if (BlockedSpan(lx, lz, rx, rz,
                                                vx[h.a], -vz[h.a], vx[h.b], -vz[h.b], vx[h.c], -vz[h.c],
                                                reach, out double blo, out double bhi))
                                {
                                    hzBlocked.Add((blo, bhi));
                                    if (dgh) Console.WriteLine($"diag: HAZARD portal {pt.A}<->{pt.B} face owner={h.owner} blocks [{blo:F3},{bhi:F3}]");
                                }
                            }
                        }
                        if (hzBlocked.Count == 0) continue;

                        // Trim only from the ENDS: a hazard lying under the middle of a
                        // doorway would split it, and splitting is not narrowing.
                        hzBlocked.Sort((u, v2) => u.lo.CompareTo(v2.lo));
                        double lo = 0.0, hi = 1.0;
                        foreach (var (blo, bhi) in hzBlocked)
                            if (blo <= lo + 1e-9) lo = Math.Max(lo, bhi);
                        for (int k = hzBlocked.Count - 1; k >= 0; k--)
                        {
                            var (blo, bhi) = hzBlocked[k];
                            if (bhi >= hi - 1e-9) hi = Math.Min(hi, blo);
                        }
                        // re-scan: a span that became end-adjacent after the first pass
                        bool changed = true;
                        while (changed)
                        {
                            changed = false;
                            foreach (var (blo, bhi) in hzBlocked)
                            {
                                if (blo <= lo + 1e-9 && bhi > lo) { lo = bhi; changed = true; }
                                if (bhi >= hi - 1e-9 && blo < hi) { hi = blo; changed = true; }
                            }
                        }
                        if (lo <= 1e-9 && hi >= 1.0 - 1e-9) continue;

                        double minKeep = Math.Min(1.0, minKeepLen / len);
                        if (hi - lo < minKeep)
                        {
                            // Cannot afford the margin: keep a body width centred on
                            // what survived (or on the doorway when nothing did).
                            double mid = hi > lo ? (lo + hi) * 0.5 : 0.5;
                            lo = Math.Max(0.0, mid - minKeep * 0.5);
                            hi = Math.Min(1.0, lo + minKeep);
                            lo = Math.Max(0.0, hi - minKeep);
                            hzNarrowedToBody++;
                        }
                        double nlx = lx + (rx - lx) * lo, nlz = lz + (rz - lz) * lo;
                        double nrx = lx + (rx - lx) * hi, nrz = lz + (rz - lz) * hi;
                        float nLeftYA = (float)(pt.LeftYA + (pt.RightYA - pt.LeftYA) * lo);
                        float nLeftYB = (float)(pt.LeftYB + (pt.RightYB - pt.LeftYB) * lo);
                        float nRightYA = (float)(pt.LeftYA + (pt.RightYA - pt.LeftYA) * hi);
                        float nRightYB = (float)(pt.LeftYB + (pt.RightYB - pt.LeftYB) * hi);
                        pt.LeftX = (float)nlx; pt.LeftZ = (float)nlz;
                        pt.RightX = (float)nrx; pt.RightZ = (float)nrz;
                        pt.LeftYA = nLeftYA; pt.LeftYB = nLeftYB;
                        pt.RightYA = nRightYA; pt.RightYB = nRightYB;
                        int before = pt.CapacityCm;
                        pt.CapacityCm = SpanCm(pt);
                        pt.Flags |= (int)PortalFlag.HazardMarginTrimmed;
                        hzTrimmed++;
                        hzTrimTotal += Math.Max(0, before - pt.CapacityCm) / 100.0;
                        if (dgh) Console.WriteLine($"diag: HAZARD trimmed {pt.A}<->{pt.B} [{lo:F3},{hi:F3}] capacity {before}cm -> {pt.CapacityCm}cm");
                    }
                    Console.WriteLine($"graph: hazard_margin={HazardMargin:F2} hazard_faces={hz.Count} portals_examined={hzExamined} " +
                                      $"portals_trimmed={hzTrimmed} narrowed_to_body={hzNarrowedToBody} trimmed_yalms={hzTrimTotal:F1}");
                }

                // The certified interval REPLACES the endpoint estimate. That
                // estimate only ever looked at whether the doorway's two ends were
                // pinned to a wall, so a wall lying along the opening, or running
                // beside it without touching either end, was invisible to it.
                // Rebuild the adjacency around the certified doorways. Three things
                // happen here at once, and they have to happen together:
                //
                //  - the certified interval REPLACES the endpoint estimate, which
                //    could not see a wall lying along an opening or running beside
                //    it without touching either end;
                //  - a doorway with no certified interval stops being an edge at
                //    all, rather than lingering at capacity zero where a later,
                //    looser policy could resurrect a crossing nobody proved;
                //  - a doorway split by an obstacle emits ONE EDGE PER COMPONENT.
                //
                // That last one was a hole in my own claim: the extra components
                // were written into the portal table and then bound to nothing,
                // because each node pair took only its widest. Present in the file,
                // unreachable by any route -- which is worse than omitting them,
                // since the file appears to offer a way through that the search can
                // never find.
                long lost = 0, pruned = 0, parallel = 0;
                for (int i = 0; i < tris.Count; i++)
                {
                    var keepE = new List<int>(outEdges[i].Count);
                    var keepG = new List<float>(outEdges[i].Count);
                    var keepP = new List<int>(outEdges[i].Count);
                    for (int k = 0; k < outEdges[i].Count; k++)
                    {
                        int j = outEdges[i][k];
                        long key = ((long)Math.Min(i, j) << 32) | (uint)Math.Max(i, j);
                        if (!portalOf.TryGetValue(key, out var pids))
                        { if (InDiag(opt, tris[i].Cx, tris[i].Cz) || InDiag(opt, tris[j].Cx, tris[j].Cz)) Console.WriteLine($"diag: BIND withdraw no-portal {i}<->{j}"); pruned++; continue; }

                        // A zero-capacity portal is dropped when the file is
                        // written, so binding an edge to one leaves it naming
                        // nothing. Take the live doorways whenever the pair has
                        // any -- after the seam repair above, it should.
                        bool anyLive = false;
                        foreach (int pid in pids) if (portalList[pid].CapacityCm >= MinSafeSpanCm) { anyLive = true; break; }

                        // Nothing left that says WHERE the gap is. Neither the
                        // welded certification nor the classified seam could
                        // place a doorway here, so the crossing is withdrawn
                        // rather than shipped for the funnel to guess at. An
                        // edge bound to no portal degrades to a centroid chain,
                        // which walks the middle of every triangle instead of
                        // the opening -- the bug this format exists to end.
                        if (!anyLive)
                        { if (InDiag(opt, tris[i].Cx, tris[i].Cz) || InDiag(opt, tris[j].Cx, tris[j].Cz)) Console.WriteLine($"diag: BIND withdraw no-live-portal {i}<->{j}"); pruned++; continue; }

                        int emitted = 0;
                        foreach (int pid in pids)
                        {
                            if (anyLive && portalList[pid].CapacityCm < MinSafeSpanCm) continue;
                            // Capacity is CARRIED, not enforced. The funnel pulls
                            // against it, but it no longer decides whether the
                            // crossing exists: doing so blocked 28,869 doorways
                            // and split the zone into 34,244 pieces with 5.4% of
                            // WALKED ground outside the main one. Whether a body
                            // can make this crossing is settled later, against
                            // the collision model, by walking it.
                            if (opt.DoorwayVeto && portalList[pid].CapacityCm <= 0) continue;
                            float cap = Math.Max(0f, portalList[pid].CapacityCm / 100f);
                            if (emitted == 0 && gate[i][k] >= opt.AgentRadius && cap < opt.AgentRadius) lost++;
                            keepE.Add(j); keepG.Add(cap); keepP.Add(pid);
                            emitted++;
                        }
                        if (emitted == 0) pruned++;
                        else if (emitted > 1) parallel += emitted - 1;
                    }
                    outEdges[i] = keepE;
                    gate[i] = keepG.ToArray();
                    outPortal[i] = keepP;
                }
                Console.WriteLine($"graph: crossings_the_endpoint_model_wrongly_allowed={lost}");
                Console.WriteLine($"graph: pruned_uncertified_edges={pruned} " +
                                  $"parallel_component_edges={parallel}");
            }

            // THE PRUNE. Every candidate crossing is walked against the collision
            // model and the ones that meet a hole or a break are removed, before
            // anything downstream believes them. This runs BEFORE clearance and
            // components so that both describe the surviving graph.
            var meshIndex = new MeshIndex(tris, steep, vx, vy, vz);
            ValidateTransitions("candidates", tris, outEdges, meshIndex, opt,
                                null, true, gate, outPortal);

            // Clearance: how far a node is from the edge of walkable ground, by
            // multi-source BFS from boundary triangles. Recast erodes the mesh by
            // agentRadius; a raw triangle graph has no such notion, so without
            // this every path would hug walls -- which is the ORIGINAL bug that
            // started all of this.
            // Bounded multi-source Dijkstra. An unbounded relaxation re-queues
            // nodes until the whole 224k-node graph settles and never finishes;
            // we only care whether a node has more than a body's width of room,
            // so stop expanding past ClearanceCap and call the rest open.
            //
            // Seeding this from `outEdges[i].Count < 3` was wrong three times over.
            // outEdges is the POST-GRADE-FILTER directed set, so it called a node
            // a wall whenever:
            //   1. a steep face genuinely rose from it            -- correct
            //   2. walkable ground simply ended at a cliff rim    -- WRONG, you
            //      can stand on a rim, and players walk them constantly
            //   3. the neighbour was standable but too steep to
            //      climb, i.e. a one-way ledge                    -- WRONG, and
            //      this fires in open field wherever a slope tops out just over
            //      the limit
            // La Theine is a plateau whose routes run along rims and slope tops,
            // so 2 and 3 fired nearly everywhere: 43 of 44 nodes on a real route
            // came back "below agent radius" on ground that is wide open. The
            // metric was libelling good terrain.
            //
            // Propagation is over UNDIRECTED adjacency. Clearance is a spatial
            // fact about how much room the body has; it has no business being
            // blocked by a ledge that happens to be one-way.
            var clearance = new float[tris.Count];
            var heap = new PriorityQueue<int, float>();
            //
            // A wall-touching triangle is seeded with the ACTUAL horizontal
            // distance from its centroid to the wall, not with zero. Zero says
            // "if any corner of this triangle touches a wall then no part of it
            // is usable", and at a median triangle width of 1.91 yalms that is
            // false: most of a 3-yalm triangle hinged on a wall is further from
            // that wall than the 0.70 the body needs. Seeding zero shattered the
            // 0.70-filtered graph into 64962 components holding 45% of nodes,
            // which is not a narrow-corridor finding, it is the metric erasing
            // every path that runs alongside a cliff -- in La Theine, most of them.
            //
            // XZ distance is the right quantity because the agent is a vertical
            // capsule: what it needs is horizontal room from the wall face.
            int wallSeeded = 0;
            for (int i = 0; i < tris.Count; i++)
            {
                var t = tris[i];
                float d = ClearanceCap;
                d = Math.Min(d, WallGap(wallEdges, canon, vx, vz, t, t.A, t.B));
                d = Math.Min(d, WallGap(wallEdges, canon, vx, vz, t, t.B, t.C));
                d = Math.Min(d, WallGap(wallEdges, canon, vx, vz, t, t.C, t.A));
                clearance[i] = d;
                if (d < ClearanceCap) { heap.Enqueue(i, d); wallSeeded++; }
            }
            Console.WriteLine($"graph: clearance_seeds={wallSeeded} " +
                              $"({100.0 * wallSeeded / Math.Max(1, tris.Count):F1}% of nodes touch a wall)");
            while (heap.TryDequeue(out int node, out float dist))
            {
                if (dist > clearance[node]) continue;   // stale heap entry
                if (dist >= ClearanceCap) continue;
                foreach (int j in neighbours[node])
                {
                    float d = dist + Dist2D(tris[node], tris[j]);
                    if (d < clearance[j])
                    {
                        clearance[j] = d;
                        heap.Enqueue(j, d);
                    }
                }
            }

            int tight = 0;
            for (int i = 0; i < tris.Count; i++)
                if (clearance[i] < opt.AgentRadius) tight++;
            Console.WriteLine($"graph: nodes_below_agent_radius={tight} " +
                              $"({100.0 * tight / Math.Max(1, tris.Count):F1}%)");

            // Erode the region: ground whose centre cannot hold the body at the
            // required stand-off stops being ground. Done HERE, after clearance
            // and before components, so what follows sees only surviving terrain
            // and the component count means "places the body can actually be".
            //
            // Cutting nodes rather than narrowing doorways is the whole point:
            // the constraint is stated once, about the body's room, and it can
            // never sever ground that is genuinely wide enough just because the
            // triangulation happened to put a short edge next to a wall.
            if (opt.RegionErode > 0)
            {
                int dropped = 0; long cutEdges = 0;
                var alive = new bool[tris.Count];
                for (int i = 0; i < tris.Count; i++)
                {
                    alive[i] = clearance[i] >= opt.RegionErode;
                    if (!alive[i]) dropped++;
                }
                for (int i = 0; i < tris.Count; i++)
                {
                    if (!alive[i])
                    {
                        cutEdges += outEdges[i].Count;
                        outEdges[i] = new List<int>();
                        gate[i] = Array.Empty<float>();
                        outPortal[i] = new List<int>();
                        continue;
                    }
                    var keepE = new List<int>(outEdges[i].Count);
                    var keepG = new List<float>(outEdges[i].Count);
                    var keepP = new List<int>(outEdges[i].Count);
                    for (int k = 0; k < outEdges[i].Count; k++)
                    {
                        if (!alive[outEdges[i][k]]) { cutEdges++; continue; }
                        keepE.Add(outEdges[i][k]);
                        keepG.Add(k < gate[i].Length ? gate[i][k] : 0f);
                        keepP.Add(k < outPortal[i].Count ? outPortal[i][k] : -1);
                    }
                    outEdges[i] = keepE; gate[i] = keepG.ToArray(); outPortal[i] = keepP;
                }
                Console.WriteLine($"graph: region_eroded_at={opt.RegionErode:F2} " +
                                  $"nodes_dropped={dropped} ({100.0 * dropped / Math.Max(1, tris.Count):F1}%) " +
                                  $"edges_cut={cutEdges}");
            }

            // Connected components. This is the cheapest possible honest answer to
            // "can I get there from here" -- two nodes in different components are
            // unreachable, full stop, and the player can be told so immediately
            // instead of being walked in circles while a search fails slowly.
            var component = new int[tris.Count];
            for (int i = 0; i < tris.Count; i++) component[i] = -1;
            int components = 0;
            // WEAKLY connected -- direction ignored, per Codex. Walking out-edges
            // only computes forward reachability from an arbitrary seed, which is
            // not connectivity: two nodes joined by a one-way step would be
            // labelled unrelated, and the runtime uses this to decide whether a
            // destination is reachable at all.
            var undirected = new List<int>[tris.Count];
            for (int i = 0; i < tris.Count; i++) undirected[i] = new List<int>(4);
            for (int i = 0; i < tris.Count; i++)
                foreach (int j in outEdges[i])
                {
                    undirected[i].Add(j);
                    undirected[j].Add(i);
                }

            var stack = new Stack<int>();
            var sizes = new List<int>();
            for (int s = 0; s < tris.Count; s++)
            {
                if (component[s] >= 0) continue;
                int id = components++;
                int members = 0;
                stack.Push(s);
                component[s] = id;
                while (stack.Count > 0)
                {
                    int i = stack.Pop();
                    members++;
                    foreach (int j in undirected[i])
                        if (component[j] < 0) { component[j] = id; stack.Push(j); }
                }
                sizes.Add(members);
            }
            sizes.Sort();
            sizes.Reverse();
            int biggest = sizes.Count > 0 ? sizes[0] : 0;
            Console.WriteLine($"graph: components={components} largest={biggest} " +
                              $"({100.0 * biggest / Math.Max(1, tris.Count):F1}% of nodes)");

            // Ground truth: the player's own recorded positions. Every one of them
            // is a place they physically stood, so they must all land on walkable
            // nodes, and a walked trail must not be split across components -- if
            // it is, the graph has invented a barrier where the player simply
            // walked through. This is the check that catches over-restriction,
            // which for a blind player is as harmful as over-connection: one
            // walks them into rock, the other strands them.
            if (!string.IsNullOrEmpty(opt.SurveyPath) && File.Exists(opt.SurveyPath))
                ReportSurveyCoverage(opt.SurveyPath, tris, component, opt);

            // Freeze the PRE-erosion answer before anything erodes. Stage 3 has to
            // ask whether erosion split something that was whole, and it cannot
            // ask that against a baseline computed after the fact -- by then the
            // components are the eroded ones and the comparison is circular.
            // Recorded positions and every destination the addon can be asked to
            // route to, each with the node and component it lands in today.
            if (!string.IsNullOrEmpty(opt.BaselinePath))
                WriteBaseline(opt.BaselinePath, opt.SurveyPath, opt.DestinationsPath,
                              tris, component, opt);


            // Stage 1. Classify every boundary per interval and put the answer
            // against ground the player has actually walked. Three tolerances
            // because the horizontal figure is the arbitrary one -- the safety
            // comes from the height test -- and the spread shows how much the
            // answer depends on a number nobody has measured.
            //
            // The local erosion pass that used to run here has been REMOVED, not
            // silenced. It clipped each triangle against only its OWN blocking
            // edges, which never touches a triangle whose neighbour eroded away,
            // so its area-retained and doorway-lost figures were optimistic and
            // are withdrawn. Full-radius erosion needs a propagated surface
            // distance field seeded from exactly the intervals below, and that is
            // stage 2.
            // Report on the classification the graph was actually BUILT from --
            // computed far above, before adjacency, so these numbers describe the
            // thing being shipped. The optional A/B re-runs the centroid proxy
            // purely to show what that proxy was costing; it never feeds the graph.
            foreach (bool centroidSide in opt.SideTestAB ? new[] { true, false } : new[] { false })
            {
                Console.WriteLine($"boundary: ===== side test = {(centroidSide ? "centroid proxy (old, diagnostic only)" : "far-side coverage (new, THE ONE BUILT FROM)")} =====");
                var report = centroidSide
                    ? ClassifyBoundaries(tris, steep, canon, vx, vy, vz, edgeOwners, AcceptGap, opt, true)
                    : boundary;
                ReportBoundaries(report);
                GateBoundariesAgainstSurvey(opt.SurveyPath, report, opt.ZoneId, opt);
                ReportAgentEnvelope(opt.SurveyPath, report, opt.ZoneId, tris, vx, vy, vz, opt);
                if (!centroidSide) ReportControlTopology(tris, report, component, opt);

                // Stage 2. Only on the verdict classification, and only when
                // asked: it is a measurement, and it must never be able to alter
                // what gets written out until the radius question is settled.
                if (!centroidSide && opt.ErodeRadii.Count > 0)
                {
                    foreach (var (rw, rr) in opt.ErodeRadii)
                    {
                        var eroded = Erode(tris, vx, vy, vz, boundary, rw, rr, opt);
                        ReportErosion2(eroded, tris);
                        VerifyErosion(eroded, tris, vx, vy, vz, boundary, opt);
                        GateErosionAgainstSurvey(opt.SurveyPath, eroded, tris, opt.ZoneId, opt, boundary);
                    }
                }
            }

            // THE GATE. Judge what is about to be written, against the collision
            // model, one transition at a time. Nothing below this line is
            // trustworthy if this reports refutations.
            // Must come back clean: this is the same test that did the pruning,
            // re-run on what survived. A non-zero count here means something
            // downstream of the prune put a refuted crossing back.
            ValidateTransitions("emitted", tris, outEdges, meshIndex, opt);

            int probesRun = 0, probesPassed = 0;
            foreach (var pr in opt.Probes)
            {
                probesRun++;
                if (ProbeRoute(pr, tris, outEdges, component, meshIndex, opt)) probesPassed++;
            }
            if (probesRun > 0)
                Console.WriteLine($"probe: {probesPassed} of {probesRun} route regressions passed");

            uint sourceCrc;
            {
                // Identify the exact collision export this graph came from. A
                // graph is only meaningful against the geometry it was built on.
                var objBytes = File.ReadAllBytes(objPath);
                sourceCrc = Crc32(objBytes, 0, objBytes.Length);
            }
            Console.WriteLine($"graph: source_obj_crc32={sourceCrc:X8} weld_mm={(uint)Math.Round(opt.WeldTolerance * 1000.0)}");
            // Orient each doorway's endpoints as LEFT and RIGHT seen by someone
            // walking A -> B, so a funnel can consume them without re-deriving
            // handedness, and so reverse traversal is just a swap. A stored
            // direction flag would be one more thing that can disagree with the
            // geometry, which is how the 61cm-one-way-300cm-the-other bug worked.
            foreach (var pt in portalList)
            {
                if (pt.CapacityCm <= 0) continue;
                double dx2 = tris[pt.B].Cx - tris[pt.A].Cx, dz2 = tris[pt.B].Cz - tris[pt.A].Cz;
                double mx = (pt.LeftX + pt.RightX) * 0.5, mz = (pt.LeftZ + pt.RightZ) * 0.5;
                if (dx2 * (pt.LeftZ - mz) - dz2 * (pt.LeftX - mx) < 0)
                {
                    (pt.LeftX, pt.RightX) = (pt.RightX, pt.LeftX);
                    (pt.LeftZ, pt.RightZ) = (pt.RightZ, pt.LeftZ);
                    (pt.LeftYA, pt.RightYA) = (pt.RightYA, pt.LeftYA);
                    (pt.LeftYB, pt.RightYB) = (pt.RightYB, pt.LeftYB);
                }
            }

            if (opt.FormatVersion >= 2)
                WriteBinaryV2(outPath, tris, outEdges, gate, outPortal, clearance, component, components,
                              portalList, sourceCrc, opt);
            else
                WriteBinary(outPath, tris, outEdges, gate, clearance, component, components, sourceCrc, opt);
            var size = new FileInfo(outPath).Length;
            Console.WriteLine($"graph: out={outPath} bytes={size}");
            return 0;
        }

        private static void ReportSurveyCoverage(string surveyPath, List<Tri> tris,
                                                 int[] component, Options opt)
        {
            // Coarse XZ buckets so we are not doing 224k comparisons per sample.
            const float Cell = 8f;
            var buckets = new Dictionary<(int, int), List<int>>(50_000);
            for (int i = 0; i < tris.Count; i++)
            {
                var key = ((int)Math.Floor(tris[i].Cx / Cell), (int)Math.Floor(tris[i].Cz / Cell));
                if (!buckets.TryGetValue(key, out var list)) buckets[key] = list = new List<int>(8);
                list.Add(i);
            }

            int samples = 0, unmatched = 0;
            var hitComponents = new Dictionary<int, int>();
            foreach (var line in File.ReadLines(surveyPath))
            {
                var f = line.Split('\t');
                if (f.Length < 7 || f[0] == "survey_id") continue;
                if (!int.TryParse(f[1], out int zone) || zone != 102) continue;
                if (!float.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out float px)) continue;
                if (!float.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out float pz)) continue;
                if (!float.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out float py)) continue;
                samples++;

                int best = -1;
                double bestD = double.MaxValue;
                int bx = (int)Math.Floor(px / Cell), bz = (int)Math.Floor(pz / Cell);
                for (int ox = -1; ox <= 1; ox++)
                for (int oz = -1; oz <= 1; oz++)
                {
                    if (!buckets.TryGetValue((bx + ox, bz + oz), out var list)) continue;
                    foreach (int i in list)
                    {
                        double dx = tris[i].Cx - px, dz = tris[i].Cz - pz, dy = tris[i].Cy - py;
                        double d = dx * dx + dz * dz + dy * dy * 4.0;   // height matters more
                        if (d < bestD) { bestD = d; best = i; }
                    }
                }
                if (best < 0 || bestD > 25.0) { unmatched++; continue; }
                hitComponents.TryGetValue(component[best], out int c);
                hitComponents[component[best]] = c + 1;
            }

            // The sharp test. "Largest share" is too blunt: the survey holds
            // several recording sessions, and two sessions may legitimately start
            // in different places. But two CONSECUTIVE samples in the same
            // session are a step the player physically took, so if they land in
            // different components the graph has invented a barrier across a
            // stride. Those are the only real defects.
            int breaks = 0, strides = 0;
            string prevSurvey = "";
            int prevSeq = -999, prevComp = -1;
            foreach (var line in File.ReadLines(surveyPath))
            {
                var f = line.Split('\t');
                if (f.Length < 7 || f[0] == "survey_id") continue;
                if (!int.TryParse(f[1], out int z2) || z2 != 102) continue;
                if (!int.TryParse(f[3], out int seq)) continue;
                if (!float.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out float px)) continue;
                if (!float.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out float pz)) continue;
                if (!float.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out float py)) continue;

                int comp = -1;
                double bestD = double.MaxValue;
                int bx2 = (int)Math.Floor(px / Cell), bz2 = (int)Math.Floor(pz / Cell);
                for (int ox = -1; ox <= 1; ox++)
                for (int oz = -1; oz <= 1; oz++)
                {
                    if (!buckets.TryGetValue((bx2 + ox, bz2 + oz), out var list)) continue;
                    foreach (int i in list)
                    {
                        double dx = tris[i].Cx - px, dz = tris[i].Cz - pz, dy = tris[i].Cy - py;
                        double d = dx * dx + dz * dz + dy * dy * 4.0;
                        if (d < bestD) { bestD = d; comp = component[i]; }
                    }
                }
                if (bestD > 25.0) comp = -1;

                if (f[0] == prevSurvey && seq == prevSeq + 1 && comp >= 0 && prevComp >= 0)
                {
                    strides++;
                    if (comp != prevComp) breaks++;
                }
                prevSurvey = f[0]; prevSeq = seq; prevComp = comp;
            }
            Console.WriteLine($"survey: consecutive_strides={strides} " +
                              $"broken_by_graph={breaks} ({100.0 * breaks / Math.Max(1, strides):F2}%)");

            var ranked = new List<KeyValuePair<int, int>>(hitComponents);
            ranked.Sort((a, b) => b.Value.CompareTo(a.Value));
            int top = ranked.Count > 0 ? ranked[0].Value : 0;
            Console.WriteLine($"survey: samples={samples} unmatched={unmatched} " +
                              $"({100.0 * unmatched / Math.Max(1, samples):F1}%) " +
                              $"components_touched={ranked.Count} largest_share={100.0 * top / Math.Max(1, samples):F1}%");
            for (int i = 0; i < Math.Min(5, ranked.Count); i++)
                Console.WriteLine($"survey:   component {ranked[i].Key} holds {ranked[i].Value} samples");
        }

        private static float Dist2D(in Tri a, in Tri b)
        {
            double dx = a.Cx - b.Cx, dz = a.Cz - b.Cz;
            return (float)Math.Sqrt(dx * dx + dz * dz);
        }

        // A vertex position at export precision (0.1mm). Fine enough that two
        // genuinely different corners never collide, coarse enough to absorb the
        // last-bit noise of a float round-trip through the OBJ text.
        private static (long, long, long) VKey(float x, float y, float z)
            => ((long)Math.Round(x * 10000.0), (long)Math.Round(y * 10000.0), (long)Math.Round(z * 10000.0));

        // Sort three vertex keys so a face hashes the same whichever corner the
        // exporter started from and whichever way it wound.
        private static void SortKeys(ref (long, long, long) a, ref (long, long, long) b,
                                     ref (long, long, long) c)
        {
            static bool Less((long, long, long) u, (long, long, long) v)
            {
                if (u.Item1 != v.Item1) return u.Item1 < v.Item1;
                if (u.Item2 != v.Item2) return u.Item2 < v.Item2;
                return u.Item3 < v.Item3;
            }
            if (!Less(a, b)) (a, b) = (b, a);
            if (!Less(b, c)) (b, c) = (c, b);
            if (!Less(a, b)) (a, b) = (b, a);
        }

        // Canonical undirected edge key. Must match AddEdge's key exactly or the
        // wall set and the adjacency map will be talking about different edges.
        private static long EdgeKey(int u, int v)
            => u < v ? ((long)u << 32) | (uint)v : ((long)v << 32) | (uint)u;

        // Clip a convex polygon to the half-plane { X : dot(n, X - P) >= offset },
        // Sutherland-Hodgman. Convex in, convex out, so this composes: applying it
        // once per blocking boundary leaves the eroded cell convex, which is the
        // property the funnel depends on.
        private static List<(double X, double Z)> ClipHalfPlane(
            List<(double X, double Z)> poly, double px, double pz,
            double nx, double nz, double offset)
        {
            var outPoly = new List<(double X, double Z)>(poly.Count + 2);
            if (poly.Count == 0) return outPoly;
            for (int i = 0; i < poly.Count; i++)
            {
                var a = poly[i];
                var b = poly[(i + 1) % poly.Count];
                double da = (a.X - px) * nx + (a.Z - pz) * nz - offset;
                double db = (b.X - px) * nx + (b.Z - pz) * nz - offset;
                bool ina = da >= 0.0, inb = db >= 0.0;
                if (ina) outPoly.Add(a);
                if (ina != inb)
                {
                    double t = da / (da - db);
                    outPoly.Add((a.X + (b.X - a.X) * t, a.Z + (b.Z - a.Z) * t));
                }
            }
            return outPoly;
        }

        private static double PolyArea(List<(double X, double Z)> poly)
        {
            if (poly.Count < 3) return 0.0;
            double a = 0.0;
            for (int i = 0; i < poly.Count; i++)
            {
                var p = poly[i];
                var q = poly[(i + 1) % poly.Count];
                a += p.X * q.Z - q.X * p.Z;
            }
            return Math.Abs(a) * 0.5;
        }

        // ---------------------------------------------------------------
        // Boundary classification, per INTERVAL.
        //
        // What this replaces, and why. The previous pass paired an open edge
        // with a partner only when the WHOLE edges matched -- near-coincident
        // midpoints, near-parallel, similar height -- and called every edge that
        // found no partner a real rim. That classifier cannot see a T-junction
        // (one model's 10-yalm border against another's five 2-yalm borders: no
        // midpoint matches anything) nor a one-to-many seam (an edge covered
        // along only part of its length). Its headline -- "7.7% seam-paired" --
        // therefore measured the classifier, not the zone, and is withdrawn.
        //
        // Every edge of every standable triangle is a parameter interval [0, L]
        // here, and each point along it is classified by what is really present
        // across it:
        //
        //   seam       another standable surface covers this stretch at a height
        //              the player could step to. The ground continues, so there
        //              is nothing here to erode. NOT blocking. Ordinary interior
        //              adjacency lands here too, and should: it is the same fact
        //              about the same geometry.
        //   wall       a steep face hinged on this stretch rises at least
        //              MaxStepUp above it. A body cannot occupy it. BLOCKING.
        //   ambiguous  a standable surface covers it, but standing further off
        //              than a step and nearer than a fall. Unknown stays
        //              BLOCKING -- and is counted apart, so the price of doubt
        //              is visible instead of buried inside whichever of the two
        //              answers flatters us.
        //   true open  nothing standable is across it at any reachable height. A
        //              cliff lip, a hole, the outer rim of the model. BLOCKING,
        //              and the population erosion exists to protect against.
        //
        // Reported as LENGTH, never as edge counts. A count is a tessellation
        // artefact: the same physical border reads as 1 or as 5 depending on
        // which side of it you stand.
        //
        // Coordinates are GAME space throughout -- x, -z, -y off the raw OBJ --
        // because the step and fall limits being applied are game-space facts.
        // ---------------------------------------------------------------

        private enum BoundaryKind : byte { Wall = 0, TrueOpen = 1, Seam = 2, Ambiguous = 3 }

        // What lies across a blocking boundary. Without this, every gate failure
        // reads the same -- "the player walked through a wall" -- when the causes
        // are entirely different work: a face just over the standing limit is the
        // slope threshold being conservative, a refused neighbour is this
        // classifier being wrong, and nothing at all is the survey or the
        // collision data being wrong.
        private enum AcrossKind : byte { Nothing = 0, Steep = 1, RefusedFloor = 2 }

        private struct BoundarySeg
        {
            public float AX, AZ, AY;
            public float BX, BZ, BY;
            public int Owner;            // the standable triangle this bounds
            public BoundaryKind Kind;
            public AcrossKind Across;
            public float AcrossGap, AcrossDy, AcrossSlope;
            // Wall intervals only: how far the steep face rises above the edge.
            // A wall belongs to ONE triangle, and every other triangle has to be
            // able to ask how tall it is -- a 0.50 riser is a step you stand on
            // top of, not an obstacle, and without this the two are the same
            // fact to anyone but the owner.
            public float WallRise;
        }

        private sealed class BoundaryReport
        {
            public double SeamTolerance;
            public List<BoundarySeg> Blocking = new List<BoundarySeg>(400_000);

            // Whole-zone length by class, over every edge of every standable face.
            public double LenTotal, LenWall, LenSeam, LenAmbiguous, LenOpen;

            // Of the seam length, how much came from a supporter that does NOT
            // share the welded edge key -- the T-junctions and one-to-many joins
            // the whole-edge classifier structurally could not see.
            public double LenSeamCrossKey;

            // The same numbers restricted to the population the old pass called
            // "open" (welded key with fewer than two standable owners). This is
            // the direct answer to the withdrawn headline.
            public double OpenLenTotal, OpenLenWall, OpenLenSeam, OpenLenAmbiguous, OpenLenOpen;
            public double OpenLenSeamCrossKey;

            // True-open runs bucketed by length. A run narrower than the weld
            // tolerance is below the precision of the input and is evidence of
            // nothing; a run wider than a body is a hole. Erosion treats both the
            // same, so the split has to be visible before anyone accepts the cost.
            public double GapSubWeld, GapNarrow, GapWide;
            public long GapSubWeldRuns, GapNarrowRuns, GapWideRuns;

            // What is actually behind the true-open length, length-weighted:
            // rows are how far away the nearest standable surface across the
            // boundary is, columns are how far it stands above or below. This
            // separates "there is nothing there" from "there is ground there we
            // declined to trust", which the old pass reported as one number.
            // Split by WHAT is across, because the two populations mean opposite
            // things and their dy is not even the same measurement: for a steep
            // face it is how far that face swings from the edge, for a refused
            // floor it is how far off the height test found it.
            public double[,] CensusSteep = new double[CensusGapBuckets, CensusDyBuckets];
            public double[,] CensusFloor = new double[CensusGapBuckets, CensusDyBuckets];
            public double CensusVoid;

            public long CandidatesTested, RejectedSameSide, RejectedHeight, RejectedGap, DegenerateEdges;

            // The centroid side-test audit. SideGeomOnly is the population that
            // matters: candidates whose surface really does cover the far side
            // but whose centroid sits on the owner's, which the proxy dropped.
            public long SideAgree, SideCentroidOnly, SideGeomOnly;
            public double SideDisagreeLen, SideDisagreeOpen, SideDisagreeAmbiguous;

            // Blocked stretches that failed only the accept-gap cap, kept as
            // named candidates rather than lost in a rejection counter.
            public List<BoundarySeg> GapCandidates = new List<BoundarySeg>(4096);
            public double GapCandidateLen;

            // Adjacency as this classifier sees it: A and B share a stretch of
            // ground the player can cross, of the given width. This is the same
            // evidence the seam length is counted from, so the graph's topology
            // and its boundary classification can no longer disagree.
            //
            // It exists because the old adjacency came from welded EDGE KEYS,
            // which requires two faces to name the identical edge. A T-junction
            // names three different edges for one physical join, so the old
            // topology could sever ground this classifier calls continuous.
            // Carries the DOORWAY, not just the fact of a join. The stretch the
            // two surfaces share is already known here as a parameter interval on
            // the owner's edge, and that interval IS the gap a body walks
            // through. Recording only a width threw the geometry away and left
            // the funnel with nothing to pull against but centroids -- which is
            // how a corridor ends up hugging a wall the portal never claimed was
            // passable. Heights are kept per OWNER at each end, because the two
            // surfaces meet at an angle and their heights differ across it.
            public List<SeamLink> Links = new List<SeamLink>(600_000);
        }

        internal struct SeamLink
        {
            public int A, B;                    // owner -> partner, directed
            public float X0, Z0, Y0A, Y0B;      // doorway end 0: position, A's height, B's height
            public float X1, Z1, Y1A, Y1B;      // doorway end 1
            public float Width;
        }

        private const int CensusGapBuckets = 5;
        private const int CensusDyBuckets = 5;
        private static readonly double[] CensusGapEdge = { 0.05, 0.25, 0.70, 1.40, double.MaxValue };
        private static readonly double[] CensusDyEdge = { 0.25, 0.50, 1.00, 1.80, double.MaxValue };
        private static readonly string[] CensusGapLabel = { "<0.05", "<0.25", "<0.70", "<1.40", ">=1.40" };
        private static readonly string[] CensusDyLabel = { "<0.25", "<0.50", "<1.00", "<1.80", ">=1.80" };

        private static int Bucket(double v, double[] edges)
        {
            for (int i = 0; i < edges.Length; i++) if (v < edges[i]) return i;
            return edges.Length - 1;
        }

        private static BoundaryReport ClassifyBoundaries(
            List<Tri> tris, List<(int A, int B, int C)> steep, int[] canon,
            List<float> vx, List<float> vy, List<float> vz,
            Dictionary<long, List<int>> edgeOwners,
            double maxGap, Options opt, bool centroidSideTest)
        {
            var rep = new BoundaryReport { SeamTolerance = maxGap };

            // How far out to LOOK, as opposed to how far out to accept. Anything
            // found between maxGap and here is not stitched; it is recorded in
            // the census below so that "nothing is across this boundary" can be
            // told apart from "something is across it that we refused". Those are
            // very different facts and the old pass reported them as one.
            const double CensusGap = 2.0;
            double queryTol = Math.Max(maxGap, CensusGap);
            // Held apart from maxGap on purpose -- see the wall test below.
            double wallGap = Math.Max(0.05, opt.WeldTolerance * 2.0);

            // Two surfaces nearer than this in XZ are candidates for describing
            // the same ground; how far apart they stand VERTICALLY is what
            // decides whether they do, and that test is below. Taking the safety
            // from the height test rather than the horizontal one is deliberate:
            // a 0.2-yalm crack in a floor is no hazard to a walking body, and a
            // 0.2-yalm horizontal offset at the top of a cliff is.
            const double ParallelDot = 0.94;   // ~20 deg; models abut, they do not align perfectly
            const double MinInterval = 1e-4;
            const double Cell = 4.0;

            double stepUp = Math.Max(1e-6, opt.MaxStepUp);
            double stepDown = Math.Max(1e-6, opt.MaxStepDown);
            // Further than a step and nearer than your own height: too far to
            // walk onto, too close to call a cliff without looking. A doubt band,
            // not a physical claim -- named so nobody later reads it as one.
            double doubtBand = AgentHeight;

            int nWalk = tris.Count * 3;
            int nEdges = nWalk + steep.Count * 3;

            // Flatten every edge once. The inner loop below touches these a few
            // tens of millions of times, and going back through List<T> indexers
            // and a struct copy each time costs more than the 30 MB this holds.
            var eAX = new float[nEdges]; var eAZ = new float[nEdges];
            var eBX = new float[nEdges]; var eBZ = new float[nEdges];
            var eAY = new float[nEdges]; var eBY = new float[nEdges];
            var eOppY = new float[nEdges];    // the third corner's height: which way a steep face swings
            var eOppX = new float[nEdges]; var eOppZ = new float[nEdges];
            // Slope of the steep face behind each steep edge. A boundary the
            // player crossed anyway means something quite different at 40.9
            // degrees than at 70, and only this tells them apart.
            var steepSlope = new float[Math.Max(1, steep.Count)];
            for (int i = 0; i < steep.Count; i++)
            {
                var s = steep[i];
                double ux2 = vx[s.B] - vx[s.A], uy2 = vy[s.B] - vy[s.A], uz2 = vz[s.B] - vz[s.A];
                double wx2 = vx[s.C] - vx[s.A], wy2 = vy[s.C] - vy[s.A], wz2 = vz[s.C] - vz[s.A];
                double nx2 = uy2 * wz2 - uz2 * wy2;
                double ny2 = uz2 * wx2 - ux2 * wz2;
                double nz2 = ux2 * wy2 - uy2 * wx2;
                double ln = Math.Sqrt(nx2 * nx2 + ny2 * ny2 + nz2 * nz2);
                steepSlope[i] = ln < 1e-9 ? 90f
                    : (float)(Math.Acos(Math.Min(1.0, Math.Abs(ny2) / ln)) * 180.0 / Math.PI);
            }

            for (int k = 0; k < nEdges; k++)
            {
                int u, v, w;
                if (k < nWalk)
                {
                    var t = tris[k / 3];
                    switch (k % 3)
                    {
                        case 0: u = t.A; v = t.B; w = t.C; break;
                        case 1: u = t.B; v = t.C; w = t.A; break;
                        default: u = t.C; v = t.A; w = t.B; break;
                    }
                }
                else
                {
                    var s = steep[(k - nWalk) / 3];
                    switch ((k - nWalk) % 3)
                    {
                        case 0: u = s.A; v = s.B; w = s.C; break;
                        case 1: u = s.B; v = s.C; w = s.A; break;
                        default: u = s.C; v = s.A; w = s.B; break;
                    }
                }
                eAX[k] = vx[u]; eAZ[k] = -vz[u]; eAY[k] = -vy[u];
                eBX[k] = vx[v]; eBZ[k] = -vz[v]; eBY[k] = -vy[v];
                eOppX[k] = vx[w]; eOppZ[k] = -vz[w]; eOppY[k] = -vy[w];
            }

            double minX = double.MaxValue, maxX = double.MinValue;
            double minZ = double.MaxValue, maxZ = double.MinValue;
            for (int k = 0; k < nEdges; k++)
            {
                if (eAX[k] < minX) minX = eAX[k];
                if (eAX[k] > maxX) maxX = eAX[k];
                if (eBX[k] < minX) minX = eBX[k];
                if (eBX[k] > maxX) maxX = eBX[k];
                if (eAZ[k] < minZ) minZ = eAZ[k];
                if (eAZ[k] > maxZ) maxZ = eAZ[k];
                if (eBZ[k] < minZ) minZ = eBZ[k];
                if (eBZ[k] > maxZ) maxZ = eBZ[k];
            }
            int gw = (int)((maxX - minX) / Cell) + 3;
            int gh = (int)((maxZ - minZ) / Cell) + 3;
            int CX(double x) => Math.Min(gw - 1, Math.Max(0, (int)Math.Floor((x - minX) / Cell) + 1));
            int CZ(double z) => Math.Min(gh - 1, Math.Max(0, (int)Math.Floor((z - minZ) / Cell) + 1));

            // CSR bucket grid. A dictionary of lists costs more in object headers
            // than payload on a 32-bit runtime, and this table holds a couple of
            // million entries.
            var cellStart = new int[gw * gh + 1];
            for (int k = 0; k < nEdges; k++)
            {
                int x0 = CX(Math.Min(eAX[k], eBX[k]) - queryTol), x1 = CX(Math.Max(eAX[k], eBX[k]) + queryTol);
                int z0 = CZ(Math.Min(eAZ[k], eBZ[k]) - queryTol), z1 = CZ(Math.Max(eAZ[k], eBZ[k]) + queryTol);
                for (int cz = z0; cz <= z1; cz++)
                for (int cx = x0; cx <= x1; cx++)
                    cellStart[cz * gw + cx + 1]++;
            }
            for (int i = 0; i < gw * gh; i++) cellStart[i + 1] += cellStart[i];
            var cellItems = new int[cellStart[gw * gh]];
            var fill = new int[gw * gh];
            for (int k = 0; k < nEdges; k++)
            {
                int x0 = CX(Math.Min(eAX[k], eBX[k]) - queryTol), x1 = CX(Math.Max(eAX[k], eBX[k]) + queryTol);
                int z0 = CZ(Math.Min(eAZ[k], eBZ[k]) - queryTol), z1 = CZ(Math.Max(eAZ[k], eBZ[k]) + queryTol);
                for (int cz = z0; cz <= z1; cz++)
                for (int cx = x0; cx <= x1; cx++)
                {
                    int c = cz * gw + cx;
                    cellItems[cellStart[c] + fill[c]++] = k;
                }
            }
            Console.WriteLine($"boundary: grid {gw}x{gh}, edges={nEdges} insertions={cellItems.Length} " +
                              $"(accept gap {maxGap:F2}, look out to {queryTol:F2})");

            // Plane coefficients per standable face, so the partner's surface
            // height at a point is a multiply-add rather than a cross product.
            var pNX = new float[tris.Count]; var pNZ = new float[tris.Count];
            var pD = new float[tris.Count]; var pOK = new bool[tris.Count];
            for (int i = 0; i < tris.Count; i++)
            {
                var t = tris[i];
                double axg = vx[t.A], ayg = -vy[t.A], azg = -vz[t.A];
                double e1x = vx[t.B] - axg, e1y = -vy[t.B] - ayg, e1z = -vz[t.B] - azg;
                double e2x = vx[t.C] - axg, e2y = -vy[t.C] - ayg, e2z = -vz[t.C] - azg;
                double nx = e1y * e2z - e1z * e2y;
                double ny = e1z * e2x - e1x * e2z;
                double nz = e1x * e2y - e1y * e2x;
                // A standable face is never near-vertical -- the slope filter
                // guarantees it -- but check rather than divide on faith.
                if (Math.Abs(ny) < 1e-9) { pOK[i] = false; continue; }
                pOK[i] = true;
                pNX[i] = (float)(-nx / ny);
                pNZ[i] = (float)(-nz / ny);
                pD[i] = (float)(ayg + (nx * axg + nz * azg) / ny);
            }

            var stamp = new int[nEdges];
            int generation = 0;

            var wallIv = new List<(double S0, double S1)>(8);
            var seamSame = new List<(double S0, double S1)>(8);
            var seamCross = new List<(double S0, double S1)>(8);
            var ambIv = new List<(double S0, double S1)>(8);
            var seamAll = new List<(double S0, double S1)>(8);
            var ambOnly = new List<(double S0, double S1)>(8);
            var openIv = new List<(double S0, double S1)>(8);
            var s1L = new List<(double S0, double S1)>(8);
            var s2L = new List<(double S0, double S1)>(8);
            var s3L = new List<(double S0, double S1)>(8);
            var census = new List<(double S0, double S1, double Gap, double Dy, byte Kind, float Slope)>(16);
            var sideDisagree = new List<(double S0, double S1)>(8);
            var gapCand = new List<(double S0, double S1, double Gap, double Dy)>(8);
            var seamHits = new List<(double S0, double S1, int Partner)>(16);

            for (int k = 0; k < nWalk; k++)
            {
                int owner = k / 3;
                double ax = eAX[k], az = eAZ[k], ay = eAY[k];
                double bx = eBX[k], bz = eBZ[k], by = eBY[k];
                double dx = bx - ax, dz = bz - az;
                double L = Math.Sqrt(dx * dx + dz * dz);
                if (L < 1e-6) { rep.DegenerateEdges++; continue; }
                double ux = dx / L, uz = dz / L;
                // Inward normal decided by the triangle's own third corner, so it
                // never depends on a winding order the soup did not promise.
                double nx = -uz, nz = ux;
                if ((eOppX[k] - ax) * nx + (eOppZ[k] - az) * nz < 0.0) { nx = -nx; nz = -nz; }

                rep.LenTotal += L;

                long weldKey = -1;
                List<int>? keyOwners = null;
                bool openKey;
                {
                    int u, v;
                    var t = tris[owner];
                    switch (k % 3)
                    {
                        case 0: u = t.A; v = t.B; break;
                        case 1: u = t.B; v = t.C; break;
                        default: u = t.C; v = t.A; break;
                    }
                    int cu = canon[u], cv = canon[v];
                    if (cu == cv) openKey = true;    // welding collapsed it; it owns nothing
                    else
                    {
                        weldKey = EdgeKey(cu, cv);
                        openKey = !edgeOwners.TryGetValue(weldKey, out keyOwners) || keyOwners.Count < 2;
                    }
                }
                if (openKey) rep.OpenLenTotal += L;

                wallIv.Clear(); seamSame.Clear(); seamCross.Clear(); ambIv.Clear(); census.Clear();
                sideDisagree.Clear(); gapCand.Clear(); seamHits.Clear();
                double wallRiseMax = 0.0;
                generation++;

                int qx0 = CX(Math.Min(ax, bx) - queryTol), qx1 = CX(Math.Max(ax, bx) + queryTol);
                int qz0 = CZ(Math.Min(az, bz) - queryTol), qz1 = CZ(Math.Max(az, bz) + queryTol);
                for (int cz = qz0; cz <= qz1; cz++)
                for (int cx = qx0; cx <= qx1; cx++)
                {
                    int c = cz * gw + cx;
                    for (int p = cellStart[c]; p < cellStart[c + 1]; p++)
                    {
                        int m = cellItems[p];
                        if (m == k) continue;
                        if (stamp[m] == generation) continue;   // one edge lands in several cells
                        stamp[m] = generation;

                        bool mSteep = m >= nWalk;
                        int mTri = mSteep ? -1 : m / 3;
                        if (!mSteep && mTri == owner) continue;

                        double fax = eAX[m], faz = eAZ[m];
                        double fbx = eBX[m], fbz = eBZ[m];
                        double fdx = fbx - fax, fdz = fbz - faz;
                        double fl = Math.Sqrt(fdx * fdx + fdz * fdz);
                        if (fl < 1e-6) continue;

                        // Same line? Perpendicular offset of both endpoints.
                        double o0 = (fax - ax) * nx + (faz - az) * nz;
                        double o1 = (fbx - ax) * nx + (fbz - az) * nz;
                        if (Math.Abs(o0) > queryTol || Math.Abs(o1) > queryTol) continue;
                        if (Math.Abs((fdx * ux + fdz * uz) / fl) < ParallelDot) continue;

                        // Overlapping stretch, in yalms from this edge's A end.
                        double s0 = (fax - ax) * ux + (faz - az) * uz;
                        double s1 = (fbx - ax) * ux + (fbz - az) * uz;
                        if (s0 > s1) { double sw = s0; s0 = s1; s1 = sw; }
                        if (s0 < 0.0) s0 = 0.0;
                        if (s1 > L) s1 = L;
                        if (s1 - s0 < MinInterval) continue;
                        rep.CandidatesTested++;

                        double gap = Math.Max(Math.Abs(o0), Math.Abs(o1));

                        if (mSteep)
                        {
                            // A steep face hinged here either rises above the
                            // stretch -- a wall -- or falls away below it, which
                            // makes this a cliff LIP and not a wall at all.
                            // Opposite facts about one triangle; only the first
                            // stops a body. y is DOWN, so above is less.
                            //
                            // The wall test keeps its OWN tight tolerance rather
                            // than following maxGap. A wall is a face HINGED on
                            // this edge -- it shares welded corners -- and a
                            // steep face a yalm and a half away is hinged on
                            // something else. Letting the two tolerances move
                            // together made every widening of the seam rule mark
                            // more wall (141698 -> 241675 yalms) and drove the
                            // gate the wrong way, which is how this surfaced.
                            double emid0 = ay + (by - ay) * ((s0 + s1) * 0.5 / L);

                            // The steep edge has to be AT this edge, not merely
                            // over it. A near-vertical face projects to a LINE in
                            // XZ, so an arch twenty yalms overhead projects onto
                            // exactly the same line as the ground beneath it, and
                            // a horizontal-only test cannot tell them apart. That
                            // is not hypothetical: it invented a wall with a
                            // 20.10 rise at (348.5,-8.0) standing on open ground
                            // at y=24, from a face whose own edge is at y=3.3,
                            // and it put a recorded position 0.111 from a "wall"
                            // -- which then reads as evidence for a body barely
                            // wider than a point.
                            double smid = (s0 + s1) * 0.5;
                            double mx = ax + ux * smid, mz = az + uz * smid;
                            double tf = Math.Clamp(((mx - fax) * fdx + (mz - faz) * fdz) / (fl * fl), 0.0, 1.0);
                            double fmid = eAY[m] + (eBY[m] - eAY[m]) * tf;
                            if (Math.Abs(fmid - emid0) > opt.MaxStepUp) continue;

                            double rise = emid0 - eOppY[m];       // y is DOWN, so a rise is positive here
                            census.Add((s0, s1, gap, Math.Abs(rise), (byte)AcrossKind.Steep,
                                        steepSlope[(m - nWalk) / 3]));
                            if (gap > wallGap) continue;
                            // STRICTLY greater. Downstream a wall is dismissed as
                            // a step when it rises no more than MaxStepUp, so
                            // recording one at exactly MaxStepUp creates a wall
                            // that every later test then refuses to apply -- it
                            // is both a wall and a step at once, and the cell
                            // keeps a corner sitting on it. The two thresholds
                            // have to be complementary, not overlapping.
                            if (rise > opt.MaxStepUp)
                            {
                                wallIv.Add((s0, s1));
                                if (rise > wallRiseMax) wallRiseMax = rise;
                            }
                            continue;
                        }

                        if (!pOK[mTri]) continue;
                        var pt = tris[mTri];

                        // Is the candidate's surface actually BEYOND this
                        // boundary? The old test asked whether its centroid sat
                        // on the far side, which is a proxy and a sliver defeats
                        // it: a long thin triangle can carry its centre of area
                        // on the owner's side while its surface genuinely covers
                        // the far side. 965086 candidates were being dropped on
                        // that proxy, so it is measured here rather than trusted.
                        //
                        // The direct test: step just past the boundary and ask
                        // whether the candidate is underfoot there. Depth scales
                        // with the measured gap, so a flush neighbour is probed
                        // at weld scale and a 0.25 seam at 0.27 -- a fixed depth
                        // would step over small neighbours entirely.
                        // All three samples must land, because partial coverage
                        // is not continuous support.
                        bool centroidFar = (pt.Cx - ax) * nx + (pt.Cz - az) * nz <= 0.05;
                        double probe = Math.Max(gap, opt.WeldTolerance) + opt.WeldTolerance;
                        int landed = 0;
                        for (int q = 0; q < 3; q++)
                        {
                            double s = s0 + (s1 - s0) * (0.15 + 0.35 * q);
                            if (PointInTriXZ(pt, vx, vz,
                                             ax + ux * s - nx * probe,
                                             az + uz * s - nz * probe)) landed++;
                        }
                        bool geomFar = landed == 3;

                        if (centroidFar != geomFar)
                        {
                            if (geomFar) rep.SideGeomOnly++; else rep.SideCentroidOnly++;
                            sideDisagree.Add((s0, s1));
                        }
                        else rep.SideAgree++;

                        if (!(centroidSideTest ? centroidFar : geomFar))
                        { rep.RejectedSameSide++; continue; }

                        // Where does that partner's SURFACE stand over the
                        // stretch in question? Evaluate its plane at points on
                        // THIS edge rather than interpolating along the
                        // partner's own: the two are within tolerance of each
                        // other but not identical, and the plane is exact.
                        //
                        // The STEP limit is the right test only at zero
                        // horizontal separation. Two model pieces abutting with
                        // a gap g and a height difference d do not present a
                        // step of d -- the player walks g forward while changing
                        // height by d, which is a GRADE of d/g. Judging a 0.62
                        // drop across a 0.65 gap by a 0.50 step limit calls a
                        // 44-degree ramp a cliff; the player walked that exact
                        // spot in the survey (recording 20260712-170700, seq
                        // 284), which is how the mistake surfaced.
                        //
                        // So the allowance is whichever is larger, the step or
                        // the grade over the measured gap. Both limits are the
                        // graph's OWN, already written into the artifact's policy
                        // header, so nothing new is invented. This cannot bridge
                        // a cliff: the gap is capped by the caller, and at 0.70
                        // yalms a down-grade limit of 1.0 permits a 0.70 drop.
                        double allowUp = Math.Max(stepUp, gap * opt.MaxUpGrade);
                        double allowDown = Math.Max(stepDown, gap * opt.MaxDownGrade);
                        double worstExcess = double.MinValue, worstAbs = 0.0;
                        for (int q = 0; q <= 2; q++)
                        {
                            double s = s0 + (s1 - s0) * (q * 0.5);
                            double sx = ax + ux * s, sz = az + uz * s;
                            double ey = ay + (by - ay) * (s / L);
                            double py = pNX[mTri] * sx + pNZ[mTri] * sz + pD[mTri];
                            double d = py - ey;    // y is DOWN: positive means the partner stands LOWER
                            double excess = d > 0.0 ? d - allowDown : (-d) - allowUp;
                            if (excess > worstExcess) { worstExcess = excess; worstAbs = Math.Abs(d); }
                        }

                        // Everything we did NOT stitch goes in the census, so a
                        // boundary with nothing behind it can be told from one
                        // with ground behind it we declined to trust.
                        if (worstExcess > 0.0 || gap > maxGap)
                            census.Add((s0, s1, gap, worstAbs, (byte)AcrossKind.RefusedFloor, tris[mTri].SlopeDeg));

                        if (gap > maxGap)
                        {
                            rep.RejectedGap++;
                            // It would have passed the height and grade test at
                            // its own measured gap; only the accept cap stopped
                            // it. Those are not seams -- a body fitting through
                            // a space does not prove the space is supported --
                            // but the ones the player has demonstrably walked
                            // are worth keeping as named candidates rather than
                            // losing them in a rejection counter.
                            if (worstExcess <= 0.0) gapCand.Add((s0, s1, gap, worstAbs));
                        }
                        else if (worstExcess <= 0.0)
                        {
                            bool sameKey = keyOwners != null && keyOwners.Contains(mTri);
                            if (sameKey) seamSame.Add((s0, s1)); else seamCross.Add((s0, s1));
                            // Who supported it, not merely that something did.
                            // The length report needs only the union; the
                            // topology needs the partner.
                            seamHits.Add((s0, s1, mTri));
                        }
                        else if (worstAbs <= doubtBand) ambIv.Add((s0, s1));
                        else rep.RejectedHeight++;
                    }
                }

                // Wall beats everything: floor beyond a wall is floor you cannot
                // reach. Seam beats ambiguity: a compatible floor found by ANY
                // partner settles the question, whatever a second partner shows.
                Merge(wallIv); Merge(seamSame); Merge(seamCross); Merge(ambIv);
                double lenWall = TotalLen(wallIv);

                s1L.Clear(); Subtract(seamSame, wallIv, s1L);          // same-key seam, minus wall
                s2L.Clear(); Subtract(seamCross, wallIv, s2L);
                s3L.Clear(); Subtract(s2L, s1L, s3L);                  // cross-key seam not already same-key
                double lenSeamSame = TotalLen(s1L);
                double lenSeamCross = TotalLen(s3L);

                seamAll.Clear(); seamAll.AddRange(s1L); seamAll.AddRange(s3L); Merge(seamAll);

                s2L.Clear(); Subtract(ambIv, wallIv, s2L);
                ambOnly.Clear(); Subtract(s2L, seamAll, ambOnly);
                double lenAmb = TotalLen(ambOnly);

                s1L.Clear(); s1L.Add((0.0, L));
                s2L.Clear(); Subtract(s1L, wallIv, s2L);
                s3L.Clear(); Subtract(s2L, seamAll, s3L);
                openIv.Clear(); Subtract(s3L, ambOnly, openIv);
                double lenOpen = TotalLen(openIv);

                // Adjacency, from the same evidence as the seam length. A wall
                // standing on a stretch overrides the ground continuing beneath
                // it, so subtract the wall intervals before believing a link.
                for (int h = 0; h < seamHits.Count; h++)
                {
                    s1L.Clear(); s1L.Add((seamHits[h].S0, seamHits[h].S1));
                    s2L.Clear(); Subtract(s1L, wallIv, s2L);
                    foreach (var iv in s2L)
                    {
                        double w = iv.S1 - iv.S0;
                        if (w < MinInterval) continue;
                        // Lift the surviving interval off the edge parameter and
                        // into the world, so the doorway travels with the link.
                        // Owner height is linear along its own edge; the partner's
                        // is read off the partner's own surface at the same XZ,
                        // because the two planes meet at an angle and assuming
                        // they agree is what puts a portal inside a wall.
                        int partner = seamHits[h].Partner;
                        double p0x = ax + ux * iv.S0, p0z = az + uz * iv.S0;
                        double p1x = ax + ux * iv.S1, p1z = az + uz * iv.S1;
                        rep.Links.Add(new SeamLink
                        {
                            A = owner, B = partner,
                            X0 = (float)p0x, Z0 = (float)p0z,
                            Y0A = (float)(ay + (by - ay) * (iv.S0 / L)),
                            Y0B = (float)TriSurfaceY(tris[partner], vx, vy, vz, p0x, p0z),
                            X1 = (float)p1x, Z1 = (float)p1z,
                            Y1A = (float)(ay + (by - ay) * (iv.S1 / L)),
                            Y1B = (float)TriSurfaceY(tris[partner], vx, vy, vz, p1x, p1z),
                            Width = (float)w,
                        });
                    }
                }

                // Gap-connection candidates, but only where the boundary really
                // did stay blocked. If some other partner stitched the stretch
                // anyway there is nothing left to wonder about.
                for (int c = 0; c < gapCand.Count; c++)
                {
                    foreach (var blocked in new[] { openIv, ambOnly })
                    foreach (var iv2 in blocked)
                    {
                        double lo = Math.Max(gapCand[c].S0, iv2.S0);
                        double hi = Math.Min(gapCand[c].S1, iv2.S1);
                        if (hi - lo < MinInterval) continue;
                        rep.GapCandidates.Add(new BoundarySeg
                        {
                            AX = (float)(ax + ux * lo), AZ = (float)(az + uz * lo),
                            AY = (float)(ay + (by - ay) * (lo / L)),
                            BX = (float)(ax + ux * hi), BZ = (float)(az + uz * hi),
                            BY = (float)(ay + (by - ay) * (hi / L)),
                            Owner = owner, Kind = BoundaryKind.Seam,
                            Across = AcrossKind.RefusedFloor,
                            AcrossGap = (float)gapCand[c].Gap, AcrossDy = (float)gapCand[c].Dy,
                        });
                        rep.GapCandidateLen += hi - lo;
                    }
                }

                // Where the two side tests disagreed, how much boundary is at
                // stake and what did it end up being called? Unique length, not
                // a candidate count -- several candidates can disagree over the
                // same stretch and it is still one piece of ground.
                if (sideDisagree.Count > 0)
                {
                    Merge(sideDisagree);
                    rep.SideDisagreeLen += TotalLen(sideDisagree);
                    s1L.Clear(); Subtract(sideDisagree, openIv, s1L);
                    rep.SideDisagreeOpen += TotalLen(sideDisagree) - TotalLen(s1L);
                    s2L.Clear(); Subtract(sideDisagree, ambOnly, s2L);
                    rep.SideDisagreeAmbiguous += TotalLen(sideDisagree) - TotalLen(s2L);
                }

                rep.LenWall += lenWall;
                rep.LenSeam += lenSeamSame + lenSeamCross;
                rep.LenSeamCrossKey += lenSeamCross;
                rep.LenAmbiguous += lenAmb;
                rep.LenOpen += lenOpen;
                if (openKey)
                {
                    rep.OpenLenWall += lenWall;
                    rep.OpenLenSeam += lenSeamSame + lenSeamCross;
                    rep.OpenLenSeamCrossKey += lenSeamCross;
                    rep.OpenLenAmbiguous += lenAmb;
                    rep.OpenLenOpen += lenOpen;
                }

                // These are stage 2's seeds: what the distance field measures
                // away from. Seam stretches are deliberately absent -- there is
                // nothing there to stand back from.
                // Every wall stretch on this edge carries the tallest rise found
                // on it. Over-stating a wall's height only ever makes it more of
                // an obstacle, which is the safe direction to be wrong in.
                foreach (var iv in wallIv)
                    Emit(rep, owner, BoundaryKind.Wall, ax, az, ay, ux, uz, by, L, iv, census, wallRiseMax);
                foreach (var iv in ambOnly)
                    Emit(rep, owner, BoundaryKind.Ambiguous, ax, az, ay, ux, uz, by, L, iv, census);
                foreach (var iv in openIv)
                {
                    double run = iv.S1 - iv.S0;
                    if (run < MinInterval) continue;
                    if (run < opt.WeldTolerance) { rep.GapSubWeld += run; rep.GapSubWeldRuns++; }
                    else if (run < 0.25) { rep.GapNarrow += run; rep.GapNarrowRuns++; }
                    else { rep.GapWide += run; rep.GapWideRuns++; }
                    var seg = Emit(rep, owner, BoundaryKind.TrueOpen, ax, az, ay, ux, uz, by, L, iv, census);

                    int gb = Bucket(seg.AcrossGap, CensusGapEdge), db = Bucket(seg.AcrossDy, CensusDyEdge);
                    if (seg.Across == AcrossKind.Nothing) rep.CensusVoid += run;
                    else if (seg.Across == AcrossKind.Steep) rep.CensusSteep[gb, db] += run;
                    else rep.CensusFloor[gb, db] += run;
                }
            }

            return rep;
        }

        private static BoundarySeg Emit(BoundaryReport rep, int owner, BoundaryKind kind,
                                        double ax, double az, double ay, double ux, double uz,
                                        double by, double L, (double S0, double S1) iv,
                                        List<(double S0, double S1, double Gap, double Dy,
                                              byte Kind, float Slope)> census,
                                        double wallRise = 0.0)
        {
            // What stands across this stretch? A floor we refused outranks a
            // steep face, because "we declined a neighbour" is a claim about
            // this classifier and "the far side is a cliff" is a claim about the
            // zone; within each, nearest in height wins, since that is the
            // surface a body would actually meet.
            var across = AcrossKind.Nothing;
            double bestGap = 0.0, bestDy = 0.0; float bestSlope = 0f;
            for (int c = 0; c < census.Count; c++)
            {
                if (Math.Min(census[c].S1, iv.S1) - Math.Max(census[c].S0, iv.S0) < 1e-4) continue;
                var kind2 = (AcrossKind)census[c].Kind;
                bool better = across == AcrossKind.Nothing
                    || (kind2 == AcrossKind.RefusedFloor && across == AcrossKind.Steep)
                    || (kind2 == across && census[c].Dy < bestDy);
                if (!better) continue;
                across = kind2; bestGap = census[c].Gap; bestDy = census[c].Dy; bestSlope = census[c].Slope;
            }

            var seg = new BoundarySeg
            {
                AX = (float)(ax + ux * iv.S0), AZ = (float)(az + uz * iv.S0),
                AY = (float)(ay + (by - ay) * (iv.S0 / L)),
                BX = (float)(ax + ux * iv.S1), BZ = (float)(az + uz * iv.S1),
                BY = (float)(ay + (by - ay) * (iv.S1 / L)),
                Owner = owner, Kind = kind,
                Across = across, AcrossGap = (float)bestGap,
                AcrossDy = (float)bestDy, AcrossSlope = bestSlope, WallRise = (float)wallRise,
            };
            rep.Blocking.Add(seg);
            return seg;
        }

        // The frozen pre-erosion baseline. One row per anchor -- every recorded
        // survey position and every destination the addon can be asked to route
        // to in this zone -- naming the node it lands on and the component that
        // node belongs to BEFORE any erosion.
        //
        // Stage 3's fragmentation test is "did erosion split something that was
        // whole", and that question is only answerable against a baseline taken
        // beforehand. Computed afterwards it compares eroded components with
        // eroded components and always agrees with itself.
        private static void WriteBaseline(string outPath, string surveyPath, string destPath,
                                          List<Tri> tris, int[] component, Options opt)
        {
            const float Cell = 8f;
            var buckets = new Dictionary<(int, int), List<int>>(50_000);
            for (int i = 0; i < tris.Count; i++)
            {
                var key = ((int)Math.Floor(tris[i].Cx / Cell), (int)Math.Floor(tris[i].Cz / Cell));
                if (!buckets.TryGetValue(key, out var list)) buckets[key] = list = new List<int>(8);
                list.Add(i);
            }

            // Same matcher ReportSurveyCoverage uses, so the two agree by
            // construction rather than by coincidence.
            int Nearest(double px, double pz, double py, out double dist)
            {
                int best = -1; double bestD = double.MaxValue;
                int bx = (int)Math.Floor(px / Cell), bz = (int)Math.Floor(pz / Cell);
                for (int ox = -1; ox <= 1; ox++)
                for (int oz = -1; oz <= 1; oz++)
                {
                    if (!buckets.TryGetValue((bx + ox, bz + oz), out var list)) continue;
                    foreach (int i in list)
                    {
                        double dx = tris[i].Cx - px, dz = tris[i].Cz - pz, dy = tris[i].Cy - py;
                        double d = dx * dx + dz * dz + dy * dy * 4.0;
                        if (d < bestD) { bestD = d; best = i; }
                    }
                }
                // Two different failures, and they must not print alike: nothing
                // within the search buckets at all, versus a nearest node too far
                // to be the same place. The first printed as 1.8e308 and read as
                // corrupt input when it only meant "nowhere near the zone".
                dist = best >= 0 ? Math.Sqrt(bestD) : -1.0;
                return best >= 0 && bestD <= 25.0 ? best : -1;
            }

            int surveyRows = 0, destRows = 0, unmatched = 0;
            using (var w = new StreamWriter(outPath, false))
            {
                w.WriteLine("# AccessXI walk-graph PRE-EROSION baseline. Frozen before stage 2.");
                w.WriteLine($"# zone={opt.ZoneId} slope={opt.MaxSlopeDeg:F1} weld={opt.WeldTolerance:F3} " +
                            $"stepup={opt.MaxStepUp:F2} stepdown={opt.MaxStepDown:F2} " +
                            $"upgrade={opt.MaxUpGrade:F6} downgrade={opt.MaxDownGrade:F6} nodes={tris.Count}");
                w.WriteLine("kind\tid\tname\tx\tz\ty\tnode\tcomponent\tmatch_distance");

                if (!string.IsNullOrEmpty(surveyPath) && File.Exists(surveyPath))
                {
                    foreach (var line in File.ReadLines(surveyPath))
                    {
                        var f = line.Split('\t');
                        if (f.Length < 7 || f[0] == "survey_id") continue;
                        if (!int.TryParse(f[1], out int z) || z != opt.ZoneId) continue;
                        if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double px)) continue;
                        if (!double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out double pz)) continue;
                        if (!double.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out double py)) continue;
                        int n = Nearest(px, pz, py, out double d);
                        if (n < 0) unmatched++;
                        w.WriteLine($"survey\t{f[0]}:{f[3]}\t{(f.Length > 8 ? f[8] : "")}\t" +
                                    $"{px:F3}\t{pz:F3}\t{py:F3}\t{n}\t{(n >= 0 ? component[n] : -1)}\t{d:F3}");
                        surveyRows++;
                    }
                }

                if (!string.IsNullOrEmpty(destPath) && File.Exists(destPath))
                {
                    foreach (var line in File.ReadLines(destPath))
                    {
                        if (line.Length == 0 || line[0] == '#') continue;
                        var f = line.Split('\t');
                        if (f.Length < 5) continue;
                        if (!int.TryParse(f[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out int z)
                            || z != opt.ZoneId) continue;
                        if (!double.TryParse(f[2], NumberStyles.Float, CultureInfo.InvariantCulture, out double px)) continue;
                        if (!double.TryParse(f[3], NumberStyles.Float, CultureInfo.InvariantCulture, out double pz)) continue;
                        if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double py)) continue;
                        int n = Nearest(px, pz, py, out double d);
                        if (n < 0) unmatched++;
                        w.WriteLine($"destination\t{(f.Length > 5 ? f[5] : "")}\t{f[1]}\t" +
                                    $"{px:F3}\t{pz:F3}\t{py:F3}\t{n}\t{(n >= 0 ? component[n] : -1)}\t{d:F3}");
                        destRows++;
                    }
                }
            }
            Console.WriteLine($"baseline: wrote {outPath} -- survey_rows={surveyRows} " +
                              $"destination_rows={destRows} unmatched={unmatched}");
        }

        // Is (px,pz) inside the triangle's XZ footprint? Game space. Winding is
        // not guaranteed by the soup, so accept either.
        private static bool PointInTriXZ(in Tri t, List<float> vx, List<float> vz,
                                         double px, double pz)
        {
            double ax = vx[t.A], az = -vz[t.A];
            double bx = vx[t.B], bz = -vz[t.B];
            double cx = vx[t.C], cz = -vz[t.C];
            double d1 = (px - ax) * (bz - az) - (pz - az) * (bx - ax);
            double d2 = (px - bx) * (cz - bz) - (pz - bz) * (cx - bx);
            double d3 = (px - cx) * (az - cz) - (pz - cz) * (ax - cx);
            bool neg = d1 < -1e-9 || d2 < -1e-9 || d3 < -1e-9;
            bool pos = d1 > 1e-9 || d2 > 1e-9 || d3 > 1e-9;
            return !(neg && pos);
        }

        // A doorway built from a classified seam rather than from a shared edge
        // key. Endpoints are already world positions and each surface's own
        // height at each end is already known, so nothing has to be re-derived
        // from a canonical edge these two faces may not share.
        //
        // Stored A < B, with the height fields following the swap, so a reader
        // never has to ask which owner a height belongs to. The overlap span is
        // the whole interval because the seam IS the overlap -- it was computed
        // by intersecting the two surfaces, not by trusting a shared label.
        // The loader's own floor for a usable doorway, in centimetres. Anything
        // under this is refused when the file is read, so it must be refused
        // here instead of being written and rejected later.
        private const int MinSafeSpanCm = 5;

        private static bool InDiag(Options opt, double x, double z)
            => opt.HasDiag && x >= opt.DiagX0 && x <= opt.DiagX1
                           && z >= opt.DiagZ0 && z <= opt.DiagZ1;

        private static double Lerp2(double a, double b, double t) => a + (b - a) * t;

        private static Portal MakeSeamPortal(int a, int b, in SeamLink lk)
        {
            bool flip = a > b;
            int lo = flip ? b : a, hi = flip ? a : b;

            // Capacity is measured from the STORED float endpoints, with the same
            // floor the loader applies, because the loader re-derives the interval
            // from exactly those floats. Rounding the parameter width instead
            // overstated the gap by up to half a centimetre and the file was
            // refused with "capacity exceeds its interval" -- a portal claiming
            // more room than the geometry it names.
            float lx = lk.X0, lz = lk.Z0, rx = lk.X1, rz = lk.Z1;
            double span = Math.Sqrt(((double)rx - lx) * ((double)rx - lx) +
                                    ((double)rz - lz) * ((double)rz - lz));
            int cm = (int)Math.Floor(span * 100.0);

            return new Portal
            {
                A = lo, B = hi,
                P = -1, Q = -1, A0 = -1, A1 = -1, B0 = -1, B1 = -1,
                LeftX = lx, LeftZ = lz,
                RightX = rx, RightZ = rz,
                LeftYA = flip ? lk.Y0B : lk.Y0A, LeftYB = flip ? lk.Y0A : lk.Y0B,
                RightYA = flip ? lk.Y1B : lk.Y1A, RightYB = flip ? lk.Y1A : lk.Y1B,
                CapacityCm = cm < MinSafeSpanCm ? 0 : cm,
                Flags = (int)(PortalFlag.SafeIntervalCertified | PortalFlag.WallEroded),
                Extra = 0,
                OverlapLo = 0.0, OverlapHi = 1.0,
                SA0 = 0.0, SA1 = 1.0, SB0 = 0.0, SB1 = 1.0,
            };
        }

        // A triangle's own surface height at a horizontal point, in GAME frame.
        // Barycentric rather than nearest-corner: a doorway endpoint almost never
        // lands on a corner, and rounding it to one tilts the portal by the whole
        // rise of the triangle. Deliberately extrapolates outside the triangle --
        // callers ask about points on a shared edge, where floating point puts
        // the answer a hair either side and clamping would quantise the height.
        private static double TriSurfaceY(in Tri t, List<float> vx, List<float> vy, List<float> vz,
                                          double px, double pz)
        {
            double ax = vx[t.A], az = -vz[t.A], ay = -vy[t.A];
            double bx = vx[t.B], bz = -vz[t.B], by = -vy[t.B];
            double cx = vx[t.C], cz = -vz[t.C], cy = -vy[t.C];
            double den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz);
            if (Math.Abs(den) < 1e-12) return t.Cy;      // degenerate in XZ; centroid is the only honest answer
            double w1 = ((bz - cz) * (px - cx) + (cx - bx) * (pz - cz)) / den;
            double w2 = ((cz - az) * (px - cx) + (ax - cx) * (pz - cz)) / den;
            return w1 * ay + w2 * by + (1.0 - w1 - w2) * cy;
        }

        private static void Merge(List<(double S0, double S1)> iv)
        {
            if (iv.Count < 2) return;
            iv.Sort((a, b) => a.S0.CompareTo(b.S0));
            int w = 0;
            for (int i = 1; i < iv.Count; i++)
            {
                if (iv[i].S0 <= iv[w].S1) { if (iv[i].S1 > iv[w].S1) iv[w] = (iv[w].S0, iv[i].S1); }
                else iv[++w] = iv[i];
            }
            iv.RemoveRange(w + 1, iv.Count - w - 1);
        }

        private static double TotalLen(List<(double S0, double S1)> iv)
        {
            double s = 0.0;
            for (int i = 0; i < iv.Count; i++) s += iv[i].S1 - iv[i].S0;
            return s;
        }

        // dst = src \ cut. Both inputs must already be merged and sorted; the
        // output is too, so these compose.
        private static void Subtract(List<(double S0, double S1)> src,
                                     List<(double S0, double S1)> cut,
                                     List<(double S0, double S1)> dst)
        {
            for (int i = 0; i < src.Count; i++)
            {
                double lo = src[i].S0, hi = src[i].S1;
                for (int c = 0; c < cut.Count; c++)
                {
                    if (cut[c].S1 <= lo) continue;
                    if (cut[c].S0 >= hi) break;
                    if (cut[c].S0 > lo) dst.Add((lo, cut[c].S0));
                    if (cut[c].S1 > lo) lo = cut[c].S1;
                    if (lo >= hi) break;
                }
                if (hi - lo > 1e-9) dst.Add((lo, hi));
            }
        }

        private static void ReportBoundaries(BoundaryReport rep)
        {
            double t = Math.Max(1e-9, rep.LenTotal);
            Console.WriteLine($"boundary: tol={rep.SeamTolerance:F2} total_edge_length={rep.LenTotal:F0} yalms");
            Console.WriteLine($"boundary:   seam      {rep.LenSeam,12:F0} ({100.0 * rep.LenSeam / t:F2}%) " +
                              $"of which cross-key {rep.LenSeamCrossKey:F0} " +
                              $"({100.0 * rep.LenSeamCrossKey / Math.Max(1e-9, rep.LenSeam):F2}%)");
            Console.WriteLine($"boundary:   wall      {rep.LenWall,12:F0} ({100.0 * rep.LenWall / t:F2}%)  BLOCKING");
            Console.WriteLine($"boundary:   ambiguous {rep.LenAmbiguous,12:F0} ({100.0 * rep.LenAmbiguous / t:F2}%)  BLOCKING");
            Console.WriteLine($"boundary:   true_open {rep.LenOpen,12:F0} ({100.0 * rep.LenOpen / t:F2}%)  BLOCKING");

            double o = Math.Max(1e-9, rep.OpenLenTotal);
            Console.WriteLine("boundary: --- restricted to the population the old pass called open ---");
            Console.WriteLine($"boundary:   open_key_length={rep.OpenLenTotal:F0} yalms");
            Console.WriteLine($"boundary:   stitched  {rep.OpenLenSeam,12:F0} ({100.0 * rep.OpenLenSeam / o:F2}%) " +
                              $"cross-key {rep.OpenLenSeamCrossKey:F0}");
            Console.WriteLine($"boundary:   wall      {rep.OpenLenWall,12:F0} ({100.0 * rep.OpenLenWall / o:F2}%)");
            Console.WriteLine($"boundary:   ambiguous {rep.OpenLenAmbiguous,12:F0} ({100.0 * rep.OpenLenAmbiguous / o:F2}%)");
            Console.WriteLine($"boundary:   true_open {rep.OpenLenOpen,12:F0} ({100.0 * rep.OpenLenOpen / o:F2}%)");

            double gapTotal = Math.Max(1e-9, rep.GapSubWeld + rep.GapNarrow + rep.GapWide);
            Console.WriteLine($"boundary: true_open runs: sub_weld={rep.GapSubWeld:F0} ({rep.GapSubWeldRuns}) " +
                              $"narrow<0.25={rep.GapNarrow:F0} ({rep.GapNarrowRuns}) " +
                              $"wide>=0.25={rep.GapWide:F0} ({rep.GapWideRuns}) " +
                              $"sliver_share={100.0 * rep.GapSubWeld / gapTotal:F2}%");
            Console.WriteLine($"boundary: blocking_segments={rep.Blocking.Count} " +
                              $"candidates={rep.CandidatesTested} rejected_same_side={rep.RejectedSameSide} " +
                              $"rejected_height={rep.RejectedHeight} rejected_gap={rep.RejectedGap} " +
                              $"degenerate={rep.DegenerateEdges}");
            Console.WriteLine($"boundary: side test audit -- agree={rep.SideAgree} " +
                              $"centroid_only={rep.SideCentroidOnly} geom_only={rep.SideGeomOnly} " +
                              $"(geom_only is what the centroid proxy was dropping)");
            Console.WriteLine($"boundary: side test disagreement covers {rep.SideDisagreeLen:F0} yalms " +
                              $"of unique boundary; of that, finally called true_open " +
                              $"{rep.SideDisagreeOpen:F0} and ambiguous {rep.SideDisagreeAmbiguous:F0}");
            Console.WriteLine($"boundary: gap-connection candidates: {rep.GapCandidates.Count} stretches, " +
                              $"{rep.GapCandidateLen:F0} yalms -- blocked only by the accept cap, " +
                              $"compatible in height and grade at their own measured gap");

            // The census. Rows: how far the nearest standable surface across the
            // boundary is. Columns: how far above or below it stands. A cliff lip
            // lands bottom-right or in "nothing"; a model seam we refused lands
            // top-left. Erosion cannot tell them apart, so this has to be looked
            // at before anyone pays for it.
            double steepTotal = 0.0, floorTotal = 0.0;
            for (int g = 0; g < CensusGapBuckets; g++)
                for (int d = 0; d < CensusDyBuckets; d++)
                { steepTotal += rep.CensusSteep[g, d]; floorTotal += rep.CensusFloor[g, d]; }
            double censusTotal = Math.Max(1e-9, rep.CensusVoid + steepTotal + floorTotal);

            void Table(string title, double[,] cells, double sum)
            {
                Console.WriteLine($"boundary: {title} -- {sum:F0} yalms " +
                                  $"({100.0 * sum / censusTotal:F2}% of true_open)");
                Console.Write("boundary:   gap \\ dy  ");
                for (int d = 0; d < CensusDyBuckets; d++) Console.Write($"{CensusDyLabel[d],10}");
                Console.WriteLine();
                for (int g = 0; g < CensusGapBuckets; g++)
                {
                    Console.Write($"boundary:   {CensusGapLabel[g],-9}");
                    for (int d = 0; d < CensusDyBuckets; d++) Console.Write($"{cells[g, d],10:F0}");
                    Console.WriteLine();
                }
            }

            Console.WriteLine("boundary: census of true_open -- what stands across it (yalms of boundary)");
            Table("across it: a STEEP face (a cliff, correctly blocked)", rep.CensusSteep, steepTotal);
            Table("across it: a standable floor we REFUSED (this is the actionable one)",
                  rep.CensusFloor, floorTotal);
            Console.WriteLine($"boundary:   nothing across it at all: {rep.CensusVoid:F0} " +
                              $"({100.0 * rep.CensusVoid / censusTotal:F2}% of true_open)");
        }

        // The gate. A classification is worth nothing unless it agrees with where
        // the player has actually been, so put it against the recorded survey: a
        // blocking boundary lying across a step somebody really took is a
        // misclassification, not a discovery. Two consecutive samples in one
        // recording are a stride the player physically walked.
        //
        // Long strides are reported apart rather than counted against it. The
        // survey samples on a timer, so a long gap between samples draws a
        // straight line through ground the player actually curved around, and a
        // crossing under it says nothing about the classifier.
        private static void GateBoundariesAgainstSurvey(string surveyPath, BoundaryReport rep,
                                                        int zoneId, Options opt)
        {
            if (string.IsNullOrEmpty(surveyPath) || !File.Exists(surveyPath)) return;

            const double Cell = 4.0;
            var grid = new Dictionary<(int, int), List<int>>(100_000);
            for (int i = 0; i < rep.Blocking.Count; i++)
            {
                var b = rep.Blocking[i];
                int x0 = (int)Math.Floor(Math.Min(b.AX, b.BX) / Cell), x1 = (int)Math.Floor(Math.Max(b.AX, b.BX) / Cell);
                int z0 = (int)Math.Floor(Math.Min(b.AZ, b.BZ) / Cell), z1 = (int)Math.Floor(Math.Max(b.AZ, b.BZ) / Cell);
                for (int gz = z0; gz <= z1; gz++)
                for (int gx = x0; gx <= x1; gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) grid[(gx, gz)] = l = new List<int>(4);
                    l.Add(i);
                }
            }

            const double ShortStride = 3.0;    // one walking step between samples
            // A boundary belonging to another floor -- under a slope, over a
            // ledge -- is not this stride's problem. Compare at the CROSSING
            // point, not at segment midpoints: a 4-yalm boundary sloping through
            // the player's height has a midpoint a yalm away from where they
            // actually walked over it, and at 1.5 that let a boundary 1.39 below
            // the player count against the classifier.
            const double LayerTol = 0.75;
            // The same question asked strictly. The collision frame was verified
            // against 40 walked samples at 0.04 mean error, so a player really
            // standing on a surface matches it far closer than 0.75; anything
            // between the two tolerances is a boundary belonging to a ledge above
            // or below the player's own footing, not one they walked through.
            // Both are printed because picking whichever flatters the classifier
            // is exactly the failure this whole exercise is correcting.
            const double LayerTolStrict = 0.25;
            int strides = 0, walkStrides = 0, longStrides = 0, fallStrides = 0;
            var crossed = new int[4];
            var crossedStrict = new int[4];
            var crossedLong = new int[4];
            var byCause = new int[3];              // AcrossKind
            var byCauseStrict = new int[3];
            int steepJustOver = 0;                 // far side is steep, but only just
            double worstJustOver = 0.0;
            var examples = new List<string>(10);
            int verifiedGap = 0;
            var verifiedGapLines = new List<string>(12);

            string prevSurvey = ""; int prevSeq = -999;
            double px = 0, pz = 0, py = 0; bool havePrev = false;

            foreach (var line in File.ReadLines(surveyPath))
            {
                var f = line.Split('\t');
                if (f.Length < 7 || f[0] == "survey_id") continue;
                if (!int.TryParse(f[1], out int z) || z != zoneId) { havePrev = false; continue; }
                if (!int.TryParse(f[3], out int seq)) continue;
                if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double x)) continue;
                if (!double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out double zz)) continue;
                if (!double.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out double y)) continue;

                if (havePrev && f[0] == prevSurvey && seq == prevSeq + 1)
                {
                    strides++;
                    double sl = Math.Sqrt((x - px) * (x - px) + (zz - pz) * (zz - pz));
                    // A stride only counts against the classifier if it was a
                    // WALK. Two other things live in this file: a long gap
                    // between timed samples, which draws a straight line through
                    // ground the player curved around, and a descent steeper than
                    // the policy allows, which is a fall or a slide. Recording
                    // 20260712-170700 seq 197 drops 5.09 yalms over 2.93 -- a
                    // true-open boundary across THAT is a cliff lip found
                    // correctly, and counting it as a defect would have pushed
                    // the classifier toward bridging real cliffs.
                    double sdy = y - py;   // y is DOWN: positive means the player went down
                    double allowed = sdy > 0.0
                        ? Math.Max(opt.MaxStepDown, sl * opt.MaxDownGrade)
                        : Math.Max(opt.MaxStepUp, sl * opt.MaxUpGrade);
                    bool isLong = sl > ShortStride;
                    bool isFall = !isLong && Math.Abs(sdy) > allowed;
                    bool isShort = !isLong && !isFall;
                    if (isShort) walkStrides++; else if (isLong) longStrides++; else fallStrides++;

                    var hit = new bool[4];
                    var hitStrict = new bool[4];
                    int cx0 = (int)Math.Floor(Math.Min(px, x) / Cell), cx1 = (int)Math.Floor(Math.Max(px, x) / Cell);
                    int cz0 = (int)Math.Floor(Math.Min(pz, zz) / Cell), cz1 = (int)Math.Floor(Math.Max(pz, zz) / Cell);
                    for (int gz = cz0; gz <= cz1; gz++)
                    for (int gx = cx0; gx <= cx1; gx++)
                    {
                        if (!grid.TryGetValue((gx, gz), out var l)) continue;
                        foreach (int bi in l)
                        {
                            var b = rep.Blocking[bi];
                            if (!SegmentsCross(px, pz, x, zz, b.AX, b.AZ, b.BX, b.BZ,
                                               out double su, out double bt)) continue;
                            double bcy = b.AY + (b.BY - b.AY) * bt;   // boundary height where it was crossed
                            double scy = py + (y - py) * su;          // player height there
                            double layer = Math.Abs(bcy - scy);
                            if (layer > LayerTol) continue;
                            hit[(int)b.Kind] = true;
                            bool strict = layer <= LayerTolStrict;
                            if (strict) hitStrict[(int)b.Kind] = true;
                            if (isShort)
                            {
                                byCause[(int)b.Across]++;
                                if (strict) byCauseStrict[(int)b.Across]++;
                                if (b.Across == AcrossKind.Steep && b.AcrossSlope <= opt.MaxSlopeDeg + 10.0)
                                {
                                    steepJustOver++;
                                    if (b.AcrossSlope > worstJustOver) worstJustOver = b.AcrossSlope;
                                }
                            }
                            if (isShort && examples.Count < 10)
                                examples.Add($"gate:   {b.Kind}/{b.Across} across stride {f[0]} seq {seq}: " +
                                             $"({px:F1},{pz:F1},{py:F2}) -> ({x:F1},{zz:F1},{y:F2}) " +
                                             $"crossed at ({px + (x - px) * su:F2},{pz + (zz - pz) * su:F2}) " +
                                             $"boundary y={bcy:F2} player y={scy:F2} " +
                                             $"far side gap={b.AcrossGap:F2} dy={b.AcrossDy:F2} slope={b.AcrossSlope:F1}");
                        }
                    }
                    for (int c = 0; c < 4; c++)
                    {
                        if (hit[c]) { if (isShort) crossed[c]++; else crossedLong[c]++; }
                        if (hitStrict[c] && isShort) crossedStrict[c]++;
                    }

                    // A gap-connection candidate the player demonstrably walked
                    // over. These stay BLOCKED -- walking one is evidence about
                    // that spot, not a licence to stitch every gap of that width
                    // -- but they are the shortlist for modelling capsule
                    // bridging properly, so they get named rather than counted.
                    if (isShort)
                    {
                        for (int gi = 0; gi < rep.GapCandidates.Count; gi++)
                        {
                            var g = rep.GapCandidates[gi];
                            if (Math.Min(px, x) - 2.0 > Math.Max(g.AX, g.BX)) continue;
                            if (Math.Max(px, x) + 2.0 < Math.Min(g.AX, g.BX)) continue;
                            if (Math.Min(pz, zz) - 2.0 > Math.Max(g.AZ, g.BZ)) continue;
                            if (Math.Max(pz, zz) + 2.0 < Math.Min(g.AZ, g.BZ)) continue;
                            if (!SegmentsCross(px, pz, x, zz, g.AX, g.AZ, g.BX, g.BZ,
                                               out double gu, out double gt)) continue;
                            double gcy = g.AY + (g.BY - g.AY) * gt;
                            if (Math.Abs(gcy - (py + (y - py) * gu)) > LayerTolStrict) continue;
                            verifiedGap++;
                            if (verifiedGapLines.Count < 12)
                                verifiedGapLines.Add(
                                    $"gate:   verified_gap_connection: {f[0]} seq {seq} walked over " +
                                    $"({px + (x - px) * gu:F2},{pz + (zz - pz) * gu:F2}) " +
                                    $"gap={g.AcrossGap:F2} dy={g.AcrossDy:F2} y={gcy:F2}");
                        }
                    }
                }

                prevSurvey = f[0]; prevSeq = seq; px = x; pz = zz; py = y; havePrev = true;
            }

            int bad = crossed[(int)BoundaryKind.Wall] + crossed[(int)BoundaryKind.TrueOpen]
                    + crossed[(int)BoundaryKind.Ambiguous];
            Console.WriteLine($"gate: strides={strides} walked={walkStrides} " +
                              $"long(> {ShortStride:F1})={longStrides} fell_or_slid={fallStrides}");
            Console.WriteLine($"gate: WALKED strides crossing a blocking boundary: " +
                              $"wall={crossed[(int)BoundaryKind.Wall]} " +
                              $"true_open={crossed[(int)BoundaryKind.TrueOpen]} " +
                              $"ambiguous={crossed[(int)BoundaryKind.Ambiguous]} " +
                              $"-> {bad} ({100.0 * bad / Math.Max(1, walkStrides):F2}% of walked strides)");
            // The decomposition that matters. Only RefusedFloor is this
            // classifier being wrong; Steep is the standing-slope threshold being
            // conservative, and Nothing is the survey or the collision data
            // disagreeing about where the ground is.
            Console.WriteLine($"gate: what was across those boundaries: " +
                              $"refused_floor={byCause[(int)AcrossKind.RefusedFloor]} " +
                              $"steep_face={byCause[(int)AcrossKind.Steep]} " +
                              $"(of which within 10 deg of the standing limit: {steepJustOver}, " +
                              $"steepest {worstJustOver:F1} deg) " +
                              $"nothing_at_all={byCause[(int)AcrossKind.Nothing]}");
            int badStrict = crossedStrict[(int)BoundaryKind.Wall] + crossedStrict[(int)BoundaryKind.TrueOpen]
                          + crossedStrict[(int)BoundaryKind.Ambiguous];
            Console.WriteLine($"gate: same, counting only boundaries within {LayerTolStrict:F2} of the " +
                              $"player's own footing: wall={crossedStrict[(int)BoundaryKind.Wall]} " +
                              $"true_open={crossedStrict[(int)BoundaryKind.TrueOpen]} " +
                              $"ambiguous={crossedStrict[(int)BoundaryKind.Ambiguous]} " +
                              $"-> {badStrict} ({100.0 * badStrict / Math.Max(1, walkStrides):F2}%) " +
                              $"refused_floor={byCauseStrict[(int)AcrossKind.RefusedFloor]} " +
                              $"steep_face={byCauseStrict[(int)AcrossKind.Steep]} " +
                              $"nothing_at_all={byCauseStrict[(int)AcrossKind.Nothing]}");
            Console.WriteLine($"gate: long strides (diagnostic only -- straight lines through curved walking): " +
                              $"wall={crossedLong[(int)BoundaryKind.Wall]} " +
                              $"true_open={crossedLong[(int)BoundaryKind.TrueOpen]} " +
                              $"ambiguous={crossedLong[(int)BoundaryKind.Ambiguous]}");
            Console.WriteLine($"gate: verified_gap_connection crossings on walked strides: {verifiedGap}");
            foreach (var s in verifiedGapLines) Console.WriteLine(s);
            foreach (var e in examples) Console.WriteLine(e);
        }

        // How close does the player's CENTRE actually get to a wall?
        //
        // This is the one measurement that can choose a body radius on evidence
        // rather than on precedent. 0.70 is what the Recast bake was given; 0.40
        // is what the native DAT sweep uses. Neither has been calibrated against
        // the game's own collision, so quoting either as "the" body radius is a
        // guess wearing a decimal point. But the player's recorded positions are
        // places the game PERMITTED the body to be, so the smallest distance from
        // a recorded position to a wall is an upper bound on the real radius --
        // measured, not assumed.
        //
        // Walls and rims are reported apart because they are different physics.
        // You cannot put your centre inside a wall at any radius. You can stand
        // at the very lip of a drop, so a small rim distance proves nothing about
        // the body and would drag the estimate down if the two were mixed.
        private static void ReportAgentEnvelope(string surveyPath, BoundaryReport rep, int zoneId,
                                                List<Tri> tris, List<float> vx, List<float> vy,
                                                List<float> vz, Options opt)
        {
            if (string.IsNullOrEmpty(surveyPath) || !File.Exists(surveyPath)) return;

            const double Cell = 4.0;
            const double Search = 3.0;
            var grid = new Dictionary<(int, int), List<int>>(100_000);
            for (int i = 0; i < rep.Blocking.Count; i++)
            {
                var b = rep.Blocking[i];
                int x0 = (int)Math.Floor(Math.Min(b.AX, b.BX) / Cell), x1 = (int)Math.Floor(Math.Max(b.AX, b.BX) / Cell);
                int z0 = (int)Math.Floor(Math.Min(b.AZ, b.BZ) / Cell), z1 = (int)Math.Floor(Math.Max(b.AZ, b.BZ) / Cell);
                for (int gz = z0; gz <= z1; gz++)
                for (int gx = x0; gx <= x1; gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) grid[(gx, gz)] = l = new List<int>(4);
                    l.Add(i);
                }
            }

            var wallD = new List<double>(7000);
            var rimD = new List<double>(7000);
            var tallD = new List<double>(2000);
            int samples = 0;
            var closest = new List<(double D, string Line)>(64);

            foreach (var line in File.ReadLines(surveyPath))
            {
                var f = line.Split('\t');
                if (f.Length < 7 || f[0] == "survey_id") continue;
                if (!int.TryParse(f[1], out int z) || z != zoneId) continue;
                if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double px)) continue;
                if (!double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out double pz)) continue;
                if (!double.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out double py)) continue;
                samples++;

                double bestWall = double.MaxValue, bestRim = double.MaxValue, bestTall = double.MaxValue;
                int bestWallIdx = -1;
                int r0 = (int)Math.Floor((pz - Search) / Cell), r1 = (int)Math.Floor((pz + Search) / Cell);
                int c0 = (int)Math.Floor((px - Search) / Cell), c1 = (int)Math.Floor((px + Search) / Cell);
                for (int gz = r0; gz <= r1; gz++)
                for (int gx = c0; gx <= c1; gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) continue;
                    foreach (int bi in l)
                    {
                        var b = rep.Blocking[bi];
                        double d = PointSegDist(px, pz, b.AX, b.AZ, b.BX, b.BZ, out double t);
                        if (d > Search) continue;

                        // Is the player standing on the surface this boundary
                        // belongs to? Evaluate the OWNER's plane right where the
                        // player is, rather than comparing against the segment's
                        // own height with a slope-scaled fudge window: on a
                        // hillside the two differ by metres and the window has to
                        // grow until it swallows the floor below.
                        if (!PlaneY(tris[b.Owner], vx, vy, vz, px, pz, out double ownerY)) continue;
                        if (Math.Abs(ownerY - py) > opt.MaxStepDown) continue;

                        if (b.Kind == BoundaryKind.Wall)
                        {
                            // A wall that rises no more than a step above the
                            // player's footing is a step, and the player walks
                            // onto it. Counting one as a wall is how a recorded
                            // position ended up 0.005 from a "wall": it was the
                            // lip of a 0.50 riser they were standing on top of,
                            // and it read as a body with no radius at all.
                            double by = b.AY + (b.BY - b.AY) * t;
                            if (by < py - AgentHeight) continue;          // clears the head
                            if (by - b.WallRise >= py - opt.MaxStepUp) continue;   // a step, not a wall
                            if (d < bestWall) { bestWall = d; bestWallIdx = bi; }
                            // Kept apart because it is the only population that
                            // can settle the radius. Everything between a step
                            // and a body's height is a kerb or a low ledge: the
                            // player walks right up against those, and whether
                            // one stops a body depends on the game's own step-up
                            // handling, which nobody here has measured. A wall
                            // taller than the body has no such doubt -- you
                            // cannot be inside it at any radius -- so the closest
                            // a recorded position ever came to ONE OF THOSE is a
                            // hard upper bound and the rest is inference.
                            if (b.WallRise >= AgentHeight && d < bestTall) bestTall = d;
                        }
                        else if (d < bestRim) bestRim = d;
                    }
                }
                if (bestWall < double.MaxValue)
                {
                    wallD.Add(bestWall);
                    // Keep the whole shortlist, not just the record holder. These
                    // are the counterexamples that decide the radius -- every one
                    // of them is either a place a body that wide could not have
                    // been, or a wall we got wrong -- and they have to be
                    // inspectable one at a time, not summarised.
                    if (bestWall < 0.80 && bestWallIdx >= 0)
                    {
                        var b = rep.Blocking[bestWallIdx];
                        closest.Add((bestWall,
                            $"envelope:   {bestWall:F3}  at ({px:F2},{pz:F2},{py:F2}) " +
                            $"survey {f[0]} seq {f[3]}  wall ({b.AX:F2},{b.AZ:F2})-({b.BX:F2},{b.BZ:F2}) " +
                            $"y={b.AY:F2}..{b.BY:F2} rise={b.WallRise:F2} owner_node={b.Owner}"));
                    }
                }
                if (bestRim < double.MaxValue) rimD.Add(bestRim);
                if (bestTall < double.MaxValue) tallD.Add(bestTall);
            }

            void Percentiles(string what, List<double> d)
            {
                if (d.Count == 0) { Console.WriteLine($"envelope: {what}: no samples in range"); return; }
                d.Sort();
                double P(double q) => d[Math.Min(d.Count - 1, (int)(q * d.Count))];
                Console.WriteLine($"envelope: {what}: n={d.Count} min={d[0]:F3} " +
                                  $"p01={P(0.01):F3} p05={P(0.05):F3} p10={P(0.10):F3} " +
                                  $"p50={P(0.50):F3} max={d[d.Count - 1]:F3}");
                foreach (double t in new[] { 0.30, 0.40, 0.50, 0.60, 0.70, 0.80 })
                {
                    int under = 0;
                    for (int i = 0; i < d.Count; i++) { if (d[i] < t) under++; else break; }
                    Console.WriteLine($"envelope:   samples closer than {t:F2}: {under} " +
                                      $"({100.0 * under / d.Count:F2}%)");
                }
            }

            Console.WriteLine($"envelope: zone-{zoneId} survey samples={samples}, " +
                              $"searched to {Search:F1} yalms, layer window = max(step, distance x tan {opt.MaxSlopeDeg:F0} deg)");
            Percentiles("distance from the player's centre to the nearest WALL", wallD);
            Percentiles($"distance to the nearest wall TALLER THAN THE BODY (rise >= {AgentHeight:F2}) -- the hard bound", tallD);
            Percentiles("distance from the player's centre to the nearest RIM (proves nothing about the body)", rimD);
            closest.Sort((a, b) => a.D.CompareTo(b.D));
            Console.WriteLine($"envelope: every recorded position within 0.80 of a wall ({closest.Count} of them):");
            for (int i = 0; i < Math.Min(24, closest.Count); i++) Console.WriteLine(closest[i].Line);
        }

        // Surface height of a standable face at an XZ point, from its plane.
        // Game space. A standable face is never near-vertical, so the divide is
        // safe -- but check rather than hand back a number nobody can trust.
        private static bool PlaneY(in Tri t, List<float> vx, List<float> vy, List<float> vz,
                                   double px, double pz, out double y)
        {
            double axg = vx[t.A], ayg = -vy[t.A], azg = -vz[t.A];
            double e1x = vx[t.B] - axg, e1y = -vy[t.B] - ayg, e1z = -vz[t.B] - azg;
            double e2x = vx[t.C] - axg, e2y = -vy[t.C] - ayg, e2z = -vz[t.C] - azg;
            double nx = e1y * e2z - e1z * e2y;
            double ny = e1z * e2x - e1x * e2z;
            double nz = e1x * e2y - e1y * e2x;
            if (Math.Abs(ny) < 1e-9) { y = 0.0; return false; }
            y = ayg - (nx * (px - axg) + nz * (pz - azg)) / ny;
            return true;
        }

        // Smallest distance between a convex polygon and a segment, in XZ.
        //
        // A vertex-only check cannot do this. Two cases defeat it and both occur
        // here: a segment can cross a cell edge with every cell vertex outside
        // the forbidden region, and a segment can lie wholly inside a cell, where
        // the nearest vertex is far away and the true distance is zero. Either
        // one leaves a body standing inside a wall while the check reports
        // nothing wrong.
        //
        // Touching anywhere means zero. Otherwise the minimum for two convex sets
        // is attained at a vertex of one against an edge of the other, so both
        // directions have to be tried.
        private static double PolySegDistance(List<(double X, double Z)> poly,
                                              double ax, double az, double bx, double bz)
        {
            int n = poly.Count;
            if (n == 0) return double.MaxValue;
            if (PointInConvex(poly, ax, az) || PointInConvex(poly, bx, bz)) return 0.0;
            for (int i = 0; i < n; i++)
            {
                var p = poly[i];
                var q = poly[(i + 1) % n];
                if (SegmentsCross(ax, az, bx, bz, p.X, p.Z, q.X, q.Z, out _, out _)) return 0.0;
            }
            double best = double.MaxValue;
            for (int i = 0; i < n; i++)
            {
                var p = poly[i];
                var q = poly[(i + 1) % n];
                best = Math.Min(best, PointSegDist(p.X, p.Z, ax, az, bx, bz, out _));
                best = Math.Min(best, PointSegDist(ax, az, p.X, p.Z, q.X, q.Z, out _));
                best = Math.Min(best, PointSegDist(bx, bz, p.X, p.Z, q.X, q.Z, out _));
            }
            return best;
        }

        // Counter-clockwise convex polygon: inside means never to the right of an
        // edge. Boundary counts as inside.
        private static bool PointInConvex(List<(double X, double Z)> poly, double px, double pz)
        {
            int n = poly.Count;
            if (n < 3) return false;
            for (int i = 0; i < n; i++)
            {
                var a = poly[i];
                var b = poly[(i + 1) % n];
                if (Cross2(a.X, a.Z, b.X, b.Z, px, pz) < -1e-12) return false;
            }
            return true;
        }

        // Which side of line AB does P fall on, and by how much (twice the
        // signed triangle area). Positive is to the left.
        private static double Cross2(double ax, double az, double bx, double bz,
                                     double px, double pz)
            => (bx - ax) * (pz - az) - (bz - az) * (px - ax);

        private static double PointSegDist(double px, double pz, double ax, double az,
                                           double bx, double bz, out double t)
        {
            double dx = bx - ax, dz = bz - az;
            double len2 = dx * dx + dz * dz;
            t = len2 > 1e-12 ? Math.Clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0.0, 1.0) : 0.0;
            double qx = px - (ax + t * dx), qz = pz - (az + t * dz);
            return Math.Sqrt(qx * qx + qz * qz);
        }

        // Do segments AB and CD cross, and if so where along each? u runs along
        // AB, t along CD, so the caller can ask what height each was at right
        // where they met rather than at a midpoint that may be nowhere near.
        private static bool SegmentsCross(double ax, double az, double bx, double bz,
                                          double cx, double cz, double dx, double dz,
                                          out double u, out double t)
        {
            u = 0.0; t = 0.0;
            double rx = bx - ax, rz = bz - az;
            double sx = dx - cx, sz = dz - cz;
            double denom = rx * sz - rz * sx;
            if (Math.Abs(denom) < 1e-12) return false;   // parallel or degenerate
            double qpx = cx - ax, qpz = cz - az;
            u = (qpx * sz - qpz * sx) / denom;
            t = (qpx * rz - qpz * rx) / denom;
            return u > 0.0 && u < 1.0 && t > 0.0 && t < 1.0;
        }

        // ---------------------------------------------------------------
        // Stage 2: agent-radius erosion that PROPAGATES.
        //
        // The pass this replaces clipped each triangle against only its OWN
        // blocking edges. That is a local operation and it under-erodes: a
        // triangle carrying no blocking edge of its own was never clipped at
        // all, however close it sat to a wall belonging to the neighbour that
        // had just eroded away. The tell was that no eroded cell ever gained a
        // vertex -- almost every cell was clipped zero or one times -- and its
        // area-retained figure was optimistic and has been withdrawn.
        //
        // The fix is not a bigger clip. It is to stop asking "what does this
        // triangle border on" and start asking "what is within a body radius of
        // this triangle, from anywhere". Every blocking interval stage 1 emitted
        // is a candidate, whoever owns it.
        //
        // Why no grid. Recast propagates a distance field across a compact
        // heightfield because its input is rasterised spans and it has no
        // segments to measure against. We do have segments, and the quantity
        // wanted -- horizontal X/Z clearance, not graph distance and not distance
        // measured over a slope -- is exactly the straight-line distance to the
        // nearest blocking segment in the same layer. That is a direct query.
        // Recast's chamfer sweep is an efficient way to compute it on a grid,
        // not a different definition, and doing it directly costs no quantization
        // error at all rather than an error we would then have to round the safe
        // way. La Theine at a 0.2-yalm cell would be 73 million columns, which a
        // 32-bit builder cannot hold in any case.
        //
        // The one approximation is deliberate and one-directional. The forbidden
        // region around a segment is a stadium -- a rectangle with a half-disc at
        // each end -- which is not a polygon. Each is replaced by the convex
        // polygon that CIRCUMSCRIBES it, so the forbidden region is always at
        // least the true one and never less. At K=8 that costs at most
        // r*(sec(pi/8)-1) = 0.057 yalms of over-erosion at a corner, and errs
        // toward keeping the player away from walls rather than toward them.
        //
        // Walls and rims get separate radii on purpose. You cannot put your
        // centre inside a wall at any radius; you CAN stand at the lip of a drop,
        // and the game lets you. Eroding both by the same number would either
        // admit walls or delete clifftops, and the survey can tell them apart.
        // Ambiguous intervals erode at the wall radius: unknown stays blocked.
        // ---------------------------------------------------------------

        private sealed class ErosionOutput
        {
            public List<float> VX = new List<float>(2_000_000);
            public List<float> VZ = new List<float>(2_000_000);
            public List<int> CellStart = new List<int>(300_000) { 0 };
            public List<int> CellSource = new List<int>(300_000);

            public double RadiusWall, RadiusRim;
            public double AreaBefore, AreaAfter, AreaPruned;
            public int Untouched, Shrunk, SplitCells, Destroyed;
            public int MaxPieces, PieceCapHits;
            public long PrunedPieces, TotalVerts;
            public long ObstaclesApplied, ObstaclesLayerRejected;
        }

        // A regular K-gon circumscribing a disc of radius r, swept along a
        // segment. Convex, and it contains the stadium it stands in for.
        private const int ErosionFacets = 8;

        private static void ObstacleFor(double ax, double az, double bx, double bz, double r,
                                        List<(double X, double Z)> outPoly)
        {
            outPoly.Clear();
            double R = r / Math.Cos(Math.PI / ErosionFacets);
            double dx = bx - ax, dz = bz - az;
            double len = Math.Sqrt(dx * dx + dz * dz);
            double ux, uz;
            if (len < 1e-9) { ux = 1.0; uz = 0.0; } else { ux = dx / len; uz = dz / len; }
            // Aligned so one facet normal lies along the segment and one across
            // it, which keeps the flat sides flush with the wall.
            var pts = new (double X, double Z)[ErosionFacets * 2];
            for (int j = 0; j < ErosionFacets; j++)
            {
                double phi = Math.PI / ErosionFacets + 2.0 * Math.PI * j / ErosionFacets;
                double c = Math.Cos(phi) * R, s = Math.Sin(phi) * R;
                double ox = ux * c - uz * s, oz = uz * c + ux * s;
                pts[j] = (ax + ox, az + oz);
                pts[ErosionFacets + j] = (bx + ox, bz + oz);
            }
            ConvexHull(pts, outPoly);
        }

        // Andrew's monotone chain, counter-clockwise, no collinear points.
        private static void ConvexHull((double X, double Z)[] pts, List<(double X, double Z)> hull)
        {
            Array.Sort(pts, (p, q) => p.X != q.X ? p.X.CompareTo(q.X) : p.Z.CompareTo(q.Z));
            var tmp = new (double X, double Z)[pts.Length * 2];
            int k = 0;
            for (int i = 0; i < pts.Length; i++)
            {
                while (k >= 2 && Cross2(tmp[k - 2].X, tmp[k - 2].Z, tmp[k - 1].X, tmp[k - 1].Z,
                                        pts[i].X, pts[i].Z) <= 1e-12) k--;
                tmp[k++] = pts[i];
            }
            for (int i = pts.Length - 2, t = k + 1; i >= 0; i--)
            {
                while (k >= t && Cross2(tmp[k - 2].X, tmp[k - 2].Z, tmp[k - 1].X, tmp[k - 1].Z,
                                        pts[i].X, pts[i].Z) <= 1e-12) k--;
                tmp[k++] = pts[i];
            }
            hull.Clear();
            for (int i = 0; i < k - 1; i++) hull.Add(tmp[i]);
        }

        // P \ O for convex P and convex CCW O, appended to `into` as convex
        // pieces. Peel one half-plane of O at a time: what falls outside that
        // half-plane is outside O for good, and what is left is still in the
        // running. Whatever survives every half-plane is inside O and is dropped.
        private static void SubtractConvex(List<(double X, double Z)> p,
                                           List<(double X, double Z)> o,
                                           List<List<(double X, double Z)>> into,
                                           double minArea)
        {
            var cur = new List<(double X, double Z)>(p);
            for (int i = 0; i < o.Count; i++)
            {
                var a = o[i];
                var b = o[(i + 1) % o.Count];
                double ex = b.X - a.X, ez = b.Z - a.Z;
                double len = Math.Sqrt(ex * ex + ez * ez);
                if (len < 1e-12) continue;
                // CCW winding: the interior lies to the LEFT of a->b.
                double inx = -ez / len, inz = ex / len;

                var outside = ClipHalfPlane(cur, a.X, a.Z, -inx, -inz, 0.0);
                if (PolyArea(outside) > minArea) into.Add(outside);

                cur = ClipHalfPlane(cur, a.X, a.Z, inx, inz, 0.0);
                if (cur.Count < 3) return;
            }
        }

        private static ErosionOutput Erode(List<Tri> tris, List<float> vx, List<float> vy, List<float> vz,
                                           BoundaryReport boundary, double radiusWall, double radiusRim,
                                           Options opt)
        {
            var outp = new ErosionOutput { RadiusWall = radiusWall, RadiusRim = radiusRim };
            double rMax = Math.Max(radiusWall, radiusRim);
            const double MinArea = 0.01;      // a piece smaller than a hand span; dropping is conservative
            // A backstop against a pathological face, not a working limit. At 64
            // it bound three faces in the zone and discarded 0.06 square yalms --
            // immaterial, but it made the difference between a measurement and a
            // measurement with an asterisk.
            const int PieceCap = 512;

            // Bucket the blocking segments so each triangle only meets its own
            // neighbourhood.
            const double Cell = 4.0;
            var grid = new Dictionary<(int, int), List<int>>(150_000);
            for (int i = 0; i < boundary.Blocking.Count; i++)
            {
                var b = boundary.Blocking[i];
                int x0 = (int)Math.Floor((Math.Min(b.AX, b.BX) - rMax) / Cell);
                int x1 = (int)Math.Floor((Math.Max(b.AX, b.BX) + rMax) / Cell);
                int z0 = (int)Math.Floor((Math.Min(b.AZ, b.BZ) - rMax) / Cell);
                int z1 = (int)Math.Floor((Math.Max(b.AZ, b.BZ) + rMax) / Cell);
                for (int gz = z0; gz <= z1; gz++)
                for (int gx = x0; gx <= x1; gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) grid[(gx, gz)] = l = new List<int>(4);
                    l.Add(i);
                }
            }

            // Plane of every standable face, so "how high is this surface at that
            // point" is a multiply-add rather than a cross product per query.
            // Double, not float. These feed a layer test whose comparisons land
            // exactly on 0.50 and 1.80 all over this zone -- a wall whose base
            // sits precisely at head height, a rim precisely one step down -- and
            // at a tie the last bit decides. Held as float they disagreed with the
            // verifier's double arithmetic by an ulp and five cells kept ground
            // they should have lost.
            var planeNX = new double[tris.Count]; var planeNZ = new double[tris.Count];
            var planeD = new double[tris.Count]; var planeOK = new bool[tris.Count];
            for (int i = 0; i < tris.Count; i++)
            {
                var t = tris[i];
                double axg = vx[t.A], ayg = -vy[t.A], azg = -vz[t.A];
                double e1x = vx[t.B] - axg, e1y = -vy[t.B] - ayg, e1z = -vz[t.B] - azg;
                double e2x = vx[t.C] - axg, e2y = -vy[t.C] - ayg, e2z = -vz[t.C] - azg;
                double nx = e1y * e2z - e1z * e2y;
                double ny = e1z * e2x - e1x * e2z;
                double nz = e1x * e2y - e1y * e2x;
                if (Math.Abs(ny) < 1e-9) { planeOK[i] = false; continue; }
                planeOK[i] = true;
                planeNX[i] = -nx / ny;
                planeNZ[i] = -nz / ny;
                planeD[i] = ayg + (nx * axg + nz * azg) / ny;
            }

            var obstacle = new List<(double X, double Z)>(ErosionFacets * 2);
            var pieces = new List<List<(double X, double Z)>>(8);
            var next = new List<List<(double X, double Z)>>(8);
            var nearby = new List<int>(64);
            var seen = new HashSet<int>();

            for (int i = 0; i < tris.Count; i++)
            {
                var t = tris[i];
                var tri = new List<(double X, double Z)>(3)
                {
                    (vx[t.A], -vz[t.A]), (vx[t.B], -vz[t.B]), (vx[t.C], -vz[t.C]),
                };
                // Counter-clockwise, so the clipper's sense of "inside" holds.
                if (SignedArea(tri) < 0.0) tri.Reverse();
                double area0 = PolyArea(tri);
                outp.AreaBefore += area0;
                // CellStart must stay one longer than CellSource. Pushing a start
                // here without a matching source would slide every later cell's
                // vertex range by one, silently.
                if (area0 <= 1e-12) { outp.Destroyed++; continue; }

                double minX = Math.Min(tri[0].X, Math.Min(tri[1].X, tri[2].X)) - rMax;
                double maxX = Math.Max(tri[0].X, Math.Max(tri[1].X, tri[2].X)) + rMax;
                double minZ = Math.Min(tri[0].Z, Math.Min(tri[1].Z, tri[2].Z)) - rMax;
                double maxZ = Math.Max(tri[0].Z, Math.Max(tri[1].Z, tri[2].Z)) + rMax;

                nearby.Clear(); seen.Clear();
                for (int gz = (int)Math.Floor(minZ / Cell); gz <= (int)Math.Floor(maxZ / Cell); gz++)
                for (int gx = (int)Math.Floor(minX / Cell); gx <= (int)Math.Floor(maxX / Cell); gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) continue;
                    foreach (int bi in l) if (seen.Add(bi)) nearby.Add(bi);
                }

                pieces.Clear(); pieces.Add(tri);
                bool touched = false;

                foreach (int bi in nearby)
                {
                    if (pieces.Count == 0) break;
                    var b = boundary.Blocking[bi];
                    double r = b.Kind == BoundaryKind.TrueOpen ? radiusRim : radiusWall;
                    if (r <= 0.0) continue;

                    // Does it stand in this triangle's layer? Compare the two
                    // surfaces at the SAME XZ point -- the point on the boundary
                    // nearest this triangle, with the triangle's own plane
                    // evaluated there. Comparing a boundary's height against a
                    // centroid's instead needs a slope-scaled fudge window to
                    // survive a hillside, and that window then admits the floor
                    // below on level ground. At a shared point no window is
                    // needed and the test is exact.
                    if (!planeOK[i]) { outp.ObstaclesLayerRejected++; continue; }

                    // Is it in this triangle's layer?
                    //
                    // The obstacle is applied to the whole triangle or not at
                    // all, so the question has to be "could this boundary
                    // constrain ANY point of this triangle", not "does it
                    // constrain one chosen point". Sampling cannot answer that:
                    // a test at the triangle's centroid gets the far end of a
                    // large triangle wrong, and a test on the boundary compares
                    // the boundary's height against the surface AT THE BOUNDARY
                    // when the body actually stands up to a radius away -- on a
                    // 45-degree slope that is 0.7 yalms of height.
                    //
                    // Both quantities are linear, so their ranges are exactly
                    // the extremes: the boundary's height over its two ends, and
                    // the surface's over the triangle's three corners. Interval
                    // arithmetic then answers it exactly, and where the ranges
                    // merely touch it errs toward eroding.
                    double byLo = Math.Min(b.AY, b.BY), byHi = Math.Max(b.AY, b.BY);
                    double tyLo = double.MaxValue, tyHi = double.MinValue;
                    foreach (var q in tri)
                    {
                        double ty = planeNX[i] * q.X + planeNZ[i] * q.Z + planeD[i];
                        if (ty < tyLo) tyLo = ty;
                        if (ty > tyHi) tyHi = ty;
                    }

                    // A hair of slack, spent only on eroding MORE. These
                    // comparisons sit exactly on 0.50 and 1.80 constantly, and a
                    // tie decided the wrong way leaves a body standing in a wall
                    // while one decided the wrong way the other direction costs a
                    // sliver of floor. Those are not equal mistakes.
                    const double LayerEps = 1e-3;

                    bool inLayer;
                    if (b.Kind == BoundaryKind.Wall)
                    {
                        // A wall reaches UP from its base, and game y is DOWN, so
                        // its top is at by - WallRise. Two ways it is not this
                        // surface's problem: it clears the body's head entirely,
                        // or it rises no further above the surface than a step,
                        // in which case the player walks ONTO it. Skipping that
                        // second test is what put a recorded position 0.005 from
                        // a "wall" -- the lip of a 0.50 riser they stood on top of.
                        inLayer = byHi >= tyLo - AgentHeight - LayerEps
                               && byLo - b.WallRise < tyHi - opt.MaxStepUp + LayerEps;   // strict: see SelfTest
                    }
                    else
                    {
                        // A rim only matters at your own footing. Half a yalm off
                        // belongs to a different surface.
                        inLayer = byHi + opt.MaxStepDown >= tyLo - LayerEps
                               && byLo - opt.MaxStepDown <= tyHi + LayerEps;
                    }
                    if (!inLayer) { outp.ObstaclesLayerRejected++; continue; }

                    ObstacleFor(b.AX, b.AZ, b.BX, b.BZ, r, obstacle);
                    double obMinX = double.MaxValue, obMaxX = double.MinValue;
                    double obMinZ = double.MaxValue, obMaxZ = double.MinValue;
                    foreach (var q in obstacle)
                    {
                        if (q.X < obMinX) obMinX = q.X;
                        if (q.X > obMaxX) obMaxX = q.X;
                        if (q.Z < obMinZ) obMinZ = q.Z;
                        if (q.Z > obMaxZ) obMaxZ = q.Z;
                    }

                    next.Clear();
                    foreach (var pc in pieces)
                    {
                        double pMinX = double.MaxValue, pMaxX = double.MinValue;
                        double pMinZ = double.MaxValue, pMaxZ = double.MinValue;
                        foreach (var q in pc)
                        {
                            if (q.X < pMinX) pMinX = q.X;
                            if (q.X > pMaxX) pMaxX = q.X;
                            if (q.Z < pMinZ) pMinZ = q.Z;
                            if (q.Z > pMaxZ) pMaxZ = q.Z;
                        }
                        if (pMaxX < obMinX || pMinX > obMaxX || pMaxZ < obMinZ || pMinZ > obMaxZ)
                        { next.Add(pc); continue; }
                        touched = true;
                        SubtractConvex(pc, obstacle, next, MinArea);
                    }
                    outp.ObstaclesApplied++;

                    pieces.Clear();
                    if (next.Count > PieceCap)
                    {
                        // Keep the largest. Discarding walkable area is the safe
                        // direction, and this is counted so it can never pass for
                        // "nothing was lost".
                        next.Sort((p2, q2) => PolyArea(q2).CompareTo(PolyArea(p2)));
                        outp.PieceCapHits++;
                        for (int q3 = PieceCap; q3 < next.Count; q3++)
                        { outp.AreaPruned += PolyArea(next[q3]); outp.PrunedPieces++; }
                        next.RemoveRange(PieceCap, next.Count - PieceCap);
                    }
                    pieces.AddRange(next);
                }

                double after = 0.0;
                foreach (var pc in pieces) after += PolyArea(pc);
                outp.AreaAfter += after;

                if (!touched) outp.Untouched++;
                else if (pieces.Count == 0) outp.Destroyed++;
                else if (pieces.Count > 1) outp.SplitCells++;
                else outp.Shrunk++;
                if (pieces.Count > outp.MaxPieces) outp.MaxPieces = pieces.Count;

                foreach (var pc in pieces)
                {
                    foreach (var q in pc) { outp.VX.Add((float)q.X); outp.VZ.Add((float)q.Z); }
                    outp.CellStart.Add(outp.VX.Count);
                    outp.CellSource.Add(i);
                    outp.TotalVerts += pc.Count;
                }
            }

            return outp;
        }

        private static double SignedArea(List<(double X, double Z)> poly)
        {
            double a = 0.0;
            for (int i = 0; i < poly.Count; i++)
            {
                var p = poly[i];
                var q = poly[(i + 1) % poly.Count];
                a += p.X * q.Z - q.X * p.Z;
            }
            return a * 0.5;
        }

        private static void ReportErosion2(ErosionOutput e, List<Tri> tris)
        {
            Console.WriteLine($"erosion: wall_radius={e.RadiusWall:F2} rim_radius={e.RadiusRim:F2}");
            Console.WriteLine($"erosion: area_before={e.AreaBefore:F0} area_after={e.AreaAfter:F0} " +
                              $"retained={100.0 * e.AreaAfter / Math.Max(1e-9, e.AreaBefore):F2}%");
            Console.WriteLine($"erosion: source_faces={tris.Count} untouched={e.Untouched} " +
                              $"shrunk={e.Shrunk} split={e.SplitCells} destroyed={e.Destroyed} " +
                              $"({100.0 * e.Destroyed / Math.Max(1, tris.Count):F2}% of faces)");
            Console.WriteLine($"erosion: cells_out={e.CellSource.Count} vertices={e.TotalVerts} " +
                              $"max_pieces_per_face={e.MaxPieces} piece_cap_hits={e.PieceCapHits} " +
                              $"pruned_pieces={e.PrunedPieces} pruned_area={e.AreaPruned:F2}");
            Console.WriteLine($"erosion: obstacles_applied={e.ObstaclesApplied} " +
                              $"layer_rejected={e.ObstaclesLayerRejected}");
            Console.WriteLine($"erosion: storage_MiB={(e.CellSource.Count * 16.0 + e.TotalVerts * 8.0) / 1048576.0:F1}");
        }

        // Does the output actually satisfy the property it claims?
        //
        // Erosion is worth nothing if it merely reports a plausible percentage.
        // The claim is: no surviving cell holds a point nearer a blocking
        // boundary, in its own layer, than the radius. So check it -- on every
        // vertex of every cell, against every segment, with the SAME layer test
        // the erosion used. Because each forbidden region was replaced by a
        // polygon that circumscribes it, the true distance should come out at or
        // ABOVE the radius, never below. Anything below is a bug, not a rounding
        // artefact, and it would be a bug that walks a blind player into a wall.
        //
        // Three earlier acceptance scripts on this project produced three false
        // conclusions before anyone tested the real thing. This is that test.
        private static void VerifyErosion(ErosionOutput e, List<Tri> tris,
                                          List<float> vx, List<float> vy, List<float> vz,
                                          BoundaryReport boundary, Options opt)
        {
            const double Cell = 4.0;
            double rMax = Math.Max(e.RadiusWall, e.RadiusRim);
            if (rMax <= 0.0) { Console.WriteLine("verify: nothing eroded, nothing to check"); return; }

            var grid = new Dictionary<(int, int), List<int>>(150_000);
            for (int i = 0; i < boundary.Blocking.Count; i++)
            {
                var b = boundary.Blocking[i];
                int x0 = (int)Math.Floor((Math.Min(b.AX, b.BX) - rMax) / Cell);
                int x1 = (int)Math.Floor((Math.Max(b.AX, b.BX) + rMax) / Cell);
                int z0 = (int)Math.Floor((Math.Min(b.AZ, b.BZ) - rMax) / Cell);
                int z1 = (int)Math.Floor((Math.Max(b.AZ, b.BZ) + rMax) / Cell);
                for (int gz = z0; gz <= z1; gz++)
                for (int gx = x0; gx <= x1; gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) grid[(gx, gz)] = l = new List<int>(4);
                    l.Add(i);
                }
            }

            long checkedCells = 0, violations = 0;
            // A segment lands in several grid cells, so without a stamp one
            // violation is counted once per cell it touches.
            var seenSeg = new int[boundary.Blocking.Count];
            for (int i = 0; i < seenSeg.Length; i++) seenSeg[i] = -1;
            double worstWall = double.MaxValue, worstRim = double.MaxValue;
            var examples = new List<string>(6);
            var cell = new List<(double X, double Z)>(16);

            for (int c = 0; c < e.CellSource.Count; c++)
            {
                int src = e.CellSource[c];
                var t = tris[src];
                cell.Clear();
                double tyLo = double.MaxValue, tyHi = double.MinValue;
                double cMinX = double.MaxValue, cMaxX = double.MinValue;
                double cMinZ = double.MaxValue, cMaxZ = double.MinValue;
                bool ok = true;
                for (int v = e.CellStart[c]; v < e.CellStart[c + 1]; v++)
                {
                    double px = e.VX[v], pz = e.VZ[v];
                    cell.Add((px, pz));
                    if (!PlaneY(t, vx, vy, vz, px, pz, out double ty)) { ok = false; break; }
                    if (ty < tyLo) tyLo = ty;
                    if (ty > tyHi) tyHi = ty;
                    if (px < cMinX) cMinX = px;
                    if (px > cMaxX) cMaxX = px;
                    if (pz < cMinZ) cMinZ = pz;
                    if (pz > cMaxZ) cMaxZ = pz;
                }
                if (!ok || cell.Count < 3) continue;
                checkedCells++;

                for (int gz = (int)Math.Floor((cMinZ - rMax) / Cell); gz <= (int)Math.Floor((cMaxZ + rMax) / Cell); gz++)
                for (int gx = (int)Math.Floor((cMinX - rMax) / Cell); gx <= (int)Math.Floor((cMaxX + rMax) / Cell); gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) continue;
                    foreach (int bi in l)
                    {
                        if (seenSeg[bi] == c) continue;   // already judged for this cell
                        seenSeg[bi] = c;
                        var b = boundary.Blocking[bi];
                        double r = b.Kind == BoundaryKind.TrueOpen ? e.RadiusRim : e.RadiusWall;
                        if (r <= 0.0) continue;

                        double d = PolySegDistance(cell, b.AX, b.AZ, b.BX, b.BZ);
                        // A cell's boundary lies exactly ON the eroded frontier, so
                        // d == r is the expected case and not a failure. Cells are
                        // float32 and the zone runs to +-900 yalms, about 6e-5 of
                        // precision there, so anything inside 2e-4 is the storage
                        // format rather than the geometry.
                        if (d >= r - 2e-4) continue;

                        // Layer overlap, derived the other way round from the
                        // erosion's version so that one derivation checks the
                        // other rather than echoing it. Work in the DIFFERENCE
                        // (boundary height minus surface height), whose range over
                        // the cell and the segment is [byLo-tyHi, byHi-tyLo]
                        // because both vary linearly. Then each rule is a plain
                        // interval overlap.
                        //
                        //   wall: needs by-ty >= -AgentHeight (not over the head)
                        //         and  by-ty <= WallRise-MaxStepUp (not a step)
                        //   rim:  needs |by-ty| <= MaxStepDown
                        double byLo = Math.Min(b.AY, b.BY), byHi = Math.Max(b.AY, b.BY);
                        double dLo = byLo - tyHi, dHi = byHi - tyLo;
                        bool inLayer = b.Kind == BoundaryKind.Wall
                            ? dHi >= -AgentHeight && dLo < b.WallRise - opt.MaxStepUp
                            : dHi >= -opt.MaxStepDown && dLo <= opt.MaxStepDown;
                        if (!inLayer) continue;

                        if (b.Kind == BoundaryKind.Wall) { if (d < worstWall) worstWall = d; }
                        else if (d < worstRim) worstRim = d;
                        violations++;
                        if (examples.Count < 8)
                        {
                            // Say WHY. The erosion judges layer membership over
                            // the whole source triangle, which is a superset of
                            // this cell, so if it also says "in layer" then the
                            // obstacle should have been applied and the fault is
                            // in gathering or subtracting, not in the layer rule.
                            double sTyLo = double.MaxValue, sTyHi = double.MinValue;
                            foreach (int sv in new[] { t.A, t.B, t.C })
                            {
                                if (!PlaneY(t, vx, vy, vz, vx[sv], -vz[sv], out double sy)) continue;
                                if (sy < sTyLo) sTyLo = sy;
                                if (sy > sTyHi) sTyHi = sy;
                            }
                            double sLo = byLo - sTyHi, sHi = byHi - sTyLo;
                            bool srcInLayer = b.Kind == BoundaryKind.Wall
                                ? sHi >= -AgentHeight && sLo < b.WallRise - opt.MaxStepUp
                                : sHi >= -opt.MaxStepDown && sLo <= opt.MaxStepDown;
                            // Would the erosion's gather have even seen it? Same
                            // bounding boxes, same margins, recomputed here.
                            double fMinX = double.MaxValue, fMaxX = double.MinValue;
                            double fMinZ = double.MaxValue, fMaxZ = double.MinValue;
                            foreach (int sv in new[] { t.A, t.B, t.C })
                            {
                                double qx = vx[sv], qz = -vz[sv];
                                if (qx < fMinX) fMinX = qx;
                                if (qx > fMaxX) fMaxX = qx;
                                if (qz < fMinZ) fMinZ = qz;
                                if (qz > fMaxZ) fMaxZ = qz;
                            }
                            bool cellsOverlap =
                                (int)Math.Floor((fMinX - rMax) / Cell) <= (int)Math.Floor((Math.Max(b.AX, b.BX) + rMax) / Cell)
                             && (int)Math.Floor((fMaxX + rMax) / Cell) >= (int)Math.Floor((Math.Min(b.AX, b.BX) - rMax) / Cell)
                             && (int)Math.Floor((fMinZ - rMax) / Cell) <= (int)Math.Floor((Math.Max(b.AZ, b.BZ) + rMax) / Cell)
                             && (int)Math.Floor((fMaxZ + rMax) / Cell) >= (int)Math.Floor((Math.Min(b.AZ, b.BZ) - rMax) / Cell);
                            // And does the obstacle actually contain the offending
                            // part of the cell? If it does, the subtraction is at
                            // fault; if it does not, the obstacle is.
                            var ob = new List<(double X, double Z)>(ErosionFacets + 2);
                            ObstacleFor(b.AX, b.AZ, b.BX, b.BZ, r, ob);
                            int inside = 0;
                            foreach (var q in cell) if (PointInConvex(ob, q.X, q.Z)) inside++;

                            examples.Add($"verify:   cell {c} (face {src}, {cell.Count} corners) " +
                                         $"comes within {d:F4} of a {b.Kind} needing {r:F2} " +
                                         $"at ({b.AX:F2},{b.AZ:F2})-({b.BX:F2},{b.BZ:F2})  " +
                                         $"[dy cell {dLo:F2}..{dHi:F2} face {sLo:F2}..{sHi:F2}; " +
                                         $"erosion layer verdict {(srcInLayer ? "IN" : "OUT")}; " +
                                         $"gather would find it: {cellsOverlap}; " +
                                         $"cell corners inside the obstacle: {inside}/{cell.Count}]");
                            var sb = new System.Text.StringBuilder("verify:     cell poly");
                            foreach (var q in cell) sb.Append($" ({q.X:F4},{q.Z:F4})");
                            sb.Append("  obstacle");
                            foreach (var q in ob) sb.Append($" ({q.X:F4},{q.Z:F4})");
                            examples.Add(sb.ToString());
                        }
                    }
                }
            }

            Console.WriteLine($"verify: wall_r={e.RadiusWall:F2} rim_r={e.RadiusRim:F2} " +
                              $"cells_checked={checkedCells} violations={violations}" +
                              (violations == 0
                                  ? "  -- no cell comes within its radius of a blocking boundary"
                                  : $"  closest wall {worstWall:F4}, closest rim {worstRim:F4}"));
            foreach (var s in examples) Console.WriteLine(s);
        }

        // The acceptance test that matters: after erosion, is the ground the
        // player actually stood on still there?
        //
        // Some loss is CORRECT -- a player who hugged a wall stood somewhere a
        // 0.70 body could not, which is the whole point of the exercise and is
        // also the evidence for what the radius should be. What must not happen
        // is losing ground that was nowhere near anything.
        private static void GateErosionAgainstSurvey(string surveyPath, ErosionOutput e,
                                                     List<Tri> tris, int zoneId, Options opt,
                                                     BoundaryReport boundary)
        {
            if (string.IsNullOrEmpty(surveyPath) || !File.Exists(surveyPath)) return;

            const double Cell = 4.0;
            var grid = new Dictionary<(int, int), List<int>>(200_000);
            for (int c = 0; c < e.CellSource.Count; c++)
            {
                int s = e.CellStart[c], t2 = e.CellStart[c + 1];
                double minX = double.MaxValue, maxX = double.MinValue;
                double minZ = double.MaxValue, maxZ = double.MinValue;
                for (int v = s; v < t2; v++)
                {
                    if (e.VX[v] < minX) minX = e.VX[v];
                    if (e.VX[v] > maxX) maxX = e.VX[v];
                    if (e.VZ[v] < minZ) minZ = e.VZ[v];
                    if (e.VZ[v] > maxZ) maxZ = e.VZ[v];
                }
                for (int gz = (int)Math.Floor(minZ / Cell); gz <= (int)Math.Floor(maxZ / Cell); gz++)
                for (int gx = (int)Math.Floor(minX / Cell); gx <= (int)Math.Floor(maxX / Cell); gx++)
                {
                    if (!grid.TryGetValue((gx, gz), out var l)) grid[(gx, gz)] = l = new List<int>(4);
                    l.Add(c);
                }
            }

            // Every blocking segment again, so a lost position can say WHY it was
            // lost. Wall erosion and rim erosion are different decisions -- one is
            // physics, a body cannot be inside a wall; the other is policy, how
            // near a drop we are willing to send someone who cannot see it -- and
            // a single "lost 77 samples" cannot be argued about until it is split.
            const double BCell = 4.0;
            var bgrid = new Dictionary<(int, int), List<int>>(150_000);
            for (int i = 0; i < boundary.Blocking.Count; i++)
            {
                var b = boundary.Blocking[i];
                int x0 = (int)Math.Floor(Math.Min(b.AX, b.BX) / BCell), x1 = (int)Math.Floor(Math.Max(b.AX, b.BX) / BCell);
                int z0 = (int)Math.Floor(Math.Min(b.AZ, b.BZ) / BCell), z1 = (int)Math.Floor(Math.Max(b.AZ, b.BZ) / BCell);
                for (int gz = z0; gz <= z1; gz++)
                for (int gx = x0; gx <= x1; gx++)
                {
                    if (!bgrid.TryGetValue((gx, gz), out var l)) bgrid[(gx, gz)] = l = new List<int>(4);
                    l.Add(i);
                }
            }

            int samples = 0, covered = 0;
            int lostToWall = 0, lostToRim = 0, lostToNeither = 0;
            var lost = new List<string>(10);
            foreach (var line in File.ReadLines(surveyPath))
            {
                var f = line.Split('\t');
                if (f.Length < 7 || f[0] == "survey_id") continue;
                if (!int.TryParse(f[1], out int z) || z != zoneId) continue;
                if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double px)) continue;
                if (!double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out double pz)) continue;
                if (!double.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out double py)) continue;
                samples++;

                bool inside = false;
                int gx2 = (int)Math.Floor(px / Cell), gz2 = (int)Math.Floor(pz / Cell);
                if (grid.TryGetValue((gx2, gz2), out var list))
                {
                    foreach (int c in list)
                    {
                        var src = tris[e.CellSource[c]];
                        if (Math.Abs(src.Cy - py) > 2.0) continue;   // a cell on another floor is not cover
                        if (!PointInCell(e, c, px, pz)) continue;
                        inside = true; break;
                    }
                }
                if (inside) { covered++; continue; }

                // What took it? Whichever kind of boundary is nearest, in the
                // player's own layer.
                double dWall = double.MaxValue, dRim = double.MaxValue;
                int bx3 = (int)Math.Floor(px / BCell), bz3 = (int)Math.Floor(pz / BCell);
                for (int gz = bz3 - 1; gz <= bz3 + 1; gz++)
                for (int gx = bx3 - 1; gx <= bx3 + 1; gx++)
                {
                    if (!bgrid.TryGetValue((gx, gz), out var l)) continue;
                    foreach (int bi in l)
                    {
                        var b = boundary.Blocking[bi];
                        double d = PointSegDist(px, pz, b.AX, b.AZ, b.BX, b.BZ, out double bt);
                        if (d > 2.0) continue;
                        double by = b.AY + (b.BY - b.AY) * bt;
                        if (Math.Abs(by - py) > opt.MaxStepDown) continue;
                        if (b.Kind == BoundaryKind.Wall) { if (d < dWall) dWall = d; }
                        else if (d < dRim) dRim = d;
                    }
                }
                bool byWall = dWall <= e.RadiusWall;
                bool byRim = dRim <= e.RadiusRim;
                if (byWall && !byRim) lostToWall++;
                else if (byRim && !byWall) lostToRim++;
                else if (byWall) lostToWall++;          // both could explain it; wall is the harder fact
                else lostToNeither++;

                if (lost.Count < 10)
                    lost.Add($"erogate:   uncovered: ({px:F2},{pz:F2},{py:F2}) survey {f[0]} seq {f[3]} " +
                             $"nearest wall {(dWall < 1e9 ? dWall.ToString("F2") : "-")} " +
                             $"nearest rim {(dRim < 1e9 ? dRim.ToString("F2") : "-")}");
            }

            Console.WriteLine($"erogate: wall_r={e.RadiusWall:F2} rim_r={e.RadiusRim:F2} " +
                              $"survey_samples={samples} still_on_walkable={covered} " +
                              $"lost={samples - covered} ({100.0 * (samples - covered) / Math.Max(1, samples):F2}%)");
            Console.WriteLine($"erogate:   of the lost: wall erosion took {lostToWall}, " +
                              $"rim erosion took {lostToRim}, neither explains {lostToNeither}");
            foreach (var s in lost) Console.WriteLine(s);
        }

        private static bool PointInCell(ErosionOutput e, int cell, double px, double pz)
        {
            int s = e.CellStart[cell], t = e.CellStart[cell + 1];
            int n = t - s;
            if (n < 3) return false;
            // Convex and counter-clockwise by construction: inside means never to
            // the right of an edge.
            for (int i = 0; i < n; i++)
            {
                double ax = e.VX[s + i], az = e.VZ[s + i];
                double bx = e.VX[s + (i + 1) % n], bz = e.VZ[s + (i + 1) % n];
                if ((bx - ax) * (pz - az) - (bz - az) * (px - ax) < -1e-9) return false;
            }
            return true;
        }

        // ---------------------------------------------------------------
        // The zero-erosion control topology.
        //
        // Before any erosion is judged, the graph has to work without it. The
        // shipped v2 artifact cannot reach two of La Theine's five zone lines and
        // holds only 52% of its nodes in one component -- but that graph's
        // adjacency comes from welded EDGE KEYS, which requires two faces to name
        // the identical edge. A T-junction names three different edges for one
        // physical join, so that test severs ground the interval classifier calls
        // continuous. The old numbers therefore say nothing about whether the new
        // architecture works; they say the old one did not.
        //
        // So: rebuild components from the interval seams, and ask the questions
        // that actually matter for a blind player. Not "how many components" --
        // an isolated rock is a component and nobody cares -- but "can the ground
        // the player walks on reach the places they ask to go".
        //
        // Two corrections to how those questions used to be asked:
        //
        //   candidate sets, not one nearest centroid. The runtime collects every
        //   node within a window and searches from all of them. Judging
        //   reachability from a single nearest triangle answers a question the
        //   runtime never asks, and one bad snap reads as an unreachable
        //   destination.
        //
        //   approach anchors, not trigger points. A zone line sits where the
        //   collision model ENDS. The trigger coordinate is often past the last
        //   walkable ground by design, and what the player needs is to reach the
        //   ground in front of it and keep walking. Requiring a node AT the
        //   trigger asks for something the zone does not contain.
        // ---------------------------------------------------------------
        // ------------------------------------------------------------------
        // The release gate. Every transition the graph is about to promise is
        // walked against the COLLISION MODEL -- all of it, standable and steep
        // alike -- and judged on whether a body could really make that crossing.
        //
        // Why this exists and why sampled routes are not enough. Every earlier
        // measurement in this file judges the graph against either the shipped
        // navmesh or the recorded survey, and both are the wrong authority. The
        // navmesh is the thing that put the player inside a hill; the survey is
        // a trail that does not go within 67 yalms of where they got stuck, so
        // it cannot speak for off-trail ground at all. The collision model is
        // the only description of the world the game itself agrees with.
        //
        // A transition is REFUTED if, walking it, the ground vanishes, or breaks
        // by more than the policy allows in the direction of travel, or the body
        // does not fit. Refuted transitions must not ship.
        private sealed class MeshIndex
        {
            public const double Cell = 4.0;
            private readonly int[] _a, _b, _c;
            private readonly List<float> _vx, _vy, _vz;
            private readonly Dictionary<long, List<int>> _grid;

            public MeshIndex(List<Tri> tris, List<(int A, int B, int C)> steep,
                             List<float> vx, List<float> vy, List<float> vz)
            {
                _vx = vx; _vy = vy; _vz = vz;
                int n = tris.Count + steep.Count;
                _a = new int[n]; _b = new int[n]; _c = new int[n];
                for (int i = 0; i < tris.Count; i++) { _a[i] = tris[i].A; _b[i] = tris[i].B; _c[i] = tris[i].C; }
                for (int i = 0; i < steep.Count; i++)
                {
                    _a[tris.Count + i] = steep[i].A; _b[tris.Count + i] = steep[i].B; _c[tris.Count + i] = steep[i].C;
                }
                _grid = new Dictionary<long, List<int>>(n);
                for (int i = 0; i < n; i++)
                {
                    double x0 = Math.Min(GX(_a[i]), Math.Min(GX(_b[i]), GX(_c[i])));
                    double x1 = Math.Max(GX(_a[i]), Math.Max(GX(_b[i]), GX(_c[i])));
                    double z0 = Math.Min(GZ(_a[i]), Math.Min(GZ(_b[i]), GZ(_c[i])));
                    double z1 = Math.Max(GZ(_a[i]), Math.Max(GZ(_b[i]), GZ(_c[i])));
                    for (int cz = (int)Math.Floor(z0 / Cell); cz <= (int)Math.Floor(z1 / Cell); cz++)
                    for (int cx = (int)Math.Floor(x0 / Cell); cx <= (int)Math.Floor(x1 / Cell); cx++)
                    {
                        long key = ((long)cx << 32) ^ (uint)cz;
                        if (!_grid.TryGetValue(key, out var list)) { list = new List<int>(4); _grid[key] = list; }
                        list.Add(i);
                    }
                }
            }

            private double GX(int i) => _vx[i];
            private double GY(int i) => -_vy[i];
            private double GZ(int i) => -_vz[i];

            // Every surface covering this horizontal point, as GAME heights.
            // Returns the one closest to refY, because a point under an arch has
            // two answers and the body is standing on exactly one of them.
            public bool Surface(double px, double pz, double refY, double band, out double y)
            {
                y = 0; bool got = false; double best = double.MaxValue;
                long key = ((long)(int)Math.Floor(px / Cell) << 32) ^ (uint)(int)Math.Floor(pz / Cell);
                if (!_grid.TryGetValue(key, out var list)) return false;
                foreach (int i in list)
                {
                    double ax = GX(_a[i]), az = GZ(_a[i]), ay = GY(_a[i]);
                    double bx = GX(_b[i]), bz = GZ(_b[i]), by = GY(_b[i]);
                    double cx = GX(_c[i]), cz = GZ(_c[i]), cy = GY(_c[i]);
                    double d1 = (px - ax) * (bz - az) - (pz - az) * (bx - ax);
                    double d2 = (px - bx) * (cz - bz) - (pz - bz) * (cx - bx);
                    double d3 = (px - cx) * (az - cz) - (pz - cz) * (ax - cx);
                    if ((d1 < -1e-9 || d2 < -1e-9 || d3 < -1e-9) && (d1 > 1e-9 || d2 > 1e-9 || d3 > 1e-9)) continue;
                    double den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz);
                    if (Math.Abs(den) < 1e-12) continue;
                    double w1 = ((bz - cz) * (px - cx) + (cx - bx) * (pz - cz)) / den;
                    double w2 = ((cz - az) * (px - cx) + (ax - cx) * (pz - cz)) / den;
                    double yy = w1 * ay + w2 * by + (1.0 - w1 - w2) * cy;
                    double d = Math.Abs(yy - refY);
                    if (d > band) continue;
                    if (d < best) { best = d; y = yy; got = true; }
                }
                return got;
            }
        }

        // Route a named pair on the finished graph and then walk the answer
        // against the collision model. Aggregates cannot catch a single broken
        // crossing, and a single broken crossing is exactly what strands a
        // player -- on 2026-08-20 one leg with no line of sight held someone in
        // the same spot for three hours while every summary statistic looked fine.
        private static bool ProbeRoute(in (string Name, double SX, double SZ, double SY,
                                           double GX, double GZ, double GY) pr,
                                       List<Tri> tris, List<int>[] edges, int[] component,
                                       MeshIndex mesh, Options opt)
        {
            int Snap(double x, double z, double y)
            {
                int best = -1; double bd = double.MaxValue;
                for (int i = 0; i < tris.Count; i++)
                {
                    double dx = tris[i].Cx - x, dz = tris[i].Cz - z, dy = tris[i].Cy - y;
                    // Height is weighted hard: stacked surfaces in this zone sit
                    // within a couple of yalms of each other in XZ, and snapping
                    // to the wrong floor answers a question nobody asked.
                    double d = dx * dx + dz * dz + 9.0 * dy * dy;
                    if (d < bd) { bd = d; best = i; }
                }
                return best;
            }

            int s = Snap(pr.SX, pr.SZ, pr.SY), g = Snap(pr.GX, pr.GZ, pr.GY);
            if (s < 0 || g < 0) { Console.WriteLine($"probe[{pr.Name}]: FAIL no node to snap to"); return false; }
            double snapS = Math.Sqrt(Math.Pow(tris[s].Cx - pr.SX, 2) + Math.Pow(tris[s].Cz - pr.SZ, 2));
            double snapG = Math.Sqrt(Math.Pow(tris[g].Cx - pr.GX, 2) + Math.Pow(tris[g].Cz - pr.GZ, 2));

            if (component[s] != component[g])
            {
                Console.WriteLine($"probe[{pr.Name}]: FAIL unreachable -- start in component {component[s]}, " +
                                  $"goal in {component[g]} (snap {snapS:F2}/{snapG:F2} yalms)");
                return false;
            }

            // A*, straight-line heuristic on centroids.
            var dist = new double[tris.Count];
            var prev = new int[tris.Count];
            for (int i = 0; i < tris.Count; i++) { dist[i] = double.MaxValue; prev[i] = -1; }
            double H(int i) => Math.Sqrt(Math.Pow(tris[i].Cx - tris[g].Cx, 2) +
                                         Math.Pow(tris[i].Cz - tris[g].Cz, 2) +
                                         Math.Pow(tris[i].Cy - tris[g].Cy, 2));
            var open = new PriorityQueue<int, double>();
            dist[s] = 0; open.Enqueue(s, H(s));
            while (open.TryDequeue(out int cur, out _))
            {
                if (cur == g) break;
                foreach (int nb in edges[cur])
                {
                    double w = Math.Sqrt(Math.Pow(tris[nb].Cx - tris[cur].Cx, 2) +
                                         Math.Pow(tris[nb].Cz - tris[cur].Cz, 2) +
                                         Math.Pow(tris[nb].Cy - tris[cur].Cy, 2));
                    if (dist[cur] + w < dist[nb]) { dist[nb] = dist[cur] + w; prev[nb] = cur; open.Enqueue(nb, dist[nb] + H(nb)); }
                }
            }
            if (dist[g] == double.MaxValue)
            {
                Console.WriteLine($"probe[{pr.Name}]: FAIL same component but A* found no path");
                return false;
            }

            var path = new List<int>();
            for (int i = g; i >= 0; i = prev[i]) path.Add(i);
            path.Reverse();

            // Walk it. Every leg, on the collision model, at a quarter yalm.
            int badLegs = 0; double worst = 0;
            for (int k = 1; k < path.Count; k++)
            {
                double ax = tris[path[k - 1]].Cx, az = tris[path[k - 1]].Cz, ay = tris[path[k - 1]].Cy;
                double bx = tris[path[k]].Cx, bz = tris[path[k]].Cz;
                double dx = bx - ax, dz = bz - az, len = Math.Sqrt(dx * dx + dz * dz);
                if (len < 1e-6) continue;
                double ux = dx / len, uz = dz / len, prevY = ay;
                for (double t = 0.25; t <= len; t += 0.25)
                {
                    if (!mesh.Surface(ax + ux * t, az + uz * t, prevY, 2.5, out double y)) { badLegs++; break; }
                    double climb = prevY - y;
                    if (climb > Math.Max(opt.MaxStepUp, 0.25 * opt.MaxUpGrade) ||
                        -climb > Math.Max(opt.MaxStepDown, 0.25 * opt.MaxDownGrade))
                    { badLegs++; if (Math.Abs(climb) > worst) worst = Math.Abs(climb); break; }
                    prevY = y;
                }
            }
            Console.WriteLine($"probe[{pr.Name}]: {(badLegs == 0 ? "PASS" : "FAIL")} " +
                              $"nodes={path.Count} length={dist[g]:F1} yalms " +
                              $"snap={snapS:F2}/{snapG:F2} broken_legs={badLegs}" +
                              (worst > 0 ? $" worst_break={worst:F2}" : ""));
            return badLegs == 0;
        }

        private static long ValidateTransitions(string label, List<Tri> tris, List<int>[] edges,
                                               MeshIndex mesh, Options opt, string? dumpPath = null,
                                               bool remove = false,
                                               float[][]? gate = null, List<int>[]? outPortal = null)
        {
            var kill = remove ? new bool[tris.Count][] : null;
            const double March = 0.25;          // fine enough to fall into a 0.25-yalm crack
            const double FindBand = 2.5;        // look this far for the surface before calling it absent
            double stepUp = opt.MaxStepUp, stepDown = opt.MaxStepDown;
            double allowUp = Math.Max(stepUp, March * opt.MaxUpGrade);
            double allowDown = Math.Max(stepDown, March * opt.MaxDownGrade);
            double radius = opt.AgentRadius;

            long total = 0, noGround = 0, broke = 0, narrow = 0, ok = 0;
            double worstBreak = 0; int worstA = -1, worstB = -1;
            var examples = new List<string>(24);
            var sync = new object();

            Parallel.For(0, tris.Count, () => (Total: 0L, NoGround: 0L, Broke: 0L, Narrow: 0L, Ok: 0L,
                                               Worst: 0.0, WA: -1, WB: -1, Ex: new List<string>(4)),
                (a, loop, acc) =>
            {
                if (edges[a] == null) return acc;
                // Each thread writes only its own node's row, so this needs no
                // lock and no shared state.
                if (kill != null) kill[a] = new bool[edges[a].Count];
                for (int ei = 0; ei < edges[a].Count; ei++)
                {
                    int b = edges[a][ei];
                    acc.Total++;
                    double ax = tris[a].Cx, az = tris[a].Cz, ay = tris[a].Cy;
                    double bx = tris[b].Cx, bz = tris[b].Cz;
                    double dx = bx - ax, dz = bz - az;
                    double len = Math.Sqrt(dx * dx + dz * dz);
                    if (len < 1e-6) { acc.Ok++; continue; }
                    // Over the run the format allows. Written out it would be
                    // refused on load, so it is refused here where the loss is
                    // visible and the topology that follows already knows.
                    if (len > opt.MaxEdgeRun)
                    {
                        acc.Broke++;
                        if (kill != null) kill[a][ei] = true;
                        continue;
                    }
                    double ux = dx / len, uz = dz / len;
                    double nx = -uz, nz = ux;

                    bool gone = false, snapped = false, tight = false;
                    double prev = ay, worst = 0;
                    for (double s = March; s <= len; s += March)
                    {
                        double px = ax + ux * s, pz = az + uz * s;
                        if (!mesh.Surface(px, pz, prev, FindBand, out double y)) { gone = true; break; }
                        // y is DOWN: y shrinking is climbing, y growing is descending.
                        double climb = prev - y;
                        if (climb > allowUp || -climb > allowDown)
                        {
                            snapped = true;
                            if (Math.Abs(climb) > worst) worst = Math.Abs(climb);
                            break;
                        }
                        // Does the BODY fit, or only its centreline? Check the two
                        // rails the shoulders trace. A rail that leaves the ground
                        // is a ledge the player would walk off, not a corridor.
                        if (!mesh.Surface(px + nx * radius, pz + nz * radius, y, FindBand, out _) ||
                            !mesh.Surface(px - nx * radius, pz - nz * radius, y, FindBand, out _))
                            tight = true;
                        prev = y;
                    }

                    if (gone) { acc.NoGround++; if (kill != null) kill[a][ei] = true; if (acc.Ex.Count < 4) acc.Ex.Add($"    no ground  {a}->{b} at ({ax:F1},{az:F1})->({bx:F1},{bz:F1})"); }
                    else if (snapped)
                    {
                        acc.Broke++;
                        if (kill != null) kill[a][ei] = true;
                        if (worst > acc.Worst) { acc.Worst = worst; acc.WA = a; acc.WB = b; }
                        if (acc.Ex.Count < 4) acc.Ex.Add($"    break {worst:F2}  {a}->{b} at ({ax:F1},{az:F1})->({bx:F1},{bz:F1})");
                    }
                    else { acc.Ok++; if (tight) acc.Narrow++; }
                }
                return acc;
            },
                acc =>
            {
                lock (sync)
                {
                    total += acc.Total; noGround += acc.NoGround; broke += acc.Broke;
                    narrow += acc.Narrow; ok += acc.Ok;
                    if (acc.Worst > worstBreak) { worstBreak = acc.Worst; worstA = acc.WA; worstB = acc.WB; }
                    foreach (var e in acc.Ex) if (examples.Count < 12) examples.Add(e);
                }
            });

            long refuted = noGround + broke;
            Console.WriteLine($"validate[{label}]: transitions={total} REFUTED={refuted} " +
                              $"({100.0 * refuted / Math.Max(1, total):F3}%) " +
                              $"-- no_ground={noGround} broke_policy={broke} | " +
                              $"passed={ok} of which body_does_not_fit={narrow} " +
                              $"({100.0 * narrow / Math.Max(1, ok):F2}%)");
            if (worstA >= 0)
                Console.WriteLine($"validate[{label}]: worst break {worstBreak:F2} yalms on {worstA}->{worstB}");
            foreach (var e in examples) Console.WriteLine(e);
            if (!string.IsNullOrEmpty(dumpPath))
                File.WriteAllText(dumpPath, string.Join("\n", examples));

            // Drop what the collision model refused. This replaces per-doorway
            // capacity as the pruning rule, and it is a strictly better one: it
            // asks whether a body walking this exact crossing meets ground the
            // whole way, instead of whether an arbitrary tessellation edge is
            // wide enough. The gate and portal rows travel with their edge, or
            // the funnel would pull against a doorway belonging to a different
            // crossing.
            if (kill != null)
            {
                long cut = 0;
                for (int a = 0; a < tris.Count; a++)
                {
                    var row = kill[a];
                    if (row == null || edges[a] == null) continue;
                    bool any = false;
                    for (int k = 0; k < row.Length; k++) if (row[k]) { any = true; break; }
                    if (!any) continue;
                    var keepE = new List<int>(edges[a].Count);
                    var keepG = new List<float>(edges[a].Count);
                    var keepP = new List<int>(edges[a].Count);
                    for (int k = 0; k < edges[a].Count; k++)
                    {
                        if (k < row.Length && row[k])
                        {
                            int j2 = edges[a][k];
                            if (InDiag(opt, tris[a].Cx, tris[a].Cz) || InDiag(opt, tris[j2].Cx, tris[j2].Cz))
                                Console.WriteLine($"diag: VALIDATE cut {a}->{j2} c=({tris[a].Cx:F2},{tris[a].Cz:F2})->({tris[j2].Cx:F2},{tris[j2].Cz:F2})");
                            cut++; continue;
                        }
                        keepE.Add(edges[a][k]);
                        if (gate != null) keepG.Add(k < gate[a].Length ? gate[a][k] : 0f);
                        if (outPortal != null) keepP.Add(k < outPortal[a].Count ? outPortal[a][k] : -1);
                    }
                    edges[a] = keepE;
                    if (gate != null) gate[a] = keepG.ToArray();
                    if (outPortal != null) outPortal[a] = keepP;
                }
                Console.WriteLine($"validate[{label}]: removed {cut} refuted transitions");
            }
            return refuted;
        }

        private static void ReportControlTopology(List<Tri> tris, BoundaryReport boundary,
                                                  int[] oldComponent, Options opt)
        {
            int n = tris.Count;
            var parent = new int[n];
            for (int i = 0; i < n; i++) parent[i] = i;
            int Find(int a) { while (parent[a] != a) { parent[a] = parent[parent[a]]; a = parent[a]; } return a; }
            void Union(int a, int b) { a = Find(a); b = Find(b); if (a != b) parent[a] = b; }

            long used = 0;
            foreach (var lk in boundary.Links)
            {
                int a = lk.A, b = lk.B;
                if (a < 0 || b < 0 || a >= n || b >= n) continue;
                used++;
                Union(a, b);
            }

            var size = new Dictionary<int, int>(50_000);
            for (int i = 0; i < n; i++)
            {
                int r = Find(i);
                size.TryGetValue(r, out int c);
                size[r] = c + 1;
            }
            int biggest = 0, biggestRoot = -1;
            foreach (var kv in size) if (kv.Value > biggest) { biggest = kv.Value; biggestRoot = kv.Key; }

            int oldCount = 0;
            var seenOld = new HashSet<int>();
            for (int i = 0; i < n; i++) if (seenOld.Add(oldComponent[i])) oldCount++;

            Console.WriteLine($"topo: links={boundary.Links.Count} used={used}");
            Console.WriteLine($"topo: components from interval seams = {size.Count} " +
                              $"(welded-edge adjacency gave {oldCount}), " +
                              $"largest holds {biggest} of {n} ({100.0 * biggest / Math.Max(1, n):F1}%)");

            if (string.IsNullOrEmpty(opt.SurveyPath) || !File.Exists(opt.SurveyPath)) return;

            // Candidate set for a point: every standable face whose centroid is
            // within the window, as the runtime does it.
            const float Cell = 8f;
            var buckets = new Dictionary<(int, int), List<int>>(50_000);
            for (int i = 0; i < n; i++)
            {
                var key = ((int)Math.Floor(tris[i].Cx / Cell), (int)Math.Floor(tris[i].Cz / Cell));
                if (!buckets.TryGetValue(key, out var list)) buckets[key] = list = new List<int>(8);
                list.Add(i);
            }
            List<int> Candidates(double px, double pz, double py, double horiz, double vert)
            {
                var outl = new List<int>(16);
                int span = (int)Math.Ceiling(horiz / Cell);
                int bx = (int)Math.Floor(px / Cell), bz = (int)Math.Floor(pz / Cell);
                for (int ox = -span; ox <= span; ox++)
                for (int oz = -span; oz <= span; oz++)
                {
                    if (!buckets.TryGetValue((bx + ox, bz + oz), out var list)) continue;
                    foreach (int i in list)
                    {
                        double dx = tris[i].Cx - px, dz = tris[i].Cz - pz;
                        if (dx * dx + dz * dz > horiz * horiz) continue;
                        if (Math.Abs(tris[i].Cy - py) > vert) continue;
                        outl.Add(i);
                    }
                }
                return outl;
            }

            // The component the player's own recorded ground belongs to.
            var walked = new Dictionary<int, int>();
            int surveyRows = 0, surveyUnsnapped = 0;
            foreach (var line in File.ReadLines(opt.SurveyPath))
            {
                var f = line.Split('\t');
                if (f.Length < 7 || f[0] == "survey_id") continue;
                if (!int.TryParse(f[1], out int z) || z != opt.ZoneId) continue;
                if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double px)) continue;
                if (!double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out double pz)) continue;
                if (!double.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out double py)) continue;
                surveyRows++;
                var cand = Candidates(px, pz, py, 6.0, 4.0);
                if (cand.Count == 0) { surveyUnsnapped++; continue; }
                foreach (int i in cand)
                {
                    int r = Find(i);
                    walked.TryGetValue(r, out int c);
                    walked[r] = c + 1;
                }
            }
            int trailRoot = -1, trailHits = 0;
            foreach (var kv in walked) if (kv.Value > trailHits) { trailHits = kv.Value; trailRoot = kv.Key; }
            Console.WriteLine($"topo: survey rows={surveyRows} unsnapped={surveyUnsnapped}; " +
                              $"the walked component is {(trailRoot == biggestRoot ? "the largest one" : "NOT the largest one")}");

            // Every consecutive pair the player actually walked must be mutually
            // reachable. This is the sharp test: a break here is a barrier the
            // graph invented across a step somebody physically took.
            int strides = 0, broken = 0;
            string prevId = ""; int prevSeq = -999; List<int> prevCand = null;
            foreach (var line in File.ReadLines(opt.SurveyPath))
            {
                var f = line.Split('\t');
                if (f.Length < 7 || f[0] == "survey_id") continue;
                if (!int.TryParse(f[1], out int z) || z != opt.ZoneId) { prevCand = null; continue; }
                if (!int.TryParse(f[3], out int seq)) continue;
                if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double px)) continue;
                if (!double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out double pz)) continue;
                if (!double.TryParse(f[6], NumberStyles.Float, CultureInfo.InvariantCulture, out double py)) continue;
                var cand = Candidates(px, pz, py, 6.0, 4.0);
                if (prevCand != null && f[0] == prevId && seq == prevSeq + 1
                    && prevCand.Count > 0 && cand.Count > 0)
                {
                    strides++;
                    var roots = new HashSet<int>();
                    foreach (int i in prevCand) roots.Add(Find(i));
                    bool shared = false;
                    foreach (int i in cand) if (roots.Contains(Find(i))) { shared = true; break; }
                    if (!shared) broken++;
                }
                prevId = f[0]; prevSeq = seq; prevCand = cand;
            }
            Console.WriteLine($"topo: walked strides={strides} with no shared component={broken} " +
                              $"({100.0 * broken / Math.Max(1, strides):F2}%)");

            if (string.IsNullOrEmpty(opt.DestinationsPath) || !File.Exists(opt.DestinationsPath)) return;

            // Destinations. An APPROACH window rather than a demand for ground at
            // the exact coordinate, because several of these coordinates are
            // deliberately past where the zone's collision stops.
            int total = 0, reachable = 0, offTrail = 0, nothingNear = 0;
            var areaLines = new List<string>(16);
            var strandedComponents = new HashSet<int>();
            StreamWriter triage = null;
            if (!string.IsNullOrEmpty(opt.TriagePath))
            {
                triage = new StreamWriter(opt.TriagePath, false);
                triage.WriteLine("# Destinations the walked ground cannot reach, zero erosion. " +
                                 "One row each, with the evidence for the verdict.");
                triage.WriteLine("kind\tname\tx\tz\ty\tsource\tconfidence\t" +
                                 "cand_6x4\tcand_used\tcand_any_y\tdy_to_nearest_ground\t" +
                                 "component\tcomponent_size\tdist_to_walked_ground\treason");
            }
            foreach (var line in File.ReadLines(opt.DestinationsPath))
            {
                if (line.Length == 0 || line[0] == '#') continue;
                var f = line.Split('\t');
                if (f.Length < 6) continue;
                if (!int.TryParse(f[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out int z)
                    || z != opt.ZoneId) continue;
                if (!double.TryParse(f[2], NumberStyles.Float, CultureInfo.InvariantCulture, out double px)) continue;
                if (!double.TryParse(f[3], NumberStyles.Float, CultureInfo.InvariantCulture, out double pz)) continue;
                if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out double py)) continue;
                total++;

                var cand = Candidates(px, pz, py, 6.0, 4.0);
                int nearWindow = cand.Count;
                string verdict;
                if (cand.Count == 0)
                {
                    // Widen once, and say so. A zone line's trigger can stand
                    // several yalms past the last walkable face by design.
                    cand = Candidates(px, pz, py, 12.0, 8.0);
                    if (cand.Count == 0) { nothingNear++; verdict = "NO GROUND WITHIN 12"; }
                    else verdict = ReachTag(cand, Find, trailRoot, out bool ok2)
                                 + " (only via a 12-yalm approach)";
                }
                else verdict = ReachTag(cand, Find, trailRoot, out _);

                if (verdict.StartsWith("reachable")) reachable++;
                else if (!verdict.StartsWith("NO GROUND")) offTrail++;
                if (f[5] == "area") areaLines.Add($"topo:   {verdict,-42} {f[1]}");

                // Everything that did NOT reach the walked ground gets written out
                // one row at a time, with the evidence needed to say WHY. An
                // aggregate count cannot distinguish a wrong coordinate from a
                // missing seam from a rock nobody walks to, and erosion can only
                // make this number worse -- so it has to be understood before
                // erosion is layered on top, or the two effects mix.
                if (triage != null && !verdict.StartsWith("reachable"))
                {
                    // Is there ground here at ALL, if we stop caring about height?
                    // If so the target's Y is wrong, not its location.
                    var anyY = Candidates(px, pz, py, 6.0, 1e9);
                    double bestDy = double.MaxValue;
                    foreach (int i in anyY) bestDy = Math.Min(bestDy, Math.Abs(tris[i].Cy - py));

                    // How far to the nearest node that IS on the walked ground,
                    // and -- the part that decides it -- how far below or above.
                    // A neighbour a yalm away at the same height is a seam we
                    // failed to find; one a yalm away and eight yalms down is a
                    // cliff doing its job, and the two must not read alike.
                    double distMain = double.MaxValue, dyMain = 0.0;
                    for (double reach = 8.0; reach <= 48.0 && distMain > 1e8; reach *= 2.0)
                        foreach (int i in Candidates(px, pz, py, reach, 1e9))
                        {
                            if (Find(i) != trailRoot) continue;
                            double dx = tris[i].Cx - px, dz = tris[i].Cz - pz;
                            double dd = Math.Sqrt(dx * dx + dz * dz);
                            if (dd < distMain) { distMain = dd; dyMain = tris[i].Cy - py; }
                        }

                    int bestComp = -1, bestCompSize = 0;
                    foreach (int i in cand) strandedComponents.Add(Find(i));
                    foreach (int i in cand)
                    {
                        int r2 = Find(i);
                        int sz = size.TryGetValue(r2, out int s2) ? s2 : 0;
                        if (sz > bestCompSize) { bestCompSize = sz; bestComp = r2; }
                    }

                    string reason;
                    if (anyY.Count > 0 && nearWindow == 0 && bestDy < 1e8 && bestDy > 4.0)
                        reason = "bad-target-y";
                    else if (cand.Count == 0)
                        reason = anyY.Count > 0 ? "bad-target-y" : "no-collision-here";
                    else if (distMain <= 3.0)
                        reason = Math.Abs(dyMain) <= opt.MaxStepDown
                               ? "missing-seam-or-portal" : "adjacent-but-a-drop";
                    else if (bestCompSize <= 32)
                        reason = "isolated-edge-geometry";
                    else
                        reason = "separate-terrain";

                    triage.WriteLine($"{f[5]}\t{f[1]}\t{px:F3}\t{pz:F3}\t{py:F3}\t" +
                                     $"{(f.Length > 6 ? f[6] : "")}\t{(f.Length > 7 ? f[7] : "")}\t" +
                                     $"{nearWindow}\t{cand.Count}\t{anyY.Count}\t" +
                                     $"{(bestDy < 1e8 ? bestDy.ToString("F2") : "")}\t" +
                                     $"{bestComp}\t{bestCompSize}\t" +
                                     $"{(distMain < 1e8 ? distMain.ToString("F2") : "")}\t" +
                                     $"{(distMain < 1e8 ? dyMain.ToString("F2") : "")}\t{reason}");
                }
            }
            Console.WriteLine($"topo: destinations={total} reachable from the walked ground={reachable} " +
                              $"({100.0 * reachable / Math.Max(1, total):F1}%) " +
                              $"off-trail={offTrail} no_ground_within_12={nothingNear}");
            // For every component that holds an unreachable destination: how
            // close does it come to the walked ground ANYWHERE, and is there a
            // pair the policy would actually allow a step between? A destination
            // sitting at the foot of a cliff says nothing about whether its
            // component joins the trail somewhere else entirely, and without
            // that, "separate terrain" is a guess.
            if (strandedComponents.Count > 0)
            {
                var byRoot = new Dictionary<int, List<int>>(strandedComponents.Count);
                for (int i = 0; i < n; i++)
                {
                    int r = Find(i);
                    if (!strandedComponents.Contains(r)) continue;
                    if (!byRoot.TryGetValue(r, out var l)) byRoot[r] = l = new List<int>(64);
                    l.Add(i);
                }
                Console.WriteLine("topo: how near the walked ground do the stranded components come?");
                foreach (var kv in byRoot)
                {
                    double best = double.MaxValue, bestDy = 0.0;
                    double bestLegal = double.MaxValue, bestLegalDy = 0.0;
                    double bx2 = 0, bz2 = 0;
                    foreach (int i in kv.Value)
                    foreach (int j in Candidates(tris[i].Cx, tris[i].Cz, tris[i].Cy, 4.0, 1e9))
                    {
                        if (Find(j) != trailRoot) continue;
                        double dx = tris[j].Cx - tris[i].Cx, dz = tris[j].Cz - tris[i].Cz;
                        double dd = Math.Sqrt(dx * dx + dz * dz);
                        double dy = tris[j].Cy - tris[i].Cy;
                        if (dd < best) { best = dd; bestDy = dy; bx2 = tris[i].Cx; bz2 = tris[i].Cz; }
                        // Does a pair even fall inside the step-and-grade
                        // envelope? This is a SCREEN, not a verdict. It says
                        // nothing about whether ground runs continuously between
                        // the two -- applying a grade allowance across a gap with
                        // nothing in it is precisely the error of treating "the
                        // body would fit" as "the space is supported".
                        double allow = dy > 0
                            ? Math.Max(opt.MaxStepDown, dd * opt.MaxDownGrade)
                            : Math.Max(opt.MaxStepUp, dd * opt.MaxUpGrade);
                        if (Math.Abs(dy) <= allow && dd < bestLegal) { bestLegal = dd; bestLegalDy = dy; }
                    }
                    Console.WriteLine($"topo:   component {kv.Key} ({kv.Value.Count} nodes): " +
                        (best < 1e8
                          ? $"nearest walked ground {best:F2} away, {bestDy:F2} in height, near ({bx2:F0},{bz2:F0}); "
                          : "no walked ground within 4 yalms anywhere; ") +
                        (bestLegal < 1e8
                          ? $"a pair at {bestLegal:F2}, {bestLegalDy:F2} falls inside the step envelope -- INSPECT, not proven"
                          : "no pair anywhere is even inside the step envelope -- separate"));
                }
            }

            if (triage != null) { triage.Flush(); triage.Dispose();
                Console.WriteLine($"topo: wrote the unreachable-destination triage to {opt.TriagePath}"); }
            Console.WriteLine("topo: zone lines and areas --");
            foreach (var s in areaLines) Console.WriteLine(s);
        }

        private static string ReachTag(List<int> cand, Func<int, int> find, int trailRoot, out bool ok)
        {
            foreach (int i in cand) if (find(i) == trailRoot) { ok = true; return "reachable"; }
            ok = false;
            return "OFF-TRAIL";
        }

        // Record edge (u,v) as a wall if the steep triangle's opposite vertex w
        // stands at least minRise ABOVE the edge. Raw OBJ y is negated game y,
        // and game y points down, so raw vy INCREASES upward -- the sign here is
        // the plain one, and it is the opposite of what the game-space code does.
        private static void MarkWall(HashSet<long> walls, int[] canon, List<float> vy,
                                     int u, int v, int w, double minRise)
        {
            double mid = (vy[u] + vy[v]) * 0.5;
            if (vy[w] - mid >= minRise) walls.Add(EdgeKey(canon[u], canon[v]));
        }

        // Horizontal gap from a triangle's centroid to edge (u,v) if that edge is
        // a wall, else "no constraint". Raw OBJ z is negated game z; x is not.
        // Sign does not matter to a distance, but the frames must not be mixed --
        // the centroid is already in game space.
        private static float WallGap(HashSet<long> walls, int[] canon,
                                     List<float> vx, List<float> vz, Tri t, int u, int v)
        {
            if (!walls.Contains(EdgeKey(canon[u], canon[v]))) return float.MaxValue;

            double ax = vx[u], az = -vz[u];
            double bx = vx[v], bz = -vz[v];
            double dx = bx - ax, dz = bz - az;
            double len2 = dx * dx + dz * dz;
            // Clamp to the segment: a wall's influence ends where the wall does.
            double s = len2 > 1e-12 ? Math.Clamp(((t.Cx - ax) * dx + (t.Cz - az) * dz) / len2, 0.0, 1.0) : 0.0;
            double px = t.Cx - (ax + s * dx), pz = t.Cz - (az + s * dz);
            return (float)Math.Sqrt(px * px + pz * pz);
        }

        // Record that `tri` owns welded edge (u,v). A collapsed edge -- both ends
        // welded to the same point -- is not an edge at all; the old code keyed it
        // as (v,v) and let it accumulate owners, 21 of them in one case, which then
        // contaminated adjacency, clearance and components alike.
        private static void AddOwner(Dictionary<long, List<int>> owners, int u, int v, int tri,
                                     ref long collapsed)
        {
            if (u == v) { collapsed++; return; }
            long key = EdgeKey(u, v);
            if (!owners.TryGetValue(key, out var list)) owners[key] = list = new List<int>(2);
            if (!list.Contains(tri)) list.Add(tri);
        }


        // The certified width as the READER will measure it: between the two
        // serialized single-precision endpoints, floored to whole centimetres.
        private static int SpanCm(Portal pt)
        {
            double dx = (double)pt.RightX - pt.LeftX, dz = (double)pt.RightZ - pt.LeftZ;
            return (int)Math.Floor(Math.Sqrt(dx * dx + dz * dz) * 100.0);
        }

        // Squared distance from a point to a triangle, in the XZ plane.
        private static double DistSqPointTri(double px, double pz,
                                             double ax, double az, double bx, double bz,
                                             double cx, double cz)
        {
            // A triangle standing vertically projects to a LINE in XZ, and a wall
            // is exactly that. The winding test cannot decide inside/outside for a
            // degenerate projection -- all three cross products are zero, which
            // reads as "inside" and returns distance zero for a point that may be
            // far away. 22404 steep faces here project exactly degenerately, so
            // this is the common case for walls, not a corner case.
            double area = (bx - ax) * (cz - az) - (bz - az) * (cx - ax);
            if (Math.Abs(area) > 1e-9)
            {
                double d1 = (px - ax) * (bz - az) - (pz - az) * (bx - ax);
                double d2 = (px - bx) * (cz - bz) - (pz - bz) * (cx - bx);
                double d3 = (px - cx) * (az - cz) - (pz - cz) * (ax - cx);
                bool neg = d1 < 0 || d2 < 0 || d3 < 0;
                bool pos = d1 > 0 || d2 > 0 || d3 > 0;
                if (!(neg && pos)) return 0.0;
            }
            return Math.Min(DistSqPointSeg(px, pz, ax, az, bx, bz),
                   Math.Min(DistSqPointSeg(px, pz, bx, bz, cx, cz),
                            DistSqPointSeg(px, pz, cx, cz, ax, az)));
        }

        private static double DistSqPointSeg(double px, double pz,
                                             double ax, double az, double bx, double bz)
        {
            double dx = bx - ax, dz = bz - az;
            double len2 = dx * dx + dz * dz;
            double t = len2 > 1e-12 ? Math.Clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0.0, 1.0) : 0.0;
            double qx = px - (ax + t * dx), qz = pz - (az + t * dz);
            return qx * qx + qz * qz;
        }

        // The span of the portal parameter where the body would be inside `radius`
        // of this obstacle. Distance from a point travelling a straight line to a
        // convex set is convex in the parameter, so the blocked span is a single
        // interval: find the closest approach, then bracket outward to the radius.
        private static bool BlockedSpan(double x0, double z0, double x1, double z1,
                                        double ax, double az, double bx, double bz,
                                        double cx, double cz, double radius,
                                        out double lo, out double hi)
        {
            lo = 0; hi = 0;
            double D(double t) => DistSqPointTri(x0 + (x1 - x0) * t, z0 + (z1 - z0) * t,
                                                 ax, az, bx, bz, cx, cz);
            double r2 = radius * radius;
            double a = 0, b = 1;
            for (int i = 0; i < 48; i++)          // ternary search for closest approach
            {
                double m1 = a + (b - a) / 3.0, m2 = b - (b - a) / 3.0;
                if (D(m1) < D(m2)) b = m2; else a = m1;
            }
            double tStar = (a + b) * 0.5;
            if (D(tStar) > r2) return false;      // never comes close enough to matter

            double Edge(double inside, double outside)
            {
                for (int i = 0; i < 40; i++)
                {
                    double m = (inside + outside) * 0.5;
                    if (D(m) <= r2) inside = m; else outside = m;
                }
                return inside;
            }
            lo = D(0) <= r2 ? 0.0 : Edge(tStar, 0.0);
            hi = D(1) <= r2 ? 1.0 : Edge(tStar, 1.0);
            return true;
        }

        // Linear interpolation of a value defined at two parameter positions.
        private static double Lerp(double v0, double v1, double s0, double s1, double s)
            => Math.Abs(s1 - s0) < 1e-12 ? v0 : v0 + (v1 - v0) * ((s - s0) / (s1 - s0));

        // The two RAW vertices of `t` whose welded ids are p and q. The raw pair is
        // what the face physically owns; the canonical key is only how we found it,
        // and welding is allowed to repair a seam but not to invent a doorway
        // between segments that merely landed in the same bucket.
        private static bool RawEdge(Tri t, int[] canon, int p, int q, out int u, out int v)
        {
            u = -1; v = -1;
            foreach (int raw in new[] { t.A, t.B, t.C })
            {
                int c = canon[raw];
                if (c == p && u < 0) u = raw;
                else if (c == q && v < 0) v = raw;
            }
            return u >= 0 && v >= 0;
        }

        // The welded vertex of `t` that is not an end of edge (p,q).
        private static int Opposite(Tri t, int[] canon, int p, int q)
        {
            int a = canon[t.A], b = canon[t.B], c = canon[t.C];
            if (a != p && a != q) return t.A;
            if (b != p && b != q) return t.B;
            if (c != p && c != q) return t.C;
            return -1;
        }

        private static int FaceIndex(string token)
        {
            // "3", "3/1", "3//1" -- OBJ indices are 1-based.
            int slash = token.IndexOf('/');
            var s = slash >= 0 ? token.Substring(0, slash) : token;
            return int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out int v)
                ? v - 1 : -1;
        }

        // AXWG v1, the layout Codex specified and owns. Node coordinates are
        // stored x, z, y -- NOT x, y, z -- because every probe and log line in
        // this project prints them that way, and quietly reordering them is
        // exactly the class of mistake that costs an afternoon.
        private const uint GridCell = 8;   // yalms; 1-yalm buckets would dwarf the node count

        // AXWG v2. The difference that matters is not the extra bytes: v1 could
        // only say a body fits SOMEWHERE along a doorway, and a number cannot
        // steer anybody. v2 records WHERE -- the certified interval's two ends and
        // both surfaces' heights at each -- so a funnel can pull a real line
        // through the openings instead of stringing triangle centres together and
        // hoping the straight bits between them are clear. That hope is what
        // walked the player into terrain in the first place.
        private static void WriteBinaryV2(string path, List<Tri> tris, List<int>[] edges,
                                          float[][] gate, List<int>[] outPortal, float[] clearance,
                                          int[] component, int componentCount, List<Portal> portals,
                                          uint sourceCrc, Options opt)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)) ?? ".");
            const int HeaderSizeV2 = 80, PolicySize = 64, GridSize = 32;
            const int NodeRec = 32, EdgeRec = 20, PortalRec = 48;

            int n = tris.Count;
            long totalEdges = 0;
            for (int i = 0; i < n; i++) totalEdges += edges[i].Count;

            // Only certified doorways are serialized, and the edge records index
            // into THIS list, so build the remap before writing anything.
            var referenced = new HashSet<int>(portals.Count);
            for (int i = 0; i < tris.Count; i++)
                if (outPortal[i] != null)
                    foreach (int pid in outPortal[i])
                        if (pid >= 0) referenced.Add(pid);

            var keep = new List<int>(portals.Count);
            var remap = new int[portals.Count];
            for (int i = 0; i < portals.Count; i++)
            {
                // Below the loader's safe-span floor is the same as absent: it
                // would be refused on read. Drop it here so the edge that names
                // it is withdrawn too, rather than shipping a file that cannot
                // be opened.
                if (portals[i].CapacityCm < MinSafeSpanCm) { remap[i] = -1; continue; }
                // A doorway no transition uses is refused on read too, and
                // rightly: it advertises a way through that no route can take.
                // Transitions are filtered after portals are chosen -- the
                // collision-model prune and the run limit both cut edges -- so
                // the survivors have to be recounted here, not assumed.
                if (!referenced.Contains(i)) { remap[i] = -1; continue; }
                remap[i] = keep.Count;
                keep.Add(i);
            }

            const double GridCell = 8.0;
            float minX = float.MaxValue, minZ = float.MaxValue, maxX = float.MinValue, maxZ = float.MinValue;
            for (int i = 0; i < n; i++)
            {
                minX = Math.Min(minX, tris[i].Cx); maxX = Math.Max(maxX, tris[i].Cx);
                minZ = Math.Min(minZ, tris[i].Cz); maxZ = Math.Max(maxZ, tris[i].Cz);
            }
            minX = (float)(Math.Floor(minX / GridCell) * GridCell);
            minZ = (float)(Math.Floor(minZ / GridCell) * GridCell);
            uint gw = (uint)Math.Max(1, (int)Math.Floor((maxX - minX) / GridCell) + 1);
            uint gh = (uint)Math.Max(1, (int)Math.Floor((maxZ - minZ) / GridCell) + 1);
            uint bucketCount = gw * gh;

            var counts = new int[bucketCount];
            var cell = new int[n];
            for (int i = 0; i < n; i++)
            {
                int cx = Math.Clamp((int)Math.Floor((tris[i].Cx - minX) / GridCell), 0, (int)gw - 1);
                int cz = Math.Clamp((int)Math.Floor((tris[i].Cz - minZ) / GridCell), 0, (int)gh - 1);
                cell[i] = cz * (int)gw + cx;
                counts[cell[i]]++;
            }
            var first = new int[bucketCount];
            for (uint b = 1; b < bucketCount; b++) first[b] = first[b - 1] + counts[b - 1];
            var cursor2 = (int[])first.Clone();
            var entries = new int[n];
            for (int i = 0; i < n; i++) entries[cursor2[cell[i]]++] = i;

            uint nodesOffset   = HeaderSizeV2 + PolicySize + GridSize;
            uint edgesOffset   = (uint)(nodesOffset + (long)n * NodeRec);
            uint portalsOffset = (uint)(edgesOffset + totalEdges * EdgeRec);
            uint bucketsOffset = (uint)(portalsOffset + (long)keep.Count * PortalRec);
            uint entriesOffset = (uint)(bucketsOffset + (long)bucketCount * 8);
            uint fileSize      = (uint)(entriesOffset + (long)n * 4);

            using var ms = new MemoryStream((int)fileSize);
            using var w = new BinaryWriter(ms);

            w.Write((byte)'A'); w.Write((byte)'X'); w.Write((byte)'W'); w.Write((byte)'G');
            w.Write((ushort)2);                     // version
            w.Write((ushort)HeaderSizeV2);
            w.Write(0x01020304u);
            w.Write((uint)opt.ZoneId);
            // DIRECTED|Y_DOWN|GRID|HAS_PORTALS|SAFE_PORTAL_INTERVALS.
            // CAPSULE_VERIFIED stays CLEAR: the erosion tests the body's width and
            // its height band, but not a swept capsule against low ceilings.
            w.Write(1u | 2u | 4u | 0x20u | 0x40u);
            w.Write((uint)n);
            w.Write((uint)totalEdges);
            w.Write(nodesOffset);
            w.Write(edgesOffset);
            w.Write((uint)HeaderSizeV2);            // policy_offset
            w.Write((uint)(HeaderSizeV2 + PolicySize));
            w.Write(bucketCount);
            w.Write((uint)n);
            w.Write(0u);                            // payload_crc32, patched below
            w.Write(fileSize);
            w.Write((uint)componentCount);
            w.Write((uint)keep.Count);              // 64: portal_count
            w.Write(portalsOffset);                 // 68: portals_offset
            w.Write((ushort)EdgeRec);               // 72
            w.Write((ushort)PortalRec);             // 74
            w.Write(0u);                            // 76: reserved
            while (ms.Position < HeaderSizeV2) w.Write((byte)0);

            w.Write((float)opt.AgentRadius);
            w.Write((float)AgentHeight);
            w.Write(0.15f);
            w.Write(0.50f);
            w.Write((float)opt.MaxUpGrade);
            w.Write((float)opt.MaxDownGrade);
            w.Write((float)opt.MaxStepUp);
            w.Write((float)opt.MaxStepDown);
            w.Write((float)opt.MaxDrop);
            // The radius is spent ONCE, by the erosion above. This is the floor on
            // a certified interval's own length, not a second helping of radius --
            // demanding the radius twice is what made a tenth of the walked zone
            // look unreachable.
            w.Write(0.05f);                         // min safe span
            w.Write(4.0f);
            w.Write((float)GridCell);
            // 0x1 PORTAL_CAPACITY | 0x2 HAZARD_MARGIN: every serialized interval has
            // been trimmed by AgentRadius + 1.5 from lateral slide hazards. The
            // loader pins both bits and builder revision 4 so an untrimmed
            // artifact cannot be opened by a runtime that assumes the margin.
            w.Write(3u);                            // policy_flags: PORTAL_CAPACITY | HAZARD_MARGIN
            w.Write(sourceCrc);
            w.Write(4u);                            // builder_revision: 4 = hazard-margin trimmed portals
            w.Write((uint)Math.Round(opt.WeldTolerance * 1000.0));

            w.Write(minX); w.Write(minZ); w.Write((float)GridCell);
            w.Write(gw); w.Write(gh);
            w.Write(bucketsOffset); w.Write(entriesOffset); w.Write(0u);

            int ec = 0;
            for (int i = 0; i < n; i++)
            {
                w.Write(tris[i].Cx); w.Write(tris[i].Cz); w.Write(tris[i].Cy);
                w.Write((uint)ec);
                w.Write((uint)component[i]);
                w.Write((uint)i);
                w.Write((ushort)edges[i].Count);
                w.Write((ushort)0);
                w.Write(clearance[i]);
                ec += edges[i].Count;
            }

            long unbound = 0;
            for (int i = 0; i < n; i++)
            for (int k = 0; k < edges[i].Count; k++)
            {
                int j = edges[i][k];
                double dx = tris[j].Cx - tris[i].Cx, dz = tris[j].Cz - tris[i].Cz;
                double run = Math.Sqrt(dx * dx + dz * dz);
                double rise = tris[i].Cy - tris[j].Cy;
                short riseCm = (short)Math.Clamp(Math.Round(rise * 100.0), short.MinValue, short.MaxValue);

                // Each edge names the doorway IT crosses. Choosing the widest per
                // node pair here is what left 2114 certified components in the file
                // with no edge pointing at them -- present, and unreachable.
                int chosen = outPortal[i][k] >= 0 ? remap[outPortal[i][k]] : -1;
                if (chosen < 0) unbound++;

                w.Write((uint)j);
                w.Write((float)Math.Sqrt(run * run + rise * rise));
                w.Write(riseCm);
                w.Write((ushort)Math.Clamp(Math.Round(run * 100.0), 0, ushort.MaxValue));
                w.Write((ushort)(riseCm >= 0 ? 1 : 3));
                w.Write((ushort)0);                 // reserved
                w.Write((uint)(chosen < 0 ? 0xFFFFFFFF : (uint)chosen));
            }

            foreach (int pi in keep)
            {
                var pt = portals[pi];
                w.Write((uint)pt.A); w.Write((uint)pt.B);
                w.Write(pt.LeftX);  w.Write(pt.LeftZ);
                w.Write(pt.RightX); w.Write(pt.RightZ);
                w.Write(pt.LeftYA); w.Write(pt.LeftYB);
                w.Write(pt.RightYA); w.Write(pt.RightYB);
                w.Write((ushort)Math.Clamp(pt.CapacityCm, 0, ushort.MaxValue));
                w.Write((ushort)pt.Flags);
                w.Write(0u);
            }

            for (int b = 0; b < bucketCount; b++) { w.Write((uint)first[b]); w.Write((uint)counts[b]); }
            for (int i = 0; i < n; i++) w.Write((uint)entries[i]);

            var bytes = ms.ToArray();
            uint crc = Crc32(bytes, HeaderSizeV2, bytes.Length - HeaderSizeV2);
            BitConverter.TryWriteBytes(bytes.AsSpan(52, 4), crc);
            File.WriteAllBytes(path, bytes);

            Console.WriteLine($"graph: AXWG v2 portals={keep.Count} edges={totalEdges} " +
                              $"unbound_walk_edges={unbound} crc={crc:X8}");
            if (unbound > 0)
                Console.WriteLine($"graph: WARNING {unbound} WALK edges have no certified portal");
        }

        private static void WriteBinary(string path, List<Tri> tris, List<int>[] edges,
                                        float[][] gate, float[] clearance, int[] component, int componentCount,
                                        uint sourceCrc, Options opt)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)) ?? ".");

            int n = tris.Count;
            int totalEdges = 0;
            for (int i = 0; i < n; i++) totalEdges += edges[i].Count;

            float minX = float.MaxValue, minZ = float.MaxValue;
            float maxX = float.MinValue, maxZ = float.MinValue;
            for (int i = 0; i < n; i++)
            {
                if (tris[i].Cx < minX) minX = tris[i].Cx;
                if (tris[i].Cx > maxX) maxX = tris[i].Cx;
                if (tris[i].Cz < minZ) minZ = tris[i].Cz;
                if (tris[i].Cz > maxZ) maxZ = tris[i].Cz;
            }
            // Snap the origin DOWN to a whole grid cell before binning. Codex
            // found 2240 nodes landing in the neighbouring bucket: the builder
            // was binning against an unsnapped minimum while the Lua loader
            // recomputes from the serialized float, and the two disagreed at
            // cell boundaries. A multiple of 8 is exactly representable as a
            // float in this coordinate range, so both sides now agree bit for
            // bit. Bin in float, exactly as the reader will.
            minX = (float)(Math.Floor(minX / GridCell) * GridCell);
            minZ = (float)(Math.Floor(minZ / GridCell) * GridCell);

            uint gw = (uint)Math.Max(1, (int)Math.Ceiling((maxX - minX) / GridCell) + 1);
            uint gh = (uint)Math.Max(1, (int)Math.Ceiling((maxZ - minZ) / GridCell) + 1);
            uint bucketCount = gw * gh;

            var counts = new int[bucketCount];
            var bucketOf = new int[n];
            for (int i = 0; i < n; i++)
            {
                uint cx = (uint)Math.Min(gw - 1, Math.Max(0,
                    (int)Math.Floor((tris[i].Cx - minX) / (float)GridCell)));
                uint cz = (uint)Math.Min(gh - 1, Math.Max(0,
                    (int)Math.Floor((tris[i].Cz - minZ) / (float)GridCell)));
                int b = (int)(cz * gw + cx);
                bucketOf[i] = b;
                counts[b]++;
            }
            var first = new int[bucketCount];
            int running = 0;
            for (int b = 0; b < bucketCount; b++) { first[b] = running; running += counts[b]; }
            var fill = new int[bucketCount];
            var entries = new int[n];
            for (int i = 0; i < n; i++) entries[first[bucketOf[i]] + fill[bucketOf[i]]++] = i;

            const int HeaderSize = 64, PolicySize = 64, NodeSize = 32, EdgeSize = 16, GridSize = 32;
            uint nodesOffset  = HeaderSize + PolicySize + GridSize;
            uint edgesOffset  = (uint)(nodesOffset + (long)n * NodeSize);
            uint bucketsOffset = (uint)(edgesOffset + (long)totalEdges * EdgeSize);
            uint entriesOffset = (uint)(bucketsOffset + (long)bucketCount * 8);
            uint fileSize      = (uint)(entriesOffset + (long)n * 4);

            using var ms = new MemoryStream((int)fileSize);
            using var w = new BinaryWriter(ms);

            // --- header (64 bytes) ---
            w.Write((byte)'A'); w.Write((byte)'X'); w.Write((byte)'W'); w.Write((byte)'G');
            w.Write((ushort)1);            // version
            w.Write((ushort)HeaderSize);
            w.Write(0x01020304u);          // endian tag
            w.Write((uint)opt.ZoneId);
            // DIRECTED=1, Y_DOWN=2, GRID=4. CAPSULE_VERIFIED and HAS_DROPS stay
            // CLEAR: clearance here is a graph-distance approximation, not a
            // swept capsule, and v1 emits no unsupported drops.
            w.Write(1u | 2u | 4u);
            w.Write((uint)n);
            w.Write((uint)totalEdges);
            w.Write(nodesOffset);
            w.Write(edgesOffset);
            w.Write((uint)HeaderSize);     // policy_offset
            w.Write((uint)(HeaderSize + PolicySize));   // grid_offset
            w.Write(bucketCount);
            w.Write((uint)n);              // grid_entry_count
            w.Write(0u);                   // payload_crc32, patched below
            w.Write(fileSize);
            w.Write((uint)componentCount);
            while (ms.Position < HeaderSize) w.Write((byte)0);

            // --- policy (64 bytes), grades as rise/run ratios not degrees ---
            // Declare the grades ADMISSION actually used (opt.MaxUpGrade /
            // opt.MaxDownGrade at the edge filter), never a value recomputed
            // from MaxSlopeDeg. Recomputing made the up field right only by
            // coincidence -- the build passed --upgrade tan(33), which equals
            // the recomputed number -- while the down field claimed 0.6494
            // against admission at 1.0. That put 77 descent edges outside the
            // file's own declared policy, so any loader enforcing the header
            // would reject a file the builder considered correct.
            w.Write((float)opt.AgentRadius);
            w.Write(1.8f);                          // agent_height
            w.Write(0.15f);                         // support_sample_step
            w.Write(0.50f);                         // support_smooth_window
            w.Write((float)opt.MaxUpGrade);
            w.Write((float)opt.MaxDownGrade);       // max_continuous_down_grade
            w.Write((float)opt.MaxStepUp);
            w.Write((float)opt.MaxStepDown);
            w.Write((float)opt.MaxDrop);
            w.Write((float)opt.AgentRadius);        // min_clearance
            w.Write(4.0f);                          // max_edge_run, measured max 3.825
            w.Write((float)GridCell);
            // Three builds now exist whose edge clearance field means three
            // different things, and all of them claimed AXWG v1 / revision 1 /
            // flags 0. A loader could not tell them apart, which is how a file
            // with 716 false-safe crossings looked interchangeable with a good
            // one. The file has to say what it is.
            //
            // POLICY_PORTAL_CAPACITY: edge.min_clearance_cm is the capacity of
            // the PORTAL being crossed, not the lesser of two nodes' distance
            // from a wall. Absent this bit, assume the old node-derived meaning.
            w.Write(1u);                            // policy_flags
            w.Write(sourceCrc);                     // source_obj_crc32
            w.Write(2u);                            // builder_revision: portal capacity
            // Weld tolerance in MILLIMETRES. It is not a cosmetic setting -- at
            // 0.25 it creates topology rather than repairing seams, and two files
            // built at different tolerances are not comparable artifacts.
            w.Write((uint)Math.Round(opt.WeldTolerance * 1000.0));

            // --- grid (32 bytes) ---
            w.Write(minX); w.Write(minZ); w.Write((float)GridCell);
            w.Write(gw); w.Write(gh);
            w.Write(bucketsOffset); w.Write(entriesOffset); w.Write(0u);

            // --- nodes (32 bytes each) ---
            int cursor = 0;
            for (int i = 0; i < n; i++)
            {
                w.Write(tris[i].Cx);
                w.Write(tris[i].Cz);
                w.Write(tris[i].Cy);
                w.Write((uint)cursor);              // first_edge
                w.Write((uint)component[i]);
                w.Write((uint)i);                   // source_ref
                w.Write((ushort)edges[i].Count);
                w.Write((ushort)0);                 // flags
                w.Write(clearance[i]);
                cursor += edges[i].Count;
            }

            // --- edges (16 bytes each) ---
            for (int i = 0; i < n; i++)
            {
                for (int k = 0; k < edges[i].Count; k++)
                {
                    int j = edges[i][k];
                    double dx = tris[j].Cx - tris[i].Cx, dz = tris[j].Cz - tris[i].Cz;
                    double run = Math.Sqrt(dx * dx + dz * dz);
                    double rise = tris[i].Cy - tris[j].Cy;      // y down: + is climbing
                    double cost = Math.Sqrt(run * run + rise * rise);
                    // Derive the flag from the QUANTIZED rise, not the double.
                    // A rise of -0.002 stores as riseCm 0 but reads as "rise < 0",
                    // so a consumer checking the stored field disagreed with the
                    // stored flag on 2213 edges. Nothing about the terrain --
                    // purely the file contradicting itself.
                    short riseCm = (short)Math.Clamp(Math.Round(rise * 100.0),
                                                     short.MinValue, short.MaxValue);
                    w.Write((uint)j);
                    w.Write((float)cost);
                    w.Write(riseCm);
                    w.Write((ushort)Math.Clamp(Math.Round(run * 100.0), 0, ushort.MaxValue));
                    // The width of the doorway being crossed, NOT the smaller of
                    // the two centroids' distance from a wall. See the gate
                    // computation in Run() for why the latter is the wrong
                    // question and how badly it scored real walked ground.
                    w.Write((ushort)Math.Clamp(Math.Floor(gate[i][k] * 100.0),
                                               0, ushort.MaxValue));
                    w.Write((ushort)(riseCm >= 0 ? 1 : 3));     // WALK, or WALK|STEP_DOWN
                }
            }

            // --- grid buckets and entries ---
            for (int b = 0; b < bucketCount; b++) { w.Write((uint)first[b]); w.Write((uint)counts[b]); }
            for (int i = 0; i < n; i++) w.Write((uint)entries[i]);

            var bytes = ms.ToArray();
            uint crc = Crc32(bytes, HeaderSize, bytes.Length - HeaderSize);
            BitConverter.TryWriteBytes(bytes.AsSpan(52, 4), crc);   // payload_crc32 slot
            File.WriteAllBytes(path, bytes);

            Console.WriteLine($"graph: grid={gw}x{gh} cell={GridCell} buckets={bucketCount} crc={crc:X8}");
        }

        private static uint Crc32(byte[] data, int offset, int length)
        {
            uint crc = 0xFFFFFFFFu;
            for (int i = offset; i < offset + length; i++)
            {
                crc ^= data[i];
                for (int k = 0; k < 8; k++)
                    crc = (crc >> 1) ^ (0xEDB88320u & (uint)(-(int)(crc & 1)));
            }
            return ~crc;
        }
    }
}
