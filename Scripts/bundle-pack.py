#!/usr/bin/env python3
"""Copy the runtime files of character packs into an app bundle, or check a bundle.

Every pack goes through the same rule: the manifest, the files the manifest
references, LICENSE and CREDITS.md. Source art, drafts, galleries and build
notes never ship. There is no per-pack case here on purpose (CLAUDE.md 8a).

  bundle-pack.py copy  <Resources/Packs> <pack dir>...   prints the first pack's id
  bundle-pack.py check <Lodger.app> <pack dir>...
"""
import json
import plistlib
import shutil
import sys
from pathlib import Path

REQUIRED = ("LICENSE", "CREDITS.md")


def runtime_files(pack_dir: Path) -> list[str]:
    manifest = json.loads((pack_dir / "pack.json").read_text())
    files = {"pack.json", *REQUIRED}
    files |= {t["file"] for t in manifest["textures"].values()}
    files |= set(manifest.get("hitMasks", {}).values())
    files |= {s["file"] for s in manifest.get("sounds", {}).values()}
    if "preview" in manifest["identity"]:
        files.add(manifest["identity"]["preview"])
    return sorted(files)


def identity(pack_dir: Path) -> dict:
    return json.loads((pack_dir / "pack.json").read_text())["identity"]


def problems_with(pack_dir: Path) -> list[str]:
    out = [f"{pack_dir}: missing {name}" for name in runtime_files(pack_dir) if not (pack_dir / name).is_file()]
    licence = identity(pack_dir)["license"]
    if licence.startswith("LicenseRef-") or "pending" in licence.lower():
        out.append(f"{pack_dir}: licence {licence!r} is not settled; a bundled pack's licence is the app's licence problem")
    return out


def copy(destination: Path, packs: list[Path]) -> int:
    errors = [p for pack in packs for p in problems_with(pack)]
    ids = [identity(pack)["id"] for pack in packs]
    if len(set(ids)) != len(ids):
        errors.append(f"duplicate pack ids: {ids}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    for pack in packs:
        for name in runtime_files(pack):
            target = destination / pack.name / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(pack / name, target)
    if ids:
        print(ids[0])
    return 0


def check(app: Path, packs: list[Path]) -> int:
    root = app / "Contents/Resources/Packs"
    errors = []
    for pack in packs:
        expected = set(runtime_files(pack))
        bundled = root / pack.name
        shipped = {str(p.relative_to(bundled)) for p in bundled.rglob("*") if p.is_file()} if bundled.is_dir() else set()
        errors += [f"{bundled}: missing {n}" for n in sorted(expected - shipped)]
        errors += [f"{bundled}: unexpected file {n}" for n in sorted(shipped - expected)]
        errors += [f"{bundled}/{n}: differs from source" for n in sorted(expected & shipped)
                   if (bundled / n).read_bytes() != (pack / n).read_bytes()]
        errors += problems_with(pack)
    extra = {p.name for p in root.iterdir()} - {pack.name for pack in packs} if root.is_dir() else set()
    errors += [f"{root}/{n}: not a declared bundled pack" for n in sorted(extra)]
    default = plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("LodgerDefaultPack")
    ids = [identity(pack)["id"] for pack in packs]
    if packs and default != ids[0]:
        errors.append(f"LodgerDefaultPack is {default!r}, expected {ids[0]!r}")
    if not packs and default is not None:
        errors.append("LodgerDefaultPack is set but no pack is bundled")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"bundled packs: {', '.join(ids) or 'none'}; runtime files only, byte-identical to source")
    return 0


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in ("copy", "check"):
        print(__doc__, file=sys.stderr)
        return 2
    action = copy if sys.argv[1] == "copy" else check
    return action(Path(sys.argv[2]), [Path(p) for p in sys.argv[3:]])


if __name__ == "__main__":
    sys.exit(main())
