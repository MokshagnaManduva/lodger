# Current status and remaining work

Updated 2026-09-30 from the working tree and recorded session results. **Lodger is a working development build,
not a completed public release.** Changes are still local and uncommitted. This file is the
current checklist; historical plans and passing component tests do not override it.

## Where we are

| Area | Implemented locally | Still needed |
|---|---|---|
| Core companion | Menu-bar app, pack discovery, Klien animations, cursor reactions, clicking, dragging, falling, render-server walking | Complete live interaction acceptance |
| Settings / pet management | Character selector, static preview/metadata, sound/volume, referenced personality controls, add/reveal/remove-to-Trash and reset | Live control/layout/file-picker/Trash acceptance on the final bundle |
| Size and persistence | Allowed integer scales, per-pack saved sizes, default reset, position-preserving recreation; automated switching/persistence checks | Full process relaunch, edge cases and mixed-display desktop verification |
| Pack import | Runtime schema/semantic/asset validation, contained paths, ID-based staged replacement, collision and rollback tests, preserved-backup notices; failed/unrelated imports retain the active pet | Live import UI acceptance; automatic recovery after process/power loss is not implemented |
| Authoring | Existing build/validation/anchor tools; new scaffold and static texture contact sheet | Valid usable starter pack, reproducible generic animation generation, animated previews/anchor traces, doctor, remaining generic lint |
| CI | macOS workflow and local engine/pack separation script | Observe a hosted run; strengthen separation coverage beyond selected asset extensions and one character-name search |
| Art | Existing active Klien pack; turnaround/perch concept references | Native runtime turnaround, transition polish and art acceptance; perch remains deferred |
| Branding / licenses | Generated icon, About panel, MIT text and pack CC-BY-NC notice/credits | Owner approval of license choice, asset provenance/attribution and branding; support metadata |
| Packaging | Local bundle, Developer ID signing target, guarded archive/notarization scripts | Actual credentialed signing, accepted notarization, final distribution and clean-machine install test |
| Updates | Manual HTTPS feed check opens an archive URL; release tool verifies Ed25519 archive signatures | Hosted feed/key configuration, end-to-end delivery; in-app authenticated download and automatic installation |

The import loader now validates manifests, state references, images, sounds and masks;
rejects unsafe paths and symlinks; and replaces by pack ID. Injected move failures verify
restoration and preservation of the previous copy. Recovery failures retain and identify
the backup. See [the exact guarantees and limits](Docs/pack-installation.md), including
manual recovery after interruption between filesystem renames.

`packtool generate` creates directories and an incomplete manifest. It generates no artwork
and its output is not immediately valid or runnable. `preview` is a static atlas contact sheet.

## Verification evidence

### Norn bundled; pack-declared behaviour controls — 2026-11-15

Pack format 2 adds typed `tuning` controls (sliders and toggles), `weightBy`,
slider-valued event thresholds and `controls.changed`. Klien 0.5.0 has nine controls
and Norn 0.4.0 five; both are bundled in `Lodger.app` by one rule, with Klien as the
first-run default. The owner confirmed Norn's licence as CC BY-NC 4.0.
See [the design](Docs/superpowers/specs/2026-11-15-norn-deployment-behaviour-controls-design.md).

Recorded results on branch `norn-deployment`: **349/349 engine checks** with both
packs (347 generic), **55/55 app checks**, **92 Norn Director checks**, Klien Director
and art checks, `make test`, `make separation`, `make release-test` and
`make release-check` passed. The built bundle was launched from outside the repository
and discovered both bundled packs; a zero-pack bundle launched to the empty state.

**Settings redesign and app-level controls (same day).** Settings has Character,
Behaviour and General tabs. General adds Show character, Opacity, Stay in place,
Calmer on battery and Launch at login; Behaviour adds a reset per slider and a
whole-behaviour reset. The About panel now lists installed characters from their
manifests instead of naming one in source, and the separation check catches that case.
Results after this step: **358/358 engine checks** with both packs and **76/76 app
checks**. Each tab is rendered offscreen to `build/settings-<character>-<tab>.png`
during `make app-test` for inspection.

