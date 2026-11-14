# Validation RC16 : distribution et dépendances

## Exécuté dans cet environnement Linux

- Compilation réelle du lanceur C vers Windows x64 graphique, avec clang/lld. Deux compilations séparées donnent le même EXE de 99 840 octets. Le PE et ses ressources indiquent 17.0.0.16 / 17.0-RC16 ; aucune signature Authenticode n'est présente.
- Neuf cas C explicites et 2 000 allers-retours indépendants d'arguments réussis. Cela n'exécute pas un processus Windows.
- **251 contrôles portables** de source, structure lexicale, XML, liaisons et ressources, export des workers, invariants et PE réussis. Ils ne sont pas le parseur natif de Windows PowerShell.
- **14 tests Python de distribution réussis**, avec sous-cas pour l'ajout/modification/retrait de 16 fichiers facultatifs, l'absence et l'altération de chacun des 26 composants obligatoires, 11 formes de manifeste invalide, les liens, la génération sans outils DEV et les copies PROD/DEV.
- Le contrôle de ces tests Python est une implémentation portable, pas une exécution de `Test-GPPackage` sous Windows. Il utilise la même liste fermée et vérifie réellement les fichiers copiés.
- Comparaison des 14 autres modules PowerShell GP avec la RC15 : uniquement les substitutions explicitement prévues de version et de messages recommandant désormais GP.exe. Les blocs métier ne sont pas réécrits. Ressources AD et configurations préservées.
- Concordance de l'EXE, du manifeste Runtime et des 26 fichiers entre les deux distributions ; intégrité ZIP vérifiée.

Les rapports exploitables sont dans `tests/rc16-portable-validation.json`, `tests/rc16-build-validation.json` et `tests/rc16-distribution-validation.json`. Les anciens rapports restent historiques.

## Non exécuté ici

Le lanceur PE sous Windows, le parseur Windows PowerShell 5.1, le code `Test-GPPackage` dans cet interpréteur, le générateur PowerShell de distributions, le rendu WPF, l'UAC, l'authentification et les opérations AD réelles. Un téléchargement d'interpréteur portable n'a pas été possible dans cet environnement ; aucun résultat d'exécution PowerShell n'est donc annoncé.

## Tests Windows fournis dans DEV

`TEST_DISTRIBUTION.cmd` analyse les scripts avec le parseur réellement disponible, vérifie le runtime puis fabrique des copies temporaires dépourvues de tous les scripts facultatifs. Il appelle **le vrai `Test-GPPackage`**, retire/modifie chaque composant obligatoire, altère le manifeste, teste sa régénération et fabrique PROD/DEV avec le générateur PowerShell.

Il ne lance ni GP.exe, ni le moteur, ni le login, ni WPF, ni UAC, ni un appel AD. Le compte rendu est enregistré dans le dossier temporaire affiché. Les opérations de test n'ont pas lieu dans l'installation active.

`TESTER.cmd` ajoute les tests WPF et les régressions isolées héritées, adaptés aux métadonnées RC16. Ces tests ne sont pas annoncés comme déjà passés.

## Recette manuelle indispensable

Sur Windows de test, avec un paquet dont la provenance a été contrôlée :

1. Copier uniquement PROD. Vérifier l'absence de DEMO.cmd, TESTER.cmd et des dossiers de développement.
2. Exécuter `GP.exe --check`, puis retirer LIRE_MOI.txt et DEBLOQUER_TOUT.cmd d'une copie : le contrôle doit rester positif.
3. Remettre une configuration de recette cohérente, puis vérifier l'ouverture par GP.exe et la connexion attendue selon le domaine.
4. Sur une autre copie non utilisée pour des opérations, retirer ou altérer un composant applicatif : l'ouverture doit refuser le paquet, sans mutation.
5. Contrôler le compte UAC effectif, la connexion intégrée en domaine, le login hors domaine et l'absence de régression des thèmes/contrôles.
6. Lancer les recettes métier existantes sur les postes et le domaine de test autorisés. Ne pas lancer une mutation pour tester seulement un conditionnement.

PROD signifie « contenu destiné à la diffusion », pas « validé sur votre environnement ». Le manifeste reste local et non signé ; il ne remplace pas les contrôles de provenance et les politiques de l'entreprise.
