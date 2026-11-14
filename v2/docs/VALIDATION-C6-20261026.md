# Validation C6 — 26 octobre 2026

## Source et portée

Reprise directe de `M4D135/pesto`, branche `codex/pesto-v2-20261023`, depuis
`f3ed854e162562d107a3f75b42aca7491c25f6c6`. La tête distante a été relue avant
préparation du commit. Aucune modification Spark non poussée n’est supposée intégrée.
Les packs et releases V1 restent indépendants ; aucune release V2 n’est publiée.

Ce lot corrige des parcours concrets et renforce la qualification. Les preuves
portables ci-dessous sont exécutées. La sixième campagne Windows C6 est entièrement
réussie sur **`51ee27058c74c27b237bff2e6250aa384198b345`** :
[preuves, empreintes et candidats PROD/DEV](evidence/20261026/windows-51ee270/README.md).
Les cinq campagnes précédentes restent documentées avec leurs échecs précis. Les
résultats natifs C5 demeurent attachés à leur ancien binaire ; aucune campagne ne
constitue une preuve d’opération AD réelle.

## Corrections implémentées

### Démarrage, authentification et configuration locale

Sur un poste joint au domaine, le démarrage utilise l’identité Windows effective
après élévation, sans demander automatiquement un deuxième compte. Le choix natif
Windows/autre compte reste disponible par Reconnecter Pesto ou `--choose-account`.
Hors domaine, la saisie AD est directe. La décision repose sur l’appartenance locale,
sans recherche réseau de domaine. Un état local indéterminé ne vaut pas une preuve.

`--settings`, une configuration absente/invalide ou une authentification annulée
ouvrent les Paramètres sans adaptateur AD. Le mode local expose son état et ses
capacités fermées ; les API métier, la fenêtre ODJ et la coordination partagée sont
refusées avant traitement de leurs arguments. Les actions explicites de configuration,
d’import/export, de mise à jour et de démonstration restent accessibles. Ce mode
n’est pas une session AD connectée. Après import, la connexion reste une action explicite.

Un fichier de configuration invalide ne fait plus quitter l’application et n’est
jamais remplacé automatiquement par la configuration distribuée. Un import valide
peut préparer sa réparation, avec aperçu, confirmation, sauvegarde exacte et
remplacement atomique. L’empreinte porte sur les octets, y compris le BOM ; un
changement concurrent invalide le plan. L’encodage illisible n’est pas remplacé par
des caractères de substitution. Les fichiers trop grands ou illisibles ne donnent
pas lieu à une prétendue sauvegarde réussie.

### Préparation des packs et mises à jour

La copie d’un pack est liée à l’empreinte validée de la source. Le répertoire copié
est validé à nouveau avant utilisation. Une modification concurrente cohérente de
la source ne peut plus être acceptée après un simple recalcul des hashes. Ce contrôle
s’applique à la préparation depuis dossier/UNC et à la création d’un pack personnalisé.
L’échec supprime seulement la nouvelle destination, jamais la source concurrente.

### Banc natif de démonstration

Le banc conserve les 44 appels directs refusés et ajoute le vrai `MainForm` local
sans adaptateur, puis deux ouvertures successives via le bouton Démonstration.
Il exige des profils WebView2 distincts, la préservation du brouillon, de la route et
des préférences de la fenêtre parente, une bannière persistante après rechargement,
les scénarios, la remise à zéro et le redémarrage fictif. Les identifiants de reçus
doivent rester distincts entre resets et fenêtres.

Chaque action doit produire un nouveau montage de page et les véritables cartes de
reçus attendues, même si le redémarrage reste sur la route Interventions. La preuve
comprend six transitions et quatre captures fictives par canal. La fermeture du
parent doit fermer son enfant. Ce parent de test est une configuration locale sans
adaptateur AD, pas une session opérateur authentifiée sur le domaine.

### Banc natif de mise à jour entre deux compilations

Le workflow reconstruit le commit source C5 immuable
`de527313b98f30d52802ec6abd51804e12f8c298` en pack A, puis le commit candidat en pack B.
Les deux EXE et les deux commits doivent être distincts. A est reconstruit dans cette
campagne, pas téléchargé comme un ancien artefact : son hash ne doit pas être assimilé
au binaire C5 historique. Les deux packs gardent leur vraie version de manifeste.

