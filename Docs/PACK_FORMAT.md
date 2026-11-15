# Character pack format v2

Format 2 adds typed Settings controls (§8), `weightBy`, slider-valued event thresholds
and the `controls.changed` event. Format 1 packs remain valid and behave as before; a
pack that uses any of the additions must declare `"format": 2`.

Normative schema: [`Schema/pack.schema.json`](../Schema/pack.schema.json)
Worked example: [`Packs/klien/pack.json`](../Packs/klien/pack.json)
Minimum viable pack: [`Tests/Fixtures/test.solidsquare/pack.json`](../Tests/Fixtures/test.solidsquare/pack.json)

This describes the authoring contract. The runtime also enforces the schema, semantic
references, asset decoding and contained paths. See [runtime validation and installation](pack-installation.md)
for supported capabilities, resource limits, replacement policy and recovery guarantees.
Install `Tools/packtool/requirements.txt` for schema validation in the author CLI.

```bash
python3 Tools/packtool/packtool.py validate Packs/mycharacter
python3 Tools/packtool/packtool.py validate Packs/mycharacter --no-assets   # before art exists
```

---

## 1. What a pack is

A folder containing `pack.json` and the files it references.

```
mycharacter/
  pack.json        # required, together with every referenced asset
  atlas/*.png      # uniform-cell grid atlases, 1x, nearest-neighbour
  audio/*.wav
  preview.png
  LICENSE  CREDITS.md
```

**A pack is inert data.** It contains no executable code and no expression language. Behaviour
is expressed by referencing a closed vocabulary of events and guards that the engine
implements (§7). This is a security property — you are asking users to drop folders from the
internet into a program that runs all day — and an efficiency one: a pack that could evaluate
arbitrary predicates per frame could burn the battery.

**A pack states durations, never rates.** It can say "hold this frame for 250 ms". It cannot
say "wake me at 60 Hz". Scheduling belongs to the engine.

---

## 2. `identity`, `format`, `requires`

```json
{
  "format": 2,
  "engineMin": "1.0.0",
  "requires": ["audio"],
  "identity": {
    "id": "com.example.mycharacter",
    "name": "My Character",
    "version": "1.0.0",
    "author": "You",
    "license": "CC-BY-NC-4.0",
    "description": "One sentence.",
    "preview": "preview.png"
  }
}
```

`id` is reverse-DNS and is the pack's permanent identity — installing a pack with an existing
id replaces it. `requires` declares capabilities the engine must grant:

| Capability | Meaning |
|---|---|
| `audio` | the pack declares sounds. Required if `sounds` is non-empty. |
| `multiDisplay` | the pack assumes more than one screen may exist |

## 3. `stage` — the coordinate contract

```json
"stage": {
  "cell": { "w": 128, "h": 128 },
  "bodyHeight": 96,
  "ground": { "x": 64, "y": 120 },
  "pixelPerfect": true,
  "scaleSteps": [1, 2, 3],
  "defaultScale": 2,
  "defaultFrameMs": 250
}
```

All values are **logical (native art) pixels**. `ground` is the feet contact point inside the
cell; every frame is registered onto it, so a stable ground point is what stops the character
jittering between frames.

**Ship 1x art only.** With `pixelPerfect` and integer `scaleSteps`, a nearest-neighbour upscale
is bit-identical to an authored @2x asset, so @2x assets quadruple memory for no visual gain.
Fractional scales are never allowed.

## 4. `textures` — uniform-cell atlases

```json
"textures": {
  "body": { "file": "atlas/body.png", "columns": 8, "rows": 8, "preload": true }
}
```

Cells are a **uniform grid**, indexed row-major from 0. This is a hard requirement, not a
convenience: the engine animates frames by stepping a layer's `contentsRect`, which assumes
every frame occupies an identically sized sub-rect. No rotation, no trimming, no packing.

`preload: true` loads the page at pack activation instead of on first use. Reserve it for pages
the idle and sleep states need; everything else loads lazily and is evicted when unused.

## 5. `clips` — animations

```json
"idle": {
  "texture": "body",
  "loop": "pingpong",
  "anchorJumpLimit": 16,
  "frames": [
    { "cell": 0, "ms": 900, "anchors": { "hand": {"x":92,"y":74}, "orbit": {"x":34,"y":52} } },
    { "cell": 1, "ms": 260, "anchors": { "hand": {"x":92,"y":75}, "orbit": {"x":34,"y":53} } }
  ]
}
```

- `loop`: `none` | `forever` | `pingpong`.
- `ms` defaults to `stage.defaultFrameMs`.
- `mirrorable` (default `true`): may the engine flip this clip horizontally to face the other
  way, or must a mirrored clip be authored? Set `false` for asymmetric characters.
