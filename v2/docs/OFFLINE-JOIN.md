# Jonction hors connexion locale (ODJ)

Pesto V2 possède un parcours de jonction hors connexion dans le **même `Pesto.exe`**. L’opérateur importe un blob déjà provisionné pour le nom Windows actuel du poste, vérifie les références déclarées, confirme une application unique, puis redémarre le poste lui-même. Le résultat final n’est vérifié qu’après une action explicite d’observation Windows/AD.

Ce guide décrit les chemins raccordés dans le code. Il ne certifie pas leur exécution sur Windows, un vrai blob ODJ ou un domaine : les preuves de validation du commit et la qualification native restent distinctes.

## Préparer et distribuer la configuration

Dans **Paramètres**, section **Politiques**, activer **Autoriser la jonction hors ligne locale**, préparer les différences puis confirmer l’enregistrement. La clé est `POLICY.AllowOfflineJoin`, un booléen strict désactivé par défaut sur un profil neuf. Elle est conservée lors d’un export/import et dans la configuration par défaut de l’installation écrite par **Définir comme configuration par défaut**. Il n’est pas nécessaire de modifier un JSON ou un manifeste à la main.

Le domaine unique, les OU gérées, le nommage et les politiques viennent de ce profil. Les valeurs distribuées ne contiennent aucun blob, mot de passe, historique, reçu ou cache. Elles sont écrites dans `wad\defaults\configuration.json`, qui ne modifie ni l’identité ni la provenance du pack ; ce fichier contient le domaine et les OU et se diffuse comme un fichier privé. Les règles générales sont dans [CONFIGURATION.md](CONFIGURATION.md).

Les options CLI `UnattendedJoinEnabled` et `UnattendedOperationsEnabled` sont indépendantes d’ODJ. Leur activation n’applique pas un blob. Ce parcours local utilise uniquement les cinq opérations d’interface décrites ci-dessous ; il ne convertit pas une jonction AD ordinaire en jonction hors ligne.

## Ouvrir la fenêtre locale

Deux entrées utilisent le même exécutable :

- Dans Pesto normal, ouvrir **Ajouter ce PC → Jonction hors ligne**. Une fenêtre distincte conserve le contexte normal et utilise un profil WebView séparé.
- Sur le poste hors domaine, lancer explicitement :

```text
Pesto.exe --offline-join
```

L’entrée locale résout d’abord le profil Windows d’origine. Si une élévation UAC est nécessaire, le relais conserve son SID ; le chemin est dérivé du registre machine, sans accepter un chemin de profil fourni par l’interface. Un LocalAppData redirigé, un chemin réseau ou une jonction de profil non pris en charge provoque un refus avant initialisation.

Sur cette entrée explicite, un `cfg.json` absent peut être initialisé depuis `wad/defaults/configuration.json`, lu localement dans le dossier `wad` de l’installation. Un profil existant n’est pas remplacé et ne reçoit pas silencieusement de nouvelles valeurs distribuées. Sans configuration disponible ou sans `AllowOfflineJoin`, la page indique pourquoi l’import est indisponible ; elle n’invente pas de domaine ni de paramètres.

La fenêtre utilise `OfflineJoinBackend`, sans construire `LiveBackend`, sans invite d’identification AD ordinaire et sans chargement du tableau de bord AD. Son `session.info` repose sur les faits locaux. Les API métier, de maintenance et de configuration hors de ce parcours sont refusées par ce backend.

## Conditions d’admission

L’import, la préparation et l’application exigent des preuves locales complètes :

- processus administrateur local, Windows PowerShell 5.1 et composant Windows `djoin.exe` disponibles ; PowerShell 7 n’est pas requis ;
- poste hors domaine, rôle Windows 0 ou 2, nom actif et nom configuré identiques, sans renommage en attente ;
- identité `MachineGuid` et heure de démarrage Windows stables et lisibles ;
- GUID AD provisionné complet et non vide, OU déclarée dans le domaine et le périmètre configurés ;
- `AllowOfflineJoin=true`, sans session de consultation, `IncidentMode` ou option DEBUG incompatible ;
- aucune coordination partagée configurée/obligatoire, ni exclusion de groupe AD exigeant une lecture en ligne ;
- aucun reçu GP contradictoire, incomplet ou encore bloquant pour l’opération locale.

Les exclusions de noms/OU et le scénario configuré restent appliqués. Les restrictions HKLM sont relues localement. ODJ ne lance pas d’inventaire AD, de réservation de nom, de création de compte AD ni de correction d’horloge. Comme le parcours V1 hors ligne, `BlockJoinOnClockSkew=true` n’oblige pas à contacter un DC avant l’application du blob. L’existence du compte et de l’OU déclarés n’est pas annoncée comme prouvée avant l’observation après boot.

