# Validation de la parité C5 — 25 octobre 2026

Ce rapport décrit le lot qui termine les derniers parcours V1 identifiés dans la branche `codex/pesto-v2-20261023`. Il succède à [la reprise C1–C4](VALIDATION-REPRISE-20261025.md). Le dépôt GitHub est la source de travail ; aucun code non poussé du Spark n’est supposé intégré. Les releases V1 restent intactes.

## Code réellement raccordé

### Attributs AD

Depuis **Un poste**, le parcours Attributs lit description, emplacement et responsable. Il conserve les espaces, distingue un champ absent d’un effacement, relit le DN canonique et le GUID du responsable, montre le diff puis exige le nom exact. Le plan lie identité, OU/DC, anciennes valeurs et configuration. Une seule écriture native suit un reçu initial durable ; le succès exige relecture exacte et persistance finale. L’observation explicite après perte de réponse ne rejoue jamais Set-ADObject.

L’interface refuse une réponse étrangère au plan, un diff partiel, un GUID de responsable divergent et un succès sans preuve cohérente. Elle invalide la confirmation si la session change. Les historiques V1 restent consultables, sans être convertis en autorisations V2. Le mode consultation peut lire les faits mais ne clôture pas un reçu ni ses verrous.

### Jonction hors ligne

Le même EXE possède l’entrée `--offline-join`, également accessible depuis Ajouter. Elle ouvre un contexte local distinct, avec bannière permanente d’opération réelle, sans connexion AD ou chargement du tableau de bord. Son backend fermé refuse toutes les API normales avant d’inspecter les arguments. Un choix natif garde le chemin et le contenu du blob hors du navigateur.

L’import est protégé par DPAPI machine et ACL SYSTEM/Administrateurs, dédupliqué par SHA et lié au nom actuel/GUID/OU déclarés. Une préparation puis une confirmation distinctes précèdent l’intention durable et l’unique djoin. Le blob devient non rejouable dès cette intention, y compris après interruption ; les journaux V1 connus restent bloquants. Le registre est borné à500 imports, sans création du 501e. Le fichier source n’est pas modifié.

Le redémarrage demeure manuel. L’observation AD se lance ensuite explicitement et exige un nouveau boot, la même machine et les mêmes GUID/nom/OU/domaine/canal sécurisé. Une preuve historique de réussite conservée ne transforme pas un contrôle courant échoué en succès. Les anciens imports ODJ V1 ne sont ni migrés ni appliqués par ce parcours. Voir [OFFLINE-JOIN.md](OFFLINE-JOIN.md).

### CLI et pilote

La CLI démarre avant WinForms, UAC et initialisation du profil. Actions fermées, opt-in de configuration et `--execute`, plan exporté lié aux identités/configuration, préparation native fraîche et clé d’idempotence sont effectifs. Le journal précède la création des adaptateurs et les accès distants. Les reprises locales ne rouvrent pas les credentials ni un fournisseur réseau ; `0/3010` exigent les octets exacts du reçu métier et son identité complète, sinon 97. Les anciens journaux V1 ne deviennent pas des autorisations de rejeu.

Le compte AD transite uniquement dans un pipe mémoire DPAPI du compte effectif. Le lecteur exige EOF et une borne indépendante de 30 secondes ; il n’utilise pas la fausse annulation d’un ReadAsync console synchrone sous Windows. Aucun dialogue de secours ni repli interactif n’existe dans ce chemin. Les accords de campagne HKLM, s’ils sont requis, portent le hash complet du plan V2 ; ce mécanisme n’introduit aucune signature applicative. Voir [CLI.md](CLI.md).

Le mode pilote est lié au lot préparé dans le moteur : première ligne seule, arrêt après son reçu, autres lignes conservées. Aucun argument envoyé à l’exécution ne peut élargir ce lot. Un résultat incertain n’est pas un pilote terminé.

### Hôte et configuration

Les trois politiques ODJ/non accompagné sont configurables dans le formulaire, incluses dans l’aperçu et le pack personnalisé, strictement booléennes, fausses dans un profil neuf. Les paramètres, différences et choix distribués restent dans le profil original sous UAC. L’entrée locale ne remplace pas une configuration existante et ne décide pas automatiquement d’une nouvelle distribution.

La fermeture du parent attend désormais les opérations et la fermeture de ses fenêtres locales possédées ; le reçu engagé reste traité avant disparition de l’interface. La démo et les contrôles santé/reprise binaire restent séparés de la configuration réelle. Les dix nouvelles API attributs/ODJ sont refusées en démonstration avant tout fournisseur ou dialogue.

