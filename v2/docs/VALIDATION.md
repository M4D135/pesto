> **Rapport historique.** Pour le code de la reprise actuelle, voir [VALIDATION-REPRISE-20261025.md](VALIDATION-REPRISE-20261025.md), [PARITY.md](PARITY.md) et [EVIDENCE.md](EVIDENCE.md). Les résultats ci-dessous restent attachés aux anciens lots et binaires.

# Validation Pesto v2 — commandes et résultats effectifs

Toutes les commandes sont portables (Linux, SDK `/home/m4d135/.dotnet` 10.0.302). Elles ne constituent pas une
qualification Windows/AD : le build Windows (Pesto.App, WebView2) et la qualification réelle AD restent des portes
distinctes (docs/PARITY.md).

## Moteur et pont (vérifié le 23/10/2026, re-vérifié à chaque lot)

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `dotnet run --project tests/Pesto.Engine.Tests -c Release` | **60 réussis, 0 en échec, 60 au total — exit 0** | 23/10 20:13 UTC (47), re-vérifié 23/10 (GUI), 24/10 (GUI 2), 24/10 (GUI 3, `logs/engine-tests-gui3.log`), **24/10 (moteur live 1, 60, `logs/engine-tests-live1.log`)** |
| `dotnet run --project tests/Pesto.Bridge.Tests -c Release` | 4 réussis, 0 en échec, 4 au total — exit 0 | 23/10 20:13 UTC, re-vérifié 23/10 (GUI), 24/10 (GUI 2), 24/10 (GUI 3), 24/10 (moteur live 1, `logs/bridge-tests-live1.log`) |

Les pipelines de test préservent le vrai code de retour (`set -o pipefail`) ; `tail` n'est jamais pris pour preuve.
**Aucune option supplémentaire n'est placée après le nom de projet** sans séparateur `--` : le 24/10 (lot moteur live 1),
`dotnet run --project … --nologo -v q` a été reproduit comme passing les options au programme, le filtre du runner ne
matchait aucun test et le processus sortait 0 avec « 0 au total » (vert vide). Les deux runners (`TestRunner.cs` Engine
et Bridge) renvoient désormais **1** quand aucun test n'est sélectionné ; le comportement est vérifié (binaire lancé
directement avec un filtre sans correspondance → exit 1).

Couverture des tests Engine (60) : naming (pattern, bornes 15 caractères, refus), cycle de vie simulation
(join local uniquement, plan consommé une fois, expiration, collision après préparation sans rejeu automatique,
move sans renommage ni redémarrage, rename+move), file (ajout/doublons/lot/arrêt sur incertain), paramètres
(validation intégrale, invalidation des aperçus/plans, refus de changement de mode), honnêteté live (aucun fait
fictif, écritures refusées avec raison), intégration pont (schémas d'arguments, sérialisation des mutations),
**lectures live (13 tests, lot moteur live 1 — voir ci-dessous)**.

## Moteur live 1 — portage C# des lectures (24/10/2026)

Aucune mutation dans ce lot : les écritures restent refusées (`write.unavailable`). Le mode réel n'invente jamais un
poste, un site, un service, un nom ou un succès ; tout chemin non qualifié est refusé avec une raison exploitable.

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.Engine.Live/Pesto.Engine.Live.csproj -c Release` | **exit 0**, 0 warning, 0 erreur (projet d'adaptateur transitoire) | 24/10 (moteur live 1) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Engine.Tests -c Release` | **60/60 — exit 0** (`logs/engine-tests-live1.log`) | 24/10 (moteur live 1) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Bridge.Tests -c Release` | **4/4 — exit 0** (`logs/bridge-tests-live1.log`) | 24/10 (moteur live 1) |
| `node tools/tests/web-check.mjs` | **90/90 — exit 0** (`logs/web-check-live1.log`) — web inchangé, re-vérifié | 24/10 (moteur live 1) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.App/Pesto.App.csproj -c Release` | **exit 0**, 0 warning, 0 erreur ; `Pesto.Engine.Live.dll` (37 376 o) dans la sortie `win-x64` — `logs/build-live1.log` | 24/10 (moteur live 1) |

Composants portés et contrôlés par les 13 tests `LiveReadTests` + 2 tests `LiveHonestyTests` ajoutés :

- **`V1Config`** (lecteur cfg.json passé en paramètre, rien en dur) : refus `config.missing` (dossier absent, sans
  cfg.json, inconnu) ; refus `config.invalid` (fichier > 1 Mio, lien/reparse point, `Configured` faux, POLICY à schéma
  fermé violée, `MaxReaders` hors 1–8, `DEBUG.HorsDomaine` actif en réel, `NamingConvention` personnalisée non portée) ;
  **domaine unique** : un OU dont la partie DC diffère de `Domaine` est refusé ; `settings.get` rend des `null`
  honnêtes sans config, jamais un domaine d'exemple ; un cfg nommant `LABO.ENTREPRISE` commande intégralement la
  session (aucune valeur codée en dur).
- **`IDirectoryGateway`** (seam de lecture, moteur pur) : `PowerShellDirectoryGateway` (adaptateur transitoire PS 5.1,
  script constant en lecture seule, `-Server` explicite, `-ResultSetSize` borné, `-ResultPageSize 500`, échappement
  LDAP, reprise bornée sur panne réseau transitoire seulement, jamais de mot de passe ni d'invite) — **hors Windows,
  chaque lecture est refusée `directory.unavailable`, jamais simulée** (5 délégués testés).
- **`LiveBackend`** raccordé : `directory.sites` = sites déclarés ∩ OU réellement observés (jamais un OU deviné) ;
  `directory.services` = codes lus dans les noms conformes du site + `NameCatalogue`, **refus `directory.incomplete`
  si la lecture n'est pas complète** ; `directory.search` bornée (plafond dur 100, `complete:false` au-delà, champs
  non observés à `null`, jamais complétés) ; `computer.inspect` (nom validé avant requête, `computer.missing` sur
  absence, garde de périmètre `ok`/`warn` par comparaison de DN composant à composant) ; `names.preview` refusé
  `names.unavailable` à ce lot (qualifié depuis — voir section moteur live 2) ; écritures et `settings.save` refusées. 

Couverture des tests Bridge (4) : rejet d'opération inconnue, rejet de requête dupliquée, lectures concurrentes,
mutations sérialisées.

## Moteur live 2 — disponibilité de noms en mode réel (24/10/2026)

Aucune mutation dans ce lot : les écritures restent refusées (`write.unavailable`). Le nom réellement libre est
calculé **avant** l'activation du bouton d'ajout ; une lecture incomplète reste « inconnu » ; une réponse obsolète
est ignorée ; collision après préparation = nouvel aperçu + nouveau clic, jamais d'ajout automatique.

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Engine.Tests -c Release` | **70/70 — exit 0** (`logs/engine-tests-live2.log`) — 60 → 70, +9 `LiveReadTests` names.preview live + 1 `LiveHonestyTests` | 24/10 (moteur live 2) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Bridge.Tests -c Release` | **4/4 — exit 0** (`logs/bridge-tests-live2.log`) — re-vérifié | 24/10 (moteur live 2) |
| `node tools/tests/web-check.mjs` | **90/90 — exit 0** (`logs/web-check-live2.log`) — simulation inchangée, re-vérifiée | 24/10 (moteur live 2) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.Engine.Live/Pesto.Engine.Live.csproj -c Release` | **exit 0**, 0 warning, 0 erreur | 24/10 (moteur live 2) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.App/Pesto.App.csproj -c Release` | **exit 0**, 0 warning, 0 erreur ; `web/js/pages/ajouter.js` et `unposte.js` modifiés recopiés dans la sortie `win-x64` (vérifié par lecture de la sortie) — `logs/build-live2.log` | 24/10 (moteur live 2) |

Comportement `names.preview` live (port de `Get-PestoJoinNameCandidates` / `Select-PestoJoinNextName` v1) et ses
contrôles :

- **Aucun nom sans lecture complète** : `ListComputerNames` sur l'OU réellement observée du site, plafond dur 20 000 ;
  `Complete:false` → refus `names.unavailable` (« le nom réellement libre reste inconnu »), jamais une liste partielle.
- **Périmètre** : site = déclaré ∩ observé, OU sous la racine gérée configurée (`WithinScope`), sinon refus motivé ;
  hors P/S/V → `type.invalid` ; service hors `[A-Z0-9]{3}` → `service.invalid` ; nom de poste validé avant requête ;
  poste absent → `computer.missing` ; panne adaptateur → `directory.unavailable` remonté, jamais masqué.
- **Sélection** : candidats `{type}{prefix}{site}{service}{number:3}` numéros 1..999, exclusions = noms réellement
  observés dans la portée ∪ noms confirmés pris dans la session (port `PestoTakenNames`) ; `RandomNameEnabled` lu du
  cfg commande tirage au hasard ou premier libre ; `alternative` ne répète jamais la dernière proposition ; série
  entièrement prise → `names.exhausted`.
- **Revérification compte par compte** : chaque candidat proposé est revérifié `FindComputer` (port de la revérification
  v1 avant `Add-Computer`) ; un candidat réellement présent est écarté, mémorisé pris pour la session et ne revient
  jamais en course ; au plus 5 bascules d'affilée (port v1), puis `names.unavailable` qui renvoie vers Noms
  disponibles — **jamais d'ajout automatique**.
- **Aperçu horodaté et obsolétisable** : `previewId` unique, `collectedAt`/`expiresAt` (5 min), `source` = « annuaire
  réel · description de l'adaptateur » — un aperçu live ne provient jamais de la simulation (test dédié) ; le
  recalcul pour la même clé rend l'aperçu précédent non consommable (base de `plan.stale` pour le lot mutations).
- **Renommage** : même site = OU réellement observée conservée (jamais ramenée à la racine du site) ; OU non observée
  → `names.unavailable`, aucun OU supposé ; changement de site = OU observée du site cible.
- **GUI** : `ajouter.js` garde un jeton de calcul — une réponse plus lente qu'une autre est ignorée (réponse obsolète
  jamais peinte), bouton « Autre nom » branché sur `alternative` ; `unposte.js` : même garde de jeton pour l'aperçu
  de renommage. Le bouton « Ajouter » reste désactivé tant qu'aucun aperçu `complete:true` n'a été renvoyé.

Limites : disponibilité calculée depuis la portée du site (l'inventaire de tous les noms du domaine reste la page
Noms disponibles) ; la qualification de ces lectures sur un AD réel reste à faire hors job (fixture = preuve
portable).

## Moteur live 3 — préparation des plans et pipeline d'envoi du harnais (24/10/2026)

Aucune mutation réelle dans ce lot : **aucune implémentation de `IMutationGateway` n'est exécutée depuis ce job**,
l'hôte n'en injecte jamais (`Program.cs` → `CreateLive(v1Root, gateway)`), les capacités join/rename/move/renameMove/queue
restent désactivées et `operation.execute` refuse par `write.unavailable` pour tout le monde. La préparation est une
planification sans écriture ; le pipeline d'envoi n'est atteignable que par la surcharge de harnais
`CreateLive(v1Root, gateway, mutation)` avec fixture.

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Engine.Tests -c Release` | **85/85 — exit 0** (`logs/engine-tests-live3.log`) — 70 → 85, +12 `LiveWriteTests` + 1 `LiveHonestyTests` (refus total sans adaptateur qualifié) + 2 contrats mis à jour (`prepare` = planification sans écriture, plus `write.unavailable`) | 24/10 (moteur live 3) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Bridge.Tests -c Release` | **4/4 — exit 0** (`logs/bridge-tests-live3.log`) — re-vérifié | 24/10 (moteur live 3) |
| `node tools/tests/web-check.mjs` | **90/90 — exit 0** (`logs/web-check-live3.log`) — GUI inchangée, re-vérifiée | 24/10 (moteur live 3) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.Engine.Live/Pesto.Engine.Live.csproj -c Release` | **exit 0**, 0 warning, 0 erreur (`logs/build-live3-engine.log`) | 24/10 (moteur live 3) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.App/Pesto.App.csproj -c Release` | **exit 0**, 0 warning, 0 erreur (`logs/build-live3-app.log`) ; `Program.cs` vérifié : toujours la factory à deux arguments, jamais l'adaptateur de mutation | 24/10 (moteur live 3) |

Comportements contrôlés (15 tests `LiveWriteTests`/`LiveHonestyTests` sur fixture, horloge contrôlée) :

- **Préparation liée à l'aperçu** : `preview.missing` sans aperçu (aucun nom calculé à la volée) ; `plan.stale` si l'aperçu
  est expiré (6 min), remplacé par un calcul plus récent, ou **déjà consommé** — un aperçu ne fonde qu'un seul plan ;
  `preview.identity` si l'aperçu appartient à un autre poste ou si un aperçu de renommage fonde une jonction ;
  `preview.changed` si `newName` diffère de l'aperçu.
- **Plan lié aux faits observés** : GUID réellement lu du poste, OU réellement observée (destination `move` = site observé
  seulement, `site.invalid` sur OU fantôme ; `move` sans destination → `invalid_arguments`), expiration 5 min,
  confirmation exacte recopiée, étapes et avertissements honnêtes du mode réel.
- **Gardes v1 portées** : `join.localOnly` (la jonction ne porte que sur `Environment.MachineName`), `join.alreadyJoined`
  (poste local déjà présent dans l'annuaire), collision après l'aperçu → `name.taken` avec « nouvel aperçu » dans la
  raison — jamais d'ajout automatique ; identité ou disponibilité qui bougent entre préparation et envoi →
  `identity.changed`/`name.taken` **avant** tout appel à l'adaptateur (0 requête fixture comptée).
- **Refus total sans adaptateur qualifié** : `operation.execute` → `write.unavailable` même avec config + adaptateur
  lecture + plan valide et confirmation exacte ; `confirmation.invalid` vérifié avant ; **aucun reçu fictif**
  (`receipts.list` vide, `receipts.get` refusé) ; le refus d'envoi ne consomme pas le plan (un envoi qui n'a jamais
  quitté le processus n'est pas un envoi) ; `queue.add` refusé ; capacités toutes désactivées ; diagnostics « Écritures »
  = unknown et « Jonction non accompagnée » = la valeur lue du cfg, jamais activée par le moteur.
- **Cycle du harnais de qualification** (fixture `FakeMutationGateway`, horloge contrôlée) : consommation du plan avant
  envoi puis `plan.consumed` au second appel — l'adaptateur n'est **jamais rappelé** (1 appel compté) ; reçu de session
  écrit avant l'envoi (`mode` = « live · » + description de l'adaptateur injecté, jamais une origine cachée) puis complété
  après relecture ; `succeeded` uniquement si l'adaptateur ET la relecture annuaire concordent ; succès annoncé mais non
  relu → `uncertain` ; panne d'adaptateur → `uncertain` avec « jamais rejoué automatiquement » ; refus avant envoi
  reconfirmé par relecture → `refused` ; phase v1 exit 10 → `pendingRestart` + `restartRequired:true` (Pesto ne redémarre
  rien) ; le GUID observé à la préparation est transmis à la demande d'envoi.