## Parcours opérateur

### 1. Lire les faits locaux

La page affiche le nom Windows actif, le nom configuré, l’identité machine, l’appartenance observée, le dernier démarrage prouvé et l’état administrateur. **Relire l’état local** reste une lecture locale. Un état inconnu n’est jamais remplacé par « hors domaine » ou par une valeur supposée favorable.

### 2. Importer le blob

Renseigner le **GUID AD déclaré du compte provisionné** et l’**OU AD déclarée**. Confirmer les références et le nom local affiché, puis choisir le fichier dans la boîte de dialogue Windows.

Le chemin sélectionné reste côté hôte natif. Aucun chemin de blob, octet secret, base64 de blob ou mot de passe ne transite dans WebView. Le service lit un fichier local ordinaire de 1 octet à 1 Mio et refuse les chemins réseau, les liens et les jonctions avant de lire leur contenu. Les ancêtres sont contrôlés avant leurs descendants pour ne pas suivre une jonction vers un partage.

Le SHA-256 des octets identifie le blob. Le secret est chiffré par DPAPI **LocalMachine** et conservé sous une ACL limitée à SYSTEM et aux administrateurs locaux. Le fichier choisi demeure intact à son emplacement d’origine. L’import ne lance aucune jonction et ne prouve pas les références AD déclarées.

Le même blob ne peut pas être importé une seconde fois, y compris après fermeture de Pesto ou si son empreinte existe dans le stockage historique V1. Un import partiel reste visible comme incomplet et n’est pas automatiquement réinitialisé. Le registre est limité à 500 imports ; l’admission du suivant est refusée avant création, en conservant les preuves déjà présentes.

### 3. Préparer puis confirmer l’application

**Préparer l’application locale** relit configuration, identité, politiques, secret protégé et barrières GP. L’import expire après 24 heures. Le plan temporaire expire au plus tard cinq minutes après sa préparation et ne prolonge jamais la validité de l’import.

Le plan affiche le **nom Windows actuel**, le domaine, le GUID et l’OU déclarés, son expiration et les conséquences. Il ne calcule pas un autre nom. Une modification de la configuration, de l’identité locale, du journal ou une expiration impose un nouveau contrôle ; elle ne choisit jamais une autre cible.

La confirmation finale affiche le nom du poste et demande d’autoriser l’application unique. Le nom du plan confirmé est transmis au moteur, qui le contrôle de nouveau ; aucune recopie n’est demandée. Un redémarrage survenu entre l’import et l’application n’est pas pris pour le redémarrage requis après application : le journal conserve séparément la baseline du boot au moment de l’intention `Requested`.

### 4. Lire le résultat de l’application

Le mutex historique `Global\GP_PostMutation_v1` couvre l’admission, les écritures durables et l’appel natif. Avant le premier effet possible, Pesto enregistre une intention immuable `Requested` et son reçu métier. Le worker crée et flushe ensuite un marqueur natif exclusif avant le seul appel :

```text
djoin.exe /requestodj /loadfile <fichier local privé> /windowspath <Windows> /localos
```

Le nom d’exécutable et les options viennent du code fixe. Le worker attend dans un bootstrap lié au hash du script jusqu’à son rattachement à un JobObject appartenant à Pesto. Une disparition du parent ne laisse pas volontairement son worker tourner hors du conteneur ; la fermeture du conteneur ne constitue jamais une preuve de rollback. Les sorties de `djoin.exe` sont drainées sans être matérialisées, publiées ou ajoutées aux journaux.

| État durable | Signification | Action disponible |
|---|---|---|
| `Imported` | Copie protégée, aucune application demandée | Préparer puis confirmer avant expiration |
| `Requested` | Intention consommée ; un envoi a pu commencer ou son résultat a été perdu | Observation dédiée après redémarrage, aucun rejeu |
| `PendingRestart` | `djoin.exe` a renvoyé 0 et sa fin a été confirmée ; code métier 10 | Redémarrage manuel puis observation |
| `Uncertain` | Réponse, résultat natif, enregistrement final ou preuve d’observation incomplet | Conserver les reçus et observer ; aucune nouvelle application |
| `Verified` | Nouveau boot et preuves Windows/AD complètes concordent | Consulter la preuve historique ou observer à nouveau |

Le code natif 0 n’est pas un succès final de jonction. Un code natif non nul ou une réponse perdue après l’intention reste incertain ; le blob n’est jamais remis dans l’état `Imported`. Le résultat ne devient pas une erreur « sans effet » qui autoriserait une seconde application.

Le secret éphémère et sa copie protégée sont supprimés seulement lorsque leur nettoyage exact est autorisé et leurs empreintes correspondent encore. Si la fin du worker ou la suppression ne peut pas être prouvée, les fichiers privés et les preuves sont conservés, avec un diagnostic. Une écriture d’audit éventuelle intervient après le reçu durable et ne contient jamais le blob.

