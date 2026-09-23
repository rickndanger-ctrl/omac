#!/opt/homebrew/bin/python3
"""On-demand controller. No API calls, credentials, or background polling."""
import fcntl,json,math,os,plistlib,re,subprocess,sys,time
from functools import lru_cache
from pathlib import Path
sys.dont_write_bytecode=True
from portable_paths import SOURCE as ROOT, STATE, RUNTIME, AERO, APP
STATE.mkdir(parents=True,exist_ok=True)
DOMAIN=f'gui/{os.getuid()}'
REMOTE_VIEWER_APP='Screen Sharing'
REMOTE_VIEWER_BUNDLE='com.apple.ScreenSharing'
REMOTE_WORKSPACE='Omac-Remote'
ROLES=[str(i) for i in range(1,31)]

def run(*args,check=True):
 p=subprocess.run([str(a) for a in args],capture_output=True,text=True,timeout=30)
 if check and p.returncode: raise RuntimeError((p.stderr or p.stdout).strip() or str(args))
 return p.stdout.strip()
def aero(*args,check=True): return run(AERO,*args,check=check)
def job(name): return DOMAIN+'/com.richard.acc.'+name
def job_running(name):
 p=subprocess.run(['launchctl','print',job(name)],capture_output=True,text=True)
 return p.returncode==0 and 'state = running' in p.stdout

def load(name):
 p=subprocess.run(['launchctl','print',job(name)],capture_output=True)
 if name.startswith('terminal.') and p.returncode==0 and b'--config-file=' not in p.stdout:
  # Reload only when creating a missing terminal; preserve already-open Ghostty windows.
  run('launchctl','bootout',job(name),check=False)
  p.returncode=1
 if p.returncode: run('launchctl','bootstrap',DOMAIN,RUNTIME/'launchd'/f'{name}.plist')

def windows():
 return json.loads(aero('list-windows','--all','--format','%{window-id} %{app-pid} %{app-name} %{app-bundle-id} %{window-title} %{workspace} %{window-layout}','--json'))
def is_remote_viewer(window):
 return window.get('app-bundle-id')==REMOTE_VIEWER_BUNDLE or window.get('app-name')==REMOTE_VIEWER_APP
def page():
 value=aero('list-workspaces','--focused').strip()
 return value if value in ('1','2','3','4','5') else '1'
@lru_cache(maxsize=1)
def boot_session(): return run('/usr/sbin/sysctl','-n','kern.boottime')
def status():
 try: return (STATE/'status').read_text()
 except FileNotFoundError: return 'Inactive'
