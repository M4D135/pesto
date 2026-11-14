. 'C:\PestoQual_20261018\pilot\commun.ps1'
$all=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
$w=@($all|Where-Object {$_.Current.Name -eq 'Speech recap'})[0]
$text=(Find-Id $w 'SpeechHistoryTextBox').GetCurrentPattern([Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)
[IO.File]::WriteAllText("$D\q29-error-spoken.txt",$text,[Text.UTF8Encoding]::new($false))
$text -split "`r?`n"|Select-Object -Last 12
$w.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close()
$w=Get-Pesto;Click-Id $w 'PanelCancel';Click-Id $w 'SetBtnReload';Click-Id $w 'PanelAccept';Click-Id $w 'NavBatch'
