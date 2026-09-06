# Next steps

Written after the second decision round. Nothing here is executed yet.

## Decisions locked this round

| Fork | Decision |
|---|---|
| Swift layout | **SwiftPM package for `Engine/` + thin Xcode project for `App/`.** The package cannot contain app resources, so Rule 1 gets a structural boundary and `swift test` runs with no Xcode. |
| First engine milestone | **Walking skeleton, riskiest claims first.** Renders `test.solidsquare` and nothing else. |
| `packtool generate` | **After** the engine core. A handful of hand-run generations is enough to validate the pipeline; scripting matters at cell 40, not cell 4. |
| Art editor | Free editor preferred — **but see below, the premise was wrong.** |

## The LibreSprite finding, and why it changes the recommendation

**LibreSprite does not have slices, so the pivot mechanism does not exist there.** It forked
from the last GPLv2 commit of Aseprite in August 2016; slices landed afterwards, and feature
comparisons list slices among what Aseprite added post-fork. The free-editor path as framed
does not work.

Two paths do work, and the second is better than the original plan:

### Compiling Aseprite from source — free, but the wrong side of a line

The EULA (§2g) permits compiling and modifying the source *"for your own personal purpose."*
It does **not** permit commercial or public use of assets made with an unlicensed build —
explicitly including publishing something that uses them. Klien's art ships inside a publicly
distributed app, which is the wrong side of that line. Fine for evaluating; **if the art
ships, buy the ~$20 licence.** Not worth the ambiguity over $20.

### The anchor picker — now the primary recommendation, not the fallback

On reflection this beats Aseprite slices regardless of what you own:

1. **It can show the anchor path across every frame at once**, live, while you place them.
   Aseprite cannot. Anchor drift is the specific defect measured in this reference art
   (`reference-audit.md`), so authoring against a visible trace attacks the actual problem.
2. **It is editor-agnostic**, so pack authors need no paid tool. That serves the stated goal
   that other people will make packs, far better than a $20 gate does.
3. It sidesteps known Aseprite export bugs — empty slice and tag metadata in tileset exports,
   slices emitted for non-tagged frames.
4. `packtool build` needs an Aseprite-JSON → manifest converter anyway. The picker replaces
   that with something simpler that we control and can change.

All any editor then has to do is export a **PNG frame strip**. Frame tags become a small
`clips.json`, which you are editing regardless because durations are per-frame in milliseconds.

**Recommended free editor: Pixelorama** — MIT, actively developed, frame tags with custom user
data, and a CLI with `--json` export. Aseprite still works fine if you buy it; nothing in the
pipeline requires either.

## Plan

### Step 0 — corrections (mine, small)

- CLAUDE.md §7 Stage 4 currently instructs a future session to author anchors as Aseprite
  slices. Rewrite for the anchor picker; keep the Aseprite path documented as optional.
- `Docs/PACK_FORMAT.md` §5 same correction.
- Record the editor decision in `Packs/klien/reference/proportions.md`.

### Step 1 — unblock the engine (mine)

- Generate the procedural 16×16 atlas for `Tests/Fixtures/test.solidsquare` so the fixture is
  complete and the engine has something real to render.

### Step 2 — `packtool anchors` (mine)

A local page: load a frame strip, click each named anchor per frame, see the trace across all
frames as you go, write `anchors.json`. Snap-to-pixel, keyboard frame stepping, and a live
readout of the per-frame jump the linter will measure.

### Step 3 — `packtool build` (mine)

PNG strip + `clips.json` + `anchors.json` → uniform-cell atlases, ground-line re-registration,
per-frame anchor tables, 1-bit RLE hit masks, emitted and validated `pack.json`. Built against
a **synthetic** fixture so it is finished and tested before your first real export exists.

### Step 4 — engine walking skeleton (mine)

`Engine/` as a SwiftPM package, `App/` as a thin Xcode project. Renders `test.solidsquare`.
Proves, in order of risk:

1. Borderless non-activating `NSPanel`, transparent, floating, absent from Dock and ⌘-Tab,
   click-through via `ignoresMouseEvents` + alpha mask.
2. `CAKeyframeAnimation` on `contentsRect`, `calculationMode = .discrete` — **verified by
   pausing at a debugger breakpoint and confirming the animation keeps running.** If it stops,
   the central efficiency claim is false and the architecture needs revisiting.
3. A `quiescent: true` state producing **zero** attributable timer fires under
   `sudo timerfires -p <pid>`.

Any of those failing is a stop-and-rethink, which is exactly why they come first.

### Step 5 — energy protocol (mine)

Run it for real. Replace the six `[estimate]` targets in CLAUDE.md §6 with measured baselines,
recording `WindowServer` delta alongside our own process.

### Then

`packtool generate` (scripted PixelLab), motion and physics, perching, app shell.

## Your track, in parallel

- **A. PixelLab comparison** — 2 free generations of `r1c0` at 128×128 against
  `sketches/r1c0@8x.png`. The gate that decides what we trace, and an early test of the
  "fixed head" claim.
- **B. Pick an editor** — Pixelorama, or buy Aseprite. Either works; nothing blocks on it
  until step C.
- **C. Canonical sprite** — hand-finish the winner of A. The three known fixes are listed in
  `proportions.md`: invent value separation in the suit, lift the cane onto its own layer,
  clean the hair spikes and wrist.

Steps 1–4 do not depend on any of A/B/C. The engine only needs `test.solidsquare`.

## Resolved after this round

- **Name: Lodger.** Bundle id `com.mokshagna.lodger`; packs at
  `~/Library/Application Support/Lodger/Packs/`. The app name and the format name are
  deliberately different words: the format is a *character pack*, the user-facing noun is
  *character* ("Add Character…"), so nobody has to say "a Lodger pack".
  **Search for trademark conflicts before this reaches a public release.**
- **Klien ships bundled as the default pack.** See CLAUDE.md §8a for the three constraints
  that keeps Rule 1 intact.

## Still open

- Klien's licence. `CC-BY-NC-4.0` is a placeholder I typed. It binds only what *other people*
  may do with him; as the author you can relicense or dual-license at any time, so this is not
  a blocker — just worth setting deliberately before the pack is public.
