# Lot Spark « filtre2 » — rapprochement au 15 octobre 2026

Pesto 1.0, branche d’origine `spark/filtre2`, base `master` `d4a1a3d`. Les brouillons de ce lot avaient passé une barrière de syntaxe, XAML et tests portables. Certains tests vérifiaient une fonction absente, une copie de logique ou aucune assertion : ils ont été retirés. Le tableau ci-dessous décrit les corrections désormais présentes dans le produit, indépendamment des qualifications Windows/AD.

Les codes de ce document sont des **compléments** au catalogue : `T108` n’est pas le point 108 des 120 exigences. Ils ne doivent pas être additionnés au total de 120.

## État des compléments

| Code | Réalisation actuelle | Sources et contrôle local | État / limite |
| --- | --- | --- | --- |
| T017 / W4V2G03 | Tableaux de choix : projection normalisée une fois, recherche temporisée 220 ms et nettoyage du timer à la fermeture | `Pesto-Workspace.ps1`, `Run-Workbench120Tests.ps1` | Code présent ; grandes collections et rendu WPF à qualifier |
| T018 | Événements du worker headless écrits pendant l’exécution ; secours borné, comptage des pertes et fermeture explicite du writer | `Pesto-Async.ps1`, `Pesto-Enterprise.ps1`, `Pesto-Automation.ps1`, `Pesto-Journal.ps1`, `Run-HeadlessAuditTests.ps1` | Contrats portables incluant le vrai writer C# local ; aucune issue métier inventée si l’audit échoue |
| T050 | Contrôle de conflits DNSHostName et SPN HOST/RestrictedKrbHost du nom cible, sur le même DC et avec la même identité | `Assert-PestoTargetNameAvailable`, `Run-RemotePreparationTests.ps1` | Code présent ; doubles AD, pas d’inventaire exhaustif de forêt ni de nettoyage |
| T057 | Option `BlockJoinOnClockSkew=false` raccordée à la configuration et au précontrôle de jonction ; observation bornée, pas de correction d’heure | `Get-PestoJoinClockCheck`, `Pesto-Policy.ps1`, `Pesto-Join.ps1`, `Run-RemotePreparationTests.ps1` | Écart connu d’au moins 300 s bloquant si activé ; inconnu reste avertissement |
| T070 | Services : chargement, erreur, état partiel et âge visibles ; liste précédente préservée en cas d’échec | `Pesto-Directory.ps1`, `Get-PestoSiteReadLabel`, `Pesto-SuiteUI.ps1`, `Pesto-Join.ps1`, `Run-DirectoryCacheTests.ps1` | Code présent ; rendu et lecture AD réels à qualifier |
| T086 | Liste bornée des étapes réellement traversées et étape courante, dans l’en-tête commun | `StageHistory`, `Get-PestoOperationStages`, `Run-UiPresentationTests.ps1` | Aucun pourcentage ni succès déduit de la fin de supervision |
| T022 | Validation réelle de l’import classique extraite ; index sources/cibles insensibles à la casse construits une fois par aperçu | `New-PestoCsvQueueCandidate`, `Pesto-BatchTools.ps1`, `Pesto-Core.ps1` | Code et validation locale terminés : BatchNames120 30/30, dont l’import réel à 5 000 lignes. Aucun hachage récursif par ligne ni cache d’empreinte risqué ajouté |
| T043 / V2B07 | Titres d’étapes et ordre de tabulation explicite dans Un poste | `Pesto-Shell.xaml`, `Run-UiPresentationTests.ps1` | Code présent ; parcours clavier réel à qualifier |
| T067 | Bandeau commun exposant les barrières existantes | `Get-PestoBlockState`, `Pesto-SuiteUI.ps1`, `Pesto-Shell.xaml` | Présentation des blocages réels ; aucune nouvelle condition moteur |
| T072 | Maximisation lorsque le dessin ne tient pas, ou sur préférence explicite ; fenêtre adaptée conservée | `Pesto-Appearance.ps1`, `Run-UiPresentationTests.ps1` | Code présent ; affichages réels à qualifier |
| T073 / W4RT005 | Ctrl+F et F5 dirigés vers la page active ; recherche Accueil sur les champs réellement projetés | `Pesto-Workbench.ps1`, `Run-Workbench120Tests.ps1` | Code présent ; raccourcis sans navigation ni mutation implicite |
| T080 | Mode effectif et DC courant dans l’en-tête | `Get-PestoModeChip`, `Pesto-SuiteUI.ps1`, `Run-UiPresentationTests.ps1` | DC non sélectionné et modes Démo/Simulation/Consultation/Réel explicites |
| T096 | Sélecteurs d’exclusions par groupe AD et OU ; lecture asynchrone, limitée, même DC/identité | `Pesto-ConfigEditor.ps1`, `Run-ConfigEditor120Tests.ps1` | Code présent ; pas de sauvegarde implicite, invalidation du contexte périmé |
| T108 | Vue asynchrone en lecture seule du registre partagé ; lectures bornées, schémas et UTF8 stricts, liens refusés, retours périmés ignorés | `Get-PestoSharedNameRegistrySnapshot`, `Complete-PestoSharedNameRegistry`, `Run-NamesLoadingTests.ps1` | Code intégré ; NamesLoading 45/45 local, aucun partage SMB réel qualifié |
| F01 | Exports atomiques sans écrasement ; réemploi d’un `.archive-info` orphelin seulement si son identité et son hash correspondent | `Write-PestoNewExport`, `Pesto-ReceiptTools.ps1`, `Run-ReceiptTools120Tests.ps1` | Code présent ; conflits conservés, nettoyage limité aux métadonnées créées par l’essai |
| F03 | Audit fermé de réconciliation des tâches/protections/nettoyage, conservé dans la chronologie du reçu et projeté dans `operation.json` | `Write-PestoReconciliationAudit`, `Get-PestoReconciliationAudit`, `Run-ReconciliationAuditTests.ps1` | Code intégré ; lecture inconnue ne devient ni suppression ni relance ni succès |
| V1T127 | Matrice exhaustive des booléens et routes bloquées de l’action principale | `Run-UiPresentationTests.ps1` | 1 024 combinaisons dans un cas du banc ; ne pas les compter comme 1 024 scénarios GUI |
| V1T008 | Protection au déplacement choisie explicitement par l’assistant | Besoin déjà raccordé sous V2D04 (`e80d8f3`) | Ne pas compter deux implémentations pour le même besoin |
| W4V1T104 | Identité matérielle locale issue du statut existant et nom proposé agrandi sur Jonction | `Pesto-Join.ps1`, `Pesto-Join.xaml` | Aucun appel matériel supplémentaire ; absence d’information explicitée |
| W4V2G06 | Journal : filtre de niveau + recherche, date complète et copie des erreurs expurgées | `Get-PestoFilteredLogEntries`, `Pesto-SuiteUI.ps1`, `Pesto-Workbench.ps1`, `Pesto-Shell.xaml` | Code présent ; copie limitée aux entrées retenues en mémoire |
| W4RT100 | Préparer un lot par lectures AD ciblées des sources puis des noms/SPN, sans attendre l’inventaire complet ; même DC/identité, réponses partielles et aperçus périmés refusés | `New-PestoNameConflictFilter`, `Invoke-PestoBulkAdRead`, `Test-PestoBulkAdContext`, `Run-BulkPlanningTests.ps1` | Code intégré ; BulkPlanning 31/31 local avec doubles AD |
| T010 | Identifiant d’opération et métadonnées conservés dans les résultats d’échec des deux parcours silencieux | `Pesto-Enterprise.ps1`, `Pesto-Automation.ps1`, `Run-IntegrationTests.ps1` | Code présent ; une issue incertaine garde sa corrélation |
| W4V1T083 | Chaînes utilisateur accentuées dans démarrage, jonction et lanceur C | `Pesto-Startup.ps1`, `Pesto-Join.ps1`, `tools/launcher/Pesto-launcher.c`, `tests/test_accents.py` | Sources corrigées ; moteur, EXE et manifestes régénérés et contrôlés localement |

