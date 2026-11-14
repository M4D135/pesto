# Reprise Pesto — 15/10/2026, fin d'après-midi

Document de passation pour une nouvelle session Claude Code. Il prime sur `PROMPT_RELAIS_2026-10-04.md` et
`PROMPT_REPRISE.md` (historiques). Lire aussi `CLAUDE.md` à la racine du dépôt : règles non négociables, conventions,
commandes. Les consignes globales KBZA (`~/.claude/CLAUDE.md`) s'appliquent : le Spark fait le gros, Claude cadre et
vérifie, réponses courtes, pas de workflow multi-agents sans demande explicite.

## 1. Demandes de David, dans l'ordre (mot pour mot)

- 14/10 : « j'ai beaucoup avancé depuis sur le projet, fouille kbza, github, le mac ( codex ), le spark pour voir les
  nouvelles data, on a une liste de points d'amélioration à faire et terminer » ; « fais tous les points, dev, code, go
  travailleur seul » ; « et test simu a la fin » ; « fais toi une team d'agents pour avancer, je veux qu'on ait terminé
  ces 120 et bien plus même , code avant puis teste ensuite » ; « utlise à fond le spark pour economiser tes tokens,
  envoie lui petites taches en parallele pour optimiser rendement ».
- 15/10 matin : « go tout boucler, commit et push , oublie spark et go toi ».
- 15/10 après-midi, avec 6 captures du réseau réel : « bloqué par les verif, c la merde, on était ok avant modifs. »
- Puis : « fais en sorte de pouvoir acquiter ces erreurs aussi au lieu de tout bloquer ».
- Puis : « fais bosser le spark a fond et economise tes tokens » (décision la plus récente sur le Spark).
- Puis : « fais un prompt de reprise pour code, donne lui toutes les infos necessaires » (ce document).

La demande de push du 15/10 matin remplace la règle « aucun push tant que… » de `CLAUDE.md` : pousser `master`
une fois tout vérifié (voir § 6).

## 2. Le blocage terrain de David

Poste **P111301PR765189**, renommage unitaire vers **CH037419**, build terrain antérieur au 15/10 (probablement
`a754ac88…` ou `b5e42115…`, non confirmé).
- Le poste est hybride. La politique `EntraPolicy` absente vaut `HybridOnly`, donc `dsregcmd /leave` s'est exécuté
  avant le renommage ; son code de retour était 0.
- La relecture `dsregcmd /status` qui suit a dépassé le délai de **25 s**. Résultat : code **97**, Entra `Uncertain`,
  renommage jamais lancé.
- L'intervention restait « Résultat incertain ». La fiche État ne pouvait rien consigner, pour deux raisons :
  `Get-PestoObservationDecision` exige le nom final, et `Confirm-PestoInterventionObservation` refuse Entra
  `Uncertain`.
- Le poste restait donc bloqué. Ce n'est pas une régression du lot 120 : ce chemin est inchangé depuis RC23 ; il
  n'avait simplement jamais été rencontré.
- Le poste a très probablement quitté Entra. Il faut vérifier `dsregcmd /status` (AzureAdJoined) et prévoir la
  réinscription hybride selon la procédure du support.

Deuxième défaut vu sur les captures : page **Noms disponibles** avec Site et Service à « (tous) ». L'erreur
« Périmètre trop large » (borne de 2 000 000 numéros, présente depuis RC23) remontait brute à travers EndInvoke.

**Procédure à donner à David une fois le build corrigé installé :**
1. Ouvrir Pesto, puis « Vérifier l'opération » (ou Interventions → sélectionner la ligne → « Acquitter… »).
2. Dans la fiche État : lecture automatique, puis « Acquitter… », saisir un motif et valider.
3. Le reçu garde « Résultat incertain » et le code 97. Le poste n'est plus bloqué.
4. Relancer le renommage vers CH037419. Pesto relit `dsregcmd /status` : si AzureAdJoined vaut NO, il saute le retrait
   et renomme.
5. Vérifier ensuite la réinscription hybride.

