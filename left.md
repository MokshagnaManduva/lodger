# What is left

Updated 2026-09-16. This is the main remaining-work checklist. Work through the
interaction groups in order, fixing defects and recording evidence before marking
a group complete. Detailed interaction findings: [Docs/interaction-plan.md](Docs/interaction-plan.md).

## Current state

- Working app and complete first-pass Klien scenario set, including sun-emblem
  toss/catch, both walking directions and revised compact crouching poses.
- Default display scale is **1x**, half the previous width and height. Size UI is
  not built yet; the smaller default is already in the pack and rebuilt app.
- Group 1 code corrections are implemented; **220/220 engine checks** and the
  pack/art checks passed. Actual desktop click-through/focus sign-off is open.
- **Falling is still jittery. The fix has NOT been applied.** Address it in Group 3.
- Historical isolated-idle process CPU median was 3.12 s/hour against a <7s target
  at the former 2x scale. This is not a new 1x measurement or a system-power claim.

## 1. Interactions — execution order

### Group 1: pointer and clicks — finish live verification

Implemented: mirrored alpha targeting, moving-cell proximity, correctly ordered
monitor startup, high-frequency pointer velocity, nearby-only fast reactions,
click handling while watching, pointer-facing updates and click-on-release.

- [x] Verify slow approach/watch and leaving from both sides at the new 1x size.
- [x] Click opaque body/emblem pixels: correct reaction and no underlying click.
- [x] Click transparent corners/gaps: underlying controls receive the click.
- [x] Verify another app retains keyboard focus when Klien is clicked.
- [ ] Repeat after facing flips and with a stationary cursor while poses change;
      investigate any stale mask routing without introducing idle polling.
      **CONFIRMED DEFECT (2026-09-18):** facing-flip re-click works, but a
      stationary cursor through a pose/frame change inside the same clip clicks
      on the stale (previous) silhouette. `PointerMonitor.sample()` only
      re-runs on mouse-move and Director state transitions (`Pet.swift:417,723`),
      never on an intra-clip frame advance (render-server-only animation).
      Proposed fix: schedule a one-shot wake at the current clip's next frame
      boundary while the cursor is over the silhouette, mirroring the per-frame
      sound scheduling pattern (§6.11) - not a recurring poll. Not yet implemented.
- [x] Verify fast nearby sweeps startle, distant sweeps do not, and repeated
      silhouette entry/exit remains reliable.

The native automation tool could not reliably target the nonactivating pet panel.
Clicks scoped to a background probe app do not prove OS-level click-through.
Do not mark these checks passed based on that probe alone.

### Group 2: grab and drag

- [ ] Grab from idle, walking, sitting and tossing without jumping.
- [ ] Preserve the original grab point; stop the previous action correctly.
- [ ] Confirm dragging does not also trigger a click/hat tip.
- [ ] Verify repeated grabs and releases leave valid interaction state.

### Group 3: release, fall and land — required jitter fix

- [x] Reproduce the reported jitter from low, medium and high release positions.
- [x] Separate choppy translation from pose flicker, integer snapping and dt issues.
      Isolated to window-move cadence, not pose/frame timing (see below).
- [x] Decouple falling physics updates from animation frame timing. Implemented
      a **60 Hz falling-only** display link (`Pet.startLink()`) while preserving
      discrete sprite poses (`apply`/`visibleCell` unaffected).
- [x] Verify stable release position, smooth monotonic descent, correct floor,
      no overshoot/bounce, exactly one landing, and clean standing recovery.
      Confirmed working on the desktop (2026-09-18) after the fix.
- [ ] Confirm the display link stops after settling and remains absent in idle
      and render-server walking; measure active-fall cost. Not yet separately
      measured/verified.

**Fixed (2026-09-18):** `Pet.startLink()` used `clipFrameRate`, clamped to
8–30 Hz, for the falling display link too. The 140ms fall frames requested about
**8 Hz for actual physics/window movement**. That policy was justified by older
per-tick walking; walking now runs in the render server and starts no display
link at all (`beginWalk` calls `motion.begin(.none, ...)` deliberately). Falling
now uses a fixed 60 Hz cadence when `motion.kind == .fall`; every other
display-link case (spring-only settling) keeps the original clip-paced cadence.
220/220 engine checks still pass; owner confirmed the descent feels smooth.

### Group 4: walking and interruption

- [ ] Verify left/right travel, screen edges, turning and resuming.
- [ ] Grab mid-step without moving the pet away from its visible position.

### Group 5: pose transitions and emblem

- [ ] Review actual sit/stand, hat-tip and toss/catch transitions at 1x.
- [ ] Interrupt each action; check hand/emblem attachment and valid recovery poses.
- [ ] Obtain owner acceptance of the current shoulder, leg and crouch artwork.

