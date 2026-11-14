# Contrat du pont Pesto V2

Le transport local reprend le modèle Domenia : requête `{id,op,args}`, résultat `{id,kind:"result",op,data}`, erreur `{id,kind:"error",op,error:{code,message}}`. `Pesto.Core.IPestoBackend.InvokeAsync` est le contrat moteur. `BridgeDispatcher` est l’autorité du schéma : propriétés inconnues/répétées refusées, message limité à 1 Mio, profondeur 24, identifiants bornés, concurrence bornée, aucune commande/script ni objet hôte arbitraire.

Un chemin externe est admis comme source explicite d’inspection d’un pack de mise à jour ou comme valeur du dossier de coordination dans un aperçu de paramètres. Enregistrer ce dernier ne le contacte pas : les API de coordination utilisent seulement la configuration active, jamais un chemin libre fourni à l’exécution. Les imports/exports et destinations personnalisées sont choisis dans des dialogues natifs. Le mode démo refuse ces opérations **avant** d’inspecter un chemin, d’ouvrir un dialogue ou de créer un client réseau. Le moteur `ApplicationServicesBackend` impose également ces gardes lors d’un appel direct sans passer par le pont.

## Session de configuration locale

L’entrée native `Pesto.exe --settings`, une configuration absente ou invalide, ou l’annulation du choix/saisie de compte AD ouvrent `ConfigurationOnlyBackend`. Aucun fournisseur d’annuaire, de mutation ou d’identifiants AD n’est construit pour cette session. `session.info` expose `configurationOnly:true`, `readOnly:true`, `dc:null` et toutes les capacités métier désactivées avec une raison de reconnexion. Le champ `readOnly` concerne les opérations métier ; il n’interdit pas les écritures de configuration explicitement confirmées. Il n’existe pas de nouveau mode fictif `configuration` : la propriété `configurationOnly` distingue ce contexte réel local.

L’hôte ouvre Paramètres avec `?configuration=local`. La navigation, les raccourcis et la palette sont limités à **Paramètres / Aide** ; la bannière et l’état de connexion annoncent **Configuration locale / Annuaire non connecté**. Ce paramètre d’URL ne constitue aucune autorisation : le refus est aussi appliqué côté moteur.

Le backend local admet seulement `session.info`, `settings.get`, `diagnostics.read` et `logs.list`. Les autres opérations métier, dont `settings.save`, sont refusées avec `session.configurationOnly` avant lecture de leurs arguments. Le service d’application conserve les actions explicites de configuration, référentiels, mises à jour, démonstration isolée et reconnexion, sous leurs gardes habituelles. Il refuse aussi `offlineJoin.open` et `coordination.inspect/prepare/apply` avant tout dialogue ou accès externe. Les cinq opérations ODJ ne sont pas disponibles dans ce backend ; elles appartiennent à l’entrée distincte `--offline-join`. `coordination.status` reste une lecture des paramètres locaux, renvoie `configurationOnly:true` et ne prouve jamais que le partage est accessible ou préparé.

Une configuration nouvellement enregistrée ne crée pas d’adaptateur AD dans cette fenêtre. `host.reconnect` exige la confirmation, ferme la session et relance le même EXE avec le SID du profil d’origine et `--choose-account`. Au lancement réel ordinaire sur un poste membre du domaine, l’identité Windows effective après UAC est utilisée sans second choix systématique. `--choose-account` demande explicitement **Compte Windows / Autre compte AD** ; sur un poste en groupe de travail, la saisie native AD est requise. Une annulation de ce dialogue ramène au contexte local ; une annulation UAC termine le lancement concerné. Les options de compte et de profil restent natives : aucun identifiant, mot de passe ou chemin libre de profil n’est admis par le pont.

## Métier

