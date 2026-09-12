# What's left

Audited 2026-09-12 against the code, not from memory. Grouped by whether it blocks
the thing working.

> **Update 2026-09-13:** item 2 below is done — all 24 declared events are now emitted,
> and the idle route into the quiescent state works. Items 1 and 3 stand.

## Blocking

**1. Klien has no art.** 18 clips referencing 47 cells, 14 states, 4 parts — all
declared, none drawn. `PackStore.load` now correctly refuses the pack and the menu
says why. Everything in the pipeline downstream of §7 Stage 2 is waiting on this.
It is the long pole and it needs a human.

**2. ~~Fourteen of the twenty-three declared events are never emitted.~~ Done.**
All 24 are emitted now. Observers are installed only for what a pack's reachable states
actually ask for, and `app.occluded` additionally stops the animation rather than just
reporting it. The only timer is `IdleWatcher`, which self-corrects rather than samples.

**3. There is no horizontal flip anywhere.** `mirrorable`, `mirrorWithBody` and
`facing: "toPointer"` all decode and are then ignored, so the pet walks left and
right while always facing the same way. Very visible, and cheap to fix.

## Declared in the format but inert

The schema and `Docs/PACK_FORMAT.md` describe these; the engine reads them and does
nothing with them. Each one is the format telling a pack author a lie.

- `orientFrames` — discrete socket rotation
- per-part `hitTest` — the hit mask only ever uses the body texture, so Klien's
  floating dumpling is not clickable
- the `float` bind's `lag` — `Spring` has no lag term
- `sounds` — no audio API is used anywhere in the project
- `tuning` — the app resolves the knobs and stores them, but nothing applies them;
  `liveliness` in particular is documented as scaling behaviour on battery and does not

## Missing tooling

- `packtool generate` — scripted PixelLab runs, so generation is reproducible
- `packtool preview` — contact sheets with anchor traces, to catch drift without
  launching the app

## Built but unverified

- **The `AXObserver` perch path.** Accessibility is not granted on this machine, so
  `attach -> .attached`, move re-seating, and live `perch.lost` have never run. The
  policy around them is tested; the plumbing is not.
- **`WindowServer` cost.** Its idle baseline drifts ±2 percentage points here, so the
  compositing side of render-server locomotion is accepted on reasoning, not evidence.

## Distribution

- Developer ID signing and notarisation. The ad-hoc signature in `Scripts/bundle.sh`
  runs locally but is not stable across rebuilds, so a granted Accessibility
  permission needs re-granting after each build.
- Sparkle updates.
- A settings window. The menu bar carries the toggles; the `tuning` sliders have
  nowhere to live yet.
- An app icon, and a decision on Klien's licence (`CC-BY-NC-4.0` is still the
  placeholder I typed).

## Suggested order

1. **Events** — biggest honesty gap, no polling required, unlocks the quiescent path
   the whole energy argument rests on.
2. **Horizontal flip** — small, very visible.
3. **Klien's art** — yours, in parallel with 1 and 2.
4. Per-part hit testing, `orientFrames`, spring `lag`, `tuning` application.
5. Audio.
6. `packtool generate` / `preview`.
7. Signing, notarisation, Sparkle, settings window.
