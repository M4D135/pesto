$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PESTO-W11-TEST' -and $env:COMPUTERNAME -notmatch '^[PSV]999004[A-Z]{2}QA1[0-9]{3}$'){throw 'Machine hors recette Pesto'}
$LabRoot='C:\Program Files\Pesto-Qualification'
$LabProof='C:\PestoTest-preuves\2026-10-04-prod'
. C:\PestoTest-run\acces-labo.ps1
# Les définitions originales sont chargées sans le démarrage interactif du moteur.
# Les cmdlets AD, CIM, registre, jonction et renommage ne sont pas remplacées.
foreach($file in Get-ChildItem (Join-Path $LabRoot 'wad\Pesto-*.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e)
 if($e.Count){throw ('Parseur : '+$file.Name)}
 foreach($node in $ast.EndBlock.Statements){
  if($node -is [Management.Automation.Language.FunctionDefinitionAst]){. ([scriptblock]::Create($node.Extent.Text))}
 }
}
# Listes et scriptblocks des workers réels, identiques aux définitions livrées.
foreach($name in @('Pesto-Core.ps1','Pesto-Join.ps1','Pesto-Direct.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $LabRoot ('wad\'+$name)),[ref]$t,[ref]$e)
 foreach($node in $ast.EndBlock.Statements){
  if($node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -in @('script:PestoWorkerCoreNames','script:PestoWorkerCoreSourceCache','script:PestoQueueWorker','script:PestoJoinWorker','script:PestoDirectWorker')){. ([scriptblock]::Create($node.Extent.Text))}
 }
}
$script:CFG=Get-Content (Join-Path $LabRoot 'wad\cfg.json') -Raw|ConvertFrom-Json
$script:JsonFile=Join-Path $LabRoot 'wad\cfg.json'
if(@(Test-CfgValid $script:CFG).Count){throw 'Configuration de recette invalide'}
$script:DOMAINE=$script:CFG.CONF[0].Domaine
$script:DC='dc01.labo.local'
$script:PREFIXE=$script:CFG.CONF[0].Prefixe
$script:OU=@{};foreach($o in $script:CFG.OUBase){$script:OU[$o.Nom]=$o.OU}
$script:OUV=@{};foreach($o in $script:CFG.OUSite){$script:OUV[$o.Nom]=$o.OU}
if($script:OU.ROOT -ne 'OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local' -or $script:PREFIXE -ne '999004'){throw 'Perimetre hors recette'}
$script:OU_POSTES=$script:OU.ROOT;$script:OU_SCAN=$script:OU.ROOT
$script:cred=Get-PestoLabCredential
$script:GUI=$false;$script:SIM=$false;$script:PestoReadOnly=$false;$script:Pesto_VERSION='1.0'
$script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY
$script:CLEAR_PROTECTION=$true;$script:DSREG_LEAVE=$false
$script:PestoQueueMonitor=New-PestoQueueMonitor -Computer $env:COMPUTERNAME
$BasePath=Join-Path $LabRoot 'wad'
Import-PestoADModule -ADModulePath (Join-Path $BasePath 'ActiveDirectory.psd1')
function New-LabJoinRequest([string]$TargetOU,[string]$NewName,[bool]$AllowExisting=$false){
 $plan=[pscustomobject]@{Computer=$env:COMPUTERNAME;NewName=$NewName;AllowExisting=$AllowExisting;Domain=$script:DOMAINE;DC=$script:DC;TargetOU=$TargetOU;DirectProd=$true;Reference='Recette Pesto 20261004';Account=$script:cred.UserName}
 [pscustomobject]@{Mode='Check';Plan=$plan;Policy=$script:PestoPolicy;ReadOnly=$false;ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);OperationId=[Guid]::NewGuid().ToString('N');Credential=$script:cred;Prefix=$script:PREFIXE;OU=$script:OU;OUSite=$script:OUV;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');StatePath=(Get-PestoJoinStatePath);Monitor=(New-PestoQueueMonitor -Computer $env:COMPUTERNAME)}
}
function Save-LabResult([string]$Name,$Result){$Result|ConvertTo-Json -Depth 12|Set-Content (Join-Path $LabProof ($Name+'.json')) -Encoding UTF8}
function Assert-Lab($Value,[string]$Reason){if(-not $Value){throw $Reason}}
