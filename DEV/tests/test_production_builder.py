"""Portable preparation and distribution contracts; no Windows program runs."""
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('pesto_builder',ROOT/'tools/Build-PestoProduction.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
import update_installation as update

class ProductionBuilderTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)
    def test_preparation_uses_modified_sources_and_preserves_original(self):
        wad=self.base/'edited'
        shutil.copytree(ROOT/'wad',wad)
        file=wad/'Pesto-Contracts.ps1';file.write_bytes(file.read_bytes()+b'\n# local fixture\n')
        before={p.relative_to(wad):p.read_bytes() for p in wad.rglob('*') if p.is_file()}
        stage=self.base/'stage';required=builder.prepare_payload(wad,stage)
        self.assertEqual((stage/'wad/Pesto-Contracts.ps1').read_bytes(),file.read_bytes())
        self.assertIn('Pesto.exe',required)
        self.assertFalse((stage/'Pesto.exe').exists())
        self.assertEqual(before,{p.relative_to(wad):p.read_bytes() for p in wad.rglob('*') if p.is_file()})
    def test_existing_destination_refused_without_compilation(self):
        output=self.base/'PROD';output.mkdir();(output/'canary').write_text('keep')
        with mock.patch.object(builder,'run') as run:
            with self.assertRaises(FileExistsError):builder.build(ROOT/'wad',output)
            run.assert_not_called()
        self.assertEqual((output/'canary').read_text(),'keep')
    def test_output_inside_tools_refused_before_compilation(self):
        source=self.base/'DEV';(source/'tools').mkdir(parents=True)
        output=source/'tools'/'PROD'
        with mock.patch.object(builder,'run') as run:
            with self.assertRaisesRegex(ValueError,'hors du dossier tools'):
                builder.build(ROOT/'wad',output,source=source)
            run.assert_not_called()
        self.assertFalse(output.exists())
        self.assertEqual(list((source/'tools').iterdir()),[])
    @unittest.skipIf(os.name=='nt','link creation requires separate Windows privileges')
    def test_output_parent_alias_to_tools_refused(self):
        source=self.base/'DEV';(source/'tools').mkdir(parents=True)
        alias=self.base/'alias';alias.symlink_to(source/'tools',target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'hors du dossier tools'):
            builder.build(ROOT/'wad',alias/'PROD',source=source)
        self.assertEqual(list((source/'tools').iterdir()),[])
    def test_prepare_payload_refuses_staging_inside_tools_without_copying(self):
        source=self.base/'DEV';(source/'tools').mkdir(parents=True)
        staging=source/'tools'/'.pesto-rebuild-fixture'/'DEV'
        with mock.patch.object(builder.shutil,'copytree') as copy:
            with self.assertRaisesRegex(ValueError,'copie récursive'):
                builder.prepare_payload(ROOT/'wad',staging,source)
            copy.assert_not_called()
        self.assertFalse(staging.exists())
    @unittest.skipIf(os.name=='nt','link creation requires separate Windows privileges')
    def test_prepare_payload_resolves_staging_parent_alias(self):
        source=self.base/'DEV';(source/'tools').mkdir(parents=True)
        alias=self.base/'alias';alias.symlink_to(source/'tools',target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'copie récursive'):
            builder.prepare_payload(ROOT/'wad',alias/'temporary',source)
        self.assertEqual(list((source/'tools').iterdir()),[])
    def test_linked_wad_refused(self):
        linked=self.base/'linked';linked.symlink_to(ROOT/'wad',target_is_directory=True)
        with self.assertRaises(ValueError):builder.prepare_payload(linked,self.base/'stage')
    def test_missing_component_refused(self):
        wad=self.base/'missing';wad.mkdir();shutil.copy2(ROOT/'wad/Pesto-Integrity.ps1',wad)
        with self.assertRaises(ValueError):builder.prepare_payload(wad,self.base/'stage')
    def test_new_production_command_shipped_only_in_dev(self):
        from package_distribution import DEV_ROOT
        self.assertIn('FABRIQUER_PROD.cmd',DEV_ROOT)
        self.assertTrue((ROOT/'FABRIQUER_PROD.cmd').is_file())
    def test_only_named_guides_are_allowed_as_development_artifacts(self):
        from package_distribution import DEV_GUIDES, DEV_SUFFIXES
        self.assertEqual(len(DEV_GUIDES), 4)
        self.assertIn('docs/Pesto-1.0-Guide-technicien.pdf', DEV_GUIDES)
        self.assertNotIn('.pdf', DEV_SUFFIXES)
        self.assertNotIn('docs/private-report.pdf', DEV_GUIDES)
    @unittest.skipIf(os.name=='nt','POSIX local permissions fixture')
    def test_update_preserves_existing_access_mode(self):
        source=self.base/'source';target=self.base/'target';source.write_text('new');target.write_text('old')
        target.chmod(0o640)
        update._replace_from(source,target)
        self.assertEqual(target.read_text(),'new')
        self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o640)
    def test_windows_replace_uses_no_acl_error_override(self):
        kernel=mock.Mock();kernel.ReplaceFileW.return_value=1
        with mock.patch.object(update.ctypes,'WinDLL',return_value=kernel,create=True):
            update._replace_windows_preserving_acl('new.tmp','existing.exe')
        kernel.ReplaceFileW.assert_called_once_with('existing.exe','new.tmp',None,0,None,None)
    def test_windows_replace_failure_is_not_silently_ignored(self):
        kernel=mock.Mock();kernel.ReplaceFileW.return_value=0
        with mock.patch.object(update.ctypes,'WinDLL',return_value=kernel,create=True),mock.patch.object(update.ctypes,'get_last_error',return_value=5,create=True):
            with self.assertRaises(OSError):update._replace_windows_preserving_acl('new.tmp','existing.exe')

if __name__=='__main__':unittest.main(verbosity=2)
