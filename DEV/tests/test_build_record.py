"""Build record checks (tools/launcher/last-build.json). Portable; no Windows execution."""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location("build_packs", ROOT / "tools/Build-PestoPacks.py")
build_packs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_packs)


class BuildRecordTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "tools/launcher").mkdir(parents=True)
        (self.root / "Pesto.exe").write_bytes(b"MZ-test")

    def tearDown(self):
        self.tmp.cleanup()

    def write_record(self, digest):
        (self.root / "tools/launcher/last-build.json").write_text(json.dumps({"SHA256": digest, "Clang": "clang 1", "Lld": "lld 1"}))

    def test_absent_record_is_not_required(self):
        self.assertIsNone(build_packs.check_build_record(self.root))

    def test_matching_record_reports_toolchain(self):
        self.write_record(hashlib.sha256(b"MZ-test").hexdigest())
        self.assertEqual(build_packs.check_build_record(self.root)["Clang"], "clang 1")

    def test_stale_record_refused(self):
        self.write_record("0" * 64)
        with self.assertRaises(ValueError):
            build_packs.check_build_record(self.root)


if __name__ == "__main__":
    unittest.main()
