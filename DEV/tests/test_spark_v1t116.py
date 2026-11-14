"""Courbe de charge en lecture AD (tools/Measure-PestoReadLoad.ps1), exécutée sous pwsh avec un module AD factice.

Le module factice enregistre chaque appel (commande, serveur, base, compte) : aucune lecture AD réelle.
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
TOOL = DEV / 'tools' / 'Measure-PestoReadLoad.ps1'
MODEL = DEV / 'tools' / 'cfg.modele-complet.json'

STUB = r"""
function Write-StubCall {
    param([string]$Command,[hashtable]$Data)
    $Data['Command']=$Command
    $path=Join-Path $env:PESTO_READLOAD_LOG ([Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($path,($Data|ConvertTo-Json -Compress))
}
function Get-ADDomainController {
    [CmdletBinding()]
    param([switch]$Discover,[string]$DomainName,[string[]]$Service)
    Write-StubCall 'Get-ADDomainController' @{Discover=[bool]$Discover;DomainName=$DomainName;Service=[string]($Service -join ',')}
    [pscustomobject]@{HostName=@('dc2.example.local')}
}
function Get-ADComputer {
    [CmdletBinding()]
    param($Identity,$SearchBase,$SearchScope,$Filter,$ResultPageSize,$ResultSetSize,$Server,$Credential)
    $user=''; if($Credential){$user=$Credential.UserName}
    Write-StubCall 'Get-ADComputer' @{Identity=[string]$Identity;SearchBase=[string]$SearchBase;Server=[string]$Server;User=$user}
    Start-Sleep -Milliseconds 120
    if($Identity){return [pscustomobject]@{Name=[string]$Identity}}
    @([pscustomobject]@{Name='P111301PA765001'},[pscustomobject]@{Name='P111301PA765002'})
}
function Get-ADOrganizationalUnit {
    [CmdletBinding()]
    param($SearchBase,$SearchScope,$Filter,$ResultSetSize,$Server,$Credential)
    $user=''; if($Credential){$user=$Credential.UserName}
    Write-StubCall 'Get-ADOrganizationalUnit' @{SearchBase=[string]$SearchBase;Server=[string]$Server;User=$user;Filter=[string]$Filter}
    [pscustomobject]@{Name='Paris'}
}
Export-ModuleMember -Function Get-ADDomainController,Get-ADComputer,Get-ADOrganizationalUnit
"""


def find_pwsh():
    for key in ('PESTO_PWSH', 'PESTO_TEST_PWSH'):
        value = os.environ.get(key)
        if value:
            return value
    return shutil.which('pwsh')


def ps_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


class TestMeasurePestoReadLoad(unittest.TestCase):
    def setUp(self):
        self.assertTrue(TOOL.is_file(), 'Outil introuvable : ' + str(TOOL))
        self.content = TOOL.read_text(encoding='utf-8-sig')
        self.pwsh = find_pwsh()
        if not self.pwsh:
            self.fail('pwsh introuvable : définir PESTO_PWSH (PowerShell 7 portable) pour exécuter ce banc.')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.log = self.dir / 'log'
        self.log.mkdir()
        (self.dir / 'ADStub.psm1').write_text(STUB, encoding='utf-8-sig')

    def run_tool(self, args, report='report.json'):
        script = self.dir / 'driver.ps1'
        script.write_text("$ErrorActionPreference='Stop'\nImport-Module %s\n"
                          "$secure=ConvertTo-SecureString 'valeur-de-test' -AsPlainText -Force\n"
                          "$cred=[pscredential]::new('EXAMPLE\\banc',$secure)\n"
                          "& %s -ConfigPath %s -ReportPath %s %s\nexit $LASTEXITCODE\n" %
                          (ps_quote(self.dir / 'ADStub.psm1'), ps_quote(TOOL), ps_quote(MODEL), ps_quote(self.dir / report), args),
                          encoding='utf-8-sig')
        env = dict(os.environ, PESTO_READLOAD_LOG=str(self.log))
        result = subprocess.run([self.pwsh, '-NoProfile', '-NonInteractive', '-File', str(script)],
                                capture_output=True, text=True, encoding='utf-8', timeout=120, env=env)
        calls = [json.loads(p.read_text(encoding='utf-8-sig')) for p in self.log.glob('*.json')]
        return result, calls

    def test_static_guards(self):
        self.assertNotIn('PrimaryDC', self.content)
        self.assertIn('Get-ADDomainController -Discover -DomainName $domain', self.content)
        self.assertNotIn('SemaphoreSlim', self.content)
        self.assertIn('[runspacefactory]::CreateRunspacePool(1, $level', self.content)
        self.assertIn('[IO.FileMode]::CreateNew', self.content)
        self.assertNotIn('Out-File', self.content)
        self.assertIn('if ($totalRequests -gt 1000)', self.content)
        self.assertIn('if ($PaceMs -lt 50)', self.content)
        for cmd in ('Set-ADComputer', 'New-ADComputer', 'Remove-ADComputer', 'Move-ADObject', 'Set-ADOrganizationalUnit', 'Rename-ADObject'):
            self.assertNotIn(cmd, self.content)

    def test_plan_only_reads_nothing_and_writes_no_report(self):
        result, calls = self.run_tool('-Concurrency 1,2 -RequestsPerLevel 3 -PaceMs 50')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual([c['Command'] for c in calls], ['Get-ADDomainController'])
        self.assertEqual(calls[0]['DomainName'], 'EXAMPLE.LOCAL')
        self.assertEqual(calls[0]['Service'], '')
        self.assertFalse((self.dir / 'report.json').exists())
        self.assertIn('PLAN SEULEMENT', result.stdout)

    def test_execute_more_requests_than_level_on_discovered_dc(self):
        # RequestsPerLevel (5) > niveau (1) : l'ancien sémaphore bloquait au deuxième Wait().
        result, calls = self.run_tool('-Concurrency 1,3 -RequestsPerLevel 5 -PaceMs 50 -Execute -Credential $cred')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        report = json.loads((self.dir / 'report.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(report['Verdict'], 'MEASURED_ONLY')
        self.assertEqual(report['DC'], 'dc2.example.local')
        self.assertEqual(report['RootDN'], 'DC=EXAMPLE,DC=LOCAL')
        self.assertEqual(report['ScanBase'], 'OU=Postes,OU=Organisme,DC=example,DC=local')
        self.assertEqual([lvl['Level'] for lvl in report['Levels']], [1, 3])
        for lvl in report['Levels']:
            self.assertEqual(lvl['Requests'], 5)
            self.assertEqual(lvl['Successes'], 5, json.dumps(lvl['Results']))
        reads = [c for c in calls if c['Command'] != 'Get-ADDomainController']
        self.assertEqual(len(reads), 1 + 10)  # échantillon initial + 2 niveaux x 5
        for call in reads:
            self.assertEqual(call['Server'], 'dc2.example.local')
            self.assertEqual(call['User'], 'EXAMPLE\\banc')
        self.assertEqual({c['SearchBase'] for c in reads if c['Command'] == 'Get-ADOrganizationalUnit'}, {'DC=EXAMPLE,DC=LOCAL'})
        self.assertIn('OU=Postes,OU=Organisme,DC=example,DC=local',
                      {c['SearchBase'] for c in reads if c['Command'] == 'Get-ADComputer'})
        self.assertIn('Identity', {r['Class'] for lvl in report['Levels'] for r in lvl['Results']})

    def test_existing_report_is_never_overwritten(self):
        report = self.dir / 'report.json'
        report.write_text('garder', encoding='utf-8')
        result, calls = self.run_tool('-Concurrency 1 -RequestsPerLevel 1 -PaceMs 50 -Execute')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(report.read_text(encoding='utf-8'), 'garder')
        self.assertEqual(calls, [])

    def test_limits_are_refused_before_any_read(self):
        for args in ('-Concurrency 9 -RequestsPerLevel 1 -PaceMs 50', '-Concurrency 1 -RequestsPerLevel 1 -PaceMs 10',
                     '-Concurrency 1,2,3,4,5,6 -RequestsPerLevel 200 -PaceMs 50'):
            result, calls = self.run_tool(args + ' -Execute')
            self.assertNotEqual(result.returncode, 0, args)
            self.assertEqual(calls, [], args)


if __name__ == '__main__':
    unittest.main()
