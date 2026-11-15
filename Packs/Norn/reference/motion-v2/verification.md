# Six-frame motion verification · 2026-09-22

Pack version: **0.2.0**. Changes are three six-pose texture pages and clip timing;
the behavior graph and engine are unchanged.

## Completed

- `make norn-animations`: all **seven artwork/mask tests** pass.
- `make norn-test`: seven art tests and **59 actual Swift Director checks** pass.
- Strict validation: zero errors and zero warnings.
- Generic export to `build/Norn.pack`: passes with one explained warning. Held
  soles move four pixels as her boots dangle, entirely above the floor; generic
  ground-drift reporting does not distinguish an airborne clip from a grounded one.
- All twelve native state/clip/mask lookups pass. `asleep`, `held` and `falling`
  each report six frames and a corresponding six-cell hit mask.
- All twelve runtime clips have at least two distinct rendered poses. The new
  sleep, held and fall clips each have six distinct character drawings, verified
  independently of the floating root's pixels.
- All four atlases share at most 32 opaque colors, with binary alpha and safe
  margins. Every mask pixel matches its rendered silhouette; runtime gallery
  texture selection, cell order and timing match the pack manifest.
- The original `atlas/body.png` remains byte-identical to v0.1.0 (SHA-256 compared
  before and after compilation). Original source and draft sheets are unchanged.
- Safari directly loaded all twelve gallery cards, with **06-frame** sleep/held/
  fall counters and the correct 4.80 s / 1.32 s / 0.70 s timings. Sleep playback,
  pause, manual stepping through frame six and wrap to frame one were exercised.
  Sleep, held and falling at 2× were visually reviewed on the paper stage.
- JavaScript syntax checks pass for the shared player and generated runtime data.

## Native six-frame sleeping smoke test

The isolated fixture `build/norn-verification/sleep-v2` uses the exact final sleep
atlas, six-frame sleep clip and mask, with a single quiescent state and a
system-wake interrupt. It excludes pointer interactions to check scheduling.

```sh
./build/Lodger.app/Contents/MacOS/Lodger --pack build/norn-verification/sleep-v2 --soak 12
```

The run lasted 12.6 seconds (more than two 4.8-second loops) and reported:

- Zero live state timers and zero scheduler wakes.
- Zero display-link starts or ticks; no pointer monitor.
- 0.0217 CPU seconds, projecting 6.21 CPU seconds/hour.

This demonstrates that a multi-frame sleeping clip does not need an animation
timer in Lodger. A short process-CPU sample is not an energy certification;
longer quiet-machine and whole-system measurements remain open. Logs are at
`build/norn-verification/sleep-v2.log`.

## Remaining scope

Generated poses retain some hair/prop shape variation, especially at transitions
between the new sheets and the original body atlas. No new live drag/fall/landing
acceptance or mobile browser regression was performed. Those interactions retain
the existing behavior graph, with Director coverage and current masks verified.
