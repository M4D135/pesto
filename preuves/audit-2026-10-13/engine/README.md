# Audit moteur — 13 octobre 2026

Windows PowerShell 5.1.26100.6584 x64, session SSH isolée 0 de PESTO-W11-TEST.

- 23 bancs du périmètre : **754 PASS, 0 FAIL, 3 SKIP**. Les trois SKIP sont les variantes WPF facultatives21/22/23, validées séparément dans les preuves UI. Ce total ne cumule pas les répétitions ci-dessous.
- Lanceur global : **31 suites**, sortie0, stderr vide,100964ms, build22f8f5c49304f67d346db72a687d216402e0c6aa86d8bb4e67a7d62878dfabad.
- Ultime build e3b7790a75338e762cb67cdbb239ad67f7e34717dd0ec6a170c41febeb31adae : **Package27/27, présentation43/43**, après les trois attributs de Configuration modifiés. Le moteur ne change pas entre ces deux builds.

## Défauts corrigés

1. Réservation partagée : une libération lisait le propriétaire, puis pouvait supprimer le fichier repris par un concurrent. `shared-release-before.json` reproduit cette séquence avec les deux vrais workers sur NTFS ; `SharedNameReservation.json` valide14 cas, dont ce chevauchement et le refus de suppression. Le fichier reste ouvert jusqu'à la suppression et un Delete refusé ne déclare aucun nom libéré.
2. Déblocage : les fichiers cachés portant Zone.Identifier étaient manqués par Get-Item sans Force. `initial/Package-unblock-before.json` contient l'erreur native. Silent a corrigé le support ; `Package.json` vérifie le vrai bloc livré, contenu préservé, idempotence et jonctions ignorées.

Les bancs Pesto21/Pester initialisent désormais la DLL commune vérifiée. Package utilise la disposition actuelle EXE+wad et le support livré. SharedNameReservation fait partie de Run-AllTests. RC14Validation reste un outil historique autonome, sans appel actuel trouvé ; son contrat17.0.0.14 est remplacé par les contrôles actuels, il n'a pas été présenté comme passant.

## Portée

Aucune opération AD réelle, aucun redémarrage, aucune UAC ni écriture de préférences réelles. Fichiers de test temporaires NTFS seulement. Les appels AD/Windows métier utilisent des doubles. Le verrouillage SMB entre machines n'a pas été testé. Plusieurs anciens rapports portent WindowsExecuted=false car ils décrivaient des doubles ; l'environnement et PowerShell indiquent la plateforme effective.

`summary.json` relie les rapports et les deux manifestes de sources. `initial/` conserve les premières observations ; elles ne sont pas les résultats finaux. Les sources, tests et exécutable sont gelés, aucun commit/push effectué par cet agent.
