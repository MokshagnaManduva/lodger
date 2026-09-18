# Klien — art bible

Locked reference for every cell in the pack. Everything inherits identity, palette and
proportions from the canonical sprite. Change this file only with a deliberate decision,
because changing it invalidates art already produced.

## Canonical cell: `r1c0` (row 1, leftmost)

Chosen for **face readability at 96 px**, not for having median proportions.

The earlier pick was `r0c1`, on the grounds that its head:body ratio (0.479) sat closest
to the median of the six reference cells. That reasoning was wrong. There is no
conformance work to minimise — exactly one sprite is authored by hand and everything else
is generated from it — so the median buys nothing. What does matter is that at a ~9.6:1
downscale the eyes get about 3 px, and `r0c1`'s half-lidded eyes collapse into a dark
smear. `r1c0` has open eyes with visible sclera and iris and is the clearest face of the
six. Since this sprite is the identity reference for PixelLab's *fixed head* setting, its
face is the single most load-bearing detail in the project.

Reference contact sheet: `sketches/compare.png`.

## Absolutes at native resolution

All values in logical pixels inside a **128 x 128** cell.

| Measurement | Value |
|---|---|
| Cell | 128 x 128 |
| Figure height (hat top to sole) | **96** |
| Figure width (bbox, arm extended) | **58** for the approved idle (original target: 53) |
| Ground line (sole contact) | **y = 120** |
| Hat top | y = 24 |
| Face band (hairline to chin) | y = 52..81, height 30 |
| Widest torso row | y = 86, width 43 |
| Head block (hat top to chin) : total | **0.60** |
| Bare head (hairline to chin) : total | 0.31 |
| Body centre line | x = 64 |

Source-art check: `r1c0` measures 934 px tall with a skin-region proxy of 467 px
(`Docs/reference-audit.md`), a 9.73:1 downscale to 96 px.

Idle milestone decision, 2026-09-15: retain the user-approved 58px silhouette
(`idle-v2/art/rest.png`, x=35..92). Compressing it to 53px would change the approved
face and costume. The 96px height, 128px cell, x=64 centre and y=120 ground boundary
remain fixed. Motion variations inherit this canonical native sprite.

## Palette

`palette.gpl` — **26 colours**, extracted by `packtool palette` and locked.

Selection is not a plain median cut. On this character the suit, cape and hat dominate by
area, and a population-driven cut spends a dozen slots on indistinguishable near-blacks.
The extractor over-segments, then selects greedily on perceptual separation weighted by
population, with two hard floors: a minimum Oklab distance **and** a minimum raw sRGB
distance. The second floor is necessary because Oklab's cube root over-separates near
black — `#000000` and `#010102` read 0.07 apart in Oklab while being identical on screen.

Regenerate with:

```bash
python3 Tools/packtool/packtool.py palette Packs/klien/reference/klien.png --colors 26
```

## Known gaps the hand pass must close

These are not defects in the tool. They are things the reference does not contain.

1. **The suit has no value separation.** At 96 px the cape, waistcoat and trousers merge
   into one black mass, because the source's blacks are already nearly identical — the
   distinction is carried by soft gradients that do not survive a 9.6:1 reduction. The
   hand pass must **invent** two or three value steps (`#0B0B0C`, `#1D1A22`, `#2C2A2D`
   are available) so the cape edge and the legs read as separate forms.
2. **The cane must be lifted onto its own layer.** It survives the downscale as a 1 px
   line with a visible pommel, which confirms it is viable as a `socket` attachment —
   but in the reference it is fused to the body.
3. **Hair spikes leave isolated pixels** around the hat brim; they need to be either
   connected or removed.
4. **The raised hand reads as a detached blob** and needs a connecting wrist pixel.
5. Cape-fold shading, the hat's specular band and the leaf's woven texture do not survive
   and should not be attempted at this size. The sprite is a reinterpretation, not a
   reduction.

## Attachment art is drawn in place

The cane and the dumpling are each authored in a **full 128x128 cell**, drawn where
they belong relative to the body at the clip's first frame. The `hand` and `orbit`
anchors then supply *motion only* - the part moves by `anchor[frame] - anchor[0]`.
Nothing declares a pivot.

This matters for the dumpling in particular: do not draw it at the cell origin and
expect `rest` to push it into position. Draw it floating beside him, and leave `rest`
near zero. `maxOffset` is capped at 12px because the engine pads the pet window by
`rest + maxOffset` to avoid clipping the drift, and what the compositor draws every
frame grows with that area - 48px of drift made the window 3.1x the cell.

## The floating item

`sketches/item/r0c1.png` — 22 px tall in a 32 x 32 cell, 11 palette colours. Leaf tips,
wrapping cord and the leaf body all read at this size, so no scale change is needed.

Reference measurements across cells (`Docs/reference-audit.md`) show the item's own height
varying 157-189 px and its anchor drifting ~8 points of figure height. Neither is
reproduced here: the item is authored once, and its position comes from the per-frame
`orbit` anchor plus the `float` bind's spring, never from the art.

## Active sun-emblem polish — 2026-09-16

The floating dumpling is superseded in v0.4.0. `sun-emblem.tiff` is the owner's
reference (copied unchanged from the repository root). Its flared gold silhouette,
tapered base and central sun seal are reinterpreted as a native 12×14 glyph, with
3px/8px edge-turn variants. `sun-emblem-palette.gpl` adds five gold colors without
changing the 26-color body palette. No glow, resampling of the body or soft alpha.

The emblem rests on the free palm: center seven pixels above the palm anchor.
A 1.2-second standing toss raises it 20px, flips it, then catches in the same hand.
All other poses hold it; no floating spring, bob or squash is installed. The
editable emblem layer is composited with body/cane for exact runtime timing.

Authored knee/foot x coordinates are compressed to 70% of their former distance
from x=59; hip anchors, y contacts, upper-body proportions and idle archive remain
unchanged. Walk foot centers are at most 20px apart. Seated/landing/held knees use
the same narrower construction. Earlier dumpling notes above describe the archive.


Crouch follow-up: lowered/held poses now use explicitly authored compact legs
instead of the 70% x-scaling rule. Seated feet center at x=54 and x=65, knees at
x=54 and x=64. Lower-leg strokes are 5px and shoes 9px; coat tails stop at y=115.
The lowering transition closes the near foot inward gradually; seated breathing
and sleep preserve identical soles. Walking retains its earlier authored stride.
