# Lodger

A macOS desktop companion: a small animated character that lives on screen, reacts to the
cursor, and idles quietly all day on battery.

The character is **not** part of this codebase. It lives in a *character pack* — a folder of
data — and the engine knows nothing about any particular one. Installing a character means
dropping in a folder.

## Status

There is a working app. `make app` assembles `build/Lodger.app` without Xcode — a real
`Info.plist`, `LSUIElement`, an ad-hoc signature and the bundled default character. It puts
a menu bar item up, discovers characters from
`~/Library/Application Support/Lodger/Packs/`, and runs one on screen.

Klien has a complete scenario set, with a gold sun-emblem toss and compact leg
poses in the current polish pass. Audio playback infrastructure is implemented;
the bundled character stays silent. Remaining work includes art refinements,
interaction/perching and energy verification, settings, safe pack import, and
release preparation. See [the current backlog](left.md) and the
[interaction verification order](Docs/interaction-plan.md).

```bash
make test          # pack validation and native-art acceptance checks
make engine-test   # engine self-tests, no Xcode needed
make all           # both, plus pack validation
make soak          # CPU soaks, repeated runs with the spread reported
```

Start with [`CLAUDE.md`](CLAUDE.md) — it carries the architecture and the reasoning.
[`Docs/PACK_FORMAT.md`](Docs/PACK_FORMAT.md) is the pack format for authors.

## Install and use

Requires macOS 14+ and a Swift toolchain (Xcode or the Command Line Tools) — no
Xcode project is needed to build or run.

```bash
git clone https://github.com/MokshagnaManduva/lodger.git
cd lodger
make app     # builds and ad-hoc signs build/Lodger.app
open build/Lodger.app
```

`make run` builds and launches it directly from the terminal instead. The app
puts a menu-bar item up (it has no Dock icon or window, by design — see
`LSUIElement` in `CLAUDE.md` §4) and starts the bundled `klien` character.

**Installing a different character:** drop its folder into
`~/Library/Application Support/Lodger/Packs/`, or use the menu bar item's
*Add Character…* (also has *Reveal Characters Folder*). Packs are watched, so a
valid one appears immediately; an invalid one shows its exact loading error in
the menu instead of failing silently. See `Docs/PACK_FORMAT.md` if you're
authoring one yourself.

**Quitting:** *Quit Lodger* (⌘Q) in the menu bar item — there's no window to close.

## The two rules

**The engine knows nothing about any character.** Sprite sizes, animation names, attachment
names, timing — all pack data. Delete every pack and the engine still builds and runs.

**Idle cost outranks features.** Sprite animation is a `CAKeyframeAnimation` on
`contentsRect` with `calculationMode = .discrete`, so it runs in the render server and the
app process does no per-frame work. This is verified, not assumed: sending `SIGSTOP` freezes
our code and the frames keep advancing.

![render server proof](Docs/render-server-proof.png)

A `quiescent` state installs no timer, no display link and no run-loop source at all. The
same idea extends to movement: a walk is resolved up front and handed to the render server
as one animation, so the pet keeps walking even while the process is frozen — 0.10% of one
core, down from 4.5% when the window was moved per frame.

![walking while frozen](Docs/render-server-walk-proof.png)

## Layout

| | |
|---|---|
| `Engine/` | Swift package — no character data, no asset files |
| `Packs/klien/` | the reference character (manifest and art direction) |
| `Tools/packtool/` | the asset pipeline: `validate`, `palette`, `pixelize`, `anchors`, `build` |
| `Schema/pack.schema.json` | the normative pack manifest schema |
| `Docs/` | format spec, measurements, energy protocol |
| `Scripts/bundle.sh` | assembles the `.app` without Xcode |

## Licence

Engine: TBD. The `klien` character pack is licensed separately — see `Packs/klien/`.