Les sources de tests ci-dessus décrivent une couverture ; les rapports exécutés et leurs empreintes doivent être liés au candidat final. Les contrats sur Mac avec doubles ne certifient ni WPF, ni RPC/DCOM, ni permissions AD. La préparation de renommage distant n’exige pas WinRM ; les lectures facultatives du registre distant ne sont pas un prérequis bloquant à elles seules.

## Clôture locale et limites

- Les compléments de code sont intégrés. NamesLoading 45/45, BulkPlanning 31/31, HeadlessAudit 10/10, ReconciliationAudit 7/7, BatchNames120 30/30 et Automation 38/38 passent localement ; les rapports sont reliés dans [le rapprochement](RAPPROCHEMENT_120.md#contrôles-locaux-des-derniers-compléments).
- Le chargement du composant Diagnostics est raccordé au parcours headless et couvert par le recontrôle Automation.
- Moteur, lanceur et manifestes régénérés ; guides définitifs contrôlés et assemblage DEV/PROD neutre réalisé. Les preuves et l’identité du candidat sont reliées dans [le rapprochement](RAPPROCHEMENT_120.md#réalisation-locale-terminée).
- Laisser les essais GUI/AD/SMB réels à la recette manuelle demandée. Aucun banc prêt ne vaut résultat PASS non exécuté.

## Corrections de la passe tests et outils conservées

- **Lanceurs de tests.**
  - `tests/Run-AllTests.ps1` reprend les 43 suites de `master`, plus la fumée WPF du banc de projection. Chaque suite
    tourne dans son propre `powershell.exe -STA`, WPF compris.
  - Le lanceur s'arrête si une `Run-*.ps1` du dossier n'est ni lancée ni déclarée « lancée ailleurs » (`TESTER.cmd`,
    `TEST_RC2x.cmd`, lancement manuel).
  - `TEST_TOUT.cmd` appelle de nouveau Windows PowerShell : la VM n'a pas de Python.
  - `tests/suites.json` décrit les 50 suites, avec leur vraie plateforme.
  - `tools/run_tests.py` résout ses chemins depuis `DEV` et prend pwsh dans `PESTO_PWSH` ou le `PATH`.
    Sous Windows, il prend `powershell.exe` dans Sysnative ou System32. Il écrit dans `tests/results/` (ignoré par
    Git). Il sort en échec si une suite échoue ou si aucune n'a réussi.
- **Tests `test_spark_*`.**
  - Les chemins sont résolus depuis `__file__` : la suite passe de la même façon depuis `DEV` et depuis la racine.
  - Une source absente fait échouer le test au lieu de le sauter.
  - `tests/test_no_skipped_spark.py` interdit tout saut, sauf un saut dont la raison commence par « Plateforme ».
  - Les tests sans assertion ou sans objet ont été retirés.
- **Audit d'accessibilité (`test_spark_g09`).**
  - Chaque XAML est lu par `ElementTree`. Le contenu des gabarits n'est pas audité, et la fenêtre principale
    (222 contrôles interactifs) est maintenant parcourue.
  - Les identifiants ne contiennent ni ligne ni chemin absolu.
  - Le rapport est écrit dans `tests/results/`, et l'ancien rapport versionné est retiré.
  - La base relue `tests/a11y-baseline.json` justifie 21 écarts connus. Un nouvel écart fait échouer le test.
- **Accents.**
  - Messages de `Pesto-Startup.ps1` (« Argument de démarrage invalide. », « Pesto - démarrage impossible »).
  - Messages de `Pesto-Join.ps1` (« Vérifier le poste… », « …traite déjà la jonction… lancé »).
  - `test_accents.py` extrait toutes les chaînes hors commentaires et compare des radicaux en préfixe. Il n'admet que
    trois identifiants stables : `Pesto-demarrage.log`, `VERIFIER_UAC.cmd` et `Verified`.
- **Mise à jour (`update_installation.py`).** Le nom du mutex était déjà corrigé par `60457ac`. Le test vérifie
  maintenant la valeur calculée sous pwsh 7.4 : `Global\GP_Session_0CB133A024FBF5F3B6C3D1D2` pour
  `C:\Pesto\Install`.
- **Observateur de réplication.**
  - L'outil est déplacé dans `DEV/tools/Observe-PestoReplication.ps1`.
  - L'auto-contrôle par grep, qui sortait toujours en 1, est retiré.
  - `-ExpectedName` et `-ExpectedDistinguishedName` sont obligatoires. Un DC qui rend encore l'ancien nom est
    « Stale », jamais convergé.
  - Le rapport est créé sans écrasement.
  - Le test utilise un faux module AD et couvre les cas convergé, ancien nom, objet absent, DC unique et rapport existant.
- **Banc de course (`DEV/tools/Measure-PestoCoordinationRace.ps1`).**
  - `-Prepare -Root` est accepté.
  - Le nom disputé est commun à tous : `RACEnnnn`.
  - Chaque participant est un processus PowerShell séparé qui appelle le vrai `$script:PestoSharedNameWorker` de
    `wad/Pesto-Names.ps1`.
  - Chaque réservation obtenue est relue avant d'être libérée.
  - Une copie volontairement cassée du worker donne `VIOLATION` dans le test.
- **Courbe de charge AD (`Measure-PestoReadLoad.ps1`).**
  - Le contrôleur est découvert par Windows, sans PDC imposé.
  - Le domaine et la base viennent de `CONF[0].Domaine` et `CONF[0].OUScanNoms`. Le DN racine est construit sur tous
    les labels.
  - Un pool de runspaces remplace le sémaphore qui bloquait.
  - `-Server` et `-Credential` sont transmis à chaque lecture. Le rapport est créé sans écrasement.
- **Inventaire Add-Type (`Measure-PestoAddType.ps1`).**
  - Plus de `$IsWindows` ni de `-Exclude`. `TypeDefinition` positionnel et `@"..."@` sont reconnus.
  - La compilation est mesurée dans un processus enfant du même type. Le rapport est toujours écrit.
- **Banc WPF de projection.**
  - `LayoutUpdated` est compté par `add_LayoutUpdated` avec un compteur `[ref]`.
  - La stratégie est un paramètre. Les deux stratégies appliquent les mêmes changements.
  - `New-PestoBenchData` rend la table elle-même.
  - La fumée Windows `tests/Run-WpfProjectionBenchTests.ps1` est listée dans `Run-AllTests.ps1`.


## Portée des résultats de la passe Spark initiale

- macOS, Python 3.14 : suite complète `python3 -m unittest discover -s tests -p "test_*.py"` depuis `DEV`. Aucun
  nouvel échec par rapport au point de départ. Les 128 échecs de cette passe initiale concernaient les empreintes du lanceur et du
  manifeste, à régénérer par l'intégrateur.
  Les tests `test_spark_*` passent aussi depuis la racine du dépôt.
  Les bancs pwsh exigent `PESTO_PWSH`, qui désigne le PowerShell 7.4.20 portable. Sans pwsh, ils échouent au lieu d'être sautés.
- macOS, PowerShell 7.4.20 : les 33 suites portables passent après régénération du module moteur. Ce sont les 25 de
  la barrière, plus BootIdentity, BulkPlanning, Common, DomainNavigation, LoginPreferences, OptionalFollowupUi,
  Stabilisation et V1Improvements. Les fichiers générés ont ensuite été restaurés.
- **Non exécuté sous Windows PowerShell 5.1** : `Run-AllTests.ps1`, `Run-WpfProjectionBenchTests.ps1`, le banc de
  course sur NTFS ou SMB entre plusieurs postes, l'observateur et la courbe de charge sur un AD réel, ainsi que les
  mesures Add-Type sous 5.1. Les outils de mesure gardent le verdict `MEASURED_ONLY`.
