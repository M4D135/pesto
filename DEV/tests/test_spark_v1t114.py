"""Inventaire et mesure Add-Type (tools/Measure-PestoAddType.ps1), exécutés sous pwsh sur un wad de démonstration.

pwsh est pris dans PESTO_PWSH, PESTO_TEST_PWSH ou le PATH ; son absence fait échouer le test (jamais ignoré).
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
TOOL = DEV / 'tools' / 'Measure-PestoAddType.ps1'

TOP_LEVEL = """Add-Type -TypeDefinition @'
namespace PestoFixtureA { public static class Alpha { public static int Value() { return 1; } } }
'@
"""
POSITIONAL = """function Initialize-FixtureB {
    if (-not ('PestoFixtureB.Beta' -as [type])) {
        Add-Type @"
namespace PestoFixtureB { public static class Beta { public static int Value() { return 2; } } }
"@
    }
}
"""
OTHERS = """Add-Type -AssemblyName System.Xml
function Initialize-FixtureC {
    if (-not ('PestoFixtureC.Gamma' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Fixture.cs') -ErrorAction Stop }
}
"""
CSHARP = "namespace PestoFixtureC { public static class Gamma { public static int Value() { return 3; } } }\n"
GENERATED = "Add-Type -TypeDefinition 'namespace PestoFixtureZ { public static class Zeta { } }'\n"


def find_pwsh():
    for key in ('PESTO_PWSH', 'PESTO_TEST_PWSH'):
        value = os.environ.get(key)
        if value:
            return value
    return shutil.which('pwsh')


class TestMeasurePestoAddType(unittest.TestCase):
    def setUp(self):
        self.assertTrue(TOOL.is_file(), 'Outil introuvable : ' + str(TOOL))
        self.pwsh = find_pwsh()
        if not self.pwsh:
            self.fail('pwsh introuvable : définir PESTO_PWSH (PowerShell 7 portable) pour exécuter ce banc.')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def run_tool(self, root, report, *extra):
        return subprocess.run([self.pwsh, '-NoProfile', '-NonInteractive', '-File', str(TOOL), '-Root', str(root),
                               '-ReportPath', str(report)] + list(extra),
                              capture_output=True, text=True, encoding='utf-8', timeout=300)

    def test_fixture_wad_is_inventoried_measured_and_reported(self):
        wad = self.dir / 'fixture' / 'wad'
        wad.mkdir(parents=True)
        (wad / 'Fixture-A.ps1').write_text(TOP_LEVEL, encoding='utf-8-sig')
        (wad / 'Fixture-B.ps1').write_text(POSITIONAL, encoding='utf-8-sig')
        (wad / 'Fixture-C.ps1').write_text(OTHERS, encoding='utf-8-sig')
        (wad / 'Fixture.cs').write_text(CSHARP, encoding='utf-8')
        (wad / 'Pesto.Engine.Runtime.ps1').write_text(GENERATED, encoding='utf-8-sig')
        report = self.dir / 'addtype.json'
        result = self.run_tool(wad.parent, report, '-Iterations', '1')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        data = json.loads(report.read_text(encoding='utf-8-sig'))
        self.assertEqual(data['Verdict'], 'MEASURED_ONLY')
        sites = {(s['File'], s['Kind']): s for s in data['Sites']}
        self.assertGreater(len(data['Sites']), 1)
        self.assertNotIn('Pesto.Engine.Runtime.ps1', {s['File'] for s in data['Sites']})
        self.assertEqual(set(sites), {('Fixture-A.ps1', 'TypeDefinition'), ('Fixture-B.ps1', 'TypeDefinition'),
                                      ('Fixture-C.ps1', 'AssemblyName'), ('Fixture-C.ps1', 'Path')})
        for key in (('Fixture-A.ps1', 'TypeDefinition'), ('Fixture-B.ps1', 'TypeDefinition'), ('Fixture-C.ps1', 'Path')):
            self.assertEqual(sites[key]['Status'], 'OK', json.dumps(sites[key]))
            self.assertGreater(sites[key]['AverageCompileMs'], 0)
            self.assertEqual(len(sites[key]['SHA256']), 64)
        self.assertTrue(sites[('Fixture-A.ps1', 'TypeDefinition')]['Context'].startswith('top-level'))
        self.assertIn('Initialize-FixtureB', sites[('Fixture-B.ps1', 'TypeDefinition')]['Context'])
        self.assertTrue(sites[('Fixture-C.ps1', 'Path')]['SourcePath'].endswith('Fixture.cs'))
        self.assertEqual(sites[('Fixture-C.ps1', 'AssemblyName')]['Status'], 'NOT_MEASURED')
        self.assertEqual(data['StartupColdCompileSumMs'], sites[('Fixture-A.ps1', 'TypeDefinition')]['AverageCompileMs'])
        # Le rapport n'est jamais écrasé.
        before = report.read_bytes()
        again = self.run_tool(wad.parent, report, '-Iterations', '1')
        self.assertNotEqual(again.returncode, 0)
        self.assertEqual(report.read_bytes(), before)

    def test_real_wad_inventory_finds_named_positional_and_path_sites(self):
        report = self.dir / 'inventaire.json'
        result = self.run_tool(DEV, report, '-InventoryOnly')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        data = json.loads(report.read_text(encoding='utf-8-sig'))
        self.assertEqual(data['Verdict'], 'INVENTORY_ONLY')
        kinds = {(s['File'], s['Kind']) for s in data['Sites']}
        self.assertNotIn(('Pesto-Core.ps1', 'TypeDefinition'), kinds)
        self.assertNotIn(('Pesto-Operations.ps1', 'TypeDefinition'), kinds)
        self.assertNotIn(('Pesto-Journal.ps1', 'Path'), kinds)
        self.assertTrue((DEV / 'wad' / 'Pesto.Runtime.dll').is_file())
        self.assertNotIn('Pesto.Engine.Runtime.ps1', {s['File'] for s in data['Sites']})
        for site in data['Sites']:
            if site['Kind'] in ('TypeDefinition', 'Path'):
                self.assertEqual(site['Status'], 'NOT_MEASURED', json.dumps(site))
                self.assertEqual(len(site['SHA256']), 64, json.dumps(site))

    def test_no_undefined_iswindows_and_counts_are_arrays(self):
        content = TOOL.read_text(encoding='utf-8-sig')
        self.assertNotIn('$IsWindows', content)
        self.assertNotIn('-Exclude', content)


if __name__ == '__main__':
    unittest.main()