def save_pages():
 # Screen Sharing is an opt-in handoff surface, not an Omac page window. If it
 # is recorded here, recovery can move/layout it while restoring an empty page.
 current=[w for w in windows() if not is_remote_viewer(w)]
 path=STATE/'pages.json'
 # AeroSpace temporarily reports an empty inventory while displays reconnect or
 # macOS hides/minimizes every window. Keep the last useful page assignment so
 # recovery and Command-Escape still have something authoritative to restore.
 if not current and path.exists():
  try:
   previous=json.loads(path.read_text())
   if isinstance(previous,dict) and previous.get('boot')==boot_session() and isinstance(previous.get('windows'),list):
    # A pre-viewer-fix snapshot may contain only Screen Sharing. It is not a
    # useful page map and must not keep repopulating an otherwise empty page.
    managed=[w for w in previous.get('windows',[]) if isinstance(w,dict) and not is_remote_viewer(w)]
    if managed:
     if len(managed)!=len(previous.get('windows',[])):
      previous=dict(previous);previous['windows']=managed
      temp=path.with_suffix('.tmp');temp.write_text(json.dumps(previous));temp.replace(path)
     return False
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
 warnings=[]
 for w in data['windows']:
  if not isinstance(w,dict) or not isinstance(w.get('window-id'),int): continue
  if is_remote_viewer(w): continue
  current=live.get(w['window-id'])
  if not current or current.get('app-pid')!=w.get('app-pid'): continue
  target=w.get('workspace')
  if target not in ('1','2','3','4','5'): continue
  # macOS can expose a hidden/fullscreen app as a non-tiling window during
  # restart. AeroSpace rejects both moving it and applying a tile layout.
  current_layout=current.get('window-layout')
  if current_layout in ('macos_native_window_of_hidden_app','macos_fullscreen'): continue
  if current.get('workspace')!=target:
   try: aero('move-node-to-workspace','--window-id',str(w['window-id']),target)
   except RuntimeError as exc:
    warnings.append(f"Window {w['window-id']} could not return to page {target}: {exc}")
    continue
  recorded=w.get('window-layout')
  desired='floating' if recorded=='floating' and current_layout!='floating' else (
   'tiling' if recorded in ('h_tiles','v_tiles','tiles','tiling') and current_layout=='floating' else None)
  if desired:
   try: aero('layout','--window-id',str(w['window-id']),desired)
   except RuntimeError as exc: warnings.append(f"Window {w['window-id']} layout was left as-is: {exc}")
 if warnings: (STATE/'recovery-warnings.log').write_text('\n'.join(warnings)+'\n')
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
def _mixed_frames(visible,count,app_side='left',gap=8,app_width='1/2'):
 x,y,width,height=visible; x+=gap;y+=gap;width-=2*gap;height-=2*gap
 if width<=3*gap or height<=(count+1)*gap: raise RuntimeError('Screen is too small for mixed layout.')
 fractions={'1/3':(1,3),'1/2':(1,2),'2/3':(2,3)}
 if app_width not in fractions: raise RuntimeError('Mixed app width must be 1/3, 1/2, or 2/3.')
 numerator,denominator=fractions[app_width];usable=width-gap;app_width_points=usable*numerator//denominator
 terminal_width=usable-app_width_points
 if app_side=='left': app=[x,y,app_width_points,height];area=[x+app_width_points+gap,y,terminal_width,height]
 else: area=[x,y,terminal_width,height];app=[x+terminal_width+gap,y,app_width_points,height]
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
   if member['original-layout'] in ('h_tiles','v_tiles'):
    aero('layout','--window-id',str(window['window-id']),'tiling')
   aero('layout','--window-id',str(window['window-id']),member['original-layout'])
  except Exception as exc: errors.append(f"{window.get('window-id')}: {exc}")
 return errors
def _validate_mixed_members(data):
 if data.get('boot')!=boot_session(): raise RuntimeError('Mixed layout belongs to an earlier boot and cannot be restored safely.')
 workspace=data.get('workspace');live={w['window-id']:w for w in windows()}
 for member in data.get('members',[]):
  current=live.get(member.get('window-id'))
  if not current or current.get('app-pid')!=member.get('app-pid') or current.get('workspace')!=workspace:
   raise RuntimeError('Mixed layout member identity or page changed; restore refused.')
 return workspace
def _verify_restored_members(members,workspace):
 live={w['window-id']:w for w in windows()};errors=[]
 for member in members:
  current=live.get(member.get('window-id'));original=member.get('original-layout')
  if not current or current.get('app-pid')!=member.get('app-pid') or current.get('workspace')!=workspace:
   errors.append(f"{member.get('window-id')}: identity or page changed after restore");continue
  actual=current.get('window-layout')
  valid=actual==original or (original=='tiling' and actual in ('h_tiles','v_tiles'))
  if not valid: errors.append(f"{member.get('window-id')}: layout is {actual}, expected {original}");continue
  if original=='floating':
   try:
    frame=_native_target(current)['frame']
    if not _same_frame(frame,member.get('original-frame')): errors.append(f"{member.get('window-id')}: floating frame did not restore")
   except Exception as exc: errors.append(f"{member.get('window-id')}: frame verification failed: {exc}")
 return errors
