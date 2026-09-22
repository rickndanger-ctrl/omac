#!/opt/homebrew/bin/python3
"""On-demand controller. No API calls, credentials, or background polling."""
import fcntl,json,math,os,plistlib,subprocess,sys,time
from functools import lru_cache
from pathlib import Path
from portable_paths import SOURCE as ROOT, STATE, RUNTIME, AERO, APP
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

def _mixed_path(): return STATE/'mixed-layout.json'
def _write_mixed(data):
 temp=STATE/'mixed-layout.tmp';temp.write_text(json.dumps(data));temp.replace(_mixed_path())
def _read_mixed():
 try:
  data=json.loads(_mixed_path().read_text())
  return data if isinstance(data,dict) else None
 except (FileNotFoundError,ValueError,OSError): return None
def _native_target(window):
 raw=run(APP,'--window-target',str(window['window-id']),str(window['app-pid']))
 try: target=json.loads(raw)
 except (TypeError,ValueError) as exc: raise RuntimeError('Native window target returned invalid JSON.') from exc
 if target.get('windowID')!=window['window-id'] or target.get('pid')!=window['app-pid']:
  raise RuntimeError('Native window identity changed.')
 for key in ('frame','visibleFrame'):
  values=target.get(key)
  if not isinstance(values,list) or len(values)!=4:
   raise RuntimeError('Native window target returned incomplete geometry.')
  try: values=[float(value) for value in values]
  except (TypeError,ValueError) as exc: raise RuntimeError('Native window target returned invalid geometry.') from exc
  if not all(math.isfinite(value) for value in values) or values[2]<=0 or values[3]<=0:
   raise RuntimeError('Native window target returned invalid geometry.')
  target[key]=values
 return target
def _same_frame(left,right):
 try: return len(left)==4 and len(right)==4 and all(abs(float(a)-float(b))<2 for a,b in zip(left,right))
 except (TypeError,ValueError): return False
def _set_frame(window,frame):
 run(APP,'--window-frame',str(window['window-id']),str(window['app-pid']),*(str(value) for value in frame))
 deadline=time.monotonic()+1.0;matches=0
 while time.monotonic()<deadline:
  actual=_native_target(window)['frame']
  matches=matches+1 if _same_frame(actual,frame) else 0
  if matches>=2:return
  time.sleep(.05)
 raise RuntimeError('Window did not settle at its requested frame.')
def _mixed_frames(visible,count,app_side='left',gap=8):
 x,y,width,height=visible; x+=gap;y+=gap;width-=2*gap;height-=2*gap
 if width<=3*gap or height<=(count+1)*gap: raise RuntimeError('Screen is too small for mixed layout.')
 half=(width-gap)//2;left=[x,y,half,height];right=[x+half+gap,y,width-half-gap,height]
 app,area=(left,right) if app_side=='left' else (right,left)
 each=(area[3]-gap*(count-1))//count;frames=[app]
 top=area[1]
 for index in range(count):
  cell=area[1]+area[3]-top if index==count-1 else each
  frames.append([area[0],top,area[2],cell]);top+=cell+gap
 return frames
def _restore_mixed_members(members):
 errors=[]
 for member in members:
  window={'window-id':member.get('window-id'),'app-pid':member.get('app-pid')}
  try:
   _native_target(window)
   aero('fullscreen','off','--window-id',str(window['window-id']))
   aero('layout','--window-id',str(window['window-id']),'floating')
   _set_frame(window,member['original-frame'])
   aero('layout','--window-id',str(window['window-id']),member['original-layout'])
  except Exception as exc: errors.append(f"{window.get('window-id')}: {exc}")
 return errors
