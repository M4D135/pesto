. 'C:\PestoQual_20261018\pilot\commun.ps1'

. "$R\pilot\gui-input.ps1"
$w=Get-Pesto;Fill-Id $w 'SetTxtMaxBatch' '201'
Click-Id $w 'SetBtnConfigPreview'
Start-Sleep 2
$w.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close()
Start-Sleep 2
@{PreviewGone=($null -eq (Find-Id $w 'Cancel'));NoDiscard=($null -eq (Find-Id $w 'PanelCancel'));Draft=(Find-Id $w 'SetTxtMaxBatch').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value;FieldEnabled=(Find-Id $w 'SetTxtMaxBatch').Current.IsEnabled}|ConvertTo-Json
Get-Texte $w|Select-Object -Last 8
