#!/opt/homebrew/bin/python3
"""On-demand controller. No API calls, credentials, or background polling."""
import fcntl,json,os,plistlib,subprocess,sys,time
from functools import lru_cache
from pathlib import Path
from portable_paths import SOURCE as ROOT, STATE, RUNTIME, AERO, APP
from tile_modes import Mode,TileModePlanner,WindowIdentity,WindowSnapshot
STATE.mkdir(parents=True,exist_ok=True)
DOMAIN=f'gui/{os.getuid()}'
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
 if p.returncode: run('launchctl','bootstrap',DOMAIN,RUNTIME/'launchd'/f'{name}.plist')

def windows():
 return json.loads(aero('list-windows','--all','--format','%{window-id} %{app-pid} %{app-name} %{window-title} %{workspace} %{window-layout}','--json'))
def page():
 value=aero('list-workspaces','--focused').strip()
 return value if value in ('1','2','3','4','5') else '1'
@lru_cache(maxsize=1)
def boot_session(): return run('/usr/sbin/sysctl','-n','kern.boottime')
def status():
 try: return (STATE/'status').read_text()
 except FileNotFoundError: return 'Inactive'
def save_pages():
 current=windows()
 path=STATE/'pages.json'
 # AeroSpace temporarily reports an empty inventory while displays reconnect or
 # macOS hides/minimizes every window. Keep the last useful page assignment so
 # recovery and Command-Escape still have something authoritative to restore.
 if not current and path.exists():
  try:
   previous=json.loads(path.read_text())
   if isinstance(previous,dict) and previous.get('boot')==boot_session() and previous.get('windows'): return False
  except (ValueError,OSError): pass
 data={'boot':boot_session(),'page':page(),'windows':current}
 temp=STATE/'pages.tmp';temp.write_text(json.dumps(data));temp.replace(path)
 return True
def restore_pages():
 path=STATE/'pages.json'
 if not path.exists(): return
 try:
  data=json.loads(path.read_text())
  if not isinstance(data,dict) or not isinstance(data.get('windows'),list): return
 except (ValueError,OSError): return
 if data.get('boot')!=boot_session(): return
 live={w['window-id']:w for w in windows()}
 commands=[]
 for w in data['windows']:
  if not isinstance(w,dict) or not isinstance(w.get('window-id'),int): continue
  current=live.get(w['window-id'])
  if not current or current.get('app-pid')!=w.get('app-pid'): continue
  target=w.get('workspace')
  if target not in ('1','2','3','4','5'): continue
  commands.append(f"move-node-to-workspace --window-id {w['window-id']} {target}")
  layout='floating' if w.get('window-layout')=='floating' else 'h_tiles'
  commands.append(f"layout --window-id {w['window-id']} {layout}")
 if commands:
  aero('eval','; '.join(commands))
  for workspace in ('1','2','3','4','5'):
   saved=[w for w in data['windows'] if isinstance(w,dict) and w.get('workspace')==workspace]
   terminals=[w for w in saved if w.get('app-name')=='Ghostty']
   if len(terminals)>=3 and all(w.get('window-layout')!='floating' for w in terminals) and all(w.get('app-name')=='Ghostty' or w.get('window-layout') in ('floating','macos_native_window_of_hidden_app','macos_fullscreen') for w in saved):
    arrange(workspace)
 target=data.get('page','1')
 aero('workspace',target if target in ('1','2','3','4','5') else '1')
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

def _tile_mode_path(): return STATE/'tile-modes.json'
def _tile_mode_key(identity): return f'{identity.boot}:{identity.app_pid}:{identity.window_id}'
def _load_tile_modes():
 try: return json.loads(_tile_mode_path().read_text())
 except (FileNotFoundError,ValueError,OSError): return {}
def _save_tile_modes(data):
 temp=STATE/'tile-modes.tmp';temp.write_text(json.dumps(data));temp.replace(_tile_mode_path())

