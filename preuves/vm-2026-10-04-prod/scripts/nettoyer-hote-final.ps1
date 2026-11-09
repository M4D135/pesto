$ProgressPreference='SilentlyContinue';$ErrorActionPreference='Stop'
$cmd=@'
Import-Module ActiveDirectory
$r=@(Get-ADOrganizationalUnit -LDAPFilter '(ou=Pesto-20261004)' -SearchBase 'OU=ADCC-Lab,DC=labo,DC=local' -SearchScope OneLevel)
$u=@(Get-ADUser -Filter 'SamAccountName -eq "pesto-qualif"')
if($r.Count -or $u.Count){throw 'Objets de recette encore présents'}
[pscustomobject]@{RootAbsent=($r.Count -eq 0);AccountAbsent=($u.Count -eq 0)}|ConvertTo-Json -Compress
'@
$out=(& C:\ADCC-Lab\scripts\Invoke-LabGuest.ps1 -VM LABO-DC01 -User Administrateur -Domain LABO -Command $cmd -TimeoutMs 60000)|Out-String
$match=[regex]::Match($out,'\{"RootAbsent":true,"AccountAbsent":true\}')
if(-not $match.Success){throw ('Lecture finale non confirmée : '+$out)}
$secret='C:\ADCC-Lab\private\pesto-qualif-20261004.txt'
if(Test-Path $secret){Remove-Item -LiteralPath $secret}
$own='C:\ADCC-Lab\scripts\pesto-recette-8c74c05-autre-pc.ps1'
if(Test-Path $own){Remove-Item -LiteralPath $own}
[pscustomobject]@{Date=(Get-Date -Format o);RootAbsent=$true;AccountAbsent=$true;HostSecretRemoved=(-not(Test-Path $secret));OtherPcTestScriptRemoved=(-not(Test-Path $own));DCLeftRunning=$true}|ConvertTo-Json
