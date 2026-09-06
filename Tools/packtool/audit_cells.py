#!/usr/bin/env python3
"""Segment a reference sheet into cells and report per-cell consistency.

    python3 Tools/packtool/audit_cells.py Packs/klien/reference/klien.png

Reports, per cell: figure height, a head-height proxy (skin-tone bbox), the
head:body ratio, and the floating item's size and anchor offset. These are the
numbers that decide whether cells can be used as frames of one animation.
"""
import sys
import numpy as np
from PIL import Image


def split_runs(proj, minrun):
    on, runs, start = proj > 0, [], None
    for i, v in enumerate(on):
        if v and start is None:
            start = i
        if not v and start is not None:
            if i - start >= minrun:
                runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(on) - 1))
    return runs


def main(path):
    a = np.array(Image.open(path).convert("RGB")).astype(np.int16)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    dark = 255 - a.min(axis=2)
    sat = a.max(axis=2) - a.min(axis=2)
    fg = (dark > 18) | (sat > 18)
    item = fg & (G > R + 12) & (G > B + 12)          # the green floating item
    body = fg & ~item

    print(f"foreground coverage: {fg.mean()*100:.1f}%\n")
    for ri, (y0, y1) in enumerate(split_runs(body.sum(axis=1), 8)):
        band_b, band_i = body[y0:y1 + 1], item[y0:y1 + 1]
        print(f"=== ROW {ri}  y[{y0},{y1}]")
        for ci, (x0, x1) in enumerate(split_runs(band_b.sum(axis=0), 20)):
            ys, _ = np.where(band_b[:, x0:x1 + 1])
            top, bot = int(ys.min()), int(ys.max())
            sub = a[y0:y1 + 1, x0:x1 + 1]
            skin = ((sub[..., 0] > 200) & (sub[..., 1] > 170) &
                    (sub[..., 2] > 150) & (sub[..., 0] - sub[..., 2] > 10))
            sy, _ = np.where(skin)
            fig_h = bot - top + 1
            if len(sy):
                head_h = int(sy.max() - sy.min() + 1)
                print(f"  cell {ci}: x[{x0},{x1}] figureH={fig_h}  "
                      f"headProxyH={head_h}  head:body={head_h/fig_h:.3f}")
            else:
                print(f"  cell {ci}: x[{x0},{x1}] figureH={fig_h}  (no skin found)")
        for ii, (x0, x1) in enumerate(split_runs(band_i.sum(axis=0), 20)):
            ys, _ = np.where(band_i[:, x0:x1 + 1])
            print(f"  item {ii}: x[{x0},{x1}] w={x1-x0+1} "
                  f"y[{y0+int(ys.min())},{y0+int(ys.max())}] h={int(ys.max()-ys.min()+1)}")
        print()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Packs/klien/reference/klien.png")
