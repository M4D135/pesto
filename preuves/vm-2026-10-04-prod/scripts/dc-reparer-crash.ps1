$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$cmd=@'
$ErrorActionPreference='Stop'
Import-Module ActiveDirectory
$root='OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local'
$guid=[Guid]'8b54de3a-a68c-4662-a8d4-742d29bc5dff'
$pc=Get-ADComputer -Identity $guid -Properties ProtectedFromAccidentalDeletion
if($pc.Name -ne 'V999004AAQA1997' -or $pc.ProtectedFromAccidentalDeletion -or $pc.DistinguishedName -notlike '*,OU=ALPHA-AA,OU=Computers,OU=Pesto-20261004,*'){throw 'Fixture crash differente'}
$before=$pc|Select Name,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion
Move-ADObject -Identity $guid -TargetPath 'OU=BETA-BB,OU=Computers,OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local'
Set-ADObject -Identity $guid -ProtectedFromAccidentalDeletion $true
$after=Get-ADComputer -Identity $guid -Properties ProtectedFromAccidentalDeletion
[pscustomobject]@{Date=(Get-Date -Format o);Purpose='Reparation explicite de la seule fixture apres crash controle; atteindre le plan puis verifier le recu';Before=$before;After=($after|Select Name,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion)}|ConvertTo-Json -Depth 4
'@
& C:\ADCC-Lab\scripts\Invoke-LabGuest.ps1 -VM LABO-DC01 -User Administrateur -Domain LABO -Command $cmd -TimeoutMs 60000
