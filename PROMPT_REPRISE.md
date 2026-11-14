# Reprise Pesto → v1.0 dans Claude Code

> À coller comme premier message dans Claude Code, lancé à la racine du pack `Pesto_V1_CLAUDE_CODE/`
> (le fichier `CLAUDE.md` du pack est chargé automatiquement et résume les règles).

## 0. Ta mission

Tu reprends **Pesto** (outil d'administration AD : jonction au domaine, renommage, déplacement de postes ; moteur
Windows PowerShell 5.1 + WPF, lanceur natif C x64). Tu dois **terminer la v1.0 à partir de la 17.0-RC23**, et cette fois
**la prouver sur un vrai Windows**, ce qui n'a jamais été fait pour les RC19 à RC23.

Définition de « terminé » :

1. Le moteur démarre et passe ses suites sous **Windows PowerShell 5.1** sur la VM Windows 11 du labo (`TESTER.cmd` vert,
   `Run-StabilisationTests.ps1` vert, `Pesto.exe --check` vert).
2. La matrice interactive de `reference/Pesto_17_RC23_RECETTE_WINDOWS.md` est jouée sur le domaine de test (UAC, WPF,
   jonction, renommage, déplacement, reprise), avec résultats datés.
3. Version passée proprement en **1.0** (source unique, pas un remplacement de titres), EXE recompilé, manifeste régénéré.
4. Packs **PROD** (`Pesto.exe` + `wad/` uniquement) et **DEV** complets.
5. Documents 1.0 : bilan des tests **réellement exécutés**, suivi honnête des 90 points, guide, recette Windows.

Style de travail attendu par l'utilisateur (Frère) : français, concis et direct, niveaux de confiance explicites
(élevé / modéré / faible / inconnu), contre-argument d'abord, pas de flatterie, pas de capitulation sans argument nouveau,
l'action plutôt que les questions. Une mauvaise nouvelle exacte vaut mieux qu'un résultat arrangé.

## 1. Contenu du pack

