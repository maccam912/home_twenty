"""Checks that native release receipts belong to the package actually launched."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / ".github/scripts/native_smoke.py"
spec = importlib.util.spec_from_file_location("native_smoke", SCRIPT)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
BOOTED = "Godot Engine v4.7.2\nLoading resource: res://game/shift.gdc\nLoading resource: res://ui/ignition_menu.gd\n"


class NativeStartupTests(unittest.TestCase):
    def test_success_requires_the_packaged_title(self):
        native.verify_startup(BOOTED)
        for log in ("", "Godot Engine v4.7.2", BOOTED.replace("ignition_menu", "missing"),
                    BOOTED + "SCRIPT ERROR: Cannot load game", BOOTED + "ERROR: Invalid PCK"):
            with self.subTest(log=log), self.assertRaises(RuntimeError):
                native.verify_startup(log)

    def test_windows_receipt_matches_the_archive_used_to_start_the_game(self):
        with tempfile.TemporaryDirectory() as directory:
            release = Path(directory)
            archive = release / "HomeTwenty-Windows-x64.zip"
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr("HomeTwenty.exe", b"game binary fixture")
            expected = f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}"
            manifest = release / "SHA256SUMS.txt"
            manifest.write_text(expected + "\n")

            def launch(args, **kwargs):
                self.assertEqual(Path(args[0]).read_bytes(), b"game binary fixture")
                self.assertIn("--headless", args)
                self.assertIn("--quit-after", args)
                self.assertGreater(kwargs["timeout"], 0)
                Path(args[-1]).write_text(BOOTED)
                return subprocess.CompletedProcess(args, 0, "", "")

            with patch.object(native.subprocess, "run", side_effect=launch) as invoked:
                self.assertEqual(native.smoke(release, "windows"), expected)
                self.assertEqual(invoked.call_count, 1)
                manifest.write_text("bad checksum")
                with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
                    native.smoke(release, "windows")
                self.assertEqual(invoked.call_count, 1)


if __name__ == "__main__":
    unittest.main()
