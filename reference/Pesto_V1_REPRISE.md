# Reprise de Pesto vers la version 1.0

La dernière base source jointe est Pesto 17.0-RC23. Elle n’est pas une version 1.0 terminée. Aucune nouvelle version du moteur n’a été validée dans cette tentative.

## Demande à poursuivre
Finaliser Pesto pour la v1.0 à partir de la RC23 et du suivi des 90 points. Produire un vrai EXE recompilé, les packs PROD et DEV complets, un bilan des tests réellement exécutés et le suivi honnête des points restants. Ne pas remplacer simplement RC23 par 1.0 dans les titres.

## Organisation impérative
PROD contient seulement Pesto.exe et wad à la racine. DEBLOQUER_TOUT.cmd reste présent dans wad/support dans PROD et DEV ; il traite tout le dossier applicatif et n’est pas requis pour démarrer. Le moteur reste PowerShell/WPF et ses empreintes sont incorporées dans le lanceur natif : modifier un composant oblige à recompiler le lanceur.

## Règles à conserver
Jonction locale et renommage unitaire sans file ; lots séparés. Même site : renommage seul et OU inchangée. Nouveau site : déplacement seulement après renommage confirmé. Connexion intégrée après UAC en domaine ; pas de second login automatique. Hors domaine : compte AD explicite. Aucun redémarrage, retrait Entra ou changement de sécurité implicite. Retrait Entra avant renommage uniquement si hybride confirmé et politique autorisée. Pas de WinRM obligatoire. Conservation de cfg, préférences, journaux, reçus et identifiants de stockage GP historiques.

## Points de stabilisation évoqués avant interruption
Revoir et prouver dans le code : effet Move conservé si la restauration de protection échoue ; résultat tardif ne résout pas l’intervention parente ; nom actuel égal au nom futur ne produit pas un faux succès de renommage ; véritables erreurs de syntaxe PowerShell dans les calculs de sites ; contrôle avant connexion de la syntaxe des scripts et de la compilation du writer C#. Ne pas présumer ces correctifs présents : les vérifier sur la base jointe.

## Validation
Les résultats RC23 sont historiques. Refaire les tests portables et la compilation reproductible. Exécuter le parseur PowerShell cible et les tests comportementaux lorsque le runtime est disponible. Distinguer PowerShell Linux des essais Windows PowerShell 5.1, WPF, UAC et AD/Entra. Ne pas annoncer de recette Windows, signature d’entreprise ou fermeture des 90 critères sans preuves.

Cette tentative a pu extraire les fichiers, mais les sorties détaillées des outils n’étaient pas lisibles. Le dossier ne contient donc aucun EXE 1.0 prétendument validé.