## 3. Ce qui est fait : commits locaux sur `master`, non poussés

`master` a 86 commits d'avance sur `origin/master` (`8bf5a7e`). Les derniers :

- `bdc7eef` — **Acquittement explicite**, délais dsregcmd, Noms disponibles.
  - Contrat d'acquittement :
    - **Objet `Acknowledged` fermé** : `{Schema=1, Utc, By, Reason (3 à 500 caractères, une ligne), Phase, ResultCode,
      Observation (snapshot ou $null)}`, validé par `Assert-PestoAcknowledgement` (`Pesto-Contracts.ps1`).
    - **Validité** : `Test-PestoAcknowledgedReceipt` (`Pesto-Policy.ps1`) n'est vrai que si `Phase` et `ResultCode`
      sont égaux à ceux du reçu ; l'acquittement devient caduc si l'état change. Fonctions associées dans Policy :
      `Test-PestoAcknowledgementNeeded` (phases Running, PendingRestart, Partial, MoveReady, Protection, Uncertain,
      hors suivi facultatif) et `New-PestoAcknowledgement`.
    - **Le reçu n'est jamais réécrit** : phase, code, effets (Entra, Rename, Move, Protection) et messages restent ;
      jamais un succès. Texte commun : `Get-PestoAcknowledgementText`.
  - Écriture et barrières :
    - **Écrivain unique** : `Set-PestoOperationAcknowledgement` (`Pesto-Interventions.ps1`), sous le mutex
      `Global\GP_PostMutation_v1`. Refusé si une opération ou un worker est actif. Ordre d'écriture : le registre
      `GP\Interventions\<id>.json`, puis `direct.json` et `Join\receipt.json` du même identifiant, chacun avec sa phase
      et son code. Ensuite `Exit-PestoCoordination` et une ligne d'audit.
    - **Barrières adaptées** :
      - lecteurs : `Read-PestoIntervention` (liste fermée et validation), `Read-PestoDirectReceipt`,
        `Assert-PestoJoinReceiptData` ;
      - contrôles du moteur : worker unitaire (`Pesto-Direct.ps1`), `Complete-PestoDirectAction`,
        `Initialize-PestoDirectState`, `Assert-PestoStoredMutationReady`, `Test-PestoInterventionConflict` ;
      - coordination et jonction : `Start-PestoIntervention` (libération de coordination), `Exit-PestoCoordination`,
        `Get-PestoJoinReceiptDecision` (Phase `Acknowledged`, Blocked faux, message dans `Complete-PestoJoinStatus`) ;
      - listes de sources des workers : `$script:PestoWorkerCoreNames`.
    - **`Test-PestoDirectTargetBarrier` non modifié, volontairement** : le recalcul de `DirectLocked` suffit (avis du
      critique du relevé).
  - Interface :
    - « **Acquitter…** » : dans la fiche État (`StateAcknowledge`, modes Ledger, Direct et Queue ; disponible même après
      une lecture en échec) et dans Interventions (`LedgerAcknowledge`).
    - Boîte `Show-PestoAcknowledgeDialog` (fenêtre hébergée, motif obligatoire), résumé par
      `Get-PestoAcknowledgeSummary` (Entra, tâches non terminées, absence de lecture).
    - Ligne d'Interventions : « · acquittée », `Unresolved` à faux.
  - File :
    - `BtnSafetyAck` (« Acquitter le verrou… », `Pesto-Shell.xaml`) et `Invoke-PestoQueueLockAcknowledgement`
      (`Pesto-Core.ps1`).
    - Effets : acquitte les reçus du lot, passe les lignes EN COURS en INCERTAIN, met `MutationUncertain` à faux, écrit
      un checkpoint en Phase `Acknowledged` (ou `Idle` si la file est vide).
  - Outil de mise à jour : `tools/update_installation.py` reproduit le prédicat (`_acknowledged`) ; la phase de file
    `acknowledged` est rangée parmi les phases closes.
  - Délais dsregcmd et surveillance :

    | Où | Avant | Après |
    |---|---|---|
    | `/status` avant `/leave` | 25 s | 90 s |
    | `/status` après `/leave` | 1 lecture de 25 s | 2 lectures de 120 s, 5 s d'écart, jamais de second `/leave` |
    | `Get-PestoLocalHealth` | 10 s | 120 s |
    | Lecture de la fiche État (PostState) | 120 s | 240 s |
    | Surveillance DirectAction et QueueAction | 300 s | 900 s |
    | Tâche SYSTEM distante `Pesto_DsregLeave` | 150 s | 450 s |

  - Noms disponibles :
    - `Build-NmIndex` calcule `$script:NmPairs`, les couples site/service connus (catalogue et inventaire).
    - `Update-NameGrid` envoie `Pairs` quand types × sites × services × 999 dépasse 2 000 000. Si c'est encore trop,
      il affiche l'état Empty « Choisissez un site ou un service ».
    - `Fail-PestoNamesProjection` déroule l'enveloppe EndInvoke et classe « Périmètre trop large » en Empty/warn.
