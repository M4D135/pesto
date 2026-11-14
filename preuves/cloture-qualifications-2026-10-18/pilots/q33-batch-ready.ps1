. 'C:\PestoQual_20261018\pilot\commun.ps1'
$w=Get-Pesto;Set-Premier $w;Click-Id $w 'NavBatch'
$pilot=(Find-Id $w 'QueuePilot').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern);if($pilot.Current.ToggleState -eq 'On'){throw 'Pilot mode must remain off for the manual stop test'}
$confirm=(Find-Id $w 'ChkConfirm').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern);if($confirm.Current.ToggleState -eq 'On'){throw 'Per-row confirmation unexpectedly on'}
Click-Id $w 'BtnPreflight';Start-Sleep 15
$status=(Find-Id $w 'LblQueueActivity').Current.Name;$status
if($status -notmatch '2 ligne\(s\), 0 blocage\(s\), 0 avertissement'){throw 'Preflight is not ready'}
Click-Id $w 'BtnRun';Start-Sleep 2
(Find-Id $w 'PanelBody').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value|Set-Content "$D\q33-confirmation.txt" -Encoding UTF8
Save-Vue $w 'q33-confirmation'
