#requires -Version 5.1
[CmdletBinding()]
param([string]$Root='',[string]$ReportDirectory)
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $Root){$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)}
# Tests de fonctions et chemins uniquement. Aucun lancement de Pesto ni demande UAC.
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Tests destinés à Windows PowerShell.'}
$Root=[IO.Path]::GetFullPath($Root)
$startup=Join-Path $Root 'wad\Pesto-Startup.ps1'
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($startup,[ref]$tokens,[ref]$errors)
if($errors.Count){throw (($errors|ForEach-Object{$_.Message}) -join '; ')}
# Le chargement des fonctions doit rester sans effet, même hors Windows/AD dans un aperçu.
. $startup
$checks=[Collections.Generic.List[object]]::new()
function Check {param([string]$Name,[scriptblock]$Body)
 try{& $Body;$checks.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host ('OK '+$Name)}
 catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('KO '+$Name+' : '+$_.Exception.Message)}
}
function Assert {param($Value,[string]$Message='Assertion non satisfaite');if(-not $Value){throw $Message}}
function Reject {param([scriptblock]$Body);$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Assert $failed}
Check 'Import du démarrage : fonctions seulement, aucune ouverture du moteur' {Assert (Get-Command Get-PestoStartupLayout -CommandType Function)}
Check 'Racine retrouvée depuis wad, indépendamment du dossier courant' {
 $old=Get-Location
 try{Set-Location -LiteralPath $env:SystemRoot;$layout=Get-PestoStartupLayout $startup;Assert ($layout.Root -ieq $Root);Assert ($layout.CorePath -ieq (Join-Path $Root 'wad\Pesto-Core.ps1'))}
 finally{Set-Location -LiteralPath $old.Path}
}
Check 'Espaces, apostrophe, crochets et accents conservés comme données' {
 $p="C:\Pesto d'atelier [1] & été\wad\Pesto-Startup.ps1"
 $l=Get-PestoStartupLayout $p
 Assert ($l.Root -ceq "C:\Pesto d'atelier [1] & été")
 Assert ($l.EntryPath -ceq $p)
 Assert ($l.LogDirectory -ceq "C:\Pesto d'atelier [1] & été\wad\logs")
}
Check 'Ancien chemin Pesto.ps1 refusé comme point de démarrage' {Reject {Get-PestoStartupLayout 'C:\Pesto\Pesto.ps1'}}
Check 'Composant placé hors wad refusé' {Reject {Get-PestoStartupLayout 'C:\Pesto\Pesto-Startup.ps1'}}
Check 'Relais UAC : nouveau chemin et paramètres non secrets conservés' {
 $p="C:\Pesto d'atelier [1]\wad\Pesto-Startup.ps1"
 $line=New-PestoStartupArgumentLine -EntryPath $p -ConfigPath 'C:\cfg test.json' -OriginLocalAppData 'C:\Users\Test\AppData\Local' -AppearanceOwnerSid 'S-1-5-21-1-2-3-1001'
 Assert ($line.Contains('"'+$p+'"'))
 Assert ($line.Contains('-ElevatedLaunch'))
 Assert ($line.Contains('-AppearanceOwnerSid'))
 Assert ($line.Contains('-OriginLocalAppData'))
 Assert (-not $line.Contains('-AskCredential'))
 Assert (-not $line.Contains('-Credential'))
}
Check 'Autre compte AD toujours explicite' {
 $line=New-PestoStartupArgumentLine -EntryPath $startup -AskCredential
 Assert ($line.Contains('-AskCredential'))
}
Check 'UAC avant traitement et absence de boucle préservées' {
 Assert ((Get-PestoStartupRoute $false $false $false) -eq 'Elevate')
 Assert ((Get-PestoStartupRoute $false $true $false) -eq 'Run')
 Assert ((Get-PestoStartupRoute $false $false $true) -eq 'Refuse')
 Assert ((Get-PestoStartupRoute $true $false $false) -eq 'Demo')
}
Check 'Écriture du journal uniquement sous wad, sur dossier temporaire' {
 $tmp=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC18-log-'+[Guid]::NewGuid().ToString('N'))
 try{
  [void][IO.Directory]::CreateDirectory((Join-Path $tmp 'wad'))
  Write-PestoStartupLog -Root $tmp -Message 'Essai de journal local, sans action'
  Assert (Test-Path -LiteralPath (Join-Path $tmp 'wad\logs\Pesto-demarrage.log'))
  Assert (-not (Test-Path -LiteralPath (Join-Path $tmp 'Pesto-demarrage.log')))
  Assert (@(Get-ChildItem -LiteralPath $tmp -Force).Count -eq 1)
 }finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
}
$failed=@($checks|Where-Object{-not $_.Passed}).Count
if(-not $ReportDirectory){$ReportDirectory=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-RC18-Layout-'+[Guid]::NewGuid().ToString('N'))}
[void][IO.Directory]::CreateDirectory($ReportDirectory)
$report=Join-Path $ReportDirectory 'startup-layout.json'
[pscustomobject]@{Version='17.0-RC18';Checks=$checks.ToArray();Failed=$failed;WindowsPowerShell=$PSVersionTable.PSVersion.ToString();RealUacExecuted=$false;RealADExecuted=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $report -Encoding UTF8
Write-Host ('Rapport : '+$report)
if($failed){exit 1}else{exit 0}
