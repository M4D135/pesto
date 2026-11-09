# Relais du projet Pesto

État relevé le 13 octobre 2026 vers 21 h 36, heure de Paris. Destinataire : prochain agent reprenant le projet avec David.

**Le développement est conservé en local, mais la livraison n’est pas terminée.** David a demandé de réduire la consommation de tokens ; les trois agents ont été interrompus. Cette passation ne relance ni développement, ni tests, ni Spark. Reprendre au rythme demandé par David, avec des vérifications ciblées.

## Où reprendre

| Élément | Emplacement ou état |
| --- | --- |
| Dépôt Pesto | `/Users/david/Projects/pesto`, branche `master` |
| HEAD | `221e050111246c9ca5ec574243ffed578e3a1142` |
| Dernier push vérifié pendant le chantier | Ce même commit, contenant seulement le catalogue des 120 améliorations |
| Base logicielle précédente | `b5d5f34b390eedca6916a754114238e49523a0a4` |
| Socle commun canonique | `/Users/david/Projects/m4d-admin-common` |
| Commit Common local | `a050525abb46696d6b1516b18cccc2b837908a09`, arbre propre, pas encore poussé par ce chantier |
| Helpers privés du chantier | `/Users/david/Documents/Codex/2026-10-12/tu-x20/work` |
| Suivi des 120 points | `DEV/docs/implementation/catalogue-120.json` et `AMELIORATIONS_120.md` |
| Preuves de cette campagne | `preuves/ameliorations-120-2026-10-13/` |
| État local exact à la passation | `preuves/ameliorations-120-2026-10-13/relais/etat-local.json` |

Le catalogue conserve des états `in_progress` : sa réconciliation finale reste à faire. Les modifications et nouveaux fichiers du chantier ne sont pas encore committés. Ne pas nettoyer le clone, les preuves ou `work/` avant sauvegarde et livraison vérifiées.

## Décisions de David à conserver

- Pesto reste en **version 1.0**. Les guides utilisateur ne racontent pas l’historique des versions.
- Deux packs classiques : **DEV et PROD**, chacun avec `Pesto.exe` et le dossier `wad/`. Le projet d’archive WAD est abandonné.
- Distribution neutre ; préserver les configurations importées, préférences, journaux et reçus existants, notamment les emplacements et mutex historiques `GP`.
- Choix aléatoire activé par défaut parmi tous les noms libres admissibles selon les filtres. Coordination partagée et réservation AD désactivées par défaut.
- Automatisation silencieuse et jonction activables explicitement en configuration ; aucune mutation sans demande explicite d’exécution.
- Suivi après redémarrage facultatif pour une commande acceptée : permettre une nouvelle préparation sans obliger à consigner la précédente. Conserver les protections des opérations actives, partielles ou incertaines.
- Contrôleur découvert par Windows ; aucune bascule automatique vers le PDC. Aucun redémarrage, retrait Entra, changement de sécurité ou activation de service implicite.
- Interface sobre et aérée, quatre boutons sur l’accueil, connexion au premier plan, icône de réduction en bas du menu, commandes indisponibles réellement désactivées.
- Tests et simulations regroupés en fin de développement. Recette humaine autorisée sur **PESTO-W11-TEST seulement**, avec captures réelles au moins 1080p, sans infobulles.
- Commit et push finaux sur **master**, après correction, validation, guides et packs. La demande spécifique de publier la liste a déjà été satisfaite ; elle ne publiait pas le logiciel inachevé.
- Mutualisation avec DOMENIA et FILPRO. Spark autorisé par la décision récente, mais aucun nouvel appel n’est nécessaire pour reprendre : sa revue est reçue.

## Travail intégré

Les rapports par lot se trouvent dans `DEV/docs/implementation/` : `UI_120.md`, `ENGINE_120.md`, `AUTOMATION_120.md`, `EXTENSIONS_120.md`, `RELEASE_120.md`, `COMMON_020_INTEGRATION.md`, `QUALIFICATION_120.md`, `GUIDE_TACHES_120.md` et `CLOTURE_120.md`.

Le lot comprend notamment les espaces de travail UI, recherche de réglages, aperçu de configuration, outils de noms, préparation/import de lots, collections, outils de reçus, diagnostics, module Engine généré, CLI Inspect/Diagnose/Join/Rename/Move/RenameMove, plans portables et idempotence, politiques administrées, options de déploiement, contrôles de mise à jour et reproductibilité. Certaines propositions sont des évaluations ou prototypes documentés : ne pas les présenter comme des intégrations externes déjà déployées.

