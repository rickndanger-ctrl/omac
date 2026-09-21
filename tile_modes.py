from dataclasses import dataclass
from enum import Enum
from math import ceil
from typing import Dict, Optional, Sequence


class Mode(str, Enum):
    SMALL = "small"
    HALF = "half"
    FULL = "full"
class LayoutError(ValueError):
    pass
@dataclass(frozen=True)
class Rect:
    x: int
    y: int
    w: int
    h: int
@dataclass(frozen=True)
class Placement:
    rect: Optional[Rect]
    occluded: bool = False
@dataclass
class LayoutPlan:
    placements: Dict[str, Placement]

    def overlaps(self):
        visible = [(key, value.rect) for key, value in self.placements.items()
                   if value.rect is not None and not value.occluded]
        result = []
        for index, (left_key, left) in enumerate(visible):
            for right_key, right in visible[index + 1:]:
                if (left.x < right.x + right.w and right.x < left.x + left.w and
                        left.y < right.y + right.h and right.y < left.y + left.h):
                    result.append((left_key, right_key))
        return result
def _grid_rects(width, height, count, gap, columns, min_rows=1):
    rows = max(min_rows, ceil(count / columns))
    cell_w = (width - gap * (columns - 1)) // columns
    cell_h = (height - gap * (rows - 1)) // rows
    if cell_w < 1 or cell_h < 1:
        raise LayoutError("available rect cannot fit positive-size tiles with this gap")
    return [Rect((index % columns) * (cell_w + gap),
                 (index // columns) * (cell_h + gap), cell_w, cell_h)
            for index in range(count)]


def plan_layout(window_ids: Sequence[str], selected_id: str, mode: Mode,
                width: int, height: int, gap: int = 8) -> LayoutPlan:
    ids = list(window_ids)
    if not ids or len(set(ids)) != len(ids) or selected_id not in ids:
        raise LayoutError("selection must identify one unique window")
    if width <= 0 or height <= 0 or gap < 0 or gap >= width or gap >= height:
        raise LayoutError("available rect and gap must be valid")
    try:
        mode = Mode(mode)
    except (TypeError, ValueError) as exc:
        raise LayoutError("unsupported layout mode") from exc

    if mode is Mode.SMALL:
        rects = _grid_rects(width, height, len(ids), gap, 2, min_rows=2)
        return LayoutPlan(dict(zip(ids, (Placement(rect) for rect in rects))))

    half_w = (width - gap) // 2
    if mode is Mode.HALF:
        other = [window_id for window_id in ids if window_id != selected_id]
        selected = Rect(0, 0, half_w, height)
        right_rects = _grid_rects(half_w, height, len(other), gap, 1)
        placements = {selected_id: Placement(selected)}
        placements.update(dict(zip(other, (Placement(Rect(rect.x + half_w + gap,
                                                           rect.y, rect.w, rect.h))
                                           for rect in right_rects))))
        return LayoutPlan({window_id: placements[window_id] for window_id in ids})

    return LayoutPlan({window_id: Placement(Rect(0, 0, width, height), False)
                       if window_id == selected_id else Placement(None, True)
                       for window_id in ids})


@dataclass(frozen=True)
class WindowIdentity:
    window_id: int
    app_pid: int
    boot: str


@dataclass(frozen=True)
class WindowSnapshot:
    identity: WindowIdentity
    workspace: str
    tile_id: str


@dataclass(frozen=True)
class TransitionIntent:
    action: str
    identity: WindowIdentity
    workspace: str
    tile_id: str
    from_mode: Mode
    to_mode: Mode
    preserve_session: bool = True
    geometry: Optional[tuple] = None
    reason: str = ""


class TileModePlanner:
    def __init__(self, snapshot: WindowSnapshot):
        if not snapshot.workspace or not snapshot.tile_id:
            raise ValueError("workspace and tile_id are required")
        self.snapshot = snapshot
        self.mode = Mode.SMALL

    def _valid(self, identity: WindowIdentity) -> bool:
        return identity == self.snapshot.identity

    def transition(self, identity: WindowIdentity, target: Mode) -> TransitionIntent:
        try:
            target = Mode(target)
        except (TypeError, ValueError) as exc:
            raise ValueError("target must be small, half, or full") from exc

        old = self.mode
        if not self._valid(identity):
            self.mode = Mode.SMALL
            return TransitionIntent(
                "reset", identity, self.snapshot.workspace, self.snapshot.tile_id,
                old, Mode.SMALL, reason="stale identity; window session reset"
            )
        if target == old:
            return TransitionIntent(
                "noop", identity, self.snapshot.workspace, self.snapshot.tile_id,
                old, target
            )

        action = {
            (Mode.SMALL, Mode.HALF): "set-half",
            (Mode.HALF, Mode.FULL): "set-full",
            (Mode.FULL, Mode.SMALL): "restore-tile",
            (Mode.SMALL, Mode.FULL): "set-full",
            (Mode.HALF, Mode.SMALL): "restore-tile",
            (Mode.FULL, Mode.HALF): "set-half",
        }[(old, target)]
        self.mode = target
        return TransitionIntent(
            action, identity, self.snapshot.workspace, self.snapshot.tile_id,
            old, target
        )
