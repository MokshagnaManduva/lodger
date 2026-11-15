# Lodger

A macOS desktop companion: a small animated character that lives on screen, walks around,
reacts to the cursor, and idles quietly. The character is **not** part of this codebase —
it lives in a *character pack*, a folder of data. The engine renders packs and knows
nothing about any specific character.

If you are a future session reading this cold, read §1 and §2 before touching anything.
The two hard rules are there, and most bugs in this project will be violations of them.

## Current status

**2026-11-15 — development build; release incomplete.** Two characters are bundled:
Klien (0.5.0) and Norn (0.4.0, CC BY-NC 4.0 confirmed by the owner). Pack format 2 adds
pack-declared Settings controls: sliders (`scaleBy`, `weightBy`, event thresholds via
`{"knob": name}`) and toggles (read by the `flag` guard), plus the `controls.changed`
event. Format 1 packs still load. Klien has nine controls, Norn five; Norn's wandering is
off by default so her resting states stay quiescent. Design and plan:
`Docs/superpowers/specs/2026-11-15-norn-deployment-behaviour-controls-design.md`.
Two follow-on sub-projects are agreed but not started: (2) Settings redesign plus
app-level controls, (3) appearance variants (palette swaps plus prop options).
Recorded November 15: 349 engine checks with both packs (347 generic), 55 app checks,
92 Norn and all Klien Director checks, pack/art, separation and release checks passed.
Live desktop acceptance of the new controls has not been done.

**Earlier status, 2026-09-30.** Klien holds a small gold
sun emblem in his free hand and occasionally tosses it. The current art has compact
leg poses and revised hand transitions. Source: `Packs/klien/reference/all-scenarios-v1/`; rebuild with
`make klien-animations`. The approved `reference/idle-v2/` remains archived.

Core engine, menu/pack discovery, basic settings, staged imports, persisted size controls,
render-server walking, mirroring, per-part hit testing, spring lag, tuning application and
audio plumbing are built.
`orientFrames` was deliberately removed. The active idle CPU target is <7 s/hour;
measurement scope and results are recorded in `Docs/energy-protocol.md` and the
animation source's verification record.

**Current backlog:** `left.md`. Remaining work includes full turnaround and system interaction
verification, quieter energy measurements, final branding/licensing, signing/notarization and
updates. Klien is intentionally silent. Window perching was removed from the current runtime
and is documented only as a future idea.

Settings now has preview/metadata, removal to Trash, size/personality reset, volume and
referenced personality controls. Resize/switch/replacement preserves screen position;
failed/unrelated imports retain the running pet. Live controls/import/Trash and pointer
acceptance remain open; see `Docs/product-acceptance.md`. Imports enforce runtime
schema/assets and path containment (see
`Docs/pack-installation.md` for limits and recovery); generic `generate`
produces an incomplete scaffold and `preview` is static. Manual update checks only open a URL.
Hosted CI, production signing/notarization, automatic updates, and energy certification are open.
Recorded September 30: 30 app checks, 306 generic engine checks and pack/art checks passed.
A final scroll-origin adjustment followed that app run; rerun and rebuild before acceptance.
September 22 historically passed 308 engine checks including both packs and 19 release checks.
Quiet battery energy samples were deferred by the owner September 30; no new certification
was performed. Computer-use access to the isolated acceptance app was rejected.

```bash
make test              # validator and native-art acceptance checks
make engine-test       # engine checks (the runner reports the current total)
make app-test          # isolated Settings/import/controller checks
make klien-test        # Klien art and Director checks, including his controls
make norn-test         # Norn art and Director checks, including her controls
make release-check     # builds the app and verifies the bundled packs
make klien-animations  # regenerate active art, atlas, masks and gallery
make app               # local ad-hoc signed bundle
```

Characters are discovered in `~/Library/Application Support/Lodger/Packs/` and
the bundle. Invalid folders are named in the menu with their loading error.
The runtime loader enforces the embedded schema, semantic references, decoded assets and
contained paths. Imports replace by ID and preserve/report backups on restoration failure.
See `Docs/pack-installation.md` for limits and crash-recovery boundaries.

---

## 1. The two rules

### Rule 1 — The engine knows nothing about any character

If a string, number, filename, or behaviour specific to one character appears anywhere in
engine source, that is a bug, not a shortcut. This includes: sprite dimensions, frame
counts, animation names, state names beyond the fixed lifecycle set, attachment names,
colours, sound names, timing constants, "the dumpling", "the cane", "klien".

The reference character (`klien`) exists to prove the pack format. When something about him
cannot be expressed in a pack, **fix the format** — do not special-case the engine.

Test of the rule: delete every pack from disk. The engine must build, launch, and show an
empty state. Add a pack authored by someone whose art looks nothing like Klien — different
sprite size, no attachments, three states instead of fifteen — and it must run without a
recompile.

### Rule 2 — Idle cost is the top-priority feature

