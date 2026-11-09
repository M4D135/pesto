# Pesto 1.0 : bilan des tests réellement exécutés

## Revue locale du 12/10/2026

Départ : `af555e5897945a9cdd00eb039ba5e6f47cf441fd`, branche `cloud/points-suite`. Demande de David :
revue approfondie, corrections et améliorations ; puis accord explicite pour les tests locaux sur le Mac.
Aucune VM démarrée ou contactée, aucun appel AD, aucune modification d'une installation Windows.
Le Spark a relu les fichiers complets ; ses six constats ont été vérifiés. Quatre recoupent les corrections
ci-dessous, un confirme le défaut JSON ajouté en fin de passe, et la proposition de modifier la découverte AD
est écartée : `-Credential` n'appartient pas au jeu `DiscoverByService` de
[`Get-ADDomainController`](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-addomaincontroller?view=windowsserver2025-ps).

Corrections de cette passe :

- Le worker indique explicitement s'il utilise un credential AD. Dans ce mode, ou si l'identité Windows est
  inconnue, `Add-PestoDomainIdentityCause` conserve l'erreur originale ; un compte local ne prouve plus à lui seul
  un refus d'authentification. L'exception enrichie conserve aussi son exception d'origine.
- Le contrôleur statique des workers vérifie le dot-sourcing avant les appels et les dépendances des fonctions
  exportées. Les commentaires et chaînes n'interfèrent plus avec l'appariement des accolades.
- `vps.sh` transmet le code de SSH et garde séparément stdout/stderr, sans filtrage destructeur de `Objs` ou `CLIXML`.
  Le format texte est demandé à PowerShell ([paramètre officiel `OutputFormat`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)).
- La sortie des packs est contrôlée sur son chemin réel : un alias de dossier ne permet plus une écriture
  dans les sources. Reproduit sur un dossier temporaire du Mac (refus absent avant correction). Le fabricant
  PowerShell refuse les liens/jonctions dans le chemin de sortie ; ce volet reste non exécuté sous Windows.
- Le pack DEV emporte `pytest.ini`, exclut les archives RC18 et aligne les listes des fabricants Python/PowerShell.
  Le contrôle du parseur propre au dépôt est séparé du contrôle livré dans le pack autonome ; son absence y est
  annoncée comme un skip. Dans le dépôt, un fichier manquant reste une erreur.
- README et titre du changelog corrigés : les campagnes Windows antérieures existent, mais ne qualifient pas
  automatiquement les nouveaux octets. Les résultats historiques sont conservés.
- Mise à jour : manifestes installés/source, entrées de manifeste, versions, empreintes et reçus mal typés
  donnent un refus propre. Huit nouveaux tests reproduisent le défaut avant correction puis passent après ;
  l'aperçu et `--apply` conservent les fichiers et n'abandonnent aucun verrou sur ce refus.

