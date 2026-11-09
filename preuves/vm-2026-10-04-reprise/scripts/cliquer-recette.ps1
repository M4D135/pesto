param([int]$X,[int]$Y,[int]$X2=-1,[int]$Y2=-1)
$ErrorActionPreference='Stop'
Import-Module C:\PestoTest-run\pilote.psm1
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class PClick{[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);}'
function Click([int]$a,[int]$b){[void][PClick]::SetCursorPos($a,$b);[PClick]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[PClick]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
Click $X $Y
Start-Sleep -Seconds 2
if($X2 -ge 0){Click $X2 $Y2;Start-Sleep -Seconds 3}
Save-Ecran C:\PestoTest-preuves\2026-10-04-reprise\bureau-courant.png
