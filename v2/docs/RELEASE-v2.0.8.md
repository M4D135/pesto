# Release Pesto V2 2.0.8 — 30 octobre 2026

**Release :** [v2.0.8](https://github.com/M4D135/pesto/releases/tag/v2.0.8), publique.
**Source exacte :** `aeb00259b3ef094e14c584559b788433aea38901` (tag `v2.0.8`).
**Campagne officielle :** [41104439245](https://github.com/M4D135/pesto/actions/runs/41104439245), tentative 1 : `windows-critical` puis `publish-release` réussis. Même commit que la campagne candidate [41099523697](https://github.com/M4D135/pesto/actions/runs/41099523697), réussie.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.8.zip` | 370 763 696 | `0fcbb2ce36c5ffc3acd146cbbdbd3ca76d6bba2b0bf56bcd837dfef262f494bf` |
| `Pesto_V2_DEV_2.0.8.zip` | 387 327 696 | `a094152ada77f59e86368a38708c32813e558bf4df2bedecd3ae6853d8537519` |
| `Pesto_V2_Windows_evidence_2.0.8.zip` | 3 814 500 | `15ce82b943f4bfc06089214731965951516eb29e841ab7dfd290ece3fd56c174` |
| `release-manifest.json` | 3 240 | `c771c2296c03b3c5501fc84c9242009823af955a031c31d55d0c9d3616f0af3a` |
| `SHA256SUMS` | 369 | `ea2db75463abb1c8556ac49ba649a641667c42e1023944acab46ecc756d0177c` |

`Pesto.exe` commun PROD/DEV : `2aa0b2458115aa6bfd9a364137f4826ea3c16f32cfde4d28a0d84a844659c4bf`.
Les cinq assets ont été téléchargés et revérifiés (`SHA256SUMS`, manifestes internes `2.0.8`, `official: true`, `qualification: unqualified`, `sourceCommit` exact, aucun `cfg.json`).

## Changement depuis 2.0.7

- **Contraste élevé Windows.** La passe accessibilité sur la VM de recette (2.0.7) a trouvé que, en contraste élevé (`forced-colors`), le point des boutons radio cochés et la coche des cases cochées étaient invisibles : on ne voyait pas, par exemple, si « Ce poste » ou « Un autre poste du domaine » était choisi. Les boutons pleins (principal, danger) n’avaient pas non plus de cadre.
- Corrigé par quatre règles `forced-colors` dans `shell.css` : point et case cochés aux couleurs système `Highlight` / `HighlightText`, cadre `ButtonText` des boutons pleins. Empreintes du kit UI rafraîchies (`ui-kit.lock.json`, `provenance.json`). Hors contraste élevé, l’apparence est inchangée.
- Aucun changement du moteur ni du pont.

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur / pont / gardes de restauration AD | 640/640, 15/15, 105/105 |
| Fabrication / publication portables | 63/63 et 50/50 |
| Parcours métier navigateur / DOM / opérateur | 58/58, 32/32, 41/41 |
| Maintenance navigateur / liste fermée du pont | 47/47 et 151/151 |
| Démo native : API réelles refusées | 45 par canal |
| Installation depuis les boutons, puis retour par le service | **v2.0.7 publiée → 2.0.8**, PROD et DEV réussis |

Aucun contrôle `forced-colors` n’a été ajouté à la CI : la correction a été vérifiée localement avec l’émulation `forced-colors` de Chromium, puis en VM. Le manifeste garde `nativeRollbackUiQualified: false`.

## Observé ensuite sur la VM de recette

- Mise à jour 2.0.7 → 2.0.8 depuis les boutons (GitHub officiel, préparation, confirmation) : « Mise à jour installée et contrôle de santé confirmé. La configuration utilisateur est conservée. » ; `Pesto.exe` = `2aa0b245…`, version 2.0.8.
- Démonstration en contraste élevé Windows : sur « Un poste », le bouton radio « Ce poste (NOUVEAU-PC) » apparaît coché, alors qu’en 2.0.7 aucun des deux choix ne semblait sélectionné. Accueil, Paramètres et « Ajouter ce PC au domaine » restent lisibles.
- Passe DPI sur 2.0.7, inchangée par cette release : 150 % et 200 % conformes, le menu se replie seul à 200 %.

## Limites

- Narrateur vérifié seulement en partie : arbre d’accessibilité lu, sans écoute (pas d’audio sur la VM).
- Un seul thème de contraste élevé (sombre) a été essayé ; les autres thèmes ne sont pas vérifiés.
