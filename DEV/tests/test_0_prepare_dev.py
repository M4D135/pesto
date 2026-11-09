"""Fresh-clone preparation. Imported first by unittest discovery (alphabetical order): creates wad/cfg.json
from the non-configured template only when it is absent, so that the other suites can run in a new clone.
An existing wad/cfg.json is never modified. Not a PowerShell/Windows test.
"""
from pathlib import Path
import json
import os
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from prepare_dev import TEMPLATE, check_pack_config, ensure_config

ensure_config(ROOT)


class PrepareDevTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "wad").mkdir()
        (self.root / "tools").mkdir()
        (self.root / TEMPLATE).write_bytes((ROOT / TEMPLATE).read_bytes())

    def tearDown(self):
        self.tmp.cleanup()

    def test_template_is_unconfigured_model(self):
        data = json.loads((ROOT / TEMPLATE).read_text("utf-8-sig"))
        self.assertIs(data.get("Configured"), False)
        self.assertEqual(set(data), {"SchemaVersion", "Configured", "Notice"})

    def test_creates_when_absent(self):
        self.assertEqual(ensure_config(self.root), "created")
        self.assertEqual((self.root / "wad/cfg.json").read_bytes(), (ROOT / TEMPLATE).read_bytes())

    def test_never_overwrites_existing_config(self):
        (self.root / "wad/cfg.json").write_text('{"PRIVATE-CONFIG":"preserve"}')
        self.assertEqual(ensure_config(self.root), "present")
        self.assertEqual((self.root / "wad/cfg.json").read_text(), '{"PRIVATE-CONFIG":"preserve"}')

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_leaves_link_untouched(self):
        outside = self.root / "outside.json"
        outside.write_text("{}")
        try:
            (self.root / "wad/cfg.json").symlink_to(outside)
        except OSError:
            self.skipTest("symlink not permitted")
        self.assertEqual(ensure_config(self.root), "present")
        self.assertEqual(outside.read_text(), "{}")

    def test_missing_template_refused(self):
        (self.root / TEMPLATE).unlink()
        with self.assertRaises(FileNotFoundError):
            ensure_config(self.root)
        self.assertFalse((self.root / "wad/cfg.json").exists())

    def test_pack_guard_accepts_template_only(self):
        ensure_config(self.root)
        self.assertEqual(check_pack_config(self.root), "template")
        (self.root / "wad/cfg.json").write_text('{"Configured":true,"Domaine":"interne.example"}')
        with self.assertRaises(ValueError):
            check_pack_config(self.root)
        self.assertEqual(check_pack_config(self.root, allow_config=True), "custom")
        self.assertIn("interne.example", (self.root / "wad/cfg.json").read_text())


if __name__ == "__main__":
    unittest.main()
