## Display-size update

Owner-requested runtime scale changed from 2x to 1x: half the displayed width and
height, with the original pixel assets retained. Generator and active source/runtime
manifests agree. Existing energy measurements below were taken at the former 2x
scale; they are historical evidence, not fresh measurements at 1x.

## Follow-up: crouch correction

Redrew knees/feet for lowering, seated/sleep/perch, landing and held poses;
prevented coat tails from pooling into the foot silhouette. Reviewed regenerated
sitting and landing contact sheets. Strict pack validation and native-art checks
pass, including new knee-support, inward-lowering and stable-sole regression
checks. App rebuilt with the corrected atlas/mask. Engine scheduling and idle
frames are unchanged; earlier energy results below are retained, not rerun.

# Verification — sun-emblem polish (v0.4.0), 2026-09-16

## Checks and scope

- `make klien-animations`: 56 poses, 19 body clips, 18 states; strict validation
  passes with zero errors and zero warnings. Native-art acceptance checks pass.
- `make test`: validator, idle/art, scenario coverage and fixture checks pass.
- `make engine-test`: 192/192 checks pass.
- `make app`: release bundle built and ad-hoc signed. Existing compiler/linker
  warnings about PerchTracker's local variable and toolchain search paths remain.
- Built manifest, preview, body atlas and mask match the active pack byte-for-byte.
- All 18 states load through PackStore with valid clip/texture lookup.
- The deterministic live showcase completes every state, including the toss,
  returns to idle and records zero display-link starts/ticks. Its extra transition
  scheduling is review instrumentation, not part of the idle measurements.
- `verify_klien_runtime.py --behavior`: the actual engine Director completes the
  toss in 1.2 seconds, returns to idle, accepts all eight idle-equivalent interrupts
  at the airborne midpoint and rejects an out-of-range pointer-near event.
- Native tests verify start/end hold equality, 20px arc, edge-turn widths, stable
  toss legs/cane, palm contact in every non-toss pose, <=20px authored foot-center
  separation, both walking directions, exact three-layer reassembly, palette,
  binary alpha, canvas margins, hit masks and GIF duration totals.
- SHA-256 checks confirm all six archived idle-v2 art PNGs are unchanged. The
  supplied TIFF reference is copied byte-for-byte into the reference directory.

## Visual review

Inspected the complete poster, toss sequence, sitting transition and right-facing
walk sheet at 2×. Sampled the rebuilt app's rendering: held emblem, body identity,
compact stance and pixel edges read correctly. The emblem is a native pixel-grid
reinterpretation of the supplied gold reference, with a central seal and flared
silhouette; no body-image resampling or external generation is used for this pass.

The gallery repeats finite actions for review; the real toss is an occasional
weighted idle choice. Interrupted tosses switch immediately to the target pose
holding the emblem, rather than continuing an independent airborne object.

Full turnaround and dangling-leg perch are deferred. Owner art acceptance,
real mouse-driven toss interruption/drag testing and permission-granted perch
tracking remain separate review items. This is sampled visual review, not a
high-frame-rate recording of every transition. Engine checks now report that
Accessibility is granted on this machine; the actual perch tracking path has
still not been exercised as part of this art milestone.

## Isolated idle measurements

Three sequential requested 60-second process-CPU samples with actual shipped
atlas/mask bytes and autonomous scheduling removed:

| Run | CPU seconds per idle hour | Scheduler wakes | Display-link ticks |
|---|---:|---:|---:|
| 1 | 3.75 | 0 | 0 |
| 2 | 3.12 | 0 | 0 |
| 3 | 1.08 | 0 | 0 |
| **Median** | **3.12** | **0** | **0** |

Passes the <7 CPU seconds/hour target. Logs and JSON: `measurements-polish/`.
This does not establish normal autonomous behavior cost, WindowServer overhead,
resident memory or whole-system battery use. The one 1024×896 RGBA atlas decodes
to 3,670,016 bytes; no duplicate cane/emblem or obsolete dumpling atlas is shipped.

The prior milestone's results below are historical and retain their original
measurement scope. They are not measurements of the current emblem pack.

---

# Historical verification — first full scenario pass (v0.3.0), 2026-09-16

## Checks passed

- Strict pack validation: zero errors and zero warnings.
- `make test`: negative validator tests, approved-idle invariants, and complete
  scenario checks pass. The original full blueprint remains the negative fixture.
- `make engine-test`: 192/192 checks pass on the current working tree.
- `make app`: release bundle builds and is ad-hoc signed.
- Runtime PackStore/clip lookup succeeds for all 17 active states.
- A deterministic in-app showcase visited all 17 states and reported zero
  display-link starts/ticks. It intentionally schedules transitions for review;
  it is not an idle energy measurement.

Native asset checks cover dimensions, binary alpha, palette membership, canvas
margins, floor contact, preserved walking head, six distinct leg configurations,
airborne leg tucks, planted landing, stationary shoes during seated breathing,
registered blinks, exact body/cane layer reconstruction, and GIF timing totals.

## Visual review

Inspected the all-scenario sheet, native overview and walking contact sheet.
Opened the animated gallery and inspected 2× previews. Reviewed live app samples
through held, falling, landing, sitting, drowsing and asleep poses. Runtime atlas
selection and independent dumpling motion read correctly in those samples.

The turning animation is a front-facing foot pivot/eye glance, with mirroring
handled by the existing engine; it is not a full rear-facing turnaround. Perching
shares the seated artwork. These are documented art refinements, not missing
scenario files. The new limb shading is simpler than the canonical costume.

This is sampled visual review, not exhaustive high-frame-rate video analysis.
Actual drag/fall/perch interaction paths are distinct from the deterministic pose
showcase. Generic motion tests pass; macOS Accessibility perch tracking remains
unverified, as documented before this work.

## Energy protocol

Target: **<7 CPU seconds per idle hour** (user-updated).
The CLI report now prints the same target. Three sequential requested 60-second
soaks use the actual runtime atlas and mask bytes with autonomous choices removed
from a temporary idle-only fixture. This isolates idle animation cost; it does not
claim that walking, interactions or frequent state changes cost the same as idle.
Raw logs and the median report are copied beside this document after completion.

### Results

| Run | CPU seconds per idle hour | Scheduler wakes | Display-link ticks |
|---|---:|---:|---:|
| 1 | 6.77 | 0 | 0 |
| 2 | 1.57 | 0 | 0 |
| 3 | 4.90 | 0 | 0 |
| **Median** | **4.90** | **0** | **0** |

**PASS against the updated <7s/hour target.** Raw logs and machine-readable results
are in `measurements/`. The spread (1.57–6.77) reinforces the existing documentation's
warning about short-run variance. This does not measure WindowServer or whole-system
battery use. The accelerated showcase's CPU is deliberately excluded: it schedules
state changes every few seconds and was used only for art/atlas selection review.

Runtime decoded atlas footprint: 3,407,872 bytes across body, dumpling and impact
atlases. Editable cane art is retained in source and omitted from runtime decoding.
