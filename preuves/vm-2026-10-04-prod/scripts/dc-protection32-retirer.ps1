$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$cmd=@'
$ErrorActionPreference='Stop'
Import-Module ActiveDirectory
$root='OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local'
$dn='OU=ALPHA-AA,OU=Computers,'+$root
$ou=Get-ADOrganizationalUnit -Identity $dn
if($ou.ObjectGUID.ToString() -ne '02826a0f-e401-4934-850a-c9872a33b4ce'){throw 'OU inattendue'}
$sid=[Security.Principal.SecurityIdentifier]::new('S-1-5-21-2348118763-2306653211-1344436245-1158')
$guid=[Guid]'bf967a86-0de6-11d0-a285-00aa003049e2'
$path='AD:\'+$dn;$acl=Get-Acl $path
$rule=[DirectoryServices.ActiveDirectoryAccessRule]::new($sid,[DirectoryServices.ActiveDirectoryRights]::WriteDacl,[Security.AccessControl.AccessControlType]::Deny,[Guid]::Empty,[DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents,$guid)
$acl.RemoveAccessRuleSpecific($rule);Set-Acl $path $acl
[pscustomobject]@{Date=(Get-Date -Format o);OU=$dn;User=$sid.Value;Rule='Deny WriteDacl retire';Purpose='Recette code32 protection apres deplacement'}|ConvertTo-Json
'@
& C:\ADCC-Lab\scripts\Invoke-LabGuest.ps1 -VM LABO-DC01 -User Administrateur -Domain LABO -Command $cmd -TimeoutMs 60000
