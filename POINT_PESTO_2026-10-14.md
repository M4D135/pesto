# Point du projet Pesto — 14 octobre 2026, 00 h 08 (CEST)

Relevé **en lecture seule** sur le Mac `192.168.1.128` (`MacBook-Air-de-Mua.local`), clone
`/Users/david/Projects/pesto`. Aucune commande d'écriture, de build, de test ou de git n'a été
exécutée sur le dépôt. Méthode : `git status --porcelain` (puis `-uall`), `git diff --numstat`,
`git rev-list --left-right --count`, `git fetch`, lecture des rapports de preuves et des logs de
`work/`.

## 1. Synthèse

Le chantier des **120 améliorations** est écrit et un candidat a été construit jusqu'à **C4**, mais
**rien n'est livré** : 0 des 120 points est réconcilié, 2 tests CLI restent en échec, les guides
rendus sont antérieurs au dernier candidat, aucune mutation AD réelle n'a été rejouée sur le build
final, et les 8 constats de la revue Spark sont tous en attente d'arbitrage.

**Le GitHub ne contient que le catalogue.** Tout le reste du chantier — code, bancs, docs
d'implémentation, preuves, candidats — vit en une seule copie sur le Mac, hors commit.

| Élément | État mesuré |
| --- | --- |
| Branche | `master` |
| HEAD | `221e050` — « Document the complete 120 point Pesto improvement plan » (13/10 20:40) |
| Synchronisation GitHub | `origin/master` = HEAD, **0 devant / 0 derrière** |
| Index (staged) | **0 fichier** |
| Entrées `git status` | **158** = 79 modifiées + 79 non suivies |
| Fichiers réels non suivis | **657** (99 hors `preuves/` + 558 dans `preuves/`) |
| Volumétrie texte modifiée | **+1 622 / −478** lignes (hors binaires) |

## 2. Avancement réel

| Domaine | État |
| --- | --- |
| Catalogue des 120 points | **120/120 `state: in_progress`, `evidence: []`** — zéro réconciliation |
| Candidats | C2 (21:10, EXE `4bd73854…`) → C3 (22:16) → **C4 (22:23, EXE `7137f4e3307077d23cb03227844211db22568ddafacc204f9dd42e4fd3c33fe0`)** |
| `package-c4.log` | `RuntimeFiles: 62`, `Config: template`, **`WindowsExecution: NOT_RUN`** |
| C2 — local | 405 tests Python PASS · Engine portable 181 PASS · UI portable 110 PASS · intégration 18 PASS · parseur 123 scripts sans erreur |
| Windows C3 | 5 suites comptées : **134 PASS / 4 FAIL / 0 SKIP** — les 4 échecs dans `CliOutput.json` (8/4) |
| Windows C4 | 3 suites comptées : **41 PASS / 2 FAIL / 0 SKIP** — encore `CliOutput.json` (10/2) |
| Guides rendus | DOCX/PDF du dépôt datés de **10 h 24 et 10 h 26** (matin), antérieurs au C4 ; `work/guides-c4/` en cours à 22 h 52-22 h 54, rendu non finalisé |
| Recette GUI | `interactive/` 58 fichiers, `interactive-c3/` 54 fichiers (captures 13→45, thèmes, suivi facultatif, annulation sans changement) |
| Mesure mémoire | `session-c4-60.json` → `Verdict: MEASURED_ONLY`, 60 échantillons, PID 9788 — **aucune conclusion de fuite possible** |
| Mutations AD sur build final | renommage, déplacement, jonction : **non faits** |
| 8 constats de la revue Spark | **aucun arbitré, aucun intégré** |
| Socle commun | `~/Projects/m4d-admin-common` commit local `a050525` (source : relais ; poussée non revérifiée) |

## 3. Fichiers modifiés (79) — `+1 622 / −478`

### Moteur `DEV/wad/` — 27 fichiers