## Validation portable réellement exécutée

SDK .NET 10.0.302 ; builds séquentiels `--disable-build-servers -m:1`. Les logs sont capturés intégralement puis écrits une fois dans l’espace de travail. [Synthèse publiable des résultats](evidence/20261025/c5/README.md).

| Contrôle | Résultat |
|---|---:|
| Moteur, tous les tests présents | **590/590**, exit 0 |
| Pont natif, schémas et sérialisation | **15/15**, exit 0 |
| Banc de qualification des transactions, mode fixture | **10/10**, exit 0 |
| Compilation moteur/tests | **0 erreur, 0 avertissement** |
| Compilation du pont/tests | **0 erreur, 0 avertissement** |
| Compilation croisée de Pesto.App Windows x64 | **0 erreur, 0 avertissement** |
| Compilation du banc de mise à jour | **0 erreur, 0 avertissement** |
| Stabilité des sources C#/projets pendant validation | **231/231**, aucun changement |
| Parité UI attributs/ODJ/pilote/historique/shell local | **50/50** |
| Opérateur | **32/32** |
| Parcours métier | **29/29** |
| Maintenance | **18/18** |
| Reprise | **23/23** |
| Cycle du pont JS | **21/21** |
| Démonstration JS | **11/11** |
| Contrôle web, navigation, imports et API démo | **149/149** |

Les dernières suites Chromium utilisent les vrais modules, formulaires et dialogues, avec réponses en mémoire et aucun accès hors loopback. Les preuves de régression conservent78 empreintes web avant/après. La preuve 50/50 précise que seul le résumé final a été conservé, sans inventer une capture complète du stdout.

Les échecs initiaux restent conservés dans l’espace de travail : cinq diagnostics CA1416 dans un lambda ACL Windows ; un test dont la fixture recréait un reçu au lieu de finaliser l’existant ; treize assertions statiques web obsolètes. Le premier a été corrigé sans retirer de garde, le second sans changement de production, le dernier en vérifiant effectivement les dix nouvelles API et les deux navigations. Les passages finaux sont verts.

## Campagnes Windows, attachées à leurs binaires

Les runners **Windows 2025 de GitHub Actions exécutent le vrai Pesto.exe et le runtime WebView2 embarqué**. Ils ne constituent pas un domaine AD de laboratoire.

- `b7e781f`, campagne 40222575362 : démarrage/fermeture PROD/DEV,29 refus directs, installation/santé/rollback, santé négative/rollback et reprise après interruption réussis. Les preuves et leurs limites restent dans le rapport précédent.
- `9f2147e`, campagne 40227090418 : échec réel du parseur Windows PowerShell5.1. Apostrophes typographiques dans chaînes simples et retours de ligne d’opérateurs corrigés dans 5421907 ; aucune réussite rétroactive attribuée à ce binaire.
- `5421907`, campagne 40227888951 : les 13 sources n’ont plus d’erreur syntaxique ; le banc échoue encore sur sa sortie de processus. Le correctif 41b7722 supprime la progression parasite et journalise toutes les postconditions strictes.
- `41b7722`, campagne 40228437180 : **13/13sources PS5.1**, exit 0, stderr vide ; PROD prêt/fermé et34 refus, mais `success:false` conservé car un compteur final était resté à 29. [Campagne et artefact original de l’échec](evidence/20261025/windows-41b7722/README.md). Le commit 8b9f143 corrige ce compteur à 34.

