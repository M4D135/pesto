# Suivi Pesto — 14 octobre 2026, après-midi

Ce relevé complète le point du matin. Il ne réécrit pas les archives. Le catalogue
`DEV/docs/implementation/catalogue-120.json` reste **120/120 `in_progress`**.

## Livré sur `master`

Commit `8851918`. EXE `a754ac8894ebf94e8df8a3c491d1e54c6c9839ba8d02a336b5fc6a60ce6a7678`,
63 composants. Les fonctions CLI sont dans `wad/Pesto-CliHost.ps1`, une seule fois.
Guides régénérés : technicien 28 pages, administrateur 62 pages. Packs neutres dans
`packs/`, empreintes dans `packs/SHA256SUMS`.

Sur ce build, avant toute mutation AD : 406 tests Python sur le Mac, 6 ignorés.
Suites Windows PowerShell 5.1 sur `PESTO-W11-TEST`, dont la relance après le correctif CLI.
Deux contrôles de mise en page large non exécutés : écran 1024 px, seuil 1244 px.

## Les 120 points

| Groupe | Nombre | Suivi |
|---|---:|---|
| Code raccordé | 89 | Présent dans les sources. Non qualifié par une recette du candidat. |
| Évaluations tranchées | 31 | Moteur ou parcours actuel conservé, ou protocole non joué. |
| Clos dans le catalogue | 0 | Une preuve d'exécution manque encore. |

Le détail est dans `DEV/docs/implementation/RAPPROCHEMENT_120.md`. Les 31 évaluations
ne sont pas activées : pas de pool de runspaces, pas de migration PowerShell 7, pas de
jonction hors ligne, pas de signature, pas de second contrôleur.

## Labo du 14 octobre

`LABO-DC01` et `PESTO-W11-TEST` ont été utilisés. Le client s'appelle
**`P111301VA765345`**, domaine `labo.local`.

- Le CLI `-Action Rename -Execute` a répondu **96**, `MutationStarted` faux. Aucune
  écriture. L'automatisation est désactivée dans `C:\PestoDemo\wad\cfg.json`.
- L'interface s'ouvre après acceptation de l'UAC. Le script de renommage, lancé
  élevé, a lu le poste, choisi Paris, le service 765 et le type Portable. La
  confirmation ne s'est pas ouverte : le bouton affiché était « Vérifier l'opération »,
  parce qu'une opération précédente attend une relecture.
- Cette relecture a été faite. Fenêtre « État de P111301LY765128 » : état observé,
  pas une commande. Nom Windows, nom configuré et objet AD valent
  `P111301VA765345`. GUID `b4797c9c-d790-4797-bf71-424a57acb36e`. OU Paris.
  Plan conservé : `P111301LY765128` vers `P111301VA765345`, renommage vrai,
  déplacement faux. Le dialogue a été fermé sans consigner la vérification.
- Au moment de cette note, un nouveau passage du script de renommage est encore
  ouvert après cette fermeture. Le nom local est toujours `P111301VA765345`.

## Reste ouvert

Recette graphique complète du build `a754ac88` : nouveau renommage, redémarrage,
contrôle du nom. Matrices de qualification des points 88, 92, 95 et 98 à 107.
Les suites de tests déjà vertes ne sont pas à rejouer tant que le code ne change pas.
