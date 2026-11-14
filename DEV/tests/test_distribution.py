"""Portable tests of packaging data and the independent Python checker.
These are NOT executions of the PowerShell/Windows startup path.
"""
from pathlib import Path
import json
import shutil
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from refresh_manifest import runtime_files, verify_runtime, write_manifest
from package_distribution import build_directory, distribution_files, write_zip
from package_distribution import DEV_ROOT, DEV_CONFIGS, DEV_SUFFIXES, DEV_EXCLUDED_DIRS, DEV_TREES


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pesto-pack-test-')
        self.base = Path(self.temp.name)
        self.root = self.base / 'source'
        self.root.mkdir()
        self.paths = runtime_files(ROOT)
        for rel in (*self.paths, 'wad/package.json'):
            dest = self.root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, dest)

    def tearDown(self):
        self.temp.cleanup()

    def test_01_runtime_only_needs_no_demo_or_helpers(self):
        m = verify_runtime(self.root)
        self.assertEqual(len(m['Files']), len(self.paths))
        self.assertFalse(any(self.root.glob('*.cmd')))
        self.assertFalse((self.root / 'wad/cfg.demo.json').exists())
        self.assertFalse((self.root / 'wad/maintenance').exists())

    def test_02_optional_changes_do_not_modify_runtime_verification(self):
        optional = ['DEMO.cmd','DEMO_DOMAINE.cmd','TESTER.cmd','VERIFIER_PACK.cmd',
                    'Pesto.cmd','Pesto_COMPTE_AD.cmd','wad/support/DEBLOQUER_TOUT.cmd','LIRE_MOI.txt','README.md',
                    'wad/cfg.json','wad/cfg.demo.json','wad/maintenance/Test-Pesto16.ps1',
                    'tools/build.py','tests/notes.txt','wad/logs/Pesto.log','wad/gp.prefs.json']
        before = (self.root / 'wad/package.json').read_bytes()
        for rel in optional:
            with self.subTest(file=rel):
                p = self.root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('Test data, not code to execute')
                verify_runtime(self.root)
                p.write_text('Changed optional file')
                verify_runtime(self.root)
                p.unlink()
                verify_runtime(self.root)
        self.assertEqual(before, (self.root / 'wad/package.json').read_bytes())

    def test_03_each_missing_runtime_file_is_refused(self):
        for rel in self.paths:
            with self.subTest(file=rel):
                p = self.root / rel
                contents = p.read_bytes()
                p.unlink()
                try:
                    with self.assertRaises((ValueError, OSError)):
                        verify_runtime(self.root)
                finally:
                    p.write_bytes(contents)

    def test_04_each_modified_runtime_file_is_refused(self):
        for rel in self.paths:
            with self.subTest(file=rel):
                p = self.root / rel
                contents = p.read_bytes()
                p.write_bytes(contents + b'\nTAMPERED')
                try:
                    with self.assertRaises(ValueError):
                        verify_runtime(self.root)
                finally:
                    p.write_bytes(contents)

    def test_05_invalid_manifest_is_refused(self):
        path = self.root / 'wad/package.json'
        original = path.read_text()
        for label in ['scope','version','schema','omission','duplicate','demo','traversal','invalidhash','missing','broken','oversized']:
            with self.subTest(case=label):
                m = json.loads(original)
                if label == 'scope': m['Scope'] = 'Development'
                elif label == 'version': m['Version'] = '17.0-RC15'
                elif label == 'schema': m['Schema'] = 1
                elif label == 'omission': m['Files'].pop()
                elif label == 'duplicate': m['Files'][1]['Path'] = m['Files'][0]['Path']
                elif label == 'demo': m['Files'][0]['Path'] = 'DEMO.cmd'
                elif label == 'traversal': m['Files'][0]['Path'] = '../outside.exe'
                elif label == 'invalidhash': m['Files'][0]['SHA256'] = 'bogus'
                path.write_text(json.dumps(m))
                if label == 'missing': path.unlink()
                elif label == 'broken': path.write_text('{badJSON')
                elif label == 'oversized': path.write_text(' ' * 262145)
                try:
                    with self.assertRaises((ValueError, OSError)):
                        verify_runtime(self.root)
                finally:
                    path.write_text(original)

    def test_06_linked_runtime_file_is_refused(self):
        rel = 'wad/Pesto-Operations.ps1'
        p = self.root / rel
        contents = p.read_bytes()
        outside = self.base / 'linked-file.ps1'
        outside.write_bytes(contents)
        p.unlink()
        p.symlink_to(outside)
        with self.assertRaises(ValueError): verify_runtime(self.root)

    def test_07_linked_manifest_directory_is_refused(self):
        shutil.move(self.root / 'wad', self.base / 'linked-wad')
        (self.root / 'wad').symlink_to(self.base / 'linked-wad', target_is_directory=True)
        with self.assertRaises(ValueError): verify_runtime(self.root)

    def test_08_generator_succeeds_without_dev_files(self):
        before = (self.root / 'wad/package.json').read_bytes()
        write_manifest(self.root)
        self.assertEqual(before, (self.root / 'wad/package.json').read_bytes())
        verify_runtime(self.root)

    def test_09_prod_export_is_closed_and_preserves_configuration(self):
        expected = set(self.paths) | {'wad/package.json','wad/cfg.json','wad/support/DEBLOQUER_TOUT.cmd'}
        self.assertEqual(set(distribution_files(ROOT,'PROD')), expected)
        dest = build_directory(ROOT, self.base / 'PROD', 'PROD')
        verify_runtime(dest)
        self.assertEqual({p.name for p in dest.iterdir()}, {'Pesto.exe', 'wad'})
        self.assertEqual({p.relative_to(dest).as_posix() for p in dest.rglob('*') if p.is_file()}, expected)
        self.assertEqual((ROOT/'wad/cfg.json').read_bytes(), (dest/'wad/cfg.json').read_bytes())
        archive = self.base/'PROD.zip'
        write_zip(dest, archive)
        with zipfile.ZipFile(archive) as z:
            self.assertIsNone(z.testzip())
            self.assertEqual(set(z.namelist()), {'PROD/'+r for r in expected})

    def test_10_dev_and_prod_share_the_same_runtime(self):
        dev = build_directory(ROOT, self.base/'DEV','DEV')
        prod = build_directory(ROOT,self.base/'PROD','PROD')
        for rel in (*self.paths,'wad/package.json'):
            self.assertEqual((dev/rel).read_bytes(), (prod/rel).read_bytes(), rel)
        for rel in ('.gitattributes','pytest.ini','DEMO.cmd','TESTER.cmd','tools/launcher/Pesto-launcher.c','wad/cfg.demo.json','tests/test_distribution.py'):
            self.assertTrue((dev/rel).is_file(), rel)
            self.assertFalse((prod/rel).exists(), rel)
        self.assertEqual((dev/'.gitattributes').read_bytes(), (ROOT/'.gitattributes').read_bytes())
        self.assertFalse((dev/'tests/historique_rc18').exists())

    def test_11_existing_destination_is_never_overwritten(self):
        dest = self.base/'EXISTING'
        dest.mkdir()
        canary = dest/'keep.txt';canary.write_text('KEEP')
        with self.assertRaises(ValueError): build_directory(ROOT,dest,'PROD')
        self.assertEqual(canary.read_text(),'KEEP')

    def test_12_unknown_and_state_files_not_exported(self):
        for rel in ['wad/cfg.json','wad/support/DEBLOQUER_TOUT.cmd']:
            target = self.root/rel;target.parent.mkdir(exist_ok=True,parents=True);shutil.copy2(ROOT/rel,target)
        for rel in ['PRIVATE.log','wad/logs/session.log','wad/gp.prefs.json','wad/cfg.original.json','wad/receipt.json','tools/SECRET.txt','DEMO.cmd']:
            target = self.root/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_text('PRIVATE-CANARY')
        dest = build_directory(self.root,self.base/'PROD','PROD')
        for path in dest.rglob('*'):
            if path.is_file(): self.assertNotIn(b'PRIVATE-CANARY',path.read_bytes(),str(path))

    def test_13_manifest_ignores_new_optional_components_on_regeneration(self):
        for rel in ['wad/maintenance/Pesto-Test.ps1','wad/Pesto-UnloadedHelper.ps1','TESTER.cmd','DEMO.cmd']:
            target=self.root/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_text('OPTIONAL')
        m=write_manifest(self.root)
        self.assertEqual({e['Path'] for e in m['Files']},set(self.paths))

    def test_14_partial_runtime_refuses_export(self):
        p=self.root/'wad/Pesto-Join.xaml';p.unlink()
        with self.assertRaises(ValueError): build_directory(self.root,self.base/'PROD','PROD')
        self.assertFalse((self.base/'PROD').exists())

    def test_15_old_root_script_is_not_required_or_exported(self):
        p=self.root/'Pesto.ps1'
        p.write_text('LEGACY-ROOT-CANARY')
        verify_runtime(self.root)
        (self.root/'wad/cfg.json').write_bytes((ROOT/'wad/cfg.json').read_bytes())
        (self.root/'wad/support').mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/'wad/support/DEBLOQUER_TOUT.cmd', self.root/'wad/support/DEBLOQUER_TOUT.cmd')
        dest=build_directory(self.root,self.base/'PROD','PROD')
        self.assertEqual({p.name for p in dest.iterdir()},{'Pesto.exe','wad'})
        self.assertFalse((dest/'Pesto.ps1').exists())
        p.unlink()
        verify_runtime(self.root)

    def test_16_no_production_script_launches_a_root_pesto_ps1(self):
        for rel in self.paths:
            if rel.endswith('.ps1'):
                self.assertNotIn("'Pesto.ps1'", (ROOT/rel).read_text('utf-8-sig'), rel)

    def test_17_unblock_is_required_for_shipping_not_for_runtime(self):
        (self.root/'wad/cfg.json').write_bytes((ROOT/'wad/cfg.json').read_bytes())
        verify_runtime(self.root)
        with self.assertRaises((ValueError, OSError)):
            build_directory(self.root,self.base/'PROD','PROD')
        self.assertFalse((self.base/'PROD').exists())
        (self.root/'wad/support').mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/'wad/support/DEBLOQUER_TOUT.cmd',self.root/'wad/support/DEBLOQUER_TOUT.cmd')
        dest=build_directory(self.root,self.base/'PROD','PROD')
        self.assertEqual({p.name for p in dest.iterdir()},{'Pesto.exe','wad'})
        (dest/'wad/support/DEBLOQUER_TOUT.cmd').unlink()
        verify_runtime(dest)

    def test_18_archives_have_distinct_named_roots(self):
        for channel in ('PROD','DEV'):
            with self.subTest(channel=channel):
                dest=build_directory(ROOT,self.base/channel,channel)
                archive=self.base/(channel+'.zip')
                write_zip(dest,archive)
                with zipfile.ZipFile(archive) as z:
                    self.assertIsNone(z.testzip())
                    self.assertEqual({n.split('/')[0] for n in z.namelist()},{channel})
                    self.assertIn(channel+'/wad/support/DEBLOQUER_TOUT.cmd',z.namelist())
                    self.assertNotIn(channel+'/Pesto.ps1',z.namelist())

    def test_19_unblock_recognizes_exe_wad_without_root_ps1(self):
        text=(ROOT/'wad/support/DEBLOQUER_TOUT.cmd').read_text('utf-8-sig')
        self.assertIn("@('Pesto.exe','wad\\Pesto-Startup.ps1','wad\\Pesto-Core.ps1')",text)
        self.assertNotIn("'Pesto.ps1'",text)
        self.assertIn("$root.FullName,'wad\\logs'",text)
        self.assertIn('DisableDelayedExpansion',text)
        self.assertIn('ReparsePoint',text)
        self.assertIn('Read-Host',text);self.assertIn('$support.Parent.Parent',text)
        self.assertNotIn('Set-ExecutionPolicy',text)
        # Les quatre lectures ADS (racine et descendants, avant/après) incluent les fichiers Hidden.
        self.assertEqual(text.count("Get-Item -LiteralPath $item.FullName -Stream '*' -Force -ErrorAction Stop"),4)
        self.assertNotIn("-Stream '*' -ErrorAction Stop",text)

    def test_20_wrong_zip_root_name_is_refused(self):
        dest=build_directory(ROOT,self.base/'Pesto','PROD')
        archive=self.base/'bad-name.zip'
        with self.assertRaises(ValueError):
            write_zip(dest,archive)
        self.assertFalse(archive.exists())


    def test_21_real_configuration_never_packed_by_default(self):
        src=self.base/'src';shutil.copytree(ROOT,src,ignore=shutil.ignore_patterns('__pycache__','.git'))
        (src/'wad/cfg.json').write_text('{"Configured":true,"Domain":"interne.example"}',encoding='utf-8')
        with self.assertRaises(ValueError): build_directory(src,self.base/'PROD','PROD')
        self.assertFalse((self.base/'PROD').exists())
        dest=build_directory(src,self.base/'PROD2','PROD',allow_config=True)
        self.assertIn('interne.example',(dest/'wad/cfg.json').read_text(encoding='utf-8'))

    def test_22_static_reports_never_in_dev_pack(self):
        src=self.base/'src';shutil.copytree(ROOT,src,ignore=shutil.ignore_patterns('__pycache__','.git'))
        (src/'tests/static-report.json').write_text('{"Domains":["interne.example"]}',encoding='utf-8')
        (src/'tests/rc9-static-report.json').write_text('{}',encoding='utf-8')
        files=distribution_files(src,'DEV')
        self.assertFalse([f for f in files if 'static-report' in f])

    def test_23_unblock_filter_covers_pack_contract_not_live_folder(self):
        # Le contrat du pack fait foi, pas le dossier réel : un check.json posé par l'opérateur n'est pas du pack.
        import re
        text=(ROOT/'wad/support/DEBLOQUER_TOUT.cmd').read_text('utf-8-sig')
        line=[l for l in text.splitlines() if re.match(r'^\s*\$isPestoEntry=',l)]
        self.assertEqual(1,len(line))
        folders,names=[{n.lower() for n in re.findall(r"'([^']+)'",m)} for m in re.findall(r"-in @\(([^)]*)\)",line[0])]
        pattern=re.compile(re.search(r"-match '([^']+)'",line[0]).group(1),re.IGNORECASE)
        def accepted(name,folder):
            return name.lower() in folders if folder else (name.lower() in names or bool(pattern.match(name)))
        for channel in ('PROD','DEV'):
            for rel in distribution_files(ROOT,channel):
                top=rel.split('/')[0]
                self.assertTrue(accepted(top,'/' in rel),channel+' : '+top)
        for name,folder in (('check.json',False),('facture.pdf',False),('setup.exe',False),('install.cmd',False),('autre.ps1',False),('Documents',True),('integrations-backup',True),('integrations.ps1',False)):
            self.assertFalse(accepted(name,folder),name)

    def test_24_powershell_distribution_keeps_the_same_dev_contract(self):
        import re
        text=(ROOT/'tools/New-PestoDistribution.ps1').read_text('utf-8-sig')
        roots=re.search(r"foreach\(\$rel in @\(([^()\n]+)\)\)\{\[void\]\$files.Add",text)
        self.assertIsNotNone(roots)
        self.assertEqual(set(re.findall(r"'([^']*)'", roots[1])),set(DEV_ROOT)|set(DEV_CONFIGS))
        suffixes=re.search(r"\$item.Extension -in @\(([^)]*)\)",text)
        self.assertEqual(set(re.findall(r"'([^']*)'",suffixes[1])),DEV_SUFFIXES)
        trees=re.search(r"foreach\(\$folder in @\(([^)]*)\)\)",text)
        self.assertIsNotNone(trees)
        self.assertEqual(set(re.findall(r"'([^']*)'",trees[1])),set(DEV_TREES))
        self.assertIn("if(Test-Path -LiteralPath (Join-Path $SourceRoot 'wad/Pesto.Engine.exports.json') -PathType Leaf){[void]$files.Add('wad/Pesto.Engine.exports.json')}",text)
        for excluded in DEV_EXCLUDED_DIRS:
            self.assertIn(excluded,text)
        self.assertIn("if(-not $SourceRoot){$SourceRoot=Split-Path -Parent $PSScriptRoot}",text)
        self.assertIn('Lien ou jonction interdit dans le chemin de sortie.',text)

    def test_25_output_alias_cannot_write_inside_source(self):
        source=build_directory(ROOT,self.base/'source-prod','PROD')
        alias=self.base/'output-alias'
        alias.symlink_to(source,target_is_directory=True)
        with self.assertRaisesRegex(ValueError,'outside the source'):
            build_directory(source,alias/'generated','PROD')
        self.assertFalse((source/'generated').exists())

    def test_26_pack_entrypoint_rejects_alias_before_creating_config(self):
        import runpy
        builder=runpy.run_path(str(ROOT/'tools/Build-PestoPacks.py'))
        alias=self.base/'output-alias'
        alias.symlink_to(self.root,target_is_directory=True)
        self.assertFalse((self.root/'wad/cfg.json').exists())
        with self.assertRaisesRegex(ValueError,'outside the source'):
            builder['build'](self.root,alias/'packs')
        self.assertFalse((self.root/'wad/cfg.json').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
