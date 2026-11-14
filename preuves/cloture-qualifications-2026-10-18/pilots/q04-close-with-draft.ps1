. 'C:\PestoQual_20261018\pilot\commun.ps1'

. "$R\pilot\gui-input.ps1"
$w=Get-Pesto;Click-Id $w 'NavSettings'
$tabs=(Find-Id $w 'SetTabs').FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
(@($tabs|Where-Object {$_.Current.Name -eq 'Politique'})[0]).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
$field=Find-Id $w 'SetTxtMaxBatch';$original=$field.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
$hash=(Get-FileHash 'C:\PestoQualPersonal_20261018\candidate-fix\PROD\wad\cfg.json').Hash
Fill-Id $w 'SetTxtMaxBatch' '199'
Click-Id $w 'SetBtnConfigPreview'
Start-Sleep 1
$w.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close()
Start-Sleep 2
$result=[ordered]@{Original=$original;Draft=$field.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value;FieldEnabled=$field.Current.IsEnabled;FieldOffscreen=$field.Current.IsOffscreen;PreviewGone=($null -eq (Find-Id $w 'Cancel'));NoDiscard=($null -eq (Find-Id $w 'PanelCancel'));SameProcess=($w.Current.ProcessId -eq 6020);ConfigUnchanged=((Get-FileHash 'C:\PestoQualPersonal_20261018\candidate-fix\PROD\wad\cfg.json').Hash -eq $hash)}
$result|ConvertTo-Json
$result|ConvertTo-Json|Set-Content "$D\q04-close-draft.json" -Encoding UTF8
Save-Vue $w 'q04-close-draft'
