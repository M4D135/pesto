"""Lanceurs de tests : Run-AllTests.ps1 (Windows, recette) et tools/run_tests.py (Mac), même liste de suites."""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
TESTS = DEV / 'tests'
RUNNER = DEV / 'tools' / 'run_tests.py'
RUN_ALL = TESTS / 'Run-AllTests.ps1'

FAKE_PWSH = """#!%s
import sys
path = sys.argv[sys.argv.index('-File') + 1]
with open(path, encoding='utf-8-sig') as f:
    sys.exit(0 if 'MARQUEUR-PASS' in f.read() else 3)
"""


def read_run_all():
    text = RUN_ALL.read_text(encoding='utf-8-sig').replace('\r\n', '\n')
    suites = re.findall(r"'(Run-[A-Za-z0-9]+\.ps1)'", re.search(r"\$suites=@\((.*?)\)\n", text, re.S).group(1))
    separate = dict(re.findall(r"'(Run-[A-Za-z0-9]+\.ps1)'='([^']*)'", text))
    return text, suites, separate


class TestSuiteLists(unittest.TestCase):
    def setUp(self):
        with open(TESTS / 'suites.json', 'r', encoding='utf-8-sig') as f:
            self.suites = json.load(f)

    def test_suites_json_valid(self):
        self.assertIsInstance(self.suites, list)
        for suite in self.suites:
            for key in ('name', 'file', 'platform', 'profile'):
                self.assertIn(key, suite)
            self.assertIn(suite['platform'], ['Portable', 'Windows51', 'Wpf'])
            self.assertIn(suite['profile'], ['Rapide', 'Complet'])
            self.assertTrue((TESTS / suite['file']).is_file(), suite['file'])
        self.assertEqual(len({s['file'] for s in self.suites}), len(self.suites))

    def test_run_all_tests_runs_every_listed_suite_under_sta(self):
        text, suites, separate = read_run_all()
        # Suites métier, fumée WPF et acquittement ; aucune plateforme ignorée, toutes en -STA.
        self.assertEqual(len(suites), sum(not s.get('separate') for s in self.suites))
        self.assertIn('Run-AcknowledgementTests.ps1', suites)
        for name in ('RemotePreparation', 'HeadlessAudit', 'ReconciliationAudit'):
            self.assertIn(f'Run-{name}Tests.ps1', suites)
        self.assertIn('Run-UiPresentationTests.ps1', suites)
        self.assertIn('Run-JoinReservationTests.ps1', suites)
        self.assertIn('Run-WorkerContractTests.ps1', suites)
        self.assertIn("-NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot $suite)", text)
        self.assertNotIn("'Wpf'", text)
        self.assertNotRegex(text, r'(?i)\$Profile\b')
        self.assertIn("throw ('Suites absentes de Run-AllTests.ps1 : '", text)
        # suites.json décrit exactement les mêmes suites, et marque les lancements séparés.
        self.assertEqual([s['file'] for s in self.suites if not s.get('separate')], suites)
        self.assertEqual({s['file'] for s in self.suites if s.get('separate')}, set(separate) - {'Run-AllTests.ps1'})

    def test_every_run_script_is_listed(self):
        present = {p.name for p in TESTS.glob('Run-*.ps1')}
        listed = {s['file'] for s in self.suites} | {'Run-AllTests.ps1'}
        self.assertEqual(present - listed, set())
        result = subprocess.run([sys.executable, str(RUNNER), '--list-missing'], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Aucune suite manquante', result.stdout)

    def test_windows_launcher_needs_no_python(self):
        cmd = (DEV / 'TEST_TOUT.cmd').read_text(encoding='utf-8', errors='replace')
        self.assertIn('"%Pesto_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0tests\\Run-AllTests.ps1"', cmd)
        self.assertNotIn('run_tests.py', cmd)

    def test_results_are_ignored_by_git(self):
        self.assertIn('tests/results/', (DEV / '.gitignore').read_text(encoding='utf-8'))
        runner = RUNNER.read_text(encoding='utf-8')
        self.assertNotIn('/Users/', runner)
        self.assertIn("root / 'tests' / 'results'", runner)
        self.assertIn("root / 'tests' / suite['file']", runner)


@unittest.skipIf(os.name == 'nt', 'Plateforme : le faux pwsh est un script exécutable POSIX.')
class TestRunnerBehaviour(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root = base / 'DEV'
        (self.root / 'tests').mkdir(parents=True)
        (self.root / 'tests' / 'Run-PassTests.ps1').write_text('# MARQUEUR-PASS\n', encoding='utf-8-sig')
        (self.root / 'tests' / 'Run-FailTests.ps1').write_text('# échoue\n', encoding='utf-8-sig')
        (self.root / 'tests' / 'Run-WindowsTests.ps1').write_text('# MARQUEUR-PASS\n', encoding='utf-8-sig')
        self.fake = base / 'faux-pwsh'
        self.fake.write_text(FAKE_PWSH % sys.executable, encoding='utf-8')
        self.fake.chmod(0o755)
        self.cwd = base / 'ailleurs'
        self.cwd.mkdir()

    def run_runner(self, suites, *extra):
        (self.root / 'tests' / 'suites.json').write_text(json.dumps(suites), encoding='utf-8')
        result = subprocess.run([sys.executable, str(RUNNER), '--root', str(self.root), '--pwsh', str(self.fake),
                                 '--platform', 'Portable'] + list(extra),
                                cwd=str(self.cwd), capture_output=True, text=True, timeout=120)
        summaries = sorted((self.root / 'tests' / 'results').glob('*/summary.json'))
        summary = json.loads(summaries[-1].read_text(encoding='utf-8')) if summaries else None
        return result, summary

    @staticmethod
    def suite(name, file, platform='Portable', profile='Complet'):
        return {'name': name, 'file': file, 'platform': platform, 'profile': profile}

    def test_statuses_and_exit_code_from_another_directory(self):
        suites = [self.suite('Pass', 'Run-PassTests.ps1'), self.suite('Windows', 'Run-WindowsTests.ps1', 'Windows51'),
                  self.suite('Absente', 'Run-AbsentTests.ps1'), self.suite('Fail', 'Run-FailTests.ps1')]
        result, summary = self.run_runner(suites)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual([r['status'] for r in summary['results']], ['PASS', 'SKIP', 'FAIL', 'FAIL'])
        self.assertIn('introuvable', summary['results'][2]['message'])
        self.assertEqual(summary['counts'], {'PASS': 1, 'FAIL': 2, 'SKIP': 1})
        self.assertEqual(list(self.cwd.iterdir()), [], 'Rien ne doit être écrit dans le dossier courant')

    def test_only_skips_is_not_a_success(self):
        result, summary = self.run_runner([self.suite('Windows', 'Run-WindowsTests.ps1', 'Windows51')])
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(summary['counts'], {'PASS': 0, 'FAIL': 0, 'SKIP': 1})

    def test_passing_suite_and_rapide_profile(self):
        suites = [self.suite('Pass', 'Run-PassTests.ps1', profile='Rapide'), self.suite('Fail', 'Run-FailTests.ps1')]
        result, summary = self.run_runner(suites, '--profile', 'Rapide')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([r['status'] for r in summary['results']], ['PASS', 'SKIP'])

    def test_separate_suite_is_skipped_and_list_missing(self):
        suites = [self.suite('Pass', 'Run-PassTests.ps1'), dict(self.suite('Win', 'Run-WindowsTests.ps1'), separate='TESTER.cmd')]
        result, summary = self.run_runner(suites)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(summary['results'][1]['status'], 'SKIP')
        missing = subprocess.run([sys.executable, str(RUNNER), '--root', str(self.root), '--list-missing'],
                                 cwd=str(self.cwd), capture_output=True, text=True, timeout=60)
        self.assertEqual(missing.returncode, 1)
        self.assertIn('Run-FailTests.ps1', missing.stdout)


if __name__ == '__main__':
    unittest.main()
