# Norn deployment and pack-declared behaviour controls — design

Date: 2026-11-15. Sub-project 1 of 3. Later sub-projects, each with its own spec:
(2) Settings redesign and app-level controls; (3) appearance variants (palette swaps
plus prop options).

## Goal

Ship Norn inside `Lodger.app` next to Klien, and let every pack declare behaviour
controls (sliders and on/off toggles) that Settings renders generically. Both
reference packs gain real controls.

## Owner decisions recorded

- Norn is licensed **CC-BY-NC-4.0**, authored by Mokshagna, the same as Klien. The
  owner confirmed distribution rights on 2026-11-15.
- Appearance variants will be palette swaps plus prop options (sub-project 3).
- Not in scope: Developer ID signing, notarization, public release, hour-long
  battery energy certification, live desktop acceptance. These stay in `left.md`.

## Constraints

- **Rule 1.** No character name, knob name or behaviour in engine or app source.
  Every control is declared by the pack and rendered generically.
- **Rule 2.** No new timer, poll or display link. Controls are read only when an
  existing event, timeout or state entry already runs. A pack's default settings
  must not cost more than it does today.
- Packs stay inert data: no expressions. Additions are closed vocabulary.

## Format changes (format version 2)

The schema accepts `format: 1` and `format: 2`. Version 1 packs stay valid and
behave exactly as before. The features below require `format: 2`; the validators
reject them in a version 1 pack.

### Typed `tuning` entries

```json
"tuning": {
  "wander":   { "label": "Wandering", "min": 0, "max": 2, "default": 1,
                "group": "Activity", "description": "How often he goes for a walk." },
  "reacts":   { "type": "toggle", "label": "Reacts to the cursor", "default": true,
                "group": "Pointer" },
  "sleepAfter": { "label": "Sleep after", "min": 60, "max": 7200, "default": 300,
                  "unit": "seconds" }
}
```

- `type`: `"slider"` (default) or `"toggle"`.
- A slider requires `min`, `max`, numeric `default`. A toggle requires a boolean
  `default` and forbids `min`/`max`.
- Optional display metadata for both: `description`, `group`, and for sliders
  `unit` (`"seconds"` or `"percent"`; anything else shows the plain number).
  The engine never interprets these; the app only formats with them.

### Using a control

1. **Toggle → guard.** A toggle's current value is the value of the existing
   `{"flag": {"name": ..., "value": ...}}` guard. A flag name must be a declared
   toggle. (Today nothing ever sets flags, so this guard is inert.)
2. **`weightBy` on a `next` transition.** `{"state": "walking", "weight": 35,
   "weightBy": "wander"}` multiplies the weight by the slider value. Zero removes
   the option. If every option's weight is zero the Director falls back to the
   unscaled weights, so a pack cannot be tuned into a dead end.
3. **Knob-valued event threshold.** A parameterised event may take
   `{"knob": "name"}` in place of a number: `{"on": {"user.idle": {"knob":
   "sleepAfter"}}}`. Supported for the existing parameterised events
   (`pointer.near`, `pointer.idle`, `pointer.fast`, `user.idle`).
4. Existing `duration.scaleBy` is unchanged.

### Validation (engine loader and `packtool validate`)

Reject: `weightBy`, `scaleBy` or an event `knob` naming an undeclared entry or a
toggle; a `flag` guard naming an undeclared entry or a slider (format 2 only —
format 1 packs keep the old permissive flag behaviour); a slider with
`min > max` or a default outside the range; a toggle with a non-boolean default.

## Engine

- `Pack.Knob` becomes a typed value (slider or toggle) with metadata.
- `Pet` and `Director` take `tuning: [String: Double]` (unchanged) and new
  `flags: [String: Bool]`. `Pet` copies flags into the guard context it already
  builds. `Director.timeout` applies `weightBy`.
- Event thresholds resolve through the Director's current tuning at the point where
  the threshold is already compared. Where the engine arms a watcher from a
  threshold (`IdleWatcher`, pointer idle), it re-arms when tuning changes; that is
  a user action, not a recurring wake.
- A changed value takes effect at the next evaluation. The pet is not restarted.

## App

- `Preferences` stores toggles per pack beside slider values; `reset(packID:)`
  clears both; resolution clamps sliders and falls back to pack defaults.
