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
ROLES=[str(i) for i in range(1,7)]

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
  try:
   aero('enable','on'); windows(); return
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

def terminal_windows():
 result=[]
 for w in windows():
  if w.get('app-name')!='Ghostty': continue
  title=w.get('window-title','')
  for role in ROLES:
   canonical='ACC · '+role
   if title.endswith(canonical):
    result.append(dict(w,**{'window-title':canonical})); break
 return sorted(result,key=lambda w:(w['window-title'],w['window-id']))

def arrange():
 tiles=terminal_windows()
 for w in tiles:
  wid=str(w['window-id'])
  aero('move-node-to-workspace','--window-id',wid,'Terminals')
  aero('layout','--window-id',wid,'tiling')
 aero('workspace','Terminals')
 if tiles:
  aero('focus','--window-id',str(tiles[0]['window-id']))
  aero('flatten-workspace-tree')
  aero('layout','--workspace','Terminals','--root','h_tiles')
  # Normalize physical order before pairing; titles need not match tree order.
  for w in reversed(tiles):
   for _ in tiles: aero('move','--window-id',str(w['window-id']),'left',check=False)
  for i in range(1,len(tiles),2):
   wid=str(tiles[i]['window-id'])
   aero('join-with','--window-id',wid,'left')
   aero('layout','--window-id',wid,'v_tiles')
  aero('balance-sizes')
  aero('focus','--window-id',str(tiles[0]['window-id']))
 return len(tiles)

def enter(count=4,add=False):
 existing=aero('config','--config-path',check=False)
 if existing and existing!=str(ROOT/'config/aerospace.toml'):
  raise RuntimeError('Another AeroSpace configuration is active. Exit it before entering Control Center.')
 run(APP,'--snapshot')
 (STATE/'aerospace.enabled').touch()
 load('aerospace')
 run('launchctl','kickstart',job('aerospace'))
 try:
  ready()
  if aero('config','--config-path')!=str(ROOT/'config/aerospace.toml'):
   raise RuntimeError('A different AeroSpace instance is running.')
  aero('reload-config')
  aero('enable','on')
  aero('mode','active')
  current=terminal_windows()
  if add: count=min(6,len(current)+1)
  present={w['window-title'] for w in current}
  needed=max(0,count-len(current))
  expected=set(present)
  for role in ROLES:
   if not needed: break
   title='ACC · '+role
   if title in present: continue
   label='terminal.'+role; load(label)
   run('launchctl','kickstart','-k',job(label),check=False)
   expected.add(title); needed-=1
  for _ in range(60):
   if expected.issubset({w['window-title'] for w in terminal_windows()}): break
   time.sleep(.25)
  missing=expected-{w['window-title'] for w in terminal_windows()}
  if missing: raise RuntimeError('Terminal windows did not appear: '+', '.join(sorted(missing))+'. Resolve any Ghostty first-launch prompt and retry.')
  total=arrange()
  save_status('Active')
  return f'{total} plain terminal windows tiled. No agents launched.'
 except Exception:
  stop(True)
  raise

def main():
 action=sys.argv[1] if len(sys.argv)>1 else 'status'
 with (STATE/'controller.lock').open('w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  if action in ('enter','four','six','new'): print(enter(6 if action=='six' else 4,add=action=='new'))
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