- `53551eb` — listes de chargement des bancs (ajout de `Test-PestoAcknowledgedReceipt`).
- `28fd398` — bouchon `BtnSafetyAck` dans `Run-QueueRemovalTests.ps1`.
- Avant : `1429004` (intégration du lot 120+), `3f4829e` (outils Spark), `074ba3f` (build fedad911), etc.

**Build actuel :**
- EXE `b983410360178aadca25ff41b39e069fb08835ea8e969ce0a532b2e80033fd62`, 63 composants (clang/lld 23.1.2).
- Packs dans `~/Projects/pesto-packs/2026-10-15-ack/` : DEV `c14c1f01…`, PROD `70f9c63c…`. Recalculer les SHA256
  complets avant livraison.

## 4. Preuves, et ce qui n'a pas été prouvé

- **Mac** :
  - Suite Python complète OK (6 ignorés), avec `PESTO_PWSH` défini.
  - `validate_pesto.py` : 477/0.
  - Parseur `parse_all.ps1` : 133 fichiers, 0 erreur.
  - Bancs pwsh 7 portables au vert, dont OptionalPostCheck, OptionalFollowupUi, InterventionView, HomeDashboard,
    ReceiptTools120, BootIdentity, Stabilisation et Automation.
- **VM `PESTO-W11-TEST`** (P111301VA765480, membre de labo.local), dossier `C:\PestoAck_20261015` :
  - `--check-json` DEV et PROD : code 0.
  - `Run-AllTests.ps1` : tout vert sauf QueueRemoval (bouchon manquant), corrigé puis rejoué seul à 25/25.
  - Journal : `~/Projects/pesto-wt/reprise-20261015/windows-ack.txt`.
  - Le matin, `fedad911` avait passé les 44 suites.
- **Non fait** :
  - Recette GUI réelle du parcours d'acquittement sur la VM (UIA).
  - Rejeu complet de `Run-AllTests` après `28fd398`.
  - Essai sur le réseau réel de David.
  - Recette GUI du pilote (g20 changement de site Paris→Lyon, redémarrage, g21, g30, g40, g50).

## 5. Travail en cours, à reprendre dans cet ordre

1. **Revue Spark du correctif : 18 constats non vérifiés.** Ils sont dans
   `~/Projects/pesto-wt/reprise-20261015/spark-revue/{surete,ps51,couverture,terrain}.out.txt`. Le diff relu
   (`-U60`) est dans `diff.txt`.
   - Titres : Run-Queue (bloquant) ; `Invoke-PestoQueueLockAcknowledgement` (×8, dont un bloquant) ;
     `Sync-PestoInterventionViews` (×3) ; `Test-PestoDirectTargetBarrier` (×2) ; `Restore-PestoQueueCheckpoint` ;
     `Test-PestoInterventionConflict` (bloquant) ; `Set-PestoOperationAcknowledgement` (×3, dont 2 bloquants).
   - Chaque constat est un brouillon. Le relire contre le code réel, réfuter ou corriger, puis tester.
   - Points connus avant d'ouvrir les constats :
     - `Test-PestoDirectTargetBarrier` n'a pas été changé exprès (voir § 3).
     - Après un acquittement de file, `MutationUncertain` reste lu brut dans Join, Names et `Update-PestoUx` ; c'est
       sans effet puisqu'il passe à faux.
     - `Apply-PestoQueueObservation` compte encore les lignes INCERTAIN déjà acquittées.
     - `Test-PestoStartupEmptyQueues` n'accepte que Idle pour une file vide, d'où le choix de Idle dans ce cas.
