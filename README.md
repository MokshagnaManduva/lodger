# Lodger

Lodger is a macOS menu-bar companion for small animated characters. Characters are data
packs; the reusable engine does not contain character art or character-specific behavior.

## Current version

The working tree contains a development build, with these implemented features:

- cursor-aware reactions, click-versus-drag handling, falling, walking, and multi-display recovery;
- native Settings with character previews, size/reset, sound/volume, each character's own behaviour sliders and toggles, and removal to Trash;
- two bundled characters, Klien and Norn, loaded through the same path as installed packs;
- staged pack installation with schema/asset/path validation, ID-based replacement and tested rollback;
- pack validation, an incomplete authoring scaffold, and static texture previews;
- render-server animation for idle/walking, with no autonomous timer/physics display link in quiescent states;
  changing silhouettes under a cursor use scoped input-routing work.

Window perching and full turnaround runtime art are absent from the current development build.
Manual update checking activates when an HTTPS feed is configured. Automatic installation
and in-app archive signature verification remain unfinished. See
[current status](left.md) and [future ideas](Docs/future-ideas.md).

Release readiness remains open: final Settings/import and desktop input acceptance, energy
certification, production artwork, and distribution testing. September 30 recorded 30 app
checks, 306 generic engine checks and pack/art checks passing; the earlier September 22
run included both working packs (308 total). These do not prove live desktop workflows.
Quiet battery energy samples were deferred by the owner. See the
[acceptance record](Docs/product-acceptance.md) for exact scope and next steps.

## Build and test

Requires macOS 14+ and Swift from Xcode or the Command Line Tools.

```sh
make test             # pack and character checks
make engine-test      # native engine checks
make app-test         # isolated Settings/import/controller checks
make release-test     # signature, packaging-sequence and update-feed checks
make separation       # engine/pack boundary check
make app              # build build/Lodger.app, ad-hoc signed
make release-check    # local release gate
```

`make run` builds and launches the app. `make soak` runs the repeatable CPU probe described in
[`Docs/energy-protocol.md`](Docs/energy-protocol.md).

## Use the app

Open `build/Lodger.app`. Lodger appears in the menu bar and starts Klien; Norn is bundled
too and can be chosen from the menu or Settings.
Use **Settings…** to select/preview a character, change its size, reset character defaults,
set sound/volume, or adjust the behaviour controls that character declares (for example how
often Klien wanders, or whether Norn walks about on her own). Installed packs
can be moved to Trash; bundled/development source packs are protected. Resize and active
replacement preserve position within display bounds. Actual desktop acceptance remains open.

Use **Add Character…** in Settings or the menu to import pack folders. Imports validate the
manifest, referenced assets, contained paths and resource limits before ID-based replacement.
Failed and unrelated imports preserve the running pet. Commit/restoration failures have
regression coverage; abrupt termination between renames still requires manual backup recovery.
See [installation guarantees](Docs/pack-installation.md).

Installed packs live in:

```text
~/Library/Application Support/Lodger/Packs/
```

## Author a pack

```sh
python3 Tools/packtool/packtool.py generate Packs/demo --id demo.pet --name Demo
# Author a complete manifest and artwork before running the commands below.
python3 Tools/packtool/packtool.py validate Packs/demo
python3 Tools/packtool/packtool.py preview Packs/demo
python3 Tools/packtool/packtool.py build Packs/demo --out build/demo.pack
```

`generate` creates an incomplete scaffold, not a valid starter pack or generated animations.
`preview` produces a static texture contact sheet; animated clip previews and anchor traces
are still pending.

The normative manifest contract is [`Schema/pack.schema.json`](Schema/pack.schema.json), with
the human-readable explanation in [`Docs/PACK_FORMAT.md`](Docs/PACK_FORMAT.md).

## Repository map

| Path | Purpose |
|---|---|
| `Engine/` | Reusable Swift engine and menu-bar application |
| `Packs/` | Character packs and their authoring references |
| `Tools/packtool/` | Validation, authoring, preview, and build tools |
| `Schema/` | Pack manifest schema |
| `Scripts/` | Bundle, separation, and release helpers |
| `Assets/Branding/` | Project-owned app icon source |
| `Docs/` | Current guidance and historical evidence |
| `site/` | Public website: landing page, docs and character gallery ([README](site/README.md)) |

For the documentation index, read [`Docs/README.md`](Docs/README.md). For the engineering
architecture, read [`CLAUDE.md`](CLAUDE.md).

## Licensing

The working tree contains MIT terms in [`LICENSE`](LICENSE) and a CC-BY-NC-4.0 notice for
Klien matching its manifest. Owner confirmation of the engine license choice and review of
asset provenance/attribution remain release tasks; see [`CREDITS.md`](CREDITS.md).
