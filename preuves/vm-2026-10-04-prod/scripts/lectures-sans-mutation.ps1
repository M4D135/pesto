$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
$root=Get-PestoInterventionRoot
$before=@(Get-ChildItem $root -File|Get-FileHash|Select Path,Hash)
$pc=Get-ADComputer -Identity '568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b' -Server $script:DC -Credential $script:cred
$r=RenameComputer -Computername $pc.Name -NewName $pc.Name
Assert-Lab ($r.ExitCode -eq 96) 'Renommage identique non refuse'
$req=New-LabMoveRequest $pc ('OU=ALPHA-AA,OU=Computers,'+$script:OU.ROOT)
$req.ReadOnly=$true
$readonly=& $script:PestoQueueWorker $req (Get-PestoWorkerCoreSource)
Assert-Lab ($readonly.Action.ExitCode -eq 96 -and $readonly.Action.ExitMsg -match 'Consultation') 'Garde consultation incorrecte'
$script:PestoReadOnly=$true
$refusal='';try{Confirm-PestoInterventionObservation -OperationId 'b926eef384a04956bfc93e7952dc1a32' -Observation $null}catch{$refusal=$_.Exception.Message}
Assert-Lab ($refusal -match 'Consultation') 'Consignation non refusee'
$after=@(Get-ChildItem $root -File|Get-FileHash|Select Path,Hash)
Assert-Lab (($before|ConvertTo-Json -Compress) -ceq ($after|ConvertTo-Json -Compress)) 'Recus modifies'
$adAfter=Get-ADComputer -Identity $pc.ObjectGUID -Server $script:DC -Credential $script:cred
Assert-Lab ($adAfter.DistinguishedName -eq $pc.DistinguishedName) 'AD modifie'
Save-LabResult 'lecture-seule-et-nom-identique' ([pscustomobject]@{Date=(Get-Date -Format o);SameName=$r;ReadOnlyWorker=$readonly;ReadOnlyObservationRefusal=$refusal;ReceiptsBefore=$before;ReceiptsAfter=$after;ADBefore=($pc|Select Name,ObjectGUID,DistinguishedName);ADAfter=($adAfter|Select Name,ObjectGUID,DistinguishedName)})
'PASS : nom identique96, mutation consultation96, consignation refusee, recus et AD inchanges'
