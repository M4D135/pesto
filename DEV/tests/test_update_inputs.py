"""Malformed update inputs: local temporary files only, no Windows or AD calls."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import update_installation as update
from refresh_manifest import file_hash, runtime_files, verify_runtime


class UpdateInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pesto-invalid-json-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.installed = self.base / 'installed'
        for relative in (*runtime_files(ROOT), 'wad/package.json'):
            target = self.installed / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        (self.installed / 'wad/cfg.json').write_text('{"private":"keep"}')
        self.manifest_path = self.installed / 'wad/package.json'
        self.manifest = json.loads(self.manifest_path.read_text('utf-8-sig'))

    def write_manifest(self, value):
        self.manifest_path.write_text(json.dumps(value), encoding='utf-8')

    def snapshot(self):
        return {p.relative_to(self.installed).as_posix(): file_hash(p)
                for p in self.installed.rglob('*') if p.is_file()}

    def test_current_engine_build_manifest_is_an_installed_runtime_component(self):
        before=self.snapshot()
        paths=update.old_components(self.installed)
        self.assertIn('wad/Pesto.Engine.build.json',paths)
        self.assertIn('wad/M4D.Admin.Common.IO.dll',paths)
        self.assertEqual(set(paths),set(runtime_files(ROOT)))
        self.assertEqual(before,self.snapshot())

    def test_installed_component_budget_accepts_boundary_not_unbounded_input(self):
        data=json.loads(json.dumps(self.manifest))
        while len(data['Files'])<update.MAX_RUNTIME_COMPONENTS:
            relative='wad/Pesto-BudgetFixture'+str(len(data['Files']))+'.ps1'
            (self.installed/relative).write_text('# fixture only')
            data['Files'].append({'Path':relative,'SHA256':file_hash(self.installed/relative)})
        self.write_manifest(data)
        self.assertEqual(len(update.old_components(self.installed)),update.MAX_RUNTIME_COMPONENTS)
        data['Files'].append(dict(data['Files'][-1]))
        self.write_manifest(data)
        with self.assertRaisesRegex(ValueError,'file count'):
            update.old_components(self.installed)

    def test_recovery_accepts_only_explicit_new_runtime_formats(self):
        for name in ('wad/Pesto.Engine.build.json','wad/Pesto.Engine.Runtime.ps1',
                     'wad/Pesto.Engine.psm1','wad/Pesto.Engine.psd1','wad/Invoke-Pesto.ps1',
                     'wad/M4D.Admin.Common.IO.dll','wad/M4D.Admin.Common.Diagnostics.dll'):
            update._validate_recovery_relative(name)
        for name in ('wad/Pesto.Engine.exports.json','wad/cfg.json','wad/Pesto-private.json',
                     'wad/other.json','wad/OtherModule.psm1','wad/Other.dll','wad/Pesto-private.log',
                     'wad/Pesto-setup.cmd','../Pesto.exe','wad/Pesto.Engine.unknown.ps1'):
            with self.subTest(name=name),self.assertRaises(ValueError):
                update._validate_recovery_relative(name)

    def test_engine_metadata_tamper_is_not_excused_by_extension(self):
        (self.installed/'wad/Pesto.Engine.build.json').write_text('{}')
        with self.assertRaisesRegex(ValueError,'incomplete or modified'):
            update.old_components(self.installed)

    def test_installed_manifest_must_be_object(self):
        for value in ([], None, 42, 'manifest'):
            with self.subTest(value=value):
                self.write_manifest(value)
                before = self.snapshot()
                with self.assertRaises(ValueError):
                    update.old_components(self.installed)
                self.assertEqual(before, self.snapshot())

    def test_installed_entries_must_be_objects(self):
        for value in ([], None, 42, 'entry'):
            with self.subTest(value=value):
                data = json.loads(json.dumps(self.manifest))
                data['Files'][0] = value
                self.write_manifest(data)
                with self.assertRaises(ValueError):
                    update.old_components(self.installed)

    def test_installed_version_must_be_string(self):
        for value in ([], None, {}, 42):
            with self.subTest(value=value):
                self.write_manifest(dict(self.manifest, Version=value))
                with self.assertRaises(ValueError):
                    update.old_components(self.installed)

    def test_installed_hash_must_be_string(self):
        for value in ([], None, {}, 42):
            with self.subTest(value=value):
                data = json.loads(json.dumps(self.manifest))
                data['Files'][0]['SHA256'] = value
                self.write_manifest(data)
                with self.assertRaises(ValueError):
                    update.old_components(self.installed)

    def test_downgrade_check_rejects_nonobject_manifest(self):
        self.write_manifest([])
        with self.assertRaises(ValueError):
            update._assert_not_downgrade(self.installed, False)

    def test_local_receipt_must_be_object_and_is_preserved(self):
        receipt = self.base / 'GP/Interventions/receipt.json'
        receipt.parent.mkdir(parents=True)
        # Select the Windows-only receipt reader with a local environment stub.
        # pathlib and the filesystem remain native macOS/Linux; no Windows API runs.
        local_os = SimpleNamespace(name='nt', environ={'ProgramData': str(self.base)})
        for value in ([], None, 42, 'receipt'):
            with self.subTest(value=value):
                content = json.dumps(value)
                receipt.write_text(content, encoding='utf-8')
                with mock.patch.object(update, 'os', local_os):
                    with self.assertRaises(ValueError):
                        update.check_local_states()
                self.assertEqual(receipt.read_text('utf-8'), content)
        for phase in ('Failed', 'NotStarted', 'Verified'):
            receipt.write_text(json.dumps({'Phase': phase}), encoding='utf-8')
            with mock.patch.object(update, 'os', local_os):
                update.check_local_states()

    def test_cli_refuses_invalid_manifest_without_traceback_or_changes(self):
        self.write_manifest([])
        before = self.snapshot()
        for flags in ([], ['--apply']):
            with self.subTest(flags=flags):
                result = subprocess.run(
                    [sys.executable, str(ROOT / 'tools/update_installation.py'),
                     '--source', str(ROOT), '--destination', str(self.installed), *flags],
                    capture_output=True, text=True, env=dict(os.environ, ProgramData=str(self.base)),
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn('Update refused:', result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                self.assertEqual(before, self.snapshot())
                self.assertFalse((self.installed / '.pesto-update.lock').exists())

    def test_source_manifest_and_entries_must_be_objects(self):
        for value in ([], None, 42, 'manifest'):
            with self.subTest(root=value):
                self.write_manifest(value)
                with self.assertRaises(ValueError):
                    verify_runtime(self.installed)
            with self.subTest(entry=value):
                data = json.loads(json.dumps(self.manifest))
                data['Files'][0] = value
                self.write_manifest(data)
                with self.assertRaises(ValueError):
                    verify_runtime(self.installed)


if __name__ == '__main__':
    unittest.main(verbosity=2)
