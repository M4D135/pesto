# Lot opérateur après b7e781f — preuves portables

Les journaux originaux sont copiés sans modification. Les empreintes de **194 fichiers C# et projets** sont identiques avant et après les builds et la suite intégrée, puis ont été revérifiées avant publication.

| Contrôle | Résultat final | Journal |
|---|---:|---|
| Moteur intégré | **519/519** | `engine-c4-final2-20261025.log.txt` |
| Builds moteur, hôte Windows et banc | **0 erreur, 0 avertissement** chacun | `build-*-c4-final2-20261025.log.txt` |
| Banc portable | **10/10** | `harness-c4-final2-20261025.log.txt` |
| Pont C# | **11/11** | `bridge-c4-20261025.log.txt` |
| Parcours opérateur Chromium | **32/32** | `operator-ui-c4-final-20261025.log.txt` |
| Métier Chromium | **29/29** | `web-business-check-c4-final-20261025.log.txt` |
| Paramètres et maintenance Chromium | **18/18** | `web-maintenance-check-c4-20261025.log.txt` |
| Reprise Chromium | **23/23** | `web-recovery-check-c4-fixed-20261025.log.txt` |
| Contrats web et provenance | **137/137** | `web-check-c4-final-20261025.log.txt` |
| Cycle de vie du pont JS | **21/21** | `bridge-lifecycle-check-c4-final-20261025.log.txt` |
| Démo navigateur | **11/11** | `demo-check-c4-final-20261025.log.txt` |

Le journal opérateur initial 27/27 est conservé séparément ; le résultat final est 32/32. Les suites se recouvrent et ne s’additionnent pas. Les échecs intermédiaires de compilation et les anciennes fixtures corrigées sont décrits dans le rapport de validation ; aucune preuve d’exécution réussie n’en est déduite.

La compilation de l’hôte Windows est une compilation croisée sous Linux. Ces contrôles n’ont effectué aucune mutation AD/SMB ni aucun redémarrage réel. L’auto-test du banc utilise un runtime factice déclaré ; `nativeWindowsExecuted` et `adExecuted` sont faux. La qualification native PowerShell 5.1 et le smoke reconstruit à 34 refus directs exigent une campagne Windows attachée au commit publié. La campagne b7e781f à 29 refus demeure historique.

`proofs.sha256.json` inventorie les octets des preuves, hors lui-même. Les instantanés de sources permettent de relier ces résultats au code compilé, sans prétendre qualifier les parcours natifs non exécutés.
