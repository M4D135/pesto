# Pesto 1.0 — livraison locale du 15 octobre 2026

## Périmètre

Développement terminé pour les 88 fonctions du catalogue. 19 évaluations sont conclues ;
la mesure prolongée 107 et 12 qualifications externes restent ouvertes. Le
[rapprochement des 120 points](../../DEV/docs/implementation/RAPPROCHEMENT_120.md)
conserve la nature et les preuves de chaque point.

Derniers compléments : planification de lots avec lectures AD ciblées des sources et
collisions, registre partagé consultable sans modification, import CSV avec ensembles
de recherche, journal silencieux écrit pendant l’action, traces bornées de réconciliation.
Les corrections comprennent aussi l’acquittement explicite sans faux succès, les contrôles
légers du renommage distant, la recherche des collisions DNS/SPN, les exclusions AD,
les exports atomiques et les améliorations de navigation, affichage et journal.

## Validations locales

| Contrôle | Résultat | Périmètre |
|---|---|---|
| Python | 513 réussis, 6 ignorés sur 519 | Fichiers, contrats et outils locaux |
| Validation portable | 620 réussis, 0 échec | Source, XML, PE, manifeste et vrai parseur PS 7.4.20 |
| Moteur | 117/117 | Fonctions réelles et doubles AD/Windows |
| Automation | 38/38 | Parcours silencieux et dépendances du runtime |
| Préparation distante | 26/26 | Contrôles de capacités et décision, sans machine distante |
| Lots ciblés | 31/31 | Worker, sources, collisions, contextes périmés et erreurs |
| Noms et registre | 45/45 | Sources des workers, parsing borné, lecture seule |
| Import et lots | 30/30 | Dont 5 000 lignes CSV validées par le helper produit |
| Journal silencieux | 10/10 | Vrai writer C# local, événements pendant le worker, doubles métier |
| Réconciliation | 7/7 | Appels des workers, traces bornées et projection support |
| Reçus et archives | 26/26 | Archives et cohérence des fichiers |
| Intégration | 24/24 | Contrats et parcours locaux |
| Présentation | 52/52 | Contrats d’interface ; aucun rendu WPF exécuté |
| Workbench | 41/41 | Choix, sources, invalidation et reprise |
| Éditeur de configuration | 26/26 | Groupes d’exclusion et formulaire |
| Cache annuaire | 20 contrôles | Helpers et doubles locaux |
| Lanceur C | 48 scénarios, 9 contrôles d’arguments, 2 000 aller-retours, 132 SHA256 | Code C compilé sur Mac, API Windows remplacées |

Les granularités diffèrent ; ces nombres ne forment pas une mesure de couverture globale.
Les [rapports bruts](local/) et leurs [empreintes et contexte](validation-context.json)
sont conservés. Le rapport natif conserve son libellé générique historique « Linux » ;
l’hôte de cette exécution est macOS et aucune API Windows n’a été exécutée.

Après les suites ciblées, seules trois propriétés d’aide XAML et les fins de ligne
originales de deux fichiers ont été corrigées ; la validation source/XML/PE/parser et
les empreintes ont été refaites. Le lanceur a été reconstruit après ces changements.

## Livrables

- [Packs DEV et PROD](../../packs/) : configuration neutre, runtime identique,
  PROD limité à `Pesto.exe` et `wad/`, CRC et SHA256 contrôlés dans [packs-audit.json](packs-audit.json).
- Guides Word/PDF v1.0 : 26 pages technicien, 61 pages administrateur. Rendu relu,
  aucune zone de texte hors marge de sécurité ; [preuve de mise en page](guides-qa.json).
  Les captures proviennent des recettes antérieures ; aucune capture VM nouvelle.
- [Dossier release](release/release.json), [SBOM CycloneDX](release/sbom.cdx.json)
  et [statement in-toto non signé](release/provenance.intoto.json).

## Limites maintenues

Aucun essai VM, lancement Windows, rendu WPF, mutation AD ou renommage distant réel
n’a été effectué sur le build livré ici. David réalise la recette graphique et AD
manuellement. Les preuves C2 et autres recettes antérieures restent liées à leurs builds.
Signature éditeur, App Control, orchestrateurs, licences de redistribution, SMB multi-opérateur,
multi-DC, Narrator et matrice graphique demandent leurs propres preuves. Le dossier release
et les empreintes ne constituent ni une signature de confiance ni une qualification de terrain.