- `anchorJumpLimit` raises the drift linter's threshold for one clip. Use it only where a large
  anchor sweep is deliberate, such as a turn.

### Anchors

`anchors` are named attachment points **in cell coordinates, authored per frame**. They are
never inferred from the art.

This is not stylistic. Measured on the reference art for `klien` (`reference-audit.md`), the
floating item's anchor drifted ~8 points of figure height between cells that were meant to be
the same character — about **8 px on a 96 px sprite**. Inferring anchors from art reproduces
exactly that. `packtool validate` therefore checks two things: every anchor a part binds is
present on **every frame reachable while that part is visible**, and no anchor jumps more than
`anchorJumpLimit` px between adjacent frames.

Author anchors with **`packtool anchors`**, a local picker that loads your frame strip, lets
you click each named anchor per frame, and draws the anchor's path across all frames while you
work — so drift is visible as you author rather than caught later by a linter. It writes
`anchors.json` beside your art and is editor-agnostic: any tool that exports a PNG frame strip
will do. (Aseprite slice pivots are accepted as an alternative source via
`packtool build --aseprite-json`, but are not the documented path, partly because LibreSprite —
the obvious free substitute — has no slices at all.)

## 6. `parts` — layers and attachments

An ordered list; declaration order is the default z-order, overridable with `z`. Exactly one
part must be `mode: "body"`, and every other part's `parent` must be declared before it.

Common fields: `visibleIn` / `hiddenIn` (state name filters), `mirrorWithBody` (when the body
flips, does this part swap sides?), `hitTest` (does this silhouette catch the pointer?).

### `body`

The base sprite. Defines the local origin.

```json
{ "name": "body", "bind": { "mode": "body" } }
```

### How attachments are positioned

**Draw the attachment in place.** An attachment's art lives in a cell the same size
as the body's, already where it belongs at the clip's first frame. The anchor then
supplies *motion only*: the part moves by `anchor[frame] - anchor[0]`, plus its
`offset` or `rest`.

So a cane is drawn into a 128×128 canvas in the character's hand, not floating at the
origin waiting to be placed. Nothing declares a pivot.

The alternative — place the attachment's pivot onto the parent's absolute anchor —
was tried first and is worse: it needs a pivot on every attachment, it is easy to get
wrong by tens of pixels, and getting it wrong pushes the art outside the window where
it is silently clipped.

### `socket` — held rigidly

Locked to a named anchor on the parent. A cane, a sword, a mug.

```json
{ "name": "cane", "z": 5, "hiddenIn": ["asleep"],
  "bind": { "mode": "socket", "parent": "body", "anchor": "hand",
            "frames": "parent", "offset": { "x": 0, "y": -2 } } }
```

`frames: "parent"` means the part's texture has exactly one cell per parent frame;
`frames: "clip"` gives it its own clip.

**There is no rotation field, deliberately.** Rotating pixel art off-axis destroys the grid,
so any tilt has to be pre-drawn — and `frames: "parent"` already gives you exactly that: one
cell of the attachment per frame of the body, so you choose the tilted cane image for the
frame where the arm is raised. An earlier draft had an `orientFrames` angle-to-cell map; it
was removed once it became clear it could express nothing that per-frame cells could not,
while adding a rotation concept the format otherwise does not have.

### `float` — drifting freely

A spring-damper follower. A companion orb, a familiar, a balloon.

```json
{ "name": "dumpling", "z": -1,
  "bind": { "mode": "float", "parent": "body", "anchor": "orbit", "clip": "dumpling_idle",
            "rest": { "x": -26, "y": -4 },
            "stiffness": 90, "damping": 11, "mass": 1.0, "lag": 0.09,
            "maxOffset": 22, "sleepThreshold": 0.15,
            "bob": { "amplitudeX": 1, "amplitudeY": 3, "periodMs": 2600, "phase": 0.25 } } }
```

The part hangs `rest` away from `anchor` and is pulled back by a spring. `lag` delays its
reaction to parent motion; `maxOffset` clamps how far it can trail.

`maxOffset` has a cost beyond aesthetics: the engine pads the pet window by the
largest `rest + maxOffset` so a drifting float is not clipped, and what the compositor
draws every frame grows with that area. `packtool validate` warns when the drift
exceeds a quarter of the cell. Keep it as small as the motion allows.

`sleepThreshold` is **required in spirit, not just in schema**: below that speed the spring is
considered settled, the engine tears down its display link, and the part's only remaining
motion is `bob` — which runs as a render-server animation costing no CPU. A drifting attachment
that could never settle would keep the process awake forever.

Tuning vocabulary, if it helps: `stiffness` is how eagerly it catches up, `damping` is how
quickly it stops overshooting, `lag` is sluggishness at the start of a move.

