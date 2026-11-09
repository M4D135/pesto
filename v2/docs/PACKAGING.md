# Packs Pesto V2 — LIGHT

## Édition à partir de 2.0.10

Un seul pack est publié : **LIGHT**.

| Poste Windows | Fichier de release |
|---|---|
| Microsoft WebView2 Runtime Evergreen installé (recommandé) | `Pesto_V2_PRODLIGHT_<version>.zip` |
| Evergreen absent — extraction du Socle WebView2 dans `wad\` | même ZIP |

Le ZIP contient `Pesto.exe` (self-contained .NET, single-file, Windows x64), `wad\` (web, module Active Directory, guides, support) et le manifeste. Il ne contient **aucun** runtime WebView2. Son manifeste porte `webview2Runtime: "evergreen"` et aucun `webview2Version`.

Le pack DEV (sources, outillage de refabrication) est LIGHT aussi. Il est qualifié en CI mais **jamais publié**.

Il n’existe plus de pack PROD avec WebView2 intégré, ni d’édition « PROD-LIGHT » distincte. Le ZIP `Pesto_V2_PRODLIGHT_<version>.zip` se télécharge à part depuis la release, puis se choisit dans Paramètres : Pesto n’interroge pas GitHub. Les sources, tests et outils se téléchargent au tag GitHub de la release.

Les sections de qualification et de fabrication ci-dessous documentent également les éditions antérieures. Le dernier pack DEV publié est celui de 2.0.9.

## État de livraison

Les compilations ordinaires préparent des **candidats V2**. La publication officielle est un lancement
manuel distinct depuis `master`, lié à un commit exact et précédé des contrôles Windows sur les archives
qui seront livrées. Un assemblage ou une publication officielle ne constitue pas une qualification AD :
le manifeste conserve `qualification=unqualified`. Les preuves historiques ci-dessous restent liées à
leurs propres sources et archives ; elles ne qualifient pas une nouvelle version par héritage.

**Release officielle 2.0.0 : [v2.0.0](https://github.com/M4D135/pesto/releases/tag/v2.0.0), source `84d76fc022eb11172021447672cfde5381a2d4ea`, [campagne 40720801680](https://github.com/M4D135/pesto/actions/runs/40720801680).** Les ZIP PROD/DEV publiés sont les octets testés sous Windows (617 tests moteur, configuration 36/36 par canal, installation depuis les boutons, refabrication DEV, mises à jour PROD en place depuis `de527313`) et ont été revérifiés après téléchargement. Une installation DEV de `de527313` passe à 2.0.0 par **nouvelle installation** (refus explicite qualifié). Statuts : `official=true`, `distribution=official`, `qualification=unqualified` — **AD, UAC réel, UNC et retour depuis les boutons UI non qualifiés**. Détails et empreintes : [rapport de release](RELEASE-v2.0.0.md).

**Historique C18 (dernier candidat avant la release) : `2adf60e15f8f7d5fd808c0471a63e1fd4457cd90`, [campagne 40675773761](https://github.com/M4D135/pesto/actions/runs/40675773761).** Les [preuves C18](evidence/20261028/windows-2adf60e/README.md) rattachent les 25 étapes réussies, 616 tests moteur, 250 gardes de restauration et 16 suites navigateur aux packs exacts PROD/DEV. Installation depuis les boutons, retour séparé par le service et reconstruction depuis les sources DEV avec SDK 10.0.302 réussissent. Les trois archives ont été téléchargées et leurs empreintes vérifiées ; les deux packs passent aussi `make-pack --verify` localement. Le [rapport C18](VALIDATION-C18-20261028.md) conserve l’échec initial `07dc741` et le correctif du banc. AD, UAC et UNC réels, profil ordinaire et retour depuis les boutons UI ne sont pas qualifiés par cette CI ; les preuves du harnais de domaine ne se transmettent pas aux ZIP.

**Historique C17 : `e087bb16aed175bc35906fa533e9cd172d2fdaca`, [40513849690](https://github.com/M4D135/pesto/actions/runs/40513849690).** Les [preuves relues le 28 octobre](evidence/20261028/windows-e087bb1/README.md) confirment l’installation depuis les boutons en PROD et DEV, le retour séparé par le service, la recompilation depuis les sources du DEV livré avec cache NuGet neuf et SDK 10.0.302, puis le démarrage natif du résultat. Le [rapport C17](VALIDATION-C17-20261027.md) distingue ces acquis du retour par bouton UI, de l’AD, de l’UAC, de l’UNC réels et du profil ordinaire non qualifiés par cette campagne. Chaque preuve reste attachée à ce commit et à ses empreintes.

Artefacts historiques C18 : [PROD](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12811723136), [DEV](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12812691213), [preuves](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12812880598), disponibles jusqu’au **27 novembre 2026**. Les [empreintes des enveloppes et ZIP intérieurs](evidence/20261028/windows-2adf60e/download-verification.json) sont vérifiées après téléchargement. Les manifestes et EXE sont liés à la source exacte ; les statuts restent `official=false`, `distribution=candidate`, `qualification=unqualified`. La reconstruction depuis DEV utilise son SDK 10.0.302 et un cache neuf ; elle est suivie d’un démarrage natif du PROD reconstruit, identifié par sa propre empreinte.

Artefacts historiques C17 : [PROD](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739549113), [DEV](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739569321), [preuves](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739149591), disponibles jusqu’au 26 novembre 2026. Les statuts restent `official=false`, `distribution=candidate`, `qualification=unqualified`.

**Historique C16 du 27 octobre 2026 :** le candidat était `3a8c49d85d5cc16dcab2d7c743be7fa445d05715`. Sa [campagne Windows `40491875705`](https://github.com/M4D135/pesto/actions/runs/40491875705) a passé les **36 contrôles natifs de configuration par canal**, dont les deux sélections positives de dossiers et les boutons de création du pack et de préparation d’une mise à jour. La campagne complète et les quatre scénarios de transactions natives entre builds distincts sont réussis ; les candidats sont publiés. Les [preuves finales](evidence/20261027/windows-3a8c49d/README.md) recoupent leurs sources, ZIP, EXE et configurations sentinelles. Le [rapport C16](VALIDATION-C16-20261027.md) décrit les corrections et les preuves.

Artefacts C16 : [PROD](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12730361970), [DEV](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729157837) et [preuves Windows](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729422738), conservés jusqu’au **26 novembre 2026**. Les packs restent `official=false`, `distribution=candidate`, `qualification=unqualified`. AD réel, UNC réel, UAC réel, Program Files et acquisition depuis une release officielle restent des qualifications distinctes.

Les [deux](evidence/20261027/windows-d803d72-failed/README.md) [premières campagnes](evidence/20261027/windows-1dbdda1-failed/README.md) ont révélé successivement un chemin retourné refusé par la garde de portée, puis un filtre de contrôle de dossier incomplet. La cause exacte du premier écart reste inconnue faute de chemin retourné enregistré ; la synchronisation de la saisie fait partie du correctif ensuite validé. Leurs échecs restent conservés ; aucun candidat n’a été publié par ces tentatives. Les preuves antérieures C15 conservent leur [identité historique](evidence/20261027/windows-b875174/README.md).

Les contrôles portables historiques C16 de fabrication réussissent **46/46**, avec le vrai EXE publié depuis Linux et un runtime synthétique. Le même PROD est réassemblé depuis l’arbre DEV livré avec les mêmes entrées EXE/runtime ; ce contrôle ne recompile pas l’EXE depuis DEV. Le parcours natif de maintenance annule la confirmation d’installation : une installation effectivement confirmée depuis ce bouton reste hors de ce banc.

**Historique C14 du 26 octobre :** le pack PROD GitHub exact de `e5a6722` passe accueil, saisie native AD synthétique, démonstration et configuration, puis une élévation UAC réelle depuis un parent non élevé, en session console 1. Les cinq parcours terminent avec code 0, sans accès au profil ordinaire ni appel AD. La [synthèse C14](evidence/20261026/windows-e5a6722/README.md) et le [rapport C14](VALIDATION-C14-20261026.md) conservent cette preuve et les essais AD distincts réalisés avec les harnais locaux. Ces résultats, comme ceux des campagnes C9 et antérieures, restent attachés à leurs propres binaires ; ils ne qualifient pas les nouveaux ZIP C18 pour l’AD ou l’UAC réel.

## Structure autonome

Chaque dossier PROD ou DEV contient exactement deux entrées à sa racine :

```text
Pesto.exe
wad/
  Pesto.package.json
  SHA256SUMS
  web/
  runtime/activedirectory/      # six fichiers Microsoft épinglés, dont ActiveDirectory.psd1
  support/DEBLOQUER_TOUT.cmd
  docs/
  dev/                         # sources et dépendances vendored, DEV seulement
  defaults/configuration.json  # distribution personnalisée seulement
