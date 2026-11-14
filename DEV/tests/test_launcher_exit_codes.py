"""L4 : contrat des codes de sortie de Pesto.exe. Lecture des sources, portable ; aucun Windows exécuté.
Le comportement est simulé par tools/launcher/test_entry.c (tools/checks/run_native_portable.py)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
# Anciennes valeurs propres au lanceur : verrou de mise à jour (32), erreurs Win32 brutes (2, 3, 5).
# Côté PowerShell, 2 et 3 sont aussi des codes de la sonde UAC (Complete-PestoStartupUacProbe), rendus tels quels :
# seuls 5 et 32 y restent interdits. Les .cmd qui démarrent Pesto.exe ne posent pas la sonde : 2, 3, 5, 32 interdits.
OLD_LAUNCHER_VALUES_CMD = r'(?:2|3|5|32)'
OLD_LAUNCHER_VALUES_PS1 = r'(?:5|32)'
# 0 (succès) et 1 (refus du script) gardent leur sens, mais plus celui du lanceur (déjà ouvert = 0 ; paramètre
# inconnu, composant refusé = 1) : une comparaison dont le message nomme une cause du lanceur doit viser son code.
LAUNCHER_CAUSES = {
    128: r'd[ée]j[àa] ouvert|already open',
    126: r'verrou de mise [àa] jour|\.pesto-update\.lock|update lock',
    125: r'empreinte|composants? (?:refus|modifi|absent)',
    120: r'param[èe]tre inconnu|unknown (?:param|argument)',
}
# Comparaison d'un code : variable PowerShell nommée *code* / *exit*, .ExitCode, $LASTEXITCODE ; errorlevel en .cmd.
PS_CODE = r'(?:\.ExitCode|\$\w*(?:code|exit)\w*)'


class LauncherExitCodes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = (ROOT / 'tools/launcher/Pesto-launcher.c').read_text('utf-8')
        cls.codes = {m.group(1): int(m.group(2)) for m in re.finditer(r'^#define (X_[A-Z]+) (\d+)\b', cls.c, re.M)}

    def test_own_codes_are_distinct_and_in_range(self):
        self.assertGreaterEqual(len(self.codes), 13)
        values = list(self.codes.values())
        self.assertEqual(len(values), len(set(values)), 'une valeur par cause')
        for name, value in self.codes.items():
            self.assertTrue(120 <= value <= 139, name)

    def test_every_refusal_uses_a_named_code(self):
        calls = re.findall(r'\bdie\(W\("(?:[^"\\]|\\.)*"\),(\w+),', self.c)
        self.assertEqual(len(calls), self.c.count('die(W('), 'chaque refus nomme son code')
        for code in calls:
            self.assertIn(code, self.codes)
        self.assertEqual(set(calls) | {'X_RUNNING', 'X_CHILDCODE'}, set(self.codes), 'chaque code défini est utilisé')

    def test_no_raw_win32_error_or_literal_exit_code(self):
        exits = [a for a in re.findall(r'\bExitProcess\(([^)]*)\);', self.c) if a != 'unsigned int']
        self.assertTrue(exits)
        for argument in exits:
            self.assertIn(argument, {'0', 'exitcode', 'code', 'X_RUNNING'})
        # Seul un code illisible est remplacé ; le code rendu par PowerShell passe tel quel.
        self.assertIn('if(!GetExitCodeProcess(pi.hProcess,&code))code=X_CHILDCODE;', self.c)
        self.assertEqual(len(re.findall(r'\bcode=', self.c)), 2, 'code initialisé puis seulement remplacé s\'il est illisible')
        self.assertIn('Code de sortie 120 à 139', self.c, 'aide du lanceur')

    def test_simulation_covers_every_code(self):
        entry = (ROOT / 'tools/launcher/test_entry.c').read_text('utf-8')
        expected = {int(x) for x in re.findall(r'expected_exit=(\d+);', entry)}
        for name, value in self.codes.items():
            self.assertIn(value, expected, name)
        self.assertIn('demand(code>=120&&code<=139', entry)

    def test_guide_documents_every_code(self):
        guide = (ROOT / 'docs/V1_GUIDE.md').read_text('utf-8')
        start = guide.index('## Codes de sortie de `Pesto.exe`')
        section = guide[start:guide.index('\n## ', start + 1)]
        documented = {int(x) for x in re.findall(r'^\| (\d{3}) \|', section, re.M)}
        self.assertEqual(documented, set(self.codes.values()))
        self.assertIn('| 133-139 |', section)

    def test_powershell_side_never_returns_launcher_range(self):
        # 1. Aucune sortie explicite de wad\ (sous-dossiers compris) avec un littéral 120-139, quelle que soit sa forme.
        literal = re.compile(r'(?i)(?:\bexit|\bQuit|\bNew-ActionResult|\[(?:System\.)?Environment\]::Exit|\.SetShouldExit)'
                             r'\s*\(?\s*1[23]\d\b')
        for path in sorted((ROOT / 'wad').rglob('*.ps1')):
            self.assertIsNone(literal.search(path.read_text('utf-8-sig')), path.name)
        # 2. Chemin de Pesto.exe (démarrage, relais élevé, moteur) : chaque sortie est énumérée et bornée.
        #    Une nouvelle sortie calculée fait échouer ce test : la borner ici avant de l'accepter.
        startup = (ROOT / 'wad/Pesto-Startup.ps1').read_text('utf-8-sig')
        core = (ROOT / 'wad/Pesto-Core.ps1').read_text('utf-8-sig')
        exits = re.compile(r'(?im)^(?![ \t]*#)[^\n]*?(?<![\w$.\[-])exit(?![\w-])[ \t]*(\(?[\w$-]*)')
        for name, text in (('Pesto-Startup.ps1', startup), ('Pesto-Core.ps1', core)):
            self.assertNotRegex(text, r'(?i)\[(?:System\.)?Environment\]::Exit|SetShouldExit|GetCurrentProcess\(\)\.Kill', name)
        self.assertEqual(set(exits.findall(startup)),
                         {'0', '1', '$errorCode', '$exitCode', '(Complete-PestoStartupUacProbe', '$LASTEXITCODE'})
        self.assertEqual(set(exits.findall(core)), {'1', '$Code', '$LASTEXITCODE'})
        # --validate-plan : 0 ou 20.
        self.assertLessEqual({int(x) for x in re.findall(r'\$errorCode=(\d+)', startup)}, {0, 20})
        # Sonde UAC : 0, 2 ou 3, rendu par un seul return.
        probe = startup[startup.index('function Complete-PestoStartupUacProbe'):startup.index('function New-PestoStartupArgumentLine')]
        assignment = re.search(r'\$code=if\([^\n]*', probe)
        self.assertIsNotNone(assignment)
        self.assertEqual({int(x) for x in re.findall(r'\{(\d+)\}', assignment.group(0))}, {0, 2, 3})
        self.assertEqual(re.findall(r'\breturn\b[^\n]*', probe), ['return $code'])
        # Relais élevé : Pesto-Startup.ps1 lui-même (mêmes sorties), ou 1223 si l'UAC est annulée.
        self.assertEqual(re.findall(r'\$exitCode=[^\n]*', startup)[0][:40], '$exitCode=Invoke-PestoStartupElevation -')
        self.assertEqual(len(re.findall(r'\$exitCode=', startup)), 1)
        relay = startup[startup.index('function Invoke-PestoStartupElevation'):]
        relay = relay[:relay.index('\n}\n')]
        self.assertEqual(re.findall(r'\breturn\b[^\n]*', relay), ['return [int]$process.ExitCode', 'return 1223'])
        self.assertIn("if([IO.Path]::GetFileName($entry) -ine 'Pesto-Startup.ps1'){throw", startup)
        # $LASTEXITCODE : seulement juste après le moteur (démarrage) ou le démarrage (moteur non élevé).
        self.assertEqual(startup.count('exit $LASTEXITCODE'), 1)
        self.assertRegex(startup, r'& \$core @parameters\s*\n\s*exit \$LASTEXITCODE')
        self.assertEqual(core.count('exit $LASTEXITCODE'), 1)
        self.assertRegex(core, r'& \$startupLauncher @startupParams\s*\n\s*exit \$LASTEXITCODE')
        # Moteur : Quit sans code, Quit 0 ou Quit 1.
        quits = re.findall(r'(?im)^(?![ \t]*#)[^\n]*?(?<![\w$.-])Quit(?![\w-])[ \t]*([^\s;}]*)', core)
        self.assertLessEqual(set(quits) - {'{'}, {'', '0', '1'})
        self.assertIn('function Quit { param([int]$Code = 0)', core)

    def _scripts_starting_launcher(self):
        def read(path):
            return path.read_text('utf-8-sig', errors='replace')
        # .cmd qui lancent Pesto.exe eux-mêmes (hors lignes rem), scripts PowerShell qui le démarrent.
        cmd = [p for p in [*ROOT.glob('*.cmd'), *(ROOT / 'wad/support').glob('*.cmd')]
               if re.search(r'(?im)^(?!\s*rem\b)[^\n]*Pesto\.exe"', read(p))]
        ps1 = [p for p in [*(ROOT / 'tools').rglob('*.ps1'), *(ROOT / 'wad/maintenance').glob('*.ps1'), *(ROOT / 'tests').glob('*.ps1')]
               if 'Pesto.exe' in read(p) and re.search(r'Start-Process|ProcessStartInfo', read(p))]
        return [(p, read(p)) for p in cmd], [(p, read(p)) for p in ps1]

    def test_pack_scripts_do_not_test_old_launcher_values(self):
        cmd, ps1 = self._scripts_starting_launcher()
        self.assertTrue(cmd)
        self.assertIn('Verify-StartupUac.ps1', [p.name for p, _ in ps1])
        for path, text in cmd:
            self.assertNotRegex(text, rf'(?i)\bif\s+(?:not\s+)?errorlevel\s+{OLD_LAUNCHER_VALUES_CMD}\b', path.name)
            self.assertNotRegex(text, rf'(?i)"%[^%"]*%"\s*==\s*"{OLD_LAUNCHER_VALUES_CMD}"', path.name)
        for path, text in ps1:
            self.assertNotRegex(text, rf'(?i){PS_CODE}\s+-(?:eq|ne)\s+{OLD_LAUNCHER_VALUES_PS1}\b', path.name)

    def test_comparisons_naming_a_launcher_cause_use_its_new_code(self):
        # Rattrape « $code -eq 0 ... déjà ouvert » (ancien sens de 0) : une comparaison numérique dont la ligne
        # nomme une cause propre au lanceur doit viser le code de cette cause.
        compare = re.compile(rf'(?i)(?:{PS_CODE}\s+-eq\s+(\d+)\b|\berrorlevel\s+(\d+)\b|%[^%"]*%"?\s*==\s*"?(\d+)\b)')
        cmd, ps1 = self._scripts_starting_launcher()
        for path, text in cmd + ps1:
            for number, line in enumerate(text.splitlines(), 1):
                if re.match(r'(?i)\s*(?:#|rem\b|::)', line):
                    continue
                values = {int(v) for m in compare.finditer(line) for v in m.groups() if v}
                if not values:
                    continue
                for code, cause in LAUNCHER_CAUSES.items():
                    if re.search(cause, line, re.I):
                        self.assertIn(code, values, f'{path.name}:{number}: {line.strip()}')

    def test_uac_harness_reads_new_launcher_codes(self):
        harness = (ROOT / 'tools/Verify-StartupUac.ps1').read_text('utf-8-sig')
        self.assertRegex(harness, r'\$code -eq 128\)\{[^\n]*d[ée]j[àa] ouvert')
        # Code 0 sans reçu : anomalie signalée, jamais expliquée par une instance déjà ouverte.
        zero = re.search(r'\$code -eq 0 -and -not \$fields\.Count\)\{([^\n]*)', harness)
        self.assertIsNotNone(zero)
        self.assertNotRegex(zero.group(1), r'(?i)d[ée]j[àa] ouvert')
        self.assertRegex(zero.group(1), r'(?i)anomalie')
        self.assertIn('$code -ge 120 -and $code -le 139', harness)

if __name__ == '__main__':
    unittest.main(verbosity=2)
