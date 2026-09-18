# Approved idle → playable milestone

Inputs: `approved-body.png` and `approved-dumpling.png`, copied from the user-approved
idle-v1 preview. These small native inputs are versioned here because the original
`reference/generated/` directory is ignored by git. `generation-prompts.json` records
the original built-in imagegen canonical and motion-study prompts.

`Tools/packtool/build_klien_idle.py` applies a small, reproducible native pixel pass:

- Remove a few isolated trouser flecks.
- Cool the cape highlights into the costume ramp, preserving the cane.
- Replace open-eye interiors/lashes with curved lids and a cheek-shadow transition.
- Derive inhale and peak through local one-pixel chest/cape edits.

The face, hat, hair, feet, cane and approved silhouette otherwise remain fixed. The
item keeps its original leaf details and size. `art/` contains the finished poses
and strips; `pack.json` is the build source. Rebuild using `make klien-idle`.

The active runtime manifest is `../../pack.json`. Do not edit that generated copy
for timing changes; change this source manifest and rebuild. `pose-sheet.png` shows
all four final body poses at the app's default 2× scale.

The original generated designs were continuous-tone illustrations, cleaned into
native sprites for the preview. This version makes a deliberately local pixel pass
on that approved native result; it does not reroll the character through imagegen.
The full art pipeline (turnarounds, independent cane art, walking and reactions)
remains future work.
