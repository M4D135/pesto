# Relais Pesto 1.0 : reprendre le chantier au 4 octobre 2026

> À donner tel quel, comme premier message, à un modèle qui reprend le travail (agent avec shell : Claude Code, Codex
> ou équivalent), lancé à la racine d'un clone du dépôt. Rédigé par Claude (Opus 5.5) au terme de la session des 2 au
> 4 octobre 2026. Chaque fait ci-dessous a été vérifié au moment de l'écriture, sur le dernier commit qui modifie ce fichier, puis
> relu par un relecteur adverse indépendant confronté au dépôt (corrections intégrées).
> Une ligne marquée « non vérifié » ne l'a pas été. **Vérifie toi-même avant d'agir : le dépôt et la VM ont pu changer.**

---

## 0. Ordre de lecture

1. Ce fichier, en entier.
2. `CLAUDE.md` : règles non négociables, conventions de code, commandes, état daté (section « État », les derniers
   paragraphes priment sur les premiers).
3. `DEV/docs/V1_CONSTATS_OUVERTS.md` : décisions et constats encore ouverts.
4. `DEV/docs/V1_RECETTE_WINDOWS.md` : la recette, ligne par ligne, avec les résultats déjà consignés.
5. `DEV/docs/V1_BILAN.md`, sections 7 et 8 : décisions et liste de ce qui n'est **pas** prouvé.
6. `outils/labo/LIRE.md` : accès à la VM et outils de pilotage.
7. Au besoin : `DEV/docs/V1_GUIDE.md` (installation, codes de sortie, mise à jour), `DEV/CHANGELOG.md`,
   `preuves/*/LIRE.md`.

