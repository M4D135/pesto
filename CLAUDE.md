# Consigne de reprise V2 — 1er novembre 2026

**Relève du 01/11 :** David a demandé à Codex de prendre la relève totale, puis de relire les derniers échanges Claude. Cette demande remplace le transfert du 28/10 ci-dessous. Les consignes KBZA fournies le 01/11 s’appliquent : gros travaux confiés au Spark, vérification indépendante par Codex, pas de nouvelle rafale de sous-agents. Le look et les animations restent validés.

**12/11/2026** : à la demande de David, la page Paramètres reprend la page de Domenia 2 (bandeau, rail de sections, recherche, adresse `?section=`), livrée en 2.0.15. Cette exception vaut pour cette page seulement ; le reste du look et des animations reste validé.

Reprise de la publication **2.0.9** : voir [le suivi daté](v2/docs/VALIDATION-REPRISE-20261101.md). Ne pas traiter une campagne candidate réussie comme la preuve d’une release publiée. Les tentatives officielles 10 et 11 du run `41196030973` ont échoué ; leur cause détaillée reste à établir. La branche Claude est conservée. Son sélecteur de runner (`27652d9`) a été repris explicitement dans `f4d9ffb` pour une comparaison sur le portable ; son outil de revue (`de9d5da`) n’est pas intégré. Le runner de secours est utilisé à la demande puis doit être arrêté à la fin du travail. Aucune intervention sur les VM.

## Consigne précédente du 28 octobre 2026

**Relève du 28/10 (après-midi) :** David a transféré le projet de Codex vers Claude Code sur le Mac (`outputs/REPRISE_PESTO2_CLAUDE_CODE_20261028.md` du dossier de session). Cette relève remplace la consigne « full Codex » ci-dessous ; le reste reste applicable.

Décision actuelle de David : reprendre et terminer Pesto V2 en **full Codex, avec plusieurs agents**. Cette instruction remplace la priorité Spark ci-dessous pour cette reprise. Le look et les animations actuels sont validés : les conserver, concentrer le travail sur les comportements, la robustesse et les qualifications restantes. Préserver le travail du Spark et les modifications locales antérieures ; leur présence ne suffit pas à prouver leur validation.

## Consigne précédente du 26 octobre 2026

Décision actuelle de David : solliciter davantage le Spark pour économiser les tokens Codex. Lui confier les lectures volumineuses, premiers jets de code/tests/docs et relectures, avec la demande et les fichiers complets. Codex garde le cadrage, les actions sur les machines et la vérification indépendante. Cette priorité remplace la restriction de délégation du 25 octobre ; elle ne change ni le périmètre de recette ni les autorisations de publication. Si le Spark est indisponible, le signaler avant une bascule cloud coûteuse.

Pour les demandes longues, préférer `~/bin/kbza ask --prompt-file FICHIER --no-memory --max-tokens 0 --timeout-seconds 0 --idle-timeout-seconds 0` lorsque le contexte utile est déjà dans le fichier. Le transport MCP a interrompu une relecture après 300 secondes malgré les délais applicatifs à zéro ; conserver les demandes complètes et attendre le client local, sans plafond arbitraire ni relance automatique.

La demande courante de David porte sur `codex/pesto-v2-20261023`, directement depuis GitHub. Vérifier le dernier head avant intégration et préserver les modifications concurrentes. Le travail Spark non poussé n’est pas intégré. Développer, compiler et contrôler les parcours ciblés, commit/push sur cette branche, puis qualifier les seuls parcours Windows critiques autorisés. Ne remplacer aucune release V1 par une V2 incomplète.

Lire `v2/README.md`, `v2/docs/PARITY.md`, `CONFIGURATION.md`, `PACKAGING.md`, `QUALIFICATION-WINDOWS.md` et `VALIDATION-REPRISE-20261025.md`. La configuration V2 est celle du profil de l’opérateur ; démo, santé et rollback binaire ne la remplacent pas. Un seul `Pesto.exe`, packs PROD/DEV autonomes, runtime fixe inclus. Exclusions définitives : LAPS, GLPI, tickets, multidomaine, PS7 obligatoire et signature applicative. Maintenir mutex GP, reçus durables, confirmations et refus explicites ; aucun reboot/changement AD implicite, aucun faux succès.

Les consignes Spark, publication sur master et suspensions de tests ci-dessous décrivent l’historique V1. Elles ne remplacent pas cette demande V2. Les périmètres de VM autorisés et l’interdiction d’intervenir sur les VM voisines restent applicables.

---

# Pesto — mémoire projet

Outil d'administration Active Directory (jonction au domaine, renommage, déplacement de postes).
Moteur **Windows PowerShell 5.1 + WPF** dans `DEV/wad/`, lancé par un **EXE natif x64** (`DEV/Pesto.exe`,
source C sans CRT dans `DEV/tools/launcher/`) qui vérifie les SHA-256 des composants avant de démarrer PowerShell.
Successeur de « GP » (Gestion des Postes). Version courante : **Pesto 1.0**. Le bilan de référence est `DEV/docs/BILAN_76_POINTS.md`.

Lire d'abord les décisions actuelles ci-dessous. `PROMPT_RELAIS_2026-10-04.md` décrit l'état historique au 04/10.
`PROMPT_REPRISE.md` est historique
(passage RC23 → 1.0 au 02/10). Base reçue intacte : `reference/`.


## État de livraison du 16 octobre 2026

Développement local : 88 fonctions, 19 évaluations conclues, qualification locale 105 acquise.
Restent 11 qualifications externes et la mesure prolongée 107. Le lot de qualification
étend les bancs Windows, WPF, interruptions de mise à jour et sorties confidentielles.
Trois textes de support/erreur ne filtraient pas toutes les données de type mot de passe :
ils sont corrigés et couverts par des sorties réelles avec marqueur synthétique.
Preuves : `preuves/qualification-2026-10-16/README.md` ; catalogue dans
`DEV/docs/implementation/catalogue-120.json`. Ne pas confondre les builds des anciennes
campagnes avec le candidat courant. Guides DOCX/PDF v1.0 applicables, packs DEV/PROD classiques.
CI 38822908737 verte au commit b107ab0 : 555 Python sur Linux, 51 suites par Windows,
52 contrôles WPF sans cas ignoré, 381/533 cycles de fenêtre isolée. EXE 9c8605d3…,
63 composants runtime. Accès VM bloqué par des expirations SSH répétées côté hôte
et invité, capture E_FAIL ; aucun nouveau parcours GUI/AD réalisé. La vérification
physique du PC a été demandée à David. Le commit de code testé est identifié ci-dessus ; les packs et preuves sont livrés avec le commit de livraison suivant sur master. Vérifier origin/master pour son identifiant exact.

