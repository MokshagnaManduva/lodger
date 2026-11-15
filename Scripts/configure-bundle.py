#!/usr/bin/env python3
"""Set optional update metadata using plist serialization, preserving URL escaping."""
import os
from pathlib import Path
import plistlib
import sys
from urllib.parse import urlsplit

path = Path(sys.argv[1])
metadata = plistlib.loads(path.read_bytes())
feed = os.environ.get("SPARKLE_FEED_URL", "")
if feed:
    url = urlsplit(feed)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
        raise SystemExit("SPARKLE_FEED_URL must be an HTTPS URL without credentials or fragments")
    metadata["SUFeedURL"] = feed
else:
    metadata.pop("SUFeedURL", None)
# The manual browser-download flow does not verify an Ed25519 signature in-app.
# Public keys are used by build-appcast.py; do not imply an automatic updater here.
metadata.pop("SUPublicEDKey", None)
path.write_bytes(plistlib.dumps(metadata))
