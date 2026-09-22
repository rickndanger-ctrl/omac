import importlib.util,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('mixed_control',Path(__file__).with_name('control.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)

class MixedLayout(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.old=c.STATE;c.STATE=Path(self.tmp.name)
  self.app={'window-id':10,'app-pid':110,'app-name':'Finder','workspace':'2','window-layout':'h_tiles'}
  self.terminals=[{'window-id':wid,'app-pid':wid+100,'app-name':'Ghostty','window-title':f'ACC · {index}','workspace':'2','window-layout':'v_tiles'} for index,wid in enumerate((20,21,22),1)]
 def tearDown(self): c.STATE=self.old;self.tmp.cleanup()
 def target(self,window):
  frames={10:[0,0,400,700],20:[400,0,400,230],21:[400,238,400,230],22:[400,476,400,224]}
  return {'windowID':window['window-id'],'pid':window['app-pid'],'frame':frames[window['window-id']],'visibleFrame':[0,0,1200,900]}
 def test_apply_is_explicit_identity_bound_and_writes_after_verification(self):
  def native(window): return self.target(window)
  with patch.object(c,'boot_session',return_value='boot'), \
       patch.object(c,'terminal_windows',return_value=self.terminals), \
       patch.object(c,'aero',side_effect=['2',json.dumps([self.app]),*(['']*20)]) as aero, \
       patch.object(c,'_native_target',side_effect=native),patch.object(c,'_set_frame') as set_frame:
   self.assertIn('3 terminals',c.apply_mixed(3))
  saved=json.loads((c.STATE/'mixed-layout.json').read_text())
  self.assertEqual([(m['window-id'],m['app-pid']) for m in saved['members']],[(10,110),(20,120),(21,121),(22,122)])
  self.assertEqual(set_frame.call_count,4)
  self.assertEqual(aero.call_args_list[-1].args,('focus','--window-id','10'))
 def test_explicit_width_presets_divide_app_and_terminal_area(self):
  visible=[0,0,1200,900]
  third=c._mixed_frames(visible,2,app_width='1/3');half=c._mixed_frames(visible,2,app_width='1/2');wide=c._mixed_frames(visible,2,app_width='2/3')
  self.assertLess(third[0][2],half[0][2]);self.assertLess(half[0][2],wide[0][2])
  for frames in (third,half,wide):
   self.assertEqual(frames[0][2]+8+frames[1][2],1184)
   self.assertEqual(frames[1][2],frames[2][2])
   self.assertEqual(frames[1][3]+8+frames[2][3],884)
 def test_narrow_app_rejection_restores_every_started_member(self):
  calls=[]
  def set_frame(window,frame):
   calls.append((window['window-id'],frame))
   if window['window-id']==10 and len(calls)==1: raise RuntimeError('minimum width refused')
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'terminal_windows',return_value=self.terminals), \
       patch.object(c,'aero',side_effect=['2',json.dumps([self.app]),*(['']*20)]), \
       patch.object(c,'_native_target',side_effect=self.target),patch.object(c,'_set_frame',side_effect=set_frame):
   with self.assertRaisesRegex(RuntimeError,'rollback was attempted'):c.apply_mixed(2,app_width='1/3')
  self.assertIn((10,[0,0,400,700]),calls)
  self.assertFalse((c.STATE/'mixed-layout.json').exists())
 def test_menu_selected_identity_is_revalidated_in_current_page_inventory(self):
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'terminal_windows',return_value=self.terminals), \
       patch.object(c,'windows',return_value=[self.app,*self.terminals]), \
       patch.object(c,'aero',side_effect=['2',*(['']*20)]),patch.object(c,'_native_target',side_effect=self.target),patch.object(c,'_set_frame'):
   self.assertIn('1/2 width',c.apply_mixed(2,selected_identity=(10,110)))
 def test_menu_selected_identity_refuses_recycled_pid_before_resize(self):
  with patch.object(c,'aero',return_value='2'),patch.object(c,'windows',return_value=[dict(self.app,**{'app-pid':999})]),patch.object(c,'_set_frame') as set_frame:
   with self.assertRaisesRegex(RuntimeError,'no longer available'):c.apply_mixed(2,selected_identity=(10,110))
  set_frame.assert_not_called()
 def test_apply_failure_rolls_back_and_does_not_publish_checkpoint(self):
  calls=[]
  def set_frame(window,frame):
   calls.append((window['window-id'],frame))
   if window['window-id']==21 and frame!=self.target(window)['frame']: raise RuntimeError('refused')
  with patch.object(c,'terminal_windows',return_value=self.terminals), \
       patch.object(c,'aero',side_effect=['2',json.dumps([self.app]),*(['']*30)]), \
       patch.object(c,'_native_target',side_effect=self.target),patch.object(c,'_set_frame',side_effect=set_frame):
   with self.assertRaisesRegex(RuntimeError,'rollback was attempted'):c.apply_mixed(2)
  self.assertFalse((c.STATE/'mixed-layout.json').exists())
  self.assertIn((10,[0,0,400,700]),calls)
  self.assertIn((20,[400,0,400,230]),calls)
  self.assertIn((21,[400,238,400,230]),calls)
 def test_failed_apply_and_failed_rollback_keeps_recovery_checkpoint(self):
  def set_frame(window,frame):
   if window['window-id']==20: raise RuntimeError('frame refused')
  with patch.object(c,'boot_session',return_value='boot'), \
       patch.object(c,'terminal_windows',return_value=self.terminals), \
       patch.object(c,'aero',side_effect=['2',json.dumps([self.app]),*(['']*20)]), \
       patch.object(c,'_native_target',side_effect=self.target),patch.object(c,'_set_frame',side_effect=set_frame), \
       patch.object(c,'_restore_mixed_members',return_value=['20: rollback refused']):
   with self.assertRaisesRegex(RuntimeError,'Rollback errors'):c.apply_mixed(2)
  saved=json.loads((c.STATE/'mixed-layout.json').read_text())
  self.assertEqual(saved['state'],'recovery-required')
  self.assertEqual(saved['rollback-errors'],['20: rollback refused'])
  self.assertEqual([(m['window-id'],m['app-pid']) for m in saved['members']],[(10,110),(20,120),(21,121)])
 def test_apply_rejects_non_omac_workspace_before_window_query(self):
  with patch.object(c,'aero',return_value='Terminals') as aero,patch.object(c,'terminal_windows') as terminals:
   with self.assertRaisesRegex(RuntimeError,'outside an Omac page'):c.apply_mixed(2)
  aero.assert_called_once_with('list-workspaces','--focused');terminals.assert_not_called()
 def test_frame_verification_waits_for_two_stable_reads(self):
  moving=dict(self.target(self.app),frame=[20,0,400,700]);stable=self.target(self.app)
  with patch.object(c,'run'),patch.object(c,'_native_target',side_effect=[moving,stable,stable]) as target, \
       patch.object(c.time,'sleep'):
   c._set_frame(self.app,stable['frame'])
  self.assertEqual(target.call_count,3)
 def checkpoint(self):
  members=[]
  for window in [self.app,*self.terminals]:
   members.append({'window-id':window['window-id'],'app-pid':window['app-pid'],'workspace':'2','original-frame':self.target(window)['frame'],'original-layout':window['window-layout'],'placed-frame':self.target(window)['frame']})
  (c.STATE/'mixed-layout.json').write_text(json.dumps({'boot':'boot','workspace':'2','state':'active','members':members}))
 def test_focus_direction_targets_floating_member_by_geometry(self):
  self.checkpoint();live=[self.app,*self.terminals]
  with patch.object(c,'page',return_value='2'),patch.object(c,'boot_session',return_value='boot'), \
       patch.object(c,'windows',return_value=live),patch.object(c,'_native_target',side_effect=self.target), \
       patch.object(c,'aero',side_effect=[json.dumps([{'window-id':10}]),'']) as aero:
   self.assertIn('21',c.focus_direction('right'))
   self.assertEqual(aero.call_args_list[-1].args,('focus','--window-id','21'))
 def test_focus_falls_back_for_stale_identity_or_outside_preset(self):
  self.checkpoint();live=[dict(self.app,**{'app-pid':999}),*self.terminals]
  with patch.object(c,'page',return_value='2'),patch.object(c,'boot_session',return_value='boot'), \
       patch.object(c,'windows',return_value=live),patch.object(c,'aero') as aero:
   self.assertIn('ordinary',c.focus_direction('left'))
   aero.assert_called_once_with('focus','--ignore-floating','left',check=False)
 def test_restore_keeps_checkpoint_when_any_member_fails(self):
  self.checkpoint()
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'), \
       patch.object(c,'windows',return_value=[self.app,*self.terminals]), \
       patch.object(c,'_restore_mixed_members',return_value=['21: refused']):
   with self.assertRaisesRegex(RuntimeError,'incomplete'):c.restore_mixed()
  self.assertTrue((c.STATE/'mixed-layout.json').exists())
 def test_restore_refuses_moved_member_before_mutating(self):
  self.checkpoint();moved=[self.app,dict(self.terminals[0],workspace='3'),*self.terminals[1:]]
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'), \
       patch.object(c,'windows',return_value=moved),patch.object(c,'_restore_mixed_members') as restore:
   with self.assertRaisesRegex(RuntimeError,'identity or page changed'):c.restore_mixed()
   restore.assert_not_called()
 def test_switch_page_restores_before_switching(self):
  self.checkpoint();events=[]
  def restore(data):events.append('restore')
  def aero(*args,**kwargs):
   if args[:2]==('list-workspaces','--focused'):return '2'
   events.append(('aero',args));return ''
  with patch.object(c,'_restore_mixed_data',side_effect=restore),patch.object(c,'aero',side_effect=aero),patch.object(c,'windows',return_value=[]):
   c.switch_page('3')
  self.assertEqual(events,['restore',('aero',('workspace','3'))])
 def test_switch_page_restore_failure_prevents_switch(self):
  self.checkpoint()
  with patch.object(c,'_restore_mixed_data',side_effect=RuntimeError('restore failed')),patch.object(c,'aero',return_value='2') as aero:
   with self.assertRaisesRegex(RuntimeError,'restore failed'):c.switch_page('3')
  self.assertEqual(aero.call_args_list,[unittest.mock.call('list-workspaces','--focused')])
 def test_switch_page_refuses_stale_external_page_checkpoint(self):
  self.checkpoint()
  with patch.object(c,'aero',return_value='5') as aero,patch.object(c,'_restore_mixed_data') as restore:
   with self.assertRaisesRegex(RuntimeError,'recorded on page 2'):c.switch_page('3')
  restore.assert_not_called();self.assertEqual(len(aero.call_args_list),1)
 def test_switch_page_allows_return_to_stale_checkpoint_page_without_restore(self):
  self.checkpoint()
  with patch.object(c,'aero',side_effect=['5','']) as aero,patch.object(c,'_restore_mixed_data') as restore,patch.object(c,'windows',return_value=[]):
   c.switch_page('2')
  restore.assert_not_called();self.assertTrue((c.STATE/'mixed-layout.json').exists())
  self.assertEqual(aero.call_args_list[-1].args,('workspace','2'))
 def test_move_member_restores_before_move(self):
  self.checkpoint();events=[]
  def restore(data):events.append('restore')
  def aero(*args,**kwargs):
   if args[0]=='list-windows':return json.dumps([self.app])
   events.append(args);return ''
  with patch.object(c,'_restore_mixed_data',side_effect=restore),patch.object(c,'aero',side_effect=aero):c.move_focused_to_page('4')
  self.assertEqual(events,['restore',('move-node-to-workspace','--window-id','10','4')])
 def test_move_member_restore_failure_prevents_move(self):
  self.checkpoint()
  with patch.object(c,'_restore_mixed_data',side_effect=RuntimeError('restore failed')),patch.object(c,'aero',return_value=json.dumps([self.app])) as aero:
   with self.assertRaisesRegex(RuntimeError,'restore failed'):c.move_focused_to_page('4')
  self.assertEqual(len(aero.call_args_list),1)
 def test_move_member_to_current_page_is_noop_and_keeps_mixed(self):
  self.checkpoint()
  with patch.object(c,'aero',return_value=json.dumps([self.app])) as aero,patch.object(c,'_restore_mixed_data') as restore:
   self.assertIn('already',c.move_focused_to_page('2'))
  restore.assert_not_called();self.assertEqual(len(aero.call_args_list),1);self.assertTrue((c.STATE/'mixed-layout.json').exists())
 def test_prepare_tuck_restores_visible_member_and_nonmember_noops(self):
  self.checkpoint()
  with patch.object(c,'aero',return_value='2'),patch.object(c,'_restore_mixed_data') as restore:
   self.assertIn('restored before tucking',c.prepare_mixed_tuck(10,110));restore.assert_called_once()
  with patch.object(c,'aero') as aero,patch.object(c,'_restore_mixed_data') as restore:
   self.assertIn('not part',c.prepare_mixed_tuck(999,999));aero.assert_not_called();restore.assert_not_called()
 def test_prepare_tuck_off_checkpoint_page_refuses_before_restore(self):
  self.checkpoint()
  with patch.object(c,'aero',return_value='5'),patch.object(c,'_restore_mixed_data') as restore:
   with self.assertRaisesRegex(RuntimeError,'Return there'):c.prepare_mixed_tuck(10,110)
  restore.assert_not_called()
 def test_tile_mutations_are_refused_on_active_mixed_page(self):
  self.checkpoint()
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'),patch.object(c,'aero') as aero:
   for args in (('swap','left'),('resize','-50'),('balance',None),('layout-toggle',None),('fullscreen',None),('native-fullscreen',None)):
    with self.subTest(args=args),self.assertRaisesRegex(RuntimeError,'Restore Mixed Layout'):
     c.tile_command(*args)
   aero.assert_not_called()
 def test_tile_mutations_keep_original_behavior_without_mixed_mode(self):
  with patch.object(c,'page',return_value='2'),patch.object(c,'aero') as aero:
   c.tile_command('swap','right');c.tile_command('resize','+50');c.tile_command('balance');c.tile_command('layout-toggle');c.tile_command('fullscreen');c.tile_command('native-fullscreen')
  self.assertEqual([call.args for call in aero.call_args_list],[('swap','right'),('resize','smart','+50'),('balance-sizes','--workspace','2'),('layout','floating','tiling'),('fullscreen',),('macos-native-fullscreen',)])
 def test_mixed_expand_persists_before_mutation_then_restores_compact_frame(self):
  self.checkpoint();live=[self.app,*self.terminals];writes=[]
  def save(data): writes.append(json.loads(json.dumps(data)));(c.STATE/'mixed-layout.json').write_text(json.dumps(data))
  expanded=[8,8,1184,884]
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'), \
       patch.object(c,'windows',return_value=live),patch.object(c,'aero',return_value=json.dumps([self.app])), \
       patch.object(c,'_native_target',side_effect=[self.target(self.app),dict(self.target(self.app),frame=expanded)]), \
       patch.object(c,'_set_frame') as set_frame,patch.object(c,'_write_mixed',side_effect=save):
   self.assertIn('expanded',c.mixed_expand_toggle());self.assertIn('restored',c.mixed_expand_toggle())
  self.assertEqual(set_frame.call_args_list[0].args,(self.app,expanded))
  self.assertEqual(set_frame.call_args_list[1].args,(self.app,[0,0,400,700]))
  self.assertEqual(writes[0]['members'][0]['expand-state'],'expanding')
  final=json.loads((c.STATE/'mixed-layout.json').read_text())['members'][0]
  self.assertNotIn('expanded',final);self.assertNotIn('pre-expand-frame',final)
  self.assertEqual(final['original-frame'],[0,0,400,700])
 def test_mixed_expand_rejects_recycled_focused_identity_without_resize(self):
  self.checkpoint();focused=dict(self.app,**{'app-pid':999})
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'), \
       patch.object(c,'windows',return_value=[self.app,*self.terminals]),patch.object(c,'aero',return_value=json.dumps([focused])), \
       patch.object(c,'_set_frame') as set_frame:
   with self.assertRaisesRegex(RuntimeError,'not a valid member'):c.mixed_expand_toggle()
  set_frame.assert_not_called()
 def test_menu_mixed_expand_uses_captured_identity_not_helper_focus(self):
  self.checkpoint();live=[self.app,*self.terminals]
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'), \
       patch.object(c,'windows',return_value=live),patch.object(c,'aero') as aero, \
       patch.object(c,'_native_target',return_value=self.target(self.app)),patch.object(c,'_set_frame') as set_frame:
   self.assertIn('expanded',c.mixed_expand_toggle(selected_identity=(10,110)))
  aero.assert_not_called();self.assertEqual(set_frame.call_args.args[0],self.app)
 def test_menu_mixed_expand_refuses_missing_captured_identity(self):
  self.checkpoint();live=[dict(self.app,**{'app-pid':999}),*self.terminals]
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'), \
       patch.object(c,'windows',return_value=live),patch.object(c,'aero') as aero,patch.object(c,'_set_frame') as set_frame:
   with self.assertRaisesRegex(RuntimeError,'no longer available'):c.mixed_expand_toggle(selected_identity=(10,110))
  aero.assert_not_called();set_frame.assert_not_called()
 def test_mixed_expand_failed_rollback_keeps_recovery_state(self):
  self.checkpoint();live=[self.app,*self.terminals]
  with patch.object(c,'boot_session',return_value='boot'),patch.object(c,'page',return_value='2'), \
       patch.object(c,'windows',return_value=live),patch.object(c,'aero',return_value=json.dumps([self.app])), \
       patch.object(c,'_native_target',return_value=self.target(self.app)), \
       patch.object(c,'_set_frame',side_effect=[RuntimeError('expand refused'),RuntimeError('rollback refused')]):
   with self.assertRaisesRegex(RuntimeError,'rollback also failed'):c.mixed_expand_toggle()
  saved=json.loads((c.STATE/'mixed-layout.json').read_text())
  self.assertEqual(saved['state'],'recovery-required');self.assertIn('rollback refused',saved['rollback-errors'][0])

if __name__=='__main__':unittest.main()