It outranks development speed and feature richness. This was stated explicitly by the
project owner: the app runs all day on battery, and idle cost should be as close to zero as
the platform allows.

Any always-running work — a timer, a poll, a display link, a redraw of unchanged pixels —
must be justified in a comment naming what it buys and why it cannot be event-driven.
"It was easier" is not a justification. §6 defines the budget and how to prove you are
inside it.

---

## 2. Architecture at a glance

```
+------------------------------------------------------------+
| App shell (AppKit, LSUIElement, .accessory activation)      |
|   - menu-bar item, native settings & pack manager            |
+------------------------------------------------------------+
| PetEngine                                                   |
|   PackLoader     manifest -> validated in-memory model      |
|   Stage          screens, edges, spaces, scale factors      |
|   Director       state machine: weighted next-state         |
|                  selection, guards, interrupts              |
|   Body           CALayer tree; one layer per part           |
|   Motion         locomotion + spring physics, display-link  |
|                  driven, only while not at rest             |
|   Input          global mouse monitor + alpha hit mask      |
|   Power          occlusion, sleep, low-power, battery       |
+------------------------------------------------------------+
| Character packs (data only - see Docs/PACK_FORMAT.md)       |
+------------------------------------------------------------+
```

**Stack: Swift + AppKit + Core Animation. Deployment target macOS 14.0.**
No SpriteKit, no Metal, no web view. The settings and pack-management UI uses native AppKit
controls so the Command Line Tools build remains independent of SwiftUI macro availability.

### Why — keep this reasoning, it is the whole design

- **Sprite animation runs in the render server, not in our process.** A
  `CAKeyframeAnimation` on `contentsRect` with `calculationMode = .discrete` steps a layer
  through atlas cells with no interpolation. Once the `CATransaction` commits, the
  animation is serialised to the render server and runs there — it keeps animating even
  with the app halted at a debugger breakpoint. **Install once, then be genuinely idle.**
  This is why AppKit + Core Animation beats SpriteKit (continuous render loop unless
  explicitly paused), raw Metal (we would own frame pacing — the thing we most want the
  system to own), and any web runtime.
- **A pack is inert data, never code.** Hardened Runtime — required for notarisation —
  blocks loading third-party signed code without `com.apple.security.cs.disable-library-validation`.
  Shipping executable packs means either weakening the app permanently or owning a script
  sandbox forever. It is also an efficiency rule: a pack that could run arbitrary
  predicates per frame could burn the battery, which contradicts Rule 2 as directly as it
  contradicts security.
- **We own hit-testing; we do not rely on the window server.** See §4.
- **No TCC prompts in the default configuration.** See §4.
- **Target distribution is a Developer ID-signed, notarized direct download — not Mac App Store.**
  Not sandboxed. This is what makes "installing a character means dropping in a folder"
  literally true: `~/Library/Application Support/Lodger/Packs/` is a real, openable,
  shareable directory. A sandboxed build would relocate packs into an opaque container and
  turn install into a security-scoped-bookmark import flow, undercutting Rule 1's whole
  point. Sparkle was the proposed automatic-update system; it is not integrated. The current
  updater reads an HTTPS feed and opens a browser download. Centralize pack I/O in `PackStore`
  so an App Store target stays possible without a rewrite. The current repository build
  is only ad-hoc signed; see `Docs/release.md` for the credentialed distribution path.

### Scope decisions already made

- **One pet, all displays.** Draggable between displays, correct per-display backing scale,
  handles hot-plug and reconfiguration. Multi-display is cheap now and painful to retrofit
  (it touches window management and coordinate conversion). Multi-pet is the
  reverse — easy to add later, and it would multiply the energy budget before we have
  proven it once.
- **Audio: plumbing in, silent by default.** Playback is disabled until opted in; the saved
  volume defaults to 0.4. Klien has no sound assets. Volume UI is implemented. Audible playback and system mute/Do Not Disturb
  behavior still need verification before they become release promises.

---

## 3. Repository layout

```
Engine/            Swift package
  Sources/LodgerEngine/   generic model, renderer, Director, motion, input, system events
  Sources/lodger/         AppKit shell, settings, preferences, manual update check
  Sources/lodger-selftest/ native test runner
Packs/klien/       the reference pack (data only)
  reference/       source art + art bible - never shipped
  atlas/  audio/   built assets
Tools/packtool/    the asset pipeline CLI (§7)
Schema/pack.schema.json
Docs/
  PACK_FORMAT.md         normative pack spec
  reference-audit.md     measurements of the original klien.png
  energy-protocol.md     §6 expanded, with recorded baselines
```

**Keep character assets out of `Engine/` and character logic out of the reusable engine.**
`make separation` checks for asset files under `Engine/Sources` and for every reference
pack's name in engine and app source (it uses grep and find, so it cannot pass by failing
to run). The macOS CI workflow invokes it; broader detection and a hosted run remain open.
If you need a fixture for tests, generate it procedurally or put it in
`Tests/Fixtures/` as an obviously synthetic pack (`test.solidsquare`).

