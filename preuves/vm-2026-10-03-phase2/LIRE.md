# Campagne 4 — VM PESTO-W11-TEST, 3 octobre 2026 (phase 2, interface sans mutation)

- Session **console** de `labadmin` (ouverture automatique activée par David, mot de passe tapé par lui, jamais vu par
  Claude), Windows PowerShell 5.1.26100.6584, hors domaine, DC joignable. Aucune UAC, aucun AD réel, aucune mutation.
- Pilotage par Claude, sans humain à l'écran : tâches planifiées interactives (jeton non élevé), captures d'écran,
  UI Automation, clavier et souris simulés. Ce n'est pas une relecture visuelle par un utilisateur.
- Packs : `e31dbb9f…` (1.3, premier 2.1), puis `3676b63e…` (correctif démo), puis `6702949d…` (accessibilité).

| N° | Résultat | Preuve |
|---|---|---|
| 1.3 | PASS : boîte « Pesto - Contrôle du pack » en console, texte complet, fermée par Entrée, code 0 | `1.3-check.png` |
| 2.1 | **Défaut bloquant** : `DEMO.cmd` → « erreur fatale : Argument types do not match » (`New-DemoComputers`, `@()` sur une `List[object]` créée par `New-Object`). Corrigé (`2d5c182`) : fenêtre « Pesto 1.0 \| Gestion des Postes », pas d'UAC, 0 connexion au DC | `2.1-journal-erreur-fatale.log`, `2.1.png` |
| 2.6 | PASS : Ctrl+K ouvre la palette, focus dans la recherche, filtre « 1 commande(s) », Échap ferme, 0 connexion au DC ; Ctrl+K fiable trois fois de suite. **Défaut d'accessibilité** corrigé (`5bb0ba7`) : commandes annoncées `@{Id=...}` | `2.6-*.png`, `2.6-*.txt` |
| 2.7 | PASS : fiche « État de PESTO-W11-TEST », Relire / Fermer, Échap rend le focus à « État du poste ». Remarque : à l'ouverture le focus reste sur la fenêtre | `2.7-fiche.png`, `2.7.txt` |
| 2.8 | PASS : « Performance observée », attente / travail / total distincts, 200 échantillons au plus, « Returned » expliqué | `2.8-performance.png` |
| — | **Défaut d'accessibilité** corrigé (`5bb0ba7`) : 0 élément UI Automation sous `MainTabs` (pages invisibles pour le Narrateur) ; 145 après correctif | rapport de session |
| 2.2 | PASS : démo de jonction affichée, pas d'UAC, 0 connexion au DC | `2.2-demo-jonction.png` |
| 2.3 | FAIL : aperçu de connexion obsolète, trois erreurs successives (deux corrigées, `ca7ba5b`) | `2.3-erreur-*.png` |
| 2.4 | Bloqué : « Corriger la configuration » (`cfg.json` modèle) | — |
| 2.5 | PASS partiel : clair / sombre lisibles à 100 % ; échelles 125-200 % non jouées. Fenêtres blanches des premiers essais = premier rendu > 1 min sur la VM saturée (ancien et nouveau pack identiques après 75 s) | `2.5-*.png` |
| 2.5b | PASS : « Suivre Windows » + contraste élevé, couleurs système lisibles, retour normal | `2.5b-*.png` |
| — | Liste des thèmes annoncée `@{Key=...}` : corrigé (`ca7ba5b`), vérifié « Clair / Sombre / Suivre Windows » | rapport de session |

Remarques cosmétiques : tableaux de 2.7 et 2.8 mal alignés (police proportionnelle) ; valeurs « (mode GUI) » affichées
comme OU en démonstration.

## 4 octobre, nuit : constats P1, P2, P3, O4 (EXE `4b08eb94…`)

- P1 : focus sur « Fermer » à l'ouverture de la fiche État, rendu à « État du poste » après Échap.
- P2 : tableaux des fiches État et Performance en Consolas, colonnes alignées (`p2-performance-07c6ea1c.png`).
- P3 : plus de « (mode GUI) » affiché ; « Démonstration : aucune OU lue » (`p1-p3-fiche-etat-4b08eb94.png`).
- Contrôles : `--check-json` Runtime PASS (38, 27, 3, AuditWriter PASS), stabilisation 21/21 sous 5.1.
- O4 (outillage Python, pas de Windows nécessaire) : 5 tests de version dans `tests/test_update.py`.

