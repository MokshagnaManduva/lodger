# Animation polish verification · 2026-09-25

Pack version **0.3.0**; 58 stored cells, seven texture/mask pages, 12 clips and
12 states. Behavior graph unchanged; clip artwork, routing and durations updated.

## Passed

- Eight artwork/mask acceptance tests. All seven pages use binary alpha and the
  original shared palette (at most 32 opaque colors); silhouettes have safe margins.
- Every hit-mask bit matches the corresponding rendered alpha pixel.
- Every played walk/greeting/sit/read/stand pose ends at y=114.
- Exact rendered endpoints agree for greeting → idle, sit → read, read → stand
  and stand → idle. Sitting and standing contain no reused landing-crouch frame.
- Walk acceptance now examines the actual runtime clip, not the archived body
  atlas's original four legs. Four distinct lower-body drawings are present.
- 59 checks using the actual Swift Director pass, including exact finite clip
  duration, grab/release/land, click/hover/walk, rest/wake and low-power guards.
  Swift compilation required the already-approved `make norn-test` escalation
  because its external module-cache writes were denied inside the sandbox.
- Strict validation: zero errors, zero warnings.
- `make norn-pack` exports successfully. Its one warning is the existing held
  soles varying by four pixels above the floor; new grounded clips add no warning.
- Existing native app's `--state NAME --headless` resolves all 12 states and
  decodes the selected texture masks. This is loader coverage, not desktop input QA.
- `node --check` passes for runtime data and the shared gallery player.
- Safari direct-file preview loads 12/12 cards, with revised counts/timings:
  walk 4 / 0.72 s, greeting 13 / 2.30 s, sit 6 / 1.09 s, stand 6 / 1.20 s.
  Pause and scrub controls were exercised; transfer/seated silhouettes were inspected at 2×.

## Limits

The new walking source required repeated leg corrections; only four selected
drawings are used. No six-frame gait quality claim is made. Heads/props are
registered consistently, but generated contours still vary between source sheets.
Sleep-to-stand and arbitrary action interrupts can still change drawings abruptly.
No new live desktop drag/fall acceptance, mobile-browser regression or energy
certification was performed. Original character rights remain pending.
