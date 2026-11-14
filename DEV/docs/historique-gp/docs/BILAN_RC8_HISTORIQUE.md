# Bilan de livraison GP 17.0-RC8

Date : 22 septembre 2026. Base : `GP_17_WAD_RC7.zip` fourni dans la conversation.
Objet : retrait d'une ligne en cours de modification, lisibilité de la commande
et persistance sûre de la file locale.

## Exécuté ici

- 56 contrôles statiques généraux ; 25 contrats de callbacks ; 28 contrats RC4 ;
  53 contrats de pilotage ; 49 contrats d'interface ; 29 contrats de saisie ;
  21 contrats ciblés de retrait. Tous passent, soit **261 contrôles statiques**.
- Cinq défauts de retrait injectés dans des copies en mémoire sont détectés.
  Les quatre contrôles négatifs du validateur de saisie passent également.
- Comparaison avec la RC7 : cinq fonctions existantes changent de logique locale
  (`Restore-GPQueueCheckpoint`, `Update-QueueButtons`, `Enter-EditMode`,
  `Exit-EditMode`, `Delete-SelectedRow`) et deux helpers de retrait sont ajoutés.
  Les 253 autres fonctions sont identiques après normalisation LF et remplacement
  du numéro de version. Les fonctions d'authentification, les opérations AD,
  les workers et la décision de déplacement selon le site ne sont pas réécrits.
- Conservation binaire des configurations et ressources de `wad` autres que le
  moteur, contrôlée face à la RC7. Intégrité ZIP et empreintes contrôlées à l'assemblage.

L'avertissement existant sur la configuration historique du pack complet reste
présent : domaine `o.LOCAL` et suffixes d'OU `labo.local`. Votre configuration
réelle doit être conservée. Aucun cfg.json n'est inclus dans le correctif.

## Non exécuté ici

Le parseur PowerShell natif, les 25 nouveaux cas Windows, l'interface WPF complète,
la connexion AD et les opérations réelles n'ont pas été exécutés. Aucun EXE n'est
compilé. Les vérifications statiques ne prouvent pas le fonctionnement Windows.
Les anciens rapports de contrôles négatifs conservés dans tests décrivent leurs
livraisons d'origine et ne sont pas de nouvelles validations de la RC8.

`TEST_FILE.cmd` lance les 25 cas avec DataTable et fichiers temporaires réels,
contrôles UI/confirmations simulés, sans lancer GP ni accéder à AD.
`TEST_TOUT.cmd` et le script de build incluent désormais cette huitième suite.

## Traces

- `tests/queue-removal-static-report.json` : nouveaux contrats et défauts injectés.
- `tests/rc8-source-baseline.json` : empreintes de comparaison avec la RC7.
- `tests/rc8-preservation-report.json` : fonctions et ressources conservées.
- `tests/*static-report.json` : rapports statiques actualisés par famille.
- `changes/GP17-RC7-to-RC8.patch` : modifications du moteur.
- `SHA256SUMS.txt` : empreintes du pack complet à sa livraison.
