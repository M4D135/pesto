$ErrorActionPreference='Stop'
Import-Module C:\PestoTest-run\pilote.psm1
try {
$w=Wait-Fenetre '^Settings$|^Paramètres$' 15
$c=$w.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'SystemSettings_Display_Scaling_ItemSizeOverride_ComboBox')))
$p=$c.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
$p.Expand()
Start-Sleep 2
Get-Arbre $w 11 | Out-File C:\PestoTest-preuves\2026-10-04-final\dpi-options.txt -Encoding utf8 -Width 220

} catch { $_ | Format-List * -Force | Out-File C:\PestoTest-preuves\2026-10-04-final\dpi-erreur.txt -Encoding utf8; throw }