2. **Tests rédigés par le Spark**, dans le worktree `~/Projects/pesto-wt/ack-tests` (HEAD détachée à `53551eb`) :
   - modifiés : `Run-BootIdentityTests.ps1` (ACK03) et `Run-InterventionViewTests.ps1` (ACK02) ;
   - nouveaux : `test_acquittement.py` (ACK04) et `test_spark_ack03.py`, non demandé, à juger ;
   - ACK01 est revenu « report » : `Run-OptionalPostCheckTests.ps1` fait plus de 14 000 caractères, donc seuls des
     extraits lui étaient transmis. À refaire (cas listés dans `~/Projects/pesto-wt/spark-ack/taches.json`) ;
   - journal : `~/Projects/pesto-wt/spark-ack/run.log`, réponses brutes dans `.../spark-ack/travail/`.
   - Relire ces brouillons, les exécuter, puis les reporter dans `master` (`git -C …/ack-tests diff`, plus les nouveaux
     fichiers).
3. Corriger les défauts confirmés. Reconstruire dans l'ordre :
   1. `pwsh tools/Build-PestoEngineModule.ps1` ;
   2. `PATH=/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH python3 tools/launcher/build_native.py` ;
   3. `python3 tools/refresh_manifest.py`, puis `--check`.

   Ensuite : suite Python, `validate_pesto.py`, bancs portables, packs, VM (`Run-AllTests`).
4. **Recette GUI sur la VM** :
   - parcours d'acquittement : fiche État, Interventions, verrou de file. Le reçu incertain ne doit être fabriqué que
     dans un dossier de test, jamais en production ;
   - pilote g20 à g50 : scripts dans `preuves/qualification-finale-2026-10-14/pilote/` (g20 à g50 ne sont pas encore
     versionnés).
5. Rapprocher les 120 points de `DEV/docs/implementation/catalogue-120.json` : réalisé, évalué ou bloqué, avec ses
   preuves. Voir aussi `DEV/docs/implementation/LOT_SPARK_FILTRE2.md` (24 éléments non implémentés, chaînes du lanceur
   sans accents).
6. Régénérer les guides (`outils/guides/`, voir son `LIRE.md`) en y décrivant l'acquittement. Refaire les packs,
   `SHA256SUMS` et le dossier de livraison.
