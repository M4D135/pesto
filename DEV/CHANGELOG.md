# Pesto 1.0 (candidate ; qualification Windows partielle, liée aux builds documentés)

- 23/10/2026 — Jonction au domaine : le nom proposé est calculé dès la lecture AD du site, avant d’activer « Ajouter ». Aucun premier numéro provisoire pendant le chargement ; un résultat incomplet ne valide aucun nom. Le choix reste stable tant qu’il est disponible. Si un autre poste le prend entre-temps, la nouvelle proposition exige un nouveau clic. Tests de présentation, cache, noms et réservations avec doubles ; pas de nouvelle qualification Windows/AD.

- Revue locale du 12/10 : erreur AD explicite conservée sans faux diagnostic de compte local ; exception d'origine
  conservée et diagnostic prudent si le compte Windows est indéterminé. Contrôle des sources et dépendances des
  workers renforcé ; script SSH sans perte de statut ni de diagnostic ; packs DEV/Python/PowerShell alignés,
  `pytest.ini` inclus, archives RC18 exclues, sortie via un lien vers la source refusée. Tests locaux uniquement ; aucun nouveau résultat Windows/AD.
  Relecture Spark vérifiée : les manifestes et reçus JSON mal typés sont refusés proprement par l'outil de mise à jour,
  sans traceback ni suppression de reçus. Consolidation demandée sur `master`, deux packs DEV et PROD conservés.
  Détails et preuves : `docs/V1_BILAN.md`, section « Revue locale du 12/10/2026 ».

