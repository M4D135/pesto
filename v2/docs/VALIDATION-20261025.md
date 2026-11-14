> **Rapport historique.** Pour le code de la reprise actuelle, voir [VALIDATION-REPRISE-20261025.md](VALIDATION-REPRISE-20261025.md), [PARITY.md](PARITY.md) et [EVIDENCE.md](EVIDENCE.md). Les résultats ci-dessous restent attachés aux anciens lots et binaires.

# Validation de développement — 25 octobre 2026

La branche `codex/pesto-v2-20261023` est une branche de développement. Le premier lot a été poussé en `f430f9b74d3ede9714d3da847955a2d122710d80`, avant les tests, selon la demande de David. Les résultats ci-dessous distinguent les contrôles portables des essais Windows. Aucune release V2 complète n'est annoncée à ce stade.

## Corrections du lot suivant

- Formulaires réellement montés ; aperçu de nom lié aux choix actuels, réponses et préparations périmées ignorées.
- Résultat métier distinct de la réception d'un reçu : refus, incertain et redémarrage attendu ne sont jamais présentés comme terminés.
- Déplacement seul restauré conformément à V1, avec identité relue, plan serveur et confirmation.
- Démarrage natif en annuaire, élévation Windows, compte Windows ou saisie AD native, sans secret dans le pont web.
- Résolution cohérente de l'installation V1 et de son dossier wad ; sonde du moteur Windows PowerShell 5.1 par PSVersionTable.
- Reçus durables finalisés après relecture ; vérification explicite après redémarrage liée au GUID, à l'état Windows et à la preuve AD. Aucune répétition automatique.
- Contrôles du GUID et de l'OU source, de la destination et de son GUID avant envoi ; maintien de la protection AD.
- Repli distant : identité COM conservée, date COM lue comme DateTime, codes Win32/HRESULT décodés.
- Fermeture idempotente et attente de la fin des opérations engagées ; annulation des lignes suivantes du lot.
- Verdict d'arrêt du watcher fondé sur une preuve native de disparition du PID attendu.

## Contrôles effectués

| Contrôle | Résultat | Portée |
|---|---:|---|
| Moteur | 229/229 | Tests comportementaux portables, logs/engine-guards-20261025.log |
| Pont | 5/5 | Sérialisation des opérations et contrat fermé |
| Interface Chromium | 32/32 | Pages réellement montées, formulaires, clavier, thèmes, reçus |
| Parcours métier Chromium | 25/25 | Statuts, aperçus périmés, sélection concurrente, déplacement seul |
| Contrôles web | 105/105 | Contrat et ressources |
| Watcher | 43/43 | Contrôles du pilote avant extension des métadonnées natives |
| AZERTY | 21/21 | Mappage des touches |
| Pack portable | 37/37 | Assemblage et refus des altérations ; le runtime factice de ce test ne qualifie pas WebView2 |
| App Release win-x64 | 0 erreur, 0 avertissement | logs/build-app-guards-20261025.log |
| Harnais win-x64 autonome | publication réussie | logs/publish-ad-harness-guards-20261025.log |

## Windows et AD : preuves réellement obtenues

La VM Pesto a été identifiée par son UUID, son nom et son appartenance au domaine. Le harnais réel a exécuté les lectures sous le compte de qualification Windows, sans identifiant secret transmis au pont. Après correction de la sonde PowerShell, les preuves natives relues confirment la découverte du contrôleur, les deux sites, les services et dix postes du labo. L'historique inaccessible au compte non élevé reste signalé inconnu, sans faux zéro.

Preuves de campagne : logs/qualification/codex-ad-read-green-20261025.json et codex-canary-before-20261025.json. Les journaux locaux de qualification et les captures sont conservés sur les machines du labo ; ils ne sont pas inclus dans le dépôt.

## Lot déplacement restant et interface native

Le reçu partiel `renameMove/code89` propose désormais un plan limité au déplacement restant. Le renommage après redémarrage, le GUID, les OU et la protection sont relus. Une autorisation native expire et se consomme une seule fois ; deux reçus durables lient le parent partiel à son enfant. Aucun renommage, redémarrage ou déplacement n'est rejoué automatiquement. Le parent conserve son résultat historique et ne devient pas un faux succès.

Contrôles portables : moteur 248/248, puis 7/7 contrôles ciblés après le dernier durcissement natif ; pont 6/6 ; interface récupération 23/23, DOM 32/32, web 106/106 et géométrie 8/8. Build final App Release win-x64 : zéro avertissement et zéro erreur. Logs de campagne : `engine-continuation89-20261025.log`, `continuation-native-final-20261025.log`, `bridge-continuation89-20261025.log`, `build-app-continuation89-20261025.log`. La nouvelle reprise 89 n'a pas encore été exécutée sur Windows.

Dans WebView2 réel, les neuf pages, cinq parcours de formulaire, les quatre thèmes, Ctrl+B, Ctrl+K vers Journal, les cartes et la fermeture par la croix ont été observés. Trois boutons coupés ont été corrigés ; six captures natives (trois formulaires, deux largeurs) confirment les libellés entiers. Les deux instances testées ont disparu après fermeture normale, sans fenêtre d'erreur Pesto. Un ancien dialogue Explorer « journal » a été distingué des fenêtres Pesto et n'a pas servi de preuve.

Preuves locales : `gui-native-4bc8f2/native-pass-summary-before-css.json`, `gui-final-4bc8f2-layout-native-cross-closed.json` et `gui-final-4bc8f2-layout-all-stopped.json`. Le pack CSS a été relu sur la VM : 1249 fichiers vérifiés, aucun défaut (`codex-layout-pack-verified-20261025.json`). Cette preuve précède la nouvelle reprise 89.

Le harnais de retour contrôlé est préparé, avec 28 tests de garde et 20 tests de barrières V1. Son déploiement a été vérifié sur la VM. L'invite AD de l'inspection suivante a été annulée pour reprendre le développement : aucune mutation AD n'a été exécutée par ce lot.

David a ajouté au périmètre les mises à jour GitHub/partage/ZIP et une démonstration complète adaptée à Pesto. Ces fonctions sont à développer ; les exclusions GLPI, tickets, multidomaine, PS7 obligatoire et signature applicative restent inchangées.

## À terminer avant livraison complète

- Mises à jour transactionnelles, référentiels versionnés et démonstration isolée, puis leurs contrôles.
- Qualification du parcours annuaire réel et de l'interface finale après les nouveaux développements.
- Mutations AD contrôlées, reçus avant/après, vérification après redémarrage et retour préparé.
- Vérification native du pack final après intégration des dernières sources.
- Qualification distincte des scénarios distants et du repli ; les tests portables ne les remplacent pas.
- Mise à jour de cette preuve finale, revue et confirmation du hash Git distant.

Les notes historiques de PARITY.md et VALIDATION.md décrivent leurs versions datées. Ce document évite de les prendre pour une qualification de la version courante.
