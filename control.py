#!/opt/homebrew/bin/python3
"""On-demand controller. No API calls, credentials, or background polling."""
import fcntl,json,os,plistlib,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
STATE=Path.home()/'Library/Application Support/AgentControlCenter'
STATE.mkdir(parents=True,exist_ok=True)
DOMAIN=f'gui/{os.getuid()}'
AERO='/opt/homebrew/bin/aerospace'
APP='/Applications/Agent Control Center.app/Contents/MacOS/AgentControlCenter'
ROLES=['Claude','Codex','Hermes','Local']

def run(*args,check=True):
 p=subprocess.run([str(a) for a in args],capture_output=True,text=True,timeout=30)
 if check and p.returncode: raise RuntimeError((p.stderr or p.stdout).strip() or str(args))
 return p.stdout.strip()
def aero(*args,check=True): return run(AERO,*args,check=check)
def job(name): return DOMAIN+'/com.richard.acc.'+name

def load(name):
 p=subprocess.run(['launchctl','print',job(name)],capture_output=True)
 if p.returncode: run('launchctl','bootstrap',DOMAIN,ROOT/'launchd'/f'{name}.plist')

def windows(): return json.loads(aero('list-windows','--all','--json'))
def ready():
 for _ in range(30):
  try: windows(); return
  except Exception: time.sleep(.2)
 raise RuntimeError('AeroSpace is not ready. Grant AeroSpace Accessibility access in System Settings, then try Enter again.')
def save_status(value): (STATE/'status').write_text(value)

def stop(restore=False):
 aero('mode','main',check=False)
 aero('enable','off',check=False)
 save_status('Paused' if not restore else 'Inactive')
 if restore:
  (STATE/'aerospace.enabled').unlink(missing_ok=True)
  run('launchctl','bootout',job('aerospace'),check=False)
  run(APP,'--restore',check=False)
 return 'Windows and agent sessions remain open.'

def enter():
 existing=aero('config','--config-path',check=False)
 if existing and existing!=str(ROOT/'config/aerospace.toml'):
  raise RuntimeError('Another AeroSpace configuration is active. Exit it before entering Control Center.')
 # Check access and save geometry before any window management changes.
 if (STATE/'status').exists() and (STATE/'status').read_text()=='Active':
  try:
   if aero('config','--config-path')==str(ROOT/'config/aerospace.toml'):
    aero('workspace','Agents'); return 'Already active; existing sessions reused.'
  except Exception: pass
 run(APP,'--snapshot')
 (STATE/'aerospace.enabled').touch()
 load('aerospace')
 run('launchctl','kickstart',job('aerospace'))
 try:
  ready()
  if aero('config','--config-path')!=str(ROOT/'config/aerospace.toml'):
   raise RuntimeError('A different AeroSpace instance is running. Exit it before entering Control Center.')
  aero('reload-config','--dry-run')
  aero('enable','on')
  aero('mode','active')
  for role in ROLES:
   label='terminal.'+role.lower(); load(label)
   # launchctl kickstart without -k never replaces a running terminal.
   run('launchctl','kickstart',job(label),check=False)
  for app in ['ChatGPT','Claude','Google Chrome']: run('open','-a',app)
  for _ in range(40):
   ws=windows()
   if all(any(w.get('window-title','')=='ACC · '+r for w in ws) for r in ROLES): break
   time.sleep(.25)
  agents=[]
  for w in windows():
   title=w.get('window-title',''); app=w.get('app-name',''); wid=str(w['window-id'])
   dest='Agents' if title.startswith('ACC · ') else 'Research' if app in ['ChatGPT','Claude','Google Chrome'] else None
   if dest:
    aero('move-node-to-workspace','--window-id',wid,dest)
    aero('layout','--window-id',wid,'tiling')
    if dest=='Agents': agents.append(wid)
  aero('workspace','Agents')
  # Four-column fallback remains usable; create a balanced 2x2 for the default four tiles.
  if len(agents)==4:
   aero('flatten-workspace-tree')
   aero('layout','h_tiles')
   aero('join-with','--window-id',agents[1],'left')
   aero('layout','--window-id',agents[1],'v_tiles')
   aero('join-with','--window-id',agents[3],'left')
   aero('layout','--window-id',agents[3],'v_tiles')
   aero('balance-sizes')
  save_status('Active')
  return 'Control Center active.'
 except Exception:
  stop(True)
  raise

def main():
 action=sys.argv[1] if len(sys.argv)>1 else 'status'
 with (STATE/'controller.lock').open('w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  if action=='enter': print(enter())
  elif action in ('pause','exit'): print(stop(action=='exit'))
  elif action=='status': print((STATE/'status').read_text() if (STATE/'status').exists() else 'Inactive')
  elif action=='rollback':
   stop(True)
   (STATE/'menu.enabled').unlink(missing_ok=True)
   run('launchctl','bootout',job('menu'),check=False)
   print('Control Center disabled. Agent terminals were not stopped. No global configuration was changed.')
  else: raise RuntimeError('Unknown action')
if __name__=='__main__':
 try: main()
 except Exception as e: print(str(e),file=sys.stderr); sys.exit(1)
