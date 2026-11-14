"""Git checkouts must retain the bytes bound into the launcher and Common lock."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DEV = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('git'), 'Git required for the isolated checkout fixture')
class CheckoutBytesTests(unittest.TestCase):
    def test_windows_checkout_preserves_runtime_and_vendor_bytes(self):
        attributes = ROOT / '.gitattributes'
        if not attributes.exists() and not (ROOT / 'CLAUDE.md').exists():
            self.skipTest('Repository checkout policy is not part of the standalone DEV pack')
        expected = {
            'DEV/wad/Pesto-Core.ps1': b'\xef\xbb\xbf# LF input\nfunction Example {}\n',
            'DEV/wad/Pesto-Enterprise.ps1': b'\xef\xbb\xbf# CRLF input\r\nfunction Example {}\r\n',
            'DEV/wad/Pesto.Engine.build.json': b'\xef\xbb\xbf{"Schema":1}\r\n',
            'DEV/vendor/M4D.Admin.Common/src/Core/Fixture.cs': b'// LF source\nclass Fixture {}\n',
        }
        self.assert_preserved(attributes, expected)

    def test_standalone_dev_checkout_preserves_runtime_and_vendor_bytes(self):
        self.assert_preserved(DEV / '.gitattributes', {
            'wad/Pesto-Core.ps1': b'\xef\xbb\xbf# LF input\nfunction Example {}\n',
            'wad/Pesto-Enterprise.ps1': b'\xef\xbb\xbf# CRLF input\r\nfunction Example {}\r\n',
            'wad/Pesto.Engine.build.json': b'\xef\xbb\xbf{"Schema":1}\r\n',
            'vendor/M4D.Admin.Common/src/Core/Fixture.cs': b'// LF source\nclass Fixture {}\n',
        })

    def assert_preserved(self, attributes, expected):
        with tempfile.TemporaryDirectory(prefix='pesto-checkout-') as tmp:
            root = Path(tmp)
            def git(*args):
                return subprocess.run(['git', '-C', str(root), *args], check=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            git('init', '--quiet')
            git('config', 'core.autocrlf', 'true')
            git('config', 'core.safecrlf', 'false')
            (root / '.gitattributes').write_bytes(attributes.read_bytes())
            for relative, raw in expected.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            git('add', '--', '.gitattributes', *expected)
            for relative in expected:
                (root / relative).unlink()
            git('checkout-index', '--force', '--all')
            for relative, raw in expected.items():
                self.assertEqual(raw, (root / relative).read_bytes(), relative)


if __name__ == '__main__':
    unittest.main(verbosity=2)
