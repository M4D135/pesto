"""Real installer against disposable files; no application or Windows call."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from refresh_manifest import runtime_files

PWSH = os.environ.get('PESTO_TEST_PWSH') or shutil.which('pwsh')


@unittest.skipUnless(PWSH, 'Set PESTO_TEST_PWSH to run local PowerShell installer fixtures')
class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.source = self.base / 'source'
        self.source.mkdir()
        required = runtime_files(ROOT)
        for relative in (*required, 'wad/cfg.json', 'wad/support/DEBLOQUER_TOUT.cmd'):
            target = self.source / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if relative == 'Pesto.exe':
                target.write_bytes(b'INERT INSTALLER FIXTURE - NEVER EXECUTED')
            else:
                shutil.copy2(ROOT / relative, target)
        manifest = {'Schema': 2, 'Version': '1.0', 'Scope': 'Runtime', 'Files': [
            {'Path': rel, 'SHA256': hashlib.sha256((self.source / rel).read_bytes()).hexdigest()}
            for rel in required]}
        (self.source / 'wad/package.json').write_text(json.dumps(manifest), encoding='utf-8')
        self.before = self.snapshot(self.source)

    @staticmethod
    def snapshot(directory):
        return {p.relative_to(directory): p.read_bytes() for p in directory.rglob('*') if p.is_file()}

    def install(self, target, config=None):
        command = [PWSH, '-NoProfile', '-File', str(ROOT / 'tools/Install-Pesto.ps1'),
                   '-SourceDirectory', str(self.source), '-Destination', str(target)]
        if config:
            command.extend(['-ConfigPath', str(config)])
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertFalse(list(self.base.glob('.pesto-install-*')), 'staging directory leaked')
        return result

    def test_install_copies_exact_payload_and_preserves_sources(self):
        target = self.base / 'installed'
        result = self.install(target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(target), self.before)
        self.assertEqual(self.snapshot(self.source), self.before)

    def test_existing_destination_preserved(self):
        target = self.base / 'installed'
        target.mkdir()
        (target / 'canary').write_text('keep')
        self.assertNotEqual(self.install(target).returncode, 0)
        self.assertEqual((target / 'canary').read_text(), 'keep')
        self.assertEqual(list(target.iterdir()), [target / 'canary'])

    def test_corrupted_runtime_refused(self):
        (self.source / 'wad/Pesto-Contracts.ps1').write_text('tampered')
        target = self.base / 'installed'
        self.assertNotEqual(self.install(target).returncode, 0)
        self.assertFalse(target.exists())

    def test_nested_destination_refused(self):
        target = self.source / 'installed'
        self.assertNotEqual(self.install(target).returncode, 0)
        self.assertFalse(target.exists())

    def test_config_array_refused_without_partial_install(self):
        config = self.base / 'cfg.json'
        config.write_text('[1,2]')
        target = self.base / 'installed'
        self.assertNotEqual(self.install(target, config).returncode, 0)
        self.assertFalse(target.exists())

    @unittest.skipIf(os.name == 'nt', 'link creation requires separate Windows privileges')
    def test_linked_parent_refused(self):
        real = self.base / 'real'
        real.mkdir()
        link = self.base / 'link'
        link.symlink_to(real, target_is_directory=True)
        self.assertNotEqual(self.install(link / 'installed').returncode, 0)
        self.assertFalse((real / 'installed').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