---

## 4. Windowing, input, and why it is done this unusual way

**Window:** one `NSPanel` per visible pet, `.nonactivatingPanel | .borderless`, sized to the
sprite's cell plus attachment margin — **never a full-screen overlay**. `isOpaque = false`,
clear background, `hasShadow = false`, `level = .floating`, and
`collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
`NSApp.setActivationPolicy(.accessory)` plus `LSUIElement = true` keep it out of the Dock and
the app switcher. Non-activating means clicking the pet never steals focus from the user's
editor.

**Hit testing — read this before "simplifying" it.** The window is
`ignoresMouseEvents = true` **by default**, and the engine flips it to `false` only while the
cursor is inside the character's opaque silhouette.

The obvious alternative — a transparent window relying on the window server to route clicks
through transparent pixels — is undocumented and has regressed at least twice: on Sonoma
(transparent windows stop passing clicks after repeated `setNeedsDisplay:`, never answered by
Apple) and on Tahoe 26.3 RC (*"mouse events are intercepted by the entire transparent window
rather than only the opaque regions"*, and separately all borderless windows becoming
unclickable). Fixed in the 26.3 public release, reported as returning in 26.4 beta. An app
that runs all day on an auto-updating OS cannot depend on that.

So:

1. `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])` fires
   while the cursor is over *other* apps.
2. Transform to pet-local coordinates; look up the **1-bit alpha mask for the current
   frame** (built by `packtool`, RLE in memory). O(1) per event.
3. Inside the silhouette -> `ignoresMouseEvents = false`. A **local** monitor / tracking area
   handles the exit, because global monitors never see events aimed at our own app.

This also gives correct hit testing for the free-floating attachment, which is a separate
layer at a physics-driven offset and would defeat any rect-based scheme.

**No TCC prompts.** Apple's *Monitoring Events* guide: a global monitor *"may only monitor
key events if accessibility is enabled or if the application is trusted for accessibility."*
The gate is on **key** events. Mouse-move monitoring needs no permission. Input Monitoring
and Accessibility apply to `CGEventTap` and `IOHIDDeviceOpen`.

**Never add `CGEventTap` or `IOHIDDeviceOpen`.** Those APIs are unnecessary for the
current interaction model and would introduce avoidable permission prompts.

---

## 5. Engine <-> pack boundary

**The pack owns:** art, atlas layout, cell size, frame durations, clip names, anchors,
attachment definitions and their physics constants, the state graph (states, weights, guards,
interrupts, transitions), sounds, personality knobs it wants exposed in Settings, its own
metadata and licence.

**The engine owns:** the *vocabulary*. Screen and display geometry, Spaces, backing scale,
the scheduler, the RNG, physics integration, hit testing, persistence, and **all decisions
about when to be idle**.

The critical asymmetry: **a pack states durations, never rates.** It can say "hold this frame
for 250 ms". It cannot say "wake me at 60 Hz". Scheduling is the engine's, because Rule 2 is
the engine's.

### The closed guard/event vocabulary

Packs reference these by name and parameter. There is **no expression language** — a
deliberate divergence from Shimeji, whose `Condition="#{mascot.environment...}"` attributes
are arbitrary evaluation loaded from untrusted folders.

Events: `clip.ended`, `state.timeout`, `pointer.enter`, `pointer.exit`, `pointer.click`,
`pointer.doubleClick`, `pointer.grab`, `pointer.release`, `pointer.near(px)`,
`pointer.idle(sec)`, `pointer.fast(pxPerSec)`, `edge.reached(edge)`, `physics.landed`,
`physics.settled`, `user.idle(sec)`, `system.wake`, `system.willSleep`, `display.changed`,
`space.changed`, `power.lowPowerMode(bool)`, `power.onBattery(bool)`, `app.occluded(bool)`,
`controls.changed` (format 2: the user just flipped a toggle; sent once, on that action only).
The four numeric thresholds may name a slider with `{"knob": name}` instead of a literal.

Guards: `random(p)`, `stateAge(op, sec)`, `pointerDistance(op, px)`, `pointerSide(left|right)`,
`onEdge(floor|wallLeft|wallRight|ceiling)`, `facing(left|right)`, `flag(name, bool)`,
`timeOfDay(from, to)`, `lowPower(bool)`, plus `all` / `any` / `not`. In format 2 a `flag`
must name a toggle the pack declares in `tuning`; the host supplies its value.

**Controls stay inert.** A pack declares sliders and toggles and references them by name
(`scaleBy`, `weightBy`, `{"knob": ...}`, `flag`). The engine multiplies, divides or
compares; it never learns a control's meaning and never evaluates one on a timer. Values
are read only when a state is entered, a timeout fires or an event arrives.

**Adding to these lists is an engine change with a format-version bump. That is correct and
intentional** — it is the seam that keeps packs inert.

---

## 6. Efficiency: the budget and how to prove you are meeting it

### Engine rules that make the numbers achievable

1. **A quiescent state installs no autonomous timer or physics display link.**
   Sprite animation remains in the render server. Input-routing exception (2026-09-22):
   a cursor over a changing silhouette requires frame-boundary deadlines, or a temporary
   display link for continuous walking/bobbing. These stop outside the panel or when paused;
   stable body/overlay pixels schedule no deadline. Measure hover cost separately from idle.
2. All sprite animation is `CAKeyframeAnimation` on `contentsRect`,
   `calculationMode = .discrete`, committed once.
3. A display link exists **only** during locomotion or unsettled physics, and is invalidated
   the instant motion settles. Use `NSView.displayLink(target:selector:)` (macOS 14+) — it
   tracks the correct display, adapts to refresh rate, and auto-suspends when the view is
   off-display.
4. Any remaining timer gets `tolerance >= 10% of its interval`. Apple: *"A general guideline
   is to set the tolerance to at least 10 percent of the interval for a repeating timer"* and
   *"even a small amount of tolerance has a significant positive impact."* Long idle waits use
   one coalesced dispatch timer with generous leeway.
5. The global mouse monitor is installed **only** while some reachable state's interrupts
   reference a pointer event, and removed otherwise.
6. Observe and react: `NSApplication.didChangeOcclusionState` (covered -> stop animating),
   `NSWorkspace.willSleepNotification` / `didWakeNotification`, `NSScreen` changes,
   `ProcessInfo.isLowPowerModeEnabled` (`NSProcessInfoPowerStateDidChange`) -> collapse to
   static poses, and on-battery -> scale the pack's `liveliness` knob down.
7. Atlases load lazily per page and evict after a configurable unused interval.
8. Avoid polling: use a notification or a known deadline. The narrow continuous-hover
   exception in rule 1 exists because input is already targeted when AppKit monitors see it.
   **`IdleWatcher` is another exception**, because macOS
   has no "the user went idle" notification. It does not sample: it asks how long the
   system has already been idle, sleeps for exactly the remainder, and re-asks on waking.
   With a 300-second threshold that is at most one wake every five minutes while the
   machine is in use, and none once the pet is asleep.
9. **Never move the window from a per-frame tick.** A window move costs ~340-450 us
   once the deferred Core Animation commit is counted — 6x the cost of `setFrameOrigin`
   alone. Walking instead resolves the whole stretch up front, sizes the window once,
   and animates the `rig` layer across it (`Walk.swift`, `Pet.startWalkStretch`). That
   took walking from 4.5% of a core to 0.10% and removed the display link entirely.
   The display link now exists only for falling and unsettled springs.
10. **AppKit accessors are not arithmetic.** `NSScreen.screens` and `visibleFrame` cost
    ~38 us and were being read every tick. Anything of that shape belongs in a cache
    invalidated by a notification, not in a per-frame path. `Calendar` is the same shape
    and is read from the guard context, so it is cached for 20 seconds.
11. **Sound is the one feature that costs timers.** Sprite frames advance in the render
    server, so the app cannot know when a frame appears without asking, and asking every
    frame is the poll Rule 2 forbids. A clip's per-frame sounds are therefore *scheduled*
    when the clip is installed — one wake per sound, not per frame, and only while audio
    is on and the clip actually has any. Audio is off by default. State-level `sound`
    fires once on entry and costs nothing.
12. **`send()` must stay cheap.** `pointer.near` and `pointer.fast` arrive on *every*
    mouse-move event, so `send` returns immediately unless the current state actually
    lists an interrupt for that event. Building a guard context unconditionally cost
    0.88% of a core against 0.13% — a 6.6x regression, from one missing guard.

### Targets

| Metric | Target | Status |
|---|---|---|
| CPU seconds per idle hour | **< 7 s** (~0.19%) | **MET — median ~1.2-1.4 s/hr** on the synthetic no-behaviour fixture; **5.6-6.3 s/hr** on the real Klien idle pack (breathing clip + float attachment), see `Packs/klien/reference/idle-v2/verification.md`. Raised from the original 2 s target because a pack with actual animation and a spring-driven attachment costs more than the empty fixture the 2 s figure was measured on, and short single soaks are noisy at this magnitude anyway (see `Docs/energy-protocol.md`); always take a median. |
| Timers in a quiescent state | **0** | **MET — scheduler live-timer count drops to 0 and stays there** |
| Pointer hit test | cheap enough to own | **MET — 21 ns/event; 0.009 s/hr at 120 events/s** |
| CPU while walking | as low as the platform allows | **MET — 0.10% of one core** (from 4.5%) via render-server locomotion, with **no display link at all**. Verified by `SIGSTOP`: the pet keeps walking with the process frozen. |
| Animation is render-server resident | app does no per-frame work | **VERIFIED** — frames keep advancing under `SIGSTOP`; see `Docs/energy-protocol.md` |
| Idle wake-ups, deep idle | **0/s** | not yet measured (needs `sudo timerfires`); zero by construction |
| Idle wake-ups, breathing idle | <= 1/s | not yet measured |
| `WindowServer` CPU delta, breathing idle | < 0.3% | **not measurable yet** — its own idle baseline drifts +/-2 points on a busy machine |
| Resident memory, one pack | < 40 MB | *estimate* |
| Activity Monitor Energy Impact, idle | < 0.1 | not yet measured |
| Package power delta vs. app killed, idle | < 10 mW | *estimate* |

Measured numbers and their caveats live in `Docs/energy-protocol.md`. Never loosen a target
without recording a measurement and a reason.

**Read the measured numbers honestly.** They were taken on a synthetic 24x24 pack with no
behaviour, no physics and no input monitor, and total CPU per run was 17-38 ms over 105 s -
small enough that run-to-run variance dominates. The finding that matters is not the absolute
value but that a running animation and a static frame cost the same, which is what
render-server residency predicts.

### The honest counterweight

Render-server-resident animation means *our process* does no per-frame work. It does not mean
the *system* does none: constant animation makes `WindowServer` recompose every frame. Most
naive pet apps look innocent in their own Activity Monitor row while inflating `WindowServer`.

Consequences, all of which shape the design: **measure `WindowServer` delta, not just our own
process**; **stillness is a feature** (frame durations in ms, ~4 fps breathing, dropping to a
single static frame with no animation installed at all in deep idle); and **a small window is
cheap while a full-screen one is not**.

### The measurement protocol

Run against a **release** build, on battery, display awake, no other user activity.

```bash
# 1. CPU seconds consumed over a 1-hour idle soak (the single most honest number)
PID=$(pgrep -x Lodger)
ps -o time= -p $PID          # note value; wait 3600s; note again; subtract

