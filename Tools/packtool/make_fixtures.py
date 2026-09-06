#!/usr/bin/env python3
"""Generate the synthetic test packs procedurally.

These exist to prove Rule 1: the engine must run a character that shares nothing
with Klien - different cell size, different palette, no attachments, no art files
authored by a human. Because they are generated, they can never quietly acquire a
dependency on the reference character.

  test.solidsquare  the minimum viable pack: one texture, one clip, one state
  test.blinker      exercises the engine: a looping multi-frame clip AND a
                    quiescent single-frame state, plus an off-centre notch so
                    frame order and orientation are visible at a glance
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / "Tests" / "Fixtures"


def cell(size: int, body: tuple, notch: tuple | None, inset: int) -> np.ndarray:
    a = np.zeros((size, size, 4), dtype=np.uint8)
    a[inset:size - inset, inset:size - inset, :3] = body
    a[inset:size - inset, inset:size - inset, 3] = 255
    if notch is not None:                       # asymmetric: shows orientation
        a[inset:inset + 3, size - inset - 4:size - inset, :3] = notch
    return a


def write(path: Path, arr: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr, "RGBA").save(path)
    print(f"  wrote {path.relative_to(ROOT.parent.parent)}  {arr.shape[1]}x{arr.shape[0]}")


def main() -> None:
    print("test.solidsquare")
    write(ROOT / "test.solidsquare" / "atlas" / "sq.png",
          cell(16, (220, 90, 70), None, 2))

    print("test.blinker")
    # 4 frames of a pulsing square, plus a 5th "resting" frame, in one row
    frames = [cell(24, (60, 130 + i * 30, 210), (250, 240, 120), 2 + (i % 3))
              for i in range(4)]
    frames.append(cell(24, (70, 70, 90), (250, 240, 120), 4))
    write(ROOT / "test.blinker" / "atlas" / "blink.png", np.concatenate(frames, axis=1))


if __name__ == "__main__":
    main()
