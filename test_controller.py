import importlib.util,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('control',Path(__file__).with_name('control.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
class Lifecycle(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.old=c.STATE;c.STATE=Path(self.tmp.name)
 def tearDown(self): c.STATE=self.old;self.tmp.cleanup()
 def test_reentry_does_not_launch_duplicates(self):
  tiles=[{'window-id':i,'window-title':'ACC · '+str(i)} for i in range(1,5)]
  with patch.object(c,'aero',return_value=str(c.ROOT/'config/aerospace.toml')),patch.object(c,'run') as run,patch.object(c,'ready'),patch.object(c,'load'),patch.object(c,'terminal_windows',return_value=tiles),patch.object(c,'arrange',return_value=4):
   self.assertIn('4 plain',c.enter())
   self.assertFalse(any('terminal.' in str(call) for call in run.call_args_list))
 def test_add_at_capacity_does_not_rearrange_or_reload(self):
  c.save_status('Active')
  tiles=[{'window-id':i,'window-title':'ACC · '+str(i)} for i in range(1,7)]
  with patch.object(c,'aero',return_value=str(c.ROOT/'config/aerospace.toml')) as aero,patch.object(c,'run') as run,patch.object(c,'terminal_windows',return_value=tiles),patch.object(c,'arrange') as arrange:
   self.assertIn('6 plain',c.enter(add=True))
   arrange.assert_not_called();run.assert_not_called()
   self.assertFalse(any(call.args[0]=='reload-config' for call in aero.call_args_list))
 def test_pause_preserves_sessions_and_snapshot(self):
  (c.STATE/'windows.json').write_text('[]')
  with patch.object(c,'aero') as aero,patch.object(c,'run') as run:
   c.stop(False);run.assert_not_called()
   self.assertTrue((c.STATE/'windows.json').exists())
   self.assertEqual(aero.call_args_list[-1].args,('enable','off'))
 def test_exit_only_stops_manager(self):
  with patch.object(c,'aero'),patch.object(c,'run') as run:
   c.stop(True)
   self.assertEqual(run.call_args_list[0].args,('launchctl','bootout',c.job('aerospace')))
   self.assertEqual(run.call_args_list[1].args,(c.APP,'--restore'))
 def test_permission_failure_does_not_enable_manager(self):
  with patch.object(c,'aero',return_value=''),patch.object(c,'run',side_effect=RuntimeError('permission')):
   with self.assertRaises(RuntimeError):c.enter()
   self.assertFalse((c.STATE/'aerospace.enabled').exists())
 def test_foreign_manager_not_modified(self):
  with patch.object(c,'aero',return_value='/another/config'),patch.object(c,'run') as run:
   with self.assertRaises(RuntimeError):c.enter()
   run.assert_not_called()
if __name__=='__main__':unittest.main()
