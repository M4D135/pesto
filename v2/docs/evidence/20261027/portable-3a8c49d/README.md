# C16 — correctif du contrôle natif de dossier

Le contenu corrigé de `NativeConfigurationQualification.cs` est publié dans [`3a8c49d`](https://github.com/M4D135/pesto/commit/3a8c49d85d5cc16dcab2d7c743be7fa445d05715). Sa publication croisée avec le SDK **10.0.302**, cible **Windows x64 self-contained**, termine avec une sortie **0** : [journal intégral](publish.log), [synthèse et empreinte source](summary.json).

La compilation locale précédait le commit : `HEAD` était encore à `1dbdda1`, avec la correction dans le working tree. Le fichier source compilé correspond au commit `3a8c49d` ; l’EXE local n’est pas présumé identique au futur binaire construit par Windows à ce commit. Ce contrôle ne lance ni dialogue Windows ni opération AD.

Le sélecteur de dossier emploie désormais uniquement le contrôle `Edit` **1152** observé dans la deuxième preuve d’échec. Les sélecteurs de fichiers conservent **1001/1148** ; la barre d’adresse **41477** reste exclue. Les gardes de focus, d’unicité, de saisie, de relecture stable et de portée avant lecture/écriture hôte restent identiques. Aucune des 36 assertions n’est retirée.

Le workflow exécute le banc de configuration juste après le runtime et l’assemblage. Les [18 étapes avant/après](workflow-order.json), analysées en YAML, forment exactement le même multiensemble : seules leurs positions changent. Toutes les régressions et transactions demeurent requises avant publication des candidats. La relecture indépendante confirme ces dépendances ; le verdict natif doit venir de la nouvelle campagne indiquée dans le [rapport C16](../../../VALIDATION-C16-20261027.md).

`SHA256SUMS` couvre les pièces de ce dossier.