def _restore_mixed_data(data):
 workspace=_validate_mixed_members(data);members=data.get('members',[])
 errors=_restore_mixed_members(members)
 if not errors: errors=_verify_restored_members(members,workspace)
 if errors:
  data['state']='recovery-required';data['rollback-errors']=errors;_write_mixed(data)
  raise RuntimeError('Mixed layout restore incomplete: '+'; '.join(errors))
 _mixed_path().unlink(missing_ok=True)
 return workspace
def apply_mixed(count,app_side='left',app_width='1/2',selected_identity=None):
 if count not in (2,3): raise RuntimeError('Mixed layout requires two or three terminals.')
 if _read_mixed(): raise RuntimeError('Restore the current mixed layout before applying another.')
 workspace=aero('list-workspaces','--focused').strip()
 if workspace not in ('1','2','3','4','5'): raise RuntimeError('Focused window is outside an Omac page.')
 if selected_identity:
  wanted_id,wanted_pid=selected_identity
  matches=[row for row in windows() if row.get('window-id')==wanted_id and row.get('app-pid')==wanted_pid and row.get('workspace')==workspace]
  if len(matches)!=1: raise RuntimeError('The app selected before opening the Omac menu is no longer available on this page.')
  app=matches[0]
 else:
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
 frames=_mixed_frames(visible,count,app_side,app_width=app_width);changed=[]
 checkpoint={'boot':boot_session(),'workspace':workspace,'app-side':app_side,
             'app-width':app_width,'state':'applying','members':snapshots}
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
 return f'Mixed layout applied with the app at {app_width} width and {count} terminals.'
def restore_mixed():
 data=_read_mixed()
 if not data: return 'No mixed layout is active.'
 workspace=data.get('workspace')
 if workspace!=page(): raise RuntimeError('Switch to the mixed layout page before restoring it.')
 _restore_mixed_data(data)
 return 'Mixed layout restored.'
def switch_page(target):
 if target not in ('1','2','3','4','5'): raise RuntimeError('Page must be 1 through 5.')
 current=aero('list-workspaces','--focused').strip();data=_read_mixed()
 if data and target!=current:
  if data.get('workspace')!=current:
   if target!=data.get('workspace'): raise RuntimeError(f"Mixed layout is still recorded on page {data.get('workspace')}. Return there and restore it before switching pages.")
  else:_restore_mixed_data(data)
 # Clear both the departing remote-control page and any stale destination.
 # Otherwise an empty page can focus the parked viewer on activation.
 if target!=current:
  evacuate_page_remote_viewers()
 aero('workspace',target)
 return f'Switched to page {target}.'

def evacuate_page_remote_viewers():
 for window in windows():
  if is_remote_viewer(window) and window.get('workspace') in ('1','2','3','4','5'):
   aero('move-node-to-workspace','--window-id',str(window['window-id']),REMOTE_WORKSPACE)

def evacuate_remote_viewers(workspace):
 """Keep Screen Sharing out of Omac's five page tile trees.

 The workspace-wide layout commands used by ``arrange`` operate on every
 node in the workspace, even when the caller's tile list excludes the viewer.
 Move remote viewers first so an already-tiled viewer cannot be reintroduced
 into an otherwise local page during a page switch or re-arrange.
 """
 for window in windows():
  if is_remote_viewer(window) and window.get('workspace')==workspace:
   aero('move-node-to-workspace','--window-id',str(window['window-id']),REMOTE_WORKSPACE)
def move_focused_to_page(target):
 if target not in ('1','2','3','4','5'): raise RuntimeError('Page must be 1 through 5.')
 focused=json.loads(aero('list-windows','--focused','--format','%{window-id} %{app-pid} %{workspace}','--json'))
 if not focused: raise RuntimeError('Focus a window first.')
 window=focused[0];data=_read_mixed()
 if target==window.get('workspace'):return f'Focused window is already on page {target}.'
 if data:
  member=next((item for item in data.get('members',[]) if item.get('window-id')==window.get('window-id') and item.get('app-pid')==window.get('app-pid')),None)
  if member:
   if window.get('workspace')!=data.get('workspace'): raise RuntimeError('Mixed window already left its recorded page; move refused.')
   _restore_mixed_data(data)
 aero('move-node-to-workspace','--window-id',str(window['window-id']),target)
 return f'Moved focused window to page {target}.'
