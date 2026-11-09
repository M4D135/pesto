# Pesto 1.0 — suivi facultatif après une commande acceptée

## Comportement

- Une commande acceptée avec redémarrage attendu ne force plus la consignation d’une vérification avant de préparer l’opération suivante.
- Les reçus et les codes d’origine restent conservés. Aucun reçu ne devient `Verified` automatiquement.
- Le bouton principal propose la préparation ordinaire. Le contrôle complémentaire reste accessible dans le suivi ; ces reçus n’alimentent plus l’alerte d’accueil des interventions à examiner.
- Les verrous partagés appartenant à une commande terminée sont libérés. Pour les anciens reçus, le nettoyage reste limité aux clés possédées par ce reçu et correspondant à la cible.
- Après jonction, Pesto relit l’identité du poste, son démarrage, le domaine, la concordance des noms Windows actuels et le canal sécurisé. Un renommage ultérieur légitime n’impose pas de conserver le nom de la jonction.
- Les opérations actives, partielles, incertaines, les protections non rétablies et les contrôles frais de la nouvelle cible conservent leurs barrières. Un nom Windows non encore appliqué nécessite toujours le redémarrage prévu.

## Portée de la validation

Build EXE : `b5e42115d2d0c740a1b5dc98bdc9798121ab678d18004abdc1313f565662c5f4`. Compilation native x64 sur Mac ; le binaire Windows n’est pas exécuté pendant cette passe.

| Contrôle | Résultat | Preuve |
| --- | --- | --- |
| Python, suite complète | 350 réussis, aucun échec ni ignoré | [rapport](python-tests.json), [sortie](python-tests.log) |
| PowerShell, moteur et workers | 350 contrôles réussis dans 8 suites, dont 83 sur le suivi facultatif | [synthèse et empreintes](engine/summary.json) |
| PowerShell, interface et routage | 126 contrôles réussis dans 4 suites, dont 16 sur le nouveau parcours | [détail](ui/README.md), [empreintes](ui/manifest.json) |
| Syntaxe PowerShell | 94 fichiers analysés, aucune erreur | [sortie du parseur](parse-all.log) |

Le premier passage Python a trouvé trois attentes devenues obsolètes : ancien libellé, canal contrôlé directement dans le worker plutôt que dans son helper, et consignation autrefois obligatoire. Les tests sont adaptés au nouveau contrat en gardant les assertions de sécurité. Le [premier résultat](python-initial.json) et sa [sortie](python-initial.log) sont conservés séparément ; la passe complète finale est réussie.

Les tests de cette passe sont exécutés sur macOS avec Python et PowerShell 7.4.20. Les bancs PowerShell chargent les fonctions réelles avec des doubles et des reçus temporaires ; ils ne réalisent aucune opération AD. La variante `-Wpf` de `Run-OptionalFollowupUiTests.ps1` exige Windows PowerShell 5.1 en STA.

L’hôte de la VM PESTO-W11-TEST est inaccessible pendant cette passe : voir [le constat d’accès](vm-availability.json). Aucun nouveau test Windows, parcours graphique ou ajout au domaine n’est revendiqué pour cette correction. L’[audit graphique précédent](../audit-2026-10-13/README.md) conserve son attribution à ses propres builds.

Les guides technicien et administrateur sont mis à jour en DOCX/PDF. Leur [contrôle de rendu](../guides-postop-2026-10-13/summary.json) est distinct d’une recette graphique de l’application. Les captures antérieures restent des illustrations ; aucune nouvelle capture de Pesto n’est fabriquée.

## Archives

Les [archives vérifiées](release-pack-verification.json) contiennent les mêmes octets que les sources contrôlées : PROD, 47 entrées ; DEV, 449 entrées avec les quatre guides et les deux nouvelles suites. Les deux configurations distribuées sont neutres. PROD conserve `Pesto.exe` et le dossier `wad/`.

Depuis la racine du dépôt, `shasum -a 256 -c packs/SHA256SUMS` contrôle les deux archives. Les [empreintes de livraison](summary.json) rattachent le build, les sources modifiées et les preuves à cette passe.

## Recette Windows complémentaire

Le constat d’inaccessibilité ci-dessus appartient à la passe locale initiale. Une [recette ultérieure sur le même build b5e42115](../recette-suivi-facultatif-2026-10-13/) a exécuté deux renommages réels : après le premier redémarrage et la réouverture de Pesto, le second est accepté sans consignation de la vérification précédente. Les deux redémarrages sont confirmés, avec noms Windows concordants, domaine et canal sécurisé valides. Les reçus contrôlés gardent leurs empreintes, leur phase PendingRestart et leur champ ObservedUtc vide. Les 12 suites Windows comptent 492 contrôles réussis, dont 18 WPF. Les résultats et leurs empreintes figurent dans ce dossier de recette distinct. Les rapports de la passe initiale restent inchangés.