def _ax_half(pid):
 # AeroSpace has no exact half-width primitive; AX places the selected app on
 # the left half of the visible main screen without changing its process.
 script='''ObjC.import("AppKit");
const s=$.NSScreen.mainScreen.visibleFrame;
const p=Application("System Events").processes.whose({unixId:%d})[0];
const w=p.windows[0];
w.position=[s.origin.x,s.origin.y];
w.size=[Math.floor(s.size.width/2),s.size.height];''' % pid
 run('/usr/bin/osascript','-l','JavaScript','-e',script)

def size_window(mode):
 try: mode=Mode(mode)
 except (TypeError,ValueError) as exc: raise RuntimeError('size must be small, half, or full') from exc
 focused=json.loads(aero('list-windows','--focused','--json'))
 if not focused: raise RuntimeError('Focus a window first.')
 window=focused[0]
 try:
  identity=WindowIdentity(int(window['window-id']),int(window['app-pid']),boot_session())
 except (KeyError,TypeError,ValueError) as exc: raise RuntimeError('Focused window has no stable identity.') from exc
 workspace=window.get('workspace')
 if workspace not in ('1','2','3','4','5'): raise RuntimeError('Focused window is outside an Omac page.')
 key=_tile_mode_key(identity);saved=_load_tile_modes();record=saved.get(key,{})
 planner=TileModePlanner(WindowSnapshot(identity,workspace,str(identity.window_id)))
 try: planner.mode=Mode(record.get('mode',Mode.SMALL.value))
 except ValueError: planner.mode=Mode.SMALL
 intent=planner.transition(identity,mode)
 if intent.action=='noop': return f'Window already {mode.value}.'
 wid=str(identity.window_id)
 if mode is Mode.SMALL:
  aero('fullscreen','off','--window-id',wid)
  aero('layout','--window-id',wid,'tiling')
 elif mode is Mode.HALF:
  aero('fullscreen','off','--window-id',wid)
  aero('layout','--window-id',wid,'floating')
  _ax_half(identity.app_pid)
 else:
  aero('fullscreen','on','--window-id',wid)
 saved[key]={'mode':mode.value,'workspace':workspace,'window-id':identity.window_id,'app-pid':identity.app_pid,'boot':identity.boot}
 _save_tile_modes(saved)
 aero('workspace',workspace)
 return f'Window set to {mode.value}; session preserved.'

def stop(restore=False):
 run('launchctl','bootout',job('watcher'),check=False)
 try: save_pages()
 except (RuntimeError,ValueError): pass
 aero('mode','main',check=False)
 aero('enable','off',check=False)
 save_status('Paused' if not restore else 'Inactive')
 if restore:
  (STATE/'aerospace.enabled').unlink(missing_ok=True)
  run('launchctl','bootout',job('aerospace'),check=False)
  run(APP,'--restore',check=False)
  run(APP,'--restore-wallpaper',check=False)
 return 'Windows and agent sessions remain open.'

def terminal_windows(workspace=None):
 result=[]
 for w in windows():
  if w.get('app-name')!='Ghostty' or (workspace is not None and w.get('workspace')!=workspace): continue
  title=w.get('window-title','')
  for role in ROLES:
   canonical='ACC · '+role
   if title.endswith(canonical) or title.endswith('Omac · '+role):
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
 aero('eval','; '.join(commands))
 # Query the actual tree order after flattening; title order need not match it.
 ordered=[]
 for index in range(len(windows())):
  aero('focus','--dfs-index',str(index),check=False)
  wid=aero('list-windows','--focused','--format','%{window-id}',check=False)
  if wid in ids and wid not in ordered: ordered.append(wid)
 for i in range(0,len(ordered)-1,2):
  aero('join-with','--window-id',ordered[i],'right')
 aero('balance-sizes','--workspace',workspace)
 aero('focus','--window-id',target)
 return len(tiles)

def start_services():
 load('watcher');run('launchctl','kickstart',job('watcher'))
 run(APP,'--apply-wallpaper',check=False)

