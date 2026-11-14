"""Adversarial filesystem fixtures; no native build, Windows runtime or AD call."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import package_distribution as package
import prepare_dev
import refresh_manifest as integrity
import update_installation as update

spec = importlib.util.spec_from_file_location('pesto_native_edges', ROOT / 'tools/launcher/build_native.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
for module_name, filename in (('production', 'Build-PestoProduction.py'), ('packs', 'Build-PestoPacks.py')):
    module_spec = importlib.util.spec_from_file_location('pesto_edges_' + module_name, ROOT / 'tools' / filename)
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    globals()[module_name] = module


class PackagingEdgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pesto-package-edges-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.source = self.base / 'source'
        (self.source / 'wad/support').mkdir(parents=True)
        (self.source / 'tools/launcher').mkdir(parents=True)
        self.paths = ['Pesto.exe', 'wad/Pesto-Integrity.ps1', 'wad/Pesto-Core.ps1']
        self.make_runtime()
        (self.source / 'wad/support/DEBLOQUER_TOUT.cmd').write_text('fixture')
        template = (ROOT / prepare_dev.TEMPLATE).read_bytes()
        (self.source / prepare_dev.TEMPLATE).write_bytes(template)
        (self.source / 'wad/cfg.json').write_bytes(template)

    def make_runtime(self):
        closed = "# BEGIN Pesto_RUNTIME_FILES\n@(\n" + ',\n'.join(repr(p) for p in self.paths) + ")\n# END Pesto_RUNTIME_FILES\n"
        (self.source / 'wad/Pesto-Integrity.ps1').write_text(closed)
        for rel in self.paths:
            if rel not in ('Pesto.exe', 'wad/Pesto-Integrity.ps1'):
                p = self.source / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('inert fixture: ' + rel)
        description = '\n'.join(p + '|' + integrity.file_hash(self.source / p) for p in self.paths if p != 'Pesto.exe')
        (self.source / 'Pesto.exe').write_bytes(b'INERT - NEVER EXECUTED\nPESTO_BINDING_V1\n' + description.encode() + b'\nPESTO_BINDING_END')
        integrity.write_manifest(self.source)

    def test_prepare_refuses_linked_wad_before_creating_external_config(self):
        outside = self.base / 'outside'
        shutil.move(self.source / 'wad', outside)
        (outside / 'cfg.json').unlink()
        (self.source / 'wad').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            prepare_dev.ensure_config(self.source)
        self.assertFalse((outside / 'cfg.json').exists())

    def test_prepare_refuses_linked_template_parent(self):
        (self.source / 'wad/cfg.json').unlink()
        outside = self.base / 'external-tools'
        shutil.move(self.source / 'tools', outside)
        (self.source / 'tools').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            prepare_dev.ensure_config(self.source)
        self.assertFalse((self.source / 'wad/cfg.json').exists())

    def test_pack_config_refuses_linked_template_even_if_bytes_equal(self):
        template = self.source / prepare_dev.TEMPLATE
        outside = self.base / 'template.json'
        shutil.move(template, outside)
        template.symlink_to(outside)
        with self.assertRaises(ValueError):
            prepare_dev.check_pack_config(self.source)

    def test_failed_directory_publication_removes_only_owned_partial_output(self):
        destination = self.base / 'PROD'
        def failed_copy(source, target, **kwargs):
            Path(target).mkdir(exist_ok=True)
            (Path(target) / 'partial').write_text('incomplete')
            raise OSError('injected copy failure')
        with mock.patch.object(package.shutil, 'copytree', side_effect=failed_copy):
            with self.assertRaises(OSError):
                package.build_directory(self.source, destination, 'PROD')
        self.assertFalse(destination.exists())
        integrity.verify_runtime(self.source)

    def test_failed_zip_write_removes_incomplete_archive(self):
        root = self.base / 'PROD'
        root.mkdir()
        (root / 'first').write_text('one')
        (root / 'second').write_text('two')
        target = self.base / 'prod.zip'
        original = zipfile.ZipFile.writestr
        def fail_second(archive, info, data, **kwargs):
            if info.filename.endswith('/second'):
                raise OSError('injected archive failure')
            return original(archive, info, data, **kwargs)
        with mock.patch.object(zipfile.ZipFile, 'writestr', fail_second):
            with self.assertRaises(OSError):
                package.write_zip(root, target)
        self.assertFalse(target.exists())

    def test_zip_refuses_target_inside_payload_without_creating_it(self):
        root = self.base / 'PROD'
        root.mkdir()
        (root / 'file').write_text('payload')
        target = root / 'recursive.zip'
        with self.assertRaises(ValueError):
            package.write_zip(root, target)
        self.assertFalse(target.exists())

    def test_zip_refuses_linked_source_file(self):
        root = self.base / 'PROD'
        root.mkdir()
        outside = self.base / 'private.txt'
        outside.write_text('not payload')
        (root / 'file').symlink_to(outside)
        target = self.base / 'linked.zip'
        with self.assertRaises(ValueError):
            package.write_zip(root, target)
        self.assertFalse(target.exists())

    def test_native_header_refuses_invalid_closed_list_before_writing(self):
        p = self.source / 'wad/Pesto-Integrity.ps1'
        p.write_text("# BEGIN Pesto_RUNTIME_FILES\n@('Pesto.exe', 'wad/../outside.ps1')\n# END Pesto_RUNTIME_FILES\n")
        (self.source / 'outside.ps1').write_text('outside runtime')
        with mock.patch.object(native, 'ROOT', self.source), mock.patch.object(native, 'HERE', self.source / 'tools/launcher'):
            with self.assertRaises(ValueError):
                native.runtime_header()
        self.assertFalse((self.source / 'tools/launcher/pesto_runtime.h').exists())

    def test_native_header_refuses_linked_parent(self):
        self.paths.append('wad/nested/component.ps1')
        self.make_runtime()
        outside = self.base / 'external-runtime'
        shutil.move(self.source / 'wad/nested', outside)
        (self.source / 'wad/nested').symlink_to(outside, target_is_directory=True)
        with mock.patch.object(native, 'ROOT', self.source), mock.patch.object(native, 'HERE', self.source / 'tools/launcher'):
            with self.assertRaises(ValueError):
                native.runtime_header()
        self.assertFalse((self.source / 'tools/launcher/pesto_runtime.h').exists())

    def test_production_staging_refuses_linked_tools_before_copying(self):
        outside = self.base / 'external-tool.py'
        outside.write_text('private source outside selected tools')
        (self.source / 'tools/linked.py').symlink_to(outside)
        stage = self.base / 'stage'
        with self.assertRaises(ValueError):
            production.prepare_payload(self.source / 'wad', stage, self.source)
        self.assertFalse(stage.exists())

    def test_two_pack_generation_failure_does_not_publish_only_one_channel(self):
        output = self.base / 'packs'
        # Minimal runtime is intentionally not a complete DEV distribution.
        # The production copy would be valid, but the whole two-pack request fails.
        with self.assertRaises(ValueError):
            packs.build(self.source, output)
        self.assertFalse(output.exists())

    def make_developer_files(self):
        for relative in (*package.DEV_ROOT, *package.DEV_CONFIGS):
            target = self.source / relative
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('inert development fixture')

    def test_two_pack_success_has_both_verified_roots_and_archives(self):
        self.make_developer_files()
        output = self.base / 'packs'
        targets = package.build_archives(self.source, output)
        self.assertEqual({p.name for p in output.iterdir()}, {'DEV', 'PROD', 'Pesto_DEV.zip', 'Pesto_PROD.zip'})
        self.assertEqual({p.name for p in targets}, {'Pesto_DEV.zip', 'Pesto_PROD.zip'})
        for channel in ('DEV', 'PROD'):
            integrity.verify_runtime(output / channel)
            with zipfile.ZipFile(output / ('Pesto_' + channel + '.zip')) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual({name.split('/')[0] for name in archive.namelist()}, {channel})
        self.assertFalse(list(self.base.glob('.pesto-packs-*')))

    def test_failed_second_archive_keeps_the_requested_output_absent(self):
        self.make_developer_files()
        original = package.write_zip
        def fail_dev(root, target):
            if root.name == 'DEV':
                raise OSError('injected DEV archive failure')
            return original(root, target)
        output = self.base / 'packs'
        with mock.patch.object(package, 'write_zip', side_effect=fail_dev):
            with self.assertRaises(OSError):
                package.build_archives(self.source, output)
        self.assertFalse(output.exists())
        self.assertFalse(list(self.base.glob('.pesto-packs-*')))

    def test_concurrently_created_pack_output_is_preserved(self):
        self.make_developer_files()
        original = package.write_zip
        output = self.base / 'packs'
        def concurrent_output(root, target):
            result = original(root, target)
            if root.name == 'DEV':
                output.mkdir()
                (output / 'canary').write_text('concurrent owner')
            return result
        with mock.patch.object(package, 'write_zip', side_effect=concurrent_output):
            with self.assertRaises(FileExistsError):
                package.build_archives(self.source, output)
        self.assertEqual(list(output.iterdir()), [output / 'canary'])
        self.assertEqual((output / 'canary').read_text(), 'concurrent owner')

    def test_failed_pack_publication_cleans_only_its_owned_output(self):
        self.make_developer_files()
        output = self.base / 'packs'
        original = package.shutil.move
        moved = []
        def fail_after_one(source, target):
            if Path(target).parent == output:
                if moved:
                    raise OSError('injected final publication failure')
                moved.append(Path(target).name)
            return original(source, target)
        with mock.patch.object(package.shutil, 'move', side_effect=fail_after_one):
            with self.assertRaises(OSError):
                package.build_archives(self.source, output)
        self.assertEqual(len(moved), 1)
        self.assertFalse(output.exists())
        self.assertFalse(list(self.base.glob('.pesto-packs-*')))
        integrity.verify_runtime(self.source)

    def test_broken_output_links_are_preserved_and_never_written_through(self):
        missing = self.base / 'missing-target'
        for name in ('directory', 'archive', 'packs'):
            with self.subTest(kind=name):
                target = self.base / name
                target.symlink_to(missing)
                with self.assertRaises((ValueError, FileExistsError)):
                    if name == 'directory':
                        package.build_directory(self.source, target, 'PROD')
                    elif name == 'archive':
                        payload = self.base / 'PROD'
                        payload.mkdir()
                        package.write_zip(payload, target)
                    else:
                        package.build_archives(self.source, target)
                self.assertTrue(target.is_symlink())
                self.assertFalse(missing.exists())

    def test_broken_tools_link_refuses_staging_before_creating_output(self):
        (self.source / 'tools/broken.py').symlink_to(self.base / 'missing-tool')
        stage = self.base / 'stage'
        with self.assertRaises(ValueError):
            production.prepare_payload(self.source / 'wad', stage, self.source)
        self.assertFalse(stage.exists())

    def test_existing_broken_config_link_is_preserved_but_never_packaged(self):
        config = self.source / 'wad/cfg.json'
        config.unlink()
        config.symlink_to(self.base / 'missing-config')
        self.assertEqual(prepare_dev.ensure_config(self.source), 'present')
        with self.assertRaises(ValueError):
            prepare_dev.check_pack_config(self.source)
        self.assertTrue(config.is_symlink())
        self.assertFalse((self.base / 'missing-config').exists())

    def test_native_header_still_pins_every_valid_runtime_file(self):
        with mock.patch.object(native, 'ROOT', self.source), mock.patch.object(native, 'HERE', self.source / 'tools/launcher'):
            native.runtime_header()
        header = (self.source / 'tools/launcher/pesto_runtime.h').read_text()
        self.assertIn('#define PESTO_RUNTIME_COUNT 2', header)
        for relative in self.paths[1:]:
            self.assertIn(relative + '|' + integrity.file_hash(self.source / relative), header)

    def test_recovery_refuses_nonstrings_as_clean_validation_errors(self):
        lock = self.source / '.pesto-update.lock'
        base = {'Schema': 1, 'Stage': 'Copying', 'Destination': str(self.source), 'Id': 'a' * 32,
                'JournalSHA256': 'b' * 64, 'Backup': str(self.base / 'source-code-backup-fixture')}
        for key in ('Id', 'Backup', 'JournalSHA256'):
            for value in (None, [], {}, 42, True):
                with self.subTest(key=key, value=value):
                    data = json.dumps(dict(base, **{key: value}))
                    lock.write_text(data)
                    with self.assertRaises(ValueError):
                        update.plan_recovery(self.source)
                    self.assertEqual(lock.read_text(), data)

    def test_old_manifest_refuses_logs_and_development_paths(self):
        self.paths.extend('wad/Pesto-Extra%02d.ps1' % n for n in range(18))
        self.make_runtime()
        manifest = json.loads((self.source / 'wad/package.json').read_text())
        for relative in ('wad/private.log', 'wad/docs/private.ps1', 'wad/maintenance/cleanup.ps1', 'wad/cfg.backup'):
            with self.subTest(relative=relative):
                p = self.source / relative
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('private mutable or developer file')
                updated = dict(manifest, Files=manifest['Files'] + [{'Path': relative, 'SHA256': integrity.file_hash(p)}])
                (self.source / 'wad/package.json').write_text(json.dumps(updated))
                with self.assertRaises(ValueError):
                    update.old_components(self.source)
                self.assertEqual(p.read_text(), 'private mutable or developer file')


if __name__ == '__main__':
    unittest.main(verbosity=2)
