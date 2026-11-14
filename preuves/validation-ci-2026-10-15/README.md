# Validation CI — Pesto 1.0

EXE `5ff886587b627a2e4b946cda47a58c17f69c05d2ab66658c57870542587ce2b6` ; [relation des builds](build-relation.json). Le réglage d’horloge expose désormais sa clé `POLICY.BlockJoinOnClockSkew` dans l’infobulle et l’aide accessible, comme les autres réglages. L’EXE est recompilé pour épingler ce XAML. Les octets du moteur et de Common.Core correspondent toujours aux preuves du point 105.

- [ConfigEditor120](config-help.json) : **26/26** sur Mac / PowerShell 7.4.20, fonctions réelles avec doubles, sans WPF/AD.
- [Accessibilité statique](accessibility-help.log) : **7/7**.
- [Contrôles portables](portable.json) : **620/620**, vrai parseur PowerShell 7.4.20 ; aucune exécution de l’EXE sous Windows déduite.
- [CI c867c59](https://github.com/M4D135/pesto/actions/runs/38799784174) : portable réussi ; Windows isolé a parcouru les 48 suites et signalé uniquement la clé d’aide manquante ci-dessus. Les deux contrôles de grande fenêtre non exécutés sur écran 1024 px restent distincts. Les quatre suites WPF dédiées étaient alors sautées. [Détails des jobs](github-c867c59-jobs.json).

Les [preuves des correctifs](../correctifs-ci-2026-10-15/README.md) conservent leur attribution : journal, adaptateur, scanner, CLI et corpus déterministe. Les guides v1.0 restent identiques aux versions relues. Packs classiques DEV/PROD neutres reconstruits avec ce candidat ; CI du candidat confirmé ci-dessous.

Catalogue : 88 fonctions implémentées, 19 études conclues, 1 qualification de contrats purs locaux acquise (105), 11 qualifications encore ouvertes et 1 mesure prolongée restante (107). Aucun nouveau test de VM labo, aucune connexion AD ni recette utilisateur réelle dans cette passe.

## CI confirmé sur le candidat b27c67c

Le [run 38800755586](https://github.com/M4D135/pesto/actions/runs/38800755586) est **réussi** sur le commit `b27c67c916492d8cf834f796e9c0d3a62dfe2f67` et l’EXE ci-dessus. Les [métadonnées du run](github-run.json) et les [étapes des jobs](github-jobs.json) sont conservées.

- Linux : **543 tests Python réussis**, aucun échec ; [journal](github-linux.log).
- Windows Server 2022 / Windows PowerShell 5.1.20348.5622 : **48 suites réussies**, dont Engine120 77/77, Engine 118/118, ConfigEditor120 26/26 et CliOutput 15/15 ; [journal complet](github-windows/run-all.log).
- Quatre bancs WPF dédiés réussis : [Zoom](github-windows/Zoom.json), [ToolsTabs](github-windows/ToolsTabs.json), [Workbench120](github-windows/Workbench120.json) et [BatchNames120](github-windows/BatchNames120.json). Contrôles WPF instanciés en isolation ; aucune application connectée à AD.

Deux contrôles de mise en page large restent **non testés** sur le viewport CI de 1024 px. Ils ne sont pas transformés en PASS et ne ferment pas la qualification visuelle du catalogue. Les copies textuelles des artefacts Windows sont décodées en UTF-8 ; les métadonnées de l’archive source et son identité de commit sont conservées dans `github-windows/artifact.json`.

La clé d’aide manquante de SetChkClockSkew était déjà signalée dans le premier run ae2a663 ; la première lecture ciblée des erreurs ne l’avait pas relevée. La revue complète des 48 sections et du résultat global a permis de la retrouver et de la corriger. Le verdict présent remplace cette lecture partielle.