**19/10** : liste des services d'« Un poste » incomplète au démarrage corrigée (lecture ciblée du site relancée
fenêtre prête, après échec et à l'ouverture de la liste ; `d31e590`). Packs régénérés à la demande de l'utilisateur
avec l'EXE compilé dans le cloud (clang/lld 18.1.3, `f7e68100…`), pas sur le Mac ; essai manuel rapporté conforme,
sans preuve consignée, aucune campagne VM. Voir `packs/README.md`.

## Décisions actuelles de David

- **16/10, dernière consigne** : une fois le développement terminé, réaliser les tests et le
  débogage VM. Cette autorisation remplace la suspension des essais du 15/10. Elle reste
  limitée à PESTO et au client temporaire déjà autorisé, avec instantané à froid avant
  mutation AD, aucune intervention sur les VM voisines ni restauration de DC01.
- **16/10, calcul** : utiliser le Spark au maximum, limiter les tokens Codex ; les brouillons
  doivent être relus et testés. Éviter de répéter les suites sans changement ou correction.
  Terminer les contrôles locaux/CI, les preuves et les packs avant publication finale sur master.

- **15/10, développement final** : terminer le développement des 120 points et les compléments restant à coder.
  Tests locaux ciblés et courts seulement, aucune simulation ni nouvelle recette VM. Les qualifications externes
  restent distinctes du code livré. Brouillons Spark relus avant intégration ; packs DEV/PROD classiques.
- **15/10, dernière décision de recette** : arrêter les tests VM automatisés pour économiser les tokens.
  David fera manuellement les essais graphiques et le renommage distant. Ne pas relancer cette recette sans
  nouvelle demande. C2 a passé les 45 suites Windows PS 5.1 ; cela ne qualifie pas les parcours GUI ni AD réels.
  La VM cliente temporaire `PESTO-REMOTE-CLIENT-20261015` a été clonée depuis l'instantané déclaré hors domaine,
  réseau interne déconnecté, sans mutation AD ; état invité non vérifié. L'accès SSH 2224 renvoyait FILPRO-W11 :
  seule une lecture d'identité/réseau a eu lieu, aucune modification ; ne pas utiliser ce port pour le clone.
  Les corrections de contrôle distant sont intégrées et testées localement ; le renommage réel reste à qualifier manuellement.
- **15/10, reprise en cours** : acquittement explicite des résultats incertains, partiels ou en protection,
  sans transformer leur résultat en succès. Motif et identité conservés ; nouvelle préparation et nouveaux contrôles.
  Une opération active ou une tâche Windows non confirmée terminée reste bloquante. Les anciennes lignes de lot
  ne sont jamais rejouées automatiquement. Référence : `PROMPT_REPRISE_2026-10-15.md`.
- **15/10** : faire travailler le Spark pour les brouillons et les revues ; vérification indépendante avant intégration.
  Cette décision remplace les restrictions « aucun Spark » plus anciennes ci-dessous. Pousser `master` et le dépôt
  commun après validations, guides et packs. Cette demande remplace le gel de push antérieur.
- **15/10, recette** : `PESTO-W11-TEST` et une VM cliente temporaire explicitement autorisée pour piloter les
  essais de renommage distant ; instantané à froid avant mutation AD, aucune action
  sur les VM voisines ou restauration de DC01. Reçus synthétiques exclusivement dans un dossier isolé.
  Le `cfg.json` privé de David ne doit être ni lu ni conservé. David a fourni l’accès pour déverrouiller la session
  de recette pendant cette reprise ; ce secret n’entre dans aucun fichier du projet ou journal de test.

- Le 13/10, David demande de confier une partie du travail au Spark pour économiser
  les tokens. Cette décision remplace la restriction Codex seul du 12/10 : relecture
  intégrale du lot CLI envoyée au Spark, puis vérification indépendante avant intégration.

- Le 13/10, après recherche comparative et consultation du Spark pour les idées,
  David autorise le catalogue complet de 120 points : « go tout faire, absolument tout ».
  Référence exacte : `DEV/docs/implementation/catalogue-120.json` ; rapports par lot dans
  ce dossier. Les points d'évaluation demandent des mesures ou une décision technique
  étayée, sans activer une optimisation régressive. Implémentation en agents Codex,
  tests locaux puis Windows/GUI sur la seule VM Pesto. Les qualifications externes
  (certificat de signature, orchestrateurs, droits de redistribution, multi-DC réel)
  doivent garder leur statut factuel. Pas de push avant intégration, tests, packs et guides.

- Le 13/10 : le suivi d'une opération terminée doit rester facultatif. Une vérification non consignée
  après redémarrage ne doit pas empêcher de préparer une nouvelle opération. Conserver les reçus et leur
  statut réel, les contrôles de la nouvelle cible et les protections d'une opération encore active,
  incertaine, partielle ou dont la protection n'a pas été rétablie.

- Nouvelle autorisation explicite du 12/10, après les tests Mac : recette rapide dans **PESTO-W11-TEST**
  (VirtualBox), interface puis ajout au domaine, renommage et déplacement, avec captures réelles pour les guides.
  Le DC de labo est partagé : coordonner son démarrage, ne pas restaurer son snapshot ni toucher aux VM
  DOMENIA/FILPRO. Préserver configuration/reçus ; qualifier chaque résultat par le hash du build essayé.
- Codex multi-agents explicitement demandé pour finir le projet. Aucun Spark. Bilan final demandé sur les 76
  améliorations et les ajouts, en distinguant réalisation, preuve et limites.

- Décision finale du 12/10 : abandon complet de l'archive WAD. DEV et PROD restent classiques :
  `Pesto.exe` + dossier `wad/`. Conserver les améliorations et finir tous les points. Le script
  `FABRIQUER_PROD.cmd` reconstruit depuis un dossier wad complet, sans changer les sources ni
  écraser une distribution existante. Brouillon WAD sauvegardé hors du dépôt, non distribué.

- Dernière consigne de calcul du 12/10 : « go sans spark, full codex ». Remplace les demandes antérieures de délégation au Spark ; aucun nouvel appel Spark pour ce chantier.

- Dernière précision : aucun nouveau push tant que tous les travaux logiciels, tests locaux, packs et guides ne sont pas terminés. Poursuivre en autonomie ; conserver les étapes en local.

- Connexion demandée le 12/10 : les deux fenêtres de connexion restent au premier plan, avec une seule activation initiale. La fenêtre principale conserve son comportement normal.

- Réglages UI demandés le 12/10 : hors domaine, désactiver aussi visuellement « Plusieurs postes ».
  Bouton réduire/déployer : petite icône seule tout en bas de la barre latérale, comme le contrôle
  BtnUxSidebarToggle de DOMENIA (32 px, Path 18 px, visible quand le menu est replié).