Limites : ce qui reste à qualifier hors job — adaptateur de mutation PS 5.1 réel (mutex `Global\GP_PostMutation_v1`,
barrières de reçus GP, reçu durable avant la commande native, relecture après), exécution WebView2, qualification
Windows/AD. Le reçu de session du moteur est en mémoire : le reçu **durable** autoritaire reste celui que l'adaptateur
qualifié devra écrire avant la commande native (contrat documenté dans `src/Pesto.Engine/MutationGateway.cs`).

## Moteur live 4 — adaptateur de mutations transitoire PS 5.1 (24/10/2026)

Gardes d'écriture relues dans la référence v1 **avant** codage : `wad/Pesto-Join.ps1` (`Write-PestoJoinReceipt`
Phase='Running' écrit avant `Add-Computer` et blocage si le reçu ne s'enregistre pas ; `Get-PestoJoinReceiptDecision` :
PendingRestart/Uncertain bloquants « Aucune nouvelle tentative automatique » ; phases selon exit code 10/97/98),
`wad/Pesto.Engine.Runtime.ps1` (mutex `Global\GP_PostMutation_v1` acquis `WaitOne(0)` et relâché en `finally` autour de
chaque mutation ; `Assert-PestoStoredMutationReady` : reçus GP Join/Operations relus avant action),
`wad/Pesto-Operations.ps1` (`AddToDomain` : nom préparé localement puis `JoinWithNewName,AccountCreate`, refus 13 si le
compte diffère du précréé, 2732 → refus politique, jamais d'objet supprimé ; `RenameComputer` : `Rename-Computer`
autorité locale, exit 20/21/97, **aucun repli automatique** ; `MoveComputer` : `Move-ADObject` **par GUID** observé,
DC exclu, relecture par GUID après, protection jamais levée sans autorisation).

