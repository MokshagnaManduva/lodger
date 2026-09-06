#!/usr/bin/env python3
"""packtool - the character pack pipeline CLI.

Subcommands (see CLAUDE.md section 7):
    validate    schema + cross-reference + policy checks on a pack directory
    build       (stage 5) authored source -> uniform-cell atlases + masks + manifest
    palette     (stage 1) extract and lock a palette from the raw reference
    anchors     (stage 4) author per-frame anchors against a live drift trace
    pixelize    (stage 2) turn a raw reference cell into a tracing sketch
    generate    (stage 3) scripted PixelLab skeleton runs        [not yet implemented]
    preview     (stage 7) contact sheets with anchor traces      [not yet implemented]

`validate` is the piece everything else leans on: it enforces the rules the JSON
Schema cannot express, above all the ones that protect Rule 2 (idle cost) and the
per-frame anchor discipline that the reference audit showed is necessary.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCHEMA_PATH = Path(__file__).resolve().parents[2] / "Schema" / "pack.schema.json"


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def note(self, where: str, msg: str) -> None:
        self.notes.append(f"{where}: {msg}")

    def error(self, where: str, msg: str) -> None:
        self.errors.append(f"{where}: {msg}")

    def warn(self, where: str, msg: str) -> None:
        self.warnings.append(f"{where}: {msg}")

    def emit(self, label: str) -> int:
        for n in self.notes:
            print(f"  .        {n}")
        for w in self.warnings:
            print(f"  warning  {w}")
        for e in self.errors:
            print(f"  ERROR    {e}")
        if self.errors:
            print(f"\n{label}: FAILED - {len(self.errors)} error(s), {len(self.warnings)} warning(s)")
            return 1
        print(f"\n{label}: OK ({len(self.warnings)} warning(s))")
        return 0


# --------------------------------------------------------------------------- schema

def check_schema(pack: dict, rep: Report) -> bool:
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        rep.warn("schema", "jsonschema not installed; skipping schema validation "
                           "(pip install jsonschema)")
        return True
    schema = json.loads(SCHEMA_PATH.read_text())
    Draft202012Validator.check_schema(schema)
    ok = True
    for err in sorted(Draft202012Validator(schema).iter_errors(pack),
                      key=lambda e: list(e.path)):
        loc = "/".join(str(p) for p in err.path) or "<root>"
        rep.error(f"schema {loc}", err.message.split("\n")[0][:200])
        ok = False
    return ok


# ------------------------------------------------------------------ cross-references

def check_references(pack: dict, root: Path, rep: Report, assets: bool = True) -> None:
    textures = pack.get("textures", {})
    clips = pack.get("clips", {})
    states = pack.get("states", {})
    sounds = pack.get("sounds", {})
    parts = pack.get("parts", [])

    for name, tex in textures.items():
        if not (root / tex["file"]).exists():
            (rep.error if assets else rep.warn)(
                f"textures/{name}", f"file not found: {tex['file']}")

    for sname, snd in sounds.items():
        if not (root / snd["file"]).exists():
            (rep.error if assets else rep.warn)(
                f"sounds/{sname}", f"file not found: {snd['file']}")

    for cname, clip in clips.items():
        tex = textures.get(clip["texture"])
        if tex is None:
            rep.error(f"clips/{cname}", f"unknown texture {clip['texture']!r}")
            continue
        cap = tex["columns"] * tex["rows"]
        for i, fr in enumerate(clip["frames"]):
            if fr["cell"] >= cap:
                rep.error(f"clips/{cname}/frames/{i}",
                          f"cell {fr['cell']} outside {clip['texture']} grid "
                          f"({tex['columns']}x{tex['rows']} = {cap} cells)")
            if "sound" in fr and fr["sound"] not in sounds:
                rep.error(f"clips/{cname}/frames/{i}", f"unknown sound {fr['sound']!r}")

    part_names: list[str] = []
    body_parts = [p["name"] for p in parts if p["bind"]["mode"] == "body"]
    if len(body_parts) != 1:
        rep.error("parts", f"expected exactly one part with mode 'body', found {len(body_parts)}")

    for p in parts:
        w = f"parts/{p['name']}"
        bind = p["bind"]
        parent = bind.get("parent", "body")
        if bind["mode"] != "body":
            if parent not in part_names:
                rep.error(w, f"parent {parent!r} is not a part declared before this one")
        if "clip" in bind and bind["clip"] not in clips:
            rep.error(w, f"unknown clip {bind['clip']!r}")
        if bind["mode"] == "socket" and bind.get("frames", "parent") == "clip" and "clip" not in bind:
            rep.error(w, "frames: 'clip' requires a clip")
        for key in ("visibleIn", "hiddenIn"):
            for s in p.get(key, []):
                if s not in states:
                    rep.error(w, f"{key} names unknown state {s!r}")
        part_names.append(p["name"])

    initial = pack.get("initialState")
    if initial and initial not in states:
        rep.error("initialState", f"unknown state {initial!r}")

    for sname, st in states.items():
        w = f"states/{sname}"
        if st["clip"] not in clips:
            rep.error(w, f"unknown clip {st['clip']!r}")
        if "sound" in st and st["sound"] not in sounds:
            rep.error(w, f"unknown sound {st['sound']!r}")
        for i, nx in enumerate(st.get("next", [])):
            if nx["state"] not in states:
                rep.error(f"{w}/next/{i}", f"unknown state {nx['state']!r}")
        for i, it in enumerate(st.get("interrupts", [])):
            if it["state"] not in states:
                rep.error(f"{w}/interrupts/{i}", f"unknown state {it['state']!r}")

    if sounds and "audio" not in pack.get("requires", []):
        rep.error("requires", "pack declares sounds but does not require the 'audio' capability")
    if not sounds and "audio" in pack.get("requires", []):
        rep.warn("requires", "'audio' required but no sounds are declared")
    if any(st.get("surface") == "windowTop" for st in states.values()) \
            and "windowEdges" not in pack.get("requires", []):
        rep.error("requires", "a state uses surface 'windowTop' but the pack does not "
                              "require the 'windowEdges' capability")


# ----------------------------------------------------------------------- Rule 2

def check_attachment_margin(pack: dict, rep: Report) -> None:
    """A drifting float pads the window, and compositing cost grows with its area.

    The engine pads the pet window by the largest `rest + maxOffset` so a float is
    not clipped. That is correct, but the window area - and therefore what
    WindowServer composites every frame - grows quadratically with it.
    """
    stage = pack.get("stage", {})
    cell = stage.get("cell", {})
    cw, ch = cell.get("w", 0), cell.get("h", 0)
    if not cw or not ch:
        return
    worst, who = 0.0, None
    for part in pack.get("parts", []):
        b = part["bind"]
        if b["mode"] != "float":
            continue
        rest = b.get("rest", {"x": 0, "y": 0})
        drift = b.get("maxOffset", 24) + max(abs(rest.get("x", 0)), abs(rest.get("y", 0)))
        if drift > worst:
            worst, who = drift, part["name"]
    if not who:
        return
    grown = ((cw + 2 * worst) * (ch + 2 * worst)) / (cw * ch)
    pct = worst / min(cw, ch) * 100
    if pct > 25:
        rep.warn("parts/" + who,
                 f"float drifts up to {worst:g}px ({pct:.0f}% of the cell), so the pet "
                 f"window grows to {grown:.1f}x the cell area. Compositing cost scales "
                 f"with that. Reduce maxOffset or rest unless the drift is essential.")
    else:
        rep.note("parts/" + who,
                 f"float drift {worst:g}px -> window is {grown:.2f}x the cell area")


def check_idle_policy(pack: dict, rep: Report) -> None:
    """A quiescent state must be one the engine can leave completely alone."""
    clips = pack.get("clips", {})
    for sname, st in pack.get("states", {}).items():
        if not st.get("quiescent"):
            continue
        w = f"states/{sname} (quiescent)"
        if st.get("next"):
            rep.error(w, "declares 'next'; a quiescent state cannot schedule a transition. "
                         "Leave it only via interrupts.")
        if "duration" in st:
            rep.error(w, "declares 'duration'; that requires a timer. Remove it.")
        motion = st.get("motion", "none")
        if motion != "none":
            rep.error(w, f"declares motion {motion!r}; motion requires a display link.")
        clip = clips.get(st["clip"])
        if clip and clip.get("loop", "none") == "none" and len(clip["frames"]) > 1:
            rep.error(w, f"clip {st['clip']!r} is multi-frame and non-looping, so it ends "
                         "and needs a clip.ended wake-up. Use a looping or single-frame clip.")
        if not st.get("interrupts"):
            rep.warn(w, "has no interrupts; the pet can never leave this state.")


# -------------------------------------------------------------------- anchors

def _states_for_part(pack: dict, part: dict) -> set[str]:
    all_states = set(pack.get("states", {}))
    if part.get("visibleIn"):
        return set(part["visibleIn"]) & all_states
    return all_states - set(part.get("hiddenIn", []))


def check_anchors(pack: dict, rep: Report, jump_limit: float = 8.0) -> None:
    """Anchors are authored, never inferred - so verify they are actually all there.

    The reference audit measured the floating item's anchor drifting ~8 px on a
    96 px sprite across cells that were meant to be the same character. Missing or
    jumpy anchors are invisible in a contact sheet and glaring in motion.
    """
    clips = pack.get("clips", {})
    states = pack.get("states", {})

    for part in pack.get("parts", []):
        bind = part["bind"]
        if bind["mode"] not in ("socket", "float"):
            continue
        anchor = bind["anchor"]
        for sname in sorted(_states_for_part(pack, part)):
            st = states.get(sname)
            if not st:
                continue
            cname = st["clip"]
            clip = clips.get(cname)
            if not clip:
                continue
            missing = [i for i, fr in enumerate(clip["frames"])
                       if anchor not in fr.get("anchors", {})]
            if missing:
                rep.error(f"clips/{cname}",
                          f"part {part['name']!r} binds anchor {anchor!r}, but it is absent "
                          f"on frame(s) {missing} - reachable from state {sname!r}")

    for cname, clip in clips.items():
        frames = clip["frames"]
        names = set()
        for fr in frames:
            names |= set(fr.get("anchors", {}))
        limit = clip.get("anchorJumpLimit", jump_limit)
        for anchor in sorted(names):
            pts = [fr.get("anchors", {}).get(anchor) for fr in frames]
            for i in range(1, len(pts)):
                a, b = pts[i - 1], pts[i]
                if not a or not b:
                    continue
                d = max(abs(a["x"] - b["x"]), abs(a["y"] - b["y"]))
                if d > limit:
                    rep.warn(f"clips/{cname}",
                             f"anchor {anchor!r} jumps {d:g} px between frames {i-1} and {i} "
                             f"(limit {limit:g}); check for drift, or set anchorJumpLimit "
                             f"on this clip if the sweep is deliberate")


# ------------------------------------------------------------------ reachability

def check_reachability(pack: dict, rep: Report) -> None:
    states = pack.get("states", {})
    initial = pack.get("initialState")
    if initial not in states:
        return
    seen, stack = {initial}, [initial]
    while stack:
        # dangling targets are reported by check_references; skip them rather than crash
        st = states.get(stack.pop())
        if st is None:
            continue
        for nx in list(st.get("next", [])) + list(st.get("interrupts", [])):
            if nx["state"] not in seen:
                seen.add(nx["state"])
                stack.append(nx["state"])
    for orphan in sorted(set(states) - seen):
        rep.warn("states", f"{orphan!r} is unreachable from initialState {initial!r}")

    for sname, st in states.items():
        if not st.get("next") and not st.get("interrupts"):
            rep.error(f"states/{sname}", "is a dead end: no 'next' and no 'interrupts'")


# --------------------------------------------------------------------------- cmds

def cmd_validate(args: argparse.Namespace) -> int:
    root = Path(args.pack).resolve()
    manifest = root / "pack.json" if root.is_dir() else root
    root = manifest.parent
    if not manifest.exists():
        print(f"no pack.json at {manifest}")
        return 2
    print(f"validating {manifest}")
    try:
        pack = json.loads(manifest.read_text())
    except json.JSONDecodeError as e:
        print(f"  ERROR    pack.json is not valid JSON: {e}")
        return 1

    rep = Report()
    if check_schema(pack, rep):
        check_references(pack, root, rep, assets=not args.no_assets)
        check_idle_policy(pack, rep)
        check_attachment_margin(pack, rep)
        check_anchors(pack, rep, jump_limit=args.anchor_jump)
        check_reachability(pack, rep)
    return rep.emit(pack.get("identity", {}).get("id", "pack"))


# ------------------------------------------------------------------ stage 1 / 2

# Generous cell windows over the reference sheet. Connected components does the
# real separation, so these only have to avoid slicing a figure in half.
REFERENCE_CELLS = {
    "r0c0": (0, 60, 681, 1030),      "r0c1": (681, 60, 1356, 1030),
    "r0c2": (1356, 60, 2048, 1030),  "r1c0": (0, 1050, 690, 2040),
    "r1c1": (690, 1050, 1361, 2040), "r1c2": (1361, 1050, 2048, 2040),
}


def _load_palette(path: Path) -> "np.ndarray":
    import numpy as np
    cols = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line[0] in "#GNC" and not line[0].isdigit():
            parts = line.split()
            if len(parts) >= 3 and all(x.isdigit() for x in parts[:3]):
                cols.append([int(x) for x in parts[:3]])
            continue
        parts = line.split()
        if len(parts) >= 3 and all(x.isdigit() for x in parts[:3]):
            cols.append([int(x) for x in parts[:3]])
    return np.array(cols, dtype=np.uint8)


def cmd_palette(args: argparse.Namespace) -> int:
    import numpy as np
    from PIL import Image
    sys.path.insert(0, str(Path(__file__).parent))
    import pixelize as px

    src = Path(args.source)
    rgb = np.array(Image.open(src).convert("RGB"))
    print(f"source   : {src}  {rgb.shape[1]}x{rgb.shape[0]}")
    fg = px.background_to_alpha(rgb, tol=args.tolerance)
    print(f"foreground: {fg.mean()*100:.1f}% after border flood (tolerance {args.tolerance})")

    pixels = rgb[fg]
    if len(pixels) > args.sample:
        rng = np.random.default_rng(0)
        pixels = pixels[rng.choice(len(pixels), args.sample, replace=False)]
    pal = px.median_cut(pixels, args.colors, min_sep=args.min_separation,
                        min_rgb=args.min_rgb)
    # sort by Oklab lightness so the ramp reads top-to-bottom
    pal = pal[np.argsort(px.srgb_to_oklab(pal)[:, 0])]
    print(f"palette  : {len(pal)} colours (requested {args.colors})")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = ["GIMP Palette", f"Name: {out.stem}", "Columns: 8", "#"]
    for c in pal:
        lines.append(f"{c[0]:3d} {c[1]:3d} {c[2]:3d}\t#{c[0]:02X}{c[1]:02X}{c[2]:02X}")
    out.write_text("\n".join(lines) + "\n")

    strip = np.zeros((1, len(pal), 3), dtype=np.uint8)
    strip[0] = pal
    px.save_zoom(np.dstack([strip, np.full(strip.shape[:2] + (1,), 255, np.uint8)]),
                 out.with_suffix(".png"), 24)
    print(f"wrote    : {out}")
    print(f"wrote    : {out.with_suffix('.png')}")
    for c in pal:
        print(f"           #{c[0]:02X}{c[1]:02X}{c[2]:02X}")
    return 0


def cmd_pixelize(args: argparse.Namespace) -> int:
    import numpy as np
    from PIL import Image
    sys.path.insert(0, str(Path(__file__).parent))
    import pixelize as px

    rgb_full = np.array(Image.open(args.source).convert("RGB"))
    if args.cell in REFERENCE_CELLS:
        x0, y0, x1, y1 = REFERENCE_CELLS[args.cell]
    else:
        x0, y0, x1, y1 = (int(v) for v in args.cell.split(","))
    rgb = rgb_full[y0:y1, x0:x1]
    print(f"cell     : {args.cell} -> source window ({x0},{y0})-({x1},{y1})")

    fg = px.background_to_alpha(rgb, tol=args.tolerance)
    labels, n = px.label_components(fg)
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    order = np.argsort(-sizes)
    print(f"components: {n}; largest areas {[int(sizes[i]) for i in order[:4]]}")

    if args.component == "largest":
        keep = {int(order[0])}
    elif args.component == "all":
        keep = {int(i) for i in order if sizes[i] > args.min_area}
    else:
        keep = {int(order[int(args.component)])}
    mask = np.isin(labels, list(keep))
    print(f"kept     : component(s) {sorted(keep)} -> {mask.sum()} px")

    pal = _load_palette(Path(args.palette))
    print(f"palette  : {len(pal)} colours from {args.palette}")

    res = px.pixelize(rgb, mask, pal,
                      target_height=args.height,
                      cell=(args.cell_size, args.cell_size),
                      ground=(args.cell_size // 2, args.ground),
                      outline_coverage=args.outline_coverage,
                      alpha_coverage=args.alpha_coverage)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    stem = args.cell
    Image.fromarray(res.sprite, "RGBA").save(out / f"{stem}.png")
    px.save_zoom(res.sprite, out / f"{stem}@8x.png", 8)
    meta = {
        "DO_NOT_SHIP": "This is a tracing sketch produced by packtool pixelize. "
                       "It is never referenced by a manifest.",
        "source": str(args.source), "cell": args.cell,
        "source_bbox": res.source_bbox, "figure_height_src": res.figure_height_src,
        "downscale": round(res.scale, 3), "target_height": args.height,
        "cell_size": args.cell_size, "palette_colours_used": res.palette_used,
        "palette": str(args.palette),
    }
    (out / f"{stem}.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"downscale: {res.scale:.2f}:1  ({res.figure_height_src}px -> {args.height}px)")
    print(f"colours  : {res.palette_used} of {len(pal)} used")
    print(f"wrote    : {out / (stem + '.png')}  and  @8x.png  and  .json")
    return 0


def cmd_anchors(args: argparse.Namespace) -> int:
    sys.path.insert(0, str(Path(__file__).parent))
    import anchors as anchor_tool

    pack = Path(args.pack).resolve()
    strip = Path(args.strip)
    if not strip.is_absolute():
        strip = pack / strip if (pack / strip).exists() else Path(args.strip)
    if not strip.exists():
        print(f"no frame strip at {strip}")
        return 2

    cell = args.cell
    ground = args.ground
    names = [a.strip() for a in args.anchors.split(",") if a.strip()]
    manifest = pack / "pack.json"
    if manifest.exists():
        pk = json.loads(manifest.read_text())
        stage = pk.get("stage", {})
        if cell is None:
            cell = stage.get("cell", {}).get("h")
        if ground is None:
            ground = stage.get("ground", {}).get("y")
        if not names:
            # default to every anchor some socket/float part actually binds
            names = sorted({p["bind"]["anchor"] for p in pk.get("parts", [])
                            if p["bind"]["mode"] in ("socket", "float")})
    if cell is None:
        print("need --cell (no pack.json to read stage.cell from)")
        return 2
    if not names:
        print("no anchors to author: pass --anchors, or declare a socket/float part")
        return 2

    anchor_tool.serve(pack, strip, cell, names, ground, args.limit, args.port,
                      open_browser=not args.no_open)
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    sys.path.insert(0, str(Path(__file__).parent))
    import build as builder

    src = Path(args.pack).resolve()
    out = Path(args.out).resolve() if args.out else src.parent / (src.name + ".pack")
    if not (src / "pack.json").exists():
        print(f"no pack.json at {src}")
        return 2
    print(f"building {src} -> {out}")

    rep = Report()
    manifest = builder.build(src, out, rep)
    if manifest is None or rep.errors:
        return rep.emit("build")

    # the built pack must pass the same gate a stranger's pack would
    if check_schema(manifest, rep):
        check_references(manifest, out, rep, assets=True)
        check_idle_policy(manifest, rep)
        check_attachment_margin(manifest, rep)
        check_anchors(manifest, rep, jump_limit=args.anchor_jump)
        check_reachability(manifest, rep)
    return rep.emit(manifest.get("identity", {}).get("id", "pack"))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="packtool", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("validate", help="schema + cross-reference + policy checks")
    v.add_argument("pack", help="pack directory or path to pack.json")
    v.add_argument("--no-assets", action="store_true",
                   help="report missing atlas/audio files as warnings instead of errors "
                        "(for validating a manifest before the art exists)")
    v.add_argument("--anchor-jump", type=float, default=8.0,
                   help="warn when an anchor moves more than this many px between "
                        "adjacent frames (default: 8)")
    v.set_defaults(func=cmd_validate)

    pa = sub.add_parser("palette", help="extract and lock a palette from raw reference art")
    pa.add_argument("source")
    pa.add_argument("--out", default="Packs/klien/reference/palette.gpl")
    pa.add_argument("--colors", type=int, default=28)
    pa.add_argument("--tolerance", type=int, default=26)
    pa.add_argument("--sample", type=int, default=400_000)
    pa.add_argument("--min-separation", type=float, default=0.035,
                    help="minimum Oklab distance between palette entries (default 0.035); "
                         "prevents a dominant colour eating slots with near-duplicates")
    pa.add_argument("--min-rgb", type=float, default=14.0,
                    help="minimum raw sRGB distance between palette entries (default 14); "
                         "Oklab over-separates near black, this catches what it misses")
    pa.set_defaults(func=cmd_palette)

    pz = sub.add_parser("pixelize", help="raw reference cell -> tracing sketch (never shipped)")
    pz.add_argument("source")
    pz.add_argument("--cell", required=True,
                    help="a named cell (%s) or x0,y0,x1,y1" % ",".join(REFERENCE_CELLS))
    pz.add_argument("--palette", default="Packs/klien/reference/palette.gpl")
    pz.add_argument("--out", default="Packs/klien/reference/sketches")
    pz.add_argument("--height", type=int, default=96, help="target figure height in px")
    pz.add_argument("--cell-size", type=int, default=128)
    pz.add_argument("--ground", type=int, default=120, help="ground y within the cell")
    pz.add_argument("--component", default="largest", help="largest | all | <rank index>")
    pz.add_argument("--min-area", type=int, default=2000)
    pz.add_argument("--tolerance", type=int, default=26)
    pz.add_argument("--outline-coverage", type=float, default=0.30)
    pz.add_argument("--alpha-coverage", type=float, default=0.45)
    pz.set_defaults(func=cmd_pixelize)

    an = sub.add_parser("anchors", help="author per-frame anchors against a live drift trace")
    an.add_argument("pack", help="pack directory (anchors.json is written here)")
    an.add_argument("--strip", required=True, help="PNG frame strip, frames left to right")
    an.add_argument("--cell", type=int, help="cell size in px (default: stage.cell.h)")
    an.add_argument("--ground", type=int, help="ground line y (default: stage.ground.y)")
    an.add_argument("--anchors", default="",
                    help="comma-separated names (default: every anchor a socket/float part binds)")
    an.add_argument("--limit", type=float, default=8.0, help="drift warning threshold in px")
    an.add_argument("--port", type=int, default=8765)
    an.add_argument("--no-open", action="store_true")
    an.set_defaults(func=cmd_anchors)

    b = sub.add_parser("build", help="authored source -> atlases + masks + validated manifest")
    b.add_argument("pack", help="source pack directory")
    b.add_argument("--out", help="output directory (default: <pack>.pack)")
    b.add_argument("--anchor-jump", type=float, default=8.0)
    b.set_defaults(func=cmd_build)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