def apply_mixed(count,app_side='left'):
 if count not in (2,3): raise RuntimeError('Mixed layout requires two or three terminals.')
 if _read_mixed(): raise RuntimeError('Restore the current mixed layout before applying another.')
 workspace=aero('list-workspaces','--focused').strip()
 if workspace not in ('1','2','3','4','5'): raise RuntimeError('Focused window is outside an Omac page.')
 focused=json.loads(aero('list-windows','--focused','--format','%{window-id} %{app-pid} %{app-name} %{workspace} %{window-layout}','--json'))
 if not focused: raise RuntimeError('Focus the native app to place first.')
 app=focused[0]
 if app.get('app-name')=='Ghostty' or app.get('workspace')!=workspace:
  raise RuntimeError('Focus a nonterminal app on the current Omac page.')
 terminals=terminal_windows(workspace)[:count]
 if len(terminals)!=count: raise RuntimeError(f'Mixed layout needs {count} managed terminals on this page.')
 selected=[app,*terminals];snapshots=[];visible=None
 for window in selected:
  if window.get('window-layout') not in ('floating','tiling','h_tiles','v_tiles'):
   raise RuntimeError('Mixed layout requires ordinary floating or tiled windows.')
  target=_native_target(window)
  if visible is None: visible=target['visibleFrame']
  elif not _same_frame(target['visibleFrame'],visible): raise RuntimeError('All mixed-layout windows must be on one display.')
  snapshots.append({'window-id':window['window-id'],'app-pid':window['app-pid'],'workspace':workspace,
                    'original-frame':target['frame'],'original-layout':window['window-layout']})
 frames=_mixed_frames(visible,count,app_side);changed=[]
 checkpoint={'boot':boot_session(),'workspace':workspace,'app-side':app_side,
             'state':'applying','members':snapshots}
 _write_mixed(checkpoint)
 try:
  for window,member,frame in zip(selected,snapshots,frames):
   changed.append(member)
   aero('fullscreen','off','--window-id',str(window['window-id']))
   aero('layout','--window-id',str(window['window-id']),'floating')
   _set_frame(window,frame);member['placed-frame']=frame
  checkpoint['state']='active';_write_mixed(checkpoint)
 except Exception as exc:
  errors=_restore_mixed_members(changed)
  if errors:
   checkpoint['state']='recovery-required';checkpoint['rollback-errors']=errors;_write_mixed(checkpoint)
  else:_mixed_path().unlink(missing_ok=True)
  suffix=(' Rollback errors: '+'; '.join(errors)) if errors else ''
  raise RuntimeError(f'Mixed layout failed and rollback was attempted: {exc}.{suffix}') from exc
 aero('focus','--window-id',str(app['window-id']))
 return f'Mixed layout applied to one app and {count} terminals.'
def restore_mixed():
 data=_read_mixed()
 if not data: return 'No mixed layout is active.'
 if data.get('boot')!=boot_session(): raise RuntimeError('Mixed layout belongs to an earlier boot and cannot be restored safely.')
 workspace=data.get('workspace')
 if workspace!=page(): raise RuntimeError('Switch to the mixed layout page before restoring it.')
 live={w['window-id']:w for w in windows()}
 for member in data.get('members',[]):
  current=live.get(member.get('window-id'))
  if not current or current.get('app-pid')!=member.get('app-pid') or current.get('workspace')!=workspace:
   raise RuntimeError('Mixed layout member identity or page changed; restore refused.')
 errors=_restore_mixed_members(data.get('members',[]))
 if errors: raise RuntimeError('Mixed layout restore incomplete: '+'; '.join(errors))
 _mixed_path().unlink(missing_ok=True)
 return 'Mixed layout restored.'
def _center(frame): return frame[0]+frame[2]/2,frame[1]+frame[3]/2
def focus_direction(direction):
 if direction not in ('left','right','up','down'): raise RuntimeError('Direction must be left, right, up, or down.')
 data=_read_mixed();workspace=page()
 if data and data.get('boot')==boot_session() and data.get('workspace')==workspace:
  live={w['window-id']:w for w in windows()};members=[]
  for saved in data.get('members',[]):
   current=live.get(saved.get('window-id'))
   if not current or current.get('app-pid')!=saved.get('app-pid') or current.get('workspace')!=workspace: break
   try: frame=_native_target(current)['frame']
   except RuntimeError: break
   members.append((current,frame))
  else:
   focused=json.loads(aero('list-windows','--focused','--format','%{window-id}','--json'))
   focused_id=focused[0].get('window-id') if focused else None
   current=next(((window,frame) for window,frame in members if window['window-id']==focused_id),None)
   if current:
    fx,fy=_center(current[1]);choices=[]
    for window,frame in members:
     if window['window-id']==focused_id: continue
     cx,cy=_center(frame)
     primary,cross={'left':(fx-cx,abs(fy-cy)),'right':(cx-fx,abs(fy-cy)),
                    'up':(fy-cy,abs(fx-cx)),'down':(cy-fy,abs(fx-cx))}[direction]
     if primary>0: choices.append((cross,primary,window['window-id']))
    if choices:
     target=min(choices)[2];aero('focus','--window-id',str(target));return f'Focused mixed-layout window {target}.'
    return 'No mixed-layout window in that direction.'
 aero('focus','--ignore-floating',direction,check=False)
 return 'Used ordinary tile navigation.'
