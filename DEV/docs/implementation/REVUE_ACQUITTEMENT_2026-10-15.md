# Revue de l’acquittement — 15 octobre 2026

Les 18 observations du Spark sont des propositions relues contre le produit. Les identifiants ci-dessous suivent
l’ordre des quatre réponses `surete`, `ps51`, `couverture` et `terrain` conservées dans le worktree de reprise.
Une proposition refusée ne constitue pas un correctif manquant.

| Observation | Décision vérifiée dans les sources | Preuve ciblée |
|---|---|---|
| Sûreté 1 — conflit après effet confirmé | Refusée : interdire tout acquittement après un effet confirmé recréerait le blocage. Les effets restent conservés ; une nouvelle préparation relit la cible. Aucun ancien résultat n’est rejoué. | OptionalPostCheck, QueueRemoval |
| Sûreté 2 — coordination et copies locales | Précaution ajoutée : aucune libération immédiate par l’écrivain si un reçu local est illisible. Les trois fichiers ne forment pas une transaction atomique ; un échec partiel reste signalé et peut nécessiter une nouvelle tentative. | Acknowledgement, relecture Set-PestoOperationAcknowledgement |
| Sûreté 3 — tâche Windows encore active | Corrigée : phases autres que Finished/Deleted refusées ; Relire les tâches doit confirmer leur fin. | Acknowledgement, QueueRemoval |
| Sûreté 4 — reçus de file illisibles | Corrigée : tout ID manquant, invalide, illisible ou d’un autre domaine conserve le verrou. | QueueRemoval |
| Sûreté 5 — domaine des reçus locaux | Corrigée : direct et jonction doivent appartenir au domaine courant. | Acknowledgement |
| PS5.1 1 — reprise de déplacement | Corrigée : Sync-PestoInterventionViews ignore le déplacement restant d’un reçu déjà acquitté. | Relecture du chemin de reprise, OptionalPostCheck |
| PS5.1 2 — recalcul du verrou de file | Corrigée : les reçus valablement acquittés satisfont le contrôle de synchronisation. | QueueRemoval, relecture Sync-PestoInterventionViews |
| PS5.1 3 — barrière cible | Défense ajoutée : un reçu valablement acquitté ne bloque plus via un indicateur UI périmé. | OptionalPostCheck |
| Couverture 1 — rejeu d’une ligne acquittée | Refusée : une ligne avec résultat reste non rejouable. L’opérateur prépare une nouvelle ligne. | QueueRemoval, garde Run-Queue conservée |
| Couverture 2 — IDs présents seulement dans les lignes | Corrigée : union de QueueOperationIds et Operation_ID des lignes concernées. | QueueRemoval |
| Couverture 3 — synchronisation de file | Doublon de PS5.1 2. | Même correction |
| Couverture 4 — barrière cible | Doublon de PS5.1 3. | Même correction |
| Couverture 5 — checkpoint déclaré acquitté mais encore EN COURS | Refusée : un checkpoint contradictoire conserve son incertitude ; sa simple étiquette ne suffit pas à le débloquer. | Relecture Restore-PestoQueueCheckpoint |
| Terrain 1 — PARTIEL absent | Corrigée : PARTIEL est compris dans les lignes concernées. | QueueRemoval |
| Terrain 2 — message après acquittement | Corrigée : le dialogue explique les résultats conservés, les lignes décochées et la nouvelle préparation. | QueueRemoval ; recette visuelle distincte |
| Terrain 3 — ID absent | Corrigée : refus explicite avant levée du verrou. | QueueRemoval |
| Terrain 4 — cases et provenance | Partiellement retenue : lignes décochées et grille rafraîchie ; IDs et messages conservés pour la traçabilité. | QueueRemoval |
| Terrain 5 — vue Interventions périmée | Corrigée : rafraîchissement si la vue est ouverte. | Relecture du callback ; recette visuelle distincte |

## Corrections complémentaires

- Mutex de mutation tenu sur l’ensemble de l’acquittement de file ; nouvelle vérification des workers après le dialogue.
- Échec de sauvegarde du checkpoint : restauration des indicateurs et des états de ligne.
- Apply-PestoQueueObservation ne recompte plus une ligne incertaine dont le reçu correspondant est valablement acquitté.
- Les reçus anciens valides sans UpdatedUtc/LastStage acceptent l’ajout de l’acquittement.
- Les exceptions des orchestrateurs silencieux préservent OperationId et les métadonnées validées ; aucune valeur héritée
  de la portée appelante ne doit apparaître lors d’un échec précoce (T010).
- Chaînes visibles du lanceur accentuées, identifiants techniques stables conservés (W4V1T083).

## Portée des tests

Les bancs isolés ne font aucune mutation AD. Acknowledgement utilise les vrais contrats, lecteurs et écrivains
avec de vrais fichiers NTFS dans un dossier temporaire sous Windows PowerShell 5.1 ; les chemins, UI et coordination
sont isolés ou remplacés par des doubles. QueueRemoval utilise de vraies DataTable et sauvegardes de checkpoint,
avec doubles explicites pour les reçus. Les résultats de recette graphique et de mutation AD sont consignés séparément.

Les brouillons Spark ont été corrigés avant intégration : suppression des faux validateurs du banc écrivain,
préservation des tests existants et ajout de véritables injections d’erreur pour T010. Un test de présence de texte
ou une copie Python d’un prédicat ne prouve pas son exécution dans le moteur Windows.
