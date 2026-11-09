# Release Pesto V2 2.0.5 — 30 octobre 2026

**Release :** [v2.0.5](https://github.com/M4D135/pesto/releases/tag/v2.0.5), publique.
**Source exacte :** `5263b540c315ea42a66c5bb26d4eb6b811decfe9` (tag `v2.0.5`).
**Campagne officielle :** [40963727506](https://github.com/M4D135/pesto/actions/runs/40963727506), tentative 1 :
`windows-critical` puis `publish-release` réussis. Même commit que la campagne candidate
[40959404149](https://github.com/M4D135/pesto/actions/runs/40959404149), réussie.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.5.zip` | 370 755 619 | `61181f7e4c5690b57a562c55a8143d810fc3898e5c1ec2c913faec2107f26ac4` |
| `Pesto_V2_DEV_2.0.5.zip` | 387 309 174 | `0bb492514d77f8991e85af1afe2861575a3adace8a6317cd0466e078b674199b` |
| `Pesto_V2_Windows_evidence_2.0.5.zip` | 3 808 257 | `42bbad11bfce7cbe0963a777fe96de52c544e595e505bed79fa94ea35356d75c` |
| `release-manifest.json` | 3 240 | `40c3a42a99b14a9102b1626a876b5f2538de9816b5fd800881a4ba0cb2952eda` |
| `SHA256SUMS` | 369 | `9400314fbfc86f5e67223cfc0a05020ebfc48fb63f350543eda83a71d47fd843` |

`Pesto.exe` commun PROD/DEV : `f1d05fe8e5ba9cadd8826f5a00089f1be16c681726d0b32d530788a4c562c61e`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.5`, `official: true`,
`qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changement depuis 2.0.4

- **Fenêtre tenue par une boîte de dialogue Windows.** Tant qu’une boîte de dialogue Windows (sélecteur de fichier,
  message) est ouverte, Windows tient sa fenêtre désactivée et ne lui transmet pas la demande de fermeture. Une
  telle fenêtre est désormais signalée d’avance, avec son motif, avant toute confirmation : rien n’est fermé ni
  modifié.
- **Demande renouvelée, refus exact.** Si une boîte de dialogue s’ouvre après la confirmation, la demande est
  renouvelée jusqu’à sa fermeture. Un refus après 30 s distingue les fenêtres qui ont reçu la demande (« leur
  fermeture reste demandée ») de celles qui n’ont pas pu la recevoir ; il ne prétend plus qu’une demande non
  transmise est en attente. Corrige la limite connue de 2.0.4.

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur (dont 3 nouveaux) / pont / gardes de restauration AD | 639/639, 15/15, 105/105 |
| Fabrication / publication portables | 63/63 et 50/50 |
| Maintenance navigateur / liste fermée du pont | 47/47 et 151/151 |
| Démo native : API réelles refusées | 45 par canal |
| Installation depuis les boutons, puis retour par le service | **v2.0.4 publiée → 2.0.5**, PROD et DEV réussis |

Ce banc exécute pour la première fois l’interface 2.0.4, qui interroge `updates.windows` avant d’installer. Le
manifeste garde `nativeRollbackUiQualified: false`.

## Observé ensuite sur la VM de recette

- Mise à jour 2.0.2 → 2.0.5 depuis les boutons : « contrôle de santé confirmé », configuration conservée,
  `Pesto.exe` = `f1d05fe8…` ; l’accueil affiche « moteur 2.0.5 ».
- Fenêtre `--settings` (processus 6656) avec la boîte « Exporter les paramètres partageables » ouverte : le bouton
  « Revenir à la version précédente » de la fenêtre principale n’a ouvert **aucune confirmation** et a affiché
  « Pesto ne peut pas fermer lui-même : « Pesto v2 — PROD — Annuaire (processus 6656) » (une boîte de dialogue
  Windows y est ouverte). Fermez-les puis recommencez ; rien n’a été modifié. »
- Boîte de dialogue annulée, même bouton : la confirmation nomme la fenêtre (processus 6656) ; après « Fermer et
  restaurer », elle se ferme et 2.0.2 est rétablie avec contrôle de santé réussi (`40bdf062…`, transaction
  `2e2ac770…` `rolledBack`), sans événement de plantage ni de blocage. Détail dans la
  [recette VM](VALIDATION-VM-20261029.md).
- Non observé en VM : une boîte de dialogue ouverte entre la confirmation et la fermeture (couvert par les tests
  du moteur).