| Opération | Arguments principaux | Résultat / garde |
|---|---|---|
| `session.info` | `{}` | Identité, domaine/DC observés, appartenance de ce poste au domaine lue par Windows (`localJoined`, `null` si inconnue), mode, lecture seule, capacités et raisons |
| `dashboard.read` | `{inventory?}` | L’accueil réel lit les reçus avec `inventory:false`. Rafraîchir lit aussi les compteurs et les sites du parc. |
| `directory.sites` | `{}` | Sites et OU réellement lus |
| `directory.services` | `{site}` | Codes et libellés du catalogue actif |
| `directory.search` | `{query,limit?}` | Liste bornée, complétude, date de lecture |
| `computer.inspect` | `{computer}` | GUID/OU/nom, type, contrôles observés et `inManagedScope` (`true` dans la racine, `false` hors racine, `null` si le DN ne permet pas de conclure) |
| `names.preview` | `{type,site,service,computer?,alternative?}` | Nom, OU, `previewId`, source, dates et complétude ; aucune mutation AD ; bail temporaire si coordination configurée |
| `join.precreated.preview` | `{name,targetOU?}` | Sélection explicite d’un compte précréé : nom, GUID, OU/GUID, DC et profil local liés à un `previewId` ; politique requise, aucune création |
| `operation.prepare` | `{kind,computer?,previewId?,newName?,targetOU?}` | Plan frais `join/rename/move/renameMove`, étapes/avertissements/expiration |
| `operation.execute` | `{planId,confirmationName,entraLeaveConfirmed?}` | Reçu ; nom exact, identité relue, plan consommé une fois ; consentement Entra séparé lorsque le plan l’exige |
| `queue.add` | `{kind,computer,previewId?,newName?,targetOU?}` | Ligne validée par les mêmes contrôles que le parcours unitaire |
| `queue.list/remove` | `{}` / `{id}` | File de la session |
| `queue.prepare` | `{pilot?}` | Lot relu avec `batchId`, `pilot`, `remainingCount` et expiration ; pilote : première ligne seulement |
| `queue.execute` | `{batchId,confirmed:true,entraLeaveConfirmed?}` | Reçus séquentiels ; poursuite après redémarrage en attente sur les cibles indépendantes, arrêt sur refus ou résultat incertain |
| `receipts.list/get` | `{query?}` / `{id}` | Registre durable et reçus de session ; illisibles signalés |
| `receipts.reconcile` | `{id}` | Relecture uniquement ; pas de rejeu de commande |
| `receipts.prepareMove` | `{id}` | Nouveau plan limité au déplacement restant d’un parent partiel 89 |
| `receipts.prepareAcknowledgement` | `{id}` | Plan de décision motivée lié aux octets exacts du reçu et aux preuves de fin d’activité ; aucune mutation AD |
| `receipts.acknowledge` | `{planId,confirmationName,reason}` | Événement durable distinct ; motif de 3 à 500 caractères, auteur Windows, résultat métier conservé |
| `receipts.prepareRestart` | `{id}` | Plan de redémarrage pour un reçu en attente ; identité Windows et cible courante fraîchement prouvées |
| `receipts.restart` | `{planId,confirmationName}` | Une demande explicite sans forçage, consignée avant envoi ; `accepted/refused/uncertain`, sans succès final inventé |
| `logs.list` | `{query?,level?}` | Journal de session, pas un historique fictif de fichiers jamais relus |
| `settings.get/save` | Schéma historique fermé | Compatibilité du moteur ; en réel, save limite les changements hérités à la convention |
| `diagnostics.read` | `{}` | Contrôles et raisons de refus |

Les objets de `directory.search` et `computer.inspect` exposent les facettes `type`, `site` et `service` de la convention active. Le type vaut `P`, `S`, `V` ou `null` quand le nom ne correspond pas à la convention. Le site d’un poste est son code de nommage. Pour une sélection, l’interface transmet le champ `selector` de `directory.sites`, qui contient le DN exact en mode réel. Elle utilise l’identifiant historique lorsque le sélecteur est absent.

Chaque changement de site ou de service relit l’annuaire. Pour un DN sélectionné, le lecteur vérifie l’OU, puis interroge les postes du site ou les noms de la série sur le contrôleur de domaine. La fenêtre peut réutiliser le processus PowerShell et son module AD entre deux lectures. Chaque requête produit un nouvel inventaire. Un aperçu n’est utilisable pour une opération qu’après relecture du nom au moment de la confirmation.

