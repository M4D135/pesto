"""Observateur de réplication (tools/Observe-PestoReplication.ps1) exécuté sous pwsh avec des doubles AD.

Aucun AD réel : Get-ADComputer et Get-ADReplicationAttributeMetadata sont des fonctions du script pilote.
pwsh est pris dans PESTO_PWSH, PESTO_TEST_PWSH ou le PATH ; son absence fait échouer le test (jamais ignoré).
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / 'tools' / 'Observe-PestoReplication.ps1'
GUID = '2f1d7c8e-0b3a-4f6e-9d21-5a7c3e9b1f40'
NEW_NAME = 'P111301PA765003'
NEW_DN = 'CN=P111301PA765003,OU=Paris,OU=Postes,DC=lab,DC=test'
OLD_NAME = 'P111301LY765128'
OLD_DN = 'CN=P111301LY765128,OU=Lyon,OU=Postes,DC=lab,DC=test'


def find_pwsh():
    for key in ('PESTO_PWSH', 'PESTO_TEST_PWSH'):
        value = os.environ.get(key)
        if value:
            return value
    return shutil.which('pwsh')


def ps_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


class TestObservePestoReplication(unittest.TestCase):
    def setUp(self):
        self.assertTrue(TOOL.is_file(), 'Outil introuvable : ' + str(TOOL))
        self.content = TOOL.read_text(encoding='utf-8-sig')
        self.pwsh = find_pwsh()
        if not self.pwsh:
            self.fail('pwsh introuvable : définir PESTO_PWSH (PowerShell 7 portable) pour exécuter ce banc.')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def run_ps(self, script):
        driver = self.dir / ('driver-%d.ps1' % len(list(self.dir.glob('driver-*.ps1'))))
        driver.write_text(script, encoding='utf-8-sig')
        return subprocess.run([self.pwsh, '-NoProfile', '-NonInteractive', '-File', str(driver)],
                              capture_output=True, text=True, encoding='utf-8', timeout=120)

    def observe(self, behaviours, report_name='report.json', extra=''):
        table = '; '.join('%s=%s' % (ps_quote(k), ps_quote(v)) for k, v in behaviours.items())
        servers = ','.join(ps_quote(k) for k in behaviours)
        report = self.dir / report_name
        script = """