Still open from this work:

- Launch at login has only been exercised through a test double; it needs a run from
  the built app (and ideally a signed one).
- Calmer on battery and Stay in place are verified at the Director and controller
  level, not by watching a character for a while on battery.
- Quiet hours and a home-display choice were considered and left out; see the spec.

- Live desktop acceptance of the new sliders and checkboxes in Settings. The automated
  checks construct the controls and drive the controller, not real input.
- Energy measurement of Norn with wandering **on**, and of Klien at non-default slider
  values. Defaults are unchanged in cost by construction, not by a new measurement.
- With Klien's cursor watching switched off, the pointer monitor stays installed because
  clicks and grabs still need it.
- Appearance variants (palette swaps plus prop options) are agreed but not started.
- `site/` and `.github/workflows/site.yml` remain uncommitted local work.

### Settings/import correctness — 2026-09-30

Added preview/metadata, removal to Trash, reset, volume and referenced personality
controls. Resize, switching and active replacement preserve screen position. Failed
and unrelated imports preserve the running pet. Settings is created on demand.

Recorded results: **30/30 app checks**, **306/306 generic engine checks**, and pack/art
checks passed. App checks cover temporary installs, saved sizes, reset, personality,
import rejection/replacement and removal fallback. Removal uses a temporary recovery
folder in tests; actual Trash and file-picker acceptance remain open. A final scroll-origin
adjustment followed these checks, so rerun `make app-test` and rebuild before live acceptance.
The final bundle/live acceptance was not completed before the session interruption.

Computer-use approval review rejected opening the isolated acceptance app. The owner
offered to enable access; no successful access was recorded. Hardware click delivery,
focus preservation and the live Settings/import workflows remain unsigned off.
See [the acceptance record and next-session checklist](Docs/product-acceptance.md).

### Norn animation polish — 2026-09-25

Local pack v0.3.0 adds alternating walk silhouettes, a visible flask-to-belt
transfer for greeting, and dedicated sitting/standing poses. Reading shares the
seated endpoint; greeting and standing return to the canonical neutral pixels.
There are 58 stored cells (including copied endpoints), 12 clips and 12 states.
See [polish notes](Packs/Norn/reference/polish-v3/README.md). The behavior graph
and generic engine are unchanged. Full desktop and energy acceptance remain open.

### Norn art and runtime milestone — 2026-09-22

