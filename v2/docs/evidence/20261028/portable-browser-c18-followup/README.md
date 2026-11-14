# C18 — seize suites navigateur après correction du banc de reprise

Les **16 suites du groupe navigateur de la CI passent localement** après correction de `web-recovery-check.mjs`. La suite de reprise passe de **15/23 sous Windows sur 07dc741** à **23/23 en fixture Chromium locale**. Le test vérifie maintenant l’absence de recopie, le nom exact affiché, l’absence d’envoi avant clic et le `confirmationName` exact transmis une seule fois. Les assertions d’annulation, de lien parent/enfant et d’absence de succès optimiste sont conservées.

La [correction du test](recovery-test.patch) est la seule modification de code après `07dc74116478f1dd28d5f54ab6e2f11b1b4ee472` dans ce relevé ; aucun code produit n’a changé. Son [manifeste](collection-manifest.json) conserve l’empreinte du fichier corrigé et `sourceCommit: null`, car la nouvelle source n’est pas encore commitée au moment de la collecte. Cela ne remplace pas la nouvelle campagne Windows attendue.

| Suite | Résultat |
|---|---:|
| Maintenance | 41/41 |
| Opérateur | 41/41 |
| Métier | 57/57 |
| Parité | 53/53 |
| Policy | 17/17 |
| Reprise | 23/23 |
| DOM | 32/32 |
| Mise en page | 8/8 |
| Démonstration DOM | 11/11 |
| Login DOM | 28 contrôles, succès |
| Web statique | 149/149 |
| Cycle du pont | 21/21 |
| Démonstration JavaScript | 11/11 |
| AZERTY | 21/21 |
| Watcher | 44/44 |
| Verdict du watcher | Succès, sortie 0 |

Le [résumé d’origine](summary.json) et les seize [journaux](logs/web-recovery-check.log) sont copiés sans transformation depuis `work/reprise-20261028/browser-ci-followup-07dc741/`. [SHA256SUMS](SHA256SUMS) couvre tous les fichiers de ce dossier sauf lui-même. La collecte ne relance pas les tests.

Il s’agit de fixtures sur macOS : aucune UAC réelle, mutation AD, opération SMB ou qualification native Windows. L’[échec Windows initial](../windows-07dc741-failed/README.md) demeure conservé ; aucun verdict rétroactif ne lui est attribué.
