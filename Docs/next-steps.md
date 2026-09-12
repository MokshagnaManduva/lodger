# Next: render-server locomotion

Written 2026-09-12, before implementation. The previous round's plan is complete;
`git log` has the record.

## Why

Walking costs **2.4% of one core** (down from 4.5%), and it is the only genuinely
expensive path in the engine. Measured cause: a window move costs ~340-450 us once
the deferred Core Animation commit is counted, and locomotion makes one per tick.
A pet walking 5% of the day costs ~4.3 s CPU/hour against a 2 s target.

Full measurement, including the two wrong guesses eliminated on the way, is in
`Docs/energy-protocol.md`.

## The mechanism

Stop moving the window during a walk. Commit one animation instead, and go idle -
the same trick sockets already use.

On entering a walk state:

1. **Compute the segment.** `startX` is the current feet x; the Director has already
   chosen the state's duration.
   ```
   travel        = speed * plannedSeconds
   endX          = clamp(startX +/- travel, world.left, world.right)
   actualSeconds = |endX - startX| / speed
   hitEdge       = actualSeconds < plannedSeconds
   ```
2. **Resize the window once** to span the segment: width `cell + |endX - startX|`,
   origin at `min(startX, endX) - halfCell`. It then stays put for the whole walk.
3. **Animate the host layer's `position`** linearly across the segment, duration
   `actualSeconds`, committed once. Every part is a sublayer, so they all ride it.
4. **Schedule.** If `hitEdge`, override the scheduler's single wake to `actualSeconds`
   and fire `edge.reached`; otherwise the Director's own timeout wake is already right.
5. **`motion.kind = .none`** so `needsTicking` is false and **no display link exists**.

One window resize per walk instead of 10-30 moves per second: one to two orders of
magnitude fewer window-server round-trips.

## The hard parts

**Where is the pet right now?** Needed for a mid-walk grab, for the next state's start
position, and for hit testing. Interpolate: store `walkStartX`, `walkEndX`, `walkStart`,
`walkSeconds`, and lerp on `elapsed / walkSeconds`. O(1), computed only when something
asks - exactly how `visibleCell` already derives the on-screen frame without polling.

**Hit testing mid-walk.** `PointerMonitor.read` maps the cursor into cell coordinates
from `panel.frame` plus `margin`. With a wide window the art sits at an animated offset
inside it, so the monitor needs an `artOffsetX` closure returning the interpolated
position. One lerp per mouse-move event, alongside the `visibleCell` call already there.

**Interruption.** On any transition out of a walk: set `motion.feet.x` to the
interpolated position, remove the position animation, and resize the window back to
`cell + margin` at that point. The new state then proceeds normally.

**Long walks would make a huge transparent window.** A slow, long walk could span most
of a display - and a near-full-screen transparent overlay is exactly what the Tahoe
26.3 hit-testing regression broke. So **cap the segment** (a third of the display width,
or an absolute pixel ceiling) and chain segments for longer walks: a handful of resizes
rather than hundreds of moves, and no window ever much wider than the pet.

**Floats ride rigidly during a render-server walk.** Parts are sublayers of the host, so
they translate with it and do not trail. Trailing needs per-frame work, which defeats
the point. Accept rigid following while walking; if it reads as dead, give the float a
phase-shifted bob rather than reintroducing a tick.

**Multi-display falls out.** The segment is clamped to the current display's world, so
crossing displays happens at a segment boundary and reuses the existing
`edge.reached` -> `Stage.neighbour` path.

**Falling and dragging keep the display link.** Falling is real physics integration and
is brief; dragging is driven by mouse events the OS already delivers. Unchanged.

## Tests

- segment maths: clamping at both edges, `actualSeconds`, `hitEdge` detection
- interpolation at t=0, mid, end, and past the end
- window geometry spans the segment; art offset correct at both ends
- a walk longer than the cap splits into chained segments, none wider than the cap
- **no display link during a walk**: `hasDisplayLink == false`, `linkStarts` unchanged
- a mid-walk grab leaves the pet at the interpolated position, not the segment end
- hit mask still correct mid-walk, with the cursor over the art at t=half

## Verification

- `test.walker` continuous walk: expect close to 0% of a core, against 2.4% today
- assert `linkStarts == 0` across a pure walk
- **SIGSTOP while walking.** If locomotion is genuinely render-server resident, the pet
  keeps walking with the process frozen. That is the same proof already recorded for
  sprite frames, applied to movement, and it is the strongest single check available.

## Risks

- A window resize at each segment boundary may be visible as a hitch. Unknown until tried.
- The wider window moves cost into `WindowServer`, which **cannot be measured on this
  machine** - its own idle baseline drifts +/-2 percentage points. Accepted on reasoning
  rather than evidence: the compositor is already blending that screen region, whereas a
  synchronous IPC round-trip per frame is pure addition. Recorded as unverified.
- A host-layer position animation must compose correctly with the socket and float
  position animations on its children. Child positions are relative, so it should, but
  this needs verifying early - it is the assumption the whole approach rests on.

## After this

Perching (the `AXObserver` path, already designed in CLAUDE.md 4a), then the app shell:
menu bar, settings, pack manager, Sparkle, signing and notarisation.