def mixed_expand_toggle():
 data=_read_mixed()
 if not data: raise RuntimeError('Apply Mixed Layout before expanding a mixed window.')
 if data.get('state')!='active': raise RuntimeError('Restore the incomplete mixed layout before expanding a window.')
 workspace=data.get('workspace')
 if data.get('boot')!=boot_session() or workspace!=page():
  raise RuntimeError('Mixed layout boot or page changed; expand refused.')
 live={w['window-id']:w for w in windows()}
 focused=json.loads(aero('list-windows','--focused','--format','%{window-id} %{app-pid} %{workspace}','--json'))
 if not focused: raise RuntimeError('Focus a mixed-layout window first.')
 row=focused[0];member=next((item for item in data.get('members',[]) if item.get('window-id')==row.get('window-id')),None)
 current=live.get(row.get('window-id'))
 if (not member or not current or current.get('app-pid')!=member.get('app-pid') or
     row.get('app-pid')!=member.get('app-pid') or current.get('workspace')!=workspace or row.get('workspace')!=workspace):
  raise RuntimeError('Focused window is not a valid member of this mixed layout.')
 target=_native_target(current);before=target['frame']
 if member.get('expanded'):
  wanted=member.get('pre-expand-frame')
  if not isinstance(wanted,list) or len(wanted)!=4: raise RuntimeError('Mixed expand restore frame is missing.')
  member['expand-state']='restoring';_write_mixed(data)
  try:_set_frame(current,wanted)
  except Exception as exc:
   try:_set_frame(current,before)
   except Exception as rollback:
    data['state']='recovery-required';data['rollback-errors']=[f"{current['window-id']}: {rollback}"];_write_mixed(data)
    raise RuntimeError(f'Mixed expand restore failed; rollback also failed: {exc}; {rollback}') from exc
   member['expand-state']='expanded';_write_mixed(data)
   raise RuntimeError(f'Mixed expand restore failed; expanded frame was restored: {exc}') from exc
  member.pop('expanded',None);member.pop('pre-expand-frame',None);member.pop('expand-state',None);_write_mixed(data)
  return 'Mixed window restored to its compact frame.'
 visible=target['visibleFrame'];wanted=[visible[0]+8,visible[1]+8,visible[2]-16,visible[3]-16]
 member['pre-expand-frame']=before;member['expand-state']='expanding';_write_mixed(data)
 try:_set_frame(current,wanted)
 except Exception as exc:
  try:_set_frame(current,before)
  except Exception as rollback:
   data['state']='recovery-required';data['rollback-errors']=[f"{current['window-id']}: {rollback}"];_write_mixed(data)
   raise RuntimeError(f'Mixed expand failed; rollback also failed: {exc}; {rollback}') from exc
  member.pop('pre-expand-frame',None);member.pop('expand-state',None);_write_mixed(data)
  raise RuntimeError(f'Mixed expand failed; compact frame was restored: {exc}') from exc
 member['expanded']=True;member['expand-state']='expanded';_write_mixed(data)
 return 'Mixed window expanded to the usable monitor area.'
def tile_command(command,value=None):
 allowed={'swap':('left','right','up','down'),'resize':('-50','+50'),'balance':(None,),
          'layout-toggle':(None,),'fullscreen':(None,),'native-fullscreen':(None,)}
 if command not in allowed or value not in allowed[command]: raise RuntimeError('Unsupported tile command.')
 data=_read_mixed();workspace=page()
 if data and data.get('boot')==boot_session() and data.get('workspace')==workspace:
  raise RuntimeError('Restore Mixed Layout before changing its floating window shapes or tile tree.')
 if command=='swap': aero('swap',value)
 elif command=='resize': aero('resize','smart',value)
 elif command=='balance': aero('balance-sizes','--workspace',workspace)
 elif command=='layout-toggle': aero('layout','floating','tiling')
 elif command=='fullscreen': aero('fullscreen')
 else: aero('macos-native-fullscreen')
 return 'Tile command applied.'

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
  elif action in ('mixed-2','mixed-3'): print(apply_mixed(int(action[-1])))
  elif action=='mixed-restore': print(restore_mixed())
  elif action=='focus-direction':
   if len(sys.argv)<3: raise RuntimeError('Usage: control.py focus-direction <left|right|up|down>')
   print(focus_direction(sys.argv[2]))
  elif action=='mixed-expand': print(mixed_expand_toggle())
  elif action=='tile-command':
   if len(sys.argv)<3: raise RuntimeError('Usage: control.py tile-command <swap|resize|balance> [value]')
   print(tile_command(sys.argv[2],sys.argv[3] if len(sys.argv)>3 else None))
  elif action in ('enter','four','six','new'): print(enter(6 if action=='six' else (4 if action=='four' else 0),add=action=='new'))
  elif action=='center':
   focused=json.loads(aero('list-windows','--focused','--format','%{window-id} %{app-pid} %{workspace} %{window-layout}','--json'))
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
   login_enabled(False)
   stop(True)
   (STATE/'menu.enabled').unlink(missing_ok=True)
   run('launchctl','bootout',job('menu'),check=False)
   print('Omac disabled. Agent terminals were not stopped. No global configuration was changed.')
  else: raise RuntimeError('Unknown action')
if __name__=='__main__':
 try: main()
 except Exception as e: print(str(e),file=sys.stderr); sys.exit(1)
