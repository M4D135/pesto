# GP 17.0-RC4 : sauvegarde locale et règle de renommage

## Le défaut signalé

Le journal RC3 s'arrêtait sur `File.Replace` avec trois arguments : « Le chemin d'accès n'a pas une forme conforme ». Dans cette version, `Start-GPNextQueueTask` sauvegardait `queue.json` en phase `Active` avant de créer le worker. Son bloc `catch` passait pourtant par le gestionnaire « Worker interrompu ». L'échec local était donc compté comme un échec d'action et pouvait déclencher un verrou de mutation incertaine, même si cette ligne n'avait pas été envoyée au worker.

La fonction `Write-GPAtomicText` passait `$null` dans le paramètre .NET de type `string` destiné au chemin de sauvegarde. Cette conversion PowerShell produit une chaîne vide, pas la référence nulle attendue par `File.Replace` pour désactiver la sauvegarde. Le défaut se manifeste lors du remplacement d'un fichier existant sans `-Backup`, notamment à la deuxième sauvegarde de la file. L'ancien test couvrait seulement le remplacement avec `-Backup`.

L'analyse du source localise ce défaut et correspond au message reçu. Elle ne remplace pas un essai Windows : la reproduction native est fournie, mais n'a pas été exécutée dans l'environnement de livraison.

## Correction de l'écriture

La branche sans sauvegarde appelle désormais :

```powershell
[IO.File]::Replace($tmp, $full,
    [System.Management.Automation.Language.NullString]::Value)
```

La branche `-Backup` conserve un chemin `.bak` explicite. Le temporaire reste dans le même dossier, est écrit et vidé avant remplacement. Aucun contournement par suppression de la destination puis déplacement n'a été ajouté. Les exceptions incluent le chemin cible et leur cause. Le nettoyage ne vise que le temporaire créé par cet appel.

En cas d'échec du contrôle local d'audit ou de sauvegarde avant création du worker, la ligne courante et les suivantes sont désormais **NON LANCÉ / 96**. Elles augmentent le compteur des non-lancées, pas celui des échecs AD. La file s'arrête. Ce chemin n'active ni ne lève de verrou de mutation incertaine. Les erreurs d'un worker réellement démarré conservent le traitement prudent RC3, dont les codes 32, 97 et 98.

## Règle demandée : renommer, déplacer seulement si le site change

| Situation | Action préparée |
|---|---|
| `P111301PR765129` vers `P111301VA765010` | Renommer, puis déplacer vers l'OU sélectionnée si nécessaire |
| `P111301VA765129` vers `P111301VA765010` | Renommer seulement, OU actuelle conservée |
| Même site, changement de service ou de type P/S | Renommer seulement |
| Nouveau code site, mais objet déjà dans l'OU cible | Renommer seulement, pas de déplacement redondant |
| Déplacement seul explicitement coché, sans renommage | Déplacement seul conservé |
| Jonction hors domaine | Parcours local inchangé, nom et OU obligatoires |

Pour un nom conforme à la convention GP, le site est déterminé par les deux lettres aux positions 8 et 9, insensibles à la casse. Le service et le numéro ne déclenchent pas un déplacement. Pour un ancien nom hors convention, le programme compare les conteneurs de site issus des racines OUSite et PREPROD configurées. Une sous-OU ne devient pas un autre site. Une source indéterminable et une destination différente entraînent un refus explicite plutôt qu'un déplacement supposé. Les contrôles habituels de périmètre et de droits AD restent nécessaires.

Pendant un renommage, la case **Déplacer (auto)** est calculée et non modifiable manuellement. Sa bulle explique la décision. Décocher Renommer efface ce déplacement automatique ; un déplacement seul doit être demandé explicitement. Sélectionner une autre OU ne coche plus à lui seul un déplacement.

La même décision est appliquée lors de la préparation, de la prévisualisation, de l'import de nouvelles lignes et de l'exécution. Les résultats historiques ne sont pas réécrits. La confirmation affiche les nombres de renommages, déplacements et redémarrages. Le worker relit l'OU actuelle avant de router le renommage ; il refuse d'ajouter une mutation absente du plan confirmé si l'état a changé.

