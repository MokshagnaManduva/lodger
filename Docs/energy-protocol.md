# Energy protocol — measured baselines

First run: 2026-09-06, M5 MacBook Air (16 GB), macOS 26.6.2, release build,
`Tests/Fixtures/test.blinker`. Rerun with `make soak`.

These replace the estimates that were in CLAUDE.md §6. Treat them as a floor to
defend, not a result to celebrate — they were taken on a synthetic 24×24 pack with
no behaviour, no physics and no input monitor. Every one of those will add cost.

## Claim 2 verified: animation is render-server resident

The load-bearing claim of the whole architecture. Verified directly rather than
argued: the process was sent `SIGSTOP` — it cannot execute a single instruction —
and the window was captured repeatedly while stopped.

| Capture pair | Process state | Pixels changed |
|---|---|---|
| f0 → f1 | running | 68.4% |
| s0 → s1 | **stopped (`T`)** | 55.2% |
| s1 → s2 | **stopped (`T`)** | 68.4% |
| s0 → s2 | **stopped (`T`)** | 69.1% |

The frames kept advancing at the same magnitude with our code frozen. A
`CAKeyframeAnimation` on `contentsRect` with `calculationMode = .discrete` runs in
the render server; the app contributes nothing per frame.

Visual record: `render-server-proof.png`. Reproduce with `make proof`
(needs Screen Recording permission).

## Our process: CPU per idle hour

100-second soaks, two rounds each. The soak blocks in `mach_msg` via a single
deferred wake — not `RunLoop.run(until:)`, which polls and would measure the
harness rather than the engine.

| State | Run 1 | Run 2 | Notes |
|---|---|---|---|
| `resting` (quiescent, no animation installed) | 1.30 s/hr | 0.63 s/hr | |
| `pulsing` (4-frame discrete keyframe loop) | 0.77 s/hr | 0.59 s/hr | |

**Target < 2 s CPU per idle hour: met, with room.**

The important reading is not the absolute number, it is that **the two states are
indistinguishable**. Running a sprite animation costs our process nothing
measurable versus showing a static frame — which is what render-server residency
predicts, and is the same fact the SIGSTOP test shows directly.

Total CPU per run is 17–38 ms over 105 s, so run-to-run variance dominates; in one
round the animated state measured *lower* than the static one. Do not read a
difference between these two columns. Do treat a jump to, say, 10 s/hr as real.

## Read this before quoting any CPU number

Our process uses **20-40 ms of CPU per minute** when idle. At that magnitude a single
soak measures the machine's mood, not the engine.

Worked example, from getting this wrong. A 90-second run of the four-part pack
reported 12.2 s/hr and looked like a 20x regression against an earlier 0.59 s/hr
reading. It was not. Three repeated 60-second runs of each configuration:

| Configuration | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| four parts (body, socket, float, overlay) | 0.043 s | 0.025 s | 0.023 s |
| one part (`test.blinker`, smaller window) | 0.019 s | 0.021 s | **0.311 s** |

The worst outlier - 15x the median, and the one that would have been read as the
regression - came from the *simpler* configuration. Multi-part rendering costs
slightly more than single-part, as expected, and the difference is far below the
noise floor.

A later 5x45s sweep, taken while the machine was under load, was worse still:
`test.blinker` 1.43 / 1.49 / 1.47 / 1.56 / **19.52** s/hr, and `socketed.pack`
7.08 / 17.94 / 8.70 / 1.54 / **18.51** s/hr. The clean runs cluster near 1.5 s/hr and
the rest is contention. **These figures are not a pass or a fail - they are evidence
that the measurement needs a quiet machine.** Rerun with nothing else running before
treating any of it as a baseline.

**Therefore: never quote a single soak.** `make soak` runs each configuration five
times and reports the median and the spread. Treat a change as real only if the
medians separate by more than the spread, or rerun on a quiet machine.

## The live state machine

The Director, Scheduler and pointer monitor running together, driving real state
transitions. `test.blinker` starts in `pulsing`, times out, and settles into
`resting`, which is quiescent.

| Scenario | Duration | Transitions | Scheduler wakes | CPU per idle hour |
|---|---|---|---|---|
| `resting` (quiescent), pointer monitor installed | 120 s | 2 | 1 | 0.59 s |
| `socketed.pack` cycling every ~3 s | 60 s | 18 | 18 | 1.42 s |
| four parts, quiescent, median of 3 | 60 s | 2 | 1 | **~1.4 s** (spread 1.3-2.4) |
| one part, quiescent, median of 3 | 60 s | 2 | 1 | **~1.2 s** (spread 1.1-17.8) |

Single-run figures in the first two rows are kept for the record but should be read
as "somewhere in the low single digits", not as precise values.

The second row is a deliberately hyperactive pack — a state change every three
seconds, all day — and it still sits under the 2 s target. The first row is the
realistic all-day case, and on entering the quiescent state the scheduler's live
timer count drops to **0** and stays there.

Note the wake accounting: 18 transitions, 18 wakes. Exactly one scheduled wake per
state, never a repeating tick.

## Pointer path: 21 ns per mouse-move event

The one thing running at a rate the engine does not control, so it needs a number.
`make bench`, 2,000,000 samples against a 128×128 mask:

| Sustained event rate | CPU per hour |
|---|---|
| 60 /s | 0.0045 s |
| 120 /s | 0.0090 s |
| 500 /s | 0.0377 s |

A ceiling, not an estimate: a real session moves the cursor a fraction of the time.
The alpha hit test is a single array lookup, so per-pixel hit testing costs
essentially nothing — which is what made it affordable to own hit testing rather
than trust the window server.

**Caveat on the soak numbers above:** they were taken in a background session where
the cursor never moved, so the pointer monitor never fired. This benchmark is what
bounds that gap.

## WindowServer: not measurable on this machine

Our animations are composited in `WindowServer`, so a change that moves cost from
us to it is not a win. It has to be watched.

It could not be measured here. `WindowServer`'s own idle baseline, sampled over
identical 30-second windows with nothing of ours running, was **6.95 s, then
7.57 s** — a ±0.6 s (±2 percentage point) drift. Our measured deltas (8.10 s and
8.00 s) sit inside that noise.

**This is an open measurement, not a passed one.** To close it, rerun on a quiet
machine: no browser, no other animating apps, display awake and untouched, several
alternating 60-second samples of baseline and pet.

## Not yet measured

- **Idle wake-ups.** Needs `sudo powermetrics --samplers tasks --show-process-wakeups`
  and `sudo timerfires -p <pid>`. Both need a password, so they were not run
  automatically. The engine installs no timer in a quiescent state by construction,
  and `lodger-selftest` asserts that a single-frame clip installs no animation at
  all — but the syscall-level confirmation is outstanding.
- **Package power delta** (`sudo powermetrics --samplers cpu_power,gpu_power`).
- **Resident memory** (`footprint -p <pid>`).

## Commands

```bash
make soak                  # 100s per state, our CPU only
make proof                 # SIGSTOP render-server verification
./Engine/.build/release/lodger --pack <dir> --state <name> --soak 100

# need sudo, run by hand
sudo timerfires -p <pid>
sudo powermetrics --samplers tasks --show-process-wakeups --show-process-energy -i 5000 -n 12
sudo powermetrics --samplers cpu_power,gpu_power -i 1000 -n 60
footprint -p <pid>
```
