"""Colour maps for a pack's `appearance` options.

An appearance option recolours exact source colours (see Docs/PACK_FORMAT.md).
These helpers derive the maps from a ramp of source colours, so the looks are
reproducible from the art rather than typed in by hand.
"""
import colorsys


def hex_color(rgb) -> str:
    return "#%02x%02x%02x" % tuple(int(v) for v in rgb[:3])


def tint(rgb, hue, saturation, lift=0.0, gain=1.0):
    """Keep the colour's lightness (optionally scaled), replace hue and saturation."""
    _, lightness, _ = colorsys.rgb_to_hls(*[v / 255 for v in rgb[:3]])
    lightness = min(1.0, lightness * gain + lift)
    return tuple(round(v * 255) for v in colorsys.hls_to_rgb(hue, lightness, saturation))


def rotate(rgb, degrees):
    """Rotate hue, keeping lightness and saturation: for an already-colourful ramp."""
    hue, lightness, saturation = colorsys.rgb_to_hls(*[v / 255 for v in rgb[:3]])
    return tuple(round(v * 255) for v in colorsys.hls_to_rgb((hue + degrees / 360) % 1, lightness, saturation))


def hue_family(colors, low, high, min_saturation=0.2):
    """Colours whose hue lies in [low, high] (0..1) and that are not near-grey."""
    out = []
    for rgb in colors:
        hue, _, saturation = colorsys.rgb_to_hls(*[v / 255 for v in rgb[:3]])
        if low <= hue <= high and saturation >= min_saturation:
            out.append(tuple(rgb[:3]))
    return sorted(out)


def recolor(ramp, transform) -> dict:
    """{'#source': '#replacement'} for every colour in the ramp that changes."""
    out = {}
    for rgb in ramp:
        replacement = transform(rgb)
        if tuple(replacement) != tuple(rgb[:3]):
            out[hex_color(rgb)] = hex_color(replacement)
    return dict(sorted(out.items()))


def choice(identifier, label, default_label, options) -> dict:
    """One appearance choice. `options` is [(id, label, recolor map)]; the default
    comes first and is the art as drawn."""
    return {"id": identifier, "label": label, "default": "default",
            "options": [{"id": "default", "label": default_label}]
                       + [{"id": i, "label": l, "recolor": m} for i, l, m in options]}


def atlas_colors(paths) -> set:
    """Every opaque colour used by the given atlas images."""
    import numpy as np
    from PIL import Image
    out = set()
    for path in paths:
        pixels = np.asarray(Image.open(path).convert("RGBA"))
        for rgb in np.unique(pixels[pixels[:, :, 3] > 0][:, :3], axis=0):
            out.add(tuple(int(v) for v in rgb))
    return out


def contact_sheet(pack_dir, out, scale=3, background=(200, 196, 190)):
    """Every option of every choice applied to the pack's preview, for review.

    One row per choice; the first cell of each row is the default look.
    """
    import json
    from pathlib import Path
    import numpy as np
    from PIL import Image
    pack_dir = Path(pack_dir)
    pack = json.loads((pack_dir / "pack.json").read_text())
    preview = Image.open(pack_dir / pack["identity"]["preview"]).convert("RGBA")
    rows = []
    for choice in pack.get("appearance", []):
        cells = []
        for option in choice["options"]:
            pixels = np.asarray(preview).copy()
            for source, target in option.get("recolor", {}).items():
                s = tuple(int(source[i:i + 2], 16) for i in (1, 3, 5))
                t = tuple(int(target[i:i + 2], 16) for i in (1, 3, 5))
                match = ((pixels[:, :, 0] == s[0]) & (pixels[:, :, 1] == s[1])
                         & (pixels[:, :, 2] == s[2]) & (pixels[:, :, 3] == 255))
                pixels[match, :3] = t
            cells.append(Image.fromarray(pixels))
        rows.append(cells)
    if not rows:
        raise SystemExit(f"{pack_dir} declares no appearance choices")
    width = max(len(r) for r in rows) * preview.width * scale
    sheet = Image.new("RGB", (width, len(rows) * preview.height * scale), background)
    for y, cells in enumerate(rows):
        for x, cell in enumerate(cells):
            big = cell.resize((cell.width * scale, cell.height * scale), Image.NEAREST)
            sheet.paste(big, (x * big.width, y * big.height), big)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"{out}: " + "; ".join(
        f"{c['label']}: " + ", ".join(o["label"] for o in c["options"]) for c in pack["appearance"]))


if __name__ == "__main__":
    import sys
    contact_sheet(sys.argv[1], sys.argv[2])
