param([ValidateSet('100% (Recommended)','125%','150%','200%')][string]$Scale)
$ErrorActionPreference='Stop'
. C:\PestoTest-run\ui-common.ps1
try{
 $settings=Wait-Fenetre '^Settings$' 15
 Select-Combo (ById $settings 'SystemSettings_Display_Scaling_ItemSizeOverride_ComboBox') $Scale
 Start-Sleep 2
 $selection=(ById $settings 'SystemSettings_Display_Scaling_ItemSizeOverride_ComboBox').GetCurrentPattern([Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()
 if($selection.Count -ne 1 -or $selection[0].Current.Name -ne $Scale){throw 'Échelle non appliquée'}
 $w=Wait-Fenetre '^Pesto 1\.0 \| Gestion des Postes$' 15
 if($w){$close=ById $w LedgerClose;if($close -and -not $close.Current.IsOffscreen){Invoke-Element $close|Out-Null;Start-Sleep -Milliseconds 300};$w.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close()}
 $deadline=(Get-Date).AddSeconds(30)
 do{Start-Sleep -Milliseconds 300;$old=@(Get-Process Pesto -ErrorAction SilentlyContinue|Where-Object Path -eq 'C:\Program Files\Pesto-Qualification\Pesto.exe')}while($old.Count -and (Get-Date) -lt $deadline)
 if($old.Count){throw 'Ancien lanceur toujours actif'}
 Start-Process 'C:\Program Files\Pesto-Qualification\Pesto.exe'|Out-Null
 $w=Wait-Fenetre '^Pesto 1\.0 \| Gestion des Postes$' 90
 if(-not $w){throw 'Pesto absent après changement DPI'}
 Start-Sleep 2
 [PNat]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)|Out-Null
 $label='dpi-'+($Scale -replace '\D','')
 Get-Arbre $w 9|Out-File "$D\$label-arbre.txt" -Encoding UTF8 -Width 240
 Save-Ecran "$D\$label.png"|Out-Null
 Add-Type 'using System;using System.Runtime.InteropServices;public class PestoDpi{[DllImport("user32.dll")]public static extern uint GetDpiForWindow(IntPtr h);}'
 [pscustomobject]@{Date=(Get-Date -Format o);RequestedScale=$Scale;SelectedScale=$selection[0].Current.Name;DpiForPesto=[PestoDpi]::GetDpiForWindow([IntPtr]$w.Current.NativeWindowHandle);Bounds=$w.Current.BoundingRectangle.ToString();Screen=[Windows.Forms.SystemInformation]::VirtualScreen.ToString();ExeSHA256=(Get-FileHash 'C:\Program Files\Pesto-Qualification\Pesto.exe').Hash}|ConvertTo-Json|Set-Content "$D\$label.json" -Encoding UTF8
}catch{$_|Out-String|Set-Content "$D\dpi-erreur.txt" -Encoding UTF8;exit 1}