Nouveau fichier : `src/Pesto.Engine.Live/PowerShellMutationGateway.cs` — script **constant** du binaire
(`-EncodedCommand`, arguments en stdin, `-NonInteractive`, jamais de mot de passe), seules commandes d'écriture
atteignables : `Add-Computer` (jonction locale, élévation exigée, nom revérifié dans l'annuaire avant envoi),
`Rename-Computer` (autorité locale ; distant = identité de session, jamais de secret), `Move-ADObject` (par GUID
uniquement, DC exclu, protection contre la suppression accidentelle **jamais levée** par l'adaptateur transitoire —
refus 31 motivé, écart de parité documenté). Refus prouvé avant envoi = `Failed` (codes portés 11/13/21/31/33/96/99) ;
résultat inconnu après envoi = `Uncertain` (97, jamais rejoué) ; acceptation = `PendingRestart` (10/20/89, Pesto ne
redémarre rien). Reçu durable écrit **avant** la commande native sous le mutex v1 (dossier `GP\V2\receipts`, contrôle
des points d'analyse comme v1, ACL SYSTEM+administrateurs portée de v1) ; reçu final non enregistré → `Uncertain`
(port exact de Pesto-Join.ps1). Barrières v1 relues avant envoi : `GP\Join\receipt.json` et `GP\Operations\direct.json`
— PendingRestart/Uncertain bloquent ; `UnattendedJoinEnabled` lu du cfg.json : si vrai, la jonction non accompagnée est
**refusée** par cet adaptateur (elle reste la commande V1 dédiée à double opt-in).

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Engine.Tests -c Release` | **90/90 — exit 0** (`logs/engine-tests-live4.log`) — 85 → 90, +5 `MutationAdapterTests`, aucun test supprimé | 24/10 (moteur live 4) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Bridge.Tests -c Release` | **4/4 — exit 0** (`logs/bridge-tests-live4.log`) — re-vérifié | 24/10 (moteur live 4) |
| `node tools/tests/web-check.mjs` | **90/90 — exit 0** (`logs/web-check-live4.log`) — GUI inchangée, re-vérifiée | 24/10 (moteur live 4) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.Engine.Live/Pesto.Engine.Live.csproj -c Release` | **exit 0**, 0 warning, 0 erreur (`logs/build-live4-engine.log`) | 24/10 (moteur live 4) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.App/Pesto.App.csproj -c Release` | **exit 0**, 0 warning, 0 erreur (`logs/build-live4-app.log`) ; `Program.cs` revérifié : toujours `CreateLive(options.V1Root, new PowerShellDirectoryGateway())` — l'adaptateur de mutation n'est jamais injecté par l'hôte | 24/10 (moteur live 4) |

Comportements contrôlés (5 tests `MutationAdapterTests`, aucun processus lancé, aucune écriture AD/disque depuis ce job) :

- **Refus hors Windows, avant toute chose** : les quatre kinds (join/rename/move/renameMove) renvoient `Failed` avec
  raison exploitable et code porté (96/11) — un refus qui n'a jamais quitté le processus n'est **jamais** `Uncertain` ;
  message borné 300 caractères sans caractère de contrôle ; `Description` se déclare « non qualifié Windows/AD ».
- **Validation avant même de sonder le système** : kind hors de la liste fermée, nom > 15 caractères, nom arbitraire,
  jonction d'un autre poste, `move` sans destination ou sans GUID, `move` avec nom imposé, OU avec caractère de
  contrôle, domaine malformé, identifiants non opaques → tous `Failed` motivés.
- **Moteur + adaptateur transitoire** (seule surcharge de qualification) : `operation.execute` produit un reçu
  `refused` honnête (refus prouvé avant envoi + relecture conforme), jamais un succès inventé ; le plan consommé ne
  peut plus être rejoué (`plan.consumed`).
- **Capacités et portes de l'hôte** : la simple présence de l'adaptateur transitoire n'active aucune capacité ;
  diagnostics « Écritures » = unknown avec réserve de qualification ; les entrées publiques `CreateLive` (avec et sans
  lecteur) refusent `write.unavailable`/`plan.stale` sans aucun reçu fictif.

Limites : **aucune exécution réelle de cet adaptateur depuis ce job** (refus systématique hors Windows ; la qualification
Windows/AD réelle — jonction d'un poste de test, renommage, déplacement par GUID, barrières GP vérifiées sur machine
réelle — reste à faire hors job). Écarts de parité assumés de l'adaptateur transitoire : protection contre la suppression
accidentelle jamais levée (refus 31, V1 la lève sous `CLEAR_PROTECTION`) ; `renameMove` non visible sous le nouveau nom
après le renommage → `pendingRestart` 89 avec déplacement à reprogrammer manuellement (port du code 89 v1) ; aucun
repli tâche/élévation distante (V1 `AllowPasswordTaskFallback` non porté, jamais de mot de passe).

## Interface web (lots GUI 23–24/10/2026)

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `node tools/tests/web-check.mjs` | **66/66 contrôles réussis — exit 0** — journal `spark/work/logs/web-check-gui2.log` | 24/10 (lot GUI 2) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.App/Pesto.App.csproj -c Release` (après ajout des pages GUI 2) | **exit 0**, 0 warning, 0 erreur ; les 9 modules `web/js/pages/*.js` sont dans `bin/Release/net10.0-windows/win-x64/web/js/pages/` | 24/10 (lot GUI 2) |

Le contrôle vérifie (sortie 0 seulement si tout passe) : les 116 imports des 41 modules JS résolus sans dépendance
externe ni CDN ; CSP `connect-src 'none'` et `script-src 'self'` dans index.html ; toutes les opérations `call('…')`
dans la liste fermée de docs/BRIDGE.md et couverture complète par le simulateur ; les 9 écrans de la navigation
(`plusieurspostes` alors explicitement listé comme non porté, écran `_todo` — état du lot GUI 2, voir lot GUI 3) ;
scénario de simulation complet — jonction
(aperçu → plan lié → confirmation fausse refusée `confirmation.invalid` → reçu simulé → plan consommé refusé
`plan.consumed` → double jonction refusée → jonction distante refusée `join.localOnly`), renommage (aperçu d'un autre
poste refusé `preview.identity`, reçu computer→newName, ancien nom disparu), même site = OU conservée, déplacement
(sans OU refusé `invalid_arguments`, sans redémarrage requis), expiration d'aperçu (`plan.stale` avec horloge
avancée), file (jonction refusée `queue.local`, doublon refusé, lot sans confirmation refusé, exécution séquentielle,
file vidée), reçus (4 simulés, relecture par id, id inconnu refusé), journal, opération inventée refusée, paramètres
(domaine invalide refusé, invalidation des aperçus à l'enregistrement, refus d'activer les écritures réelles).

Corrections apportées par ce contrôle : `web/js/simulation.js` appliquait déjà l'ordre des gardes du moteur C# mais
omettait deux refus documentés — ajout de « poste requis hors jonction » et « OU de destination requise pour un
déplacement » (`invalid_arguments`), alignés sur `SimulationBackend.OperationPrepare` et le test C# existant
`Déplacement sans OU refusé`.

Pages écrites au lot GUI 2 : `ajouter.js` (jonction locale, bouton activé seulement après `names.preview` complet,
confirmation exacte recopiée, collision → nouvel aperçu + nouveau clic, jamais d'ajout automatique), `unposte.js`
(recherche bornée, identité lue, renommage lié à l'aperçu, déplacement verrouillé tant qu'un renommage confirmé de ce
poste n'a pas été reçu dans la session, destination excluant le site courant), `interventions.js`, `journal.js`,
`parametres.js` (validation moteur, enregistrement annoncé comme invalidant aperçus/plans/file), `aide.js`
(raccourcis, diagnostics lus, à-propos honnête) et le module partagé `writeflow.js` (séquence
aperçu→plan→confirmation→exécution→reçu, sans aucun rejeu). Styles de pages ajoutés dans `css/shell.css`.

## Page Plusieurs postes (lot GUI 3 — 24/10/2026)

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `node tools/tests/web-check.mjs` | **90/90 contrôles réussis — exit 0** (`set -o pipefail`) — journal `spark/work/logs/web-check-gui3.log` | 24/10 (lot GUI 3) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.App/Pesto.App.csproj -c Release` (après ajout de la page) | **exit 0**, 0 warning, 0 erreur ; `web/js/pages/plusieurspostes.js` et `web/js/csv.js` sont dans la sortie `win-x64` — `logs/build-gui3.log` | 24/10 (lot GUI 3) |

Contrôles ajoutés par ce lot (outre les 66 existants, tous re-passés) :

- module d'import pur `web/js/csv.js` : aucun DOM/réseau/pont dans le fichier ; liste collée (majuscules, doublon
  ignoré, lignes invalides refusées ligne à ligne avec numéro, refus explicite si rien de valide, bornée à 50) ;
  CSV (en-tête sauté, « ; » ou « , », guillemets, colonnes optionnelles à `null`, type/nom invalides signalés avec
  leur ligne, fichier vide refusé, borné à 50 lignes) ;
- scénario file « côté page » sur un monde de simulation neuf : ajout en file sans aperçu refusé `plan.stale`
  (le nom vient de `names.preview`, jamais d'une saisie), jonction hors file `queue.local`, trois ajouts, doublon
  refusé `queue.duplicate`, retrait puis réajout (aperçu recalculé), lot préparé, exécution séquentielle
  **arrêtée** sur la ligne dont le poste a été renommé hors file entre-temps (2 reçus + raison, `stopped:true`),
  ligne échouée laissée en file sans rejeu, lot déjà envoyé refusé `batch.stale`, re-préparation de la ligne
  échouée refusée `computer.missing` (retrait explicite requis), lot sur file vide refusé `queue.empty` ;
- les 9 écrans de la navigation ont désormais leur module (liste `UNPORTED` vidée ; `_todo` reste le repli honnête
  des écrans non portés) ; `plusieurspostes` vérifié exporter `render`.

Page écrite au lot GUI 3 : `pages/plusieurspostes.js` (recherche bornée 25, liste collée et CSV lus côté interface
et validés ligne à ligne AVANT tout envoi, sélection = aperçu avec signalement par ligne, ajout en file qui relit
l'identité `computer.inspect` et calcule le nom par `names.preview` poste par poste — identité incomplète ou lecture
incomplète = refus affiché sans envoi ; `queue.prepare` servi d'aperçu du lot ; exécution unique après confirmation
écrite de l'identifiant du lot, reçus rendus par poste, arrêt affiché sans aucun rejeu). Module partagé `csv.js`
(épuré de tout DOM pour être testable sous node).

## Build Windows Pesto.App (win-x64) — débloqué et vérifié le 24/10/2026

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `timeout 180 dotnet restore src/Pesto.App/Pesto.App.csproj --verbosity diagnostic --disable-parallel` | exit 124 ; journal 58 321 lignes ; blocage au 1er appel HTTP api.nuget.org, après « Package source mapping match not found for package ID 'Microsoft.AspNetCore.App.Runtime.win-x64' » — `logs/restore-diag-01.log` | 24/10 00:37 UTC |
| `timeout 45 dotnet package search Microsoft.Web.WebView2 --source https://api.nuget.org/v3/index.json` | exit 124 « A task was canceled » (idove avec HTTP/2 désactivé) ; **exit 0** avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true` — `logs/pkgsearch-*.log` | 24/10 00:41 UTC |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true timeout 900 dotnet restore src/Pesto.App/Pesto.App.csproj` | **exit 0** — « Restored Pesto.App (in 2.2 sec) » ; `project.assets.json` présent avec les 5 packs win-x64 — `logs/restore-fix-01.log` | 24/10 00:45 UTC |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true timeout 600 dotnet build src/Pesto.App/Pesto.App.csproj -c Release` | **exit 0**, 0 warning, 0 erreur ; `bin/Release/net10.0-windows/win-x64/Pesto.exe` = PE32+ (GUI) x86-64 MS Windows — `logs/build-01.log` | 24/10 00:46 UTC |

Cause exacte du blocage (prouvée par les journaux ci-dessus) :

1. **Réseau/IPv6** : le client HTTP .NET privilégie IPv6 vers api.nuget.org ; la route IPv6 est un blackhole sur ce
   réseau et la connexion reste pendue sans erreur (d'où « Determining projects to restore » puis timeout 124).
   Preuve : `dotnet package search` expire sans option, échoue aussi avec HTTP/2 désactivé, puis réussit
   immédiatement avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true`. Ce n'est pas le dépôt, pas TLS, pas un verrou NuGet.
2. **packageSourceMapping incomplet** : `v2/NuGet.config` ne déclarait que `Microsoft.AspNetCore.App.Ref` ; or
   `Microsoft.WindowsDesktop.App.Runtime.win-x64` dépend de `Microsoft.AspNetCore.App.Runtime.win-x64`, sans source
   correspondante (ligne explicite du journal diagnostic).

Corrections appliquées (périmètre minimal) :

- `v2/NuGet.config` : pattern `Microsoft.AspNetCore.App.Ref` → `Microsoft.AspNetCore.App.*` (seul fichier modifié).
- Environnement de lancement local des commandes dotnet du job : `DOTNET_SYSTEM_NET_DISABLEIPV6=true`. Aucune
  installation globale, aucun changement de service, TLS et contrôles intacts. **À conserver dans toute commande
  dotnet future de ce job** (ou correction réseau IPv6 côté hébergeur).

Limites : compilation croisée Linux→win-x64. Elle ne valide ni l'exécution GUI/WebView2 ni la qualification AD.

## Packaging portable 1 — outils/manifestes du pack Windows (24/10/2026)

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `node tools/tests/pack-check.mjs` | **37/37 contrôles — exit 0** — `logs/pack-check-live5.log` | 24/10 (lot Packaging 1) |
| `node tools/tests/web-check.mjs` | **90/90 — exit 0** (re-vérifié, GUI inchangée) — `logs/web-check-live5.log` | 24/10 |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Engine.Tests -c Release` | **90/90 — exit 0** — `logs/engine-tests-live5.log` | 24/10 |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Bridge.Tests -c Release` | **4/4 — exit 0** — `logs/bridge-tests-live5.log` | 24/10 |

Artefacts écrits ce lot (aucun fichier compilé touché ; src/ et tests/ C# inchangés) :

- `tools/pack/pack-manifest.json` : manifeste fermé du pack — 21 fichiers requis (Pesto.exe/dll,
  Pesto.Core/Bridge/Engine/Engine.Live.dll, les 3 dll WebView2 + WebView2Loader, coreclr/clrjit/clretwrc/
  clrgc/clrgcexp/hostfxr/hostpolicy, createdump.exe, web/index.html), règles allow (dll racine, `web/`,
  `runtime/webview2/`, `runtimes/`, dossiers de culture en `.resources.dll` uniquement), interdits
  (`.pdb`, `cfg.json` et consorts, extensions de logs, tout lien), en-tête PE exigé pour `Pesto.exe`,
  chemins d'exécution d'AppPaths.cs repris à l'identique (`web`, `runtime\webview2\msedgewebview2.exe`,
  `Pesto.package.json`) et **contrôlés synchronisés** par pack-check (lecture d'AppPaths.cs et de
  MainForm.cs : l'hôte ne retombe jamais sur un navigateur installé).
- `tools/pack/make-pack.mjs` : assemblage (stage temporaire, destination nouvelle **jamais écrasée**,
  refus des liens, auto-vérification avant publication, `Pesto.package.json` + `SHA256SUMS` déterministes)
  et vérification (ensemble fermé, requis, PE32+ x86-64 par en-tête — contrôle d'artefact, pas
  d'exécution —, arbre `web/` identique à `v2/web/` en fichiers + SHA-256, SHA256SUMS exacts et complets,
  canal DEV/PROD). Exit 0 complet / 2 invalide / 3 valide mais runtime WebView2 fixe absent.
- `tools/tests/pack-check.mjs` : 37 contrôles sur la **vraie sortie de build** Release win-x64 —
  assemblage réel (333 fichiers, sans `.pdb` ni `cfg.json`, SHA256SUMS exacts, déterminisme DEV/PROD),
  refus sans runtime, pack marqué incomplet (exit 3, jamais présenté complet), pack complet avec runtime
  factice (exit 0), 11 altérations toutes refusées (fichier modifié, requis supprimé, fichier/dossier
  hors manifeste, `cfg.json`, `.pdb`, lien, arbre web détourné, PE corrompu, canal invalide, SHA256SUMS
  amputé), refus d'écrasement et de destination dans la sortie de build, synchronisation manifeste ↔
  AppPaths.cs/MainForm.cs.
- `docs/PACKAGING.md` : inventaire réel des dépendances (WebView2 1.0.4258.31 vendored + SHA-256, packs
  runtime self-contained win-x64 restaurés, 53 fichiers web/ contrôlés, runtime fixe **fourni hors job**
  — aucun téléchargement depuis ce job), structure, commandes, procédure Fixed Version sur poste
  Windows qualifié.
- `docs/QUALIFICATION-WINDOWS.md` : checklist d'exécution sur le poste Windows (pack vérifié, exécution
  WebView2 réelle depuis `runtime\webview2\`, pack amputé refusé, 9 écrans, lectures live relues, puis
  écritures labo PowerShellMutationGateway : reçus avant envoi, barrières GP, mutex v1, exit 10/20/89/97,
  refus 13/31/33/96, aucun secret en arguments/logs, consommation unique). Tout y est **non fait** —
  c'est l'état honnête, pas une case pré-cochée.

Faux positif écarté pendant le lot (corrigé dans le script, pas dans le test) : la classification du
code de sortie de `make-pack.mjs` se faisait par regex sur le message — « SHA256SUMS incomplet » était
interprété à tort comme pack incomplet (exit 3 au lieu de 2). Remplacé par un type d'exception dédié
`PackIncomplete` ; le test qui l'a détecté est conservé tel quel.

## Revue de parité complète (24/10/2026)

Dernier grand travail indépendant du job : relecture de docs/PARITY.md ligne à ligne contre les sources et les
journaux, correction du cosmétique connu, et ajout des contrôles qui manquaient pour que chaque « fait (portable) »
ait une preuve reproductible.

| Commande (depuis `v2/`) | Résultat | Date |
|---|---|---|
| `node tools/tests/web-check.mjs` | **102/102 — exit 0** (`logs/web-check-parity.log`) — 90 → 102, +12 contrôles (section 6 ci-dessous) | 24/10 (revue de parité) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet build src/Pesto.App/Pesto.App.csproj -c Release` | **exit 0**, 0 warning, 0 erreur (`logs/build-parity-app.log`) ; `web/js/pages/unposte.js` corrigé recopié dans la sortie `win-x64` (vérifié par lecture : 4× `icon('sync')`, 0× `icon('edit')`) | 24/10 (revue de parité) |
| `node tools/tests/pack-check.mjs` | **37/37 — exit 0** (`logs/pack-check-parity.log`) — pack re-assemblé depuis la sortie reconstruite, arbre `web/` identique à `v2/web/` en fichiers + SHA-256 | 24/10 (revue de parité) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Engine.Tests -c Release` | **90/90 — exit 0** (`logs/engine-tests-parity.log`) — re-vérifié, code C# inchangé | 24/10 (revue de parité) |
| `DOTNET_SYSTEM_NET_DISABLEIPV6=true dotnet run --project tests/Pesto.Bridge.Tests -c Release` | **4/4 — exit 0** (`logs/bridge-tests-parity.log`) — re-vérifié | 24/10 (revue de parité) |

Contrôles ajoutés à `tools/tests/web-check.mjs` (section 6 — 12 contrôles) :

- **Icônes** : les 117 appels `icon('nom')` statiques de tout `web/js` (hors `icons.js`) référencent une icône réellement
  déclarée dans `icons.js` — un nom absent tombait jusqu'ici en silence sur `info` ; les 15 icônes de la navigation et
  des thèmes (`icon(page.icon)`/`icon(t.icon)` dans app.js) et les 60 options `{ icon }` hors kit (pill, commandes
  d'écran — rendues par `glyph()` avec repli `icon()`) sont contrôlées de la même façon (jeu figé `glyphs.js` accepté).
- **Couverture réelle des 9 pages vs docs/BRIDGE.md** : les **20 opérations** du pont sont toutes appelées par
  l'interface (`call('…')` ou `trackedCall('…')`) — aucune opération documentée sans écran ; le repli maquette
  `_todo` est réservé au routeur (aucune page ne l'importe) ; les 9 écrans ont leur module et `export render`
  (contrôles existants conservés).
- **Shell promis** : handlers clavier Ctrl+B (repli du menu, bouton tout en bas) et Ctrl+K (palette) présents dans
  `app.js` ; les 4 thèmes (clair/sombre/contraste/système) sont déclarés.
- **Kit Domenia figé** : chaque entrée non « modified » de `web/provenance.json` est vérifiée par empreinte SHA-256
  locale, puis **comparée octet à octet à `../references/domenia/v2/web`** quand la référence est sur le poste
  (29/29 identiques le 24/10) ; les copies écartées du figé doivent porter un motif `modified`.

Contrôles de non-vacuité de ces nouveaux contrôles (faux négatifs écartés par reproduction indépendante — chaque
mutation est restaurée ensuite, et l'état restauré repasse 102/102) :

- `icon('info')` → `icon('edit')` dans `pages/aide.js` → **FAIL + exit 1** (`logs/web-check-mut1.log`) ;
- retrait de l'appel `diagnostics.read` de `aide.js` → **FAIL + exit 1** (`logs/web-check-mut2.log`, opération
  jamais appelée détectée) ;
- octet ajouté dans la copie figée `js/kit/dialog.js` → **FAIL + exit 1** (`logs/web-check-mut3.log`, empreinte
  provenance divergente).

Corrections apportées par cette revue :

- **Cosmétique connu** : `pages/unposte.js` appelait `icon('edit')` (4 usages — carte « Renommer » et bouton
  « Appliquer le renommage ») ; `edit` n'existe pas dans `icons.js` (copie Domenia figée, non touchée) et tombait en
  silence sur `info`. Usage corrigé vers `icon('sync')` (icône existante, non utilisée ailleurs) ; `writeflow.js`
  vérifié : il n'utilisait pas `icon('edit')` (la note du lot précédent était imprécise — seuls les 4 usages de
  `unposte.js` existaient).
- **docs/PARITY.md** : comptes de tests obsolètes corrigés contre les sources (47 → classes actuelles et 90/90 ;
  « 15 tests LiveWriteTests » → 14 ; « 8 tests V1Config » → 4 config + honnêteté ; comptes web-check 66/90 → 102) ;
  preuves design kit et shell renforcées (comparaison octet à octet à la référence, Ctrl+B/Ctrl+K/thèmes contrôlés).

État après revue : **parité portable complète et contrôles portables verts**. La limite externe unique du job reste
entière et documentée : **aucune exécution Windows/AD réelle** — pack avec runtime WebView2 fixe, exécution GUI,
lectures relues contre l'AD et écritures labo `PowerShellMutationGateway` à exécuter sur le poste de qualification
(`docs/QUALIFICATION-WINDOWS.md`, tout y est non fait) ; écarts assumés de l'adaptateur transitoire (protection de
suppression jamais levée, pas de repli tâche/élévation distante, `renameMove` différé 89) — l'adaptateur n'est
jamais injecté par l'hôte.

## File live sur gateway de qualification (24/10/2026)

Réponse au constat 1 et au « prochain lot concret » de REVIEW_REQUIRED.md : la file réelle du mode réel n'est plus
un refus constant. `LiveBackend` implémente `queue.add / queue.list / queue.remove / queue.prepare / queue.execute`
sur le gateway de qualification injecté, en partageant les chemins existants (aucun chemin d'écriture parallèle) :

- `queue.add` : validation par le **même** `BuildPlan` que l'opération unitaire (aperçu obligatoire/frais/dernier/lié
  au poste, **consommé à l'ajout** ; GUID et OU réellement observés ; nom re-vérifié → `name.taken` avec raison
  « nouvel aperçu + nouveau clic ») ; refus `queue.local` (jonction), `queue.duplicate` (poste ou nom), `queue.limit`
  (borne = `POLICY.MaxBatch` **lu** de la configuration V1 — test avec `MaxBatch: 2`, la raison cite 2 et MaxBatch).
- `queue.prepare` : relecture annuaire ligne à ligne (GUID → `identity.changed`, nom → `name.taken`, poste →
  `computer.missing`, destination → `site.invalid`), sinon un plan par ligne (expiration 5 min, confirmation exacte)
  et version de file enregistrée sur le lot.
- `queue.execute` : `confirmed:true` exigé (`confirmation.invalid`), `batch.stale` sur file modifiée/expirée/déjà
  envoyée (aucun rejeu), puis envoi **séquentiel sous le verrou du moteur** par `ExecutePlan` partagé avec
  l'unitaire (identité et disponibilité relues avant envoi, reçu écrit avant envoi, relecture après, incertain jamais
  rejoué). Première ligne non `succeeded` (refusée/incertaine/`pendingRestart`) = arrêt ; lignes tentées sorties de
  la file avec leur reçu ; lignes non tentées restantes. Sans adaptateur injecté : `write.unavailable` **avant toute
  consommation** (file et lot intacts, zéro reçu) — exécution de production toujours fermée.
- `names.preview` exclut les noms visés par la file (jamais reproposés pendant qu'ils y sont).

Commandes et résultats (24/10, DOTNET_SYSTEM_NET_DISABLEIPV6=true, pipefail) :

- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **111/111** (logs/engine-tests-livequeue.log) :
  90 antérieurs + **21 nouveaux** `LiveQueueTests` (round-trip add/list/remove, jonction refusée, consommation unique
  de l'aperçu, doublons, borne MaxBatch lue, aperçu expiré, nom pris après aperçu, move sans aperçu, nom en file
  jamais reproposé, préparation refusée sur identité/nom modifiés, lot séquentiel avec arrêt sur refus (3 lignes :
  2 envoyées, la 3ᵉ jamais), incertain jamais rejoué, pendingRestart arrête, exécution sans adaptateur = refus sans
  consommation, confirmation explicite, lot périmé par changement de file, lot expiré, identité changée avant envoi =
  zéro reçu et lignes conservées, reçus du lot listés et liés à la demande avant envoi).
- Non-vacuité prouvée par mutations temporaires restaurées ensuite (pleine suite re-verte 111/111 après
  restauration) : `queue.list` forcé vide → **9 échecs + exit 1** (logs/engine-tests-livequeue-mut1.log) ;
  `queue.execute` forcé en refus constant → **8 échecs + exit 1** (logs/engine-tests-livequeue-mut2.log).
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4** (logs/bridge-tests-livequeue.log).
- `dotnet build src/Pesto.App/Pesto.App.csproj -c Release` → exit 0, 0 warning, 0 erreur
  (logs/build-livequeue-app.log) ; l'`Pesto.Engine.dll` win-x64 du pack contient bien les nouveaux chemins
  (`queue.duplicate`, `queue.empty`, `batch.stale` présents dans les métadonnées).
- `node tools/tests/web-check.mjs` → **102/102** (logs/web-check-livequeue.log) ; `node tools/tests/pack-check.mjs`
  → **37/37** (logs/pack-check-livequeue.log).

Tests existants ajustés (et non supprimés) là où ils verrouillaient le refus stub que la revue demandait de lever :
`LiveWriteTests.ExecuteWithoutQualifiedAdapterRefusesEveryWrite` (l'ajout et la préparation sont lecture seule ;
l'exécution du lot reste `write.unavailable`, zéro reçu, file intacte), `LiveReadTests.WritesStayRefusedEvenWithGateway`
(`queue.add` sans aperçu → `preview.missing`, `queue.execute` sans lot → `batch.stale`),
`LiveHonestyTests.WritesAndConfigAreRefused` (sans configuration : `queue.add` → `config.missing`, `queue.execute` →
`batch.stale`). Les refus d'exécution sans adaptateur qualifié restent couverts partout.

État après lot : file réelle **codée et testée sur fixtures** (code réel portable) ; ce n'est **ni** une exécution
AD (aucune, hors job), **ni** une capacité activée (`queue` reste `enabled:false` tant que la qualification
Windows/AD n'existe pas). La page Plusieurs postes reste branchée sur les mêmes opérations ; son exécution dans
WebView2 et l'exécution réelle du lot sur gateway qualifié restent à la checklist de qualification.

## Configuration réelle et convention configurable (24/10/2026)

Réponse au constat 2 de REVIEW_REQUIRED.md : `settings.save` n'est plus un refus `config.unavailable` et le motif
n'est plus le motif par défaut codé en dur. La convention de nommage est **réellement lue, enregistrée et prise en
compte selon le modèle V1 actuel** (`Pesto-Contracts.ps1` : `Assert-PestoNamingConvention`, `Get-PestoNamingLayout`,
`ConvertTo-PestoNameParts`, `New-PestoComputerName` ; `Pesto-Configuration.ps1` : `Save-Cfg`, `Apply-CfgHot`,
`Write-PestoAtomicText`, `Assert-PestoConfigFileUnchanged`, `Invalidate-PestoConfigurationPlans`) :

- **Lecture** (`V1Config`) : objet `NamingConvention` du cfg.json validé au schéma fermé (Schema=1 ; Id ; Tokens =
  permutation exacte de Type/Prefix/Site/Service/Number ; Widths Prefix 1-12 / Site 1-4 / Service 1-6 / Number 1-6 ;
  Types sous-ensemble sans doublon de P/S/V ; total ≤ 15). L'absence conserve le format historique. Les facettes
  lues sont commandées par la convention : `Prefixe` (chiffres à la largeur Prefix), `PreprodSite` (largeur
  Service), `TAGS.Tag` et `NameCatalogue` (largeurs Site/Service) — ports de `Get-PestoFacetPattern` dans
  `Test-CfgValid`.
- **Prise en compte** : `names.preview` (génération et validation type/service), l'analyse inverse des noms observés
  (`directory.services`, `directory.search`, `computer.inspect`) et `settings.get` utilisent la convention lue ;
  sans configuration lue, `namingPattern` est `null`. `diagnostics.read` rend la convention active (identifiant,
  ordre des facettes, largeurs, types).
- **Écriture** (`LiveBackend.SettingsSave`) : validation intégrale **avant** écriture (`config.invalid` cite la
  facette incompatible — préfixe, PreprodSite, TAGS, NameCatalogue, POLICY), garde d'empreinte SHA-256
  (`config.changed` si le fichier a bougé hors session — jamais remplacé à l'aveugle), écriture atomique avec
  `cfg.json.bak` conservé, relecture + revalidation avec rétablissement de l'ancienne version si la relecture
  échoue, puis invalidation des aperçus, plans et file. Champs métier (domaine, préfixe, production, sites) :
  refus `config.business_readonly` sans écriture ; `dc` informatif, jamais enregistré ; motif refusé :
  `invalid_naming` ; sans dossier V1 : `config.missing`. Retour au motif historique = suppression de l'objet du
  fichier (l'absence est le format historique v1). `POLICY.RandomNameChoice` est synchronisé pour ne jamais
  contredire `RandomNameEnabled`.
- **Contrat du pont** : le motif s'exprime `{type}`/`{type:PS}`, `{prefix}`, `{site}`/`{site:3}`,
  `{service}`/`{service:4}`, `{number:2}` (largeurs site 1-4, service 1-6, numéro 1-6 ; tirets seuls séparateurs) ;
  hint de la page Paramètres aligné.

Commandes et résultats (24/10, DOTNET_SYSTEM_NET_DISABLEIPV6=true, pipefail) :

- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **131/131 — exit 0** (`logs/engine-tests-settings.log`) :
  111 antérieurs + **14** `LiveSettingsTests` (motif lu rendu par settings.get ; convention atelier V1 commande le
  nom « IT01P123PA » numéro au milieu ; analyse inverse aux positions configurées ; types restreints P/S ; écriture
  de la convention dans le cfg.json + `.bak` exact + nom proposé suivant le motif enregistré ; retour historique
  supprime l'objet ; motif invalide refusé sans toucher le disque ni créer de `.bak` ; convention incompatible avec
  les TAGS lus → `config.invalid` fichier intact ; cinq changements métier → `config.business_readonly` zéro octet
  écrit ; fichier modifié hors session → `config.changed` contenu extérieur préservé ; RandomNameEnabled persisté
  et relu dans les deux sens ; RandomNameChoice synchronisé ; reste du cfg conservé ; invalidation aperçus/plans/file
  avec re-préparation obligatoire ; `namingPattern` null sans config ; flux complet via le pont fermé + `mode_fixed`)
  + **4** `NamingTests` (grandes et ordre configurés, bornes v1 des largeurs, sous-ensemble de types, largeur 6)
  + **2** refus de convention hors schéma dans `LiveReadTests`.
- Non-vacuité prouvée par mutations temporaires restaurées ensuite (pleine suite re-verte 131/131 après
  restauration, résidu vérifié absent) : `settings.save` forcé en refus constant → **13 échecs**
  (`logs/engine-tests-settings-mut1.log`) ; convention demandée jamais écrite (`IsHistoricalDefault` forcé vrai) →
  **7 échecs** (`logs/engine-tests-settings-mut2.log`) ; `settings.get`/calculs retombés sur le motif par défaut →
  **6 échecs** (`logs/engine-tests-settings-mut3.log`) — exactement les comportements du constat 2.
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4 — exit 0** (`logs/bridge-tests-settings.log`).
- `dotnet build src/Pesto.App/Pesto.App.csproj -c Release` → **exit 0**, 0 warning, 0 erreur
  (`logs/build-settings-app.log`) ; l'`Pesto.Engine.dll` win-x64 (13:08) du pack contient les nouveaux chemins
  (`config.business_readonly`, `config.changed`, `NamingConvention`, `RandomNameChoice` présents) ; le
  `parametres.js` de la sortie porte le hint aligné.
- `node tools/tests/web-check.mjs` → **102/102 — exit 0** (`logs/web-check-settings.log`) ;
  `node tools/tests/pack-check.mjs` → **37/37 — exit 0** (`logs/pack-check-settings.log`, pack ré-assemblé depuis
  la sortie reconstruite).

Tests existants ajustés (et non supprimés) là où ils verrouillaient le refus stub que la revue demandait de lever :
`LiveReadTests.WritesStayRefusedEvenWithGateway` (le changement métier est refusé `config.business_readonly`, plus
`config.unavailable`), `LiveHonestyTests.WritesAndConfigAreRefused` (`settings.save` sans dossier V1 →
`config.missing`). Les refus d'écriture AD sans adaptateur qualifié restent couverts partout (capacités
`enabled:false`, `write.unavailable`).

État après lot : convention de nommage **réellement lue/enregistrée/prise en compte et testée sur fixtures** (code
réel portable) ; l'écriture n'a **jamais** été exécutée sur une installation V1 réelle sous Windows (hors job) —
la qualification de `settings.save` sur poste Windows (fichier réel, `.bak`, concurrence) reste à la checklist.
Aucune écriture AD : `settings.save` écrit le cfg.json du dossier fourni par l'hôte, jamais l'annuaire.

## Tableau de bord réel et historique durable (24/10/2026 — constats 3 et 4 de la revue)

Constats relus dans `src/Pesto.Engine/LiveBackend.cs` : `Dashboard` renvoyait systématiquement null/listes vides ;
les listes de reçus/journaux étaient purement mémoire. Portés et vérifiés :

- `src/Pesto.Engine/GpHistory.cs` (nouveau) — lecteur **lecture seule stricte** du registre durable GP :
  `Interventions` V1 (port de `Read-PestoIntervention` pour l'affichage : schéma fermé 34 champs, champs requis,
  `Schema` 1-3, énumérations `Phase`/`Entra`/`Protection`/`Rename`/`Move`, plan fermé 13 champs avec `Renommer`/`Deplacer`
  booléens, nom de fichier = `OperationId`, `Timeline` monotone ≤ 96, `Tasks` ≤ 8, `Coordination` par empreintes,
  taille ≤ 128 Kio, liens non suivis) et `V2/receipts` de l'adaptateur (même format que
  `PowerShellMutationGateway.WritePreSendReceipt`, nom de fichier = `ReceiptId`). Aucun fichier supprimé, déplacé ni réécrit ;
  illisible → ligne isolée `invalid:<fichier>` « Aucun verrou levé » ; borne v1 5 000/dossier annoncée `truncated`.
- `LiveBackend.Dashboard` — lecteur réel : inventaire borné (≤ 20 000) de la racine gérée via l'adaptateur injecté,
  comptes de sites par la convention réellement lue, `pendingRestart`/`uncertain` d'après reçus durables relus
  (acquittements exclus), `lastActivity` = reçus fusionnés triés ; null réservé à l'inconnu ; refus motivés
  `config.missing`/`directory.unavailable` (plus de null/listes constants). Nœud `history` d'état du registre.
- `LiveBackend.ReceiptsList/ReceiptsGet` — fusion session + registre durable par identité uniquement (aucun effacement,
  aucune fusion arbitraire), reçus de l'adaptateur consultables après redémarrage, `receipts.get` hors les deux sources →
  `receipt.missing` motivé ; champs `{invalidCount,truncated,persistent}` ajoutés.
- Diagnostics : check « Historique durable » (lu / illisibles / tronqué / non lu).
- Frontend : `accueil.js` (null → « — » avec infobulle, note d'historique), `interventions.js` (cartes `unreadable`,
  pilule « Acquittée », note durable).

Commandes et résultats (24/10, toutes avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true`, node 24.18.0) :

- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **147/147 — exit 0** (`logs/engine-tests-dashboard.log`)
  = 131 antérieurs + 16 nouveaux `LiveDashboardHistoryTests` :
  refus motivés sans adaptateur/config, comptes d'inventaire réels, null sur lecture incomplète, compteurs d'après reçus
  durables, tri du plus récent, acquittement non compté, survie au redémarrage (reçu de l'adaptateur relu depuis le
  disque par un moteur sans adaptateur injecté), isolement des fichiers illisibles (jamais supprimés, jamais fondus),
  rejet des entrées V1 hors barrières (Phase hors énumération, fichier ≠ OperationId, champ inconnu, `Renommer` non
  booléen), fusion sans effacement, panne d'énumération honnête, filtre sur les deux sources.
- Non-vacuité prouvée par mutations temporaires restaurées à l'identique (pleine suite re-verte 147/147 après
  restauration, résidu vérifié absent par grep) : compteurs du dashboard retombés en constantes null/vide →
  **6 échecs + exit 1** (`logs/engine-tests-dashboard-mut1.log`) ; historique durable ignoré par la fusion →
  **9 échecs + exit 1** (`logs/engine-tests-dashboard-mut2.log`) ; fichier illisible silencieusement écarté de la liste
  au lieu d'être isolé → **2 échecs + exit 1** (`logs/engine-tests-dashboard-mut3.log`) — exactement les comportements
  des constats 3 et 4.
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4 — exit 0** (`logs/bridge-tests-dashboard.log`).
- `dotnet build src/Pesto.App/Pesto.App.csproj -c Release` → **exit 0**, 0 warning, 0 erreur (`logs/build-dashboard-app.log`).
- `node tools/tests/web-check.mjs` → **102/102 — exit 0** (`logs/web-check-dashboard.log`) ;
  `node tools/tests/pack-check.mjs` → **37/37 — exit 0** (`logs/pack-check-dashboard.log`).

Tests existants ajustés (et non supprimés) là où la revue exigeait de lever la constante :
`LiveHonestyTests.EmptyResultsAreHonestNotFabricated` — `dashboard.read` sans configuration refuse `config.missing` et
sans adaptateur annuaire refuse `directory.unavailable` (au lieu d'un objet constamment null) ; les autres assertions
d'honnêteté (aucun reçu/journal inventé, capacités désactivées) restent vertes.

État après lot : tableau de bord réel et historique/reçus durables **portés et testés sur fixtures** (code réel
portable). **Aucune exécution Windows/AD** : la relecture du vrai `%ProgramData%\GP` (registre V1 réel, reçus réels de
l'adaptateur) et l'affichage WebView2 restent à la checklist `docs/QUALIFICATION-WINDOWS.md`. Le moteur ne supprime
jamais un fichier du registre ; les capacités d'écriture restent `enabled:false`.

## Lot raccordement production — 24/10/2026 (constat 5 de la revue)

Portée : `src/Pesto.Engine/HostWiring.cs` (nouveau) — décision pure et testable du raccordement de l'hôte ;
`Program.cs` branché dessus ; `LaunchOptions` retiré de `HostPolicy.cs` (analyse d'arguments déplacée dans le moteur,
donc testable) ; `MainForm`/`AppPaths` : titre « Annuaire · Qualification » et profil de données `Qualification`
séparé ; `session.info.readOnly` honnête (`mutation is null`) ; surcharge de qualification de `PestoBackend` et
documentation de `PowerShellMutationGateway` mises à jour.

Commandes et résultats (24/10, toutes avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true`, node 24.18.0) :

- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **160/160 — exit 0** (`logs/engine-tests-hostwiring.log`)
  = 147 antérieurs + 13 nouveaux `HostWiringTests` : profil par défaut production sans aucune injection (session
  `readOnly:true`, capacités toutes `enabled:false`, `operation.execute` → `write.unavailable`, aucun reçu) ; refus
  `host.wiring_inconsistent` d'un adaptateur ou d'une confirmation demandés hors harnais (analyse d'arguments **et**
  décision pure) ; exclusivité simulation (`mode_fixed`) ; options inconnues/dupliquées/tronquées refusées
  (`host.args`) ; `--v1-root` absolu local exigé (relatif et partage réseau refusés) ; harnais sans `--v1-root` refusé
  (`config.missing`) ; adaptateur absent ou non déclaré refusé (`host.adapter_missing`, `host.adapter_unknown`,
  variante `PS51` refusée) ; harnais hors Windows refusé (`host.not_windows`) ; confirmation approximative refusée
  (`host.confirmation_required` : null, vide, minuscules, préfixe, espaces ajoutés) ; jeu complet sélectionné
  uniquement sur Windows ; sélection harnais = pipeline d'envoi ouvert sur fixture (reçu `succeeded`, un seul appel,
  consommation unique) **sans activer aucune capacité** ; sélection production = adaptateur jamais construit.
- Non-vacuité prouvée par mutations temporaires restaurées à l'identique (pleine suite re-verte 160/160 après
  restauration, résidu vérifié absent par grep) : profil par défaut retombé en harnais → **3 échecs + exit 1**
  (`logs/engine-tests-hostwiring-mut1.log`) ; gardes Windows et confirmation retirées du harnais → **3 échecs + exit 1**
  (`logs/engine-tests-hostwiring-mut2.log`) ; `readOnly` retombé en constante `true` → **1 échec + exit 1**
  (`logs/engine-tests-hostwiring-mut3.log`) — exactement les comportements du constat 5.
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4 — exit 0** (`logs/bridge-tests-hostwiring.log`).
- `dotnet build src/Pesto.App/Pesto.App.csproj -c Release` → **exit 0**, 0 warning, 0 erreur (`logs/build-hostwiring-app.log`) ;
  `Pesto.dll` win-x64 contient « Annuaire · Qualification », `Pesto.Engine.dll` contient `host.not_windows`,
  `host.confirmation_required`, `host.adapter_unknown`, `host.adapter_missing`, `host.wiring_inconsistent`,
  « QUALIFICATION WINDOWS/AD » et les nouvelles options `--qualification-harness`/`--mutation-adapter`/`--confirm-qualification`
  (octets UTF-16 vérifiés).
- `node tools/tests/web-check.mjs` → **102/102 — exit 0** (`logs/web-check-hostwiring.log`) ;
  `node tools/tests/pack-check.mjs` → **37/37 — exit 0** (`logs/pack-check-hostwiring.log`).

Gardes conservées vérifiées : aucune écriture AD exécutée ni injectée depuis ce job (le harnais reste refusé hors
Windows, donc impossible à activer ici) ; capacités toujours `enabled:false` même sélection harnais ; aucun fichier V1
ni politique V1 modifiée ; `PowerShellMutationGateway` jamais construit par le chemin de production ; le harnais n'a
pas le même profil de données que le mode réel courant.

État après lot : le raccordement production/harnais est **implémenté, documenté et testé sur fixtures** (code réel
portable). **Aucune exécution Windows/AD** : l'usage réel du harnais (section 3 de `docs/QUALIFICATION-WINDOWS.md`)
reste à faire sur le poste de qualification, hors job.

## Lot écarts transitoires V1 — 24/10/2026 (constat 6 de la revue)

Portée : `src/Pesto.Engine.Live/PowerShellMutationGateway.cs` — les trois écarts de parité transitoires traités selon V1
(`../references/pesto-v1/DEV/wad/Pesto-Operations.ps1` : `MoveComputer`, `GoRenameAndMove`, `Wait-ADComputerVisible`,
`Invoke-RenameComputerTaskFallback` ; `Pesto-Core.ps1` : lecture `CLEAR_PROTECTION`) :

- **(a) Protection contre la suppression accidentelle portée de V1** (remplace le refus 31 plat) :
  `ReadClearProtectionOnMove` lit `CONF.ClearProtectionOnMove` du cfg.json (absent = true comme le moteur V1 ; texte
  « true »/« false » ou booléen, sans casse ; illisible/absent/invalide = `unknown`) ; la décision part dans le payload
  stdin (jamais normalisée en vrai par complaisance) ; le script constant applique le port de `MoveComputer` : levée
  temporaire par `Set-ADObject -ProtectedFromAccidentalDeletion:$false` pendant le seul `Move-ADObject`, restauration
  `:$true` **toujours tentée en finally puis relue** (relecture finale par GUID avec la propriété de protection),
  **32 « Protection NON RÉTABLIE »** en incertain jamais rejoué, refus **31** « levée temporaire interdite par la
  configuration » si lu false, refus **96** « ni levée ni admise » si la valeur n'a pas pu être lue.
- **(b) Repli V1 par tâche planifiée/élévation sous compte AD : écart bloquant la parité, documenté et nommé, jamais
  masqué.** Le repli V1 exige un compte AD saisi et `POLICY.AllowPasswordTaskFallback` (donc un mot de passe) — hors du
  contrat de l'adaptateur transitoire (aucun mot de passe, jamais). Chaque refus concerné (jonction non élevée,
  renommage local non élevé, refus confirmé local et distant) nomme l'écart dans son message ; la règle V1 « aucun repli
  après un résultat incertain » est rappelée sur les deux appels de renommage. Le script ne contient ni `schtasks`, ni
  `Register-ScheduledTask`, ni `-Credential` (assertions de non-vacuité). Port réservé à l'adaptateur qualifié ultérieur.
- **(c) `renameMove` différé porté** : attente de la visibilité du nouveau nom sous 60 s **par le GUID du plan**
  (port `Wait-ADComputerVisible`) — panne AD levée immédiatement → **89 « DÉPLACEMENT NON TENTÉ »**, expiration →
  **89 « DÉPLACEMENT DIFFÉRÉ »** à reprogrammer seul ; mapping V1 des suites du déplacement : 30/33 → **77**,
  32 → protection non rétablie (incertain), incertain → **97 ARRÊT DE SÉCURITÉ**, autre refus → **89 « DÉPLACEMENT
  ÉCHOUÉ »** — un renommage accepté avec déplacement non fait n'est jamais rendu comme un succès ni comme un « rien
  écrit ».

Commandes et résultats (24/10, toutes avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true`, node 24.18.0) :

- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **166/166 — exit 0** (`logs/engine-tests-v1gaps.log`)
  = 160 antérieurs + 6 nouveaux `TransientAdapterParityTests` : lecture `ClearProtectionOnMove` sur fixtures (absent =
  vrai V1, texte/booléen/casse, invalide et nombre → unknown, cfg malformé/absent/null → unknown) ; payload = décision
  lue + champs fermés, sans secret, `unknown` jamais converti en vrai ; gardes du script constant (levée+restauration,
  32/31/96, relecture OU+protection, les deux chemins d'appel passent la décision) ; renameMove 60 s / 89 NON TENTÉ /
  89 DIFFÉRÉ / 77 / ARRÊT DE SÉCURITÉ / 89 ÉCHOUÉ ; repli nommé ≥ 3 fois et jamais implémenté (aucune
  `schtasks`/`Register-ScheduledTask`/`-Credential`/`Get-Credential`) ; aucune commande native interdite
  (`Remove-ADComputer`/`Remove-ADObject`/`Restart-Computer`/`shutdown`/`dsregcmd`/`Set-ADComputer`…).
- Non-vacuité prouvée par mutations temporaires restaurées à l'identique (pleine suite re-verte 166/166 après
  restauration, résidu `MUT-` vérifié absent) : garde de protection retombé en refus 31 plat (ancien code) →
  **1 échec + exit 1** (`logs/engine-tests-v1gaps-mut1.log`) ; `renameMove` retombé à l'unique 89 passe-plat sans
  DIFFÉRÉ/ARRÊT DE SÉCURITÉ/89 ÉCHOUÉ → **1 échec + exit 1** (`logs/engine-tests-v1gaps-mut2.log`) ; lecture
  `ClearProtectionOnMove` retombée en « true » constant (chemin null, valeur invalide, catch) → **1 échec + exit 1**
  (`logs/engine-tests-v1gaps-mut3.log`) ; mention du repli masquée sur le refus distant → le premier test s'est révélé
  **insuffisant (passait à tort)**, renforcé en comptage des mentions (≥ 3), puis **1 échec + exit 1**
  (`logs/engine-tests-v1gaps-mut4.log`) — le renforcement est consigné comme exigence : un masquage partiel du repli
  fait désormais échouer la suite.
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4 — exit 0** (`logs/bridge-tests-v1gaps.log`).
- `dotnet build src/Pesto.App/Pesto.App.csproj -c Release` → **exit 0**, 0 warning, 0 erreur (`logs/build-v1gaps-app.log`) ;
  `Pesto.Engine.Live.dll` win-x64 contient (octets UTF-16 vérifiés) « DÉPLACEMENT DIFFÉRÉ », « DÉPLACEMENT NON TENTÉ »,
  « Protection NON RÉTABLIE », « levée temporaire interdite par la configuration », « AllowPasswordTaskFallback »,
  « ARRÊT DE SÉCURITÉ », « DÉPLACEMENT ÉCHOUÉ ».
- `node tools/tests/web-check.mjs` → **102/102 — exit 0** (`logs/web-check-v1gaps.log`) ;
  `node tools/tests/pack-check.mjs` → **37/37 — exit 0** (`logs/pack-check-v1gaps.log`).

Gardes conservées vérifiées : aucune exécution PowerShell ni écriture AD depuis ce job (l'adaptateur refuse hors
Windows ; le harnais reste refusé ici) ; capacités toujours `enabled:false` ; aucun fichier V1 ni politique V1 modifiée
(les fixtures cfg.json sont des copies temporaires de test) ; barrières GP, mutex, reçu avant envoi, `UnattendedJoinEnabled`
inchangés ; `TreatWarningsAsErrors` a d'ailleurs refusé une mutation introduisant du code inatteignable (CS0162), la
mutation a été refaite sur des chemins atteignables.

État après lot : les écarts (a) et (c) sont **portés selon V1 et testés sur fixtures** (code réel portable) ; l'écart
(b) est **documenté comme bloquant la parité** avec nommage explicite dans chaque refus concerné. **Aucune exécution
Windows/AD** : le comportement réel du script (levée/restauration, codes 30/31/32/33/77/89/97) reste à qualifier —
lignes 3.5, 3.6 et 3.11 de `docs/QUALIFICATION-WINDOWS.md`.

## Lot revue croisée finale — 24/10/2026 (les six constats relus dans les sources actuelles)

Portée : relecture des six constats de `REVIEW_REQUIRED.md` dans les sources actuelles (`LiveBackend.cs`, `GpHistory.cs`,
`HostWiring.cs`, `Program.cs`, `PowerShellDirectoryGateway.cs`, pages web), contrôle que **chaque refus restant est une
porte de qualification ou une garde métier réelle** — jamais une fonction demandée remplacée par une valeur constante —
et production du dossier de preuves `docs/EVIDENCE.md` (index des lots, commandes, logs, portes, limites).

Contrôles effectués sur source entière :

- **Constats 1–5** : file live (`QueueAdd/Prepare/Execute` réels, borne `POLICY.MaxBatch` lue, pipeline unitaire
  partagé, aucun rejeu), `settings.save` réel (modèle V1 complet, convention lue commandant preview/analyse),
  dashboard lecteur réel (inventaire borné + registre GP fusionné, null = inconnu uniquement), historique durable
  (`GpHistory` strictement lecture seule, fusion par identité), raccordement (`HostWiring.Parse` dans `Program.cs`,
  production jamais injectable, harnais à confirmation exacte) — chacun vérifié dans le code ET dans ses tests.
- **Constat 4 — journal** : vérification faite dans la source V1 (`wad/Pesto-Journal.ps1`, `wad/Pesto.Engine.Runtime.ps1`) :
  l'UI journal V1 lit `$script:LogEntries` en mémoire (plafond 1 500) ; les fichiers d'audit `Pesto_yyyy-MM-dd.log` sont
  une persistence séparée ouverte via Explorateur (`Open-AuditLog`), **jamais relue dans la liste du journal**. La ligne
  PARITY « journal = événements de session (conforme V1) » est donc exacte ; elle cite désormais les fonctions source.
- **Refus restants inventoriés** (tableau §3 d'EVIDENCE.md) : `write.unavailable` (`mutation is null`), capacités
  `enabled:false`, `host.not_windows`, `directory.unavailable`/`names.unavailable` (aucun adaptateur actif ou lecture
  incomplète), `config.missing` (pas de `--v1-root`), gardes métier (`plan.stale`, `name.taken`, `identity.changed`,
  `confirmation.invalid`, `batch.stale`…), `config.business_readonly` (périmètre V1), repli sous compte AD (écart (b)
  nommé). Aucun n'est un passe-plat constant ; les `null` rendus sont des faits non observés, affichés « — ».
- **Champs de l'adaptateur annuaire** : `PowerShellDirectoryGateway.ToComputer` ne mappe que des propriétés réellement
  lues (`DistinguishedName`, `OperatingSystem`, `DnsHostName`, `ObjectGUID`) ; fabricant/modèle/série/IP/pendingRestart =
  `null` (non observés), jamais des valeurs inventées.
- **Correction d'honnêteté** : le repli routeur `web/js/pages/_todo.js` présentait encore « plusieurspostes » comme
  « écran en cours de portage » avec fonctions « prévues », alors que les 9 écrans ont leur module (liste `UNPORTED`
  vide, web-check) — un échec de chargement du module aurait fait passer un écran porté pour non porté. Le repli est
  devenu purement défensif : « Écran indisponible », aucune liste de fonctions promises, rappel qu'aucune écriture
  n'est admise depuis ce repli.
- **Dossier de preuves** : `docs/EVIDENCE.md` — quatre états, commandes de reproduction, table des six constats
  (traitement/preuve/état), inventaire des portes, limites honnêtes, journal des lots.

Commandes et résultats (24/10, `DOTNET_SYSTEM_NET_DISABLEIPV6=true`, node 24.18.0) :

- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **166/166 — exit 0** (`logs/engine-tests-crossreview.log`)
  (répartition par classe consignée dans EVIDENCE.md §1/§5).
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4 — exit 0** (`logs/bridge-tests-crossreview.log`).
- `dotnet build src/Pesto.App/Pesto.App.csproj -c Release` → **exit 0**, 0 warning, 0 erreur (`logs/build-crossreview-app.log`).
- `node tools/tests/web-check.mjs` → **102/102 — exit 0** (`logs/web-check-crossreview.log`) — la correction `_todo.js`
  est verte aux contrôles (repli réservé au routeur, 9 modules de pages, couverture des 20 opérations).
- `node tools/tests/pack-check.mjs` → **37/37 — exit 0** (`logs/pack-check-crossreview.log`) — le premier run a **légitimement
  échoué** (`PACK REFUSÉ — web/ diffère de la source (hachiers) : js/pages/_todo.js`) parce que la sortie de build portait
  l'ancien fichier : le manifeste fermé a détecté la dérive, la reconstruction de `Pesto.App` a resynchronisé `web/`, puis
  37/37. Le contrôle de hachiers est ainsi démontré non vacant sur un cas réel.

État après lot : aucun développement portable nouveau inventé ; les six constats restent traités dans les sources ;
la **porte externe unique** demeure la checklist Windows/AD non exécutée (`docs/QUALIFICATION-WINDOWS.md`) et l'écart
(b) documenté. Pas de `ready_for_review` depuis ce job.

## Lot repli authentifié V1 — 24/10/2026 (SECURE_FALLBACK_REQUIRED.md : l'écart (b) devient un développement à réaliser)

Le superviseur a tranché : le repli V1 par tâche planifiée sous compte AD n'est pas une dépendance externe, c'est un
développement manquant que le contrat provisoire V2 peut couvrir. Port réalisé **selon les sources V1 lues en entier**
(`Pesto-Operations.ps1` `RenameComputer` 1202-1270 et `Invoke-RenameComputerTaskFallback`, `Pesto.Engine.Runtime.ps1`
`New-PestoTaskService`/`Invoke-PestoSchtasks`/`New-PestoRunOnceTaskXml`/`Get-PestoTaskRunResult`/
`Set-PestoTaskEvidence`/`Assert-PestoTaskDefinition`/`Get-PestoTaskDefinitionHash`/`New-PestoRenameTaskScript`/
`Get-PestoRemoteTaskLogTail`, `Pesto-Authentication.ps1` pour SSO vs compte explicite, `Pesto-Policy.ps1`
`ConvertTo-PestoPolicy`).

Sources ajoutées/modifiées :
- `src/Pesto.Engine/TaskFallback.cs` (nouveau) : `PestoAdCredential` (secret en mémoire, purge, `ToString` masqué),
  `ITaskFallbackCredentialSource` (mode SSO vs compte explicite, port du formulaire V1), `TaskFallbackPolicy`
  (lecture `POLICY.AllowPasswordTaskFallback` — défaut faux, seul le booléen JSON vrai active, illisible = `unknown`
  jamais vrai), `TaskFallback.Decide` (table exacte du garde V1 : distant + 5/1314 + compte explicite + politique
  vraie, jamais 1326, jamais après incertain), `NewRunOnceTaskXml` (sans déclencheur, échappé, `PT10M`),
  `DefinitionHash` (SHA-256 majuscule borné 128 Ko), `TaskEvidence` (phases Registering→Deleted, écriture atomique
  sans lien, divergence de définition = aucun lancement ni nettoyage), `PestoTaskFallbackRunner` (création→lancement→
  sonde numérique→suppression relue ; 0→20 redémarrage à planifier, 43→Entra nommé, 97 et 267008/9/11→incertain avec
  tâche **conservée** et **aucun rejeu** ; script interne port de `New-PestoRenameTaskScript`, Rename(NULL,NULL),
  aucun secret réinjecté).
- `src/Pesto.Engine.Live/TaskSchedulerComTransport.cs` (nouveau) : COM `Schedule.Service` en mémoire (port
  `New-PestoTaskService` : « Jamais /p, /rp ou secret dans un processus »), opérations fermées créer/lancer/supprimer
  dans l'espace `\Pesto_...`, suppression confirmée par relecture d'absence, COM libérés en finally, tail du journal
  cible en lecture seule (port `Get-PestoRemoteTaskLogTail`).
- `src/Pesto.Engine.Live/ConsoleAdCredentialSource.cs` (nouveau) : saisie réservée au harnais de qualification —
  identifiant + mot de passe **sans écho** + **confirmation « OUI » de l'action** ; sans console, mode session SSO et
  repli refusé ; credential purgé par l'adaptateur en finally (durée bornée à l'opération ; la préférence V1 analogue
  ne stocke que l'identifiant).
- `PowerShellMutationGateway` : constructeur élargi (source de credentials, transport, dossier de preuves — défauts
  sûrs), `FallbackPolicyState` lu du cfg.json, `Description` qui **déclare** politique lue + mode de compte + transport,
  `AfterDirectAttempt` (raccord du garde V1 après refus confirmé du renommage direct ; acquisition et purge du
  credential ; enchaînement `renameMove` → `moveAfterRename` après repli accepté), script constant : messages de refus
  qui nomment la politique sans plus jamais prétendre que le repli « n'est pas porté », op `moveAfterRename`
  (déplacement seul après repli accepté, mapping 77/89/97/32 inchangé, jamais de rejeu du renommage).
- `Program.cs` : le harnais de qualification injecte `ConsoleAdCredentialSource` (la production et le pont n'ont
  jamais accès au compte ; `HostWiring` inchangé — harnais explicite seul).

Vérifications du lot (toutes avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true`) :
- `dotnet build src/Pesto.Engine` puis `src/Pesto.Engine.Live` → exit 0, 0 warning.
- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **183/183 — exit 0** (`logs/engine-tests-fallback.log`) :
  17 nouveaux `TaskFallbackTests` (table de décision complète, lecture politique 8 cas, XML sans déclencheur sans
  secret, empreinte, split de compte, déroulement complet avec ordre register→run→probe→delete et preuves, incertain =
  tâche conservée + un seul run, échec de création = refus prouvé, divergence de définition = stop sans nettoyage,
  43/autres codes nommés, preuve inscriptible obligatoire avant tâche, échec de suppression sans inversion du
  résultat, hygiène credential (purge, ToString, sérialisation), Description déclarative, script interne port V1) ;
  `TransientAdapterParityTests.ScriptHandsTheV1PasswordTaskFallbackToTheAdapterWithoutHidingIt` remplace l'ancien test
  d'écart : le script doit nommer la politique sur chaque refus, ne plus prétendre au faux écart, ne jamais improviser
  le repli ni manipuler de secret, et exposer `moveAfterRename` sans rejeu du renommage.
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4 — exit 0** (`logs/bridge-tests-fallback.log`).
- `dotnet build src/Pesto.App -c Release` → exit 0, 0 warning (`logs/build-fallback-app.log`).
- `node tools/tests/web-check.mjs` → **102/102 — exit 0** (`logs/web-check-fallback.log`) ;
  `node tools/tests/pack-check.mjs` → **37/37 — exit 0** (`logs/pack-check-fallback.log`).
- **Non-vacuité du repli prouvée par 3 mutations** : (1) `FallbackEligibleCodes = []` (repli redevenu refus constant)
  → échec `DecisionTableIsTheExactV1Guard` ; (2) politique retombant sur `true` par défaut → échecs
  `PolicyFollowsTheV1Reading…` et `AdapterDisclosesTheFallbackState…` ; (3) suppression de la conservation de la tâche
  sur sonde non confirmée → échec `UncertainResultKeepsTheTaskAndNeverRerunsIt`. Sources restaurées, série verte.

Gardes conservés : aucune exécution PowerShell ni création de tâche réelle depuis ce job ; capacités toujours
`enabled:false` ; aucun secret en arguments CLI, logs, reçus, XML de tâche ou réponses du pont ; `HostWiring` inchangé
(harnais explicite seul, production lecture seule) ; mutex/barrières GP/reçu avant envoi intacts ; aucun fichier V1
modifié ; aucun `git push`.

## Lot divulgation du repli dans l'aperçu — 24/10/2026 (port du « control summary » V1)

Demande du lot précédent (nextLot) : exposer l'état réellement lu de `POLICY.AllowPasswordTaskFallback` et le mode de
compte dans l'aperçu du plan, comme V1 le faisait avant confirmation — `Pesto-Core.ps1:4035` (confirmation de file :
« Politique : un repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé.
Les tâches sont suivies ; aucun repli après résultat incertain. ») et `Pesto-Direct.ps1:345` (confirmation unitaire :
« Politique : le repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé.
Aucun repli sur résultat incertain. »), textes relus dans la référence figée avant codage.

Sources ajoutées/modifiées :
- `src/Pesto.Engine/MutationGateway.cs` : contrat `IMutationFallbackDisclosure` (état lu « true »/« false »/« unknown » +
  mode de compte). Le moteur n'affiche une note QUE pour un adaptateur qui l'implémente : aucun état jamais inventé.
- `PowerShellMutationGateway` : implémente le contrat (les deux propriétés lues existaient déjà — `FallbackPolicyState`
  lu du cfg.json et `FallbackAccountMode` observé de la source de credentials).
- `LiveBackend.FallbackNotes` : note rendue dans les avertissements du plan unitaire (`operation.prepare`, texte
  Pesto-Direct) et du lot (`queue.prepare`, texte Pesto-Core) — réservée aux plans contenant un renommage (le repli V1
  n'existe que pour le renommage : l'afficher sur un déplacement seul serait mensonger). Politique vraie + compte
  explicite → texte V1 mot pour mot + note « Compte de repli : compte AD explicitement saisi… mémoire seule… jamais
  après un résultat incertain » ; politique vraie + SSO → repli dit **indisponible** (raison V1, jamais dit autorisé) ;
  false → « lu « false » (défaut V1) — aucun repli… jamais activée implicitement » ; unknown → « non lu de façon fiable…
  aucun repli ». Sans adaptateur déclarant (production, simulation) : aucune note.
- `tests/Pesto.Engine.Tests/FallbackDisclosureTests.cs` (nouveau, 9 tests) : textes V1 exacts contrôlés mot pour mot
  (unitaire et file), variante fermée false et unknown (jamais « autorisé en cas de refus confirmé »), SSO jamais dit
  autorisé, déplacement seul jamais note, adaptateur muet jamais devancé, simulation et production muettes, et
  l'adaptateur réel bien raccordé au contrat (type + état lu sur fixture cfg.json).

Vérifications du lot (toutes avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true`) :
- `dotnet run --project tests/Pesto.Engine.Tests -c Release` → **192/192 — exit 0** (`logs/engine-tests-disclosure.log`).
- `dotnet run --project tests/Pesto.Bridge.Tests -c Release` → **4/4 — exit 0** (`logs/bridge-tests-disclosure.log`).
- `dotnet build src/Pesto.App -c Release` → exit 0 (`logs/build-disclosure-app.log`).
- `node tools/tests/web-check.mjs` → **102/102 — exit 0** (`logs/web-check-disclosure.log`) ;
  `node tools/tests/pack-check.mjs` → **37/37 — exit 0** (`logs/pack-check-disclosure.log`).
- **Non-vacuité prouvée par 3 mutations** : (1) texte autorisé modifié → échecs `UnitPlanCarriesTheExactV1PolicyNote…`
  et `BatchCarriesTheExactV1QueuePolicyNote` (les textes V1 sont exigés mot pour mot) ; (2) variante false/unknown
  prétendant l'autorisation → échecs `ClosedVariantWhenThePolicyIsReadFalse` et `…NotReliablyRead` ; (3) moteur
  fabriquant une note sans adaptateur déclarant → échec `AdapterThatStaysSilentIsNeverGivenWords`. Sources restaurées,
  série verte.

Gardes conservés : aucune exécution PowerShell ni écriture AD ; capacités toujours `enabled:false` ; `HostWiring`
inchangé ; aucun secret dans les notes (textes fixes sur états lus, jamais le compte ni le mot de passe) ; simulation
et production inchangées ; aucun `git push`.

## Lot accès qualification — 24/10/2026 (QUALIFICATION_PRIORITY.md : demande explicite David, remplace les restrictions VM/SSH)

Accès réel utilisé (autorisé par la demande) : SSH BatchMode `degun@192.168.1.173` (clé), VBoxManage guestcontrol sur
la SEULE VM PESTO-W11-TEST (UUID `9b2ad4f0-0506-4f58-aed2-c43ac1973516`), PowerShell 5.1 invité en EncodedCommand
UTF16LE, compte local `labadmin` via le passwordfile existant (chemin seulement — contenu jamais lu ni affiché).
Aucun service, aucun tunnel, aucune autre VM touchée, aucun `pkill`.

Preuves effectives (fichiers relus, pas des codes VBox — le `VERR_NOT_IMPLEMENTED` attendu sur stdout est ignoré au
profit du fichier relu) :
- Hôte : `hostname` = **DESKTOP-285EKHU** ; `C:\ADCC-Lab\validation\pesto-v2-20261024\identity.json` lu :
  `P111301VA765158`, domaine `labo.local`, `Joined=true`, utilisateur `labadmin`, 61 racines labo listées.
- VM : `VMState="running"` (showvminfo relu) ; guestproperties : Windows 11 10.0.26200.6584, Guest Additions 7.2.20,
  IPs 10.77.0.30 / 10.0.4.15, **session interactive `tech.pesto` connectée**.
- Sonde invitée `tools/qualification/probes/guest-identity.ps1` → `logs/qualification/guest-guest-identity.json`
  (+ copie hôte `guest-guest-identity.json`) : identité `P111301VA765158\labadmin`, `IsAdmin=false`, SessionId 0,
  PS **5.1.26100.6584** (le chemin d'adaptateur transitoire est donc présent), 61 racines inventoriées bornées.
- Sonde invitée `tools/qualification/probes/guest-webview2-v1roots.ps1` → `logs/qualification/webview2-v1roots.json` :
  **WebView2 Fixed Version 155.0.4283.62 réellement présente** sous
  `C:\Program Files (x86)\Microsoft\EdgeWebView\Application\155.0.4283.62`, signature **Valid**, signataire
  `CN=Microsoft Corporation`, émetteur `Microsoft Code Signing PCA 2024`, empreinte
  `21CA9DD6DA7C57C3A599880D17317D7BDA31899C`, `msedgewebview2.exe` SHA-256
  `93ACBCAD0B6F390AE1CE6A1DBF1E09E165520A7F1196EB22323AFA64A9BBA96B`, 916 fichiers / 909 827 702 octets.
  → Le « runtime à fournir » est résolu par une copie présente à provenance/signature vérifiées ; le pack complet peut
  l'embarquer sans bootstrapper ni faux exécutable.
- Racines V1 de référence localisées (lecture seule) : cfg.json réels sous
  `C:\PestoQual_20261018\candidate\PROD\wad\cfg.json`, `C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD\wad\cfg.json`,
  `C:\PestoVerify_20261018\repo\DEV\wad\cfg.json`, `C:\PestoVM_20261016\candidate\PROD\wad\cfg.json` — c'est le dossier
  `wad` qui sert de `--v1-root`. Aucune écriture dans ces dossiers.
- Pilote réutilisable ajouté : `tools/qualification/lab-driver.mjs` (SSH→guestcontrol→copyfrom→scp, JSON de preuve relu
  localement, échec démontré par absence de fichier, jamais par un code VBox) + `tools/qualification/probes/`.

Limites honnêtes de ce lot : aucune mutation AD, aucun essai GUI interactif, aucun pack assemblé à ce stade — la
signature WebView2 et les identités sont des faits relus ; les sections 1–3 de `docs/QUALIFICATION-WINDOWS.md` restent
à exécuter avec le pack déployé (prochain lot). `labadmin` invité est non élevé (IsAdmin=false) et hors session
interactive : les essais GUI et les écritures élévation-dépendantes devront cibler la session `tech.pesto` existante
avec préparation préalable, sans jamais activer d'unattended.

## Non vérifié (à ne pas déclarer comme fait)

- Exécution de l'interface dans WebView2, pack complet avec runtime WebView2 fixe, qualification Windows/AD : non
  faites (aucun Windows ni AD depuis ce job). Ordre d'exécution et preuves attendues : `docs/QUALIFICATION-WINDOWS.md`
  (tout y est non fait à ce jour) ; assemblage/vérification du pack : `docs/PACKAGING.md`.

## Lot 24/10 18:38 UTC — diagnostic instrumenté du vérificateur de pack (recadrage VM_PACK_REVIEW_REQUIRED.md)

Objectif superviseur : réparer le PILOTE et ses preuves d'exécution (pas les règles de validation), instrumenter
chaque point bloquant, nouveaux IDs/chemins, puis poursuite GUI/AD.

### Exécuté et relu (preuves)
- `verify-deploy.mjs` réécrit, run id `v3` : heartbeat `verify-phase3.json` (phase + chemin exact) écrit AVANT chaque
  opération potentiellement bloquante (dont chaque `Get-FileHash`), `try/catch/finally` → statut terminal
  COMPLETED/FAILED + ErrorRecord, `Start-Process` avec `-RedirectStandardOutput/-RedirectStandardError` vers fichiers,
  `ProgressPreference/VerbosePreference/WarningPreference=SilentlyContinue`, enregistrement PID+création+chemins.
- `start` → PID invité **2924** créé 2026-10-24T17:58:43Z (cmdline relue : `powershell.exe -NoProfile -NonInteractive
  -ExecutionPolicy Bypass -File C:\Windows\Temp\pesto-v2-qual\verify-pack3.ps1`), `StartedProc=true`.
- Instantanés `status` (JSON invité relu copyfrom/scp) : boucle SHA256 **terminée** (loop-done → enumerating → exe-hash
  → package-read → **final-write**), puis gel à `final-write`. Entre deux sondes (~25 s) : **CPU 21,48 s → 142,62 s**
  (multi-cœurs) et **WorkingSet 349,5 Mo → 2874,6 Mo** en croissance, `Responding=true`. Preuve d'une explosion
  CPU/mémoire, pas d'une attente réseau ni d'un pipe.

### Cause localisée (confirmée par reproduction)
- Gel dans l'ultime `ConvertTo-Json -Depth 12` du dictionnaire composite `[ordered]` du résultat (récursion
  incontrôlée de ConvertTo-Json sur OrderedDictionary à profondeur élevée dans Windows PowerShell 5.1).
- Hypothèses écartées par preuve : (a) hachage lent — sonde attachée `diag-verify-tail.json` : fichiers 1195→1249
  hachés en **1 s** (max 171 ms, tous ok) ; (b) « révocation réseau » via `Get-AuthenticodeSignature` — absent du
  script ; (c) pipe stdout orphelin — gel persistant malgré redirection + ProgressPreference.
- Le dernier heartbeat `Checked=1200` des anciens vérificateurs venait de ce que 1249 n'est pas multiple de 50 : la
  boucle avait fini, le gel était déjà dans le `ConvertTo-Json` final (cohérent avec verify-pack/verify-pack2).

### Correction (règles de validation inchangées)
- Résultat final assemblé **à la main** (`Esc`/`ArrJson`, sans `ConvertTo-Json` composite) : déterministe. Contrôles
  conservés à l'identique (SHA256 par ligne, absences, hash exe, package.json, `Checked==Total==1249`, fixed runtime).

### Blocage externe en cours (action superviseur requise)
- Le PID **2924** (version `-Depth 12` d'avant correction) tourne toujours et sature la mémoire invitée ; depuis,
  `VBoxManage guestcontrol run` échoue de façon reproductible en **VERR_DUPLICATE** (agent invité dégradé) alors que
  le côté hôte va (`VMState="running"`). Aucune nouvelle exécution invitée n'est possible.
- Conformité : 2924 n'a **pas** été arrêté par le job (pas d'arrêt global autorisé ; VM_PACK_REVIEW_REQUIRED.md demande
  l'arrêt ciblé par le superviseur). Arrêt ciblé demandé : PID 2924, cmd ci-dessus, création 17:58:43Z, seul powershell
  de ce run (le PID 7772 était la sonde probe-pid, déjà terminée).
- Le pilote corrigé n'a donc **pas** encore pu être exécuté de bout en bout : aucune preuve verte, pack non déclaré vérifié.

## Lot 24/10 21:40 UTC — VRAIE preuve verte du vérificateur de pack (reprise VM_RECOVERY_20261024.md)

Contexte : VM récupérée par reboot Windows normal (19:28:26Z), guestcontrol de nouveau fonctionnel, PID 2924 absent.
Preuves v3 antérieures copiées intactes dans `work/logs/qualification/archive-pre-recovery-20261024/` avant tout écrasement.

### Exécution réelle du pilote corrigé (commandes + résultats relus)
- `node tools/qualification/verify-deploy.mjs start` (node v24.18.0) → `scpCode=0`, `copyCode=0`, invité
  **PID 3960**, `StartedProc=true`, Started 2026-10-24T19:35:41Z (preuve `logs/qualification/verify-start3.json`).
- `node tools/qualification/verify-deploy.mjs status` (~45 s après start) → **done=true, ok=true, exit=0** :
  `Status=COMPLETED`, **Checked=Total=1249**, Mismatched/Missing/Malformed **vides**, `FilesPresent=1250`,
  `ExeSha256=93ACBCAD0B6F390AE1CE6A1DBF1E09E165520A7F1196EB22323AFA64A9BBA96B` (== attendu),
  `PackageJson` avec `"webview2Runtime":"fixed"`, **ElapsedSec=21**.
  Verdict écrit dans `logs/qualification/pack-deployed-verify.json` : **`verdict: "OK"`**.
- Le décalage 1250 vs 1249 est attendu et expliqué : `tools/pack/make-pack.mjs:145` exclut explicitement `SHA256SUMS`
  du manifeste (un fichier ne peut pas contenir son propre hash) → `FilesPresent` = 1249 contrôlés + SHA256SUMS lui-même.
- Le correctif anti-gel (assemblage manuel `Esc`/`ArrJson` au lieu de `ConvertTo-Json -Depth 12` composite) est
  **validé en exécution réelle** : terminal COMPLETED en 21 s, aucun gel (première preuve verte à ce jour).

### Garde d'autonomie ajouté (VM_RECOVERY_20261024.md §2)
- Nouveau mode `stop` dans `verify-deploy.mjs` : arrêt ciblé du SEUL vérificateur, identité exigée avant tout arrêt
  (`Win32_Process` : `Name=powershell.exe` ET `CommandLine` contenant `verify-pack3.ps1`, PID lu du fichier de start ;
  `CreationDate` consignée ; annulation **REFUSED** si identité différente ; aucun kill global ; sérialisation
  strictement primitive). `status` rapporte désormais `Started` pour mesurer la borne 180 s / 512 Mo.
- Test réel du chemin d'identité : `stop` sur PID 3960 déjà terminé → `{"Status":"ALREADY_GONE","Pid":3960}`, exit=0.
  Aucun processus n'a été tué par le job pendant ce lot (le vérificateur s'est terminé seul en 21 s).

### Limites honnêtes
- Ce lot prouve l'**intégrité du pack déployé** (hachages + exe + fixed runtime déclaré), rien d'autre : ni lancement
  de l'application, ni GUI, ni AD, ni parité production. La signature du fixed runtime 155.0.4283.62 reste prouvée
  côté hôte (`webview2-hostcheck.json` Valid), non re-testée dans l'invité sans réseau.

## Lot 24/10 22:11–22:40 UTC — correction du helper COMMUN de sérialisation (SERIALIZATION_REVIEW_REQUIRED.md)

Contexte : le vérificateur du lot 28 avait fini (lot 28, 19:50Z) mais `deploy-pack.mjs` avait **réintroduit** la voie
dangereuse : `$pkg=(Get-Content -Raw)` dans `$result`, puis `RESULT_TAIL` → `ConvertTo-Json -Depth 10`. Le texte lu par
`Get-Content` est un `System.String` **enrichi par le provider** (PSPath/PSParentPath/PSChildName/PSDrive/PSProvider/
ReadCount/Length) : `-Depth 10` descend dans `PSDrive` (DriveInfo) et `PSProvider` (ProviderInfo) et sature la mémoire
(PID 4740, 2681 Mo, ~20 min). Ce lot corrige la **source** et le **helper partagé**, pas une énième exception locale.

### 1. Ce qui a été changé (une seule source de vérité)
- **`tools/qualification/ps-strict.mjs` (nouveau)** — helper commun livré sous forme de **fichier à adresse de contenu**
  (`pesto-strict-<sha256[0:12]>.ps1`, déposé une fois par process sur l'hôte puis dans l'invité, **dot-sourcé** par
  chaque script ; l'inliner dans l'`EncodedCommand` ferait sauter la limite de ~8191 caractères de cmd.exe) :
  - `ConvertTo-PestoJson` : n'accepte **que** primitives, tableaux et dictionnaires de données. Tout objet .NET non
    reconnu est rendu par `"[PESTO_NON_DATA_TYPE:<type>]"` — **aucune exploration de graphe d'objets n'est possible**.
    Les conteneurs sont testés **uniquement par `-is`** (voir bug corrigé ci-dessous) ;
  - `Get-PlainText` : lecture `.NET` (`File.ReadAllBytes` + décodage UTF-8/UTF-16 BOM) → **aucun objet enrichi** ;
  - gardes : `Get-PestoGuard` / `Assert-PestoGuard` (borne **180 s**, **512 Mo** sur le PID invité), `Write-PestoSelf`
    (auto-enregistrement PID + nom process + `CreationDate` + owner + script) pour l'annulation ciblée.
- **`lab-driver.mjs`** : `RESULT_TAIL` remplacé par `resultTail` (écrit via `Write-PestoResult`, `.NET WriteAllText`,
  sans BOM) ; `runGuestJson`/`runGuestJsonFile` **bornés à 180 s** (tout `timeoutMs` supérieur est ramené à la borne,
  plus aucun `timeoutMs: 1200000`) ; `cancelOwnRun(name)` + CLI `cancel <name>` ; **archivage avant purge**
  (`archiveGuestJson` → copie horodatée invitée + rapatriement hôte/Spark + `archive/index.jsonl` avec UTC réel).
- **`deploy-pack.mjs`** : `PackageJson` lu par `Get-PlainText` ; `SHA256SUMS` lu par `Get-PlainText` puis `-split` ;
  `Assert-PestoGuard` dans la boucle de hachage ; timeout invité 180 s ; **`--reuse`/`--check`** : les hashes du tar
  sont relus côté Spark/hôte/invité et les transferts de 1 Go sont **sautés s'ils sont identiques**, sans ré-extraire
  le pack déjà en place.
- **`verify-deploy.mjs`** : suppression de l'exception locale `Esc`/`ArrJson` (4ᵉ exception manuelle) au profit du
  **même** `ConvertTo-PestoJson` pour phase/progress/final ; lectures en `Get-PlainText` ; `Assert-PestoGuard` par tour.
- **`smoke-pack.mjs`**, **`fetch-runtime.mjs`** : mêmes helper et lectures ; plus aucun `ConvertTo-Json` composite.

### 2. Bug RÉEL trouvé par la preuve Windows (et corrigé)
La première exécution de la preuve a révélé que `ConvertTo-PestoJson` **pliait un tableau d'un seul élément en son
élément** (`@('x')` → `"x"`, `@()` → `null`). Cause : l'**énumération de membres** de PowerShell détourne `.GetType()`
sur une collection à un seul élément vers l'élément (`@('x').GetType()` renvoie `System.String`, `@().GetType()`
renvoie `null`). Preuve invitée `logs/qualification/probe-serial.json` (avant) : `JsonOne:"\"x\""`, `JsonEmpty:"null"`.
Après correction (tests de conteneurs par `-is` uniquement) : `JsonOne:"[\"x\"]"`, `JsonEmpty:"[]"`,
`JsonDict:"{\"K\":[\"x\"]}"`, `JsonNested:"{\"K\":[\"x\"]}"` — même preuve, après correctif.

### 3. Preuve Windows ciblée sur le cas `PackageJson` (`tools/qualification/serialization-proof.mjs`)
Exécution réelle sur le **vrai** `C:\PestoV2_Qual_20261024\Pesto-2.0.0-DEV\Pesto.package.json`, strictement en lecture,
**sans jamais rejouer le gel** (aucun `ConvertTo-Json -Depth 10` sur l'objet enrichi). Verdict **OK**, 11/11 contrôles,
preuve `work/logs/qualification/ser-diag-v4.json` (1108 o, `Utc` invité 2026-10-24T22:21:50Z) :
- enrichissement **confirmé** côté `Get-Content -Raw` : `Enrichi_PropertiesEts` = PSPath, PSParentPath, PSChildName,
  PSDrive, PSProvider, ReadCount, Length (type `System.String`, 139 caractères) ;
- chemin corrigé : `Get-PlainText` → `System.String` **sans aucune propriété provider** (`Correct_PropertiesEts` =
  `["Length"]`, propriété intrinsèque .NET légitime), 139 caractères ;
- `PackageJson` **JSON parseable**, **champs préservés** et **identique octet à octet** à la copie Spark
  (`dist/Pesto-2.0.0-DEV/Pesto.package.json`, clés `packName, version, channel, entryPoint, webview2Runtime`) ;
- **aucune expansion provider** : le fichier preuve ne contient `"PSDrive":`, `"PSProvider":`, `"PSPath":`,
  `"PSParentPath":`, `"PSChildName":`, `"ReadCount":` ni `"Length":` (0 occurrence chacun) ;
- objets hostiles **remplacés par balise** : `PSDriveInfo`, `ProviderInfo`, `Process`, `FileInfo` (+ `PSDriveInfo`
  imbriqué) → 5 balises `[PESTO_NON_DATA_TYPE:…]`, aucune récursion ;
- **fin rapide** : `Guard.ElapsedMs=459`, `WS_MB=94,5`, `Pid=9200`, bornes 180 s / 512 Mo déclarées ; paroi pilote
  ~7 s.

### 4. Bornes 180 s / 512 Mo et annulation du propre PID (exigence §2)
`tools/qualification/cancel-selftest.mjs` (nouveau) :
- `sleep` + `cancel` : le processus invité **vivant** (PID 3188, `powershell.exe`, création 10/25/2026 00:28:50,
  owner `P111301VA765158\labadmin`, script vérifié) a été arrêté → `{"Status":"STOPPED","Reason":"identite verifiee,
  arret du pid enregistre par ce pilote"}` ; le run annulé s'est terminé `runCode=126` sans JSON (preuve
  `logs/qualification/cancel-cancel-test-v4.json`) ;
- `refuse` : enregistrement **falsifié** visant un `svchost.exe` (PID 992) → `{"Status":"REFUSED","Reason":"nom de
  processus different","Found":"svchost.exe"}` et cible **toujours vivante** (`StillAlive=true`) : le contrôle
  d'identité n'est pas décoratif, **aucun processus étranger n'a été touché** ;
- aucun `pkill`/`killall`/`Stop-Process` global utilisé dans ce lot.

### 5. Vérification du pack ACTUEL, sans redéploiement de 1 Go
- Original du lot 28 **copié intact** dans `v2/logs/qualification/archive-lot28-2026-10-24T22-33-33Z/` avant toute
  réécriture. **Constat d'honnêteté** : le `pack-deployed-verify.json` revendiqué par le lot 28 **n'existait pas** sur
  le disque à l'ouverture du lot ; il a été régénéré par la présente exécution, et le résultat du lot 28 n'est **pas**
  revendiqué comme résultat de la nouvelle version.
- `node tools/qualification/deploy-pack.mjs dist/Pesto-2.0.0-DEV --reuse --check` (22:37Z) : hash du tar local
  `311723FF741052F74AE541889975E158D256699DE6B1C4BBCDFCF6616CD0E961` (1 036 288 000 o) **égal** aux copies hôte et
  invitée relues → **scp et copyto sautés**, aucune extraction, pack invité laissé en place.
- `node tools/qualification/verify-deploy.mjs start` (22:34:10Z, invité **PID 4496**) puis `status` (22:34:57Z) :
  **`verdict: "OK"`**, `Status=COMPLETED`, **Checked=Total=1249**, Mismatched/Missing/Malformed vides,
  `FilesPresent=1250` (SHA256SUMS exclu du manifeste par `tools/pack/make-pack.mjs:145`),
  `ExeSha256=93ACBCAD0B6F390AE1CE6A1DBF1E09E165520A7F1196EB22323AFA64A9BBA96B` == attendu,
  `PackageJson` avec `"webview2Runtime":"fixed"`, **ElapsedSec=18** — preuve réellement écrite :
  `v2/logs/qualification/pack-deployed-verify.json` (628 o).

### 6. Non-régression portable
- `node --check` sur les 7 modules `tools/qualification/*.mjs` ;
- `node tools/tests/web-check.mjs` → **102/102** ;
- `dotnet run --project tests/Pesto.Engine.Tests -c Release` (avec `DOTNET_SYSTEM_NET_DISABLEIPV6=true`) →
  **192 réussis, 0 en échec**. (Note : `dotnet test` sort 0 **sans exécuter** ce projet — c'est un Exe à harnais
  maison, il faut `dotnet run`.)

### 7. Limites honnêtes de ce lot
- Ce lot valide le **pilote** (sérialisation sûre, bornes, annulation ciblée, archivage) et l'**intégrité du pack
  déployé**. Il ne qualifie **ni** le lancement de `Pesto.exe`, **ni** la GUI, **ni** l'AD, **ni** la parité V1.
- La correction est prouvée sur le chemin `PackageJson` (le cas gelé) + un jeu d'objets hostiles ; elle n'est pas une
  qualification GUI/AD. `Program.ShowFatal` (modification du lot précédent) reste à fumer côté invité.
- Le helper invité est identifié par contenu : `pesto-strict-bd1f85641e59.ps1`, et le **nom est le sha256 du fichier
  réellement déposé** — vérifié sur l'invité (`Get-FileHash` = `BD1F85641E59E6B902FBAC31C9FF0C0788CFA8CCD4F87C9ECCD86CF608C5450B`,
  7797 octets, `NomEgalHash=true`, preuve `logs/qualification/helper-hash.json`, 22:49:19Z). Les preuves de ce lot
  portent sur cette version, pas sur une version antérieure.

## Lot 24/10 23:05–23:29 UTC — SMOKE-PACK RÉEL du pack déployé (nextLot du lot « helper commun »)

Contexte : aucun redéploiement (défense de rejouer 1 Go identique). Le pack invité est le tar
`311723FF741052F74AE541889975E158D256699DE6B1C4BBCDFCF6616CD0E961` déjà vérifié identique Spark/hôte/invité.

### 1. Identité de la source déployée AVANT fumer (doute levé, pas supposé)
Le hash `93ACBCAD…` consigné par `verify-deploy` est celui de `runtime\webview2\msedgewebview2.exe`
(`deploy-pack.mjs:160`), pas de `Pesto.exe` — l'appeler « ExeSha256 » était un piège. Le correctif `ShowFatal` vit
dans `Pesto.dll` (l'`exe` n'est que l'apphost, identique avant/après correctif). Preuve invitée relue
(`logs/qualification/guest-pesto-dll-check.json`, 23:06:38Z) : `Pesto.dll` invité =
`297B8F70907B705637925917CC4E85811BE18FEE337EFA373160769DAC768C8D` == `dist/Pesto-2.0.0-DEV/Pesto.dll` == extrait
du tar local (`logs/tarcheck-lot29/`) ≠ `05796a6b…` du pack pré-fixe conservé `dist/Pesto-2.0.0-DEV.pre-fatal-fix/`.
→ l'invité exécute bien le build corrigé ; aucune ré-extraction nécessaire.

### 2. Premier passage réel (23:07Z) : 2/3 — et un VRAI diagnostic
- `args-refus` **ok** : exit 2, stderr « Options acceptées : --simulation ; … », aucun chemin de disque.
- `runtime-absent` **ok** : copie extraite du tar sans `runtime\webview2` → exit 2, stderr
  « Le moteur WebView2 fixe manque … aucune installation automatique », jamais de repli navigateur, copie supprimée.
- `demarrage` **échec** : `Windows: null`, 6 webviews vus. Trois causes distinctes diagnostiquées une par une :
  1. `diag-smoke-start1` (run=33, aucun JSON) : lecture `ReadAllBytes` de stderr **pendant** que Pesto tenait le
     handle → exception hors try → le tail n'écrivait pas la preuve. Script rejoué avec try/catch global.
  2. `diag-smoke-start2/3` : le handle de redirection stderr est **hérité par les webviews enfants** — même après
     `Stop-Process` sur Pesto, la lecture échouait en sharing violation. Corrigé : arrêt Pesto **puis** webviews,
     lecture **partagée** `FileShare.ReadWrite` (`diag-smoke-start5.json`, Err=OK).
  3. Fond réel : la fenêtre **« Pesto v2 — DEV — Simulation » est bien créée** (handle + titre, classe
     `WindowsForms10.Window.8…`) avec 7 `msedgewebview2.exe` chargés depuis `runtime\webview2` du pack, process
     vivant 40 s, stderr vide — mais `IsWindowVisible=false` pour TOUTES les fenêtres.

### 3. Contrôle qui disculpe le produit et inculpe le harnais
`diag-minform-visible.json` (23:25:14Z) : un **formulaire WinForms minimal** (`New-Object Windows.Forms.Form`,
`Show()`, DoEvents, 2 s) lancé par le même guestcontrol renvoie `SessionId=0`,
`VisibleAfterShow/AfterDoEvents/After2s = false/false/false`. En SessionId 0 sans bureau interactif, AUCUNE fenêtre
n'est jamais visible — la visibilité n'est pas un bug Pesto mais une limite du harnais console. La fenêtre visible,
rendue et navigable est qualifiée au lot GUI interactif tech.pesto (docs/QUALIFICATION-WINDOWS.md §2).

### 4. Critères du scénario C ajustés HONNÊTEMENT (smoke-pack.mjs)
Énumération de TOUTES les fenêtres du PID (Visible consigné, plus filtré) ; jugé sur : fenêtre créée avec le titre
exact + ≥1 webview dont le Path est sous `PACK\runtime\webview2` (fixed runtime réellement chargé) + process vivant
+ stderr vide. Nettoyage avant/après limité aux processus **au propre** dont `Path` est sous le pack (les fuites
`Pesto` PID 6300/7700 des tentatives antérieures ont été arrêtées par chemin, `PestoAfterKill=[]`,
`WebviewAfterKill=[]`). Constantes mortes supprimées (dont `EXPECTED_EXE_SHA` qui portait le hash du webview, piège
de lecture).

### 5. Passage final vert (23:27–23:28Z) — `v2/logs/qualification/smoke-pack.json`, verdict OK, exit 0
- `args-refus` : Exit=2, message d'accueil des options sur stderr, **le correctif `Program.ShowFatal` est prouvé
  dans l'invité** — comparaison avec la preuve du gel d'avant correctif (`diag-smoke-args3.json`, 20:08Z :
  APPCRASH `0xe0434352` InvalidOperationException MessageBox en mode non interactif).
- `runtime-absent` : Exit=2, refus sans repli, copie nettoyée (`NoRuntimeDeleted=true`).
- `demarrage` : `SessionId=0`, `AliveAtEnd=true`, fenêtre « Pesto v2 — DEV — Simulation » créée, **7 webviews depuis
  le fixed runtime du pack**, `Stderr=""`, nettoyages vides. Guard invité 6,8 s / 94,3 Mo (bornes 180 s / 512 Mo).

### 6. Non-régression portable
`node --check` sur les 7 modules `tools/qualification/*.mjs` ; `node tools/tests/web-check.mjs` → **102/102** ;
`dotnet run --project tests/Pesto.Engine.Tests -c Release` (`DOTNET_SYSTEM_NET_DISABLEIPV6=true`) →
**192 réussis, 0 en échec**.

### 7. Limites honnêtes de ce lot
- SessionId 0 : ce lot prouve **création** de fenêtre + chargement du fixed runtime + refus non interactifs propres,
  PAS le rendu ni la navigation — c'est précisément le lot GUI interactif tech.pesto qui reste ouvert.
- Le texte stderr invité arrive avec des accents remplacés par `?` (codepage console du canal redirecté) : cosmétique,
  jugé sur les motifs « Options acceptées »/« WebView2 fixe manque » ; le texte exact est prouvé côté source.
- Aucune écriture AD, aucun autre processus touché (arrêts limités aux chemins du pack), aucune autre VM, aucun
  redéploiement 1 Go, aucun git push.

## Lot 25/10 02:xx–03:xx UTC — GUI HANDOFF : mapping AZERTY, watcher sécurisé, layout accueil (GUI_HANDOFF_20261025.md §1–§3)

### 1. Mapping AZERTY du pilote (gui-session1.mjs) — cause racine prouvée
La capture supervisor-gui-current.png (« CM\Te,p\w:bat » au lieu de « C:\Temp\w.bat ») s'explique exactement par
trois entrées erronées de l'ancienne table, reconstituées caractère par caractère :
- ':' cherché sous Shift+0x27 → tapait « M » (0x27 est la touche m en français) ;
- 'm' à 0x32 → tapait « , » (0x32 est la touche virgule) ;
- '.' à 0x34 → tapait « : » (0x34 est la touche deux-points, sans shift en français).
Table corrigée selon la disposition 0000040C et les scancodes ÉPROUVÉS du handoff : m=0x27, ,=0x32, ;=0x33,
:=0x34 sans shift, .=Shift+0x33, /=Shift+0x34, !=0x35, "&é'(-è_çà) sur 0x02..0x0c sans shift (chiffres = même
touches avec shift), =/+, sur 0x0d, <=touche 102 (e0 56), ù=0x28, ²=0x29. AltGr en RMENU seul (e0 38), forme
validée par la séquence antislash du handoff ; la forme Ctrl+Alt (e0 1d e0 38) de l'ancien pilote est écartée.
Les caractères non établis (ex. « ^ ») lèvent une erreur explicite au lieu de taper un code deviné.
Preuve portable : `node tools/tests/azerty-check.mjs` → **21/21**, dont la séquence complète
« c:\temp\g.bat après Ctrl+A » **identique octet à octet** à la séquence éprouvée du handoff
(2e ae 34 b4 e0 38 09 89 e0 b8 14 94 12 92 27 a7 19 99 … 14 94). Ce test a lui-même découvert l'écart
AltGr RMENU vs Ctrl+Alt sur le chemin backslash, corrigé dans le pilote.

### 2. Watcher session 1 (watch.ps1 généré) — arrêt ciblé et canal de validation de frappe
Conformément à GUI_HANDOFF §2 : `KILL_PESTO` ne fait plus `Get-Process -Name Pesto | Stop-Process -Force`
(interdit) ; il cible par `Get-CimInstance Win32_Process` la triple conjonction nom Pesto.exe + ExecutablePath
sous C:\PestoV2_Qual_20261024\* + SessionId de l'agent, arrête par PID et consigne `KillTargets`. `CLOSE_SNIP`
(fermeture SnippingTool, programme utilisateur) est **supprimé**. Les commandes hors liste fermée sont refusées
(`commande inconnue refusee` dans CmdErr). Nouvelle commande `READ_EDIT` : relit le champ Edit du dialogue
ayant le focus clavier (repli : fenêtre « Exécuter ») via UIA ValuePattern → `EditText`/`FocusWin` dans
status.ndjson et latest.json. `LAUNCH_PESTO` refuse la multiplication d'instances (renvoie `deja_en_cours`) et
consigne `LaunchedPid` ; chaque tick consigne `PestoPids` (PID/chemin/session de l'instance interactive).
Le pilote expose `run <texte>` : Ctrl+A (remplace le contenu du dialogue Exécuter — aucune saisie accolée ne
peut reconstituer une ligne MRU type shutdown), frappe en une rafale, capture d'écran, puis relit le champ par
READ_EDIT et **n'appuie jamais sur Entrée** ; le juge est `match = (EditText === texte attendu)`.
`collect()` corrigé : il lisait des snap-NNN.json que le watcher ne produit pas (résultat toujours vide sans
erreur) ; il rapatrie désormais status.ndjson/latest.json réellement écrits.

### 3. Défaut visuel de l'accueil confirmé et corrigé (GUI_HANDOFF §3)
Symptôme de la capture (quatre cartes chiffrées anormalement étroites, texte coupé, grand espace inutilisé)
reproduit statiquement : `.grid` est en `repeat(12, minmax(0,1fr))` (layout.css:154) et le gabarit `kpiCard`
n'avait **aucune classe span** → chaque carte occupait 1/12 de la largeur, les 8/12 restants inutilisés.
Toutes les autres grilles des pages utilisaient déjà span-5/7/6 — seule la rangée KPI était fautive.
Correctif : `span-3` sur chaque carte (4 × 3 = ligne pleine ; responsive 1400px → 2×2, 900px → pile, déjà
câblés pour span-3 dans layout.css). Test de régression ajouté à web-check (gabarit kpiCard sans span → FAIL).

### 4. Non-régression portable de ce lot
`node --check` sur les 7 modules tools/qualification + tools/tests ; `node tools/tests/azerty-check.mjs` →
**21/21** ; `node tools/tests/web-check.mjs` → **103/103** (nouveau contrôle span-3 inclus) ;
`dotnet run --project tests/Pesto.Engine.Tests -c Release` (`DOTNET_SYSTEM_NET_DISABLEIPV6=true`) →
**192 réussis, 0 en échec** (C# non modifié par ce lot, exécuté comme contrôle).

### 5. Limites honnêtes de ce lot
- Le PS généré (watch.ps1) est relu et validé par inspection du fichier produit (aucun PowerShell sur ce poste
  Linux pour un parse AST) ; le script complet a déjà tourné sur l'invité dans cette forme, les changements sont
  localisés au bloc commandes et aux champs ajoutés.
- La correction du mapping est prouvée contre la séquence éprouvée du handoff, pas encore ré-injectée sur la
  console réelle : la qualification effective des neuf pages, thèmes, Ctrl+B/Ctrl+K, pont et erreurs dans la
  fenêtre ouverte (étape §3 du handoff) reste le prochain lot, avec le watcher d'abord déployé pour que
  `run`/READ_EDIT puissent juger la frappe.
- Aucun arrêt de processus hors pack, aucune écriture hors C:\Temp, C:\Users\Public\pesto-gui et dossiers de
  preuve, aucune mutation AD, aucun git push.
