# Recette réelle 1 : renommage sur le même site (Paris) par « Un seul poste ». Comparaison avant/après, annulation à la
# confirmation (aucun changement), puis confirmation réelle. Le redémarrage est demandé séparément (aucun automatique).
. 'C:\PestoFinal_20261014\pilot\commun.ps1'
"avant : $(Get-EtatPoste)"
"reçus avant :"; Get-RecusRecents 2
$w = Start-PestoCopie "$R\gui"; Set-Max $w
Set-Formulaire $w 'Paris'
"nom proposé : $(Get-Valeur $w 'CbName')"
"aperçu : actuel=$(Get-Valeur $w 'UxCurrentName') nouveau=$(Get-Valeur $w 'UxNewName') ; $(Get-Valeur $w 'UxSiteTransition') ; $(Get-Valeur $w 'UxActualTargetOU') ; $(Get-Valeur $w 'UxOperation')"
"bouton principal : $(Get-Valeur $w 'SuiteDirectRun') ; sous le bouton : $(Get-Valeur $w 'SuiteDirectHint')"
Save-Vue $w 'g10-1-formulaire'
# Annulation à la confirmation.
Set-Premier $w; Invoke-Element (Find-Id $w 'SuiteDirectRun') | Out-Null
if (-not (Wait-Panel $w 180)) { Save-Vue $w 'g10-2-sans-confirmation'; throw 'confirmation non affichée' }
Save-Vue $w 'g10-2-confirmation'
"confirmation (1) : $(Get-PanelText $w)"
Click-Id $w 'PanelCancel'; Start-Sleep -Seconds 3
"après annulation : $(Get-EtatPoste) ; message : $(Get-Valeur $w 'SuiteDirectHint')"
"reçus après annulation :"; Get-RecusRecents 2
Save-Vue $w 'g10-3-annule'
# Confirmation réelle.
Set-Premier $w; Invoke-Element (Wait-Enabled $w 'SuiteDirectRun' 120) | Out-Null
if (-not (Wait-Panel $w 180)) { Save-Vue $w 'g10-4-sans-confirmation'; throw 'confirmation non affichée (2)' }
$texte = Get-PanelText $w
"confirmation (2) : $texte"
Save-Vue $w 'g10-4-confirmation'
Click-Id $w 'PanelAccept'
$fin = (Get-Date).AddSeconds(300); while ((Get-Date) -lt $fin -and -not (Find-Id $w 'PanelBody')) { Start-Sleep -Seconds 2 }
Start-Sleep -Seconds 2
Save-Vue $w 'g10-5-bilan'
"bilan : $(Get-PanelText $w)"
Click-Id $w 'PanelCancel'; Start-Sleep -Seconds 3
"suivi : $(Get-Valeur $w 'SuiteDirectStage') | $(Get-Valeur $w 'SuiteDirectAdvice')"
Save-Vue $w 'g10-6-suivi'
"après : $(Get-EtatPoste)"
"reçus après :"; Get-RecusRecents 2
Stop-PestoFenetre $w
'FIN g10'
