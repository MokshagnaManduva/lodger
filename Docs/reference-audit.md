# Reference audit — `Packs/klien/reference/klien.png`

Measured 2026-09-05. Reproduce with:

```bash
python3 Tools/packtool/audit_reference.py Packs/klien/reference/klien.png
python3 Tools/packtool/audit_cells.py     Packs/klien/reference/klien.png
```

**Conclusion: the reference is not pixel art and cannot be turned into sprites by any
automated extraction.** It is a continuous-tone render imitating pixel art. The art must be
re-authored at native resolution (see `CLAUDE.md` §7). This document exists so that no future
session re-litigates that, or wastes time building a sprite extractor.

---

## 1. Structural measurements

| Property | Measured | True pixel art |
|---|---|---|
| Dimensions / mode | 2048x2072, RGBA | — |
| Alpha channel | present but **100% opaque** — 1 distinct value | transparent background |
| Unique RGB values | **60,154** | 8-64 |
| Background purity | `#FFFFFF` 28.59%, `#FEFEFE` 12.21%, `#FFFFFD` 5.42%, `#FEFEFC` 2.50%, `#FDFDFD` 2.04% | one flat key colour |
| Mean horizontal same-colour run | **1.42 px** (76.4% of runs are 1 px, 16.7% are 2 px) | approximately the upscale factor |
| Grid-period score, columns | **1.362** at period 20 | ~N for an N-times upscale |
| Grid-period score, rows | **1.295** at period 22 | same period as columns |

The grid score is the fraction of edge energy landing on a regular lattice, normalised so that
**1.0 means no grid at all**. Both axes score ~1.3, and they disagree on the period (20 vs 22).
There is no consistent pixel grid and no consistent phase.

### What this rules out

- **Background keying.** The background is noisy; a colour-key on `#FFFFFF` would leave 71% of
  it behind. Use a *tolerance flood from the image border* instead.
- **Nearest-neighbour downsampling.** There is no integer factor to downsample by.
- **Palette extraction.** 60k colours must be reduced by median-cut and then hand-corrected,
  not read off.

## 2. Per-cell consistency

Six cells in two rows. Segmentation splits the green floating item from the figure by hue.

| Cell | Figure height (px) | Head proxy (px) | Head : body |
|---|---|---|---|
| row 0, cell 0 | 921 | 408 | 0.443 |
| **row 0, cell 1** | **923** | **442** | **0.479** |
| row 0, cell 2 | 923 | 439 | 0.476 |
| row 1, cell 0 | 935 | 467 | 0.499 |
| row 1, cell 1 | 935 | 480 | 0.513 |

Overall height is nearly constant (921-935 px) — that is *not* the problem. **Proportions
drift**: the head:body ratio spans 0.443-0.513, a ~16% spread. Row 1 is a visibly
bigger-headed chibi than row 0. Frames mixed across rows would pop.

*Caveat:* the head proxy is the skin-tone bounding box, which also catches the raised hand, so
treat the magnitude as approximate. The direction and the row-to-row split are solid.

### Floating item

| Cell | Item bbox height (px) | Item centre, as fraction of figure height from head top |
|---|---|---|
| row 0, cell 0 | 157 | 39.3% |
| row 0, cell 1 | 186 | 36.8% |
| row 0, cell 2 | 189 | 36.8% |
| row 1 (all)   | 186-188 | 30.9% |

Two independent defects:

1. **The anchor drifts** by ~8 points of figure height between rows — about 78 px here, or
   **~8 px on a 96 px sprite**. Very visible in motion.
2. **The item's own scale drifts** by ~20% within row 0, and the top-left item is **missing the
   leaf tips** present in the other five. It is a different drawing, not a different pose.

**This is the evidence for authored-per-frame anchors and an anchor-continuity linter**
(`CLAUDE.md` §7, Stage 6). Inferring an anchor from the art is exactly what produces this.

## 3. Segmentation notes

- Foreground coverage at threshold 18 is 44.3%.
- The item's dark outline is not green, so it classifies as body and contaminates the figure
  bounding box on the left.
- In row 1, adjacent figures' bounding boxes touch: column-projection splitting merges cells 0
  and 1 into `x[34,1361]`. Grid-slicing and column-projection slicing both fail on this sheet.

## 4. What the reference is good for

Art direction, and only that: silhouette, costume, palette source, and the canonical
proportions. **Row 0, cell 1** is the canonical cell (head ratio 0.479) — everything else is
conformed to it.
