. 'C:\PestoQual_20261018\pilot\commun.ps1'

. "$R\pilot\gui-input.ps1"
$w=Get-Pesto;Set-Premier $w
Click-Id $w 'SetBtnConfigPreview'
Start-Sleep 2
Add-Type 'using System;using System.Runtime.InteropServices;public static class PestoCaptionPointer{[DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);}'
[void][PestoCaptionPointer]::SetThreadDpiAwarenessContext([IntPtr](-4))
# Coordinates observed in the current full-window capture q04 (not inferred from DPI).
[void][PestoCaptionPointer]::SetCursorPos(1683,10)
[PestoMouse]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[PestoMouse]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep 2
$report=[ordered]@{Utc=[DateTime]::UtcNow.ToString('o');Input='Physical mouse caption close at 1683,10';PreviewGone=($null -eq (Find-Id $w 'Cancel'));NoDiscard=($null -eq (Find-Id $w 'PanelCancel'));Draft=(Find-Id $w 'SetTxtMaxBatch').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value;FieldEnabled=(Find-Id $w 'SetTxtMaxBatch').Current.IsEnabled;SameProcess=($w.Current.ProcessId -eq 6020);ExeHash=(Get-FileHash 'C:\PestoQualPersonal_20261018\candidate-fix\PROD\Pesto.exe').Hash}
$report|ConvertTo-Json|Set-Content "$D\q07-close-physical.json" -Encoding UTF8
$report|ConvertTo-Json
Save-Vue $w 'q07-close-physical'
if(-not $report.PreviewGone -or -not $report.NoDiscard -or -not $report.FieldEnabled){throw 'Caption close failed'}
Click-Id $w 'SetBtnReload';if(Find-Id $w 'PanelAccept'){Click-Id $w 'PanelAccept'}
Click-Id $w 'NavHome'
