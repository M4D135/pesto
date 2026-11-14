# Pesto 17.0-RC20 : chargement des noms disponibles

## Modification intégrée

La page « Noms disponibles » affiche désormais un état de chargement au centre de la liste. La barre est indéterminée : elle indique une activité, jamais un pourcentage inventé. Le titre suit l'étape en cours, le compteur indique la quantité réellement lue ou examinée dans cette étape, et un chronomètre indique le temps écoulé.

Deux travaux sont effectués hors du thread de l'interface : la lecture d'Active Directory et, maintenant, l'indexation puis le calcul des noms. Le second utilise un runspace de lecture séparé. Les mises à jour WPF restent sur le Dispatcher. Les nouveaux noms sont affectés à la grille seulement après réussite complète de la lecture et du calcul.

Une absence temporaire dans une collecte partielle ne permet pas de déclarer un nom libre. C'est pourquoi cette version privilégie un indicateur pendant la collecte plutôt qu'une liste de noms « disponibles » alimentée à partir d'un scan incomplet. Il n'y a pas de nouvelle lecture AD déclenchée en tapant dans la recherche : les filtres recalculent la vue du dernier inventaire complet.

## Comportements

- À la première ouverture : lecture de l'inventaire si nécessaire, progression, puis liste.
- À l'actualisation : ancienne liste masquée, indicateur visible, compteur de lecture réel, puis remplacement cohérent des résultats.
- Pendant un calcul de filtre : ancien résultat invalidé immédiatement ; une réponse issue d'un ancien filtre ou d'un inventaire remplacé ne peut pas réapparaître.
- Tant que la liste n'est pas prête : copie, export et boutons du prochain nom indisponibles.
- Échec ou délai dépassé : arrêt de l'indicateur, explication et bouton « Réessayer », sans publication du résultat partiel.
- Zéro résultat : message « Aucun nom pour ces filtres », distinct d'un chargement et d'une erreur.
- Liste prête : nombre de noms affichés, nombre de disponibles, date de l'inventaire et rappel du périmètre. Une suggestion n'est pas une réservation dans AD.
- Fermeture : arrêt du minuteur d'affichage. La supervision asynchrone existante reste responsable du nettoyage des workers de lecture.

La grille conserve sa virtualisation. Pour éviter un résultat excessivement volumineux avec « jusqu'à 999 » et tous les sites/équipes, l'affichage est borné à 50 000 lignes correspondant aux filtres. Une mention explicite demande de préciser le site ou l'équipe si cette borne est atteinte et qu'il existe des lignes supplémentaires. Les compteurs et l'export portent alors sur les lignes affichées, pas sur un total supposé.

Le choix de couleur suit les ressources du thème clair/sombre. Aucun nouveau login, aucune mutation AD, aucun redémarrage, aucun changement de traitement Entra n'est ajouté par cette page.

## Installer

1. Vérifier l'issue des anciennes opérations avant de fermer Pesto. Sauvegarder l'installation.
2. Conserver la configuration opérationnelle `wad\cfg.json`, les préférences, les journaux et les états de reprise. Le fichier fourni pour une installation neuve est toujours un modèle non configuré.
3. Remplacer ensemble `Pesto.exe`, les composants applicatifs `wad\Pesto-*` et `wad\package.json`, dans le même dossier. Ne pas remplacer seulement un PS1 : le nouveau lanceur incorpore les empreintes des nouveaux composants.
4. Après vérification de la provenance, lancer `wad\support\DEBLOQUER_TOUT.cmd` si nécessaire, puis `Pesto.exe --check`.
5. Tester la version sur une copie de recette avant utilisation connectée. La version affichée est `17.0-RC20`.

PROD conserve uniquement `Pesto.exe` et `wad` à sa racine. DEV ajoute les sources, tests et outils. Le support et les tests ne sont pas des dépendances obligatoires au lancement.

## Validation réalisée et limites

Réalisé dans l'environnement Linux de préparation :

- 52 tests Python réussis, dont 12 contrôles de source/XML spécifiques aux noms.
- 267 contrôles portables du source, des ressources, du manifeste et du PE réussis.
- Compilation croisée du lanceur x64. Deux compilations produisent le même EXE de 108 544 octets.
- SHA-256 EXE : `1766c70ecc98a2047743bee0c9682417332db0260112d36ab51a77c0aa7c9e74`.
- Comparaison des fonctions à la RC19 : 8 fonctions existantes modifiées, 6 ajoutées, 430 inchangées après normalisation de la seule version. Cette comparaison ne couvre pas les raccordements hors fonctions ni le XAML ; voir `RC20_FUNCTION_CHANGES.json`.

**Non exécutés ici :** parseur Windows PowerShell 5.1, tests PowerShell comportementaux, rendu WPF, démarrage Windows du PE, UAC, registre et domaine réel. Les contrôles lexicaux Python ne remplacent pas le parseur natif. Aucune accélération chiffrée ni fluidité mesurée sur Windows n'est revendiquée. L'EXE reste non signé. Les limites de l'audit RC19 restent applicables ; cette version ne clôt pas les 44 points.

Les rapports courants sont `RC20_VALIDATION.json` et `RC20_preuves`. Les rapports de versions antérieures restent historiques.

## Tests Windows fournis

`TEST_NOMS.cmd` lance 25 cas PowerShell isolés, dont 3 cas utilisant le vrai XAML et de vrais timers/runspaces WPF. Il n'appelle pas AD, ne lance aucun renommage et ne demande pas d'UAC. Les cas portent notamment sur les noms déjà utilisés, les réservations de file, les filtres, l'inventaire vide, les bornes, les erreurs, le rejet des retours périmés et le calcul asynchrone. Ces 25 cas sont fournis, pas présentés comme déjà passés.

`TESTER.cmd` enchaîne la suite existante puis ces nouveaux tests si la première réussit. Son option `-Capture` reste gérée par la suite générale. Le fichier historique `Test-Pesto19.ps1` est conservé comme chemin interne, avec des attentes de version RC20.

Recette manuelle sur Windows de test :

1. Ouvrir Noms avec un inventaire non chargé et observer l'indicateur dès le début.
2. Actualiser un périmètre comportant plusieurs milliers de postes : les quantités lues évoluent sans prétendre connaître le total final.
3. Changer rapidement les filtres et le texte, puis vérifier que seul le dernier choix est publié.
4. Simuler un défaut de lecture dans une fixture : aucune liste de noms libres partielle, bouton Réessayer visible.
5. Essayer un filtre vide de résultats, puis un filtre large avec la borne d'affichage.
6. Vérifier en clair et sombre, à 100/125/150/200 %, et sur une fenêtre étroite : titre, compteur, temps écoulé et bouton lisibles.

## Références techniques

Ces sources décrivent les mécanismes WPF, pas une validation du projet sur Windows :

- Microsoft, ProgressBar.IsIndeterminate : https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.progressbar.isindeterminate?view=windowsdesktop-9.0
- Microsoft, WPF threading model : https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model
