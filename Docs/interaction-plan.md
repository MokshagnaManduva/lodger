# Interaction verification workflow

Agreed order, 2026-09-16. Work through each group, fix observed defects, record
repeatable checks and distinguish automated evidence from real desktop testing.
Do not mark a group complete solely because its animation gallery looks correct.

| Order | Group | Acceptance | Status |
|---|---|---|---|
| 1 | Pointer and clicks | Correct opaque/transparent targeting in both directions; approach/watch/click/fast reactions; no stolen focus | Code corrections implemented and automated checks pass; real desktop routing/focus sign-off remains open |
| 2 | Grab and drag | Grab from idle/walk/sit/toss without a position jump; preserve grab point; stop previous action; no click also firing | Pending; click-on-release prerequisite implemented in Group 1 |
| 3 | Release, fall and land | Release from multiple heights; smooth descent; correct floor; one landing; natural recovery | Fixed and desktop-verified 2026-09-18 (60 Hz falling-only display link); display-link-stops/cost measurement still open, see below |
| 4 | Walking and interruption | Both directions, edges, turn/resume; mid-step grab keeps visible position | Pending |
| 5 | Pose transitions and emblem | Sit/stand/hat tip/toss transitions; interrupted actions leave valid held-emblem poses | Art and Director checks exist; full interaction review pending |
| 6 | Perch acquisition | Drop onto an eligible window; permission/off/invalid-target fallbacks | Pending |
| 7 | Perch tracking and loss | Follow move/resize; recover on close/minimize/hide/quit/fullscreen/Space changes | Pending |
| 8 | Displays and recovery | Mixed scales, cross-display dragging, display removal/rearrangement; pet always reachable | Pending |
| 9 | Idle and system events | Inactivity, sleep/wake, low power, occlusion; no unwanted timers/link | Pending |

After these groups stabilize, run the normal-behavior and whole-system energy
milestone from [the consolidated backlog](../left.md). Full turnaround/dangling-perch artwork stays a
separate art task. Record newly reported defects in the earliest group whose
prerequisites allow a reliable fix.

## Group 1 — findings and implemented corrections

- Mirrored art was tested against unmirrored alpha pixels. Hit targets now carry
  effective mirroring and reflected offsets, including counter-mirrored parts.
- Distance and side used the full walk-wide host window. They now use the moving
  character cell, independently of the transparent travel corridor.
- Startup installed monitoring before layers/callbacks existed. Installation now
  follows setup; state/facing changes refresh routing without recursively
  emitting pointer events. The panel explicitly accepts local mouse-move events.
- High-frequency events repeatedly reset the velocity baseline before the minimum
  interval. The estimator now accumulates short intervals and rejects a stale
  sample after a pause. No polling or extra timer was introduced.
- Approaching Klien entered watching, which ignored clicks. Watching now accepts
  click/fast reactions. Fast reactions require a pointer within 60 screen points
  of the character cell, preventing distant screen motion from startling him.
- Pointer-following states update facing when the cursor changes sides. Pointer
  side/facing are also supplied to guard evaluation.
- Pressing the mouse used to fire a click before drag intent was known. Clicks
  now fire on release only if no drag occurred; double-click count is preserved.
  The nonactivating view accepts first mouse without requesting key/main status.

### Evidence and remaining desktop checks

`make engine-test` passes **220/220 checks**; `make test` passes all validator
and art checks. The release app was rebuilt with the Group 1 runtime fixes.
Engine tests cover asymmetric masks at 1x/2x/3x, mirror bounds/current atlas cells,
part mirroring, cell-relative proximity, high-frequency velocity and pauses,
click-versus-drag lifecycle, and non-key panel configuration. Klien Director
checks cover click from idle/watching, nearby fast reaction and distant rejection.
Native art validation remains clean.

The temporary desktop probe confirms that its own click counter and focused text
field work. The CUA native tool could not reliably target Lodger's nonactivating
panel (`AXError.notImplemented`); clicks scoped to the background app are not
proof of OS-level click-through. Focus changes caused by selecting apps through
the tool must not be attributed to pet clicks. Live logs include approach/startle
reactions, but are not a controlled hover/exit or focus test.

Still required, using actual desktop pointer actions:

1. Focus a text field in another app. Approach slowly from both sides; Klien should
   watch and face the cursor. Leaving should allow the normal timeout to idle.
2. Click solid body/emblem pixels: a hat tip; underlying app receives no click;
   its existing keyboard focus remains usable. Repeat after facing flips.
3. Click transparent corners and gaps: the underlying control receives the click.
4. Repeat as the pose changes with the cursor stationary. Routing is refreshed on
   mouse moves/state/facing changes, not every animation frame; validate this
   boundary explicitly and fix any stale-target defect without adding idle polling.
5. Sweep quickly nearby: startle. Sweep far away: no startle. Verify entering and
   leaving the silhouette continues to work after repeated clicks.

### Reproduce automated checks

```sh
make klien-animations
make test
make engine-test
make app
python3 Tools/packtool/verify_klien_runtime.py --behavior
```

## Group 3 — jittery falling (fixed 2026-09-18)

**Owner report:** Klien's descent was visibly jittery. Diagnosed and fixed ahead
of Group 2 sign-off (root cause was already isolated in code) at the owner's
request; grab/drag itself remains separately open.

**Root cause:** `Pet.startLink()` derived the display-link cadence from
`clipFrameRate`, clamped to 8–30 Hz, for every ticking motion kind including
falling. The four-pose falling clip uses 140ms frames, so the clamp requested
about 8 Hz for actual physics/window movement - visibly coarse translation. The
clamp's original justification was per-tick walking; walking now runs in the
render server and starts no display link at all (`beginWalk` calls
`motion.begin(.none, ...)` explicitly, "deliberately no display link").

**Fix:** `Pet.startLink()` now uses a fixed 60 Hz cadence when
`motion.kind == .fall`, independent of the falling clip's own frame count/
duration. Sprite pose timing is untouched - `apply`/`visibleCell` still hold
each art frame for its authored duration. Every other display-link case
(spring-only settling) keeps the original clip-paced cadence, since that path
was not implicated and walking does not use this display link in the first
place. 220/220 engine checks pass; owner confirmed the descent feels smooth on
the desktop after rebuilding.

Still open, not yet separately verified:

- Confirm the display link stops after settling and stays absent in idle and
  render-server walking (expected from the existing `syncDisplayLink`/`stopLink`
  logic, but not independently re-measured after this change).
- Measure active-fall CPU cost at the new 60 Hz cadence.
- Mixed-display falling behaviour stays deferred to Group 8.
