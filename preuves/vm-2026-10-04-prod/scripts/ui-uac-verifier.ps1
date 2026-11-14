$ErrorActionPreference='Stop'
. C:\PestoTest-run\ui-common.ps1
try{
 $w=Wait-Fenetre '^Pesto 1\.0 \| Gestion des Postes$' 25
 if(-not $w){throw 'Pesto absent'}
 $before=Get-Content "$D\uac-histories-avant.json" -Raw -Encoding UTF8|ConvertFrom-Json
 $after=@(foreach($i in $before){$hash=(Get-FileHash $i.Path).Hash;if($hash -ne $i.Hash){throw 'Historique original modifié'};[pscustomobject]@{Profile=$i.Profile;Path=$i.Path;Hash=$hash}})
 $archive=Join-Path (Split-Path $before[1].Path) ('history-imported-'+$before[0].Hash+'.json')
 if((Get-FileHash $archive).Hash -ne $before[0].Hash){throw 'Archive non identique'}
 $launch=Get-Content "$D\lancement-SSO.json" -Raw|ConvertFrom-Json
 if($launch.Admin -ne $false -or $launch.User -notlike '*\PestoProd'){throw 'Lanceur pas standard'}
 $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$w.Current.ProcessId)
 $owner=Invoke-CimMethod -InputObject $p -MethodName GetOwner
 if($owner.Domain -ne 'LABO' -or $owner.User -ne 'pesto-qualif'){throw 'Moteur hors identité UAC'}
 Add-Type 'using System;using System.Runtime.InteropServices;public static class TokenProbe{[DllImport("kernel32.dll",SetLastError=true)]public static extern IntPtr OpenProcess(uint a,bool b,int p);[DllImport("advapi32.dll",SetLastError=true)]public static extern bool OpenProcessToken(IntPtr h,uint a,out IntPtr t);[DllImport("advapi32.dll",SetLastError=true)]public static extern bool GetTokenInformation(IntPtr t,int c,out int b,int n,out int r);[DllImport("kernel32.dll")]public static extern bool CloseHandle(IntPtr h);}'
 $handle=[TokenProbe]::OpenProcess(0x1000,$false,$w.Current.ProcessId);$token=[IntPtr]::Zero;$elevated=0;$len=0
 try{if(-not[TokenProbe]::OpenProcessToken($handle,8,[ref]$token)){throw 'Jeton inaccessible'};if(-not[TokenProbe]::GetTokenInformation($token,20,[ref]$elevated,4,[ref]$len) -or $elevated -ne 1){throw 'Moteur non élevé'}}finally{if($token -ne [IntPtr]::Zero){[TokenProbe]::CloseHandle($token)|Out-Null};if($handle -ne [IntPtr]::Zero){[TokenProbe]::CloseHandle($handle)|Out-Null}}
 Get-Arbre $w 8|Out-File "$D\uac-deux-comptes-valide-arbre.txt" -Encoding UTF8 -Width 240
 Save-Ecran "$D\uac-deux-comptes-valide.png"|Out-Null
 [pscustomobject]@{Date=(Get-Date -Format o);Launch=$launch;ConsoleUser=(Get-CimInstance Win32_ComputerSystem).UserName;EnginePID=$w.Current.ProcessId;EngineOwner=($owner.Domain+'\'+$owner.User);EngineElevated=($elevated -eq 1);OriginalHistoriesUnchanged=$true;Originals=$after;Archive=$archive;ArchiveSHA256=(Get-FileHash $archive).Hash;ExeSHA256=(Get-FileHash 'C:\Program Files\Pesto-Qualification\Pesto.exe').Hash}|ConvertTo-Json -Depth 6|Set-Content "$D\uac-deux-comptes-valide.json" -Encoding UTF8
}catch{$_|Out-String|Set-Content "$D\uac-deux-comptes-erreur.txt" -Encoding UTF8;exit 1}
