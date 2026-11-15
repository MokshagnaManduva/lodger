# Norn Deployment and Behaviour Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Packs declare sliders and toggles that the engine applies generically; Klien and Norn both gain controls; Norn ships in the app bundle.

**Architecture:** `tuning` entries become typed (slider or toggle). Sliders scale durations (`scaleBy`), transition weights (`weightBy`) and event thresholds (`{"knob": name}`); toggles feed the existing `flag` guard. The Director stays pure; `Pet` passes values in; the app persists them per pack.

**Tech Stack:** Swift 5.9 / AppKit, Python 3 packtool, plain-executable selftests (no XCTest).

**Spec:** `Docs/superpowers/specs/2026-11-15-norn-deployment-behaviour-controls-design.md`

## Global Constraints

- No character name, knob name or behaviour in `Engine/Sources` (Rule 1).
- No new timer, poll or display link; pack defaults cost what they cost today (Rule 2).
- Schema accepts `format` 1 and 2; new features require 2; format 1 packs behave as before.
- The embedded schema (`PackSchema.swift`) is regenerated with `python3 Scripts/embed-pack-schema.py`; only the keywords that script allows may be used.
- Norn: `license: CC-BY-NC-4.0`, `author: Mokshagna`.
- Commit and push after every task. `site/` and `.github/workflows/site.yml` stay uncommitted.

## Review Focus

1. A saved preference whose type no longer matches the pack (slider saved, entry now a toggle, or the reverse): the pack default is used, no crash.
2. Every weighted option scaled to zero: the Director falls back to unscaled weights rather than stalling.
3. A knob threshold changed while an idle watcher is armed: the watcher re-arms to the new value.
4. A format 1 pack that uses `flag` with an undeclared name: still loads, guard reads false.
5. Norn with wandering off: `idle` stays quiescent and requests no wake; toggling on does not restart her.

Each is pinned by a check in the owning task below.

---

### Task 1: Engine model and Director

**Files:** `Engine/Sources/LodgerEngine/Pack.swift`, `Director.swift`; test `Engine/Sources/lodger-selftest/ControlChecks.swift` (new, called from `main.swift`).

**Produces:**
- `Pack.Knob`: `label`, `kind: Kind` (`.slider(min:max:defaultValue:)` / `.toggle(defaultValue: Bool)`), `group: String?`, `description: String?`, `unit: String?`; conveniences `min`, `max`, `defaultValue` (0/1/0-or-1 for toggles), `isToggle`.
- `Pack.Transition.weightBy: String?`; `Pack.EventRef.knob: String?` and `func threshold(_ tuning: [String: Double]) -> Double?`.
- `Pack.requestedEvents(tuning:)`; the old property calls it with `[:]` plus knob defaults.
- `Director.flags: [String: Bool]`; `timeout` applies `weightBy` with the all-zero fallback; `deliver` compares against `threshold(tuning)`; `timeout`/`deliver` overlay `flags` onto the context.

- [ ] Write failing checks: typed decoding (slider, toggle, metadata, toggle with `min` rejected, non-boolean toggle default rejected); flag guard follows `Director.flags`; `weightBy` 0 removes an option over 200 seeded draws; all-zero fallback still returns a plan; knob threshold fires at the tuned value and not at the old one.
- [ ] Run `make engine-test`; confirm they fail to compile or fail.
- [ ] Implement; run until green with the previous 308 checks intact.
- [ ] Commit and push.

### Task 2: Schema v2 and validation

**Files:** `Schema/pack.schema.json`, `Engine/Sources/LodgerEngine/PackSchema.swift` (generated), `PackValidation.swift`, `Tools/packtool/packtool.py`, `Docs/PACK_FORMAT.md`; tests in `PackValidationChecks.swift` and a new `Tools/packtool/test_controls.py` wired into `make test`.

- [ ] Failing checks for each rejection: `weightBy` / `scaleBy` / event `knob` naming an undeclared entry or a toggle; `flag` naming an undeclared entry or a slider in format 2; the same `flag` accepted in format 1; any new feature in a format 1 pack rejected; slider default outside range.
- [ ] Schema: `format` enum `[1, 2]`; `tuning` entries `oneOf` slider/toggle; `weightBy` on `next`; parameterised events accept a number or `{"knob": string}`; `weight` stays exclusive-minimum 0.
- [ ] Implement the semantic rules in `PackValidation.validate` and mirror them in `packtool.py validate` (shared rule list: same messages).
- [ ] Regenerate the embedded schema; run `make test engine-test`; commit and push.

