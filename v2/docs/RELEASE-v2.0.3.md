# Release Pesto V2 2.0.3 — 29 octobre 2026

**Release :** [v2.0.3](https://github.com/M4D135/pesto/releases/tag/v2.0.3), publique.
**Source exacte :** `7402483078001a3ad7efbfb875de18cd6778df89` (tag `v2.0.3`).
**Campagne officielle :** [40900470004](https://github.com/M4D135/pesto/actions/runs/40900470004), tentative 1 :
`windows-critical` puis `publish-release` réussis. Code identique à la campagne candidate
[40893218916](https://github.com/M4D135/pesto/actions/runs/40893218916) (`59ff059`), réussie, hors numéro de version.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.3.zip` | 370 745 054 | `b573b1230d734cd054971b1ae73535b2877993c3569d53bef41af29d834a623e` |
| `Pesto_V2_DEV_2.0.3.zip` | 387 283 854 | `ed13ebf9fc71ae4d13763f119a1f8b064f09ed1743cdd5135003be3b4c6446ac` |
| `Pesto_V2_Windows_evidence_2.0.3.zip` | 3 797 214 | `d7a0ac929a8c70ac19ba282ef3fd45e9728db73618b1a56dc88e936ca9788837` |
| `release-manifest.json` | 3 240 | `2010eb64419cf1d3553cac6c4b130b43ad53864158832bd47066433dcad2f82a` |
| `SHA256SUMS` | 369 | `e9e7a5858fb55322b9e4c588f8539cfead216be1851874ff477394a96e5cefe4` |

`Pesto.exe` commun PROD/DEV : `5e0fe693dc26b14fa55ca070909a84f6dbfec9a8a6b17e9b29caa0f19dd2fcce`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.3`, `official: true`,
`qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changement depuis 2.0.2

- **Version du moteur réelle.** Accueil, Aide et barre de marque affichaient « 2.0.0-dev » dans toutes les versions.
  Le moteur réel, la démonstration et la jonction hors ligne indiquent désormais la version inscrite dans le build,
  identique à celle du pack ; la simulation de navigateur, sans pack, indique « simulation navigateur ».

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur (dont 3 nouveaux sur la version) / pont / gardes de restauration AD | 628/628, 15/15, 105/105 |
| Fabrication / publication portables | 63/63 et 50/50 |
| Installation depuis les boutons, puis retour par le service | **v2.0.2 publiée → 2.0.3**, PROD et DEV réussis |

## Observé ensuite sur la VM de recette

- Mise à jour 2.0.2 → 2.0.3 depuis les boutons (GitHub officiel, préparation, confirmation, UAC réelle) : « contrôle de
  santé confirmé », configuration conservée, `Pesto.exe` = `5e0fe693…` ; l’accueil affiche « moteur 2.0.3 ».
- **Retour binaire depuis le bouton « Revenir à la version précédente »**, détaillé dans la
  [recette VM](VALIDATION-VM-20261029.md) : 2.0.2 rétablie, contrôle de santé réussi, paramètres conservés.

Le manifeste de release garde `nativeRollbackUiQualified: false` : ce champ décrit la campagne Windows automatisée,
pas la recette manuelle en VM.
