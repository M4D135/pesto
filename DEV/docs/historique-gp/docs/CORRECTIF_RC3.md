# Correctif GP 17.0-RC3 : Invoke-GPAsyncCallback introuvable

## Cause dans la version fournie

La fonction existe dans le fichier. L'erreur vient de sa résolution depuis le callback `Tick` créé par `GetNewClosure()`, pas d'une DLL ActiveDirectory absente et pas du fichier de configuration. `GP.ps1` appelle le moteur avec `&`, donc les fonctions du moteur sont dans une portée de script enfant. La closure du timer utilise un module dynamique distinct. Son appel non qualifié à la fonction ne retrouve pas cette portée.

La documentation Microsoft décrit explicitement le nouveau module de `GetNewClosure()` :
https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.scriptblock.getnewclosure?view=powershellsdk-7.6.0

La méthode est ancienne, mais cette page documente le SDK actuel. Elle explique le mécanisme ; elle ne vaut pas validation du correctif sous Windows PowerShell 5.1.

## Modification appliquée

Le timer reçoit le délégué d'une fonction nommée définie dans GP, sans création d'un module de closure. Son opération est retrouvée par l'identité de l'objet timer. Les informations variables des callbacks sont transmises par `CallbackContext` ; les traitements conservent leur accès aux fonctions du script GP.

Le même défaut potentiel a été retiré de la lecture de poste, du rafraîchissement de l'annuaire, du navigateur d'OU et du bouton de correction de configuration. Les quatre closures restantes n'utilisent que des références locales capturées, des objets .NET et des commandes intégrées ; le callback d'icône reçoit explicitement sa référence de journalisation.

Les erreurs du worker et les exceptions des callbacks restent signalées. Aucun faux succès, aucune élévation globale et aucune suppression des verrous de sécurité ne sont introduits. Un worker remplacé ne supprime pas la nouvelle opération du même nom. Un worker annulé ou expiré ne publie pas un succès tardif.

## Mise à jour sans écraser votre configuration

1. Fermer GP et vérifier qu'aucune action n'est en cours.
2. Extraire le contenu du correctif **dans le dossier GP existant**. Il contient `wad/GP-Core.ps1` mais aucun `cfg.json` ni autre fichier de configuration.
3. Accepter le remplacement de `wad/GP-Core.ps1`, puis exécuter le `DEBLOQUER_TOUT.cmd` déjà présent, après vérification de la confiance dans l'archive.
4. Relancer `GP.cmd`. La connexion doit porter le titre **GP 17.0-RC3**. Un ancien titre indique qu'une autre copie du moteur est encore lancée.

Ne pas déplacer l'installation ou le fichier de configuration : l'identifiant du stockage de reprise dépend de son chemin. Le correctif ne modifie ni les données de reprise, ni les journaux, ni les identifiants.

L'archive complète RC3 est également fournie. Elle contient toujours la configuration issue de la RC2 : **ne pas écraser votre propre `wad/cfg.json` avec elle** si vous l'avez corrigée depuis.

## Test de régression disponible sous Windows

`TEST_ASYNC.cmd` lance `tests/Run-AsyncTests.ps1`, qui appelle une fixture avec `&` dans une portée de script enfant. Seules les définitions sélectionnées du moteur sont chargées ; son corps n'est pas exécuté.

Les 29 cas couvrent le retour de connexion, erreurs terminantes et non terminantes, résultat vide, tableau résultat et contexte, callback invalide, exception de callback, verrou de file, annulation, remplacement, doublon, timeout, concurrence, réentrance, défaut de polling, callbacks poste/annuaire/OU et validation de configuration.

Les timers WPF, runspaces et `TreeViewItem` sont réels sur Windows ; les workers n'effectuent que des opérations fictives. L'AD, les postes et l'écriture de configuration ne sont pas appelés. Il ne s'agit pas d'une recette complète de l'interface GP.

Le rapport `tests/windows-async-results.json` n'est créé qu'après exécution réelle. **Aucun résultat de cette suite Windows n'est revendiqué dans la livraison.**

## Vérifications réalisées ici

- 53 contrôles statiques généraux réussis et 25 contrôles statiques ciblés réussis.
- 10 défauts injectés détectés par la garde générale et 7 par la garde ciblée. Ces résultats testent les validateurs, pas Windows.
- Appliquée au moteur RC2 d'origine, la garde ciblée signale 20 échecs attendus, dont les appels de fonctions dans les closures privées. Rapport négatif : `tests/rc2-scope-defect-detection.json`.
- 186 fonctions racines conservées textuellement ; 9 modifiées et 2 ajoutées. 14 fichiers de configuration, ressources et lanceurs identiques par comparaison binaire.
- Diff du moteur et rapport de préservation fournis.

Environnement Linux sans PowerShell exécutable, WPF ni AD. Pas de parseur natif, pas d'essai de login Windows, pas de recette de domaine, pas de compilation EXE. Les précédents résultats statiques n'avaient pas empêché cet incident : les nouveaux contrôles statiques ne sont pas davantage une garantie d'exécution complète.

Empreinte SHA-256 de `wad/GP-Core.ps1` : `b6c25aeb13249be575071ebee99a79cff775ff4fee0aa0420383c7f00fe01282`.
