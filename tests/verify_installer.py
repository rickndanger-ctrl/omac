from pathlib import Path
import tempfile,subprocess,os,shutil
repo=Path.cwd()
with tempfile.TemporaryDirectory(prefix='omac-install-test-') as folder:
 root=Path(folder);source=root/'download';source.mkdir()
 shutil.copy2(repo/'Install Omac.command',source/'Install Omac.command')
 subprocess.run(['ditto',str(repo/'dist/staging/Omac.app'),str(source/'Omac.app')],check=True)
 for failing in (False,True):
  case=root/('failure' if failing else 'success');case.mkdir();state=case/'state';state.mkdir();(state/'sentinel').write_text('original')
  target=case/'Applications/Omac.app';target.mkdir(parents=True);(target/'old-app-marker').write_text('original')
  saver=case/'savers';(saver/'OMAC.saver').mkdir(parents=True);(saver/'OMAC.saver/old-marker').write_text('original')
  if failing:(state/'runtime').write_text('force generator failure')
  env=dict(os.environ,OMAC_INSTALL_DESTINATION=str(target),OMAC_STATE_ROOT=str(state),OMAC_SAVER_DESTINATION=str(saver),OMAC_BACKUP_ROOT=str(case/'backups'),OMAC_NO_LAUNCH='1')
  r=subprocess.run(['/bin/zsh',str(source/'Install Omac.command')],env=env,capture_output=True,text=True)
  if failing:
   assert r.returncode!=0,r.stdout
   assert (target/'old-app-marker').read_text()=='original'
   assert (state/'runtime').read_text()=='force generator failure'
   assert (saver/'OMAC.saver/old-marker').read_text()=='original'
   print('FAILURE ROLLBACK PASSED: original app, state, saver restored')
  else:
   assert r.returncode==0,r.stderr
   assert (target/'Contents/MacOS/AgentControlCenter').is_file()
   assert (state/'sentinel').read_text()=='original'
   assert (state/'runtime/launchd/menu.plist').is_file()
   print('SUCCESS INSTALL PASSED: relocated app and runtime ready')
