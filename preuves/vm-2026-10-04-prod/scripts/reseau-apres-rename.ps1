$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
Assert-Lab ($env:COMPUTERNAME -eq 'V999004BBQA1003') 'Nom actif inattendu'
$pc=Get-ADComputer -Identity '568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b' -Server $script:DC -Credential $script:cred
Assert-Lab ($pc.Name -eq $env:COMPUTERNAME) 'Nom AD incoherent'
$req=New-LabMoveRequest $pc ('OU=ALPHA-AA,OU=Computers,'+$script:OU.ROOT)
$req.Rename=$true;$req.NewName='V999004AAQA1004'
$req.PlanFingerprint=Get-PestoPlanFingerprint (New-PestoExecutionPlan $req)
$req|Add-Member -NotePropertyName Plan -NotePropertyValue (New-PestoExecutionPlan $req)
$req|Add-Member -NotePropertyName Version -NotePropertyValue '1.0'
$req|Add-Member -NotePropertyName LocalSource -NotePropertyValue $true
$source=Get-PestoWorkerCoreSource
# Point d'arret de recette dans la telemetrie, APRES le vrai renommage Windows.
# Aucun transport/cmdlet AD ou Windows n'est remplace; le moteur est celui du pack.
$source+=@'
$script:LabOriginalStage=${function:Set-PestoWorkerStage}
function Set-PestoWorkerStage {
 param([string]$Name,[string]$Detail='')
 & $script:LabOriginalStage $Name $Detail
 if($Name -eq 'Renommage confirmé'){
  [IO.File]::WriteAllText('C:\PestoTest-run\reseau-rename-ready.txt',[DateTime]::UtcNow.ToString('o'))
  $end=[DateTime]::UtcNow.AddSeconds(90)
  while(-not [IO.File]::Exists('C:\PestoTest-run\reseau-rename-continue.txt')){
   if([DateTime]::UtcNow -gt $end){throw 'Pause de recette expiree'}
   Start-Sleep -Milliseconds 200
  }
 }
}
'@
$result=& $script:PestoDirectWorker $req $source $script:PestoQueueWorker.ToString() (Get-PestoDirectSupportSource)
# Lecture du resultat uniquement sur disque : le reseau reste coupe jusqu'au retour.
$central=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($req.OperationId+'.json'))
Save-LabResult 'reseau-apres-rename' ([pscustomobject]@{Date=(Get-Date -Format o);FaultInjection='Pause telemetrie apres Rename Confirmed; NIC2 deconnectee avant Wait-ADComputerVisible';Result=$result;Central=$central})
[IO.File]::WriteAllText('C:\PestoTest-run\reseau-rename-done.txt',[string]$result.Action.ExitCode)
Assert-Lab ($result.Action.ExitCode -eq 89 -and $central.Phase -eq 'Partial' -and $central.Rename -eq 'Confirmed' -and $central.Move -eq 'NotRequested') ('Resultat '+$result.Action.ExitCode+' : '+$result.Action.ExitMsg)
'PASS : renommage confirme, coupure avant lecture AD, code89, deplacement non tente'
