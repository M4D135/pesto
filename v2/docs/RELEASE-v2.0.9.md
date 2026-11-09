# Release Pesto V2 2.0.9 — 1er novembre 2026

**Release publiée : [v2.0.9](https://github.com/M4D135/pesto/releases/tag/v2.0.9).** Source exacte : `ee40af18458ae0bb604f02665a6f4e2df57d7378`.

La [campagne officielle 41284549253](https://github.com/M4D135/pesto/actions/runs/41284549253), tentative 1, a réussi ses deux jobs `windows-critical` et `publish-release` sur le runner Windows `pesto-lab`, lancé à la demande. Les cinq assets ont ensuite été téléchargés et vérifiés indépendamment ; [résultat et empreintes](evidence/20261101/release-2.0.9/download-verification.json).

## Fichiers publiés

| Fichier | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_DEV_2.0.9.zip` | 386 593 486 | `f58cee11f9f3232540bb075342194f888ecc3f82c78571b889a9e0f66091672a` |
| `Pesto_V2_PROD_2.0.9.zip` | 370 532 742 | `605052194e31db5dc48af50384a0596034ab55fb6397662be73804f8ec94eb34` |
| `Pesto_V2_Windows_evidence_2.0.9.zip` | 4 121 087 | `33f979dfb569750356e57c90c1106d77fc57d1192deab4e144072bf670a634ae` |
| `release-manifest.json` | 3 240 | `bc6dcb83a1bc6cb0ee5f80362208c1b84dc2929530e1d494e4da4acdf4738a20` |
| `SHA256SUMS` | 369 | `02812ed8354b5038fa9cbb66382912b9684e0bdaa60ecf65a08ada7dd77d3ad0` |

`Pesto.exe` commun aux deux canaux : `885c693cd863008a96aa31d4835d863aecf6f412210664faafc6bf5d13833b44`.

Le contrôle après téléchargement recoupe les digests GitHub, `SHA256SUMS`, les manifestes, le tag, la campagne et sa tentative, le manifeste du transfert local, chaque preuve transportée, les sources web/DEV du commit et l’icône native au fond vert pastel. Les deux packs passent leur vérification d’inventaire. Aucun `cfg.json` ni archive historique de preuves n’est livré dans les packs.

## Changements depuis 2.0.8

Le poste local est maintenant distingué selon son appartenance au domaine lue par Windows. Un poste hors domaine reçoit l’indication d’utiliser « Ajouter ce PC au domaine », sans recherche inutile de son nom dans l’annuaire. S’il est membre du domaine mais que son compte n’est pas trouvé, Pesto demande de vérifier le compte dans l’AD ; il ne suggère pas une nouvelle jonction.

Les refus décidés par les pages affichent leur motif au lieu du message générique d’erreur interne. Le look et les animations validés sont conservés.

Les packs conservent leurs guides et les sources nécessaires à la reconstruction. Les archives de preuves historiques restent accessibles dans GitHub au commit source ; leur retrait des nouveaux packs évite le chemin trop long observé lors de l’extraction DEV sous Windows PowerShell 5.1.

L’écriture du journal de mise à jour tolère désormais un fichier temporairement retenu par Windows. Le remplacement reste atomique : l’ancien journal est conservé jusqu’à la publication du nouveau, et un refus persistant reste signalé comme un échec. Le lecteur de preuves ferme aussi le fichier avant d’analyser son contenu.

La fabrication dispose aussi d’un outil de changement de version et d’un runner Windows de secours lancé uniquement à la demande. Le banc natif observe les journaux aux moments où l’ancien programme ne les modifie plus. Il conserve les contrôles des fichiers, des reçus de santé et de la restauration ; le détail des limites de temps est documenté dans le guide de qualification Windows.

La campagne de publication conserve deux étapes distinctes sur le portable labo. Après tous les tests, les archives sont transférées localement avec un manifeste dont l’empreinte passe par GitHub. La publication contrôle encore le succès de la campagne et les cinq fichiers avant de rendre la release disponible ; ce transport évite de dépendre du quota des artefacts Actions.

## Résultats de cette campagne Windows

| Contrôle | Résultat |
|---|---|
| Moteur / pont | 644/644 et 15/15 |
| Fabrication / publication / transfert local | 69/69, 50/50 et 54/54 |
| Régressions navigateur | 19 suites réussies |
| Configuration, saisie native et démonstration | Parcours natifs réussis avec profils isolés |
| Reconstruction depuis les seules sources du DEV livré | Compilation et démarrage réussis |
| PROD depuis la base `de527313` | Installation et retour, échec de santé avec restauration, interruption avec reprise : réussis |
| DEV depuis la base `de527313` | Refus explicite du nouveau format avant remplacement : réussi ; nouvelle installation requise |
| Depuis les packs publiés 2.0.8, PROD et DEV | Installation de 2.0.9 depuis les boutons, puis retour distinct par le service : réussis |

Le rapport Windows complet est joint à la release. Le [guide de qualification](QUALIFICATION-WINDOWS.md) décrit les gardes, la lecture des journaux et les limites de temps du banc. Les essais isolés antérieurs restent liés à leur ancien commit ; ils ne sont pas présentés comme la qualification de ce build.

## Périmètre et limites

La release garde `official: true`, `distribution: official`, **`qualification: unqualified`** et `adQualified: false`. Cette campagne ne qualifie ni l’AD réel, ni l’UAC réel, ni un partage UNC réel, ni le retour arrière depuis le bouton UI. Les essais VM sont différés ; aucun résultat historique n’est transféré à ce nouvel EXE.

La campagne candidate hébergée par GitHub [41284542116](https://github.com/M4D135/pesto/actions/runs/41284542116) s’est arrêtée sur le quota de stockage avant les tests. La publication officielle ci-dessus utilise le même commit et tous les contrôles Windows, avec un transport local vérifié entre les deux jobs. L’ancienne validation V1 [41284541947](https://github.com/M4D135/pesto/actions/runs/41284541947) est distincte et n’est pas annoncée réussie par ce rapport.

Les 116 anciens ZIP de fabrication retirés avec l’accord de David sont documentés dans le [reçu de nettoyage](evidence/20261101/github-artifact-cleanup/verification.json). Les releases et les preuves Windows ont été conservées.
