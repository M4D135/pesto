# Release Pesto V2 2.0.7 — 30 octobre 2026

**Release :** [v2.0.7](https://github.com/M4D135/pesto/releases/tag/v2.0.7), publique.
**Source exacte :** `f954ca19d42678ca7c1c75c5d67bab90aa439b6b` (tag `v2.0.7`).
**Campagne officielle :** [41037119110](https://github.com/M4D135/pesto/actions/runs/41037119110), réussie à la tentative 2. Tentative 1 : échec ponctuel du test de délai `EntraDiagnosticTaskTests.BlockedRpcIsBoundedAndCannotStartAnyLaterDiagnosticOrMutation`, sans rapport ; le même commit est vert en candidate [41032853737](https://github.com/M4D135/pesto/actions/runs/41032853737) avec 640/640.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.7.zip` | 370 761 304 | `b95fc2639979e60d9e90cd17c66ed29a618a242bad2daea3dd733127d60801d7` |
| `Pesto_V2_DEV_2.0.7.zip` | 387 322 508 | `6d28f04665ebe88371923819bbfdad9b6f947705b432e1a473e065225f7f225f` |
| `Pesto_V2_Windows_evidence_2.0.7.zip` | 3 677 907 | `d43f315629726918036cbb8e124fe9df3a91441ad7d5fcfc9d31f6402cf606dc` |
| `release-manifest.json` | 3 240 | `37f583ee33e5891a95254f841361e05d14b397675357654ab32cbb4564fc401a` |
| `SHA256SUMS` | 369 | `9d647083e4f18d8164bb08e3b406dc69f7c80f054b422340611684e9fb7f012b` |

`Pesto.exe` commun PROD/DEV : `ddd65a55efacf25e4697bb160098c01f422682413ac26a28c546bd9911146b4e`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.7`, `official: true`, `qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changement depuis 2.0.6

- En 2.0.6, « Un poste » déduisait l’appartenance au domaine de la capacité `join`. Dans le moteur réel, cette capacité dit seulement que la jonction est autorisée (politique, droits) : un poste joint était renvoyé à tort vers « Ajouter ce PC au domaine ». Signalé par David en démonstration (scénario « Poste déjà joint »).
- Désormais « Un poste » lit toujours ce poste dans l’annuaire et ne renvoie vers la jonction que si l’annuaire ne connaît pas son nom (`computer.missing`).
- La démonstration de l’application ferme la capacité de jonction quand le poste fictif est déjà joint (« Ce poste simulé a déjà rejoint le domaine. »), comme la simulation du navigateur : « Ajouter ce PC au domaine » ne propose plus de joindre un poste déjà joint.
- Tests ajoutés : un test moteur (capacité de jonction de la démonstration selon le scénario, lecture du poste local) et un contrôle navigateur (session réelle sur un poste joint, jonction autorisée : ce poste est lu d’office).
- La 2.0.6 ne doit pas être utilisée sur un poste réel joint.

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur / pont / gardes de restauration AD | 640/640, 15/15, 105/105 |
| Fabrication / publication | 63/63 et 50/50 |
| Parcours métier navigateur | 58/58 |
| Démonstration DOM (Chromium, sans qualification native Windows ; la démonstration ferme la jonction si le poste fictif est déjà joint) | 13/13 |
| Maintenance | 47/47 |
| Liste fermée du pont | 151/151 |
| Installation depuis les boutons, puis retour par le service | `v2.0.6` publiée → `2.0.7` réussie |

Ces totaux intègrent les nouveaux contrôles : capacité de jonction de la démonstration selon le scénario, lecture du poste local et session réelle sur un poste joint avec jonction autorisée. Les contrôles navigateur reposent sur des fixtures explicites, sans Windows/AD ; les contrôles de fabrication et de publication n’appellent pas GitHub, Windows ou l’AD.

## Vérification hors CI

- Pas de recette VM : interface et démonstration ; le parcours moteur du poste local est déjà prouvé sur l’AD réel le 29 octobre.
- `nativeRollbackUiQualified: false` reste au manifeste.
