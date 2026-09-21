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
ROLES=[str(i) for i in range(1,31)]

def run(*args,check=True):
 p=subprocess.run([str(a) for a in args],capture_output=True,text=True,timeout=30)
 if check and p.returncode: raise RuntimeError((p.stderr or p.stdout).strip() or str(args))
 return p.stdout.strip()
def aero(*args,check=True): return run(AERO,*args,check=check)
def job(name): return DOMAIN+'/com.richard.acc.'+name

def load(name):
 p=subprocess.run(['launchctl','print',job(name)],capture_output=True)
 if name.startswith('terminal.') and p.returncode==0 and b'--config-file=' not in p.stdout:
  # Reload only when creating a missing terminal; preserve already-open Ghostty windows.
  run('launchctl','bootout',job(name),check=False)
  p.returncode=1
 if p.returncode: run('launchctl','bootstrap',DOMAIN,ROOT/'launchd'/f'{name}.plist')

def windows():
 return json.loads(aero('list-windows','--all','--format','%{window-id} %{app-pid} %{app-name} %{window-title} %{workspace} %{window-layout}','--json'))
def page():
 value=aero('list-workspaces','--focused').strip()
 return value if value in ('1','2','3','4','5') else '1'
def save_pages():
 data={'page':page(),'windows':windows()}
 temp=STATE/'pages.tmp';temp.write_text(json.dumps(data));temp.replace(STATE/'pages.json')
def restore_pages():
 path=STATE/'pages.json'
 if not path.exists(): return
 data=json.loads(path.read_text());live={w['window-id']:w for w in windows()}
 commands=[]
 for w in data['windows']:
  current=live.get(w['window-id'])
  if not current or current.get('app-pid')!=w.get('app-pid'): continue
  target=w.get('workspace')
  if target not in ('1','2','3','4','5'): continue
  commands.append(f"move-node-to-workspace --window-id {w['window-id']} {target}")
  layout='floating' if w.get('window-layout')=='floating' else 'tiling'
  commands.append(f"layout --window-id {w['window-id']} {layout}")
 if commands: aero('eval','; '.join(commands))
 aero('workspace',data.get('page','1'))
def migrate_pages():
 for w in windows():
  if w.get('workspace')=='Terminals':
   aero('move-node-to-workspace','--window-id',str(w['window-id']),'1')

def ready():
 for _ in range(30):
  try:
   aero('enable','on'); windows(); return
  except Exception: time.sleep(.2)
 raise RuntimeError('AeroSpace is not ready. Grant AeroSpace Accessibility access in System Settings, then try Enter again.')
def save_status(value): (STATE/'status').write_text(value)

def stop(restore=False):
 try: save_pages()
 except (RuntimeError,ValueError): pass
 aero('mode','main',check=False)
 aero('enable','off',check=False)
 save_status('Paused' if not restore else 'Inactive')
 if restore:
  (STATE/'aerospace.enabled').unlink(missing_ok=True)
  run('launchctl','bootout',job('aerospace'),check=False)
  run(APP,'--restore',check=False)
 return 'Windows and agent sessions remain open.'

def terminal_windows(workspace=None):
 result=[]
 for w in windows():
  if w.get('app-name')!='Ghostty' or (workspace is not None and w.get('workspace')!=workspace): continue
  title=w.get('window-title','')
  for role in ROLES:
   canonical='ACC · '+role
   if title.endswith(canonical):
    result.append(dict(w,**{'window-title':canonical})); break
 return sorted(result,key=lambda w:(w['window-title'],w['window-id']))

