# Ouverture de session automatique de labadmin sur PESTO-W11-TEST (VM de test Pesto).
# -Activer : lit le mot de passe sur l'entrée standard (jamais en argument), le range comme secret LSA « DefaultPassword »
#            (méthode de Sysinternals Autologon), sans valeur DefaultPassword en clair dans le registre.
# -Retirer : AutoAdminLogon=0 et suppression du secret.
# -Reinitialiser (avec -Activer) : donne d'abord ce mot de passe au compte local labadmin (cette VM seulement).
# -Compte / -Domaine : autre compte (ex. compte de domaine de recette LABO\tech.pesto pour la démo réelle) ; par défaut
#            labadmin, compte local de ce poste quel que soit son nom.
param([switch]$Activer, [switch]$Retirer, [switch]$Reinitialiser, [string]$Compte = 'labadmin', [string]$Domaine = '')
$ErrorActionPreference = 'Stop'
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
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ($Activer -eq $Retirer) { throw 'Choisir -Activer ou -Retirer.' }
if ($Activer) {
  # Octets bruts de l'entrée standard, décodés en UTF-8 (l'encodage console OEM déformerait é, ç, €...).
  $in = [Console]::OpenStandardInput(); $buf = New-Object System.Collections.Generic.List[byte]
  while (($c = $in.ReadByte()) -ge 0 -and $c -ne 10) { if ($c -ne 13) { $buf.Add([byte]$c) } }
  $mdp = [Text.Encoding]::UTF8.GetString($buf.ToArray()); $buf.Clear()
  if ([string]::IsNullOrEmpty($mdp)) { throw 'Mot de passe vide : rien modifié.' }
  if ($Reinitialiser -and ($Domaine -or $Compte -ne 'labadmin')) { throw '-Reinitialiser ne vaut que pour le compte local labadmin.' }
  if ($Reinitialiser) { Set-LocalUser -Name labadmin -Password (ConvertTo-SecureString $mdp -AsPlainText -Force); 'Mot de passe local de labadmin remplace (PESTO-W11-TEST seulement).' }
  $r = [PestoLsa]::Store('DefaultPassword', $mdp); $mdp = $null
  if ($r -ne 0) { throw ('Secret LSA non enregistré, erreur Windows ' + $r) }
  $dom = if ($Domaine) { $Domaine } else { $env:COMPUTERNAME }
  Set-ItemProperty $wl -Name DefaultUserName -Value $Compte
  Set-ItemProperty $wl -Name DefaultDomainName -Value $dom
  Remove-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue
  Set-ItemProperty $wl -Name AutoAdminLogon -Value '1'
  'AUTOLOGON ACTIF pour ' + $dom + '\' + $Compte + ' (secret LSA). Effet au prochain démarrage.'
} else {
  Set-ItemProperty $wl -Name AutoAdminLogon -Value '0'
  Remove-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue
  $r = [PestoLsa]::Store('DefaultPassword', $null)
  'AUTOLOGON RETIRE (secret LSA : code ' + $r + ', 2 = déjà absent).'
}