La campagne **[40229224507](https://github.com/M4D135/pesto/actions/runs/40229224507) du commit 8b9f143 est réussie** : PS5.1 13/13, démarrage/fermeture PROD/DEV et 34 refus directs, ainsi que les trois scénarios transactionnels PROD avec santé, rollback et reprise. [Accès aux preuves originales](evidence/20261025/windows-8b9f143/README.md). EXE `f1216b4d44e9459506d02d01de852ece4c4160c02d5bb52d70f6c9bde03f73d9`. Elle reste attachée à ce commit.

### C5 : campagne native réussie

La campagne **[40230708170](https://github.com/M4D135/pesto/actions/runs/40230708170)** est terminée avec la conclusion **success** pour le commit **`de527313b98f30d52802ec6abd51804e12f8c298`**. Le runner Windows 2025 utilise Windows NT 10.0.26100.0 et le runtime WebView2 fixe **156.0.4314.42** livré dans les packs. Les [preuves et empreintes du candidat](evidence/20261025/windows-de52731/README.md) identifient les archives originales.

| Contrôle Windows C5 | Résultat observé |
|---|---|
| Parseur Windows PowerShell 5.1 | **18/18** variantes analysées, code 0, stderr vide ; scripts métier non exécutés |
| Suites moteur ciblées sur Windows | **171/171**, sur fixtures ; pont **15/15**, banc portable **10/10** |
| Vrai EXE PROD puis DEV, mode de qualification démo | Interface prête, fermeture normale, **44 API réelles refusées par canal**, aucun appel à l’hôte, aucun profil réel créé |
| Installation PROD puis rollback explicite | Santé native confirmée, retour contrôlé ; état final `rolledBack` |
| Santé négative puis rollback PROD | Échec détecté, ancien pack restauré et contrôlé ; état final `rolledBack` |
| Interruption pendant le contrôle de santé puis reprise PROD | Interruption observée, reprise native contrôlée ; état final `rolledBack` |
| Préservation dans les trois scénarios | Pack source et configuration sentinelle inchangés ; deux tentatives de santé distinctes par scénario |
| Archivage | Deux packs complets PROD/DEV et artefact de preuves disponibles ; aucune release publiée |

SHA-256 du même `Pesto.exe` dans les deux packs :
`438c4528d2c529f6b4a33225924330e47491cee9bb76ec1f121bebd639365848`.

| Archive interne produite par le workflow | SHA-256 |
|---|---|
| `Pesto_V2_PROD_candidate.zip` | `169e02fcbcbf8ac2c1cff53ad8a5ac7897dfcaa5344127691356edd5ca2861e6` |
| `Pesto_V2_DEV_candidate.zip` | `0741e606e74d2f09c0acb7df3ffa7d7bc6858efe200582a816f04df408b4f934` |

Ces empreintes proviennent de `artifacts.json`, produit après les essais. L’archive de preuves a été téléchargée et son SHA-256 contrôlé ; les gros packs n’ont pas été téléchargés une deuxième fois dans l’environnement de développement. Les résultats Windows sont rattachés à ce commit source, indépendamment du commit documentaire qui consigne ensuite leur bilan. Les journaux natifs originaux restent dans les artefacts GitHub ; seule leur synthèse sans données de laboratoire est ajoutée au dépôt.

Le smoke natif automatise une fenêtre de démo masquée. Il vérifie l’initialisation de l’interface et les refus directs, sans parcourir tous les clics des scénarios ni effectuer de capture réseau indépendante. Les contrôles moteur et Chromium couvrent séparément les scénarios, le reset, les identifiants et le redémarrage fictif.

## Limites et qualification réelle restante

Le contrôle SSH du bastion de laboratoire autorisé, renouvelé **après le push de `de52731`**, a répondu **Connection refused** (code 255). Cela ne prouve pas que la VM soit arrêtée ; aucune session Windows de ce laboratoire n’a été obtenue et aucune mutation AD n’a été tentée par cette voie.

Restent à qualifier sur le domaine/poste autorisés : canari AD réversible avec retour prouvé, réutilisation de compte précréé, exclusions récursives, attributs AD réels, diagnostic/tâches distants, réservations/coordination SMB intermachines, horloge du DC, ODJ/djoin/DPAPI/ACL et observation après boot, CLI avec credentials et GPO de campagne, UAC avec autre compte et profil original, retrait Entra hybride et redémarrage réel explicitement autorisés.

Le banc automatique de mise à jour emploie des copies isolées PROD et plusieurs versions de manifeste avec le **même EXE candidat**. Il teste la mécanique transactionnelle et de santé avec des fichiers Windows chargés. Il ne prouve ni le remplacement entre deux builds applicatifs indépendants, ni un UNC réel, ni les droits ProgramFiles ou une élévation avec un autre utilisateur. La transaction native DEV n’a pas été exécutée. Le démarrage en mode démo ne qualifie pas une session AD normale, ni la coexistence native d’une session AD active avec sa fenêtre de démonstration.

Les [contrôles Windows critiques](QUALIFICATION-WINDOWS.md) donnent les preuves attendues. Candidats PROD/DEV autonomes, distribution personnalisée et release officielle restent distincts. Aucune release V1 n’est remplacée ; aucune qualification AD n’est inventée.