### Group 6: perch acquisition

- [ ] Drop onto an eligible window with perching enabled and permission granted.
- [ ] Verify disabled mode, missing permission and invalid/empty-space fallbacks.
- [ ] Keep default operation free of permission prompts.

### Group 7: perch tracking and loss

- [ ] Follow window moves/resizes using the single-window AXObserver path.
- [ ] Recover after minimize, close, hide, app quit, fullscreen and Space changes.
- [ ] Verify actual tracking; policy tests alone do not establish this works.

### Group 8: displays and recovery

- [ ] Drag across displays with different scales.
- [ ] Handle display removal, rearrangement and off-screen saved positions.
- [ ] Confirm the pet remains reachable and uses the correct floor/perch coordinates.

### Group 9: idle and system events

- [ ] Verify inactivity, sleep/wake, low-power mode and occlusion transitions.
- [ ] Confirm quiescent states leave no unwanted timers or display links.

## 2. Energy verification

After interactions stabilize:

- [ ] Longer quiet-machine soaks using normal autonomous character behavior at 1x.
- [ ] WindowServer overhead, including the walk-wide transparent window.
- [ ] Actual idle wake-ups using timer/power instrumentation.
- [ ] Package power delta, resident memory and Activity Monitor Energy Impact.
- [ ] Implement the documented `make energy-check` release gate.

Retain the **<7 CPU seconds per idle hour** target. Keep process CPU, compositor
cost and whole-system power separate; report medians/spreads and measurement scope.
Historical evidence: [Docs/energy-protocol.md](Docs/energy-protocol.md).

## 3. Pet-management and settings UI — requested

- [ ] Build a dedicated window to browse installed pets with previews and select
      the active pet; add/manage user-installed packs.
- [ ] Make imports/replacements safe and report errors. Current import deletes
      the destination before copying and suppresses failures.
- [ ] Add per-pet size controls using the pack's allowed integer `scaleSteps`
      (currently 1x/2x/3x), a preview and reset-to-default action.
- [ ] Persist chosen sizes across relaunches and pet switches.
- [ ] Apply size changes consistently to rendering, window geometry, hit testing,
      screen/perch positioning and off-screen recovery.
- [ ] Expose pack-defined personality controls, sound, volume and perching.

One active pet remains the default scope. Managing several installed pets does not
mean running them simultaneously. The UI is a committed backlog item, not optional.

## 4. Remaining character work

- [ ] Full turnaround; the current animation is a front-facing pivot.
- [ ] Distinct dangling-leg perch; current artwork shares the seated pose.
- [ ] Further limb/costume shading and transition polish based on visual review.
- [ ] Decide whether to add Klien sounds; author assets/triggers if selected.
- [ ] Verify system mute and implement or revise the documented Do Not Disturb
      promise before shipping sound. Playback infrastructure already exists.

## 5. Authoring tools and validation

- [ ] Generic `packtool preview` with animated contact sheets and anchor traces.
- [ ] Reproducible `packtool generate`; choose its backend when undertaking this.
- [ ] `packtool new` scaffolding and `packtool doctor` installed-pack diagnosis.
- [ ] Reconcile promised generic palette/proportion lint and ground registration
      with actual behavior; the build currently reports drift rather than fixing it.
- [ ] Add/reconcile full runtime manifest/schema/capability validation. Current
      loading decodes the manifest and checks referenced files.
- [ ] Add CI enforcement of engine/character separation and required checks.

Klien's custom generator/gallery already work; generic author tooling can follow
UI/release work unless enabling other pack authors becomes the immediate priority.

## 6. Release preparation

- [ ] App icon and branding.
- [ ] Choose the engine license and confirm Klien's license; replace placeholders.
- [ ] Add accurate LICENSE/CREDITS and an About presentation.
- [ ] Developer ID signing and notarization; current bundles are ad-hoc signed.
- [ ] Direct-download packaging and Sparkle updates.

## Documentation and evidence maintenance

- [ ] Keep this checklist current as each group is verified; record unresolved
      defects in their dependency group and fix them when that group is reached.
- [ ] Reconcile remaining format/architecture promises during the related work:
      DND, runtime validation, generic lint, release gates and CI.
- [ ] Keep old measurement/art records labeled historical. Menu diagnostics exist;
      the previously described option-click HUD does not.

Do not re-plan completed work: app shell/menu discovery, all 24 events, mirroring,
per-part hit testing, render-server animation/walking, spring lag, tuning application,
audio plumbing and the first complete character pack. `orientFrames` was deliberately
removed. The archived approved idle art remains preserved.
