# Bilan de livraison GP 17.0-RC11

## Base et modifications

Base des ressources/lanceurs : pack complet RC9 précédemment livré. Base du moteur : fichier RC10 avec traitement Entra préalable récupéré dans la Bibliothèque. La référence exacte de ce source et ses empreintes de fonctions figurent dans `tests/rc10-core-baseline.json`.

Ajouts : `wad/GP-Startup.ps1`, parcours UAC avant login, reprise prudente des fichiers d'état entre profils, test du vrai lanceur sans moteur métier. Le `GP.ps1` et le `GP.cmd` doivent être remplacés, pas seulement `GP-Core.ps1`.

Seules cinq fonctions du moteur RC10 ont changé : `AddToDomain`, `RenameComputer`, `Run-Queue`, `Show-LoginWindow` et le titre dans `Show-GPStartupWindow`. Le garde-fou de démarrage est également ajouté au début du fichier. Les 264 autres fonctions sont identiques à la RC10 après normalisation des fins de ligne, notamment les fonctions de retrait Entra, transport de tâche SYSTEM, déplacement et restauration des checkpoints.

## Vérifié ici

Contrôles Python de structure lexicale PowerShell, gabarits XML/XAML, contrats statiques et références de fonctions. Le validateur RC11 `tests/startup_static_checks.py` vérifie notamment l'ordre élévation/login, la sortie du parent, les arguments du relais, la préservation RC10, la reprise des états et les refus avant mutation. Ses cinq modifications négatives en mémoire sont détectées. Le rapport indique explicitement que ces vérifications ne sont pas une exécution native.

Les huit validateurs existants ont également été relancés. Leur référence de préservation a été actualisée explicitement pour partir de la véritable RC10 et de la liste des cinq modifications autorisées, au lieu de contrôler un moteur antérieur au correctif Entra. Le contrôle historique devenu sans objet sur une réparation Entra facultative a été remplacé par le contrôle du retrait préalable RC10 et de son résultat.

Les rapports courants sont listés dans `tests/rc11-validation-summary.json`. Les rapports historiques de versions antérieures et les anciens auto-tests de validateurs ne constituent pas des essais RC11. Les totaux des différents validateurs se recouvrent : ils ne mesurent pas un nombre de scénarios Windows validés.

Les fichiers de configuration et ressources AD sont conservés. Le correctif est dépourvu de fichiers de configuration. Les archives et les empreintes sont contrôlées lors de leur création.

## Fourni, mais NON exécuté ici

- Parseur natif Windows PowerShell 5.1 et suites Windows de tests.
- `TEST_UAC.cmd` : tests de routage, relais simulé, annulation, arguments et copie d'état en dossiers temporaires.
- `VERIFIER_UAC.cmd` : essai manuel de la vraie élévation avec un moteur factice et sans AD.
- Nouvelles régressions moteur simulées : credentials réutilisés, séquence dsreg/rename, refus dsreg, absence de credentials, absence d'élévation.
- Workflow CI Windows et compilation PS2EXE.

## Non validé dans cet environnement

Windows, UAC réelle, session standard vers session administrateur, accès aux anciens profils, propriétés WPF à l'exécution, rendu de connexion, signature ou politiques d'entreprise, appels AD/RPC/DCOM, retrait Entra, renommage, jonction, déplacement réel, réinscription Entra. Aucun EXE compilé ne fait partie du livrable.

Il faut donc réaliser la recette sur un poste de test. Cette livraison ne certifie ni les droits du compte ni le fonctionnement de bout en bout dans le domaine du destinataire.

## Limites importantes

UAC et mot de passe AD restent distincts au démarrage. Un timeout signifie que le résultat est à vérifier, pas que Windows a annulé l'opération. Une file d'un autre profil n'est pas ignorée ou fusionnée arbitrairement : un conflit bloque la reprise. Le test UAC sans AD prouve seulement le jeton obtenu, pas la réussite d'une mutation métier.
