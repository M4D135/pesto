param([ValidateSet('Creer','RetirerAuto','Nettoyer')][string]$Action)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PESTO-W11-TEST'){throw 'VM Pesto exclusivement'}
$statePath='C:\PestoTest-run\session-final-20261004.json'
$account='PestoFinal'
$wl='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PestoLsa {
  [StructLayout(LayoutKind.Sequential)] struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
  [StructLayout(LayoutKind.Sequential)] struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
  [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr systemName, ref LSA_OBJECT_ATTRIBUTES attributes, uint access, out IntPtr policy);
  [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr policy, ref LSA_UNICODE_STRING key, IntPtr data);
  [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr policy);
  [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint status);
  static LSA_UNICODE_STRING Text(string s, out IntPtr memory) {
    memory = Marshal.StringToHGlobalUni(s);
    LSA_UNICODE_STRING u = new LSA_UNICODE_STRING();
    u.Buffer = memory; u.Length = (ushort)(s.Length * 2); u.MaximumLength = (ushort)(s.Length * 2 + 2);
    return u;
  }
  public static int Store(string key, string value) {
    LSA_OBJECT_ATTRIBUTES attributes = new LSA_OBJECT_ATTRIBUTES();
    attributes.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
    IntPtr policy;
    uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x000F0FFF, out policy);
    if (status != 0) return LsaNtStatusToWinError(status);
    IntPtr keyMemory = IntPtr.Zero, valueMemory = IntPtr.Zero, data = IntPtr.Zero;
    try {
      LSA_UNICODE_STRING k = Text(key, out keyMemory);
      if (value != null) {
        LSA_UNICODE_STRING v = Text(value, out valueMemory);
        data = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LSA_UNICODE_STRING)));
        Marshal.StructureToPtr(v, data, false);
      }
      return LsaNtStatusToWinError(LsaStorePrivateData(policy, ref k, data));
    } finally {
      LsaClose(policy);
      if (valueMemory != IntPtr.Zero) { for (int i = 0; i < value.Length * 2; i++) Marshal.WriteByte(valueMemory, i, 0); Marshal.FreeHGlobal(valueMemory); }
      if (keyMemory != IntPtr.Zero) Marshal.FreeHGlobal(keyMemory);
      if (data != IntPtr.Zero) Marshal.FreeHGlobal(data);
    }
  }
}
'@

if($Action -eq 'Creer'){
 if(Test-Path $statePath){
  $previous=Get-Content $statePath -Raw | ConvertFrom-Json
  if($previous.Sid -or (Get-LocalUser -Name $account -ErrorAction SilentlyContinue)){throw 'Etat deja present'}
  Move-Item $statePath ($statePath+'.creation-incomplete')
 }
 if(Get-LocalUser -Name $account -ErrorAction SilentlyContinue){throw 'Compte deja present'}
 if((Get-ItemPropertyValue $wl AutoAdminLogon) -ne '0'){throw 'Ouverture auto deja active'}
 $saved=@{}
 foreach($key in @('DefaultUserName','DefaultDomainName','AutoAdminLogon')){
  $item=Get-ItemProperty $wl -Name $key -ErrorAction SilentlyContinue
  $saved[$key]=if($item){[string]$item.$key}else{$null}
 }
 $record=@{Account=$account;Created=(Get-Date -Format o);Registry=$saved;Sid=$null}
 $record | ConvertTo-Json -Depth 4 | Set-Content $statePath -Encoding UTF8
 $bytes=New-Object byte[] 32
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
 $secret=[Convert]::ToBase64String($bytes)+'Aa1!'
 $secure=ConvertTo-SecureString $secret -AsPlainText -Force
 try {
  $user=New-LocalUser -Name $account -Password $secure -Description 'Recette Pesto temporaire 2026-10-04' -AccountExpires (Get-Date).AddDays(1)
  $record.Sid=$user.SID.Value
  $record | ConvertTo-Json -Depth 4 | Set-Content $statePath -Encoding UTF8
  Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $user
  Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $user
  $result=[PestoLsa]::Store('DefaultPassword',$secret)
  if($result -ne 0){throw "LSA code $result"}
  Set-ItemProperty $wl DefaultUserName $account
  Set-ItemProperty $wl DefaultDomainName $env:COMPUTERNAME
  Set-ItemProperty $wl AutoAdminLogon '1'
  $proof='C:\PestoTest-preuves\2026-10-04-final'
  & icacls.exe $proof /grant ('*'+$user.SID.Value+':(OI)(CI)M') | Out-Null
  if($LASTEXITCODE -ne 0){throw 'ACL preuves'}
  'Compte temporaire administrateur pour recette UAC cree ; ouverture auto preparee ; secret non affiche.'
 }finally{$secret=$null;$secure.Dispose();[Array]::Clear($bytes,0,$bytes.Length)}
}else{
 $record=Get-Content $statePath -Raw | ConvertFrom-Json
 if($record.Account -ne $account -or -not $record.Sid){throw 'Etat de compte invalide'}
 Set-ItemProperty $wl AutoAdminLogon '0'
 $result=[PestoLsa]::Store('DefaultPassword',$null)
 if($result -notin @(0,2)){throw "Retrait LSA code $result"}
 foreach($key in @('DefaultUserName','DefaultDomainName','AutoAdminLogon')){
  $value=$record.Registry.$key
  if($null -eq $value){Remove-ItemProperty $wl $key -ErrorAction SilentlyContinue}else{Set-ItemProperty $wl $key $value}
 }
 'Ouverture automatique retiree ; valeurs anterieures restaurees.'
 if($Action -eq 'Nettoyer'){
  $profile=Get-CimInstance Win32_UserProfile | Where-Object SID -eq $record.Sid
  if($profile -and $profile.Loaded){throw 'Fermer la session de test avant nettoyage'}
  $user=Get-LocalUser -Name $account -ErrorAction SilentlyContinue
  if($user -and $user.SID.Value -ne $record.Sid){throw 'Identite du compte changee'}
  if($user){Remove-LocalUser -SID $user.SID}
  if($profile){$profile | Remove-CimInstance}
  & icacls.exe 'C:\PestoTest-preuves\2026-10-04-final' /remove ('*'+$record.Sid) | Out-Null
  'Compte et profil temporaires retires.'
 }
}
