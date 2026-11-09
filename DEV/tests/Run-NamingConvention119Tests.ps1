#requires -Version 5.1
# Test de branchement reel : la convention NamingConvention de cfg.json atteint-elle le moteur ?
# Harnais calque sur DEV/tests/Run-ConfigEditor120Tests.ps1 (extraction AST, aucune charge WPF).
# Controle negatif : lancee avec -RepoRoot sur un arbre sans la machinerie ni le branchement
# (5938cde, avant ac9e657), cette suite echoue des le chargement : les cas exercent bien le branchement reel.
param([string]$RepoRoot='')
if(-not $RepoRoot){$RepoRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent}
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Join-Path $RepoRoot 'DEV'
$defs=@{}
foreach($file in @('Pesto-Directory.ps1','Pesto-ConfigEditor.ps1','Pesto-Configuration.ps1','Pesto-Core.ps1','Pesto-Contracts.ps1','Pesto-Operations.ps1','Pesto-Policy.ps1','Pesto-ManagedPolicy.ps1')){
  $t=$null;$e=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e)
  if($e.Count){throw ($file+': '+($e.Message -join '; '))}
  foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}
}
foreach($name in @('Get-PestoDefaultNamingConvention','Get-PestoNamingResolutionNonce','Assert-PestoNamingConvention','Set-PestoActiveNamingConvention','Get-PestoActiveNamingConvention','Get-PestoNamingLayout','Get-PestoNameLength','Get-PestoNameMaximumNumber','ConvertTo-PestoNameParts','New-PestoComputerName','New-PestoNameSeries','Assert-PestoClosedObject','Test-PestoPropertyPresent','ConvertTo-PestoCanonicalValue','Get-PestoStableHash','Get-PestoConfigurationSignature','Test-CfgValid','Read-PestoStartupConfig','Apply-CfgHot','ConvertTo-PestoPolicy','Merge-PestoManagedPolicy','Test-PestoDnsName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoDomainFromDN','Convert-Value-TF')){
  if(-not $defs.ContainsKey($name)){throw ('Fonction introuvable : '+$name)}
  . ([scriptblock]::Create($defs[$name]))
}
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Case {param($Name,[scriptblock]$Test);try{& $Test;$script:results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$script:results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Reject {param([scriptblock]$Test);$blocked=$false;try{& $Test|Out-Null}catch{$blocked=$true};Assert $blocked}
$script:results=[Collections.Generic.List[object]]::new()
$fixture=Get-Content (Join-Path $root 'tools/cfg.modele-complet.json') -Raw -Encoding UTF8|ConvertFrom-Json
. (Join-Path $root 'wad/Pesto-Contracts.ps1')
function New-Cfg {param($Convention)$c=Get-Content (Join-Path $root 'tools/cfg.modele-complet.json') -Raw -Encoding UTF8|ConvertFrom-Json;if($null -ne $Convention -and $Convention.Widths.Prefix){$c.CONF[0].Prefixe='1'*[int]$Convention.Widths.Prefix};if($null -ne $Convention){$c|Add-Member -NotePropertyName NamingConvention -NotePropertyValue $Convention -Force};return $c}
$conv4=[pscustomobject]@{Schema=1;Id='labo4';Tokens=@('Type','Prefix','Site','Service','Number');Widths=@{Prefix=4;Site=2;Service=3;Number=3};Types='PSV'}
# La ruche GPO n'existe pas hors Windows : seule substitution d'environnement, aucune logique concernee.
function Get-PestoManagedPolicy {return [pscustomobject]@{Configured=$false;Values=[pscustomobject]@{}}}
function Show-MsgError {param($Text,[string]$Title='')throw ('UI: '+$Text)}
function Show-MsgWarning {param($Text,[string]$Title='')throw ('UI: '+$Text)}
function Show-MsgInfo {param($Text,[string]$Title='')}
function Add-LogLine {param($Text,$Kind='info')}
function Sync-PestoAppearanceControls {}
function Update-QueueButtons {}
function Update-AddButton {}
function Invalidate-PestoConfigurationPlans {}
$SetLblStatus=New-Object PSObject -Property @{Text=''}

Case 'a1 Sans NamingConvention le moteur reste au format livre' {
  [void](Set-PestoActiveNamingConvention $null)
  $d=Get-PestoActiveNamingConvention
  Assert ($d.Id -eq 'defaut') ('Id='+$d.Id)
  Assert ($d.Widths['Prefix'] -eq 6 -and $d.Widths['Site'] -eq 2 -and $d.Widths['Service'] -eq 3 -and $d.Widths['Number'] -eq 3) ('largeurs modifiees')
  $n=New-PestoComputerName -Type P -Prefix 000001 -Site AA -Service 001 -Number 1
  Assert ($n -ceq 'P000001AA001001') ('nom='+$n)
}
Case 'a2 Le cfg.json modele sans NamingConvention est valide' {
  Assert (@(Test-CfgValid $fixture).Count -eq 0) ('erreurs: '+(@(Test-CfgValid $fixture) -join ' | '))
}
Case 'b1 Une convention valide change la largeur generee' {
  [void](Set-PestoActiveNamingConvention $conv4)
  $c=Get-PestoActiveNamingConvention
  Assert ($c.Id -eq 'labo4' -and $c.Widths['Prefix'] -eq 4) ('Id='+$c.Id)
  $n=New-PestoComputerName -Type V -Prefix 1234 -Site AB -Service X90 -Number 7
  Assert ($n -ceq 'V1234ABX90007') ('nom='+$n)
  $p=ConvertTo-PestoNameParts -Name $n
  Assert ($null -ne $p -and $p.Number -eq 7) ('analyse inverse echouee')
}
Case 'b2 Test-CfgValid accepte la convention valide du cfg.json' {
  $errs=@(Test-CfgValid (New-Cfg $conv4))
  Assert ($errs.Count -eq 0) ('erreurs: '+($errs -join ' | '))
}
Case 'c1 Assert-PestoNamingConvention refuse une convention invalide' {
  Reject {Assert-PestoNamingConvention ([pscustomobject]@{Schema=9})}
  $msg=''
  try{[void](Assert-PestoNamingConvention ([pscustomobject]@{Schema=1;Id='t';Tokens=@('Type');Widths=@{Prefix=6;Site=2;Service=3;Number=3};Types='PSV'}))}catch{$msg=$_.Exception.Message}
  Assert ($msg -match 'jeton') ('message='+$msg)
}
Case 'c2 Test-CfgValid signale la convention invalide sans la valider' {
  $errs=@(Test-CfgValid (New-Cfg ([pscustomobject]@{Schema=9})))
  Assert ($errs.Count -ge 1) 'aucune erreur remontee'
  Assert (@($errs|Where-Object{$_ -like 'NamingConvention : *'}).Count -eq 1) ('erreurs: '+($errs -join ' | '))
}
Case 'c3 Une convention trop longue est refusee (plafond NetBIOS 15)' {
  $errs=@(Test-CfgValid (New-Cfg ([pscustomobject]@{Schema=1;Id='toowide';Tokens=@('Type','Prefix','Site','Service','Number');Widths=@{Prefix=12;Site=4;Service=6;Number=6};Types='PSV'})))
  Assert (@($errs|Where-Object{$_ -match 'plafonn' -and $_ -match '15'}).Count -eq 1) ('erreurs: '+($errs -join ' | '))
}
Case 'd1 Set-PestoActiveNamingConvention $null retablit exactement le defaut' {
  [void](Set-PestoActiveNamingConvention $conv4)
  [void](Set-PestoActiveNamingConvention $null)
  $n=New-PestoComputerName -Type P -Prefix 000001 -Site AA -Service 001 -Number 1
  Assert ($n -ceq 'P000001AA001001') ('nom='+$n)
}
# Redefinition : Show-MsgError enregistreur permet de verifier le refus sans interrompre le test.
function Show-MsgError {param($Text,[string]$Title='')$script:UiErrors.Add([string]$Text)}
function Show-PestoConfigRepair {param($Path,$Text,$Errors)$script:RepairCalls++;return $script:RepairResult}
$script:UiErrors=[Collections.Generic.List[string]]::new()
$script:RepairCalls=0;$script:RepairResult=$null
$tmp=[IO.Directory]::CreateDirectory([IO.Path]::Combine([IO.Path]::GetTempPath(),[Guid]::NewGuid().ToString('N'))).FullName
function Write-CfgFile {param($Cfg)$p=Join-Path $tmp ('cfg-'+[Guid]::NewGuid().ToString('N')+'.json');[IO.File]::WriteAllText($p,($Cfg|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false));return $p}

Case 'e1 Read-PestoStartupConfig branche la convention du cfg.json sur le moteur' {
  [void](Set-PestoActiveNamingConvention $null)
  $p=Write-CfgFile (New-Cfg $conv4)
  $cfg=Read-PestoStartupConfig -Path $p
  Assert ($null -ne $cfg) 'configuration refusee'
  $active=Get-PestoActiveNamingConvention
  Assert ($active.Id -eq 'labo4') ('convention active='+$active.Id)
  $n=New-PestoComputerName -Type V -Prefix 1234 -Site AB -Service X90 -Number 7
  Assert ($n -ceq 'V1234ABX90007') ('nom='+$n)
}
Case 'e2 Read-PestoStartupConfig sans NamingConvention laisse le defaut' {
  [void](Set-PestoActiveNamingConvention $conv4)
  $p=Write-CfgFile (New-Cfg $null)
  [void](Read-PestoStartupConfig -Path $p)
  $active=Get-PestoActiveNamingConvention
  Assert ($active.Id -eq 'defaut') ('convention active='+$active.Id)
  $n=New-PestoComputerName -Type P -Prefix 000001 -Site AA -Service 001 -Number 1
  Assert ($n -ceq 'P000001AA001001') ('nom='+$n)
}
Case 'e3 Une convention invalide ne passe pas par la relecture annulee' {
  [void](Set-PestoActiveNamingConvention $null)
  $script:RepairCalls=0;$script:RepairResult=$null
  $p=Write-CfgFile (New-Cfg ([pscustomobject]@{Schema=9}))
  $cfg=Read-PestoStartupConfig -Path $p
  Assert ($script:RepairCalls -eq 1) ('reparation appelee '+$script:RepairCalls+' fois')
  Assert ($null -eq $cfg) 'configuration invalide retournee'
  Assert ((Get-PestoActiveNamingConvention).Id -eq 'defaut') 'convention invalide appliquee'
}
Case 'e4 La convention reparee est branchee au moteur' {
  [void](Set-PestoActiveNamingConvention $null)
  $script:RepairCalls=0;$script:RepairResult=(New-Cfg $conv4)
  $p=Write-CfgFile (New-Cfg ([pscustomobject]@{Schema=9}))
  [void](Read-PestoStartupConfig -Path $p)
  $script:RepairResult=$null
  Assert ((Get-PestoActiveNamingConvention).Id -eq 'labo4') ('convention active='+(Get-PestoActiveNamingConvention).Id)
}
Case 'f1 Apply-CfgHot branche la convention relue sur le moteur' {
  [void](Set-PestoActiveNamingConvention $null)
  $cfg=New-Cfg $conv4
  $script:JsonFile=Write-CfgFile $cfg
  $script:CFG=($cfg|ConvertTo-Json -Depth 30|ConvertFrom-Json)
  $r=Apply-CfgHot
  Assert ($r -eq $true) ('Apply-CfgHot='+$r+' erreurs: '+($script:UiErrors -join ' | '))
  Assert ((Get-PestoActiveNamingConvention).Id -eq 'labo4') ('convention active='+(Get-PestoActiveNamingConvention).Id)
}
Case 'f2 Apply-CfgHot refuse une convention invalide et ne la branche pas' {
  [void](Set-PestoActiveNamingConvention $null)
  $script:UiErrors.Clear()
  $script:JsonFile=Write-CfgFile (New-Cfg ([pscustomobject]@{Schema=9}))
  $r=Apply-CfgHot
  Assert ($r -eq $false) ('Apply-CfgHot='+$r)
  Assert (@($script:UiErrors|Where-Object{$_ -match 'NamingConvention'}).Count -eq 1) ('UI: '+($script:UiErrors -join ' | '))
  Assert ((Get-PestoActiveNamingConvention).Id -eq 'defaut') 'convention invalide appliquee'
}
Case 'f3 Apply-CfgHot sans NamingConvention retablit le defaut' {
  [void](Set-PestoActiveNamingConvention $conv4)
  $cfg=New-Cfg $null
  $script:JsonFile=Write-CfgFile $cfg
  $script:CFG=($cfg|ConvertTo-Json -Depth 30|ConvertFrom-Json)
  $r=Apply-CfgHot
  Assert ($r -eq $true) ('Apply-CfgHot='+$r)
  $n=New-PestoComputerName -Type P -Prefix 000001 -Site AA -Service 001 -Number 1
  Assert ($n -ceq 'P000001AA001001') ('nom='+$n)
}
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
$failed=@($script:results|Where-Object{-not $_.Passed})
foreach($f in $failed){Write-Output ('ECHEC  '+$f.Name+' :: '+$f.Error)}
foreach($r in $script:results){Write-Output ($(if($r.Passed){'OK     '}else{'ECHEC  '})+$r.Name)}
Write-Output ('NamingConvention119 : {0}/{1} PASS' -f ($script:results.Count-$failed.Count),$script:results.Count)
if($failed.Count){exit 1}