# 2. Wake-ups. Also watch WindowServer.
sudo powermetrics --samplers tasks --show-process-wakeups \
     --show-process-energy -i 5000 -n 12

# 3. System-wide power delta: run with app, then killed, compare
sudo powermetrics --samplers cpu_power,gpu_power -i 1000 -n 60

# 4. Memory
footprint -p $PID

# 5. Timer forensics when a wake-up count is unexplained
sudo timerfires -p $PID
```

Also: Activity Monitor -> Energy tab -> View > Column > **Idle Wake Ups**. Apple documents
this as "how many times per second a timer fired, averaged over the sample interval."

`make energy-check` is a planned release gate, not an existing command. Current
measurements use `make soak` and the Klien verification script. The menu Diagnostics
submenu samples state, scheduler timers, display-link status and window enumerations
when opened; there is no option-click HUD. A quiescent state must have no scheduler timer.

---

## 7. The asset pipeline: raw art -> conforming pack

**Current workflow:** Klien is authored reproducibly by `animate_klien.py` from the
approved native body, with editable body/cane/emblem layers. The emblem uses the
owner-supplied sun reference and a five-color gold extension; runtime frames bake
both props into the body to keep toss timing synchronized. Built-in generated pose
studies from the earlier milestone are retained as references. PixelLab/Aseprite
steps below describe the original authoring proposal, not required tools for the
current pack. Generic `generate` now creates an incomplete directory/manifest scaffold;
`preview` renders static texture sheets. Neither implements the original motion-generation
or animated-preview proposal. Doctor and some proposed lint checks remain backlog items.
The original ~65-cell estimate is not a requirement.


### Start here: the reference art is not pixel art

`Packs/klien/reference/klien.png` is art direction, not assets. Measured — full numbers in
`Docs/reference-audit.md`:

- 100% opaque, no alpha channel at all
- **60,154 unique RGB values** (real pixel art: 8-64)
- mean horizontal same-colour run **1.42 px**; 77.1% of runs are a single pixel
- **no consistent pixel grid**: grid-period score 1.36 where 1.0 means "no grid"; best column
  period 23 but best row period 15

It is a continuous-tone render *imitating* pixel art. **No downsample recovers a clean sprite,
because no clean sprite was ever there.** Do not build a "sprite extractor". The art is
re-authored at native resolution with this file as reference.

The six cells also disagree with each other: head-to-body ratio ranges 0.443-0.514 (row 1 is a
bigger-headed chibi than row 0), the floating item's vertical anchor drifts ~8 points of figure
height (~8 px on a 96 px sprite), the item's own height varies 157-189 px, and the top-left
item is missing the leaf tips the other five have. **This is why anchors are authored per
frame and linted, not inferred.**

### Resolution policy

Native art is authored at **96 px body height in a 128x128 cell**, at 1x only, magnified by
the GPU with **nearest-neighbour at integer factors only** (1x, 2x, 3x). For pixel art, an
integer nearest-neighbour upscale is bit-identical to an authored @2x asset — so shipping @2x
quadruples memory for no visual gain. `stage.pixelPerfect: true` makes the engine snap window
origin and scale to whole logical pixels. Never allow a fractional scale.

128x128 is also a natively accepted canvas size for the generator in Stage 3, so nothing is
resampled anywhere in the chain.

### Stage 1 — Art bible (once per character)

Produce and commit to `Packs/<id>/reference/`:

- `palette.gpl` — the locked palette (target 24-32 colours + transparent), derived by
  median-cut from the reference and hand-corrected.
- `proportions.md` — canonical ratios, chosen from **one** reference cell and stated as
  absolutes at native resolution: total height, head height, shoulder width, ground line, hat
  top, eye line.
- `turnaround.aseprite` — front / three-quarter / side at native resolution.

For klien the canonical cell is **`r1c0`** (row 1, leftmost) — see
`Packs/klien/reference/proportions.md` for the measured absolutes and the reasoning.
It was chosen for **face readability at 96 px**, not for median proportions: at a 9.6:1
downscale the eyes get about 3 px, and this is the identity reference the generator's
"fixed head" setting copies onto every frame.

Run stage 1 with:

```bash
python3 Tools/packtool/packtool.py palette  Packs/klien/reference/klien.png --colors 26
python3 Tools/packtool/packtool.py pixelize Packs/klien/reference/klien.png --cell r1c0
```

### Stage 2 — The canonical sprite (the highest-value hour in the project)

Produce **one** finished Klien at native resolution: 96 px tall in a 128x128 cell,
palette-conformant, on-grid, transparent background. Everything downstream inherits its
identity, proportions and palette from this single image, so it is worth doing slowly.

Route: `packtool pixelize` the canonical reference cell into a tracing sketch — flood-fill the
near-white background to alpha with a **tolerance flood from the border, not a colour key**
(`#FFFFFF` is only 28.6% of that background), block-average, quantise to the locked palette,
snap to grid — then finish by hand in Aseprite. Sketches live in `reference/sketches/`, are
marked `DO NOT SHIP`, and are never referenced by a manifest.

