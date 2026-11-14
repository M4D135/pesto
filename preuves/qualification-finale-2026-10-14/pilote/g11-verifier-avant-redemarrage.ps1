# Avant redémarrage : « Vérifier seulement » sur le poste dont le renommage attend le redémarrage. Lecture seule ; Pesto
# doit refuser un nouveau renommage (renommage en attente), sans rien écrire.
. 'C:\PestoFinal_20261014\pilot\commun.ps1'
"état : $(Get-EtatPoste)"
$w = Start-PestoCopie "$R\gui"; Set-Max $w
Set-Formulaire $w 'Paris'
"aperçu : actuel=$(Get-Valeur $w 'UxCurrentName') nouveau=$(Get-Valeur $w 'UxNewName') ; bouton : $(Get-Valeur $w 'SuiteDirectRun')"
Set-Premier $w; Invoke-Element (Wait-Enabled $w 'SuiteDirectCheck' 60) | Out-Null
Start-Sleep -Seconds 25
if (Find-Id $w 'PanelBody') { "panneau : $(Get-PanelText $w)" }
"résultat : $(Get-Valeur $w 'SuiteDirectResult') | conseil : $(Get-Valeur $w 'SuiteDirectAdvice') | sous le bouton : $(Get-Valeur $w 'SuiteDirectHint')"
Get-Texte $w | Where-Object { $_ -match 'attente|redémarr|refus|bloq|BLOQU|incertain' } | Select-Object -First 12
Save-Vue $w 'g11-verifier-avant-redemarrage'
if (Find-Id $w 'PanelCancel') { Click-Id $w 'PanelCancel' }
"reçus :"; Get-RecusRecents 2
Stop-PestoFenetre $w
'FIN g11'
