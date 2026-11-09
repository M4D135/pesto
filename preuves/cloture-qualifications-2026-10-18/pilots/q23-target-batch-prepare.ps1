. 'C:\PestoQual_20261018\pilot\commun.ps1'
. "$R\pilot\gui-input.ps1"
$all=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
foreach($n in $all){if($n.Current.Name -eq 'Speech recap'){$n.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close()}}
$w=Get-Pesto;Set-Premier $w;Click-Id $w 'NavBatch'
(Find-Id $w 'ActionScroll').GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern).SetScrollPercent(-1,100)
(Find-Id $w 'QueueTools').GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
(Find-Id $w 'ActionScroll').GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern).SetScrollPercent(-1,100)
Click-Id $w 'QueueTabFiles'
$ou='OU=Lyon,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local'
[Windows.Clipboard]::SetText("Nom_du_PC;Nouveau_Nom;OU_Destination;Renommer;Deplacer`r`nP111301VA765158;P111301VA765158;$ou;false;true`r`nV111301VA765542;V111301VA765542;$ou;false;true")
Click-Id $w 'QueueMappedImport'
$list=Find-Id $w 'PanelChoices';$items=$list.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
(@($items|Where-Object {$_.Current.Name -like '*presse-papiers*'})[0]).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
Click-Id $w 'PanelAccept';Start-Sleep 1
Click-Id $w 'Validate';Start-Sleep 1
Click-Id $w 'Apply';Click-Id $w 'PanelAccept';Start-Sleep 1
Click-Id $w 'BtnCheckAll'
$check=Find-Id $w 'ChkConfirm';$toggle=$check.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern);if($toggle.Current.ToggleState -eq 'On'){$toggle.Toggle()}
$pilot=Find-Id $w 'QueuePilot';$toggle=$pilot.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern);if($toggle.Current.ToggleState -eq 'On'){$toggle.Toggle()}
Click-Id $w 'BtnPreflight';Start-Sleep 15
Get-Texte $w|Select-Object -Last 35
Save-Vue $w 'q23-target-batch-preflight'
