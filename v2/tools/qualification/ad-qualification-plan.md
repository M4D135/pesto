# Qualification AD bornée — développement du 25/10/2026

Statut : sources préparées, **aucune nouvelle exécution Windows/AD ni compilation ni test dans ce lot avant commit/push**, conformément à la priorité de David. Le binaire et les preuves devront porter le SHA du commit effectivement poussé. Les tests de fixtures restent distincts de la qualification AD.

## Périmètre et pilote

Seul l’orchestrateur contrôle Windows : Spark → SSH BatchMode `degun@192.168.1.173` → VM `PESTO-W11-TEST`, UUID `9b2ad4f0-0506-4f58-aed2-c43ac1973516`. Le harnais vérifie le UUID BIOS Windows et le nom exact avant toute lecture AD. Un éventuel UUID BIOS différent de l’UUID VBox est un blocage à résoudre par une observation indépendante, jamais une raison de retirer la garde. Aucun accès DC, autre VM, service, tunnel, snapshot ni changement de compte partagé.

`ad-harness/Pesto.AdQualification.csproj` référence les vrais `Pesto.Engine` et `Pesto.Engine.Live`, utilise `PestoBackend.CreateLive`, les gateways PowerShell et leurs reçus durables. Aucun mock ni réponse fabriquée. Une invocation n’exécute qu’une action ; pas de redémarrage, sortie de domaine, suppression, réparation ou retour automatique. Les programmes existants `lab-driver.mjs` et `gui-session1.mjs` restent les transports contrôlés par l’orchestrateur.

Après push seulement :

```sh
DOTNET_SYSTEM_NET_DISABLEIPV6=true ~/.dotnet/dotnet run --project v2/tests/Pesto.Engine.Tests -- LiveProductionSafetyTests
DOTNET_SYSTEM_NET_DISABLEIPV6=true ~/.dotnet/dotnet run --project v2/tests/Pesto.Engine.Tests -- MutationAdapterTests
DOTNET_SYSTEM_NET_DISABLEIPV6=true ~/.dotnet/dotnet publish v2/tools/qualification/ad-harness/Pesto.AdQualification.csproj -r win-x64 --self-contained true -c Release -o v2/artifacts/ad-harness
```

Puis copier le répertoire publié dans la seule VM et exécuter `Pesto.AdQualification.exe C:\chemin\request.json` depuis un contexte de labo élevé. `request.example.json` doit être renseigné avec **les valeurs observées** ; ses marqueurs sont volontairement inutilisables pour une mutation. `explicitCredential:true` ouvre le dialogue Windows natif du même fournisseur que Pesto. Le secret reste en mémoire DPAPI CurrentUser, jamais dans request.json, stdout, fichiers ou arguments. L’option n’est utilisable que dans la session interactive. Le compte SSO doit avoir les droits effectivement nécessaires, sinon le refus est une preuve, pas une réussite.

L’identité locale, le SHA du cfg, chaque réponse moteur, le plan, le plan de retour, le reçu moteur et durable (avec SHA), les snapshots AD par GUID (DN/protection/UAC) et l’état local après sont écrits dans un **nouveau répertoire unique**. Aucun fichier précédent n’est remplacé. Codes du pilote : 0 lecture/préparation ou succès, 10 redémarrage requis, 20 refus/incertain, 2 garde/lecture/erreur. Lire les JSON, pas seulement le code du pilote. Un reçu `sent`, `uncertain` ou manquant arrête la séquence et exige des observations indépendantes ; aucune relance automatique.

## Ordre concret

