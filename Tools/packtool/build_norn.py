#!/usr/bin/env python3
"""Compile Norn's reviewed sheet and authored registration into a local runtime pack.

Image generation is a separate, recorded art step. This compiler only normalizes
the pixel grid/palette, applies explicit registration, and builds data/masks.
Never infer ground or attachment anchors from connected components.
"""
from pathlib import Path
import json
import subprocess
import sys

import numpy as np
from PIL import Image

from build import encode_masks
import looks

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "Packs/Norn"
SOURCE = PACK / "reference/runtime-v1"
MOTION = PACK / "reference/motion-v2"
POLISH = PACK / "reference/polish-v3"


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def compile_sheet(sheet_path, registration_path, texture, palette=None, shared_body=None):
    art = json.loads(registration_path.read_text())
    sheet = Image.open(sheet_path).convert("RGBA")
    columns, rows = art["columns"], art["rows"]
    if len(art["frames"]) != columns * rows:
        raise ValueError(f"Incomplete registration for {texture}")
    if sheet.getchannel("A").getextrema()[0] != 0:
        raise ValueError("Source has no transparency; regenerate it, do not color-key it")
    frames = []
    for index, registration in enumerate(art["frames"]):
        # Reuse complete canonical endpoint cells, not redrawn lookalikes. A
        # clip uses one texture, so endpoints are packed onto each new page.
        if "bodyCell" in registration:
            cell = registration["bodyCell"]
            frames.append(shared_body.crop((cell % 4 * 128, cell // 4 * 128,
                                            cell % 4 * 128 + 128, cell // 4 * 128 + 128)))
            continue
        # Explicit authored rectangle includes the whole pose, with fixed scale
        # within each motion. Generated source rows are not perfectly uniform;
        # only the compiled atlas must be. Never cut blindly at sheet.width/4.
        cell = sheet.crop(tuple(registration["crop"]))
        cell = cell.resize(tuple(registration["size"]), Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (128, 128))
        frame.paste(cell, tuple(registration["at"]))
        frames.append(frame)
    atlas = Image.new("RGBA", (columns * 128, rows * 128))
    for index, frame in enumerate(frames):
        atlas.paste(frame, (index % columns * 128, index // columns * 128))
    # One shared palette, never a different color ramp in each animation frame.
    alpha = atlas.getchannel("A").point(lambda a: 255 if a >= art["alphaThreshold"] else 0)
    atlas.putalpha(alpha)
    if palette is None:
        atlas = atlas.quantize(colors=32, method=Image.Quantize.FASTOCTREE,
                               dither=Image.Dither.NONE).convert("RGBA")
    else:
        # The added motion sheets inherit the original runtime palette; adding
        # poses must not recolor the existing character or introduce new ramps.
        atlas = atlas.convert("RGB").quantize(palette=palette,
                                              dither=Image.Dither.NONE).convert("RGBA")
    atlas.putalpha(alpha)
    # Canonical transparent pixels also have zero RGB, avoiding stray color in
    # tools that inspect RGB without compositing alpha correctly.
    pixels = np.array(atlas)
    pixels[pixels[:, :, 3] == 0] = 0
    atlas = Image.fromarray(pixels)
    (PACK / "atlas").mkdir(exist_ok=True)
    (PACK / "masks").mkdir(exist_ok=True)
    atlas.save(PACK / f"atlas/{texture}.png")
    pixels = np.asarray(atlas)
    masks = [pixels[r*128:(r+1)*128, c*128:(c+1)*128, 3] > 0
             for r in range(rows) for c in range(columns)]
    (PACK / f"masks/{texture}.mask").write_bytes(encode_masks(masks, 128, 128))
    return atlas, len(frames)


def main():
    body, count = compile_sheet(SOURCE / "lifecycle-sheet.png", SOURCE / "registration.json", "body")
    body.crop((0, 0, 128, 128)).save(PACK / "preview.png")
    pixels = np.asarray(body)
    colors = [tuple(int(v) for v in rgb) for rgb in np.unique(pixels[pixels[:, :, 3] > 0, :3], axis=0)]
    palette = Image.new("P", (1, 1))
    palette.putpalette([v for rgb in colors + [colors[-1]] * (256 - len(colors)) for v in rgb])
    for name in ("sleep", "held", "fall"):
        _, added = compile_sheet(MOTION / f"{name}-sheet.png", MOTION / f"{name}-registration.json",
                                 name, palette=palette)
        count += added
    for name in ("walk", "greet", "sit"):
        _, added = compile_sheet(POLISH / f"{name}-sheet.png", POLISH / f"{name}-registration.json",
                                 name, palette=palette, shared_body=body)
        count += added
    manifest = json.loads((SOURCE / "pack.source.json").read_text())
    # Selectable looks. Her flask's purples are a hue family of their own, so the
    # potion can change colour without touching hair, apron or the root. (Her
    # irises share two of those purples and shift slightly with it.)
    used = looks.atlas_colors(PACK / t["file"] for t in manifest["textures"].values())
    potion = looks.hue_family(used, 0.70, 0.87)
    manifest["appearance"] = [looks.choice("potion", "Potion", "Violet", [
        ("emerald", "Emerald", looks.recolor(potion, lambda c: looks.rotate(c, -151))),
        ("amber", "Amber", looks.recolor(potion, lambda c: looks.rotate(c, -241))),
        ("azure", "Azure", looks.recolor(potion, lambda c: looks.rotate(c, -79)))])]
    write_json(PACK / "pack.json", manifest)
    descriptions = json.loads((SOURCE / "clips.json").read_text())
    studies = []
    for name, clip in manifest["clips"].items():
        texture = manifest["textures"][clip["texture"]]
        study = dict(descriptions[name], id=name, src=texture["file"],
                     columns=texture["columns"], rows=texture["rows"],
                     frames=[f["ms"] for f in clip["frames"]],
                     cells=[f["cell"] for f in clip["frames"]], nativeCell=128,
                     duration=sum(f["ms"] for f in clip["frames"]), runtimeLoop=clip["loop"])
        studies.append(study)
    (PACK / "runtime.js").write_text("// Generated by build_norn.py; edit reference/runtime-v1 sources.\n"
                                     + "window.NORN_DRAFTS = " + json.dumps(studies, indent=2) + ";\n")
    subprocess.run([sys.executable, str(ROOT / "Tools/packtool/packtool.py"),
                    "validate", str(PACK)], check=True)
    print(f"Built {count} cells, {len(manifest['clips'])} clips, {len(manifest['states'])} states")


if __name__ == "__main__":
    main()
