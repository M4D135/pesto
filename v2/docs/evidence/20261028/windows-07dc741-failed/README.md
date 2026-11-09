# C18 — campagne Windows 07dc741 échouée

La [campagne 40671804121](https://github.com/M4D135/pesto/actions/runs/40671804121), job `122760169366`, a testé le commit exact `07dc74116478f1dd28d5f54ab6e2f11b1b4ee472` le 28 octobre 2026 entre **10:23:59 et 10:39:19 UTC**. Son verdict est **failure**. Le [rapport C18](../../../VALIDATION-C18-20261028.md) distingue ces résultats partiels du dernier candidat Windows complet C17.

Le [journal de reprise navigateur](logs/web-recovery-check.log) montre **15/23 contrôles réussis**. Les huit échecs attendent le champ de recopie supprimé du dialogue individuel « Confirmer le déplacement restant ». Les attentes obsolètes se trouvent dans `v2/tools/tests/web-recovery-check.mjs` aux lignes 95, 128 et 130 de cette source. Aucun correctif ni relancement n’est attribué à cette preuve.

Résultats acquis avant l’arrêt :

- [Moteur](logs/Engine-All.log) : **616/616**.
- [Gardes de restauration](logs/AdRestoreGuards.log) : **250/250**, dont **105 accès aux reçus**. Les deux contrôles supplémentaires par rapport au Mac vérifient le refus d’ouverture en écriture sous Windows, un par reçu ; aucun test de suppression pendant le verrouillage n’est présent.
- [SDK candidat](candidate-sdk.json) : **10.0.302**, exact, `rollForward=disable`.
- [Reconstruction DEV](dev-rebuild-proof.json) : sources seules du ZIP livré, cache neuf, SDK 10.0.302 et [démarrage natif du PROD reconstruit](dev-rebuild-rebuilt-native-demo.json) réussis.
- Configuration native [PROD](native-configuration-PROD.json) et [DEV](native-configuration-DEV.json) réussie, avec annulation finale de l’installation dans ces parcours.
- [Métier navigateur](logs/web-business-check.log) : **57/57**.

L’[artefact 12808854192](https://github.com/M4D135/pesto/actions/runs/40671804121/artifacts/12808854192) a été téléchargé : **1 828 912 octets**, SHA-256 **`5520b1854f86c068a3b30f206d1b42df082393f4be5052cbf39667c40e4952c1`**, identique au digest GitHub. Expiration annoncée : **27 novembre 2026 à 10:39:11 UTC**. L’archive complète est conservée localement dans `work/update-ci-20261028/c18/failed-evidence-07dc741.zip`.

Le [manifeste de collecte](collection-manifest.json) relie chaque copie à ses octets d’origine ; seules les fins de ligne CRLF des preuves ont été normalisées en LF. Les [métadonnées d’artefacts](github-artifacts.json), du [run](workflow-run.json), du [job](workflow-jobs.json) et le [diagnostic](failure-summary.json) sont conservés. [SHA256SUMS](SHA256SUMS) couvre tous les fichiers de ce dossier sauf lui-même.

**Aucun artefact PROD/DEV n’a été publié par ce run.** Les parcours natifs exécutés après les suites navigateur, notamment les transactions de mise à jour et l’installation depuis l’interface, sont ignorés à cause de l’échec antérieur. Ces preuves ne qualifient aucune mutation AD réelle, UAC réelle, restauration de VM, livraison C18 complète ou production.