def enter(count=0,add=False):
 existing=aero('config','--config-path',check=False)
 if existing and existing!=str(RUNTIME/'config/aerospace.toml'):
  raise RuntimeError('Another AeroSpace configuration is active. Exit it before entering Omac.')
 active=existing==str(RUNTIME/'config/aerospace.toml') and (STATE/'status').exists() and (STATE/'status').read_text()=='Active'
 if not active:
  run(APP,'--snapshot')
  (STATE/'aerospace.enabled').touch()
  load('aerospace')
  run('launchctl','kickstart',job('aerospace'))
 try:
  if not active: ready()
  if aero('config','--config-path')!=str(RUNTIME/'config/aerospace.toml'):
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
   # Place new terminals on their requested page, then apply the same grid as Four / Six.
   all_tiles=terminal_windows()
   added=[w for w in all_tiles if w['window-title'] in expected-present]
   for w in added:
    wid=str(w['window-id'])
    aero('move-node-to-workspace','--window-id',wid,workspace)
    aero('layout','--window-id',wid,'tiling')
   if added:
    aero('workspace',workspace)
    aero('focus','--window-id',str(added[-1]['window-id']))
    arrange(workspace)
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
  start_services()
  return f'{total} plain terminal windows tiled. No agents launched.'
 except Exception:
  stop(True)
  raise

def login():
 # A separate RunAtLoad job runs once per GUI login; never launches agent commands.
 marker=STATE/'login-boot'
 if marker.exists() and marker.read_text()!=boot_session():
  (STATE/'windows.json').unlink(missing_ok=True)
 marker.write_text(boot_session())
 if aero('config','--config-path',check=False)!=str(RUNTIME/'config/aerospace.toml'):
  save_status('Inactive')
 (STATE/'menu.enabled').touch()
 load('menu');run('launchctl','kickstart',job('menu'))
 return enter()
def login_enabled(enabled):
 destination=Path.home()/'Library/LaunchAgents/com.richard.acc.login.plist'
 if enabled:
  destination.parent.mkdir(parents=True,exist_ok=True)
  destination.write_bytes((RUNTIME/'launchd/login.plist').read_bytes())
  run('launchctl','bootout',job('login'),check=False)
  run('launchctl','bootstrap',DOMAIN,destination)
  return 'Omac will start after macOS sign-in.'
 run('launchctl','bootout',job('login'),check=False)
 destination.unlink(missing_ok=True)
 return 'Automatic start disabled.'
def recover():
 # Startup hook executes under the same lock as all window mutations.
 previous=status()
 if previous not in ('Active','Paused'): return 'No recovery needed.'
 save_status('Recovering')
 try:
  ready();restore_pages()
  if previous=='Active':
   aero('mode','active');save_status('Active');save_pages()
   load('watcher');run('launchctl','kickstart',job('watcher'))
  else:
   aero('mode','main');aero('enable','off');save_status('Paused')
  return 'Recovered live page assignments.'
 except Exception:
  aero('mode','main',check=False);aero('enable','off',check=False);save_status('Paused')
  raise

def main():
 action=sys.argv[1] if len(sys.argv)>1 else 'status'
 with (STATE/'controller.lock').open('w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  if action=='login': print(login())
  elif action=='enable-login': print(login_enabled(True))
  elif action=='disable-login': print(login_enabled(False))
  elif action=='recover': print(recover())
  elif action in ('enter','four','six','new'): print(enter(6 if action=='six' else (4 if action=='four' else 0),add=action=='new'))
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
  elif action=='size':
   if len(sys.argv)<3: raise RuntimeError('Usage: control.py size <small|half|full>')
   print(size_window(sys.argv[2]))
  elif action in ('pause','exit'): print(stop(action=='exit'))
  elif action=='status': print((STATE/'status').read_text() if (STATE/'status').exists() else 'Inactive')
  elif action=='rollback':
   login_enabled(False)
   stop(True)
   (STATE/'menu.enabled').unlink(missing_ok=True)
   run('launchctl','bootout',job('menu'),check=False)
   print('Omac disabled. Agent terminals were not stopped. No global configuration was changed.')
  else: raise RuntimeError('Unknown action')
if __name__=='__main__':
 try: main()
 except Exception as e: print(str(e),file=sys.stderr); sys.exit(1)
