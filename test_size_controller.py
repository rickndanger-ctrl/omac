import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import control


class SizeControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old_state = control.STATE
        control.STATE = Path(self.tmp.name)
        self.window = {
            "window-id": 41, "app-pid": 812, "workspace": "2",
            "app-name": "Finder", "window-layout": "h_tiles",
        }
        self.focused = json.dumps([self.window])
        self.target = json.dumps({"windowID": 41, "pid": 812,
                                  "frame": [100, 100, 500, 400],
                                  "visibleFrame": [0, 0, 1200, 800]})
        self.addCleanup(self._restore)

    def _restore(self):
        control.STATE = self.old_state
        self.tmp.cleanup()

    def test_native_frames_reject_invalid_geometry(self):
        identity = control.WindowIdentity(41, 812, "boot-a")
        for frame in ([0, 0, 0, 400], [0, 0, -1, 400], [float("nan"), 0, 500, 400], [0, 0, float("inf"), 400]):
            data = json.loads(self.target)
            data["frame"] = frame
            with self.subTest(frame=frame), patch.object(control, "run", return_value=json.dumps(data)):
                with self.assertRaises(RuntimeError):
                    control._native_target(identity)

    def test_truncated_frame_never_counts_as_restored(self):
        self.assertFalse(control._same_frame([], [0, 0, 500, 400]))
        self.assertFalse(control._same_frame([0, 0], [0, 0, 500, 400]))

    def test_inventory_explicitly_requests_required_real_cli_fields(self):
        def actual_cli_shape(*args, **kwargs):
            if "--workspace" in args:
                return self.focused
            if "--format" not in args:
                return json.dumps([{"window-id": 41, "app-name": "Finder"}])
            return self.focused
        with patch.object(control, "aero", side_effect=actual_cli_shape), \
             patch.object(control, "run", return_value=self.target), \
             patch.object(control, "boot_session", return_value="boot-a"):
            self.assertIn("full", control.size_window("full"))

    def test_full_small_targets_one_window_and_keeps_session(self):
        def aero(*args, **kwargs):
            if args[0:1] == ("list-windows",) and "--json" in args:
                return self.focused
            return ""

        def native_run(*args, **kwargs):
            return self.target if "--window-target" in args else ""
        with patch.object(control, "aero", side_effect=aero) as aero_mock, \
             patch.object(control, "run", side_effect=native_run) as run_mock, \
             patch.object(control, "boot_session", return_value="boot-a"):
            self.assertIn("full", control.size_window("full"))
            self.assertIn("small", control.size_window("small"))

        calls = aero_mock.call_args_list
        self.assertIn(("fullscreen", "on", "--window-id", "41"),
                      [call.args for call in calls])
        self.assertIn(("layout", "--window-id", "41", "h_tiles"),
                      [call.args for call in calls])
        self.assertIn((control.APP, "--window-frame", "41", "812", "100.0", "100.0", "500.0", "400.0"),
                      [call.args for call in run_mock.call_args_list])
        saved = json.loads((control.STATE / "tile-modes.json").read_text())
        self.assertEqual(next(iter(saved.values()))["mode"], "small")

    def test_half_preflights_target_then_uses_exact_native_helper(self):
        def native_run(*args, **kwargs):
            return self.target if "--window-target" in args else ""
        with patch.object(control, "aero", return_value=self.focused) as aero, \
             patch.object(control, "run", side_effect=native_run) as run_mock, \
             patch.object(control, "boot_session", return_value="boot-a"):
            self.assertIn("half", control.size_window("half"))
        calls = [call.args for call in aero.call_args_list]
        self.assertEqual(calls[0][:3], ("list-windows", "--focused", "--format"))
        self.assertIn(("fullscreen", "off", "--window-id", "41"), calls)
        self.assertIn(("layout", "--window-id", "41", "floating"), calls)
        self.assertIn((control.APP, "--window-target", "41", "812"),
                      [call.args for call in run_mock.call_args_list])
        self.assertIn((control.APP, "--window-half", "41", "812"),
                      [call.args for call in run_mock.call_args_list])

    def test_preflight_snapshots_each_workspace_identity(self):
        other = {"window-id": 42, "app-pid": 813, "workspace": "2",
                 "window-layout": "v_tiles"}
        inventory = json.dumps([self.window, other])
        def aero(*args, **kwargs):
            if "--json" in args:
                return self.focused if "--focused" in args else inventory
            return ""
        def native_run(*args, **kwargs):
            pid = int(args[-1])
            return json.dumps({"windowID": 41 if pid == 812 else 42,
                               "pid": pid, "frame": [100, 100, 500, 400],
                               "visibleFrame": [0, 0, 1200, 800]})
        with patch.object(control, "aero", side_effect=aero), \
             patch.object(control, "run", side_effect=native_run) as run_mock, \
             patch.object(control, "boot_session", return_value="boot-a"):
            control.size_window("full")
        targets = [call.args for call in run_mock.call_args_list
                   if "--window-target" in call.args]
        self.assertEqual({call[-2:] for call in targets}, {("41", "812"), ("42", "813")})

    def test_half_failure_restores_previous_tiling_and_state(self):
        def native_run(*args, **kwargs):
            if "--window-target" in args: return self.target
            raise RuntimeError("native half failed")
        with patch.object(control, "aero", return_value=self.focused) as aero, \
             patch.object(control, "run", side_effect=native_run), \
             patch.object(control, "boot_session", return_value="boot-a"):
            with self.assertRaises(RuntimeError):
                control.size_window("half")
        calls = [call.args for call in aero.call_args_list]
        self.assertIn(("layout", "--window-id", "41", "h_tiles"), calls)
        self.assertFalse((control.STATE / "tile-modes.json").exists())

    def test_small_frame_mismatch_reports_failure_and_restores_full_mode(self):
        state = {"boot-a:812:41": {"mode": "full", "workspace": "2",
                "window-id": 41, "app-pid": 812, "boot": "boot-a",
                "original_layout": "h_tiles", "original_frame": [100, 100, 500, 400],
                "visible_frame": [0, 0, 1200, 800]}}
        (control.STATE / "tile-modes.json").write_text(json.dumps(state))
        calls = []
        def native_run(*args, **kwargs):
            calls.append(args)
            if "--window-target" in args:
                frame = [999, 100, 500, 400] if len([x for x in calls if "--window-target" in x]) > 1 else [100, 100, 500, 400]
                return json.dumps({"windowID": 41, "pid": 812, "frame": frame,
                                   "visibleFrame": [0, 0, 1200, 800]})
            return ""
        with patch.object(control, "aero", return_value=self.focused) as aero, \
             patch.object(control, "run", side_effect=native_run), \
             patch.object(control, "boot_session", return_value="boot-a"):
            with self.assertRaisesRegex(RuntimeError, "did not restore"):
                control.size_window("small")
        self.assertIn(("fullscreen", "on", "--window-id", "41"),
                      [call.args for call in aero.call_args_list])
        self.assertEqual(json.loads((control.STATE / "tile-modes.json").read_text()), state)

    def test_half_rejects_native_identity_mismatch_without_layout_mutation(self):
        mismatch = json.dumps({"windowID": 99, "pid": 900,
                               "frame": [100, 100, 500, 400],
                               "visibleFrame": [0, 0, 1200, 800]})
        def native_run(*args, **kwargs):
            return mismatch if "--window-target" in args else ""
        with patch.object(control, "aero", return_value=self.focused), \
             patch.object(control, "run", side_effect=native_run), \
             patch.object(control, "boot_session", return_value="boot-a"):
            with self.assertRaisesRegex(RuntimeError, "identity"):
                control.size_window("half")

    def test_invalid_focused_page_is_rejected_without_commands(self):
        bad = dict(self.window, workspace="Research")
        with patch.object(control, "aero", return_value=json.dumps([bad])) as aero:
            with self.assertRaises(RuntimeError):
                control.size_window("full")
        self.assertEqual(aero.call_count, 1)


if __name__ == "__main__":
    unittest.main()