| Chemin | Contenu |
|---|---|
| `DEV/` | Arbre de travail : sources **corrigées**, `Pesto.exe` et `wad/package.json` **régénérés** et cohérents. |
| `.git/` | Commit `1375908` = base RC23 telle que reçue ; commit suivant = correctifs. `git diff 1375908 -- DEV/wad` montre tout. |
| `reference/` | Bilan, 90 points, guide, recette, note de reprise d'origine de la base RC23. L'archive reçue `Pesto_17_RC23_DEV.zip` est retirée le 9 novembre 2026 (elle contenait le domaine réel du labo, et son lanceur ne se recompile pas à l'identique). |
| `outils/` | `parse_all.ps1` (vrai parseur sur tous les `.ps1`), `ps_symbols.py` (lint d'appels/paramètres, tree-sitter), `ts_scan.py`. |
| `preuves/` | Journaux réellement produits : base RC23 rejouée (`base-rc23/`) et état après correctifs. |
| `CLAUDE.md` | Règles non négociables, conventions, commandes. |

## 2. Le fait majeur : la RC23 ne pouvait pas démarrer

Le vrai parseur PowerShell (7.4.6, même règle en 5.1) refuse `wad/Pesto-Core.ps1` de la RC23 :
`Pesto-Core.ps1:1443:7 EmptyPipeElement` — dans `Get-SiteTag`, une instruction `foreach` était envoyée dans un pipeline
(`@(foreach(...){...}|Sort-Object -Unique)`). Le fichier entier ne se charge pas : **l'application ne démarrait pas du tout**.
C'est le point « véritables erreurs de syntaxe dans les calculs de sites » de la note de reprise.

Deuxième blocage de démarrage, juste derrière : `Pesto-Workspace.ps1:274` affectait `$home` (variable automatique en
lecture seule) dans `Initialize-PestoWorkspace`, appelée sans `try` au démarrage.

Conséquence à garder en tête : **les 122 tests Python et les 340 contrôles portables de la RC23 étaient verts sur une
application qui ne démarre pas.** Ces suites contrôlent des chaînes dans les sources, pas le comportement. Ne leur accorde
aucune valeur de preuve fonctionnelle. La grammaire tree-sitter n'a pas vu l'erreur non plus : seul le vrai parseur compte.

## 3. Défauts : corrigés dans ce pack

Tous vérifiés par relecture du code, puis par le parseur réel ; D1 à D4 et F7 en plus par exécution sous PowerShell 7.4.6
avec doubles AD (`DEV/tests/Run-StabilisationTests.ps1`, 8/8). **Aucun n'a encore tourné sous Windows PowerShell 5.1.**

| Id | Fichier | Défaut | Correctif appliqué |
|---|---|---|---|
| D4 | `Pesto-Core.ps1` ~1440-1443 (`Get-SiteTag`) | Erreur de syntaxe : `foreach` pipé. Bloquant, démarrage impossible. | `@($(foreach(...){...})\|Sort-Object -Unique)`. |
| F2 | `Pesto-Workspace.ps1:274` | `$home=...` : écriture de `$HOME` (lecture seule) → exception au démarrage. | Variable renommée `$homeButton`. |
| D1 | `Pesto-Operations.ps1` (`MoveComputer`) | Déplacement réussi mais restauration de protection en échec : retour 32 **avant** `Set-PestoEffect Move Confirmed` → effet Move perdu dans le reçu. | L'effet observé est consigné avant le contrôle de protection, puis retour 32. |
| D2 | `Pesto-Safety.ps1` (`Complete-PestoIntervention`) | La résolution du parent (`ResumeFrom`) testait le code d'origine (30/33) et ignorait `TimedOut` : un résultat tardif résolvait l'intervention parente. | Condition : `-not $TimedOut -and $r.Phase -eq 'Verified' -and $Action.ExitCode -in @(30,33)`. |
| D3 | `Pesto-Operations.ps1` (`RenameComputer`) | Nom actuel = nom demandé → code **20** (succès de renommage) sans renommage. | Code **96** (action non lancée). |
| F4 | `Pesto-Inspection.ps1:91` | `DomainRole` CIM distant est `[uint16]`, refusé par `Assert-PestoObservationSnapshot` → toute cible distante rejetée. | `[int]$cs.DomainRole`. |
| F5 | `Pesto-Inspection.ps1` (`Get-PestoInspectionSource`) | `Test-PestoOUPath`, `Get-PestoDomainFromDN`, `Test-PestoDnsName` absents de la source du worker d'observation → jonction jamais vérifiable. | Ajoutés à la liste. |
| F3 | `Pesto-Interventions.ps1:31` | Paramètre nommé `$args` écrasé par la variable automatique → `$args.Cancel` échoue. | `param($sender,$e)`. |
| F7 | `Pesto-Policy.ps1` (`Assert-PestoOperationPolicy`) | Filtre LDAP des groupes exclus échappé avec l'échappeur de RowFilter → filtre invalide ou exclusion contournée en silence si le DN contient `( ) * \ '`. | Échappement RFC 4515 en ligne. |
| F6 | `Pesto-Core.ps1` ~3466 | `d''action` affiché tel quel (chaîne à guillemets doubles). | `d'action`. |

## 4. Défauts et chantiers : restant à faire

**A. Recette Windows réelle (priorité absolue).** Rien d'autre n'a de valeur tant que le moteur n'a pas démarré sous 5.1.
Premier geste : copier `DEV/` sur la VM, `Pesto.exe --check`, puis `TESTER.cmd`. Attends-toi à d'autres erreurs
d'exécution que la relecture n'a pas vues (le code RC19-RC23 n'a jamais tourné).

**B. Contrôle avant connexion (point de stabilisation n° 5, absent).** À concevoir et prouver :
- Avant la connexion, analyser chaque `.ps1` d'exécution avec `[System.Management.Automation.Language.Parser]::ParseFile`
  et refuser de démarrer avec la liste fichier:ligne:message. Emplacement conseillé : `Pesto-Integrity.ps1` (déjà chargé par
  `Pesto-Startup.ps1` avant le moteur), appelé juste avant `& $core` et dans le mode `--check` / `--check-json`
  (ajouter le résultat au rapport JSON).
- Compiler le writer C# (`Add-Type -Path wad\Pesto-LogWriter.cs`) à ce moment-là, avec erreur **visible**. Aujourd'hui
  `Initialize-AuditLog` (`Pesto-Journal.ps1:34-51`) avale l'échec dans `catch { continue }` : l'appli démarre sans journal et
  les mutations sont bloquées plus tard par « Audit indisponible », sans explication.
- Les scripts **embarqués** dans des chaînes (`Pesto-Operations.ps1` : helper élevé `$helper=@'…'@`, tâche de renommage
  `$inner=@"…"@`, script dsreg construit par concaténation) ne sont analysés qu'en pleine mutation. Les faire passer par
  `Parser::ParseInput` dans ce même contrôle (marqueur en première ligne du here-string, ou fonctions de construction pures).
- `Pesto-LogWriter.cs` contient des caractères accentués **sans BOM** : passer les littéraux en ASCII ou ajouter le BOM.

**C. Défaut logique ouvert (certitude modérée, à vérifier puis corriger).** `Pesto-Join.ps1:196-206` : le reçu local est écrit
`Phase='Running'` **avant** des appels qui peuvent lever (politique, `Start-PestoIntervention`, `Set-PestoEffect`, observation
initiale) alors qu'aucune commande n'est partie. L'UI affiche « Ajout non lancé » mais le reçu reste `Running` et bloque tous
les contrôles suivants sans issue dans l'application. Piste : politique avant l'écriture du reçu, et `try/catch` qui repasse le
reçu en `Failed` (et clôt l'entrée centrale en 96) si `MutationStarted` est faux.

**D. Passage en version 1.0.** Voir section 7.

**E. Durcissements utiles, non bloquants.**
- `Get-PestoObservationDecision` (`Pesto-Inspection.ps1`) : refuser explicitement un plan `Renommer=$true` dont le nouveau nom
  égale l'ancien (aujourd'hui bloqué en amont par `Get-PestoRenameMoveDecision`, pas dans la décision elle-même).
- Affectations à des variables automatiques sans effet réel mais signalées par PSScriptAnalyzer (la gate `Verify-Release.ps1`
  l'exécute) : `$matches=` (Review:42, Contracts:214, Names:70/128, Workspace:34, Inspection:19, Interventions:104, Join:113),
  `$event=` (Async:18/58/63, Safety:69/374), `$args=` (Operations:855, Inspection:27), `$pwd=` (Authentication:332).
- Pistes écartées faute de preuve, à trancher sous Windows : écrasement possible de `Items[Index-1]` dans
  `Fail-PestoQueueCallback` ; `Reset-PestoRowPreflight -ClearIdentity` ne vide pas `TargetOUGuid` ; défaut
  `CLEAR_PROTECTION=$true` (`Pesto-Core.ps1` ~4831) à confirmer comme choix produit.
- Ajouter le vrai parseur à la validation portable (`validate_pesto.py` : appeler `pwsh` s'il est présent, sinon `NOT_RUN`),
  pour qu'une erreur de syntaxe ne repasse plus jamais au vert.

**F. Couverture de relecture (pour savoir où chercher).** Relus intégralement : Operations, Safety, Recovery, Contracts,
Direct, Async, Journal, Startup, Integrity, Directory, Review (par moi) ; Join, JoinRecovery, Inspection, Interventions,
Names, Tables, Workspace, Policy, Preparation, UXFlow, SuiteUI, Support, Configuration, Authentication, Appearance et
`Pesto-Core.ps1` (hors base64) par des relecteurs automatiques. Non relus en profondeur : `Pesto-Shell.xaml` (seuls les noms de
contrôles ont été croisés : tous présents), `tools/*.py`, `tools/*.ps1`, `tools/launcher/*.c`, scripts `.cmd`.

## 5. Ce qui a réellement tourné, et où

| Contrôle | Résultat | Moteur réel |
|---|---|---|
| Parseur sur 65 `.ps1` (wad, tests, tools, maintenance) | Base RC23 : **1 erreur**. Après correctifs : **0**. | PowerShell 7.4.6 Linux, pas 5.1 |
| `Run-StabilisationTests.ps1` | 8 / 8 | PowerShell 7.4.6, doubles AD |
| `Run-NamesLoadingTests.ps1` (sans `-Wpf`) | 22 cas OK | PowerShell 7.4.6 |
| `Run-Pesto21/22/23Tests.ps1` | **Non exécutés** : refusent tout autre moteur que Windows PowerShell 5.1 | — |
| Python `unittest` | 122 OK (base et après correctifs) | Contrôles de chaînes dans les sources |
| `validate_pesto.py` | 340 OK (base et après correctifs) | Idem + XML + PE |
| `run_native_portable.py` | 35 scénarios C + 9 arguments + 2 000 allers-retours + 132 SHA | API Windows remplacées par des doubles |
| Compilation de l'EXE | 2 fois, identiques. SHA-256 dans `preuves/exe-sha256.txt` | clang / lld-link 18.1.3 |
| Exécution du PE | `--check --quiet` : pack intact 0, composant modifié 1, verrou de mise à jour 32, paramètre inconnu 1 (lanceur d'avant L4 ; depuis le 04/10 : 125, 126, 120, voir `DEV/docs/V1_GUIDE.md`) | **Wine 9.0**, pas Windows ; `powershell.exe` = stub |
| `Pesto-LogWriter.cs` | Compile en C# 5 | Mono `mcs -langversion:5`, pas le CLR .NET Framework |

Jamais exécuté : Windows PowerShell 5.1, WPF, UAC, registre/ACL, AD/Entra réels, signature. Reproductibilité : l'EXE RC23
livré (`95b736ef…`) n'est **pas** reproduit par clang 18.1.3 (même taille, octets différents) : l'outillage n'était pas épinglé.
Consigne la version de clang/lld dans les preuves de build.

## 6. Labo Windows

- PC Windows du réseau local, accessible en SSH : `degun@192.168.1.173`. Le mot de passe a été donné par l'utilisateur dans la
  conversation d'origine ; il n'est **volontairement pas recopié ici** : demande-le, ou mieux, installe une clé SSH puis fais
  changer ce mot de passe (il a transité en clair).
- Sur ce PC : **VirtualBox** avec un **contrôleur de domaine Windows** et un **client Windows 11** membre du domaine.
- Le labo est **partagé** : « domenia » et « filpro » y font aussi leurs tests. Ne modifie pas l'état de leurs machines.
  Si un test doit muter (jonction, renommage, déplacement, redémarrage), **crée ta propre VM** (clone lié du client Windows 11,
  nom explicite) et prends un instantané avant chaque campagne (`VBoxManage snapshot … take`), restaure après.
- Ordre conseillé : (1) inventaire `VBoxManage list vms` / `list runningvms`, sans rien toucher ; (2) clone dédié ;
  (3) copie de `DEV/` dans la VM ; (4) `Pesto.exe --check` ; (5) `TESTER.cmd` et `Run-StabilisationTests.ps1` sous 5.1 —
  aucun appel AD ni UAC à ce stade ; (6) démos (`DEMO.cmd`, `DEMO_DOMAINE.cmd`) pour le rendu WPF ; (7) seulement ensuite la
  matrice réelle sur le domaine de test, objets de test dédiés, instantané pris.
- WPF et UAC exigent une session interactive : une session SSH ne suffit pas pour ces cas (session console/RDP de la VM, ou
  tâche planifiée interactive). Les suites `-Wpf` donnent `SKIP` sans bureau ; un `SKIP` n'est pas un `PASS`.
- Rapporte pour chaque campagne : build Windows, version PowerShell, SHA de l'EXE, compte et mode utilisés (sans secret), date.

## 7. Passage en 1.0 : ce qu'il faut réellement changer

`tools/version.json` (`{"major":17,"minor":0,"patch":0,"revision":23,"channel":"RC"}`) est censé être la source unique, mais :

- `tools/release_version.py` **impose** `channel == 'RC'` et fabrique `17.0-RC23` ; il faut un canal de version finale.
- La version est écrite en dur à une trentaine d'endroits : `wad/Pesto-Core.ps1` (46, titre ~2273, commentaire 12),
  `Pesto-Integrity.ps1:70` (comparaison du manifeste), `Pesto-Startup.ps1` (18, et **`"RC21 Route="`** ligne 309),
  `Pesto-Join.ps1` (1, 196), `Pesto-Safety.ps1:163`, `Pesto-Authentication.ps1` (127, 370), `Pesto-Shell.xaml` (2 et 112,
  encore **`17.0-RC20`**), `tools/launcher/Pesto-launcher.c` (1, 68, 111, 157, 168), `Pesto.manifest` (**`17.0.0.18`**),
  `tools/Build-Pesto.ps1`, `Update-PackageManifest.ps1`, `New-PestoDistribution.ps1`, `Verify-Release.ps1`,
  `tools/checks/validate_pesto.py`, `tools/update_installation.py` (18, 83 : « RC18 to RC23 » seulement), `TESTER.cmd`,
  `TEST_RC23.cmd`, `.github/workflows/validate.yml`, plus les tests qui attendent `RC23`.
- Recommandation : un outil d'estampillage (`tools/stamp_version.py`) qui applique `version.json` à ces emplacements et un
  mode `--check` qui échoue s'il reste un littéral périmé ; le brancher dans `validate_pesto.py`.
- **Le numéro descend** de `17.0.0.23` à `1.0.x` : vérifier tout ce qui compare des versions (`update_installation.py`, la
  mise à jour depuis une installation 17.0-RC18…RC23, les outils de déploiement type WAPT qui lisent la FileVersion du PE).
  Décision à faire valider par l'utilisateur si un outil de parc refuse la « rétrogradation ».
- Compatibilité des reçus : la RC23 écrit des reçus centraux de schéma 3 ; lecture des schémas 1/2/3 à conserver. Le champ
  `Version` des reçus est informatif : ne pas en faire une condition de lecture.
- Après tout changement : `build_native.py` → `refresh_manifest.py` → suites → packs.

## 8. Plan d'exécution proposé

1. `git log`, `git diff 1375908 -- DEV/wad`, relire `CLAUDE.md`. Rejouer les commandes de la section « Commandes ».
2. Labo : inventaire, VM dédiée, instantané. **Premier démarrage réel** de `DEV/` sous Windows 11. Corriger ce qui casse,
   un défaut à la fois, test à l'appui ; tout nouveau défaut entre dans le tableau de la section 3.
3. Point B (contrôle avant connexion) avec tests, puis point C (reçu `Running` de jonction).
4. Version 1.0 (section 7), recompilation, manifeste, suites, packs.
5. Matrice interactive sur le domaine de test, résultats datés.
6. Documents 1.0. Reprendre `reference/Pesto_17_RC23_90_POINTS.md` ligne par ligne : ne changer un statut que sur preuve ;
   les points 44 (djoin) et 23 (signature) restent ouverts sauf décision contraire.
7. Rapport delta : construit contre prévu, écarts et raisons, risques restants.

Si une décision non prévue ici apparaît (comportement métier, nommage de version, suppression de code), arrête-toi, expose
la décision avec ta recommandation et son niveau de confiance, puis continue une fois tranchée.

## 9. Pièges connus

- Un `.ps1` sans BOM est lu en ANSI par PowerShell 5.1 ; les accents cassent, et certains octets UTF-8 deviennent des
  guillemets typographiques que PowerShell traite comme des délimiteurs de chaîne.
- Le lanceur refuse de démarrer si un seul octet d'un composant diffère de l'empreinte incorporée : après une modification,
  l'EXE **et** le manifeste doivent être régénérés, sinon `Pesto.exe --check` échoue pour une raison triviale.
- `Pesto.cmd` et `Pesto-Startup.ps1` vérifient aussi `wad/package.json` : même contrainte hors EXE.
- Les tests historiques de `DEV/tests/` et `DEV/wad/maintenance/` antérieurs à RC23 gardent un statut historique.
- macOS : le clang d'Apple n'a pas `lld-link` ; `brew install llvm lld` et mettre ce clang en tête du `PATH`.
  `brew install --cask powershell` pour le contrôle secondaire sous PowerShell 7.
- Ne confonds jamais « compilé », « empreintes cohérentes », « tests de chaînes verts » avec « fonctionne ».

## 10. Livrables attendus

`Pesto.exe` 1.0 recompilé (SHA-256 consigné) ; `Pesto_PROD.zip` et `Pesto_DEV.zip` ; bilan des tests réellement exécutés
(par moteur) ; suivi des 90 points ; guide 1.0 ; recette Windows avec résultats ; liste honnête de ce qui reste ouvert.