### `overlay` — locked to the parent's cell

Own clip, no offset. Blinks, blushes, sleep Z's.

```json
{ "name": "face", "z": 10, "hitTest": false, "hiddenIn": ["asleep"],
  "bind": { "mode": "overlay", "parent": "body", "clip": "blink" } }
```

This exists to prevent frame explosion: 6 body poses times 2 eye states is 8 cells as an
overlay, versus 12 baked in.

## 7. `states` — the behaviour graph

```json
"initialState": "idle",
"states": {
  "idle": {
    "clip": "idle",
    "motion": "none",
    "surface": "floor",
    "facing": "keep",
    "duration": { "minMs": 3000, "maxMs": 12000 },
    "next": [
      { "state": "walking", "weight": 35 },
      { "state": "sitting", "weight": 15, "when": { "random": 0.5 } }
    ],
    "interrupts": [
      { "on": { "pointer.near": 60 }, "state": "watching" },
      { "on": "pointer.grab", "state": "held" }
    ]
  }
}
```

`next` fires when `duration` elapses (or the clip ends, with `"duration": "clip"`); the engine
picks among the entries whose `when` guard passes, by `weight`. `interrupts` preempt at any
time. `initialState` is explicit so that no state name is special to the engine.

`motion` is `"none"`, or `{"type":"walk", "speed":…, "direction":…}`,
`{"type":"fall", "gravity":…, "terminal":…}`, or `{"type":"drag"}`. `surface` is
`floor` | `ceiling` | `wallLeft` | `wallRight` | `air`.

### Scaling a duration by one of your own knobs

```json
"duration": { "minMs": 3000, "maxMs": 12000, "scaleBy": "liveliness" }
```

`scaleBy` names a knob from your `tuning` block. The engine divides the duration by its
value — a higher knob means a livelier pet — and **never learns what the knob means**.
That is how a pack ships a "Liveliness" slider without the word appearing anywhere in the
engine.

### Scaling how often something happens

```json
"next": [
  { "state": "idle",    "weight": 25 },
  { "state": "walking", "weight": 35, "weightBy": "wander" }
]
```

`weightBy` names a slider. The transition's weight is multiplied by the slider's value, so
`0` removes that option and `2` makes it twice as likely relative to the others. If every
eligible option has been scaled to zero, the authored weights apply: settings can never
strand a character in a state with nowhere to go. Leave at least one option unscaled if
"all off" should mean something specific.

### Letting the user set a threshold

```json
{ "on": { "user.idle": { "knob": "sleepAfter" } }, "state": "sleep_preparing" }
```

`pointer.near`, `pointer.idle`, `pointer.fast` and `user.idle` accept `{"knob": name}` in
place of a number. The slider must have a positive minimum. When the user moves it, the
engine re-arms the affected watcher once; nothing is re-read on a tick.

### `quiescent` — the one field that matters most for battery

```json
"asleep": {
  "clip": "sleep",
  "quiescent": true,
  "interrupts": [ { "on": "pointer.click", "state": "waking" } ]
}
```

Marks a state with no autonomous state timer or physics display link. Sprite animation
stays in Core Animation. Input routing is an engine-owned exception: while a cursor overlaps
a changing silhouette, a boundary deadline or temporary continuous-motion hover tracker
keeps clicks targeted correctly. Stable pixels and cursors outside the panel add no routing
wake. See [interaction verification](interaction-plan.md) and [energy scope](energy-protocol.md).

`packtool validate` enforces the conditions that make this true, and will reject a quiescent
state that declares `next`, `duration`, or motion, or whose clip is multi-frame and
non-looping (because it would end and need a wake-up). **Give every pack at least one
quiescent state.** A pet with none is a pet that never stops costing power.

### Closed vocabulary

**Events** usable in `interrupts`:

`clip.ended` · `state.timeout` · `pointer.enter` · `pointer.exit` · `pointer.click` ·
`pointer.doubleClick` · `pointer.grab` · `pointer.release` · `physics.landed` ·
`physics.settled` · `system.wake` · `system.willSleep` · `display.changed` · `space.changed` ·
`controls.changed` (a toggle was just switched in Settings; format 2) ·
`{"pointer.near": px}` · `{"pointer.idle": sec}` ·
`{"pointer.fast": pxPerSec}` · `{"user.idle": sec}` ·
`{"edge.reached": "left"|"right"|"top"|"bottom"}` · `{"power.lowPowerMode": bool}` ·
`{"power.onBattery": bool}` · `{"app.occluded": bool}`

**Guards** usable in `when`:

