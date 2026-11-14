"""Banc WPF de projection (tools/Measure-PestoWpfProjection.ps1).

La mesure WPF elle-même ne tourne que sous Windows PowerShell 5.1 en STA (tests/Run-WpfProjectionBenchTests.ps1,
listé dans Run-AllTests.ps1). Ici : contrôles statiques et fonctions pures exécutées sous pwsh (PESTO_PWSH,
PESTO_TEST_PWSH ou PATH ; son absence fait échouer le test).
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
TOOLS = DEV / 'tools'
COMMON = TOOLS / 'PestoWpfBench.Common.ps1'
MAIN = TOOLS / 'Measure-PestoWpfProjection.ps1'
SMOKE = DEV / 'tests' / 'Run-WpfProjectionBenchTests.ps1'


def find_pwsh():
    for key in ('PESTO_PWSH', 'PESTO_TEST_PWSH'):
        value = os.environ.get(key)
        if value:
            return value
    return shutil.which('pwsh')


def read(path):
    if not path.is_file():
        raise AssertionError('Fichier introuvable : ' + str(path))
    return path.read_text(encoding='utf-8-sig')


class TestPestoWpfBench(unittest.TestCase):
    def test_common_helpers_exist(self):
        content = read(COMMON)
        self.assertIn('function New-PestoBenchData', content)
        self.assertIn('function Get-PestoBenchChanges', content)
        self.assertIn('function Get-PestoBenchStats', content)
        self.assertIn('function Get-PestoBenchGridHelperDefinitions', content)
        self.assertIn('function New-PestoBenchObservableRow', content)
        self.assertIn('function New-PestoBenchObservableRows', content)

    def test_layout_counter_is_a_clr_event_with_shared_counter(self):
        content = read(MAIN)
        # DataGrid n'a pas de LayoutUpdatedEvent routé ; un $c++ dans un [EventHandler] modifie une copie locale.
        self.assertNotIn('LayoutUpdatedEvent', content)
        self.assertIn('$grid.add_LayoutUpdated($handler)', content)
        self.assertIn('$grid.remove_LayoutUpdated($handler)', content)
        self.assertIn('$count = [ref]0', content)
        self.assertIn('$count.Value++ }.GetNewClosure()', content)
        self.assertIn('LayoutPasses = $count.Value', content)

    def test_strategy_is_an_explicit_parameter(self):
        content = read(MAIN)
        body = re.search(r'function Invoke-BenchCell \{(.*?)\n\}\n', content.replace('\r\n', '\n'), re.S)
        self.assertIsNotNone(body)
        self.assertRegex(body.group(1), r"\[ValidateSet\('FullRebind', 'InPlace', 'ObservableInPlace'\)\]\[string\]\$Strategy")
        self.assertIn('Invoke-BenchCell -Strategy $strategy', content)
        self.assertNotIn('Run-BenchCell', content)

    def test_observable_strategy_measures_the_delivered_helper(self):
        # Le point 61 est une evaluation du chemin reellement livre : le banc doit exercer
        # Update-PestoGridRows tel qu'il est dans wad/, jamais une copie reecrite ici.
        main = read(MAIN)
        common = read(COMMON)
        self.assertNotIn('function Update-PestoGridRows', main)
        self.assertNotIn('function Get-PestoStableHash', main)
        self.assertNotIn('function New-PestoGridRowCollection', main)
        self.assertIn('Get-PestoBenchGridHelperDefinitions -Root (Split-Path $PSScriptRoot -Parent)', main)
        self.assertIn('. ([ScriptBlock]::Create($deliveredDefinition))', main)
        self.assertIn("[void](Update-PestoGridRows -Grid $grid -Rows $rows -IdProperty 'RowId')", main)
        for needle in ('add_CollectionChanged', 'remove_CollectionChanged', 'SortKept', 'SelectionKept',
                       'Notifications = $notifications.Value'):
            self.assertIn(needle, main, needle + ' : la strategie livree ne releve plus ce qu\'elle doit mesurer')
        # Le produit tourne en Set-StrictMode -Off (wad/Invoke-Pesto.ps1) : le helper livre doit etre exerce
        # dans le meme etat, la propriete facultative PestoRowFingerprints en depend.
        self.assertIn('Set-StrictMode -Off', main)
        self.assertIn('Set-StrictMode -Version Latest', main)
        extraction = common[common.index('function Get-PestoBenchGridHelperDefinitions'):]
        for source in ("'Pesto-Collections.ps1'", "'Pesto-Contracts.ps1'"):
            self.assertIn(source, extraction, source + ' n\'est plus relu dans les sources livrées')
        for helper in ('Get-PestoGridRowId', 'New-PestoGridRowCollection', 'Update-PestoGridRows',
                       'Get-PestoStableHash'):
            self.assertIn("'" + helper + "'", extraction, helper + ' n\'est plus chargé depuis la source livrée')
        self.assertIn('FunctionDefinitionAst', extraction)
        self.assertIn('Extent.Text', extraction)

    def test_smoke_suite_asserts_the_delivered_contract(self):
        smoke = read(SMOKE)
        self.assertIn("'FullRebind,InPlace,ObservableInPlace'", smoke)
        self.assertIn('Notifications', smoke)
        self.assertIn('SortKept', smoke)
        self.assertIn('SelectionKept', smoke)

    def test_windows_smoke_suite_is_wired(self):
        smoke = read(SMOKE)
        self.assertIn("-STA", read(DEV / 'tests' / 'Run-AllTests.ps1'))
        self.assertIn("'Run-WpfProjectionBenchTests.ps1'", read(DEV / 'tests' / 'Run-AllTests.ps1'))
        self.assertIn('& $tool -Smoke', smoke)
        self.assertIn('LayoutPasses', smoke)
        content = read(MAIN)
        self.assertIn('[switch]$Smoke', content)
        self.assertIn('MEASURED_ONLY', content)

    def test_pure_helpers_under_pwsh(self):
        pwsh = find_pwsh()
        if not pwsh:
            self.fail('pwsh introuvable : définir PESTO_PWSH (PowerShell 7 portable) pour exécuter ce banc.')
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'helpers.ps1'
            script.write_text("""