7. **Pousser `master`**, et `m4d-admin-common` (1 commit d'avance, `a050525`). Avant de pousser : tout vert. Conserver
   les worktrees `spark*`, `filtre*` et `ack-tests`, et la branche `origin/spark/filtre2` déjà poussée.
8. Compléter `CLAUDE.md`, rubrique « Décisions actuelles », avec les décisions du 15/10 (acquittement, Spark à fond,
   push demandé) et l'état vérifié. Écrire une note KBZA (`~/bin/kbza note … --id pesto-reprise-20261015`).
9. Donner à David la procédure du § 2 et le build à installer.

## 6. Outils et accès

- **pwsh 7.4.20** : `~/Documents/Codex/2026-10-12/tu-x20/work/pesto-runtime/powershell-7.4.20/pwsh`. Exporter
  `PESTO_PWSH` avec ce chemin pour les tests Python.
- **Lanceur de bancs parallèle** : `python3 ~/Projects/pesto-wt/reprise-20261015/outils-session/run_pwsh.py <dossier>
  [Run-X.ps1 …]`. Il écrit un fichier par banc et le code retour. Un banc qui échoue en 0 s sur le Mac exige Windows
  PowerShell 5.1.
- **VM** : `ssh -J degun@192.168.1.173 -p 2223 labadmin@127.0.0.1`, avec
  `UserKnownHostsFile=~/.ssh/known_hosts_pesto`.
  - Helper `outils-session/lab.py` : `ps()`, `put()`, `get()`, `screenshot()`, `session(etape)` via une tâche
    planifiée élevée sous `LABO\tech.pesto`, `push_pilot()`, `fetch_preuves()`. Le copier dans un dossier de
    travail et l'importer depuis ce dossier.
  - Recette type : packs → `C:\Pesto…\packs`, Expand-Archive, Unblock-File, `Pesto.exe --check-json`, puis
    `powershell -ExecutionPolicy Bypass -File tests\Run-AllTests.ps1`.
- **Spark** : `~/bin/kbza ask --prompt-file F --max-tokens 0 --no-memory --reasoning-mode direct|inherit`.
  - Il est partagé avec d'autres sessions (Domenia) : une passe prend 1 h 15 à 1 h 30 en mode inherit sous charge.
  - Toujours lancer en tâche de fond suivie (`run_in_background`), jamais `&` dans une commande ordinaire : les
    processus survivent et se dédoublent.
- **Outils Spark** dans `outils/spark/` :
  - `spark_pesto.py` : tâches JSON → blocs SEARCH/REPLACE appliqués dans un worktree. Les fichiers de plus de
    14 000 caractères ne sont transmis qu'en extraits : nommer les fonctions dans la fiche.
  - `spark_replay.py` : filtre syntaxe + XAML + tests.
  - `bisect_revert.sh`.
- **Relevé des sites de blocage** : `outils-session/ack-map.json`, 264 sites (barrières, schémas, tests), pour vérifier
  la couverture.

**Pièges connus :**
- Les variables PowerShell ignorent la casse (`$r` = `$R`).
- Fichiers `.ps1` en UTF-8 avec BOM. `Pesto-Policy.ps1` est en CRLF, les autres en LF : conserver.
- Les bancs chargent les fonctions par AST, dans des listes figées : toute fonction nouvelle appelée doit y être
  ajoutée.
- Après toute modification de `wad/` : reconstruire module, EXE et manifeste, sinon une centaine de tests Python
  échouent sur « Changed runtime component ».
- `Pesto.Engine.Runtime.ps1` est généré : ne pas l'éditer.

## 7. Contraintes de sécurité, toujours en vigueur

- Ne jamais saisir de mot de passe ni d'identifiant AD : David les tape lui-même dans un onglet de terminal, avec un
  script masqué.
- Ne jamais lire ni conserver le `cfg.json` privé de David ; aucune valeur réelle dans le dépôt.
- Tests sur la VM uniquement, jamais sur l'hôte. Instantanés à froid avant les phases qui modifient.
- Ne pas toucher aux VM DOMENIA, FILPRO et DEX. Ne pas restaurer DC01 ; le laisser allumé (demande de Domenia).
- Ne pas changer soi-même les réglages de sécurité de Windows.
- Honnêteté des preuves : distinguer Windows PowerShell 5.1 réel, pwsh 7 et doubles. Ne jamais annoncer une recette
  non jouée.
- Commits terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 8. Prompt à coller dans la nouvelle session

> Reprends Pesto dans `~/Projects/pesto` (branche `master`, local en avance de 86 commits). Lis d'abord
> `PROMPT_REPRISE_2026-10-15.md` à la racine, puis `CLAUDE.md`. Consigne de David : faire bosser le Spark à fond et
> économiser les tokens Claude. Commence par le § 5 : vérifie les 18 constats de la revue Spark contre le code, intègre
> les tests rédigés par le Spark depuis le worktree `ack-tests`, corrige, reconstruis, teste sur le Mac puis sur la VM,
> fais la recette GUI de l'acquittement. Ensuite : catalogue des 120 points, guides, packs, puis push de `master` et de
> `m4d-admin-common`. Enfin, donne à David la procédure pour débloquer P111301PR765189.
