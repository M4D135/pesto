# Qualification Windows critique

Cette checklist ne remplace ni [la parité](PARITY.md) ni [le rapport de release 2.0.0](RELEASE-v2.0.0.md) ni [le rapport daté C18](VALIDATION-C18-20261028.md). Une ancienne preuve Windows demeure attachée à son ancien binaire. Ne cocher une ligne que pour le commit, les empreintes EXE/pack et le runtime effectivement testés.

### Banc 2.0.10 du 3 novembre 2026 — candidat 81e4b703

Windows 11, 2 vCPU, 4 Gio. Le même exécutable (`84f6f527c40424729477850df721104b4ff8b90c190c083ddaf3078afe361822`) a été testé sur les deux éditions. Ce passage ne qualifie pas une release.

| Observation | Résultat |
|---|---|
| Référence AD avant et après | Deux lectures indépendantes de la série dans tout le domaine : 999 numéros libres, premier numéro 001. La requête après import du module a pris 142 puis 997 ms. |
| Noms disponibles, Ajouter ce PC, Renommer | Les trois vues ont affiché `P111301PR765001`. Le site de production était absent ; le profil du banc associait le tag PR à une OU de substitution et déclarait le service 765. |
| Temps depuis le clic sur Noms disponibles | À la première visite, site visible avant 6,95 s, service avant 8,47 s, nom entre 17,26 et 19,90 s. Au retour, les trois étaient visibles avant 2,80 s dans le même processus. Il s’agit de bornes d’après captures, pas de chronos LDAP. |
| Poste hors du périmètre géré | Windows UI Automation a confirmé que les boutons « Appliquer le renommage » et « Déplacer le poste » étaient désactivés, même après sélection d’une destination. |
| Connexion et fenêtre autonome | 24 contrôles de connexion réussis. Les deux éditions ont ouvert et fermé leur fenêtre autonome. Aucun nouvel essai d’élévation UAC réelle. |
| Démo ouverte depuis les paramètres | Échec sur les deux éditions : délai à la première fenêtre enfant en PROD (runtime fixe 156.0.4314.42) ; délai au redémarrage fictif et nettoyage incomplet en PROD-LIGHT (Evergreen 140.0.3485.54). |

La VM a été rendue sans modification AD. Le prochain essai de coexistence doit employer un nouveau binaire et un dossier vierge. Le cas du parc peuplé (`013` puis `004`), la course au moment de l’écriture et la campagne Windows du successeur restent distincts de ces preuves.

Sur le candidat suivant, le calcul local utilise les numéros occupés pour choisir un trou ; il relit toujours l’AD avant de proposer un nom. Sur un Mac ARM64 en Release, dans une série de 999 999 numéros sans exclusions avec 1 000 postes observés, la médiane du **calcul seul** passe d’environ 52 ms à moins de 0,1 ms. Sur la série historique à 999 numéros, l’ancien calcul prenait déjà bien moins de 1 ms : cela n’explique pas à lui seul les 19,90 s affichées sur Windows. La procédure de chronométrage ci-dessous sert à localiser ce délai sur le prochain binaire.

### Banc 2.0.10 du 2 novembre 2026

Le candidat `c5a335b86c5fdbcf0c7e4adb5b20a3f43f7b3d6c` a tourné sur Windows 11 dans une session de domaine ouverte. Les deux éditions contenaient le même exécutable, SHA-256 `de58be9b1b3ffbb176f6fe11df6a39917f50ec1ecb80de5bbe68560b64595b69`.

| Essai | Résultat observé sur ce binaire |
|---|---|
| Connexion native | 24 contrôles réussis. La capture à 96 DPI montre le logo entier, le thème clair et les deux boutons. |
| Démarrage et fermeture de la fenêtre autonome | Réussis sur PROD avec le runtime fixe 156.0.4314.42 et sur PROD-LIGHT avec Evergreen 140.0.3485.54. |
| Coexistence avec la fenêtre de démonstration | Échec sur délai pour les deux éditions. PROD s’est arrêté à l’ouverture de la fenêtre enfant. PROD-LIGHT a atteint le redémarrage fictif. |
| Noms disponibles, aperçu de jonction et aperçu de renommage | Les trois écrans ont proposé `P111301PR765001`. La série du labo était vide avant et après l’essai. Le site PR représentait une OU de substitution et le service 765 était déclaré dans le profil local. |
| Temps du premier nom depuis l’ouverture de Noms disponibles | Site visible à 7,60 s, service à 21,11 s, nom à 30,33 s. Des lectures de référence, effectuées après import du module, ont pris 126 puis 97 ms. |

Pour qualifier le correctif suivant, reprendre ces mesures sur le nouvel exécutable, puis changer le service et relire le résultat. Prévoir un autre cas sur un annuaire isolé qui contient le site `131_PROD_A_NOMMER` et douze numéros successifs occupés dans plusieurs OU. Attendre `013`, libérer `004` dans cette fixture et attendre `004` à la prochaine sélection. L’essai du 2 novembre s’est limité aux aperçus. Le renommage, la jonction et une collision survenue entre la préparation et l’exécution demandent leurs propres reçus.

