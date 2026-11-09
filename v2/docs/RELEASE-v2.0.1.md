# Release Pesto V2 2.0.1 — 29 octobre 2026

**Release :** [v2.0.1](https://github.com/M4D135/pesto/releases/tag/v2.0.1), publique.
**Source exacte :** `062c59535e2e721ce2ee4c594b2935f56f3e7ba0` (tag `v2.0.1`).
**Campagne officielle :** [40823673562](https://github.com/M4D135/pesto/actions/runs/40823673562), tentative 1 :
`windows-critical` puis `publish-release` réussis. Les ZIP publiés sont les octets testés par ce run.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.1.zip` | 370 745 443 | `b447e12e991a1517b769521e51d155d95e3f506918de092caf53e08d796c6db3` |
| `Pesto_V2_DEV_2.0.1.zip` | 387 282 221 | `36fcff6160256688ad689cd65e7368019aa407233037f86b76d8f5f55ea52c7e` |
| `Pesto_V2_Windows_evidence_2.0.1.zip` | 4 273 858 | `f8dfe881d159481207d9ca4d0549cc73b87a35aa62ab43200123c1b9eee3cfda` |
| `release-manifest.json` | 3 240 | `7183d4fa1e1f25db1455594afba90f3273c0e319df77d144d198ac9fc99740ea` |
| `SHA256SUMS` | 369 | `b33e793702040e0cb6fdfebf24b108661b62486d1d3e074ad70d57d88ba9a91e` |

`Pesto.exe` commun PROD/DEV : `1e3872abdc9df3e03306ec8adb48d525286ca73caa2d9a8f41ba25eb29b550f4`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.1`, `official: true`,
`qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changements depuis 2.0.0

Interface uniquement ; moteur, pont et règles métier inchangés.

- **Ajouter ce PC** : le formulaire du compte AD précréé n’apparaît plus quand la politique l’interdit, et le
  formulaire ordinaire se masque en mode précréé (un formulaire du kit portant `hidden` restait affiché). Le reçu
  de la jonction s’affiche après confirmation (il restait à opacité nulle) ; l’écran se verrouille ensuite et
  demande de redémarrer puis de vérifier dans Interventions. Un échec de lecture des sites propose « Réessayer ».
- **Menu** : bouton de repli harmonisé avec Domenia, FILPRO et GLPI — ligne « Replier le menu » en déplié,
  icône seule en replié — dans un pied toujours visible ; entrées non écrasées en fenêtre basse ; focus clavier
  jamais caché sous le pied ; poignée de largeur fonctionnelle ; infobulles du rail lisibles ; aucune préférence
  modifiée en silence quand la fenêtre impose le rail replié.
- **Reçus** : toutes les cartes de reçu ajoutées après l’affichage d’une page sont visibles (Un poste, Attributs,
  jonction hors ligne, réservations, lots).
- **Suivi** : Accueil affiche « — » et non de faux zéros si la lecture échoue ; libellés français au lieu des
  codes internes ; listes de recherche invalidées après un renommage ou un lot ; filtre d’Interventions par
  libellés français ; champs de filtre pleine largeur ; erreurs de Paramètres amenées à l’écran et annoncées ;
  « Détail moteur » conserve le focus.

51 contrôles navigateur ajoutés (`gui-rail`, `gui-join`, `gui-follow`, `gui-receipts`), chacun en échec sur 2.0.0 ;
exécutés en simulation Chromium hors CI.

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur / pont / gardes de restauration AD | 617/617, 15/15, 105/105 |
| Fabrication / publication portables | 63/63 et 50/50 |
| Contrôles navigateur exécutés par la CI | web 150/150, DOM 32/32, opérateur 41/41, métier 57/57, … |
| Mise à jour PROD et DEV depuis `de527313` | en place (`normal`, `health-failure`, `interruption`) |
| Installation depuis les boutons, puis retour par le service | **v2.0.0 publiée → 2.0.1**, PROD et DEV réussis |

Le banc d’installation depuis les boutons installait auparavant le build de référence `de527313` depuis le build
courant ; avec 2.0.1 ce serait un retour de version, refusé à juste titre par le produit. Il part désormais des
archives v2.0.0 publiées (empreintes épinglées dans le workflow), qui installent 2.0.1 depuis leurs boutons.

## Limites

**Qualification AD partielle, recette VM du 29 octobre.** UAC réelle, saisie native du compte AD, jonction par les
boutons, mise à jour 2.0.0 → 2.0.1 depuis les boutons, renommage + déplacement (CLI) et retour arrière AD par les
boutons sont prouvés sur l’AD du laboratoire ; voir [VALIDATION-VM-20261029.md](VALIDATION-VM-20261029.md). Le
retour binaire depuis le bouton de l’interface et les autres limites listées dans ce rapport restent à qualifier. Les correctifs C# éventuels de recherche par libellé et
de « Autre nom » déterministe ne concernent que la simulation navigateur.
