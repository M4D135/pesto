$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$cmd=@'
$ErrorActionPreference='Stop'
Import-Module ActiveDirectory
$dn='OU=BETA-BB,OU=Computers,OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local'
$ou=Get-ADOrganizationalUnit -Identity $dn
if($ou.ObjectGUID.ToString() -ne '75e2833e-ede5-4d1c-8e36-fd1c17778b35'){throw 'OU inattendue'}
$sid=[Security.Principal.SecurityIdentifier]::new('S-1-5-21-2348118763-2306653211-1344436245-1158')
$schema=Get-ADObject -SearchBase (Get-ADRootDSE).schemaNamingContext -LDAPFilter '(lDAPDisplayName=computer)' -Properties schemaIDGUID
$guid=[Guid]::new([byte[]]$schema.schemaIDGUID)
$path='AD:\'+$dn;$acl=Get-Acl $path
$rule=[DirectoryServices.ActiveDirectoryAccessRule]::new($sid,[DirectoryServices.ActiveDirectoryRights]::CreateChild,[Security.AccessControl.AccessControlType]::Deny,$guid,[DirectoryServices.ActiveDirectorySecurityInheritance]::None)
$acl.AddAccessRule($rule);Set-Acl $path $acl
[pscustomobject]@{Date=(Get-Date -Format o);OU=$dn;User=$sid.Value;Rule='Deny CreateChild computer, ThisObjectOnly';SchemaGuid=$guid.ToString();Purpose='Recette Pesto de reprise après renommage; retirer après constat'}|ConvertTo-Json
'@
& C:\ADCC-Lab\scripts\Invoke-LabGuest.ps1 -VM LABO-DC01 -User Administrateur -Domain LABO -Command $cmd -TimeoutMs 60000
