import unittest
import json, os, shutil, subprocess, tempfile
from pathlib import Path

INTEGRATIONS = Path(__file__).resolve().parents[1] / 'integrations'


class TestSparkT014(unittest.TestCase):
    def test_adapter_uses_cli_host_and_ascii_json(self):
        script_path = INTEGRATIONS / 'Invoke-PestoDeployment.ps1'
        self.assertTrue(script_path.is_file(), "Script Invoke-PestoDeployment.ps1 not found: " + str(script_path))
        content = script_path.read_text(encoding='utf-8-sig')

        # 1. Check for Pesto-CliHost.ps1 dot-sourcing
        self.assertIn("Pesto-CliHost.ps1", content, "Must dot-source Pesto-CliHost.ps1")
        
        # 2. Check for Initialize-PestoCliProcess call
        self.assertIn("Initialize-PestoCliProcess", content, "Must call Initialize-PestoCliProcess")

        # 3. Check for ConvertTo-PestoCliJson usage
        self.assertIn("ConvertTo-PestoCliJson", content, "Must use ConvertTo-PestoCliJson")

        # 4. Check that raw ConvertTo-Json is NOT used for the main success path
        # We allow ConvertTo-Json in the fallback block, but not the main one.
        # Simple heuristic: Ensure the main output line uses the helper.
        self.assertIn("ConvertTo-PestoCliJson $result 12", content, "Main JSON output must use ConvertTo-PestoCliJson")

        # 5. L'échappement ASCII du refus précoce reste compatible 5.1 (MatchEvaluator, pas de -replace à scriptblock).
        self.assertIn('[Text.RegularExpressions.MatchEvaluator]', content)
        self.assertNotRegex(content, r"-replace\s+'[^']*'\s*,\s*\{")


class DeploymentFailureTests(unittest.TestCase):
    def setUp(self):
        self.ps = (os.environ.get('PESTO_TEST_PWSH') or os.environ.get('PESTO_PWSH')
                   or shutil.which('powershell.exe') or shutil.which('pwsh'))
        if not self.ps:
            self.skipTest('PowerShell unavailable')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.wad = self.root / 'wad'
        self.wad.mkdir()
        self.marker = 'PESTO_SYNTHETIC_SECRET_7c1539'
        self.write('Pesto-CliHost.ps1', 'function Initialize-PestoCliProcess { [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false) }')
        self.write('Pesto-Integrity.ps1', 'function Test-PestoPackage { param($Root) return $true }')
        self.write('Pesto.Engine.psd1', "@{ModuleVersion='1.0';RootModule='Fixture.psm1';FunctionsToExport=@('Invoke-PestoCommand')}")
        self.write('Fixture.psm1', "function Invoke-PestoCommand { throw 'password="+self.marker+"' }")
    def write(self, name, text):
        (self.wad / name).write_bytes(('\ufeff'+text).encode('utf-8'))
    def run_adapter(self, *args):
        p=subprocess.run([self.ps,'-NoProfile','-File',str(INTEGRATIONS/'Invoke-PestoDeployment.ps1'),
                          '-Installation',str(self.root),'-AsJson',*args],
                         capture_output=True,text=True,encoding='utf-8',timeout=25)
        self.assertNotIn(self.marker,p.stdout+p.stderr)
        lines=[line for line in p.stdout.splitlines() if line.strip().startswith('{')]
        self.assertTrue(lines,'Expected JSON result')
        return p.returncode,json.loads(lines[-1])
    def test_inspection_exception_has_no_secret_and_no_mutation(self):
        code,result=self.run_adapter('-Action','Inspect')
        self.assertEqual(code,96); self.assertEqual(result['State'],'NotStarted')
        self.assertFalse(result['MutationStarted'])
    def test_execution_exception_remains_uncertain_not_safe_to_retry(self):
        code,result=self.run_adapter('-Action','Rename','-Execute','-IdempotencyKey','fixture-1')
        self.assertEqual(code,97); self.assertEqual(result['State'],'Uncertain')
        self.assertTrue(result['MutationStarted'])
    def test_failure_loading_host_does_not_echo_secret_path(self):
        self.write('Pesto-CliHost.ps1', "throw '"+self.marker+"'")
        code,result=self.run_adapter('-Action','Rename','-Execute','-IdempotencyKey','fixture-2')
        self.assertEqual(code,96); self.assertFalse(result['MutationStarted'])
        self.assertIn('lanceur',result['Message'])
    def test_missing_engine_export_never_marks_mutation_started(self):
        self.write('Fixture.psm1', '# no export')
        code,result=self.run_adapter('-Action','Rename','-Execute','-IdempotencyKey','fixture-4')
        self.assertEqual(code,96); self.assertFalse(result['MutationStarted'])
    def test_malformed_results_never_exit_success(self):
        for value in ("$null", "[pscustomobject]@{State='Failed';MutationStarted=$true}",
                      "[pscustomobject]@{State='Failed';ExitCode='0';MutationStarted=$true}",
                      "[pscustomobject]@{State='Failed';ExitCode=-1;MutationStarted=$true}"):
            with self.subTest(value=value):
                self.write('Fixture.psm1', 'function Invoke-PestoCommand { '+value+' }')
                code,result=self.run_adapter('-Action','Rename','-Execute','-IdempotencyKey','fixture-5')
                self.assertEqual(code,97); self.assertEqual(result['State'],'Uncertain')
    def test_normal_result_is_not_reclassified(self):
        self.write('Fixture.psm1', "function Invoke-PestoCommand { [pscustomobject]@{Schema=1;Mode='Rename';State='PendingRestart';ExitCode=20;MutationStarted=$true;RestartRequired=$true;Message='Accepted'} }")
        code,result=self.run_adapter('-Action','Rename','-Execute','-IdempotencyKey','fixture-3')
        self.assertEqual(code,20); self.assertEqual(result['State'],'PendingRestart')
        self.assertTrue(result['RestartRequired'])
    def test_windows_restart_code_is_preserved_in_json(self):
        self.write('Fixture.psm1', "function Invoke-PestoCommand { [pscustomobject]@{State='PendingRestart';ExitCode=3010;MutationStarted=$true} }")
        code,result=self.run_adapter('-Action','Join','-Execute','-IdempotencyKey','fixture-6')
        self.assertEqual(result['ExitCode'],3010)
        self.assertEqual(code,3010 if os.name=='nt' else 3010%256)


if __name__ == '__main__':
    unittest.main()
