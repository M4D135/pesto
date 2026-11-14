"""Banc de course du registre partagé (tools/Measure-PestoCoordinationRace.ps1), exécuté sous pwsh.

Les participants sont de vrais processus séparés qui appellent le worker de wad/Pesto-Names.ps1 ; une copie de
Pesto-Names.ps1 volontairement cassée doit donner VIOLATION. pwsh est pris dans PESTO_PWSH, PESTO_TEST_PWSH ou le
PATH ; son absence fait échouer le test (jamais ignoré).
"""
import datetime
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
TOOL = DEV / 'tools' / 'Measure-PestoCoordinationRace.ps1'
NAMES = DEV / 'wad' / 'Pesto-Names.ps1'
LOCK_DECISION = "if(($e -and [string]$e.Owner -eq $owner) -or -not (Test-Active $e $path)){"


def find_pwsh():
    for key in ('PESTO_PWSH', 'PESTO_TEST_PWSH'):
        value = os.environ.get(key)
        if value:
            return value
    return shutil.which('pwsh')


class TestSparkH11RaceHarness(unittest.TestCase):
    def setUp(self):
        self.assertTrue(TOOL.is_file(), 'Outil introuvable : ' + str(TOOL))
        self.pwsh = find_pwsh()
        if not self.pwsh:
            self.fail('pwsh introuvable : définir PESTO_PWSH (PowerShell 7 portable) pour exécuter ce banc.')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def tool(self, *args, timeout=180):
        return subprocess.run([self.pwsh, '-NoProfile', '-NonInteractive', '-File', str(TOOL)] + [str(a) for a in args],
                              capture_output=True, text=True, encoding='utf-8', timeout=timeout)

    def analyze(self, reports):
        result = self.tool('-Analyze', '-ReportPath', reports)
        self.assertEqual(result.returncode, 0, result.stderr)
        script = self.dir / 'analyze.ps1'
        script.write_text("$r=& '%s' -Analyze -ReportPath '%s'\n$r|ConvertTo-Json -Compress\n" %
                          (str(TOOL).replace("'", "''"), str(reports).replace("'", "''")), encoding='utf-8-sig')
        result = subprocess.run([self.pwsh, '-NoProfile', '-NonInteractive', '-File', str(script)],
                                capture_output=True, text=True, encoding='utf-8', timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout.strip())

    def race(self, root, reports, operator, source=None):
        # Allow three cold PowerShell/AST imports on a shared CI runner before the first slot.
        # A missed slot remains INCOMPLETE; neither Late results nor lock violations are ignored.
        start = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=15)).strftime('%Y-%m-%dT%H:%M:%SZ')
        args = ['-Run', '-Root', root, '-Operator', operator, '-Rounds', 3, '-StartAtUtc', start, '-IntervalMs', 1500,
                '-Processes', 3, '-ReportPath', reports]
        if source:
            args += ['-SourcePath', source]
        return self.tool(*args)

    def test_prepare_accepts_root_and_creates_marker_and_registry(self):
        root = self.dir / 'course'
        result = self.tool('-Prepare', '-Root', root)
        self.assertEqual(result.returncode, 0, result.stderr)
        marker = json.loads((root / 'race-harness.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(marker['Purpose'], 'PestoRaceHarness')
        registry = json.loads((root / 'pesto-coordination.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(registry['Domain'], 'race-harness.invalid')
        self.assertTrue((root / 'reservations').is_dir())

    def test_prepare_refuses_non_empty(self):
        root = self.dir / 'occupe'
        root.mkdir()
        (root / 'dummy.txt').write_text('x', encoding='utf-8')
        result = self.tool('-Prepare', '-Root', root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('vide', result.stderr.lower())
        self.assertEqual(sorted(p.name for p in root.iterdir()), ['dummy.txt'])

    def test_run_requires_marker(self):
        start = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=1)).strftime('%Y-%m-%dT%H:%M:%SZ')
        result = self.tool('-Run', '-Root', self.dir, '-Operator', 'TEST', '-Rounds', 1, '-StartAtUtc', start,
                           '-IntervalMs', 500, '-Processes', 1, '-ReportPath', self.dir / 'rapports')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('marqueur', result.stderr.lower())

    def test_run_refuses_a_production_registry(self):
        root = self.dir / 'prod'
        self.assertEqual(self.tool('-Prepare', '-Root', root).returncode, 0)
        (root / 'pesto-coordination.json').write_text(
            '{"Schema":1,"Domain":"labo.local","Purpose":"PestoCoordination"}', encoding='utf-8')
        result = self.race(root, self.dir / 'rapports', 'A')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('production', result.stderr.lower())

    def test_real_processes_one_owner_per_round_with_pesto_worker(self):
        root, reports = self.dir / 'course', self.dir / 'rapports'
        self.assertEqual(self.tool('-Prepare', '-Root', root).returncode, 0)
        result = self.race(root, reports, 'A')
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((reports / 'report_A.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(report['SourcePath'], str(NAMES.resolve()))
        self.assertEqual(len(report['Results']), 9)
        # Le nom disputé est le même pour tous les participants : RACEnnnn, sans suffixe d'opérateur.
        self.assertEqual(sorted({r['Name'] for r in report['Results']}), ['RACE0001', 'RACE0002', 'RACE0003'])
        self.assertEqual(len({r['Owner'] for r in report['Results']}), 3)
        verdict = self.analyze(reports)
        self.assertEqual(verdict['Verdict'], 'ONE_OWNER_PER_ROUND', json.dumps(report['Results']))
        self.assertEqual(verdict['TotalRounds'], 3)
        # A late peer must still see these leases after the first workers have exited.
        # Releasing here used to let a slower machine reacquire the last names.
        leases = sorted((root / 'reservations').glob('*.json'))
        self.assertEqual(len(leases), 3)
        original = {p.name: p.read_bytes() for p in leases}
        late = self.race(root, reports, 'LATE')
        self.assertEqual(late.returncode, 0, late.stderr)
        delayed = json.loads((reports / 'report_LATE.json').read_text(encoding='utf-8-sig'))
        self.assertTrue(all(r['Outcome'] == 'Other' for r in delayed['Results']))
        self.assertEqual({p.name: p.read_bytes() for p in leases}, original)
        self.assertEqual(self.analyze(reports)['Verdict'], 'ONE_OWNER_PER_ROUND')

    def test_regression_in_pesto_locking_gives_violation(self):
        source = NAMES.read_text(encoding='utf-8-sig')
        self.assertEqual(source.count(LOCK_DECISION), 1, 'Décision de reprise introuvable dans Pesto-Names.ps1')
        broken = self.dir / 'Pesto-Names.ps1'
        broken.write_text(source.replace(LOCK_DECISION, 'if($true){'), encoding='utf-8-sig')
        root, reports = self.dir / 'course', self.dir / 'rapports'
        self.assertEqual(self.tool('-Prepare', '-Root', root).returncode, 0)
        result = self.race(root, reports, 'B', broken)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.analyze(reports)['Verdict'], 'VIOLATION')

    def test_analyze_verdict(self):
        reports = self.dir / 'reports'
        reports.mkdir()

        def report(operator, results):
            doc = {'Schema': 1, 'Operator': operator, 'Processes': 1, 'Rounds': 2, 'Results': results}
            (reports / ('report_%s.json' % operator)).write_text(json.dumps(doc), encoding='utf-8')

        def rec(rnd, operator, outcome, verified=None):
            return {'Round': rnd, 'Operator': operator, 'Process': 1, 'Owner': operator + '-1', 'Name': 'RACE%04d' % rnd,
                    'Outcome': outcome, 'OwnerVerified': verified}

        report('A', [rec(1, 'A', 'Owner', True), rec(2, 'A', 'Other')])
        report('B', [rec(1, 'B', 'Other'), rec(2, 'B', 'Owner', True)])
        verdict = self.analyze(reports)
        self.assertEqual(verdict['Verdict'], 'ONE_OWNER_PER_ROUND')
        self.assertEqual(verdict['TotalRounds'], 2)
        # Deux propriétaires sur un même tour : violation.
        report('C', [rec(1, 'C', 'Owner', True), rec(2, 'C', 'Other')])
        self.assertEqual(self.analyze(reports)['Verdict'], 'VIOLATION')
        (reports / 'report_C.json').unlink()
        # Réservation écrasée après coup (relecture du propriétaire fausse) : violation.
        report('B', [rec(1, 'B', 'Other'), rec(2, 'B', 'Owner', False)])
        self.assertEqual(self.analyze(reports)['Verdict'], 'VIOLATION')
        # Erreur ou créneau manqué : jamais un succès.
        report('B', [rec(1, 'B', 'Late'), rec(2, 'B', 'Owner', True)])
        self.assertEqual(self.analyze(reports)['Verdict'], 'INCOMPLETE')


if __name__ == '__main__':
    unittest.main()
