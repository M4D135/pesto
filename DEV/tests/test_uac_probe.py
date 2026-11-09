"""Constat O7 : VERIFIER_UAC.cmd teste la vraie demande d'UAC avec le vrai Pesto.exe et des composants intacts.

Contrôle portable du texte seulement : rien ici ne lance Windows PowerShell, l'UAC ou Pesto.exe. La logique des
fonctions de la sonde est couverte par tests/Run-StabilisationTests.ps1 (doubles) ; l'UAC réelle par VERIFIER_UAC.cmd.
"""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
from ps_lexical import functions, tokens  # noqa: E402

TOKEN = "'^[0-9a-f]{32}\\z'"


def top_level_args(call):
    """Split the arguments of a C call on top-level commas."""
    depth, current, out = 0, '', []
    for ch in call:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(current.strip())
            current = ''
        else:
            current += ch
    out.append(current.strip())
    return out


class UacProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.startup = (ROOT / 'wad/Pesto-Startup.ps1').read_text('utf-8-sig')
        cls.body = cls.startup[cls.startup.index("if($MyInvocation.InvocationName -eq '.') { return }"):]
        cls.fn = functions(cls.startup)
        cls.harness_bytes = (ROOT / 'tools/Verify-StartupUac.ps1').read_bytes()
        cls.harness = cls.harness_bytes.decode('utf-8-sig')
        cls.launcher = (ROOT / 'tools/launcher/Pesto-launcher.c').read_text('utf-8')
        cls.cmd_bytes = (ROOT / 'VERIFIER_UAC.cmd').read_bytes()

    def function(self, name):
        start, end = self.fn[name]
        return self.startup[start:end]

    def test_probe_token_is_strict_and_relay_ignores_environment(self):
        resolve = self.function('Resolve-PestoStartupUacProbe')
        self.assertIn('-cnotmatch ' + TOKEN, resolve)
        self.assertIn('$value=if($ParameterBound -or $ElevatedLaunch){$Parameter}else{$Environment}', resolve)
        self.assertIn('throw', resolve)
        # La variable n'est lue qu'à un endroit, avant toute décision de route.
        self.assertEqual(1, self.startup.count('$env:PESTO_UAC_PROBE'))
        for name in ('New-PestoStartupArgumentLine', 'Complete-PestoStartupUacProbe'):
            self.assertIn('-cnotmatch ' + TOKEN, self.function(name), name)

    def test_probe_stops_before_state_import_session_mutex_and_engine(self):
        body = self.body
        order = [
            '$probe=Resolve-PestoStartupUacProbe',
            'if($CheckPackage){',
            'if($probe -and ($Demo -or $Consult)){throw',
            '$isAdmin=Test-PestoStartupAdministrator',
            "if($probe -and $route -ne 'Elevate'){",
            'exit (Complete-PestoStartupUacProbe',
            "if($route -eq 'Refuse'){",
            '-UacProbe $probe',
            'Import-PestoStartupState -OriginLocalAppData',
            "$sessionMutex=[Threading.Mutex]::new",
            '& $core @parameters',
        ]
        positions = [body.index(marker) for marker in order]
        self.assertEqual(positions, sorted(positions), order)
        self.assertNotIn('$core', self.function('Complete-PestoStartupUacProbe'))
        self.assertNotIn('Import-PestoStartupState', self.function('Complete-PestoStartupUacProbe'))

    def test_relay_receipt_is_create_new_at_a_fixed_local_path(self):
        complete = self.function('Complete-PestoStartupUacProbe')
        self.assertIn("$relative='wad\\logs\\Pesto-sonde-uac-'+$Probe+'.txt'", complete)
        self.assertIn('Assert-PestoStartupLocalPath $directory', complete)
        self.assertIn('Write-PestoStartupNewFile -Path $path', complete)
        self.assertIn("if($ElevatedLaunch -and $IsAdministrator -and $Route -eq 'Run'){'UAC_OK'}", complete)
        self.assertNotIn('FileMode]::Create,', self.startup)

    def test_check_report_echoes_probe_for_the_preflight(self):
        self.assertIn("if($probe){$report['UacProbe']=$probe}", self.body)
        self.assertIn('-UacProbe', self.function('New-PestoStartupArgumentLine'))

    def test_harness_uses_real_launcher_and_intact_components(self):
        self.assertTrue(self.harness_bytes.startswith(b'\xef\xbb\xbf'))
        tokens(self.harness)
        # Ni copie ni composant remplacé, ni lancement direct du script de démarrage ou d'un PowerShell élevé.
        for forbidden in ('Update-PackageManifest', 'Copy-Item', 'WriteAllText', 'Set-Content', 'Pesto-Core.ps1',
                          'Get-PestoRuntimeFiles', 'Pesto.cmd', 'wad\\Pesto-Startup.ps1', 'powershell.exe', '-Verb'):
            self.assertNotIn(forbidden, self.harness, forbidden)
        self.assertIn("$exe=Join-Path $root 'Pesto.exe'", self.harness)
        self.assertIn("$info.EnvironmentVariables['PESTO_UAC_PROBE']=$probe", self.harness)
        self.assertIn("$probe=[Guid]::NewGuid().ToString('N')", self.harness)
        self.assertIn('if($admin){throw', self.harness)
        # Écho de la sonde exigé par --check-json AVANT le lancement normal (sans argument) qui demande l'UAC.
        preflight = self.harness.index("Start-PestoProbeLauncher @('--check-json',$check)")
        echo = self.harness.index('[string]$report.UacProbe -cne $probe')
        launch = self.harness.index('$code=Start-PestoProbeLauncher @()')
        self.assertLess(preflight, echo)
        self.assertLess(echo, launch)
        self.assertIn("$fields['Resultat'] -ceq 'UAC_OK'", self.harness)

    def test_launcher_has_no_test_mode_and_inherits_environment(self):
        lowered = self.launcher.lower()
        self.assertNotIn('probe', lowered)
        self.assertNotIn('pesto_uac', lowered)
        self.assertLess(self.launcher.index('pesto_verify_runtime()'), self.launcher.index('CreateProcessW(pspath'))
        call = re.search(r'CreateProcessW\(pspath,(.*?)\);', self.launcher, re.S)
        self.assertIsNotNone(call)
        args = top_level_args('pspath,' + call.group(1))
        self.assertEqual(10, len(args), args)
        # lpEnvironment NULL : PowerShell hérite de l'environnement du lanceur, canal de la sonde.
        self.assertEqual('0', args[6], args)

    def test_verifier_uac_cmd_runs_the_harness(self):
        self.assertNotIn(b'\n', self.cmd_bytes.replace(b'\r\n', b''))
        text = self.cmd_bytes.decode('ascii')
        self.assertIn('-File "%~dp0tools\\Verify-StartupUac.ps1"', text)
        self.assertNotIn('Pesto.cmd', text)
        self.assertNotRegex(text, r'(?im)^\s*call\s+"%~dp0')


if __name__ == '__main__':
    unittest.main(verbosity=2)