1. Relever sur la VM le nom, UUID BIOS, domaine, nom actif/configuré, compte et élévation, bootUtc, GUID/OU/protection du poste et du canari. Relever sans modifier l’état des barrières GP, tâches Pesto existantes et la source V1 locale. Conserver le SHA du cfg sans le contenu. Identifier deux OU **déjà autorisées et réellement résolues par Pesto**. Ne pas créer de topology AD pour rendre le test vert.
2. Requête `action:read`, `execute:false` : session, paramètres, sites, services, diagnostic et inventaire réel. GUI réelle en parallèle uniquement sous le contrôle de l’orchestrateur. Lire et comparer les valeurs avec AD. Tester `names.preview` par préparation de renommage : type/site/service issus du cfg, nom calculé puis relu libre, jamais saisie d’un nom improvisé.
3. `action:negative`, GUID et OU exacts du canari, destination observée : jonction d’un autre poste refusée, renommage sans aperçu refusé, OU étrangère refusée, mauvaise confirmation refusée. Aucune mutation native dans cette phase.
4. `action:move`, canari protégé, `expectedGuid` et `expectedSourceOu` exacts, `targetOu` autorisée. Premier passage `execute:false`; après revue du plan de retour, passage `execute:true`, `confirmation:"EXECUTE PESTO CANARY"`, `returnPlan` concret. Attendu 30 + statut succeeded, même GUID, destination et protection identique. Retour = **nouvelle requête** source/destination inversées après relecture ; jamais réutilisation du plan. Même-OU = refus 33, aucune mutation.
5. `action:rename`, cible uniquement le nom actuel de la VM et GUID relu, aperçu calculé avant opération. Attendu 20/pendingRestart, nom configuré = nom calculé, nom actif encore ancien ; le pilote ne redémarre pas. L’orchestrateur redémarre **cette VM seulement**, puis relève nom actif, GUID, domaine, canal sécurisé, bootUtc changé et reçu durable. Retour au nom initial : plan distinct expliqué et autorisé ; ne jamais réutiliser un nom déjà occupé ni remplacer l’identité AD.
6. `action:renameMove` vers une autre OU/site observée, aperçu lié au poste. Attendu 77 avec GUID, nouveau nom, destination et protection tous confirmés, redémarrage requis. 89 = renommage accepté mais déplacement différé/non tenté/échoué ; programmer uniquement le déplacement après relecture. 97/32 = arrêt, réparation manuelle documentée, pas de rejeu.
7. Jonction en dernier : l’orchestrateur prépare d’abord un retour explicite et la possibilité de reprendre le compte local, puis effectue la sortie de domaine autorisée sur cette VM, redémarre et relève état workgroup et ancien objet AD **sans le supprimer**. Le nom courant peut encore correspondre à l’ancien compte AD : `join.alreadyJoined` doit alors rester un refus ; prévoir un nom local temporaire libre et autorisé avec redémarrage avant Pesto. Le calcul `names.preview` live exige le compte AD explicite utilisable depuis workgroup. Le pilote vérifie libre le nom calculé, prépare puis exécute une seule fois : reçu Running avant le renommage local et Add-Computer, 10/pendingRestart attendu. Redémarrage manuel puis domaine, canal sécurisé, nom, GUID et OU relus. Ne pas annoncer la jonction qualifiée sur la seule acceptation de la commande.

## Matrice des contrôles encore non qualifiés

| Action | Succès réel à observer | Négatifs / arrêt | Moyen borné |
|---|---|---|---|
| Lectures AD et naming | Inventaire/sites/services exacts, aperçu conforme et libre | Hors domaine sans credential, module absent, inventaire incomplet, collision après aperçu | read + préparation ; comparaison AD indépendante |
| join | Reçu avant envoi, 10 puis nom/domaine/OU/canal après reboot | Déjà joint, cible distante, collision entre aperçu/prepare/execute, unattended, pas d’élévation, authentification refusée ; renommage préalable non effacé par un échec Add | Une seule VM ; credential natif ; aucune suppression de compte |
| rename | 20 puis nom actif et même GUID après reboot | Nom pris, mauvaise confirmation, plan consommé, pendingRename, refus SSO/élévation | Local VM seulement dans le harnais |
| move | 30 + GUID/OU/protection relus | 33 déjà en place, protection false→31, cfg illisible→96, DC refusé | Canari GUID, aller puis retour séparé |
| renameMove | 77 + nouveau nom/OU/GUID/protection, reboot | 89 différé/non tenté/échoué, 97 transport, 32 protection non rétablie | Pas de panne DC provoquée ; situations de panne restent non qualifiées si non réalisables sans modifier la topologie |
| queue | Deux canaris identifiés, séquentiel, consommation unique | Duplication, limite MaxBatch, premier refus arrête le reste, aucun rejeu | GUI réelle ; prépare les deux lignes, une exécution, reçus individuels |
| settings.save | cfg écrit atomiquement + .bak + SHA/relecture + invalidation plans | Concurrent config.changed, convention invalide, champs métier refusés | Copie V1 locale dédiée conservée ; retour exact de convention après preuve |
| Barrières/reçus | Running durable, final durable, mutex, reprise après reboot | PendingRestart/Uncertain bloque, reçu illisible bloque, crash enfant → incertain | Tests dangereux différés ; ne jamais modifier les vraies barrières pour contourner un refus |
| Repli tâche authentifié | Compte explicite+politique vraie+refus distant 5/1314, tâche supprimée après preuve | Pas de repli SSO/politique false/incertain, tâche non confirmée conservée | **Non réalisable via ce harnais local uniquement** ; qualification distincte exige périmètre distant autorisé, pas d’autre machine implicite |
| GUI/pack | Actions accessibles, résultat+reçu réels visibles, WebView2 du pack | Runtime absent, annulation credential, erreur lecture | Pilote GUI existant de l’orchestrateur |

La présence du code et `capabilities.enabled:true` annoncent une action disponible ; elles ne prouvent aucune ligne de qualification. Mettre à jour PARITY/VALIDATION avec les seules preuves datées et les contrôles restants.


## Réconciliation explicite après redémarrage

Après le redémarrage contrôlé, utiliser le bouton **Vérifier l’état** du reçu ou une requête du harnais `action:"reconcile"`, `receiptId` exact, `computer` ancien ou nouveau nom du canari, `expectedComputer` nom actif désormais observé, `execute:true` et la confirmation du harnais. Il s’agit d’une vérification et d’un enregistrement de preuve, sans modification du poste.

