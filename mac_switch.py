"""Opt-in Screen Sharing handoff for Omac's generated AeroSpace config."""
import json
import subprocess
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
from portable_paths import AERO, STATE

CONFIG = STATE / 'remote-control.json'
RETURN_STATE = STATE / 'mac-switch-window.json'
VIEWER_BUNDLE = 'com.apple.ScreenSharing'
REMOTE_WORKSPACE = 'Omac-Remote'
EXCLUDED_LAYOUTS = {'floating', 'macos_native_window_of_hidden_app', 'macos_fullscreen'}
WINDOW_FORMAT = '%{window-id} %{app-pid} %{app-bundle-id} %{workspace} %{window-layout}'
PAGES = {'1', '2', '3', '4', '5'}


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True,
                          text=True, timeout=8).stdout.strip()


def best_effort(*args):
    try:
        return run(*args)
    except (OSError, subprocess.SubprocessError):
        return ''


def config():
    try:
        value = json.loads(CONFIG.read_text())
    except (FileNotFoundError, OSError, ValueError) as exc:
        raise RuntimeError('Remote control is not configured.') from exc
    if not isinstance(value, dict):
        raise RuntimeError('Remote control is disabled or has an invalid configuration.')
    connection = value.get('connectionPath')
    if value.get('version') != 1 or value.get('enabled') is not True or not isinstance(connection, str):
        raise RuntimeError('Remote control is disabled or has an invalid configuration.')
    saved = Path(connection).expanduser()
    if not saved.is_file():
        raise RuntimeError('Configured Screen Sharing connection is missing.')
    return saved


def rows(*scope):
    try:
        raw = run(AERO, 'list-windows', *scope, '--format', WINDOW_FORMAT, '--json')
    except subprocess.CalledProcessError as exc:
        if '--focused' in scope and 'No window is focused' in (exc.stderr or ''):
            return []
        raise
    value = json.loads(raw)
    return value if isinstance(value, list) else []


def current_page():
    value = run(AERO, 'list-workspaces', '--focused')
    return value if value in PAGES else '1'


def visible_viewer():
    candidates = [row for row in rows('--all') if row.get('app-bundle-id') == VIEWER_BUNDLE]
    return next((row for row in candidates
                 if row.get('window-layout') != 'macos_native_window_of_hidden_app'), None)


def remember_return_target(page):
    focused = rows('--focused')
    target = next((row for row in focused if eligible_local(row)), None)
    data = {'page': page}
    if target:
        data.update({'window-id': target.get('window-id'), 'app-pid': target.get('app-pid')})
    STATE.mkdir(parents=True, exist_ok=True)
    temp = RETURN_STATE.with_suffix('.tmp')
    temp.write_text(json.dumps(data))
    temp.replace(RETURN_STATE)


def focused_local():
    return next((row for row in rows('--focused') if eligible_local(row)), None)


def remembered_return_target():
    try:
        value = json.loads(RETURN_STATE.read_text())
    except (FileNotFoundError, OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def wait_for_viewer():
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        viewer = visible_viewer()
        if viewer:
            return viewer
        time.sleep(.1)
    raise RuntimeError('The Screen Sharing window did not appear.')


PARK_SCRIPT = '''tell application "System Events" to tell process "Screen Sharing"
    repeat with w in windows
        try
            if (value of attribute "AXMinimized" of w) is false and (value of attribute "AXModal" of w) is false then
                set size of w to {300, 221}
                set position of w to {10000, 10000}
            end if
        end try
    end repeat
end tell'''


def park_remote_viewer():
    time.sleep(.2)
    best_effort('/usr/bin/osascript', '-e', PARK_SCRIPT)


def ensure_remote_control():
    run('/usr/bin/osascript', '-e',
        'tell application "System Events" to tell process "Screen Sharing" to '
        'if exists menu item "Switch to Control Mode" of menu "View" of menu bar 1 then '
        'click menu item "Switch to Control Mode" of menu "View" of menu bar 1')


def eligible_local(row):
    return (row.get('app-bundle-id') != VIEWER_BUNDLE and
            row.get('window-layout') not in EXCLUDED_LAYOUTS)


def enter_remote():
    saved = config()
    viewer = visible_viewer()
    origin = focused_local()
    # Capture a local origin even if a viewer already exists behind it. Repeated
    # Enter while the viewer is focused preserves the prior return identity.
    if origin or not any(row.get('app-bundle-id') == VIEWER_BUNDLE for row in rows('--focused')):
        remember_return_target(current_page())
    if viewer is None:
        run('/usr/bin/open', str(saved))
        viewer = wait_for_viewer()
    destination = current_page()
    window_id = str(viewer['window-id'])
    if viewer.get('workspace') != destination:
        run(AERO, 'move-node-to-workspace', '--window-id', window_id, destination)
    best_effort(AERO, 'layout', '--window-id', window_id, 'floating')
    best_effort(AERO, 'workspace', destination)
    run(AERO, 'focus', '--window-id', window_id)
    ensure_remote_control()
    park_remote_viewer()


def leave_remote():
    target = remembered_return_target()
    page = target.get('page') if target.get('page') in PAGES else current_page()
    viewer = visible_viewer()
    best_effort('/usr/bin/osascript', '-e',
                'tell application "System Events" to set visible of process "Screen Sharing" to false')
    park_error = None
    if viewer and viewer.get('workspace') != REMOTE_WORKSPACE:
        try:
            run(AERO, 'move-node-to-workspace', '--window-id', str(viewer['window-id']), REMOTE_WORKSPACE)
        except (OSError, subprocess.SubprocessError) as exc:
            park_error = exc
    best_effort(AERO, 'workspace', page)
    live = rows('--workspace', page)
    exact = next((row for row in live if row.get('window-id') == target.get('window-id') and
                  row.get('app-pid') == target.get('app-pid') and eligible_local(row)), None)
    chosen = exact or next((row for row in live if eligible_local(row)), None)
    if chosen:
        run(AERO, 'focus', '--window-id', str(chosen['window-id']))
    # Do not reuse a stale process/window identity after a completed return.
    RETURN_STATE.unlink(missing_ok=True)
    if park_error:
        raise RuntimeError('Screen Sharing returned locally but its viewer could not leave the Omac pages.') from park_error


def main(choice):
    if choice == 'remote':
        enter_remote()
    elif choice == 'local':
        leave_remote()
    else:
        raise ValueError('Choose local or remote.')


if __name__ == '__main__':
    try:
        main(sys.argv[1] if len(sys.argv) == 2 else '')
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
