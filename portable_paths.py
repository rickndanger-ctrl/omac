"""Portable dependency discovery shared by controller and config generation."""
import os,shutil,sys
from pathlib import Path
SOURCE=Path(__file__).resolve().parent
STATE=Path(os.environ.get('OMAC_STATE_ROOT',str(Path.home()/'Library/Application Support/AgentControlCenter')))
RUNTIME=STATE/'runtime'
APP=os.environ.get('OMAC_APP_EXECUTABLE','/Applications/Omac.app/Contents/MacOS/AgentControlCenter')
PYTHON=sys.executable
AERO=os.environ.get('OMAC_AEROSPACE_CLI') or shutil.which('aerospace') or next((str(p) for p in [Path('/opt/homebrew/bin/aerospace'),Path('/usr/local/bin/aerospace')] if p.is_file()),'/opt/homebrew/bin/aerospace')
def application(name):
 return next((str(p) for p in [Path('/Applications')/name,Path.home()/'Applications'/name] if p.is_dir()),str(Path('/Applications')/name))
AERO_APP=application('AeroSpace.app')
GHOSTTY_APP=application('Ghostty.app')
