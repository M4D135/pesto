# GP 17.0-RC8 | Retirer une ligne de la file

## Cause identifiée dans la RC7

Le bouton « Annuler » visible sur la capture signifie que le formulaire modifie
une ligne existante. `Update-QueueButtons` interdisait le retrait dès que
`EDIT_ROW_INDEX >= 0`, même sans exécution ou contrôle en cours.
Ce blocage est local à l'interface : ce n'est pas un refus de droits AD.

Dans la RC7, la solution immédiate est : **Annuler**, puis **Supprimer**.
« Annuler » quitte seulement la modification du formulaire. La ligne reste
présente jusqu'à sa suppression explicite.

## Nouveau comportement

Le bouton **Retirer de la file** est visible au-dessus du tableau, à côté de
**Détails**, sans ouvrir « Plus d'outils ». Il agit sur la ligne surlignée, pas
sur toutes les cases cochées. La confirmation indique le nom du poste et précise
qu'aucun ordinateur ni objet Active Directory n'est supprimé ou modifié.

Le retrait est autorisé pendant la modification du formulaire. S'il concerne
la ligne en cours de modification, ses changements non enregistrés sont
abandonnés après confirmation. S'il concerne une autre ligne, le brouillon en
cours reste associé à la même DataRow, même si sa position change.

Le bouton reste bloqué pendant une exécution ou un précontrôle AD. Son aide
au survol indique pourquoi et rappelle la commande d'arrêt ou d'annulation
adaptée. « Annuler » s'appelle désormais **Annuler la modification**.

Le retrait sauvegarde la nouvelle file. En cas d'erreur d'écriture, la ligne et
ses données sont remises à leur place, un message est affiché et aucun retrait
réussi n'est annoncé. En démo/simulation, la non-persistance existante est conservée.
Le journal et l'historique ne sont pas effacés. Retirer un résultat ne revient
pas en arrière sur une opération déjà effectuée.

Un verrou de sécurité existant n'est pas levé par ce bouton. La relecture du
checkpoint conserve maintenant aussi ce verrou quand la file est devenue vide.
La règle renommage/déplacement selon le changement de site reste inchangée.

## Installation sur votre GP déjà configuré

1. Fermer GP et sauvegarder le dossier actuel.
2. Extraire `GP_17_RC8_CORRECTIF_FILE.zip` dans le dossier contenant déjà `GP.cmd`,
   en acceptant les remplacements. Ne pas créer un deuxième sous-dossier GP.
3. Lancer `DEBLOQUER_TOUT.cmd`, puis `GP.cmd`. Le titre doit afficher **17.0-RC8**.

Le correctif ne contient aucune configuration, aucun journal utilisateur,
aucune préférence et aucun fichier d'état réel. Le fichier applicatif remplacé
est `wad/GP-Core.ps1`. Les tests, les documents et le script de build sont aussi
mis à jour. `wad/cfg.json` reste intact.

Le pack complet `GP_17_WAD_RC8.zip` inclut tout le projet, le module AD et `wad`.
Conserver impérativement votre `wad/cfg.json` actuel. La configuration historique
incluse dans le pack complet n'est pas un substitut à votre configuration.
Aucun nouvel EXE compilé n'est fourni. Démarrage : `GP.cmd`.

## Vérifications et recette

Des contrôles de source, XML et conservation des fonctions ont été exécutés ici.
**Aucun lancement Windows, parseur PowerShell natif, rendu WPF ou test AD réel
n'a été exécuté dans cet environnement.**

`TEST_FILE.cmd` fournit 25 cas ciblés sous Windows PowerShell 5.1 x64 : bouton
en mode modification, retrait/refus, annulation, tri/filtre, conservation d'une
autre ligne éditée, sauvegarde, restauration en cas d'erreur, maintien du verrou
et historique. Ces cas utilisent les fonctions extraites de GP, de vraies
DataTable/DataView et des fichiers temporaires ; les contrôles et confirmations
sont simulés. Ils ne lancent pas l'application et ne contactent pas AD.
Ils sont fournis, **pas annoncés comme exécutés ici**.

Recette visuelle conseillée dans `GP.cmd -Demo` : ajouter deux lignes, entrer en
modification de l'une par double-clic, retirer cette ligne, refuser puis accepter
la confirmation, vérifier que seule cette ligne disparaît. Refaire l'essai avec
un tri ou filtre et avec l'autre ligne en modification. Ne pas utiliser cette
RC en production avant la recette Windows et les tests adaptés à votre contexte.
