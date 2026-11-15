# Klien — sun-emblem polish (0.4.0)

Klien holds a small gold sun emblem in his free hand and occasionally tosses and
catches it while standing idle. Walking and other leg poses use a narrower stance;
hat-tip and seated transitions include smoother hand movement. The supplied
`reference/sun-emblem.tiff` is the visual reference.

**Review:** [animation gallery](reference/all-scenarios-v1/gallery.html) ·
[toss sheet](reference/all-scenarios-v1/sheets/toss_emblem.png) ·
[verification](reference/all-scenarios-v1/verification.md)

```sh
make klien-animations
make test
make engine-test
make app
./build/Lodger.app/Contents/MacOS/Lodger
```

Choose Klien from the character menu. A user-installed pack with the same ID
shadows the bundled pack. Restart after rebuilding to reload bundled assets.

The authoring source has 56 poses and 19 body clips. The active runtime manifest has
18 clips and 17 states after perching removal. Default scale is 1×. Both walking directions
are in the gallery; the engine mirrors the complete rig for rightward movement.

Body, cane and emblem remain separate editable source layers. Runtime uses one
composited body atlas, with no companion spring, floating bob or impact squash.
The approved 3-second breathing/blink timing and native body identity are retained.
Audio remains off and no sound assets are included.

`reference/idle-v2/` preserves the older approved idle/dumpling artwork;
`make klien-idle` rebuilds that archive only. To deliberately restore the archived
idle-only pack, use `python3 Tools/packtool/build_klien_idle.py --install`.
`make klien-animations` restores the current development pack.

Full runtime turnaround is unfinished. The new turnaround reference is concept artwork,
not a replacement for the runtime pivot. Perch concepts belong to future work; no active
perching behavior exists. Energy certification and live interaction acceptance remain open.
See [current status](../../left.md) and [energy evidence](../../Docs/energy-protocol.md).
