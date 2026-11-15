# Future ideas

This document holds deliberately deferred product ideas. They are not part of the
current Lodger version, current Klien pack, or current interaction contract.

## Deferred art references

The current runtime keeps its existing front-facing pivot and has no perch state. Reference
art for later authoring is preserved outside the active manifest:

- `Packs/klien/reference/turnaround-concept.png` — front, three-quarter, and side studies.
- `Packs/klien/reference/future/perch-concept.png` — distinct seated perch studies.

These are concept references, not validated runtime sprites. Before activation they need a
native-resolution redraw, palette audit, anchors, hit masks, interaction timing, and owner art
approval. They must not be copied into the active atlas by accident.

## Window perching

Let the user drag the character onto the top edge of one normal application window.
The character should sit there until the target moves, disappears, becomes hidden,
enters fullscreen, moves to another Space, becomes too small, or leaves the visible
desktop. In every loss case the character should fall to the nearest screen floor.

### Proposed interaction

- Perching is disabled by default and controlled by an explicit user setting.
- A drop over a valid window selects that window; a drop elsewhere follows normal
  drag-release and falling behavior.
- The first valid drop may request Accessibility permission, at the moment of the
  user action rather than at launch.
- Window geometry can be hit-tested from `CGWindowList` without reading titles or
  requesting Screen Recording permission.
- Only one target window is tracked at a time.
- A normal window must be on-screen, large enough, not Lodger’s own window, and have
  the standard-window accessibility subrole. The Dock, menu bar, palettes, sheets,
  popovers, HUDs, and fullscreen windows are excluded.

### Performance and implementation constraints

- Enumerate windows once at drag release to select the target; never poll the full
  window list.
- Track the selected window with one event-driven `AXObserver`.
- Do not add a timer or display link while the target is stationary.
- Convert CGWindowList’s top-down coordinates to AppKit’s bottom-up coordinates at
  the API boundary.
- Revalidate the target on display and Space change notifications.
- Keep the engine generic: packs may react to `perch.acquired` and `perch.lost`, but
  they must not know window IDs, owner applications, or window metadata.

### Open questions before implementation

- Decide whether the first release should use a dedicated dangling-leg perch pose or
  reuse the seated pose.
- Define behavior when Accessibility is denied: fall immediately, or keep the drag
  release and show a one-time explanation.
- Verify Safari, Finder, Terminal, fullscreen windows, minimized windows, multiple
  Spaces, and mixed-display layouts on supported macOS versions.
- Add explicit live acceptance tests for attach, movement, resize, close, hide,
  fullscreen, Space changes, and display removal.
