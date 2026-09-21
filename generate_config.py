from pathlib import Path
import plistlib,shlex
r=Path('outputs/agent-control-center').resolve()
s=Path.home()/'Library/Application Support/AgentControlCenter'
s.mkdir(parents=True,exist_ok=True)
config='''config-version = 2
start-at-login = false
after-startup-command = ['enable off']
default-root-container-layout = 'tiles'
default-root-container-orientation = 'horizontal'
persistent-workspaces = ['Agents', 'Research']
[mode.main.binding]
[mode.active.binding]
ctrl-alt-left = 'focus left'
ctrl-alt-right = 'focus right'
ctrl-alt-up = 'focus up'
ctrl-alt-down = 'focus down'
ctrl-alt-shift-left = 'move left'
ctrl-alt-shift-right = 'move right'
ctrl-alt-shift-up = 'move up'
ctrl-alt-shift-down = 'move down'
ctrl-alt-1 = 'workspace Agents'
ctrl-alt-2 = 'workspace Research'
ctrl-alt-minus = 'resize smart -50'
ctrl-alt-equal = 'resize smart +50'
ctrl-alt-f = 'fullscreen'
ctrl-alt-space = 'layout floating tiling'
ctrl-alt-esc = "exec-and-forget open 'agent-control-center://exit'"
ctrl-alt-p = "exec-and-forget open 'agent-control-center://pause'"
[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.right = 8
outer.top = 8
outer.bottom = 8
[[on-window-detected]]
if = 'true'
run = 'layout floating'
'''
(r/'config/aerospace.toml').write_text(config)
env={'PATH':str(Path.home()/'.local/bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'}
app='/Applications/Agent Control Center.app/Contents/MacOS/AgentControlCenter'
for name,args,keep in [
 ('menu',[app,'--managed'],{'PathState':{str(s/'menu.enabled'):True}}),
 ('aerospace',['/Applications/AeroSpace.app/Contents/MacOS/AeroSpace','--config-path',str(r/'config/aerospace.toml')],{'PathState':{str(s/'aerospace.enabled'):True}}),
 *[('terminal.'+role.lower(),['/usr/bin/open','-W','-n','-a','/Applications/Ghostty.app','--args','--title=ACC · '+role,'--window-save-state=never','--quit-after-last-window-closed=true','--working-directory='+str(Path.home()/'Documents'),'-e','/opt/homebrew/bin/python3',str(r/'terminal.py'),role],False) for role in ['Claude','Codex','Hermes','Local']]]:
 d={'Label':'com.richard.acc.'+name,'ProgramArguments':args,'RunAtLoad':False,'KeepAlive':keep,'ThrottleInterval':5,'EnvironmentVariables':env,'StandardOutPath':str(s/(name+'.log')),'StandardErrorPath':str(s/(name+'.error.log'))}
 (r/'launchd'/f'{name}.plist').write_bytes(plistlib.dumps(d))
