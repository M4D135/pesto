$ErrorActionPreference='Stop'
. C:\PestoTest-run\ui-common.ps1
Add-Type 'using System;using System.Runtime.InteropServices;public class DpiExact{[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);}'
$w=Wait-Fenetre '^Pesto 1\.0 \| Gestion des Postes$' 15
$dpi=[DpiExact]::GetDpiForWindow([IntPtr]$w.Current.NativeWindowHandle)
if($dpi -ne 192){throw "DPI différent : $dpi"}
$buttons=@('LedgerObserve','LedgerProtection','LedgerClose')|ForEach-Object{$b=ById $w $_;if(-not $b -or $b.Current.IsOffscreen){throw "Commande masquée $_"};[pscustomobject]@{Id=$_;Name=$b.Current.Name;Visible=$true}}
Get-Arbre $w 10|Out-File "$D\dpi-200-valide-arbre.txt" -Encoding UTF8 -Width 240
[pscustomobject]@{Date=(Get-Date -Format o);Dpi=$dpi;ExpectedDpi=192;Commands=$buttons;WindowPid=$w.Current.ProcessId;ExeSHA256=(Get-FileHash 'C:\Program Files\Pesto-Qualification\Pesto.exe').Hash}|ConvertTo-Json -Depth 4|Set-Content "$D\dpi-200-valide.json" -Encoding UTF8
Invoke-Element (ById $w LedgerClose)|Out-Null