**Release officielle 2.0.0 : [v2.0.0](https://github.com/M4D135/pesto/releases/tag/v2.0.0), source `84d76fc022eb11172021447672cfde5381a2d4ea`, [campagne 40720801680](https://github.com/M4D135/pesto/actions/runs/40720801680).** Les ZIP PROD/DEV publiés sont les octets testés sous Windows (617 tests moteur, configuration 36/36 par canal, installation depuis les boutons, refabrication DEV, mises à jour PROD en place depuis `de527313`) et ont été revérifiés après téléchargement. Une installation DEV de `de527313` passe à 2.0.0 par **nouvelle installation** (refus explicite qualifié). Statuts : `official=true`, `distribution=official`, `qualification=unqualified` — **AD, UAC réel, UNC et retour depuis les boutons UI non qualifiés**. Détails et empreintes : [rapport de release](RELEASE-v2.0.0.md). Les lignes ci-dessous détaillent encore les preuves C18 ; la campagne 2.0.0 repasse ces mêmes bancs sur l’EXE `15c51b086fc5f04506f00e5e0fe2fee36afd518af0f5aa9cf7afd5fa410ff715`.

**Historique C18 : `2adf60e15f8f7d5fd808c0471a63e1fd4457cd90`, [campagne 40675773761](https://github.com/M4D135/pesto/actions/runs/40675773761).** Les [preuves C18](evidence/20261028/windows-2adf60e/README.md) rattachent les 25 étapes réussies, 616 tests moteur, 250 gardes de restauration et 16 suites navigateur aux packs exacts PROD/DEV. Installation depuis les boutons, retour séparé par le service et reconstruction depuis les sources DEV avec SDK 10.0.302 réussissent. Les trois archives ont été téléchargées et leurs empreintes vérifiées ; les deux packs passent aussi `make-pack --verify` localement. Le [rapport C18](VALIDATION-C18-20261028.md) conserve l’échec initial `07dc741` et le correctif du banc. AD, UAC et UNC réels, profil ordinaire et retour depuis les boutons UI ne sont pas qualifiés par cette CI ; les preuves du harnais de domaine ne se transmettent pas aux ZIP.

Les candidats C18 utilisent l’EXE commun **`b8361c8b0185ab5c528eb182639ca5bf81fbb456c647f68db410382190b33e24`**. Les [archives et manifestes vérifiés](evidence/20261028/windows-2adf60e/download-verification.json) et les [46 recoupements de preuves](evidence/20261028/windows-2adf60e/independent-validation.json) relient source, ZIP, runtime et exécutions. La validation du harnais de retour AD compte 250 contrôles synthétiques, dont deux refus d’écriture des reçus conservés ouverts sous Windows ; ce n’est pas une restauration native ni une qualification AD des ZIP.

**Historique C17 : `e087bb16aed175bc35906fa533e9cd172d2fdaca`, [40513849690](https://github.com/M4D135/pesto/actions/runs/40513849690).** Les [preuves relues le 28 octobre](evidence/20261028/windows-e087bb1/README.md) confirment l’installation depuis les boutons en PROD et DEV, le retour séparé par le service, la recompilation depuis les sources du DEV livré avec cache NuGet neuf et SDK 10.0.302, puis le démarrage natif du résultat. Le [rapport C17](VALIDATION-C17-20261027.md) distingue ces acquis du retour par bouton UI, de l’AD, de l’UAC, de l’UNC réels et du profil ordinaire non qualifiés par cette campagne. Chaque preuve reste attachée à ce commit et à ses empreintes.

**Historique C16 — campagne Windows entièrement RÉUSSIE :** la [troisième campagne 40491875705](https://github.com/M4D135/pesto/actions/runs/40491875705), sur [`3a8c49d85d5cc16dcab2d7c743be7fa445d05715`](https://github.com/M4D135/pesto/commit/3a8c49d85d5cc16dcab2d7c743be7fa445d05715), termine avec succès le 27 octobre 2026. Elle valide l’accueil natif (**5 contrôles**), la saisie native (**16**), le démarrage et la coexistence locale/démo avec **44 refus directs d’API par canal**, et le nouveau banc de configuration : **36 contrôles, 9 dialogues Windows, 2 choix positifs de dossier et 6 captures WebView2 par canal PROD et DEV**. Les suites complètes et les **quatre cas transactionnels entre deux compilations, avec huit tentatives de santé**, réussissent également. L’archive de preuves a été téléchargée, son empreinte vérifiée et les huit JSON natifs recoupés ; la [synthèse des preuves C16](evidence/20261027/windows-3a8c49d/README.md) conserve leurs identités et leurs limites.

Artefacts C16, disponibles jusqu’au **26 novembre 2026** : [PROD](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12730361970), [DEV](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729157837) et [preuves Windows](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729422738). Les deux canaux utilisent l’EXE de SHA-256 `0d8e8936060098fffc25f7b807e14546b25df7244775abe7a3dcdee4ebb4bba8`. Les packs restent des candidats non officiels ; cette campagne ne qualifie ni AD, UNC ou UAC réels, ni l’installation confirmée depuis les boutons de maintenance.

Les deux premières campagnes restent des échecs distincts ; les résultats de la troisième ne leur sont pas réattribués :

| Source et campagne | Résultat observé du banc de configuration | Portée et correction |
|---|---|---|
| [`d803d72`](https://github.com/M4D135/pesto/commit/d803d72ed1084d631364a1830d6211d841e02813) — [40486971793](https://github.com/M4D135/pesto/actions/runs/40486971793) | Échec PROD au premier export, après 2 contrôles | Le texte saisi est relu stable mais le chemin retourné par l’hôte est refusé par la portée temporaire après l’export. Ce chemin n’a pas été enregistré : sa destination exacte et la cause de l’écart restent inconnues. Le correctif pilote la saisie avec focus, contrôle le chemin avant IO et conserve les erreurs et chemins réellement retournés. [Preuves du premier échec](evidence/20261027/windows-d803d72-failed/README.md). |
| [`1dbdda1`](https://github.com/M4D135/pesto/commit/1dbdda1020cf21ea2c65fc69b5572bbfc857095e) — [40489970770](https://github.com/M4D135/pesto/actions/runs/40489970770) | Échec PROD au premier choix positif de dossier, après 19 contrôles | Export, enregistrement et import sont réussis. Le pilote exclut l’Edit 1152 réellement observé dans le dialogue de dossier ; aucune saisie n’est tentée. Le filtre est corrigé par type de dialogue : 1152 pour les dossiers, 1001/1148 pour les fichiers, barre d’adresse 41477 toujours exclue. [Preuves du deuxième échec](evidence/20261027/windows-1dbdda1-failed/README.md). |

Ces deux campagnes n’ont exécuté ni la configuration DEV ni les transactions suivantes, et n’ont publié aucun candidat PROD/DEV. Les contrôles portables initiaux et les publications croisées des correctifs sont conservés séparément pour [`d803d72`](evidence/20261027/portable-d803d72/README.md), [`1dbdda1`](evidence/20261027/portable-1dbdda1/README.md) et [`3a8c49d`](evidence/20261027/portable-3a8c49d/README.md). Ils ne remplacent pas les preuves finales Windows.

**Historique C15 entièrement réussi :** [40479609012, commit `b875174`](https://github.com/M4D135/pesto/actions/runs/40479609012), le 27 octobre 2026. Elle couvre les 14 contrôles natifs de configuration par canal, démarrage, coexistence locale/démo et fermeture en PROD et DEV, 44 refus directs par canal, les trois cas transactionnels PROD et le cas normal DEV entre deux compilations distinctes. La [synthèse des preuves C15](evidence/20261027/windows-b875174/README.md) rassemble les empreintes et les liens des candidats et des captures. L’accueil et la saisie natifs passent aussi cinq et seize contrôles. C15 n’exécute aucun appel AD et ne rejoue pas l’UAC réel ; les preuves de laboratoire C14 restent historiques.

Artefacts C15 : [PROD](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723481580), [DEV](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723720181) et [preuves Windows](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723740186).

**Résultats transactionnels C15 :** PROD, installation depuis le ZIP B et retour explicite à A,
santé négative puis restauration de A, interruption pendant le contrôle de santé puis reprise vers A ;
DEV, installation depuis le ZIP B et retour explicite à A. Les sources et le cfg sentinelle extérieur
restent inchangés. Le [rapport historique C15](VALIDATION-C15-20261027.md) précise la portée de ces quatre cas et de leurs huit tentatives de santé.
Les échecs des premières campagnes restent dans le [rapport C6](VALIDATION-C6-20261026.md) ; les [preuves C5 de `de52731`](evidence/20261025/windows-de52731/README.md) restent historiques.

**Historique laboratoire C14 :** le pack PROD GitHub exact de `e5a6722` passe accueil, saisie native AD synthétique, démonstration et configuration, puis une élévation UAC réelle depuis un parent non élevé, en session console 1. Les cinq parcours terminent avec code 0. Les bancs restent isolés du profil ordinaire et ne font aucun appel AD. Cette preuve UAC demeure attachée au binaire C14, comme le précise sa [synthèse](evidence/20261026/windows-e5a6722/README.md).

Les essais AD C14 utilisent des harnais locaux distincts : `3316a6b` pour le renommage réel `P111301VA765158` → `P111301VA765586` et sa vérification après redémarrage, puis `e5a6722` pour le retour au nom initial et l’inspection finale. L’inspection du 26 octobre à 17:41 UTC retrouve le même GUID, Paris, UAC4096, protection false, domaine et canal sécurisé sains, noms actif/configuré cohérents et aucun renommage en attente. Les cinq anciennes entrées V1 sont inchangées. Le [rapport C14](VALIDATION-C14-20261026.md) conserve ces identités et leurs limites ; aucun de ces essais ne qualifie les binaires C15 ou C16 pour l’AD. Le déplacement Paris → Lyon → Paris reste lié au moteur C9 et à son rapport historique.

## Préconditions et traces

Consigner commit, hash EXE et ZIP, canal, version Windows et WebView2, identité du poste et compte utilisé sans secret. Utiliser exclusivement le poste/canari de laboratoire autorisé ; constater son état initial et disposer du retour prévu avant toute mutation. Ne jamais restaurer un contrôleur de domaine ni toucher aux VM voisines pour ce contrôle.

Le pack doit passer `make-pack.mjs --verify` ; la sortie est `PACK VÉRIFIÉ`. Le vérificateur refuse tout `wad/runtime/webview2/...` et tout `msedgewebview2.exe` dans un pack. Les options `--webview2`, `--webview2-version`, `--allow-missing-webview2` et `--evergreen` sont supprimées ; les passer donne un échec explicite (code 2). Les candidats sont `official=false`, `distribution=candidate`, `qualification=unqualified`. Cette checklist ne publie aucune release V2 et ne remplace pas V1.

### Chronométrer « Noms disponibles » sur Windows

Utiliser un candidat qui contient le fournisseur `Pesto-DirectoryRead`, introduit après `81e4b703`. Depuis PowerShell élevé, se placer dans le dossier de preuves de l’essai. Démarrer la collecte avant Pesto pour inclure la première découverte du contrôleur.

```powershell
$session = 'PestoRead-' + [guid]::NewGuid().ToString('N')
$etl = Join-Path (Get-Location).Path ($session + '.etl')
$provider = '{b705d7fc-108d-4e8d-9150-8191fb15936a}'
& logman.exe start $session -ets -p $provider '0xFFFFFFFFFFFFFFFF' 4 -o $etl
if ($LASTEXITCODE -ne 0) { throw 'Collecte ETW indisponible.' }
```

Associer la fenêtre au PID, à la session Windows, au chemin de l’EXE et à l’heure UTC de création relevés dans `live-launch.json`. Relever séparément en UTC le clic de navigation, l’affichage du site, du service et du nom sur le premier passage, puis lors du retour dans la même fenêtre. Conserver les captures. Arrêter la collecte dans le même terminal à la fin de l’essai, même en cas d’échec.

```powershell
& logman.exe stop $session -ets
if ($LASTEXITCODE -ne 0) { throw 'Vérifier la session ETW avant de lire le fichier.' }
& tracerpt.exe $etl -of XML -o ($etl + '.xml') -summary ($etl + '.summary.txt')
if ($LASTEXITCODE -ne 0) { throw 'Décodage ETW en échec.' }
```

Dans Windows Performance Analyzer, ouvrir l’ETL (`wpa.exe $etl`), puis **Generic Events**. Filtrer sur le fournisseur **Pesto-DirectoryRead**, l’événement **Duration** et le PID du Pesto lancé. Isoler chaque intervalle de capture dans la durée de vie de ce processus. Les champs utiles sont `operation`, `phase` et `milliseconds`. Un essai avec des événements perdus, un PID ambigu ou sans ligne décodée pour l’opération attendue reste indéterminé. [Capture avec Logman](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/how-to-capture-a-usb-event-trace) · [Export XML avec tracerpt](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/tracerpt) · [Lecture des événements autodescriptifs dans WPA](https://learn.microsoft.com/en-us/windows/win32/tracelogging/tracelogging-record-and-display-tracelogging-events)

`backend.total` inclut `backend.gateWait`. `module.verify` mesure le contrôle local du module pour chaque lecture. `worker.roundTrip` englobe le bootstrap éventuel du processus (`worker.bootstrap`) et le code PowerShell. Pour une réponse réussie, `ps.moduleImport`, `ps.selectedOu` et `ps.query` distinguent l’import, la validation de l’OU et la lecture demandée. `series.select` isole le calcul local du numéro après réception de l’inventaire. Les durées imbriquées se lisent séparément. Comparer le total moteur aux captures pour situer le temps restant entre l’action de l’opérateur et l’affichage.

## 1. Démarrage, fermeture et démonstration

| Essai | Preuve attendue | Dernière preuve disponible et limites |
|---|---|---|
| Pack LIGHT, moteur Evergreen ou Socle | Interface réellement prête ; Evergreen installé passe en premier, sinon `wad\runtime\webview2\msedgewebview2.exe` validé contre l’index embarqué, sinon message clair avec le lien de la release du Socle ; aucune erreur de fenêtre | Démarrage et démo natifs réussis sur `2adf60e` (runtime fixe, avant la 2.0.10) ; session AD normale à exécuter |
| Fermeture par la croix avec lecture en cours | Fenêtre et processus Pesto/WebView2 associés terminés normalement ; pas de processus étranger arrêté | Smoke, enfant puis parent avec second enfant fermés sur `2adf60e` ; fermeture pendant lecture AD à exécuter |
| Démo ouverte depuis un parent en configuration locale | Autre fenêtre/profil ; brouillon, route et préférences conservés ; bannière permanente | Réussi en PROD et DEV sur `2adf60e` |
| Démo ouverte depuis une session AD connectée | Autre fenêtre/profil ; contexte AD normal conservé | À exécuter ; le parent local du banc ne construit aucun adaptateur AD |
| Reset et scénarios | Plans périmés invalidés ; nouveaux IDs distincts ; redémarrage fictif fonctionne sans reboot Windows | Reset, IDs distincts et redémarrage fictif prouvés sur `2adf60e` ; ce parcours natif ne teste pas le rejeu d’un ancien plan ni les huit scénarios |
| Appels directs configuration/UNC/GitHub/host depuis démo | Refus avant dialogue, IO externe ou HTTP ; aucun profil réel modifié | `2adf60e` : 44 refus par canal, aucun appel hôte interdit, aucun profil réel créé |

`Pesto.exe --qualify-demo <nouveau-sous-dossier-de-Temp>` automatise une partie de ce contrôle sur le vrai MainForm/WebView2. Le code courant vérifie 44 refus directs, dont les huit API de réservation/coordination et les cinq API réelles de compte précréé, acquittement et redémarrage, les dix API attributs/ODJ, ainsi que la non-création du profil réel sentinelle. Les campagnes antérieures ne comportant que 21 ou 29 refus restent identifiées séparément dans le rapport. La preuve n’est écrite qu’après fermeture. Le workflow `pesto-v2.yml` exécute ce smoke pour le pack LIGHT ; le pack DEV, jamais publié, y est seulement assemblé et vérifié. Il n’atteste pas une session AD normale ni le contexte UAC d’un autre utilisateur.

`Pesto.exe --qualify-configuration <nouveau-sous-dossier-de-Temp>` lance, depuis 2.0.14, le banc de la configuration par défaut écrite sur place décrit dans la section suivante : vrais boutons de MainForm/WebView2, confirmations, sélecteurs Windows et observations du pont et des services réels, sur une copie du pack. Ce banc n’a pas encore été exécuté sous Windows. Le banc C16 de l’ancien bouton, qui fabriquait un pack personnalisé, réussissait en PROD et DEV sur `2adf60e`, avec preuves recoupées dans la campagne complète C18 ; il est décrit dans la section « Historique ». Le banc historique C15 de `b875174` réussissait 14 contrôles par canal ; il annulait le choix du dossier puis construisait le pack par appel direct au service. Ce résultat historique reste distinct de la preuve du nouveau parcours C16 et de sa sélection positive de dossier.


### Banc de coexistence introduit en C6 — réussi en PROD et DEV sur C18

Le parcours ouvre un parent **en configuration locale**, avec profil et registre GP temporaires
dédiés, puis déclenche la démo depuis son interface. Le parent ne construit aucun adaptateur AD et ne
dispose d’aucun domaine connecté. Un brouillon de paramètres non enregistré, sa route et ses préférences
doivent rester identiques pendant les interactions avec les fenêtres de démo.

Le parcours contrôle la bannière permanente, les scénarios, la remise à zéro et le redémarrage fictif,
ainsi que les identifiants de reçus distincts après reset et entre deux fenêtres. Il vérifie les profils
séparés, la fermeture d’un enfant puis celle du parent avec un nouvel enfant ouvert, sans appel hôte
interdit. Le rapport `proof.json` doit contenir `coexistence.success=true` et les contrôles associés ;
captures et détails sont conservés sous `coexistence/`. Les profils temporaires doivent être nettoyés.
Ces preuves sont obtenues en PROD et DEV sur `2adf60e` lors de C18 : six transitions avec un nouveau montage DOM,
trois profils, deux instances de démo et trois IDs de reçus distincts. Le même reçu passe de
`pendingRestart` à `simulated` après le redémarrage fictif, sans changement de route ; le reset revient
vers Ajouter. Les compteurs hôte interdit et coordination valent zéro, aucun profil réel n’est créé et
les profils temporaires sont supprimés. Les deux JSON et les huit captures sont conservés dans les preuves C18 ; les contrôles confirment que les valeurs
visibles du parent sont conservées et le même reçu passe de « Redémarrage en attente » à « Simulé ».
Ces essais ne remplacent pas le contrôle du contexte d’une session AD réelle ni celui d’une autre
identité UAC ; aucune capture réseau indépendante n’a été réalisée.

## 2. Configuration et UAC critiques

### Banc de configuration 2.0.14 — configuration par défaut écrite sur place, pas encore exécuté sous Windows

Depuis 2.0.14, « Définir comme configuration par défaut » ne fabrique plus de pack : le bouton écrit `wad\defaults\configuration.json` dans l’installation en cours, hors de l’identité du pack. Le banc `Pesto.exe --qualify-configuration <nouveau-sous-dossier-de-Temp>` a été réécrit pour ce parcours ; sa preuve passe au schéma 3. **Il compile sur le Mac, mais il n’a encore tourné sur aucun runner Windows : aucun des 44 contrôles ci-dessous n’est qualifié à ce jour.** Le résultat C18 décrit plus bas porte sur l’ancien bouton et ne vaut pas pour ce parcours. Dans la CI actuelle, seul le pack PROD-LIGHT passe ce banc.

Le banc ouvre la vraie fenêtre **MainForm/WebView2** sur les Paramètres, avec une configuration synthétique (`example.local`) préparée avant son démarrage dans un nouveau profil temporaire, sans adaptateur AD. Avant l’ouverture, il exige que le pack lancé ne contienne pas `wad\defaults`, puis le copie par `UpdatePackage.CopyToNew`, avec l’empreinte validée, dans son dossier temporaire. **Cette copie est l’installation passée à `ApplicationServicesBackend` et à `UpdateService`** : le banc n’écrit jamais dans le pack lancé, que la CI contrôle ensuite (absence de `wad\defaults`, puis `make-pack --verify`). Les scripts compilés cliquent les boutons et confirmations de la page sans appeler le bridge ; les observations enregistrent les vrais appels et résultats du moteur, sans réponse fabriquée.

| Groupe | Contrôles | Vérification principale |
|---|---:|---|
| Copie et ouverture | 3 | Copie identique au pack lancé (empreinte, inventaire, SHA256SUMS, manifeste, exécutable, aucun `wad\defaults`) ; page prête en mode configuration |
| Export, enregistrement et import | 14 | Inchangés depuis C16 |
| Configuration par défaut depuis le bouton | 14 | Confirmation sans appel d’écriture ni fichier, puis annulation ; refus réel d’un dossier non inscriptible ; écriture positive ; second clic sans réécriture |
| Vérifications de service du fichier écrit | 3 | Profil neuf importé ; profil existant différent conservé, décision en attente ; choix « Conserver » mémorisé |
| Ancien pack personnalisé et maintenance | 7 | Fixture scellée fabriquée par code ; inspection, préparation, confirmation d’installation annulée et lecture d’état depuis les boutons |
| Intégrité | 3 | Aucun appel interdit ; configuration et export conservés ; pack lancé inchangé et sans `wad\defaults` |

- **Confirmation.** Le clic relit `configuration.status`, puis ouvre « Définir comme configuration par défaut » avec le bouton « Enregistrer comme défaut ». Aucun appel `configuration.setDefault` ni aucun fichier avant la confirmation ; l’annulation n’appelle rien.
- **Refus réel.** Une règle ACL Deny (création de fichiers et de dossiers, écriture), sans héritage, est posée pour le SID courant sur `wad` de la copie. Après confirmation, le moteur doit refuser par `config.default_readonly`, avec son message exact ; le statut de la carte doit valoir exactement « Configuration par défaut non enregistrée : » suivi de ce message, sans notification de succès. Aucun fichier, aucun temporaire, aucune copie dans le profil ; empreinte et inventaire inchangés. La règle est retirée aussitôt, puis de nouveau avant le nettoyage si une étape a échoué ; la preuve porte `readOnlyRuleLeftInPlace`. Ce refus ne reproduit ni Program Files ni une session non élevée : il ne qualifie pas l’UAC réelle.
- **Écriture.** Statut exact « Configuration par défaut enregistrée dans cette installation : wad\defaults\configuration.json (version native-ui-qualification). » et notification « Configuration par défaut enregistrée. ». Le moteur rend `written`, le fichier de la copie, l’empreinte de configuration de l’export et la distribution d’origine (`candidate` en CI ordinaire, `official` en publication). Ensuite, `UpdatePackage.Validate` rend la même empreinte, la même distribution et le même nombre de fichiers ; les octets de SHA256SUMS, du manifeste et de `Pesto.exe` sont inchangés ; le fichier est exactement la forme canonique de l’export de l’interface et reste seul sous `wad\defaults`. Un second clic transmet le SHA-256 affiché et doit rendre `unchanged` sans rien réécrire.
- **Ancien pack personnalisé.** `LegacyCustomPack.Build` fabrique par code, en lisant seulement le pack lancé, un pack au format produit par le bouton jusqu’en 2.0.13 (défaut scellé, `distribution=custom`). Cette fixture n’est pas un parcours d’interface. Son dossier est ensuite choisi par le sélecteur Windows ; inspection et préparation passent par les boutons, avec la mention « Pack personnalisé », au-dessus d’une installation qui porte déjà un défaut local de même empreinte. La confirmation d’installation est annulée : **l’installation de cet ancien pack n’est pas exécutée** ; `legacyCustomPackPreparedFromUiQualified` ne couvre que l’inspection et la préparation.

Le banc pilote **7 dialogues Windows** : six sélecteurs de fichier (export et variantes d’import, dont trois annulés ou refusés) et un seul choix positif de dossier, l’ancien pack personnalisé. Il produit **6 captures WebView2** : export, aperçu d’import, confirmation de la configuration par défaut, statut après écriture, mise à jour préparée et confirmation d’installation. La CI exige la liste ordonnée des 44 contrôles, ces deux nombres, les indicateurs `installationDefaultButtonFlowQualified`, `readOnlyRefusalQualified`, `legacyCustomPackPreparedFromUiQualified`, `sourcePackUnchanged` et `sourcePackDefaultsAbsent` à `true`, et `nativeUpdateInstallFromUiQualified`, `adQualification`, `adExecuted`, `realUac`, `ordinaryProfileAccess`, `uncQualification` et `readOnlyRuleLeftInPlace` à `false`. Ce banc ne qualifie pas la conservation du fichier pendant une mise à jour ou un retour arrière réels.

### Historique — banc C16 de l’ancien bouton, 36 contrôles réussis par canal sur C18

Ce parcours (choix d’un dossier parent, création d’un nouveau pack personnalisé) n’existe plus depuis 2.0.14. Ses résultats restent ceux de `2adf60e` et ne qualifient pas le banc 2.0.14 ci-dessus.

Le banc ouvre la vraie fenêtre **MainForm/WebView2** sur les Paramètres, avec une configuration synthétique préparée avant son démarrage dans un nouveau profil temporaire. Il ne construit aucun adaptateur AD. Les scripts compilés saisissent les champs et cliquent les boutons et confirmations de la page ; ils n’appellent pas directement le bridge. Les observations du backend enregistrent les vrais appels et résultats, sans fabriquer de réponses de succès. Les empreintes des fichiers, des sauvegardes et des packs complètent ces observations.

Le gate de la [campagne 40675773761](https://github.com/M4D135/pesto/actions/runs/40675773761) valide les **36 contrôles suivants dans chacun des canaux PROD et DEV** sur `2adf60e` :

| Groupe | Contrôles réussis | Vérification principale |
|---|---:|---|
| Ouverture | 2 | Page prête, mode configuration et profil isolé |
| Export, enregistrement et import | 14 | Version saisie puis export natif exact ; différences avant enregistrement ; confirmation et sauvegarde exacte ; annulations ; encodage invalide refusé ; aperçu d’import avant écriture, confirmation et retour exact à la configuration exportée |
| Pack personnalisé depuis les boutons | 9 | Confirmation préalable ; annulation de la confirmation puis du sélecteur ; choix positif du dossier parent ; résultat visible ; manifeste, exécutable et paramètres distribués exacts ; aucun répertoire de préparation résiduel |
| Vérifications de service du bundle produit | 2 | Initialisation d’un profil neuf puis conservation d’un profil existant |
| Maintenance depuis les boutons | 6 | Inspection du dossier, préparation du candidat et copie exacte ; confirmation d’installation sans envoi, annulation de cette confirmation, puis lecture d’état |
| Intégrité | 3 | Aucun appel interdit ; configuration et export conservés ; pack source inchangé |

Les deux vérifications de profil utilisent directement `ProfileConfigurationService` sur le bundle créé par l’interface. Elles sont identifiées comme des contrôles de service, **pas comme deux parcours supplémentaires de boutons**. La préparation initiale de la fixture précède également l’ouverture de MainForm. Après cette ouverture, les modifications de la configuration du profil de travail passent par l’interface.

Le gate réussi confirme **9 dialogues Windows par canal** : six sélecteurs de fichier pour l’export et les variantes d’import, puis trois sélecteurs de dossier. Deux choix de dossier sont positifs : le dossier parent du pack personnalisé et le dossier de ce pack pour son inspection comme candidat de mise à jour. Le troisième choix de dossier est annulé. Un chemin accepté doit avoir été relu identiquement au moins trois fois ; le pilote exige ensuite un bouton actif et la fermeture effective du dialogue. La présence du fichier ou du pack et la réponse réelle du service sont vérifiées séparément. Le chemin retourné par le sélecteur est enregistré et contrôlé dans la portée temporaire avant toute lecture ou écriture de l’hôte.

Les **6 captures WebView2 par canal** documentent l’export, l’aperçu d’import, la confirmation de création du pack, le résultat de création, la mise à jour préparée et la confirmation d’installation. Elles représentent ces écrans web, pas les sélecteurs Windows eux-mêmes. La preuve `proof.json` au schéma 2 conserve les étapes DOM, les observations des dialogues et les appels backend/hôte. Le succès exige aussi la fermeture du parent, le nettoyage des données temporaires et la conservation de l’empreinte du pack source. Le banc possède une borne de 480 secondes ; le workflow laisse 600 secondes au processus pour terminer et rendre sa preuve.

**L’installation effective depuis l’interface n’est pas qualifiée par ce parcours.** Le bouton d’installation ouvre sa confirmation, puis le banc l’annule ; il exige zéro appel `updates.install`, aucun relais en attente et aucune transaction engagée. Les sentinelles refusent les autres effets hôte et tout accès HTTP. Les indicateurs `nativeUpdateInstallFromUiQualified`, `adQualification`, `adExecuted`, `realUac`, `ordinaryProfileAccess` et `uncQualification` restent `false` dans les deux preuves finales. Les transactions natives entre deux compilations, décrites plus bas, réussissent également lors de C18, mais passent par leur propre banc et les API du service. Un autre banc C18 qualifie séparément l’installation confirmée depuis les boutons, comme précisé ci-dessous.

### Installation confirmée depuis les boutons — preuve distincte C18

Le banc `Invoke-NativeUpdateUiQualification.ps1` réussit en PROD et DEV sur `2adf60e`. Il sélectionne le ZIP de la référence par le dialogue Windows, inspecte et prépare le pack, annule une première confirmation puis confirme explicitement l’installation. Il exige un seul appel `updates.install`, la fermeture du parent, le lancement du helper attribué, le remplacement exact et une santé native réussie. Le retour vers le candidat passe ensuite par le service transactionnel, avec nouvelle santé et conservation de la configuration sentinelle.

Les preuves finales [PROD](evidence/20261028/windows-2adf60e/native-update-ui-PROD.json) et [DEV](evidence/20261028/windows-2adf60e/native-update-ui-DEV.json) portent `nativeUpdateInstallFromUiQualified=true` et `nativeServiceRollbackQualified=true`. `nativeRollbackFromUiQualified` reste `false`. Le reçu de relais du parent, écrit avant la fin, n’accorde pas lui-même le verdict final d’installation. Ces profils isolés ne qualifient ni UAC réelle, ni profil ordinaire, ni UNC/AD réels.

### UAC et qualifications complémentaires

La preuve historique `--qualify-uac` du paquet C14 exact `e5a6722` part d’une console non élevée : le bouton d’accueil ouvre le consentement Windows, puis le processus enfant prouve le jeton élevé et le même hash d’EXE avec PID/nonce liés. Ce banc ne lit ni profil ordinaire ni AD. Les CI C15 à C18 ne rejouent pas ce contrôle UAC réel. Sur `2adf60e`, les cinq contrôles d’erreur/annulation et de redimensionnement passent dans `--qualify-welcome`, avec résultats d’élévation synthétiques ; `--qualify-login` réussit seize comportements de saisie native sur secrets synthétiques. Aucune de ces preuves ne qualifie une élévation sous un autre compte.

Le choix positif du dossier et la création complète d’un pack par les boutons (parcours de l’ancien bouton, jusqu’à 2.0.13) réussissent dans le banc isolé C18 sur `2adf60e`. Les profils ordinaires, ACL réelles, conflits de référentiel et effets d’une élévation sous un autre compte demandent toujours leurs preuves propres.

| Essai | Preuve attendue |
|---|---|
| Configuration par défaut écrite par le bouton dans une installation PROD réelle | `wad\defaults\configuration.json` présent ; `SHA256SUMS`, manifeste, empreinte et distribution inchangés ; aucun secret, historique, cache ni session |
| `--settings` non élevé sous `C:\Program Files` | Refus `config.default_readonly` ; aucun fichier, temporaire ni copie de profil |
| Mise à jour puis retour arrière avec une configuration par défaut locale | Octets conservés par la mise à jour ; au retour, modification ou suppression depuis la mise à jour conservée, et confirmation conforme |
| Retour vers 2.0.13 avec une configuration par défaut locale | Fichier sous `<transaction>\defaults-set-aside\installation\` ; 2.0.13 démarre |
| Profil neuf | Import automatique dans le LocalAppData du bon opérateur ; pack source inchangé |
| Profil existant + nouvelle version/empreinte | Différences exactes ; Conserver ne remplace rien ; choix mémorisé pour ce profil seulement |
| Remplacer après confirmation | Sauvegarde relisible, remplacement atomique, invalidation des anciens plans |
| UAC avec autre compte administrateur | Config et préférences restent dans le profil de l’opérateur d’origine ; aucun second cfg dans celui de l’admin |
| Référentiel avec conflit puis réimport | Aucun changement avant résolution ; application unique ; aucun doublon |
| Santé ou rollback après modification de configuration | Même hash du cfg actif avant/après ; aucun ancien défaut réimporté automatiquement |

## 3. Opération AD canari réversible

La CI C18 n’exécute aucun canari AD. La procédure ci-dessous reste à qualifier sur les ZIP exacts `2adf60e` ; les preuves de laboratoire C14 et celles du harnais courant ne leur sont pas transférées.

Au point de laboratoire du 28 octobre, le harnais distinct a produit un retour Lyon → Paris, suivi d’une lecture indépendante retrouvant le même GUID, le SID original et un canal sain. Le poste porte encore le nom `P111301LY765715` ; la restauration du nom initial n’a pas été lancée. Ce résultat borné ne constitue ni une fin de restauration ni une qualification AD des ZIP C18.

Les fonctions sont raccordées à l’hôte normal. Le profil distinct du harnais reste disponible avec le jeu complet `--qualification-harness --mutation-adapter ps51 --confirm-qualification "QUALIFICATION WINDOWS/AD" --v1-root <dossier-local>` ; ce choix ne dispense d’aucun contrôle métier.

1. Relire le canari par GUID, nom, OU, protection, appartenance au domaine et état Entra ; capturer le reçu/état initial. Confirmer qu’aucune barrière GP n’interdit l’opération.
2. Préparer une opération réversible limitée à ce canari. Vérifier que le nom réellement proposé figure déjà dans l’interface avant l’action. Vérifier les étapes et OU puis fournir la confirmation exacte.
3. Observer la commande native et le reçu durable, puis relire l’AD et la cible. Un succès de commande ne vaut pas confirmation de l’état final. Si un redémarrage est nécessaire, il reste une action séparée de l’opérateur.
4. Revenir à l’état initial par une **nouvelle** préparation et confirmation, jamais en rejouant le reçu. Relire le retour par GUID/nom/OU/protection.
5. Si le résultat est partiel 89, ne reprendre que le déplacement restant après preuve du renommage ; si incertain, arrêter et conserver la preuve. Aucun nettoyage de verrou pour faire passer le test.

La tâche de contrôle Entra distante et le repli de renommage exigent des preuves natives distinctes : principal réellement exécuté, définition/empreinte, absence de secret, codes de sortie, nettoyage relu ou tâche conservée sur incertitude. Un poste hybride n’est jamais retiré automatiquement d’Entra. Le parcours hybride doit faire l’objet d’une qualification dédiée avec un poste autorisé et une procédure de réenrôlement établie : politique, case de consentement, intention durable avant l’unique retrait, preuve AD seul, conservation de l’effet si le renommage échoue. Un canari AD ordinaire ne qualifie pas ce parcours.

Les preuves Windows distantes doivent être comparées au poste effectivement ciblé : MachineGuid, boot Kernel-General/12, noms actif/configuré, domaine/rôle et canal sécurisé, avec GUID/OU/protection AD relus sur le DC exact. Vérifier aussi un résultat absent ou altéré, le nettoyage du seul fichier possédé et la conservation des tâches en cas d’incertitude. La continuation d’un résultat 89 ne doit jamais rejouer le renommage.

Le redémarrage réel se teste seulement depuis son plan distinct après confirmation du nom courant. Conserver la demande durable et prouver qu’un résultat accepté n’acquitte pas le reçu métier ; une seconde demande sur le même boot doit être refusée. La réconciliation après le nouveau boot doit comparer toutes les identités. L’acquittement motivé se teste séparément : reçu original inchangé, événement lié au hash exact, auteur/date/motif restitués après fermeture, absence de worker/tâche encore active et libération des seuls verrous possédés après persistance. Un compte précréé doit rester le même GUID/OU tout au long du parcours, sans création implicite ni assouplissement des droits Netjoin.

### Ports attributs, ODJ et CLI

Ces contrôles utilisent le même canari autorisé et une configuration dédiée, après observation de son état initial. Ils ne sont pas considérés passés par les fixtures ou le parseur PS5.1.

- **Attributs :** description/emplacement/managedBy, diff affiché (y compris effacement et GUID du responsable), confirmation, relecture exacte, reçu durable ; restauration des valeurs initiales par un nouveau plan. Interrompre la réponse ne doit produire ni succès sans preuve ni deuxième Set-ADObject.
- **Pilote :** première ligne seule préparée et envoyée ; toutes les autres conservées jusqu’à une nouvelle confirmation. Un pilote incertain ne vaut pas pilote terminé.
- **ODJ :** PC hors domaine autorisé, blob provisionné pour son nom actuel, import protégé/ACL, aucun AD avant observation explicitement demandée ; intention et marqueur natifs avant djoin, un seul envoi ; redémarrage manuel puis preuve nouvelle du boot/GUID/OU/domaine/canal. L’ancien blob reste non rejouable après interruption et après acquittement générique refusé. Le retour arrière est une opération de laboratoire préparée séparément, jamais une suppression automatique par Pesto.
- **CLI :** console déjà élevée, profil d’origine, aucune invite, plan exporté puis double opt-in ; DPAPI sous le compte effectif et pipe fermé ; pipe resté ouvert doit être refusé au délai sans lecteur résiduel. Résultat0 ou3010 lié aux octets du reçu ; reprise avec même clé sans nouvel accès AD ; perte/altération du reçu =97. Accord de campagne si GPO active, hash du plan V2 exact.
- **Fermeture :** fermeture du parent pendant une opération dans sa fenêtre ODJ ; le parent attend la fin de l’enfant et les deux disparaissent sans second clic, après finalisation du reçu.

## 4. Mise à jour, rollback et reprise

Utiliser deux packs LIGHT candidats issus de compilations distinctes, jamais les releases V1. Conserver leurs
vraies versions : une version identique est admise si les commits sources et hashes EXE sont distincts ;
le candidat ne doit pas être plus ancien que la base. Consigner hashes et arbre de fichiers, ainsi que
le hash du cfg concerné. Le banc automatique décrit plus bas utilise uniquement un cfg sentinelle isolé.
Un pack avec WebView2 intégré (`fixed`) est refusé (`package.edition`) ; le conseil est d’installer le
LIGHT dans un nouveau dossier. La migration depuis 2.0.9 PROD (ancien pack avec WebView2 intégré) ne
peut pas se faire en place : le code 2.0.9 refuse un pack evergreen. Installer le pack LIGHT dans un
nouveau dossier ; si Evergreen manque, extraire le Socle dans `wad\` ou recopier le `wad\runtime\webview2`
de l’ancienne installation à condition qu’il soit identique au Socle (sinon Pesto le refuse). La
configuration du profil de l’opérateur n’est pas dans le pack et n’est pas touchée.

| Essai | Preuve attendue |
|---|---|
| Inspection ZIP et dossier/UNC | Aperçu exact ; aucune installation ni exécution de contenu lors de l’inspection |
| Préparation explicite | Copie isolée validée ; installation et profil inchangés |
| Installation confirmée | Parent et WebView2 fermés ; helper copié du binaire A ; backup durable ; pack B exact en place |
| Santé valide | Vrai chargement WebView2, fermeture normale ; preuve nonce/transaction/version/hash cohérente |
| Santé refusée | Ancien pack restauré et contrôlé ; candidat défaillant conservé ; résultat jamais présenté comme réussite |
| Rollback explicite | Ancien binaire restauré ; configuration actuelle inchangée |
| Interruption à chaque frontière de renommage/journal | Reprise déterministe depuis le journal ou double-clic helper ; aucun écrasement d’une modification concurrente |

Les `UpdateTests` vérifient les frontières d’interruption sur dossiers/fixtures. Ils ne remplacent pas l’essai natif avec un exécutable chargé, les verrous WebView2, UAC et un vrai partage UNC.

### Historique C5 conservé

Trois cas sont **réussis sur `de52731` en PROD** : installation/santé/rollback explicite, santé négative/rollback,
puis interruption du contrôle de santé/reprise. Cette campagne utilisait le même binaire réel et le même
runtime dans ses variantes, avec des versions de manifeste synthétiques. Les preuves confirment deux
tentatives de santé distinctes par cas et la conservation du pack source et de la configuration sentinelle.
Elle ne couvre pas une transaction DEV, l’acquisition native du vrai ZIP candidat, ni deux compilations
applicatives indépendantes. Ses résultats restent ceux de la [campagne C5 historique](evidence/20261025/windows-de52731/README.md).

### Banc C6 entre deux compilations sur copies isolées

Le workflow V2 exécute `tools/qualification/Invoke-NativeUpdateQualification.ps1` après les smokes
PROD/DEV et avant la publication des artefacts. Les ZIP candidats sont déjà créés avant cette étape et
ne sont pas réécrits après le contrôle. Le compagnon `Pesto.UpdateQualification.dll` est construit avec
`UseAppHost=false` : il n’ajoute aucun autre exécutable Pesto. Le script utilise Windows PowerShell 5.1
et exige un jeton déjà administrateur ; une demande UAC bloquée n’est pas automatisée ni considérée
comme un succès.

La baseline **A** est reconstruite à chaque CI depuis le commit épinglé
`962f3ba0826730077b2ccd918e0f8415870646bb` (2.0.10, pack LIGHT, canal PROD seulement), avec le SDK de la campagne.
Le dépôt recréé le 9 novembre 2026 n’a plus `ef759f6a`, la baseline précédente ; avant la 2.0.10, c’était `de527313`, en PROD fixe. Son propre
script de packaging fournit son interface et ses fichiers sources. **B** est la compilation du nouveau
commit testé. Le banc exige des commits et SHA-256 de `Pesto.exe` distincts ; leurs valeurs effectivement
produites sont consignées. Il ne dépend ni des anciens artefacts à durée de rétention limitée ni de la
reproduction exacte du hash EXE historique de A. Les deux packs LIGHT doivent être complets, du même canal,
déclarés candidats et dépourvus de configuration personnalisée. Le Socle WebView2 (version Microsoft
156.0.4314.42, dépôt privé `M4D135/socle-windows`) reste hors de l’identité du pack : il n’entre ni dans
`wad\SHA256SUMS`, ni dans l’empreinte, ni dans le nombre de fichiers. À la mise à jour et au retour arrière,
le Socle de l’installation est recopié à l’identique vers la nouvelle version.

Le banc copie physiquement A dans un nouveau sous-dossier local de Temp, sans liens physiques ou
jonctions. Le cas normal inspecte le **ZIP B réel fourni** puis prépare ses octets par les API publiques
du service. Son empreinte doit être exactement celle du dossier B validé, manifeste et version compris.
Un ZIP absent ou différent provoque un refus, sans repli sur le dossier B et sans preuve de qualification.
L’inspection et la préparation doivent laisser A intact avant la confirmation.

| Canal | Cas exigés | Identités natives attendues |
|---|---|---|
| LIGHT (jeton `PRODLIGHT`) | `normal` : ZIP B, installation et rollback explicite ; `health-failure` : santé négative et retour ; `interruption` : arrêt pendant `checking`, puis reprise | Helper A ; santé candidat B ; santé du retour A |
| DEV (jeton `DEV`) | `normal` : ZIP B, installation et rollback explicite, si A connaît les sources DEV exactes de B ; sinon `format-refusal` : ZIP B préparé, le helper A refuse un chemin de `UpdatePackage.DevExactSourcePaths` par son propre dialogue, code non nul, journal resté `prepared`, aucune sauvegarde ni santé, A intact | Helper A ; santé candidat B ; santé du retour A — ou helper A seul pour le refus |

Le compagnon choisit le cas DEV d’après les deux packs (`scenarios`) : B contient au moins une source
exacte et A aucune. Depuis `de527313`, c’est un refus : la mise à jour DEV en place n’est pas qualifiée
et la preuve le déclare (`inPlaceUpdateQualified: false`, `formatRefusalQualified: true`,
`newInstallationRequired: true`). Le dialogue n’est fermé que s’il appartient au helper validé, s’intitule
`Pesto v2` et cite exactement l’un de ces chemins ; tout autre refus reste un échec. La migration DEV
correspondante est une nouvelle installation (voir `PACKAGING.md`). Pesto n’interroge plus GitHub : un pack choisi
localement doit être de la même édition que l’installation, sinon `package.edition`.

Les cas négatifs LIGHT modifient uniquement une copie de B : page présente et hashée mais dépourvue du
shell attendu, notice de panne synthétique, retrait de `sourceCommit` pour ne pas prétendre conserver
l’arbre intact, puis nouvel inventaire. Le binaire B et la vraie version restent inchangés.
Aucune version synthétique ne participe à C6. Le cas de santé négative exige une preuve de refus durable
puis une santé positive de A. Le cas d’interruption exige l’observation de `checking`, du processus de
santé et d’un descendant WebView2 avant l’arrêt du seul arbre créé, puis une reprise native.

Le processus qui prépare la transaction sort avant chaque lancement du vrai helper, y compris pour
le retour et la reprise. Toute coupure revérifie PID, heure de création et chemin du helper créé.
Un inventaire ambigu est rejeté en entier ; le banc peut attendre un inventaire entièrement attribuable
dans la borne de 210 secondes. Avant l’arrêt, il exige un second inventaire complet, les empreintes du
helper A et du processus santé B, ainsi que le journal encore à `checking`. Dans la campagne historique C14 sur `e5a6722`,
aucun refus d’attribution n’a été rencontré ; deux descendants et le helper sont arrêtés après
les revérifications exigées. La campagne historique C7 (`95f8ce0`) avait rencontré un refus
`descendant-image-outside-case` avant un inventaire accepté et l’arrêt de trois descendants.
Les observations des deux campagnes restent distinctes.
La boîte de résultat est acquittée uniquement pour ce PID, avec classe et titre attendus, après un
état terminal. Le moniteur attend un dialogue de ce helper ou sa sortie avant d'ouvrir le journal ;
pour l'interruption, il attend d'abord les vrais descendants santé et WebView2 attribués, puis exige
toujours `checking` et les revérifications avant l'arrêt. Il évite ainsi de lire pendant les mutations
de l'ancien helper : sous Windows, `FileShare.Delete` seul ne suffit pas à éviter tous les refus de
remplacement. Les flux restent partagés et sont fermés avant l'analyse JSON.

La limite globale reste de 210 secondes. Le refus DEV doit être identifié en moins de 60 secondes
depuis le début de l'observation. La garde de 30 secondes borne désormais la reconnaissance du
dialogue observé, sa fermeture et la sortie du helper. Elle ne mesure plus l'intervalle entre une
transition terminale non observée et l'apparition du dialogue. Un dialogue fatal générique, un journal
non terminal, une sortie non conforme ou une restauration non prouvée restent des échecs.

Les reçus `health-attempts`, les transitions effectivement observées, les identités de processus et les preuves par étape sont
conservés. Les empreintes des packs A et B, du ZIP B et du `cfg.json` sentinelle extérieur aux packs
doivent rester identiques. Les canaux et scénarios sont séquentiels ; seules les copies d’un cas entièrement réussi sont
retirées après conservation des preuves. Un cas incomplet, une frontière perdue, une identité de
processus restant inconnue, un délai expiré ou une santé non confirmée fait échouer la campagne. La limite CI est de **dix-huit
minutes pour les deux canaux**. La troisième campagne C16 sur `3a8c49d` réussit les trois cas PROD et le cas normal DEV, avec **huit tentatives de santé** au total : installation depuis le ZIP B et retour explicite à A dans chaque canal ; santé négative puis restauration de A et interruption puis reprise vers A en PROD. Les preuves confirment deux compilations distinctes, sans version synthétique, et la conservation des packs sources A/B, des ZIP candidats et des configurations sentinelles extérieures aux packs. La [synthèse finale C16](evidence/20261027/windows-3a8c49d/README.md) conserve les empreintes et les quatre résultats. Les deux premières campagnes C16 n’avaient pas atteint cette étape ; les réussites C15 sur `b875174` restent historiques.
La reprise après interruption se termine à `rolledBack`, avec restauration et santé de A prouvées ;
elle ne déclare pas B installé. Les refus et résultats partiels des campagnes précédentes restent
conservés dans leurs rapports datés, sans être requalifiés rétroactivement. Ces transactions passent
par le banc et les API du service ; elles ne qualifient pas le parcours complet des boutons de mise à jour.

Depuis `v2/` du dépôt ou `wad/dev/` du pack DEV, dans une console Windows déjà élevée, avec des packs A
et B du même canal et un ZIP B existant :

```powershell
dotnet build tools/qualification/Pesto.UpdateQualification/Pesto.UpdateQualification.csproj -c Release --disable-build-servers -m:1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/qualification/Invoke-NativeUpdateQualification.ps1 `
  -BasePack 'C:\qualification\base\LIGHT' `
  -CandidatePack 'C:\qualification\candidat\LIGHT' `
  -CandidateZip 'C:\qualification\Pesto_V2_PRODLIGHT_candidate.zip' `
  -RunnerDll (Resolve-Path 'tools/qualification/Pesto.UpdateQualification/bin/Release/net10.0/Pesto.UpdateQualification.dll').Path `
  -DotNet 'C:\Program Files\dotnet\dotnet.exe' `
  -ReportDirectory 'C:\qualification\nouveau-rapport-PROD'
```

Les six arguments sont obligatoires. Pour DEV, fournir les deux packs et le ZIP DEV et un autre
`ReportDirectory` neuf ; le canal du manifeste choisit les scénarios, sans option permettant de réduire
les trois cas LIGHT. Les sources, l’archive et les rapports sont des chemins locaux sur volume fixe,
sans UNC, liens ou jonctions. Le banc conserve les sources et crée lui-même sa racine Temp unique.

Le verdict se trouve dans `transaction-evidence/proof.json`, ou dans `failure.json` et les journaux en
cas d’échec. Le rapport final au schéma 2 conserve `base`, `candidate`, leurs commits/versions/empreintes
EXE, `candidateZipSha256`, les résultats par scénario et la conservation des sources et du
profil sentinelle. Un succès exige `distinctBuilds=true`, `syntheticVersions=false`,
`zipAcquisitionQualified=true` et `nativeBinaryUpdateQualification=true` pour **le canal et les cas
effectivement exécutés**. La preuve DEV ne vaut pas preuve de panne/reprise DEV. Les détails d’acquisition
sont dans `acquisition.json` de chaque cas.

Le banc n’exécute aucun accès AD, SMB ou HTTP ; `adQualification=false` et `uncQualification=false`
restent obligatoires. Il n’y a pas de partage UNC de boucle locale dans C6. L’UAC avec autre compte,
une vraie configuration utilisateur, les permissions Program Files, le transport SMB et le canari AD
restent des qualifications séparées.

## Verdict

Reporter exactement les lignes exécutées et leur preuve dans le rapport courant. Tout essai impossible faute de VM, de réseau ou de droit reste **non qualifié**, avec la cause observée. Une compilation, un smoke démo ou un booléen de test ne qualifie pas le canari AD ou le remplacement natif.

**Qualification du Socle hors CI.** Le démarrage sur le Socle sans Evergreen n’est pas qualifié en CI (le runner dispose d’Evergreen). Il est qualifié par la recette sur banc : VM recréée, Evergreen désinstallé, message clair avec lien `https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42`, extraction du Socle dans `wad\`, vérification de l’inventaire (257 fichiers, tailles, empreinte de l’exécutable contre l’index embarqué `vendor/socle/webview2-156.0.4314.42.files.json`, SHA-256 `a846d3785426fabe872f7e53188e3ba998d4a0ebde34f6af66ac4fe04acf77d3`), puis démarrage. Une copie altérée ou incomplète est refusée (`package.socle`). La recopie du Socle à la mise à jour et au retour arrière est couverte par les tests Engine sur le runner. Les preuves natives indiquent `runtimeMode` (`evergreen`) et `runtimeSource` (`evergreen` ou `socle`).

## Transfert local entre jobs sur le runner labo

Depuis le 8 novembre 2026, le dépôt est public et aucun runner auto-hébergé n’y est enregistré : le workflow n’admet que `windows-2025`, et ce transfert n’est plus utilisé. Cette section décrit l’historique.

Une publication explicite depuis `master`, sélectionnant `pesto-lab` (portable) ou `pesto-ci` (VM CI), peut transférer les ZIP et les preuves sur le disque du même runner. Les deux jobs restent séparés : `publish-release` dépend de la réussite complète de `windows-critical`. Le programme de publication vérifie toujours ce succès via l’API GitHub, le commit de `master`, les preuves SDK et les identités des ZIP avant de créer la release. Il ne reconstruit pas les fichiers testés.

Après tous les contrôles, le lot est copié dans un dossier propre au commit, à l’exécution et à sa tentative, hors du checkout et du répertoire temporaire nettoyé par le runner. Un manifeste scellé décrit chaque fichier. Son SHA-256 passe par une sortie du job GitHub ; le second job exige ce digest indépendant du disque, contrôle l’identité, les fichiers absents ou supplémentaires, les liens et les empreintes, puis copie vers un nouveau dossier de publication. Une autre tentative ou un autre runner est refusé. La preuve `lab-transfer-receipt.json` est ajoutée au rapport publié, sans annoncer de qualification supplémentaire.

Ce mode remplace seulement le transport `upload-artifact` / `download-artifact` pour les publications du labo. Les campagnes hébergées par GitHub et les candidats gardent le transport habituel. Aucune garde de test, délai, preuve métier ou vérification des quatre assets publiés n’est retirée. En cas d’échec, les lots incomplets restent inspectables et ne sont pas consommés ; les preuves d’un échec de test restent récupérables depuis le portable. Une nouvelle tentative complète est nécessaire : les preuves d’une ancienne tentative ne sont pas réétiquetées.

Contrôle préalable du 1er novembre 2026 : 54 cas synthétiques du transfert et 50 cas synthétiques de publication réussis sur Windows avec Node 24.22.0, dont l’écriture réelle de `GITHUB_OUTPUT` par la commande Windows. Les empreintes des quatre fichiers exécutés concordent avec les sources locales ([preuve](evidence/20261101/lab-handoff/verification.json)). Ces essais ne sont pas une campagne produit et ne qualifient pas l’AD.

Le runner dédié utilise le nom et le label métier `pesto-ci`. Le portable conserve `pesto-lab`. Le premier job vérifie l’identité du runner choisi avant la compilation, et le second vérifie cette même identité à la restauration. Un runner qui porterait le label de l’autre ne peut pas publier son lot.

Avant de rendre un runner disponible, vérifier les jobs en file pour son label. Un dispatch avec `publish_release: true` sur `master` enchaîne automatiquement les deux jobs et publie les quatre fichiers (`Pesto_V2_PRODLIGHT_<version>.zip`, preuves Windows, `release-manifest.json`, `SHA256SUMS`) si toutes les vérifications réussissent. Un dispatch avec `publish_release: false` fabrique des candidats et n’exécute pas le job de publication.
