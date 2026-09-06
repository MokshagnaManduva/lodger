"""packtool build - authored source -> a conforming, validated pack.

Source layout (what a human edits):

    Packs/klien/
      pack.json        identity, stage, clips (loop + per-frame ms), parts, states
      art/body.png     PNG frame strips, frames left to right, one per texture
      anchors/body.json  from `packtool anchors`
      audio/

Built output (what the engine loads):

    Packs/klien.pack/
      pack.json        same manifest with cells resolved and anchors injected
      atlas/body.png   uniform-cell grid page
      masks/body.mask  1-bit hit masks, RLE

Three things happen here that cannot happen anywhere else:

  * strips become **uniform-cell grid** pages. Uniform cells are non-negotiable:
    the engine animates by stepping a layer's contentsRect, which assumes every
    frame occupies an identically sized sub-rect.
  * per-frame anchors are injected from anchors.json into the clip frames, so the
    runtime manifest is self-contained.
  * hit masks are derived from alpha. Never hand-authored, so never wrong.

Ground-line drift is **reported, not silently corrected**. Auto-registering every
frame onto stage.ground would destroy deliberate vertical motion - a walk bob, a
jump, a squash on landing. Opt in per clip with "register": "ground".
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

MASK_MAGIC = b"LMSK"
MASK_VERSION = 1


def _varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def encode_masks(cells: list[np.ndarray], cw: int, ch: int) -> bytes:
    """1-bit alpha masks, RLE over runs starting with transparent.

    The engine hit-tests one array lookup per mouse-move event, so this has to be
    cheap to decode and cheap to keep resident. For a 128x128 cell a silhouette
    compresses to a few hundred bytes.
    """
    out = bytearray(MASK_MAGIC)
    out += bytes([MASK_VERSION])
    out += _varint(cw) + _varint(ch) + _varint(len(cells))
    for m in cells:
        flat = m.ravel().astype(bool)
        runs, cur, n = [], False, 0
        for v in flat:
            if bool(v) == cur:
                n += 1
            else:
                runs.append(n)
                cur, n = bool(v), 1
        runs.append(n)
        out += _varint(len(runs))
        for r in runs:
            out += _varint(r)
    return bytes(out)


def build(src: Path, out: Path, rep, *, clean: bool = True) -> dict | None:
    manifest = json.loads((src / "pack.json").read_text())
    stage = manifest["stage"]
    cw, ch = stage["cell"]["w"], stage["cell"]["h"]
    ground_y = stage["ground"]["y"]

    if clean and out.exists():
        shutil.rmtree(out)
    (out / "atlas").mkdir(parents=True, exist_ok=True)
    (out / "masks").mkdir(parents=True, exist_ok=True)

    # ---- anchors: {texture: {cellIndex: {anchorName: {x, y}}}} -----------------
    anchors_by_tex: dict[str, dict[int, dict]] = {}
    adir = src / "anchors"
    if adir.is_dir():
        for f in sorted(adir.glob("*.json")):
            doc = json.loads(f.read_text())
            per_cell: dict[int, dict] = {}
            for name, frames in doc.get("anchors", {}).items():
                for k, p in frames.items():
                    per_cell.setdefault(int(k), {})[name] = {"x": p["x"], "y": p["y"]}
            anchors_by_tex[f.stem] = per_cell

    cells_by_tex: dict[str, list[np.ndarray]] = {}

    # ---- strips -> uniform-cell grid pages ------------------------------------
    for name, tex in manifest["textures"].items():
        if "strip" in tex:
            strip_path = src / tex["strip"]
            im = Image.open(strip_path).convert("RGBA")
            w, h = im.size
            if h != ch or w % cw:
                rep.error(f"textures/{name}", f"strip {strip_path.name} is {w}x{h}; expected "
                                              f"height {ch} and width a multiple of {cw}")
                continue
            n = w // cw
            arr = np.array(im)
            cells = [arr[:, i * cw:(i + 1) * cw] for i in range(n)]
            cols = min(n, max(1, 1024 // cw))
            rows = (n + cols - 1) // cols
            page = np.zeros((rows * ch, cols * cw, 4), dtype=np.uint8)
            for i, cellimg in enumerate(cells):
                r, c = divmod(i, cols)
                page[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = cellimg
            rel = f"atlas/{name}.png"
            Image.fromarray(page, "RGBA").save(out / rel)
            manifest["textures"][name] = {k: v for k, v in tex.items() if k != "strip"}
            manifest["textures"][name].update({"file": rel, "columns": cols, "rows": rows})
            cells_by_tex[name] = [c[..., 3] > 0 for c in cells]
            rep.note(f"textures/{name}", f"{n} frames -> {cols}x{rows} grid "
                                         f"({cols*cw}x{rows*ch}px)")
        else:
            srcf = src / tex["file"]
            if not srcf.exists():
                rep.error(f"textures/{name}", f"file not found: {tex['file']}")
                continue
            (out / tex["file"]).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(srcf, out / tex["file"])
            arr = np.array(Image.open(srcf).convert("RGBA"))
            cols, rows = tex["columns"], tex["rows"]
            cells_by_tex[name] = [
                arr[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw, 3] > 0
                for r in range(rows) for c in range(cols)]

    # ---- cell overflow ---------------------------------------------------------
    # Art touching the cell edge has almost certainly been cropped, and it will
    # tear when the sprite is magnified or when a socket offsets it. Generators
    # crowd the canvas edge by default, which is why SpriteCook's animation tool
    # defaults to an edge_margin of 6px; we check for it rather than assume it.
    for name, cells in cells_by_tex.items():
        touching = []
        for i, m in enumerate(cells):
            if not m.any():
                continue
            if m[0].any() or m[-1].any() or m[:, 0].any() or m[:, -1].any():
                touching.append(i)
        if touching:
            shown = ", ".join(str(i) for i in touching[:8])
            more = f" (+{len(touching) - 8} more)" if len(touching) > 8 else ""
            rep.warn(f"textures/{name}",
                     f"art touches the cell edge on frame(s) {shown}{more}. Almost always a "
                     f"crop: leave a few pixels of margin so magnification and socket "
                     f"offsets do not clip the silhouette.")

    # ---- inject anchors, lint ground-line drift --------------------------------
    for cname, clip in manifest["clips"].items():
        tex = clip["texture"]
        per_cell = anchors_by_tex.get(tex, {})
        register = clip.pop("register", "none")
        bottoms = []
        for fr in clip["frames"]:
            idx = fr["cell"]
            found = per_cell.get(idx)
            if found:
                fr.setdefault("anchors", {}).update(found)
            cells = cells_by_tex.get(tex)
            if cells and idx < len(cells):
                mask = cells[idx]
                ys = np.where(mask.any(axis=1))[0]
                bottoms.append(int(ys.max()) if len(ys) else None)
        solid = [b for b in bottoms if b is not None]
        if solid:
            drift = max(solid) - min(solid)
            if register == "ground" and drift:
                rep.warn(f"clips/{cname}", f"register:ground requested but frames differ by "
                                           f"{drift}px at the sole; fix the art, not the build")
            elif drift > 2:
                rep.warn(f"clips/{cname}", f"ground line drifts {drift}px across frames "
                                           f"(soles at y {min(solid)}..{max(solid)}, "
                                           f"stage.ground.y={ground_y}). Intentional for a bob "
                                           f"or a jump; a bug otherwise.")

    # ---- hit masks --------------------------------------------------------------
    masks = {}
    for name, cells in cells_by_tex.items():
        if not cells:
            continue
        rel = f"masks/{name}.mask"
        blob = encode_masks(cells, cw, ch)
        (out / rel).write_bytes(blob)
        masks[name] = rel
        rep.note(f"masks/{name}", f"{len(cells)} cells, {len(blob)} bytes "
                                  f"({len(blob)/max(1,len(cells)):.0f} B/cell)")
    if masks:
        manifest["hitMasks"] = masks

    for extra in ("audio", "preview.png", "LICENSE", "CREDITS.md"):
        s = src / extra
        if s.is_dir():
            shutil.copytree(s, out / extra, dirs_exist_ok=True)
        elif s.exists():
            shutil.copy2(s, out / extra)

    (out / "pack.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest
