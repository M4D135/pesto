# Recette GP RC6

## Avant tout

Sauvegarder l'installation complète. Maintenir le même chemin de cfg.json pour retrouver
l'état de reprise existant. Ne pas supprimer ou contourner un verrou par déplacement du
projet. Conserver les journaux d'un essai avant de recommencer une mutation incertaine.

## Tests fournis, à exécuter sous Windows

`TEST_INTERFACE.cmd` lance 38 cas en Windows PowerShell 5.1 x64 STA. La suite extrait
seulement les fonctions requises via le parseur natif. Elle ne démarre pas le corps du
moteur et n'importe pas le module AD. Elle charge le vrai XAML principal dans une fenêtre
isolée, transparente et hors écran. Elle vérifie les ressources, FindName, aides,
colonnes, thèmes, navigation, mise en page large/compacte, timers et fonctions d'aperçu.
Des doubles remplacent les accès AD, l'exécution de file et la sauvegarde des préférences.

Le rapport n'est créé qu'à l'exécution : `tests/windows-ui-results.json`.
`TEST_TOUT.cmd` lance aussi les cinq suites héritées dans des processus séparés.
Ne pas confondre le rapport statique livré avec les rapports Windows locaux.

## Recette visuelle en démonstration

Lancer `GP.cmd -Demo`, puis vérifier les points suivants.

| Essai | Résultat à observer |
|---|---|
| Largeur 1460, puis 1100, puis large | Aperçu à droite, puis en dessous, puis à droite. Aucun contrôle dupliqué ou disparu. |
| Résolutions habituelles, DPI 100/125/150 % | Champs et boutons accessibles ; défilement utilisable ; commandes d'exécution visibles. |
| Menu latéral et Ctrl+1/2/3 | Bonne page ; brouillon et file conservés ; aucune opération exécutée. |
| F1, Tab, Maj+Tab, flèches des listes | Aides et navigation cohérentes. Vérifier les listes éditables et la saisie du service. |
| Champs et commandes grisés | Aide visible au survol, notamment Ajouter, Exécuter et Déplacer automatique. |
| Sélection site/type/service | Nom proposé, raison d'action et emplacement prévu cohérents. |
| Ajouter puis trier/filtrer | Bonne ligne dans la file, avertissement de sélection masquée, aperçu de file exact. |
| Colonnes techniques | 6 colonnes simples, 17 en détail, sans modifier une ligne. |
| Thème clair/sombre puis relance | Choix conservé, texte lisible, états de champ et menus cohérents. |
| Noms, paramètres, journal, aide | Fonctions héritées disponibles ; confirmer les fenêtres secondaires. |
| Historique vide | Message explicite, pas de faux lots de démonstration annoncés comme réels. |

En mode réel, tester également le thème et les erreurs de connexion : texte long,
mot de passe invalide, annulation, session Windows, délai de lecture. La démo saute
l'authentification et ne peut donc pas valider visuellement cet écran.

## Recette métier sur des postes non critiques

Utiliser la configuration réelle conservée et des comptes autorisés. Ne pas tester
sur un lot de production tant que les cas isolés ci-dessous ne sont pas acceptés.

| Cas | Attendu |
|---|---|
| PR vers VA | Aperçu renommer puis déplacer ; nom confirmé avant le déplacement. |
| VA vers VA, numéro ou service différent | Renommage seul ; OU actuelle inchangée. |
| Site différent, objet déjà dans la bonne OU | Pas de déplacement supplémentaire inutile. |
| Déplacement seul explicite | Nom inchangé ; destination contrôlée. |
| Lire le poste ou Entrée | Lecture seulement ; aucune ligne ajoutée ou exécutée. |
| Frappe rapide puis édition d'une autre ligne | Une ancienne lecture temporisée ne remet pas son brouillon dans le formulaire. |
| Reboot non coché | Aucun redémarrage demandé. |
| Renommage réussi, déplacement refusé | Résultat partiel ; reprise du déplacement seulement. |
| Résultat incertain ou protection non rétablie | Verrou conservé ; pas de relance automatique. |
| Mode hors domaine | Jonction du PC local uniquement ; aucune extension implicite des droits. |
| Contrôle AD préalable | Lecture uniquement, résultat daté, aucun droit de mutation certifié. |

Confirmer le nom effectif du poste, son objet AD, son GUID et son OU en dehors de GP.
La validation finale après redémarrage dépend de votre procédure de déploiement.

## Retour arrière

Fermer GP sans mutation en cours. Restaurer les fichiers RC5 depuis la sauvegarde,
mais conserver les traces et états produits pour examiner toute opération incertaine.
Un retour de code n'annule ni un renommage, ni un déplacement, ni une jonction déjà faits.