| fichier | +/− |
| --- | --- |
| `package.json` (manifeste) | 98/26 |
| `Pesto-Core.ps1` | 47/17 |
| `Pesto-Workspace.ps1` | 42/10 |
| `Pesto-Preparation.ps1` | 42/2 |
| `Pesto-Automation.ps1` | 32/14 |
| `Pesto-Interventions.ps1` | 31/15 |
| `Pesto-Journal.ps1` | 27/2 |
| `Pesto-Configuration.ps1` | 27/11 |
| `Pesto-Shell.xaml` | 21/21 |
| `common.lock.json` | 21/9 |
| `Pesto-Integrity.ps1` | 19/1 |
| `Pesto-Common.ps1` | 18/8 |
| `Pesto-Direct.ps1` | 15/6 |
| `Invoke-PestoAutoJoin.ps1` | 11/4 |
| `Pesto-Async.ps1` | 9/3 |
| `Pesto-Policy.ps1` | 7/5 |
| `Pesto-Safety.ps1` | 7/4 |
| `Pesto-Contracts.ps1` | 6/2 |
| `Pesto-SuiteUI.ps1` | 6/3 |
| `Pesto-Appearance.ps1` | 6/5 |
| `Pesto-Join.ps1` | 4/2 |
| `Pesto-Review.ps1` | 4/2 |
| `Pesto-JoinRecovery.ps1` | 3/2 |
| `Pesto-Operations.ps1` | 1/1 |
| `support/DEBLOQUER_TOUT.cmd` | 1/1 |
| `M4D.Admin.Common.Core.dll` | binaire, 4 608 → 7 680 octets |
| `M4D.Admin.Common.Query.dll` | binaire, 17 408 octets (contenu changé) |

### Lanceur — 3 fichiers

- `DEV/Pesto.exe` (binaire, modifié)
- `DEV/tools/launcher/pesto_runtime.h` 87/51
- `DEV/tools/launcher/last-build.json` 4/4

→ Le lanceur suivi par Git **est bien le candidat C4** : `DEV/Pesto.exe` vaut
`7137f4e3307077d23cb03227844211db22568ddafacc204f9dd42e4fd3c33fe0`, empreinte identique aux EXE des
packs DEV et PROD de `pesto-120-c4-packs` (mesuré le 14/10). `pesto_runtime.h`, `last-build.json` et
`wad/package.json` portent tous les quatre le même horodatage **22:23:22**, postérieur à la dernière
modification de `wad/` (21:30:55) : l'ordre `build_native.py` → `refresh_manifest.py` est respecté.

### Bancs `DEV/tests/` — 24 fichiers

20 suites PowerShell : `Run-CommonTests` 38/4 · `Run-Pesto21Tests` 9/1 · `Run-OptionalPostCheckTests` 6/1 ·
`Run-HomeDashboardTests` 4/4 · `Run-ZoomTests` 4/4 · `Run-NamesLoadingTests` 4/2 · `Run-PilotageTests` 4/2 ·
`Run-EngineTests` 3/2 · `Run-RandomNamesTests` 3/2 · `Run-SettingsTests` 3/2 · `Run-UxTests` 3/2 ·
`Run-BulkPlanningTests` 3/1 · `Run-JoinTests` 3/1 · `Run-RC4Tests` 3/1 · `Run-InterventionViewTests` 2/2 ·
`Run-ToolsTabsTests` 2/2 · `Async-ScopeFixture.ps1` 2/1 · `Run-LoginPreferencesTests` 2/1 ·
`Run-AllTests` 1/1 · `Run-QueueRemovalTests` 1/1

4 tests Python : `test_update_inputs.py` 37/0 · `test_shared_common.py` 11/4 · `test_reservations_noms.py` 5/1 · `test_distribution.py` 4/2

### Outillage `DEV/tools/` — 9 fichiers

`update_installation.py` 105/22 · `Sign-PestoRelease.ps1` 62/12 · `Build-PestoProduction.py` 6/0 ·
`package_distribution.py` 5/3 · `New-PestoDistribution.ps1` 4/3 · `Build-PestoPacks.py` 1/1 ·
`refresh_manifest.py` 1/1

### Docs & racine — 7 fichiers

`DEV/docs/FABRIQUER_PROD.md` 141/4 · `DEV/docs/SOCLE_COMMUN.md` 64/23 · `DEV/README.md` 31/4 ·
`DEV/LIRE_MOI.txt` 17/1 · `README.md` 19/0 · `CLAUDE.md` 13/0 ·
`DEV/.github/workflows/validate.yml` 53/26

