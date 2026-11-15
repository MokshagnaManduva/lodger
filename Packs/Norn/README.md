# Norn · desktop alchemist

Norn is a **bundled Lodger character (v0.4.0)**, shipped in the app next to Klien and
licensed CC BY-NC 4.0. Open [runtime.html](runtime.html) to inspect the exact runtime
frames and timings. The original [gallary.html](gallary.html) remains the concept
sketchbook; its spelling is retained for existing links. Both pages work directly from disk.

Norn is a curious, slightly distracted alchemist accompanied by a floating root.
Her movement language is careful footwork, expressive hands, and prop-driven
mishaps. Her identity reference and all original sheets remain unchanged.

## Looks (0.4.0)

**Potion:** Violet (the art as drawn), Emerald, Amber, Azure. `build_norn.py` finds the
flask's purple hue family in the compiled atlases and rotates it; `make looks` renders
the result to `build/looks-norn.png`. Her irises share two of those purples and shift
slightly with the potion. The other props are baked into the generated sheets and share
colours with her clothes, so they are not offered as choices.

## Settings controls (0.4.0)

| Control | Kind | Effect |
|---|---|---|
| Wanders on her own | toggle, **off** | Off: she rests until you interact. On: she walks, reads for a while, gets up and repeats |
| Wander pace | slider 50–200% | How soon she moves on while wandering |
| Notices the cursor | toggle, on | The curious look when the cursor touches her |
| Greets on click | toggle, on | The wave; double-click still sends her walking |
| Naps in Low Power Mode | toggle, on | Sleeping while Low Power Mode is on |

Wandering is off by default so that `idle` and `reading` stay quiescent: no state
timer, as measured. Switching it on routes her into `idle_restless` and
`reading_restless`, timed twins of those states, which cost one coalesced wake per
20–60 s idle spell and per 45–120 s reading spell (divided by the pace). The switch
takes effect at once through `controls.changed`: she looks at her flask or closes
her book and carries on in the new mode. She now arrives with a brief look at her
flask (`initialState` is `inspecting`) so that arrival routes to the right idle.
The manifest source is `reference/runtime-v1/pack.source.json`.

## Run and build

From the repository root:

```sh
make norn-animations       # compile artwork, masks, manifest and preview; art checks
make norn-test             # art acceptance + actual Swift Director checks
make norn-pack             # export only runtime assets to build/Norn.pack
make app                  # if the local Lodger bundle does not yet exist
./build/Lodger.app/Contents/MacOS/Lodger --pack Packs/Norn
```

For the normal menu/settings flow, start Lodger from the repository root and select
Norn from its discovered development packs, or use **Add Character…** and choose
`build/Norn.pack`. The export excludes generated source sheets, JavaScript and
preview HTML. `make app` bundles her runtime files with Klien's.

## Desktop behavior

| Input / event | Response |
| --- | --- |
| Launch | Inspect the flask once, then idle |
| Quiet desktop | Slow blink and smile; quiescent idle (unless wandering is on) |
| Pointer enters her silhouette | Curious look, inspect the flask, return to idle |
| Click while standing | Wave, inspect, recover |
| Double-click while standing | Walk a bounded segment, settle down, read |
| Click while reading or sleeping | Stand up and return to idle |
| Grab from any action | Tuck her boots and hold props close |
| Release / floor contact | Fall, compress on landing, recover |
| System sleep / low power | Sleep; system wake / power restoration wakes her |

Idle, reading and sleep request no state timer, display link, `user.idle` watcher
or `pointer.idle` watcher. Rest follows a completed walk; sleep follows system
notifications. This avoids the engine's pack-wide inactivity watcher, which would
otherwise remain armed in quiescent states. Normal walking uses the existing
render-server motion path. Character names and logic have not been added to the
engine.

## Animation polish — 2026-09-25

Three new source sheets add 18 drawings. Runtime pages also copy six canonical
endpoint cells, for **58 stored cells across seven atlases** (not 58 unique poses).
The original body, sleep, held and fall atlases retain their existing artwork.

- **Walk:** four selected contact/passing drawings in a 0.72-second loop, with
  visibly alternating raised boots and a steadier head/flask position.
- **Greeting:** 13 timed frames over 2.30 seconds. Lower the flask into a belt
  loop, release it, wave, then reverse the transfer and retrieve it. Starts and
  ends on an exact copy of the canonical neutral frame.
- **Sit:** six timed frames over 1.09 seconds, with knee bends, flask placement
  on the floor and a seated book pose. No landing crouch is reused.
- **Stand:** six timed frames over 1.20 seconds, reversing the sitting poses and
  retrieving the flask. Ends on the canonical neutral frame.
- **Read:** uses the exact seated endpoint plus its closed-eye drawing, avoiding
  a redraw jump at the sit/read and read/stand boundaries.

All these grounded frames end at y=114. Registration aligns standing heads and
props with the original pack. This improves the normal sequences; it does not
provide a bespoke bridge for every interrupt or eliminate all generated shape
variation. Root, book and flask remain baked into each drawing.