def prepare_mixed_tuck(window_id,app_pid):
 data=_read_mixed()
 if not data:return 'Window is not part of an active mixed layout.'
 member=next((item for item in data.get('members',[]) if item.get('window-id')==window_id and item.get('app-pid')==app_pid),None)
 if not member:return 'Window is not part of the active mixed layout.'
 current=aero('list-workspaces','--focused').strip()
 if current!=data.get('workspace'):
  raise RuntimeError(f"Mixed layout is recorded on page {data.get('workspace')}. Return there and restore it before tucking this app.")
 _restore_mixed_data(data)
 return 'Mixed layout restored before tucking its app window.'
def _center(frame): return frame[0]+frame[2]/2,frame[1]+frame[3]/2
def center_or_enlarge(window_id,app_pid,layout):
 if layout=='floating':
  run(APP,'--center',str(app_pid))
  aero('focus','--window-id',str(window_id))
  return 'Floating window centered without changing the tile grid.'
 aero('fullscreen','--window-id',str(window_id))
 aero('focus','--window-id',str(window_id))
 return 'Tile enlarged or restored without leaving the tile grid.'
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
def mixed_expand_toggle(selected_identity=None):
 data=_read_mixed()
 if not data: raise RuntimeError('Apply Mixed Layout before expanding a mixed window.')
 if data.get('state')!='active': raise RuntimeError('Restore the incomplete mixed layout before expanding a window.')
 workspace=data.get('workspace')
 if data.get('boot')!=boot_session() or workspace!=page():
  raise RuntimeError('Mixed layout boot or page changed; expand refused.')
 live={w['window-id']:w for w in windows()}
 if selected_identity:
  wanted_id,wanted_pid=selected_identity;row=live.get(wanted_id)
  if not row or row.get('app-pid')!=wanted_pid: raise RuntimeError('The mixed tile selected before opening the Omac menu is no longer available.')
 else:
  focused=json.loads(aero('list-windows','--focused','--format','%{window-id} %{app-pid} %{workspace}','--json'))
  if not focused: raise RuntimeError('Focus a mixed-layout window first.')
  row=focused[0]
 member=next((item for item in data.get('members',[]) if item.get('window-id')==row.get('window-id')),None)
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
 elif command=='balance': arrange(workspace)
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

def add_window_to_existing_terminal(current, workspace):
 # A fresh Ghostty process briefly activates its last-used workspace before
 # AeroSpace can move the new window. File > New Window in a process already
 # on this page creates the window directly here instead.
 target=current[-1]
 before={w['window-id'] for w in windows()}
 pid=int(target['app-pid'])
 script=(f'tell application "System Events"\n'
         f' tell (first process whose unix id is {pid})\n'
         ' click menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1\n'
         ' end tell\nend tell')
 run('osascript','-e',script)
 added=[]
 for _ in range(40):
  added=[w for w in windows() if w['window-id'] not in before and w.get('app-pid')==pid]
  if added: break
  time.sleep(.1)
 if not added: raise RuntimeError('Ghostty did not create a window on this page.')
 new=added[-1]
 wid=str(new['window-id'])
 if new.get('workspace')!=workspace: aero('move-node-to-workspace','--window-id',wid,workspace)
 aero('layout','--window-id',wid,'tiling')
 aero('focus','--window-id',wid)
 return len(terminal_windows(workspace))