### Guides — 5 fichiers

`outils/guides/administrateur.md` 199/59 · `outils/guides/technicien.md` 78/17 ·
`outils/guides/administrateur.json` 9/9 · `outils/guides/technicien.json` 5/5 · `outils/guides/build_guide.js` 11/4

### Socle commun `DEV/vendor/M4D.Admin.Common/` — 6 fichiers

`tests/Core/CoreTests.cs` 19/0 · `tests/IO/FileIOTests.cs` 7/0 · `README.md` 7/3 ·
`tools/build.ps1` 5/2 · `version.json` 6/3 · `tools/test.ps1` 1/1

## 4. Fichiers non suivis (99 hors `preuves/`)

**Module Engine généré — 5** : `DEV/wad/Pesto.Engine.Runtime.ps1` **12 914 l / 955 Ko** ·
`Pesto.Engine.build.json` 3 282 l · `Pesto.Engine.psd1` 7 l · `Pesto.Engine.psm1` 5 l ·
`Pesto.Engine.exports.json` 10 l — régénérés, jamais édités à la main.

**Nouveaux volets `DEV/wad/` — 14** : `Pesto-Enterprise.ps1` 349 l · `Pesto-Workbench.ps1` 179 l ·
`Pesto-ConfigEditor.ps1` 180 l · `Pesto-Diagnostics.ps1` 164 l · `Pesto-Collections.ps1` 136 l ·
`Pesto-BatchTools.ps1` 135 l · `Pesto-EngineContracts.ps1` 127 l · `Pesto-ReceiptTools.ps1` 94 l ·
`Pesto-NameWorkbench.ps1` 67 l · `Pesto-Catalogue.ps1` 71 l · `Pesto-ManagedPolicy.ps1` 46 l ·
`Invoke-Pesto.ps1` 43 l · `M4D.Admin.Common.IO.dll` · `M4D.Admin.Common.Diagnostics.dll`

**Nouveaux bancs `DEV/tests/` — 14** : `Run-IntegrationTests.ps1` 166 l · `Run-Engine120Tests.ps1` 152 l ·
`Run-CliOutputTests.ps1` 113 l · `Run-Workbench120Tests.ps1` 76 l · `Run-OptionalIntegrationsTests.ps1` 71 l ·
`Measure-Engine120.ps1` 86 l · `Run-BatchNames120Tests.ps1` 53 l · `Run-AuditPathTests.ps1` 51 l ·
`Run-Collections120Tests.ps1` 36 l · `Run-ConfigEditor120Tests.ps1` 38 l · `Run-ReceiptTools120Tests.ps1` 29 l ·
`test_managed_update.py` 254 l · `test_release_120.py` 173 l · `test_checkout_bytes.py` 57 l

**Nouveaux outils `DEV/tools/` — 14** : `release_assurance.py` 155 l · `Build-PestoEngineModule.ps1` 98 l ·
`managed_install.py` 82 l · `installation_receipt.py` 80 l · `qualification.py` 49 l ·
`update_channels.py` 31 l · `scan_evidence.py` 31 l · `rebind_signed_engine.py` 28 l ·
`Capture-PestoQualification.ps1` 30 l · `check_toolchain.py` 19 l · `reproducible_build.py` 16 l ·
`Test-PestoEnvironment.ps1` 14 l · `Measure-PestoSession.ps1` 12 l · `toolchain.lock.json` 11 l

**Docs d'implémentation du lot 120 — 9** : `RELEASE_120.md` 119 l · `CLOTURE_120.md` 114 l ·
`UI_120.md` 91 l · `ENGINE_120.md` 88 l · `QUALIFICATION_120.md` 72 l · `EXTENSIONS_120.md` 64 l ·
`AUTOMATION_120.md` 39 l · `GUIDE_TACHES_120.md` 35 l · `COMMON_020_INTEGRATION.md` 27 l

**Intégrations — 5** : `DEV/integrations/Pesto.Optional.psm1` 120 l · `README.md` 105 l ·
`Invoke-PestoDeployment.ps1` 36 l · `policies/Pesto.admx` 25 l · `policies/fr-FR/Pesto.adml` 14 l

