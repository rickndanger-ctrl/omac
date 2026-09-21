#!/opt/homebrew/bin/python3
import os,subprocess,sys
from pathlib import Path
role=sys.argv[1]
root=Path(__file__).resolve().parent
commands={
 'Claude':[str(Path.home()/'.local/bin/claude')],
 'Codex':[str(Path.home()/'.local/bin/codex')],
 'Hermes':[str(Path.home()/'.local/bin/hermes'),'chat'],
 'Local':['/bin/bash',str(Path.home()/'Documents/Local-Model-Mode/Local-Qwen/Local Qwen - Claude Code.command')],
}
os.environ['PATH']=str(Path.home()/'.local/bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
# Do not inherit this Codex task's session identity in a newly opened agent.
for key in ['CODEX_THREAD_ID','CODEX_INTERNAL_ORIGINATOR_OVERRIDE','CLAUDECODE']:
 os.environ.pop(key,None)
os.chdir(Path.home()/'Documents')
print(f'Agent Control Center · {role}\nNormal agent permissions and model settings apply.\n',flush=True)
while True:
 if role=='Local': print('Uses your existing Local Qwen launcher. Full Local mode must already be selected.',flush=True)
 result=subprocess.run(commands[role])
 print(f'\n{role} exited (code {result.returncode}). No automatic restart.',flush=True)
 try: answer=input('Return to restart, or type shell for a normal terminal: ')
 except EOFError: break
 if answer.strip().lower()=='shell': os.execv('/bin/zsh',['zsh','-l'])