### Stage 3 — Generate the motion frames (PixelLab, skeleton-driven)

Feed the Stage 2 sprite in as the **reference character**. For each motion clip, author the
skeleton keypoints per frame — this is animation *direction*: cheap, and it keeps the motion
under your control rather than the model's — and generate at **128x128**.

- Enable **"fixed head"**: it copies the reference head onto each generated frame. For a
  character whose whole identity is a top hat and a face, this is the setting that keeps 65
  cells on-model.
- Start with as few frames per generation as possible and iterate; the auto-estimated skeleton
  "isn't perfect and might require some touch ups."
- Use *rotation* for facing variants and *inpainting* for single-cell fixes.
- Script it via the `pixellab` Python SDK from `packtool generate` so runs are reproducible and
  prompts/skeletons are version-controlled. **Never hand-click 65 cells through a web UI** —
  you will not be able to regenerate them consistently later.

Generated frames land in `reference/generated/`. They are **inputs to Stage 4**, not assets.
Nothing generated ships without passing through Aseprite.

### Writing the animation prompt

Craft rules worth following whichever generator is used:

- **Inspect the source first.** Upscale the canonical sprite nearest-neighbour to about
  1024x1024 and look at it. Name only details that are actually visible - silhouette, hat,
  cape, cane, facing. Inventing detail the sprite does not have is what produces off-model
  frames.
