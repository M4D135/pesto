# Correctifs et contrats locaux — Pesto 1.0

Candidat EXE `add688198e38269f4d3d8084bba9bd3b3a5664f1336ec961677c130eb2d75e7f`. Les empreintes de [sources](sources.json) relient les preuves au code. Aucun lancement de VM, aucune connexion AD et aucune simulation de parc dans cette passe.

## Corrections

- Journal : clés JSON quotées, valeurs échappées ou tronquées, variantes de clés, schémas Authorization et userinfo URL masqués. Une valeur non quotée masque conservativement le reste de la ligne ; objet/tableau sensible : reste du texte masqué. Limite de taille et timeout fermés. Ce filtre supplémentaire ne remplace pas l’absence de secrets à la source.
- Adaptateur de déploiement : erreurs fermées sans exception brute ; export moteur absent refusé avant appel ; exception ou résultat incomplet après appel en écriture déclaré incertain (97), sans réessai automatique. Le code Windows 3010 reste conservé.
- Scanner de marqueurs : BOM de liste accepté, UTF-16 sans BOM/NUL non déclaré examiné, chemins masqués, liens refusés, I/O inaccessible déclaré incomplet sans trace sensible. Images et fichiers binaires restent non examinés.
- CI : HelpText des deux filtres du journal ajouté ; vrai helper du statut et ses dépendances chargés dans le banc HomeDashboard.

La [revue OpenCode](revue-opencode.md) est un brouillon reçu avant ces corrections. Ses cas ont été examinés et convertis en contrôles locaux. L’incertitude après un appel d’écriture est volontairement conservatrice : absence de réponse ne prouve pas absence de mutation.

## Résultats locaux

| Banc | Résultat | Portée |
|---|---:|---|
| [Python complet](local/python-final.log) | 543/543 | Contrats et processus locaux, dont 8 cas adaptateur |
| [Release/scanner ciblé](local/release-tests.log) | 50/50 | Dont 19 cas de marqueurs et I/O |
| [Contrôles portables](local/pesto-portable-validation.json) | 620/620 | Sources, XML, PE et vrai parseur PS 7.4.20 |
| [Engine120](local/Engine120-generative.json) | 77/77 | Vraies fonctions du module et DLL Common |
| [HeadlessAudit](local/headless.json) | 12/12 | Vrai writer C# local, queue doublée |
| [HomeDashboard](local/HomeDashboard-fixed.json) | 46/46 | Vraies fonctions, fenêtre mémoire sans WPF |
| [Automation](local/automation.json) | 38/38 | Contrats avec doubles, sans Windows/AD |

Les nombres n’ont pas la même unité et ne sont pas additionnés. Windows PowerShell 5.1, WPF et AD ne sont pas déduits des tests Mac.

## Point 105

Qualification acquise pour les **contrats purs locaux Unicode/DN/JSON/limites/états** : seed 1052026, 256 textes Unicode, 1 536 contrôles JSON aux limites, 8 JSON/UTF-8 invalides, 69 DN valides et 9 invalides, 6 bornes texte, 576 combinaisons d’état. Rapport : empreintes corpus/runtime/DLL/test. Cela ne qualifie ni le rendu WPF ni une opération AD.

Le catalogue contient désormais 88 fonctions implémentées, 19 études conclues, 1 qualification locale acquise, 11 qualifications ouvertes et 1 mesure prolongée restante (107). Le point 106 reste ouvert pour sa portée complète, notamment captures et exports réels.

## GitHub

Le [run précédent](https://github.com/M4D135/pesto/actions/runs/38794198372), sur `ae2a663`, a réussi le job portable et échoué le job Windows isolé. Les [détails des jobs](ci-precedent-jobs.json) et le [journal brut](ci-precedent-windows.log) sont conservés. Les échecs produits par UxTests et HomeDashboard sont corrigés ici. Deux contrôles larges étaient non exécutés sur écran 1024 px. Le nouveau résultat CI sera constaté après push, sans transformer les tests isolés en recette AD.

## Distribution

PROD classique : `Pesto.exe` + `wad/`. DEV : sources, tests, outils et guides v1.0. Configuration neutre issue du modèle. Les guides technicien (26 pages) et administrateur (61 pages) restent identiques aux versions déjà relues ; ces correctifs internes ne changent pas leurs parcours.

## Alignement du contrat de masquage

Le [run 8556142](https://github.com/M4D135/pesto/actions/runs/38798124521) a révélé une attente ancienne dans Run-EngineTests : conservation de `user=test` après `password=abc`. Le nouveau filtre masque volontairement la fin de ligne lorsque la valeur sensible n’est pas quotée. Le test est aligné sur ce contrat ; un contrôle supplémentaire prouve qu’une valeur quotée conserve bien les champs suivants. [Engine : 118/118](local/engine-mask.json) sur PowerShell 7.4.20 Mac, fonctions réelles et doubles ; le nom historique « PS 5.1 » d’un cas ne désigne pas l’hôte réel. Aucun changement de runtime ou de l’EXE pour cet alignement.

Le pack DEV est régénéré avec ce test et la synthèse de livraison actualisée ; le pack PROD doit rester identique. Les preuves `release/` et `packs-check.json` gardent les empreintes de la première publication ; `release-followup/` et `packs-followup-check.json` décrivent les archives finales.

## Compatibilité des bancs CI

Le run `58d6ee1` confirme Engine 118/118 et Engine120 77/77 sous Windows PowerShell 5.1. Le banc CliOutput attendait encore l’ancien texte brut d’exception et utilisait un résultat sans MutationStarted : fixture et assertions sont alignées sur le contrat fermé. Contrôle négatif ajouté pour une exception contenant un marqueur ; [15/15 local](local/CliOutput-fixed.json).

Sur Linux partagé, un processus du banc de concurrence arrivait après le premier créneau (INCOMPLETE correctement signalé). Le test réserve désormais 15 secondes au démarrage de trois PowerShell et utilise des créneaux de 1 500 ms, au lieu de 5 secondes/500 ms. Les attentes restent strictes : aucun Late accepté, un propriétaire par tour et régression volontaire détectée comme VIOLATION. [7/7 local](local/race-ci.log). Aucune modification du worker de coordination.

Les packs finaux sont décrits par `packs-ci-fixtures-check.json` et `release-ci-fixtures/` ; PROD reste identique, DEV intègre les deux bancs corrigés.
