$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
$normalRoot=Get-PestoInterventionRoot
$normalHashes=@(Get-ChildItem $normalRoot -Filter *.json|Get-FileHash|Select-Object Path,Hash)
$parent=(Get-Content "$LabProof\code89-avant-reprise.json" -Raw|ConvertFrom-Json).Central
Assert-Lab ($parent.OperationId -eq 'e640e9f327cb4adbaaf8c31920c4869f' -and $parent.Phase -eq 'Partial' -and $parent.ResultCode -eq 89) 'Preuve parente inattendue'
$testRoot=Join-Path $LabProof 'late-ledger'
Assert-Lab (-not(Test-Path $testRoot)) 'Banc tardif déjà présent'
[IO.Directory]::CreateDirectory($testRoot)|Out-Null
function Get-PestoInterventionRoot {return 'C:\PestoTest-preuves\2026-10-04-prod\late-ledger'}
Write-PestoIntervention $parent
$guid=[Guid]'568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b'
$pc=Get-ADComputer $guid -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
$alpha='OU=ALPHA-AA,OU=Computers,'+$script:OU.ROOT
$beta='OU=BETA-BB,OU=Computers,'+$script:OU.ROOT
Assert-Lab ($env:COMPUTERNAME -eq 'V999004AAQA1004' -and $pc.Name -eq $env:COMPUTERNAME -and (Get-PestoParentDN $pc.DistinguishedName) -eq $alpha) 'PC de recette non confirmé'
$initialProtection=[bool]$pc.ProtectedFromAccidentalDeletion
$adp=@{Server=$script:DC;Credential=$script:cred;ErrorAction='Stop'}
try{
 if($initialProtection){Set-ADObject $guid -ProtectedFromAccidentalDeletion $false @adp}
 Move-ADObject $guid -TargetPath $beta @adp
 if($initialProtection){Set-ADObject $guid -ProtectedFromAccidentalDeletion $true @adp}
 $observeRequest=[pscustomobject]@{Computer=$env:COMPUTERNAME;AlternativeComputer='';ObjectGuid=$guid.ToString();LocalSource=$true;Domain=$script:DOMAINE;DC=$script:DC;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1')}
 $observation=Get-PestoPostObservation $observeRequest
 $ready=Confirm-PestoInterventionObservation -OperationId $parent.OperationId -Observation $observation
 Assert-Lab ($ready.Phase -eq 'MoveReady') 'Préparation de reprise refusée'
 $parentPath=Join-Path $testRoot ($parent.OperationId+'.json')
 $parentHash=(Get-FileHash $parentPath).Hash
 $pc=Get-ADComputer $guid @adp
 $req=New-LabMoveRequest $pc $alpha
 $req.ResumeId=$parent.OperationId
 $source=Get-PestoWorkerCoreSource
 $source+=@'
$script:LabOriginalComplete=${function:Complete-PestoIntervention}
function Complete-PestoIntervention {
 param($Action,[bool]$TimedOut=$false)
 if($Action.ExitCode -eq 30 -and $script:ActiveIntervention.Move -eq 'Confirmed'){
  # Le retour du vrai déplacement est retenu ; seul le signal de supervision est injecté.
  Start-Sleep -Seconds 3
  $script:PestoQueueMonitor.TimedOut=$true
  $TimedOut=$true
 }
 & $script:LabOriginalComplete -Action $Action -TimedOut $TimedOut
}
'@
 $result=& $script:PestoQueueWorker $req $source
 $child=Read-PestoIntervention (Join-Path $testRoot ($req.OperationId+'.json'))
 $parentAfter=Read-PestoIntervention $parentPath
 $ad=Get-ADComputer $guid -Properties ProtectedFromAccidentalDeletion @adp
 $parentUnchanged=(Get-FileHash $parentPath).Hash -eq $parentHash
 $normalAfter=@(Get-ChildItem $normalRoot -Filter *.json|Get-FileHash|Select-Object Path,Hash)
 $normalUnchanged=($normalHashes|ConvertTo-Json -Compress) -ceq ($normalAfter|ConvertTo-Json -Compress)
 Save-LabResult 'reprise-tardive-integration' ([pscustomobject]@{Date=(Get-Date -Format o);Harness='Copie isolée du reçu réel 89, nouvelle observation Windows/AD, déplacement AD réel ; expiration de supervision injectée au retour confirmé, sans attendre les 300 s de production.';ParentSource='code89-avant-reprise.json / Central';ParentBefore=$ready;ParentAfter=$parentAfter;ParentSHA256=$parentHash;ParentUnchanged=$parentUnchanged;NormalLedgerUnchanged=$normalUnchanged;Result=$result;Child=$child;ADName=$ad.Name;ADGuid=$ad.ObjectGUID.ToString();ADOU=(Get-PestoParentDN $ad.DistinguishedName);ProtectionRestored=($ad.ProtectedFromAccidentalDeletion -eq $initialProtection)})
 Assert-Lab ($result.Action.ExitCode -eq 97 -and $child.Phase -eq 'Uncertain' -and $child.Move -eq 'Confirmed' -and $parentAfter.Phase -eq 'MoveReady' -and $parentUnchanged -and $normalUnchanged) 'Résultat tardif non conservateur'
 'PASS : vrai déplacement confirmé ; enfant incertain97 ; parent et registre normal inchangés'
}finally{
 $actual=Get-ADComputer $guid -Properties ProtectedFromAccidentalDeletion @adp
 if((Get-PestoParentDN $actual.DistinguishedName) -ne $alpha){
  if($actual.ProtectedFromAccidentalDeletion){Set-ADObject $guid -ProtectedFromAccidentalDeletion $false @adp}
  Move-ADObject $guid -TargetPath $alpha @adp
 }
 Set-ADObject $guid -ProtectedFromAccidentalDeletion $initialProtection @adp
 $restored=Get-ADComputer $guid -Properties ProtectedFromAccidentalDeletion @adp
 Assert-Lab ((Get-PestoParentDN $restored.DistinguishedName) -eq $alpha -and $restored.ProtectedFromAccidentalDeletion -eq $initialProtection) 'Restauration labo non confirmée'
}
