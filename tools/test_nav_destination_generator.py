from __future__ import annotations

import hashlib
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import generate_nav_zoneline_destinations as navgen


class NavDestinationGeneratorTests(unittest.TestCase):
    def test_default_repo_root_is_the_checkout_containing_the_generator(self) -> None:
        expected = Path(navgen.__file__).resolve().parents[1]

        self.assertEqual(navgen.ROOT, expected)

    def test_seven_nine_and_appended_schemas_preserve_the_first_nine_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "destinations.tsv"
            path.write_text(
                "101\tLegacy\t1\t2\t3\tnpc\tmanual\n"
                "101\tCurrent\t4\t5\t6\tobject\tmanual\tobserved\tnote\n"
                "101\tAppended\t7\t8\t9\tarea\tlsb-zoneline-all\tuntested\tsection\t"
                "area:v1:101:987\tlsb:zonelines:987\t\t\n",
                encoding="utf-8",
            )

            _lines, rows = navgen.read_destinations(path)

        first_nine = [
            (row.zone, row.name, row.x, row.z, row.y, row.kind, row.source, row.confidence, row.section)
            for row in rows
        ]
        self.assertEqual(
            first_nine,
            [
                (101, "Legacy", 1.0, 2.0, 3.0, "npc", "manual", "", ""),
                (101, "Current", 4.0, 5.0, 6.0, "object", "manual", "observed", "note"),
                (101, "Appended", 7.0, 8.0, 9.0, "area", "lsb-zoneline-all", "untested", "section"),
            ],
        )
        self.assertEqual(getattr(rows[0], "destination_id", ""), "")
        self.assertEqual(getattr(rows[1], "destination_id", ""), "")
        self.assertEqual(getattr(rows[2], "destination_id", ""), "area:v1:101:987")
        self.assertEqual(getattr(rows[2], "raw_identity", ""), "lsb:zonelines:987")
        self.assertEqual(getattr(rows[2], "raw_spawn_ids", ()), ())
        self.assertEqual(getattr(rows[2], "cluster_policy_version", ""), "")

    def test_static_ids_use_only_schema_kind_zone_and_exact_raw_identity(self) -> None:
        make_id = getattr(navgen, "static_destination_id", None)
        self.assertTrue(callable(make_id), "static identity builder is missing")
        assert make_id is not None

        original = make_id("npc", 230, "lsb:npc_list:17719394", schema_revision="v1")
        moved_or_renamed = make_id("npc", 230, "lsb:npc_list:17719394", schema_revision="v1")
        revised = make_id("npc", 230, "lsb:npc_list:17719394", schema_revision="v2")

        self.assertEqual(original, "npc:v1:230:17719394")
        self.assertEqual(moved_or_renamed, original)
        self.assertEqual(revised, "npc:v2:230:17719394")
        self.assertNotEqual(revised, original)
        self.assertEqual(
            make_id("object", 239, "lsb:npc_list:17756172", schema_revision="v1"),
            "object:v1:239:17756172",
        )
        self.assertEqual(
            make_id("area", 101, "lsb:zonelines:880095866", schema_revision="v1"),
            "area:v1:101:880095866",
        )

    def test_malformed_stable_destination_aborts_refresh(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "destinations.tsv"
            path.write_text(
                "101\tValid\t1\t2\t3\tnpc\tmanual\n"
                "101\tMalformed coordinate\tnot-a-number\t2\t3\tnpc\tmanual\n",
                encoding="utf-8",
            )

            with self.assertRaises(ValueError):
                navgen.read_destinations(path)

    def test_npc_rows_retain_the_exact_lsb_record_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "npc_list.sql"
            path.write_text(
                "INSERT INTO `npc_list` VALUES "
                "(17719394,'Ambrotien','Ambrotien',0,93.419,0.999,-57.347,0,50,50,0,0,0,2,3,"
                "0x0000320000000000000000000000000000000000,0,NULL,0,0);\n",
                encoding="utf-8",
            )

            rows = navgen.parse_npc_list(path)

        self.assertEqual(len(rows), 1)
        self.assertEqual(getattr(rows[0], "raw_identity", ""), "lsb:npc_list:17719394")
        self.assertEqual(getattr(rows[0], "destination_id", ""), "npc:v1:230:17719394")

    def test_object_and_area_rows_keep_raw_ids_without_geometry_in_their_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "npc_list.sql"
            path.write_text(
                "INSERT INTO `npc_list` VALUES "
                "(17756172,'Door_Orastery','Door:Orastery',0,10.000,0.000,20.000,0,50,50,0,0,0,2,3,"
                "0x0000320000000000000000000000000000000000,0,NULL,0,0);\n",
                encoding="utf-8",
            )
            object_row = navgen.parse_npc_list(path)[0]

        edge = navgen.ZoneLine(
            zoneline_id=880095866,
            from_zone=102,
            from_x=1.0,
            from_y=2.0,
            from_z=3.0,
            to_zone=103,
            to_x=4.0,
            to_y=5.0,
            to_z=6.0,
            from_label="La Theine Plateau",
            from_code="z660",
            to_label="Valkurm Dunes",
            to_code="z670",
            note="",
            comment="fixture",
        )
        area_row = navgen.generated_destination(edge, "Valkurm Dunes zone line")

        self.assertEqual(object_row.kind, "object")
        self.assertEqual(getattr(object_row, "raw_identity", ""), "lsb:npc_list:17756172")
        self.assertEqual(getattr(object_row, "destination_id", ""), "object:v1:239:17756172")
        self.assertEqual(getattr(object_row, "cluster_policy_version", ""), "")
        self.assertEqual(getattr(area_row, "raw_identity", ""), "lsb:zonelines:880095866")
        self.assertEqual(getattr(area_row, "destination_id", ""), "area:v1:102:880095866")
        self.assertEqual(getattr(area_row, "cluster_policy_version", ""), "")

    @staticmethod
    def _mob_sql(ids_and_points: list[tuple[int, float, float, float]]) -> str:
        return "".join(
            (
                "INSERT INTO `mob_spawn_points` VALUES "
                f"({mobid},0,'Orcish_Fodder','Orcish Fodder',34,1,2,{x:.3f},{y:.3f},{z:.3f},0);\n"
            )
            for mobid, x, y, z in ids_and_points
        )

    @staticmethod
    def _parse_single_mob_x(expression: str) -> float:
        zone_base = 169 << 12
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "mob_spawn_points.sql"
            path.write_text(
                "INSERT INTO `mob_spawn_points` VALUES "
                f"({zone_base + 32},0,'Numeric','Numeric',1,1,1,{expression},3,4,0);\n",
                encoding="utf-8",
            )
            return navgen.parse_mob_spawn_points(path)[0].x

    def test_complete_link_clustering_conserves_ids_splits_chains_and_floors(self) -> None:
        zone_base = 101 << 12
        fixture = [
            (zone_base + 1, 10.0, 0.0, 1.0),
            (zone_base + 2, 90.0, 0.0, 1.0),
            (zone_base + 3, 170.0, 0.0, 1.0),
            (zone_base + 4, 10.0, 30.0, 1.0),
        ]

        def build(order: list[tuple[int, float, float, float]]):
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "mob_spawn_points.sql"
                path.write_text(self._mob_sql(order), encoding="utf-8")
                return navgen.cluster_enemy_camps(navgen.parse_mob_spawn_points(path))

        first = build(fixture)
        shuffled_fixture = list(fixture)
        random.Random(8675309).shuffle(shuffled_fixture)
        shuffled = build(shuffled_fixture)

        expected_ids = tuple(sorted(mobid for mobid, *_point in fixture))
        actual_ids = tuple(sorted(raw_id for camp in first for raw_id in getattr(camp, "raw_spawn_ids", ())))
        partitions = sorted(tuple(getattr(camp, "raw_spawn_ids", ())) for camp in first)
        shuffled_partitions = sorted(tuple(getattr(camp, "raw_spawn_ids", ())) for camp in shuffled)

        self.assertEqual(actual_ids, expected_ids)
        self.assertEqual(partitions, [(zone_base + 1, zone_base + 2), (zone_base + 3,), (zone_base + 4,)])
        self.assertEqual(shuffled_partitions, partitions)
        self.assertEqual(
            sorted(getattr(camp, "destination_id", "") for camp in shuffled),
            sorted(getattr(camp, "destination_id", "") for camp in first),
        )
        self.assertTrue(
            all(
                getattr(camp, "cluster_policy_version", "")
                == getattr(navgen, "ENEMY_CLUSTER_POLICY_VERSION", None)
                for camp in first
            )
        )

        by_id = {mobid: (x, y, z) for mobid, x, y, z in fixture}
        for camp in first:
            ids = tuple(getattr(camp, "raw_spawn_ids", ()))
            for index, left_id in enumerate(ids):
                for right_id in ids[index + 1 :]:
                    left = by_id[left_id]
                    right = by_id[right_id]
                    horizontal = ((left[0] - right[0]) ** 2 + (left[2] - right[2]) ** 2) ** 0.5
                    self.assertLessEqual(horizontal, 120.0)
                    self.assertLessEqual(abs(left[1] - right[1]), 24.0)

    def test_orcish_fodder_east_west_raw_fixture_is_conserved_bounded_and_shuffle_stable(self) -> None:
        # Exact active LandSandBoat source records used by the pinned Orcish Scouts review.
        # Fields are mobid, groupid, x, y, z; all records are levels 3-8.
        raw_rows = (
            (17186886, 12, -452.464, -50.248, 328.077),
            (17186903, 12, -366.087, -52.215, 215.323),
            (17186909, 12, -289.602, -39.223, 137.827),
            (17186921, 12, -299.000, -37.000, 136.000),
            (17186922, 12, -364.029, -39.683, 75.880),
            (17186933, 12, -623.685, -60.867, 515.693),
            (17186934, 12, -551.982, -57.411, 490.599),
            (17186942, 12, -506.264, -63.156, 499.804),
            (17186945, 12, -572.030, -61.785, 465.120),
            (17186948, 12, -686.695, -62.956, 571.229),
            (17186951, 12, -284.394, -60.339, 399.875),
            (17186952, 12, -641.506, -61.714, 545.992),
            (17186954, 12, -655.000, -62.000, 544.000),
            (17186981, 12, -570.453, -43.341, 177.916),
            (17187013, 12, -251.174, -32.634, 18.299),
            (17187034, 12, -343.971, -23.195, -85.691),
            (17187056, 12, -167.142, -20.261, -151.021),
            (17187076, 12, -443.646, -32.196, -20.914),
            (17187087, 12, -502.975, -30.850, -25.544),
            (17187103, 12, -492.824, -20.263, -193.635),
            (17187122, 12, -427.064, -20.484, -268.616),
            (17190987, 13, 231.425, -40.400, 45.023),
            (17190988, 13, 223.272, -49.865, 138.079),
            (17191007, 13, 289.535, -50.375, 150.856),
            (17191008, 13, 300.724, -40.949, 94.131),
            (17191036, 13, 351.789, -21.110, -152.175),
            (17191153, 13, 480.248, -30.544, -55.194),
            (17191174, 13, 280.287, -20.181, -313.448),
            (17191184, 13, 385.000, -19.000, -183.000),
            (17191204, 13, 467.998, -18.949, -210.121),
            (17191228, 13, 226.858, -19.627, -335.959),
            (17191273, 13, 392.228, -19.185, -330.174),
        )

        def build(rows: list[tuple[int, int, float, float, float]]):
            sql = "".join(
                "INSERT INTO `mob_spawn_points` VALUES "
                f"({mobid},0,'Orcish_Fodder','Orcish Fodder',{groupid},3,8,{x:.3f},{y:.3f},{z:.3f},0);\n"
                for mobid, groupid, x, y, z in rows
            )
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "mob_spawn_points.sql"
                path.write_text(sql, encoding="utf-8")
                spawns = navgen.parse_mob_spawn_points(path)
            return spawns, navgen.cluster_enemy_camps(spawns)

        source_rows = list(raw_rows)
        first_spawns, first_camps = build(source_rows)
        shuffled_rows = list(raw_rows)
        random.Random(20260809).shuffle(shuffled_rows)
        shuffled_spawns, shuffled_camps = build(shuffled_rows)

        expected_ids = tuple(sorted(row[0] for row in raw_rows))
        self.assertEqual(len([spawn for spawn in first_spawns if spawn.zone == 100]), 21)
        self.assertEqual(len([spawn for spawn in first_spawns if spawn.zone == 101]), 11)
        self.assertEqual(len([camp for camp in first_camps if camp.zone == 100]), 12)
        self.assertEqual(len([camp for camp in first_camps if camp.zone == 101]), 7)
        self.assertEqual(
            tuple(sorted(raw_id for camp in first_camps for raw_id in camp.raw_spawn_ids)),
            expected_ids,
        )
        self.assertEqual(
            tuple(sorted(raw_id for camp in shuffled_camps for raw_id in camp.raw_spawn_ids)),
            expected_ids,
        )
        self.assertEqual(
            sorted((camp.zone, camp.raw_spawn_ids, camp.destination_id) for camp in shuffled_camps),
            sorted((camp.zone, camp.raw_spawn_ids, camp.destination_id) for camp in first_camps),
        )

        points = {spawn.mobid: spawn for spawn in first_spawns}
        for camp in first_camps:
            members = [points[raw_id] for raw_id in camp.raw_spawn_ids]
            for index, left in enumerate(members):
                for right in members[index + 1 :]:
                    horizontal = ((left.x - right.x) ** 2 + (left.z - right.z) ** 2) ** 0.5
                    self.assertLessEqual(horizontal, navgen.MOB_CLUSTER_DISTANCE_YALMS)
                    self.assertLessEqual(abs(left.y - right.y), navgen.MOB_CLUSTER_Y_DISTANCE_YALMS)

    def test_enemy_identity_uses_raw_mobname_sorted_ids_and_policy_not_display_or_coordinates(self) -> None:
        zone_base = 101 << 12
        first_rows = [
            (zone_base + 9, 10.0, 0.0, 1.0),
            (zone_base + 2, 30.0, 0.0, 1.0),
        ]

        def parsed(sql: str):
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "mob_spawn_points.sql"
                path.write_text(sql, encoding="utf-8")
                return navgen.parse_mob_spawn_points(path)

        original = parsed(self._mob_sql(first_rows))
        changed_display_and_geometry_sql = "".join(
            (
                "INSERT INTO `mob_spawn_points` VALUES "
                f"({mobid},0,'Orcish_Fodder','Display Name Changed',34,1,2,{x + 5:.3f},{y:.3f},{z + 5:.3f},0);\n"
            )
            for mobid, x, y, z in reversed(first_rows)
        )
        changed = parsed(changed_display_and_geometry_sql)
        make_camp = navgen.enemy_camp_destination
        try:
            original_camp = make_camp(original, policy_version="complete-link-v1-h120-y24")
            changed_camp = make_camp(changed, policy_version="complete-link-v1-h120-y24")
            revised_policy_camp = make_camp(original, policy_version="complete-link-v2-h100-y20")
        except TypeError as error:
            self.fail(f"enemy camp identity does not accept an explicit policy version: {error}")

        self.assertEqual(
            getattr(original_camp, "raw_identity", ""),
            "lsb:mob_spawn_points:group:34:mobname:Orcish_Fodder",
        )
        self.assertEqual(
            getattr(original_camp, "raw_spawn_ids", ()),
            (zone_base + 2, zone_base + 9),
        )
        self.assertEqual(original_camp.destination_id, changed_camp.destination_id)
        self.assertNotEqual(original_camp.destination_id, revised_policy_camp.destination_id)
        self.assertTrue(original_camp.destination_id.startswith("camp:v1:101:orcish-fodder:"))

    def test_clustering_rejects_a_policy_version_without_matching_geometry(self) -> None:
        zone_base = 101 << 12
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "mob_spawn_points.sql"
            path.write_text(
                self._mob_sql(
                    [
                        (zone_base + 1, 0.0, 0.0, 0.0),
                        (zone_base + 2, 110.0, 0.0, 0.0),
                    ]
                ),
                encoding="utf-8",
            )
            spawns = navgen.parse_mob_spawn_points(path)

        with self.assertRaises(ValueError):
            navgen.cluster_enemy_camps(
                spawns,
                policy_version="complete-link-v2-h100-y20",
            )

    def test_mob_parser_accounts_for_arithmetic_rows_and_ignores_commented_inserts(self) -> None:
        zone_base = 169 << 12
        active_arithmetic_id = zone_base + 26
        active_normal_id = zone_base + 27
        placeholder_id = zone_base + 28
        commented_id = zone_base + 29
        fixture = (
            "-- INSERT INTO `mob_spawn_points` VALUES "
            f"({commented_id},0,'Commented','Commented',1,1,1,1*2,3,4,0);\n"
            "INSERT INTO `mob_spawn_points` VALUES "
            f"({active_arithmetic_id},0,'Arithmetic_Mob','Arithmetic Mob',6,62,64,-464.527-320,-167.58-240,-241.576-240,0);\n"
            "  INSERT INTO `mob_spawn_points` VALUES "
            f"({active_normal_id},0,'Normal_Mob','Normal Mob',7,20,21,10.5,-2.0,30.25,0); -- valid inline note\n"
            "INSERT INTO `mob_spawn_points` VALUES "
            f"({placeholder_id},0,'Position_Placeholder','Position Placeholder',8,1,1,0,4,0,0);\n"
        )
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "mob_spawn_points.sql"
            path.write_text(fixture, encoding="utf-8")
            audit = navgen.audit_mob_spawn_points(path)

        self.assertEqual(audit.active_insert_count, 3)
        self.assertEqual(len(audit.spawns), 2)
        self.assertEqual(
            [
                (spawn.mobid, round(spawn.x, 3), round(spawn.y, 3), round(spawn.z, 3))
                for spawn in audit.spawns
            ],
            [
                (active_arithmetic_id, -784.527, -407.58, -481.576),
                (active_normal_id, 10.5, -2.0, 30.25),
            ],
        )
        self.assertEqual(
            [(item.mobid, item.reason) for item in audit.exclusions],
            [(placeholder_id, "placeholder-position")],
        )
        self.assertEqual(audit.active_insert_count, len(audit.spawns) + len(audit.exclusions))

    def test_mob_parser_rejects_unsupported_active_numeric_expression(self) -> None:
        zone_base = 169 << 12
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "mob_spawn_points.sql"
            path.write_text(
                "INSERT INTO `mob_spawn_points` VALUES "
                f"({zone_base + 30},0,'Unsafe','Unsafe',1,1,1,1*2,3,4,0);\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "unsupported numeric expression"):
                navgen.parse_mob_spawn_points(path)

    def test_mob_parser_rejects_non_finite_additive_result(self) -> None:
        zone_base = 169 << 12
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "mob_spawn_points.sql"
            path.write_text(
                "INSERT INTO `mob_spawn_points` VALUES "
                f"({zone_base + 31},0,'Overflow','Overflow',1,1,1,1e999,3,4,0);\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "non-finite numeric expression"):
                navgen.parse_mob_spawn_points(path)

    def test_mob_parser_rejects_adjacent_decimal_tokens(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported numeric expression"):
            self._parse_single_mob_x("1.2.3")

    def test_mob_parser_rejects_fraction_after_exponent(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported numeric expression"):
            self._parse_single_mob_x("1e2.5")

    def test_mob_parser_rejects_whitespace_joined_tokens(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported numeric expression"):
            self._parse_single_mob_x("1 2")

    def test_mob_parser_accepts_signed_additive_exponents(self) -> None:
        self.assertEqual(self._parse_single_mob_x(" -1e2 - 2.5e-1 "), -100.25)

    def test_npc_parser_ignores_commented_insert_like_rows(self) -> None:
        commented_id = (230 << 12) + 401
        active_id = (230 << 12) + 402
        row_tail = ",'Ambrotien','Ambrotien',0,93.419,0.999,-57.347,0,50,50,0,0,0,0,0,0x00,32,NULL,1);\n"
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "npc_list.sql"
            path.write_text(
                "-- INSERT INTO `npc_list` VALUES (" + str(commented_id) + row_tail
                + "INSERT INTO `npc_list` VALUES (" + str(active_id) + row_tail,
                encoding="utf-8",
            )

            rows = navgen.parse_npc_list(path)

        self.assertEqual([row.raw_identity for row in rows], [f"lsb:npc_list:{active_id}"])

    def test_enemy_camp_harness_imports_tests_from_selected_root_outside_caller_cwd(self) -> None:
        repo_root = Path(navgen.__file__).resolve().parents[1]
        harness = repo_root / "tools" / "test_nav_enemy_camps.ps1"
        with tempfile.TemporaryDirectory() as temporary:
            completed = subprocess.run(
                [
                    "powershell.exe",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(harness),
                    "-Root",
                    str(repo_root),
                ],
                cwd=temporary,
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )

        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )
        self.assertIn("nav enemy camp checks ok", completed.stdout)

    def test_paired_destination_writes_are_repo_scoped_and_byte_identical(self) -> None:
        writer = getattr(navgen, "write_destination_copies", None)
        self.assertTrue(callable(writer), "paired atomic destination writer is missing")
        assert writer is not None

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "selected-repo"
            root_copy = root / "data" / "ffxi-nav-destinations.tsv"
            addon_copy = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-destinations.tsv"
            root_graph = root / "data" / "ffxi-nav-zoneline-graph.tsv"
            addon_graph = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-zoneline-graph.tsv"
            root_copy.parent.mkdir(parents=True)
            addon_copy.parent.mkdir(parents=True)
            original = (
                "101\tManual\t1\t2\t3\tnpc\tmanual\n"
                "101\tRetained appended\t2\t3\t4\tobject\tmanual\tobserved\tnote\t"
                "object:v1:101:77\tlsb-npc-list-all\t\t\n"
            )
            root_copy.write_text(original, encoding="utf-8")
            addon_copy.write_text(original, encoding="utf-8")
            graph_bytes = b"proven\tgraph\tevidence\n"
            root_graph.write_bytes(graph_bytes)
            addon_graph.write_bytes(graph_bytes)
            lines, _rows = navgen.read_destinations(root_copy)
            generated = [
                navgen.Destination(
                    101,
                    "Generated",
                    4.0,
                    5.0,
                    6.0,
                    "npc",
                    navgen.GENERATED_NPC_SOURCE,
                    "untested",
                    navgen.GENERATED_NPC_SECTION,
                    destination_id="npc:v1:101:413697",
                    raw_identity="lsb:npc_list:413697",
                )
            ]

            written_hash = writer(root, lines, generated)

            self.assertTrue(root_copy.is_file())
            self.assertTrue(addon_copy.is_file())
            self.assertEqual(root_copy.read_bytes(), addon_copy.read_bytes())
            self.assertEqual(written_hash, hashlib.sha256(root_copy.read_bytes()).hexdigest())
            self.assertIn("npc:v1:101:413697", root_copy.read_text(encoding="utf-8"))
            self.assertIn("object:v1:101:77", root_copy.read_text(encoding="utf-8"))
            self.assertEqual(root_graph.read_bytes(), graph_bytes)
            self.assertEqual(addon_graph.read_bytes(), graph_bytes)
            rendered = root_copy.read_bytes()
            self.assertFalse(rendered.startswith(b"\xef\xbb\xbf"))
            self.assertNotIn(b"\r\n", rendered)
            text = rendered.decode("utf-8")
            self.assertNotIn("C:\\Users\\", text)
            generated_line = next(line for line in text.splitlines() if "\tGenerated\t" in line)
            self.assertEqual(len(generated_line.split("\t")), 13)
            self.assertTrue(generated_line.endswith("\t\t"))

    def test_generated_identity_replaces_non_generated_source_override_and_render_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "selected-repo"
            root_copy = root / "data" / "ffxi-nav-destinations.tsv"
            addon_copy = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-destinations.tsv"
            root_graph = root / "data" / "ffxi-nav-zoneline-graph.tsv"
            addon_graph = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-zoneline-graph.tsv"
            root_copy.parent.mkdir(parents=True)
            addon_copy.parent.mkdir(parents=True)
            identity = "area:v1:103:846606970"
            original = (
                "103\tProven override\t1\t2\t3\tarea\troute-recorder\tproven\tlive evidence\t"
                f"{identity}\tlsb:zonelines:846606970\t\t\n"
            )
            root_copy.write_text(original, encoding="utf-8")
            addon_copy.write_text(original, encoding="utf-8")
            root_graph.write_text("proven graph\n", encoding="utf-8")
            addon_graph.write_text("proven graph\n", encoding="utf-8")
            generated = [
                navgen.Destination(
                    103,
                    "Proven override",
                    1.0,
                    2.0,
                    3.0,
                    "area",
                    "route-recorder",
                    "proven",
                    "live evidence",
                    destination_id=identity,
                    raw_identity="lsb:zonelines:846606970",
                )
            ]

            first_lines, _rows = navgen.read_destinations(root_copy)
            navgen.write_destination_copies(root, first_lines, generated)
            first_render = root_copy.read_bytes()
            second_lines, _rows = navgen.read_destinations(root_copy)
            navgen.write_destination_copies(root, second_lines, generated)
            second_render = root_copy.read_bytes()

            self.assertEqual(second_render, first_render)
            identities = [
                fields[9]
                for line in second_render.decode("utf-8").splitlines()
                if line and not line.startswith("#")
                for fields in [line.split("\t")]
                if len(fields) >= 10 and fields[9]
            ]
            self.assertEqual(identities.count(identity), 1)
            self.assertEqual(len(identities), len(set(identities)))

    def test_render_rejects_duplicate_nonempty_destination_ids(self) -> None:
        duplicate = "npc:v1:101:77"
        lines = [
            f"101\tFirst\t1\t2\t3\tnpc\tmanual\tobserved\tnote\t{duplicate}\tlsb:npc_list:77\t\t",
            f"101\tSecond\t4\t5\t6\tnpc\tmanual\tobserved\tnote\t{duplicate}\tlsb:npc_list:77\t\t",
        ]

        with self.assertRaises(ValueError):
            navgen._render_destination_file(lines, [])

    def test_paired_writer_rejects_a_non_repo_root_before_creating_outputs(self) -> None:
        writer = getattr(navgen, "write_destination_copies", None)
        self.assertTrue(callable(writer), "paired atomic destination writer is missing")
        assert writer is not None

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "not-a-repository"
            root.mkdir()
            with self.assertRaises(ValueError):
                writer(root, [], [])
            self.assertEqual(list(root.iterdir()), [])

    def test_paired_writer_refuses_to_discard_a_divergent_addon_copy(self) -> None:
        writer = getattr(navgen, "write_destination_copies", None)
        self.assertTrue(callable(writer), "paired atomic destination writer is missing")
        assert writer is not None

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "selected-repo"
            root_copy = root / "data" / "ffxi-nav-destinations.tsv"
            addon_copy = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-destinations.tsv"
            root_graph = root / "data" / "ffxi-nav-zoneline-graph.tsv"
            addon_graph = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-zoneline-graph.tsv"
            root_copy.parent.mkdir(parents=True)
            addon_copy.parent.mkdir(parents=True)
            root_copy.write_text("101\tRoot\t1\t2\t3\tnpc\tmanual\n", encoding="utf-8")
            addon_copy.write_text("101\tAddon edit\t1\t2\t3\tnpc\tmanual\n", encoding="utf-8")
            root_graph.write_text("graph\n", encoding="utf-8")
            addon_graph.write_text("graph\n", encoding="utf-8")
            before_root = root_copy.read_bytes()
            before_addon = addon_copy.read_bytes()

            with self.assertRaises(ValueError):
                writer(root, root_copy.read_text(encoding="utf-8").splitlines(), [])

            self.assertEqual(root_copy.read_bytes(), before_root)
            self.assertEqual(addon_copy.read_bytes(), before_addon)

    def test_paired_writer_refuses_to_write_when_graph_copies_diverge(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "selected-repo"
            root_copy = root / "data" / "ffxi-nav-destinations.tsv"
            addon_copy = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-destinations.tsv"
            root_graph = root / "data" / "ffxi-nav-zoneline-graph.tsv"
            addon_graph = root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-zoneline-graph.tsv"
            root_copy.parent.mkdir(parents=True)
            addon_copy.parent.mkdir(parents=True)
            destination_bytes = b"101\tManual\t1\t2\t3\tnpc\tmanual\n"
            root_copy.write_bytes(destination_bytes)
            addon_copy.write_bytes(destination_bytes)
            root_graph.write_bytes(b"root graph\n")
            addon_graph.write_bytes(b"addon graph edit\n")

            with self.assertRaisesRegex(ValueError, "graph copies differ"):
                navgen.write_destination_copies(root, destination_bytes.decode().splitlines(), [])

            self.assertEqual(root_copy.read_bytes(), destination_bytes)
            self.assertEqual(addon_copy.read_bytes(), destination_bytes)

    def test_generator_exposes_only_the_checked_paired_destination_write_boundary(self) -> None:
        source = Path(navgen.__file__).read_text(encoding="utf-8")

        self.assertNotIn("def write_destination_file(", source)
        self.assertNotIn("def write_graph(", source)

    def test_manual_nearby_row_does_not_suppress_a_raw_identity_candidate(self) -> None:
        manual = navgen.Destination(
            230,
            "Ambrotien",
            93.419,
            -57.347,
            0.999,
            "npc",
            "manual",
            "observed",
            "manual row",
        )
        generated = navgen.Destination(
            230,
            "Ambrotien",
            93.419,
            -57.347,
            0.999,
            "npc",
            navgen.GENERATED_NPC_SOURCE,
            "untested",
            navgen.GENERATED_NPC_SECTION,
            destination_id="npc:v1:230:17719394",
            raw_identity="lsb:npc_list:17719394",
        )

        kept = navgen.filter_generated_destinations([generated], [manual], 8.0, 8.0)

        self.assertEqual(kept, [generated])

    def test_nearby_manual_areas_cannot_suppress_any_active_zoneline_identity(self) -> None:
        edge_ids = (880095866, 913650298, 947204730)
        edges = [
            navgen.ZoneLine(
                zoneline_id=edge_id,
                from_zone=102,
                from_x=float(index),
                from_y=0.0,
                from_z=float(index),
                to_zone=103 + index,
                to_x=0.0,
                to_y=0.0,
                to_z=0.0,
                from_label="La Theine Plateau",
                from_code=f"z{index}",
                to_label=f"Destination {index}",
                to_code=f"d{index}",
                note="",
                comment="fixture",
            )
            for index, edge_id in enumerate(edge_ids, start=1)
        ]
        manual = navgen.Destination(
            102,
            "Nearby manual exit",
            2.0,
            2.0,
            0.0,
            "area",
            "manual",
            "proven",
            "manual route evidence",
        )

        generated = navgen.generate_destinations(
            edges,
            {102: "La Theine Plateau", 104: "Valkurm Dunes", 105: "Ordelle's Caves", 106: "Ordelle's Caves"},
            [manual],
        )

        self.assertEqual(len(generated), len(edges))
        self.assertEqual(
            {row.destination_id for row in generated},
            {f"area:v1:102:{edge_id}" for edge_id in edge_ids},
        )

    def test_scripted_chateau_gate_is_generator_owned_and_one_way(self) -> None:
        access_note = (
            "requires: Chateau d'Oraguille access; eligibility is enforced by "
            "Northern San d'Oria event 569"
        )
        expected_edge = (
            231233001,
            231,
            "Northern San d'Oria",
            "trigger-area-1",
            0.0,
            -2.0,
            110.0,
            233,
            "Chateau d'Oraguille",
            "event-569",
            0.0,
            0.0,
            -13.0,
            access_note,
        )

        edges = navgen.apply_edge_policy([])
        chateau_edges = [
            edge
            for edge in edges
            if edge.from_zone in {231, 233} and edge.to_zone in {231, 233}
        ]

        self.assertEqual(
            [
                (
                    edge.zoneline_id,
                    edge.from_zone,
                    edge.from_label,
                    edge.from_code,
                    edge.from_x,
                    edge.from_y,
                    edge.from_z,
                    edge.to_zone,
                    edge.to_label,
                    edge.to_code,
                    edge.to_x,
                    edge.to_y,
                    edge.to_z,
                    edge.note,
                )
                for edge in chateau_edges
            ],
            [expected_edge],
        )

        destinations = navgen.generate_destinations(
            edges,
            {231: "Northern San d'Oria", 233: "Chateau d'Oraguille"},
            [],
        )
        self.assertEqual(
            [
                (
                    row.zone,
                    row.name,
                    row.x,
                    row.z,
                    row.y,
                    row.kind,
                    row.source,
                    row.confidence,
                    row.section,
                    row.destination_id,
                    row.raw_identity,
                )
                for row in destinations
            ],
            [
                (
                    231,
                    "Chateau d'Oraguille zone line",
                    0.0,
                    110.0,
                    -2.0,
                    "area",
                    "lsb-scripted-trigger",
                    "proven",
                    access_note,
                    "area:v1:231:231233001",
                    "lsb:scripted_trigger:231233001",
                )
            ],
        )

        repo_root = Path(navgen.__file__).resolve().parents[1]
        expected_graph_row = (
            "231233001\t231\tNorthern San d'Oria\ttrigger-area-1\t0.000\t110.000\t-2.000\t"
            "233\tChateau d'Oraguille\tevent-569\t0.000\t-13.000\t0.000\t"
            f"lsb-scripted-trigger\tproven\t{access_note}"
        )
        for graph_path in (
            repo_root / "data" / "ffxi-nav-zoneline-graph.tsv",
            repo_root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-zoneline-graph.tsv",
        ):
            rows = graph_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual([row for row in rows if row.startswith("231233001\t")], [expected_graph_row])
            self.assertFalse(any(row.startswith("231233001\t233\t") for row in rows))

        expected_destination_row = (
            "231\tChateau d'Oraguille zone line\t0.000\t110.000\t-2.000\tarea\t"
            f"lsb-scripted-trigger\tproven\t{access_note}\tarea:v1:231:231233001\t"
            "lsb:scripted_trigger:231233001\t\t"
        )
        for destination_path in (
            repo_root / "data" / "ffxi-nav-destinations.tsv",
            repo_root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-destinations.tsv",
        ):
            rows = destination_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                [row for row in rows if "\tarea:v1:231:231233001\t" in row],
                [expected_destination_row],
            )

    def test_cli_rejects_another_repo_shaped_root_before_dry_run_or_write(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            other = Path(temporary) / "other-repo"
            root_destination = other / "data" / "ffxi-nav-destinations.tsv"
            addon_destination = other / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-destinations.tsv"
            root_graph = other / "data" / "ffxi-nav-zoneline-graph.tsv"
            addon_graph = other / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-zoneline-graph.tsv"
            third_party = other / "third_party" / "LandSandBoat-server"
            for path in (root_destination, addon_destination, root_graph, addon_graph):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("protected\n", encoding="utf-8")
            (other / "data" / "lsb_zonelines.sql").write_text("", encoding="utf-8")
            (other / "data" / "lsb_npc_list.sql").write_text("", encoding="utf-8")
            (third_party / "sql").mkdir(parents=True)
            (third_party / "documentation").mkdir(parents=True)
            (third_party / "sql" / "mob_spawn_points.sql").write_text("", encoding="utf-8")
            (third_party / "documentation" / "ZoneIDs.txt").write_text("", encoding="utf-8")
            protected = {
                path: path.read_bytes()
                for path in (root_destination, addon_destination, root_graph, addon_graph)
            }

            for mode in ("--dry-run", "--write"):
                completed = subprocess.run(
                    [
                        sys.executable,
                        str(Path(navgen.__file__).resolve()),
                        "--repo-root",
                        str(other),
                        "--third-party-root",
                        str(third_party),
                        mode,
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                with self.subTest(mode=mode):
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertIn("checkout containing this generator", completed.stderr)
                    self.assertTrue(all(path.read_bytes() == content for path, content in protected.items()))


if __name__ == "__main__":
    unittest.main()
