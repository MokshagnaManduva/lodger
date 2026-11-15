# Runtime pack validation and installation

Implemented locally on 2026-09-22. Bundled, development and installed packs all
pass through `PackStore`. Validation runs during discovery/import, never on an idle timer.

The loader enforces the embedded copy of `Schema/pack.schema.json`, then checks
references between states, transitions, interrupts, clips, textures, parts, anchors,
sounds and tuning. Unknown fields/vocabulary, invalid durations, frame indices,
quiescent-state timers/motion and unsupported capabilities are rejected. Cycles
are allowed; reachability and artistic continuity warnings remain author-tool checks.

The pack API version is **1.0.0**, independent of the application release version.
`engineMin` cannot exceed that version. Supported capabilities are `audio` and
`multiDisplay`. Historical perching declarations in the authoring schema are
rejected by the current runtime. Texture strips must first be compiled with
`packtool build`. Attachments currently bind directly to the body; nested part
hierarchies are rejected. Floating parts must specify their own clip.

Images must decode completely and match their declared atlas dimensions. Optional
previews and audio files must decode too. Declared masks must decode within bounded
allocations, have the correct cell dimensions/count and match every texture alpha
pixel. Masks remain optional for compatibility with minimal packs.

## File and resource limits

Referenced files must be regular files beneath the pack root. Absolute paths,
parent/dot components, symbolic links (even links targeting the pack itself) and
special files are rejected. The imported tree is checked before copying and again
in staging, including unused files. Later audio, texture and mask reads check paths
again. Ancestor symlinks such as macOS's `/var` alias are resolved before containment
checks; a symlink used as the pack root is rejected.

| Resource | Runtime limit |
|---|---|
| Manifest | 2 MiB; 48 levels; 100,000 JSON nodes |
| JSON numbers | Finite, magnitude at most 1 billion |
| Imported tree | 4,096 entries; 32 directory levels; 256 MiB total |
| Individual file | 64 MiB |
| Cell dimensions | 1–1,024 pixels per axis |
| Atlas | 8,192 pixels per axis; 4,096 cells |
| All decoded atlas pixels | 32 Mi pixels |
| Parts / states / clips / textures | 64 / 512 / 1,024 / 64 |
| Frames per clip | 4,096 |
| Clip or state duration | One day, including maximum tuning-scaled duration |
| Floating attachment margin | 1,024 logical pixels |
| Scaled stage including margins | 8,192 pixels per axis |
| Spring parameters | Mass ≥ 0.0001; stiffness/mass ≤ 10,000; damping/mass ≤ 200 |
| Concurrent instances per sound | 16 |

Scale choices must be nonempty and unique and include the default. Bounds are
checked before dimension multiplication, image decoding and mask allocation.
A pack is not sandboxed against another process actively rewriting its filesystem
while it is read. Do not modify a pack during import or activation.

## Replacement and recovery

New installations use `identity.id` as the folder name. A replacement locates the
existing ID even if its folder has a different name. It also recognizes the ID of
an installed manifest whose artwork is damaged. Multiple installed folders with
the same ID block replacement. An unrelated or unreadable folder occupying the
new destination is preserved and reported as a collision.

Discovery rejects multiple valid copies of an ID within one search directory.
Across search directories, later directories override earlier ones, preserving
installed-pack overrides of bundled packs. Hidden transaction folders are never
activated. Surviving `.backup-*` folders are reported separately for recovery.

Each import is copied into a unique hidden staging folder on the destination
volume and validated there before touching the old installation. The old folder
is renamed to a unique backup, then the candidate is renamed into its place.

- Validation or copy failure leaves the old folder unchanged.
- Commit failure triggers restoration of the old folder.
- Restoration failure preserves the backup and reports its exact path and intended
  destination. The backup remains visible as a recovery notice after relaunch.
- Backup cleanup failure reports a warning; the new installation is retained.

The app processes a multi-folder import in order. After an ID has been encountered,
additional copies of that ID in the same batch are rejected; earlier successful
imports remain installed. A batch is not an all-or-nothing transaction.

Abrupt process termination or power loss between the two renames is not an atomic
replacement: the backup survives for manual recovery. There is no automatic crash
journal replay or cross-process installer lock. The app serializes its own imports.

## App-level behavior — 2026-09-30

Settings and the menu share the import flow. A successful import of an unrelated ID or
an invalid import leaves the running pet intact. Replacing the active ID reloads it while
preserving its feet position within display bounds. Per-file notices also report successful
installs whose backup cleanup produced a warning; a notice does not mean every import failed.

Settings removes only user-installed packs, using Trash. Removing an override reveals its
bundled/development counterpart; source folders cannot be removed through this action.
The September 30 app suite passed 30 checks using isolated preferences/temporary directories.
Removal lifecycle tests use an injected move to a temporary recovery folder, not actual Trash.
Live file-picker, alert and Trash acceptance remains open; see [product acceptance](product-acceptance.md).

## Verification

The 2026-09-22 local run passed 282 checks including both working character packs
(280 generic checks). Pack/art, separation and release/update regressions also passed.

`make engine-test` exercises malformed manifests, asset and mask corruption, path
escapes, duplicates, collisions and injected commit/restore failures against real
temporary directories. To include the working character packs:

```sh
LODGER_TEST_PACKS=Packs/klien:Packs/Norn make engine-test
make test
make separation
```

The schema is embedded so validation needs no network, Python or source checkout
at runtime. After a schema change, run `python3 Scripts/embed-pack-schema.py`.
`make test` and `make engine-test` fail if the embedded copy is stale or the schema
uses a keyword the runtime validator does not implement. This is a validator for
this project's schema, not a general JSON Schema library.
