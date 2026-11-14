# Passer de GP à Pesto

## Ce qui est renommé

`GP.exe` devient **Pesto.exe**, réellement recompilé avec son nom et ses métadonnées.
`wad\GP-*.ps1` et `GP-*.xaml` deviennent `Pesto-*.ps1` et `Pesto-*.xaml`.
Le point d'entrée est `wad\Pesto-Startup.ps1`. Aucun Pesto.ps1 n'est requis à la racine.
Les fonctions préfixées GP et les espaces de noms du code embarqué utilisent Pesto.
Les nouveaux rapports, journaux, fichiers temporaires et tâches utilisent Pesto.
Les générateurs produisent des dossiers **PROD** et **DEV** et des ZIP nommés Pesto.

## Pourquoi quelques identifiants techniques GP sont conservés

Il ne faut pas faire disparaître un verrou ou un reçu en changeant simplement le nom de l'application.
Les emplacements suivants restent des identifiants de compatibilité, pas du branding visible :

| Élément | Identifiant stable |
|---|---|
| Thème et disposition de l'utilisateur d'origine | `HKEY_USERS\<SID>\Software\GP\Appearance` |
| Préférences héritées à côté de cfg.json | `gp.prefs.json` |
| File et historique par chemin de configuration | `%LOCALAPPDATA%\GP\State\<id>` |
| Reçu de jonction | `%ProgramData%\GP\Join\receipt.json` |
| Reçu du parcours unitaire | `%ProgramData%\GP\Operations\direct.json` |
| Exclusion entre mutations et instances | mutex `GP_PostMutation_v1`, `GP_Session_…`, `GP_Launcher_…` |

Aucun déplacement, conversion ou effacement automatique de ces données. Leurs schémas et
les contrôles de sécurité restent identiques. Le nom du mutex partagé n'est pas un droit supplémentaire.
Conserver le même emplacement de cfg.json, puisque l'identifiant de la file dépend de son chemin.
Les anciens journaux restent sur disque ; les nouveaux journaux applicatifs portent Pesto.

## Mise à jour dans votre installation configurée

1. Vérifier l'issue des opérations en cours ou incertaines. Fermer GP normalement.
2. Sauvegarder le dossier entier et les éventuels états externes selon votre procédure.
3. Copier `Pesto.exe`, `DEBLOQUER_TOUT.cmd` et tous les composants applicatifs de `wad` depuis PROD,
   y compris `wad\package.json`, **sans remplacer votre `wad\cfg.json`** ni vos fichiers de données.
4. Garder le même dossier d'installation et le même chemin de configuration.
5. Retirer l'ancien `GP.exe` et ses raccourcis. Les anciens `wad\GP-*.ps1`/`GP-*.xaml` ne sont plus
   chargés par Pesto ; les retirer seulement une fois la sauvegarde faite. Ne pas supprimer
   les dossiers GP de ProgramData, LocalAppData ou du registre.
6. Débloquer le nouveau pack si nécessaire, lancer `Pesto.exe --check`, puis effectuer la recette
   Windows depuis DEV avant utilisation réelle. Mettre à jour les raccourcis vers Pesto.exe.

## Périmètre conservé

Même site : renommage seul. Site différent : renommage puis déplacement après confirmation.
Jonction locale sur sa page dédiée, sans file. Pas de redémarrage implicite. Connexion Windows
intégrée en domaine, parcours explicite hors domaine et restrictions de renommage distant conservés.
La préparation Entra n'est pas modifiée. Une erreur ou un délai dépassé ne signifie pas annulation Windows.

Le code et l'EXE livrés sont renommés ; le moteur n'est pas réécrit en C.
La marque Pesto n'a pas fait l'objet d'une recherche de disponibilité.