- Le 12/10 : réaliser les 76 améliorations proposées et ajouter une jonction silencieuse, activable explicitement
  dans la configuration pour une task sequence. Tirage aléatoire actif par défaut parmi tous les candidats libres
  des filtres actifs ; coordination partagée et réservation AD restent inactives par défaut.
- Mutualiser les modules avec DOMENIA et FILPRO : source canonique privé `M4D135/m4d-admin-common`, C#5/net472.
  Chaque produit embarque sa version/hash verrouillés, sans téléchargement au démarrage. Corriger le dépôt
  commun puis actualiser les consommateurs ; ne pas éditer indépendamment les copies vendor.
- Les guides DOCX/PDF finaux décrivent Pesto **1.0**, sans récit d'évolution de version. Les réviser après le logiciel.

- Restriction initiale du 12/10 : tests Mac uniquement. Elle est remplacée par l’autorisation de recette VirtualBox ci-dessus ; cette autorisation reste limitée au poste PESTO et au domaine du labo.
- Le 12/10 : « nettoie le github, commit tout en master », « en deux pack, dev et prod, comme à l'origine ».
  Dernière précision du 12/10 : `master` remplace la demande précédente de `main`. Branche de référence : `master`. Conserver les deux livrables `packs/Pesto_DEV.zip` et `packs/Pesto_PROD.zip`.
  Supprimer uniquement les branches entièrement intégrées après vérification ; préserver l'historique.

- Décision de David du 08/10 (réseau réel) : « remet comme avant ça marchait bien, le mutli controleur foutr la merde » :
  plus de bascule vers l'émulateur PDC ; contrôleur découvert par Windows, comme avant le 07/10. Remplace la décision du 07/10.
- Décision de David du 07/10 (la plus récente) : « utilise le spark tant que possible pour économiser tes tokens ». Elle remplace celle du 04/10 ci-dessous. Les réponses du Spark restent des brouillons : relire et tester avant d'intégrer.
- Décision antérieure du 04/10 : « oublie le spark only codex ». Pesto revient à **Codex uniquement**. La demande de revue Spark initiée après l’autorisation temporaire de 21 h 54 est annulée ; aucune nouvelle délégation au Spark.
- Les anciennes campagnes restent liées à leur build. La nouvelle recette limitée du 12/10 est autorisée explicitement ci-dessus.

## Règles non négociables

- **PROD classique : `Pesto.exe` + dossier `wad/`.** DEV conserve ses fichiers de développement.
- Les empreintes des composants sont **incorporées dans le lanceur** : toute modification d'un fichier de `wad/` listé dans
  `Get-PestoRuntimeFiles` (`wad/Pesto-Integrity.ps1`) impose `build_native.py` **puis** `refresh_manifest.py`.
- Règles métier : jonction locale et renommage unitaire **sans file**, lots séparés ; même site = renommage seul, OU inchangée ;
  nouveau site = déplacement **seulement après renommage confirmé** ; en domaine = connexion Windows intégrée après UAC, pas de
  second login automatique ; hors domaine = compte AD explicite ; **aucun** redémarrage, retrait Entra ou changement de sécurité
  implicite ; retrait Entra avant renommage uniquement si hybride confirmé **et** politique autorisée ; pas de WinRM obligatoire.
- Ne jamais renommer ni effacer : `cfg.json`, préférences, journaux, reçus, identifiants de stockage historiques **GP**
  (`%ProgramData%\GP\…`, `%LOCALAPPDATA%\GP\State\…`, `HKU\<SID>\Software\GP`, mutex `GP_*`).
- Un résultat incertain ou tardif n'est jamais un succès ; une étape confirmée n'est jamais rejouée ; aucun verrou effacé pour débloquer.
- **Honnêteté des preuves** : distinguer ce qui a tourné sous Windows PowerShell 5.1 / WPF / UAC / AD réel de ce qui a tourné
  sous PowerShell 7, Wine, Mono ou des doubles. Ne jamais annoncer recette Windows, signature ou clôture des 90 points sans preuve.
  Ne pas « passer en 1.0 » par simple remplacement de titres.
- **Domaine réel du labo jamais versionné** (nettoyage du 9 novembre 2026) : textes, exemples et fixtures disent
  `labo.local` / `LABO` ; captures et guides masqués. Les outils de labo lisent le vrai domaine dans une config locale
  ignorée par Git : `outils/labo/labo.local.env` (scripts Mac), `-Domain` ou `PESTO_LABO_DOMAINE` (scripts VM),
  `v2/tools/qualification/lab.local.json` (pilotes `.mjs`), `lab.local.json` à côté de l'exécutable ou
  `PESTO_LABO_DOMAINE` (harnais AD). Modèles : `*.exemple`. Voir `outils/labo/LIRE.md`.

## Conventions de code

- `.ps1` : **UTF-8 avec BOM** obligatoire (PS 5.1 lit sinon en ANSI). Fins de ligne : conserver celles du fichier
  (mélange LF / CRLF selon les fichiers — ne pas normaliser en passant). Nouveaux fichiers : BOM + CRLF.
- Cible **PowerShell 5.1 uniquement** : pas de `?:`, `??`, `??=`, `&&`, `||`, `?.`. C# compilé par `Add-Type` : **C# 5**.
- Apostrophes typographiques doublées `’’` dans les chaînes entre apostrophes simples = échappement volontaire, ne pas « corriger ».
- Ne pas affecter de variable automatique (`$home` est en lecture seule ; `$args`, `$matches`, `$event`, `$input`, `$pwd` à éviter).
- Les workers tournent dans des runspaces séparés : toute fonction appelée doit figurer dans la liste de sources du worker
  (`$script:PestoWorkerCoreNames` dans `Pesto-Core.ps1`, `Get-PestoInspectionSource`, `Get-PestoDirectSupportSource`, …).
- Codes de résultat : 10/20/77 succès avec redémarrage requis, 30/33 déplacement vérifié, 32 protection non rétablie,
  89 renommé mais déplacement à reprendre, 96 non lancé, 97 incertain, 98/99 technique. Voir l'en-tête de `Pesto-Core.ps1`.

## Commandes (depuis `DEV/`)