Common 0.2.0 conserve `AssemblyVersion=0.1.1.0`, avec `FileVersion=0.2.0.0`. Pesto embarque Core, Query, IO et Diagnostics, verrouillés par hash. Wpf reste séparé. Digest source : `eaad4c85b4cc47cbe307f282358ff45e9b103777c8d3c0282812ea9f54e58a35`. Ne pas remplacer les persistances critiques, leases ou writers éprouvés simplement parce qu’une primitive commune existe.

La coordination a été transmise au chat FILPRO `01a13043-e2d9-7ae2-824f-f0cb627cc440` avec contrat, commit candidat, preuves Windows et statut non poussé. Aucun clone ou VM FILPRO n’a été modifié par Pesto.

## Candidat testé et sources actuelles

Le candidat **C2** a été construit avec 62 composants runtime, 632 fonctions Engine et une fermeture de worker de 136 fonctions.

**SHA256 EXE C2 :** `4bd73854d6499f3ded5d5712bd5869b441a5641c7401129d947461137bc70cd8`.

- Packs candidats : `work/pesto-120-c2-packs/Pesto_DEV.zip` et `Pesto_PROD.zip`.
- Deux builds PROD indépendants identiques : `work/pesto-120-c2-repro/`, preuve `local/repro-c2.json`.
- DEV candidat : 531 fichiers. PROD : 65 fichiers, sans tests/outillage/vendor, configuration neutre.
- Ces ZIP contiennent encore les anciens guides rendus. Ils ne sont pas les livrables finaux.

**Attention : les sources actuelles ne correspondent plus au lanceur C2.** Le relevé `relais/etat-local.json` liste les différences exactes. Après les tests, des correctifs ont été écrits dans `Pesto-Diagnostics.ps1`, les deux wrappers CLI et `Pesto-Shell.xaml`. Ils n’ont pas encore été incorporés au module généré, au lanceur et au manifeste.

Correctifs récents à relire et qualifier :

1. Libellés distincts LDAP/TCP389 et ADWS/TCP9389.
2. `-AsJson` des deux wrappers : échappement Unicode produisant un JSON ASCII, valide UTF-8 et indépendant des pages de codes, sans modifier la sortie objet. Nouveau `Run-CliOutputTests.ps1` présent ; travail interrompu, ne pas le déclarer validé.
3. Marge de 16 px entre la case « Son en fin de lot… » et le bouton Densité. Test portable Workbench : 34 PASS ; contrôle visuel Windows de cette marge restant.
4. Corrections de bancs Windows listées ci-dessous.
5. `.gitattributes` dans le clone et le DEV autonome pour préserver les octets runtime/vendor. Listes de packaging Python/PowerShell et helper de déblocage alignés. Ce helper est hors binding EXE ; prochains ZIP à reconstruire.

Ordre de reconstruction : `Build-PestoEngineModule.ps1`, `tools/launcher/build_native.py`, puis `tools/refresh_manifest.py`. Ne pas éditer à la main les fichiers Engine générés. Cible Windows PowerShell 5.1, C#5/net472 ; conserver BOM UTF-8 et fins de ligne des scripts.

## Résultats déjà obtenus

| Campagne | Résultat et portée |
| --- | --- |
| C2 Python local | 405 tests PASS, `local/python-c2.log` |
| C2 Engine portable | 181 PASS, `local/engine-c2/summary.json` |
| C2 UI portable | 110 PASS, `local/ui-c2/summary.json` |
| C2 intégration | 18 PASS, `local/Integration-c2.json` |
| Parseur C2 | 123 scripts, aucune erreur |
| Module/manifeste C2 | génération déterministe et 62 composants vérifiés |
| Common Windows PS5.1 | Core2625, Query81, IO22, Diagnostics15, Wpf7 PASS ; trois cas de liens indisponibles via API C# complétés par cinq tests PowerShell réels de liens PASS |
| Packaging autonome ajouté ensuite | deux tests Git et trois contrôles packaging ciblés PASS |

### Windows avec fixtures

Ne pas confondre doubles, chargement WPF isolé et opérations AD réelles.

