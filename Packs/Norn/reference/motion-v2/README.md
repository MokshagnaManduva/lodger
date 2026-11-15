# Norn · six-frame motion loops

Generated with the built-in imagegen tool on 2026-09-22, using the original
runtime lifecycle sheet as the identity and costume reference. Each source sheet
contains six distinct drawings in a 3 × 2 layout.

| Motion | Source artwork | Exact generation prompt | Compiled runtime atlas |
| --- | --- | --- | --- |
| Sleep | [sleep-sheet.png](sleep-sheet.png) | [sleep-prompt.txt](sleep-prompt.txt) | [sleep.png](../../atlas/sleep.png) |
| Held | [held-sheet.png](held-sheet.png) | [held-prompt.txt](held-prompt.txt) | [held.png](../../atlas/held.png) |
| Falling | [fall-sheet.png](fall-sheet.png) | [fall-prompt.txt](fall-prompt.txt) | [fall.png](../../atlas/fall.png) |

Edit the `*-registration.json` files to adjust source rectangles and placement.
Compilation uses 128 × 128 cells and the original body's locked palette. The
original body PNG stays byte-identical. Source sheet bytes stay intact.

Sleep soles are registered at y=114. Held soles deliberately move between y=106
and y=110 as her boots dangle, producing one expected generic ground-drift warning
on export. Falling poses share the y=114 ground reference while knees, hair,
apron and leaves move within each cell; the engine supplies actual downward motion.

Timing and runtime routing are authored in
[`../runtime-v1/pack.source.json`](../runtime-v1/pack.source.json). Sleep loops in
4.80 seconds, held in 1.32 seconds, and falling in 0.70 seconds. The initial
single-frame versions are no longer used by these clips. All runtime clips have
at least two distinct poses; these three each have six.

See [verification.md](verification.md) for checks and remaining limits.