$ErrorActionPreference='Stop'
$global:Behaviour=@{%s}
function Get-ADComputer {
    [CmdletBinding()]
    param($Identity,$Server,$Properties,$Credential)
    switch($global:Behaviour[$Server]){
        'expected' {[pscustomobject]@{Name=%s;DistinguishedName=%s;whenChanged=[DateTime]::UtcNow;uSNChanged=42}}
        'stale'    {[pscustomobject]@{Name=%s;DistinguishedName=%s;whenChanged=[DateTime]::UtcNow;uSNChanged=41}}
        'notfound' {Write-Error -Message 'Objet introuvable sur ce DC' -Category ObjectNotFound}
        default    {throw 'Serveur inattendu'}
    }
}
function Get-ADReplicationAttributeMetadata {
    [CmdletBinding()]
    param($Object,$Server,$Credential)
    [pscustomobject]@{AttributeName='name';Version=3;LastOriginatingChangeTime=[DateTime]::UtcNow}
}
& %s -Domain 'lab.test' -ObjectGuid %s -Server @(%s) -ExpectedName %s -ExpectedDistinguishedName %s `
    -IntervalSeconds 2 -TimeoutSeconds 1 -ReportPath %s %s
exit $LASTEXITCODE
""" % (table, ps_quote(NEW_NAME), ps_quote(NEW_DN), ps_quote(OLD_NAME), ps_quote(OLD_DN), ps_quote(TOOL), ps_quote(GUID),
           servers, ps_quote(NEW_NAME), ps_quote(NEW_DN), ps_quote(report), extra)
        result = self.run_ps(script)
        data = None
        if result.returncode != 1 and report.exists():
            data = json.loads(report.read_text(encoding='utf-8-sig'))
        return result, data

    def test_converged_only_when_every_dc_returns_the_expected_values(self):
        result, data = self.observe({'dc1.lab.test': 'expected', 'dc2.lab.test': 'expected'})
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(data['Verdict'], 'CONVERGED')
        self.assertEqual([d['Status'] for d in data['Details']], ['Expected', 'Expected'])
        self.assertEqual(data['ExpectedName'], NEW_NAME)

    def test_stale_dc_is_never_converged(self):
        # Tous les DC rendent encore l'ancien nom : l'ancien comportement concluait CONVERGED sur ces données.
        result, data = self.observe({'dc1.lab.test': 'stale', 'dc2.lab.test': 'stale'})
        self.assertEqual(result.returncode, 3, result.stderr + result.stdout)
        self.assertEqual(data['Verdict'], 'INCOMPLETE')
        self.assertEqual([d['Status'] for d in data['Details']], ['Stale', 'Stale'])
        result, data = self.observe({'dc1.lab.test': 'expected', 'dc2.lab.test': 'stale'}, 'mixed.json')
        self.assertEqual(result.returncode, 3, result.stderr + result.stdout)
        self.assertEqual(data['Verdict'], 'INCOMPLETE')
        self.assertEqual(data['Details'][1]['Name'], OLD_NAME)

    def test_not_found_is_reported_and_incomplete(self):
        result, data = self.observe({'dc1.lab.test': 'expected', 'dc2.lab.test': 'notfound'})
        self.assertEqual(result.returncode, 3, result.stderr + result.stdout)
        self.assertEqual(data['Verdict'], 'INCOMPLETE')
        self.assertEqual(data['Details'][1]['Status'], 'NotFound')

    def test_single_dc_verdict(self):
        result, data = self.observe({'dc1.lab.test': 'expected'})
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(data['Verdict'], 'SINGLE_DC')

    def test_existing_report_is_never_overwritten(self):
        report = self.dir / 'existing.json'
        report.write_text('garder', encoding='utf-8')
        result, _ = self.observe({'dc1.lab.test': 'expected'}, 'existing.json')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report.read_text(encoding='utf-8'), 'garder')

    def test_expected_values_are_mandatory(self):
        for name in ('ExpectedName', 'ExpectedDistinguishedName'):
            self.assertRegex(self.content, r'\[Parameter\(Mandatory=\$true\)\]\s*\[ValidateNotNullOrEmpty\(\)\]\s*\[string\]\$' + name + r'\b')
        self.assertIn('[ValidateCount(1, 8)]', self.content)
        self.assertIn('[ValidateRange(2, 60)]', self.content)
        self.assertIn('[ValidateRange(1, 3600)]', self.content)
        self.assertIn('[IO.FileMode]::CreateNew', self.content)

    def test_only_read_commands_are_called(self):
        # Analyse AST : seuls les vrais appels de commande comptent (pas les chaînes ni les commentaires).
        result = self.run_ps("""
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(%s,[ref]$t,[ref]$e)
if($e.Count){throw ($e|ForEach-Object{$_.Message}) -join '; '}
$names=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object{$_.GetCommandName()}|Where-Object{$_}|Sort-Object -Unique)
ConvertTo-Json -InputObject $names -Compress
""" % ps_quote(TOOL))
        self.assertEqual(result.returncode, 0, result.stderr)
        names = json.loads(result.stdout.strip())
        self.assertIn('Get-ADComputer', names)
        for name in names:
            self.assertNotRegex(name, r'(?i)^(Set|Rename|Move|Remove|Sync|Restart|New|Add|Enable|Disable|Clear|Reset|Unlock)-AD')
            self.assertNotRegex(name, r'(?i)^(repadmin|Get-ADDomainController|Find-ADDomainController)')
        self.assertNotRegex(self.content, r'(?i)\$MyInvocation\.MyCommand\.Path')


if __name__ == '__main__':
    unittest.main()
