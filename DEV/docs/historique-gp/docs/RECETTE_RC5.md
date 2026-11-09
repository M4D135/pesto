# Recette RC5 avant déploiement

## Conditions

Poste Windows de test, Windows PowerShell 5.1 x64, extraction complète, configuration
validée, compte AD de test délégué sur une OU de test. Ne pas commencer par le parc
réel. Pas d'EXE compilé ni de validation environnementale livrés.

## A. Tests locaux sans AD

Exécuter `DEBLOQUER_TOUT.cmd`, puis `TEST_TOUT.cmd`. Conserver les cinq rapports :
`windows-test-results.json`, `windows-package-results.json`, `windows-async-results.json`,
`windows-rc4-results.json`, `windows-pilotage-results.json`.

Les suites exécutent le parseur natif, des fonctions extraites avec doublures AD,
les opérations de fichiers temporaires, DataView et des composants WPF isolés.
La nouvelle suite fournit 53 cas, mais elle n'a pas été exécutée dans l'environnement
de livraison. Un échec interdit de conclure à une validation du correctif.

## B. Recette visuelle en démonstration

Lancer `GP.cmd -Demo`. Vérifier RC5 sur les trois fenêtres et les thèmes clair/sombre.
Tester la lecture du tableau à 100 %, 125 % et 150 % d'échelle, un écran de portable,
les barres de défilement, les noms avant/après et le nom figé horizontalement.

Préparer un lot sur des sources fictives présentes dans l'onglet Noms. Vérifier
que l'ajout est décoché, ne redémarre pas et conserve la règle de site. Modifier
les sources après aperçu doit désactiver l'ajout jusqu'à une nouvelle préparation.
Tester un doublon, une source inconnue et une recherche contenant apostrophes,
crochets, pourcentages et astérisques.

Filtrer/trier puis modifier une ligne : seule la ligne réellement sélectionnée
doit changer. Décocher les visibles en filtre « À traiter » doit traiter toutes
les lignes visibles initiales sans sauter la deuxième. Vérifier l'avertissement
pour une ligne cochée masquée. Contrôler en démo ne doit pas lire AD.

Exporter un bilan, vérifier qu'il contient aussi les lignes masquées et affiche
SIMULATION/DÉMO sans les confondre avec une mutation réelle. Aucun site externe
ne doit être requis pour l'ouvrir ou l'imprimer.

## C. Lectures AD réelles, avant toute écriture

Avec la configuration de test et GUI désactivé, préparer une seule ligne. Contrôler
la date, la source, le nom cible, l'OU et les messages. Comparer avec l'annuaire.
Contrôler une cible occupée, une OU inexistante/inaccessible et un objet protégé.
ICMP bloqué ne doit pas suffire à déclarer une mutation impossible.

Pendant la lecture, les formulaires de mutation doivent être verrouillés et Annuler
contrôle disponible. Après annulation, aucun callback tardif ne doit modifier le
nouveau contexte. Le verrou d'une ancienne mutation ne doit pas être effacé.

Déplacer manuellement l'objet de TEST après préparation, puis contrôler : l'ancienne
OU doit être signalée comme dérivée. Recréer la ligne après la relecture, ne pas
modifier son GUID dans un fichier pour contourner cette protection.

## D. Une mutation à la fois sur des postes sacrifiables

| Cas | Attendu |
|---|---|
| Même code site, autre numéro | Renommage seulement, sous-OU inchangée. |
| Autre site | Renommage confirmé puis déplacement vers l'OU prévue. |
| Site changé mais déjà dans l'OU cible | Renommage sans déplacement inutile. |
| Même site, changement de type/service | Renommage seul. |
| Déplacement seul explicite | Aucun renommage. |
| Reboot non coché | Aucun reboot demandé. |
| Protection impossible à restaurer | Code 32, verrou, aucun enchaînement silencieux. |
| Renommage réussi, déplacement refusé | Code 89, reprise déplacement uniquement. |
| Erreur réseau après départ | État incertain/technique, pas de retry automatique. |
| Sauvegarde locale refusée avant départ | NON LANCÉ / 96, pas de faux échec de mutation. |

Vérifier le nom appliqué après le redémarrage explicitement planifié et la réplication
AD. Une lecture sur un seul DC ne prouve pas une convergence de tous les contrôleurs.
Tester ensuite un lot de deux postes, puis seulement augmenter progressivement.

Le chemin hors domaine, l'élévation UAC et la compilation restent à revalider ;
le préparateur de lot est volontairement indisponible hors domaine. Pas de migration
simultanée de centaines de postes comme premier essai.

## Retour de version

Conserver l'ancienne installation et les journaux. Un retour au code RC4 ne défait
aucun renommage ni déplacement AD. Vérifier l'état réel des postes et ne pas
restaurer un vieux checkpoint comme s'il s'agissait d'une transaction réversible.