$ErrorActionPreference='Stop'
. '%s'
$table=New-PestoBenchData -RowCount 100 -Seed 42
$again=New-PestoBenchData -RowCount 100 -Seed 42
$rows=New-PestoBenchObservableRows -Table $table
$againRows=New-PestoBenchObservableRows -Table $table
$helpers=@(Get-PestoBenchGridHelperDefinitions -Root '%s')
$changes=@(Get-PestoBenchChanges -TotalRows 100 -ChangeCount 10 -Seed 7)
$clamped=@(Get-PestoBenchChanges -TotalRows 5 -ChangeCount 50 -Seed 7)
$one=@(Get-PestoBenchChanges -TotalRows 100 -ChangeCount 1 -Seed 7)
$empty=Get-PestoBenchStats -Samples @()
$single=Get-PestoBenchStats -Samples @(4.5)
$many=Get-PestoBenchStats -Samples @(5,1,4,2,3)
[pscustomobject]@{Rows=$table.Rows.Count;SameFirst=($table.Rows[0]['Site'] -eq $again.Rows[0]['Site']);
  ObservableRows=$rows.Count;FirstId=[string]$rows[0].RowId;Stable=($rows[0].RowId -ceq $againRows[0].RowId);
  Helpers=$helpers.Count;Delivered=@($helpers|Where-Object{$_ -match 'function Update-PestoGridRows'}).Count;
  Changes=$changes.Count;Distinct=@($changes|Select-Object -Unique).Count;Clamped=$clamped.Count;One=$one.Count;
  EmptyCount=$empty.Count;SingleMedian=$single.Median;Median=$many.Median;P95=$many.P95}|ConvertTo-Json -Compress
""" % (str(COMMON).replace("'", "''"), str(DEV).replace("'", "''")), encoding='utf-8-sig')
            result = subprocess.run([pwsh, '-NoProfile', '-NonInteractive', '-File', str(script)],
                                    capture_output=True, text=True, encoding='utf-8', timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout.strip())
        self.assertEqual(data['Rows'], 100)
        self.assertTrue(data['SameFirst'])
        self.assertEqual(data['ObservableRows'], 100)
        self.assertEqual(data['FirstId'], 'PC-00000')
        self.assertTrue(data['Stable'])
        # Les quatre helpers du chemin livre (identite, collection, mise a jour, empreinte) doivent sortir
        # des sources du moteur : c'est la seule facon pour le banc de mesurer ce qui est vraiment livre.
        self.assertEqual((data['Helpers'], data['Delivered']), (4, 1))
        self.assertEqual((data['Changes'], data['Distinct']), (10, 10))
        self.assertEqual(data['Clamped'], 5)
        self.assertEqual(data['One'], 1)
        self.assertEqual(data['EmptyCount'], 0)
        self.assertEqual(data['SingleMedian'], 4.5)
        self.assertEqual((data['Median'], data['P95']), (3, 5))

    def test_refuses_outside_windows_powershell(self):
        pwsh = find_pwsh()
        if not pwsh:
            self.fail('pwsh introuvable : définir PESTO_PWSH (PowerShell 7 portable) pour exécuter ce banc.')
        result = subprocess.run([pwsh, '-NoProfile', '-NonInteractive', '-File', str(MAIN), '-Smoke'],
                                capture_output=True, text=True, encoding='utf-8', timeout=120)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Windows PowerShell 5.1', result.stderr)

    def test_no_modern_syntax(self):
        for path in (COMMON, MAIN, SMOKE):
            content = read(path)
            self.assertNotRegex(content, r'\?\?|\?\.|&&|\|\|', path.name)


if __name__ == '__main__':
    unittest.main()
