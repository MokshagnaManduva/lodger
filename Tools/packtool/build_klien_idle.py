#!/usr/bin/env python3
"""Finish the approved native idle and build Klien's first playable milestone.

The approved PNGs are checked-in inputs; no image service is needed to rebuild.
Pixel edits are deliberately local so the approved silhouette never changes.
"""
from pathlib import Path
import argparse
import shutil
import tempfile

import numpy as np
from PIL import Image, ImageDraw

from build import build
from packtool import Report

REPO = Path(__file__).resolve().parents[2]
PACK = REPO / 'Packs/klien'
SOURCE = PACK / 'reference/idle-v2'
PALETTE = []
for line in (PACK / 'reference/palette.gpl').read_text().splitlines():
    fields = line.split()
    if len(fields) >= 3 and all(f.isdigit() for f in fields[:3]):
        PALETTE.append(tuple(map(int, fields[:3])))


def finish_body():
    rest = np.array(Image.open(SOURCE / 'approved-body.png').convert('RGBA'))
    # Remove isolated dark/brown flecks inside the trousers, retaining seams.
    for x, y in [(52,100), (50,103), (51,103), (53,105), (53,108)]:
        rest[y, x] = (*PALETTE[3], 255)
    # Cool the cape-fold highlights into the costume ramp; keep the cane untouched.
    for y in range(97, 108):
        for x in list(range(71, 80)) + list(range(83, 90)):
            if tuple(rest[y, x, :3]) in [PALETTE[i] for i in (6, 8, 13)]:
                rest[y, x, :3] = PALETTE[5]
    inhale = rest.copy()
    inhale[80:89, 45:71] = rest[81:90, 45:71]
    peak = inhale.copy()
    peak[85:89, 79:94] = rest[86:90, 79:94]
    blink = rest.copy()
    # Clear eye interiors and the open upper lashes; retain hair and cheeks.
    blink[63, 48:53] = (*PALETTE[24], 255)
    blink[63, 62:69] = (*PALETTE[24], 255)
    for x0, x1 in [(48, 54), (61, 69)]:
        blink[64:69, x0:x1] = (*PALETTE[24], 255)
    blink[69, 49:52] = (*PALETTE[24], 255)
    blink[69, 62:68] = (*PALETTE[24], 255)
    # Curved closed lids, with a one-pixel cheek-shadow transition underneath.
    for x0, x1 in [(48, 54), (61, 69)]:
        blink[67, x0:x1] = (*PALETTE[2], 255)
        blink[66, x0] = blink[66, x1-1] = (*PALETTE[2], 255)
        blink[68, x0+1:x1-1] = (*PALETTE[20], 255)
    return [Image.fromarray(p) for p in (rest, inhale, peak, blink)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--install', action='store_true', help='replace the active pack with the idle-only milestone')
    args = parser.parse_args()
    poses = finish_body()
    art = SOURCE / 'art'
    art.mkdir(exist_ok=True)
    strip = Image.new('RGBA', (512, 128))
    for i, (name, pose) in enumerate(zip(('rest','inhale','peak','blink'), poses)):
        strip.paste(pose, (i*128, 0))
        pose.save(art / f'{name}.png')
    strip.save(art / 'body.png')
    # Full-cell separate attachment: no resampling, unchanged 22px leaf details.
    dumpling = Image.open(SOURCE / 'approved-dumpling.png').convert('RGBA')
    dumpling.save(art / 'dumpling.png')
    preview = poses[0].copy()
    preview.alpha_composite(dumpling)
    preview.save(SOURCE / 'preview.png')

    with tempfile.TemporaryDirectory(prefix='klien-idle-') as tmp:
        report = Report()
        build(SOURCE, Path(tmp), report, clean=False)
        if report.emit('Klien idle build'):
            raise SystemExit(1)
        for relative in ('pack.json', 'preview.png', 'atlas/body.png',
                         'atlas/dumpling.png', 'masks/body.mask', 'masks/dumpling.mask'):
            dst = PACK / relative
            dst.parent.mkdir(parents=True, exist_ok=True)
            if args.install:
                shutil.copy2(Path(tmp) / relative, dst)

    # A labeled pose sheet for pixel cleanup review (runtime bob is separate).
    sheet = Image.new('RGB', (4*276, 290), '#9D9596')
    draw = ImageDraw.Draw(sheet)
    for i, (name, pose) in enumerate(zip(('rest', 'inhale', 'peak', 'blink'), poses)):
        composite = pose.copy()
        composite.alpha_composite(dumpling)
        zoom = composite.resize((256,256), Image.Resampling.NEAREST)
        sheet.paste(zoom, (i*276+10, 5), zoom)
        draw.text((i*276+10, 270), name, fill='#1D1A22')
    sheet.save(SOURCE / 'pose-sheet.png')


if __name__ == '__main__':
    main()