**Socle commun — 22** : `src/Core/Contracts.cs` 76 l · `src/Diagnostics/BoundedJournal.cs` 65 l ·
`src/Wpf/Presentation.cs` 45 l · `src/IO/AtomicFile.cs` 39 l · `tools/release.py` 79 l ·
`tests/test_release.py` 51 l · `docs/COMPATIBILITY.md` 27 l · `tests/Wpf/Run-WpfContracts.ps1` 28 l ·
`tests/Diagnostics/DiagnosticsTests.cs` 29 l · `tools/public_api.ps1` 13 l ·
`validation/catalogue-120/` 5 JSON · `validation/macos-2026-10-12/` 4 JSON ·
`.github/workflows/validate.yml` 47 l · `.gitignore` · `source-commit.txt`

**CI / intégrité — 6** : `.github/workflows/validate.yml` 71 l (racine) ·
`.github/workflows/release-evidence.yml` 39 l · `DEV/.github/workflows/release-evidence.yml` 39 l ·
`.gitattributes` 4 l · `DEV/.gitattributes` 3 l

**Captures des guides — 10** : `outils/guides/images/ui-2026-10-13/` →
`zoom-interface.png` 172 Ko · `confirmation.png` 132 Ko · `renommer-deplacer.png` 116 Ko ·
`renommer-seul.png` 116 Ko · `outils-navigation.png` 99 Ko · `noms-filtres.png` 93 Ko ·
`parametres-noms.png` 93 Ko · `accueil.png` 81 Ko · `parametres.png` 72 Ko · `manifest.json`

**Divers — 1** : `RELAIS_PESTO_2026-10-13.md` 155 l (le doc de passation lui-même est hors Git)

## 5. `preuves/` — 558 fichiers, 76,6 Mo, entièrement hors Git

- `preuves/ameliorations-120-2026-10-13/` — **461 fichiers / 76 Mo** : `local/`, `windows/`,
  `windows-retry/`, `windows-c3`, `windows-c4`, `interactive/` (58), `interactive-c3/` (54),
  `relais/`, `common-windows/`, `updater/`, `release-audit/`
- `preuves/implementation-120-2026-10-13/` — 97 fichiers / 600 Ko

## 6. Ce que cette liste dit (trois lectures)

1. **Le socle commun a bougé des deux côtés.** 2 DLL modifiées (`Core` 4 608 → 7 680 o ; `Query` à
   taille égale mais contenu différent) + 2 DLL nouvelles non suivies (`IO`, `Diagnostics`) + 22
   fichiers source non suivis. `common.lock.json` (21/9) est la trace de verrouillage.
2. **Rien de rendu n'est à jour.** Sources Markdown/JSON des guides modifiées et 10 captures
   nouvelles, mais les DOCX/PDF suivis datent de 10 h 26 et n'apparaissent pas dans la liste : le
   rendu n'a pas été régénéré depuis.
3. **Le lanceur est cohérent avec le dernier candidat.** *Ligne corrigée le 14/10 : elle annonçait
   l'inverse, reprise du relais qui ne connaissait que C2.* Mesuré : `DEV/Pesto.exe` vaut
   `7137f4e3…`, identique aux EXE des packs C4 ; `pesto_runtime.h`, `last-build.json` et
   `wad/package.json` ont été écrits à 22:23:22, après la dernière retouche de `wad/` (21:30:55).
   L'empreinte du lanceur est donc bien celle du build reçu par la VM.

## 7. Risque principal

**Dépassé depuis la poussée décrite en section 13** : le code, les bancs, les docs d'implémentation
et les preuves de recette sont désormais sur GitHub, plus en copie unique sur ce Mac.

Restent **hors GitHub** : le dossier `work/` des candidats (packs C2/C3/C4, logs de build natif,
scripts `pesto_120_c*.py`, `guides-c4/`) et le dépôt `~/Projects/m4d-admin-common` (commit local
`a050525`). Le Mac peut toujours s'endormir ou redémarrer en pleine opération — il est passé par un
arrêt à 01 h 14 et un démarrage à 06 h 35 dans la nuit.

