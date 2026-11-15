#!/usr/bin/env python3
"""Publish metadata for an existing archive after verifying its Ed25519 signature.

Never repacks or modifies the archive. Apple code signing/notarization is a
separate release step. Only public key material is accepted here.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import re
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def https_url(value: str) -> str:
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.fragment):
        raise ValueError("release URLs must use HTTPS without credentials or fragments")
    return value


def render(archive: bytes, *, version: str, url: str, signature: str,
           public_key: str, minimum_system_version: str = "14.0",
           notes_url: str | None = None) -> bytes:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

    for value in (version, minimum_system_version):
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
            raise ValueError("versions must contain one to three numeric components")
    https_url(url)
    if notes_url:
        https_url(notes_url)
    try:
        key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key, validate=True))
        signed = base64.b64decode(signature, validate=True)
        key.verify(signed, archive)
    except (ValueError, binascii.Error, InvalidSignature) as error:
        raise ValueError("Ed25519 signature does not verify for this archive and public key") from error

    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Lodger Updates"
    ET.SubElement(channel, "description").text = "Lodger releases"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Lodger {version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = minimum_system_version
    if notes_url:
        ET.SubElement(item, f"{{{SPARKLE}}}releaseNotesLink").text = notes_url
    ET.SubElement(item, "enclosure", {
        "url": url, "length": str(len(archive)), "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": signature,
    })
    ET.indent(root)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("archive", type=Path)
    ap.add_argument("--version", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--signature", required=True, help="base64 Ed25519 archive signature")
    ap.add_argument("--public-key", required=True, help="base64 Ed25519 public key")
    ap.add_argument("--notes-url")
    ap.add_argument("--output", type=Path, default=Path("build/appcast.xml"))
    ap.add_argument("--minimum-system-version", default="14.0")
    args = ap.parse_args()
    try:
        if args.output.resolve() == args.archive.resolve():
            raise ValueError("output must not overwrite the archive")
        archive = args.archive.read_bytes()
        xml = render(archive, version=args.version, url=args.url,
                     signature=args.signature, public_key=args.public_key,
                     notes_url=args.notes_url,
                     minimum_system_version=args.minimum_system_version)
    except ImportError:
        ap.error("install release dependencies: python3 -m pip install -r Scripts/requirements-release.txt")
    except (OSError, ValueError) as error:
        ap.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(xml)
    print(f"wrote {args.output}; signature verified")
    print(f"sha256 {hashlib.sha256(archive).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
