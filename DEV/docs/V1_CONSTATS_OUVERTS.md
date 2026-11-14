# Pesto 1.0 : constats de relecture encore ouverts

## Revue locale du 12/10/2026

Corrections : faux diagnostic de compte local avec des identifiants AD explicites, conservation de l'erreur
originale, contrôle du chargement et des dépendances des workers, code de sortie du script SSH, cohérence du pack DEV.
La revue et les tests de cette passe se limitent au Mac ; aucune VM ni aucun AD contacté.
Voir [le bilan](V1_BILAN.md#revue-locale-du-12102026) pour les preuves et les limites du nouveau build.
Les qualifications Windows antérieures ci-dessous restent liées à leurs candidats datés.

État actuel au 04/10, fin de campagne : P6 est clos par la vraie consultation AD. Les défauts F7, code32, reprise UAC entre comptes et navigation à grande échelle sont corrigés et testés. Restent les conditions de déploiement L1/L6 déjà documentées, la signature par un éditeur approuvé, Entra hybride, RDP et l’endurance sur un parc représentatif. Le problème historique NEM n’a pas été « corrigé » en modifiant l’hôte partagé. Les anciennes sections ci-dessous sont datées ; leurs mentions « aucun AD réel » sont remplacées par la campagne finale et sa matrice.

Relectures adversariales faites dans le cloud le 2 octobre 2026 (branche `cloud/points-suite`) sur les zones jamais
relues : lanceur C, outillage Python/PowerShell, `.cmd`, `Pesto-Shell.xaml` et `Pesto-Join.xaml`. Les constats corrigés
sont dans l'historique Git de la branche. Confiance indiquée pour chacun.

Le 4 octobre 2026, David a délégué les décisions sur les constats de code L1, L4, L6, X5 et O7 (« fais au mieux »).
L1 et L6, non traités par du code, sont acceptés pour la 1.0 sous conditions de déploiement, désormais dans
`V1_GUIDE.md` (« Emplacement et droits ») et vérifiées le 04/10 sur la VM de test. L4 et X5 sont traités et vus sous
Windows le 04/10 ; O7 est validé après correction d’un refus UAC réel (code 1 au lieu de 1223). Accepter et Refuser
ont été pilotés sur la console VirtualBox avec l’autorisation de David. X5 couvre aussi l’onglet actif. P8 est clos
par documentation des raccourcis pris en charge ; P6 et LAB restent ouverts. Recette 1.1 à
1.7 rejouée le 04/10 sur l’EXE alors courant `8fd5bd8c…` : verte (`preuves/vm-2026-10-04-phase1/`).

## Décisions prises le 04/10 (risques acceptés sous conditions)

Code du lanceur inchangé pour L1 et L6 : la vérification des 37 empreintes reste entière, sans exception ni
contournement. Les conditions de déploiement font partie de la décision : si l'une ne peut pas être tenue, le constat
est rouvert. Le lanceur ne les contrôle pas ; elles reposent sur le guide et le contrôle avant mise en service.

Conditions, dans `V1_GUIDE.md` (chapitre Installation, « Emplacement et droits ») :

1. Pack sous `%ProgramFiles%` : `BUILTIN\Users` en lecture et exécution seules, écriture réservée à Administrators,
   SYSTEM et TrustedInstaller, propriétaire Administrators, SYSTEM ou TrustedInstaller, jamais un compte utilisateur
   (L6). Une installation existante ailleurs (exemple historique `C:\Outils\Pesto`) doit être durcie aux mêmes valeurs.
2. Pas de pack dans un dossier synchronisé à la demande (OneDrive, Bureau ou Documents redirigés) ni sur un volume
   dédupliqué (L1, L6).
3. Contrôle avant mise en service (`icacls` sur la racine et `wad`, propriétaire par `Get-Acl`), valeurs attendues
   écrites dans le guide.

Vérifié le 04/10 sur `PESTO-W11-TEST` (pack PROD de test sous `C:\Program Files\Pesto-PROD-test`, compte `labadmin`
non élevé, `preuves/vm-2026-10-04/`) : droits hérités `BUILTIN\Users:(I)(RX)`, propriétaire `BUILTIN\Administrators` ;
écriture dans `wad` refusée ; `--check --quiet` et `--check-json` rendent 0 sans élévation (Runtime PASS, 38
composants). Les commandes du guide ont été relues sur ce résultat, pas rejouées telles quelles sur un autre poste.

| Id | Constat | Décision et conditions de déploiement | À réexaminer si | Confiance |
|---|---|---|---|---|
| L1 | Le lanceur refuse tout fichier ou dossier portant un point d'analyse. Faux refus non reproduit sous Windows PowerShell 5.1 le 03/10 (`preuves/vm-2026-10-03/`) : un fichier compressé par `compact /exe` (WOF, point d'analyse masqué par Windows) et un dossier compressé NTFS sont **acceptés** ; lien symbolique et jonction refusés. Non testables sur la VM : Bureau redirigé OneDrive (balises cloud) et volume dédupliqué. | Risque accepté : refus strict conservé. Au pire, un faux refus empêche le démarrage, sans exécuter de fichier non vérifié. Piste « name surrogate » : ne refuser que les balises de nom de substitution (`0x20000000` : liens symboliques, jonctions, points de montage), lues par `GetFileInformationByHandleEx(FileAttributeTagInfo)` sur le handle déjà ouvert ; brouillon écrit le 04/10 hors du dépôt, non conservé, à réécrire et tester si besoin. Condition 2 du guide (emplacement) : si elle n'est pas tenue, le lanceur peut refuser de démarrer ; il n'exécute rien de non vérifié. | Un refus est vu sur un poste réel, ou le pack doit vivre dans un dossier synchronisé : reproduire, puis réécrire, tester et appliquer la piste. | faible (non reproduit) |
| L6 | Seuls les 37 fichiers listés sont vérifiés ; des fichiers ajoutés dans `wad` (DLL, `.resources.dll`, jonction sur `wad\logs`) ne sont pas refusés et peuvent être chargés par le moteur élevé. PowerShell rouvre par chemin. Exploitable si le dossier est inscriptible par un tiers, c'est-à-dire par tout processus non élevé : celui d'un utilisateur standard (UAC vers un compte administrateur) comme celui de l'administrateur lui-même en jeton filtré (UAC vers le même compte, contournement de l'UAC). Un dossier du profil, même d'un administrateur, ne convient donc pas. | Risque accepté sous les conditions 1 à 3 du guide, vérifiées le 04/10 sur la VM (écriture non élevée refusée, contrôles à 0 sans élévation). Conséquences des ACL : voir sous le tableau. | Le pack doit vivre dans un dossier inscriptible par les utilisateurs (profil, partage, dossier synchronisé), ou le contexte change : appliquer la piste (énumérer `wad`, refuser les exécutables inconnus et une jonction sur `logs`, passer le chemin final `GetFinalPathNameByHandleW`). | moyenne (conditions vérifiées sur une VM) |