- **One short paragraph of plain prose**, not a keyword list. Say what moves, how it moves,
  what stays stable, and how the props are used. "The gentleman in the black top hat rocks
  gently forward and back in a slow breathing idle, his cape settling behind him while the
  cane stays planted and his head remains level" beats "idle, breathing, 4 frames".
- **Leave an edge margin.** Generators crowd the canvas edge, and art touching the cell
  border tears when magnified or when a socket offsets it. `packtool build` warns about it.

**Why this tool.** The missing work is a walk cycle plus 65 frames that stay on-model.
Generating 65 independent images and hoping they match is the exact failure the reference sheet
already demonstrates across six cells. Skeleton-driven generation makes poses **specified
rather than sampled**. No local option does this: SDXL + a pixel-art LoRA reproduces the
reference's own failure mode (continuous tone, no grid) with no consistency mechanism beyond a
character LoRA trained on six images, and Flux only runs at Q4 on 16 GB. Retro Diffusion's
Aseprite extension (local, one-time cost, pixel-native model trained on consented art) is a
good optional assist for Stage 2 and for palette reduction, but it does no pose-driven
animation.

**SpriteCook was evaluated and is a credible alternative to PixelLab, not to `pixelize`.**
It is a cloud generation service driven over MCP (`npx spritecook-mcp setup`), so it sits at
Stage 3. `generate_character` plus `generate_character_animations` gives a guided character
workflow with `platformer` presets (`idle`, `walk`, `jump`, `run`, `attack`, `hurt`, `death`)
and `custom_animations` for anything else, and `generate_game_art` accepts a hex palette of
up to 64 colours - which would land frames already conformant to our locked 26. Its
independent conclusion matches ours exactly: generate one canonical asset, then animate that
same asset id per motion, never a fresh still per motion.

