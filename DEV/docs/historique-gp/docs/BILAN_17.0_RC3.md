# Bilan de livraison GP 17.0-RC3

Correctif ciblé du crash `Invoke-GPAsyncCallback` visible à la connexion. L'organisation `wad` et `DEBLOQUER_TOUT.cmd` est conservée. Aucun EXE compilé.

## Exécuté ici

| Vérification | Résultat | Limite |
|---|---:|---|
| Contrôles statiques généraux | 53/53 | Pas un parseur PowerShell |
| Contrôles statiques de portée des callbacks | 25/25 | Structure lexicale, pas de liaison à l'exécution |
| Défauts injectés dans les copies de contrôle | 17/17 détectés | Validation des validateurs |
| Moteur RC2 initial soumis à la nouvelle garde | 20 échecs attendus | Contrôle négatif sur l'ancien fichier |
| Fonctions non modifiées | 186 | Comparaison textuelle |
| Configurations, ressources et lanceurs préservés | 14 fichiers identiques | Comparaison binaire/SHA-256 |

Rapports dans `tests/`, diff dans `changes/GP17-RC2-to-RC3.patch`.

## Non exécuté

Les suites Windows `Run-EngineTests.ps1`, `Run-PackageTests.ps1` et `Run-AsyncTests.ps1` n'ont pas été exécutées dans cet environnement Linux. Ni le parseur natif Windows PowerShell 5.1, ni les CMD, ni le lancement complet WPF, ni les opérations AD/UAC, ni la compilation n'ont été validés à l'exécution. La nouvelle suite fournit 29 cas ciblés sans accès AD et peut se lancer par `TEST_ASYNC.cmd`.

## Mise à jour

Utiliser le correctif sans configuration **dans le dossier GP existant**. Conserver `wad/cfg.json`, les journaux et le chemin de l'installation. Les trois fenêtres affichent 17.0-RC3. Le guide détaillé est `docs/CORRECTIF_RC3.md`.

L'archive complète conserve la configuration fournie précédemment, dont l'incohérence domaine/OU signalée. Ne pas la substituer à une configuration déjà adaptée par l'utilisateur.

SHA-256 du moteur : `b6c25aeb13249be575071ebee99a79cff775ff4fee0aa0420383c7f00fe01282`.
