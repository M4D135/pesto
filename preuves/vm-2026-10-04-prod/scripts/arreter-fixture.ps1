$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
. C:\PestoTest-run\worker-labo.ps1
$pause=Get-Content C:\PestoTest-run\arret-fixture-ready.json -Raw|ConvertFrom-Json
$process=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$pause.PID)
Assert-Lab ($process.Name -eq 'powershell.exe' -and $process.CommandLine -match '\\fixture-arret\.ps1') 'Processus non confirme'
Stop-Process -Id ([int]$pause.PID) -Force
Start-Sleep 1
$path=Join-Path (Get-PestoInterventionRoot) (([Guid]$pause.OperationId).ToString('N')+'.json')
$r=Read-PestoIntervention $path
$pc=Get-ADComputer -Identity '8b54de3a-a68c-4662-a8d4-742d29bc5dff' -Server $script:DC -Credential $script:cred -Properties ProtectedFromAccidentalDeletion
$hash=(Get-FileHash $path).Hash
$req=New-LabMoveRequest $pc ('OU=BETA-BB,OU=Computers,'+$script:OU.ROOT)
$replay=& $script:PestoQueueWorker $req (Get-PestoWorkerCoreSource)
Save-LabResult 'arret-force-entre-etapes' ([pscustomobject]@{Date=(Get-Date -Format o);StoppedPID=$pause.PID;FaultInjection='Pause apres ecriture Move Requested, protection deja levee, avant appel Move-ADObject; Stop-Process exact';Receipt=$r;AD=($pc|Select Name,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion);Replay=$replay;ReceiptHashBeforeReplay=$hash;ReceiptHashAfterReplay=(Get-FileHash $path).Hash})
Assert-Lab ($r.Phase -eq 'Running' -and $r.Move -eq 'Requested' -and $r.InitialProtection -eq $true -and $r.Protection -eq 'Lowering') 'Recu crash inattendu'
Assert-Lab (-not $pc.ProtectedFromAccidentalDeletion -and $pc.DistinguishedName -like '*,OU=ALPHA-AA,*') 'Effet reel inattendu'
Assert-Lab ($replay.Action.ExitCode -eq 96 -and (Get-FileHash $path).Hash -eq $hash) 'Relance non bloquee'
'PASS : processus arrete entre etapes, effet de protection reel, recu Running conserve, relance96 sans modification'
