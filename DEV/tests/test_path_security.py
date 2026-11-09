import stat, sys, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import refresh_manifest as rm
import update_installation as ui
from refresh_manifest import runtime_files, safe_file, validate_relative, _is_link_or_junction
from update_installation import _plain_target


class ValidateRelativeTests(unittest.TestCase):
    def test_valid(self):
        for rel in (
            "Pesto.exe",
            "wad/Pesto-Core.ps1",
            "wad/package.json",
            "wad/cfg.json",
            "wad/foo.log",
            "wad/foo.JSON",
            "wad/foo.LOG",
            "wad/fr-FR/ActiveDirectoryPowerShellResources.dll.mui",
            "COM0",
            "COM10",
            "LPT0",
            "LPT10",
            "CONS",
            "CONSOLE",
            ".CON",
        ):
            validate_relative(rel)

    def test_trailing_dot_or_space(self):
        for rel in (
            "wad/cfg.json.",
            "wad/cfg.json ",
            "wad/dir./file",
            "wad/dir /file",
            "Pesto.exe.",
            "Pesto.exe ",
            "CON ",
            "CON.txt ",
        ):
            with self.subTest(rel=rel):
                with self.assertRaises(ValueError):
                    validate_relative(rel)

    def test_reserved_windows_names(self):
        for rel in (
            "CON",
            "con.txt",
            "wad/PRN.log",
            "AUX",
            "NUL",
            "COM1",
            "COM9.txt",
            "LPT1",
            "LPT9.log",
            "wad/COM1",
            "CON.",
            "CON.txt.",
            "COM1.",
            "COM1.txt.",
            "LPT1.",
            "LPT9.txt.",
            "PRN.",
            "AUX.",
            "NUL.",
        ):
            with self.subTest(rel=rel):
                with self.assertRaises(ValueError):
                    validate_relative(rel)

    def test_alternate_data_stream(self):
        for rel in (
            "wad/file.txt:stream",
            "wad/file.txt::$DATA",
            "CON.txt:ADS",
            "CON:ADS",
            "NUL:ADS",
            "C:/foo",
        ):
            with self.subTest(rel=rel):
                with self.assertRaises(ValueError):
                    validate_relative(rel)

    def test_invalid_and_traversal(self):
        for rel in (
            "../x",
            "wad/../x",
            "wad/./x",
            "/etc/passwd",
            r"wad\x",
            "wad//x",
            "wad/x/",
            "",
            b"x",
        ):
            with self.subTest(rel=rel):
                with self.assertRaises(ValueError):
                    validate_relative(rel)


class RuntimeFilesTests(unittest.TestCase):
    def _root(self, entries):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        (root / "wad").mkdir()
        body = ",".join(f"'{e}'" for e in entries)
        (root / "wad/Pesto-Integrity.ps1").write_text(
            "# BEGIN Pesto_RUNTIME_FILES\n@(" + body + ")\n# END Pesto_RUNTIME_FILES\n",
            encoding="utf-8",
        )
        return root

    def test_valid(self):
        root = self._root(("Pesto.exe", "wad/Pesto-Core.ps1"))
        self.assertEqual(runtime_files(root), ("Pesto.exe", "wad/Pesto-Core.ps1"))

    def test_json_and_log_refused(self):
        for entries in (
            ("Pesto.exe", "wad/package.json"),
            ("Pesto.exe", "wad/cfg.json"),
            ("Pesto.exe", "wad/foo.log"),
            ("Pesto.exe", "wad/foo.JSON"),
            ("Pesto.exe", "wad/foo.LOG"),
        ):
            with self.subTest(entries=entries):
                with self.assertRaises(ValueError):
                    runtime_files(self._root(entries))

    def test_dangerous_names_refused(self):
        for entries in (
            ("Pesto.exe", "wad/CON.txt"),
            ("Pesto.exe", "wad/file.txt:ADS"),
            ("Pesto.exe", "wad/file.txt."),
            ("Pesto.exe", "wad/file.txt "),
        ):
            with self.subTest(entries=entries):
                with self.assertRaises(ValueError):
                    runtime_files(self._root(entries))


class IsLinkOrJunctionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.file = self.root / "file.txt"
        self.file.write_text("x")

    def _fake_stat(self, attrs=None):
        if attrs is None:
            return SimpleNamespace()
        return SimpleNamespace(st_file_attributes=attrs)

    def test_normal_false(self):
        self.assertFalse(_is_link_or_junction(self.file))

    def test_symlink_true(self):
        link = self.root / "link"
        try:
            link.symlink_to(self.file)
        except OSError as exc:
            self.skipTest(f"symlinks not available: {exc}")
        self.assertTrue(_is_link_or_junction(link))

    def test_symlink_true_without_is_junction(self):
        link = self.root / "link2"
        try:
            link.symlink_to(self.file)
        except OSError as exc:
            self.skipTest(f"symlinks not available: {exc}")
        with mock.patch.object(Path, "is_junction", None, create=True):
            self.assertTrue(_is_link_or_junction(link))

    def test_is_junction_true(self):
        with mock.patch.object(Path, "is_junction", return_value=True, create=True):
            self.assertTrue(_is_link_or_junction(self.file))

    def test_is_junction_false(self):
        with mock.patch.object(Path, "is_junction", return_value=False, create=True):
            self.assertFalse(_is_link_or_junction(self.file))

    def test_is_junction_absent_normal_false(self):
        with mock.patch.object(Path, "is_junction", None, create=True):
            self.assertFalse(_is_link_or_junction(self.file))

    def test_windows_reparse_fallback(self):
        attrs = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x00000400)
        with mock.patch.object(Path, "is_symlink", return_value=False), \
             mock.patch.object(Path, "is_junction", None, create=True), \
             mock.patch.object(rm.os, "name", "nt"), \
             mock.patch.object(rm.os, "lstat", return_value=self._fake_stat(attrs)):
            self.assertTrue(_is_link_or_junction(self.file))

    def test_windows_normal_fallback(self):
        with mock.patch.object(Path, "is_symlink", return_value=False), \
             mock.patch.object(Path, "is_junction", None, create=True), \
             mock.patch.object(rm.os, "name", "nt"), \
             mock.patch.object(rm.os, "lstat", return_value=self._fake_stat(0)):
            self.assertFalse(_is_link_or_junction(self.file))

    def test_windows_missing_attributes_fallback(self):
        with mock.patch.object(Path, "is_symlink", return_value=False), \
             mock.patch.object(Path, "is_junction", None, create=True), \
             mock.patch.object(rm.os, "name", "nt"), \
             mock.patch.object(rm.os, "lstat", return_value=self._fake_stat()):
            self.assertFalse(_is_link_or_junction(self.file))

    def test_windows_lstat_error_fallback(self):
        with mock.patch.object(Path, "is_symlink", return_value=False), \
             mock.patch.object(Path, "is_junction", None, create=True), \
             mock.patch.object(rm.os, "name", "nt"), \
             mock.patch.object(rm.os, "lstat", side_effect=OSError):
            self.assertFalse(_is_link_or_junction(self.file))

    def test_is_junction_error_then_windows_fallback(self):
        attrs = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x00000400)
        with mock.patch.object(Path, "is_symlink", return_value=False), \
             mock.patch.object(Path, "is_junction", side_effect=OSError, create=True), \
             mock.patch.object(rm.os, "name", "nt"), \
             mock.patch.object(rm.os, "lstat", return_value=self._fake_stat(attrs)):
            self.assertTrue(_is_link_or_junction(self.file))

    def test_symlink_error_then_fallback(self):
        attrs = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x00000400)
        with mock.patch.object(Path, "is_symlink", side_effect=OSError), \
             mock.patch.object(Path, "is_junction", None, create=True), \
             mock.patch.object(rm.os, "name", "nt"), \
             mock.patch.object(rm.os, "lstat", return_value=self._fake_stat(attrs)):
            self.assertTrue(_is_link_or_junction(self.file))


class ConfinementTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        root = self.base / "root"
        root.mkdir()
        self.root = root.resolve(strict=True)
        self.addCleanup(self.tmp.cleanup)
        self.outside = self.base / "outside.txt"
        self.outside.write_text("outside")

    def _symlink(self, link, target):
        try:
            link.symlink_to(target)
        except OSError as exc:
            self.skipTest(f"symlinks not available: {exc}")

    def test_safe_file_normal(self):
        p = self.root / "file.txt"
        p.write_text("x")
        self.assertEqual(safe_file(self.root, "file.txt"), p)

    def test_safe_file_missing(self):
        with self.assertRaises(ValueError):
            safe_file(self.root, "missing.txt")

    def test_safe_file_uses_link_detector(self):
        p = self.root / "file.txt"
        p.write_text("x")
        with mock.patch.object(rm, "_is_link_or_junction", return_value=True):
            with self.assertRaises(ValueError):
                safe_file(self.root, "file.txt")

    def test_safe_file_refuses_symlink_inside(self):
        target = self.root / "target.txt"
        target.write_text("x")
        link = self.root / "link.txt"
        self._symlink(link, target)
        with self.assertRaises(ValueError):
            safe_file(self.root, "link.txt")

    def test_safe_file_refuses_symlink_outside(self):
        link = self.root / "link.txt"
        self._symlink(link, self.outside)
        with self.assertRaises(ValueError):
            safe_file(self.root, "link.txt")

    def test_plain_target_normal(self):
        (self.root / "wad").mkdir()
        p = self.root / "wad/file.txt"
        p.write_text("x")
        self.assertEqual(_plain_target(self.root, "wad/file.txt"), p)

    def test_plain_target_missing_allowed(self):
        (self.root / "wad").mkdir()
        p = self.root / "wad/file.txt"
        self.assertEqual(_plain_target(self.root, "wad/file.txt"), p)

    def test_plain_target_refuses_directory(self):
        (self.root / "wad").mkdir()
        d = self.root / "wad/file.txt"
        d.mkdir()
        with self.assertRaises(ValueError):
            _plain_target(self.root, "wad/file.txt")

    def test_plain_target_refuses_symlink_inside(self):
        (self.root / "wad").mkdir()
        target = self.root / "target.txt"
        target.write_text("x")
        link = self.root / "wad/file.txt"
        self._symlink(link, target)
        with self.assertRaises(ValueError):
            _plain_target(self.root, "wad/file.txt")

    def test_plain_target_refuses_symlink_outside(self):
        (self.root / "wad").mkdir()
        link = self.root / "wad/file.txt"
        self._symlink(link, self.outside)
        with self.assertRaises(ValueError):
            _plain_target(self.root, "wad/file.txt")

    def test_plain_target_refuses_resolved_escape(self):
        (self.root / "wad").mkdir()
        p = self.root / "wad/file.txt"
        p.write_text("x")
        with mock.patch.object(Path, "resolve", return_value=self.outside):
            with self.assertRaises(ValueError):
                _plain_target(self.root, "wad/file.txt")

    def test_plain_target_refuses_resolved_escape_if_detector_false(self):
        (self.root / "wad").mkdir()
        link = self.root / "wad/file.txt"
        self._symlink(link, self.outside)
        with mock.patch.object(ui, "_is_link_or_junction", return_value=False):
            with self.assertRaises(ValueError):
                _plain_target(self.root, "wad/file.txt")

    def test_plain_target_uses_link_detector(self):
        (self.root / "wad").mkdir()
        p = self.root / "wad/file.txt"
        p.write_text("x")
        with mock.patch.object(ui, "_is_link_or_junction", return_value=True):
            with self.assertRaises(ValueError):
                _plain_target(self.root, "wad/file.txt")

    def test_plan_update_refuses_linked_root(self):
        dest = self.base / "dest"
        dest.mkdir()
        with mock.patch.object(ui, "_is_link_or_junction", return_value=True):
            with self.assertRaises(ValueError):
                ui.plan_update(self.root, dest)

    def test_update_imports_link_detector(self):
        self.assertTrue(callable(ui._is_link_or_junction))


if __name__ == "__main__":
    unittest.main(verbosity=2)
