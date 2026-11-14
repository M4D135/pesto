. 'C:\PestoQual_20261018\pilot\commun.ps1'
. "$R\pilot\gui-input.ps1"
$w=Get-Pesto;Click-Id $w 'NavSettings'
$tabs=(Find-Id $w 'SetTabs').FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
(@($tabs|Where-Object {$_.Current.Name -eq 'Politique'})[0]).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
$hash=(Get-FileHash 'C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD\wad\cfg.json').Hash
Fill-Id $w 'SetTxtMaxBatch' '201';(Find-Id $w 'SetTxtMaxBatch').SetFocus();Start-Sleep 4
Click-Id $w 'SetBtnSave';Start-Sleep 4
Get-Texte $w|Select-Object -Last 20
Save-Vue $w 'q25-invalid-limit'
[Windows.Forms.SendKeys]::SendWait('{ESC}');Start-Sleep 1
Click-Id $w 'SetBtnReload';Click-Id $w 'PanelAccept'
@{ConfigUnchanged=((Get-FileHash 'C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD\wad\cfg.json').Hash -ceq $hash);Restored=(Find-Id $w 'SetTxtMaxBatch').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value}|ConvertTo-Json|Set-Content "$D\q25-invalid-verification.json" -Encoding UTF8
Click-Id $w 'NavBatch'
