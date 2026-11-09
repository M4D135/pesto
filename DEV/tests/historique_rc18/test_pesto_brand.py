"""Pesto rename invariants. Portable checks only, no Windows/AD execution."""
from pathlib import Path
import hashlib
import json
import re
import struct
import sys
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'tools'))
from ps_lexical import functions
from refresh_manifest import runtime_files, verify_runtime


def text(relative):
    return (ROOT / relative).read_text(encoding='utf-8-sig')


class PestoBrandTests(unittest.TestCase):
    def test_01_no_old_executable_or_root_ps1(self):
        self.assertTrue((ROOT / 'Pesto.exe').is_file())
        for name in ('GP.exe', 'GP.ps1', 'Pesto.ps1'):
            self.assertFalse((ROOT / name).exists(), name)

    def test_02_runtime_names_are_new(self):
        paths = runtime_files(ROOT)
        self.assertEqual(paths[0], 'Pesto.exe')
        self.assertTrue(all('GP-' not in p and 'GP.exe' not in p for p in paths))
        self.assertIn('wad/Pesto-Startup.ps1', paths)
        self.assertIn('wad/Pesto.ico', paths)
        self.assertTrue(verify_runtime(ROOT))

    def test_03_no_developer_dependency(self):
        for p in runtime_files(ROOT):
            self.assertFalse(p.endswith(('.cmd', '.bat')))
            self.assertNotIn('/maintenance/', p)
            self.assertNotIn('/docs/', p)

    def test_04_badge_and_titles_are_readable(self):
        auth = text('wad/Pesto-Authentication.ps1')
        shell = text('wad/Pesto-Shell.xaml')
        self.assertIn('Text="P" FontSize="20"', auth)
        self.assertIn('Connexion à Pesto', auth)
        self.assertIn('Text="Pesto" FontSize="16"', shell)
        self.assertNotIn('Text="GP"', shell + auth)
        self.assertNotIn('Text="Pesto" FontSize="20"', auth)
        self.assertIn('ResizeMode="NoResize"', auth)
        self.assertIn('Title="Pesto 17.0-RC18', shell)

    def test_05_all_runtime_functions_match_the_intended_rename(self):
        data = json.loads(text('tests/pesto-rename-baseline.json'))
        sources = {}
        for row in data['Functions']:
            if row['File'] not in sources:
                source = text(row['File'])
                sources[row['File']] = {n: source[a:b] for n, (a, b) in functions(source).items()}
            with self.subTest(function=row['Name']):
                actual = sources[row['File']][row['Name']]
                self.assertEqual(hashlib.sha256(actual.encode()).hexdigest(), row['ExpectedSHA256'])
        self.assertGreaterEqual(len(data['Functions']), 400)
        self.assertEqual(data['UnexpectedChanges'], [])

    def test_06_external_resources_and_configuration_are_unchanged(self):
        data = json.loads(text('tests/pesto-rename-baseline.json'))
        for item in data['PreservedAssets']:
            with self.subTest(path=item['Path']):
                self.assertEqual(hashlib.sha256((ROOT / item['Path']).read_bytes()).hexdigest(), item['SHA256'])

    def test_07_machine_mutation_lock_is_shared_with_gp(self):
        for name in ('Core', 'Direct', 'Join'):
            self.assertIn(r'Global\GP_PostMutation_v1', text('wad/Pesto-' + name + '.ps1'))
            self.assertNotIn(r'Global\Pesto_PostMutation_v1', text('wad/Pesto-' + name + '.ps1'))

    def test_08_machine_receipts_are_not_reset(self):
        self.assertIn("Combine($base,'GP','Operations','direct.json')", text('wad/Pesto-Direct.ps1'))
        self.assertIn("Combine($base,'GP','Join','receipt.json')", text('wad/Pesto-Join.ps1'))

    def test_09_original_user_preferences_remain_reachable(self):
        app = text('wad/Pesto-Appearance.ps1')
        self.assertIn(r'Software\GP\Appearance', app)
        self.assertNotIn(r'Software\Pesto\Appearance', app)
        self.assertIn("'gp.prefs.json'", text('wad/Pesto-Core.ps1'))
        self.assertIn('GP\\State\\', text('wad/Pesto-Core.ps1'))
        self.assertIn('GP\\State\\', text('wad/Pesto-Startup.ps1'))

    def test_10_launcher_and_cross_account_guards_stay_compatible(self):
        self.assertIn(r'Local\\GP_Launcher_', text('tools/launcher/Pesto-launcher.c'))
        self.assertIn(r'Global\GP_Session_', text('wad/Pesto-Startup.ps1'))

    def test_11_current_launchers_reference_existing_files(self):
        names = ('Pesto.cmd', 'Pesto_COMPTE_AD.cmd', 'DEMO.cmd', 'DEMO_DOMAINE.cmd',
                 'TESTER.cmd', 'VERIFIER_PACK.cmd', 'FABRIQUER_PACKS.cmd', 'DEBLOQUER_TOUT.cmd')
        for name in names:
            content = text(name)
            self.assertNotIn('%~dp0GP', content, name)
            self.assertNotIn('GP.exe', content, name)
            self.assertNotIn('GP-Startup.ps1', content, name)
            for path in re.findall(r'%~dp0([^"%\r\n]+)', content):
                if Path(path.replace('\\', '/')).suffix.lower() not in ('.exe', '.ps1', '.cmd'):
                    continue  # output-directory templates are not input dependencies
                with self.subTest(file=name, target=path):
                    self.assertTrue((ROOT / path.replace('\\', '/')).exists())

    def test_12_windows_build_versions_and_names_agree(self):
        build = text('tools/Build-Pesto.ps1')
        for marker in ('/ENTRY:PestoEntry', 'FILEVERSION 17,0,0,18', '17.0-RC18', 'Pesto.exe', 'DEBLOQUER_TOUT.cmd'):
            self.assertIn(marker, build)
        manifest = ET.fromstring(text('tools/launcher/Pesto.manifest'))
        identity = manifest.find('{urn:schemas-microsoft-com:asm.v1}assemblyIdentity')
        self.assertEqual(identity.get('name'), 'Pesto.Launcher')
        self.assertEqual(identity.get('version'), '17.0.0.18')

    def test_13_binary_is_compiled_not_merely_renamed(self):
        binary = (ROOT / 'Pesto.exe').read_bytes()
        pe = struct.unpack_from('<I', binary, 60)[0]
        self.assertEqual(binary[:2], b'MZ')
        self.assertEqual(binary[pe:pe+4], b'PE\0\0')
        self.assertEqual(struct.unpack_from('<H', binary, pe + 4)[0], 0x8664)
        for value in ('Pesto.exe', 'Pesto', '17.0-RC18', '17.0.0.18', '\\wad\\Pesto-Startup.ps1'):
            self.assertIn(value.encode('utf-16le'), binary)
        self.assertNotIn('GP.exe'.encode('utf-16le'), binary)
        self.assertNotIn('GP-Startup.ps1'.encode('utf-16le'), binary)

    def test_14_startup_and_tasks_use_the_new_components(self):
        for p in (ROOT / 'wad').glob('Pesto-*.ps1'):
            content = p.read_text('utf-8-sig')
            self.assertNotRegex(content, r'(?<![A-Za-z0-9])GP-[A-Za-z]+\.(?:ps1|xaml)')
            self.assertNotIn('GP.exe', content)
            for name in functions(content):
                self.assertNotIn('-GP', name)
        self.assertIn('namespace Pesto', text('wad/Pesto-Operations.ps1'))
        self.assertIn('Pesto.GestionDesPostes', text('wad/Pesto-Core.ps1'))

    def test_15_rename_does_not_change_join_or_restart_policy(self):
        baseline = json.loads(text('tests/pesto-rename-baseline.json'))
        names = {x['Name'] for x in baseline['Functions'] if x['PreservedAfterNamingChanges']}
        for name in ('AddToDomain', 'RenameComputer', 'MoveComputer', 'Get-PestoRenameMoveDecision',
                     'Invoke-PestoDsregLeaveBeforeRename', 'Invoke-PestoWindowsLocalRename'):
            self.assertIn(name, names)

    def test_16_generators_keep_explicit_prod_dev_roots(self):
        py = text('tools/package_distribution.py')
        ps = text('tools/New-PestoDistribution.ps1')
        self.assertIn('{"Pesto.exe", "DEBLOQUER_TOUT.cmd", "wad"}', py)
        self.assertIn('("PROD", "DEV")', py)
        self.assertIn("'PROD','DEV','BOTH'", ps)
        self.assertIn("'Pesto_17.0-RC18_'", ps)


if __name__ == '__main__':
    unittest.main()
