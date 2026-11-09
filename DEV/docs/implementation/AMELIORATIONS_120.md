# Les 120 améliorations de Pesto

Catalogue autorisé le 13 octobre 2026 pour **Pesto 1.0**. Les 120 points représentent **88 fonctions, 20 évaluations et 12 qualifications** ; ils ne correspondent pas à 120 fonctionnalités déjà testées en conditions réelles.

## État au 15 octobre 2026

- Le code des parcours, diagnostics, automatisations et outils de livraison est présent. Le [rapprochement détaillé](RAPPROCHEMENT_120.md) relie chaque exigence à ses sources et à ses bancs.
- Les derniers compléments de code sont intégrés : vue du registre partagé (**T108**), lecture AD ciblée des lots (**W4RT100**), index de l’import (**T022**) et audit de réconciliation (**F03**). Les six bancs locaux associés passent, avec leurs périmètres détaillés dans le rapprochement. Ces codes Spark sont distincts des numéros 1 à 120.
- Les finitions récentes comprennent l’audit headless au fil de l’eau, les conflits de nom/SPN, le contrôle facultatif d’horloge, les états de lecture des services, les étapes réellement parcourues, les filtres du journal et les exports atomiques. Leurs contrats locaux ne certifient pas le rendu WPF ou une opération AD réelle.
- Les études sont documentées. Le pool de runspaces, le top-k, le delta AD et la migration PS7 restent non activés ; les mesures ou conditions de sécurité ne justifient pas leur remplacement en production. Pour le **point 107**, le banc et le protocole sont livrés, mais la mesure prolongée Windows/WPF reste à réaliser manuellement : aucun résultat sur les fuites n’est acquis.
- Le point **105** est qualifié pour les contrats purs locaux ; les **11 autres qualifications** restent ouvertes dans leur périmètre complet. Les essais GUI/AD et les environnements externes seront vérifiés manuellement ; aucune nouvelle campagne VM n’est lancée dans cette passe.
- **Les 88 réalisations fonctionnelles sont terminées localement.** Les guides définitifs sont produits et relus (technicien : 26 pages ; administrateur : 61), et l’assemblage DEV/PROD neutre est réalisé. La publication Git/CI reste une étape distincte.
- Les preuves locales consignent **513 tests Python réussis sur 519, 6 ignorés**, **620 contrôles source/XML/PE réussis**, ainsi que les contrôles natifs du lanceur C avec API Windows doublées. Ces unités ne sont pas additionnées et ne qualifient pas Windows/AD.

Les packs restent classiques : `Pesto.exe` et le dossier `wad/`, avec une configuration neutre. Le choix aléatoire reste actif parmi tous les candidats libres des filtres. La coordination commune et la réservation AD restent facultatives et désactivées par défaut.

## Lecture de la liste

Les numéros et exigences restent stables. **Fonction** désigne une évolution du produit, **Évaluation** une étude avant décision et **Qualification** une vérification qui exige sa preuve d’exécution. Le [catalogue JSON](catalogue-120.json) distingue code présent, étude conclue, mesure restante et qualification restante. Ses références de tests décrivent la couverture prévue ; elles ne constituent pas à elles seules un résultat PASS.

## Interface et navigation

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 1 | Confirmation dimensionnée au contenu | Fonction |
| 2 | Confirmation avant/après et bouton explicite | Fonction |
| 3 | Alléger le formulaire unitaire | Fonction |
| 4 | Petite fenêtre avec un seul axe de défilement | Fonction |
| 5 | Préparer une autre opération après résultat en gardant reçu et suivi facultatif | Fonction |
| 6 | Volet latéral de détails | Fonction |
| 7 | Interventions récentes compactes à l’accueil | Fonction |
| 8 | Hiérarchie visuelle sémantique sobre | Fonction |
| 9 | F6/Maj+F6 entre grandes zones | Fonction |
| 10 | Annonces Narrator utiles et regroupées | Fonction |
| 11 | Palette avec synonymes et classement | Fonction |
| 12 | Notification facultative de fin de lot | Fonction |

## Nommage et capacité

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 13 | Recherche exacte de nom candidat ; aléatoire conservé | Fonction |
| 14 | Segments visuels du nom et différences | Fonction |
| 15 | Tableau de capacité interactif avec seuils | Fonction |
| 16 | Provenance et âge des exclusions de noms | Fonction |
| 17 | Suggestions matérielles modifiables | Fonction |
| 18 | Vue réutilisable des anomalies de convention | Fonction |

