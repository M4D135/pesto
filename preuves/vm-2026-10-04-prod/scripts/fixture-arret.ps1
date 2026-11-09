$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
$pc=Get-ADComputer -Identity '8b54de3a-a68c-4662-a8d4-742d29bc5dff' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
Assert-Lab ($pc.Name -eq 'V999004AAQA1997' -and $pc.ProtectedFromAccidentalDeletion -and $pc.DistinguishedName -like '*,OU=ALPHA-AA,*') 'Fixture non confirmee'
$req=New-LabMoveRequest $pc ('OU=BETA-BB,OU=Computers,'+$script:OU.ROOT)
$source=Get-PestoWorkerCoreSource
$source+=@'
$script:LabOriginalEffect=${function:Set-PestoEffect}
function Set-PestoEffect {
 param([string]$Name,$Value)
 & $script:LabOriginalEffect $Name $Value
 if($Name -eq 'Move' -and $Value -eq 'Requested'){
  # La protection a deja ete levee reellement. Le deplacement n'est pas encore appele.
  [pscustomobject]@{PID=$PID;OperationId=$script:ActiveIntervention.OperationId;Date=(Get-Date -Format o)}|ConvertTo-Json|Set-Content C:\PestoTest-run\arret-fixture-ready.json -Encoding UTF8
  Start-Sleep -Seconds 120
  throw 'Pause de recette expiree sans arret'
 }
}
'@
& $script:PestoQueueWorker $req $source | Out-Null
