# Complément RC5

La RC5 compare le GUID préparé et l'OU source avant mutation. Le contrôle préalable est une lecture datée, pas une autorisation de mutation. Aucun secret ni credential n'est ajouté à l'historique. Les exports contiennent des données techniques internes. Voir INNOVATIONS_RC5.md pour les limites.

---

# Sécurité, exploitation et limites

## Secrets et authentification

Le transport d’administration planifiée passe par `Schedule.Service`. Le credential est remis à l’API COM en mémoire ; aucun mot de passe n’est construit dans les arguments de `schtasks.exe`. Cela ne signifie pas « mot de passe jamais présent en mémoire » : les API ont besoin du secret et certaines conversions produisent temporairement des chaînes .NET non effaçables de façon garantie. Le credential reste nécessaire durant la session GP.

Une tâche enregistrée avec un logon de type Password est gérée par le Planificateur Windows et son mécanisme de stockage d’identifiants. GP ne prétend pas empêcher tout stockage par Windows. Les tâches terminées sont supprimées au mieux ; une tâche au résultat incertain peut être conservée pour diagnostic et doit alors faire l’objet d’un contrôle et d’un nettoyage par l’administrateur.

Pour l’élévation locale, le canal nommé possède des ACL limitées à l’utilisateur courant et aux administrateurs. Le PID du client doit correspondre au helper élevé démarré avant transmission du credential. Ces protections doivent être testées sous UAC avec consentement et avec saisie d’un autre administrateur. Elles ne protègent pas contre un administrateur local malveillant, une injection dans le processus, un système compromis ou tous les dénis de service.

Les scripts helper ne contiennent pas le mot de passe sur leur ligne de commande. Leurs paramètres non secrets, comme l’OU et le nom cible, peuvent rester visibles aux outils d’administration et d’audit. La politique d’élévation Windows demeure applicable ; GP ne promet pas de supprimer une demande UAC obligatoire.

## Entra, protection AD et actions incertaines

`AllowHybridRepair=false` par défaut. L’activer permet une opération impactante (`dsregcmd /leave`) dans le chemin de réparation après blocage de renommage ; cela peut affecter la jointure Entra et l’authentification du poste. Ne l’activer qu’après diagnostic sur une maquette et procédure approuvée de réinscription. GP ne garantit pas la réinscription après redémarrage.

Le déplacement utilise le GUID et tente de restaurer la protection anti-suppression d’origine. Ce n’est pas une transaction distribuée : une erreur réseau ou de droits peut laisser un état partiel. Les codes 32 et 97 existent précisément pour signaler cette situation et bloquer la suite.

Un résultat inconnu n’est pas un échec sans effet. Après code 32/97/98 : conserver les journaux, vérifier le nom réel du poste, l’objet AD par GUID, l’OU, la protection, les tâches `\GP_*` sur la cible et l’éventuel redémarrage en attente. Lever le verrou seulement après cette vérification. Le bouton ne réalise pas ces contrôles à la place de l’opérateur.

## Journaux et reprise

Audit : premier emplacement inscriptible parmi `logs` près du programme, `%LOCALAPPDATA%\GP\logs` et `%TEMP%\GP\logs`. Le chemin effectif est affiché. Les journaux `GP_*.log` de plus de 30 jours sont purgés au mieux au démarrage dans le dossier sélectionné. Revoir cette rétention et les permissions selon les règles internes. Les logs distants de tâches sous `C:\ProgramData\GP` nécessitent une politique de rétention distincte.

La file de reprise est située sous `%LOCALAPPDATA%\GP\State\<identifiant de configuration>`. Elle contient les postes, OU, actions et résultats, pas le credential. Elle dépend du profil utilisateur et du chemin de configuration ; elle n’est pas signée ni chiffrée par GP. Une modification manuelle malveillante par un utilisateur du profil ou un administrateur n’est pas exclue. Après un crash, les lignes restent décochées et les incertitudes maintiennent le verrou.

Le masquage des secrets dans les textes est une protection limitée à des formats reconnus (`password=...`, `pwd=...`, etc.), pas un moteur de détection universel. Relire tout export/diagnostic avant transmission. La neutralisation des formules CSV vise les tableurs ; elle n’empêche pas toutes les interprétations de tous les logiciels tiers.

