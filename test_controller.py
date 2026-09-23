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
 def test_inactive_reentry_restores_pages_even_with_existing_omac_server(self):
  c.save_status('Inactive')
  with patch.object(c,'aero',return_value=str(c.RUNTIME/'config/aerospace.toml')),patch.object(c,'run'),patch.object(c,'ready'),patch.object(c,'load'),patch.object(c,'terminal_windows',return_value=[]),patch.object(c,'arrange'):
   c.enter()
  c.restore_pages.assert_called_once_with()
 def test_add_at_capacity_does_not_rearrange_or_reload(self):
  c.save_status('Active')
  tiles=[{'window-id':i,'window-title':'ACC · '+str(i)} for i in range(1,7)]
  with patch.object(c,'aero',return_value=str(c.RUNTIME/'config/aerospace.toml')) as aero,patch.object(c,'run') as run,patch.object(c,'terminal_windows',return_value=tiles),patch.object(c,'arrange') as arrange:
   self.assertIn('6 plain',c.enter(add=True))
   arrange.assert_not_called();run.assert_not_called()
   self.assertFalse(any(call.args[0]=='reload-config' for call in aero.call_args_list))
 def test_new_terminal_keeps_origin_and_balances_tiles(self):
  c.save_status('Active')
  old={'window-id':1,'window-title':'ACC · 1','workspace':'2','app-pid':123}
  def aero(*args,**kwargs):
   if args[:2]==('config','--config-path'): return str(c.RUNTIME/'config/aerospace.toml')
   if args[:2]==('list-workspaces','--focused'): return '2'
   return ''
  with patch.object(c,'aero',side_effect=aero),patch.object(c,'run') as run,patch.object(c,'terminal_windows',return_value=[old]),patch.object(c,'add_window_to_existing_terminal',return_value=2) as create,patch.object(c,'arrange') as arrange,patch.object(c,'start_services') as services:
   self.assertIn('2 plain',c.enter(add=True))
   arrange.assert_called_once_with('2');services.assert_not_called()
   create.assert_called_once_with([old],'2')
   run.assert_not_called()
 def test_first_terminal_reuses_supervised_process_when_no_window_is_tracked(self):
  c.save_status('Active')
  source=[{'app-pid':4121}]
  def aero(*args,**kwargs):
   if args[:2]==('config','--config-path'): return str(c.RUNTIME/'config/aerospace.toml')
   if args[:2]==('list-workspaces','--focused'): return '3'
   return ''
  with patch.object(c,'aero',side_effect=aero),patch.object(c,'run') as run,patch.object(c,'terminal_windows',return_value=[]),patch.object(c,'running_terminal_source',return_value=source) as find,patch.object(c,'add_window_to_existing_terminal',return_value=1) as create,patch.object(c,'arrange'):
   self.assertIn('1 plain',c.enter(add=True))
  find.assert_called_once_with()
  create.assert_called_once_with(source,'3')
  self.assertFalse(any('terminal.' in str(item) for item in run.call_args_list))
 def test_first_terminal_uses_ghostty_pid_not_open_wrapper(self):
  from types import SimpleNamespace
  config='--config-file='+str(c.ROOT/'config/ghostty.conf')
  output=f'54702 /usr/bin/open -W -n -a /Applications/Ghostty.app\n54704 /Applications/Ghostty.app/Contents/MacOS/ghostty --title=ACC · 1 {config}\n'
  with patch.object(c.subprocess,'run',return_value=SimpleNamespace(stdout=output)):
   self.assertEqual(c.running_terminal_source(),[{'app-pid':54704}])
 def test_existing_process_creates_window_without_page_switch(self):
  old={'window-id':1,'window-title':'ACC · 1','workspace':'2','app-pid':123}
  new={'window-id':2,'window-title':'ACC · 1','workspace':'2','app-pid':123}
  with patch.object(c,'windows',side_effect=[[old],[old,new]]),patch.object(c,'run') as run,patch.object(c,'aero') as aero,patch.object(c,'terminal_windows',return_value=[old,new]):
   self.assertEqual(c.add_window_to_existing_terminal([old],'2'),2)
   self.assertEqual(run.call_args.args[:2],('osascript','-e'))
   aero.assert_any_call('layout','--window-id','2','tiling')
   aero.assert_any_call('focus','--window-id','2')
   self.assertFalse(any(call.args[0]=='workspace' for call in aero.call_args_list))
 def test_empty_page_reuses_terminal_from_another_page(self):
  c.save_status('Active')
  remote={'window-id':1,'window-title':'ACC · 1','workspace':'1','app-pid':123}
  def aero(*args,**kwargs):
   if args[:2]==('config','--config-path'): return str(c.RUNTIME/'config/aerospace.toml')
   if args[:2]==('list-workspaces','--focused'): return '2'
   return ''
  def terminals(workspace=None): return [] if workspace=='2' else [remote]
  with patch.object(c,'aero',side_effect=aero),patch.object(c,'terminal_windows',side_effect=terminals),patch.object(c,'add_window_to_existing_terminal',return_value=1) as create,patch.object(c,'run') as run,patch.object(c,'arrange'):
   self.assertIn('1 plain',c.enter(add=True))
   create.assert_called_once_with([remote],'2')
   run.assert_not_called()
 def test_grid_reset_is_one_batch_and_preserves_focus(self):
  tiles=[{'window-id':i,'window-title':'ACC · '+str(i),'workspace':'1','window-layout':'h_tiles'} for i in range(1,7)]
  with patch.object(c,'terminal_windows',return_value=tiles),patch.object(c,'windows',return_value=list(reversed(tiles))),patch.object(c,'aero',return_value='3') as aero,patch.object(c,'page',return_value='1'):
   self.assertEqual(c.arrange(),6)
   batches=[call for call in aero.call_args_list if call.args[0]=='eval']
   self.assertEqual(len(batches),1)
   batch=batches[0].args[1]
   self.assertIn('flatten-workspace-tree; layout --workspace 1 --root h_tiles; join-with --window-id 6 right; join-with --window-id 4 right; join-with --window-id 2 right; balance-sizes --workspace 1; focus --window-id 3',batch)
   self.assertFalse(any(call.args[0] in ('move','join-with','balance-sizes') for call in aero.call_args_list))
 def test_pause_preserves_sessions_and_snapshot(self):
  (c.STATE/'windows.json').write_text('[]')
  with patch.object(c,'aero') as aero,patch.object(c,'run') as run:
   c.stop(False);run.assert_called_once_with('launchctl','bootout',c.job('watcher'),check=False)
   self.assertTrue((c.STATE/'windows.json').exists())
   self.assertEqual(aero.call_args_list[-1].args,('enable','off'))
 def test_exit_only_stops_manager(self):
  import subprocess
  with patch.object(c,'aero'),patch.object(c,'run') as run,patch.object(c.subprocess,'run',side_effect=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],1)]):
   c.stop(True)
   run.assert_any_call('launchctl','bootout',c.job('aerospace'))
   run.assert_any_call(c.APP,'--restore')
   self.assertEqual(c.status(),'Inactive')
 def test_failed_native_restore_retains_exit_evidence(self):
  import subprocess
  (c.STATE/'aerospace.enabled').touch()
  (c.STATE/'windows.json').write_text('[{"pid": 1}]')
  def command(*args,**kwargs):
   if args[:2]==(c.APP,'--restore'): raise RuntimeError('AX window not restored')
  with patch.object(c,'aero'),patch.object(c,'run',side_effect=command),patch.object(c.subprocess,'run',side_effect=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],1)]):
   with self.assertRaisesRegex(RuntimeError,'AX window not restored'):c.stop(True)
  self.assertEqual(c.status(),'RecoveryNeeded')
  self.assertTrue((c.STATE/'aerospace.enabled').exists())
  self.assertTrue((c.STATE/'windows.json').exists())
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
  rows=[{'app-name':'Ghostty','window-id':i,'window-title':'ACC · '+str(i),'workspace':str(i),'window-layout':'h_tiles'} for i in (1,2)]
  with patch.object(c,'windows',return_value=rows),patch.object(c,'aero',return_value='2') as aero:
   c.arrange('2')
   batch=[x.args[1] for x in aero.call_args_list if x.args[0]=='eval'][0]
   self.assertNotIn('--window-id 1',batch)
   self.assertIn('workspace 2',batch)
 def test_arrange_evacuates_remote_viewer_before_workspace_layout(self):
  viewer={'app-name':'Screen Sharing','app-bundle-id':c.REMOTE_VIEWER_BUNDLE,
          'window-id':5418,'workspace':'1','window-layout':'h_tiles'}
  terminal={'app-name':'Ghostty','window-id':42,'workspace':'1',
            'window-layout':'h_tiles','window-title':'ACC · 1'}
  with patch.object(c,'windows',return_value=[viewer,terminal]), \
       patch.object(c,'aero',return_value='1') as aero:
   c.arrange('1')
  self.assertIn(('move-node-to-workspace','--window-id','5418',c.REMOTE_WORKSPACE),
                [call.args for call in aero.call_args_list])
  batch=[call.args[1] for call in aero.call_args_list if call.args[0]=='eval'][0]
  self.assertNotIn('5418',batch)
 def test_switch_page_evacuates_viewers_from_departing_and_empty_destination_pages(self):
  departing={'window-id':5418,'app-name':'Screen Sharing','app-bundle-id':c.REMOTE_VIEWER_BUNDLE,'workspace':'1'}
  destination={'window-id':5419,'app-name':'Screen Sharing','app-bundle-id':c.REMOTE_VIEWER_BUNDLE,'workspace':'2'}
  def fake_aero(*args): return '1' if args==('list-workspaces','--focused') else ''
  with patch.object(c,'aero',side_effect=fake_aero) as aero,patch.object(c,'windows',return_value=[departing,destination]):
   self.assertEqual(c.switch_page('2'),'Switched to page 2.')
  calls=[call.args for call in aero.call_args_list]
  self.assertEqual(calls[0],('list-workspaces','--focused'))
  self.assertEqual(calls[-1],('workspace','2'))
  self.assertEqual(set(calls[1:-1]),{
   ('move-node-to-workspace','--window-id','5418',c.REMOTE_WORKSPACE),
   ('move-node-to-workspace','--window-id','5419',c.REMOTE_WORKSPACE)})
 def test_all_five_pages_and_same_page_evacuate_remote_before_activation(self):
  for origin in map(str,range(1,6)):
   for target in map(str,range(1,6)):
    viewer={'window-id':5418,'app-name':'Screen Sharing','app-bundle-id':c.REMOTE_VIEWER_BUNDLE,'workspace':origin}
    def fake_aero(*args): return origin if args==('list-workspaces','--focused') else ''
    with self.subTest(origin=origin,target=target),patch.object(c,'aero',side_effect=fake_aero) as aero,patch.object(c,'windows',return_value=[viewer]):
     c.switch_page(target)
     self.assertLess(aero.call_args_list.index(next(call for call in aero.call_args_list if call.args[0]=='move-node-to-workspace')),
                     aero.call_args_list.index(next(call for call in aero.call_args_list if call.args[0]=='workspace')))
 def test_remote_viewer_cannot_be_moved_into_numbered_page(self):
  viewer={'window-id':5418,'app-pid':900,'app-name':'Screen Sharing','app-bundle-id':c.REMOTE_VIEWER_BUNDLE,'workspace':'Omac-Remote'}
  with patch.object(c,'aero',return_value=__import__('json').dumps([viewer])) as aero,patch.object(c,'_read_mixed',return_value=None):
   with self.assertRaisesRegex(RuntimeError,'stays outside Omac pages'):
    c.move_focused_to_page('1')
  self.assertFalse(any(call.args[0]=='move-node-to-workspace' for call in aero.call_args_list))
 def test_restore_rejects_recycled_window_ids(self):
  import json
  with tempfile.TemporaryDirectory() as directory,patch.object(c,'STATE',Path(directory)):
   (c.STATE/'pages.json').write_text(json.dumps({'boot':'test','page':'3','windows':[{'window-id':1,'app-pid':100,'workspace':'3'}]}))
   with patch.object(c,'boot_session',return_value='test'),patch.object(c,'windows',return_value=[{'window-id':1,'app-pid':200}]),patch.object(c,'aero') as aero:
    c.restore_pages()
    aero.assert_called_once_with('workspace','3')
if __name__=='__main__':unittest.main()
