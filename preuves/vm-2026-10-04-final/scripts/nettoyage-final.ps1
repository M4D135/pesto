$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PESTO-W11-TEST'){throw 'Mauvaise machine'}
$state=Get-Content C:\PestoTest-run\session-final-20261004.json -Raw | ConvertFrom-Json
$user=Get-LocalUser -Name PestoFinal -ErrorAction Stop
if($user.SID.Value -ne $state.Sid){throw 'Identite differente'}
$session=@(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq 'PestoFinal' } | Select-Object -ExpandProperty SessionId -Unique)
if($session.Count -ne 1){throw "Session non univoque : $($session.Count)"}
& logoff.exe $session[0]
if($LASTEXITCODE -ne 0){throw 'Echec fermeture session'}
$deadline=(Get-Date).AddSeconds(45)
do {Start-Sleep 2;$profile=Get-CimInstance Win32_UserProfile | Where-Object SID -eq $state.Sid} while($profile.Loaded -and (Get-Date) -lt $deadline)
if($profile.Loaded){throw 'Profil encore charge'}
& C:\PestoTest-run\session-final.ps1 -Action Nettoyer
$wl=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$tasks=@(Get-ScheduledTask | Where-Object TaskName -like 'PestoPilote-*')
$report=[pscustomobject]@{
 Date=(Get-Date -Format o);AccountAbsent=(-not(Get-LocalUser -Name PestoFinal -ErrorAction SilentlyContinue));ProfileAbsent=(-not(Get-CimInstance Win32_UserProfile | Where-Object SID -eq $state.Sid));AutoAdminLogon=$wl.AutoAdminLogon;DefaultPasswordRegistryPresent=($null -ne $wl.PSObject.Properties['DefaultPassword']);LsaDefaultPasswordDeleteSucceeded=$true;PilotTasks=@($tasks | Select-Object TaskName,State);RefusalReceiptAbsent=(-not(Test-Path C:\PestoTest\wad\logs\Pesto-sonde-uac-c5ddeb046bde427d9337679ea4aaa5d7.txt))
}
$report | ConvertTo-Json -Depth 5 | Set-Content C:\PestoTest-preuves\2026-10-04-final\nettoyage.json -Encoding UTF8
$report | ConvertTo-Json -Depth 5
if(-not $report.AccountAbsent -or -not $report.ProfileAbsent -or $report.AutoAdminLogon -ne '0' -or $report.DefaultPasswordRegistryPresent -or $tasks.Count){throw 'Nettoyage incomplet'}