Le ZIP réel B est créé avant les essais et reste celui archivé à leur issue. Le
parcours normal prépare ce ZIP, installe B, vérifie sa santé puis revient à A.
L’identité du helper A et celles des sondes de santé B puis A sont contrôlées.
PROD ajoute santé négative et interruption du contrôle de santé ; DEV couvre
installation et rollback normaux. Les variantes de panne sont explicitement dérivées
de B, sans prétendre être des packs officiels intacts. L’acquisition UNC n’est pas
qualifiée par ce banc.

## Validation portable exécutée

Environnement Linux, SDK .NET 10.0.402 compatible avec le `rollForward` du projet.
Le workflow Windows conserve le SDK 10.0.302 épinglé. Les compilations sont séquentielles,
avec `--disable-build-servers -m:1`, configuration Release.

| Contrôle exécuté | Résultat |
|---|---|
| Compilation moteur et tests | Aucun avertissement ni erreur |
| Tests moteur complets | **604/604** après la régression de profil neuf |
| Compilation et tests du pont | Aucun avertissement ni erreur ; **15/15** |
| Compilation croisée de l’hôte Windows | Aucun avertissement ni erreur |
| Banc de mise à jour portable | **30/30**, fixtures déclarées PROD/DEV et ZIP ; aucune exécution Windows |
| `web-maintenance-check.mjs` | **20/20** dans Chromium, dont configuration locale et récupération d’un fichier invalide |
| `operator-ui-check.mjs` | **32/32** dans Chromium |
| `demo-dom-check.mjs` | **8/8** dans Chromium |
| `bridge-lifecycle-check.mjs` | **21/21**, horloge et canal factices |
| `web-check.mjs` | **149/149**, dont provenance locale ; référence externe Domenia absente |

Les tests moteur ont utilisé exactement les sources compilées. Le renforcement du
banc natif a d’abord fait l’objet de recompilations de l’hôte seul. Après identification
du défaut sur profil neuf, la suite moteur complète (604 tests) et l’hôte ont été
recompilés puis vérifiés à nouveau. Les sources du pont et du banc de mise à jour
sont celles vérifiées par leurs contrôles portables, dont la recompilation et les
30 contrôles du compagnon après le dernier correctif d’observation. Les journaux
intégraux locaux restent dans `v2/logs`, hors Git. Ces tests n’ont effectué aucune
mutation AD, aucun redémarrage réel et aucune installation de production.

## Qualification Windows

### Première campagne : e708752