La résolution des sites déclarés lit une seule fois les OU enfants de chaque conteneur pour une demande, puis applique les motifs de sites à ce même instantané. Une nouvelle demande relit l’annuaire ; aucun cache persistant ni résultat partiel de secours n’est introduit.

Un reçu contient notamment `{id,time,kind,computer,newName,targetOU,mode,status,code,message,restartRequired}`. États : `simulated`, `succeeded`, `pendingRestart`, `refused`, `uncertain`. Un succès de commande et un besoin de redémarrage ne sont pas fusionnés en succès final. Un reçu partiel conserve son résultat même lorsqu’un enfant réussit.

La jonction est locale. Un simple renommage conserve l’OU source. Une collision demande un nouvel aperçu et un nouveau clic. Les politiques V1, barrières GP et identités sont contrôlées à la préparation et avant l’envoi. La disponibilité d’une capacité n’est pas une preuve de qualification Windows.

### Préparation, comptes précréés et Entra

La préparation d’un renommage effectue un diagnostic Windows/Entra. Sur un poste distant, elle peut créer et exécuter une tâche de diagnostic SYSTEM temporaire, bornée et journalisée ; elle ne renomme pas le poste et ne lance aucun retrait Entra. Les préparations sont donc sérialisées avec les autres opérations. Les preuves distantes associent nonce, requête, identité machine, GUID attendu et empreinte du reçu ; le résultat est enregistré localement avant le nettoyage exact du fichier possédé. Une preuve manquante reste inconnue. Un ancien reçu sans identité Windows initiale ne devient pas vérifiable par supposition.

Les plans de renommage exposent `entraLeaveRequired`, `entraState`, `entraPolicy`, `entraObservedAt` et `entraExpiresAt`. Un état inconnu ou incompatible refuse le plan. Un état hybride exige `HybridOnly`, une case de confirmation dédiée et `entraLeaveConfirmed:true` ; ce booléen ne crée aucune autorisation native. Le jeton interne à usage unique lie la configuration, les identités, la cible et l’observation. Une évolution d’AD seul vers hybride impose une nouvelle préparation. La demande de retrait est durable avant l’unique appel à `dsregcmd /leave` ; seule une relecture bornée prouvant AD seul peut confirmer le retrait. Un retrait confirmé reste un effet réel si le renommage échoue ensuite. Aucun réenrôlement ni redémarrage n’est automatique.

Le compte précréé apparaît avec son nom et son OU **avant** l’activation d’Ajouter au domaine. Le plan se prépare avec `kind:"join"` et le seul `previewId`, sans GUID ni autorisation de réutilisation fournis par le navigateur. Il expose `joinAccountMode:"precreated"` et `reservationRequired:false`. L’identité et l’OU sont relues avant exécution ; le compte n’est ni créé ni supprimé, même si la réservation AD est activée pour les jonctions ordinaires. Les règles Windows de réutilisation du compte restent applicables.

Un lot refuse les chaînes ou cycles entre noms sources et destinations. Sa préparation refuse aussi un résultat dont les premières autorisations ont déjà expiré : il faut alors préparer un lot plus petit. Les reçus des postes en attente de redémarrage restent individuellement non vérifiés lorsque le lot poursuit les autres cibles. Le booléen strict `pilot` appartient au lot préparé ; `queue.execute` ne l’accepte pas. Un pilote terminé conserve toutes les lignes suivantes et demande une nouvelle préparation/confirmation. Une incertitude ne produit jamais `pilotCompleted:true`.

### Acquittement, redémarrage et preuves après interruption

L’acquittement exprime une décision de l’opérateur ; il ne transforme pas un effet incertain en succès. Le plan de deux minutes est consommable une seule fois et exige le nom exact, le motif, le mutex GP, la configuration inchangée et l’absence prouvée d’activité encore engagée. La capacité distincte `acknowledge` reste permise en mode incident, comme V1, mais refuse la consultation, une indisponibilité native et les configurations fictives. L’événement séparé est lié aux empreintes des reçus, sans réécriture du parent ni d’un enfant. L’interface restitue ensuite le motif, l’auteur et la date, y compris après redémarrage de Pesto. Les reçus V1 peuvent recevoir cet événement V2 ; leurs fichiers restent intacts et l’ancien exécutable V1 conserve ses propres barrières.

