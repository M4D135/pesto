$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
$pc=Get-ADComputer -Identity '8b54de3a-a68c-4662-a8d4-742d29bc5dff' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
Assert-Lab ($pc.Name -eq 'V999004AAQA1997' -and -not $pc.ProtectedFromAccidentalDeletion -and $pc.DistinguishedName -like '*,OU=BETA-BB,*') 'Fixture non confirmee'
$req=New-LabMoveRequest $pc ('OU=ALPHA-AA,OU=Computers,'+$script:OU.ROOT)
$source=Get-PestoWorkerCoreSource
$source+=@'
$script:LabOriginalEffect=${function:Set-PestoEffect}
function Set-PestoEffect {
 param([string]$Name,$Value)
 & $script:LabOriginalEffect $Name $Value
 if($Name -eq 'Move' -and $Value -eq 'Requested'){
  [IO.File]::WriteAllText('C:\PestoTest-run\reseau-move-ready.txt',[DateTime]::UtcNow.ToString('o'))
  $end=[DateTime]::UtcNow.AddSeconds(90)
  while(-not [IO.File]::Exists('C:\PestoTest-run\reseau-move-continue.txt')){
   if([DateTime]::UtcNow -gt $end){throw 'Pause de recette expiree'}
   Start-Sleep -Milliseconds 200
  }
 }
}
'@
$result=& $script:PestoQueueWorker $req $source
$central=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($req.OperationId+'.json'))
Save-LabResult 'reseau-pendant-move' ([pscustomobject]@{Date=(Get-Date -Format o);FaultInjection='NIC2 deconnectee apres persistance Move Requested, avant vrai appel Move-ADObject';Result=$result;Central=$central})
Assert-Lab ($result.Action.ExitCode -eq 97 -and $central.Phase -eq 'Uncertain' -and $central.Move -eq 'Requested') ('Resultat '+$result.Action.ExitCode+' : '+$result.Action.ExitMsg)
'PASS : appel Move-ADObject sans reseau, resultat97, recu Uncertain, aucune reussite supposee'