```

`Pesto.exe` est publié en **.NET self-contained, single-file, Windows x64**, bibliothèques natives incluses.
Le poste n’a pas besoin d’installer .NET.

### Choix du moteur WebView2 au démarrage

Un seul moteur est sélectionné par processus, dans cet ordre :

1. **WebView2 Evergreen** installé sur le poste ;
2. sinon `wad\runtime\webview2\msedgewebview2.exe`, c’est-à-dire le pack WebView2 du Socle extrait dans `wad\`. Au démarrage, Pesto vérifie rapidement son inventaire (fichiers attendus, tailles, empreinte de l’exécutable) contre l’index embarqué ;
3. sinon un message clair en français, avec le lien `https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42`.

Les preuves natives indiquent `runtimeMode` (`evergreen`) et `runtimeSource` (`evergreen` ou `socle`).

### Le Socle WebView2

- Version fixe Microsoft **156.0.4314.42**, publiée une fois dans le dépôt **privé** `M4D135/socle-windows`, release `webview2-156.0.4314.42`. Il faut un accès à ce dépôt pour la télécharger.
- On extrait son ZIP dans `wad\`, ce qui crée `wad\runtime\webview2\` (257 fichiers).
- L’arbre doit correspondre **exactement** à l’index publié, embarqué dans Pesto (`vendor/socle/webview2-156.0.4314.42.files.json`, SHA-256 `a846d3785426fabe872f7e53188e3ba998d4a0ebde34f6af66ac4fe04acf77d3`). Un fichier modifié, en trop ou manquant, ou un dossier vide, est refusé (`package.socle`).
- Le Socle reste **hors de l’identité du pack** : il n’entre ni dans `wad\SHA256SUMS`, ni dans l’empreinte, ni dans le nombre de fichiers.
- À partir de cette version, la mise à jour et le retour arrière recopient le Socle de l’installation, à l’identique, vers la nouvelle version.
- On ne l’extrait que si Evergreen manque. Sinon, il est inutile, car Evergreen passe en premier.

### Migration depuis 2.0.9 PROD (ancien pack avec WebView2 intégré)

- Pas de mise à jour en place : le code 2.0.9 refuse un pack evergreen.
- Installer le pack LIGHT dans un **nouveau dossier**.
- Si Evergreen manque, extraire le Socle dans `wad\`, ou recopier le `wad\runtime\webview2` de l’ancienne installation, à condition qu’il soit identique au Socle (sinon Pesto le refuse).
- La configuration du profil de l’opérateur n’est pas dans le pack et n’est pas touchée.

Le module Microsoft ActiveDirectory déjà livré avec V1 est inclus sous `wad/runtime/activedirectory/` :
son manifeste, la DLL de gestion, les fichiers de types et formats, la DLL de ressources et sa ressource
`fr-FR`, soit **six fichiers aux SHA-256 épinglés**. Aucun `cfg.json` V1 n’est copié. La résolution native
préfère ce bundle depuis le dossier de `Pesto.exe`, indépendamment du profil AppData ; elle contrôle les
six empreintes avant tout import. Un bundle présent mais incomplet ou altéré est refusé sans repli.
Les emplacements V1 puis le module système protégé restent des solutions de compatibilité en dehors
d’un pack autonome ; `PSModulePath` n’est jamais utilisé pour choisir un module. Le pack ne nécessite
donc pas d’installation RSAT pour fournir ces composants, et conserve Windows PowerShell 5.1.
L’assemblage et la validation des mises à jour exigent ces mêmes six fichiers, même si `SHA256SUMS`
a été recalculé. La démo et les contrôles de santé ne chargent pas le module et ne contactent pas AD.

`DEBLOQUER_TOUT.cmd` est conservé en PROD et DEV sous `wad/support`. Il remonte de deux niveaux pour
retirer la marque de téléchargement des fichiers de **tout le dossier de l’application**. Il n’est pas
une dépendance obligatoire au démarrage.

Le dossier DEV inclut `wad/dev/src`, `tests`, `tools`, `web`, `docs`, le README, les propriétés de build, `global.json`,
`NuGet.config` et `vendor/nuget`. Les sources des guides sont nécessaires à la refabrication du pack depuis DEV. Les sorties `bin/obj`, caches, journaux et configurations privées sont
exclues. Recompiler demande le SDK .NET déclaré et les packs de ciblage Windows ; exécuter le pack ne
les demande pas.

### Archives de preuves

La fabrication omet uniquement le sous-arbre `docs/evidence/` dans les documents `wad/docs/`
et les sources `wad/dev/docs/`. Ces archives historiques restent dans GitHub. Certains de leurs
chemins imbriqués dépassent la limite de l’extraction Windows PowerShell 5.1 une fois placés dans
le dossier temporaire du banc : un chemin de 276 caractères a provoqué l’échec du 1er novembre.
Les autres guides restent livrés ; leurs sources DEV sont conservées octet par octet pour la
refabrication. Les liens des guides opérateur vers les archives omises pointent vers GitHub au
commit fourni par `--source-commit`, y compris les rapports Markdown et les fichiers `.json.txt`.
Les règles de validation des packs existants restent inchangées : cette omission concerne
la fabrication des nouveaux packs, sans rendre incompatibles les anciennes distributions.

### Contrat de mise à jour DEV depuis `de527313` : nouvelle installation

Depuis l’identité visuelle unifiée, le pack DEV contient six sources exactes hors des extensions source
génériques : `src/Pesto.App/Assets/Pesto.ico`, `src/Pesto.App/Assets/pesto-master.png`,
`web/assets/pesto.png`, `web/assets/pesto-favicon.png`, `tools/check-ui-kit.py` et
`tools/m4d-components/components.py` (sous `wad/dev/`, liste `UpdatePackage.DevExactSourcePaths`). Un
programme installé valide un pack avec ses propres règles compilées : celles de `de527313` ne connaissent
ni PNG/ICO ni Python sous `wad/dev/`. D’après son code, son inspection (`InspectLocal`, même
validateur) refuse donc le pack DEV actuel (« Fichier hors du contenu autorisé : … ») ; sous Windows, son
helper a effectivement affiché ce refus avant toute étape de transaction (run 40701751220). Le programme,
le runtime et la configuration du profil restent inchangés. Aucun nouveau programme ne
peut modifier un validateur déjà compilé, et déguiser ces fichiers dans un format admis contournerait le
contrôle au lieu de le respecter.

Une installation DEV de `de527313` passe donc à cette version par une **nouvelle installation** :
décompresser `Pesto_V2_DEV_<version>.zip` dans un nouveau dossier. La configuration appartient au profil
de l’opérateur et n’est pas dans le pack. PROD ne contient aucun de ces fichiers et se met à jour en
place. Les installations DEV qui embarquent déjà ces sources se mettent de nouveau à jour en place.
Le banc C6 qualifie ce refus explicitement (scénario `format-refusal`) ; la release l’annonce et le
manifeste porte `newInstallationRequiredFromBaseline: true` pour DEV.

`wad/docs/README.md` ouvre la documentation livrée : configuration, référentiels, parité, validation,
pont et qualification Windows, ainsi qu’un guide de prise en main. Les liens entre documents livrés sont adaptés à l’arborescence du pack ; les liens vers les archives de preuves exclues pointent vers GitHub au commit fourni par `--source-commit`. Sans cet argument, ils pointent vers la branche V2. Les anciens rapports
restent marqués historiques ; ils ne qualifient pas le binaire candidat courant.

## Manifeste et intégrité

Le format de pack est versionné : `schemaVersion: 2`, `layout: "singlefile-wad"`,
`repository: "M4D135/pesto"`, `entryPoint: "Pesto.exe"`, `channel: "PROD"` ou `"DEV"`.
`wad/SHA256SUMS` couvre exactement tous les fichiers, avec des chemins relatifs à la racine du pack ;
seul le fichier SHA256SUMS lui-même est exclu.

La vérification refuse les fichiers hors du contenu autorisé, les chemins Windows ambigus, les noms
réservés, les doublons sans distinction de casse, les liens symboliques/jonctions, les empreintes
incorrectes et les exécutables qui ne sont pas PE32+ x64. Les archives ZIP sont inspectées **avant**
extraction et bornées en nombre d’entrées et en taille décompressée. Ni chemin absolu, ni `..`, ni ADS,
ni lien Unix de ZIP ne peut sortir du dossier de préparation.

Trois provenances sont distinguées :

| `distribution` | Sens |
|---|---|
| `candidate` | Assemblage de développement, non présenté comme release officielle. |
| `official` | Pack déclaré de release. L’acquisition depuis la release du dépôt officiel est vérifiée séparément. Un manifeste copié dans un ZIP local ne suffit pas à attester cette origine. |
| `custom` | Pack produit par « Définir comme configuration par défaut », contenant les seuls paramètres diffusables validés. `official` est toujours faux. |

Un pack personnalisé déclare également `configurationVersion` et `configurationFingerprint`, cohérents
avec son enveloppe `wad/defaults/configuration.json`. Le moteur valide le schéma fermé et les champs
configurables, recalcule l’empreinte et refuse secrets, sessions, historique, caches et champs inconnus.
L’application travaille ensuite avec le `cfg.json` du profil utilisateur, hors des fichiers du pack.

## Publication et assemblage

Passage à une nouvelle version, depuis la racine du dépôt : `python3 v2/tools/release/bump-version.py X.Y.Z` (`--dry-run` pour voir sans écrire).
Il met à jour `Directory.Build.props`, `app.manifest` et `pack-manifest.json`, puis épingle le banc d’installation du workflow
(`UI_UPDATE_FROM_*`) sur la release officielle courante : commit de son tag et empreintes PROD/DEV de son `SHA256SUMS`.
Il refuse une version non postérieure, une release ou une empreinte absente, sans rien écrire.

Depuis `v2/` :

```bash
dotnet publish src/Pesto.App/Pesto.App.csproj -c Release -r win-x64 \
  --self-contained true --disable-build-servers -m:1

