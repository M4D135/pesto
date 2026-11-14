# Relevé de l'arbre UIA de la fenêtre principale de Pesto (agrandie) et capture de la fenêtre seule.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
$w = Get-Pesto
if (-not $w) { 'fenêtre principale introuvable' | Out-File "$D\02-arbre.txt"; return }
Set-Agrandie $w
Save-Fenetre $w "$D\02-fenetre.png"
Get-Arbre $w 14 | Out-File "$D\02-arbre.txt" -Encoding UTF8
