from pathlib import Path
import plistlib,shlex
r=Path(__file__).resolve().parent
s=Path.home()/'Library/Application Support/AgentControlCenter'
s.mkdir(parents=True,exist_ok=True)
config='''config-version = 2
start-at-login = false
after-startup-command = []
default-root-container-layout = 'tiles'
default-root-container-orientation = 'horizontal'
persistent-workspaces = ['Terminals']
[mode.main.binding]
[mode.active.binding]
cmd-left = 'focus --ignore-floating left'
cmd-right = 'focus --ignore-floating right'
cmd-up = 'focus --ignore-floating up'
cmd-down = 'focus --ignore-floating down'
cmd-shift-left = 'swap left'
cmd-shift-right = 'swap right'
cmd-shift-up = 'swap up'
cmd-shift-down = 'swap down'
cmd-minus = 'resize smart -50'
cmd-equal = 'resize smart +50'
cmd-f = 'fullscreen'
cmd-k = "exec-and-forget open 'agent-control-center://guide'"
cmd-o = "exec-and-forget open 'agent-control-center://center'"
cmd-t = 'layout floating tiling'
cmd-alt-f = 'macos-native-fullscreen'
alt-tab = 'focus --wrap-around dfs-next'
alt-shift-tab = 'focus --wrap-around dfs-prev'
cmd-shift-equal = 'balance-sizes'
cmd-enter = "exec-and-forget open 'agent-control-center://new'"
ctrl-alt-4 = "exec-and-forget open 'agent-control-center://four'"
ctrl-alt-6 = "exec-and-forget open 'agent-control-center://six'"
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
 *[('terminal.'+role.lower(),['/usr/bin/open','-W','-n','-a','/Applications/Ghostty.app','--args','--title=ACC · '+role,'--config-file='+str(r/'config/ghostty.conf'),'--working-directory='+str(Path.home()/'Documents')],False) for role in [str(i) for i in range(1,7)]]]:
 d={'Label':'com.richard.acc.'+name,'ProgramArguments':args,'RunAtLoad':False,'KeepAlive':keep,'ThrottleInterval':5,'EnvironmentVariables':env,'StandardOutPath':str(s/(name+'.log')),'StandardErrorPath':str(s/(name+'.error.log'))}
 (r/'launchd'/f'{name}.plist').write_bytes(plistlib.dumps(d))
