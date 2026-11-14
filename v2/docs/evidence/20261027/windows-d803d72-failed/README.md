# C16 — première campagne Windows échouée, source d803d72

La [campagne 40486971793](https://github.com/M4D135/pesto/actions/runs/40486971793), source [`d803d72ed1084d631364a1830d6211d841e02813`](https://github.com/M4D135/pesto/commit/d803d72ed1084d631364a1830d6211d841e02813), se termine en **échec** le 27 octobre 2026. Le job `windows-critical` a commencé à 10:14:52 UTC et s’est terminé à 10:29:32 UTC. Ces preuves conservent les contrôles réussis avant l’arrêt et l’échec du nouveau banc de configuration ; elles ne qualifient pas un pack C16 livré.

**Aucun pack PROD ou DEV n’a été publié par cette campagne.** L’assemblage des candidats avait réussi, mais les transactions natives de mise à jour, l’archivage final des candidats et les deux publications de packs ont été ignorés après l’échec. Seule l’archive de preuves a été publiée. Les résultats GitHub sont conservés dans [workflow-run.json](workflow-run.json), [workflow-jobs.json](workflow-jobs.json) et [github-artifacts.json](github-artifacts.json).

## Échec observé

La [preuve de configuration PROD](native-configuration-PROD.json) porte `success: false`, l’étape `export-ui` et le code final `qualification.configuration.ui-timeout`. Seules **deux assertions sur les 36 attendues** ont été acquittées : `parentReady` et `isolatedConfigurationPage`.

Les actions DOM `SetVersion` puis `Export` ont été acceptées. Le pilote du dialogue déclare avoir saisi et relu le chemin demandé, puis fermé le sélecteur par son bouton. Cela ne prouve pas la destination finalement acceptée par le service natif. L’unique appel `configuration.export` et l’unique action hôte `export` se terminent avec `failureCode: qualification.scope`, sans résultat d’export réussi. Leur champ `completed: true` indique une fin d’appel, pas une réussite.

**La destination effective de l’export n’est pas connue.** Dans le code `d803d72`, le wrapper de qualification vérifie le chemin retourné après avoir attendu `NativeHostActions.SaveExportAsync`, donc après son opération d’écriture. Le refus de périmètre ne constitue pas une barrière avant IO. Le champ brut `ordinaryProfileAccess: false` est conservé tel qu’émis, mais il ne prouve pas l’absence d’accès au profil ordinaire ou à une autre destination hors du dossier temporaire. Le présent résumé ne reprend pas cette valeur comme une garantie vérifiée.

Le rapport brut indique la fermeture de la fenêtre, la suppression de son dossier temporaire et la conservation du pack source. Ces observations ne permettent pas de conclure à l’absence ou au nettoyage d’un fichier écrit ailleurs. La correction du banc doit déplacer la garde avant l’IO et obtenir une nouvelle preuve ; elle ne réécrit pas cet essai échoué.

Les étapes d’enregistrement, d’import, de création du pack personnalisé, de sélection positive du dossier et de maintenance n’ont pas été atteintes. La configuration DEV n’a pas été lancée. Les transactions natives de mise à jour PROD et DEV ont été ignorées. Aucune installation depuis les boutons, confirmée ou annulée, n’est qualifiée par cet essai de configuration.

## Contrôles réussis avant l’échec

| Contrôle | Résultat | Preuve et portée |
|---|---:|---|
| Moteur complet | 615/615 | [Engine-All.log](logs/Engine-All.log), fournisseurs isolés |
| Pont | 15/15 | [Bridge.log](logs/Bridge.log), contrats et sérialisation |
| Mécanique des packs | 46/46 | [Pack-Mechanics.log](logs/Pack-Mechanics.log), runtime factice déclaré, sans exécution Windows |
| Banc portable de mise à jour | 30 contrôles | [NativeUpdateHarness-portable.log](logs/NativeUpdateHarness-portable.log), `nativeWindowsExecuted: false` |
| Gardes du retour AD | 22 + 28 + 20 = 70 | [AdRestoreGuards.log](logs/AdRestoreGuards.log), aucune commande native exécutée |
| Syntaxe PowerShell 5.1 | 18/18 variantes métier et zéro erreur sur l’entrée du banc | [Scripts métier](logs/PowerShell51-syntax.log), [entrée du banc](logs/Qualification-entrypoint-PS51.log), analyse syntaxique sans exécution métier |
| UTF-8 PowerShell 5.1 | 2 contrôles | [PowerShell51-utf8.log](logs/PowerShell51-utf8.log) |
| Accueil natif | 5 assertions | [native-welcome.json](native-welcome.json), résultat UAC synthétique |
| Saisie native | 16 assertions | [native-login.json](native-login.json), identifiants synthétiques |
| Démonstration native PROD et DEV | Réussie dans les deux canaux | [PROD](native-demo-PROD.json), [DEV](native-demo-DEV.json) : six transitions et 44 refus d’API réelles par canal, contexte parent de configuration locale conservé |

Les cinq JSON natifs conservés portent le même SHA-256 d’exécutable observé : `20ef0b4cd7fa4589739b003e9293dad92cc7f3f4510d526069936d99243a8897`. Il identifie l’exécutable construit pour cet essai, **pas un pack publié ou globalement qualifié**. Le [runtime](runtime.json) est WebView2 `156.0.4314.42` ; les preuves de démonstration observent Windows `10.0.26100.0`.

### Seize suites JavaScript et navigateur

L’étape de régressions JavaScript/navigateur est réussie. Les journaux ci-dessous utilisent les fixtures déclarées par leurs suites ; un contrôle Chromium ou JavaScript ne vaut pas qualification WebView2, UAC ou AD réelle.

| Suite | Résultat |
|---|---:|
| [azerty-check](logs/azerty-check.log) | 21/21 |
| [bridge-lifecycle-check](logs/bridge-lifecycle-check.log) | 21/21 |
| [demo-check](logs/demo-check.log) | 11/11 |
| [demo-dom-check](logs/demo-dom-check.log) | 9/9 |
| [login-dom-check](logs/login-dom-check.log) | 28/28 |
| [operator-ui-check](logs/operator-ui-check.log) | 41/41 |
| [parity-ui-check](logs/parity-ui-check.log) | 53/53 |
| [policy-ui-check](logs/policy-ui-check.log) | 17/17 |
| [watch-check](logs/watch-check.log) | 44/44 |
| [watcher-result-check](logs/watcher-result-check.log) | Réussi, sans compteur publié |
| [web-business-check](logs/web-business-check.log) | 48/48 |
| [web-check](logs/web-check.log) | 149/149 |
| [web-dom-check](logs/web-dom-check.log) | 32/32 |
| [web-layout-check](logs/web-layout-check.log) | 8/8 |
| [web-maintenance-check](logs/web-maintenance-check.log) | 35/35 |
| [web-recovery-check](logs/web-recovery-check.log) | 23/23 |

Le contrôle statique signale que la référence Domenia est absente : les 28 empreintes locales sont contrôlées, mais aucune comparaison octet à octet avec cette référence n’est déclarée. Les comptes de cette campagne recouvrent ceux des contrôles locaux et ne s’y additionnent pas.

## Origine et intégrité des pièces

L’[archive de preuves 12725624824](https://github.com/M4D135/pesto/actions/runs/40486971793/artifacts/12725624824) a été téléchargée. Ses **1 705 242 octets** donnent le SHA-256 `3fc934dfcbcf34a0d8e16f834a4285e9d020bb8273ee956ca39f755c966f67d6`, identique au digest GitHub. Il s’agit de l’enveloppe de preuves, pas d’un ZIP candidat. Son expiration GitHub annoncée est le 26 novembre 2026 à 10:29:24 UTC.

Ce dossier conserve **24 journaux**, **cinq JSON natifs**, le JSON du runtime et les trois réponses de métadonnées GitHub, soit **33 fichiers sources**. Les captures et les autres fichiers de l’archive restent accessibles dans l’enveloppe complète ; ils ne sont pas dupliqués ici.

Les entrées provenant de l’archive ont été comparées octet à octet aux fichiers téléchargés avant copie. Leur seule transformation est le remplacement de CRLF par LF ; leurs autres octets sont conservés. Pour les deux réponses GitHub `github-artifacts.json` et `workflow-jobs.json`, la ligne vide finale supplémentaire est également supprimée afin de conserver une seule fin de ligne LF. [summary.json](summary.json) donne pour chaque copie son chemin d’origine, sa provenance, ses tailles et SHA-256 avant/après, ainsi que les normalisations effectuées. Les trois réponses GitHub sont identifiées séparément des entrées d’archive. [SHA256SUMS](SHA256SUMS) contrôle tous les fichiers de ce dossier, à l’exception du manifeste lui-même.

## Limites

Cette campagne ne qualifie ni AD réel, ni UNC réel, ni UAC réel. Le succès des contrôles portables et des premiers bancs natifs n’efface pas l’échec de configuration et ne valide pas les étapes ignorées. L’isolement du profil ordinaire pendant l’export échoué reste **non prouvé**.

Le [rapport C16](../../../VALIDATION-C16-20261027.md) distingue cette première campagne de la correction et de sa requalification. Les preuves AD/UAC des rapports antérieurs restent attribuées à leurs binaires d’origine. Aucun résultat d’une campagne ultérieure n’est présumé dans ce dossier.