## Lots et collections

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 19 | Planificateur de lot autonome | Fonction |
| 20 | Import CSV/tableau collé avec mapping des colonnes | Fonction |
| 21 | Toutes les erreurs par ligne dans grille éditable | Fonction |
| 22 | Édition groupée des lignes préparées avec aperçu et invalidation | Fonction |
| 23 | Annuler les changements locaux de file, jamais une mutation AD | Fonction |
| 24 | Regroupement visuel sans changer ordre exécution | Fonction |
| 25 | Préréglages colonnes Essentiel/Diagnostic | Fonction |
| 26 | Vues filtrage/tri enregistrées sans consentement ni sélection exécutante | Fonction |
| 27 | Collections dynamiques enregistrées | Fonction |
| 28 | Delta collection puis instantané de lot | Fonction |

## Configuration

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 29 | Recherche dans paramètres | Fonction |
| 30 | Diff config lisible, JSON avancé | Fonction |
| 31 | Sélecteur OU avec recherche et DN manuel | Fonction |
| 32 | Erreurs validation AD reliées aux réglages | Fonction |
| 33 | Rétablir champ ou rubrique | Fonction |
| 34 | Conflit modification externe cfg.json | Fonction |
| 35 | Exemples de noms/OU sur brouillon config | Fonction |
| 36 | Effets immédiats/redémarrage/invalidation avant sauvegarde | Fonction |
| 37 | Plusieurs brouillons nommés | Fonction |
| 38 | Partager collections favoris/modèles avec aperçu compatibilité | Fonction |

## Diagnostics Active Directory et Windows

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 39 | Diagnostic DNS suffixes SRV découverte DC Windows | Fonction |
| 40 | Diagnostic incohérences DNS/SPN pertinentes sans nettoyage | Fonction |
| 41 | Tests transport adaptés à action, ping indicatif | Fonction |
| 42 | Décalage horloge observé sans correction automatique | Fonction |
| 43 | Diagnostic réutilisation compte précréé Netjoin | Fonction |
| 44 | Capacités compte par action : connu/refusé/non certifiable | Fonction |
| 45 | Raisons redémarrage et conséquence | Fonction |
| 46 | NetSetup corrélé intervalle/noms/codes opération | Fonction |
| 47 | États AD/Entra observés ou inconnus | Fonction |
| 48 | Actions de diagnostic guidées lecture seule | Fonction |

## Interventions et support

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 49 | Libellé/filtre suivi facultatif cohérent | Fonction |
| 50 | Chronologie par identité stable malgré renommages | Fonction |
| 51 | Retiré sur demande de David le 16 octobre 2026 | Hors périmètre |
| 52 | Comparaison explicite deux reçus | Fonction |
| 53 | Archivage consultable des reçus terminés, préserver non résolus | Fonction |
| 54 | Dossier support par opération aperçu/masquage | Fonction |

## Mesures et performances

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 55 | Benchmark froid/chaud/volumes/latence/mémoire/UI reproductible | Fonction |
| 56 | Évaluer pool runspaces lectures isolé auth | Évaluation |
| 57 | Coalescer lectures identiques | Fonction |
| 58 | Évaluer traitement progressif inventaire borné avec complétude | Évaluation |
| 59 | Évaluer index inventaire C# compact | Évaluation |
| 60 | Évaluer cache AD incrémental complet/invalidation/suppressions/DC | Évaluation |
| 61 | Évaluer mises à jour WPF seulement lignes modifiées | Évaluation |
| 62 | Index reçus incrémental et projections réutilisées | Fonction |
| 63 | Évaluer précompilation des Add-Type C# | Évaluation |
| 64 | Évaluer pagination/top-k Common.Query | Évaluation |

## Architecture du moteur

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 65 | Module moteur importable indépendant WPF | Fonction |
| 66 | Générer/valider fermeture dépendances workers par AST | Fonction |
| 67 | Contrats typés plans/résultats/contextes | Fonction |
| 68 | Transitions et invariants états formalisés | Fonction |
| 69 | Migrations schémas cfg/brouillons/reçus sauvegardant original | Fonction |
| 70 | Codes erreurs natifs typés plutôt que messages localisés | Fonction |
| 71 | Journal structuré corrélé opération/worker/étape/build | Fonction |
| 72 | Évaluer surcharge/reprises lectures bornées, jamais mutation auto | Évaluation |