Conséquences des ACL de L6, d'après le code ; le 04/10, seuls le refus d'écriture non élevée et les contrôles à 0 ont
été vus sous Windows :

- La partie non élevée n'écrit plus dans `wad\logs` : ni `Pesto-lanceur.log` (journal facultatif du lanceur, ouverture
  sans échec bloquant), ni ses lignes de `Pesto-demarrage.log` (`Write-PestoStartupLog` dans `Pesto-Startup.ps1` ne fait
  qu'avertir). La boîte d'erreur du lanceur renvoie pourtant vers ces deux fichiers : en cas d'échec avant l'élévation,
  ils peuvent manquer. Un pack neuf n'a pas de dossier `wad\logs` (constaté le 04/10).
- La partie élevée (jeton administrateur) garde l'écriture : lignes élevées du journal de démarrage, audit du moteur
  (`wad\logs`, repli sur `%LOCALAPPDATA%\Pesto\logs` puis `%TEMP%`).
- Une mise à jour du pack (`update_installation.py`, verrou `.pesto-update.lock` à la racine) demande une console
  administrateur.
- Les états restent hors du pack (`%LOCALAPPDATA%`, `%ProgramData%`) : pas de casse fonctionnelle attendue.

## Traités le 04/10, vus sous Windows le 04/10

Traités par les lots du 04/10 (commit `abd6c2e`), vus le jour même sur `PESTO-W11-TEST` avec le `Pesto.exe` reconstruit
sur ce commit (vrai lanceur, Windows PowerShell 5.1, compte `labadmin` non élevé ; `preuves/vm-2026-10-04/`).

| Id | Constat d'origine | Vérifié sous Windows PowerShell 5.1 | Résultat Windows (04/10) |
|---|---|---|---|
| L4 | Codes de sortie du lanceur ambigus : instance déjà ouverte = 0 ; verrou de mise à jour = 32 (même valeur que « protection non rétablie ») ; erreurs Win32 brutes (5, 2…) mélangées aux codes du script. Change le contrat vu par les scripts appelants. | Depuis un script appelant, sur des copies jetables : chaque cause rend son code documenté. | **Conforme** : `--check-json` 0 ; argument inconnu 120 ; racine d'un lecteur 123 ; composant absent 124 ; empreinte refusée 125 ; verrou de mise à jour 126 ; seconde instance 128 (boîte « Déjà ouvert »). Défaut trouvé et corrigé dans `abd6c2e` : sous `--quiet`, le refus « racine d'un lecteur » affichait une boîte et rendait 1 ; après correctif, 123 sans boîte (scénario C 47). Non provoqués : 121, 122, 127, 129-132, « protection non rétablie ». |
| X5 | Contraste élevé : l'élément survolé au clavier (`AccentSoft`), l'onglet et le bouton de menu actifs ne se distinguent que par la couleur du texte. | Thème Contraste élevé de Windows : états repérables sans se fier à la couleur du texte (captures). | **Conforme pour ce qui a été vu** (thème Contraste élevé, mode « Suivre Windows ») : bordure à la couleur système Highlight sur le bouton de menu actif (Accueil) et sur le bouton sous le focus clavier (Plusieurs postes, en partie masqué par son info-bulle) (`x5-contraste-*.png`). Onglet Apparence et menu Paramètres actifs également capturés le 04/10 à 18:55 (`preuves/vm-2026-10-04-final/x5-onglet-actif.png`). Contraste élevé remis ensuite à son état d'origine (flags 126). |
| O7 | La sonde modifiait autrefois Core et échouait sur les empreintes. | Vrai lanceur et vraie UAC, composants intacts. | **Conforme après correction complémentaire** : refus réel 1223, acceptation réelle 0 et reçu UAC_OK (`preuves/vm-2026-10-04-final/`). Le premier vrai refus sur `8fd5bd8c…` produisait 1 : `Start-Process` perdait le code natif. `Process.Start` préserve Win32Exception 1223, 30 tests Startup sous 5.1. Contre-épreuve d’empreinte : L4 (125). |

## Vus en console le 03/10 (phase 2), mineurs

| Id | Constat | Piste | Confiance |
|---|---|---|---|
| P6 | `--consult` sur un poste hors domaine avec `cfg.json` modèle : ouvre « Corriger la configuration » (2.4 bloqué). | Rejouer 2.4 avec une configuration validée du labo. | élevée |
| P8 | Ctrl+Tab et Ctrl+Page suivante ne changent pas de page. | **Clos pour la 1.0 par limite documentée** : menu latéral et Ctrl+1 à Ctrl+4 conservés, sans ajouter un deuxième ordre de navigation. Les quatre raccourcis sont joués en console le 04/10 (`clavier-natif-*`). | élevée pour Ctrl+1 à Ctrl+4 ; pas de nouveau raccourci Ctrl+Tab |
| LAB | Labo : VirtualBox en mode NEM (Hyper-V actif sur l'hôte) ; VM figée trois fois ~30 min après l'ouverture de session (vCPU à 100 %, aucune E/S) ; le 04/10 vers 17 h, figée aussi juste après un démarrage, sans session ouverte (3 vCPU à 100 %, SSH muet 11 min, écran noir), rétablie par une réinitialisation (SSH en 25 s) ; premier rendu WPF > 1 min. | Désactiver Hyper-V sur l'hôte (décision de David) ou autre hyperviseur. | élevée sur le constat |

## Constats d'exécution sans conséquence identifiée

- 66 `.ps1` dans le cloud contre 68 sur l'hôte et la VM : expliqué et corrigé le 04/10. Sous Windows, `-Filter *.ps1`
  reconnaît aussi les deux `.ps1xml` de `wad/` (analysés comme des scripts, sans erreur) ; `parse_all.ps1` et la passe
  parseur de `validate_pesto.py` filtrent l'extension exacte (test `test_ps51_compat.py`) ; 66 fichiers sous 5.1
  (`preuves/vm-2026-10-04-phase1/ps1xml.txt`).
- Scripts `tests/*_static_checks.py` et 15 suites `.ps1` historiques obsolètes (fonctions ou fichiers disparus) ; hors
  `TESTER.cmd`, échecs identiques sur `c2e62e2`.
- Sous PowerShell 7 : 4 échecs RC21/RC23 identiques sur `c2e62e2` (vert sous 5.1) — écarts de moteur, pas des régressions.

## Rappel

Le 02/10/2026 au soir, la phase 1 de la recette (SSH, sans interface, sans UAC, sans AD) a tourné sous Windows PowerShell 5.1
sur `PESTO-W11-TEST` avec la branche `cloud/points-suite` (`preuves/vm-2026-10-02/`). Depuis : phase 2 jouée en partie en WPF en session console (03-04/10), UAC acceptée et refusée réellement le 04/10 au soir (voir campagne finale ci-dessous) ; aucun AD réel.

## Reprise du 04/10 en soirée

Recette **1.8, 2.3 et 2.11 PASS** (`preuves/vm-2026-10-04-reprise/`) : 407 contrôles avec le parseur 5.1 ; aperçu local de connexion et erreur visible 120 rejoués en console standard. Tests Python Windows : 228 réussis et 1 ignoré en cumulant la passe complète et trois rejeux ciblés après correction du banc (dossier outils absent et Python embarqué isolé). Aucune correction produit induite par ces trois résultats.

**LAB-PILOTE corrigé** : sans session console, `lancer.ps1` rendait 0 alors que la tâche n'avait pas tourné (267011). Désormais échec explicite ; résultats enfant non nuls et délais signalés, tâche active conservée pour observation. Six scénarios réels passent sous 5.1. Les états Queued prolongé et erreurs RPC restent non provoqués. P6, LAB et les validations AD restent ouverts. O7 et P8 sont traités dans la campagne finale.


## Campagne AD et robustesse du 04/10 au soir

P6 est clos avec une configuration de labo valide : `--consult` démarre sans UAC depuis un jeton non élevé, autorise la lecture ciblée et l’inventaire demandé, bloque mutation et consignation dans le moteur. Preuves : `preuves/vm-2026-10-04-prod/consultation-*` et `lecture-seule-et-nom-identique.json`.

La campagne LAB a désormais exécuté la jonction, le renommage local, le déplacement, la reprise après codes 97 et 89, la réparation d’une protection après code 32, la coupure réseau et le disque plein. Deux défauts supplémentaires ont été corrigés : exclusions de groupes avec antislash dans le DN ignorées par l’ancien filtre ADWS ; message de déplacement seul trompeur après code 32. Le détail des essais et des limites reste dans `V1_RECETTE_WINDOWS.md` et le `LIRE.md` des preuves. La signature d’éditeur, les essais Entra hybrides et les cases non jouées ne sont pas déclarés validés.

## Signalés par David le 05/10, corrigés

Présents dans la RC23 reçue (`1375908`) ; non introduits par la branche. Correction du 05/10, EXE `98eba546…`.

| Id | Constat | Correction | Vérifié | Reste |
|---|---|---|---|---|
| S1 | **Critique.** Mode jonction (poste hors domaine) : plus de liste des services. Le service n'était qu'une zone de texte, et le login léger ne charge pas les postes : aucune liste, ni dans « Ajouter au domaine » ni dans « Un poste » (domaine), tant que Noms n'avait pas été ouvert ; les noms proposés ignoraient aussi les postes de l'AD (la relecture AD avant jonction bloquait ensuite un nom pris). | `JnService` devient une liste éditable (3 caractères, majuscules, saisie libre conservée) remplie des services connus du site : noms conformes sous l'OU du site ou portant son code site (`Get-PestoSiteServiceCodes`, cache local, aucun appel AD). Hors domaine, l'ouverture de la page et le choix d'un site lancent la lecture de l'inventaire en arrière-plan (`Refresh-Names`, comme Noms) ; les listes et les noms proposés sont complétés à la fin du chargement, sans effacer la saisie (`Update-PestoServiceChoices`). « Un poste » utilise la même liste. | Mac : `test_services_list.py` (7 tests, en échec sur l'ancien code). Windows PowerShell 5.1 sur la VM : stabilisation 27/27 dont le nouveau cas, vrai `Pesto-Join.xaml` en WPF sans bureau 10/10 (liste, saisie conservée, 3 caractères, événements, demande d'inventaire), `TESTER.cmd` et banc UX sans régression (`preuves/vm-2026-10-05-services/`). | Vue en session console (démonstration puis AD réel) : non jouée. |
| S2 | Noms disponibles : le code service était affiché « Équipe » (filtre, colonne, boutons, message, export CSV). | « Service » partout où c'est visible ; filtre « (tous) » ; colonne `Service` dans l'export CSV. Noms internes inchangés. | Mac : même fichier de test. Windows 5.1 : vraie fenêtre principale chargée, colonne et filtre « Service » (`preuves/vm-2026-10-05-services/`). | Vue en session non jouée. |

## Version du 07/10 (archive `PESTO.zip`), relue et vérifiée

Changements trouvés non commités dans le clone, identiques au pack DEV de l'archive :

- Fenêtres de résultat : `Show-PestoOutcome` (fenêtre rattachée à Pesto, même quand elle n'est pas au premier plan)
  à la fin d'une jonction (succès, erreur, simulation), d'une action directe et du bilan de la file.
- Recherche de site au-dessus de la liste des sites retirée (`SuiteSiteSearch`).
- Démonstration : l'action directe accepte l'OU fictive « (mode GUI) ».
- EXE `5178edab…` compilé avec le **clang d'Apple 21** (piège du `PATH`) : remplacé par `92676b22…`, construit avec la
  chaîne documentée (clang/lld 23.1.2) sur les mêmes sources. Vérifié sous 5.1 sans bureau : `--check-json` PASS,
  stabilisation 27/27, test WPF des services 10/10 (`preuves/vm-2026-10-07-popups/LIRE.md`).

`cfg.json` livré dans l'archive (format historique, accepté par la 1.0) : `DEBUG.Simulation` vaut `"true"` (aucune
modification réelle tant qu'il reste ainsi) et `DirectProd` vaut `"false"` (jonction en zone de préparation : service
imposé `765`, donc pas de liste de services en jonction, par règle de configuration). À confirmer par David avant usage
en production.

## Nom pris par un autre poste du banc (S3, 07/10)

Trois techniciens peuvent recevoir le même « prochain nom libre » tant qu'aucun ne l'a encore écrit dans l'AD (inventaire
lu par chacun). Pesto revérifiait déjà le nom dans l'AD avant l'opération (jonction : contrôle, lancement, juste avant
`Add-Computer` ; renommage : contrôle, juste avant `Rename-Computer`) mais **bloquait** sans proposer le suivant.
Correction (décision de David : proposer + un clic) : le nom trouvé pris est écarté pour la session, le nom libre suivant
est sélectionné et annoncé (« X est déjà utilisé… Nom suivant proposé : Y »), revérifié dans l'AD, puis confirmé par le
technicien ; au plus 5 bascules d'affilée. Jamais d'opération sous un nom non confirmé. Vérifié sur l'AD réel du labo et
dans la vraie vue de jonction sous 5.1 (`preuves/vm-2026-10-07-noms-pris/`).

Plusieurs contrôleurs de domaine : deux postes pouvaient interroger des DC différents, un nom créé sur l'un n'étant visible
sur l'autre qu'après réplication. Décision de David (07/10) : **émulateur PDC pour tous les postes**. Après la découverte
d'un DC, la lecture AD bascule sur l'émulateur PDC, qui sert ensuite aux contrôles, à la jonction et aux renommages ; le
journal indique le contrôleur utilisé. PDC injoignable : le DC découvert est gardé, rôle « Secours » signalé dans le
journal (revérifications maintenues, réplication non garantie). Labo à un seul DC : bascule vers un autre DC non
observable ; vérifié par test statique et sous 5.1 (parseur, stabilisation 27/27).

**Retiré le 08/10** (décision de David, réseau réel à plusieurs contrôleurs : « remet comme avant ça marchait bien, le
multi contrôleur fout la merde »). Mesuré sous 5.1 : un serveur AD injoignable coûte 27 s (hôte sans ADWS) à 65 s (adresse
muette) par lecture, et la bascule était retentée à chaque actualisation ; un PDC distant ralentit toutes les lectures.
Chaque poste garde le contrôleur découvert par Windows (inscriptible, ADWS). Risque de réplication entre contrôleurs : de
nouveau ouvert, couvert seulement par les revérifications avant l'opération.

## Nom pris : essais successifs puis abandon (signalé par David le 08/10, corrigé)

Symptôme : en mise au domaine, Pesto essayait plusieurs noms pris avant de trouver le bon, puis s'arrêtait après
quelques essais ; il fallait relancer. Causes, lues dans le code :

- Les noms proposés viennent de l'inventaire local (OU racine), chargé en arrière-plan hors domaine ; le contrôle, lui,
  interroge tout le domaine. Inventaire pas encore chargé ou périmètre plus étroit : le premier nom libre « local » est
  pris, puis le suivant, etc. Un contrôle AD complet par numéro.
- Quand l'inventaire arrivait pendant l'enchaînement, la liste des noms était recalculée, la sélection changeait et le
  contrôle en cours était rejeté (« Contrôle périmé. Relancez la vérification. ») : arrêt de l'enchaînement.
- Le compteur de bascules (5 au plus) ne repartait de zéro qu'après un contrôle réussi ou à l'ouverture de la vue.

Correction : série du nom pris lue dans l'AD (jonction et contrôle préalable du renommage) et écartée pour la session ;
relance automatique du contrôle quand seule la liste a changé (aucune saisie du technicien), 3 fois au plus ; compteurs
remis à zéro à chaque clic ; inventaire des noms ajouté aux noms déjà utilisés. Toujours : nom suivant annoncé, revérifié,
confirmé par le technicien. Preuves : `preuves/vm-2026-10-08-noms-suite/`.

## Même nom pour plusieurs techniciens sur plusieurs postes (demande de David le 08/10, traité)

Options : registre partagé des réservations (dossier réseau, POLICY.CoordinationRoot), réservation dans l'AD à la mise au
domaine (ReserveNamesInAD), numéro au hasard (RandomNameChoice) ; toutes réglables dans Paramètres. Reprise après
redémarrage par RunOnce retirée le même soir (décision de David : elle n'agit qu'à l'ouverture de session suivante). Mesure sur la VM (4 processus, même instant, 8 tours) : sans protection, collision à chaque tour ;
hasard, collision à chaque tour mais 3,5 fois moins de nouveaux essais ; registre, aucune collision
(`preuves/vm-2026-10-08-reservations/collisions.html`). Limites : avec un dossier configuré, un partage injoignable refuse
l'opération avant écriture (verrou d'engagement existant) ; réservation AD vérifiée sur l'AD réel du labo par le worker de
Pesto (création, doublon refusé, retrait), jonction par Pesto avec réservation non jouée en session ; plusieurs contrôleurs avec réplication réelle non qualifiés.

## « Vérification requise » en renommage alors que tout est rempli (signalé par David le 08/10, corrigé)

Causes (enquête multi-agents contre-vérifiée, puis banc) : (1) après une mise au domaine faite par Pesto et le
redémarrage, le reçu de jonction reste « à vérifier » (`ReadyToObserve`) et bloque toute écriture sur ce PC ; le message
« Consignez la vérification AD dans Interventions » n'apparaît que sur la page de jonction, masquée une fois le PC dans le
domaine ; (2) dans « Un poste », la cause précise calculée par `Update-PestoSuiteUI` était écrasée par le texte général du
parcours (« Une opération ou une configuration attend votre vérification ») ; (3) « Enregistrer les paramètres » sans rien
changer posait « redémarrage requis » quand le cfg.json n'avait pas `EntraPolicy` (cas du cfg livré). Correction : cause
dite sous le bouton, bouton qui ouvre la vérification correspondante (consignation toujours explicite), signature de
configuration où `EntraPolicy` absent vaut `HybridOnly` comme dans le moteur. Non joué : enchaînement réel jonction,
redémarrage, vérification, renommage sur l'AD (identifiants de David requis).

## Services longs à apparaître, « Vérifier » grisé (signalé par David le 08/10, corrigé)

Réseau réel : au moins 30 s avant de voir un service ; « Vérifier » grisé. Cause : depuis S1 (05/10), la liste des services
et les numéros pris venaient uniquement de l'inventaire complet (tous les postes de l'OU racine et du périmètre des noms),
lu en arrière-plan ; sans service choisi, aucun nom n'est proposé et « Vérifier » reste grisé. La bascule PDC (07/10,
retirée) aggravait l'attente. Correction : recherche ciblée du site au choix du site (noms commençant par le code du site
dans tout le domaine, postes de l'OU du site ; lecture seule, une fois par site et par session, relue après intervention).
« Un poste » affiche ce qui manque sous le bouton. Vu sous 5.1 avec un AD simulé (1,1 s) ; mesure sur l'AD réel du labo
prévue dans `outils/labo/mac/banc-noms-serie.sh` (mot de passe tapé par David). Non mesuré sur le réseau réel de David.

## Démo réelle du 08/10/2026 (AD du labo, vrai Pesto PROD)

- **R1 corrigé** : reçu ou intervention de jonction écrits sous un autre préfixe (cfg.json changé, autre département)
  refusés comme invalides ; conséquence : toute mutation du PC bloquée (97) et liste des interventions illisible.
  Validation structurelle du nom pour les données historiques (`Pesto-JoinRecovery.ps1`, `Pesto-Recovery.ps1`).
- **R2 corrigé** : refus du garde d'état persistant noté 97 (incertain) alors que rien n'était lancé, ce qui enregistrait
  une opération incertaine et bloquait la suite ; désormais 96 (`Pesto-Core.ps1`).
- Observé, non corrigé (conception) : une opération unitaire restée incertaine ne se clôt que si l'état réel devient
  conforme au plan (consignation) ou par la reprise du déplacement ; il n'existe pas de « constaté non lancé ».