`receipts.reconcile` est l’inspection explicite après une opération ou une interruption. Pour un retrait Entra dont la terminaison n’est pas prouvée, il peut lancer un **nouveau diagnostic en lecture** afin d’observer la fin de la tâche et de ses processus ; il ne relance jamais `/leave`. Une preuve de terminaison peut permettre un acquittement motivé, sans confirmer rétroactivement le résultat métier. Le chargement de la page et la préparation d’acquittement ne lancent pas cette inspection distante à l’insu de l’opérateur.

Le redémarrage réel possède un plan distinct et sa propre confirmation du nom Windows courant prouvé. La configuration d’autorisation actuelle est liée au plan et pincée sous GP ; politiques, exclusions et disponibilité sont revérifiées avant l’envoi. Une intention durable précède la commande sans `Force`. Une demande acceptée, incertaine ou encore demandée ne se rejoue pas sur le même boot. Le reçu métier conserve son résultat d’origine : seuls un nouveau boot stable et les observations Windows/AD requises permettent la vérification. Un résultat partiel 89 peut demander ce redémarrage si l’OU source et la protection initiale sont encore prouvées et qu’aucun enfant n’est engagé ; il reste partiel et son déplacement n’est jamais relancé par le redémarrage. Le redémarrage fictif de démonstration utilise une autre API et aucun adaptateur système.

## Attributs AD

| Opération | Arguments | Effet / garde |
|---|---|---|
| `attributes.inspect` | `{computer}` | Lecture AD explicite ; identité, valeurs initiales et `inspectionId` valable cinq minutes |
| `attributes.prepare` | `{inspectionId,values}` | Diff exact lié aux anciennes valeurs, GUID, DN, domaine, DC, OU et configuration |
| `attributes.apply` | `{planId,confirmationName}` | Une écriture confirmée, journal durable avant l’envoi, relecture puis reçu |
| `attributes.observe` | `{id}` | Observation explicite liée à un reçu V2 ; aucune modification AD rejouée |

`values` est un objet fermé de un à trois champs parmi `description`, `location`, `managedBy`. Une propriété absente reste inchangée ; une chaîne vide demande explicitement l’effacement. Les chaînes sont bornées à 1 024 caractères, sans caractère de contrôle ; espaces de description/emplacement conservés, aucun `trim` implicite. `null`, doublons et propriétés inconnues sont refusés. Un DN `managedBy` est relu dans le domaine : son écriture canonique et le GUID référencé apparaissent dans le diff **avant** confirmation. La comparaison de ce DN admet seulement la casse ; une substitution de référence GUID est refusée.

Le navigateur ne fournit pas de GUID d’autorisation. Le moteur conserve les faits de l’inspection ; une modification concurrente des valeurs, de l’objet, du responsable ou de la configuration invalide le plan. Le reçu `succeeded/code30` exige une preuve native, les valeurs exactes et la persistance finale. Une observation incomplète conserve l’incertitude. Les cartes historiques confrontent l’identité complète et tous les attributs du diff avant d’afficher une nouvelle vérification. Les reçus attributs V1 restent lisibles, sans devenir des autorisations de vérification V2.

## Jonction hors ligne locale

| Opération | Arguments | Effet / garde |
|---|---|---|
| `offlineJoin.open` | `{}` | Demande une fenêtre locale distincte depuis la session normale ; ne prépare ni n’applique de jonction |
| `offlineJoin.list` | `{}` | État local Windows et registre de blobs ; aucun accès AD/SMB/HTTP |
| `offlineJoin.import` | `{objectGuid,targetOU,confirmed:true}` | Sélection par dialogue natif puis copie protégée ; références AD déclarées, non encore vérifiées |
| `offlineJoin.prepare` | `{id}` | Plan exact, nom actuel conservé, blob non consommé et politique relus |
| `offlineJoin.apply` | `{planId,confirmationName,confirmed:true}` | Intention durable avant l’unique application `djoin` ; résultat en attente, jamais jonction finale supposée |
| `offlineJoin.observe` | `{id}` | Après redémarrage manuel : contrôle AD explicite GUID/nom/OU/domaine/canal sécurisé, sans réparation ni réapplication |

