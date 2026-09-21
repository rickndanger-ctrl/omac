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
            "app-name": "Finder", "window-layout": "tiling",
        }
        self.focused = json.dumps([self.window])
        self.addCleanup(self._restore)

    def _restore(self):
        control.STATE = self.old_state
        self.tmp.cleanup()

    def test_half_full_small_targets_one_window_and_keeps_session(self):
        def aero(*args, **kwargs):
            if args[:2] == ("list-windows", "--focused"):
                return self.focused
            return ""

        with patch.object(control, "aero", side_effect=aero) as aero_mock, \
             patch.object(control, "boot_session", return_value="boot-a"), \
             patch.object(control, "_ax_half") as ax:
            self.assertIn("half", control.size_window("half"))
            self.assertIn("full", control.size_window("full"))
            self.assertIn("small", control.size_window("small"))

        calls = aero_mock.call_args_list
        self.assertIn(("layout", "--window-id", "41", "floating"),
                      [call.args for call in calls])
        self.assertIn(("fullscreen", "on", "--window-id", "41"),
                      [call.args for call in calls])
        self.assertIn(("layout", "--window-id", "41", "tiling"),
                      [call.args for call in calls])
        ax.assert_called_once_with(812)
        saved = json.loads((control.STATE / "tile-modes.json").read_text())
        self.assertEqual(next(iter(saved.values()))["mode"], "small")

    def test_failed_ax_operation_does_not_record_half(self):
        with patch.object(control, "aero", return_value=self.focused), \
             patch.object(control, "boot_session", return_value="boot-a"), \
             patch.object(control, "_ax_half", side_effect=RuntimeError("AX")):
            with self.assertRaises(RuntimeError):
                control.size_window("half")
        self.assertFalse((control.STATE / "tile-modes.json").exists())

    def test_invalid_focused_page_is_rejected_without_commands(self):
        bad = dict(self.window, workspace="Research")
        with patch.object(control, "aero", return_value=json.dumps([bad])) as aero:
            with self.assertRaises(RuntimeError):
                control.size_window("full")
        self.assertEqual(aero.call_count, 1)


if __name__ == "__main__":
    unittest.main()