Norn now has a local development pack with 34 registered native cells, 12 clips,
12 states, alpha hit masks, a reproducible compiler and an offline runtime
gallery. Original reference/draft image bytes are retained. Character behavior
uses the existing generic engine. `make norn-test` checks art and Director
behavior; `make norn-pack` exports runtime assets to `build/Norn.pack`.
Sleep, held and falling now each have six distinct poses; no runtime clip is
single-frame. See [Norn's notes](Packs/Norn/README.md) and
[current verification](Packs/Norn/reference/motion-v2/verification.md).

The September 25 polish supersedes the earlier walk/greeting/seated-transition gaps.
Still open: arbitrary-interrupt/prop continuity polish, the high-five/page/sneeze concepts,
full desktop interaction and energy acceptance, and character provenance/distribution
license confirmation.
Norn was not bundled at that milestone; she is bundled as of 2026-11-15 (see above).

### Pack validation and import milestone — 2026-09-22

Runtime schema, semantic and asset validation and ID-based replacement are implemented.
`LODGER_TEST_PACKS=Packs/klien:Packs/Norn make engine-test` passed **282/282 checks**
(280 generic checks plus the two working character packs). `make test`, `make separation`
and `make release-test` passed; release regressions remain 7 Python tests and 12 Swift checks.
The new checks cover corrupt manifests/images/masks, paths and symlinks, duplicate IDs,
legacy folder replacement, collisions, and commit/restoration failure with preserved bytes.
See [installation policy](Docs/pack-installation.md). Live import UI acceptance and
manual recovery after abrupt termination remain separate from these automated checks.

### Stationary-cursor routing milestone — 2026-09-22

Frame-boundary routing, shared animation timing and scoped continuous-motion hover tracking
are implemented. Stationary cursors update in both opacity directions; stable pixels and
cursor-away cases add no animation timer. Walking targets its current displayed position;
pet-owned presses keep their drag/release. The final local suite passed **308/308 checks**
including both working packs; pack/art and separation checks and the ad-hoc app build passed.
See [interaction evidence](Docs/interaction-plan.md). Hardware click delivery/focus and the new hover energy measurements remain acceptance work.

### Previous project checks

Last recorded local results, not a new test run during this documentation update:

- Pack/character checks passed.
- Engine self-tests passed: **205/205**.
- Release/update regressions passed: **7 Python tests and 12 Swift checks**.
- Local separation check, app build, and bundle/plist checks passed.
- Ad-hoc bundles were rejected by the distribution archive check; missing notary credentials
  were rejected before archive modification.
- App launch was smoke-tested. That does not verify Settings controls, import recovery,
  size persistence, or update delivery end to end.
- Hosted CI and successful Apple notarization have not been observed.

The release tests cover archive signature rejection, preservation after failure, notarization
sequence using test doubles, and feed selection/parsing. They do not exercise Apple's service
or a production update server.

## Energy: verification started; certification deferred

On **2026-09-30 the owner deferred the quiet, battery-powered hour-long samples** to
another session. No new energy pass or certification was recorded. The Mac was on AC
power, and a privileged `sudo -n powermetrics` probe reported that a password was required.
Resume measurement after desktop acceptance and a final release build; retain the
protocol's CPU, wakeup, WindowServer, memory, power and Energy Impact requirements.

Five 60-second normal-behavior Klien samples had a median of **17.38 CPU seconds/hour**.
The socketed fixture median was **1.21**; the blinker fixture median was **15.94** with a wide
spread. These are short process-CPU measurements. Normal autonomous behavior is not an
isolated-idle test, and the observations do not establish the source of the variation.

Retain the **<7 CPU seconds per idle hour** target. Repeat isolated-idle and normal-behavior
runs separately on a quiet machine; measure WindowServer, wakeups, memory, package power and
Energy Impact. Recheck the final app after product changes. The energy gate is not implemented.
See [measurement history and scope](Docs/energy-protocol.md).

## Next work, in order

1. **Rebuild and finish Settings/import desktop acceptance.** Rerun `make app-test`,
   include both packs in engine checks, and rebuild the app. Exercise previews, selectors,
   actual import dialogs/Trash, reset, persisted sizes after relaunch and screen position.
2. **Complete pointer and desktop acceptance.** Verify opaque/transparent clicks and focus
   with actual desktop input, then drag from each action, interrupt walking, land/recover,
   test mixed displays and sleep/wake/low power/occlusion, and confirm display-link shutdown.
3. **Resume energy verification when scheduled by the owner.** Quiet machine on battery;
   isolated idle, normal use and hover measured separately, plus whole-system A/B evidence
   and a reproducible gate. Energy is deferred, not passed.
4. **Complete art and author tools.** Runtime turnaround, transition review, generic authoring
   functionality and a hosted CI run on a clean checkout.
5. **Complete public release.** Confirm license/provenance and branding, configure signing and
   update keys/hosting, notarize, then verify fresh install and update delivery.

Perching is excluded from the current runtime and belongs in
[future ideas](Docs/future-ideas.md). Its concept art does not reactivate the feature.

The public website is tracked separately in [site/STATUS.md](site/STATUS.md). It does not
block the acceptance steps above. Root license/credits files exist; their presence does not
complete owner approval or asset provenance review.

## Commands and references

```sh
make test
make app-test
LODGER_TEST_PACKS=Packs/klien:Packs/Norn make engine-test
make release-test
make separation
make release-check
```

`release-check` rebuilds an ad-hoc bundle. Run it before signing. Follow
[the release sequence](Docs/release.md) for Developer ID signing, notarization and generating
the feed without changing a signed archive.

Read [interaction acceptance](Docs/interaction-plan.md),
[the pack contract](Docs/PACK_FORMAT.md), and [the documentation index](Docs/README.md).