Les cinq API locales fonctionnent dans `OfflineJoinBackend`, qui refuse toutes les autres opérations avant analyse des arguments ou création de fournisseur. `session.info` y expose `mode:offline` et `localOnly:true`. Le démarrage `Pesto.exe --offline-join` évite connexion AD, découverte de DC et tableau de bord. Le shell affiche une bannière permanente d’**opération réelle locale**, sans commande Démonstration. Il ne lance jamais `offlineJoin.observe` automatiquement.

Le chemin et le contenu du blob restent dans l’hôte natif. Les API refusent `path`, `source`, `blob` et toute autorisation forgée. L’import exige la politique explicite et une machine hors domaine ; le contenu opaque est protégé avant persistance, le SHA empêche les doublons, les journaux V1 connus empêchent le rejeu. L’acquittement générique ne rend jamais ce blob réutilisable. Un contrôle courant échoué est annoncé comme tel, même si le registre conserve une preuve historique de réussite. Voir [OFFLINE-JOIN.md](OFFLINE-JOIN.md).

La CLI n’est pas exposée au navigateur : aucune opération `automation.*` n’existe dans le schéma. Voir [CLI.md](CLI.md) pour l’entrée native du même EXE, les plans exportés et les règles de reprise idempotente.

## Réservations AD et coordination

| Opération | Arguments | Effet / garde |
|---|---|---|
| `reservations.list` | `{}` | Reçus locaux bornés ; aucune lecture AD ou SMB au montage du panneau |
| `reservations.inspect` | `{id}` | Inspection explicitement demandée du compte lié au reçu ; GUID, DN, marqueur et usage relus |
| `reservations.prepare` | `{id,action}` | `action=resumeJoin/release` ; plan interne à usage unique, valable deux minutes, aucune mutation AD |
| `reservations.execute` | `{planId,confirmationName}` | Confirmation exacte du nom, nouvelle vérification, reçu durable ; aucun chemin ou GUID libre |
| `coordination.status` | `{}` | Paramètres locaux, sans sonder le dossier configuré |
| `coordination.inspect` | `{}` | Inspection explicite du registre configuré, aucune création |
| `coordination.prepare` | `{}` | Aperçu lié à la configuration et à l’état observé ; aucune création |
| `coordination.apply` | `{planId,confirmed:true}` | Création exclusive des éléments manquants du registre après confirmation ; aucun partage, ACL ou verrou existant remplacé |

Le plan initial de jonction expose `reservationRequired`. La confirmation annonce la création du compte avant la jonction lorsque cette politique est activée. La liste conserve le nom Windows d’origine ; un plan de reprise expose le nom Windows actuel prouvé dans `computer`. Le reçu enfant doit correspondre à ce plan. Fermer un écran, annuler une confirmation ou redémarrer Pesto ne supprime aucun compte réservé.

Inspection, préparation et exécution de réservation/coordination sont sérialisées avec les autres mutations. Une réponse absente n’autorise aucun rejeu. `reservations.execute` et `coordination.apply` restent en attente du résultat natif sans expiration artificielle du délai JS de lecture.

## Démonstration

| Opération | Arguments | Effet |
|---|---|---|
| `demo.open` | `{}` | Depuis le mode réel, autre fenêtre avec un moteur et profil isolés |
| `demo.status` | `{}` | Scénario, génération, contexte fictif |
| `demo.reset` | `{confirmed:true}` | Nouveau monde ; anciens plans invalides et IDs jamais réutilisés |
| `demo.scenario` | `{id,confirmed:true}` | Scénario fermé parmi les huit proposés |
| `demo.restart` | `{confirmed:true}` | Redémarrage fictif ; aucune commande système |
| `demo.prepareMove` | `{id}` | Équivalent fictif de la reprise limitée au déplacement |