L'ordre reste : **renommage confirmé, visibilité du nouveau nom, puis déplacement**. Si le renommage échoue ou si son résultat manque, aucun déplacement n'est tenté. Si le renommage réussit mais que le déplacement échoue, **PARTIEL / 89** permet de préparer une reprise du déplacement seul. Les résultats de protection ou d'état incertain gardent leur verrou. La RC4 n'active pas de redémarrage automatiquement.

## Mise à jour d'une installation RC3 déjà configurée

1. Fermer GP après vérification qu'aucune action n'est encore en cours. Sauvegarder le dossier existant, en particulier `wad\cfg.json` et les journaux.
2. Extraire le **correctif sans configuration dans ce même dossier GP**, au niveau de `GP.cmd`. Remplacer `wad\GP-Core.ps1` et ajouter les tests/guide du correctif. Ne pas créer un sous-dossier `GP` imbriqué.
3. Exécuter `DEBLOQUER_TOUT.cmd` seulement après avoir vérifié la confiance dans l'archive, puis `TEST_CORRECTIF.cmd`. Cette suite ne lance ni l'application ni les commandes AD : elle utilise des fichiers temporaires et des doublures.
4. Si les tests échouent, conserver leur rapport et ne pas lancer d'écriture réelle. S'ils passent, lancer `GP.cmd`. La connexion, le chargement et l'interface doivent afficher **17.0-RC4**.
5. Relire le poste concerné, vérifier son état et préparer une nouvelle ligne. Examiner **Prévisualiser** avant un premier essai sur un poste de test, pas un lot.

**Ancien verrou RC3 :** il n'est pas supprimé automatiquement. Contrôler l'état réel dans AD et sur le poste ainsi que les éventuelles tâches GP, puis utiliser le bouton normal de levée seulement après vérification. Ne pas supprimer le stockage de reprise ou changer de répertoire pour contourner ce contrôle. Les lignes historiques restent décochées.

Le correctif ne contient aucun `cfg.json`. L'archive complète conserve les configurations d'origine, y compris leur incohérence de domaine signalée précédemment. **Ne pas substituer cette configuration d'exemple à votre configuration LABO.LOCAL déjà adaptée.** Pour une réinstallation complète, conserver le chemin de l'installation et remettre le fichier de configuration opérationnel avant lancement. L'archive ne contient pas de nouvel EXE ; `GP.cmd` reste le point d'entrée.

## Tests et limites

`TEST_CORRECTIF.cmd` fournit **51 cas** Windows PowerShell 5.1 : parseur natif, reproduction de l'appel RC3, remplacements successifs avec/sans sauvegarde, verrouillage de fichier, phases de checkpoint, décision de site, états de file, UI factice, séquence rename/move avec doublures, et absence de démarrage du worker lors d'un refus local. Les fichiers d'essai sont créés dans un dossier temporaire propre à la suite. Le seul rapport conservé est `tests/windows-rc4-results.json`.

La suite est fournie **sans résultat Windows prétendument réussi**. Les suites natives, WPF complet, opérations AD/RPC/COM/UAC, exécution des CMD et compilation n'ont pas été exécutés ici. Les rapports `static-report.json`, `async-static-report.json`, `rc4-static-report.json` et leurs contrôles négatifs correspondent seulement aux vérifications Python exécutées sur le source. Un compteur statique n'est pas une validation fonctionnelle Windows.

Le build optionnel exige la réussite des quatre processus de test avant compilation. La définition de CI a été mise à jour mais n'a pas été exécutée à distance.

## Références techniques Microsoft

Consultées le 21 septembre 2026. Le diagnostic propre à GP provient du source RC3 et du journal fourni ; les références expliquent le contrat des API, pas l'état des machines du domaine.

- File.Replace, paramètre `destinationBackupFileName`, référence nulle sans backup et exception de chemin invalide : https://learn.microsoft.com/en-us/dotnet/api/system.io.file.replace?view=netframework-4.8.1
- NullString, transmission d'une référence nulle à une méthode .NET attendant une chaîne : https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.nullstring
