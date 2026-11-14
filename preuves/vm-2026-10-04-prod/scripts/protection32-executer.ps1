$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
$pc=Get-ADComputer -Identity 'V999004AAQA1997' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
Assert-Lab ($pc.DistinguishedName -like ('*,OU=BETA-BB,OU=Computers,'+$script:OU.ROOT) -and $pc.ProtectedFromAccidentalDeletion) 'Fixture protection incorrecte'
$req=New-LabMoveRequest $pc ('OU=ALPHA-AA,OU=Computers,'+$script:OU.ROOT)
$result=& $script:PestoQueueWorker $req (Get-PestoWorkerCoreSource)
$r=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($req.OperationId+'.json'))
$after=Get-ADComputer -Identity $pc.ObjectGUID -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
Save-LabResult 'protection32-execution' ([pscustomobject]@{Date=(Get-Date -Format o);Result=$result;Receipt=$r;AD=($after|Select Name,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion)})
Assert-Lab ($result.Action.ExitCode -eq 32) ('Code obtenu '+$result.Action.ExitCode+' : '+$result.Action.ExitMsg)
Assert-Lab ($r.Move -eq 'Confirmed' -and $r.InitialProtection -eq $true -and -not $after.ProtectedFromAccidentalDeletion -and $r.Phase -eq 'Uncertain') 'Effet deplacement/protection non conserve'
$result.Action|Select ExitCode,ExitMsg,OperationId|ConvertTo-Json
