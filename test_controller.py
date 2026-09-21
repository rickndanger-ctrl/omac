import importlib.util,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('control',Path(__file__).with_name('control.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
class Lifecycle(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.old=c.STATE;c.STATE=Path(self.tmp.name)
  for name in ('save_pages','migrate_pages','restore_pages','start_services'):
   patcher=patch.object(c,name);patcher.start();self.addCleanup(patcher.stop)
 def tearDown(self): c.STATE=self.old;self.tmp.cleanup()
 def test_reentry_does_not_launch_duplicates(self):
  tiles=[{'window-id':i,'window-title':'ACC · '+str(i)} for i in range(1,5)]
  with patch.object(c,'aero',return_value=str(c.RUNTIME/'config/aerospace.toml')),patch.object(c,'run') as run,patch.object(c,'ready'),patch.object(c,'load'),patch.object(c,'terminal_windows',return_value=tiles),patch.object(c,'arrange',return_value=4):
   self.assertIn('4 plain',c.enter(4))
   self.assertFalse(any('terminal.' in str(call) for call in run.call_args_list))
 def test_add_at_capacity_does_not_rearrange_or_reload(self):
  c.save_status('Active')
  tiles=[{'window-id':i,'window-title':'ACC · '+str(i)} for i in range(1,7)]
  with patch.object(c,'aero',return_value=str(c.RUNTIME/'config/aerospace.toml')) as aero,patch.object(c,'run') as run,patch.object(c,'terminal_windows',return_value=tiles),patch.object(c,'arrange') as arrange:
   self.assertIn('6 plain',c.enter(add=True))
   arrange.assert_not_called();run.assert_not_called()
   self.assertFalse(any(call.args[0]=='reload-config' for call in aero.call_args_list))
 def test_grid_reset_is_one_batch_and_preserves_focus(self):
  tiles=[{'window-id':i,'window-title':'ACC · '+str(i)} for i in range(1,7)]
  cursor=['3']
  def fake_aero(*args,**kwargs):
   if args[:2]==('focus','--dfs-index'):cursor[0]=str(6-int(args[2]))
   return cursor[0]
  with patch.object(c,'terminal_windows',return_value=tiles),patch.object(c,'windows',return_value=list(reversed(tiles))),patch.object(c,'aero',side_effect=fake_aero) as aero:
   self.assertEqual(c.arrange(),6)
   batches=[call for call in aero.call_args_list if call.args[0]=='eval']
   self.assertEqual(len(batches),1)
   self.assertEqual(aero.call_args_list[-1].args,('focus','--window-id','3'))
   self.assertEqual([call.args[2] for call in aero.call_args_list if call.args[0]=='join-with'],['6','4','2'])
   self.assertFalse(any(call.args[0]=='move' for call in aero.call_args_list))
 def test_pause_preserves_sessions_and_snapshot(self):
  (c.STATE/'windows.json').write_text('[]')
  with patch.object(c,'aero') as aero,patch.object(c,'run') as run:
   c.stop(False);run.assert_called_once_with('launchctl','bootout',c.job('watcher'),check=False)
   self.assertTrue((c.STATE/'windows.json').exists())
   self.assertEqual(aero.call_args_list[-1].args,('enable','off'))
 def test_exit_only_stops_manager(self):
  with patch.object(c,'aero'),patch.object(c,'run') as run:
   c.stop(True)
   run.assert_any_call('launchctl','bootout',c.job('aerospace'),check=False)
   run.assert_any_call(c.APP,'--restore',check=False)
 def test_permission_failure_does_not_enable_manager(self):
  with patch.object(c,'aero',return_value=''),patch.object(c,'run',side_effect=RuntimeError('permission')):
   with self.assertRaises(RuntimeError):c.enter()
   self.assertFalse((c.STATE/'aerospace.enabled').exists())
 def test_foreign_manager_not_modified(self):
  with patch.object(c,'aero',return_value='/another/config'),patch.object(c,'run') as run:
   with self.assertRaises(RuntimeError):c.enter()
   run.assert_not_called()
class Pages(unittest.TestCase):
 def test_window_filter_never_collects_another_page(self):
  rows=[{'app-name':'Ghostty','window-id':i,'window-title':'ACC · '+str(i),'workspace':str(i)} for i in (1,2)]
  with patch.object(c,'windows',return_value=rows):
   self.assertEqual([w['window-id'] for w in c.terminal_windows('2')],[2])
 def test_grid_moves_only_selected_page(self):
  rows=[{'app-name':'Ghostty','window-id':i,'window-title':'ACC · '+str(i),'workspace':str(i)} for i in (1,2)]
  with patch.object(c,'windows',return_value=rows),patch.object(c,'aero',return_value='2') as aero:
   c.arrange('2')
   batch=[x.args[1] for x in aero.call_args_list if x.args[0]=='eval'][0]
   self.assertNotIn('--window-id 1',batch)
   self.assertIn('workspace 2',batch)
 def test_restore_rejects_recycled_window_ids(self):
  import json
  with tempfile.TemporaryDirectory() as directory,patch.object(c,'STATE',Path(directory)):
   (c.STATE/'pages.json').write_text(json.dumps({'boot':'test','page':'3','windows':[{'window-id':1,'app-pid':100,'workspace':'3'}]}))
   with patch.object(c,'boot_session',return_value='test'),patch.object(c,'windows',return_value=[{'window-id':1,'app-pid':200}]),patch.object(c,'aero') as aero:
    c.restore_pages()
    aero.assert_called_once_with('workspace','3')
if __name__=='__main__':unittest.main()
