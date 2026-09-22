import json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import control as c
class Hardening(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.old=c.STATE;c.STATE=Path(self.tmp.name)
 def tearDown(self): c.STATE=self.old;self.tmp.cleanup()
 def test_corrupt_checkpoint_is_ignored(self):
  (c.STATE/'pages.json').write_text('{broken')
  with patch.object(c,'aero') as aero:c.restore_pages();aero.assert_not_called()
 def test_previous_boot_does_not_move_reused_ids(self):
  (c.STATE/'pages.json').write_text(json.dumps({'boot':'old','page':'2','windows':[{'window-id':1,'app-pid':1,'workspace':'2'}]}))
  with patch.object(c,'boot_session',return_value='new'),patch.object(c,'aero') as aero:c.restore_pages();aero.assert_not_called()
 def test_hidden_app_does_not_prevent_terminal_grid_recovery(self):
  rows=[{'window-id':i,'app-pid':i,'workspace':'1','app-name':'Ghostty','window-layout':'v_tiles'} for i in range(1,5)]
  rows.append({'window-id':9,'app-pid':9,'workspace':'1','app-name':'Messages','window-layout':'macos_native_window_of_hidden_app'})
  (c.STATE/'pages.json').write_text(json.dumps({'boot':'same','page':'1','windows':rows}))
  with patch.object(c,'boot_session',return_value='same'),patch.object(c,'windows',return_value=rows),patch.object(c,'aero'),patch.object(c,'arrange') as arrange:
   c.restore_pages()
   arrange.assert_called_once_with('1')
 def test_empty_inventory_does_not_erase_last_page_map(self):
  previous={'boot':'same','page':'1','windows':[{'window-id':1,'app-pid':2,'workspace':'1'}]}
  (c.STATE/'pages.json').write_text(json.dumps(previous))
  with patch.object(c,'windows',return_value=[]),patch.object(c,'boot_session',return_value='same'):
   self.assertFalse(c.save_pages())
  self.assertEqual(json.loads((c.STATE/'pages.json').read_text()),previous)
 def test_new_boot_replaces_stale_empty_inventory_checkpoint(self):
  (c.STATE/'pages.json').write_text(json.dumps({'boot':'old','page':'1','windows':[{'window-id':1,'app-pid':2}]}))
  with patch.object(c,'windows',return_value=[]),patch.object(c,'boot_session',return_value='new'),patch.object(c,'page',return_value='1'):
   self.assertTrue(c.save_pages())
  self.assertEqual(json.loads((c.STATE/'pages.json').read_text())['windows'],[])
 def test_active_recovery_restores_before_enabling_bindings(self):
  c.save_status('Active');events=[]
  with patch.object(c,'ready'),patch.object(c,'restore_pages',side_effect=lambda:events.append('restore')),patch.object(c,'aero',side_effect=lambda *args,**kw:events.append(args)),patch.object(c,'save_pages'),patch.object(c,'load'),patch.object(c,'run'):
   c.recover()
  self.assertEqual(events[:2],['restore',('mode','active')]);self.assertEqual(c.status(),'Active')
 def test_recovery_failure_releases_bindings(self):
  c.save_status('Active')
  with patch.object(c,'ready',side_effect=RuntimeError('unavailable')),patch.object(c,'aero') as aero:
   with self.assertRaises(RuntimeError):c.recover()
   aero.assert_any_call('mode','main',check=False);aero.assert_any_call('enable','off',check=False)
  self.assertEqual(c.status(),'Paused')
 def test_package_prefers_a_stable_development_signature(self):
  script=Path('package.sh').read_text()
  self.assertIn('security find-identity -v -p codesigning',script)
  self.assertIn('Apple Development:',script)
  self.assertIn('OMAC_SIGN_IDENTITY',script)
if __name__=='__main__':unittest.main()
