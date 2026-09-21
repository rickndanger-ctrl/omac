"""Experimental whole-page geometry transaction; not a daily shortcut yet."""
import json
import control as c
from tile_modes import Mode, plan_layout, WindowIdentity


def apply_page(mode, selected_id):
    """Reserve space for every window, rolling back frames on any refusal."""
    mode = Mode(mode)
    workspace = c.page()
    rows = [w for w in c.windows() if w.get('workspace') == workspace]
    if not 1 <= len(rows) <= 6:
        raise RuntimeError('Grid preview requires one to six windows on this page.')
    if selected_id not in {w['window-id'] for w in rows}:
        raise RuntimeError('Selected window is not on this page.')
    snapshots = {}
    for row in rows:
        identity = WindowIdentity(row['window-id'], row['app-pid'], c.boot_session())
        target = c._native_target(identity)
        snapshots[str(identity.window_id)] = (row, identity, target)
    monitors = {tuple(v[2]['visibleFrame']) for v in snapshots.values()}
    if len(monitors) != 1:
        raise RuntimeError('Grid preview refuses windows spanning different displays.')
    ids = sorted(snapshots, key=lambda wid: (snapshots[wid][2]['frame'][1], snapshots[wid][2]['frame'][0], int(wid)))
    x, y, width, height = next(iter(monitors))
    plan = plan_layout(ids, str(selected_id), mode, int(width)-16, int(height)-16)
    changed = []
    try:
        for wid in ids:
            row, identity, target = snapshots[wid]
            changed.append(wid)
            c.aero('fullscreen','off','--window-id',wid)
            c.aero('layout','--window-id',wid,'floating')
        for wid, placement in plan.placements.items():
            if placement.occluded:
                continue
            row, identity, target = snapshots[wid]
            r = placement.rect
            wanted = [x+8+r.x,y+8+r.y,r.w,r.h]
            c.run(c.APP,'--window-frame',wid,str(identity.app_pid),*map(str,wanted))
            if not c._same_frame(c._native_target(identity)['frame'], wanted):
                raise RuntimeError('App refused its grid size.')
        c.aero('focus','--window-id',str(selected_id))
    except Exception as error:
        failures = []
        for wid in changed:
            row, identity, target = snapshots[wid]
            try:
                c.run(c.APP,'--window-frame',wid,str(identity.app_pid),*map(str,target['frame']))
                if row['window-layout'] != 'floating':
                    c.aero('layout','--window-id',wid,row['window-layout'])
            except Exception as rollback:
                failures.append(f'{wid}: {rollback}')
        suffix = '; rollback failures: '+ '; '.join(failures) if failures else '; rollback attempted'
        raise RuntimeError(str(error)+suffix) from error
    return snapshots
