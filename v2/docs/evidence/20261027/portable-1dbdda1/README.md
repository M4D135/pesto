# C16 — publication croisée et fabrication du correctif natif

Ces contrôles locaux concernent le contenu des trois fichiers natifs publié dans [`1dbdda1`](https://github.com/M4D135/pesto/commit/1dbdda1020cf21ea2c65fc69b5572bbfc857095e). La compilation s’est déroulée avant la création de ce commit, avec `HEAD` encore à `d803d72` et ces modifications dans le working tree. Les empreintes des trois sources sont consignées dans [summary.json](summary.json) et correspondent au commit publié. L’EXE local n’est pas présenté comme identique au futur EXE produit par Windows au nouveau commit.

- Publication croisée avec SDK **10.0.302**, cible **Windows x64 self-contained** : sortie **0**, [journal intégral](publish.log).
- Fabrication : **46/46 contrôles**, [journal final](pack-mechanics.log), runtime WebView2 factice explicitement déclaré ; aucune exécution Windows.
- Réassemblage du même PROD depuis l’arbre DEV livré, avec les mêmes entrées de publication et de runtime ; aucune recompilation depuis DEV dans cet essai.
- Les **299 fichiers documentaires** sont restés identiques entre le début et la fin du passage réussi et leurs empreintes correspondent toutes à `1dbdda1` ; [empreintes des entrées](pack-inputs.json).

Le [premier passage](pack-mechanics-during-document-edit.log) avait réussi 45 contrôles sur 46 ; seul le contrôle d’assemblage déterministe échouait pendant une édition concurrente des métadonnées documentaires de la preuve Windows précédente. Ce passage n’est pas le verdict final. La relance sur les entrées figées réussit tous les contrôles.

La publication croisée et la fabrication n’exécutent ni les dialogues Windows ni une opération AD. Le [rapport C16](../../../VALIDATION-C16-20261027.md) donne séparément le verdict de la campagne Windows du correctif. `SHA256SUMS` couvre les pièces de ce dossier.