`{"random": p}` · `{"stateAge": {"op":…,"sec":…}}` · `{"pointerDistance": {"op":…,"px":…}}` ·
`{"pointerSide": "left"|"right"}` · `{"onEdge": …}` · `{"facing": "left"|"right"}` ·
`{"lowPower": bool}` · `{"flag": {"name":…,"value":…}}` ·
`{"timeOfDay": {"from":"23:00","to":"06:00"}}` · `{"all": [...]}` · `{"any": [...]}` ·
`{"not": {...}}`

Comparison operators are `lt` `lte` `gt` `gte` `eq`.

There is deliberately no way to write an arbitrary expression. If you need a verb that does not
exist, it is an engine change and a format-version bump — that seam is what keeps packs inert.


## 7a. Facing

`stage.artFacing` says which way your art is drawn (`"left"` by default). When the
character should face the other way, the engine mirrors the whole rig — art, sockets and
floats together. A state's `facing` chooses: `keep`, `left`, `right`, or `toPointer`. A
walking state that says `keep` naturally faces the way it is going.

Two escapes: a clip with `mirrorable: false` is never flipped, for art that is not
symmetrical enough to mirror; and a part with `mirrorWithBody: false` is counter-flipped so
it keeps its handedness and stays on the same visual side.

## 8. `sounds` and `tuning`

```json
"sounds": { "step": { "file": "audio/step.wav", "volume": 0.15, "maxConcurrent": 1 } }
```

Sounds are triggered per frame (`"sound": "step"` on a frame) or per state. Audio ships **off
by default**; the engine respects system mute and Do Not Disturb regardless.

### `tuning` — the controls your character shows in Settings

```json
"tuning": {
  "liveliness": { "label": "Liveliness", "min": 0.2, "max": 2.0, "default": 1.0,
                  "unit": "percent", "group": "Activity",
                  "description": "How quickly he moves from one activity to the next." },
  "sleepAfter": { "label": "Sleep after", "min": 60, "max": 3600, "default": 300,
                  "unit": "seconds", "group": "Rest" },
  "startles":   { "type": "toggle", "label": "Startles", "default": true, "group": "Pointer" }
}
```

There are two kinds of control. Neither the engine nor Settings knows what any of them
means; you give them meaning by where you reference them.

| Kind | Declared with | Referenced from |
|---|---|---|
| Slider (`"type": "slider"`, the default) | `min`, `max`, numeric `default` | `duration.scaleBy`, `next[].weightBy`, an event threshold `{"knob": name}` |
| Toggle (`"type": "toggle"`) | boolean `default`; no `min`/`max`/`unit` | the guard `{"flag": {"name": ..., "value": true|false}}` |

Optional display fields: `group` (a heading; controls are grouped and sorted by it),
`description` (a tooltip) and, for sliders, `unit` — `"seconds"` shows `5 min`,
`"percent"` shows `100%`, anything else shows the plain number.

Rules the loader and `packtool validate` both enforce:

- every reference names a declared control of the right kind;
- a slider's default lies within its range; `scaleBy` and threshold sliders have a positive
  minimum, `weightBy` sliders a non-negative one;
- in format 2, a `flag` guard must name a declared toggle (format 1 keeps the old
  behaviour, where an unknown flag simply reads false);
- typed entries, display fields, `weightBy`, `{"knob": ...}` and `controls.changed` require
  `"format": 2`.

Settings shows only controls that some state actually references; `packtool validate`
warns about a declared control nothing uses. Values are clamped, saved per character and
applied live: a slider affects the next duration, weight or threshold evaluation (not a
deadline already scheduled), and a toggle is read the next time one of its guards is
evaluated. The character is not restarted.

Because guards are only evaluated when an event or timeout already occurs, a toggle alone
cannot wake a quiescent state. If a switch should take effect immediately, listen for it:

```json
{ "on": "controls.changed", "state": "inspecting",
  "when": { "flag": { "name": "wanders", "value": true } } }
```

`controls.changed` is sent once when the user flips any toggle, never for slider
movement and never on a timer.

**Keep the default cheap.** A control that turns on timed behaviour should default to off
if the character is otherwise quiescent, and route into a separate non-quiescent state
rather than making the resting state timed. `Packs/Norn` does this for wandering.

## 9. Checklist before publishing

- [ ] `packtool validate` passes with no errors and no unexplained warnings
- [ ] at least one `quiescent: true` state
- [ ] every socket/float anchor present on every reachable frame
- [ ] atlases are 1x, uniform-cell, nearest-neighbour, no @2x
- [ ] no art touching the cell edge (`packtool build` warns; it tears when magnified)
- [ ] `LICENSE` and `CREDITS.md` present, including the provenance of any generated art
- [ ] `preview.png` looks like the character at `defaultScale`
