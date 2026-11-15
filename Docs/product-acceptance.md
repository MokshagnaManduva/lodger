# Settings, imports and desktop acceptance

Updated 2026-09-30. Settings/import implementation has advanced; live desktop
acceptance is still open. Energy certification is deferred at the owner's request.

## Implemented locally

- Character selection with a static pack preview and metadata.
- Allowed integer sizes, per-character persistence, and reset of size/personality defaults.
- Position preservation during resize, character switching, reset and active-pack replacement.
  Placement is clamped to the selected display's valid bounds when necessary.
- Volume and sound controls. Personality sliders show knobs referenced by state
  duration `scaleBy`; changes apply to subsequent state-duration calculations.
  Klien's unused `sleepAfter` declaration is not shown as a functioning control.
- Add/reveal actions in Settings and the menu; removal of installed packs to Trash.
  Bundled/development source folders are protected. Removing an override exposes the
  underlying source/bundled pack, or selects another character when necessary.
- Failed imports and imports of unrelated characters preserve the running pet.
  A successful replacement of the active ID reloads it and preserves its position.
- Settings refreshes on pack/user changes. The Settings controller is created on
  demand; no background refresh timer was added.
- Preview reads recheck path containment through `PackStore`.

Reset applies to the selected character's size and personality values. Sound and
volume are global preferences and are not reset by this action. Restarting an active
character for resize/reset/replacement restarts its action at its initial state.

## Behaviour controls — 2026-11-15

Settings now shows, per character, a checkbox for each toggle and a slider with a
formatted readout for each slider the pack declares and uses, under the pack's group
headings. Changes apply to the running character without restarting it and are saved
per character; Reset restores them with size. Klien exposes nine controls and Norn five.

The 55 app checks cover defaults on first activation, live application to the same
running pet, persistence across controllers and switching, reset, rejection of a value
of the wrong kind, the `controls.changed` round trip, the rendered control set and the
configured first-run character. They do not exercise real mouse input on the controls;
add these to the next desktop session:

- Drag each Klien slider to 0% and 200% and watch a few minutes of behaviour.
- Set Klien's "Sleep after" to 1 min and confirm he sleeps after a minute idle.
- Switch Norn's "Wanders on her own" on and off; she should react at once both ways.
- Confirm tooltips, group headings, readouts and scrolling in light and dark mode.

## Recorded automated evidence

The September 30 run passed **30/30 app checks**, **306/306 generic engine checks**,
and `make test` (pack validation and both character artwork suites). The app checks
use isolated preferences and a temporary installation directory. Removal tests inject
an operation that moves fixtures to a temporary recovery folder; they verify lifecycle
and preservation without exercising Finder's actual Trash operation.

Covered: applied/saved scales, switching, a fresh controller reading persisted values,
invalid saved scales, reset, volume bounds, personality persistence, invalid imports,
duplicate batches, active/unrelated imports, preserved installed bytes, protected source
packs, removal fallback, and construction of Settings with and without packs.

A fresh controller is not a full process relaunch. Constructing/rendering Settings
is not proof that its native controls, scroll view, file picker or alerts work through
real desktop input. The offscreen render was inspected, and a final scroll-origin
adjustment followed the 30-check run. Rerun the checks and rebuild the bundle before
acceptance. No final bundle acceptance was recorded before the session was interrupted.

```sh
make app-test
LODGER_TEST_PACKS=Packs/klien:Packs/Norn make engine-test
make test
make app
```

The previously recorded **308/308** result includes both working packs on September 22.
That count is historical; the confirmed September 30 default run was 306 generic checks.

## Next desktop session

Use an isolated installation directory and preferences for imports/removal. The
app host supports `LODGER_PROFILE_DIRECTORY=/absolute/path/to/profile`, or a
`LodgerVerificationProfile` plist entry in a separate acceptance bundle. The profile
uses its own `Packs/` subdirectory and a UserDefaults suite based on the profile's
last path component; choose a unique profile name. Production bundles omit the entry.
The locally prepared `build/acceptance/Lodger Acceptance.app` predates the final edits
and must be refreshed before use.

1. Rebuild and launch the final acceptance bundle. Confirm Settings layout, previews,
   selector updates, scrolling, and the zero-pack state.
2. Change each pack's size; switch away/back, quit/relaunch, and check persistence.
   Resize near edges and on mixed-scale displays; confirm position and reachability.
3. Exercise sound/volume and referenced personality sliders; reset one character
   and verify that the other character's preferences are preserved. Audible playback
   requires a validated audio-capable fixture; Klien and Norn are silent.
4. Use Add Character to install a valid folder, replace the active ID, and import
   an unrelated ID. Try invalid artwork/manifests, duplicate IDs, and a mixed-success
   batch; confirm notices, retained bytes, and that failures do not restart the pet.
5. Remove an installed override through the actual Trash UI; verify fallback and
   recoverability. Confirm bundled/source packs cannot be removed.
6. Complete [pointer acceptance](interaction-plan.md): opaque/transparent delivery,
   both facings, stationary-cursor silhouette changes, no stolen keyboard focus,
   nearby/far fast movement, and press/drag/release ownership.

Computer-use approval review rejected opening “Lodger Acceptance” twice, reporting
only “Computer Use was not approved to use Lodger Acceptance”. The owner offered to
enable access, but no successful access or live UI acceptance was recorded. Updated
filesystem permissions do not by themselves establish computer-use app approval.
Do not sign off cross-application pointer routing from app-scoped synthetic clicks;
use actual desktop pointer actions and observe both the pet and the underlying app.

Record the build, pack versions, displays, observed results and defects. After these
checks, proceed through the remaining drag/fall/walk/system-event groups and resume
[energy verification](energy-protocol.md) when the owner schedules a quiet battery run.