### 5. Redémarrer manuellement puis observer

Pesto ne redémarre pas le poste dans ce parcours. Après un redémarrage décidé par l’opérateur, relancer la même fenêtre locale et sélectionner **Observer après redémarrage — accès AD** sur le reçu concerné. Ce bouton reste disponible même quand le poste est désormais membre du domaine et que de nouveaux imports sont indisponibles.

Avant tout accès AD, Pesto exige que l’identité machine et les noms Windows correspondent au reçu, que le poste soit membre du domaine prévu avec un rôle 1 ou 3, et que le boot observé soit plus récent que celui de l’application. Une condition locale non prouvée produit un résultat non vérifié sans contacter AD.

L’observation explicite découvre ensuite un DC du domaine prévu et lit le compte par son GUID déclaré. Elle exige ensemble : GUID exact, nom exact, OU exacte, domaine exact, absence de rôle contrôleur de domaine et canal sécurisé valide. Les faits Windows sont relus après la lecture AD. Il n’y a ni `Test-ComputerSecureChannel -Repair`, ni nouvelle jonction, ni renommage, ni redémarrage.

La preuve complète est ajoutée au journal immuable avant la projection du reçu `Verified`, code métier 30. Le miroir est lié au SHA-256 d’un événement réel de cette chaîne. L’historique et les barrières ne considèrent pas comme preuve un simple JSON terminal dont le journal manque ou a changé. Une observation ultérieure qui échoue ne réécrit pas une preuve historique vérifiée en faux échec sans effet ; l’interface distingue le contrôle courant non confirmé du résultat historique conservé.

## Interruption, concurrence et journaux V1

Les événements ODJ V2 sont conservés sous `%ProgramData%\GP\V2\offline-join\<empreinte>\events`, avec séquence, hash précédent, identité, configuration et baseline. Le reçu métier est sous `GP\V2\receipts`. Les créations d’événements sont exclusives ; les miroirs ne sont remplacés que si leurs octets correspondent toujours à l’empreinte attendue. Une collision, un fichier modifié, lié ou tronqué est conservé et bloque l’action qui aurait dû s’appuyer dessus.

Après une interruption entre l’intention durable et le tout premier miroir, une observation explicite peut créer uniquement cette projection encore absente. Elle ne renvoie pas la demande native. Une projection déjà référencée puis disparue ou remplacée n’est pas réparée silencieusement.

Les anciens fichiers `GP\OfflineJoin\<empreinte>.json` et `.protected` restent reconnus pour les doublons et les barrières. Un reçu V1 demandé ou incertain est signalé comme historique V1, sans être ignoré. **Cette version ne migre pas ces imports, ne rejoue pas leurs blobs et ne convertit pas leurs journaux en preuves V2.** La fenêtre locale décrit ses propres imports V2 ; elle ne prétend pas offrir une migration des imports ODJ V1 existants.

Les voies génériques d’acquittement, réconciliation ou redémarrage ne libèrent pas un ODJ à partir du seul nom ou de l’OU. L’observation ODJ dédiée est le chemin de vérification. Un changement de nom local hors Pesto ne suffit pas à contourner une ancienne intention ODJ non résolue sur la même machine.

## Isolation et limites de qualification

Les constructeurs du service et du provider n’effectuent aucun IO. Les appels directs en modes démonstration, contrôle de santé et récupération binaire sont refusés avant lecture de configuration, sonde native, accès au blob ou au registre GP. Les remplacements binaires et rollbacks ne réinitialisent pas le profil réel. La session de consultation refuse aussi les opérations qui écrivent des preuves.

Le code de tests portable exerce le vrai format du journal et du miroir avec un provider injecté : intention durable avant effet, confirmation, concurrence, interruption, absence de rejeu, nouvelle baseline du boot, erreurs de GUID/canal, barrières V1, isolation, limite du registre et options de configuration. Le fait que ces cas soient écrits ne signifie pas qu’ils ont réussi pour le commit courant. Consulter les résultats datés dans [VALIDATION-REPRISE-20261025.md](VALIDATION-REPRISE-20261025.md).

Restent à qualifier sur un environnement Windows/AD explicitement autorisé : UAC avec un compte administrateur différent, droits NTFS, DPAPI machine, démarrage/fermeture de la fenêtre WebView, application d’un vrai blob, comportement de `djoin.exe` lors d’une interruption, redémarrage manuel et preuve AD/canal après boot. La compilation, l’analyse syntaxique PS5.1 et les fixtures ne suffisent pas à qualifier ces effets. Le protocole global figure dans [QUALIFICATION-WINDOWS.md](QUALIFICATION-WINDOWS.md).
