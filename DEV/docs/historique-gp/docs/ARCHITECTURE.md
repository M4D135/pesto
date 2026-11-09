# Complément RC5

La RC5 ajoute un worker indépendant de lecture seule, un préparateur de lot local, un filtre DataView, un rapport HTML et des synthèses locales. Les helpers restent intégrés dans wad/GP-Core.ps1. Voir INNOVATIONS_RC5.md et FONCTIONS_RC5.json.

---

# Architecture de la RC1

## Runtime

Le runtime est intégré à `wad/GP-Core.ps1`. `GP.ps1`, à la racine, est un lanceur compilable par PS2EXE ; `GP.cmd` constitue le point d’entrée par double-clic. La configuration, l’icône et le module AD se trouvent dans `wad`. Il n’y a pas de dossier `mod`, de patch à appliquer, ni de conversion du moteur en application C# native. Les fonctions métier de la RC1 restent dans le moteur, avec les mêmes verrous de sécurité.

Le thread STA possède WPF. Les requêtes longues et les mutations sont envoyées aux runspaces. Les callbacks nommés reviennent vers l’état réel du script principal ; la file ne modifie pas ses réglages pendant une action. Le worker reçoit une photographie des paramètres et une copie des fonctions métier nécessaires, avec des fonctions de journalisation adaptées et sans affichage modal depuis le runspace.

La prévisualisation est une validation en mémoire. Les précontrôles réels restent dans le moteur, juste avant mutation, avec des possibilités de course inhérentes à un annuaire partagé. La file est séquentielle ; l’objectif n’est pas de paralléliser les écritures AD.

## Chemin d’une action

`Run-Queue` valide et confirme la sélection, puis crée un état de lot. `Start-GPNextQueueTask` traite une seule ligne ; avant une mutation réelle il vérifie l’audit et écrit le checkpoint Active. Le worker répète les contrôles de la ligne puis appelle le moteur. `Complete-GPQueueItem` exige un résultat exploitable, complète la ligne une seule fois, incrémente les compteurs et décide de continuer ou d’arrêter la file. Le Dispatcher planifie l’action suivante sans appel récursif direct.

En mode hors domaine, l’action est la jonction du poste local. En mode joint, elle est un renommage, un déplacement ou leur combinaison. Le renommage précède le déplacement. Le moteur local n’utilise pas les paramètres d’administration distante pour renommer le poste courant.

## Contrat de résultat

| Code | Sens |
|---|---|
| 10 / 11 / 13 | Jonction confirmée / refusée / compte déjà existant |
| 20 / 21 / 69 | Renommage confirmé / refusé / nom occupé |
| 30 / 31 / 33 | Déplacement confirmé / refusé / déjà dans l’OU |
| 32 | Protection d’origine non rétablie : arrêt et verrou |
| 77 | Renommage et déplacement confirmés |
| 88 | Nom occupé lors de l’action combinée |
| 89 | Renommage réussi, déplacement non terminé : résultat partiel |
| 97 | État incertain : arrêt et verrou, aucun replay automatique |
| 98 | Résultat/worker technique défaillant : arrêt et verrou conservateur |
| 99 | Précontrôle/objet/erreur métier inattendue selon le chemin |
| 40 / 41 | Redémarrage demandé / refusé, diagnostic distinct du résultat AD |

Une réussite AD avec un redémarrage refusé reste un résultat AD réussi, accompagné de l’échec de demande de redémarrage. Le bilan l’indique séparément dans le message. Une demande de redémarrage acceptée n’est pas une preuve que le poste a redémarré ni que la jointure est saine après démarrage.

Les événements d’échec inattendus de l’interface empêchent la suite du lot sans tuer un worker qui pourrait être en train de modifier la machine. Une incohérence de comptage déclenche également un verrou ; elle n’est pas masquée par un bilan 0/0.

## Données persistées

Le CSV inclut les champs métier et les résultats. L’import valide tout le fichier avant modification de la DataTable et ne supprime pas silencieusement une ligne existante. Les lignes importées sont décochées ; un historique incertain conserve un blocage.

La reprise utilise un schéma JSON versionné et vérifie domaine, poste opérateur, taille et nombre de lignes. Une action Active au crash devient incertaine à la reprise. Les écritures atomiques créent d’abord un fichier temporaire dans le même dossier puis remplacent la destination. Les erreurs d’audit ou de checkpoint empêchent une nouvelle mutation réelle ; les limites matérielles et interprocessus sont détaillées dans SECURITE.md.
