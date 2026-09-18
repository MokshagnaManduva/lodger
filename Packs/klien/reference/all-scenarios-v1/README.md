# Klien — complete scenarios and focused polish

Current active pack: **v0.4.0**, 56 named poses, 19 body clips, 18 runtime states.
The runtime default is 1×, half the former 2× width and height.
Open `gallery.html` for native/2× animation previews and both walking directions.
The directory name is retained to preserve existing links.

## What changed

- Replaced the dumpling with a native 12×14 gold sun emblem based on the supplied
  `../sun-emblem.tiff`; five colors in `../sun-emblem-palette.gpl` extend the locked
  26-color body palette. The reproducible glyph lives in `animate_klien.py`.
- The free hand holds the emblem in all poses. A 1.2-second toss is occasionally
  chosen after standing idle (weight 15 taken from idle's former weight 40).
  It rises 20px, turns edge-on, descends, catches and recovers to the same hold.
- Narrowed knees/feet about the hip center; walking foot-center separation is at
  most 20px, down from 28px. Added hat-tip hand travel and smoothed seated lowering.
- No runtime float, bob or dumpling squash. The cane and emblem are baked into the
  body atlas for synchronous playback; their source layers remain editable.

## Coverage and retained limitations

Idle, left/right walk, front-facing turn, watching, hat tip, startle, held,
falling, landing, sitting/perching, sleeping/waking, posture transitions and toss.
Turnaround and distinct dangling-leg perching are deferred. No sound added.
Pose playback is not a substitute for permission-granted Accessibility testing.

## Files

- `frames/`: combined 128×128 frames.
- `layers/body/`, `layers/cane/`, `layers/emblem/`: exact reassembly layers.
- `art/`: composite body/cane strips and native sun-emblem glyph.
- `frames.json`: order, timings, palm/emblem coordinates and leg joints.
- `anchors/body.json`: authored cane-hand and emblem centers.
- `sheets/`, `previews/`, `gallery.html`: review artifacts; finite actions repeat.
- `guides/`: retained pose studies from the first full pass, not the new emblem.
- `pack.json`: source manifest; `../../pack.json`: runtime manifest.
- `verification.md`: checks, measurement results and remaining limits.

The approved head, hat, body colors, 96px standing height and ground boundary
at y=120 remain. The original idle-v2 files and blueprint are preserved. The toss
uses the original standing lower body to avoid a stance pop at entry/exit. Its
interrupt routes match idle; destination poses immediately hold the emblem again.
Hand travel in toss/lowering clips has an explicit 10px anchor-jump allowance;
other clips retain the normal 8px continuity check.

```sh
make klien-animations
make test
make engine-test
make app
python3 Tools/packtool/verify_klien_runtime.py --behavior --showcase
python3 Tools/packtool/verify_klien_runtime.py --measure
```


### Crouch correction

The follow-up pose pass replaces the scaled splayed squat with authored knees
above the feet, 5px lower-leg strokes and 9px shoes. The stance closes gradually
while lowering to 11px foot-center separation, with identical planted soles in
seated breathing/sleep. Coat tails stop above the soles instead of spreading
across the ground. Landing and held poses use the same compact leg treatment.