## Modules communs

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 73 | Primitives communes validation/résultat/sérialisation | Fonction |
| 74 | Instrumentation commune bornée événements/journal async | Fonction |
| 75 | Composants WPF communs séparés du Core générique | Fonction |
| 76 | Primitives communes IO atomique et sauvegarde | Fonction |
| 77 | Tests compatibilité consommateurs/versions/downgrade | Fonction |
| 78 | Pipeline release commune build/hash/locks consommateurs | Fonction |

## Automatisation et déploiement

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 79 | CLI préparation/rename/move avec moteur et protections | Fonction |
| 80 | CLI inspection lecture seule JSON | Fonction |
| 81 | Exporter/importer plan exécutable après revalidation | Fonction |
| 82 | Clé idempotence externe et rejet payload différent | Fonction |
| 83 | Adaptateurs ConfigMgr/PSADT/PDQ/DeployR | Fonction |
| 84 | Kit premier boot SYSTEM avec contexte réseau et credentials | Fonction |
| 85 | Métadonnées séquence/campagne/étape/build autorisées | Fonction |
| 86 | Contrats JSON et codes retour stables documentés | Fonction |

## Fabrication et livraison

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 87 | CI racine réellement active et chemins DEV corrigés | Fonction |
| 88 | Signature réelle outillée EXE/scripts/DLL confiance/horodatage | Qualification |
| 89 | Toolchain épinglée et builds reproductibles comparés | Fonction |
| 90 | SBOM standard | Fonction |
| 91 | Attestations provenance artefacts | Fonction |
| 92 | Qualification App Control/WDAC et diagnostic compatibilité | Qualification |
| 93 | Installation/désinstallation/détection gérée optionnelle préservant données | Fonction |
| 94 | Canaux pilote/général sur updater sûr | Fonction |
| 95 | Provenance versions/signature/droits redistribution DLL Microsoft | Qualification |
| 96 | Dossier release unique versions/packs/guides/tests/limites | Fonction |

## Tests et documentation

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 97 | Rapports test distinguant plateforme/doubles/WPF/app/AD/build | Fonction |
| 98 | Matrice Windows/langues/.NET/comptes/politiques | Qualification |
| 99 | Tests GUI end-to-end complets | Qualification |
| 100 | Régressions visuelles DPI/résolutions/zoom/thèmes/petites fenêtres | Qualification |
| 101 | Recette clavier/Narrator complète | Qualification |
| 102 | Injection pannes frontières persistance/effets natifs | Qualification |
| 103 | Concurrence deux opérateurs SMB réel | Qualification |
| 104 | Tests délai réplication réel sans changer DC automatiquement | Qualification |
| 105 | Tests génératifs contrats Unicode/DN/JSON/limites/états | Qualification |
| 106 | Tests fuite secrets logs/erreurs/exports/captures/adaptateurs | Qualification |
| 107 | Évaluer longues sessions mémoire/handles/abonnements WPF | Évaluation |
| 108 | Guide court par tâches/aide contextuelle/manuels | Fonction |

## Extensions et études

| N° | Amélioration | Nature |
| ---: | --- | --- |
| 109 | Évaluer jonction hors connexion : blob secret | Évaluation |
| 110 | Profils multi-domaines retirés sur demande de David le 16 octobre 2026 | Hors périmètre |
| 111 | Évaluer scénarios administrés champs autorisés/obligatoires/verrouillés | Évaluation |
| 112 | Évaluer canal ADMX/GPO et priorité visible | Évaluation |
| 113 | Retiré sur demande de David le 16 octobre 2026 | Hors périmètre |
| 114 | Évaluer attributs AD complémentaires limités avec diff/reçu | Évaluation |
| 115 | Évaluer Event Log ou collecteur audit externe | Évaluation |
| 116 | Retiré sur demande de David le 16 octobre 2026 | Hors périmètre |
| 117 | Évaluer approbation séparée campagnes sélectionnées | Évaluation |
| 118 | Mode incident explicite suspendant nouvelles mutations | Fonction |
| 119 | Évaluer conventions de nommage supplémentaires | Évaluation |
| 120 | Migration PowerShell 7/.NET moderne retirés sur demande de David le 16 octobre 2026 | Hors périmètre |

Les [correctifs de clôture](../../../preuves/correctifs-ci-2026-10-15/README.md) renforcent le masquage des journaux, les résultats de déploiement et le scanner, et corrigent les deux échecs du CI précédent. Le corpus final passe 543 tests Python et 620 contrôles portables.
