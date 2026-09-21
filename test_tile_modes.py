import unittest

from tile_modes import (
    LayoutError,
    Mode,
    Rect,
    TileModePlanner,
    WindowIdentity,
    WindowSnapshot,
    plan_layout,
)


class TileModePlannerTests(unittest.TestCase):
    def setUp(self):
        self.identity = WindowIdentity(window_id=41, app_pid=812, boot="boot-a")
        self.snapshot = WindowSnapshot(
            identity=self.identity, workspace="2", tile_id="root.left"
        )

    def test_three_modes_are_declarative_and_keep_identity(self):
        planner = TileModePlanner(self.snapshot)

        half = planner.transition(self.identity, Mode.HALF)
        full = planner.transition(self.identity, Mode.FULL)
        small = planner.transition(self.identity, Mode.SMALL)

        self.assertEqual((half.action, half.from_mode, half.to_mode),
                         ("set-half", Mode.SMALL, Mode.HALF))
        self.assertEqual((full.action, full.from_mode, full.to_mode),
                         ("set-full", Mode.HALF, Mode.FULL))
        self.assertEqual((small.action, small.from_mode, small.to_mode),
                         ("restore-tile", Mode.FULL, Mode.SMALL))
        for intent in (half, full, small):
            self.assertEqual(intent.identity, self.identity)
            self.assertEqual(intent.workspace, "2")
            self.assertEqual(intent.tile_id, "root.left")
            self.assertTrue(intent.preserve_session)
        self.assertIsNone(half.geometry)

    def test_same_mode_is_noop(self):
        planner = TileModePlanner(self.snapshot)
        intent = planner.transition(self.identity, Mode.SMALL)
        self.assertEqual(intent.action, "noop")
        self.assertEqual(intent.from_mode, Mode.SMALL)
        self.assertEqual(intent.to_mode, Mode.SMALL)

    def test_stale_identity_resets_without_window_operations(self):
        planner = TileModePlanner(self.snapshot)
        stale = WindowIdentity(window_id=41, app_pid=812, boot="boot-b")

        intent = planner.transition(stale, Mode.FULL)

        self.assertEqual(intent.action, "reset")
        self.assertEqual(intent.to_mode, Mode.SMALL)
        self.assertIn("identity", intent.reason)
        self.assertEqual(planner.mode, Mode.SMALL)

    def test_recycled_window_id_or_pid_is_rejected(self):
        planner = TileModePlanner(self.snapshot)
        for identity in (
            WindowIdentity(99, 812, "boot-a"),
            WindowIdentity(41, 999, "boot-a"),
        ):
            with self.subTest(identity=identity):
                self.assertEqual(
                    planner.transition(identity, Mode.HALF).action, "reset"
                )

    def test_invalid_mode_does_not_emit_launch_or_close(self):
        planner = TileModePlanner(self.snapshot)
        with self.assertRaises(ValueError):
            planner.transition(self.identity, "fullscreen")


class LayoutPlannerTests(unittest.TestCase):
    def test_small_preserves_order_and_uses_two_columns_minimum_two_rows(self):
        plan = plan_layout(["a", "b", "c"], "b", Mode.SMALL, 1000, 800)
        self.assertEqual(list(plan.placements), ["a", "b", "c"])
        self.assertEqual(plan.placements["a"].rect, Rect(0, 0, 496, 396))
        self.assertEqual(plan.placements["b"].rect, Rect(504, 0, 496, 396))
        self.assertEqual(plan.placements["c"].rect, Rect(0, 404, 496, 396))

    def test_single_small_window_is_quarter_size(self):
        plan = plan_layout(["only"], "only", Mode.SMALL, 1000, 800)
        self.assertEqual(plan.placements["only"].rect, Rect(0, 0, 496, 396))

    def test_five_and_six_use_three_rows(self):
        for count in (5, 6):
            with self.subTest(count=count):
                plan = plan_layout([str(i) for i in range(count)], "0", Mode.SMALL, 1000, 800)
                self.assertEqual(plan.placements["4"].rect.y, 538)

    def test_half_selected_is_left_and_right_side_has_no_overlaps(self):
        plan = plan_layout(["a", "b", "c"], "b", Mode.HALF, 1000, 800)
        self.assertEqual(plan.placements["b"].rect, Rect(0, 0, 496, 800))
        self.assertEqual(plan.placements["a"].rect, Rect(504, 0, 496, 396))
        self.assertEqual(plan.placements["c"].rect, Rect(504, 404, 496, 396))
        self.assertEqual(plan.overlaps(), [])

    def test_full_marks_other_windows_occluded(self):
        plan = plan_layout(["a", "b", "c"], "b", Mode.FULL, 1000, 800)
        self.assertEqual(plan.placements["b"].rect, Rect(0, 0, 1000, 800))
        self.assertTrue(plan.placements["a"].occluded)
        self.assertTrue(plan.placements["c"].occluded)
        self.assertIsNone(plan.placements["a"].rect)

    def test_cramped_layout_rejects_nonpositive_cells(self):
        for mode in (Mode.SMALL, Mode.HALF):
            with self.subTest(mode=mode):
                with self.assertRaises(LayoutError):
                    plan_layout(list("abcdef"), "a", mode, 17, 17, 8)

    def test_invalid_selection_and_rect_are_rejected(self):
        cases = [
            ((["a"], "missing", Mode.SMALL, 100, 100), "selection"),
            (([], None, Mode.SMALL, 100, 100), "selection"),
            ((["a"], "a", Mode.SMALL, 0, 100), "rect"),
            ((["a"], "a", Mode.SMALL, 100, 100, -1), "rect"),
        ]
        for args, label in cases:
            with self.subTest(label=label):
                with self.assertRaises(LayoutError):
                    plan_layout(*args)


if __name__ == "__main__":
    unittest.main()
