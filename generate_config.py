from pathlib import Path
import plistlib,shlex,os,sys,json
sys.dont_write_bytecode=True
from portable_paths import SOURCE as r, STATE as s, RUNTIME, APP as app, PYTHON, AERO, AERO_APP, GHOSTTY_APP
(RUNTIME/'config').mkdir(parents=True,exist_ok=True)
(RUNTIME/'launchd').mkdir(parents=True,exist_ok=True)
s.mkdir(parents=True,exist_ok=True)
config='''config-version = 2
start-at-login = false
after-startup-command = ['exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" recover']
exec-on-workspace-change = ['/Applications/Omac.app/Contents/MacOS/AgentControlCenter', '--shelf-page-changed']
default-root-container-layout = 'tiles'
default-root-container-orientation = 'horizontal'
persistent-workspaces = ['1', '2', '3', '4', '5']
[mode.main.binding]
[mode.active.binding]
ctrl-alt-m = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" mixed-expand'
ctrl-alt-shift-2 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" mixed-2'
ctrl-alt-shift-3 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" mixed-3'
ctrl-alt-shift-r = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" mixed-restore'
ctrl-alt-space = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --shelf-action shelf'
ctrl-alt-shift-space = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --shelf-action shelf-add'
cmd-alt-down = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --shelf-action shelf-tuck'
ctrl-alt-left = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --shelf-action place-left'
ctrl-alt-right = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --shelf-action place-right'
cmd-1 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" switch-page 1'

cmd-shift-1 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" move-focused-page 1'
cmd-2 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" switch-page 2'
cmd-shift-2 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" move-focused-page 2'
cmd-3 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" switch-page 3'
cmd-shift-3 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" move-focused-page 3'
cmd-4 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" switch-page 4'
cmd-shift-4 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" move-focused-page 4'
cmd-5 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" switch-page 5'
cmd-shift-5 = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" move-focused-page 5'
cmd-alt-c = 'exec-and-forget open -a "Claude"'
cmd-alt-h = 'exec-and-forget open -a "Hermes"'
cmd-alt-g = 'exec-and-forget open -b com.openai.codex'
cmd-alt-b = 'exec-and-forget open -a "Google Chrome"'
cmd-alt-e = 'exec-and-forget open -a "Finder"'
cmd-alt-r = 'exec-and-forget open -b com.todesktop.230313mzl4w4u92'
cmd-alt-v = 'exec-and-forget open -b com.microsoft.VSCode'
cmd-alt-t = 'exec-and-forget open -b ru.keepcoder.Telegram'
cmd-alt-i = 'exec-and-forget open -b com.apple.MobileSMS'
cmd-alt-m = 'exec-and-forget open -b com.apple.mail'
cmd-alt-s = 'exec-and-forget open -b com.apple.systempreferences'
cmd-left = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" focus-direction left'
cmd-right = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" focus-direction right'
cmd-up = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" focus-direction up'
cmd-down = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" focus-direction down'
cmd-shift-left = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command swap left'
cmd-shift-right = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command swap right'
cmd-shift-up = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command swap up'
cmd-shift-down = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command swap down'
cmd-minus = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command resize -50'
cmd-equal = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command resize +50'
cmd-f = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command fullscreen'
cmd-k = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --guide' 
cmd-o = "exec-and-forget open -g 'agent-control-center://center'"
cmd-t = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command layout-toggle'
cmd-alt-f = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command native-fullscreen'
alt-tab = "exec-and-forget open -g 'agent-control-center://cycle-next'"
alt-shift-tab = "exec-and-forget open -g 'agent-control-center://cycle-previous'"
cmd-b = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command balance'
cmd-shift-equal = 'exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" tile-command balance'
cmd-esc = "exec-and-forget open -g 'agent-control-center://rescue'"
cmd-shift-esc = "exec-and-forget open -g 'agent-control-center://refocus'"
cmd-alt-enter = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --shelf-action menu'
cmd-enter = "exec-and-forget open -g 'agent-control-center://new'"
ctrl-alt-4 = "exec-and-forget open -g 'agent-control-center://four'"
ctrl-alt-6 = "exec-and-forget open -g 'agent-control-center://six'"
ctrl-alt-esc = "exec-and-forget open -g 'agent-control-center://exit'"
ctrl-alt-p = "exec-and-forget open -g 'agent-control-center://pause'"
[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.right = 8
outer.top = 8
outer.bottom = 8
[[on-window-detected]]
if = 'test %{app-bundle-id} = com.richard.agentcontrolcenter'
run = 'layout floating'
[[on-window-detected]]
if = 'test %{app-bundle-id} = com.apple.systempreferences'
run = 'layout floating'
[[on-window-detected]]
if = 'test %{app-bundle-id} = com.apple.ScreenSharing'
run = 'layout floating'
[[on-window-detected]]
if = 'test %{app-bundle-id} = com.richardholguin.omac.preview'
run = 'layout floating'
'''
lines=config.splitlines()
for i,line in enumerate(lines):
 if line.startswith('after-startup-command ='):
  lines[i]='after-startup-command = ['+json.dumps('exec-and-forget '+shlex.join([PYTHON,str(r/'control.py'),'recover']))+']'
 elif line.startswith('exec-on-workspace-change ='):
  lines[i]='exec-on-workspace-change = '+json.dumps([app,'--shelf-page-changed'])
 elif '"CONTROLLER"' in line:
  key=line.split(' =',1)[0]
  arguments=shlex.split(line.split('"CONTROLLER"',1)[1].rstrip("'").strip())
  lines[i]=key+' = '+json.dumps('exec-and-forget '+shlex.join([PYTHON,str(r/'control.py'),*arguments]))
 elif line.startswith('cmd-alt-') and ('open -a ' in line or 'open -b ' in line):
  app_bundles={'c':'com.anthropic.claudefordesktop','h':'com.nousresearch.hermes.setup','g':'com.openai.codex','b':'com.google.Chrome','e':'com.apple.finder','r':'com.todesktop.230313mzl4w4u92','v':'com.microsoft.VSCode','t':'ru.keepcoder.Telegram','i':'com.apple.MobileSMS','m':'com.apple.mail','s':'com.apple.systempreferences'}
  key=line.split(' =')[0].strip()
  bundle=app_bundles.get(key.removeprefix('cmd-alt-'))
  if bundle: lines[i]=key+' = '+json.dumps("exec-and-forget "+shlex.join([app,"--favorite-key",key.removeprefix("cmd-alt-")]))
 elif line.startswith('cmd-k ='):
  lines[i]='cmd-k = '+json.dumps('exec-and-forget '+shlex.join([app,'--guide']))
 elif line.startswith('cmd-alt-enter ='):
  lines[i]='cmd-alt-enter = '+json.dumps('exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --shelf-action menu')
