"""Regression tests for archive immutability and appcast signature verification."""
import base64
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import release

SCRIPT = Path(__file__).with_name("build-appcast.py")
spec = importlib.util.spec_from_file_location("appcast", SCRIPT)
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.archive = b"fixed archive bytes"
        key = Ed25519PrivateKey.generate()
        self.kwargs = dict(version="1.2.3", url="https://releases.example/Lodger.zip?a=1&b=2",
                           signature=base64.b64encode(key.sign(self.archive)).decode(),
                           public_key=base64.b64encode(key.public_key().public_bytes_raw()).decode())

    def test_valid_signature_and_xml_metadata(self):
        root = ET.fromstring(appcast.render(self.archive, **self.kwargs))
        item = root.find("./channel/item")
        self.assertEqual(item.find(f"{{{appcast.SPARKLE}}}version").text, "1.2.3")
        self.assertEqual(item.find("enclosure").get("url"), self.kwargs["url"])
        self.assertEqual(item.find("enclosure").get("length"), str(len(self.archive)))
        self.assertNotIn("REPLACE_", ET.tostring(root).decode())
        self.assertNotIn(".invalid", ET.tostring(root).decode())

    def test_modified_archive_or_wrong_key_rejected(self):
        with self.assertRaises(ValueError):
            appcast.render(self.archive + b"tampered", **self.kwargs)
        other = Ed25519PrivateKey.generate().public_key().public_bytes_raw()
        self.kwargs["public_key"] = base64.b64encode(other).decode()
        with self.assertRaises(ValueError):
            appcast.render(self.archive, **self.kwargs)

    def test_placeholder_signature_and_insecure_urls_rejected(self):
        for url in ("http://releases.example/app.zip", "https://user:pass@example.com/a", "file:///tmp/a"):
            with self.assertRaises(ValueError):
                appcast.render(self.archive, **(self.kwargs | {"url": url}))
        with self.assertRaises(ValueError):
            appcast.render(self.archive, **(self.kwargs | {"signature": "test-signature"}))

    def test_cli_preserves_archive_and_previous_feed_on_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "app.zip"
            output = Path(temporary) / "appcast.xml"
            archive.write_bytes(self.archive)
            command = [sys.executable, str(SCRIPT), str(archive), "--output", str(output)]
            for name, value in self.kwargs.items():
                command.extend(["--" + name.replace("_", "-"), value])
            subprocess.run(command, check=True, capture_output=True)
            feed = output.read_bytes()
            self.assertEqual(archive.read_bytes(), self.archive)
            archive.write_bytes(b"changed after signing")
            failed = subprocess.run(command, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(output.read_bytes(), feed)

    def test_notarization_requires_profile_before_archive(self):
        with patch.object(release, "archive") as archive:
            with self.assertRaises(ValueError):
                release.notarize("")
            archive.assert_not_called()

    def test_notarization_archives_again_only_after_ticket_validation(self):
        events = []
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "build").mkdir()
            def run(*args, **kwargs):
                events.append(args)
                return subprocess.CompletedProcess(args, 0, stdout='{"status":"Accepted"}')
            with patch.object(release, "ROOT", root), patch.object(release, "run", run), \
                    patch.object(release, "archive", lambda: events.append(("archive",))):
                release.notarize("test-profile")
            self.assertEqual(events[0], ("archive",))
            self.assertEqual(events[-1], ("archive",))
            self.assertEqual(events[-2][0], "spctl")
            self.assertEqual(events[-3][1:3], ("stapler", "validate"))

    def test_rejected_notarization_never_staples(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "build").mkdir()
            with patch.object(release, "ROOT", root), patch.object(release, "archive"), \
                    patch.object(release, "run", return_value=subprocess.CompletedProcess(
                        [], 0, stdout='{"status":"Invalid"}')) as run:
                with self.assertRaises(ValueError):
                    release.notarize("test-profile")
                self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
