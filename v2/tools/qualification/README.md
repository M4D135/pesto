# Outils de qualification : portée des recettes

Les outils C# `Pesto.UpdateQualification` et les scripts `Invoke-NativeUpdate*` / `Invoke-DevRebuildQualification.ps1` sont appelés par la CI courante. Leurs résultats sont liés au SHA et aux packs de leur campagne ; ils ne prouvent aucune opération AD réelle.

Les pilotes `lab-driver.mjs`, `gui-session1.mjs`, `fetch-runtime.mjs` et `deploy-pack.mjs` conservent la recette datée des 24–25 octobre 2026. Ils portent les identités, chemins et versions de ce banc : notamment runtime 155 et pack 2.0.0. Ils ne sont pas appelés par la CI LIGHT actuelle, qui récupère son runtime 156 épinglé directement dans le workflow.

Ces pilotes sont des archives de recette, pas des commandes de reprise du banc courant. Ne pas changer leurs versions ou empreintes pour les rejouer : toute nouvelle qualification utilise sa procédure autorisée, ses identités vérifiées et ses propres preuves. Aucun lancement de VM n’est requis pour lire ou tester la logique portable de Pesto.
