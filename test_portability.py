import json,os,plistlib,shutil,subprocess,sys,tempfile,tomllib,unittest
from pathlib import Path
class Portability(unittest.TestCase):
 def test_relocated_resources_generate_only_user_state_with_safe_paths(self):
  source=Path(__file__).resolve().parent
  with tempfile.TemporaryDirectory(prefix="omac user's space ") as temp:
   temp=Path(temp).resolve();payload=temp/'Moved Omac.app/Contents/Resources/Payload';payload.mkdir(parents=True)
   state=temp/'User Data';app=str(payload.parents[1]/'MacOS/AgentControlCenter')
   for name in ('generate_config.py','portable_paths.py'):
    shutil.copy2(source/name,payload/name)
   env=dict(os.environ,OMAC_STATE_ROOT=str(state),OMAC_APP_EXECUTABLE=app,PYTHONDONTWRITEBYTECODE='1')
   subprocess.run([sys.executable,str(payload/'generate_config.py')],env=env,check=True)
   self.assertEqual(sorted(x.name for x in payload.iterdir()),['generate_config.py','portable_paths.py'])
   config=tomllib.loads((state/'runtime/config/aerospace.toml').read_text())
   self.assertIn(str(payload/'control.py').replace("'","'\"'\"'"),config['after-startup-command'][0])
   self.assertIn(str(payload/'control.py').replace("'","'\"'\"'"),config['mode']['active']['binding']['cmd-enter'])
   self.assertTrue(config['mode']['active']['binding']['cmd-enter'].endswith(' new'))
   self.assertNotIn('agent-control-center://new',config['mode']['active']['binding']['cmd-enter'])
   self.assertEqual(config['persistent-workspaces'],['1','2','3','4','5'])
   job=plistlib.loads((state/'runtime/launchd/menu.plist').read_bytes())
   self.assertEqual(job['ProgramArguments'],[app,'--managed'])
   self.assertEqual(job['EnvironmentVariables']['OMAC_STATE_ROOT'],str(state))
   self.assertEqual(job['EnvironmentVariables']['PYTHONDONTWRITEBYTECODE'],'1')
   watcher=plistlib.loads((state/'runtime/launchd/watcher.plist').read_bytes())
   self.assertEqual(watcher['ProgramArguments'],[sys.executable,str(payload/'watcher.py')])
   terminal=plistlib.loads((state/'runtime/launchd/terminal.1.plist').read_bytes())
   self.assertEqual(terminal['ProgramArguments'][:4],['/usr/bin/open','-W','-n','-a'])
   self.assertIn('--title=ACC · 1',terminal['ProgramArguments'])
   # No original checkout or user's account directory may leak into generated jobs.
   for file in (state/'runtime/launchd').glob('*.plist'):
    self.assertNotIn(str(source),file.read_text())
 def test_remote_bindings_are_opt_in_and_work_in_both_modes(self):
  source=Path(__file__).resolve().parent
  with tempfile.TemporaryDirectory() as temp:
   temp=Path(temp);payload=temp/'Payload';payload.mkdir()
   state=temp/'state';app=str(temp/'Omac.app/Contents/MacOS/AgentControlCenter')
   for name in ('generate_config.py','portable_paths.py'):
    shutil.copy2(source/name,payload/name)
   (state/'remote-control.json').parent.mkdir()
   (state/'remote-control.json').write_text(json.dumps({'version':1,'enabled':True,'connectionPath':'~/Library/Connections/mini.vncloc'}))
   env=dict(os.environ,OMAC_STATE_ROOT=str(state),OMAC_APP_EXECUTABLE=app,PYTHONDONTWRITEBYTECODE='1')
   subprocess.run([sys.executable,str(payload/'generate_config.py')],env=env,check=True)
   config=tomllib.loads((state/'runtime/config/aerospace.toml').read_text())
   for mode in ('main','active'):
    bindings=config['mode'][mode]['binding']
    self.assertIn('ctrl-alt-1',bindings)
    self.assertIn('ctrl-alt-2',bindings)
    self.assertIn(str(payload/'mac_switch.py'),bindings['ctrl-alt-2'])
    self.assertTrue(bindings['ctrl-alt-1'].endswith(' local'))
    self.assertTrue(bindings['ctrl-alt-2'].endswith(' remote'))
 def test_optional_host_monitor_mapping_is_generated_without_a_hardcoded_display(self):
  source=Path(__file__).resolve().parent
  with tempfile.TemporaryDirectory() as temp:
   temp=Path(temp);payload=temp/'Payload';payload.mkdir();state=temp/'state'
   for name in ('generate_config.py','portable_paths.py'):
    shutil.copy2(source/name,payload/name)
   state.mkdir()
   (state/'preferred-monitor.json').write_text(json.dumps({'version':1,'workspaceToMonitor':{'1':'main','4':'secondary','9':'ignored'}}))
   env=dict(os.environ,OMAC_STATE_ROOT=str(state),PYTHONDONTWRITEBYTECODE='1')
   subprocess.run([sys.executable,str(payload/'generate_config.py')],env=env,check=True)
   config=tomllib.loads((state/'runtime/config/aerospace.toml').read_text())
   self.assertEqual(config['workspace-to-monitor-force-assignment'],{'1':'main','4':'secondary'})
if __name__=='__main__':unittest.main()