Les contrôles du monde fictif sont refusés dans le moteur réel. Les opérations configuration/référentiels/mises à jour/hôte/réservations/coordination, la sélection précréée, les attributs AD, toutes les API de jonction hors ligne et les décisions réelles d’acquittement/redémarrage sont refusées en démo, même directement et même si les contrôles web sont détournés. Le refus précède toute inspection d’arguments ou de chemins dans les services concernés. Aucun backend réel n’est substitué au backend de démonstration.

## Configuration et référentiels

| Opération | Arguments | Effet |
|---|---|---|
| `configuration.status` | `{}` | `configured`, `configurationExists`, `configurationState`, diagnostic fermé, empreinte métier, éventuel choix de distribution ; `installationDefault` `{state,path,version,fingerprint,sha256}` décrit `wad\defaults\configuration.json` de cette installation |
| `configuration.settings` | `{}` | État de configuration et paramètres validés ; aucun paramètre métier par défaut présenté comme actif si le fichier est invalide |
| `configuration.export` | `{version?}` | Enveloppe nettoyée sauvegardée par dialogue natif |
| `configuration.previewImport` | `{}` | Sélection native, validation et différences ; prépare aussi le remplacement explicite d’un fichier existant invalide, sans application |
| `configuration.previewSettings` | `{domain,prefix,rootOu,namingPattern,production,randomNames,sites,dc?,preprodOu?,preprodSite?,fingerprint?}` | Validation complète, plan lié aux octets effectivement lus |
| `configuration.applyImport` | `{planId,confirmed:true}` | Vérification des octets attendus, sauvegarde exacte, remplacement atomique et consommation du plan |
| `configuration.decideDistribution` | `{planId,replace,confirmed:true}` | Remplacer/Conserver et mémoriser par profil/version/empreinte |
| `configuration.setDefault` | `{version?,expectedSha256?,confirmed:true}` | Écrit sur place `wad\defaults\configuration.json` dans cette installation, sans dialogue natif ni nouveau pack ; résultat `written` ou `unchanged` |
| `references.preview` | `{}` | Sélection native du document, ajouts/conflits/inchangés |
| `references.apply` | `{planId,resolutions:[{key,choice}],confirmed:true}` | `choice=current/incoming`, 2 500 résolutions au plus ; application atomique unique |

La préparation de configuration accepte de 1 à 100 sites fermés `{id,name,code,ou}` (le schéma générique du pont autorise 200 éléments, mais le service applique la borne de 100). Les documents d’import sont limités à 1 Mio. Les différences ne constituent pas une autorisation de mutation AD. Voir [CONFIGURATION.md](CONFIGURATION.md) pour formats, durée des plans et limites.

`installationDefault` est une lecture légère (manifeste et fichier seulement, aucun hachage du pack). `state` vaut `missing` (aucun fichier), `local` (fichier écrit sur place depuis 2.0.14, hors `SHA256SUMS` et hors empreinte du pack), `sealed` (manifeste d’un ancien pack personnalisé déclarant `configurationFingerprint` ou `configurationVersion` : fichier inscrit dans l’inventaire du pack) ou `invalid` (fichier illisible ou hors schéma : `version`, `fingerprint` et `sha256` valent `null`). `path` vaut toujours `wad\defaults\configuration.json` ; `sha256` est l’empreinte hexadécimale minuscule des octets du fichier.

