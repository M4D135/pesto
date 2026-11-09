# C16 — deuxième campagne Windows échouée, source 1dbdda1

La [campagne 40489970770](https://github.com/M4D135/pesto/actions/runs/40489970770), source [`1dbdda1020cf21ea2c65fc69b5572bbfc857095e`](https://github.com/M4D135/pesto/commit/1dbdda1020cf21ea2c65fc69b5572bbfc857095e), se termine en **échec** le 27 octobre 2026. Le job `windows-critical` a commencé à 10:37:55 UTC et s’est terminé à 10:49:48 UTC. Le nouveau banc progresse jusqu’à **19 assertions sur 36** : les parcours natifs d’export, d’enregistrement et d’import réussissent, puis le pilote bloque sur la sélection positive du dossier de destination.

**Aucun pack PROD ou DEV n’a été publié par cette campagne.** L’assemblage des candidats avait réussi, mais les transactions natives de mise à jour, l’archivage final des candidats et leurs publications ont été ignorés après l’échec. Seule l’archive de preuves a été publiée. Les résultats GitHub sont conservés dans [workflow-run.json](workflow-run.json), [workflow-jobs.json](workflow-jobs.json) et [github-artifacts.json](github-artifacts.json).

## Échec observé et cause identifiée

La [preuve de configuration PROD](native-configuration-PROD.json) porte `success: false`, l’étape `default-positive-folder-ui` et le code `qualification.configuration.dialog`. Les 19 assertions terminées sont conservées dans son tableau `checks` ; la dernière est `packDestinationCancelled`. La sélection positive du dossier, qui devait suivre, n’est pas acquittée.

Le dernier inventaire de contrôles du dialogue contient un champ de classe `Edit` d’identifiant **1152** pour le dossier, ainsi que la barre d’adresse `Edit` **41477**. Le [code du pilote dans `1dbdda1`](https://github.com/M4D135/pesto/blob/1dbdda1020cf21ea2c65fc69b5572bbfc857095e/v2/src/Pesto.App/NativeConfigurationQualification.cs) ne retenait que les identifiants **1001 ou 1148**, observés dans les sélecteurs de fichiers. Il ne sélectionnait donc aucun champ valide dans ce dialogue de dossier.

L’observation correspondante enregistre `writeAttempts: 0`, `stableReads: 0`, `clicked: false` et `closedAfterClick: false`. **Aucune tentative de saisie du chemin du dossier n’a eu lieu** ; `writeAttempts` compte ici les tentatives de saisie dans le contrôle, pas des écritures de fichiers. La fermeture de nettoyage annule le dialogue ; les deux appels `configuration.setDefault` consignés se terminent avec `status: cancelled`. Aucun pack personnalisé n’est produit par ce parcours.

La cause est un filtre incomplet du pilote de qualification. Ce constat ne constitue pas une réussite de la sélection positive par le bouton de l’application : ce parcours exige une nouvelle campagne avec le pilote corrigé.

## Parcours de configuration acquis avant l’arrêt

Cette campagne franchit le point d’échec de la [première campagne `d803d72`](../windows-d803d72-failed/README.md). Les preuves natives établissent, pour le canal **PROD** :

- l’export depuis le bouton et le champ de version, avec contenu et empreinte exacts, et absence de temporaire d’export résiduel ;
- l’enregistrement après confirmation, avec état inchangé avant celle-ci et sauvegarde exacte ;
- les annulations des sélecteurs d’import et d’export, ainsi que le refus d’un fichier mal encodé ;
- l’aperçu d’import avant écriture, son annulation, puis l’application confirmée du plan exact, le retour à la configuration exportée et la sauvegarde correspondante ;
- l’attente de confirmation avant fabrication d’un pack, l’annulation de cette confirmation et l’annulation du sélecteur natif de destination.

Les champs `nativeExportFromUiQualified` et `nativeImportFromUiQualified` valent `true`. Quatre sélections de fichiers sont consignées avec `selectionObservedBeforeIo: true`, leur chemin effectivement choisi et sa forme normalisée identiques. L’export réussi vise exactement `data/export.json` dans le périmètre temporaire ; le chemin retourné par le backend correspond à l’observation de l’hôte. Le fichier exporté porte le SHA-256 `e104b89382d84ec5bbdd6c600f9c4ecc278be2263cef8cf6f373472133f7e85f` et l’empreinte canonique de configuration `f504e531455ee3cc94c9f2ac3793068bf6bfea1b706a2750570b715f257df55f`.

Les gardes de sélection interviennent désormais avant l’IO des fichiers. La fenêtre est fermée, le profil temporaire est supprimé et l’empreinte du pack source reste inchangée. Ces observations concernent cet essai sur profil temporaire ; elles ne qualifient pas un profil de production et ne résolvent pas rétroactivement la destination inconnue de l’export de la première campagne.

La création du pack personnalisé et le parcours de maintenance ne sont pas atteints. La configuration DEV n’a pas été lancée. Les transactions natives de mise à jour PROD et DEV sont ignorées. Aucune installation depuis les boutons, confirmée ou annulée, n’est qualifiée par cet essai de configuration.

## Autres contrôles réussis

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

Les cinq JSON natifs conservés portent le même SHA-256 d’exécutable observé : `f9e2f9d8b8d918b89d4c177605eac09528930ebcefab9e3422c3904dfb4e8046`. Il identifie l’exécutable construit pour cet essai, **pas un pack publié ou globalement qualifié**. Le [runtime](runtime.json) est WebView2 `156.0.4314.42` ; les preuves de démonstration observent Windows `10.0.26100.0`.

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

Le contrôle statique signale que la référence Domenia est absente : les 28 empreintes locales sont contrôlées, mais aucune comparaison octet à octet avec cette référence n’est déclarée. Les comptes de cette campagne recouvrent ceux des contrôles locaux et de la première campagne ; ils ne s’additionnent pas.

## Origine et intégrité des pièces

L’[archive de preuves 12728737832](https://github.com/M4D135/pesto/actions/runs/40489970770/artifacts/12728737832) a été téléchargée. Ses **2 150 475 octets** donnent le SHA-256 `7d88e78ba1b8e8c3b2157b951e815c213dee3a90e1d66d63de23d0281e1a2d7d`, identique au digest GitHub. Il s’agit de l’enveloppe de preuves, pas d’un ZIP candidat. Son expiration GitHub annoncée est le 26 novembre 2026 à 10:49:41 UTC.

Ce dossier conserve **24 journaux**, **cinq JSON natifs**, le JSON du runtime et les trois réponses de métadonnées GitHub, soit **33 fichiers sources**. Les captures, dont celles de l’export et de l’aperçu d’import réussis, et les autres fichiers de l’archive restent accessibles dans l’enveloppe complète ; ils ne sont pas dupliqués ici.

Les 30 entrées provenant de l’archive ont été comparées octet à octet aux fichiers téléchargés avant copie. Leur seule transformation est le remplacement de CRLF par LF ; leurs autres octets sont conservés. Les trois réponses GitHub sont identifiées séparément et conservées avec une seule fin de ligne LF finale. [summary.json](summary.json) donne pour chaque copie son chemin d’origine, sa provenance, ses tailles et SHA-256 avant/après, ainsi que les normalisations effectuées ; aucune ligne vide finale supplémentaire n’a dû être retirée de ces trois réponses. [SHA256SUMS](SHA256SUMS) contrôle tous les fichiers de ce dossier, à l’exception du manifeste lui-même.

## Limites

Cette campagne ne qualifie ni AD réel, ni UNC réel, ni UAC réel. Les 19 assertions natives terminées ne valent pas réussite des 36 attendues ni qualification du canal DEV. Le blocage du pilote de dossier conserve la création du pack personnalisé et les actions suivantes hors du périmètre réussi.

Le [rapport C16](../../../VALIDATION-C16-20261027.md) distingue les deux campagnes échouées de la correction et de sa requalification. Les preuves AD/UAC antérieures restent attribuées à leurs binaires d’origine. Aucun résultat d’une campagne ultérieure n’est présumé dans ce dossier.
