# Norn artwork provenance

- `Norn.png`: project-owner-supplied character identity reference, retained unchanged.
- `drafts/*.png`: prior generated motion studies; prompts preserved in `drafts.js`.
- `reference/runtime-v1/lifecycle-sheet.png`: new artwork generated on 2026-09-22
  with the built-in imagegen tool, using only `Norn.png` as identity reference.
  The exact prompt is recorded in `reference/runtime-v1/generation-prompt.txt`.
- `reference/motion-v2/{sleep,held,fall}-sheet.png`: three new six-pose sheets
  generated with the built-in imagegen tool on 2026-09-22, referencing the lifecycle
  sheet. Exact prompts and per-pose registration are retained beside each sheet.
- `reference/polish-v3/{walk,greet,sit}-sheet.png`: generated on 2026-09-25
  using the built-in imagegen tool and the original lifecycle sheet as reference.
  Exact prompts, walk correction prompts and explicit registration are retained.
- `atlas/*.png`, `preview.png`, `masks/*.mask`: reproducible compilation of
  the source sheets, using explicit per-pose crop/placement coordinates, a shared
  32-color-plus-transparent palette, binary alpha and native 128 × 128 cells.
- No Klien artwork or character-specific animation routines are used.

The runtime sheet is generated art normalized for a working prototype, not a
claim of hand-pixeled production animation. Ownership/provenance of the supplied
character and a public distribution license still need confirmation.