node tools/pack/make-pack.mjs \
  --source src/Pesto.App/bin/Release/net10.0-windows/win-x64/publish \
  --dest /chemin/nouveau/PROD \
  --channel PROD

node tools/pack/make-pack.mjs \
  --source src/Pesto.App/bin/Release/net10.0-windows/win-x64/publish \
  --dest /chemin/nouveau/DEV \
  --channel DEV

node tools/pack/make-pack.mjs --verify /chemin/nouveau/PROD
node tools/pack/make-pack.mjs --verify /chemin/nouveau/DEV
```

Les options `--webview2`, `--webview2-version`, `--allow-missing-webview2` et `--evergreen` sont
supprimées ; les passer donne un échec explicite (code 2). `--verify` refuse tout
`wad/runtime/webview2/...` et tout `msedgewebview2.exe` dans un pack ; la sortie est `PACK VÉRIFIÉ`.
Le pack DEV livre l’index du Socle pour la refabrication, jamais le runtime.

`--source-commit <SHA40>` est disponible lorsque les sources compilées correspondent exactement à ce
commit. Ne pas attribuer le commit de base à un build contenant des modifications non commitées.
L’assemblage refuse une simple sortie `dotnet build` contenant `Pesto.dll` à côté de `Pesto.exe`.
Il copie l’arbre web source, vérifie l’ensemble dans un dossier temporaire, puis publie par renommage
vers une destination neuve. Il n’écrase jamais un dossier existant.

Un pack complet valide retourne **0** ; un pack invalide retourne **2**.
Le contrôle portable `node tools/tests/pack-check.mjs [dossier-publish]` utilise un runtime **factice**
explicitement marqué dans sa sortie et prouve la mécanique, pas le fonctionnement de WebView2.

Le workflow `.github/workflows/pesto-v2.yml` construit `master` et la branche V2, et assemble les deux packs LIGHT.
Le banc de configuration native passe ensuite avant les suites complètes du moteur et du pont,
les seize suites JavaScript/navigateur, la mécanique de fabrication et les autres bancs natifs. Tous ces contrôles et les transactions
de mise à jour restent exigés avant publication des candidats. Le CAB Microsoft Fixed Version **156.0.4314.42**, épinglé par URL et SHA-256
`cb4612ce79a62a0be094301a72f73cf91bb250f5e83dc51886f66a083fc0694f`, n’est plus téléchargé que pour vérifier que l’index du Socle
correspond exactement au runtime Microsoft (`socle-match.json`) ; il ne remplit aucun pack. Le job conserve les preuves
et les deux archives comme artefacts pendant trente jours. Un push, une pull request ou un lancement manuel
avec `publish_release=false` reste un contrôle candidat et ne crée aucune release.

### Publication officielle explicite

Le lancement manuel du même workflow depuis `master` accepte `publish_release=true` et exige
`expected_source_sha=<SHA40 complet de master>`. Toute autre branche ou divergence de commit est refusée.
Le pack est alors assemblé directement avec `--distribution official`, avant les contrôles Windows ;
`--source-commit` est obligatoire.
La distribution officielle indique le canal de publication, sans transformer une recette AD absente en réussite.

Après la réussite du job `windows-critical`, le job `publish-release` télécharge les artefacts de cette
même exécution. Il vérifie le commit, le numéro d’exécution et de tentative, le SDK exact, les résultats
Windows déclarés et les SHA-256 des ZIP. Il réserve le tag `v<version du pack>` sur ce commit, crée une
release brouillon, puis téléverse le ZIP `Pesto_V2_PRODLIGHT_<version>.zip` inchangé, l’archive des preuves,
`release-manifest.json` et `SHA256SUMS`. Avant 2.0.10, les noms livrés étaient `Pesto_V2_PROD_<version>.zip`
et `Pesto_V2_DEV_<version>.zip`.
Les tailles et empreintes renvoyées par GitHub doivent correspondre pour les quatre fichiers ; le tag et
`master` sont relus avant de rendre la release visible. Aucun binaire n’est reconstruit après les tests.

Un tag ou une release préexistants sont refusés, sans remplacement. Une panne après réservation conserve
le tag et le brouillon éventuel pour inspection manuelle ; un nouvel essai ne les efface pas. Les notes
de release annoncent explicitement la qualification AD restante. La publication ne nécessite aucun accès
à la VM de laboratoire. Pour une version ultérieure, augmenter la version dans `tools/pack/pack-manifest.json`
avant de lancer une nouvelle campagne sur son commit exact.

Pour le banc C6, chaque exécution reconstruit aussi la baseline **A** depuis les sources épinglées au
commit `de527313b98f30d52802ec6abd51804e12f8c298`, avec le SDK de CI et le même runtime fixe. Ses packs
sont assemblés avec le script et l’interface de ce commit. **B** est la nouvelle compilation du commit
de la campagne. Le banc exige des commits sources et des SHA-256 de `Pesto.exe` distincts ; il consigne
les empreintes réellement produites, sans supposer qu’une recompilation de A reproduit le binaire
archivé lors de C5. Il ne dépend pas de la disponibilité des anciens artefacts GitHub.

Les ZIP B de PROD et DEV sont créés avant le banc, inspectés par le vrai service de mises à jour et
conservés sans réécriture jusqu’à leur archivage. Le scénario normal refuse un ZIP absent ou dont le
pack diffère du dossier B validé ; il ne se rabat jamais sur une autre source. Le manifeste et la version
réelle restent intacts. Deux compilations de même version sont admises si leurs identités diffèrent.

`Pesto.exe --qualify-demo <nouveau-sous-dossier-de-Temp>` est le point d’entrée du smoke Windows : il
vérifie le pack, charge la vraie interface WebView2 sur profil éphémère, vérifie les refus d’API réelles
en démo, attend la fermeture normale et la disparition des processus du runtime, puis écrit
`proof.json`. Le rapport distingue expressément démarrage/démo de la qualification AD et de la mise à
jour native, qui restent fausses dans cette preuve. Le workflow refuse le succès si cette preuve est
absente ou incomplète. Il n’exécute aucun adaptateur AD réel.
L’extension C6 ouvre également la démo depuis l’interface d’un parent en **configuration locale**, sur
des profils temporaires dédiés, sans adaptateur AD. Elle contrôle le brouillon non enregistré, la route
et les préférences du parent, les profils distincts, la bannière permanente, les scénarios, la remise à
zéro, les identifiants distincts et le redémarrage fictif. Elle ferme ensuite le parent avec un enfant
ouvert. Ce parcours a réussi en PROD et DEV sur `3a8c49d` lors de C16.
La preuve porte sur le parent en configuration locale et les profils temporaires du banc ; elle ne
qualifie pas une session AD connectée ni le contexte de l’opérateur réel. Les captures et le résultat
sont conservés sous `coexistence/` et dans le champ `coexistence` de `proof.json`.
Les contrôles santé et démo n’ouvrent pas de dialogue d’erreur modal. Après validation d’une destination
de preuve, un échec produit `success: false` et un `failureCode`, avec un code de sortie non nul ; une
demande malformée est refusée avant toute écriture. Une erreur d’interface ne peut donc pas devenir un
succès de qualification ou attendre indéfiniment un clic dans une fenêtre masquée.

## Mises à jour depuis l’application

Le parcours est séparé en quatre actions : **Choisir → Aperçu → Préparer → Installer après
confirmation**. Ni l’aperçu ni la préparation ne remplacent les fichiers installés.

Depuis la 2.0.10 (décision du 08/11/2026), Pesto ne contacte aucun serveur pour ses mises à jour : ni
recherche de release, ni téléchargement. Le ZIP de la release se récupère à part, puis se choisit ici.
Un pack avec WebView2 intégré (`fixed`) est refusé (`package.edition`), avec le conseil d’installer le
LIGHT dans un nouveau dossier.
- **Dossier local ou partage UNC** : inspection du pack choisi et de ses sommes, aperçu de la version,
  du canal et du type de distribution. L’origine officielle n’est pas déduite du nom du fichier.
- **ZIP local** : extraction contrôlée dans une préparation distincte. L’archive peut contenir le pack
  directement ou dans un unique dossier racine.

Le pack choisi est copié dans une préparation isolée, relu et comparé aux empreintes de l’aperçu.
La comparaison porte sur le dossier entièrement copié, avant son admission : un remplacement concurrent
cohérent de la source, même à version identique, est refusé. Seule la nouvelle copie est nettoyée ; la
source modifiée est préservée. La création d’un pack personnalisé applique le même contrôle avant de
modifier les paramètres distribués et le manifeste.
Le pack courant est également contrôlé : un changement concurrent fait échouer l’installation sans
écraser ces modifications. Un pack identique est signalé ; un pack plus ancien nécessite le retour
transactionnel de la sauvegarde, et non un déclassement implicite.

## Installation, santé, rollback et interruption

La confirmation crée un journal durable et une copie de **`Pesto.exe` de l’installation actuelle** dans un dossier de
transaction voisin de l’installation :
`<parent>/.pesto-v2-update-<identité-installation>/<transaction>/helper/Pesto.exe`.
La copie attend l’arrêt du processus parent, lié à son PID **et** son heure de création, puis prend un
verrou exclusif par installation. L’hôte contrôle aussi l’extinction des processus du pack avant le
remplacement. Aucun processus Windows étranger n’est arrêté pour forcer le passage.

Depuis 2.0.4, avant l’installation, le retour ou la reprise demandés depuis la page Maintenance,
Pesto liste les autres `Pesto.exe` lancés depuis ce pack et les nomme dans la confirmation. Avec
l’accord explicite, il demande leur fermeture comme leur propre bouton de fermeture : une opération
en cours s’y termine et enregistre son reçu d’abord. Rien n’est forcé ni tué. Une fenêtre d’une autre
session Windows, sans fenêtre (ligne de commande), tenue par une boîte de dialogue Windows (2.0.5) ou
impossible à inspecter est désignée et bloque l’action. Si une boîte de dialogue s’ouvre après la
confirmation, la demande est renouvelée jusqu’à sa fermeture, et le refus éventuel distingue les fenêtres
qui ont reçu la demande de celles qui n’ont pas pu la recevoir. Si la liste a changé depuis la confirmation, ou si une fenêtre reste ouverte après 30 s, Pesto
refuse avant de créer la transaction : aucun fichier n’est remplacé et aucune reprise n’est laissée en
attente.

Le journal est écrit avec vidage disque avant chaque étape significative : sauvegarde du pack actuel,
placement du nouveau pack, contrôle de santé, résultat. Les dossiers `stage`, `backup` et
`failed-candidate` restent sur le même volume. L’ancienne installation est conservée avant que la
nouvelle prenne sa place.

Le contrôle de santé lance le candidat dans un profil temporaire, sans configuration utilisateur,
sans accès AD et sans application des paramètres distribués. Sa preuve doit relier transaction,
nonce aléatoire, version, SHA-256 de `Pesto.exe`, chargement effectif de WebView2 (avec `runtimeMode`
et `runtimeSource`), et fermeture normale.
Un simple code de sortie ou un booléen ne suffit pas à annoncer le succès.

Chaque tentative possède désormais son reçu durable dans
`<transaction>/health-attempts/<nonce>.json`. L’intention `started` est vidée sur disque avant de lancer
la sonde ; le résultat `passed` ou `failed`, sa corrélation transaction/version/empreinte et la preuve
native disponible sont enregistrés avant la tentative suivante. Le refus du candidat reste donc
relisible après une santé réussie de l’ancien pack. Une reprise classe un essai inachevé `interrupted`
et conserve sa preuve éventuelle avec `accepted: false`, même si cette preuve annonçait un succès.
Les reçus ont un schéma fermé, des chemins dérivés du nonce et les mêmes refus de liens que le journal.
`UpdateTransaction.ReadHealthAttempts` les relit et les valide ; une erreur d’écriture ou un reçu
incohérent ne donne jamais un succès de mise à jour.

Une santé non confirmée déclenche la restauration binaire, suivie du contrôle de santé de l’ancien
pack. Si cette seconde santé échoue, le résultat reste **non confirmé**, même si les fichiers ont été
rétablis. Aucun ancien résultat AD n’est rejoué. Aucun paramètre du profil utilisateur n’est remplacé.

Le bouton de retour permet de rétablir explicitement la sauvegarde de la dernière installation.
Après une interruption, la reprise restaure l’état initial à partir des dossiers et du journal relus ;
elle ne relance pas une opération métier. Les frontières de renommage des dossiers sont traitées même
si le processus s’est arrêté entre le renommage et l’écriture du statut suivant. Une préparation
interrompue avant tout remplacement peut être annulée sans toucher à l’installation.

Si une coupure est survenue alors que le dossier d’installation était momentanément absent, la copie
isolée est conservée. Un double-clic sur `<transaction>\helper\Pesto.exe` ouvre la reprise après
confirmation. Depuis un terminal autorisé, reprendre avec :

```powershell
& '<transaction>\helper\Pesto.exe' --update-helper '<transaction>'
```

Le journal valide le chemin d’installation, l’identifiant de transaction, la copie helper et les
empreintes avant toute action. Les dossiers inattendus ou modifiés sont conservés et le refus est
motivé. Le contrôle de santé, le rollback et la reprise ne déclenchent jamais le remplacement d’une
configuration réelle.

## Qualification Windows native et limites

Les tests portables exercent la validation des packs, les refus en démo, les copies, les renommages,
les preuves de santé synthétiques, les verrous, les interruptions et les retours. Ils ne prouvent pas
l’arrêt des processus WebView2, le remplacement de fichiers chargés sur NTFS, l’élévation UAC, les ACL
Program Files, le comportement d’un partage SMB réel ni la santé GUI native. Ces essais critiques
restent identifiés dans la qualification Windows et doivent être liés au hash exact du pack testé.
La campagne native C18 sur `2adf60e` apporte les preuves de chargement/fermeture WebView2 et de remplacement des
packs sur les copies locales isolées décrites ci-dessous. Elle ne qualifie ni UAC réel, ni ACL
Program Files, ni partage SMB. L’installation confirmée depuis les boutons réussit dans un banc séparé PROD/DEV ; le retour par les boutons UI reste non qualifié.

Le banc C6 utilise deux packs complets du même canal sur des copies temporaires : **A → B → A**.
En PROD (LIGHT), il exige installation depuis le ZIP B puis retour explicite, santé négative puis restauration,
et interruption ciblée pendant le vrai contrôle WebView2 puis reprise. En DEV, il exige le scénario
normal depuis le ZIP B, comprenant le retour explicite, lorsque A connaît déjà les sources DEV exactes de B ;
sinon il exige le scénario `format-refusal` décrit ci-dessus (refus par le helper A, A intact, aucune
santé lancée). Le helper doit être le binaire A,
la santé du candidat celle de B et la santé du retour celle de A. Les deux cas de panne PROD altèrent
seulement la page de santé sur une copie de B, ajoutent une notice synthétique et retirent la déclaration
de source intacte ; le binaire, le runtime et la vraie version de B sont conservés. Aucune version
artificielle ne sert de preuve.

Le point d’entrée est `tools/qualification/Invoke-NativeUpdateQualification.ps1`, avec les arguments
obligatoires `-BasePack`, `-CandidatePack`, `-CandidateZip`, `-RunnerDll`, `-DotNet` et
`-ReportDirectory`. La [procédure Windows](QUALIFICATION-WINDOWS.md#banc-c6-entre-deux-compilations-sur-copies-isolées)
donne la commande, les conditions et les preuves attendues. Le rapport final au schéma 2 conserve les
deux commits et empreintes, le hash du ZIP, les reçus de santé et le hash du cfg sentinelle extérieur
aux packs. Il exige leur conservation ainsi que l’arrêt des processus associés.

Sur `2adf60e`, les trois cas PROD et le cas normal DEV sont réussis dans la [campagne C18](VALIDATION-C18-20261028.md). L’installation normale utilise
le vrai ZIP candidat ; les cas PROD de santé négative et d’interruption utilisent une copie locale
avec défaut synthétique, sans modifier le binaire ni sa version. La reprise après interruption aboutit
à `rolledBack`, avec santé de A prouvée ; elle ne constitue pas un succès d’installation de B. Les
sources et le cfg sentinelle sont conservés. Les échecs des premières campagnes C6, dont le refus
d’attribution de processus sur `19cabd1`, restent documentés dans le [rapport daté](VALIDATION-C6-20261026.md).

Le banc ne contacte ni AD, ni SMB, ni HTTP ; `uncQualification` et `adQualification` restent faux.
UAC avec un autre utilisateur, ACL Program Files, partage UNC réel, configuration utilisateur réelle
et canari AD restent des qualifications séparées.

### Qualification CI et recette sur banc (2.0.10)

- **CI Windows** (Evergreen installé sur le runner) : qualification native du pack LIGHT, avec `runtimeSource == 'evergreen'` ; le pack DEV est assemblé et vérifié ;
- mise à jour inter-builds depuis une base LIGHT reconstruite au commit `962f3ba` (2.0.10 ; `ef759f6a` jusqu’à la recréation du dépôt le 9 novembre 2026), puis interface de mise à jour depuis cette base ;
- sur le runner, une copie exacte du Socle est acceptée sans changer l’empreinte, et une copie altérée est refusée (`package.socle`). La recopie du Socle à la mise à jour et au retour arrière est couverte par les tests Engine sur le runner ;
- **non qualifié en CI** : le démarrage sur le Socle sans Evergreen. Il est qualifié par la recette sur banc (VM recréée, Evergreen désinstallé, message clair, extraction du Socle, démarrage) ;
- la mise à jour en place depuis 2.0.9 PROD n’est pas qualifiée, puisqu’elle est impossible par construction.