(RUNTIME/'config/aerospace.toml').write_text('\n'.join(lines)+'\n')
env={'PATH':str(Path.home()/'.local/bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'}
env.update({'PYTHONDONTWRITEBYTECODE':'1','OMAC_APP_EXECUTABLE':app,'OMAC_STATE_ROOT':str(s),'OMAC_AEROSPACE_CLI':AERO})
for name,args,keep in [
 ('watcher',[PYTHON,str(r/'watcher.py')],{'PathState':{str(s/'aerospace.enabled'):True}}),
 ('login',[app,'--login'],False),
 ('menu',[app,'--managed'],{'PathState':{str(s/'menu.enabled'):True}}),
 ('aerospace',[str(Path(AERO_APP)/'Contents/MacOS/AeroSpace'),'--config-path',str(RUNTIME/'config/aerospace.toml')],{'PathState':{str(s/'aerospace.enabled'):True}}),
 *[('terminal.'+role.lower(),['/usr/bin/open','-W','-n','-a',GHOSTTY_APP,'--args','--title=Omac · '+role,'--config-file='+str(r/'config/ghostty.conf'),'--working-directory='+str(Path.home()/'Documents')],False) for role in [str(i) for i in range(1,31)]]]:
 d={'Label':'com.richard.acc.'+name,'ProgramArguments':args,'RunAtLoad':name=='login','KeepAlive':keep,'ThrottleInterval':5,'EnvironmentVariables':env,'StandardOutPath':str(s/(name+'.log')),'StandardErrorPath':str(s/(name+'.error.log'))}
 (RUNTIME/'launchd'/f'{name}.plist').write_bytes(plistlib.dumps(d))