La campagne [40287410603](https://github.com/M4D135/pesto/actions/runs/40287410603)
porte sur `e7087527dbaec712aa5a91f189b29a0451f26f4a` et se termine en échec.
Les compilations Windows, les **199 tests moteur ciblés**, **15 tests du pont**,
**30 contrôles du banc portable**, **18 variantes de syntaxe PS5.1** et les assemblages
A/B PROD/DEV réussissent. Le smoke PROD historique conserve `ready=true`,
`closeReturned=true`, **44 refus directs**, zéro appel hôte et aucun profil réel créé.

Le nouveau parcours de coexistence s’arrête à `parent-start`, avec
`qualification.coexistence.bridge-read`, après 2,229 secondes. Aucune fenêtre enfant
n’est encore ouverte ; les profils temporaires sont supprimés. Les mises à jour
natives sont **non exécutées** et aucun pack de cette campagne n’est publié.
L’[artefact original de preuves](https://github.com/M4D135/pesto/actions/runs/40287410603/artifacts/12634742926)
a été téléchargé et vérifié : SHA-256
`dc794f65e253006d3c803b3f070d67afc60e12c01bfb782520472b04353e890a`.

Le script de lecture fonctionne dans Chromium avec la page et sa CSP, sans reproduire
l’échec de l’évaluation native WebView2. Le correctif rend l’URL du module absolue sur
la même origine et ajoute un diagnostic fermé distinguant chargement du module,
export et lectures du pont. Aucun refus d’API ni critère de réussite n’est assoupli.
Le script exact passe aussi six cas Chromium ciblés, dont les refus de canal et de
module ; l’hôte recompilé ne présente ni avertissement ni erreur. Les sources du
moteur, du pont et du banc de mise à jour restent identiques aux validations précédentes.
Une nouvelle campagne Windows doit confirmer le résultat ; la cause initiale n’est
pas présentée comme démontrée par le seul essai Chromium.

### Deuxième campagne : 9c7c75b et défaut de relecture confirmé

La campagne [40288733126](https://github.com/M4D135/pesto/actions/runs/40288733126)
porte sur `9c7c75b1aff95b2dbb599efd1a3b98d1fffbdafe`. Elle confirme le chargement
du module et de son export, puis échoue à `bridge-session-refused`, toujours avant
l’ouverture d’un enfant. Les assemblages et contrôles précédant le smoke réussissent ;
les transactions natives restent sautées. L’artefact de preuve **12634964807** a été
vérifié avec le SHA-256
`592a064b48ee35bf1476d157fae1d8f8ca3e1f466b3ca03035750a402dbfc253`.
L’URL d’import n’était donc pas la cause démontrée du refus.

La relecture du code révèle un défaut réel sur profil neuf : le premier `session.info`
mémorise une configuration absente ; le suivant appelle le résolveur de chemin dans
`RefreshConfigurationIfChanged`, qui laisse remonter `config.missing`. Un test ciblé
reproduit cet échec **avant** correction. Le correctif absorbe uniquement ce code lors
du rafraîchissement, avec une empreinte absente ; il ne masque pas les autres refus.
L’apparition d’un cfg force son chargement. Sa suppression après un chargement valide
invalide toujours aperçus, plans, file, lots et caches. Les contrôles d’empreinte
juste avant l’envoi restent distincts et inchangés.

Le test couvre les lectures répétées pendant absence, création puis suppression du
fichier, ainsi que le maintien des capacités fermées et le refus métier du mode local.
La suite complète compte désormais **604 tests**, après correction. Le banc conserve
aussi une liste fermée de codes serveur pour distinguer précisément un éventuel
nouveau refus, sans recopier messages, chemins ou contenus. Ses neuf contrôles
Chromium ciblés passent. Une nouvelle campagne native reste nécessaire.

### Troisième campagne : 43a530b, profil neuf et premier scénario prouvés

La campagne [40289832414](https://github.com/M4D135/pesto/actions/runs/40289832414)
porte sur `43a530ba9687f0d6b7798bed105d901a824728bb`. Elle confirme le correctif du
profil neuf dans le vrai MainForm : session locale prête, ouverture de la démo depuis
le bouton, brouillon/route/préférences du parent préservés et bannière persistante après
rechargement. Le premier scénario affiche le bon reçu `pendingRestart` dans une
nouvelle page Interventions. Une capture native du brouillon parent est conservée.

Le banc s’arrête ensuite sur son interprétation du champ `code` : le contrat expose
une chaîne (`"20"`), alors que deux assertions utilisaient un entier. Ces deux
assertions sont corrigées selon le contrat, qui reste inchangé. Les autres types
consommés par le banc ont été relus. Cette campagne ne prouve pas encore le redémarrage
fictif, le reset, la fermeture parent/enfant ni les transactions natives suivantes.
L’artefact **12635442184** a été téléchargé et vérifié : SHA-256
`85c7f8c5df766faf6a9cd3db306c52c40bfc2b1129f653b3e1c8d285b2f79933`.

### Quatrième campagne : 06c4931, démo native complète réussie

La campagne [40290717963](https://github.com/M4D135/pesto/actions/runs/40290717963)
porte sur `06c493148bc869675b742dcdd4de6ffce1e195e6`. Les compilations, les
**200 tests moteur ciblés**, **15 tests du pont**, **30 contrôles du banc portable**,
les **18 variantes PS5.1** et les assemblages sont verts.

Les deux preuves natives **PROD et DEV** sont désormais entièrement réussies :

- Vrai EXE et WebView2 fixe prêts puis fermés ; **44 API réelles refusées par canal**.
- Démo ouverte depuis le bouton du parent en configuration locale sans adaptateur.
- Brouillon, route et préférences du parent conservés ; bannière persistante après rechargement.
- Six transitions réelles d’écran par canal, dont le même reçu passé de `pendingRestart`
  à `simulated` après le redémarrage fictif, puis le reset vers Ajouter.
- Trois profils distincts, deux instances et trois identifiants de reçus distincts,
  après reset comme entre fenêtres ; enfant fermé, puis parent fermé avec son nouvel enfant.
- Zéro appel hôte interdit, zéro accès au fournisseur de coordination, aucune configuration
  créée, aucun profil réel créé et profils temporaires supprimés.

Les huit PNG ont été ouverts et relus avec les deux JSON : les valeurs du brouillon
parent restent identiques, les reçus et états correspondent aux transitions, et les
bannières sont visibles. Les durées de coexistence sont 38,682 s en PROD et 49,520 s
en DEV. SHA-256 du même EXE dans les deux packs :
`dcb3c2caf79204f52429e2fbd8fbcfb102aa04abaf2797b8256ea1f0430afac6`.
L’[artefact 12635602958](https://github.com/M4D135/pesto/actions/runs/40290717963/artifacts/12635602958)
est téléchargé et vérifié : SHA-256
`5458486bca76334f0a0f6b400b665ff3ca5f91cf3c190d056cde270ef65d3517`.

La campagne globale échoue ensuite **avant toute transaction de mise à jour** : le
parseur Windows PowerShell 5.1 refuse un `-or` placé au début d’une nouvelle ligne
dans le script du banc. L’opérateur est replacé en fin de ligne, sans changer la
condition. Le workflow ajoute un contrôle explicite de parsing PS5.1 de ce fichier,
avec son hash et zéro erreur exigé, avant l’assemblage et les essais natifs. Aucun
code App, moteur ou pont n’est modifié par cette correction de script. Les scénarios
transactionnels entre deux compilations restent à exécuter ; aucun pack candidat de
cette campagne incomplète n’est publié.

La démo est qualifiée pour les copies et profils temporaires décrits, sans session
AD authentifiée, sans UAC avec autre utilisateur et sans capture réseau indépendante.

### Cinquième campagne : 19cabd1, installation et deux retours PROD prouvés

La campagne [40291882599](https://github.com/M4D135/pesto/actions/runs/40291882599)
porte sur `19cabd1242584e45220339944a841c5260330758`. Le nouveau contrôle du fichier
par le parseur PS5.1 réussit. La démo native complète repasse en PROD et DEV.
Le banc transactionnel exécute cette fois de véritables changements de binaire :

| Étape PROD exécutée | Verdict durable |
|---|---|
| Acquisition et préparation du ZIP B, installation et santé B | `completed`, preuve d’installation réussie |
| Rollback explicitement demandé, restauration et santé A | `rolledBack`, preuve de retour réussie |
| Page de santé B volontairement invalide, détection puis restauration et santé A | `rolledBack`, santé négative conservée séparément |
| Observation de l’interruption pendant `checking` | Refus d’attribution d’un descendant ; interruption et reprise non qualifiées |

A provient du commit `de527313b98f30d52802ec6abd51804e12f8c298`, avec EXE SHA-256
`62c1786a7ec3b5321520943740699ceece6c4a39ceae11c9d1c93bcb170d4a6c`.
B provient du commit `19cabd1242584e45220339944a841c5260330758`, avec EXE SHA-256
`8974a91ff03e6955df2a3a53f3b1678799dee2b291aa83829ea545974c836667`.
Les deux gardent la version réelle `2.0.0`. Le ZIP PROD inspecté porte le SHA-256
`fc1885da13965f584f746af9b4df0dcfe029b22c6ebf06189e6dee0db6e4d730`.
Les sources et le cfg sentinelle restent inchangés dans les trois preuves d’étape
terminées. Les reçus de santé identifient le candidat B puis le retour A.

Pendant le cas d’interruption, le journal atteint `checking` et l’enfant santé est
observé ; un inventaire ne peut pas attribuer avec certitude un descendant au pack
temporaire. L’interruption demandée est donc refusée. Le nettoyage refait ensuite
l’attribution complète avec succès et ferme l’arbre du banc. Cette fermeture de
nettoyage ne vaut pas une interruption qualifiée ni une preuve de reprise. Le
processus initialement ambigu n’est pas identifié dans cette ancienne observation ;
aucune nouvelle catégorie de processus ne peut être autorisée sur cette seule preuve.
DEV n’a pas encore exécuté sa transaction dans cette campagne.

L’[artefact 12636797142](https://github.com/M4D135/pesto/actions/runs/40291882599/artifacts/12636797142)
a été téléchargé et vérifié : SHA-256
`fc5001249c5fbb9664e2745f30409f6a607d06156fc0220072e6f3df283b575f`.
La campagne demeure en échec et n’a publié aucun pack candidat. Le banc est corrigé
pour attendre, dans sa borne existante de 210 secondes, un inventaire entièrement
attribuable. Un inventaire ambigu est rejeté en entier, sans filtrage ni nouvelle
catégorie de processus autorisée. Les seize diagnostics au plus conservés décrivent
le motif et l’identité observée. Un second inventaire complet, l’identité et le hash
du helper A, le hash du processus santé B et le journal encore à `checking` sont
exigés avant l’interruption. Une frontière perdue ou un délai expiré échouent ; le
nettoyage conserve son contrôle strict et ne déclare l’arrêt qu’après disparition
vérifiée des processus du banc.

Ce correctif du banc compile avec zéro avertissement et zéro erreur ; les
**30 contrôles portables** repassent. Le hash du fichier compilé est
`f5c7a124b93bdb2f334ff212e3ade22e496b53ec7b87c5bd0089dd5175edba54`.
Il ne modifie ni l’application ni le moteur. Son efficacité native reste à établir
dans la campagne suivante ; les contrôles portables ne l’attestent pas.

À l’issue de cette cinquième campagne, la dernière campagne entièrement réussie
était encore [C5 sur de52731](evidence/20261025/windows-de52731/README.md).

### Sixième campagne : 51ee270, qualification native complète réussie

La campagne [40294452798](https://github.com/M4D135/pesto/actions/runs/40294452798)
sur **`51ee27058c74c27b237bff2e6250aa384198b345`** est entièrement réussie. Les
compilations Windows ne comportent ni avertissement ni erreur. Les **200 tests
moteur ciblés**, **15 tests du pont**, **30 contrôles portables**, **18 variantes
PS5.1** et le nouveau parsing PS5.1 du point d’entrée repassent.

Les deux packs complets passent leur validation et leur vrai MainForm/WebView2 :
44 refus directs par canal, contexte parent local conservé, six nouveaux montages
de page, bannière, scénarios contrôlés, reset et redémarrage fictif, trois profils,
deux instances et trois reçus distincts. Les fermetures et le retrait des profils
temporaires réussissent. Les deux JSON et les huit PNG ont été relus ; les durées
sont 35,446 s en PROD et 35,515 s en DEV. Aucun adaptateur AD n’est construit par
le parent local et aucune configuration réelle n’est créée.

| Canal et cas natif | Preuve finale |
|---|---|
| PROD normal | ZIP B acquis et préparé, B installé avec santé positive, rollback explicite et santé A ; `rolledBack` |
| PROD santé négative | Preuve négative B conservée, restauration et santé A ; `rolledBack` |
| PROD interruption/reprise | Arrêt réel à `checking`, demande `recover`, retour et santé A ; `rolledBack` |
| DEV normal | ZIP B acquis et préparé, B installé avec santé positive, rollback explicite et santé A ; `rolledBack` |

Les quatre transactions, huit reçus de santé et sept lancements du helper se
recoupent avec les demandes, journaux, fixtures et preuves finales. Le helper A et
ses trois descendants — santé B et deux WebView2 — sont attribués avant l’arrêt
pendant `checking`. Son code de sortie est -1 après l’interruption ; le nouveau
helper de reprise finit à zéro et ferme son dialogue. La tentative B reste
`interrupted`, non acceptée, et n’est pas rejouée. Aucun refus d’attribution n’a été
rencontré dans cette campagne : le parcours complet est établi, sans prétendre que
la branche d’attente d’un inventaire ambigu a été sollicitée.

Les rapports finaux au schéma 2 confirment les deux commits et EXE distincts,
l’acquisition réelle du ZIP pour les cas normaux et la conservation des sources
A/B, des archives et du cfg sentinelle extérieur. Chaque cas conserve exactement
deux tentatives de santé et finit sur A, puis sa copie temporaire est retirée.
Le banc n’a exécuté ni AD, ni UNC, ni redémarrage réel. DEV ne couvre pas les cas
natifs de panne ou de reprise.

Le binaire A reconstruit depuis `de52731` a le SHA-256
`62c1786a7ec3b5321520943740699ceece6c4a39ceae11c9d1c93bcb170d4a6c`.
Le nouveau `Pesto.exe` B, commun aux deux canaux, a le SHA-256
`b196f141d83a043c1f81a42da29fdc0f9d68fe6b72219aafd1236fda902a858f`.
Les deux gardent leur vraie version `2.0.0`. Les ZIP utilisés avant les essais sont
ceux archivés après les essais, sans réécriture. Leurs empreintes et les liens de
téléchargement sont dans la [synthèse finale](evidence/20261026/windows-51ee270/README.md).

L’[artefact de preuves 12638096574](https://github.com/M4D135/pesto/actions/runs/40294452798/artifacts/12638096574)+a été téléchargé et son SHA-256 vérifié :
`cc6c71d4056257d42b07a3efa9a69592582ad07524e9c408046171dadba333f4`.
Les gros packs restent les artefacts GitHub d’origine ; leurs SHA et tailles sont
ceux du workflow et de GitHub, sans retéléchargement local. Aucun log brut ni chemin
de laboratoire n’est ajouté au dépôt. Le commit documentaire du bilan ne reconstruit
pas ces binaires et ne les attribue pas à une source différente.

## Commits de développement de cette reprise

| Commit | Changement |
|---|---|
| `e7087527dbaec712aa5a91f189b29a0451f26f4a` | Configuration locale et authentification raccordées, récupération exacte, copie de pack liée à l’empreinte, renforcement des deux bancs natifs |
| `9c7c75b1aff95b2dbb599efd1a3b98d1fffbdafe` | Import explicite du pont natif et diagnostic fermé du refus de session |
| `43a530ba9687f0d6b7798bed105d901a824728bb` | Régression du profil neuf reproduite puis corrigée ; lectures répétées absence/création/suppression |
| `06c493148bc869675b742dcdd4de6ffce1e195e6` | Assertions du banc alignées sur le vrai contrat de code de reçu sous forme de chaîne |
| `19cabd1242584e45220339944a841c5260330758` | Script compatible PS5.1 et contrôle explicite de son parsing dans la CI |
| `51ee27058c74c27b237bff2e6250aa384198b345` | Inventaires complets et identités A/B exigés avant interruption du banc ; candidat qualifié ci-dessus |

Chaque publication vérifie la tête attendue de la branche, sans forcer sa mise à
jour. Les changements Spark non poussés restent hors de ce bilan.

## Qualification restant ouverte et blocage observé

Restent indépendants de ce banc : canari AD réversible sur poste autorisé, contrôle
après redémarrage réel, UAC avec autre compte et profil opérateur original, SMB/UNC
réel avec droits et concurrence intermachines, coexistence avec une session AD
connectée. L’acquisition d’une release officielle par HTTP et les autres frontières
d’interruption que `checking` restent non qualifiées nativement par cette campagne.
Les dialogues natifs d’import/export/récupération, la fabrication complète
du pack personnalisé et les ACL/DPAPI du vrai profil restent également distincts
des contrôles sur fixtures. Le contrôle en lecture seule du bastion a été renouvelé
le 26 octobre à **08:51 UTC** après le push de `51ee270` et a encore répondu
`Connection refused` (code 255). Aucune session Windows du laboratoire
n’a été obtenue et aucune opération AD n’a été tentée. Ce refus ne permet pas de
conclure que la VM est arrêtée.