## 8. Où reprendre

| Élément | Emplacement |
| --- | --- |
| Doc de passation | `RELAIS_PESTO_2026-10-13.md` (racine, **non commité**, état à 21 h 36 → déjà périmé sur les candidats) |
| Relevé de l'état local | `preuves/ameliorations-120-2026-10-13/relais/etat-local.json` (21 h 38, figé sur C2) |
| Candidats, packs, logs | `~/Documents/Codex/2026-10-12/tu-x20/work` (`pesto-120-c2|c3|c4-packs`, `build-native-120-*.log`, `pesto_120_c4.py`, `guides-c4/`) |
| Suivi des 120 points | `DEV/docs/implementation/catalogue-120.json` et `AMELIORATIONS_120.md` (seuls fichiers poussés) |
| Socle commun | `~/Projects/m4d-admin-common` ; copie embarquée dans `DEV/vendor/M4D.Admin.Common/` (non suivie) |
| VM de recette | `PESTO-W11-TEST`, UUID `9b2ad4f0-0506-4f58-aed2-c43ac1973516`, 1920×1200, `labo.local`, poste `P111301LY765128` ; copies `C:\Pesto120_20261013`, `C:\Pesto120_Retry_20261013`, `C:\Pesto120_GUI_20261013`, `C:\PestoCommon020_20261013` à préserver |
| Ordre de reconstruction | `tools/Build-PestoEngineModule.ps1` → `tools/launcher/build_native.py` → `tools/refresh_manifest.py` (jamais les fichiers Engine à la main) |

## 9. Séquence restante telle que la prescrit le relais

1. Arbitrer les 8 constats Spark contre le code complet (dont le n° 5, possiblement déjà réfuté par
   le schéma fermé de `Assert-PestoJoinReceiptData`, et le n° 6, à ne pas appliquer automatiquement).
2. Finir les correctifs réels et leurs tests ciblés — en particulier les 2 échecs restants de
   `Run-CliOutputTests.ps1` (`-AsJson` ASCII).
3. Reconstruire Engine, EXE et manifeste dans un nouveau candidat ; rejouer les bancs Windows encore
   en échec et les régressions JSON/diagnostics.
4. Terminer la recette GUI sur le seul poste Pesto, avec captures propres ≥ 1080p et hash de build.
5. Régénérer les deux guides DOCX/PDF (`outils/guides/build_guide.js`) et inspecter toutes les pages.
6. Réconcilier les 120 points avec preuves réelles ; garder explicitement non qualifiés : signature
   sans certificat, autres orchestrateurs, multi-DC, App Control, redistribution, matrice complète.
7. Refaire les packs neutres, assurance et reproductibilité, scan des secrets, puis commit/push
   Pesto et Common **seulement après clôture**.

## 10. Ce qui n'a pas été fait ici

Aucune écriture dans le dépôt **hormis ce fichier de point**, aucun commit, aucun push, aucun build,
aucun test lancé, aucun appel au Spark, aucune mutation sur la VM. Le dépôt est laissé exactement
dans l'état décrit ci-dessus.

## 11. Vérification de stabilité — 14 octobre 2026, 01 h 05 (CEST)

Contrôle en lecture seule effectué après la rédaction de ce point : **rien n'a bougé**.

| Contrôle | Attendu | Mesuré |
| --- | --- | --- |
| HEAD / branche | `221e050` / `master` | identique |
| Synchronisation GitHub | 0 / 0 | identique |
| Entrées `git status` | 159 (158 + ce fichier) | **159** — 79 `M` + 80 `??` |
| Index | 0 fichier | 0 |
| Diff texte | 79 fichiers, `+1 622 / −478` | **exactement** `fichiers=79 +1622 -478` |
| Empreinte de ce fichier | `4d604a28…` | `4d604a2825b8d4a0f4cdbd27fc3551f64b24cc7982bd604ad65ecb349fdca22c` |

Le **seul** fichier touché dans le dépôt depuis le relevé de 00 h 08 est ce fichier de point
(`scp` de 00 h 24). Aucun autre octet. `work/` ne contient aucun fichier postérieur à 00 h 08.

