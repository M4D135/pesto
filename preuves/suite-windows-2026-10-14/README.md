# Suite Windows — 14 octobre 2026

VM `PESTO-W11-TEST`, Windows PowerShell 5.1.26100.6584. Aucune mutation AD.
Copie `C:\PestoSuite-20261014`. La VM a été arrêtée ensuite.

Python sur le Mac : 406 tests, 6 ignorés, code 0.

Première passe `Run-AllTests.ps1` : neuf suites en échec.
Sept venaient de fichiers `._*` apportés par tar. Deux autres, Async et UX, refusaient
`ConvertTo-PestoCliJson` et `Initialize-PestoCliProcess` définies dans les deux entrées CLI.
`Run-HeadlessOutcomeTests.ps1` est cité par l'agrégateur mais le fichier n'existe pas ;
ces cas sont déjà dans `Run-IntegrationTests.ps1` (19/19). Le nom a été retiré de la liste.

Après correctif, relance des suites en échec plus le CLI et le package : toutes au code 0.
UX : 2 cas non exécutés, l'écran de la VM fait 1024 px et la mise en page large demande 1244 px.
Le rapport le dit ; la suite reste au code 0.

La recette souris, les redémarrages et les renommages AD réels ne font pas partie de cette passe.
