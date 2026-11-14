# GP 17.0-RC12 : connexion compacte inspirée de RBP

## Ce qui est livré

Le login a été modifié dans le code WPF, pas sous forme d'image. Il reprend la disposition de la capture RBP : badge à gauche du titre, deux champs, case de mémorisation, petit bouton Annuler et bouton de connexion principal, option de session Windows en dessous.

- Largeur de 460 unités WPF ; hauteur ajustée au contenu, sans les 700 pixels imposés auparavant.
- `ResizeMode="NoResize"`, état normal et garde-fou contre la maximisation. Aucun bouton d'agrandissement ni réduction dans le login. La fenêtre principale reste redimensionnable.
- Hauteur et largeur maximales limitées à la zone de travail. Un défilement vertical reste possible sur un petit écran ou avec une forte mise à l'échelle.
- Texte et puces du mot de passe dans les contrôles WPF natifs, avec hauteur minimale de 44, sans marge doublée.
- Messages d'erreur et progression masqués au repos ; ils prennent leur place seulement lorsque nécessaire. Les erreurs longues reviennent à la ligne.
- Infobulles sur chaque commande interactive, également sur les commandes désactivées, et descriptions accessibles.
- Entrée valide ; Échap annule. Si un identifiant est déjà mémorisé, le focus arrive sur le mot de passe.
- Les ressources clair/sombre existantes sont conservées.

## Mémoriser uniquement l'identifiant

La case est désactivée par défaut. Après une connexion explicite réussie, elle enregistre uniquement le nom de compte, le domaine, la version du format et le choix de mémorisation. Elle ne contient aucun mot de passe, SecureString ou PSCredential.

La préférence se trouve dans `login.json`, dans le répertoire d'état existant de GP associé à la configuration et au profil Windows qui exécute GP. Elle n'est pas écrite dans `cfg.json` ni dans un fichier partagé avec le projet. Une élévation sous un autre compte Windows implique le profil de ce compte.

Décocher efface immédiatement cette préférence, même si la connexion suivante est annulée. Cocher sans réussir la connexion n'enregistre rien. Le mot de passe du champ est effacé à la fermeture ; le credential nécessaire aux opérations reste en mémoire pendant la session GP comme auparavant.

## Démarrage et authentification

Le ZIP fourni était en RC10. Cette livraison conserve les corrections RC11 : lanceurs, `wad\GP-Startup.ps1`, élévation UAC avant le login et refus des mutations locales non élevées.

Le bouton « Utiliser mon compte Windows » conserve son fonctionnement RC11 : lectures et déplacements selon les droits de cette identité. Les chemins de renommage et de jonction actuels exigent encore un credential de domaine explicite. Cette limitation figure dans l'infobulle et la description accessible ; le redesign ne la supprime pas.

Il ne s'agit pas d'une fusion de l'authentification UAC et de l'authentification AD. Depuis une session standard, l'UAC peut demander un compte administrateur, puis GP un compte de domaine. Aucune nouvelle promesse de connexion unique n'est faite.

## Installation

Fermer GP seulement après avoir vérifié l'issue des anciennes opérations. Sauvegarder l'installation et sa configuration active.

Pour le correctif, extraire tout le contenu à côté de `GP.cmd`, sans deuxième dossier GP. Remplacer les lanceurs, `wad\GP-Core.ps1` et `wad\GP-Startup.ps1`, pas seulement le moteur. Le correctif ne livre aucun `cfg.json` ni préférence utilisateur.

Lancer `DEBLOQUER_TOUT.cmd`, puis `APERCU_LOGIN.cmd` pour examiner la fenêtre isolée. Aucune connexion AD ni saisie réelle n'est nécessaire dans cet aperçu. Lancer ensuite `TEST_LOGIN_COMPACT.cmd`, et `TEST_TOUT.cmd` pour les suites locales plus larges. Ouvrir le logiciel avec `GP.cmd` et vérifier la version 17.0-RC12.

Le pack complet conserve exactement la configuration du ZIP reçu. Celle-ci mentionne `o.LOCAL` avec des OU se terminant par `DC=labo,DC=local`. Si cette copie a été anonymisée, remettre la configuration opérationnelle avant une connexion réelle. Aucune valeur de domaine ou d'OU n'a été inventée pour la remplacer.

## Ce qui ne change pas

Les fonctions métier de RC11 sont inchangées : traitement Entra préalable au renommage, protection AD, supervision, file, historique et règles de déplacement. Même site : renommage seul. Site différent : renommage puis déplacement après résultat confirmé. Aucun redémarrage ajouté.

La jonction au domaine utilise encore le parcours existant. Le nouvel écran sans file décrit dans `PROPOSITION_AJOUT_DOMAINE.md` est une proposition, non implémentée dans cette RC12.

## Validation

Les contrôles source/XML et de conservation des fonctions métier sont exécutés dans l'environnement de livraison. Ils ne constituent pas une exécution de PowerShell Windows, de WPF, de l'UAC ou d'Active Directory. Les tests Windows fournis sont à exécuter sur un poste de recette. Aucun nouvel EXE n'est compilé.

Référence technique du comportement NoResize : https://learn.microsoft.com/en-us/dotnet/api/system.windows.resizemode
