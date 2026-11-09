$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
$p=Get-Content (Join-Path $LabProof 'legacy-fixture-preparation.json') -Raw|ConvertFrom-Json
$sourceHash=(Get-FileHash $p.Source).Hash
Assert-Lab ($sourceHash -eq $p.SHA256) 'Source historique modifiée'
$root=Get-PestoInterventionRoot
$before=@(Get-ChildItem $root -Filter '*.json'|Get-FileHash|Select Path,Hash)
$r=Read-PestoIntervention (Join-Path $root ($p.OperationId+'.json'))
Assert-Lab ($r.Schema -eq 1 -and $r.Phase -eq 'Uncertain' -and $r.ResultCode -eq 97 -and $null -eq $r.InitialProtection) 'Import annonce une réussite ou protection inventée'
$records=@(Get-PestoInterventions)
foreach($schema in @(1,2,3)){Assert-Lab (@($records|Where-Object{$_.Schema -eq $schema}).Count -gt 0) ('Schéma absent '+$schema)}
$after=@(Get-ChildItem $root -Filter '*.json'|Get-FileHash|Select Path,Hash)
Assert-Lab (($before|ConvertTo-Json -Compress) -ceq ($after|ConvertTo-Json -Compress)) 'Lecture modifie les reçus'
$ad=Get-ADComputer -Identity '8b54de3a-a68c-4662-a8d4-742d29bc5dff' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
Assert-Lab ($ad.DistinguishedName -eq $p.AD.DistinguishedName -and $ad.ProtectedFromAccidentalDeletion -eq $p.AD.ProtectedFromAccidentalDeletion) 'Import a modifié AD'
Save-LabResult 'legacy-import-et-schemas' ([pscustomobject]@{Date=(Get-Date -Format o);SyntheticSource=$true;SourceSHA256=$sourceHash;SourceUnchanged=$true;ADUnchanged=$true;Imported=$r;Before=$before;After=$after;Schemas=($records|Group-Object Schema|Select Name,Count)})
'PASS : import incertain, source et AD inchangés ; schémas 1/2/3 lus sans écriture'
