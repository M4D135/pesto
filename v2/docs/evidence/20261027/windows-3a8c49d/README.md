# C16 — preuves Windows finales du candidat 3a8c49d

La [campagne 40491875705](https://github.com/M4D135/pesto/actions/runs/40491875705) est **entièrement réussie** pour le commit [`3a8c49d85d5cc16dcab2d7c743be7fa445d05715`](https://github.com/M4D135/pesto/commit/3a8c49d85d5cc16dcab2d7c743be7fa445d05715), le 27 octobre 2026, de **10:52:46 à 11:13:51 UTC**. Le [rapport C16](../../../VALIDATION-C16-20261027.md) décrit les corrections métier, les deux incidents du banc et leur résolution. Aucun succès de cette campagne n’est transféré à un autre binaire.

## Résultats vérifiés

| Ensemble | Résultat | Portée |
|---|---:|---|
| Moteur complet | **615/615** | Runner séquentiel complet, fournisseurs isolés ; [journal](logs/Engine-All.log) |
| Pont | **15/15** | Contrats et sérialisation ; [journal](logs/Bridge.log) |
| Fabrication | **46/46** | Runtime synthétique déclaré ; reconstruction du même PROD depuis DEV avec les mêmes entrées de publication/runtime, aucune recompilation depuis DEV ; [journal](logs/Pack-Mechanics.log) |
| Compagnon portable | **30 contrôles** | Fixtures, aucune exécution native Windows dans cette suite ; [journal](logs/NativeUpdateHarness-portable.log) |
| Gardes du retour AD | **70** | 22 historique, 28 identité, 20 barrières V1 ; aucune mutation AD ; [journal](logs/AdRestoreGuards.log) |
| PowerShell 5.1 | **18 variantes**, entrée du banc et **2 contrôles UTF-8** | Analyse syntaxique et échange Unicode, sans exécution métier AD |
| JavaScript et navigateur | **16 suites réussies** | 540 contrôles chiffrés, plus le verdict distinct `watcher-result-check` sans compteur ; fixtures déclarées |
| Accueil et saisie Windows | **5 et 16 contrôles** | Vrais contrôles natifs, résultats UAC et identifiants synthétiques |
| Démonstration PROD et DEV | **44 refus et 6 transitions par canal** | Vraies fenêtres MainForm/WebView2, profils temporaires, conservation du parent et fermetures vérifiées |
| Configuration PROD et DEV | **36/36 par canal** | Boutons, confirmations, dialogues et fichiers réels, décrits ci-dessous |
| Transactions de mise à jour | **4 scénarios, 8 tentatives de santé** | Deux builds distincts, installation et retour réels sur copies isolées |

Le runtime embarqué est **WebView2 156.0.4314.42**, Windows observé **10.0.26100.0**. Les tests navigateur emploient Playwright **1.62.1** et Chromium **151.0.7922.34**. Les comptes locaux, les deux campagnes échouées et cette campagne se recouvrent ; ils ne s’additionnent pas.

## Parcours de configuration acquis

Les preuves [PROD](native-configuration-PROD.json) et [DEV](native-configuration-DEV.json) portent les mêmes **36 assertions**, **9 dialogues**, **2 sélections positives de dossier** et **6 captures WebView2** par canal. Le pilote agit dans les champs et boutons de la vraie fenêtre ; le pont et les services fournissent leurs réponses réelles.

Le parcours couvre l’export avec sa version, les différences avant enregistrement et sa confirmation, les sauvegardes exactes, les annulations d’import/export, le refus d’UTF-8 invalide et l’import confirmé après aperçu. Il produit un pack personnalisé depuis **Définir comme configuration par défaut**, sélectionne réellement son dossier parent et vérifie son manifeste, ses paramètres, son EXE et l’absence de répertoire de préparation résiduel.

Deux contrôles de service distincts vérifient l’import des paramètres distribués dans un profil neuf et la conservation d’un profil existant ; ils ne sont pas présentés comme deux parcours supplémentaires de boutons. Le banc choisit ensuite le dossier du pack comme source de maintenance, l’inspecte, le prépare, contrôle la copie préparée et relit l’état.

Pour chaque canal, les **six chemins retournés** lors des choix positifs de fichier ou dossier sont enregistrés et contrôlés avant la lecture du fichier importé ou l’écriture de l’export par l’hôte. Ils correspondent aux chemins relus dans les sélecteurs. Les dossiers utilisent le contrôle `Edit` **1152** observé, les fichiers 1001/1148 ; la barre d’adresse 41477 reste exclue. Le focus, les trois relectures stables et la fermeture effective sont vérifiés.

La confirmation d’installation est ouverte puis **annulée** : zéro appel `updates.install`, aucun relais ni transaction engagée par ce parcours. `nativeUpdateInstallFromUiQualified` reste `false`. Aucun appel hôte/backend interdit ou HTTP du service n’est observé ; les données Pesto temporaires sont supprimées et les sources sont conservées. Les six captures par canal sont dans l’archive complète, pas dupliquées ici.

## Transactions natives séparées

Les preuves [PROD](native-update-PROD.json) et [DEV](native-update-DEV.json) comparent le candidat B à une compilation A des sources `de527313b98f30d52802ec6abd51804e12f8c298`. Leurs commits et empreintes d’EXE sont distincts ; aucune version synthétique n’est substituée.

- **PROD :** installation depuis le ZIP B puis retour explicite à A ; santé négative injectée puis restauration de A ; interruption pendant la santé puis reprise vers A.
- **DEV :** installation depuis le ZIP B puis retour explicite à A.

Chaque scénario produit deux tentatives de santé, soit huit, dont les échecs attendus des scénarios négatifs. Les packs sources, les ZIP et la configuration sentinelle extérieure restent inchangés. Le ZIP contrôlé par la transaction est celui archivé par la campagne. Ces essais qualifient les transactions et les binaires ; ils ne remplacent pas un parcours d’installation effectivement confirmé depuis le bouton de maintenance.

## Livrables et identités

| Livrable | Téléchargement |
|---|---|
| PROD | [Artefact 12730361970](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12730361970) |
| DEV | [Artefact 12729157837](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729157837) |
| Journaux complets, captures et preuves | [Artefact 12729422738](https://github.com/M4D135/pesto/actions/runs/40491875705/artifacts/12729422738) |

Expiration GitHub : **26 novembre 2026**. Extraire l’enveloppe GitHub puis le ZIP candidat qu’elle contient. Le pack conserve `Pesto.exe` et `wad/` à la racine, et le déblocage sous `wad/support/DEBLOQUER_TOUT.cmd`. Les packs restent candidats, `official=false`, `distribution=candidate`, `qualification=unqualified` ; aucune release V1 n’est remplacée.

| Élément | SHA-256 |
|---|---|
| ZIP candidat PROD intérieur | `6a10bf715390aaa4fa210cd1839ad1dad1e845d4d086bf0db96422f4645ab1cc` |
| ZIP candidat DEV intérieur | `aa33ec85b161216b61a89fd81746611903ddd9ead84abe0cf47ae415141a8710` |
| EXE commun PROD/DEV | `0d8e8936060098fffc25f7b807e14546b25df7244775abe7a3dcdee4ebb4bba8` |
| EXE de base de52731 | `62c1786a7ec3b5321520943740699ceece6c4a39ceae11c9d1c93bcb170d4a6c` |

Ces valeurs sont distinctes des digests des enveloppes GitHub conservés dans [github-artifacts.json](github-artifacts.json). L’enveloppe complète des preuves a été téléchargée et son SHA-256 recoupé : **3 520 579 octets**, `e4b250b6ebf8276e8955da7f11d3a23f4896a2459f0f49dcd8ace51c7d50cadb`. Les deux grosses enveloppes binaires n’ont pas été retéléchargées localement ; leurs empreintes de ZIP/EXE sont celles produites par la CI et recoupées dans les transactions natives.

## Pièces et vérification indépendante

[summary.json](summary.json) conserve les comptes, les limites et les empreintes avant/après des **34 pièces copiées de l’archive** : huit JSON natifs, 24 journaux, le runtime et les identités des candidats. Seules leurs fins de ligne CRLF sont normalisées en LF ; les autres octets sont conservés. Les métadonnées GitHub sont sérialisées séparément avec une seule fin de ligne finale. Les extraits datés du journal ne constituent pas le journal complet, disponible dans l’artefact.

La [vérification indépendante](independent-validation.json) recoupe les huit preuves, le schéma et les noms des 36 contrôles, les neuf dialogues, les six chemins avant IO, les captures, les compteurs nuls, les commits et les empreintes des sources/ZIP/EXE. Les empreintes du pack de configuration et du candidat des transactions correspondent dans chaque canal. `SHA256SUMS` couvre tous les fichiers de ce dossier à l’exception du manifeste lui-même.

Les échecs [d803d72](../windows-d803d72-failed/README.md) et [1dbdda1](../windows-1dbdda1-failed/README.md) restent inchangés et attachés à leurs binaires. Cette campagne ne qualifie **ni AD réel, ni UNC réel, ni UAC réel**, ni l’accès au profil Pesto ordinaire de l’opérateur. Les preuves de laboratoire C14 conservent leur attribution d’origine.
