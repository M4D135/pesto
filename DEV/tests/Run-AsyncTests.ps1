#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourcePath='',
    [string]$ReportPath=''
)
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $SourcePath){$SourcePath=Join-Path $PSScriptRoot '..\wad\Pesto-Core.ps1'}
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-async-results.json'}
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    throw 'Tests asynchrones : Windows PowerShell 5.1 x64 requis.'
}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){
    throw 'Un thread STA est requis. Utiliser TEST_ASYNC.cmd ou powershell.exe -NoProfile -STA -File tests\Run-AsyncTests.ps1.'
}
# Important : appel avec &, pas de dot-source. La fixture cree ses fonctions
# dans une portee de script enfant, comme Pesto.ps1 appelle wad\Pesto-Core.ps1.
# Ne jamais dot-sourcer ni executer le corps du moteur reel.
& (Join-Path $PSScriptRoot 'Async-ScopeFixture.ps1') -SourcePath ([IO.Path]::GetFullPath($SourcePath)) -ReportPath ([IO.Path]::GetFullPath($ReportPath))
