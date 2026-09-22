import unittest
from unittest.mock import patch

import control


class CenterGuardrailTests(unittest.TestCase):
    def test_tiled_window_enlarges_without_leaving_grid(self):
        with patch.object(control, 'aero') as aero, patch.object(control, 'run') as run:
            message = control.center_or_enlarge(12, 99, 'h_tiles')
        self.assertEqual(
            [call.args for call in aero.call_args_list],
            [('fullscreen', '--window-id', '12'), ('focus', '--window-id', '12')],
        )
        run.assert_not_called()
        self.assertIn('without leaving the tile grid', message)

    def test_floating_window_centers_without_joining_grid(self):
        with patch.object(control, 'aero') as aero, patch.object(control, 'run') as run:
            message = control.center_or_enlarge(12, 99, 'floating')
        run.assert_called_once_with(control.APP, '--center', '99')
        self.assertEqual([call.args for call in aero.call_args_list], [('focus', '--window-id', '12')])
        self.assertIn('without changing the tile grid', message)


if __name__ == '__main__':
    unittest.main()