Two things keep PixelLab as the recommendation for now: `generate_character` is fixed at
**64x64**, which cannot produce our 128 cell (only the free-form `generate_game_art` reaches
128, and that forfeits the animation workflow), and PixelLab's skeleton keypoints make poses
**specified rather than described**, which is the whole reason it was chosen. PixelLab also
has a `Force colors` option, so palette enforcement is not a differentiator. Worth trialling
side by side on the walk cycle if PixelLab's skeleton estimates prove fiddly.

**SpriteCook does not improve `packtool pixelize`.** It has no pixelisation primitive to
borrow - it generates, it does not downsample reference art. Stage 2 stays as it is.

### Stage 4 — Finishing and anchors — the step no tool does

**The pipeline is editor-agnostic.** Any editor that can export a PNG frame strip works.
Recommended free option: **Pixelorama** (MIT, actively developed, frame tags, CLI `--json`).
Aseprite works too if you own it.

Per frame: conform to the locked palette, register the ground line, clean the silhouette, and
**place the anchors**.

The editor produces two things:

1. **A PNG frame strip** per clip group, frames left to right, uniform cell.
2. **`clips.json`** — clip names, loop mode, per-frame durations in ms. You are editing this
   by hand regardless, because durations are per-frame and are characterisation, not a rate.

Anchors come from `packtool anchors`, not from the editor.

```bash
python3 Tools/packtool/packtool.py anchors Packs/klien --strip body.png --cell 128
```

**Anchors are always authored, never inferred.** No generator places them, and inferring them
is precisely what produced the ~8 px item drift measured in the reference. Budget real time for
this; it is a large share of the 5-10 min per cell.

#### Why a purpose-built picker rather than Aseprite slices

Aseprite slice keys carry a per-frame `pivot`, which was the original plan. It was dropped for
four reasons, and the picker turned out to be better on the merits:

1. **The picker shows the anchor path across every frame at once, live, while you place them.**
   Aseprite cannot. Anchor drift is the specific defect measured in this reference art
   (`Docs/reference-audit.md`), so authoring against a visible trace attacks the real problem
   rather than catching it later in a linter.
2. **Editor-agnostic**, so pack authors need no paid tool. That matters more than a $20 gate,
   given that other people are expected to make packs.
3. **LibreSprite does not have slices.** It forked from the last GPLv2 commit of Aseprite in
   August 2016 and slices landed afterwards, so the obvious free Aseprite substitute cannot
   carry pivots at all.
4. It avoids known Aseprite export bugs — empty slice and tag metadata in tileset exports,
   slices emitted for non-tagged frames.

Aseprite slice import was proposed but is not implemented as an `--aseprite-json` option.
The current build reads PNG strips/atlases and per-texture JSON anchor files.

### Stage 5 — `packtool build`

```bash
packtool build Packs/klien --out Packs/klien.pack
```

1. Read the source manifest and PNG strips or existing grid atlases.
2. Report ground-line drift. The build does not automatically reposition artwork;
   intentional bobbing/jumping must remain authored.
3. Pack into **uniform-cell grid atlases** — no rotation, no trim. Uniform cells are a hard
   requirement: `contentsRect` animation assumes every frame occupies an identically sized
   sub-rect.
4. Inject per-frame anchors from authored `anchors/*.json` files.
5. Generate 1-bit alpha hit masks per frame (RLE).
6. Emit `pack.json`; validate against `Schema/pack.schema.json`.

### Stage 6 — proposed lint coverage and current limits

There is no standalone `lint` subcommand. Build/validate currently check references, schema
when jsonschema is installed, state reachability, capability requirements, quiescent policy,
anchor continuity, attachment margins and relevant atlas/asset constraints. Some findings
are warnings (including drift, margins and unreachable states). The list below is the original
broader target; generic palette/grid/proportion enforcement is not fully implemented.

- palette conformance — every pixel is in the declared palette
- off-grid pixels — art must sit on the native grid
- ground-line drift across frames of a clip
- **attachment margin** — a `float` whose `rest + maxOffset` exceeds a quarter of the
  cell is flagged, because the engine pads the window to avoid clipping it and
  compositing cost grows with the window's area
- **anchor continuity** — an anchor that jumps more than *N* px between adjacent frames is
  flagged. This is the specific defect present in the reference art: invisible in a contact
  sheet, glaring in motion, and the defect most likely to survive Stage 3 since a generator has
  no concept of an anchor at all.
- **proportion conformance** — head-height ratio within tolerance of the canonical sprite. The
  reference drifts 0.443->0.514 across six cells; a generator asked for 65 will drift at least
  as much unless something checks.
- every referenced clip / texture / sound / state exists; no atlas cell index out of range
- `initialState` resolves; no unreachable states; no dead-end states
- **quiescent-state discipline** — a `quiescent: true` state may not declare `next`,
  `duration`, or motion, and its clip must loop or be a single frame. This is Rule 2
  made mechanical, and it is the check most worth keeping honest.