def running_terminal_source():
 # launchctl reports the PID of /usr/bin/open, not its reparented Ghostty app.
 # Resolve the actual app PID from the executable and this controller's config.
 result=subprocess.run(['/bin/ps','-ww','-axo','pid=,command='],capture_output=True,text=True)
 flag='--config-file='+str(ROOT/'config/ghostty.conf')
 for line in result.stdout.splitlines():
  match=re.match(r'\s*(\d+)\s+(\S+)(?:\s|$)',line)
  if match and match.group(2).endswith('/ghostty') and flag in line and re.search(r'--title=(?:ACC|Omac) · (?:[1-9]|[12][0-9]|30)(?:\s|$)',line):
   return [{'app-pid':int(match.group(1))}]
 return []

def arrange(workspace=None):
 workspace=workspace or page()
 evacuate_remote_viewers(workspace)
 terminal_count=len(terminal_windows(workspace))
 # Include native apps in the same tile tree. Pair adjacent windows into
 # rectangular tiles instead of letting each new app become a tall column.
 tiles=[w for w in windows() if w.get('workspace')==workspace
        and w.get('window-layout') in ('h_tiles','v_tiles','tiling')
        and not is_remote_viewer(w)]
 if not tiles: return terminal_count
 ids=[str(w['window-id']) for w in tiles]
 focused=aero('list-windows','--focused','--format','%{window-id}',check=False)
 target=focused if focused in ids else ids[0]
 # One request avoids repainting between dozens of individual CLI invocations.
 commands=[]
 for wid in ids:
  commands.extend([f'fullscreen off --window-id {wid}',
                   f'layout --window-id {wid} tiling'])
 commands.extend([f'workspace {workspace}',f'focus --window-id {ids[0]}',
                  'flatten-workspace-tree',f'layout --workspace {workspace} --root h_tiles'])
 aero('eval','; '.join(commands))
 # Query the actual tree order after flattening; title order need not match it.
 ordered=[]
 # DFS also counts floating windows, including the parked remote viewer.
 for index in range(len(windows())):
  aero('focus','--dfs-index',str(index),check=False)
  wid=aero('list-windows','--focused','--format','%{window-id}',check=False)
  if wid in ids and wid not in ordered: ordered.append(wid)
 if len(ordered)>2:
  for i in range(0,len(ordered)-1,2):
   aero('join-with','--window-id',ordered[i],'right')
 aero('balance-sizes','--workspace',workspace)
 aero('focus','--window-id',target)
 return terminal_count

def start_services():
 load('watcher');run('launchctl','kickstart',job('watcher'))
 run(APP,'--apply-wallpaper',check=False)

def omac_config(path,expected=None):
 expected=expected or RUNTIME/'config/aerospace.toml'
 if path==str(expected): return True
 if not path or status()!='Active' or not (STATE/'aerospace.enabled').exists(): return False
 try: text=Path(path).read_text()
 except (OSError,ValueError): return False
 markers=("persistent-workspaces = ['1', '2', '3', '4', '5']",'[mode.active.binding]','control.py','recover')
 return all(marker in text for marker in markers)