### Task 3: Pet wiring

**Files:** `Engine/Sources/LodgerEngine/Pet.swift`; tests in `ControlChecks.swift`.

- [ ] `public var flags: [String: Bool]` forwarding to the Director; `tuning.didSet` recomputes `wants` via `requestedEvents(tuning:)` and re-arms the idle watchers when started.
- [ ] Check (Review Focus 3): with a pack whose `user.idle` threshold is a knob, changing tuning changes the armed deadline; no scheduler timer appears in a quiescent state.
- [ ] Commit and push.

### Task 4: App preferences and Settings

**Files:** `Engine/Sources/lodger/Preferences.swift`, `AppController.swift`, `SettingsWindow.swift`, `main.swift`, `Scripts/bundle.sh` (plist key); test `Tests/AppChecks/main.swift`.

**Produces:** `Preferences.flags(for:)`, `setFlags(_:for:)`, `resolvedFlags(for: Pack)`; `resolvedTuning` covers sliders only; `AppController.setFlag(_ value: Bool, name: String, for id: String)`; `AppController.defaultPackID` read from Info.plist key `LodgerDefaultPack`.

- [ ] Failing app checks: toggle persists per pack; reset clears it; `setFlag` updates the running pet without recreating it (same `Pet` instance); mistyped saved value falls back to default (Review Focus 1); first activation honours the default ID; zero-pack state still constructs Settings.
- [ ] Settings: grouped controls, checkbox per referenced toggle, slider plus value label (formatted by `unit`) per referenced slider, tooltip from `description`.
- [ ] `make app-test`; commit and push.

### Task 5: Klien controls

**Files:** `Tools/packtool/animate_klien.py`, regenerated `Packs/klien/pack.json` and `reference/all-scenarios-v1/pack.json`, `Tools/packtool/test_klien_director.swift`, `Packs/klien/README.md`.

- [ ] Extend the Director test first: with defaults the transition distribution and interrupts match the 0.4.0 pack; each slider at 0 removes its transition; each toggle off blocks its interrupt; `sleepAfter` moves the `user.idle` threshold.
- [ ] Add the controls tabled in the spec; `format: 2`, version `0.5.0`.
- [ ] `make klien-animations`; confirm art outputs are byte-identical apart from manifests; commit and push.

### Task 6: Norn controls and licence

**Files:** `Packs/Norn/reference/runtime-v1/pack.source.json`, regenerated `Packs/Norn/pack.json`, `Packs/Norn/LICENSE`, `CREDITS.md`, `README.md`, `Tools/packtool/test_norn_director.swift`, `Tools/packtool/test_norn.py`.

- [ ] Extend the Director test first: defaults reproduce the existing 59 checks; wandering off → entering idle yields `Wake.none` (Review Focus 5); wandering on → returns to `idle_restless`, which times out into walking; each toggle off blocks its interrupt.
- [ ] Add `idle_restless`, the flag-guarded pairs, tuning, `format: 2`, version `0.4.0`, licence and author.
- [ ] `make norn-animations norn-test`; commit and push.

### Task 7: Bundling and checks

**Files:** `Scripts/bundle.sh`, `Makefile`, `Scripts/check-separation.sh`, `.github/workflows/engine-ci.yml` if it names packs, selftest §8a section.

- [ ] `BUNDLED_PACKS` loop; a small Python helper lists the files a manifest references so only those plus `LICENSE`, `CREDITS.md`, `README.md` ship.
- [ ] `release-check` asserts manifest, licence and credits per bundled pack and no `reference`, `drafts`, `.html` or `.js` under `Resources/Packs`.
- [ ] Separation script: `grep` fallback, hard failure if no search tool, loop over reference pack names.
- [ ] `make app release-check separation`; launch the bundle with each pack for a smoke test; commit and push.

### Task 8: Documentation

- [ ] `Docs/PACK_FORMAT.md` (controls section), `CLAUDE.md` status / §5 / §8a, `left.md`, `Docs/product-acceptance.md`.
- [ ] Full run: `make test`, `LODGER_TEST_PACKS=Packs/klien:Packs/Norn make engine-test`, `make app-test norn-test separation app`; commit and push.
