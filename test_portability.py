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
   self.assertEqual(config['persistent-workspaces'],['1','2','3','4','5'])
   job=plistlib.loads((state/'runtime/launchd/menu.plist').read_bytes())
   self.assertEqual(job['ProgramArguments'],[app,'--managed'])
   self.assertEqual(job['EnvironmentVariables']['OMAC_STATE_ROOT'],str(state))
   self.assertEqual(job['EnvironmentVariables']['PYTHONDONTWRITEBYTECODE'],'1')
   watcher=plistlib.loads((state/'runtime/launchd/watcher.plist').read_bytes())
   self.assertEqual(watcher['ProgramArguments'],[sys.executable,str(payload/'watcher.py')])
   # No original checkout or user's account directory may leak into generated jobs.
   for file in (state/'runtime/launchd').glob('*.plist'):
    self.assertNotIn(str(source),file.read_text())
if __name__=='__main__':unittest.main()