Le reçu n’est marqué vérifié qu’après concordance de son GUID lié initialement, du nom et du placement AD, de la protection attendue pour un déplacement, et pour les actions nécessitant redémarrage : identité machine locale identique, bootUtc postérieur, noms actif/configuré attendus, domaine joint et canal sécurisé confirmé. Une erreur, un ancien reçu sans métadonnées initiales ou un résultat distant non observable maintient le blocage. **Ne jamais éditer les JSON pour contourner la barrière.**

Validation du premier ensemble après le push `f430f9b` (avant ajout de cette API) : Engine 207/207 (`logs/engine-finalizer-20261025.log`), publication win-x64 autonome du harnais réussie (`logs/build-ad-harness-20261025.log`), App Release win-x64 compilée sans avertissement (`logs/build-app-finalizer-20261025.log`). Ces preuves ne constituent pas une exécution AD. La nouvelle réconciliation exige les tests et builds suivants consignés séparément.


## Validation de développement terminée le 25/10/2026

Sur Spark, après le premier push et corrections de réconciliation/chemins/sonde PowerShell/garde distante :

- Engine : **219/219**, `logs/engine-complete-20261025.log` ; compilation sans avertissement, `logs/build-engine-complete-20261025.log`.
- Pont : **5/5**, dont sérialisation de `receipts.reconcile`, `logs/bridge-reconciliation-20261025.log`.
- Harnais Windows autonome : publication réussie vers `v2/artifacts/ad-harness`, `logs/publish-ad-harness-complete-20261025.log`.
- Hôte Windows Release win-x64 : compilation réussie, **0 avertissement/0 erreur**, `logs/build-app-complete-20261025.log`. Le pack doit encore reprendre la dernière version web validée par son responsable.

Une invocation `dotnet run` a quitté en 139 sans résultat de tests ; compilation séparée (`UseSharedCompilation=false`) puis exécution directe de la DLL ont réussi. Aucun de ces tests sur fixtures ni aucune compilation ne prouve une mutation AD réelle. Les essais Windows sont réalisés exclusivement par l’orchestrateur, avec leurs fichiers de preuve séparés.


## Gardes de périmètre et arrêt entre lignes — 25/10/2026

Avant toute mutation, le moteur exige un GUID source valide et une OU source dans la racine configurée. Le plan conserve cette OU et le GUID réel de l’OU de destination pour join/move/renameMove. La préparation du lot et l’envoi relisent ces identités ; une OU source déplacée, une destination supprimée/recréée au même DN ou une lecture insuffisante refusent l’envoi. L’adaptateur refait les contrôles immédiatement avant les commandes natives. Le déplacement seul reste permis après inspection et confirmation, conformément à GoMoveOnly V1, sans condition artificielle de renommage dans la même page.

Une demande de fermeture laisse finir la mutation déjà engagée, sa relecture et son reçu ; elle arrête la file entre les lignes. Les lignes intactes restent dans la file et le lot consommé ne peut pas être rejoué. La fermeture effective de l’hôte attend ces travaux engagés.

Validation sur Spark après ces corrections : **229/229** (`logs/engine-guards-20261025.log`), compilation **0 avertissement/0 erreur** (`logs/build-engine-guards-20261025.log`). Cela inclut les corrections COM authentifié, DateTime COM et extraction des codes natifs. Ces validations de développement ne qualifient aucune mutation AD réelle.


## Reprise explicite du déplacement restant après code 89

La préparation `receipts.prepareMove({id})` relit une preuve complète de renommage local après redémarrage (même machine/GUID, nom actif/configuré/AD, domaine/canal, OU initiale et protection), conserve la cible originale et son GUID, puis rend un nouveau plan de déplacement seul. Le web ne fournit ni nouveau nom ni destination. `operation.execute` exige ensuite la confirmation exacte du nom. Autorité en mémoire bornée au SHA du parent, au plan, aux identités et au seul enfant ; consommation sous mutex, autres barrières conservées.

Le parent reste Partial/code89, avec un lien vers l’enfant confirmé et son SHA ; il n’est pas réécrit en succès. Running/Uncertain/crash de l’enfant bloque la reprise ; seule une nouvelle preuve explicite peut vérifier cet enfant. La réconciliation générique du parent code89 reste refusée. Aucun renommage, ajout au domaine, reboot ou relâchement générique de barrière n’est rejoué.

Validation de développement : Engine **248/248** (`logs/engine-continuation89-20261025.log`) ; les deux durcissements natifs supplémentaires de lien machine/boot/résolution ont ensuite leurs **7/7** tests ciblés (`logs/continuation-native-final-20261025.log`). Pont **6/6** (`logs/bridge-continuation89-20261025.log`). Ces fixtures ne prouvent aucune récupération code89 réelle en AD.

Le snapshot `v2/artifacts/ad-harness-stable-simple-20261025` reste distinct : DLL Core/Engine/Live identiques au build229, harnais retour avec **28/28** gardes et **20/20** contrôles V1 bruts ; il permet les lectures/mouvements simples pendant le développement de la reprise89 et ne contient pas cette dernière fonctionnalité.