```bash
python3 tools/prepare_dev.py                                   # clone neuf : wad/cfg.json depuis le modèle, jamais écrasé
pwsh -NoProfile -File ../outils/parse_all.ps1 -Root .          # vrai parseur PowerShell sur tous les .ps1 (0 erreur attendu)
pwsh -NoProfile -File tests/Run-StabilisationTests.ps1          # 24 cas au 04/10 (branche points-suite), doubles AD
python3 -m unittest discover -s tests -p "test_*.py"            # 229 tests au 04/10
python3 tools/checks/validate_pesto.py                          # 340 contrôles portables (réécrit tests/pesto-portable-validation.json)
# run_native_portable.py réécrit aussi tools/launcher/pesto_runtime.h et tests/rc23-native-portable.json : build et manifeste d'abord
python3 tools/checks/run_native_portable.py                     # logique C du lanceur avec doubles
python3 tools/launcher/build_native.py                          # EXE (clang + lld-link ; macOS : brew install llvm lld)
python3 tools/refresh_manifest.py                               # manifeste wad/package.json, toujours APRÈS le build
python3 tools/refresh_manifest.py --check
python3 tools/Build-PestoPacks.py --source . --output ../packs  # PROD + DEV (destination neuve)
```

Sous Windows (VM) : `Pesto.exe --check`, `TESTER.cmd`, `TEST_RC23.cmd`,
`powershell -NoProfile -ExecutionPolicy RemoteSigned -File tests\Run-StabilisationTests.ps1`
(sans `-ExecutionPolicy`, la stratégie par défaut Restricted refuse le script).

## État (journal daté du 2 au 4 octobre 2026 : les entrées les plus récentes, en bas, priment)

- Commits : `1375908` base RC23 reçue (ne démarrait pas) ; `8fa63e7` correctifs D1-D4, F2-F7 ; `c2e62e2` outillage macOS ;
  `f04d95e` premières preuves 5.1 (hôte du labo, **pas une VM**) ; `4066c50` points B, C, E ; `c7ded37` version 1.0.
- Vérifié : 122 tests Python, 341 contrôles portables, tests C, `stamp_version.py --check` ; parseur Windows PowerShell 5.1
  (syntaxe seule) 0 erreur / 68 fichiers. Sur l'hôte du labo, base `c2e62e2` : `Pesto.exe --check-json` PASS, suites
  stabilisation / Test-Pesto19 / Names / RC21-23 `-Wpf` vertes (`preuves/windows-hote-2026-10-02/`).
- **Non exécuté sous Windows** : tout ce qui suit `c2e62e2` (B, C, E, 1.0). Aucune UAC, aucun AD réel, aucune mutation.
- `Pesto.exe` n'est pas versionné (`.gitignore`) : le reconstruire (`build_native.py` puis `refresh_manifest.py`).
  Dernier build : clang/lld 23.1.2, SHA-256 `8590640ccab78aefb4badab334d65716550d0a567594ce5216bc87887117d8ed`
  (branche `cloud/revue-b-c-e-v1` ; `583cbef1…` = état `c7ded37`).
- Revue adversariale de `4066c50` et `c7ded37` faite (branche `cloud/revue-b-c-e-v1`, PR vers master) : 3 défauts corrigés,
  dont un **bloquant** (`param()` placé après des fonctions dans `Get-PestoEmbeddedScriptSamples` : Pesto refusait de
  démarrer dans tous les modes). Relecture seulement : rien n'a tourné sous Windows PowerShell 5.1.
- Labo (LAN de David, injoignable depuis le cloud) : VM dédiée `PESTO-W11-TEST` (Windows 11 Entreprise Évaluation,
  groupe de travail, réseau `LABO-LAB`, DC `dc01.labo.local` 10.77.0.10), SSH par clé via rebond `degun@192.168.1.173`
  → `127.0.0.1:2223` (`labadmin`). Instantanés : `00-clone-brut`, `01-ssh-ok-sysprep-bloque`, `02-groupe-de-travail-pret`.
  SID non changé (sysprep bloqué sur `wuaueng.dll`) ; décision proposée : inutile pour la jonction.
- État du labo au 02/10 ~19 h 20 (heure du labo) : `PESTO-W11-TEST` renommée, hors domaine (groupe `LABO` ; la
  généralisation partielle de sysprep l'avait sortie du domaine câble débranché, sans toucher au compte AD de W11-01),
  lien `LABO-LAB` actif, DNS/SRV `dc01.labo.local` OK, écart d'horloge 20 s. `LABO-DC01` démarré (était sauvegardé).
  Instantané à chaud `02-groupe-de-travail-pret` **en cours, très lent** (~10 Mo/min) ; une copie de `DEV/` (commit
  `3b0d501`, sans les correctifs de la PR n° 1) vers `C:\PestoTest` suit automatiquement. À la reprise depuis le Mac :
  vérifier la fin de l'instantané, recopier `DEV/` après fusion de la PR, puis remettre les deux VM en état sauvegardé.
- 02/10 soir (cloud) : PR n° 1 fusionnée dans `master` (`1a04a35`). Sous pwsh 7.4.6 Linux : défaut `param()` reproduit
  sur l'ancien `master`, corrigé après fusion (`Test-PestoRuntimeReady` : 27 fichiers, EmbeddedScripts=3,
  AuditWriter=PASS), stabilisation 8/8, 122 tests, 408 contrôles. Toujours **rien de la 1.0 sous Windows PowerShell 5.1**.
- Le cloud (clang/lld 18.1.3) produit un autre EXE (`61ee7366…`) que le Mac (23.1.2, `8590640c…`) : build non
  reproductible entre versions de LLVM ; EXE et manifeste à livrer viennent du Mac.
- `wad/cfg.json` est ignoré par Git ; le modèle non configuré est versionné dans `tools/cfg.template.json` et
  `tools/prepare_dev.py` le crée seulement s'il est absent (aussi appelé par `Build-PestoPacks.py` et `test_0_prepare_dev.py`).
- Branche `cloud/docs-1.0` : 2 derniers points E corrigés dans `Pesto-Core.ps1` (file : résultat conclu écrasé en 98 ;
  formulaire : `TargetOUGuid` non effacé), stabilisation 11/11 sous pwsh 7. Le manifeste versionné y référence l'EXE du
  **cloud** (clang 18, `b3f39d39…`) : sur le Mac, `build_native.py` puis `refresh_manifest.py` avant toute copie vers la VM.
- `master` = `da1c3f3` (1.0 + documents + correctifs E). Branche `cloud/points-suite` (non fusionnée, rien sous 5.1) :
  points 87 (fiche de build `last-build.json`, garde-fou `cfg.json` dans tous les chemins de packs), 36 (parseur et
  générateur uniques ; type V des VM conservé en lecture), 79/77 (contraste élevé « Suivre Windows », libellés
  d'accessibilité), 01 (codes d'échec du Planificateur), porte PSScriptAnalyzer 1.24 réparée (plantait sur
  `Pesto-Core.ps1`), `LiveSetting` retiré (.NET 4.7.1+), lanceur (`--quiet`, racine de lecteur refusée),
  `update_installation` (reprises vérifiées), `New-PestoDistribution.ps1` réparé, `DEBLOQUER_TOUT` borné au pack.
  Stabilisation 20/20, 37 scénarios C, tests Python, 407 contrôles (pwsh 7 / Linux). Constats ouverts :
  `DEV/docs/V1_CONSTATS_OUVERTS.md`. Le manifeste versionné vise l'EXE du cloud : rebuild + refresh sur le Mac.
