# Norn credits

Norn artwork and character-specific pack data: Mokshagna Manduva.

License: CC BY-NC 4.0, confirmed by the project owner on 2026-11-15. The Lodger engine
and app source use the repository-level MIT License; that license does not relicense
this pack.

## Artwork provenance

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

The runtime sheets are generated art, produced with an AI image tool from the
owner's reference and then normalized by the build script. They are not a claim of
hand-pixeled production animation.