`configuration.setDefault` exporte la configuration partageable du profil et l’écrit dans le dossier de l’installation en cours, comme le fichier de déploiement de GLPI-Pilot. `expectedSha256` reprend le `sha256` de `installationDefault` lu avant la confirmation, ou `""` si aucun fichier n’était présent (absent vaut `""`) ; toute autre valeur que `""` ou 64 caractères hexadécimaux minuscules est refusée (`invalid_arguments`). Le résultat porte `status` (`written`, ou `unchanged` si un défaut local a déjà la même empreinte de configuration : aucune écriture, version existante conservée), `path`, `file` (chemin complet), `version`, `fingerprint` (empreinte de configuration), `sha256` (octets écrits ou conservés), `replaced`, `previous` (`{version,fingerprint,sha256}` ou `null`), `backup` (copie exacte de l’ancien fichier dans le profil, `backups\installation-default.<horodatage>.<32 hex>.json`, jamais dans le pack, ou `null`), `distribution`, `official` et `packFingerprint`, inchangés par l’écriture, et `decisionSaved` (faux si le profil n’a pas pu mémoriser le choix de l’auteur : le fichier reste écrit et vérifié, et le prochain démarrage pourra proposer cette configuration à ce profil). Refus, sans écriture (la copie de profil éventuelle est retirée, sauf si le fichier change pendant l’écriture elle-même ou si l’ancien fichier a dû être remis en place) : `update.pending` (transaction de mise à jour non terminée), `config.default_sealed` (ancien pack personnalisé, à remplacer par le pack officiel dans un nouveau dossier), `config.default_changed` (fichier différent de celui affiché, y compris pendant l’écriture), `config.default_readonly` (dossier non inscriptible), `config.default_write` (autre échec d’écriture), `package.defaults` (défaut existant invalide), ainsi que les refus de l’export du profil et de la validation du pack installé. Après écriture, le fichier est relu et le pack revalidé (même empreinte, même distribution) ; en cas d’écart, les octets précédents sont remis (ou le fichier écrit est retiré s’il n’y en avait pas) et `config.default_verification` est renvoyé, avec un message distinct si cette remise a elle-même échoué. `written` comme `unchanged` mémorisent la décision de ce profil pour cette version et cette empreinte : Remplacer/Conserver ne lui est pas redemandé. L’interface lit `configuration.status`, affiche le chemin et la version remplacée dans sa confirmation, puis transmet `expectedSha256` ; un refus remplace le statut « Écriture de la configuration par défaut… » par « Configuration par défaut non enregistrée : » suivi du motif. Le fichier contient le domaine et les OU : le dossier configuré se diffuse comme un fichier privé.

`configurationState` vaut `missing`, `valid` ou `invalid`. Pour un fichier existant invalide, `configured=false`, `configurationExists=true`, `fingerprint=null`, `pendingDistribution=null` et `requiresDecision=false`. Le diagnostic ne divulgue pas les octets invalides, les valeurs rejetées ou le détail du parseur. `configuration.settings` retourne cet état, `sites:[]`, `simulation:false` et `liveExecutionEnabled:false`, sans inventer domaine, préfixe ou politiques actifs. L’initialisation ne lit ni valeurs distribuées ni source V1 pour remplacer ce fichier ; `configuration.previewSettings` refuse avec `config.recovery_required`.

La récupération utilise les API d’import existantes, sans endpoint de réparation ni chemin libre supplémentaire. Un aperçu valide de remplacement porte `replacesInvalidConfiguration:true`, `backupRequired:true` et `requiresConfirmation:true`. Sa différence annonce un original invalide non affiché et contient seulement la configuration candidate validée. Le plan de quinze minutes est lié au SHA-256 des **octets** existants, BOM compris ; cette garde interne est distincte du `fingerprint` métier canonique exposé au navigateur. Une modification même limitée au BOM provoque `config.changed`. Un fichier impossible à lire et sauvegarder exactement provoque `config.unreadable`, sans plan. L’application confirmée conserve les octets originaux dans une sauvegarde unique ; un plan consommé ou expiré est refusé avec `config.plan`. L’annulation du dialogue, de l’aperçu ou de la confirmation n’applique rien.

`configuration.previewSettings` accepte aussi les champs optionnels `coordinationRoot`, `coordinationRequired`, `reserveNamesInAd`, `auditEventLogEnabled`, `blockJoinOnClockSkew` et `excludedGroupGuids`. Le chemin est limité à 240 caractères, les quatre indicateurs sont des booléens stricts, les groupes une liste de 200 GUID canoniques distincts et non nuls au plus. Un champ absent conserve la politique existante ; un champ présent est validé puis inclus dans l’aperçu. L’enregistrement ne contacte pas AD, le partage ou le journal Windows.

