#!/usr/bin/env python3
"""Measure a raw reference sheet and report whether it istrue pixel art.

Reproduces every number in Docs/reference-audit.md.

    python3 Tools/packtool/audit_reference.py Packs/klien/reference/klien.png

Requires numpy + Pillow only (no scipy).
"""
import sys, collections
import numpy as np
from PIL import Image


def load(path):
    im = Image.open(path)
    return im, np.array(im.convert("RGB")).astype(np.int16), np.array(im)


def alpha_report(raw):
    if raw.ndim == 3 and raw.shape[2] == 4:
        a = raw[..., 3]
        u = np.unique(a)
        return f"alpha channel present; {len(u)} distinct values; fully opaque: {(a == 255).all()}"
    return "no alpha channel"


def palette_report(rgb):
    flat = rgb.reshape(-1, 3)
    uniq, counts = np.unique(flat, axis=0, return_counts=True)
    order = np.argsort(-counts)
    top = [(tuple(int(v) for v in uniq[i]), int(counts[i]), counts[i] / len(flat)) for i in order[:8]]
    return len(uniq), top


def run_length_report(rgb, box=None):
    sub = rgb if box is None else rgb[box[1]:box[3], box[0]:box[2]]
    runs = collections.Counter()
    for row in sub:
        cur = 1
        for i in range(1, len(row)):
            if (row[i] == row[i - 1]).all():
                cur += 1
            else:
                runs[cur] += 1
                cur = 1
        runs[cur] += 1
    total = sum(runs.values())
    mean = sum(L * c for L, c in runs.items()) / total
    return mean, runs.most_common(5), total


def grid_report(gray, box, lo=4, hi=24):
    """Score how much edge energy lands on a regular grid.

    1.0 == energy is spread uniformly (no grid). A clean Nx upscale of true
    pixel art scores near N.
    """
    sub = gray[box[1]:box[3], box[0]:box[2]]
    out = {}
    for axis, sig in (("columns", np.abs(np.diff(sub, axis=1)).sum(axis=0)),
                      ("rows", np.abs(np.diff(sub, axis=0)).sum(axis=1))):
        total = sig.sum()
        best = (0.0, 0, 0)
        for p in range(lo, hi + 1):
            for ph in range(p):
                v = sig[np.arange(ph, len(sig), p)].sum() / total * p
                if v > best[0]:
                    best = (v, p, ph)
        out[axis] = best
    return out


def main(path):
    im, rgb, raw = load(path)
    gray = rgb.mean(axis=2)
    print(f"file        : {path}")
    print(f"mode/size   : {im.mode} {im.size}")
    print(f"alpha       : {alpha_report(raw)}")

    n, top = palette_report(rgb)
    print(f"unique RGB  : {n}")
    for c, k, frac in top:
        print(f"              {c}  {k:>9}  {frac*100:5.2f}%")

    # a figure-sized window, avoiding the sheet margins
    h, w = gray.shape
    box = (w // 8, h // 16, w // 8 + min(460, w // 4), h // 16 + min(800, h // 2))
    mean, common, total = run_length_report(rgb, box)
    print(f"run lengths : mean {mean:.2f} over {total} runs in {box}")
    for L, c in common:
        print(f"              len={L:<3} n={c:<7} {c/total*100:5.1f}%")

    for axis, (score, p, ph) in grid_report(gray, box).items():
        print(f"grid {axis:<7}: best score {score:.3f} at period {p} phase {ph}"
              "   (1.0 == no grid)")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Packs/klien/reference/klien.png")
