# Release Pesto V2 2.0.6 — 30 octobre 2026

**Release :** [v2.0.6](https://github.com/M4D135/pesto/releases/tag/v2.0.6), publique.
**Source exacte :** `0cbdf3a66ef243e6fda6d74b8d92b57861f058f4` (tag `v2.0.6`).
**Campagne officielle :** [41024785514](https://github.com/M4D135/pesto/actions/runs/41024785514), tentative 1 :
`windows-critical` puis `publish-release` réussis. Même commit que la campagne candidate
[41021070973](https://github.com/M4D135/pesto/actions/runs/41021070973), réussie.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.6.zip` | 370 758 986 | `c3fd520e62d7e0ed3807670abef6b57cfc17dc8a195e3b321259aa04b2031331` |
| `Pesto_V2_DEV_2.0.6.zip` | 387 317 129 | `3ca3516371c69528d9e10569dd074534004a3225074d7e599a75d5b3946ff0fa` |
| `Pesto_V2_Windows_evidence_2.0.6.zip` | 3 805 202 | `ae96d7fae8a996cb315ccc861a33fecc189727c22bc8ee2ce5958544d0752efc` |
| `release-manifest.json` | 3 240 | `e04f10ec03a48ab24f26e5f3049ee957867f2f1569292cd5cf80680831b0a255` |
| `SHA256SUMS` | 369 | `678a4a26637252c3fbb9cedc0dafa53e981fe8fbb574095f1474ef4671b92264` |

`Pesto.exe` commun PROD/DEV : `2c0920d7a37eedb619c117e6ca97e118862639ab405a81035d6d76eee21da4f6`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.6`, `official: true`,
`qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changement depuis 2.0.5

- **Page « Un poste » :** à la demande de David après son essai en démonstration du 30 octobre, retour du choix de la V1 (case « Un autre poste du domaine », `ChkRemote`). Champ « Poste concerné » : « Ce poste (NOM) » par défaut, ou « Un autre poste du domaine ». Ce poste : identité lue directement, sans recherche ; le moteur traite déjà ce nom comme la cible locale (`Rename-Computer` sur place, aucun appel distant), il n’a pas changé. Un autre poste : la recherche bornée apparaît. Changer de choix efface la sélection précédente, pour qu’aucune action n’atteigne l’autre poste ; pendant une opération, le choix reste verrouillé. Un poste encore hors domaine est renvoyé vers « Ajouter ce PC au domaine », sans lecture AD. La carte s’intitule « Poste à modifier », comme en V1.
- **Exemples de noms retirés.** Les exemples de noms (`P111301…`) sont retirés des champs de recherche de « Un poste » et « Plusieurs postes » et de la liste collée de « Plusieurs postes ».

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur / pont / gardes de restauration AD | 639/639, 15/15, 105/105 |
| Fabrication / publication | 63/63 et 50/50 |
| Parcours métier navigateur | 57/57 |
| Démonstration DOM (dont 2 nouveaux contrôles : ce poste par défaut lu sans recherche puis bascule et retour ; poste hors domaine renvoyé vers la jonction, champs sans exemple) | 13/13 |
| Maintenance | 47/47 |
| Liste fermée du pont | 151/151 |
| Installation depuis les boutons, puis retour par le service | **v2.0.5 publiée → 2.0.6**, PROD et DEV réussis |

Sept suites navigateur choisissent désormais « Un autre poste du domaine » avant de chercher. Vérification : changement d’interface seul. Le manifeste garde `nativeRollbackUiQualified: false`.

## Vérification hors CI

- Pas de nouvelle recette en VM : le parcours moteur du poste local est celui déjà prouvé sur l’AD réel le 29 octobre (renommage et retour du poste de la VM par les boutons, voir la [recette VM](VALIDATION-VM-20261029.md)), et la session locale de la VM PESTO ne lit pas l’AD.
- Captures de la démonstration hors dépôt (`demo-206-unposte-*.png`, dossier `release-final-20261028`) : ce poste joint lu automatiquement, autre poste avec recherche sans exemple, poste hors domaine.
