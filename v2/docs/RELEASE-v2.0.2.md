# Release Pesto V2 2.0.2 — 29 octobre 2026

**Release :** [v2.0.2](https://github.com/M4D135/pesto/releases/tag/v2.0.2), publique.
**Source exacte :** `c4c3d671aa6bf3fe7454d8d67b4ba6f231b3262f` (tag `v2.0.2`).
**Campagne officielle :** [40865020178](https://github.com/M4D135/pesto/actions/runs/40865020178), tentative 1 :
`windows-critical` puis `publish-release` réussis. Campagne candidate préalable sur la même source :
[40857032213](https://github.com/M4D135/pesto/actions/runs/40857032213), réussie.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.2.zip` | 370 741 986 | `d515cd7a3df1fdc6d05db378a5c55cf3c7a625a7ac63e3180542eaf651692f20` |
| `Pesto_V2_DEV_2.0.2.zip` | 387 276 113 | `fad77a96e1e120bb155d9460d8514bdaa0197c2033c55bd7307690e1ed0b468e` |
| `Pesto_V2_Windows_evidence_2.0.2.zip` | 3 742 461 | `066dbc66225707e2fe73db90534b00d02c69cfb747d7f3a3ccae881c46b2dbaa` |
| `release-manifest.json` | 3 240 | `f7ab9c3e5e76915b7d385a27e2195c0097dd8d4a217ab8d37beb1360b9d390e9` |
| `SHA256SUMS` | 369 | `116254c8c13eb3daf70a4805260f0a9e2bb9eb3ebb1ed98ef883aab95a260a0d` |

`Pesto.exe` commun PROD/DEV : `40bdf062d56494cd149726772feb7f5d734c8f7f7587a401edd23d487fbccb23`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.2`, `official: true`,
`qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changements depuis 2.0.1

Issus de la [recette VM AD réelle du 29 octobre](VALIDATION-VM-20261029.md).

- **UAC dès le lancement, comme en V1.** L’écran « Connexion » affiché avant l’UAC est supprimé (fenêtre, page web,
  qualification `--qualify-welcome`/`--qualify-uac` et étape de CI). Seule l’intégrité du pack est contrôlée avant la
  demande Windows. Une annulation ou un échec ouvre une boîte native **Réessayer / Fermer** ; rien n’est relancé sans
  ce choix. Après l’UAC, le comportement est inchangé : identité Windows sur un poste joint, saisie native hors domaine.
- **Sonde Windows PowerShell 5.1 patiente.** Elle attend jusqu’à 60 s (au lieu de 10 s) et, après un échec, sonde de
  nouveau 30 s plus tard au lieu de refuser toute la session ; un moteur confirmé reste mémorisé.
- **`--cli verify --receipt ID`.** Même contrôle que **Interventions → Vérifier l’état** : relecture AD et Windows,
  passage à `Verified` seulement si toutes les preuves concordent. Codes `0` vérifié, `3010` redémarrage encore
  attendu, `97` incertain, `96` refus ; aucune opération rejouée, aucun journal idempotent. Exige
  `UnattendedOperationsEnabled` ou `UnattendedJoinEnabled` sans interdiction HKLM. Voir [CLI.md](CLI.md).
- **CI** : l’installation depuis les boutons part désormais de la v2.0.1 publiée (archives épinglées) ; les suites
  navigateur `gui-rail`, `gui-join`, `gui-follow` et `gui-receipts` font partie de la campagne Windows.

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur (dont 5 démarrage et 5 `verify` nouveaux) / pont / gardes de restauration AD | 625/625, 15/15, 105/105 |
| Fabrication / publication portables | 63/63 et 50/50 |
| Suites navigateur exécutées par la CI | web 150/150, menu 19/19, jonction 16/16, suivi 9/9, reçus 7/7, … |
| Mise à jour depuis `de527313` | PROD en place ; DEV refus explicite qualifié (nouvelle installation), inchangé |
| Installation depuis les boutons, puis retour par le service | **v2.0.1 publiée → 2.0.2**, PROD et DEV réussis |

## Limites

**Observé ensuite sur la VM de recette (poste joint `labo.local`) :** mise à jour 2.0.1 → 2.0.2 depuis les boutons
(GitHub officiel, préparation, confirmation, UAC réelle, « contrôle de santé confirmé », configuration conservée,
`Pesto.exe` = `40bdf062…`) ; au lancement suivant, l’invite UAC apparaît directement, sans écran intermédiaire ;
un refus affiche « Pesto n’est pas ouvert » avec **Réessayer / Fermer** ; Réessayer redemande l’UAC et Pesto s’ouvre
sous l’identité Windows effective. Retour binaire depuis le bouton de l’interface,
plusieurs DC, DPI/accessibilité et signature du lanceur restent à qualifier. Les manifestes publiés gardent
`qualification: unqualified`.
