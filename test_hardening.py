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
 def test_restore_skips_same_page_move_and_hidden_window_layout(self):
  saved=[{'window-id':7,'app-pid':70,'workspace':'1','app-name':'Ghostty','window-layout':'h_tiles'},
         {'window-id':8,'app-pid':80,'workspace':'1','app-name':'Ghostty','window-layout':'h_tiles'}]
  live=[dict(saved[0]),dict(saved[1],**{'window-layout':'macos_native_window_of_hidden_app'})]
  (c.STATE/'pages.json').write_text(json.dumps({'boot':'same','page':'1','windows':saved}))
  with patch.object(c,'boot_session',return_value='same'),patch.object(c,'windows',return_value=live),patch.object(c,'aero') as aero:
   c.restore_pages()
  self.assertEqual([call.args for call in aero.call_args_list],[('workspace','1')])
 def test_same_page_tiles_and_hidden_app_do_not_trigger_rearrange(self):
  rows=[{'window-id':i,'app-pid':i,'workspace':'1','app-name':'Ghostty','window-layout':'v_tiles'} for i in range(1,5)]
  rows.append({'window-id':9,'app-pid':9,'workspace':'1','app-name':'Messages','window-layout':'macos_native_window_of_hidden_app'})
  (c.STATE/'pages.json').write_text(json.dumps({'boot':'same','page':'1','windows':rows}))
  with patch.object(c,'boot_session',return_value='same'),patch.object(c,'windows',return_value=rows),patch.object(c,'aero'),patch.object(c,'arrange') as arrange:
   c.restore_pages()
   arrange.assert_not_called()
 def test_screen_sharing_is_never_saved_or_restored_as_a_page_window(self):
  remote={'window-id':5418,'app-pid':82697,'app-name':'Screen Sharing','workspace':'2','window-layout':'floating'}
  terminal={'window-id':7,'app-pid':7,'app-name':'Ghostty','workspace':'1','window-layout':'h_tiles'}
  with patch.object(c,'windows',return_value=[remote,terminal]),patch.object(c,'boot_session',return_value='same'),patch.object(c,'page',return_value='1'):
   self.assertTrue(c.save_pages())
  saved=json.loads((c.STATE/'pages.json').read_text())
  self.assertEqual(saved['windows'],[terminal])
  (c.STATE/'pages.json').write_text(json.dumps({'boot':'same','page':'1','windows':[remote]}))
  with patch.object(c,'windows',return_value=[remote]),patch.object(c,'boot_session',return_value='same'),patch.object(c,'aero') as aero:
   c.restore_pages()
  self.assertEqual([item.args for item in aero.call_args_list],[('workspace','1')])
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
 def test_owned_legacy_config_is_not_mistaken_for_foreign(self):
  path=Path(self.tmp.name)/'legacy.toml'
  path.write_text("persistent-workspaces = ['1', '2', '3', '4', '5']\n[mode.active.binding]\nafter-startup-command = ['exec-and-forget python control.py recover']\n")
  c.save_status('Active');(c.STATE/'aerospace.enabled').touch()
  self.assertTrue(c.omac_config(str(path)))
  self.assertFalse(c.omac_config('/another/config'))
 def test_routes_macos_27_control_permission_panel(self):
  source=Path('Launcher.swift').read_text()
  self.assertIn('Device Control and Data Access',source)
  self.assertIn('com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility',source)
 def test_installer_names_the_current_permission_panel(self):
  script=Path('Install Omac.command').read_text()
  self.assertIn('Device Control and Data Access',script)
  self.assertIn('major < 27',script)
 def test_bundled_python_never_writes_into_the_signed_app(self):
  for name in ('control.py','generate_config.py'):
   source=Path(name).read_text()
   self.assertLess(source.index('sys.dont_write_bytecode=True'),source.index('from portable_paths import'))
if __name__=='__main__':unittest.main()
