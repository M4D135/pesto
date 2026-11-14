$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
$local=Get-PestoJoinLocalStatus
Assert-Lab (-not $local.PartOfDomain -and -not $local.PendingRename -and $local.Admin) 'Ce test exige le retour hors domaine réel'
$req=New-LabJoinRequest ('OU=ALPHA-AA,OU=Computers,'+$script:OU.ROOT) 'V999004AAQA1006'
$preflight=Get-PestoJoinPreflight $req
Assert-Lab $preflight.Valid 'Précontrôle réel invalide'
$req|Add-Member ConfirmedTargetOUGuid $preflight.TargetOUGuid
$req|Add-Member ConfirmedExistingGuid ([string]$preflight.ExistingGuid)
$req|Add-Member ConfirmedMachineId $preflight.Local.MachineId
$script:PestoQueueMonitor=$req.Monitor
$script:LabOriginalInitialJoin=${function:Set-PestoInitialJoinObservation}
function Set-PestoInitialJoinObservation {
 param($Local,[string]$ExistingGuid)
 & $script:LabOriginalInitialJoin -Local $Local -ExistingGuid $ExistingGuid
 throw 'Recette : préparation interrompue après persistance, avant toute commande Windows.'
}
$before=Get-PestoJoinLocalStatus
$adBefore=@(Get-ADComputer -Filter * -SearchBase $script:OU.ROOT -Server $script:DC -Credential $script:cred|Select-Object Name,ObjectGUID,DistinguishedName)
$errorText=''
try{Invoke-PestoJoinExecute -Request $req|Out-Null;throw 'Échec de recette non déclenché'}catch{$errorText=$_.Exception.Message}
$receipt=Read-PestoJoinReceipt $req.StatePath
$central=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($req.OperationId+'.json'))
$after=Get-PestoJoinLocalStatus
$adAfter=@(Get-ADComputer -Filter * -SearchBase $script:OU.ROOT -Server $script:DC -Credential $script:cred|Select-Object Name,ObjectGUID,DistinguishedName)
$again=New-LabJoinRequest ('OU=ALPHA-AA,OU=Computers,'+$script:OU.ROOT) 'V999004AAQA1006'
$retry=Get-PestoJoinPreflight $again
$sameAD=($adBefore|ConvertTo-Json -Compress) -ceq ($adAfter|ConvertTo-Json -Compress)
Save-LabResult 'jonction-echec-preparation-reelle' ([pscustomobject]@{Date=(Get-Date -Format o);FaultInjection='Exception ajoutée après la photographie initiale persistée. Registre, Windows, AD et reçus réels ; aucune commande système remplacée.';Error=$errorText;LocalBefore=$before;LocalAfter=$after;JoinReceipt=$receipt;Central=$central;MonitorMutationStarted=$req.Monitor.MutationStarted;RetryPreflightValid=$retry.Valid;ADUnchanged=$sameAD;ExeSHA256=(Get-FileHash (Join-Path $LabRoot 'Pesto.exe')).Hash})
Assert-Lab ($receipt.Phase -eq 'Failed' -and $central.Phase -eq 'Failed' -and $central.ResultCode -eq 96 -and -not $req.Monitor.MutationStarted -and -not $after.PartOfDomain -and -not $after.PendingRename -and $retry.Valid -and $sameAD) 'Préparation non close correctement'
'PASS : reçu Failed, intervention Failed96, aucune jonction, nouveau précontrôle permis'