Résultats locaux de la première passe : 295 tests Python réussis dans le dépôt ; dans le pack DEV autonome, 294 réussis et un
skip explicite pour l'outil réservé au dépôt. Six tests du script SSH avec un faux exécutable `ssh` local
(quatre échouaient sur l'ancienne version). Contrôle des workers : 9/9, sept défauts injectés détectés ;
les trois omissions ciblées au départ n'étaient pas détectées par l'ancien contrôleur. Contrôles statiques
Startup 109/109, SSO 56/56, retrait de file 26/26, connexion 33/33 ; leurs contrôles négatifs passent.
Validation portable : 360/360, parseur PowerShell absent. Banc C sur le Mac : 48 scénarios d'entrée,
9 contrôles d'arguments, 2 000 allers-retours d'arguments et 132 cas SHA-256 ; API Windows remplacées par des doubles.

Fin de passe après relecture Spark : 303 tests Python dans une copie isolée alignée sur les sources ;
46 tests ciblés de mise à jour et 26 tests de distribution. Le test des reçus sélectionne le lecteur avec
un environnement factice et des fichiers temporaires locaux ; aucune API Windows n'est appelée.
Le DEV final autonome rejoue 303 tests : 302 réussis et le même contrôle réservé au dépôt ignoré.

Preuves de la passe : `preuves/audit-mac-2026-10-12/` dans le dépôt. Les empreintes du build et des packs
sont consignées dans `summary.json`. Le champ `WindowsExecution: NOT_RUN` de `last-build.json` décrit la
fabrication ; il n'est jamais modifié pour représenter une campagne Windows ultérieure.

Limites : absence de PowerShell sur ce Mac, donc contrôles lexicaux uniquement pour le PowerShell ; aucun test WPF,
UAC, module AD ou scénario d'authentification réel. Le cas PowerShell ajouté reste à exécuter sur Windows.
La signature, Entra hybride, RDP et la qualification sur un parc représentatif restent les sujets externes ouverts.
À la demande de David le 12/10, le dépôt est consolidé sur `master` (branche par défaut), avec
la PR n° 2 fusionnée et les anciennes branches entièrement intégrées supprimées. Les deux livrables
restent `Pesto_DEV.zip` et `Pesto_PROD.zip`. Cette consolidation ne prononce aucune validation
générale de production.

## Campagne du 04/10/2026 (historique)

État au 04/10/2026, fin de campagne : le candidat AD local est construit et éprouvé sur Windows 11 / PowerShell 5.1. Dernier code `5f91b8b`, EXE `572beef39fb305b1eb83f09e4d1a00018475cadcc8190556da3301455dc96411`. La diffusion en production signée n’est pas autorisée par le rapport automatique : aucun certificat d’éditeur approuvé n’est disponible. Entra hybride et RDP restent non validés. Les sections datées plus anciennes décrivent leur état historique ; la matrice `V1_RECETTE_WINDOWS.md` et `preuves/vm-2026-10-04-prod/LIRE.md` font foi pour cette campagne.

Corrections finales : nomenclature P/S/V conforme à la décision de David, exclusion AD des groupes à DN avec antislash, message du code 32, reprise UAC entre comptes sans conflit sur files vides et avec archivage des historiques divergents, navigation sans texte coupé aux grandes échelles.

Validation finale : 229 tests Python ; 408 contrôles avec parseur Windows 5.1 ; 32 Pester, 55 natifs, 65 RC23 WPF ; 35 tests Startup sur son dernier changement. Jonction, renommages, déplacements, reprises 89/97, code 32, disque plein, coupure réseau, arrêt forcé, refus depuis un autre PC, import historique et deux comptes UAC ont des preuves distinctes. Ces nombres ne transforment pas les doubles AD en opérations réelles.

**Statut : recette de production en cours au 4 octobre 2026 au soir.** UAC acceptée/refusée, connexion AD explicite, jonction réelle et vérification après redémarrage acquises sur la VM dédiée. Les autres lignes restent détaillées dans la matrice : aucune clôture globale déduite de ces succès. Dernier EXE testé au contrôle de paquet : `5dc8cea143e29c8b6a3224b4bb0caaf50372872fd604619e8299586adbd8045b` (P/S/V, présentation du reçu et exclusion par identité de groupe).
Détail ligne à ligne : `V1_RECETTE_WINDOWS.md` ; preuves : `preuves/`.

## Historique utile

| Commit | Contenu |
|---|---|
| `1375908` | Base 17.0-RC23 reçue. **Ne démarrait pas** (D4 : erreur de syntaxe dans `Get-SiteTag` ; F2 : écriture de `$HOME`). |
| `8fa63e7` | Correctifs D1 à D4, F2 à F7. |
| `c2e62e2` | Outillage portable sous macOS. Aucun fichier de `wad/` modifié. |
| `4066c50` | B : contrôle avant connexion. C : reçu de jonction. E : durcissements. |
| `c7ded37` | Version 1.0 depuis une source unique. |
| `1a04a35` | Fusion de la PR n° 1 : trois défauts de `4066c50` corrigés, dont un **bloquant** (`param()` mal placé : Pesto refusait de démarrer dans tous les modes). |
| `9ee3fe2` | Branche `cloud/points-suite` : EXE et manifeste reconstruits sur le Mac (clang/lld 23.1.2), `8c723efb…`. Base copiée sur la VM. |
| `25ae335`, `c4b5b20`, `ebc19e0` | Phases 0 et 1 jouées sous 5.1 sur la VM ; test `DEBLOQUER_TOUT` corrigé ; chaînes de version du PE conservées (1.4). |
| `ce3d013`, `a76443c` | L2 et O12 corrigés ; mécanisme L2 vérifié sous 5.1 (micro-test), O12 reproduit puis vérifié sous 5.1 ; L1 non reproduit ; phase 1 rejouée sur `e31dbb9f…`. |
| `2d5c182`, `5bb0ba7` | Mode démo (arrêt fatal sous 5.1) ; contenu des pages et palette exposés à UI Automation. |
| `d86cfe3` à `81a8e7b` | Phase 2 partielle et preuves ; `ca7ba5b` : listes déroulantes accessibles, `$PSScriptRoot`. |
| `23360f8`, `9ea9c99` | P1, P2, P3 (fiches) et O4 (refus de retour en arrière). |
| `11bc7d7` | O9 et O10 (outillage Python). |
| `d4b6be1`, `daeed5e`, `07fbab0` | P5, suites connexion, préférences et UX, P7, contrôles statiques ; EXE `de44fc4a…`. |
| `c86381d` | Constats O9, O10, P5, P7 clos (P7 jamais inscrit aux constats) ; T1 ouvert. |
| `0a54ff2`, `5e9c357`, `ab2be8d` | O8 (files de lots locales signalées par l'aperçu de mise à jour) et T1 (autotests des contrôles statiques) clos. |
| `abd6c2e` | L4, X5, O7 traités ; décisions L1 et L6 (délégation du 04/10) ; correctif `--quiet` vu sous Windows ; EXE `8fd5bd8c…`. |
| `64ef559` | Conditions L6 dans `V1_GUIDE.md`, vérifiées sur la VM ; résultats Windows L4, X5, O7 (`preuves/vm-2026-10-04/`). |
| `786136c` et suivant | Relais (`PROMPT_RELAIS_2026-10-04.md`), outils de labo versionnés ; recette 1.1 à 1.7 rejouée sur `8fd5bd8c…` (`preuves/vm-2026-10-04-phase1/`) ; P8 inscrit. |

## 1. Windows PowerShell 5.1, Windows réel

### Hôte du labo (2 octobre, avant B, C, E et la 1.0)

Hôte du labo `DESKTOP-285EKHU` (Windows 11 Pro 10.0.26200, PowerShell 5.1.26100.9549 Desktop x64), session SSH
**non interactive**, compte `degun`. **Pas une VM du domaine.** Commit `c2e62e2`, donc **avant B, C, E et la 1.0**.
`Pesto.exe` SHA-256 `d844c2fc…e45e2`. Preuves : `preuves/windows-hote-2026-10-02/`.

| Contrôle | Résultat |
|---|---|
| Vrai parseur 5.1 (`outils/parse_all.ps1`) | 68 fichiers, 0 erreur |
| `Pesto.exe --check-json` (PE réel) | Code 0, Runtime PASS, 38 composants |
| `Run-StabilisationTests.ps1` (D1 à D4, F7 ; doubles AD) | 8/8 |
| `Test-Pesto19.ps1` | Vert |
| `Run-NamesLoadingTests.ps1 -Wpf` | 25 OK |
| `Run-Pesto21Tests.ps1 -Wpf` | 61 PASS |
| `Run-Pesto22Tests.ps1 -Wpf` | 33 PASS |
| `Run-Pesto23Tests.ps1 -Wpf` | 65 PASS |

Ensuite, via SSH depuis le Mac, le vrai parseur 5.1 de cet hôte a aussi analysé `4066c50` : 68 fichiers, **0 erreur,
syntaxe seule**. Il n'a pas vu le défaut `param()`, qui ne se manifeste qu'à l'exécution.

Ne prouve pas : interaction WPF (chargement XAML hors écran seulement), UAC, AD/Entra, mutations, démarrage de
l'interface connectée.

### VM `PESTO-W11-TEST` : phases 0 et 1 (2 et 3 octobre, SSH)

VM dédiée (VirtualBox 7.2 en mode NEM sur l'hôte du labo), Windows 11 Entreprise Évaluation 25H2, build 26200.6584,
**Windows PowerShell 5.1.26100.6584 Desktop**, .NET 4.8.1, **hors domaine** (groupe `LABO`, DC `dc01.labo.local`
joignable), compte `labadmin`, session SSH non interactive. Phase 0 : traçabilité remplie, instantané
`02-groupe-de-travail-pret` pris à froid. Branche `cloud/points-suite`, `9ee3fe2`, `Pesto.exe` `8c723efb…` ; phase 1
rejouée le 03/10 sur `e31dbb9f…` (L2, O12) avec les mêmes résultats ; 1.1 à 1.7 rejouées le 04/10 vers 17 h sur
`8fd5bd8c…` (mêmes résultats, stabilisation 24/24). Preuves : `preuves/vm-2026-10-02/`, `preuves/vm-2026-10-03/`,
`preuves/vm-2026-10-04-phase1/`.

| N° | Résultat |
|---|---|
| 1.1 | PASS : vrai parseur 5.1, 68 fichiers, 0 erreur (`-ExecutionPolicy RemoteSigned` requis : stratégie Restricted par défaut) |
| 1.2 | PASS : `--check-json` code 0, Runtime PASS, 38 composants, `ParsedFiles=27`, `EmbeddedScripts=3`, `AuditWriter=PASS` |
| 1.3 | PASS : `--check --quiet` code 0 en SSH ; boîte « Pesto - Contrôle du pack » vue en console le 03/10, code 0 |
| 1.4 | PASS après décision du 02/10 : binaire 1.0.0.0 ; chaînes ProductVersion « 1.0 » et ProductName « Pesto - Gestion des Postes » conservées, documents alignés |
| 1.5 | Stabilisation 19/20, puis 20/20 après correction du test `DEBLOQUER_TOUT` (défaut du test, pas du produit) ; 24/24 le 04/10 sur `8fd5bd8c…` (3 cas O7 ajoutés) |
| 1.6 | PASS : `TESTER.cmd` code 0, 5 suites, 239 OK/PASS (cas WPF hors écran, sans bureau) |
| 1.7 | PASS : `TEST_RC23.cmd` 65 PASS, 0 FAIL |
| 1.8 | PASS le 04/10 à 17:47 : 407 contrôles, parseur 5.1 Desktop, Python 3.14.7 temporaire ; `preuves/vm-2026-10-04-reprise/` |
| 1.9 | PASS : copie altérée refusée avant connexion, `wad/Pesto-Names.ps1:204:1` |
| 1.10 | PASS : `--validate-plan` valide 0, invalide 20 (`INVALID_DRAFT`), rapport existant refusé (1) |

### VM `PESTO-W11-TEST` : phase 2 partielle (3 et 4 octobre, console)

Session console de `labadmin` (ouverture automatique activée par David, mot de passe saisi par lui). Pilotage par Claude :
tâches planifiées interactives (jeton non élevé), UI Automation, clavier et souris simulés, captures. **Ce n'est pas une
relecture visuelle par un utilisateur.** Aucune UAC, aucun AD réel, aucune mutation. Preuves :
`preuves/vm-2026-10-03-phase2/`.

| N° | Résultat (03/10 sauf mention) |
|---|---|
| 2.1 `DEMO.cmd` | FAIL puis PASS : erreur fatale « Argument types do not match » sous 5.1, corrigée (`2d5c182`) ; fenêtre « Pesto 1.0 \| Gestion des Postes », pas d'UAC, 0 connexion au DC |
| 2.2 `DEMO_DOMAINE.cmd` | PASS : démonstration de jonction affichée, pas d'UAC, 0 connexion au DC |
| 2.3 `APERCU_LOGIN.cmd` | FAIL le 03/10 : banc obsolète (`$PSScriptRoot`, gabarits déplacés, `docs/RC6_UI_TOKENS.json` supprimé). Après P5 (04/10) : fenêtre compacte « TEST LOCAL SANS AD », saisie fictive, pas d'UAC, 0 connexion au DC ; `Run-LoginTests.ps1` 19/19. Rejoué le 04/10 à 18:11 sur `8fd5bd8c…`, compte standard temporaire : PASS, fenêtre non maximisable, code 0, configuration inchangée, aucun état GP créé ; capture et trace dans `preuves/vm-2026-10-04-reprise/` |
| 2.4 `--consult` | BLOQUÉ : « Corriger la configuration » (`cfg.json` modèle non configuré, P6) ; pas d'UAC |
| 2.5 Thèmes, échelles, RDP | PASS partiel : clair et sombre lisibles à 100 % ; 125 à 200 % et RDP non joués |
| 2.5b Contraste élevé | PASS : « Suivre Windows » + contraste élevé, couleurs système, texte lisible, retour au thème habituel |
| 2.6 Palette Ctrl+K | PASS : clavier, filtre, Échap, 0 connexion au DC ; noms accessibles corrigés (`5bb0ba7`) |
| 2.7 Fiche État | PASS : Relire / Fermer, Échap rend le focus ; focus à l'ouverture corrigé le 04/10 (P1). Arrêt du worker non vérifié |
| 2.8 Performance observée | PASS : attente / travail / total distincts, 200 échantillons au plus |

Sur les lignes 2.1 à 2.8 du tableau : 7 PASS (dont 2.1 et 2.3 après correctifs), 1 PASS partiel, 1 BLOQUÉ. Recette complète au 04/10 en soirée : 9 PASS, 2 PARTIEL (2.5 et 2.9), 1 BLOQUÉ (2.4), 1 NON JOUÉ (2.12) ; voir la matrice pour 2.9 à 2.12.

### Défauts et constats corrigés, reproduits ou vérifiés en tout ou partie sous 5.1 sur la VM (3 et 4 octobre)

La colonne « Trouvé » dit où le défaut a été vu d'abord : seuls la démo, l'accessibilité, le premier volet de
`$PSScriptRoot`, P1 à P3 et P5 ont été trouvés sous 5.1. La colonne « Vérification » dit ce qui a tourné sous 5.1.

| Id | Trouvé | Défaut | Commit, EXE | Vérification |
|---|---|---|---|---|
| Démo | 5.1, recette 2.1 | `@()` sur une liste créée par `New-Object` : arrêt fatal du mode démo (depuis la RC23) | `2d5c182`, `3676b63e…` | 2.1 PASS ; stabilisation 21/21, en échec sur l'ancien code |
| Accessibilité | 5.1, phase 2 (UI Automation) | 0 élément UI Automation sous `MainTabs` ; palette `@{Id=...}` ; thèmes `@{Key=...}` | `5bb0ba7` (`6702949d…`), `ca7ba5b` (`73eb6795…`) | 145 éléments exposés ; thèmes lus « Clair », « Sombre », « Suivre Windows » |
| `$PSScriptRoot` | 5.1, recette 2.3 (`ca7ba5b`) ; Mac, `test_ps51_compat.py` corrigé (`d4b6be1`) | Vide dans une valeur par défaut de paramètre (`APERCU_LOGIN.cmd`) | `ca7ba5b` (4 scripts), `d4b6be1` (9 scripts) | Parseur 5.1 : 68 fichiers, 0 erreur (syntaxe seule) ; sur les 13 scripts, seule exécution consignée sous 5.1 : `Run-LoginTests.ps1` (P5) ; aperçu ouvert |
| L2 | Relecture du 02/10 | Racine ouverte en accès 0 : dossier renommable | `ce3d013`, `e31dbb9f…` | Mécanisme seulement : micro-test .NET aux mêmes paramètres, renommé avant, refusé après. En exécution réelle, la mesure ne distingue pas les mécanismes (les composants ouverts bloquaient déjà le renommage) |
| O12 | Relecture du 02/10 | `call` dans `Pesto_COMPTE_AD.cmd` (`a^b`, `c%PATH%d`) | `ce3d013`, `e31dbb9f…` | Reproduit : code 1 avant ; chemin exact et code transmis après |
| L1 | Relecture du 02/10 | Tout point d'analyse refusé | Non modifié | Non reproduit : WOF et compression NTFS acceptés ; lien symbolique et jonction refusés |
| P1, P2, P3 | 5.1, console (phase 2) | Focus de la fiche État, colonnes mal alignées, « (mode GUI) » affiché | `23360f8`, `4b08eb94…` (capture de P2 sur l'EXE intermédiaire `07c6ea1c…`, jamais commité) | UI Automation et captures ; `--check-json` PASS, stabilisation 21/21 |
| P5 | 5.1, recette 2.3 | Aperçu et tests de connexion obsolètes | `d4b6be1` | 19/19 en Light et Dark ; fenêtre compacte affichée |
| P7 | Mac, `ux_static_checks.py` 48/49 | 8 contrôles sans `HelpText`, dont 7 sans `ShowOnDisabled` | `07fbab0`, `de44fc4a…` | 1 contrôle sur 8 vérifié sous 5.1 : `HelpText` de `TabJoin` lu par UI Automation. Les 8 contrôlés sur le Mac seulement (`ux_static_checks.py` 49/49) |

P7 touche Favoris de préparation, l'onglet Apparence et `TabJoin` (`Pesto-Shell.xaml`), `KeepService`, `KeepNumber`,
Annuler et `ConfirmRun` (`Pesto-Core.ps1`), `LoginTheme` (`Pesto-Authentication.ps1`, qui avait déjà `ShowOnDisabled`).
Les infobulles changent (affichage sur contrôle désactivé, délais ; l'onglet Apparence en reçoit une) ; aucun
comportement métier modifié.

Avec le pack de `07fbab0` (EXE `de44fc4a…`, 04/10), d'après le message de ce commit : `--check-json` PASS, seul
résultat qui exécute l'EXE ; stabilisation code 0, connexion 19/19, préférences 15/15, UX 43/43 en session console (en
SSH, 2 mesures de mise en page hors écran renvoient 0), ces suites lisant les sources du pack sans lancer l'EXE. La phase 1
complète (`TESTER.cmd`, `TEST_RC23.cmd`, 1.9, 1.10) n'est consignée que sur `8c723efb…` (02/10) et `e31dbb9f…` (03/10),
pas sur `de44fc4a…`. Sur `8fd5bd8c…` (04/10) : 1.1 à 1.7, `TESTER.cmd` et `TEST_RC23.cmd` compris (`preuves/vm-2026-10-04-phase1/`) ; pas
1.9 ni 1.10.

**Preuves du 04/10 postérieures à `4b08eb94…`** : P5 (19/19) et `APERCU_LOGIN.cmd`, préférences 15/15, UX 43/43,
`--check-json` et stabilisation sur `de44fc4a…`, `HelpText` de `TabJoin`. Aucun de ces résultats n'a de fichier dans
`preuves/` : ils ne sont consignés que dans les messages de `d4b6be1`, `daeed5e` et `07fbab0`, les sorties brutes étant
restées hors du dépôt. À archiver dans `preuves/` ou à rejouer en recette. L’aperçu `APERCU_LOGIN.cmd` a depuis été rejoué et archivé le 04/10 en soirée ; les autres limites restent inchangées.

O4, O8, O9 et O10 sont désormais exercés par les tests Python sous Windows sur des copies temporaires (reprise du 04/10 en soirée, 228 réussis et 1 ignoré après trois rejeux ciblés ; détail et limites en §8).

## 2. PowerShell 7.4.6 Core sous Linux (cloud, 2 octobre 2026, commit `1a04a35`)

| Contrôle | Résultat |
|---|---|
| Vrai parseur (`outils/parse_all.ps1 -Root .`) | 66 fichiers, 0 erreur |
| `Run-StabilisationTests.ps1` | 8/8 (doubles AD), puis 11/11 avec les deux correctifs E de la file et du formulaire |
| `Get-PestoEmbeddedScriptSamples` exécuté | 3 scripts générés (helper de jonction, helper de renommage, tâche de renommage), 0 erreur de syntaxe chacun |
| `Test-PestoRuntimeReady` exécuté | `Valid=true`, `ParsedFiles=27`, `EmbeddedScripts=3`, `AuditWriter=PASS` (compilation C# sous .NET 8, pas le .NET Framework) |
| Contre-épreuve sur `master` avant fusion (`5400cdc` sans la PR) | Échec reproduit : `The term 'param' is not recognized` |

Écart expliqué le 04/10 (VM) : sous Windows, `Get-ChildItem -Filter *.ps1` reconnaît aussi les deux `.ps1xml` de `wad/`
(filtre Win32 : une extension de trois caractères reconnaît les extensions plus longues). `parse_all.ps1` et la passe
parseur de `validate_pesto.py` filtrent désormais l'extension exacte : 66 fichiers sous 5.1 aussi (`preuves/vm-2026-10-04-phase1/ps1xml.txt`).

### Suites RC21, RC22, RC23 sous PowerShell 7 (copie jetable, garde 5.1 neutralisée ; branche `cloud/points-suite`)

| Suite | Branche | `c2e62e2` (vert sous 5.1 sur l'hôte) |
|---|---|---|
| RC21 | 56 PASS, 3 FAIL, 1 SKIP | mêmes 3 FAIL |
| RC22 | 31 PASS, 1 SKIP | idem |
| RC23 | 62 PASS, 1 FAIL, 1 SKIP | même FAIL |

Les 4 échecs sont identiques sur `c2e62e2`, vert sous Windows PowerShell 5.1 : écarts de moteur (lecture JSON des
reçus et réservations par PowerShell 7), pas des régressions. Les 15 autres suites historiques refusent tout autre moteur
que 5.1, ou sont obsolètes (fonctions disparues : `Run-PilotageTests`) ; hors `TESTER.cmd`. `Run-LoginPreferencesTests`
a depuis été remise en état (fonctions cherchées dans tous les `wad\*.ps1`) : 15 tests réussis sous Windows PowerShell 5.1
le 04/10.

### PSScriptAnalyzer (porte `Verify-Release.ps1`)

Installé depuis la publication GitHub (la galerie PowerShell est bloquée dans le cloud). Version 1.24.0 exigée par la
porte, toutes règles, `wad/Pesto-*.ps1`, sous pwsh 7.4.6 Linux : avant correctif, **plantage** sur `Pesto-Core.ps1` (la
porte échouait toujours) ; après correctif du stub `Confirm-YesNo` : 0 plantage, 0 erreur, 702 avertissements ou
informations. Règle de compatibilité de syntaxe ciblant 5.1 : 0 constat.

### Relectures adversariales (agents, lecture seule)

Lanceur C, outillage Python/PowerShell et `.cmd`, `Pesto-Shell.xaml` et `Pesto-Join.xaml`. Aucun défaut bloquant ni de
sécurité exploitable dans le lanceur ; aucune perte de `cfg.json`, reçus ou journaux dans l'outillage. Corrigés : voir
l'historique de `cloud/points-suite`. Encore ouverts : `V1_CONSTATS_OUVERTS.md`.

## 3. Contrôles portables (sans PowerShell Windows)

| Contrôle | Mac (`c7ded37` puis PR n° 1) | Cloud Linux (`1a04a35`) | Mac (`cloud/points-suite`, 02 au 04/10) |
|---|---|---|---|
| Python `unittest` | 122 OK | 122 OK, puis 127 avec `test_0_prepare_dev.py` (voir section 6) | 136 OK (`9ee3fe2`) ; 187 OK (`c86381d`, 04/10) ; 228 OK (`abd6c2e`, 04/10) ; 229 OK (test du filtre `.ps1xml`, 04/10) |
| `validate_pesto.py` | 341 OK sans moteur | 408 OK (341 + passe du vrai parseur pwsh 7) | 340 OK sans moteur (`9ee3fe2` ; rapport versionné réécrit en dernier par `abd6c2e`, parseur `NOT_RUN`) |
| `stamp_version.py --check` | OK | OK (dans `validate_pesto.py`) | OK (dans `validate_pesto.py`) |
| `run_native_portable.py` | OK | 35 scénarios C, 9 arguments, 2 000 allers-retours, 132 SHA-256 ; API Windows remplacées par des doubles | 37 scénarios C (`9ee3fe2`) ; double L2 mis à jour (`ce3d013`) ; 48 scénarios C (`abd6c2e`) |
| Contrôles statiques UX et connexion | — | — | `ux_static_checks.py` 49/49, `login_compact_static_checks.py` 33/33 et 9/9 (`07fbab0`) ; `ux_static_checks.py` 50/50 (`abd6c2e`) |

Valeur de preuve : faible pour le comportement. Ces suites étaient vertes sur une RC23 qui ne démarrait pas, et sur une
1.0 dont le mode démo s'arrêtait en erreur fatale sous 5.1.

## 4. Compilation de `Pesto.exe`

| Chaîne | SHA-256 | Statut |
|---|---|---|
| clang / lld-link 23.1.2 (Mac), branche de la PR n° 1 | `8590640ccab78aefb4badab334d65716550d0a567594ce5216bc87887117d8ed` | Référencé alors par `wad/package.json` de cette branche |
| clang / lld-link 18.1.3 (cloud), mêmes sources | `61ee7366cad408954ab7b2d2179c434bfafb0a11d0436cf47177a90ffee9e95c` | Non livré, non commité |
| clang / lld-link 23.1.2 (Mac), `cloud/points-suite`, 02 au 04/10 | `8c723efb…` (`9ee3fe2`), `e31dbb9f…` (`ce3d013`), `3676b63e…` (`2d5c182`), `6702949d…` (`5bb0ba7`), `73eb6795…` (`ca7ba5b`), `4b08eb94…` (`23360f8`) ; `07c6ea1c…`, intermédiaire jamais commité (capture de P2) | Copiés sur la VM au fil de la recette |
| clang / lld-link 23.1.2 (Mac), `07fbab0` | `de44fc4a6a6871ae0669a8770fcce4fcd10ec265168018873a6e683b43ce0207` (113 664 octets) | Build précédent ; manifeste régénéré au même commit ; `--check-json` PASS sous 5.1 d'après le seul message de `07fbab0` (`last-build.json` : `WindowsExecution: NOT_RUN`) |
| clang / lld-link 23.1.2 (Mac), `abd6c2e` | `8fd5bd8cf914058f1f0b84a95f43536ff91c4dc2718c6c67f411bb24b7fd7ca0` (113 664 octets) | Dernier build ; manifeste régénéré au même commit ; même empreinte sur la VM le 04/10 ; reconstruit vers 17 h sur un clone neuf aux mêmes octets ; L4, X5, O7 vus sous 5.1 (`preuves/vm-2026-10-04/`), puis recette 1.1 à 1.7 (`preuves/vm-2026-10-04-phase1/`) |

Les deux premiers : même taille (112 128 octets), octets différents : **la compilation n'est pas reproductible d'une
version de LLVM à l'autre.** L'EXE et le manifeste à livrer doivent venir de la même machine. L'EXE n'est pas versionné
(`.gitignore`) : le reconstruire avec `build_native.py`, puis `refresh_manifest.py`. **Non signé.**

## 5. Packs PROD et DEV

Fabrication à blanc dans le cloud (`Build-PestoPacks.py`, EXE clang 18, manifeste rafraîchi sur une copie jetable) :
PROD = `Pesto.exe` + `wad/` uniquement, 41 fichiers ; DEV = 365 fichiers ; `Version 1.0`. Mécanisme vérifié,
**packs non livrables** (EXE de la mauvaise chaîne) et non publiés. La VM a reçu des copies de `DEV/` avec l'EXE du
Mac. Packs livrables : à fabriquer depuis le Mac, après la recette.

## 6. `wad/cfg.json` dans un clone neuf

Le `cfg.json` de la RC23 est un modèle non configuré (`"Configured": false`), exclu de Git par `.gitignore`. Dans un
clone neuf, 52 tests Python échouaient et la fabrication des packs était impossible. Corrigé : modèle versionné dans
`tools/cfg.template.json`, créé en `wad/cfg.json` par `tools/prepare_dev.py` seulement s'il est absent (appelé aussi par
`Build-PestoPacks.py` et par `tests/test_0_prepare_dev.py`). Vérifié dans le cloud sur une copie sans `cfg.json` :
`unittest` OK, 408 contrôles, packs fabriqués ; un `cfg.json` existant reste intact.

## 7. Constats ouverts et décisions attendues

Détail : `V1_CONSTATS_OUVERTS.md`. Clos du 2 au 4 octobre : V1 (chaînes de version), L2, O12, P1, P2, P3, O4, O8, O9,
O10, P5, T1. P7, trouvé et corrigé le 04/10 (`07fbab0`), n'y a jamais été inscrit.

Le 04/10, David a délégué les décisions sur L1, L4, L6, X5 et O7 (« fais au mieux ») :

| Id | Décision (04/10) | État Windows (04/10, `preuves/vm-2026-10-04/`) |
|---|---|---|
| L1 | Risque accepté : refus strict des points d'analyse conservé ; condition d'emplacement dans `V1_GUIDE.md` | Non reproduit le 03/10 (WOF et compression NTFS acceptés) ; OneDrive et déduplication non testables sur la VM |
| L4 | Codes propres au lanceur 120-132 (133-139 réservés), table dans `V1_GUIDE.md` (`abd6c2e`) | Vus : 0, 120, 123, 124, 125, 126, 128 ; défaut `--quiet` sur la racine d'un lecteur trouvé et corrigé le jour même |
| L6 | Risque accepté sous conditions : pack sous `%ProgramFiles%`, droits et contrôle avant mise en service dans `V1_GUIDE.md` | Conditions vérifiées sur un pack PROD de test sous `C:\Program Files` : écriture non élevée refusée, contrôles à 0 |
| X5 | Bordure aux couleurs système, en contraste élevé seulement (`abd6c2e`) | Vue sur le menu, le focus clavier et l’onglet actif (complément final du 04/10 à 18:55) |
| O7 | `VERIFIER_UAC.cmd` teste la vraie UAC avec le vrai lanceur (sonde `PESTO_UAC_PROBE`, `abd6c2e`) | Refus 1223 et acceptation 0 avec reçu UAC_OK, console réelle et clavier VirtualBox, après correction `Process.Start` (campagne finale) |

Restent ouverts : P6 (`--consult` bloqué par le `cfg.json` modèle) et LAB. P8 est clos pour la 1.0 en documentant les raccourcis pris en charge (Ctrl+1 à Ctrl+4, joués en console) et l’absence de Ctrl+Tab/Ctrl+Page suivante. LAB nécessite une décision concernant l’hôte partagé :

| Id | Décision attendue de David | Enjeu |
|---|---|---|
| LAB | Hyper-V sur l'hôte du labo : le désactiver, ou changer d'hyperviseur | VirtualBox tourne en mode NEM : VM figée trois fois ~30 min après l'ouverture de session (vCPU à 100 %, aucune E/S), puis le 04/10 juste après un démarrage sans session (réinitialisation nécessaire), premier rendu WPF > 1 min, instantané à chaud échoué après 3 h 40 (instantanés pris à froid) |

Préalables des phases 3 et 4 (recette) : identifiants AD saisis par David ; configuration validée du labo pour rejouer 2.4 ;
OU de test à définir ; groupe de test pour 4.16 ; instantané avant chaque phase qui mute. SID de la VM non changé (sysprep
bloqué) : s'en passer pour la jonction est une proposition, non validée.

## 8. Campagne finale du 04/10 et limites restantes

Preuves : `preuves/vm-2026-10-04-final/LIRE.md`. Windows PowerShell 5.1.26100.6584 Desktop, VM hors domaine, session console du compte administrateur temporaire `PestoFinal`, lanceur avec jeton filtré.

- **Refus UAC corrigé** : l’ancien EXE `8fd5bd8c…` rendait 1 et des diagnostics après un vrai clic Non. `Start-Process` perdait Win32Exception 1223. `Process.Start` conserve l’erreur native ; le nouveau lanceur rend 1223 sans reçu. Acceptation réelle : 0, sonde UAC_OK, Admin=True et RelaisEleve=True, reçu archivé. La sonde s’arrête avant le moteur et ne prouve ni SSO, ni AD, ni reprise entre comptes.
- **Tests du correctif** : 30/30 Startup sous 5.1 ; 16/16 tests Python ciblés (sonde et codes) ; 407/407 contrôles avec le vrai parseur 5.1. Premier rapport à 409 issu d’une ancienne copie du validateur, conservé comme diagnostic ; le rapport final utilise le validateur courant et 66 scripts. Le champ `windowsExecuted=false` de ce validateur qualifie l’absence de test natif WPF/AD par cet outil, pas le système qui a exécuté son parseur.
- **Interface** : onglet Apparence et menu Paramètres actifs visibles en contraste élevé, puis retour au thème normal (flags 126). Ctrl+1 à Ctrl+4 fonctionnent. Les premiers essais clavier perturbés par le pilote sont conservés et distingués des captures `clavier-natif-*` concluantes. Échelles 125–200 %, RDP et lecteur d’écran restent non joués ; tentative d’accès au sélecteur Windows non concluante, aucune échelle modifiée. 2.4 reste bloqué par le modèle de configuration ; 2.12 n’est pas validé par la tentative faite alors que la boîte du refus précédent était encore ouverte.
- **Mise à jour réelle du code RC23** : archive d’origine extraite sur Windows ; aperçu inchangé, application vers 1.0, 38 composants conformes. Configuration, `wad/gp.prefs.json`, journaux et reçus témoins conservés octet pour octet. Les données sont synthétiques, pas des résultats AD. Clé GP absente dans le profil de démo avant et après ; conservation de valeurs registre existantes non prouvée. Après arrêt injecté du processus au premier remplacement, code 93, verrou présent, lanceur 126 ; récupération en aperçu sans altération, sauvegardes conservées. Ne prouve ni panne électrique ni récupération appliquée.
- **AD et Entra** : aucune lecture ou mutation AD réelle par Pesto, aucune jonction, renommage, déplacement ou reprise réelle. Accès de test et OU demandés à David ; aucun mot de passe collecté dans cette campagne. Les doubles AD ne remplacent pas ces recettes. Coupure réseau, disque plein, fermeture du moteur entre deux mutations et import réel des anciens reçus restent à jouer.
- **Autres limites antérieures** : arrêt du worker de la fiche État non vérifié ; L2 vu par son mécanisme, P7 vu sous 5.1 pour un contrôle sur huit ; 12 des 13 scripts corrigés pour `$PSScriptRoot` seulement analysés. ACL de déploiement vérifiées dans la campagne précédente ; pas de validation des opérations métier de registre/partage.
- **Livraison** : packs candidats PROD/DEV issus de cet EXE, configuration modèle non configurée. EXE non signé, build non reproductible entre versions LLVM. Ces archives permettent la reprise de la recette ; aucune publication de version de production ni clôture des 90 points.
- **Clôture** : critères de `V1_RECETTE_WINDOWS.md` non remplis tant que les phases AD et les autres cas requis ne sont pas joués. État de nettoyage et contrôles des archives dans le `LIRE.md` de la campagne finale.

## Campagne AD réelle du 04/10 au soir — en cours

Accès fourni par la configuration existante du labo, compte temporaire `LABO\pesto-qualif` délégué uniquement sur `OU=Pesto-20261004,OU=ADCC-Lab,DC=labo,DC=local`. Compte ajouté aux administrateurs de la seule VM Pesto pour la recette SSO ; aucun droit administrateur du domaine. Instantané froid `04-avant-AD-Pesto-20261004` pris avant mutation. Secrets exclus des preuves et de Git.

- La précision de David sur le nom du poste est intégrée : P portable, S fixe, V VM ; département sur six chiffres, site physique sur deux lettres, service sur trois caractères, numéro sur trois chiffres. V, auparavant seulement lu comme nom historique, est maintenant généré dans les parcours unitaire, jonction, noms et capacité. Le numéro 000 reste lisible seulement pour les noms existants.
- Jonction réelle depuis le formulaire normal : `V999004AAQA1001` dans `ALPHA-AA`, code 10 et reçus `PendingRestart`, sans redémarrage implicite. Un second ajout est bloqué.
- Après redémarrage explicitement confirmé : nom actif/configuré, domaine, MachineGuid, nouveau démarrage, GUID objet/OU et canal sécurisé contre le DC du plan concordent. La lecture seule n’a pas clos l’intervention. « Conserver cette lecture » a ajouté l’observation en gardant le blocage. Une lecture devenue trop ancienne a été refusée dans l’interface ; une nouvelle lecture et une confirmation explicite ont ensuite passé les deux reçus à `Verified`.
- Des objets de recette réels ont été supprimés/recréés pour vérifier les changements de GUID d’un compte précréé et d’une OU au même DN : refus avant `Add-Computer`. Une exclusion de politique avant création du reçu est aussi acquise ; elle ne prouve pas le cas distinct d’échec après écriture de `Running`.
- Connexion AD explicite hors domaine puis SSO en domaine après UAC réelle acquis. Le même compte est utilisé avant/après élévation ; le scénario avec deux comptes UAC distincts reste séparé.
- Deuxième lancement normal pendant une instance élevée : vérificateur en 1, code natif 128, aucune nouvelle UAC. Le contrôle de paquet a refusé un chemin de rapport déjà utilisé ; le même contrôle vers un fichier neuf passe.
- Tests Windows : noms P/S/V et 5 994 combinaisons, stabilisation, suites WPF 21/22/23 et banc natif passés. Le contrôle Python lisait le XAML en encodage Windows implicite : lecture UTF-8 explicite corrigée. Un test Pester ne chargeait pas une fonction pure imbriquée dans le worker Entra : chargement corrigé, puis `Verify-Release` terminé en code 0.

Les tentatives de pilotage en délai dépassé ne sont pas assimilées à un échec produit. Les rapports initiaux en échec sont conservés avec ceux du rejeu. La preuve de signature reste absente ; aucun certificat de confiance n’a été fabriqué.

### Défaut F7 réellement reproduit puis corrigé

Sur le DC du labo, l’ancien filtre de groupe exclu ne trouvait pas l’appartenance si le DN du groupe contenait un antislash, sans lever d’erreur. Parenthèses et astérisque seuls fonctionnaient. Le double historique vérifiait uniquement la chaîne LDAP et ne détectait pas ce défaut.

Le filtre utilise désormais le GUID binaire du poste et le DN alternatif `<GUID=...>` du groupe, après confirmation de l’identité relue. Cette forme est définie par [MS-ADTS, formes alternatives de DN](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/92a54869-38d7-4e71-a3be-5f67a0dcdd7e) ; la recherche transitive reste celle de la règle AD 1.2.840.113556.1.4.1941. Les essais réels couvrent groupes avec `( ) * \`, appartenance directe, appartenance imbriquée, et non-membre non bloqué. Le banc de stabilisation passe à 25 cas, tous verts sous 5.1. Le gate complet `gate-5dc8cea/resultat.txt` est PASS.

Les vérifications de disponibilité des noms ont aussi été jouées sur des objets AD dédiés : collisions indépendantes sur `name`, `sAMAccountName` et `dNSHostName`, puis nom libre daté sans création d’objet. Les fixtures sont supprimées dans le nettoyage du test. Le renommage réel dans le même site vers `V999004AAQA1002` est confirmé après démarrage : mêmes GUID/OU, noms actif et configuré concordants, reçus central et direct Verified. Le redémarrage Windows du labo est resté bloqué après fermeture de Pesto ; un arrêt/remise en marche de cette seule VM a été nécessaire. Cela ne prouve pas un redémarrage Windows sans incident.