- Brouillons 1.0 sur la branche `cloud/docs-1.0` : `README.md`, `LIRE_MOI.txt`, `CHANGELOG.md`, `docs/V1_GUIDE.md`,
  `V1_BILAN.md`, `V1_90_POINTS.md` (statuts inchangés), `V1_RECETTE_WINDOWS.md` (colonnes de résultat vides).
- 02/10 soir (Mac) : EXE reconstruit sur le Mac (`9ee3fe2`, SHA-256 `8c723efb…dae8`). Instantané à chaud
  `02-groupe-de-travail-pret` **échoué** : VirtualBox en mode NEM (Hyper-V actif sur l'hôte) ne convergeait pas (3 h 40),
  une pause l'a fait échouer et a figé la VM ; processus tué après sauvegarde du disque différentiel
  (`C:\ADCC-Lab\VirtualBox\PESTO\sauvegarde-avant-kill-2026-10-02`), puis instantané **pris à froid**. Instantanés
  suivants : toujours à froid. **Phase 1 de la recette jouée sous Windows PowerShell 5.1** sur `PESTO-W11-TEST`
  (SSH, hors domaine) : tout vert sauf 1.3 partiel (boîte de message en console), 1.4 PASS après décision (chaînes du build
  conservées, documents alignés), 1.8 non joué (pas de Python) ; test `DEBLOQUER_TOUT` corrigé (énumérait le dossier réel).
  Preuves : `preuves/vm-2026-10-02/`. Copie sur la VM : `C:\PestoTest` (DEV), `C:\outils`, preuves `C:\PestoTest-preuves`.
- Fin du 02/10 (~23 h 40) : `PESTO-W11-TEST` éteinte proprement (état = instantané 02 + `C:\PestoTest`), `LABO-DC01`
  laissé en marche : `LABO-W11-01` (autre session) tourne et en dépend. `savestate` non live est rapide (~11 s) ; vérifier
  `list runningvms` avant de toucher au DC. Phase 2 bloquée : ouverture de session Windows en console par David.
- 03/10 nuit : constats vérifiés sous Windows (`preuves/vm-2026-10-03/`). **L2 corrigé** (racine ouverte en
  FILE_LIST_DIRECTORY, partage 3 ; avec l'accès 0 le dossier se renommait), **O12 corrigé** (`Pesto_COMPTE_AD.cmd` sans
  `call` ; échouait depuis un dossier `a^b` ou `c%PATH%d`). **L1 non reproduit** (WOF et compression NTFS acceptés),
  code inchangé. EXE `e31dbb9f…` (clang/lld 23.1.2 : mettre `/opt/homebrew/opt/llvm/bin` en tête du PATH, sinon le
  clang d'Apple est pris) ; phase 1 rejouée, mêmes résultats. Sur la VM : `C:\PestoTest` = ce build, ancien pack dans
  `C:\PestoTest-9ee3fe2`. IP labo de `PESTO-W11-TEST` passée en 10.77.0.30 (10.77.0.20 = W11-01 ; l'instantané 02 porte
  encore .20). FILPRO a cloné l'instantané 02 (`FILPRO-W11-TEST`, 10.77.0.40, ssh 2224).
- 03/10 matin : **phase 2 partielle** en console (`preuves/vm-2026-10-03-phase2/`), pilotée par UI Automation.
  Trois défauts corrigés et vérifiés sous 5.1 : démo en erreur fatale (`New-Object` + `@()`, `2d5c182`) ; pages
  invisibles pour UI Automation et noms de palette bruts (`5bb0ba7`). EXE `6702949d…`. 2.2 à 2.5b non joués : la VM se
  fige ~30 min après l'ouverture de session (NEM). Ouverture automatique de `labadmin` **active** sur PESTO-W11-TEST
  (mot de passe changé par David, secret LSA) : la retirer par le script de David (VM démarrée ; aujourd'hui `outils/labo/mac/autologon.sh --retirer`).
  Mises à jour automatiques suspendues (`NoAutoUpdate=1` ; lever : aujourd'hui `outils/labo/mac/windows_update.sh --retablir`). Ces deux scripts
  ne sont pas versionnés à cette date (ils le sont depuis le 04/10 : `outils/labo/mac/autologon.sh` et
  `windows_update.sh`). PESTO-W11-TEST éteinte. Outils de pilotage : `C:\PestoTest-run\` sur la VM.
- 03/10 après-midi : 2.2 PASS, 2.5 PASS partiel (100 % seulement), 2.5b PASS, 2.3 FAIL (aperçu de connexion obsolète,
  P5), 2.4 bloqué (`cfg.json` modèle, P6). Listes déroulantes accessibles et `$PSScriptRoot` corrigés (`ca7ba5b`),
  EXE `73eb6795…`. Premier rendu WPF > 1 min sur la VM : attendre 90 s avant de piloter. `C:\PestoTest` = ce build.
- 04/10 nuit : P1, P2, P3 (affichage) et O4 (refus de retour en arrière, `--allow-downgrade`) corrigés et vérifiés, EXE `4b08eb94…`.
- 04/10 : O9/O10 (liens, jonctions, noms Windows ; Python), P5 (aperçu et tests de connexion : 19/19 sous 5.1),
  suites préférences (15/15) et UX (43/43 en session) remises en état, P7 (textes d'aide) ; contrôles statiques à jour.
  EXE `de44fc4a…`. Workflows multi-agents utilisés (ultracode activé par David). Constats encore ouverts : L1, L2-doc, L4,
  L6, O7, O8, X5, P6, T1, LAB.
- 04/10 après-midi : le clone `~/Downloads/Pesto_V1_CLAUDE_CODE` a disparu (rangement externe, 14:27) ; travail repris dans
  un clone neuf (GitHub fait foi). O8 (files locales signalées par l'aperçu de mise à jour), T1, CHANGELOG et bilan livrés.
  Ouverture automatique de `labadmin` **retirée** de PESTO-W11-TEST (15:00). Constats ouverts : L1, L4, L6, O7, X5, P6, LAB.
- 04/10 fin d'après-midi : L4, X5, O7 traités (`abd6c2e`, EXE `8fd5bd8c…`) sur délégation de David, vus sous 5.1
  (`preuves/vm-2026-10-04/`) : L4 conforme (0, 120, 123, 124, 125, 126, 128 ; boîte sous `--quiet` à la racine d'un
  lecteur trouvée et corrigée), X5 vu en contraste élevé (onglet actif non capturé), O7 vu jusqu'à l'invite UAC (Accepter / Refuser : clic humain).
  L1 et L6 acceptés sous conditions, écrites dans `V1_GUIDE.md` (« Emplacement et droits ») et vérifiées sur un pack PROD
  de test laissé sous `C:\Program Files\Pesto-PROD-test`. Ouverture automatique de `labadmin` réactivée par David pour
  ces tests (16:20), **retirée par lui à 16:50** (`AutoAdminLogon=0`, aucun mot de passe en clair, vérifié) ;
  `NoAutoUpdate=1` maintenu pour la suite de la recette. Outils de pilotage de la VM versionnés dans `outils/labo/` (voir son `LIRE.md`). Constats
  ouverts : P6, LAB. Relais pour un autre modèle : `PROMPT_RELAIS_2026-10-04.md`.
- 04/10 vers 17 h : clone de travail recréé dans `~/Projects/pesto` (le scratchpad de session a été vidé ; tout était
  poussé). EXE reconstruit sur ce clone : mêmes octets `8fd5bd8c…`. VM figée juste après son démarrage (3 vCPU à 100 %,
  SSH muet, écran noir, aucune session) : réinitialisée (SSH en 25 s). **Recette 1.1 à 1.7 rejouée sur `8fd5bd8c…` : verte**
  (1.1 à 1.7 ; stabilisation 24/24 dont les 3 cas O7 ; `preuves/vm-2026-10-04-phase1/`). Corrections de la relecture
  du relais (compte des composants, 407 contrôles, exceptions des modes silencieux, P8 inscrit, outils de labo).
  Écart 66/68 `.ps1` expliqué : sous Windows, `-Filter *.ps1` prend aussi les deux `.ps1xml` ; filtre corrigé dans
  `parse_all.ps1` et `validate_pesto.py` (test, 66 fichiers sous 5.1). Constats ouverts : P6, P8, LAB.
  PESTO-W11-TEST éteinte proprement à 17:33 ; `LABO-DC01` non touché (W11-01 et FILPRO tournent).
- Reste : O7 Accepter / Refuser (2.9) et 2.11, 2.12 en console ; X5 onglet actif ; 2.3 rejoué en recette ; échelles 125-200 % (2.5) ; 2.4 avec une configuration
  validée du labo (P6) ; phases 3 et 4 (identifiants AD saisis par David, instantané à froid avant chaque phase qui mute) ;
  1.8 (Python sur la VM) ; P8 (Ctrl+Tab) ; phase 5 ; packs PROD/DEV livrables après recette ; décision LAB (Hyper-V)
  de David.

- 04/10 soirée, reprise Codex sur `549a4aa` : **1.8 PASS** (407 contrôles, Python 3.14.7 embarqué temporaire, parseur Windows 5.1), **2.3 et 2.11 PASS** en console du compte local temporaire standard PestoRecette, créé avec accord actuel de David. EXE toujours `8fd5bd8c…`. Tests Python Windows : 228 réussis, 1 ignoré en cumulant la passe complète et trois rejeux ciblés après correction du banc (outils absent, imports bloqués par Python embarqué isolé). Pilote de labo corrigé : fin non nulle, absence de session et délai ne rendent plus un faux succès ; six cas réels passent. Preuves : `preuves/vm-2026-10-04-reprise/`. Instantané à froid `03-avant-session-recette-20261004` pris avant création du compte. Ouverture automatique retirée dès la session ouverte ; mot de passe labadmin inchangé.
- Fin de cette reprise : compte PestoRecette et profil retirés, ouverture automatique à 0, aucune tâche PestoPilote restante, VM éteinte proprement (`nettoyage.json`, `vm-fin.txt`). Les trois autres VM restent en marche, sans intervention. Contrôle des 38 composants du manifeste toujours conforme. Revue Spark non obtenue (aucun texte public reçu, collectes annulées) ; code relu par Codex, six cas réels puis test de résultat tardif avec doubles et rejeu réel sans session sur le code final. Reste : P6, P8, LAB, UAC acceptée/refusée, 2.12, contraste onglet actif, échelles 125–200 %, phases AD et robustesse, packs livrables après recette.

- 04/10 fin de campagne : vrai refus UAC reproduit (code 1 au lieu de 1223) ; remplacement ciblé de `Start-Process` par `Process.Start` dans Startup, exception native préservée. Refus 1223 et acceptation 0 avec reçu UAC_OK validés sur le nouvel EXE `aed2be19…`, 30/30 Startup Windows 5.1, 407/407 contrôles parseur, 16/16 Python ciblés. Revue Spark obtenue et vérifiée. X5 onglet actif capturé ; Ctrl+1 à Ctrl+4 vus, P8 clos par documentation de l’absence de Ctrl+Tab/Ctrl+Page suivante. 5.5/5.6 jouées sur archive RC23 originale avec données sentinelles : conservation, interruption, code 126 et aperçu de récupération sans altération. Preuves `preuves/vm-2026-10-04-final/`. Restent P6, LAB, 2.12, DPI/RDP/lecteur d’écran, AD réel et robustesse métier. Compte AD et OU de test demandés, non reçus ; ne pas inventer de configuration ni annoncer la recette close.
- Fin vérifiée : packs candidats PROD/DEV extraits sur Windows, deux contrôles natifs à 0 (38 composants, syntaxe et writer PASS). Compte PestoFinal et profil supprimés, ouverture automatique à 0, secret LSA retiré, aucune tâche pilote restante ; VM arrêtée normalement à 19:13:30, autres VM inchangées. Archives candidates dans le dossier outputs du chat ; aucune publication de production.
- 05/10 (Claude, à la demande de David) : **S1 critique** corrigé : en jonction, le service redevient une liste éditable
  des services connus du site ; hors domaine, l'inventaire est lu en arrière-plan à l'ouverture de « Ajouter au domaine »
  et au choix d'un site (jamais pendant un traitement) ; « Un poste » partage la même liste. **S2** : « Service » au lieu
  de « Équipe » dans Noms. Défauts présents dans la RC23. EXE `98eba546…`. Windows 5.1 sans bureau : stabilisation
  27/27, WPF réel 10/10 (`preuves/vm-2026-10-05-services/`). Vue en session (démo, AD réel) non jouée. Ancien pack sur la
  VM dans `C:\PestoTest-avant-0510`. Relecture Spark lancée par erreur puis arrêtée (décision « only codex ») ; non utilisée.
- 07/10 : version de l'archive `PESTO.zip` (fenêtres de résultat, recherche de site retirée, démo de l'action directe),
  trouvée non commitée dans le clone, relue et commitée. EXE de l'archive compilé avec le clang d'Apple (piège du PATH) :
  remplacé par `92676b22…` (clang/lld 23.1.2). 5.1 sans bureau : check-json PASS, stabilisation 27/27, WPF services 10/10.
  `cfg.json` de l'archive : Simulation=true, DirectProd=false (à confirmer par David).
- 07/10 soir : **S3** (3 techniciens sur le banc, même nom proposé) : nom pris → nom suivant proposé, revérifié, confirmé
  en un clic (jonction et renommage direct). AD réel du labo (banc `outils/labo/mac/banc-noms-pris.sh`, compte saisi par
  David) : PASS, objets de test supprimés. WPF jonction 11/11. EXE `9eb555ed…`. Risque restant : plusieurs DC (réplication).
  Session console de test : ouverture automatique ACTIVE et `DevicePasswordLessBuildVersion=0` posés par David le 07/10 :
  à retirer en fin de campagne (`autologon.sh --retirer`, puis remettre la valeur 2). Revue Spark : premier lot sans
  réponse publique après 55 min de raisonnement ; relancée en mode direct.
- 07/10 : décision de David « PDC pour tous les postes » appliquée (`Set-PestoDCRole`, rôle « Secours » signalé si le PDC
  est injoignable). EXE `ae8370ad…` ; 5.1 : parseur 66/0, check-json 0, stabilisation 27/27, WPF noms pris 11/11.
- 07/10 soir : revue du design en session console (démo). David : garder les infobulles ; retirer seulement l'entrée
  « Aide et raccourcis » du menu (fait). Aperçu « Nouveau nom » corrigé. EXE `921864d2…`. VM éteinte à 19:27 pour
  libérer la mémoire (session DASHBOARD / DEX-SRV) ; ouverture automatique et PasswordLess=0 toujours posés (VM éteinte).
- 07/10 20:22 : fin de campagne. Ouverture automatique retirée par David (`AutoAdminLogon=0`, aucun `DefaultPassword`),
  `DevicePasswordLessBuildVersion` remis à 2 par David (vérifiés), PESTO-W11-TEST éteinte proprement. DC01 non touché par
  Pesto (son arrêt vers 20:18 vient d'ailleurs, signalé à la session FILPRO).
- 07/10 soir : guides du dossier DOC refaits (demande de David : « plus détaillé, plus simple pour les tech »). Sources
  versionnées dans `outils/guides/` (`technicien.md`, `administrateur.md`, fiches JSON, captures) ; `build_guide.js` produit
  le `.docx` et le `.pdf` (Chrome sans interface) ; voir `outils/guides/LIRE.md`. Premiers jets par le Spark, relus et
  corrigés contre le code (libellés vérifiés par grep). Archive livrée : `~/Desktop/NEW/PESTO-1.0-final-20261007-c.zip`
  (= `-b` + nouveau dossier DOC). Prompt réutilisable pour un autre logiciel : `outils/guides/PROMPT_GUIDES_AUTRE_LOGICIEL.md`.
- 07/10 fin de soirée : prompt et kit éprouvés (agent à l'aveugle sur un logiciel fictif jusqu'au PDF, revue adverse,
  contre-vérification, contrôle final) ; défauts confirmés corrigés (9 champs, recadrage exact `crop_image.swift` au lieu
  de `sips --cropOffset 0 0` qui recadre au centre, contrôles de syntaxe et d'encodage, Chrome portable, `--no-sandbox`
  en root Linux). Trois captures des guides Pesto recadrées exactement. Archives : `PESTO-1.0-final-20261007-d.zip`
  (remplace `-c`, seul DOC change) et `KIT-GUIDES-20261007.zip` (`outils/guides/fabriquer_kit.sh`).
- 08/10 nuit : demandes de David : guide technicien direct, sans mode simulation ni démonstration ; détails dans le guide
  administrateur ; docs simples, en commençant par la mise au domaine ; accueil du logiciel sans slogan. Accueil sobre
  (`Pesto-Shell.xaml`, `tests/test_accueil.py`), EXE `bbd7473a…`, packs `pesto-packs/2026-10-07-accueil`. Guides réécrits
  (technicien 23 p., 10 chapitres ; administrateur 48 p., 27 chapitres), vérifiés contre le code, captures = rendus de la
  vraie fenêtre en mode réel, valeurs fictives (`preuves/vm-2026-10-07-reel/`, `render-guide.ps1`), contrôlées par OCR
  (`outils/guides/ocr_image.swift`). Démo réelle préparée (`outils/labo/mac/demo-reelle.sh`, `autologon.sh --compte`) mais
  non jouée : saisie du mot de passe AD non aboutie (le lancement par « ! » dans le chat ne transmet pas la saisie masquée).
  PESTO-W11-TEST : instantané à froid `04-avant-demo-reelle-20261007` ; ouverture automatique posée par David pour
  LABO\tech.pesto (compte non créé) : à retirer (`autologon.sh --retirer`) ou remettre l'instantané. Livraison :
  `~/Desktop/NEW/NEW/PESTO.zip` et `KIT-GUIDES-20261008.zip`.
- 08/10 matin : **démo réelle** sur l'AD du labo (vrai PROD, compte et OU de recette, préparation et nettoyage par David)
  pour les captures des guides : renommage et changement de site réels par Pesto, vérifiés et consignés. Trois défauts
  trouvés et corrigés : reçus/interventions historiques jugés invalides si le préfixe a changé (R1), refus avant lancement
  noté 97 au lieu de 96 (R2), mise en garde « simulation » de l'historique affichée sans lot simulé. EXE `f1d88060…`
  (5.1 : syntaxe 71/0, check-json 0 DEV et PROD, stabilisation 27/27, RC23 65 contrôles). Guides refaits avec ces
  captures (technicien 26 p., 17 figures). AD nettoyé, PESTO-W11-TEST remise sur `04-avant-demo-reelle-20261007` et
  éteinte. Livraison `~/Desktop/NEW/NEW/PESTO.zip` (+ `KIT-GUIDES-20261008.zip`). Preuves `preuves/vm-2026-10-08-demo-reelle/`.
- 08/10 après-midi : défaut signalé par David en mise au domaine (plusieurs noms pris essayés, puis arrêt après ~3 : il fallait
  relancer). Causes : noms calculés sur l'inventaire local (chargé en arrière-plan) contre un contrôle sur tout le domaine ;
  inventaire arrivé pendant l'enchaînement → « Contrôle périmé », arrêt ; compteur non remis à zéro au clic. Corrigé : série
  du nom pris lue dans l'AD et écartée, relance automatique (3 au plus), compteurs remis à zéro au clic, inventaire des noms
  inclus. EXE `4636913b…` ; 5.1 : parseur 66/0, check-json 0 DEV et PROD, RC23 65/0, stabilisation 27/27, WPF 25/25
  (`preuves/vm-2026-10-08-noms-suite/`). Banc AD réel `outils/labo/mac/banc-noms-serie.sh` (mot de passe tapé par David).
  Guide administrateur (chapitre 3) mis à jour. PESTO-W11-TEST démarrée sur l'instantané 04 (hors domaine) pour ces tests :
  `C:\PestoTest` = ce build, ancien dans `C:\PestoTest-avant-0810-143253`.
- 08/10 vers 15 h 30 : retours de David sur le réseau réel. (1) Bascule PDC retirée à sa demande (`8648e93`, EXE `210137fd…`).
  (2) « 30 s mini pour afficher un service, bouton vérification grisé » : services et numéros pris lus par une recherche
  ciblée du site (`Request-PestoSiteLookup`, `Pesto-Directory.ps1`) au lieu d'attendre l'inventaire complet ; « Un poste »
  dit ce qui manque sous le bouton. EXE `c5fb8ba6…` ; 5.1 : parseur 66/0, check-json 0 DEV et PROD, stabilisation 27/27,
  WPF noms 25/25, WPF services 14/14, UX 42/44 (2 mises en page réelles KO sans bureau, identiques avant). Enquête multi-agents
  sur le bouton grisé : causes anciennes, avec message (CfgRestartRequired après « Enregistrer », verrous de reçus).
- 08/10 vers 16 h : « Vérification requise » en renommage (David, réseau réel, après une mise au domaine) : cause dite
  sous le bouton, bouton « Vérifier la jonction » / « Vérifier l'opération » / « Ouvrir les interventions » ; « Enregistrer »
  sans changement ne demande plus de relance (EntraPolicy absent = HybridOnly). EXE `ef0cc654…` ; 5.1 : parseur 66/0,
  check-json 0 DEV et PROD, stabilisation 27/27, noms 25/25, services 14/14, blocage 14/14 (9 échecs sur la version
  précédente), UX 42/44 (2 KO sans bureau, identiques avant). Preuves `preuves/vm-2026-10-08-blocage/`.
- 08/10 soir : plusieurs techniciens (registre partagé, réservation AD à la jonction, numéro au hasard), reprise après
  redémarrage (RunOnce/NextLogon), Paramètres complets (onglets Noms et coordination, Politique), plus d'inventaire complet
  au choix du site. EXE `df41450b…` ; 5.1 : parseur 66/0, check-json 0, stabilisation 27/27, noms 25/25, services 14/14,
  blocage 14/14, registre SMB 15/15 (6 processus), jonction 23/23, paramètres 16/16, reprise 16/16, UX 42/44 (2 KO sans
  bureau). Banc de collisions : `preuves/vm-2026-10-08-reservations/collisions.html`. Le cfg réel de David n'est pas
  versionné et ses copies de travail ont été effacées à sa demande ; modèle fictif : `DEV/tools/cfg.modele-complet.json`.
  Grok : crédit épuisé (402) ; Spark : idées reçues. Audit multi-agents : 173 suggestions (à livrer à David).
- 08/10 vers 19 h 20 : reprise après redémarrage (RunOnce/NextLogon) retirée entièrement (David : « supprime totalement cette
  option c pas faisable », « devoir se relogguer au reboot c merdique »). Réservation AD vérifiée sur l'AD réel (worker de Pesto :
  création, doublon refusé, retrait). EXE `cbb0b008…`. PESTO-W11-TEST jointe (P111301VA765003, Paris), session auto
  LABO\tech.pesto, PasswordLess=0 : à remettre (nettoyage + instantané) en fin de tests visibles.


- 12/10, revue Codex demandée par David après le travail Spark : corrections auth AD explicite/diagnostic, contrat
  des workers, statuts SSH et distribution DEV. Tests locaux Mac autorisés ; **aucune VM ni AD pour cette passe**.
  EXE/manifeste et packs reconstruits. Bilan et limites : `DEV/docs/V1_BILAN.md`, revue locale du 12/10 ; preuves
  `preuves/audit-mac-2026-10-12/`. Le changement préexistant de `DEV/tests/worker-runspace-report.json`
  a été conservé puis commité à la demande « commit tout » ; ce rapport historique de 7 contrôles ne remplace
  pas les nouvelles preuves de 9 contrôles dans le dossier daté. PR n° 2 fusionnée dans `master`, branches intégrées nettoyées.


## État logiciel vérifié le 12/10/2026 — R7

- EXE final : `ba43a8de4d303b4d09ff8831ba112c345adc8b776c31a1367bc5ec90da3a78b1`, 44 composants.
  329 tests Python et 17 suites PowerShell locales réussis ; parseur 38 fichiers, 0 erreur. Sous Windows PowerShell 5.1 :
  Engine117, Automation34, JoinReservation27, UiPresentation39, BootIdentity17, WorkerContract20, Join39, tous réussis.
- Pilote réel : renommage et déplacement Lyon→Paris confirmés, GUID conservé ; puis jonction R6 du poste
  `P111301LY765128` dans `labo.local`, OU Lyon, compte activé, canal sécurisé conforme après démarrage.
  Intervention `5f0eee7279bb459c93b9d9939e7caf11` consignée Verified. Ancien compte Paris conservé désactivé.
- La jonction prépare et relit le nouveau nom local, puis utilise `JoinWithNewName,AccountCreate`. Une issue partielle
  reste conservée et bloque le rejeu. L'identité de démarrage vient de Kernel-General12 StartTime, stable malgré une
  correction d'horloge ; aucun retour silencieux au CIM LastBootUpTime susceptible de dériver.
- R7 ne change que deux fonctions de présentation par rapport à R6 : le champ et l'aperçu conservent le nom soumis
  après rafraîchissement. Moteur de mutation identique ; vérification UI réelle R7 : nom/champ/reçu cohérents,
  fenêtre principale non Topmost. Les nouveaux tests reproduisent 7 échecs sur l'ancien affichage.
- Captures VirtualBox : une veille écran DPMS peut donner bpp0, screenshotpng E_FAIL et surfaces figées/blanches
  malgré un arbre UIA vivant. Un réveil clavier matériel rétablit l'affichage ; éviter les Maj répétées (StickyKeys).
  Aucun réglage pilote, registre, pare-feu ou UAC modifié pour ce diagnostic.
- Preuves détaillées : `preuves/vm-2026-10-12/`, `preuves/ameliorations-mac-2026-10-12/final/`.
  Le snapshot06 de départ et les sauvegardes sont conservés ; aucune restauration du DC ni des VM voisines.
  La task sequence réelle, la réplication multi-DC, les ACL de déploiement et la matrice complète DPI/accessibilité
  restent des qualifications distinctes ; le lanceur n'est pas signé.
