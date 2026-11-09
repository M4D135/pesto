# Pesto 1.0 — recette de présentation

Campagne du 12 octobre, finalisée le 13 octobre 2026. Le fichier
[summary.json](summary.json) relie les résultats à leurs exécutables et sources.

## Version distribuée

EXE SHA-256 : `540c64442f19d246fcbd67c34f387e501e104f45514687d1db31a67739e253b6`.

- Python local sur le candidat ad05 : **323 réussis, 6 ignorés, 0 échec** (329 cas).
- PowerShell local sur ad05 : **192 contrôles réussis**, répartis en sept suites.
- Après l'alignement des quatre boutons sur 540c : suites locales Accueil **43/43**,
  Présentation **41/41** et Navigation **10/10** relancées avec succès.
- Windows final : **Zoom 42/42**, **ToolsTabs 33/33**.
- Navigation interactive finale Noms → Interventions → Accueil : réussie.
- Les quatre boutons d'accueil du dernier EXE sont alignés et de même taille ;
  « Plusieurs postes » ouvre la file. Captures finales à 100 % et 120 % validées.
- Fenêtre 760 × 560 à 150 % : grilles conservées, défilement disponible,
  barre de zoom accessible. Le défilement global vertical et horizontal est
  nécessaire pour voir toutes les actions du pied de fenêtre.

Les captures destinées aux guides sont en **1920 × 1160**, relues sans infobulles.
Les captures 760 × 560 sont uniquement des preuves de la recette petite fenêtre.

## Limites et résultats intermédiaires

`windows-home-buttons/` porte les contrôles du binaire final 540c.
`windows-release/` conserve la recette ad05 avant l'alignement des quatre boutons,
notamment les parcours Noms/Interventions et petite fenêtre. `windows-final/` désigne
le candidat précédent `cab4…`, dont la suite Ux compte 48 réussites et 2 contrôles
de géométrie ignorés dans une session Windows sans bureau interactif. La navigation
réelle a été contrôlée séparément. Cette recette n'est pas une matrice exhaustive
de toutes les résolutions et échelles DPI de Windows.

Les répertoires `windows-home/`, `windows/` et `windows-zoom-only/` gardent les
résultats de leurs candidats respectifs ; ils ne sont pas attribués au dernier EXE.

Le contrôle `08-small-footer-final.log` a échoué en exigeant le bouton Fermer
à droite alors que la vue était défilée tout à gauche. Le contrôle 09 vérifie son
accès après défilement à droite, avec une mesure du rectangle et une capture relue.
`IsOffscreen=false` seul ne prouve pas la présence complète dans la zone visible.

Les captures des étapes 01/02 du candidat final ont été rejetées : Windows avait
verrouillé la console. Les captures 04/05 les remplacent pour les guides.
Les images de diagnostic rejetées sont conservées hors dépôt ; leurs journaux
restent présents pour ne pas transformer une tentative invalide en validation.

## Périmètre

Cette campagne ne déclenche aucune jonction, aucun renommage ni déplacement AD.
La recette antérieure correspondante est conservée dans
[vm-2026-10-12](../vm-2026-10-12/). Seule la VM `PESTO-W11-TEST` a été utilisée ici.
Le contrôle de fermeture et de restauration des préférences est enregistré dans
`windows-home-buttons/03-cleanup.json`.
