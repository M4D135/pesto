# GP 17.0-RC13 : connexion Windows intégrée

## Périmètre livré

Sur un PC membre du domaine configuré, `GP.cmd` demande l'UAC si nécessaire, puis ouvre GP avec le compte Windows du processus élevé. Il n'affiche plus le formulaire de login GP par défaut. Si GP est déjà élevé, aucun nouveau relais UAC n'est demandé par le lanceur.

La connexion utilise le jeton Windows, pas un mot de passe récupéré dans l'UAC. Le compte effectif apparaît dans l'écran d'attente, puis dans le bandeau de l'application. L'identité du worker AD est comparée à cette identité avant de valider la lecture initiale. Cette lecture ne prouve pas les droits d'écriture sur chaque objet.

Le mode intégré ne crée pas de PSCredential, n'enregistre pas de mot de passe et ne modifie ni l'UAC, ni les stratégies de sécurité, ni la délégation Kerberos. Les cmdlets AD omettent le paramètre Credential au lieu de lui passer une valeur nulle.

## Opérations et limite importante

| Parcours | Comportement RC13 |
|---|---|
| Ouverture sur PC membre du domaine | UAC si nécessaire, puis connexion Windows automatique. |
| Lectures AD et déplacement d'OU | Compte Windows courant ; AD conserve le contrôle des autorisations. |
| Renommage du PC exécutant GP | Appel local Win32_ComputerSystem.Rename via CIM/WMI, sans mot de passe explicite. |
| Renommage d'un autre PC | Le moteur RPC actuel conserve les identifiants AD explicites. La file est refusée avant son lancement si elle en a besoin et qu'ils manquent. |
| Poste hors domaine | Formulaire explicite et parcours de jonction existants conservés. |
| Démonstration | Pas de connexion AD ni d'élévation réelle. |

**Cette livraison ne promet pas un renommage distant sans mot de passe.** Un jeton UAC ne fournit pas à GP le mot de passe utilisable dans l'appel distant. Aucun compte SYSTEM ni tâche locale ne sont utilisés comme substitut improvisé pour l'accès au domaine.

Pour choisir volontairement le parcours explicite, lancer `GP_COMPTE_AD.cmd` ou `GP.cmd -AskCredential`. Ce choix peut conduire à UAC puis formulaire GP. Il ne faut donc pas utiliser ce lanceur pour tester la connexion unique automatique.

Si le compte autorisé dans l'UAC est un compte local, si l'accès AD échoue ou si le domaine est incorrect, l'application affiche l'erreur. Elle ne rouvre pas automatiquement un deuxième login. Les boutons Réessayer, Annuler et Autre compte AD permettent un choix explicite. Le compte autorisé dans l'UAC doit être un compte du domaine disposant des droits nécessaires, pas obligatoirement Domain Admin.

## Renommage local : ce qui change

Le moteur conserve ses précontrôles AD (source, périmètre, identité et disponibilité du nom). En l'absence de credential explicite et pour la cible locale uniquement, il vérifie ensuite le jeton, le nom et le domaine observés localement, le rôle membre Windows et la disponibilité de la cmdlet CIM.

La préparation Entra déjà présente en RC12 est appelée sans modification de ses fonctions. Le renommage n'est lancé qu'après son résultat confirmé. L'appel CIM porte sur l'instance Win32_ComputerSystem locale ; il ne passe ni ComputerName distant, ni CimSession, ni UserName, ni Password. Il n'a besoin d'aucun service WinRM.

Seul un résultat unique avec ReturnValue numérique égal à zéro est accepté comme réussite. Un résultat absent, mal formé ou une exception après l'appel devient un état incertain, sans second essai automatique. Les codes Windows non nuls restent des erreurs. Le redémarrage n'est pas implicite.

Règle inchangée : site différent => renommage puis déplacement après confirmation ; même site => renommage seul et OU conservée. L'audit, les verrous et les reprises sont conservés. Aucun ancien verrou n'est supprimé lors de l'installation.

## Installation

Fermer GP seulement après vérification des anciennes actions en cours ou incertaines. Sauvegarder le dossier existant, notamment `wad\cfg.json`.

Extraire le correctif directement à côté de `GP.cmd`, en remplaçant les fichiers. Il faut remplacer **les trois fichiers** `GP.ps1`, `wad\GP-Startup.ps1` et `wad\GP-Core.ps1`, pas seulement le moteur. Le correctif ne contient aucune configuration, aucun état de file ni ressource AD de remplacement.

Exécuter `DEBLOQUER_TOUT.cmd`, puis `TEST_CONNEXION_UNIQUE.cmd` et `TEST_TOUT.cmd` sur le poste de recette. Le premier lance des tests isolés avec des doubles AD/CIM/Entra ; il ne renomme pas le poste de test. Le second reprend les suites existantes. Ces tests n'ont pas été exécutés dans l'environnement de fabrication Linux.

Ensuite lancer **`GP.cmd`**, sans `-AskCredential`. Utiliser dans l'UAC le compte de domaine autorisé sur le poste. L'écran d'attente porte la version 17.0-RC13 et indique le compte utilisé, sans champ de mot de passe. Après la lecture AD, le bandeau de l'application indique ce même compte.

La première recette réelle doit se faire sur une machine de test prévue pour être renommée, avec sa procédure de réinscription Entra vérifiée. Un test unitaire vert ne garantit pas les droits effectifs ou la configuration du domaine.

Avec le pack complet, remettre impérativement la configuration opérationnelle. Les fichiers cfg reçus ont été conservés à l'identique ; ils peuvent être anonymisés. Aucun EXE n'est compilé dans cette livraison.

## Traces attendues

`GP-demarrage.log` indique le choix du relais et `Admin=True confirme`. Le journal d'audit GP indique l'identité de connexion, puis `AuthMode=Windows` et `CredentialEnMemoire=False`. Ces lignes décrivent la connexion ; elles ne prouvent pas qu'un renommage a eu lieu.

Pendant un renommage local intégré, l'étape doit annoncer « Renommage local avec le compte Windows ». Les messages Entra et les contrôles de mutation restent visibles. En cas d'erreur, ne pas relancer en boucle et ne pas effacer l'état de sécurité.

## Références techniques consultées

Ces références décrivent les mécanismes Windows, pas une validation réelle de GP dans votre domaine.

- Microsoft : Win32_ComputerSystem.Rename, UserName nul => contexte appelant ; succès zéro ; restriction des appels distants sur les postes de domaine.
  https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/rename-method-in-class-win32-computersystem
- Microsoft : NetRenameMachineInDomain, contexte local possible, identifiants exigés pour l'appel distant sans délégation.
  https://learn.microsoft.com/en-us/windows/win32/api/lmjoin/nf-lmjoin-netrenamemachineindomain
- Microsoft : Invoke-CimMethod, appel local COM lorsqu'aucune session/cible distante n'est fournie, et jeu de paramètres Query pour les instances.
  https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/invoke-cimmethod?view=powershell-5.1
- Microsoft : UAC et jetons d'accès.
  https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works