`PROMPT_REPRISE.md` est **historique** (passage RC23 → 1.0, état au 2 octobre). Ses sections 2, 3 et 9 (défauts
d'origine, pièges PowerShell) restent utiles ; son plan et son « état » sont dépassés.

---

## 1. Mission

Pesto est un outil d'administration Active Directory (jonction au domaine, renommage, déplacement de postes) : un
moteur Windows PowerShell 5.1 + WPF (`DEV/wad/`), lancé par un EXE natif x64 (`DEV/Pesto.exe`, C sans CRT) qui vérifie
les SHA-256 de ses composants avant de démarrer PowerShell. Successeur de « GP » (Gestion des Postes).

But : **livrer la 1.0 en la prouvant sur un vrai Windows.** La 17.0-RC23 reçue ne démarrait pas du tout (erreur de
syntaxe) alors que ses 122 tests Python et 340 contrôles portables étaient verts. Depuis, chaque affirmation doit
reposer sur une exécution réelle et datée.

« Terminé » veut dire (critères de clôture de `V1_RECETTE_WINDOWS.md`) :

1. Phases 1 à 4 de la recette jouées sous Windows PowerShell 5.1 sur la VM de test, preuves dans `preuves/vm-<date>/`.
   Un cas non provoqué reste « non joué » avec sa raison ; jamais PASS par déduction.
2. Chaque défaut trouvé : reproduit, test qui échoue sur l'ancien code, correctif, EXE et manifeste reconstruits,
   vérifié de nouveau sous 5.1.
3. Documents 1.0 honnêtes : recette, constats, bilan, CHANGELOG, guide, `V1_90_POINTS.md` (statut changé sur preuve
   seulement ; points 44 djoin et 23 signature ouverts sauf décision de David).
4. Packs PROD (`Pesto.exe` + `wad/` seulement) et DEV fabriqués depuis le Mac **après** la recette.
5. Fusion vers `master` ou PR : seulement à la demande de David.

---

## 2. David, et comment travailler avec lui

- Français. Réponses courtes et directes. Niveaux de confiance explicites (élevé, modéré, faible, inconnu).
  Contre-argument d'abord, pas de flatterie, pas de capitulation sans argument nouveau. Une mauvaise nouvelle exacte
  vaut mieux qu'un résultat arrangé.
- Il délègue largement (« go autonome », « fais tout toi », « fais au mieux termine tout ») : avance seul sur tout
  ce qui est réversible et dans le périmètre, sans redemander une autorisation déjà donnée. Le 04/10, il a délégué
  les décisions L1, L4, L6, X5 et O7 ; cette délégation ne s'étend pas aux autres sujets.
- « Si go c des machines de tests y'a rien à craindre » : feu vert pour agir franchement sur la VM de test
  `PESTO-W11-TEST`, **dans les limites de la section 3**.
- Il est souvent loin du clavier (« j'ai pas la main ») ou suit depuis un téléphone. Quand une action lui revient,
  donne-lui **une commande prête à coller**, dans son propre bloc, et dis ce qu'elle fait. Ne bloque pas le reste du
  travail en l'attendant.
- S'il tourne avec Claude Code sur son Mac, ses consignes globales (`~/.claude/CLAUDE.md`, KBZA) s'appliquent aussi,
  dont la consigne d'économie : le Spark (LLM local, `~/bin/kbza ask --prompt-file FICHIER --max-tokens 0`) fait le
  gros du travail mécanique, le modèle principal cadre et vérifie, et pas de workflow multi-agents sans demande
  explicite. Il avait activé ce mode (« ultracode ») pour la session du 04/10 seulement. Toute réponse du Spark est un
  brouillon : relire et tester avant d'intégrer (nuit du 03 au 04/10, lot O4 : son application d'un diff avait atterri
  au mauvais endroit).

---

## 3. Règles de sécurité : non négociables

1. **Mots de passe.** Tu ne saisis jamais un mot de passe, et tu n'en manipules jamais un, même si David le colle
   dans le chat : refuse et renvoie-le vers un script qui le lit masqué (`read -s`). Le mot de passe Windows de
   `labadmin` ne passe que par `outils/labo/mac/autologon.sh`, lancé par David. Les identifiants AD des phases 3 et 4
   sont saisis par David lui-même dans Pesto, sur la console de la VM. Tu ne lis jamais un fichier de mot de passe
   désigné par une configuration de VM.
2. **Réglages système et de sécurité de Windows** (ouverture automatique, Windows Update, UAC, Defender, pare-feu,
   stratégies, Hyper-V de l'hôte) : tu ne les modifies pas toi-même. Ils passent par les scripts de David
   (`outils/labo/mac/autologon.sh`, `windows_update.sh`) ou par lui. Exception passée, sur son feu vert : le
   contraste élevé a été basculé pour tester X5, puis remis à son état d'origine (flags 126). Redemande avant de
   refaire ce genre de chose.
3. **Écrans de consentement** (écran de confidentialité Windows, comptes Microsoft, cookies) : l'option la plus
   protectrice. L'écran « Microsoft account » (WWAHost) ne répond pas aux clics simulés : `taskkill /IM WWAHost.exe /F`,
   ne rien accepter.
4. **Tests Windows sur la VM seulement**, jamais sur l'hôte du labo (`DESKTOP-285EKHU`) ni sur le Mac.
5. **Machines des autres sessions.** `PESTO-W11-TEST` est à nous. `LABO-DC01` est **partagé** (sessions Domenia et
   FILPRO, via `LABO-W11-01`) : ne l'arrête, ne le sauvegarde ni ne le modifie sans accord, et vérifie toujours
   `VBoxManage list runningvms` juste avant d'y toucher. `LABO-W11-01` et `FILPRO-W11-TEST` : n'y touche pas.
   Toute écriture dans l'AD `labo.local` (jonction, objets de test, OU) est une mutation d'un DC partagé : accord
   explicite de David et OU de test dédiée d'abord.
6. **Honnêteté des preuves.** Toujours dire où ça a tourné : Windows PowerShell 5.1 sur la VM, PowerShell 7, Python ou
   doubles C sur le Mac. Ne jamais annoncer recette Windows, signature ou clôture des 90 points sans preuve. « Compilé »,
   « empreintes cohérentes » et « tests de chaînes verts » ne veulent pas dire « fonctionne ».
7. **Fichiers.** Jamais de dossier créé dans `~/Downloads` (le clone `~/Downloads/Pesto_V1_CLAUDE_CODE` a disparu le
   04/10 à 14:27, rangement externe). Ne jamais garder de travail non poussé. Ne rien supprimer sans l'avoir regardé.
8. **Git.** Commits limités aux fichiers de la tâche, messages en français, branche `cloud/points-suite`. Pas de
   force-push, pas de fusion vers `master`, pas de PR sans demande de David. Ne pas commiter `wad/cfg.json` (ignoré
   par Git : une configuration réelle ne doit jamais y entrer).
9. Toute action irréversible ou visible de l'extérieur (publication, message, achat, effacement) : demander d'abord.

---

## 4. Le produit en deux minutes

```
DEV/
  Pesto.exe                 lanceur natif x64 (non versionné : .gitignore ; à reconstruire)
  wad/                      moteur : Pesto-Core.ps1, Pesto-Startup.ps1, Pesto-Shell.xaml, Pesto-Join.*, …
  wad/package.json          manifeste (empreintes, FileVersion)
  wad/cfg.json              configuration (ignorée par Git ; modèle dans tools/cfg.template.json)
  tools/launcher/           Pesto-launcher.c, pesto_verify.h, pesto_sha256.h, pesto_runtime.h (généré, VERSIONNÉ),
                            test_entry.c (doubles de l'API Windows), build_native.py, last-build.json (VERSIONNÉ)
  tools/                    refresh_manifest.py, update_installation.py, Build-PestoPacks.py, stamp_version.py, …
  tests/                    test_*.py (Python), Run-*.ps1 (PowerShell 5.1), ux/login static checks
  *.cmd                     DEMO.cmd, TESTER.cmd, VERIFIER_UAC.cmd, Pesto_COMPTE_AD.cmd, APERCU_LOGIN.cmd, …
  docs/V1_*.md              guide, recette, bilan, constats, 90 points
outils/                     parse_all.ps1, ps_symbols.py, reprise_locale.sh, labo/ (pilotage de la VM)
preuves/                    preuves datées (vm-2026-10-02, -03, -03-phase2, -04, windows-hote-2026-10-02, …)
```

- `Get-PestoRuntimeFiles` (`wad/Pesto-Integrity.ps1`) liste **38 composants** : `Pesto.exe` et 37 fichiers de
  `wad/`. Le lanceur incorpore les empreintes des 37 de `wad/` (`PESTO_RUNTIME_COUNT 37` dans `pesto_runtime.h`) ; le
  manifeste, `refresh_manifest.py --check` et `--check-json` vérifient les 38. Un octet changé dans l'un des 37 de
  `wad/` → refus du lanceur (code 125) ; dans `Pesto.exe` → refus par le manifeste côté PowerShell (code 1). Les fichiers **ajoutés** dans `wad\` ne sont pas
  refusés (constat L6, accepté sous conditions).
- **Après toute modification d'un composant de `wad/`** : `build_native.py` **puis** `refresh_manifest.py`, et commiter
  `wad/package.json`, `tools/launcher/pesto_runtime.h`, `tools/launcher/last-build.json` avec le changement (oubli de
  `pesto_runtime.h` le 03/10 : commit de rattrapage).
- Chaîne de build du Mac : Homebrew clang/lld 23.1.2. **Mettre `/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin`
  en tête du `PATH`**, sinon le clang d'Apple (sans `lld-link`) est pris. Mêmes sources + même chaîne = même EXE
  (vu plusieurs fois) ; une autre version de LLVM donne d'autres octets (le cloud, clang 18, produisait `61ee7366…`).
  L'EXE et le manifeste livrés viennent donc du Mac.
- Commandes (depuis `DEV/`) :

```bash
export PATH=/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH
python3 tools/prepare_dev.py                          # clone neuf : crée wad/cfg.json depuis le modèle s'il manque
python3 tools/launcher/build_native.py                # EXE
python3 tools/refresh_manifest.py                     # manifeste, toujours APRÈS le build
python3 tools/refresh_manifest.py --check
python3 -m unittest discover -s tests -p "test_*.py"   # 229 tests OK au 04/10
python3 tools/checks/validate_pesto.py                 # 340 contrôles OK (parseur PowerShell NOT_RUN sur le Mac)
python3 tools/checks/run_native_portable.py            # 48 scénarios C avec doubles de l'API Windows
python3 tests/ux_static_checks.py --report <scratch>   # 50/50 ; toujours --report hors du dépôt
python3 tests/login_compact_static_checks.py --report <scratch>   # 33/33 et 9/9
```

  Plusieurs outils réécrivent des fichiers versionnés : les contrôles statiques (sans `--report`),
  `validate_pesto.py` (`tests/pesto-portable-validation.json`, toujours), `run_native_portable.py`
  (`tools/launcher/pesto_runtime.h` et `tests/rc23-native-portable.json`). Sur un arbre cohérent et sans `powershell` ni `pwsh` dans
  le `PATH` (cas du Mac), ils réécrivent à l'identique ; avec pwsh, `validate_pesto.py` ajoute la passe parseur et
  réécrit son rapport autrement (407 contrôles) ; après une modification de `wad/` sans rebuild, `pesto_runtime.h` serait désaccordé de l'EXE. Toujours
  build → manifeste → suites, puis `git status` avant de commiter.
  `shasum -a 256 Pesto.exe` à consigner à chaque build copié sur la VM.
- Sous Windows (VM) : `Pesto.exe --check`, `--check --quiet`, `--check-json <fichier>`, `TESTER.cmd`,
  `powershell -NoProfile -ExecutionPolicy RemoteSigned -File tests\Run-StabilisationTests.ps1` (sans
  `-ExecutionPolicy`, la stratégie Restricted par défaut refuse le script).
- Règles métier (rappel de `CLAUDE.md`) : jonction locale et renommage unitaire sans file ; même site = renommage seul ;
  nouveau site = déplacement **seulement après** renommage confirmé ; en domaine = connexion Windows intégrée après UAC ;
  hors domaine = compte AD explicite ; aucun redémarrage, retrait Entra ou changement de sécurité implicite ; un
  résultat incertain ou tardif n'est jamais un succès ; aucun verrou effacé pour débloquer ; ne jamais renommer ni
  effacer `cfg.json`, préférences, journaux, reçus, identifiants historiques GP.
- Codes de résultat des opérations : 10/20/77 succès avec redémarrage requis, 30/33 déplacement vérifié, 32 protection
  non rétablie, 89 renommé mais déplacement à reprendre, 96 non lancé, 97 incertain, 98/99 technique.
- Codes de sortie du lanceur (L4, depuis le 04/10 ; table complète dans `V1_GUIDE.md`) : codes de PowerShell transmis
  tels quels (0, 1, 20 plan invalide, 1223 UAC annulée ; sonde UAC 2 et 3) ; lanceur : 120 paramètres, 121 chemin en
  argument, 122 emplacement du lanceur, 123 racine d'un lecteur, 124 composant de démarrage absent, 125 empreintes,
  126 verrou de mise à jour, 127 verrou invérifiable, 128 déjà ouvert, 129 contrôle d'instance, 130 PowerShell 5.1
  introuvable, 131 PowerShell non lancé, 132 code illisible, 133-139 réservés. Modes silencieux (`--quiet`,
  `--check-json`, `--validate-plan`) : aucune fenêtre, sauf 120 sur ligne de commande illisible ; `--help` et
  `--version`, quand ils sont atteints, affichent leur fenêtre (code 0) même avec `--quiet` (les refus d'emplacement et
  un argument invalide placé avant passent en premier).

### Pièges PowerShell 5.1 rencontrés (tous corrigés là où vus)

- `@()` autour d'une liste générique créée par `New-Object` → « Argument types do not match » : utiliser
  `[System.Collections.Generic.List[T]]::new()` (9 occurrences corrigées dans `wad/`, `2d5c182`).
- `$PSScriptRoot` est vide dans les valeurs par défaut de `param()` : calculer le chemin dans le corps du script.
- `.ps1` sans BOM lu en ANSI : **UTF-8 avec BOM** obligatoire ; nouveaux fichiers en BOM + CRLF ; ne pas normaliser
  les fins de ligne des fichiers existants.
- Pas de `?:`, `??`, `&&`, `||`, `?.` ; C# 5 dans `Add-Type`. Littéral `0x80000000` : passer par `[uint32]`.
- Pas d'affectation de variable automatique (`$home`, `$args`, `$matches`, `$input`, `$event`, `$pwd`).
- Fonctions appelées dans un worker : à déclarer dans les listes de sources du worker (`$script:PestoWorkerCoreNames`…).
- `Get-ChildItem -Filter *.ps1` reconnaît aussi `*.ps1xml` sous Windows (filtre Win32 : une extension de trois
  caractères reconnaît les plus longues) ; filtrer `$_.Extension -eq '.ps1'` (corrigé le 04/10 dans `parse_all.ps1` et
  `validate_pesto.py`).

---

## 5. État du dépôt

- GitHub `M4D135/pesto`. Branche de travail **`cloud/points-suite`**, 43 commits devant `master` (`da1c3f3`) à la dernière mise à jour de ce
  fichier (`git log --oneline origin/master..HEAD`), non fusionnée, sans PR. Branches `cloud/docs-1.0` et `cloud/revue-b-c-e-v1` : anciennes, déjà reprises.
- Dernier EXE : **`8fd5bd8cf914058f1f0b84a95f43536ff91c4dc2718c6c67f411bb24b7fd7ca0`** (113 664 octets, `abd6c2e`,
  clang/lld 23.1.2). Reconstruit vers 17 h sur un clone neuf : mêmes octets. Même empreinte sur la VM dans
  `C:\PestoTest`. `last-build.json` porte
  `WindowsExecution: NOT_RUN` (champ jamais mis à jour à la main ; les preuves sont dans `preuves/`).
- Suites sur le Mac au 04/10 : 229 tests Python OK (228 à `abd6c2e`), 340 contrôles portables, 48 scénarios C, UX 50/50, connexion 33/33
  et 9/9.

| Commits | Contenu | Vu sous Windows 5.1 ? |
|---|---|---|
| `d7ebaa0` … `4a26b8c` (02/10, cloud) | Points 87, 36, 79/77, 01 ; porte PSScriptAnalyzer ; lanceur `--quiet` et racine de lecteur ; `update_installation --recover` ; `DEBLOQUER_TOUT` borné | Phases 0-1 seulement |
| `41e4543`, `9ee3fe2` | `outils/reprise_locale.sh` ; premier EXE du Mac sur cette branche `8c723efb…` (un build Mac antérieur, `8590640c…`, visait la PR n° 1) | — |
| `25ae335`, `c4b5b20`, `ebc19e0`, `0ef956a` | Phases 0 et 1 jouées sur la VM ; test `DEBLOQUER_TOUT` corrigé ; chaînes du PE (décision 1.4) | Oui (`preuves/vm-2026-10-02/`) |
| `ce3d013`, `a76443c` | L2 (racine ouverte en `FILE_LIST_DIRECTORY`, partage 3) et O12 (`Pesto_COMPTE_AD.cmd` sans `call`) ; L1 non reproduit | Oui (`preuves/vm-2026-10-03/`) |
| `2d5c182`, `5bb0ba7` | Mode démo en erreur fatale (2.1) ; pages et palette exposées à UI Automation | Oui |
| `d86cfe3`, `f2c8505`, `556bda8`, `ca7ba5b`, `81a8e7b` | Phase 2 partielle ; listes déroulantes accessibles ; `$PSScriptRoot` | Oui (`preuves/vm-2026-10-03-phase2/`) |
| `23360f8`, `9ea9c99` | P1, P2, P3 (fiches) ; O4 (refus de retour en arrière, `--allow-downgrade`) | P1-P3 oui ; O4 Mac seulement |
| `11bc7d7` | O9, O10 (liens, jonctions, noms Windows dangereux ; Python) | Non (pas de Python sur la VM) |
| `d4b6be1`, `daeed5e`, `07fbab0`, `c86381d` | P5 (aperçu et tests de connexion), suites préférences et UX, P7 (textes d'aide), contrôles statiques | En partie (messages de commit) |
| `0a54ff2`, `5e9c357`, `d3c8967`, `ab2be8d` | O8 (files de lots signalées par l'aperçu de mise à jour), T1 ; CHANGELOG et bilan alignés | Non (Python) |
| `abd6c2e` | L4 (codes 120-132), X5 (anneaux en contraste élevé), O7 (sonde UAC), décisions L1/L6 ; correctif `--quiet` à la racine d'un lecteur | Oui (`preuves/vm-2026-10-04/`) |
| `64ef559` | Conditions L6 dans le guide, vérifiées sur la VM ; résultats Windows L4, X5, O7 | Oui |
| `786136c` | Relais ; `outils/labo/` versionné ; exception `--quiet` du guide corrigée ; traçabilité de la recette | — |
| dernier commit (ce fichier mis à jour) | Recette 1.1 à 1.7 rejouée sur `8fd5bd8c…` ; filtre `.ps1xml` des passes du parseur corrigé (66 fichiers sous 5.1) ; P8 inscrit ; scripts de labo corrigés ; corrections des relectures adverses du relais | Oui (`preuves/vm-2026-10-04-phase1/`) |

---

## 6. Recette (`DEV/docs/V1_RECETTE_WINDOWS.md`) : où on en est

| Phase | État au 04/10 |
|---|---|
| 0 Traçabilité | Remplie (build Windows 26200.6584, PS 5.1.26100.6584 Desktop, .NET 4.8.1, EXE successifs). |
| 1 SSH, sans interface | Tout PASS sauf 1.8. 1.1 à 1.7 rejouées le 04/10 vers 17 h sur le dernier EXE `8fd5bd8c…` (stabilisation 24/24 dont les 3 cas O7, `TESTER.cmd` 239 OK/PASS, `TEST_RC23.cmd` 65 PASS ; `preuves/vm-2026-10-04-phase1/`) ; 1.9 et 1.10 joués sur `8c723efb…` (02/10) et `e31dbb9f…` (03/10), pas sur `8fd5bd8c…` ; 1.11 à 1.13 sur `8fd5bd8c…`. **1.8 non joué** : pas de Python sur la VM (seul l'alias du Store). |
| 2 Interface sans mutation | Jouée sur les builds successifs du 03 et du 04/10 (jamais en entier sur `8fd5bd8c…`). 2.1 FAIL puis PASS ; 2.2 PASS ; **2.3 FAIL** puis suites corrigées (P5), **non rejoué en recette** ; **2.4 bloqué** (P6) ; **2.5 partiel** (100 % seulement ; 125-200 % et RDP non joués) ; 2.5b à 2.8 PASS ; **2.9 partiel** (invite UAC vue, pas de réponse) ; 2.10 PASS ; **2.11 et 2.12 non joués**. |
| 3 Domaine, UAC, lectures AD | Rien. Exige les identifiants AD saisis par David et une session console. |
| 4 Mutations réelles | Rien. Instantané à froid avant ; objets et OU de test dédiés ; accord de David (DC partagé). |
| 5 Robustesse | Rien (5.6 couvert en partie par L4 : code 126 vu). |

Ce qui n'est **pas** prouvé (détail : `V1_BILAN.md` §8) : aucun démarrage élevé accepté ; aucun AD ni Entra réel ;
aucune mutation ; registre, ACL et partages jamais exercés en réel ; outillage Python jamais exécuté sous Windows ;
interface pilotée par UI Automation sans relecture humaine ni lecteur d'écran ; EXE non signé.

---

## 7. Constats et décisions (`V1_CONSTATS_OUVERTS.md`)

- **Clos** (2-4/10) : V1, L2, O12, P1, P2, P3, O4, O8, O9, O10, P5, T1. P7 (textes d'aide), corrigé le 04/10
  (`07fbab0`), n'a jamais été inscrit aux constats.
- **Risques acceptés sous conditions (04/10, délégation de David)** :
  - L1 : le lanceur refuse tout point d'analyse ; faux refus non reproduit (WOF et compression NTFS acceptés).
    Piste « name surrogate » (refuser seulement les balises de point d'analyse de type nom de substitution, `0x20000000`,
    lues par `GetFileInformationByHandleEx(FileAttributeTagInfo)` sur le handle déjà ouvert) : décrite, **aucun code
    conservé** (le brouillon vivait dans un dossier temporaire effacé). Rouvrir si un refus est vu sur un poste réel.
  - L6 : fichiers ajoutés dans `wad` non refusés. Conditions dans `V1_GUIDE.md` (« Emplacement et droits ») : pack
    sous `%ProgramFiles%`, hors dossier synchronisé, `icacls` / `Get-Acl` avant mise en service. Vérifiées le 04/10
    sur un pack PROD de test. Rouvrir si le pack doit vivre dans un dossier inscriptible par les utilisateurs.
- **Traités et vus sous Windows le 04/10** : L4 conforme (0, 120, 123, 124, 125, 126, 128 ; non provoqués : 121,
  122, 127, 129-132) ; X5 vu sur le bouton de menu actif et le focus clavier (**onglet actif non capturé**) ;
  O7 vu jusqu'à l'invite UAC (**Accepter et Refuser à faire par un humain**).
- **Ouverts** : P6 (`--consult` hors domaine avec le `cfg.json` modèle ouvre « Corriger la configuration » ; rejouer
  2.4 avec une configuration validée du labo) ; P8 (Ctrl+Tab et Ctrl+Page suivante ne changent pas de page ; vu le
  03/10, inscrit le 04/10 ; décider si ces raccourcis sont attendus) ; LAB (Hyper-V sur l'hôte → VirtualBox en NEM ;
  décision de David).

---

## 8. Le labo

| Machine | Rôle | Accès |
|---|---|---|
| Mac de David | Clone, build, tests portables, pilotage | — |
| `DESKTOP-285EKHU` (`degun@192.168.1.173`) | Hôte VirtualBox 7.2, Hyper-V actif (NEM). VM dans `C:\ADCC-Lab\VirtualBox\` | SSH par clé |
| `PESTO-W11-TEST` | **Notre VM de test** : Windows 11 Entreprise Évaluation 25H2 (26200.6584), groupe de travail `LABO`, 10.77.0.30 | `outils/labo/mac/g.sh` (rebond, NAT `127.0.0.1:2223`, `labadmin`) |
| `LABO-DC01` | DC `dc01.labo.local`, 10.77.0.10. **Partagé** | Ne pas toucher sans accord |
| `LABO-W11-01` | Autre session (Domenia/FILPRO), 10.77.0.20 | Ne pas toucher |
| `FILPRO-W11-TEST` | Session FILPRO (clone de notre instantané 02), 10.77.0.40, NAT 2224 | Ne pas toucher |

Réseau interne VirtualBox `LABO-LAB`, sans DHCP. **L'instantané 02 porte encore l'IP 10.77.0.20** (conflit avec
W11-01) : après une restauration, remettre 10.77.0.30 avant de brancher le réseau.

Instantanés de `PESTO-W11-TEST` : `00-clone-brut` → `01-ssh-ok-sysprep-bloque` → `02-groupe-de-travail-pret` (courant,
pris à froid le 02/10). SID non changé (sysprep bloqué) : sans effet attendu sur la jonction (proposition non validée).

**Instantanés à froid seulement** : arrêt propre de l'invité, puis sur l'hôte
`VBoxManage snapshot PESTO-W11-TEST take <nom> --description "…"`, puis `VBoxManage startvm PESTO-W11-TEST --type
headless`. Jamais `--live`, jamais `controlvm pause` pendant un instantané : le 02/10, un instantané à chaud a tourné
3 h 40 sans converger, une pause a figé la VM et il a fallu tuer le processus. `savestate` non live prend ~11 s.

### État de la VM à la fin de cette session (04/10, 17 h 33)

- **Éteinte proprement à 17:33** (après un dernier démarrage, normal cette fois, pour expliquer l'écart 66/68
  `.ps1`). Ouverture automatique **retirée** par David à 16:50 (`AutoAdminLogon=0`, aucun `DefaultPassword` en clair ;
  revérifié à 17:18 et 17:33). `NoAutoUpdate=1` maintenu pour la suite de la recette
  (`windows_update.sh --retablir` pour le lever, David).
- Démarrée vers 17 h 04 pour rejouer la phase 1, elle s'est figée aussitôt (3 vCPU à 100 %, SSH muet 11 min, écran
  noir, aucune session) ; `VBoxManage controlvm PESTO-W11-TEST reset` l'a rétablie (SSH en 25 s). Son horloge
  retardait ensuite d'environ 11 min. Si elle ne répond pas en SSH 5 min après un démarrage : capture
  (`controlvm … screenshotpng`), charge CPU du processus sur l'hôte, puis réinitialisation (VM de test seulement).
- `C:\PestoTest` = DEV de `786136c` (composants identiques à `abd6c2e`), EXE `8fd5bd8c…`. Anciens packs : `C:\PestoTest-9ee3fe2`. Copies jetables L4 :
  `C:\PC\L4\`. Pack PROD de test : `C:\Program Files\Pesto-PROD-test` (EXE intermédiaire `8c4592dd…`), laissé en place.
- Outils de pilotage : `C:\PestoTest-run\`, recopiés depuis `outils/labo/vm/` le 04/10 vers 17 h (`eveil.ps1` de la VM
  était rempli de zéros après un ancien arrêt brutal). Preuves brutes : `C:\PestoTest-preuves\`. `C:\outils\` =
  `outils/` du dépôt (sans `labo/`), pour `parse_all.ps1` (recette 1.1).
- `LABO-DC01`, `LABO-W11-01` et `FILPRO-W11-TEST` tournaient à 17:33 ; aucun n'a été touché.
- `outils/labo/vm/lancer.ps1` corrigé le 04/10 (attente du vrai démarrage aussi avec `-Attendre`) : **pas encore
  essayé**, faute de session console ouverte. Le vérifier au premier `run.sh` de la prochaine campagne.
- Clone de travail sur le Mac : `~/Projects/pesto` (le scratchpad de session est vidé entre deux sessions : n'y laisser
  rien d'unique). `known_hosts` de la VM : `PESTO_KNOWN_HOSTS` (par défaut `~/.ssh/known_hosts_pesto`, rempli au
  premier contact).

### Piloter l'interface sans humain

Une session SSH est en session 0, élevée et sans bureau : WPF, UAC et captures n'y ont pas de sens. Méthode qui a
marché (scripts dans `outils/labo/`) :

1. David ouvre une session console de `labadmin` (ou l'ouverture automatique la donne au démarrage de la VM).
2. `mac/envoyer.sh` copie un script d'étape `.ps1` dans `C:\PestoTest-run\`.
3. `mac/run.sh etape.ps1` le lance **dans la session console** par une tâche planifiée `Interactive` à jeton non
   élevé (`vm/lancer.ps1`), et attend la fin.
4. L'étape utilise `vm/pilote.psm1` : `Wait-Fenetre`, `Get-Arbre` (UI Automation), `Invoke-Element`,
   `Send-Touches`, `Save-Ecran`, `Get-Focus`. Elle écrit sa sortie et ses captures dans `C:\PestoTest-preuves\…`.
5. `mac/recuperer.sh` rapatrie ; relire les captures soi-même avant de conclure.

Repères : premier rendu WPF > 1 min sur cette VM (attendre 90 s avant de parler de « fenêtre blanche ») ; la VM s'est
figée trois fois ~30 min après l'ouverture de session (enchaîner vite) ; `obs.ps1` compte les connexions TCP vers
le DC (la démo doit en avoir 0) et la présence de `consent.exe` (invite UAC) ; l'invite UAC est sur le bureau
sécurisé, hors d'atteinte des captures et des clics simulés.

---

## 9. Méthode qui a fait ses preuves

1. Une phase de la recette à la fois. Consigner chaque ligne aussitôt : résultat exact, date et heure de la VM,
   fichier de preuve, remarque. Ce qui n'a pas été vu exactement comme attendu s'écrit tel quel (PARTIEL, FAIL,
   NON JOUÉ, avec la raison).
2. Défaut trouvé sous 5.1 : le reproduire ; écrire le test qui échoue sur l'ancien code (Python, scénario C dans
   `test_entry.c` + `run_native_portable.py`, ou suite `.ps1`) ; corriger ; reconstruire EXE et manifeste ; suites du
   Mac ; recopier sur la VM ; vérifier sous 5.1 ; commit avec preuves.
3. Après un changement de comportement, **chercher dans tous les documents** les phrases qui le décrivent (`grep`) :
   le 04/10, le guide décrivait encore l'ancien comportement de `--quiet` après le correctif du jour même.
4. Relecture adverse de ses propres correctifs avant de commiter (un relecteur indépendant : agent, Spark ou second
   passage), puis vérification par l'exécution.
5. Chaque lot met à jour `V1_CONSTATS_OUVERTS.md`, la recette, `V1_BILAN.md`, `DEV/CHANGELOG.md` et la section État
   de `CLAUDE.md`. Preuves : `preuves/vm-<date>/` avec un `LIRE.md` (contexte, EXE, tableau constat → résultat →
   fichier). Noter l'empreinte de **chaque** EXE utilisé (le 04/10, le pack PROD de test venait d'un build
   intermédiaire).
6. Fichiers texte rapatriés de la VM : souvent en UTF-16 avec BOM (`iconv -f UTF-16LE -t UTF-8`).

---

## 10. Erreurs commises pendant cette session : ne pas les refaire

- Pause d'une VM pendant un instantané à chaud → VM figée, processus tué (disque sauvegardé avant).
- Affirmations non vérifiées, rattrapées ensuite : « les journaux non élevés vont dans `%LOCALAPPDATA%` » (faux, vérifié
  sur la VM) ; une ligne du CHANGELOG sur O4. Vérifier avant d'écrire.
- Faux positifs d'interface : « fenêtre blanche » (rendu lent, pas une régression) ; un raccourci Ctrl+K « cassé »
  (artefact de ma propre astuce Alt dans le pilote).
- Tuer `consent.exe` n'équivaut pas à cliquer « Non » : Windows rend « Incorrect function » au lieu de 1223, et Pesto
  affiche « démarrage impossible ». Ne pas présenter ce résultat comme un refus d'UAC.
- `stop.ps1` tuait son propre `cmd` parent ; `lancer.ps1` désinscrivait la tâche avant son démarrage ; le répertoire
  courant d'`eveil.ps1` verrouillait `C:\PestoTest` : corrigés dans `outils/labo/vm/` (`lancer.ps1` prend désormais
  `C:\PestoTest-run` comme répertoire courant par défaut).
- Commande `ssh` rangée dans une variable sous zsh (pas de découpage) ; `powershell -Command -` qui ignore les lignes
  multiples ; guillemets `cmd` via SSH : passer par des fichiers `.ps1` copiés.
- `pesto_runtime.h` oublié dans un commit après un build.
- Réponse du Spark intégrée sans relecture : un diff placé au mauvais endroit (signature de `plan_update`).
- Travail laissé dans le scratchpad de session : il est vidé quand la session redémarre (le 04/10 vers 17 h, clone,
  scripts d'accès et `known_hosts` perdus ; rien de non poussé, heureusement). Cloner dans `~/Projects/`.
- Résultat annoncé « vu » alors qu'une partie manquait : la relecture du relais a trouvé un onglet actif X5 non capturé,
  un compte de composants mal expliqué, un total de contrôles repris de `master`. Relire chaque chiffre à sa source.

---

## 11. Prochaines étapes, dans l'ordre recommandé

### A. À la reprise (état attendu : VM éteinte, ouverture automatique retirée)

1. Après démarrage de la VM, vérifier que l'ouverture automatique est bien retirée :
   `outils/labo/mac/g.sh 'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon'`
   (attendu `0x0` ou `0`). Sinon, demander à David `bash outils/labo/mac/autologon.sh --retirer`.
2. VM éteinte entre deux campagnes (`g.sh 'shutdown /s /t 0'`, puis `VBoxManage showvminfo PESTO-W11-TEST
   --machinereadable | findstr VMState` sur l'hôte).

### B. Sans identifiants AD (David : ouverture automatique, et accords signalés ligne par ligne)

Demande d'abord à David de réactiver l'ouverture automatique (`autologon.sh`) pour la durée de la campagne, puis de la
retirer à la fin.

1. **2.11** : `Pesto.exe --inconnu` en session console → fenêtre « Pesto 1.0 | Demarrage » terminée par « Code de
   sortie du lanceur : 120. », code 120 (capture + code).
2. **X5, onglet actif** : capture en contraste élevé d'une page à onglets (le reste de X5 est vu). Le contraste élevé
   est un réglage Windows : redemander le feu vert, remettre ensuite les flags d'origine (`vm/hc126.ps1`).
3. **2.3 rejoué en recette** (`APERCU_LOGIN.cmd`, suites de connexion corrigées par P5).
4. **2.5, échelles 125 à 200 %** : changer l'échelle impose de fermer la session ; c'est un réglage d'affichage de la
   VM, à faire avec l'accord de David (ou par lui).
5. **P6 / 2.4** : écrire une `cfg.json` de labo (domaine `labo.local`, DC `dc01.labo.local`, OU de test à définir
   avec David) en partant de `wad/Pesto-Configuration.ps1` et du guide ; la poser sur la VM seulement, jamais dans
   Git ; rejouer 2.4 (`--consult`).
6. **1.8** : installer Python sur la VM (téléchargement d'un exécutable : accord de David, source officielle
   python.org) puis `python tools\checks\validate_pesto.py --require-parser` (407 attendus sur cette branche : 340 +
   le parseur + 66 `.ps1`, compte vérifié sous 5.1 le 04/10 après le correctif du filtre `.ps1xml` ; la recette disait
   408, chiffre de `master`) ; l'outillage
   Python (O4, O8, O9, O10, `update_installation.py`) n'a jamais tourné sous Windows.

### C. Exige David à la console de la VM (clic humain ou identifiants)

1. **2.9 (O7)** : `VERIFIER_UAC.cmd` par double-clic en session **non élevée** ; Accepter → fenêtre « Pesto - sonde
   UAC » `UAC_OK`, Admin=True, reçu `wad\logs\Pesto-sonde-uac-<jeton>.txt`, code 0 ; puis Refuser → code 1223, aucun
   reçu. Tu peux tout préparer et lire les résultats ; seul le clic est à lui.
2. **2.12** : `VERIFIER_UAC.cmd` pendant qu'un Pesto normal (UAC acceptée) est ouvert → contrôle préalable accepté,
   aucune nouvelle invite UAC, fenêtre « Pesto | Deja ouvert », message « ECHEC : Pesto est déjà ouvert depuis ce
   dossier (code 128 du lanceur) » et code de sortie **1** du script (le lanceur, lui, rend 128).
3. **Phase 3** (domaine, UAC, lectures AD) : instantané à froid avant ; David saisit ses identifiants AD dans Pesto.
   3.2 hors domaine (`Pesto_COMPTE_AD.cmd` en DEV) est le premier pas ; 3.1 exige une VM jointe au domaine.
4. **Phase 4** (mutations réelles : jonction, renommage, déplacement, reprises) : instantané à froid, OU et objets de
   test dédiés dans `labo.local`, accord explicite de David (DC partagé). Premier test : 4.1 avant jonction.
5. **LAB** : décision de David (désactiver Hyper-V sur l'hôte ou changer d'hyperviseur).

### D. Après la recette

1. Phase 5 (robustesse) sur une VM jetable ou un instantané.
2. Packs PROD/DEV livrables depuis le Mac (`python3 tools/Build-PestoPacks.py --source . --output <neuf>`), SHA-256
   consignés ; jamais avec une `cfg.json` réelle dans la source.
3. `V1_90_POINTS.md` : statuts mis à jour sur preuve seulement. Signature de l'EXE (point 23) : décision de David.
4. Proposer à David la fusion de `cloud/points-suite` vers `master` (PR), avec un résumé des preuves.

---

## 12. Fin de chaque session

- Tout est commité et poussé ; `git status` propre ; aucune modification hors du périmètre.
- Recette, constats, bilan, CHANGELOG et `CLAUDE.md` (État) disent la même chose que les preuves.
- Ouverture automatique retirée (vérifiée par `reg query`), processus de pilotage arrêtés (`vm/stoppilote.ps1` :
  étapes de `C:\PestoTest-run` et `eveil.ps1` ; `vm/qui.ps1` : processus lancés depuis `C:\PestoTest`), VM éteinte
  proprement ; `LABO-DC01` laissé dans l'état trouvé (partagé ; décision du 02/10, la recette est alignée).
- Un dernier message à David : ce qui est fait et vérifié, ce qui ne l'est pas, ce qui l'attend (commandes prêtes).
