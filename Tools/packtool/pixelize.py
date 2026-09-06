"""Stage 2 of the asset pipeline: raw reference cell -> tracing sketch.

The reference art is not pixel art (see Docs/reference-audit.md): 60k colours, no
pixel grid, anti-aliased edges. Reducing a ~920px figure to 96px is a ~9.6:1
downscale, and the naive operator (box average) is the worst possible choice for
this style - it washes black outlines into grey and blends adjacent flat colours
into invented in-between shades.

So instead:

  1. background -> alpha by tolerance flood from the image border. A flood, not a
     colour key: the background is noisy (#FFFFFF is only 28.6% of it), and a flood
     correctly leaves *enclosed* light areas - the shirt collar - opaque.
  2. isolate the subject with connected components, so the floating item separates
     from the figure on its own.
  3. quantise to the locked palette FIRST, in Oklab (RGB nearest shifts hues).
  4. downsample by per-block MODE, not mean - "which palette colour dominates this
     block", so no colour is ever invented.
  5. a separate outline pass, because outlines are thin and would lose every vote.
  6. hard alpha only. Pixel art has no partial alpha.

Output is a *sketch* to trace over. It is never a shipped asset.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

# --------------------------------------------------------------------- colour

def srgb_to_oklab(rgb: np.ndarray) -> np.ndarray:
    """rgb uint8/float in 0..255, shape (..., 3) -> Oklab, shape (..., 3)."""
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    return np.stack([
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    ], axis=-1)


def nearest_palette_index(rgb: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Perceptually-nearest palette index for each pixel. rgb (...,3) -> (...)."""
    lab = srgb_to_oklab(rgb).reshape(-1, 3)
    plab = srgb_to_oklab(palette)
    out = np.empty(len(lab), dtype=np.int32)
    step = 200_000
    for i in range(0, len(lab), step):
        chunk = lab[i:i + step]
        d = ((chunk[:, None, :] - plab[None, :, :]) ** 2).sum(axis=2)
        out[i:i + step] = d.argmin(axis=1)
    return out.reshape(rgb.shape[:-1])


def median_cut(pixels: np.ndarray, n: int, spread: float = 3.0,
               min_sep: float = 0.0, min_rgb: float = 0.0) -> np.ndarray:
    """A palette that is a usable ramp, not a population histogram.

    Plain median cut on this character returns ~12 indistinguishable near-blacks,
    because the suit, cape and hat dominate by area. So: over-segment to spread*n
    boxes, then greedily select n candidates trading off perceptual separation
    against how much of the image each one actually represents.
    """
    cand, pops = _median_cut_boxes(pixels, max(n, int(n * spread)))
    if len(cand) <= n:
        return cand
    lab = srgb_to_oklab(cand)
    rgbf = cand.astype(np.float64)
    weight = np.log1p(pops)
    chosen = [int(np.argmax(weight))]
    while len(chosen) < n:
        d = np.sqrt(((lab[:, None, :] - lab[None, chosen, :]) ** 2).sum(axis=2)).min(axis=1)
        # Oklab alone is not enough: its cube root over-separates near black, so
        # #000000 and #010102 read as 0.07 apart while being identical on screen.
        # Gate on raw sRGB distance too.
        drgb = np.sqrt(((rgbf[:, None, :] - rgbf[None, chosen, :]) ** 2).sum(axis=2)).min(axis=1)
        score = d * weight
        score[chosen] = -1.0
        score[(d < min_sep) | (drgb < min_rgb)] = -1.0
        if score.max() <= 0:
            break
        chosen.append(int(np.argmax(score)))
    return cand[np.array(sorted(chosen))]


def _median_cut_boxes(pixels: np.ndarray, n: int) -> tuple[np.ndarray, np.ndarray]:
    """Classic median cut over Oklab, returning representatives and their populations."""
    lab = srgb_to_oklab(pixels)
    boxes = [np.arange(len(pixels))]
    while len(boxes) < n:
        spreads = []
        for bi, idx in enumerate(boxes):
            if len(idx) < 2:
                spreads.append((-1.0, bi, 0))
                continue
            ext = lab[idx].max(axis=0) - lab[idx].min(axis=0)
            ax = int(ext.argmax())
            spreads.append((float(ext[ax]) * len(idx) ** 0.25, bi, ax))
        spread, bi, ax = max(spreads)
        if spread <= 0:
            break
        idx = boxes.pop(bi)
        order = idx[np.argsort(lab[idx][:, ax])]
        mid = len(order) // 2
        boxes += [order[:mid], order[mid:]]
    reps, pops = [], []
    for idx in boxes:
        if len(idx):
            reps.append(np.round(pixels[idx].mean(axis=0)).astype(np.uint8))
            pops.append(len(idx))
    reps = np.array(reps)
    pops = np.array(pops, dtype=np.float64)
    uniq, inv = np.unique(reps, axis=0, return_inverse=True)
    merged = np.zeros(len(uniq))
    np.add.at(merged, inv, pops)
    return uniq, merged


# ---------------------------------------------------------------- segmentation