def arrange(workspace=None):
 workspace=workspace or page()
 tiles=terminal_windows(workspace)
 if not tiles: return 0
 ids=[str(w['window-id']) for w in tiles]
 focused=aero('list-windows','--focused','--format','%{window-id}',check=False)
 target=focused if focused in ids else ids[0]
 # One request avoids repainting between dozens of individual CLI invocations.
 commands=[]
 for wid in ids:
  commands.extend([f'fullscreen off --window-id {wid}',
                   f'move-node-to-workspace --window-id {wid} {workspace}',
                   f'layout --window-id {wid} tiling'])
 commands.extend([f'workspace {workspace}',f'focus --window-id {ids[0]}',
                  'flatten-workspace-tree',f'layout --workspace {workspace} --root h_tiles'])
 for wid in reversed(ids):
  commands.extend([f'move --window-id {wid} left || true']*len(ids))
 for i in range(1,len(ids),2):
  commands.extend([f'join-with --window-id {ids[i]} left',f'layout --window-id {ids[i]} v_tiles'])
 commands.extend([f'balance-sizes --workspace {workspace}',f'focus --window-id {target}'])
 aero('eval','; '.join(commands))
 return len(tiles)

def enter(count=0,add=False):
 existing=aero('config','--config-path',check=False)
 if existing and existing!=str(ROOT/'config/aerospace.toml'):
  raise RuntimeError('Another AeroSpace configuration is active. Exit it before entering Control Center.')
 active=existing==str(ROOT/'config/aerospace.toml') and (STATE/'status').exists() and (STATE/'status').read_text()=='Active'
 if not active:
  run(APP,'--snapshot')
  (STATE/'aerospace.enabled').touch()
  load('aerospace')
  run('launchctl','kickstart',job('aerospace'))
 try:
  if not active: ready()
  if aero('config','--config-path')!=str(ROOT/'config/aerospace.toml'):
   raise RuntimeError('A different AeroSpace instance is running.')
  if not active:
   aero('reload-config')
   aero('enable','on')
   aero('mode','active')
  if not active and not existing: restore_pages()
  migrate_pages()
  workspace=page()
  current=terminal_windows(workspace)
  if add: count=min(6,len(current)+1)
  before={w['window-id'] for w in current}
  present={w['window-title'] for w in terminal_windows()}
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
  if add and active:
   # Insert only new windows; preserve current sizes, positions and fullscreen state.
   all_tiles=terminal_windows()
   added=[w for w in all_tiles if w['window-title'] in expected-present]
   for w in added:
    wid=str(w['window-id'])
    aero('move-node-to-workspace','--window-id',wid,workspace)
    aero('layout','--window-id',wid,'tiling')
   if added:
    aero('workspace',workspace)
    aero('focus','--window-id',str(added[-1]['window-id']))
   total=len(terminal_windows(workspace))
  elif count:
   for w in terminal_windows():
    if w['window-title'] in expected-present:
     aero('move-node-to-workspace','--window-id',str(w['window-id']),workspace)
   total=arrange(workspace)
  else:
   total=len(current)
  save_status('Active')
  save_pages()
  return f'{total} plain terminal windows tiled. No agents launched.'
 except Exception:
  stop(True)
  raise

def main():
 action=sys.argv[1] if len(sys.argv)>1 else 'status'
 with (STATE/'controller.lock').open('w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  if action in ('enter','four','six','new'): print(enter(6 if action=='six' else (4 if action=='four' else 0),add=action=='new'))
  elif action=='center':
   focused=json.loads(aero('list-windows','--focused','--json'))
   if not focused: raise RuntimeError('Focus a window first.')
   wid=str(focused[0]['window-id'])
   layout=aero('list-windows','--focused','--format','%{window-layout}')
   if layout=='floating':
    aero('layout','--window-id',wid,'tiling')
    aero('balance-sizes','--workspace',page())
    aero('focus','--window-id',wid)
    print('Terminal returned to tiling.')
   else:
    pid=aero('list-windows','--focused','--format','%{app-pid}')
    aero('fullscreen','off','--window-id',wid)
    aero('layout','--window-id',wid,'floating')
    try: run(APP,'--center',pid)
    except Exception:
     aero('layout','--window-id',wid,'tiling')
     raise
    aero('focus','--window-id',wid)
    print('Terminal centered; Command-O returns it to tiling.')
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
