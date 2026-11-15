# Runtime milestone verification · 2026-09-22

## Completed checks

- `make norn-animations`: source compilation and six artwork acceptance tests pass.
- `make norn-test`: six artwork tests and **59 Swift Director checks** pass.
  The Swift runner compiles the actual Pack, Guard and Director sources, outside
  the engine target. Its checks cover grab from every applicable state,
  release/fall/landing, click/double-click, hover, walk-to-rest, system sleep/wake,
  boolean low-power guards, exact finite-clip completion times and quiet states.
- Strict `packtool validate`: **zero errors, zero warnings**.
- `make norn-pack`: generic author-tool export to `build/Norn.pack`, **zero
  warnings**. Export contains runtime PNGs, hit mask, manifest, license and credits.
- Existing `build/Lodger.app/Contents/MacOS/Lodger --pack Packs/Norn --state NAME
  --headless`: all **12 states** resolve their clips/textures and decode the 16-cell
  mask. This is loader coverage; this CLI flag reports the requested state rather
  than demonstrating its visual behavior.
- `node --check Packs/Norn/gallery.js` and `runtime.js`: pass.
- Safari direct `file://` load: all **12/12 clips** ready, visible character preview,
  expected 1/3/4/5-frame counters and finite-action labels. Desktop header/layout
  visually reviewed. The original six-study gallery still loads. No new automated
  browser interaction/mobile regression run was performed in this milestone.

## Art acceptance

- One 512 × 512 RGBA atlas, 16 uniform 128 × 128 cells.
- Alpha is exactly 0 or 255. At most 32 opaque RGB colors shared across all frames.
- Each silhouette has an 8 px minimum safe margin and more than 2,000 opaque pixels.
- All grounded poses share an exclusive sole edge at **y=114**; the held pose is
  intentionally above that edge. No ground anchor is inferred at runtime.
- Four distinct lower-body drawings in the walk cycle; this is a mechanical
  distinctness check, not certification of ideal leg choreography.
- Independently decoded mask bits match every atlas alpha pixel, including the
  disconnected root and props; preview PNG matches runtime frame zero.
- Gallery cell order and timing match `pack.json`; runtime manifest matches its
  authored source. Native atlas and the source sheet were visually inspected.

The source is generated artwork, not a finished hand-pixeled master. Explicit
registration fixes uniform-cell cuts and ground drift; it does not eliminate all
head-size, pose or prop discontinuities. See the pack README for remaining work.

## Native scheduling smoke tests (not an energy pass)

An initial 15-second normal-pack run was interrupted by the physical pointer:
`idle → watching → inspecting → idle`. It reported two scheduler wakes and zero
display-link starts/ticks. It used 0.0776 CPU seconds over 15.7 seconds wall time,
projecting 17.73 CPU seconds/hour. It is not an isolated-idle measurement.

The final pack requests no `user.idle` or `pointer.idle` events: the current engine
arms such watchers pack-wide, including in quiescent states. Rest is instead
entered after a completed walk; sleep follows system notifications.

A temporary fixture at `build/norn-verification/idle` used the exact final atlas,
mask and idle clip with a single quiescent state and only a system-wake interrupt,
to exclude the physical cursor. Run:

```sh
./build/Lodger.app/Contents/MacOS/Lodger --pack build/norn-verification/idle --soak 20
```

Observed: zero live state timers, **zero scheduler wakes**, **zero display-link
starts/ticks**, and no pointer monitor. CPU was 0.0678 seconds over 21.0 seconds
wall time, projecting **11.62 CPU seconds/hour**, above the <7 target. This short
sample was taken during active development and does **not** meet or replace the
project's energy acceptance protocol. Longer quiet-machine measurements,
WindowServer/system power and normal-behavior acceptance remain open.

## Scope still open

Native launch was smoke-tested with the existing app binary. Full real-pointer
click/drag/release, render-server walking, mixed-display, sleep/wake and scaling
acceptance were not completed here. No engine source or bundled default was
changed, and no public distribution/license claim is made.
