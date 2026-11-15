#!/usr/bin/env python3
"""Archive/notarize the existing bundle without rebuilding or re-signing it."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "build/Lodger.app"
ARCHIVE = ROOT / "build/Lodger.zip"
# Apple Developer ID Application certificate, not an ad-hoc/local signature.
REQUIREMENT = 'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None)


def verify():
    if not APP.is_dir():
        raise ValueError("build and Developer ID-sign build/Lodger.app first")
    run("codesign", "--verify", "--deep", "--strict", "-R", "=" + REQUIREMENT, str(APP))
    metadata = run("codesign", "--display", "--verbose=4", str(APP), capture=True)
    if "runtime" not in metadata.stderr or "Timestamp=" not in metadata.stderr:
        raise ValueError("distribution requires hardened runtime and a secure timestamp")


def archive():
    verify()
    # A failed ditto cannot truncate the previous distribution ZIP.
    with tempfile.TemporaryDirectory(prefix="lodger-archive-", dir=ROOT / "build") as temporary:
        staged = Path(temporary) / "Lodger.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(APP), str(staged))
        os.replace(staged, ARCHIVE)
    print(f"created {ARCHIVE}")


def notarize(profile):
    # Check credentials before changing any existing archive.
    if not profile:
        raise ValueError("set NOTARY_PROFILE to a stored notarytool keychain profile")
    archive()
    result = run("xcrun", "notarytool", "submit", str(ARCHIVE),
                 "--keychain-profile", profile, "--wait", "--output-format", "json",
                 capture=True)
    report = json.loads(result.stdout)
    (ROOT / "build/notarization.json").write_text(json.dumps(report, indent=2) + "\n")
    if report.get("status") != "Accepted":
        raise ValueError(f"notarization was not accepted; see build/notarization.json")
    run("xcrun", "stapler", "staple", str(APP))
    run("xcrun", "stapler", "validate", str(APP))
    run("spctl", "--assess", "--type", "execute", "--verbose", str(APP))
    archive()  # Distribute the stapled bundle; sign these final bytes for the feed.


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action", choices=("archive", "notarize"))
    args = ap.parse_args()
    try:
        if args.action == "archive":
            archive()
        else:
            notarize(os.environ.get("NOTARY_PROFILE", ""))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        ap.exit(1, f"release failed: {error}\n")


if __name__ == "__main__":
    main()
