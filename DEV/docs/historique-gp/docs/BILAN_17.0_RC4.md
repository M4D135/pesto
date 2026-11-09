# Bilan de livraison GP 17.0-RC4

Date : 21 septembre 2026. Base : l'archive GP_17_WAD_RC3 fournie dans la conversation.

La RC4 corrige l'appel `File.Replace` lors des sauvegardes locales sans backup et applique la règle : renommage avec déplacement automatique seulement lorsque le site change. Le parcours hors domaine, les protections des mutations et le correctif des callbacks restent conservés. Aucun EXE nouvellement compilé.

## Vérifications exécutées ici

| Vérification | Résultat | Portée |
|---|---:|---|
| Contrôles statiques généraux | 55/55 | Encodage, délimiteurs, XML/XAML, liaisons, dépendances et gardes |
| Gardes statiques des callbacks | 25/25 | Défauts de portée ciblés de RC3 |
| Gardes statiques RC4 | 28/28 | Appel NullString, intégration de la règle, frontière avant worker |
| Défauts injectés : validateur général | 10/10 détectés | Copies temporaires, tests du détecteur seulement |
| Défauts injectés : callbacks | 7/7 détectés | Copies temporaires, tests du détecteur seulement |
| Défauts injectés : RC4 | 7/7 détectés | Copies temporaires, tests du détecteur seulement |
| Configurations, ressources et lanceurs préservés | 15 fichiers identiques | Comparaison binaire à la RC3 |
| Fonctions racines préservées | 180 inchangées | Comparaison textuelle, pas preuve fonctionnelle |

Total : **108 contrôles statiques passés**, **24 défauts de contrôle détectés**. Ces nombres ne sont pas des tests d'opérations Windows ou AD. Le scanner lexical n'est pas le parseur natif PowerShell ; il ne démontre ni la liaison .NET ni le fonctionnement WPF.

Un avertissement persiste dans la configuration d'origine livrée : `o.LOCAL` n'est pas le domaine des DN terminés par `DC=labo,DC=local`. Ce fichier est préservé, pas corrigé arbitrairement. L'installation réelle de l'utilisateur a déjà sa configuration ; le correctif sans configuration évite de la remplacer.

Rapports actuels : `tests/static-report.json`, `tests/async-static-report.json`, `tests/rc4-static-report.json`, `tests/rc4-preservation-report.json`, et les trois rapports `*checker-selftest-report.json`. Les fichiers dont le nom contient RC2/RC3, les anciens diffs et les anciens bilans constituent un historique.

## Fourni mais non exécuté ici

- `Run-RC4Tests.ps1` : **51 cas natifs** avec parseur Windows PowerShell, fichiers temporaires réels et doublures pour l'AD, les mutations et l'UI ; lancement par `TEST_CORRECTIF.cmd`.
- Suites natives existantes `Run-EngineTests.ps1`, `Run-PackageTests.ps1`, `Run-AsyncTests.ps1`. La régression d'écriture sans backup a aussi été ajoutée à la suite moteur.
- Exécution des CMD, démarrage complet et rendu WPF, tests sur AD/RPC/COM/UAC, jonction/renommage/déplacement réels, redémarrage et compilation EXE.
- Définition de CI Windows mise à jour, mais non lancée à distance.

Aucun rapport Windows réussi n'est fabriqué dans l'archive. Le test natif doit d'abord passer sur un poste de test ; les parcours AD réels doivent ensuite être vérifiés avant utilisation en lot. Le build vérifie les codes de sortie des quatre suites avant compilation.

## Changements et reprise

5 fonctions ajoutées, 17 modifiées, aucune supprimée. Le diff du moteur est `changes/GP17-RC3-to-RC4.patch`. `RenameComputer`, `MoveComputer`, `AddToDomain`, le moteur des callbacks, la jonction hors domaine et la levée manuelle du verrou sont inchangés textuellement. Cette préservation ne dispense pas des essais d'intégration.

L'erreur d'une sauvegarde locale avant création du worker est désormais NON LANCÉ / 96, sans nouveau verrou de mutation. Une erreur après émission de la demande garde son traitement de sécurité. Un ancien verrou RC3 n'est jamais levé automatiquement.

Pour une installation existante, extraire le correctif dans le même dossier GP, garder `wad/cfg.json`, débloquer les fichiers de confiance et utiliser `TEST_CORRECTIF.cmd`. Ne pas effacer les états ou changer le chemin de configuration pour contourner un verrou. Guide : `docs/CORRECTIF_RC4.md`.

SHA-256 du moteur RC4 : `c5d959148b2710e2d74e04c4ea2b7de4ba779a2a6600b026cabc11634f8d06b7`.
