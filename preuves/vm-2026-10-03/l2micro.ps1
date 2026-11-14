Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;using Microsoft.Win32.SafeHandles;public static class K{[DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern SafeFileHandle CreateFileW(string p,uint a,uint s,IntPtr sa,uint d,uint f,IntPtr t);}'
$b = 'C:\PC\L2micro'
function Essai([string]$nom, [scriptblock]$ouvrir) {
  if (Test-Path -LiteralPath "$b-x") { Remove-Item -LiteralPath "$b-x" -Recurse -Force }
  if (Test-Path -LiteralPath $b) { Remove-Item -LiteralPath $b -Recurse -Force }
  New-Item -ItemType Directory -Path "$b\wad" -Force | Out-Null; Set-Content -LiteralPath "$b\wad\f.ps1" -Value 'x'
  $h = & $ouvrir
  try { Rename-Item -LiteralPath $b -NewName 'L2micro-x' -ErrorAction Stop; $r = 'RENOMME' ; Rename-Item -LiteralPath "$b-x" -NewName 'L2micro' } catch { $r = 'refuse : ' + $_.Exception.Message }
  foreach ($x in @($h)) { if ($x) { $x.Dispose() } }
  '{0} -> {1}' -f $nom, $r
}
Essai 'aucun handle' { $null }
Essai 'racine acces 0, partage lecture (lanceur 9ee3fe2)' { [K]::CreateFileW($b, 0, 1, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero) }
Essai 'racine FILE_LIST_DIRECTORY, partage 3 (correctif L2)' { [K]::CreateFileW($b, 1, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero) }
Essai 'fichier wad\f.ps1 lecture, partage lecture (composant)' { [K]::CreateFileW("$b\wad\f.ps1", [uint32]2147483648, 1, [IntPtr]::Zero, 3, 0x00200000, [IntPtr]::Zero) }