**L'activité du chantier s'était arrêtée avant ce relevé** :

| Dernier fichier touché | Horodatage |
| --- | --- |
| `work/spark-reprise-120/stderr.log` | 13/10 **23 h 09 min 49** — dernier fichier de toute la chaîne |
| `preuves/…/interactive-c3/human-actions.jsonl` et `48-c4-deplacement-seul.png` | 13/10 22 h 59 min 46 |
| `outils/guides/build_guide.js` | 13/10 22 h 59 min 42 |
| `outils/guides/technicien.md`, `administrateur.md` | 13/10 22 h 55 min 52 |
| `outils/guides/technicien.json`, `administrateur.json` | 13/10 22 h 52 min 24 |

Aucun processus de travail actif : les workers Codex encore vivants sont oisifs depuis le 13/10
17 h 36, rien de nouveau côté Pesto. Mac up depuis 6 jours 16 h, charge ~1,3.

→ Les relevés de ce fichier restent fidèles à l'état réel du dépôt au 14/10 01 h 05.

## 12. Contre-vérification après redémarrage du Mac — 14 octobre 2026, 08 h 47 (CEST)

Le Mac a été **arrêté à 01 h 14** (neuf minutes après le contrôle ci-dessus) et a **redémarré à
06 h 35 min 10**. Il est de nouveau joignable sur **`192.168.1.13`** — l'adresse de l'alias `mac`
du `~/.ssh/config` du Spark, qui refonctionne donc ; `192.168.1.128` (adresse de la veille) est
morte. Session console ouverte depuis 08 h 33, démons de Software Update actifs.

Malgré ce cycle, **le dépôt n'a pas bougé** :

| Contrôle | 01 h 05 | 08 h 47 |
| --- | --- | --- |
| HEAD | `221e050` | `221e050` |
| Synchronisation GitHub | 0 / 0 | 0 / 0 |
| Entrées `git status` | 159 | **159** |
| Index | 0 | 0 |
| Diff texte | 79 fichiers, `+1 622 / −478` | **identique** |
| Fichiers du dépôt touchés après 00 h 08 | ce fichier | **ce fichier uniquement** |
| Fichiers de `work/` touchés après 00 h 08 | aucun | **aucun** |

Aucun processus Pesto ou Codex actif. Les horodatages de la section 11 (dernière activité réelle à
23 h 09 min 49) restent donc valables.

## 13. Poussée du chantier sur GitHub — 14 octobre 2026

Sur demande explicite de David, les 158 entrées décrites par ce document ont été committées et
poussées sur `master`. Trois commits, vérifiés par `git ls-remote` :

| Commit | Contenu |
| --- | --- |
| `41d2477` | ce fichier de point |
| `f0a24e6` | 178 fichiers — moteur `wad/`, lanceur, bancs PowerShell et Python, outillage, guides, docs d'implémentation, intégrations, socle commun embarqué |
| `e62b2be` | 558 fichiers — `preuves/`, 78 Mo de rapports et captures de recette |

Contrôles de sûreté faits avant poussée : `DEV/tests/pesto-portable-validation.json` **non modifié**
(pas de rapport régénéré sur macOS, qui aurait détruit des contrôles de preuve) ; aucun fichier au
dessus de 50 Mo (plus gros : 5,3 Mo) ; aucun nom ni contenu correspondant à une clé privée, un jeton
GitHub, un identifiant AWS ou `LABPASS` ; aucun `.DS_Store` indexé.

**Ce que la poussée ne change pas** : le catalogue reste à **0 des 120 points réconciliés**, les
2 échecs de `Run-CliOutputTests.ps1` restent ouverts, les guides DOCX/PDF n'ont pas été régénérés,
et aucune mutation AD réelle n'a été rejouée sur le build final. Un commit n'est pas une validation.

**Retrait consigné** : la section 6, point 3, et la ligne de la section 3 annonçaient le lanceur
suivi par Git « incohérent avec le dernier candidat ». C'était faux, repris du relais qui s'arrêtait
à C2. Mesuré le 14/10 : `DEV/Pesto.exe` = `7137f4e3…` = les EXE des packs C4, construit à 22:23:22
après la dernière retouche de `wad/`.
