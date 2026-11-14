# Vérification du paquet RC17 R1

## Exécuté pour cette révision

- 20 tests Python de distribution réussis. Ce sont des tests portables, pas une exécution du démarrage Windows.
- 251 contrôles portables source/XML/PE réussis, sans modification du moteur.
- Comparaison octet pour octet des 25 composants applicatifs, du manifeste et de cfg.json avec le pack DEV RC17 source : identiques.
- Vérification des deux ZIP par lecture complète, CRC et empreintes du manifeste.
- PROD : exactement GP.exe, DEBLOQUER_TOUT.cmd et wad à la racine.
- DEV : même application et même déblocage, avec outils et tests supplémentaires.
- Les ZIP contiennent respectivement un seul dossier racine PROD et DEV.
- Le déblocage n'exige plus GP.ps1 et conserve le périmètre local, la confirmation, l'exclusion des liens et la vérification des flux.

## Non exécuté ici

Le lancement de GP.exe sous Windows, Windows PowerShell 5.1, le script de déblocage sur des flux NTFS réels, WPF, UAC et les opérations AD.

La suite Windows de distribution a été adaptée aux nouveaux noms et ajoute le contrôle par le parseur natif du bloc PowerShell inclus dans DEBLOQUER_TOUT.cmd. Elle reste à exécuter sur un poste de recette. Les anciens tests de versions antérieures restent historiques.

## Aucun nouveau binaire

L'EXE fourni est celui de la RC17, inchangé et non signé. Il n'a pas été recompilé pour cette correction de distribution. R1 identifie le paquet corrigé ; la version affichée de l'application reste 17.0-RC17.
