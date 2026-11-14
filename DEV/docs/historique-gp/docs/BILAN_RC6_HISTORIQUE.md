# Bilan de livraison GP 17.0-RC6

Date : 21 septembre 2026. Base : `GP_17_WAD_RC5.zip` fourni dans cette conversation.
Livrables : projet complet et mise à jour sans configuration. Aucun EXE compilé.

## Réalisé dans l'environnement de livraison

| Vérification | Résultat | Portée réelle |
|---|---:|---|
| Contrôles génériques | 56/56 | Encodage, structure lexicale, six gabarits XML, 160 noms publics liés, ressources et dépendances de worker. |
| Callbacks hérités | 25/25 | Portées, contextes, références et gardes de timers. |
| Régressions RC4 | 28/28 | Contrats du remplacement atomique, règle de site et sauvegarde avant lancement. |
| Fonctions RC5 | 53/53 | Lots, lecture AD préalable, identité avant mutation, filtres et export. |
| Interface RC6 | 49/49 | Ressources, templates WPF déclarés, navigation, aides, aperçu, temporisation et dépendances du test isolé. |

**211 contrôles statiques réussis.** Le validateur générique conserve **un avertissement** :
la configuration historique fournie contient le domaine `o.LOCAL` alors que ses OU
se terminent par `labo.local`. Le paquet de mise à jour n'embarque aucune configuration.

**44 défauts injectés dans des copies temporaires ont été détectés** : 10 génériques,
7 callbacks, 7 RC4, 10 RC5, 10 RC6. Cela vérifie la réaction des validateurs à ces
régressions choisies, pas le fonctionnement de Windows ou d'Active Directory.

Le rapport de comparaison confirme : 223 fonctions RC5 non modifiées, 12 fonctions
de présentation/préférences adaptées, 23 nouvelles fonctions de présentation,
aucune fonction supprimée. Les ressources wad autres que le moteur, y compris les
configurations, le module AD et l'icône, ont les mêmes empreintes que dans RC5.

Les contrôles UI couvrent 160 noms publics, 17 colonnes conservées dont six visibles,
132 éléments interactifs munis d'aide dans les six gabarits XAML. Ces métriques sont
issues du source, pas d'un audit dynamique de tous les contrôles générés par WPF.

## Non réalisé ici

**Aucun parseur PowerShell natif, test Windows, chargement WPF réel, rendu ou capture
de l'application, lecteur d'écran, connexion AD, renommage, déplacement, UAC ou
compilation EXE n'a été exécuté dans cet environnement Linux.**

Le scanner lexical Python n'est pas un parseur PowerShell. Le parseur XML ne contrôle
pas toutes les propriétés, surcharges, conversions, résolutions de ressources et
règles de noms du moteur WPF. La présence de garde et l'égalité du moteur RC5 ne
prouvent pas l'absence de régression d'intégration induite par l'interface.

`TEST_INTERFACE.cmd` fournit **38 cas Windows isolés**, dont des chargements du vrai
XAML, navigation par événements, changements de taille, thèmes, aides et timers.
Ils **n'ont pas été exécutés ici**. `TEST_TOUT.cmd` les joint aux cinq suites héritées.
Les rapports natifs ne sont créés que lorsque ces tests sont réellement lancés.

## Sources des résultats

- `tests/static-report.json`, `async-static-report.json`, `rc4-static-report.json`,
  `pilotage-static-report.json`, `ux-static-report.json` : résultats statiques et
  empreinte du moteur contrôlé. Les libellés RC4/RC5 identifient la famille de tests.
- `tests/*checker-selftest-report.json` : défauts injectés et contrôles les détectant.
- `tests/rc6-preservation-report.json` : comparaison RC5/RC6 et empreintes des ressources.
- `tests/rc5-engine-baseline.json` : références des fonctions conservées.
- `changes/GP17-RC5-to-RC6.patch` : diff du moteur, interface incluse.
- `SHA256SUMS.txt` : empreintes des fichiers du paquet, hors le manifeste lui-même.

## Acceptation

Sauvegarder, installer sans remplacer cfg.json, débloquer les fichiers, exécuter les
suites Windows, vérifier le rendu en démo puis effectuer la recette AD sur des postes
non critiques. Voir `RECETTE_RC6.md`. Ni un mode démo réussi ni les tests isolés ne
constituent à eux seuls une certification de production.
