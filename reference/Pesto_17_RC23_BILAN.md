# Pesto RC23 : bilan de vérification

Date : 2 octobre 2026. Base : DEV RC22 effectivement disponible. Les journaux de tests de cette itération sont dans RC23_PREUVES. Les anciens rapports restent historiques.

## Artefact réellement compilé

- Windows x64, EXE natif de 112128 octets ; moteur PowerShell 5.1/WPF conservé.
- SHA-256 : `95b736ef748b6f1db057c63490ac67a242fa35486b34e508661f4ea797408557`.
- Deux compilations indépendantes donnent le même EXE.
- 38 composants applicatifs contrôlés par le manifeste ; 37 ressources/scripts sont liées aux empreintes incorporées du lanceur.
- L’EXE est NON SIGNÉ. Une compilation et des empreintes ne prouvent pas l’identité de l’éditeur.

## Tests exécutés dans le conteneur Linux

| Groupe | Résultat | Portée exacte |
|---|---:|---|
| Python unittest | 122 réussis, 0 échec | Distribution, copie/reprise et inspection du source/XML/liaisons ; pas de PowerShell. |
| Contrôles portables | 340 réussis, 0 échec | Délimiteurs/guillemets, XML, références, dépendances, empreintes, structure PE. |
| Code C du lanceur | 35 scénarios réussis | API Windows remplacées par des doubles ; ce n’est pas le lancement du PE. |
| Arguments C | 9 cas + 2 000 allers-retours | Décodeur indépendant, chaînes et bornes. |
| SHA-256 C | 132 cas réussis | Comparaison à hashlib, tailles et découpage différents. |
| Interruption de mise à jour | 39 frontières de copie couvertes | Arrêts de processus dans des fixtures Linux, restauration vérifiée ; inclus dans les 122 tests. |
| Passage depuis les vrais composants RC22 | 4 interruptions sélectionnées puis mise à jour réussie | Retour exact au code RC22, nouveaux fichiers retirés au rollback, configuration conservée ; fixtures Linux. |
| Compilation répétée | Identique | Même source, même outillage LLVM, pas d’exécution Windows. |

Le nouveau fichier test_rc23.py ajoute 26 contrôles de raccordement. Il ne prétend pas exécuter les 65 scénarios métier PowerShell.

## Erreurs rencontrées puis traitées pendant cette itération

Le premier rerun général utilisait encore une attente de révision 22 dans un test et l’outil de mise à jour refusait la RC23. Le support de version a été corrigé. Deux nouvelles assertions de source avaient ensuite un mauvais nom de variable ou un mauvais espace dans la ligne Add-Computer : leurs attentes ont été alignées sur les vrais raccordements sans retirer les conditions contrôlées. Les premières sorties sont conservées. Le contrôle supplémentaire du vrai pack RC22 a initialement appelé le validateur exigeant la version courante, qui l’a refusé normalement. Le test utilise maintenant le validateur des composants historiques avec vérification des empreintes natives. Les résultats verts indiqués ici sont ceux des reruns, pas ceux des tentatives interrompues.

## Différences de fonctions

Après normalisation des fins de ligne et du seul numéro de version : 13 fonctions ajoutées, 30 modifiées, 0 supprimées, 505 inchangées. Ces nombres décrivent les différences ; ils ne constituent pas un score de sécurité. Liste exacte : function-changes.json.

## Fourni, mais NON exécuté

65 cas Windows RC23 sont fournis, dont deux chargements de vrais XAML. Ils emploient le parseur cible et des fonctions extraites par AST, avec doubles interdisant les opérations réelles. Les suites antérieures restent raccordées à TESTER.cmd. Une absence de -Wpf donne SKIP et une recette incomplète.

Non exécutés : Windows PowerShell 5.1, Pester/PSScriptAnalyzer sous Windows, PE Windows, compilation CLR du writer, rendu/interactions WPF, UAC, registre/ACL/partages, jonction/renommage/déplacement/reboot AD/Entra et accessibilité/DPI/RDP. Le téléchargement d’un runtime Linux n’a pas abouti ; aucune exécution de celui-ci n’est revendiquée.

## Statut des 90 points et diffusion

RC23_90_POINTS.md distingue chaque statut. Les points 53 et 63 passent de code partiel à code livré ; l’acceptation Windows reste absente. Les autres chantiers concernés sont documentés sans être déclarés complets. djoin et la signature restent notamment ouverts.

PublicReleaseAuthorized demeure false dans les preuves. Recette interactive, signature approuvée et décision de diffusion de l’organisation ne sont pas déduites d’un ZIP cohérent ou de tests Linux.