def background_to_alpha(rgb: np.ndarray, tol: int = 26) -> np.ndarray:
    """Flood the background from the image border. Returns a boolean foreground mask.

    A flood rather than a colour key, so enclosed light regions (a white collar)
    stay opaque.
    """
    h, w, _ = rgb.shape
    lab = srgb_to_oklab(rgb)
    seed = lab[0, 0]
    # scalar "distance from the border colour", scaled so tol reads like 0..255
    dist = np.sqrt(((lab - seed) ** 2).sum(axis=2)) * 255.0
    similar = dist <= tol

    bg = np.zeros((h, w), dtype=bool)
    frontier = np.zeros((h, w), dtype=bool)
    frontier[0, :] = frontier[-1, :] = True
    frontier[:, 0] = frontier[:, -1] = True
    frontier &= similar
    bg |= frontier
    # iterative 4-connected dilation constrained to `similar`, vectorised
    while frontier.any():
        grown = np.zeros_like(bg)
        grown[1:, :] |= frontier[:-1, :]
        grown[:-1, :] |= frontier[1:, :]
        grown[:, 1:] |= frontier[:, :-1]
        grown[:, :-1] |= frontier[:, 1:]
        frontier = grown & similar & ~bg
        bg |= frontier
    return ~bg


def label_components(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """8-connected CCL via run-length union-find. No scipy needed."""
    h, w = mask.shape
    parent: list[int] = [0]

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    labels = np.zeros((h, w), dtype=np.int32)
    prev_runs: list[tuple[int, int, int]] = []
    for y in range(h):
        row = mask[y]
        if not row.any():
            prev_runs = []
            continue
        d = np.diff(np.concatenate(([0], row.view(np.int8), [0])))
        starts, ends = np.flatnonzero(d == 1), np.flatnonzero(d == -1)
        runs = []
        for s, e in zip(starts, ends):
            lab = 0
            for ps, pe, pl in prev_runs:          # 8-connected overlap
                if ps <= e and s <= pe:
                    lab = pl if lab == 0 else (union(lab, pl) or min(find(lab), find(pl)))
            if lab == 0:
                parent.append(len(parent))
                lab = len(parent) - 1
            labels[y, s:e] = lab
            runs.append((s - 1, e, lab))
        prev_runs = runs

    remap = {}
    for i in range(1, len(parent)):
        r = find(i)
        remap.setdefault(r, len(remap) + 1)
    lut = np.zeros(len(parent), dtype=np.int32)
    for i in range(1, len(parent)):
        lut[i] = remap[find(i)]
    return lut[labels], len(remap)


# ------------------------------------------------------------------ downsample

@dataclass
class PixelizeResult:
    sprite: np.ndarray          # (H, W, 4) uint8
    scale: float                # source px per target px
    source_bbox: tuple[int, int, int, int]
    figure_height_src: int
    palette_used: int


def pixelize(rgb: np.ndarray, fg: np.ndarray, palette: np.ndarray, *,
             target_height: int, cell: tuple[int, int], ground: tuple[int, int],
             outline_coverage: float = 0.30, alpha_coverage: float = 0.45,
             outline_lightness: float = 0.35) -> PixelizeResult:
    ys, xs = np.where(fg)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    sub_rgb = rgb[y0:y1 + 1, x0:x1 + 1]
    sub_fg = fg[y0:y1 + 1, x0:x1 + 1]
    sh, sw = sub_fg.shape

    scale = sh / target_height
    tw = max(1, int(round(sw / scale)))
    th = target_height

    idx = nearest_palette_index(sub_rgb, palette)
    lab_l = srgb_to_oklab(palette)[:, 0]
    is_outline = lab_l < outline_lightness           # dark palette entries

    out_idx = np.full((th, tw), -1, dtype=np.int32)
    for ty in range(th):
        sy0, sy1 = int(round(ty * scale)), max(int(round((ty + 1) * scale)), int(round(ty * scale)) + 1)
        for tx in range(tw):
            sx0, sx1 = int(round(tx * scale)), max(int(round((tx + 1) * scale)), int(round(tx * scale)) + 1)
            blk_fg = sub_fg[sy0:sy1, sx0:sx1]
            n = blk_fg.size
            if n == 0 or blk_fg.mean() < alpha_coverage:
                continue                              # hard alpha: in or out
            blk = idx[sy0:sy1, sx0:sx1][blk_fg]
            if blk.size == 0:
                continue
            counts = np.bincount(blk, minlength=len(palette))
            # separate outline vote: thin lines would lose a plain mode vote
            if counts[is_outline].sum() / blk.size >= outline_coverage:
                cand = np.where(is_outline, counts, 0)
                out_idx[ty, tx] = int(cand.argmax())
            else:
                out_idx[ty, tx] = int(counts.argmax())

    sprite_small = np.zeros((th, tw, 4), dtype=np.uint8)
    solid = out_idx >= 0
    sprite_small[solid, :3] = palette[out_idx[solid]]
    sprite_small[solid, 3] = 255

    cw, ch = cell
    canvas = np.zeros((ch, cw, 4), dtype=np.uint8)
    gx, gy = ground
    px = int(round(gx - tw / 2))
    py = int(round(gy - th))
    sx0, sy0 = max(0, px), max(0, py)
    sx1, sy1 = min(cw, px + tw), min(ch, py + th)
    if sx1 > sx0 and sy1 > sy0:
        canvas[sy0:sy1, sx0:sx1] = sprite_small[sy0 - py:sy1 - py, sx0 - px:sx1 - px]

    return PixelizeResult(canvas, scale, (int(x0), int(y0), int(x1), int(y1)),
                          int(sh), int(len(np.unique(out_idx[solid]))))


def save_zoom(arr: np.ndarray, path: Path, factor: int) -> None:
    im = Image.fromarray(arr, "RGBA")
    im.resize((im.width * factor, im.height * factor), Image.NEAREST).save(path)
