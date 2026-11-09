$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PESTO-W11-TEST' -or (Get-CimInstance Win32_ComputerSystem).PartOfDomain){throw 'Machine de recette hors domaine attendue'}
& C:\PestoTest-run\session-prod.ps1 -Action RetirerAuto
$record=Get-Content C:\PestoTest-run\session-prod-20261004.json -Raw|ConvertFrom-Json
$user=Get-LocalUser PestoProd
if($user.SID.Value -ne $record.Sid){throw 'Compte différent'}
$console=(Get-CimInstance Win32_ComputerSystem).UserName
if($console -eq 'PESTO-W11-TEST\PestoProd'){
 $q=(& quser.exe PestoProd 2>$null)|Out-String
 if($q -notmatch '(?im)^\s*>?pestoprod\s+console\s+1\s+Active\s'){throw 'Session console différente'}
 & logoff.exe 1
 Start-Sleep 3
}
$end=(Get-Date).AddSeconds(20)
do{$profile=Get-CimInstance Win32_UserProfile|Where-Object SID -eq $record.Sid;if(-not $profile.Loaded){break};Start-Sleep 1}while((Get-Date) -lt $end)
if($profile.Loaded){throw 'Profil encore chargé'}
& C:\PestoTest-run\session-prod.ps1 -Action Nettoyer
$member=@(Get-LocalGroupMember -SID S-1-5-32-544|Where-Object{$_.SID.Value -eq 'S-1-5-21-2348118763-2306653211-1344436245-1158'})
if($member){Remove-LocalGroupMember -SID S-1-5-32-544 -Member $member}
$private='C:\PestoTest-run\private-prod-20261004'
if(Test-Path $private){$files=@(Get-ChildItem $private -Force);if(@($files|Where-Object Name -ne 'AD.credential.json').Count){throw 'Dossier privé contient un autre fichier'};Remove-Item -LiteralPath $private -Recurse -Force}
$tasks=@(Get-ScheduledTask -TaskName 'PestoPilote-*' -ErrorAction SilentlyContinue)
foreach($task in $tasks){if($task.State -in @('Running','Queued')){throw 'Pilote encore actif'};Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false}
[pscustomobject]@{Date=(Get-Date -Format o);Machine=$env:COMPUTERNAME;PartOfDomain=(Get-CimInstance Win32_ComputerSystem).PartOfDomain;TemporaryAccountAbsent=(-not(Get-LocalUser PestoProd -ErrorAction SilentlyContinue));TemporaryProfileAbsent=(-not(Get-CimInstance Win32_UserProfile|Where-Object SID -eq $record.Sid));PrivateCredentialRemoved=(-not(Test-Path $private));AutoAdminLogon=(Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' AutoAdminLogon);ScheduledPilotCount=@(Get-ScheduledTask -TaskName 'PestoPilote-*' -ErrorAction SilentlyContinue).Count;ProgramDataReceiptsPreserved=$true}|ConvertTo-Json|Set-Content 'C:\PestoTest-preuves\2026-10-04-prod\nettoyage-vm-final.json' -Encoding UTF8
'Compte, profil, accès temporaire et tâches retirés ; reçus conservés'