Les champs optionnels `allowPrecreatedJoin` (booléen strict) et `entraPolicy` (`Disabled/HybridOnly`) suivent le même aperçu et le même remplacement atomique. Une configuration neuve choisit explicitement `Disabled` et `false`. Un import V1 sans valeur Entra explicite garde le comportement V1 effectif `HybridOnly`, affiché dans les paramètres ; l’action exige toujours une préparation et un consentement séparés.

Les booléens optionnels `allowOfflineJoin`, `unattendedJoinEnabled` et `unattendedOperationsEnabled` suivent le même contrat : absent = conserver, présent = booléen strict inclus dans le diff, configuration neuve = faux. Aucun de ces réglages ne lance une opération.

## Mises à jour et hôte

| Opération | Arguments | Effet |
|---|---|---|
| `updates.status` | `{}` | Préparations, sauvegarde et interruption éventuelle ; `rollbackVersion` (version rétablie par le retour, ou `null`), `recoveryVersion` (version rétablie par la reprise d’une interruption, ou `null`), `rollbackDefaults` et `recoveryDefaults` (sort de la configuration par défaut : `kept`, `withdrawn`, `deleted`, `setAside` ou `null`) et `localConfiguration` (état de `wad\defaults\configuration.json`, même forme que `installationDefault`) |
| `updates.windows` | `{}` | Autres `Pesto.exe` de ce pack : libellé, fermeture possible ou motif, jeton de la liste (lecture seule) |
| `updates.inspect` | `{source? ,kind?}` | Pack dossier/UNC/ZIP ; sans source, sélection native `folder/zip` ; `localConfiguration` vrai si la source porte une configuration par défaut hors identité, `configurationIncluded` vrai pour un ancien pack personnalisé scellé ; `installDefaults` (`kept`, `adopted` ou `null`) dit ce que l’installation fera de la configuration par défaut ; un défaut différent de celui de l’installation est refusé (`update.default_conflict`) |
| `updates.prepare` | `{candidateId}` | Copie isolée, hashes et manifeste revalidés ; `localConfiguration` comme pour l’inspection, et la configuration par défaut de la source liée à celle inspectée (`update.changed` si elle a changé) |
| `updates.install` | `{preparedId,confirmed:true,closeWindows?}` | Fermeture consentie des autres fenêtres du pack (jeton de `updates.windows`), puis journal transactionnel et fermeture avant lancement du helper |
| `updates.rollback/recover` | `{confirmed:true,closeWindows?}` | Même fermeture consentie, puis restauration/reprise explicite avec santé et journal |
| `host.reconnect` | `{confirmed:true}` | Fermeture puis nouveau processus gardant le SID du profil, avec choix explicite de compte `--choose-account` ; aucun reboot du poste |

Les accès métier et maintenance sont sérialisés également au niveau du service, hors pont. Une fermeture/install/reconnexion acceptée bloque les nouvelles demandes ; une mutation déjà engagée achève son reçu. Les fenêtres et WebView2 sont disposés avant le lancement du helper. Le contrôle de santé utilise un profil éphémère et une preuve liée au nonce/transaction/version/hash, sans importer la configuration réelle.

Les préparations natives, réconciliations et actions confirmées attendent leur résultat natif sans délai JS qui ferait abandonner une commande encore en cours. La fermeture d’un écran n’autorise ni confirmation tardive sur un autre contexte, ni rejeu automatique.

Les gardes C6 de configuration locale et de récupération sont couvertes par les tests locaux du moteur, du pont et des écrans. La campagne Windows réussie `40294452798`, source `51ee270`, confirme MainForm/WebView2 en configuration locale et la coexistence avec les fenêtres de démonstration dans les deux packs, sans adaptateur AD ni création de profil réel ; le [rapport C6](VALIDATION-C6-20261026.md) identifie les binaires, les preuves transactionnelles et leur portée. L’authentification native, UAC avec un autre compte et conservation du profil d’origine, les dialogues natifs de récupération/import/export ainsi que les ACL et DPAPI restent non qualifiés par cette campagne.