- `AppController` gains `setFlag(_:name:for:)` and applies resolved flags on
  activation.
- Settings (minimal change; redesign is sub-project 2): every declared slider that
  is referenced by `scaleBy`, `weightBy` or an event threshold is shown with a
  formatted value label; every toggle referenced by a guard is shown as a
  checkbox; controls are grouped under their `group` heading, with `description`
  as a tooltip. Unreferenced entries are still hidden.
- First-run default: with no saved choice, the app picks the pack named by the
  bundle's `LodgerDefaultPack` Info.plist key if present, else the first
  discovered. The build sets that key; no pack ID appears in source.

## Klien (generated by `animate_klien.py`, format 2, version 0.5.0)

| Control | Type | Wiring |
|---|---|---|
| Liveliness | slider 0.2–2 | existing `scaleBy` |
| Wandering | slider 0–2 | `weightBy` on idle → walking |
| Emblem tosses | slider 0–2 | `weightBy` on idle → toss_emblem |
| Hat tips | slider 0–2 | `weightBy` on idle → tipping_hat |
| Sitting | slider 0–2 | `weightBy` on idle → sitting_down |
| Sleep after | slider 60–7200 s, default 300 | `user.idle` threshold |
| Reacts to the cursor | toggle, on | guard on `pointer.near` → watching |
| Startles | toggle, on | guard on `pointer.fast` → startled |
| Sleeps at night | toggle, on | guard on the `timeOfDay` branch of sitting → sleeping |

Defaults reproduce today's behaviour exactly.

## Norn (generated by `build_norn.py`, format 2, version 0.4.0)

| Control | Type | Wiring |
|---|---|---|
| Notices the cursor | toggle, on | guard on `pointer.enter` → watching |
| Greets on click | toggle, on | guard on `pointer.click` → greeting |
| Naps in Low Power Mode | toggle, on | guard on `power.lowPowerMode` → asleep |
| Wanders on her own | toggle, **off** | routes into a non-quiescent idle |
| Wander pace | slider 0.5–2 | `scaleBy` on the non-quiescent idle |

Wandering adds a state `idle_restless`: the idle clip, the same interrupts as
`idle`, a duration of 20–60 s scaled by Wander pace, and `next` → walking. Each
transition that targets `idle` becomes a pair guarded by the flag, so the pet
lands in `idle` (quiescent, zero timers, as measured) when wandering is off and
in `idle_restless` when on. After a self-started walk she settles and reads as
today. Turning the toggle on while she is in quiescent `idle` takes effect the
next time she returns to idle; that is acceptable and documented.

Manifest identity: `license: CC-BY-NC-4.0`, `author: Mokshagna`; `LICENSE` and
`CREDITS.md` updated, including the provenance of the generated source sheets.

## Bundling

- `Scripts/bundle.sh` bundles every pack in `BUNDLED_PACKS` (Makefile variable,
  default `Packs/klien Packs/Norn`) with one shared rsync rule: only the manifest,
  the files it references, `LICENSE`, `CREDITS.md` and `README.md` are shipped.
  No per-pack branch.
- `Scripts/check-app.sh` / `make app` checks assert `pack.json`, `LICENSE` and
  `CREDITS.md` for every bundled pack and that no reference/draft/gallery file
  shipped.
- The "bundled loads identically" check covers every bundled pack.
- `Scripts/check-separation.sh` currently calls `rg`, which is not installed here,
  and still prints OK. It falls back to `grep`, fails if neither search can run,
  and searches for every reference pack name.

## Testing

Test-first in the existing runners:

- Engine selftests: typed knob decoding; toggle → flag guard; `weightBy` scaling,
  zero, and all-zero fallback; knob thresholds; each validation rejection; format
  1 packs unchanged.
- `packtool validate` tests for the same rejections.
- Klien and Norn Director tests: defaults match the previous behaviour; each
  toggle and slider changes the reachable transitions as tabled; Norn with
  wandering off never requests a wake from idle.
- App checks: toggle persistence, reset, live application without restart,
  first-run default from the plist key, zero-pack state.
- Final: `make test`, `engine-test` with both packs, `app-test`, `norn-test`,
  `separation`, `app`.

## Documentation

`Docs/PACK_FORMAT.md`, `CLAUDE.md` status and §5/§8a, `left.md`, both pack
READMEs, `Docs/product-acceptance.md`.