- `windows/` : première passe de 46 suites. Certains scripts ont déclaré des échecs malgré un code processus 0 ; le wrapper a été corrigé pour propager le code de sortie. Lire les rapports, pas seulement les codes.
- `windows-retry/` : sept suites rejouées après correction des chargeurs AST/dépendances : **243 PASS, 2 FAIL, 2 SKIP**. Les six premières réussissent ; Ux manque encore `Get-PestoNameSegments` dans cette copie testée.
- Sans double compte, 39 suites initialement réussies + sept reprises : **1 449 PASS, 2 FAIL, 5 SKIP** sur 46 suites.
- Neuf variantes WPF séparées : **347 PASS, 5 FAIL, 0 SKIP**. Les échecs concernent Workbench120 (3), NamesLoading (1) et Pesto21 (1).
- Total du seul dossier retry, sept reprises + neuf variantes WPF : **590 PASS, 7 FAIL, 2 SKIP**. Ce total recoupe le précédent : ne pas les additionner.

Correctifs écrits après ces résultats, à rejouer :

- Ux : dépendance AST `Get-PestoNameSegments` ajoutée.
- Workbench WPF : collision de portée `$name` / paramètre `$Name` du helper Case ; les trois extractions XAML ne s’exécutaient pas. Variable renommée. Trois extractions XML et 34 tests portables réussis ensuite ; WPF final attendu 40 cas.
- NamesLoading : vraie fusion ManagedPolicy chargée, lecture GPO doublée.
- Pesto21 : le test lisait Dropped avant la fin du thread du writer ; il attend maintenant Close. Relire `local/engine-c3-harness/` avant toute affirmation sur le dernier essai.

Les preuves d’échec restent conservées. Les helpers refusent d’écraser une campagne existante : préparer une nouvelle campagne pour le prochain runtime. `work/pesto_120_retry.py` a repris C2 en vérifiant les 531 originaux puis en copiant 524 fichiers et sept bancs corrigés. L’échec initial de staging était une commande Windows trop longue ; `resume-stage` transfère désormais le script séparément.

## Recette humaine atteinte

VM : **PESTO-W11-TEST**, UUID `9b2ad4f0-0506-4f58-aed2-c43ac1973516`. Dernière observation : Windows 11, PowerShell 5.1 x64, domaine `labo.local`, nom `P111301LY765128`, console `LABO\administrateur`, résolution **1920 × 1200**.

Copies distinctes sur la VM :

- `C:\Pesto120_20261013` : DEV C2 immuable pour fixtures, 531 hashes vérifiés.
- `C:\Pesto120_Retry_20261013` : reprise des fixtures ; préserver les rapports.
- `C:\Pesto120_GUI_20261013` : PROD séparé, 65 hashes vérifiés avant import ; configuration de labo importée par l’interface depuis la précédente copie PestoOptionalLive. Ne pas redistribuer cette configuration.
- `C:\PestoCommon020_20261013` : qualification Common et fixtures de liens, à conserver.

Parcours réels observés dans `interactive/`, captures 13 à 40 et `human-actions.jsonl` : premier lancement neutre, import puis validation, accueil avec quatre boutons, réglages par onglets, recherche `RandomNameEnabled`, noms filtrés LY/765/Portable, candidat `P111301LY765423` vérifié libre sur le DC, transfert au formulaire unitaire, vérification seule, ouverture de confirmation et **annulation sans changement**, accès au lot vide et à ses commandes. Les anciens reçus PendingRestart restent présents ; une nouvelle préparation a été ouverte sans validation obligatoire de l’ancien suivi.

CLI réel : Inspect et Diagnose ont renvoyé ExitCode0 en lecture seule, sur `dc01.labo.local`. GUID observé : `b4797c9c-d790-4797-bf71-424a57acb36e`. Les premières sorties JSON redirigées sont en OEM, pas UTF-8 ; les accents paraissent erronés si le lecteur impose UTF-8. Conserver leurs octets et tracer toute normalisation. C’est la raison du correctif ASCII JSON.

**Aucune nouvelle mutation AD n’a été confirmée dans cette campagne C2.** Renommage, déplacement et jonction sur le build final restent à réaliser. Les opérations des campagnes précédentes ne les remplacent pas.

Une mesure en lecture seule a été lancée sur le processus GUI7748 : 180 échantillons espacés de cinq secondes, rapport prévu `C:\Pesto120_20261013\interactive\preuves\session-c2-180.json`, processus observateur3804. Au relais, sa fin n’a pas été relue ; récupérer le rapport s’il existe. Ne pas en déduire une absence de fuite à long terme.

Helpers locaux : `pesto_lab.py` (SSH existant), `pesto_120_human.py` (vrais clics/scancodes VirtualBox), `pesto_120_gui.py` (lecture UIA/captures), `pesto_120_live_lab.py` et `pesto_120_retry.py`. `KEY` attend un scancode entier, Entrée=0x1c. Éviter de lancer le pilote UIA pendant une saisie humaine : une console transitoire peut voler le focus. Sur SSH invité, préférer transfert tar de fichiers puis commande courte ; le gros payload stdin a expiré lors d’une vérification.

