"""Managed ownership and durable update fixtures; no Pesto/Windows/AD execution.

Child processes deliberately terminate only their own temporary-file updater.
Their Windows coordination is doubled, so this suite never takes the real
application mutex or reads operation receipts on the test host.
"""
import contextlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import managed_install as managed
import update_installation as update
from installation_receipt import RECEIPT, PROD_HELPERS
from package_distribution import build_directory
from refresh_manifest import file_hash, runtime_files, write_manifest, verify_runtime


def fixture(root, generation):
    (root / 'wad/support').mkdir(parents=True)
    (root / 'tools').mkdir()
    paths = ['Pesto.exe', 'wad/Pesto-Integrity.ps1']
    paths += ['wad/Pesto-Fixture%02d.ps1' % i for i in range(18)]
    paths += ['wad/Pesto-' + ('Retired' if generation == 'old' else 'Added') + '.ps1']
    (root / 'wad/Pesto-Integrity.ps1').write_text(
        '# BEGIN Pesto_RUNTIME_FILES\n@(\n' + ','.join(repr(p) for p in paths) +
        '\n)\n# END Pesto_RUNTIME_FILES\n', encoding='utf-8')
    for path in paths[2:]:
        (root / path).write_text('# ' + generation + ' inert fixture', encoding='utf-8')
    (root / 'wad/cfg.json').write_text('{"Configured":false}', encoding='utf-8')
    (root / 'tools/cfg.template.json').write_bytes((root / 'wad/cfg.json').read_bytes())
    for helper in PROD_HELPERS:
        (root / helper).write_text('@rem ' + generation + ' helper fixture', encoding='utf-8')
    binding = 'PESTO_BINDING_V1\n' + ''.join(
        path + '|' + file_hash(root / path) + '\n' for path in paths[1:]) + 'PESTO_BINDING_END'
    (root / 'Pesto.exe').write_bytes(binding.encode('ascii'))
    write_manifest(root)
    return root


class ManagedUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pesto-managed-update-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.old = fixture(self.base / 'old-source', 'old')
        self.new = fixture(self.base / 'new-source', 'new')
        self.dest = self.base / 'installed'
        managed.install(self.old, self.dest)
        (self.dest / 'wad/cfg.json').write_text('private configuration', encoding='utf-8')
        (self.dest / 'wad/private-note.txt').write_text('keep', encoding='utf-8')
        self.before = self.snapshot()
        for module in (managed, update):
            guard = mock.patch.object(module, 'mutation_guard', contextlib.nullcontext)
            guard.start(); self.addCleanup(guard.stop)
            states = mock.patch.object(module, 'check_local_states', lambda: None)
            states.start(); self.addCleanup(states.stop)
        session = mock.patch.object(update, '_check_pesto_session_lock', lambda destination: None)
        session.start(); self.addCleanup(session.stop)

    def test_existing_installation_is_preserved_when_install_refuses_it(self):
        with self.assertRaises(ValueError):
            managed.install(self.old, self.dest)
        self.assertEqual(self.snapshot(), self.before)

    def test_detect_reports_missing_owned_file_without_traceback(self):
        (self.dest / 'Pesto.exe').unlink()
        result = managed.detect(self.dest)
        self.assertTrue(result['installed'])
        self.assertFalse(result['healthy'])
        self.assertIn('Pesto.exe', result['changed'])
        with self.assertRaises(ValueError):
            managed.uninstall(self.dest, True)

    def test_detect_reports_invalid_receipt_without_adopting_files(self):
        (self.dest / RECEIPT).write_text('{broken', encoding='utf-8')
        result = managed.detect(self.dest)
        self.assertTrue(result['installed'])
        self.assertFalse(result['healthy'])
        self.assertEqual(result['owned'], [])
        with self.assertRaises(ValueError):
            managed.uninstall(self.dest, True)

    def test_recovery_report_never_claims_success_before_fence_removal(self):
        self.crash(after=1)
        fence, lock, _, _ = self.journal()
        original_unlink = Path.unlink
        def refuse_fence(path, *args, **kwargs):
            if path == fence:
                raise PermissionError('Synthetic fence removal denial')
            return original_unlink(path, *args, **kwargs)
        with mock.patch.object(Path, 'unlink', refuse_fence):
            with self.assertRaises(PermissionError):
                update.recover_update(self.dest, apply=True)
        report = json.loads((Path(lock['Backup']) / 'recovery-result.json').read_text())
        self.assertFalse(report['Recovered'])
        self.assertTrue(fence.is_file())
        self.assertTrue(update.recover_update(self.dest, apply=True)['Recovered'])
        self.assert_old()

    def test_file_replacement_syncs_its_parent_directory(self):
        with mock.patch.object(update, '_fsync_directory') as sync:
            update._replace_from(self.new / 'Pesto.exe', self.dest / 'Pesto.exe')
        sync.assert_called_with(self.dest)


    def test_install_publishes_receipt_through_atomic_writer(self):
        target = self.base / 'second-installation'
        with mock.patch.object(managed, '_write_json', wraps=managed._write_json) as write:
            receipt = managed.install(self.old, target)
        write.assert_called_once_with(target / RECEIPT, receipt)
        self.assertTrue(managed.detect(target)['healthy'])

    def test_receipt_publication_failure_removes_only_the_new_installation(self):
        target = self.base / 'failed-installation'
        with mock.patch.object(managed, '_write_json', side_effect=OSError('Synthetic publication failure')):
            with self.assertRaises(OSError): managed.install(self.old, target)
        self.assertFalse(target.exists())
        self.assertEqual(self.snapshot(), self.before)
        verify_runtime(self.old)

    def test_final_report_failure_does_not_reclassify_restored_code(self):
        self.crash(after=1)
        write = update._write_json
        def fail_success_report(path, value):
            if path.name == 'recovery-result.json' and value.get('Recovered'):
                raise OSError('Synthetic final report failure')
            return write(path, value)
        with mock.patch.object(update, '_write_json', fail_success_report):
            result = update.recover_update(self.dest, apply=True)
        self.assertTrue(result['Recovered'])
        self.assertFalse(result['ResultReportWritten'])
        self.assert_old()


    def snapshot(self):
        return {p.relative_to(self.dest).as_posix(): file_hash(p)
                for p in self.dest.rglob('*') if p.is_file()}

    def boundaries(self):
        return len(set(runtime_files(self.old)) | set(runtime_files(self.new)) |
                   {'wad/package.json', RECEIPT} | set(PROD_HELPERS))

    def assert_old(self):
        self.assertEqual(self.snapshot(), self.before)
        self.assertTrue(managed.detect(self.dest)['healthy'])
        self.assertFalse((self.dest / '.pesto-update.lock').exists())

    def crash(self, *, after=None, stage=None):
        code = (
            'import sys,contextlib,json;from pathlib import Path;'
            'sys.path.insert(0,sys.argv[1]);import update_installation as u;'
            'u.mutation_guard=contextlib.nullcontext;u.check_local_states=lambda:None;u._check_pesto_session_lock=lambda p:None;'
            'u.apply_update(Path(sys.argv[2]),Path(sys.argv[3]),**json.loads(sys.argv[4]))')
        flags = {'_crash_after': after} if after is not None else {'_crash_stage': stage}
        result = subprocess.run([sys.executable, '-c', code, str(ROOT / 'tools'),
                                 str(self.new), str(self.dest), json.dumps(flags)],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 93 if after is not None else 94 if stage == 'preparing' else 95,
                         result.stderr)
        self.assertTrue((self.dest / '.pesto-update.lock').is_file())

    def journal(self):
        fence = self.dest / '.pesto-update.lock'
        lock = json.loads(fence.read_text(encoding='utf-8'))
        path = Path(lock['Backup']) / 'transaction.json'
        return fence, lock, path, json.loads(path.read_text(encoding='utf-8'))

    def rewrite_journal(self, fence, lock, path, journal):
        path.write_text(json.dumps(journal), encoding='utf-8')
        lock['JournalSHA256'] = file_hash(path)
        fence.write_text(json.dumps(lock), encoding='utf-8')

    def test_upgrade_detect_and_uninstall_preserve_private_and_retired_files(self):
        preview = update.plan_update(self.new, self.dest)
        self.assertTrue(preview['ManagedInstallation'])
        self.assertEqual(self.snapshot(), self.before)
        result = update.apply_update(self.new, self.dest)
        self.assertTrue(result['ManagedInstallation'])
        self.assertTrue(managed.detect(self.dest)['healthy'])
        self.assertEqual(file_hash(self.dest / 'Pesto.exe'), file_hash(self.new / 'Pesto.exe'))
        self.assertNotEqual(file_hash(self.dest / RECEIPT), self.before[RECEIPT])
        for helper in PROD_HELPERS:
            self.assertEqual(file_hash(self.dest / helper), self.before[helper])
            self.assertNotEqual(file_hash(self.dest / helper), file_hash(self.new / helper))
        records = json.loads((Path(result['Backup']) / 'transaction.json').read_text())['Records']
        self.assertEqual(records[-1]['Path'], RECEIPT)
        self.assertTrue(managed.uninstall(self.dest, True)['executed'])
        self.assertEqual((self.dest / 'wad/cfg.json').read_text(), 'private configuration')
        self.assertEqual((self.dest / 'wad/private-note.txt').read_text(), 'keep')
        self.assertEqual(file_hash(self.dest / 'wad/Pesto-Retired.ps1'), self.before['wad/Pesto-Retired.ps1'])
        self.assertFalse(managed.detect(self.dest)['installed'])

    def test_portable_installation_is_never_adopted_from_source(self):
        portable = self.base / 'portable'
        build_directory(self.old, portable, 'PROD')
        (self.new / RECEIPT).write_text('must not be copied', encoding='utf-8')
        self.assertFalse(update.plan_update(self.new, portable)['ManagedInstallation'])
        self.assertFalse(update.apply_update(self.new, portable)['ManagedInstallation'])
        self.assertFalse((portable / RECEIPT).exists())
        self.assertFalse(managed.detect(portable)['installed'])
        verify_runtime(portable)

    def test_invalid_ownership_is_refused_before_any_destination_write(self):
        receipt_path = self.dest / RECEIPT
        original = json.loads(receipt_path.read_text())
        variants = [dict(original, schema=True), dict(original, version='wrong'),
                    dict(original, files={**original['files'], 'wad/cfg.json': file_hash(self.dest / 'wad/cfg.json')}),
                    dict(original, files={**original['files'], 'Pesto.exe': 'bad'})]
        for value in variants:
            with self.subTest(value=value.get('schema'), version=value.get('version')):
                receipt_path.write_text(json.dumps(value), encoding='utf-8')
                before = self.snapshot()
                with self.assertRaises(ValueError): update.apply_update(self.new, self.dest)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse((self.dest / '.pesto-update.lock').exists())

    def test_modified_owned_helper_is_not_silently_rebaseline(self):
        (self.dest / PROD_HELPERS[0]).write_text('foreign change', encoding='utf-8')
        before = self.snapshot()
        with self.assertRaises(ValueError): update.apply_update(self.new, self.dest)
        self.assertEqual(self.snapshot(), before)

    def test_broken_receipt_link_is_refused_not_treated_as_portable(self):
        target = self.dest / RECEIPT
        target.unlink(); target.symlink_to(self.base / 'missing-receipt')
        with self.assertRaises(ValueError): update.plan_update(self.new, self.dest)
        with self.assertRaises(ValueError): managed.detect(self.dest)
        self.assertTrue(target.is_symlink())

    def test_rollback_at_every_boundary_restores_original_receipt(self):
        for boundary in range(1, self.boundaries() + 1):
            with self.subTest(boundary=boundary):
                with self.assertRaises(OSError): update.apply_update(self.new, self.dest, _inject_after=boundary)
                self.assert_old()

    def test_crash_recovery_at_every_replacement_boundary(self):
        for boundary in range(1, self.boundaries() + 1):
            with self.subTest(boundary=boundary):
                self.crash(after=boundary)
                preview = update.recover_update(self.dest)
                self.assertEqual(preview['Kind'], 'RestorePreviousCodeOnly')
                self.assertFalse(preview['Conflicts'])
                self.assertTrue(update.recover_update(self.dest, apply=True)['Recovered'])
                self.assert_old()

    def test_second_process_crash_during_recovery_is_itself_recoverable(self):
        for boundary in (1, 5):
            with self.subTest(recovery_boundary=boundary):
                self.crash(after=self.boundaries())
                code = """
import sys, contextlib, os
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import update_installation as u
u.mutation_guard = contextlib.nullcontext
u.check_local_states = lambda: None
original = u._replace_from
count = 0
def interrupted(source, target):
    global count
    original(source, target)
    count += 1
    if count == int(sys.argv[3]): os._exit(96)
u._replace_from = interrupted
u.recover_update(Path(sys.argv[2]), apply=True)
"""
                result = subprocess.run([sys.executable, '-c', code, str(ROOT / 'tools'),
                                         str(self.dest), str(boundary)],
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 96, result.stderr)
                self.assertTrue((self.dest / '.pesto-update.lock').is_file())
                self.assertFalse(update.recover_update(self.dest)['Conflicts'])
                self.assertTrue(update.recover_update(self.dest, apply=True)['Recovered'])
                self.assert_old()

    def test_completed_crash_keeps_new_healthy_ownership_and_allows_uninstall(self):
        self.crash(stage='completed')
        before = file_hash(self.dest / RECEIPT)
        self.assertEqual(update.recover_update(self.dest)['Kind'], 'ReleaseCompletedUpdate')
        self.assertTrue(update.recover_update(self.dest, apply=True)['Recovered'])
        self.assertEqual(file_hash(self.dest / RECEIPT), before)
        self.assertTrue(managed.detect(self.dest)['healthy'])
        self.assertTrue(managed.uninstall(self.dest, True)['executed'])

    def test_preparation_crash_keeps_original_receipt(self):
        self.crash(stage='preparing')
        self.assertEqual(update.recover_update(self.dest)['Kind'], 'ReleaseInterruptedPreparation')
        self.assertTrue(update.recover_update(self.dest, apply=True)['Recovered'])
        self.assert_old()

    def test_preparation_crash_missing_receipt_keeps_fence(self):
        self.crash(stage='preparing')
        (self.dest / RECEIPT).unlink()
        with self.assertRaises(ValueError): update.recover_update(self.dest, apply=True)
        self.assertTrue((self.dest / '.pesto-update.lock').is_file())

    def test_concurrent_receipt_change_refuses_recovery_without_writes(self):
        self.crash(after=1)
        (self.dest / RECEIPT).write_text('{"foreign":"keep"}', encoding='utf-8')
        before = self.snapshot()
        with self.assertRaises(ValueError): update.recover_update(self.dest, apply=True)
        self.assertEqual(self.snapshot(), before)

    def test_corrupt_receipt_backup_keeps_fence(self):
        self.crash(after=1)
        _, lock, _, _ = self.journal()
        (Path(lock['Backup']) / 'old' / RECEIPT).write_text('{}', encoding='utf-8')
        before = self.snapshot()
        with self.assertRaises(ValueError): update.recover_update(self.dest, apply=True)
        self.assertEqual(self.snapshot(), before)

    def test_recovery_cannot_add_configuration_to_owned_paths_even_with_rehashed_journal(self):
        self.crash(after=1)
        fence, lock, path, journal = self.journal()
        journal['Records'].append({'Path': 'wad/cfg.json', 'OldSHA256': None, 'NewSHA256': 'a' * 64})
        self.rewrite_journal(fence, lock, path, journal)
        before = self.snapshot()
        with self.assertRaises(ValueError): update.recover_update(self.dest, apply=True)
        self.assertEqual(self.snapshot(), before)

    def test_recovery_requires_preexisting_receipt_ownership(self):
        self.crash(after=1)
        fence, lock, path, journal = self.journal()
        for record in journal['Records']:
            if record['Path'] == RECEIPT: record['OldSHA256'] = None
        self.rewrite_journal(fence, lock, path, journal)
        with self.assertRaises(ValueError): update.recover_update(self.dest, apply=True)
        self.assertTrue((self.dest / '.pesto-update.lock').is_file())

    def test_ownership_paths_require_explicit_boolean_managed_flag(self):
        for flag in (False, 1, 'true'):
            with self.subTest(flag=flag):
                if not (self.dest / '.pesto-update.lock').exists(): self.crash(after=1)
                fence, lock, path, journal = self.journal()
                journal['ManagedInstallation'] = flag
                self.rewrite_journal(fence, lock, path, journal)
                with self.assertRaises(ValueError): update.recover_update(self.dest, apply=True)
                self.assertTrue((self.dest / '.pesto-update.lock').exists())

    def test_incomplete_receipt_rollback_is_recoverable_and_never_releases_fence(self):
        replace = update._replace_from
        def fail_receipt_restore(source, target):
            if source.name == RECEIPT and 'old' in source.parts:
                raise OSError('fixture backup temporarily unavailable')
            return replace(source, target)
        with mock.patch.object(update, '_replace_from', side_effect=fail_receipt_restore):
            with self.assertRaises(RuntimeError):
                update.apply_update(self.new, self.dest, _inject_after=self.boundaries())
        self.assertTrue((self.dest / '.pesto-update.lock').exists())
        self.assertTrue(update.recover_update(self.dest, apply=True)['Recovered'])
        self.assert_old()


if __name__ == '__main__': unittest.main(verbosity=2)
