$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
$j=[Console]::In.ReadToEnd()|ConvertFrom-Json
$bytes=$null;$secure=$null;$sent=$false
try{
 $original='P111301VA765158';$guid=[Guid]'b4797c9c-d790-4797-bf71-424a57acb36e'
 $ou='OU=Paris,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local'
 $cs=Get-CimInstance Win32_ComputerSystem
 $uuid=[string](Get-CimInstance Win32_ComputerSystemProduct).UUID
 $active=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
 $configured=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if($uuid -ine '9b2ad4f0-0506-4f58-aed2-c43ac1973516' -or -not $cs.PartOfDomain -or $cs.Domain -ine 'labo.local' -or [int]$cs.DomainRole -ne 1){throw 'Wrong local identity'}
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or -not (Test-ComputerSecureChannel -ErrorAction Stop)){throw 'Local elevation/channel not confirmed'}
 $recordedRenameMove=[string]$j.currentName -ieq 'P111301LY765715' -and [string]$j.sourceReceiptId -ceq 'receipt-50a635a9b3ee46138c9fc231bcff83af' -and [string]$j.returnMoveReceiptId -match '^receipt-[a-fA-F0-9]{32}$'
 if(([string]$j.currentName -notmatch '^P111301VA765[0-9]{3}$' -and -not $recordedRenameMove) -or [string]$j.currentName -ieq $original -or $active -ine [string]$j.currentName -or $configured -ine $active -or $cs.Name -ine $active){throw 'Name drift or pending rename'}
 if(-not $j.module -or -not $j.credential){throw 'Explicit native credential/module missing'}
 Import-Module -Name ([string]$j.module) -ErrorAction Stop
 Add-Type -AssemblyName System.Security
 $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String([string]$j.credential.blob),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $bytes.Length;$i+=2){$secure.AppendChar([char]([int]$bytes[$i] -bor ([int]$bytes[$i+1] -shl 8)))}
 $secure.MakeReadOnly();$credential=New-Object Management.Automation.PSCredential([string]$j.credential.userName,$secure)
 [Array]::Clear($bytes,0,$bytes.Length);$bytes=$null
 $p=@{Server=[string]$j.server;Credential=$credential}
 $before=Get-ADComputer -Identity $guid -Properties ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion,userAccountControl @p
 if([Guid]$before.ObjectGUID -ne $guid -or [string]$before.Name -ine $active -or [string]$before.DistinguishedName -ine ('CN='+$active+','+$ou) -or [bool]$before.ProtectedFromAccidentalDeletion -or [long]$before.userAccountControl -ne 4096){throw 'AD identity/OU/protection drift'}
 $occupied=@(Get-ADComputer -LDAPFilter '(|(name=P111301VA765158)(sAMAccountName=P111301VA765158$))' -ResultSetSize 2 @p)
 if($occupied.Count -ne 0){throw 'Original name occupied'}
 $sent=$true
 $renamed=Rename-Computer -NewName $original -DomainCredential $credential -Force -PassThru -ErrorAction Stop
 if(-not $renamed.HasSucceeded){throw 'Rename not confirmed'}
 $after=Get-ADComputer -Identity $guid -Properties ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion,userAccountControl @p
 $configuredAfter=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
 $activeAfter=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
 if([Guid]$after.ObjectGUID -ne $guid -or [string]$after.Name -ine $original -or [string]$after.DistinguishedName -ine ('CN='+$original+','+$ou) -or [bool]$after.ProtectedFromAccidentalDeletion -or [long]$after.userAccountControl -ne 4096 -or $configuredAfter -ine $original -or $activeAfter -ine $active){throw 'Post-rename readback incomplete'}
 @{phase='PendingRestart';restartRequired=$true;guid=[string]$after.ObjectGUID;name=[string]$after.Name;dn=[string]$after.DistinguishedName;protected=[bool]$after.ProtectedFromAccidentalDeletion;uac=[long]$after.userAccountControl;activeName=$activeAfter;configuredName=$configuredAfter;utc=[DateTime]::UtcNow.ToString('o');nativeAttempts=1}|ConvertTo-Json -Compress
}catch{
 @{phase=$(if($sent){'Uncertain'}else{'Refused'});restartRequired=$sent;message='Guard, rename or readback did not confirm the intended state. Inspect separately; no replay.';utc=[DateTime]::UtcNow.ToString('o');nativeAttempts=$(if($sent){1}else{0})}|ConvertTo-Json -Compress
}finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)};if($secure){$secure.Dispose()}}