Ne pas redémarrer/restaurer les DC ou VM DOMENIA/FILPRO. Avant mutation du seul poste Pesto, relire son état courant et préserver les reçus. Ne pas lancer de mutation interactive pendant les suites utilisant les mutex réels du produit. Aucun mot de passe ne doit être copié dans les documents, preuves ou commits.

## Revue Spark à terminer

Réponse complète reçue ; aucun appel encore actif. Copies conservées : `relais/spark-review.txt` et `relais/spark-sources.json`. Entrée complète d’origine dans `work/spark-review-120/prompt.txt`. **Ce sont des propositions de revue, pas des bugs tous reproduits.**

Huit constats à arbitrer contre le code complet :

1. Cohérence Phase/ExitCode et timeout dans Invoke-PestoUnattendedOperation.
2. Transmission du timeout dans Invoke-PestoUnattendedJoin ; les snippets proposés doivent être relus car une branche ultérieure peut réécraser l’état incertain.
3. Nettoyage de `$script:cred` après Diagnose dans Invoke-PestoCommand.
4. Initialize-AuditLog : ouverture du journal avant contrôle des liens/ancêtres.
5. Reçu de jonction facultatif avec JoinEvidence non accepté : **hypothèse possiblement déjà réfutée par le schéma fermé** de Assert-PestoJoinReceiptData, qui n’autorise pas JoinEvidence dans le reçu local. Vérifier avant modification.
6. Proposition de supprimer une clé idempotente après refus96 : **ne pas appliquer automatiquement**. La conservation d’un résultat et le non-rejeu sont intentionnels ; préférer documenter une nouvelle tentative explicite avec nouvelle clé après examen.
7. Robustesse du catch du worker direct si OperationId invalide : vérifier les validations en amont.
8. Garde sur Monitor.Events : vérifier le contrat du constructeur avant d’ajouter un contournement silencieux.

À l’interruption, Enterprise/Automation/Direct/Journal avaient encore exactement les octets C2 selon le relevé comparatif. Les agents chargés de ces remarques ont été arrêtés avant une intégration confirmée. Ne pas annoncer les huit points corrigés.

## Prochaine séquence de travail

1. Relire ce relais, l’état Git et les corrections interrompues ; rester économe en tokens. Pas de rafale d’agents ou nouvel appel Spark sans besoin.
2. Arbitrer les constats Spark, finir les vrais correctifs et leurs tests ciblés. Préserver les invariants de non-rejeu et résultats incertains.
3. Reconstruire Engine, EXE et manifeste dans un nouveau candidat. Rejouer les quatre bancs Windows encore en échec et les nouvelles régressions JSON/diagnostics, puis contrôler les dépendances touchées.
4. Terminer la recette GUI : import de lots/corrections, outils par onglets, historique/reçus, navigation clavier, petites fenêtres/zoom/thèmes ; opérations réelles sur le seul poste Pesto, suivi facultatif après redémarrage, simulation hors domaine avec les deux commandes désactivées. Garder de nombreuses captures propres et leur hash de build.
5. Mettre à jour les images et générer les deux guides DOCX/PDF, puis inspecter toutes les pages rendues. Les sources Markdown technicien/administrateur ont été actualisées ; les mappings JSON/images et documents rendus restent à finir. Builder : `outils/guides/build_guide.js`, sorties `DEV/docs/Pesto-1.0-Guide-{technicien,administrateur}.{docx,pdf}`. Utiliser les skills documents/PDF et les runtimes fournis, pas une installation improvisée.
6. Réconcilier les 120 points avec preuves réelles. Signature sans certificat, autres orchestrateurs, multi-DC absent, App Control, redistribution et matrice complète non exécutée restent explicitement non qualifiés. Une évaluation documentée n’est pas un déploiement réussi.
7. Refaire les packs neutres, assurance/reproductibilité, scan des secrets et revue des captures. Suivre `CLOTURE_120.md`. Commit/push Pesto et Common seulement après clôture, puis vérifier les références distantes.

## Reprise rapide à transmettre

« Reprends Pesto à partir de RELAIS_PESTO_2026-10-13.md et du relevé relais/etat-local.json. Le code des 120 points est intégré mais la validation, les derniers correctifs Spark et les guides/packs ne sont pas terminés. Le runtime source dépasse le candidat C2 : reconstruire avant qualification. Préserver tous les fichiers locaux et reçus, rester économe en tokens, ne pas présenter les tests de fixtures comme des opérations AD réelles. »
