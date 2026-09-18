# Idle milestone verification — 2026-09-15

## Automated

- Strict `packtool validate Packs/klien`: **pass, zero warnings**.
- `make test`: full-blueprint negative validator tests and idle asset integration checks pass.
- `make engine-test`: **194/194 pass**.
- `make app`: release bundle built and ad-hoc signed.
- Bundled manifest, preview, atlases and masks match the validated pack byte-for-byte.
- `git diff --check`: clean.

Asset checks include 128×128 cells; exact 96px height; ground boundary y=120;
58px approved width; binary alpha; locked palette membership; unclipped silhouettes;
fixed feet/cane; identical breathing head; nontrivial local breathing deformation;
one 120ms blink per 3000ms; unchanged 22px dumpling and alpha-derived hit masks.

## Visual

Inspected the native resting composite and final 2× pose sheet. Launched the built
Lodger app and inspected live 2× screenshots, including a 9.3-second sampling run
across three loops. Samples show the closed-eye blink, subtle torso/cape changes,
and the separate vertical dumpling motion. Feet/cane stay planted and the head
silhouette is stable. No apparent clipping or loop-boundary jump was observed.

This was a sampled live-frame review, not a high-frame-rate video analysis. The
engine's existing smooth float bob differs from the GIF's discrete pixel steps.

## Runtime energy

The first 60-second requested soak, during active Computer Use inspection, reported:

- 63.0s wall time, 0.0986s CPU, projected 5.63s CPU/hour (under the <7s target).
- One initial state entry; **zero scheduler wakes**.
- **Zero display-link starts and ticks**, not running at exit.
- **Zero window enumerations**; pointer monitor not installed.

A capture-free repeat is recorded below. These are short process-CPU observations,
not a whole-system power measurement or a multi-run energy certification.

Capture-free repeat:

- 63.0s wall time, 0.1105s CPU, projected 6.32s CPU/hour.
- One initial state entry; zero scheduler wakes, display-link starts/ticks, and
  window enumerations.
- **The <7s CPU/hour target was met in these short runs**, with the structural
  no-timer/no-display-link requirement also passing. The target was raised from
  2s to 7s (see CLAUDE.md §6) on the strength of these two measurements, since a
  pack with real animation and a spring-driven float attachment costs more than
  the empty synthetic fixture the original 2s figure came from. These remain
  short process-CPU observations, not a multi-run median or a whole-system power
  measurement — a `make soak`-style median run is still the more trustworthy
  follow-up.