- Démarrage rétabli : erreur de syntaxe de `Get-SiteTag` (D4) et écriture de `$HOME` (F2) corrigées. La RC23 ne démarrait pas.
- Contrôle avant connexion : vrai parseur sur les scripts d'exécution et les trois scripts embarqués, compilation du writer d'audit ; refus de démarrer avec `fichier:ligne:message`. Rendu dans `--check-json`.
- Jonction : politique contrôlée avant le reçu ; un échec avant la commande Windows donne `Failed` et 96, plus de reçu `Running` bloquant.
- Collisions de noms entre techniciens, audit et correctifs (08/10 soir, question de David : « avec quelle méthode t'as testé la collision avec le partage, mais on avait aussi l'option random name et celle de créer l'objet ») : le banc v1 simulait l'AD et réservait avant l'affichage. Défauts corrigés : (1) le registre ne réservait rien pendant la vérification, la confirmation et l'exécution (clic dans la seconde suivant l'affichage, nom changé par Pesto) ; (2) « détenu par un autre poste » reçu pendant la vérification était ignoré : nom suivant revérifié avant la réservation AD et la confirmation (jonction et renommage) ; (3) à la fermeture, libération du registre annulée aussitôt et compte AD réservé laissé : libération attendue 3 s, compte retiré (8 s au plus) ; (4) graine du tirage au hasard tirée de l'horloge : graine GUID ; (5) message « premier numéro libre » faux avec le hasard ; (6) poste hors domaine : registre et verrou d'opération lus avec le jeton du compte local, donc toute mise au domaine refusée (« Coordination non préparée ») avec un registre sur un partage du domaine : connexion au partage avec le compte AD saisi dans Pesto. Banc v2 sur l'AD réel (4 techniciens, 108 tours, 9 réglages, 2 profils, vrai code de Pesto, sous LABO\tech.pesto) : 0 doublon, 0 orphelin ; refus après confirmation sur 24 ajouts : sans protection 36, hasard 7, registre avant correctif 31, registre corrigé 0, réservation AD 0, toutes combinaisons protégées 0 ; arbitre AD : un seul gagnant sur 4 au même instant. Relecture contradictoire du correctif (3 relecteurs, chaque point vérifié) : 7 points confirmés et corrigés : fermeture de Pesto refusée quelques secondes pendant la création ou le retrait d'un compte réservé dans l'AD (sinon compte « Réservé par Pesto » orphelin) ; nom seulement réservé au registre écarté tant que la réservation dure, plus pour toute la session, et Journal « réservé par un autre poste (registre partagé) » au lieu de « déjà utilisé dans l'AD » ; connexion au partage ouverte avec le compte AD fermée à la fermeture de Pesto (sinon active jusqu'à la déconnexion Windows) ; registre lu d'abord avec le jeton du processus, connexion seulement s'il est illisible. Bancs 5.1 : correctifs 27/27 puis complétés, jonction 25/25 (`preuves/vm-2026-10-08-collisions-v2/`).
- Tests GUI visibles (08/10 soir, demande de David : « renommage, déplacement, en mode manuel via le GUI, je veux le voir ») sur l'AD réel du labo, dans la session ouverte : deux Pesto côte à côte proposent 004 et 005 (aucune collision) ; renommage même site 003 → 004 ; redémarrage ; « Vérifier l'opération » puis consignation ; changement de site Paris → Lyon (P111301LY765002, déplacé dans OU=Lyon) ; redémarrage ; vérification consignée (`preuves/vm-2026-10-08-tests-visibles/`). Accents rétablis dans le motif affiché à la confirmation (« Site VA conservé : renommage seul, aucun déplacement », « déplacement automatique après renommage confirmé »).
- Plusieurs techniciens, plusieurs postes (08/10 soir, demandes de David) : (1) registre partagé des réservations de noms (POLICY.CoordinationRoot, worker en arrière-plan, création exclusive d'un fichier par nom, durée NameReservationMinutes, reprise d'une réservation expirée sous verrou exclusif) : le nom proposé est réservé une seconde après son affichage, les autres Pesto le sautent ; « Préparer ce dossier » et « Tester » dans Paramètres (aucun partage ni droit créé). (2) Réservation dans l'AD à la mise au domaine (ReserveNamesInAD) : compte créé après la vérification et avant la confirmation, repris par la jonction par GUID, retiré à l'annulation s'il n'a jamais servi. (3) Numéro tiré au hasard parmi les N premiers libres (RandomNameChoice). (4) Reprise après redémarrage (RunOnce) essayée puis retirée le même soir (décision de David : « supprime totalement cette option c pas faisable », la relance n'intervient qu'à l'ouverture de session suivante). (5) Paramètres : onglets « Noms et coordination » et « Politique » (toutes les options POLICY, levée de protection, exclusions) ; signature de configuration sur les valeurs appliquées (POLICY absente = défauts). (6) L'inventaire complet n'est plus lancé au choix d'un site ni à l'ouverture de la jonction : il faisait répondre « Patientez » à « Vérifier puis renommer ». Banc de collisions (4 techniciens, 8 tours) : sans protection 8/8 tours en collision, hasard 8/8 (13 essais au lieu de 46), registre 0/8. Bancs 5.1 : registre SMB 15/15, jonction 23/23, paramètres 16/16, Réservation AD vérifiée sur l'AD réel du labo (création, refus du doublon, retrait).
- « Vérification requise » expliqué et actionnable (08/10, signalé par David : « blocage sur vérification requise alors que tous les champs sont remplis en renommage ») : la cause exacte calculée par Pesto était remplacée par un texte général. Le texte sous le bouton dit maintenant la cause, et le bouton ouvre la vérification qui lève le blocage : « Vérifier la jonction » (PC ajouté au domaine puis redémarré, reçu à consigner), « Vérifier l'opération » (action unitaire), « Ouvrir les interventions » (ancienne exécution). La consignation reste explicite. « Enregistrer les paramètres » sans changement ne pose plus « redémarrage requis » (EntraPolicy absent = HybridOnly dans la signature). Banc 5.1 : 14/14 (9 échecs sur la version précédente).
- Services du site en quelques secondes (08/10, signalé par David : « ça met 30 s mini pour afficher un service alors qu'avant non. et le bouton vérification est grisé ») : la liste des services attendait la lecture complète de tous les postes (inventaire, depuis le 05/10). Dès le choix du site (« Ajouter au domaine » et « Un poste »), une recherche ciblée lit seulement les postes du site (début du nom dans le domaine, OU du site) en arrière-plan ; services et numéros pris arrivent en quelques secondes ; l'inventaire complet n'est plus attendu. « Vérifier » restait grisé faute de service : le texte sous le bouton de « Un poste » dit maintenant ce qui manque. Banc WPF 5.1 : 14/14 (`preuves/vm-2026-10-08-services-rapides/`).
- Contrôleur de domaine (08/10, décision de David sur le réseau réel à plusieurs contrôleurs : « remet comme avant ça marchait bien, le multi contrôleur fout la merde ») : la bascule de tous les postes vers l'émulateur PDC (07/10) est retirée. Chaque poste garde le contrôleur découvert par Windows, comme avant. Un PDC injoignable coûtait 27 à 65 s à chaque lecture AD (mesuré sous 5.1), répétées à chaque actualisation ; un PDC distant ralentissait inventaire, services et contrôles.
- Mise au domaine, nom pris (08/10, signalé par David : « il cherche plusieurs postes avant de trouver le bon […] il cherche 3 postes et abandonne, il faut le relancer ») : (1) un nom trouvé pris renvoie toute sa série (12 premiers caractères), lue dans tout le domaine en une requête ; le nom proposé ensuite est le premier numéro réellement libre, en un essai au lieu d'un par numéro (jonction et renommage direct). (2) L'inventaire chargé en arrière-plan pendant l'enchaînement recalculait la liste des noms : le contrôle en cours était jeté (« Contrôle périmé ») et l'enchaînement s'arrêtait. Sans saisie du technicien, le contrôle est désormais relancé sur le nom proposé (3 relances au plus) ; la confirmation reste obligatoire. (3) Les compteurs de relance repartent de zéro à chaque clic du technicien. (4) Les noms proposés tiennent compte aussi de l'inventaire des noms (OUScanNoms), pas seulement de l'OU racine. Banc WPF réel sous 5.1 : 25/25 (`preuves/vm-2026-10-08-noms-suite/`).
- Démo réelle du 08/10 sur l'AD du labo (vrai Pesto PROD, compte de recette, renommage et changement de site réels) : deux défauts trouvés et corrigés. (1) Un reçu de jonction ou une intervention de jonction écrits avec un autre préfixe de département (cfg.json changé depuis, autre département) étaient jugés invalides : toute opération sur le PC était refusée et la liste « Interventions à suivre » devenait illisible (« Lecture des reçus impossible »). Les données historiques (reçu, intervention, import d'un ancien état) se valident sur la structure du nom, pas sur le préfixe du jour. (2) Ce refus, prononcé avant toute commande, rendait 97 (« Résultat incertain ») et enregistrait l'opération comme incertaine, bloquant la suite : il rend 96 (non lancé), l'état persistant restant intact. Tests `tests/test_recus_bloquants.py` et cas « Reçu d'un autre préfixe accepté » (`Run-Pesto23Tests.ps1`, 65 contrôles sous 5.1). EXE `43af2ab3…`.
- Accueil sobre (07/10, demande de David : « pas de slogan ») : titre « Accueil », blocs « Interventions à vérifier » et « Accès rapide », carte « Règle de site » ; slogan et phrases d'accroche retirés, compteurs et boutons inchangés (`tests/test_accueil.py`). EXE `bbd7473a…` ; sous Windows PowerShell 5.1 : parseur 70 fichiers 0 erreur, `--check-json` 0, stabilisation 27/27, rendus WPF 43/45 (2 mesures de mise en page connues sans session).
- Interface (07/10) : icône lune du bouton de thème lisible sur fond clair et en contraste élevé (couleur du texte du thème au lieu d'un violet pâle fixe) ; entrée « Aide et raccourcis » retirée du menu (demande de David ; bouton « ? », panneau d'aide, F1 et infobulles conservés) ; l'aperçu n'affiche plus le nom actuel comme « Nouveau nom » tant qu'aucun site n'est choisi.
- Nom pris par un autre poste (07/10, S3) : en jonction et en renommage direct, un nom trouvé pris dans l'AD n'est plus seulement bloqué : il est écarté, le nom libre suivant est proposé et annoncé, revérifié, puis confirmé par le technicien (5 bascules au plus). Vérifié sur l'AD réel du labo et en WPF sous 5.1. Tous les postes utilisent l'émulateur PDC (un seul point de vérité pour les noms) ; PDC injoignable : contrôleur de secours signalé.
- Fenêtres de résultat (07/10) : bilan affiché dans une fenêtre rattachée à Pesto à la fin d'une jonction, d'une action directe et de la file ; recherche de site retirée ; démonstration de l'action directe sans OU lue. EXE reconstruit avec la chaîne documentée (`92676b22…`).
- Liste des services (05/10, signalé par David, critique) : en mode jonction, le service redevient une liste (éditable) des services connus du site ; hors domaine, l'inventaire des postes est lu en arrière-plan à l'ouverture de « Ajouter au domaine » et au choix d'un site, pour la liste et les noms proposés ; « Un poste » utilise la même liste. Noms disponibles : « Service » au lieu de « Équipe ». Défauts présents dans la RC23. Vérifié sous Windows PowerShell 5.1 sans bureau (WPF réel, stabilisation 27/27) ; vue en session non jouée (`preuves/vm-2026-10-05-services/`).
- Renommage vers le nom actuel refusé (96, plus 20). Effet Move conservé si la protection n'est pas rétablie (32). Résultat tardif sans effet sur l'intervention parente.
- Observation : `DomainRole` distant, fonctions du worker d'observation, canal sécurisé contrôlé contre le DC du plan, filtre LDAP des exclusions (RFC 4515).
- 47 affectations de variables automatiques renommées.
- Version 1.0 (FileVersion 1.0.0.0) depuis `tools/version.json`, appliquée par `tools/stamp_version.py`. `update_installation.py` accepte 17.0-RC18 à RC23 et 1.x. Chaînes du PE gardées telles que le build les produit (décision du 02/10) : ProductVersion « 1.0 », ProductName « Pesto - Gestion des Postes » ; lues sous Windows (recette 1.4).
- État historique avant les compléments du 04/10 ci-dessous : voir `docs/V1_BILAN.md`. Sous Windows PowerShell 5.1 sur la VM `PESTO-W11-TEST`, hors domaine : phases 0 et 1 de la recette sauf 1.8 (outillage Python : pas de Python sur la VM), phase 2 partielle (console pilotée par UI Automation ; échelles 125 à 200 % et RDP non joués ; 2.3 non rejoué en recette ; 2.4 bloqué : `cfg.json` modèle, P6). UAC, AD et Entra réels, jonction, renommage, déplacement, registre, ACL et partages, robustesse, mise à jour réelle, outillage Python sous Windows et signature : non exécutés.

Relecture du 2 octobre 2026 (cloud, branche `cloud/points-suite`, avant la recette). Vérifié dans le cloud (pwsh 7.4.6 Linux, Python, banc C). Sous 5.1, seulement au travers des phases 0 et 1 du pack `9ee3fe2` (stabilisation 20/20 en 1.5, cas ajoutés ce jour-là compris) et de la recette 2.5b (contraste élevé). Scénarios propres au lanceur, `--recover` et `Unblock-File` : non exécutés sous Windows.

- File de lots et formulaire, derniers points E (`da1c3f3`) : un poste déjà conclu dans le lot n'est plus écrasé par 98 ; `-ClearIdentity` efface aussi `TargetOUGuid`.
- Point 36 (`88073c2`, `17f3d7d`, `458c9e9`) : site du nom actuel, noms disponibles et code ville passent par le parseur et le générateur uniques (`ConvertTo-PestoNameParts -CurrentName` : P, S et V hérité, numéro 000 admis ; génération inchangée, P/S et 001-999). Aucune décision de renommage ou de déplacement modifiée.
- Point 79 (`458c9e9`, `2c98844`) : « Suivre Windows » suit le contraste élevé (palette des couleurs système, repli sur le thème habituel si une couleur manque) ; un choix explicite clair ou sombre reste respecté.
- Points 77 et 79 (`789cf37`) : noms accessibles tirés des libellés (21 contrôles, ☰ et « ? », vue de jonction) ; 8 contrôles au libellé dynamique sans nom figé.
- Point 01 (`95eb37b`) : échecs du Planificateur de tâches classés par `Get-PestoNativeFailureCode` (999 hors codes Windows ; après Run, indéterminé 1460 sauf 2, 5 et 1326).
- XAML (`2c98844`, `19486a2`) : `AutomationProperties.LiveSetting` retiré (.NET 4.7.1 et plus) ; infobulle technique de la liste déroulante retirée ; survol rétabli sur la file ; bouton « Enregistrer les paramètres » non tronqué.
- Lanceur (`5ec8a21`) : `--quiet`, `--check-json` et `--validate-plan` pris en compte quel que soit l'ordre des arguments ; lancement depuis la racine d'un lecteur refusé.
- `update_installation.py --recover` (`024d9ef`) : reprise après une préparation interrompue (verrou libéré si le code installé concorde avec son manifeste) et après `completed.json` (nouveau code gardé).
- Fabrication (`918b093`, `d7ebaa0`, `2c98844`, `cb0431b`) : `tools/cfg.template.json` et `tools/prepare_dev.py` pour un clone neuf ; fiche `tools/launcher/last-build.json` (point 87), EXE différent de la fiche refusé ; pack refusé avec un `cfg.json` configuré, sauf option explicite (`--allow-config`, `-AllowConfig`) ; rapports `*static-report*` exclus du DEV ; `New-PestoDistribution.ps1` réparé ; `DEBLOQUER_TOUT.cmd` limité aux éléments du pack.
- Porte PSScriptAnalyzer (`2c98844`) : plus de plantage sur `Pesto-Core.ps1` (stub `Confirm-YesNo` sans `param()`).

Défauts corrigés, reproduits ou vérifiés en tout ou partie sous Windows PowerShell 5.1 (VM `PESTO-W11-TEST`, 2-4 octobre 2026). L'origine de chaque constat est indiquée : L1, L2 et O12 viennent de la relecture du 02/10, le second volet de `$PSScriptRoot` d'un contrôle Python sur le Mac.

- Mode démo (trouvé sous 5.1, recette 2.1) : `DEMO.cmd` s'arrêtait en erreur fatale « Argument types do not match » (`@()` sur une liste générique créée par `New-Object`, dans `New-DemoComputers`), défaut présent depuis la RC23. Les 9 listes de `wad/` créées par `New-Object` passent à `::new()` (`2d5c182`). Vérifié sous 5.1 : fenêtre « Pesto 1.0 | Gestion des Postes », pas d'UAC, 0 connexion au DC (recette 2.1) ; nouveau cas de stabilisation, en échec sur l'ancien code, 21/21 après. Contrôle Python équivalent sur le Mac.
- Accessibilité UI Automation (trouvé sous 5.1, phase 2) : aucun élément exposé sous `MainTabs` (le modèle `PageHost` n'avait pas de `TabPanel`), formulaires et boutons invisibles pour le Narrateur ; 145 éléments exposés après correctif. Commandes de la palette annoncées `@{Id=...}`, liste des thèmes `@{Key=...}` : noms accessibles liés aux libellés (`5bb0ba7`, `ca7ba5b`). Vérifié sous 5.1 par UI Automation en session console pilotée (thèmes lus « Clair », « Sombre », « Suivre Windows »), sans relecture humaine. Ctrl+Tab et Ctrl+Page suivante ne changent toujours pas de page.
- `$PSScriptRoot` vide sous 5.1 dans une valeur par défaut de paramètre. Premier volet trouvé sous 5.1 : `APERCU_LOGIN.cmd` échouait (recette 2.3) ; chemins calculés dans le corps de 4 scripts de test (`ca7ba5b`). Second volet trouvé sur le Mac par `test_ps51_compat.py`, corrigé pour voir les `param(...)` tenant sur une ligne : 9 scripts de `tests/` et `wad/maintenance/` (`d4b6be1`). Vérifié : parseur 5.1, 68 fichiers, 0 erreur (syntaxe seule) ; sur ces 13 scripts, seule l'exécution de `Run-LoginTests.ps1` est consignée sous 5.1 (voir P5), les 12 autres n'ont que le parseur ; `APERCU_LOGIN.cmd` s'ouvre sous 5.1.
- L2 (lanceur ; constat de la relecture du 02/10) : la racine du pack était ouverte sans droit d'accès ; Windows ignorait alors le mode de partage et le dossier pouvait être renommé. Ouverture en `FILE_LIST_DIRECTORY`, partage lecture et écriture sans suppression (`ce3d013`). Mécanisme vérifié sous 5.1 par micro-test (handles .NET aux mêmes paramètres : renommé avant, refusé après), pas l'EXE corrigé : en exécution réelle, les composants ouverts bloquaient déjà le renommage et la mesure ne distingue pas les deux mécanismes ; le correctif ferme la fenêtre avant leur ouverture. Double C mis à jour, en échec si l'on revient à l'accès 0 (Mac).
- O12 (constat de la relecture du 02/10, reproduit sous 5.1) : `Pesto_COMPTE_AD.cmd` transfère à `Pesto.cmd` sans `call` ; depuis un dossier `a^b` ou `c%PATH%d`, le lancement échouait (code 1) (`ce3d013`). Vérifié sous 5.1 avant et après : chemin exact et code transmis. Test Python (Mac) : aucun `.cmd` racine ne fait `call "%~dp0`.
- P1, P2, P3 (fiches ; vus sous 5.1 en console, phase 2) : focus sur « Fermer » à l'ouverture de la fiche État ; tableaux des fiches État et Performance en police à chasse fixe ; en démonstration, « Démonstration : aucune OU lue » au lieu de « (mode GUI) », valeur interne et contrats inchangés (`23360f8`). Vérifié sous 5.1 par UI Automation et captures ; `--check-json` PASS, stabilisation 21/21.
- P5 (trouvé sous 5.1, recette 2.3) : `tests/Run-LoginTests.ps1` réécrit sur les sources actuelles (palettes lues par le parseur dans `$script:Themes` de `Pesto-Core.ps1`, sans exécuter le moteur ; gabarits de `Pesto-Shell.xaml` et `Pesto-Authentication.ps1`), mêmes paramètres, 19 contrôles et code de sortie (`d4b6be1`). Vérifié sous 5.1 : 19/19 en Light et Dark, contrôle négatif compris ; `APERCU_LOGIN.cmd` affiche la fenêtre compacte « TEST LOCAL SANS AD », saisie fictive, pas d'UAC, 0 connexion au DC.

Constats de la relecture du 02/10 traités le 04/10 sur délégation de David (« fais au mieux »), vus sous 5.1 le même jour sur l'EXE `8fd5bd8c…` (`abd6c2e`, `preuves/vm-2026-10-04/`) :

- L4 (lanceur) : codes de sortie propres au lanceur, un par cause, de 120 à 132 (133 à 139 réservés) ; codes du script PowerShell transmis tels quels ; table dans `docs/V1_GUIDE.md`. Changement de contrat pour les scripts appelants : instance déjà ouverte 128 (avant : 0), verrou de mise à jour 126 (avant : 32), paramètre inconnu 120, empreintes refusées 125 (avant : 1). Vus sous 5.1 : 0, 120, 123, 124, 125, 126, 128. Défaut trouvé à cette occasion sous 5.1 et corrigé : lancé depuis la racine d'un lecteur, le lanceur affichait une boîte de message malgré `--quiet` et rendait 1 ; les arguments sont désormais lus avant les contrôles d'emplacement (scénario C 47).
- X5 (interface) : en contraste élevé seulement, bordure aux couleurs système sur l'élément survolé, l'onglet et le bouton de menu actifs (transparente en clair et sombre). Vue sous 5.1 sur le bouton de menu actif et le focus clavier ; onglet actif non capturé.
- O7 (outillage) : `VERIFIER_UAC.cmd` teste la vraie UAC avec le vrai `Pesto.exe` et des composants intacts (sonde `PESTO_UAC_PROBE` ; le relais élevé s'arrête avant la reprise d'état et le moteur et écrit un reçu `wad\logs\Pesto-sonde-uac-<jeton>.txt`). Premier passage limité à l’invite ; acceptation et refus réels validés le 04/10 au soir après le correctif décrit ci-dessous.
- L1 et L6 : code du lanceur inchangé, risques acceptés sous conditions de déploiement, écrites dans `docs/V1_GUIDE.md` (« Emplacement et droits ») : pack sous `%ProgramFiles%`, hors dossier synchronisé, droits contrôlés avant mise en service. Conditions vérifiées sur la VM avec un pack PROD de test sous `C:\Program Files` (écriture non élevée refusée, `--check --quiet` et `--check-json` à 0 sans élévation).

Trouvé sur le Mac, vérifié sous 5.1 pour 1 contrôle sur 8 :

- P7 (trouvé par `ux_static_checks.py`, 48/49) : `AutomationProperties.HelpText` et délais d'infobulle ajoutés aux 8 contrôles qui n'avaient pas de `HelpText` (Favoris de préparation, onglet Apparence et `TabJoin` dans `Pesto-Shell.xaml` ; `KeepService`, `KeepNumber`, Annuler et `ConfirmRun` dans `Pesto-Core.ps1` ; `LoginTheme` dans `Pesto-Authentication.ps1`), `ToolTipService.ShowOnDisabled` aux 7 qui ne l'avaient pas (`LoginTheme` l'avait déjà). Texte repris de l'infobulle existante ; l'onglet Apparence, sans infobulle, en reçoit une. Les infobulles changent (affichage sur contrôle désactivé, délais) ; aucun comportement métier modifié (`07fbab0`). Vérifié : `ux_static_checks.py` 49/49 (Mac) ; sous 5.1, seul le `HelpText` de `TabJoin` a été lu par UI Automation.

Résultats sous 5.1 du 04/10 postérieurs à `4b08eb94…` (P5 et `APERCU_LOGIN.cmd`, préférences 15/15, UX 43/43, `--check-json` et stabilisation sur `de44fc4a…`, `HelpText` de `TabJoin`) : consignés dans les messages de `d4b6be1`, `daeed5e` et `07fbab0` seulement, sans fichier dans `preuves/`.

L1 (constat de la relecture du 02/10) : non reproduit sous 5.1 (fichier compressé WOF et dossier compressé NTFS acceptés ; lien symbolique et jonction refusés), code du lanceur inchangé ; risque accepté le 04/10 (ci-dessus).

Outillage de recette (trouvé sous 5.1 sur la VM le 04/10) : `outils/parse_all.ps1` et la passe parseur de `tools/checks/validate_pesto.py` analysaient aussi les deux `.ps1xml` de `wad/` comme des scripts (sous Windows, `-Filter *.ps1` reconnaît `.ps1xml`) : 68 fichiers au lieu de 66. Filtre sur l'extension exacte ; test `test_ps51_compat.py` (en échec sur l'ancien code) ; 66 fichiers, 0 erreur sous 5.1 (`preuves/vm-2026-10-04-phase1/ps1xml.txt`).

Outillage Python (vérifié sur le Mac seulement : pas de Python sur la VM) :

- O4 : `wad/package.json` porte `FileVersion` ; `update_installation.py` refuse une version source plus ancienne (RC antérieure à 1.x, puis `FileVersion`, sinon `Version`), sauf `--allow-downgrade`, en aperçu comme en application (`23360f8`). 5 tests de version dans `tests/test_update.py`, dont 3 en échec sur l'ancien code (refus de retour en arrière, `--allow-downgrade`) ; les 2 autres gardent le cas normal.
- O9 : détection des liens et jonctions sans exiger Python 3.12 (`Path.is_junction` si présent, sinon attribut `FILE_ATTRIBUTE_REPARSE_POINT` de `lstat` sous Windows) dans `refresh_manifest.py` et `update_installation.py` (racines, composants, journaux, sauvegarde) ; la cible résolue de chaque composant doit rester sous la racine (`11bc7d7`).
- O10 : `validate_relative` refuse les segments finissant par un point ou une espace, les noms réservés (CON, PRN, AUX, NUL, COM1-9, LPT1-9) et les flux alternatifs ; `runtime_files` refuse un `.json` ou un `.log` dans la liste requise (`11bc7d7`). O9 et O10 : `tests/test_path_security.py` (repli Windows simulé, liens hors racine).
- O8 : après un aperçu ou une mise à jour réussis, `update_installation.py` liste en lecture seule les files de lots de l'utilisateur courant (`%LOCALAPPDATA%\GP\State\<id>\queue.json`) et signale celles qui ne sont pas conclues ou sont incertaines (avertissement sur stderr, champ `UserQueues` en JSON) ; rien n'est bloqué, plan inchangé (`0a54ff2`). `tests/test_update_queues.py` (25 cas).

EXE et manifeste reconstruits sur le Mac (clang/lld 23.1.2) après chaque modification d'un composant d'exécution, puis copiés sur la VM au fil de la recette : `8c723efb…` (02/10), `e31dbb9f…`, `3676b63e…`, `6702949d…`, `73eb6795…`, `4b08eb94…`, `de44fc4a…` (04/10 ; son `--check-json` PASS sous 5.1 n'est consigné que dans le message de `07fbab0`), puis `8fd5bd8c…` (`abd6c2e`, 04/10, avant la correction UAC finale ; reconstruit vers 17 h sur un clone neuf aux mêmes octets ; vu sous 5.1 pour L4, X5 et O7, `preuves/vm-2026-10-04/`, puis recette 1.1 à 1.7, `preuves/vm-2026-10-04-phase1/` ; `last-build.json` porte toujours `WindowsExecution: NOT_RUN`, champ non mis à jour à la main). Un EXE intermédiaire `07c6ea1c…`, jamais commité, a servi à la capture de P2. Les scripts de `wad/maintenance/` modifiés par `d4b6be1` n'en font pas partie : pas de reconstruction. Non signé.

Suites de test remises en état :

- `Run-StabilisationTests.ps1` : le cas `DEBLOQUER_TOUT` énumérait le dossier réel et signalait `check.json` écrit par la recette 1.2 ; il porte désormais sur des noms fixes, la couverture complète étant vérifiée contre `distribution_files` en Python (`25ae335`). Nouveau cas du jeu de démo (`2d5c182`). Sous 5.1 : 20/20 le 02/10, puis 21/21, puis 24/24 le 04/10 sur l'EXE `8fd5bd8c…` (3 cas O7 ajoutés, `preuves/vm-2026-10-04-phase1/`).
- `Run-LoginTests.ps1` : voir P5 (19/19 sous 5.1).
- `Run-LoginPreferencesTests.ps1` : fonctions cherchées dans tous les `wad\*.ps1` (unicité exigée), version lue dans le moteur, échecs de préparation inscrits au rapport ; mêmes 15 cas (`daeed5e`). 15/15 sous 5.1.
- `Run-UxTests.ps1` : fenêtre lue dans `Pesto-Shell.xaml`, fonctions dans le cœur et ses composants, palettes `$script:Themes` (47 couleurs par thème), contrôles adaptés à l'interface 1.0 (`daeed5e`). 43/43 sous 5.1 en session console ; en SSH, 2 mesures de mise en page hors écran renvoient 0.
- Contrôles statiques Python sur les sources actuelles (`daeed5e`, `07fbab0`) : `ux_static_checks.py` 49/49, `login_compact_static_checks.py` 33/33 et 9/9 (deux contrôles sans objet retirés, le premier avec son contrôle négatif « Business engine unexpectedly changed », et un remplacé ; motivés dans le script (`REMOVED`) et dans le rapport quand il est régénéré : à `c86381d`, le rapport versionné est encore l'ancien format RC13, constat T1), `ux_checker_selftest.py` (mutants détectés). Mac seulement. Restes ouverts à `c86381d` : constat T1.
- `TEST_LOGIN_COMPACT.cmd` : bandeau 1.0 ; rapports UX ignorés par Git (`07fbab0`).


### 4 octobre 2026 — refus UAC corrigé et campagne finale

- Sous Windows PowerShell 5.1, cliquer Non dans la vraie UAC renvoyait 1 et deux diagnostics : `Start-Process` perdait le code Win32 1223. `Process.Start`, avec `UseShellExecute` et `RunAs`, conserve l’exception native ; refus 1223 et acceptation 0 avec reçu UAC_OK validés en console. Aucun changement de politique UAC.
- Banc Startup adapté au vrai point d’entrée, 30/30 sous 5.1, dont erreur native « fichier absent » distincte de l’annulation ; tests Python ciblés : 16/16. Validation complète avec parseur 5.1 : 407/407. Relecture Spark obtenue puis vérifiée par les tests et les preuves Windows.
- EXE reconstruit (clang/lld 23.1.2) : `aed2be1900b45d380ac95f360daaf770b613c047e4d1a80f5bea07e24722d782`. Manifeste régénéré après le build.
- Contraste élevé : onglet actif désormais capturé ; Ctrl+1 à Ctrl+4 vus en console. P8 clos en documentant que Ctrl+Tab/Ctrl+Page suivante ne changent pas de page.
- Recette 5.5/5.6 sur copies extraites de l’archive RC23 : conservation de données sentinelles, verrou après interruption, refus 126 et aperçu de récupération sans modification. Ce ne sont pas des opérations AD. Preuves et limites : `preuves/vm-2026-10-04-final/LIRE.md`.

## Historique

# Pesto 17.0-RC23

- Reçus de jonction stricts, photographie initiale et transitions natives persistées ; nouveau schéma central 3.
- Vérification Windows/AD/canal sécurisé après reboot avec confirmation, ancien statut local non résolutif.
- Import prévisualisé des anciens reçus de jonction locale, sans suppression ni succès supposé.
- Bouton principal adaptatif du parcours unitaire, fiche d’observation intégrée avec focus/Échap.
- Mesures locales bornées de tous les workers ; attentes, travail et issues séparés.
- Tests RC23, gate, packs et EXE recompilé. Les essais Windows restent à réaliser.

## Historique

# 17.0-RC22

- Conservation structurée des observations avant/prévu/après et correction d’effets partiels.
- Vérification du GUID lors de la reprise d’un brouillon.
- Analyses asynchrones de capacité du périmètre et de conformité nom/site/OU.
- Recherche locale dans Actions/Ctrl+K ; préférences contrôlées des trois principales grilles.
- Mise à jour avec journal et reprise explicite après interruption ; lanceur bloqué par la présence du verrou.
- Échappement des guillemets typographiques PowerShell et nouveau lint.
- 96 tests Python et 331 contrôles portables exécutés. 33 tests Windows fournis mais non exécutés.
- EXE recompilé ; points du plan restant partiels documentés dans RC22_90_POINTS.md.

## Historique

# RC21

Index réutilisé, pagination, candidats, favoris nommés, brouillons, panneaux intégrés, consultation, coordination optionnelle, journal asynchrone et reprises contrôlées. Détail et limites : docs/RC21_90_POINTS.md.

## Historique antérieur

# Pesto 17.0-RC20

- Indicateur de chargement visible dans Noms disponibles, étape courante, compteur réel et durée.
- Calcul de la vue dans un runspace séparé, après inventaire complet.
- Résultats périmés rejetés, copie/export neutralisés pendant le calcul, états vide/erreur/chargement séparés.
- Borne de 50 000 lignes affichées avec avertissement et export limité à la vue.
- Nouveau lanceur compilé avec les empreintes actualisées ; mêmes distributions PROD/DEV.
- Tests et recette dans docs/RC20_NOMS.md. Aucun essai Windows exécuté ici.

## Versions antérieures (historique, pas preuve de validation RC20)

# Pesto 17.0-RC19

- Préparation Entra conditionnelle et reçus indépendants des effets.
- Registre local d’interventions partagé, observation et relecture ciblée des tâches.
- Identité distante préalablement vérifiée, protection initiale persistée.
- Redémarrage demandé sans fermeture forcée implicite.
- Import AD absolu ; empreintes de tous les composants immuables vérifiées par l’EXE avant PowerShell.
- Favori de préparation, journal WPF incrémental, configuration neuve neutre et rechargement métier cohérent.
- Déblocage déplacé dans wad/support, nouveaux packs, outil de mise à jour avec aperçu et sauvegarde.
- Scénarios portables exécutés ; tests Windows fournis mais non exécutés. Suivi explicite des 44 points dans docs/RC19_SUIVI_AUDIT.md.

## Historique antérieur (ne vaut pas validation RC19)

# Pesto 17.0-RC18

- Nouveau nom Pesto dans le lanceur natif, les ressources de version, les fenêtres, les messages, les exports et les nouveaux journaux.
- Composants `Pesto-*.ps1`, `Pesto-*.xaml`, fonctions `*-Pesto*` et espaces de noms Pesto.
- Badge compact P, nom Pesto lisible dans le menu et les fenêtres. Icône neutre d'origine conservée, renommée Pesto.ico.
- Sources de compilation, tests courants, script de déblocage et générateurs PROD/DEV adaptés.
- Régénération du manifeste sur les seuls composants nécessaires.
- Stockage et verrous hérités maintenus intentionnellement pour préserver les opérations non résolues, les préférences et la coordination avec GP.
- Archives de documentation antérieures conservées à l'identique dans docs/historique-gp.

Aucun changement des commandes AD, des droits, de la préparation Entra ou des règles de redémarrage.

### 4 octobre 2026 — reprise de la recette et pilote de labo

- Recette Windows 1.8 (407 contrôles, parseur 5.1), 2.3 (aperçu de connexion) et 2.11 (message/code 120) jouées avec succès, preuves dans `preuves/vm-2026-10-04-reprise/`.
- Tests Python sur Windows : 228 réussis et 1 ignoré au total après trois rejeux ciblés corrigeant la préparation du banc ; aucune nouvelle passe complète entièrement verte annoncée.
- Pilote `outils/labo/vm/lancer.ps1` : absence de démarrage, résultat enfant non nul et délai donnent un échec ; tâche encore active conservée, compte console paramétrable. Six cas réels sous 5.1, puis régression ciblée de résultat tardif avec doubles et rejeu réel sans session sur le code final. EXE et moteur inchangés.
