# Settings redesign and app-level controls — design

Date: 2026-11-15. Sub-project 2 of 3. Builds on
`2026-11-15-norn-deployment-behaviour-controls-design.md`. Sub-project 3
(appearance variants) adds an Appearance tab later.

The owner asked for "better features and control in the settings" and chose
app-level controls and a Settings redesign. This spec records the choices made
without a further review round, so they are easy to revisit.

## App-level controls

These apply to whichever character is running. Each is generic: nothing names a
character, state or control.

| Control | Default | Mechanism | Idle cost |
|---|---|---|---|
| Show character | on | Off stops and releases the pet; the choice of character and its position are kept. Also in the menu as Hide/Show Character. | Hidden: nothing runs |
| Opacity | 100% (30–100%) | `Pet.opacity` sets the panel's `alphaValue` | None in our process |
| Stay in place | off | `Director.allowsAutonomousWalking = false`: a timeout never picks a state whose motion is `walk`. If that leaves no option the current state is re-entered. Interrupt-driven walks (a pack's double-click, say) and dragging still work. | None |
| Calmer on battery | off | `Director.pace`: timed (non-clip) durations are divided by it. The pet sets 0.5 while on battery, from the existing event-driven power-source observer, installed only while this option is on. | No timer; one notification source |
| Launch at login | off | `SMAppService.mainApp` register/unregister. Shown disabled with an explanation when not running from an app bundle. | None |
| Sound, Volume | as today | unchanged | unchanged |

Not included, deliberately: quiet hours (needs a scheduled wake at each boundary;
revisit with a measured justification), choosing a home display (the pet is already
draggable between displays), window level.

## Settings window

A fixed-size window with three tabs (`NSTabView`), created on demand as today, with
no refresh timer:

- **Character** — picker, preview, name/version/description/licence, display size,
  Add / Remove / Reveal, Reset Character Settings.
- **Behaviour** — the selected character's declared controls, grouped, each slider
  with a readout and a small reset button that is enabled only when the value
  differs from the pack default; a "Reset Behaviour" button; an explanatory line
  when the character declares none.
- **General** — the app-level controls above, sound and volume, version and
  Check for Updates.

The selected tab is remembered for the session only.

## Other changes

- `AppController` keeps `selectedID` separately from the running pet so a hidden
  character still has a selection; `activeID` returns it.
- The About panel lists bundled characters' names and licences read from the
  loaded packs. It currently hard-codes one character's name in app source, which
  the separation check missed because of a word-boundary match; the check drops
  that flag.

## Testing

Engine selftests: `allowsAutonomousWalking` (excludes walk states, re-enters when
nothing else is eligible, interrupts unaffected), `pace` (timed durations only).
App checks: each preference persists and applies to the running pet and to the
next activation; hide keeps selection and position and show restores them; the
three tabs construct with and without packs; per-control reset; About text.
Launch at login is exercised through an injected service, not the real one.

Not covered: real input on the new window, energy measurement with the new
options, and login-item behaviour on a signed build.
