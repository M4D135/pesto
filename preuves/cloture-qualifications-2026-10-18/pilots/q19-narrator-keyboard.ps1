. 'C:\PestoQual_20261018\pilot\commun.ps1'

. "$R\pilot\gui-input.ps1"
$w=Get-Pesto;Set-Premier $w
$notes=[Collections.Generic.List[object]]::new()
function Observe([string]$Action){$e=[Windows.Automation.AutomationElement]::FocusedElement;$notes.Add(@{Action=$Action;Utc=[DateTime]::UtcNow.ToString('o');FocusId=$e.Current.AutomationId;FocusName=$e.Current.Name});Start-Sleep 3}
(Find-Id $w 'NavHome').SetFocus();[Windows.Forms.SendKeys]::SendWait('{ENTER}');Observe 'Enter on Home'
[Windows.Forms.SendKeys]::SendWait('{TAB}');Observe 'Tab'
[Windows.Forms.SendKeys]::SendWait('+{TAB}');Observe 'Shift Tab'
[Windows.Forms.SendKeys]::SendWait('{F6}');Observe 'F6'
[Windows.Forms.SendKeys]::SendWait('+{F6}');Observe 'Shift F6'
Click-Id $w 'NavSettings'
(Find-Id $w 'SetSearchSettings').SetFocus();[Windows.Forms.SendKeys]::SendWait('{ENTER}');Observe 'Enter opens settings search'
[Windows.Forms.SendKeys]::SendWait('{TAB}');Observe 'Tab inside hosted search'
[Windows.Forms.SendKeys]::SendWait('{ESC}');Observe 'Escape closes hosted search and returns focus'
Click-Id $w 'NavRename';(Find-Id $w 'TxtPCName').SetFocus();Observe 'Current computer field'
Click-Id $w 'SuiteRefreshSite';Start-Sleep 15;Observe 'AD refresh final status'
$notes|ConvertTo-Json -Depth 4|Set-Content "$D\q19-keyboard.json" -Encoding UTF8
$notes|ConvertTo-Json -Depth 4
Save-Vue $w 'q19-narrator-keyboard'
