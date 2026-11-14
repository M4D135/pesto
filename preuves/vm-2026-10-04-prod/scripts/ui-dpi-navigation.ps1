$ErrorActionPreference='Stop'
. C:\PestoTest-run\ui-common.ps1
$w=Wait-Fenetre '^Pesto 1\.0 \| Gestion des Postes$' 20
Invoke-Element (ById $w NavRename)|Out-Null
[PNat]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
Get-Arbre $w 10|Out-File "$D\dpi-corrige-navigation-arbre.txt" -Encoding UTF8 -Width 240
