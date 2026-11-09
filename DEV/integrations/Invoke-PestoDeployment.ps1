#requires -Version 5.1
<#
.SYNOPSIS
Adaptateur commun ConfigMgr, PSADT, PDQ, DeployR et premier démarrage SYSTEM.
.DESCRIPTION
L'appelant fournit un PSCredential en mémoire et les métadonnées autorisées.
Aucune lecture globale de variables de task sequence, aucun compte embarqué,
aucun démarrage automatique, aucun redémarrage ni réessai de mutation.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Installation,
    [ValidateSet('ConfigMgr','PSADT','PDQ','DeployR','FirstBoot','Custom')][string]$Orchestrator='Custom',
    [ValidateSet('Inspect','Join','Rename','Move','RenameMove')][string]$Action='Inspect',
    [string]$ConfigPath='',$Credential,[string]$Computer='',[string]$NewName='',[string]$TargetOU='',
    [string]$Type='',[string]$SiteCode='',[string]$ServiceCode='',
    [string]$PlanPath='',[string]$OutPlanPath='',[string]$IdempotencyKey='',
    [string]$Campaign='',[string]$Sequence='',[string]$Stage='',[string]$DeploymentBuild='',
    [switch]$Execute,[switch]$AsJson)
$ErrorActionPreference='Stop';Set-StrictMode -Off
$adapterPhase='Installation';$mutationPossible=$false
try{
    if(-not[IO.Path]::IsPathRooted($Installation)){throw 'Installation doit être un chemin absolu local.'}
    $runtime=Join-Path $Installation 'wad'
    $adapterPhase='CliHost'
    . (Join-Path $runtime 'Pesto-CliHost.ps1')
    Initialize-PestoCliProcess
    $adapterPhase='Integrity'
    . (Join-Path $runtime 'Pesto-Integrity.ps1')
    [void](Test-PestoPackage -Root $Installation)
    $adapterPhase='Engine'
    $engine=Import-Module (Join-Path $runtime 'Pesto.Engine.psd1') -PassThru -ErrorAction Stop
    $command=$engine.ExportedCommands['Invoke-PestoCommand']
    if($null -eq $command){throw 'Point d’’entrée moteur absent.'}
    $adapterPhase='Idempotency'
    if($Execute -and -not $IdempotencyKey){throw 'Une clé idempotente stable de campagne/poste/action est requise par cet adaptateur.'}
    $adapterPhase='FirstBoot'
    if($Orchestrator -eq 'FirstBoot' -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-18'){throw 'Le scénario FirstBoot doit être appelé par SYSTEM.'}
    $metadata=[pscustomobject]@{Campaign=$Campaign;Sequence=$Sequence;Stage=$Stage;DeploymentBuild=$DeploymentBuild;Orchestrator=$Orchestrator}
    $adapterPhase='Command';$mutationPossible=([bool]$Execute -and $Action -ne 'Inspect')
    $result=& $command -RuntimeRoot $runtime -ConfigPath $ConfigPath -Credential $Credential -Action $Action -Computer $Computer -NewName $NewName `
        -TargetOU $TargetOU -Type $Type -SiteCode $SiteCode -ServiceCode $ServiceCode -PlanPath $PlanPath -OutPlanPath $OutPlanPath `
        -IdempotencyKey $IdempotencyKey -Metadata $metadata -Execute:$Execute
    # Une sortie absente, multiple ou mal formée ne doit jamais devenir exit 0.
    if($null -eq $result -or $result -is [array] -or
       ($result.ExitCode -isnot [int] -and $result.ExitCode -isnot [long]) -or
       $result.ExitCode -lt 0 -or $result.ExitCode -gt [int]::MaxValue -or
       [string]::IsNullOrWhiteSpace([string]$result.State) -or
       $result.MutationStarted -isnot [bool]){throw 'Résultat moteur incomplet.'}
}catch{
    # Une exception peut contenir les arguments ou un secret : message fermé, sans texte brut.
    # Après l'appel du moteur en écriture, l'absence de résultat ne prouve pas un refus.
    $messages=@{
        Installation='Installation doit être un chemin absolu local.'
        CliHost='Chargement du lanceur silencieux impossible.'
        Integrity='Intégrité du paquet non confirmée.'
        Engine='Chargement du moteur impossible.'
        Idempotency='Une clé idempotente stable de campagne/poste/action est requise.'
        FirstBoot='Le scénario FirstBoot doit être appelé par SYSTEM.'
        Command='Le moteur n’’a pas retourné de résultat exploitable. Consultez les reçus avant toute reprise.'
    }
    $message=[string]$messages[$adapterPhase];if(-not $message){$message='Échec de l’’adaptateur.'}
    $state='NotStarted';$code=96
    if($mutationPossible){$state='Uncertain';$code=97}
    $result=[pscustomobject]@{Schema=1;Mode=$Action;State=$state;ExitCode=$code;MutationStarted=$mutationPossible;RestartRequired=$false;Message=$message}
}finally{$Credential=$null}
if($AsJson){
    # Avant le chargement du CliHost (refus précoce), même échappement ASCII compatible 5.1 :
    # -replace avec scriptblock exige PowerShell 6.1+, MatchEvaluator fonctionne partout.
    if(Get-Command ConvertTo-PestoCliJson -CommandType Function -ErrorAction SilentlyContinue){ConvertTo-PestoCliJson $result 12}
    else{$json=$result|ConvertTo-Json -Depth 12 -Compress;[regex]::Replace($json,'[^\x00-\x7F]',[Text.RegularExpressions.MatchEvaluator]{param($m) '\u{0:x4}' -f [int][char]$m.Value[0]})}
}else{$result}
exit ([int]$result.ExitCode)