def enter(count=0,add=False):
 origin=page() if add else None
 existing=aero('config','--config-path',check=False)
 if existing and not omac_config(existing):
  raise RuntimeError('Another AeroSpace configuration is active. Exit it before entering Omac.')
 active=omac_config(existing) and status()=='Active'
 if not active:
  run(APP,'--snapshot')
  (STATE/'aerospace.enabled').touch()
  load('aerospace')
  run('launchctl','kickstart',job('aerospace'))
 try:
  if not active: ready()
  if not omac_config(aero('config','--config-path')):
   raise RuntimeError('A different AeroSpace instance is running.')
  if not active:
   aero('reload-config')
   aero('enable','on')
   aero('mode','active')
  # A disengaged AeroSpace server can still answer with Omac's config path.
  # Restore the saved page map whenever Omac is re-entering, not only when the
  # server was completely absent before startup.
  if not active: restore_pages()
  migrate_pages()
  workspace=origin or page()
  current=terminal_windows(workspace)
  if add: count=min(6,len(current)+1)
  if add and active and len(current)<6:
   # A window in another workspace can also create a new window on the
   # currently focused page without switching to its own page.
   source=current or terminal_windows() or running_terminal_source()
   if source:
    total=add_window_to_existing_terminal(source,workspace)
    arrange(workspace)
    save_pages()
    return f'{total} plain terminal windows tiled. No agents launched.'
  present={w['window-title'] for w in terminal_windows()}
  needed=max(0,count-len(current))
  expected=set(present)
  for role in ROLES:
   if not needed: break
   title='ACC · '+role
   if title in present: continue
   label='terminal.'+role; load(label)
   # A supervised Ghostty process can exist before AeroSpace sees its window.
   # Do not restart that process and risk ending an untracked shell session.
   if job_running(label): continue
   run('launchctl','kickstart','-k',job(label),check=False)
   expected.add(title); needed-=1
  if needed: raise RuntimeError('No idle terminal launch jobs are available.')
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
    # AeroSpace already tiles the inserted window. Rebuilding the whole tree
    # can expose another workspace and disturbs the user's native-app layout.
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
  if not active: start_services()
  return f'{total} plain terminal windows tiled. No agents launched.'
 except Exception:
  if not (add and active): stop(True)
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
 selected_identity=None
 if '--window-id' in sys.argv or '--app-pid' in sys.argv:
  try:selected_identity=(int(sys.argv[sys.argv.index('--window-id')+1]),int(sys.argv[sys.argv.index('--app-pid')+1]))
  except (ValueError,IndexError) as exc: raise RuntimeError('Both a valid window ID and app PID are required.') from exc
 with (STATE/'controller.lock').open('w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  if action=='login': print(login())
  elif action=='enable-login': print(login_enabled(True))
  elif action=='disable-login': print(login_enabled(False))
  elif action=='recover': print(recover())
  elif action in ('mixed-2','mixed-3'): print(apply_mixed(int(action[-1]),selected_identity=selected_identity))
  elif action.startswith('mixed-') and action.endswith(('third','half','two-thirds')):
   parts=action.split('-',2)
   if len(parts)<3 or parts[1] not in ('2','3'): raise RuntimeError('Unknown mixed layout action.')
   widths={'third':'1/3','half':'1/2','two-thirds':'2/3'}
   print(apply_mixed(int(parts[1]),app_width=widths[parts[2]],selected_identity=selected_identity))
  elif action=='mixed-restore': print(restore_mixed())
  elif action=='switch-page':
   if len(sys.argv)<3: raise RuntimeError('switch-page requires a page number.')
   print(switch_page(sys.argv[2]))
  elif action=='move-focused-page':
   if len(sys.argv)<3: raise RuntimeError('move-focused-page requires a page number.')
   print(move_focused_to_page(sys.argv[2]))
  elif action=='prepare-mixed-tuck':
   if not selected_identity: raise RuntimeError('prepare-mixed-tuck requires an exact window ID and app PID.')
   print(prepare_mixed_tuck(*selected_identity))
  elif action=='focus-direction':
   if len(sys.argv)<3: raise RuntimeError('Usage: control.py focus-direction <left|right|up|down>')
   print(focus_direction(sys.argv[2]))
  elif action=='mixed-expand': print(mixed_expand_toggle(selected_identity=selected_identity))
  elif action=='tile-command':
   if len(sys.argv)<3: raise RuntimeError('Usage: control.py tile-command <swap|resize|balance> [value]')
   print(tile_command(sys.argv[2],sys.argv[3] if len(sys.argv)>3 else None))
  elif action in ('enter','four','six','new'): print(enter(6 if action=='six' else (4 if action=='four' else 0),add=action=='new'))
  elif action=='center':
   focused=json.loads(aero('list-windows','--focused','--format','%{window-id} %{app-pid} %{workspace} %{window-layout}','--json'))
   if not focused: raise RuntimeError('Focus a window first.')
   window=focused[0]
   print(center_or_enlarge(window['window-id'],window['app-pid'],window['window-layout']))
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
