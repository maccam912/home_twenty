import runpy
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
stamp_version = runpy.run_path(str(ROOT / ".github/scripts/build_commits.py"))["stamp_android_version"]
SHA = "abcdef0123456789abcdef0123456789abcdef01"


class AndroidVersionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.presets = Path(temporary.name) / "export_presets.cfg"
        self.original = (
            '[preset.4]\n\nname="Android"\nplatform="Android"\n'
            '\n[preset.4.options]\n\nversion/code=27\nversion/name="2.1.4"\n'
            'permissions/internet=false\n'
        )

    def test_keeps_every_other_setting_when_version_changes(self):
        settings = self.original
        self.presets.write_text(settings)
        stamp_version(self.presets, SHA, 4097)
        expected = settings.replace("version/code=27\n", "version/code=4097\n")
        expected = expected.replace('version/name="2.1.4"', 'version/name="2.1.4+abcdef012345"')
        self.assertEqual(self.presets.read_text(), expected)

    def test_only_stamps_the_android_preset_selected_for_export(self):
        other = '[preset.9]\nname="Android demo"\n\n[preset.9.options]\nversion/code=8\nversion/name="Demo"\n'
        self.presets.write_text(other + self.original)
        stamp_version(self.presets, SHA, 8193)
        self.assertTrue(self.presets.read_text().startswith(other))
        self.assertIn("version/code=8193\n", self.presets.read_text())

    def test_missing_field_fails_without_writing_partial_preset(self):
        settings = self.original.replace("version/code=27\n", "")
        self.presets.write_text(settings)
        with self.assertRaises(ValueError):
            stamp_version(self.presets, SHA, 8193)
        self.assertEqual(self.presets.read_text(), settings)
