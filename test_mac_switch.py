import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import mac_switch as switch


class MacSwitchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state = Path(self.temp.name)
        self.connection = self.state / 'remote.vncloc'
        self.connection.write_text('saved connection')
        (self.state / 'remote-control.json').write_text(json.dumps({
            'version': 1, 'enabled': True, 'connectionPath': str(self.connection)}))

    def tearDown(self):
        self.temp.cleanup()

    def test_remote_uses_current_workspace_and_remembers_local_origin(self):
        calls = []
        viewer = {'window-id': 77, 'workspace': '1', 'app-bundle-id': switch.VIEWER_BUNDLE,
                  'window-layout': 'floating'}
        local = {'window-id': 42, 'app-pid': 9, 'app-bundle-id': 'com.openai.codex',
                 'window-layout': 'h_tiles'}
        with patch.object(switch, 'STATE', self.state), patch.object(switch, 'CONFIG', self.state/'remote-control.json'), \
             patch.object(switch, 'RETURN_STATE', self.state/'return.json'), patch.object(switch, 'current_page', return_value='2'), \
             patch.object(switch, 'visible_viewer', side_effect=[None, viewer]), \
             patch.object(switch, 'rows', return_value=[local]), \
             patch.object(switch, 'run', side_effect=lambda *a: calls.append(a) or ''), \
             patch.object(switch.time, 'sleep'):
            switch.main('remote')
        self.assertEqual(json.loads((self.state/'return.json').read_text()), {'page':'2','window-id':42,'app-pid':9})
        self.assertIn((switch.AERO, 'move-node-to-workspace', '--window-id', '77', '2'), calls)

    def test_repeated_remote_does_not_overwrite_return_target(self):
        return_state = self.state/'return.json'
        return_state.write_text(json.dumps({'page':'3','window-id':42,'app-pid':9}))
        viewer = {'window-id': 77, 'workspace': '3', 'app-bundle-id': switch.VIEWER_BUNDLE,
                  'window-layout': 'floating'}
        with patch.object(switch, 'STATE', self.state), patch.object(switch, 'CONFIG', self.state/'remote-control.json'), \
             patch.object(switch, 'RETURN_STATE', return_state), patch.object(switch, 'visible_viewer', return_value=viewer), \
             patch.object(switch, 'focused_local', return_value=None), \
             patch.object(switch, 'rows', return_value=[viewer]), \
             patch.object(switch, 'run', return_value=''), patch.object(switch.time, 'sleep'):
            switch.main('remote')
        self.assertEqual(json.loads(return_state.read_text())['window-id'], 42)

    def test_local_clears_stale_return_after_exact_focus(self):
        return_state = self.state/'return.json'
        return_state.write_text(json.dumps({'page':'5','window-id':42,'app-pid':9}))
        local = {'window-id':42,'app-pid':9,'app-bundle-id':'com.openai.codex','window-layout':'v_tiles'}
        calls = []
        with patch.object(switch, 'STATE', self.state), patch.object(switch, 'RETURN_STATE', return_state), \
             patch.object(switch, 'rows', return_value=[local]), \
             patch.object(switch, 'run', side_effect=lambda *a: calls.append(a) or ''):
            switch.main('local')
        self.assertIn((switch.AERO, 'focus', '--window-id', '42'), calls)
        self.assertFalse(return_state.exists())

    def test_empty_page_return_parks_viewer_outside_omac_pages(self):
        return_state = self.state/'return.json'
        return_state.write_text(json.dumps({'page':'1'}))
        viewer = {'window-id':77,'app-bundle-id':switch.VIEWER_BUNDLE,
                  'workspace':'2','window-layout':'floating'}
        calls = []
        def rows(*scope): return [viewer] if scope == ('--all',) else []
        with patch.object(switch,'STATE',self.state),patch.object(switch,'RETURN_STATE',return_state), \
             patch.object(switch,'rows',side_effect=rows), \
             patch.object(switch,'run',side_effect=lambda *a: calls.append(a) or ''):
            switch.main('local')
        self.assertIn((switch.AERO,'move-node-to-workspace','--window-id','77',switch.REMOTE_WORKSPACE),calls)
        self.assertIn((switch.AERO,'workspace','1'),calls)
        self.assertFalse(return_state.exists())

    def test_no_focused_window_is_an_empty_inventory(self):
        error = subprocess.CalledProcessError(2,'aerospace',stderr='No window is focused')
        with patch.object(switch,'run',side_effect=error):
            self.assertEqual(switch.rows('--focused'),[])

    def test_non_object_configuration_is_rejected(self):
        path = self.state/'remote-control.json'
        path.write_text('[]')
        with patch.object(switch, 'CONFIG', path):
            with self.assertRaisesRegex(RuntimeError, 'invalid configuration'):
                switch.config()

    def test_control_mode_failure_is_reported(self):
        with patch.object(switch, 'run', side_effect=subprocess.CalledProcessError(1, 'osascript')):
            with self.assertRaises(subprocess.CalledProcessError):
                switch.ensure_remote_control()


if __name__ == '__main__':
    unittest.main()
