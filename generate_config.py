from pathlib import Path
import plistlib,shlex
r=Path(__file__).resolve().parent
s=Path.home()/'Library/Application Support/AgentControlCenter'
s.mkdir(parents=True,exist_ok=True)
config='''config-version = 2
start-at-login = false
after-startup-command = ['exec-and-forget /opt/homebrew/bin/python3 "CONTROLLER" recover']
default-root-container-layout = 'tiles'
default-root-container-orientation = 'horizontal'
persistent-workspaces = ['1', '2', '3', '4', '5']
[mode.main.binding]
[mode.active.binding]
cmd-1 = 'workspace 1'
cmd-shift-1 = 'move-node-to-workspace 1'
cmd-2 = 'workspace 2'
cmd-shift-2 = 'move-node-to-workspace 2'
cmd-3 = 'workspace 3'
cmd-shift-3 = 'move-node-to-workspace 3'
cmd-4 = 'workspace 4'
cmd-shift-4 = 'move-node-to-workspace 4'
cmd-5 = 'workspace 5'
cmd-shift-5 = 'move-node-to-workspace 5'
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
cmd-k = 'exec-and-forget "/Applications/Omac.app/Contents/MacOS/AgentControlCenter" --guide' 
cmd-o = "exec-and-forget open -g 'agent-control-center://center'"
cmd-t = 'layout floating tiling'
cmd-alt-f = 'macos-native-fullscreen'
alt-tab = 'focus --wrap-around dfs-next'
alt-shift-tab = 'focus --wrap-around dfs-prev'
cmd-b = 'balance-sizes'
cmd-shift-equal = 'balance-sizes'
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
if = 'test %{app-bundle-id} = com.richardholguin.omac.preview'
run = 'layout floating'
'''
(r/'config/aerospace.toml').write_text(config.replace('CONTROLLER',str(r/'control.py')))
env={'PATH':str(Path.home()/'.local/bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'}
app='/Applications/Omac.app/Contents/MacOS/AgentControlCenter'
for name,args,keep in [
 ('watcher',['/opt/homebrew/bin/python3',str(r/'watcher.py')],{'PathState':{str(s/'aerospace.enabled'):True}}),
 ('login',[app,'--login'],False),
 ('menu',[app,'--managed'],{'PathState':{str(s/'menu.enabled'):True}}),
 ('aerospace',['/Applications/AeroSpace.app/Contents/MacOS/AeroSpace','--config-path',str(r/'config/aerospace.toml')],{'PathState':{str(s/'aerospace.enabled'):True}}),
 *[('terminal.'+role.lower(),['/usr/bin/open','-W','-n','-a','/Applications/Ghostty.app','--args','--title=Omac · '+role,'--config-file='+str(r/'config/ghostty.conf'),'--working-directory='+str(Path.home()/'Documents')],False) for role in [str(i) for i in range(1,31)]]]:
 d={'Label':'com.richard.acc.'+name,'ProgramArguments':args,'RunAtLoad':name=='login','KeepAlive':keep,'ThrottleInterval':5,'EnvironmentVariables':env,'StandardOutPath':str(s/(name+'.log')),'StandardErrorPath':str(s/(name+'.error.log'))}
 (r/'launchd'/f'{name}.plist').write_bytes(plistlib.dumps(d))
