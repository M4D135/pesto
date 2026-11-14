. 'C:\PestoQual_20261018\pilot\commun.ps1'
. "$R\pilot\gui-input.ps1"
$w=Get-Pesto;Set-Premier $w
$tabs=(Find-Id $w 'SetTabs').FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
(@($tabs|Where-Object {$_.Current.Name -eq 'Politique'})[0]).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
Fill-Id $w 'SetTxtMaxBatch' '201';Click-Id $w 'SetBtnSave';Start-Sleep 2
[Windows.Forms.SendKeys]::SendWait('+{TAB}');Start-Sleep 1
[Windows.Forms.SendKeys]::SendWait('+{TAB}');Start-Sleep 8
Get-Focus|ConvertTo-Json|Set-Content "$D\q28-error-focus.json" -Encoding UTF8