Sources, exact prompts and verification: [polish-v3](reference/polish-v3/README.md).

## Six-frame motion update

The former single-frame `sleep`, `held` and `fall` clips each now have **six
separately drawn poses**:

| Clip | Loop | Movement |
| --- | --- | --- |
| Sleep | 4.80 s | Slow inhale/exhale, chin settling, gentle root leaf movement |
| Held | 1.32 s | Alternating boot swings, tucked knees, blink and cautious smile |
| Fall | 0.70 s | Feet-first leg adjustments, hair and apron flutter, root leaf motion |

All 12 runtime clips now contain multiple distinct poses. Falling remains
interruptible by floor contact; held remains interruptible by release. Sleeping
still loops through Core Animation in a quiescent state. No animation timer or
engine change was introduced.

## Artwork and editable sources

The original runtime sheet has 16 poses: neutral, blink, inspect, smile; four tiptoe poses;
curious glance, wave, read, sleep; held, fall, landing crouch and recovery.
It is compiled into a transparent **512 × 512 atlas**. Three added **384 × 256
atlases** contain 18 new motion poses, for the initial 34 stored cells. The polish update adds a 384 × 256 walk atlas
and two 384 × 384 transition atlases, bringing the total to 58 cells. Every cell is
**128 × 128**, with binary alpha and the same locked 32-color palette. The original
body atlas remains byte-for-byte unchanged. Standing body
height is approximately 96 px, the authored ground point is `(72, 114)`, and all
grounded soles end at y=114. The held tuck deliberately ends above the ground.
Default display scale is 2×; 1× and 3× are also supported.

- `reference/runtime-v1/lifecycle-sheet.png`: generated source, kept intact.
- `reference/runtime-v1/generation-prompt.txt`: exact built-in imagegen prompt.
- `reference/runtime-v1/registration.json`: authored source rectangles, target
  sizes and placements. The generated image is 1254 × 1254 with uneven row gaps,
  so splitting it blindly into quarters would cut through boots.
- `reference/motion-v2/*-sheet.png`: three new generated six-pose source sheets.
- `reference/motion-v2/*-prompt.txt`: exact built-in imagegen prompts.
- `reference/motion-v2/*-registration.json`: explicit crop and placement for every
  new pose. Sleeping soles remain fixed at y=114; held toes deliberately swing
  between y=106 and y=110 above the floor.
- `reference/polish-v3/*-sheet.png` and `*-registration.json`: current walk,
  greeting and sitting sources and registration; complete canonical endpoint cells
  are reused by `bodyCell` references. Exact prompts are retained beside them.
- `reference/runtime-v1/pack.source.json`: editable behavior graph and clip timing.
- `reference/runtime-v1/clips.json`: descriptions for the runtime gallery.
- `Tools/packtool/build_norn.py`: deterministic compiler; generation is not part
  of a rebuild. It samples nearest-neighbor, thresholds existing source alpha,
  applies one shared palette, and writes masks from the resulting silhouettes.
- `atlas/*.png`, `masks/*.mask`, `pack.json`, `preview.png`, `runtime.js`:
  generated output. Edit the sources and rebuild rather than patching these.

The root, book and flask are baked into the body so they stay synchronized with
these key poses; no attachment anchors or independent root physics are claimed.

## Original studies

| Study | Motion | Intended use |
| --- | --- | --- |
| A little too curious | Swirl a potion, follow a bubble | Quiet idle |
| The book has opinions | React to magically turning pages | Surprise |
| Field assistant | Give the root a high-five | Companion interaction |
| Precious cargo | Tiptoe while keeping a flask level | Locomotion |
| An unexpected reaction | Inhale, sneeze, sheepish recovery | Comic reaction |
| Just one more chapter | Seated reading, doze, root nudge | Rest |

Those six sheets remain concept references, not runtime textures. `drafts.js`
retains their original generation prompts and per-pose timing. Both galleries
support pause, step, scrub, tempo and background changes, reduced-motion startup,
and suspension while the browser tab is hidden. Finite runtime actions replay in
the gallery for inspection; they terminate normally in Lodger.

## Verification and remaining art work

See the [polish verification](reference/polish-v3/verification.md) for
current scope, and [initial milestone evidence](reference/runtime-v1/verification.md)
for earlier energy observations. Strict validation passes without warnings; eight
artwork/mask tests and 59 actual Swift Director checks pass. Export emits one
expected ground-drift warning for the deliberately dangling held boots. All 12 states resolve through the existing
native loader. Native launch and idle scheduling were smoke-tested; full desktop
interaction acceptance and energy certification remain open.

This remains generated artwork normalized into a development pack. The normal
walk, greeting and seated transitions have received a polish pass; individual
hair/prop shapes and abrupt transitions after interruptions can still vary.
High-five, page chase and sneeze concepts are not implemented yet.

There is no perching behavior. Source-character rights and public distribution
licensing remain unconfirmed; see [CREDITS.md](CREDITS.md) and [LICENSE](LICENSE).