- capability gating — sounds imply `audio`
- cell overflow (art touching the cell edge)
- atlas byte budget

### Stage 7 — `packtool preview`

`preview` renders a generic texture contact sheet so an author can inspect every frame without
launching the app. Animated clip sheets, anchor overlays, and an installed-pack `doctor` remain
future extensions; they are not promised by the current CLI.

### Historical initial art estimate

~65 unique cells: ~51 body (idle/sit, walk+turn, cursor reaction, grabbed/fall/land, sleep,
tip-hat), 7 cane, 4 dumpling, 3 face. At a 128x128 cell, 1x only, that is roughly one 1024x1024
atlas, ~4 MB decoded.

Absent from the reference entirely and requiring new art: a walk cycle, a drag/held pose, a
fall pose, sitting, sleeping, and **a cane separated from the body art** (recommended — it is
what makes the socket attachment path real and lets the cane swing during the walk).

---

## 8. Adding a character pack

**As a user:** drop the folder in `~/Library/Application Support/Lodger/Packs/`, or use the
menu-bar item > *Add Character...*. Discovery refreshes when the menu opens and after imports;
there is no continuous directory watcher. Loader failures are listed in the menu.
Imports stage a copy before replacement and attempt backup restoration on move failure.
Runtime schema/assets, contained paths, ID replacement and rollback are implemented.
Actual import dialogs and crash recovery remain separate acceptance/implementation work.

**As an author:**

```
Packs/mycharacter/
  pack.json              # required, together with every referenced asset
  atlas/
    body.png             # uniform-cell grid, 1x, nearest-neighbour
    prop.png
  audio/step.wav
  preview.png
  LICENSE
  CREDITS.md
```

```bash
# available today
python3 Tools/packtool/packtool.py validate Packs/mycharacter
python3 Tools/packtool/packtool.py validate Packs/mycharacter --no-assets  # before art exists

# scaffold, inspect, validate, and build
python3 Tools/packtool/packtool.py generate Packs/mycharacter --id mycharacter
python3 Tools/packtool/packtool.py preview Packs/mycharacter
python3 Tools/packtool/packtool.py build Packs/mycharacter
```

The normative schema is `Schema/pack.schema.json`; `Docs/PACK_FORMAT.md` explains it.
Use `Tests/Fixtures/test.solidsquare` as a minimal working example. The current `generate`
scaffold needs required metadata, art, clips, parts and states before validation or use.

## 8a. The bundled default pack

Klien and Norn ship inside the app bundle so that Lodger is never empty on first run.
`BUNDLED_PACKS` (Makefile / `Scripts/bundle.sh`) lists them; `Scripts/bundle-pack.py`
copies each by one rule (manifest, the files it references, `LICENSE`, `CREDITS.md`) and
refuses a pack whose licence is unsettled. The first listed pack becomes the Info.plist
`LodgerDefaultPack`, which is how the app picks a first-run character without a pack ID
in source.

```
Lodger.app/Contents/Resources/Packs/klien/     read-only
Lodger.app/Contents/Resources/Packs/Norn/      read-only
~/Library/Application Support/Lodger/Packs/    user-installed, writable
```

Three constraints keep this from quietly destroying Rule 1:

1. **The bundled pack loads through the identical code path as a user-installed one.**
   No `if bundled`, no privileged shortcut, no assumption that it is valid. It is discovered,
   decoded and checked for referenced files exactly like a folder someone dropped in yesterday. Runtime schema/capability/asset validation is enforced.
   `PackStore` merges the two directories and nothing downstream knows which is which.
2. **A user pack shadows a bundled pack with the same id.** That is how someone replaces Klien
   with their own edit of him without touching the app bundle.
3. **The zero-packs empty state stays supported and stays tested.** Strip the bundle's Packs
   directory and the app must still launch and show an empty state. This is the Rule 1 test,
   and pack authors will hit it.

A test asserts (1) by loading the bundled pack through `PackStore` and diffing the resulting
model against the same pack loaded from a temporary directory. They must be identical.

Because the app bundle now carries character art, the bundled pack's license becomes the
app's problem too — keep the pack's declared license and credits accurate in release materials.

---

## 9. Things that are bugs, stated plainly

- A character name, dimension, or timing constant in `Engine/`.
- A timer running in a state marked `quiescent`.
- A poll where a notification exists.
- Enumerating windows outside a drag-drop interaction.
- A pack that can cause arbitrary evaluation.
- Relying on window-server alpha routing for click-through (§4).
- An @2x atlas in a pixel-art pack (§7).
- A non-uniform atlas cell (§7, Stage 5 step 3).
- Adding a TCC-gated API to the default build path (§4).
- Loosening an energy target without a recorded measurement and a reason (§6).
- Any code path that treats the bundled pack differently from an installed one (§8a).
