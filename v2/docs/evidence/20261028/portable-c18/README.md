# C18 — preuves portables collectées le 28 octobre 2026

Ce dossier conserve les journaux existants du travail sur les confirmations, l’identité des reçus et la simulation. Le [rapport C18](../../../VALIDATION-C18-20261028.md) détaille les résultats et leurs limites. Aucune suite n’a été relancée pour cette collecte.

Le candidat est un **arbre de travail non commité**, basé sur `e087bb16aed175bc35906fa533e9cd172d2fdaca`. La base n’est pas l’identité du code modifié testé. Le [manifeste de collecte](collection-manifest.json) laisse `sourceCommit` à `null` : le commit final sera identifié avant la CI Windows. Les journaux n’étaient pas accompagnés d’un instantané immuable des sources ; les empreintes ci-dessous établissent l’intégrité des preuves copiées, pas un lien rétroactif avec un commit encore inexistant.

Le [résumé d’origine](workflow-reliability-summary.json) et les douze journaux ont été copiés **sans transformation d’octets** depuis `work/reprise-20261028/`. Le manifeste indique pour chaque copie sa provenance, sa taille et son SHA-256. Le fichier [SHA256SUMS](SHA256SUMS) couvre tous les fichiers de ce dossier sauf lui-même.

## Résultats finaux

| Suite | Contrôles réussis | Journal |
|---|---:|---|
| Moteur complet | 616/616 | [engine-all-sdk401-final.log](logs/engine-all-sdk401-final.log) |
| Compilation | 0 avertissement, 0 erreur | [engine-build-sdk401-final.log](logs/engine-build-sdk401-final.log) |
| Métier navigateur | 57/57 | [web-business-check-final-identity.log](logs/web-business-check-final-identity.log) |
| Actions opérateur | 41/41 | [operator-ui-check-final.log](logs/operator-ui-check-final.log) |
| Parité | 53/53 | [parity-ui-check.log](logs/parity-ui-check.log) |
| Réservations et coordination | 17/17 | [policy-ui-check.log](logs/policy-ui-check.log) |
| Démonstration DOM | 11/11 | [demo-dom-final-simulation.log](logs/demo-dom-final-simulation.log) |
| Web statique | 149/149 | [web-check-final.log](logs/web-check-final.log) |
| Démonstration JavaScript | 11/11 | [demo-engine-js-final.log](logs/demo-engine-js-final.log) |

Le moteur a été compilé et exécuté sur macOS arm64 avec le SDK **10.0.401** ; ce n’est pas une validation du SDK **10.0.302** fixé par `v2/global.json`, ni une validation Windows. Les parcours navigateur utilisent Chromium et des backends de test explicites, sans effets réels AD, SMB ou Windows.

## Régressions conservées

- [single-receipt-before.log](logs/single-receipt-before.log) : les cinq scénarios de reçu individuel incohérent échouent avant le contrôle d’identité ; ces cinq cas passent dans la suite métier finale.
- [engine-simulation-before.log](logs/engine-simulation-before.log) : un test échoue parce que le reçu de déplacement refusé ou incertain porte Paris, l’OU actuelle, au lieu de Lyon, l’OU prévue. La suite moteur finale contient le test corrigé et réussit à 616/616.
- [demo-simulation-before.log](logs/demo-simulation-before.log) : la carte de reçu refusé est absente avant correction. Les scénarios DOM finaux `denied` et `uncertain` vérifient le reçu du plan visible et le poste inchangé.

## Limites au moment de la collecte

La CI Windows C18 est encore attendue. **C17/e087bb1 reste le dernier binaire Windows vérifié.** Le harnais de restauration AD est en revue et **non exécuté** dans cette collecte ; ses gardes et sa recette native sont hors des totaux ci-dessus. Aucun pack C18, aucune restauration de VM et aucune qualification de production ne sont établis par ce dossier.