## Limites d’exploitation connues

Les délais de polling ne sont pas des limites absolues : un appel COM/RPC bloqué peut prendre plus longtemps. L’arrêt demandé ne coupe volontairement pas une mutation en vol ; l’interface reste dépendante de la fin du worker. La tâche possède aussi sa propre limite d’exécution Windows. Un arrêt forcé externe doit conduire à une vérification manuelle, pas à une relance aveugle.

Une seule instance de GP doit utiliser une configuration à la fois. Pas de mutex interprocessus ni de coordination avec un autre outil AD ; les états peuvent changer entre prévisualisation et exécution. Les contrôles de nom ne réservent pas un nom dans l’annuaire. Le DC observé n’est pas une garantie de convergence immédiate de tous les DC.

La compilation PS2EXE n’est ni une obfuscation sûre ni une signature. Ne jamais embarquer de secret dans le source. Les politiques AppLocker/WDAC, AMSI, signatures et EDR doivent être validées par l’organisation. Aucun contournement ni exclusion antivirus n’est proposé. Le module AD joint et l’icône sont inchangés, pas certifiés par cette livraison ; vérifier provenance, signatures, droits de redistribution et compatibilité avant déploiement.

## Références primaires consultées

Microsoft, `Add-Computer` : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer?view=powershell-5.1

Microsoft, `Rename-Computer` : https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/rename-computer?view=powershell-5.1

Microsoft, `TaskService.Connect` : https://learn.microsoft.com/en-us/windows/win32/taskschd/taskservice-connect

Microsoft, `TaskFolder.RegisterTask` : https://learn.microsoft.com/en-us/windows/win32/taskschd/taskfolder-registertask

Microsoft, `GetNamedPipeClientProcessId` : https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid

Projet PS2EXE, paramètres et limites : https://github.com/MScholtes/PS2EXE

Ces références documentent les API ; elles ne constituent pas une validation de ce projet sur le parc réel.


## RC2 : déblocage de fichiers et dossier wad

`DEBLOQUER_TOUT.cmd` ne lève pas les verrous de la file GP et ne donne pas de droits AD. Il retire seulement le flux de provenance des fichiers présents sous son propre dossier, après confirmation, en ignorant les points de réanalyse. Ce contrôle n'est pas une isolation face à un acteur hostile modifiant simultanément le dossier ; ne pas l'exécuter dans un emplacement partagé non maîtrisé.

Le code est lisible dans le CMD. Il ne télécharge rien, ne lance pas le moteur, ne s'élève pas automatiquement et ne change ni les ACL ni les politiques du système. Les erreurs sont conservées dans son bilan ; le script ne demande pas de désactiver l'antivirus en cas de refus.

Le lanceur `GP.cmd` demande RemoteSigned pour son processus seulement. Les restrictions imposées par les GPO, AppLocker ou WDAC ne sont pas supprimées. Le déplacement de la configuration modifie la clé de stockage de reprise basée sur son chemin absolu : aucun ancien verrou ou travail interrompu ne doit être ignoré lors d'un changement de dossier. Voir la procédure de mise à jour dans README.md.

## Frontière avant lancement du worker, RC4

Le code 96 n'est émis que lorsque le contrôle local du journal ou du checkpoint échoue avant `Start-GPAsyncOperation`. La ligne et celles qui suivent n'ont pas été envoyées au worker ; elles sont comptées NON LANCÉ. Ce chemin ne modifie pas le verrou d'incertitude. Une erreur après lancement, une protection non rétablie ou un résultat absent conserve les codes et les verrous précédents. La RC4 ne déduit jamais automatiquement que les anciens incidents RC3 sont tous sans mutation.

Le déplacement lié au renommage est calculé avant confirmation et recontrôlé avec l'OU relue. Un déplacement non présenté dans le plan ne peut pas être ajouté par le worker sans nouvelle préparation. La sélection d'une OU seule ne déclenche plus de déplacement implicite. Les déplacements explicitement préparés sans renommage restent disponibles.
