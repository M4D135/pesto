$ProgressPreference='SilentlyContinue';$ErrorActionPreference='Stop'
$cmd=@'
$ErrorActionPreference='Stop'
Import-Module ActiveDirectory
$root='OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local'
$o=Get-ADOrganizationalUnit $root
if($o.ObjectGUID.ToString() -ne 'ad13eeac-026c-4085-a943-fad052cbaa2b'){throw 'OU différente'}
$all=@(Get-ADObject -SearchBase $root -SearchScope Subtree -Filter * -Properties ProtectedFromAccidentalDeletion,objectSid)
if($all.Count -gt 20 -or $all.Count -lt 7){throw 'Inventaire de recette inattendu'}
$known=@('ad13eeac-026c-4085-a943-fad052cbaa2b','19a13d79-5fd6-4b19-b09e-10914c3e122c','3c82021c-2ddc-4685-8e89-d531293aa31b','f763143d-d1bc-442f-ab6b-e09dade74523','02826a0f-e401-4934-850a-c9872a33b4ce','75e2833e-ede5-4d1c-8e36-fd1c17778b35','7db6db0b-5177-4836-8ab6-779eb201954f','568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b','8b54de3a-a68c-4662-a8d4-742d29bc5dff')
foreach($a in $all){
 if($a.objectSid.Value -eq 'S-1-5-21-2348118763-2306653211-1344436245-1158'){continue}
 if($a.ObjectGUID.ToString() -notin $known){throw ('Objet non attribué à cette recette : '+$a.Name+' / '+$a.ObjectGUID)}
}
$inventory=@($all|Select-Object Name,ObjectClass,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion)
foreach($a in $all){if($a.ProtectedFromAccidentalDeletion){Set-ADObject $a.ObjectGUID -ProtectedFromAccidentalDeletion $false}}
Remove-ADOrganizationalUnit $o.ObjectGUID -Recursive -Confirm:$false
$left=@(Get-ADOrganizationalUnit -LDAPFilter '(ou=Pesto-20261004)' -SearchBase 'OU=ADCC-Lab,DC=labo,DC=local' -SearchScope OneLevel)
$account=@(Get-ADUser -Filter 'SamAccountName -eq "pesto-qualif"')
if($left.Count -or $account.Count){throw 'Nettoyage incomplet'}
[pscustomobject]@{Date=(Get-Date -Format o);Scope=$root;Inventory=$inventory;RemovedCount=$inventory.Count;RootAbsent=$true;AccountAbsent=$true;ScopeRestrictedByGuids=$true}|ConvertTo-Json -Depth 5
'@
& C:\ADCC-Lab\scripts\Invoke-LabGuest.ps1 -VM LABO-DC01 -User Administrateur -Domain LABO -Command $cmd -TimeoutMs 60000
if($LASTEXITCODE -ne 0){throw 'Nettoyage AD non confirmé'}
Remove-Item -LiteralPath 'C:\ADCC-Lab\private\pesto-qualif-20261004.txt'
$own='C:\ADCC-Lab\scripts\pesto-recette-8c74c05-autre-pc.ps1'
if(Test-Path $own){Remove-Item -LiteralPath $own}
'Fichier secret temporaire et script de test autre PC supprimés sur hôte.'
