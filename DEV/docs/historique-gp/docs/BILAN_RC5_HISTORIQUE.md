# Bilan de livraison GP 17.0-RC5

Date : 21 septembre 2026. Base exacte : `GP_17_WAD_RC4.zip` fourni dans la conversation.
Livrable : source complet et mise à jour sans configuration. Aucun nouvel EXE compilé.

## Exécuté dans cet environnement

| Contrôles | Résultat | Ce que le résultat signifie |
|---|---:|---|
| Génériques | 56/56 | Encodage, structure lexicale, six gabarits XML/XAML, 103 contrôles principaux, dépendances et chemins wad. |
| Callbacks RC3 | 25/25 | Gardes de source concernant la portée, les contextes et la gestion des timers. |
| Régressions RC4 | 28/28 | File.Replace/NullString, règle de site, sauvegarde avant worker, absence de replay implicite. |
| Innovations RC5 | 53/53 | Liste blanche du worker en lecture seule, génération de lots, identité avant mutation, sélection filtrée, exports et dépendances des tests. |

**162 contrôles statiques passent.** Ils ne sont pas 162 tests PowerShell ou
AD réussis. Le scanner lexical n'est pas le parseur natif PowerShell, le parseur XML
n'est pas le moteur de rendu WPF et la présence d'une garde n'en prouve pas toute
la sémantique à l'exécution.

Les validateurs ont également été confrontés à **34 défauts injectés dans des
copies temporaires**, tous détectés : 10 génériques, 7 callbacks, 7 RC4 et 10 RC5.
Ce sont des tests des détecteurs de source, pas des tests d'opérations Windows.
Aucune variante défectueuse n'est incluse comme moteur exécutable.

Les quatre configurations, le module AD, les icônes, les lanceurs et le déblocage
ont été comparés à la RC4 : leurs octets sont identiques. Le rapport détaillé est
`tests/rc5-preservation-report.json`. Les archives finales sont contrôlées par CRC,
liste de fichiers et SHA-256 lors de l'empaquetage.

## Fourni, mais non exécuté ici

Le parseur natif Windows PowerShell, les cinq suites Windows, le lancement complet
WPF et son rendu, l'authentification AD, les lectures réelles, RPC/WMI, la jonction,
le renommage, le déplacement, la protection AD, UAC, les redémarrages et PS2EXE.
Aucune CI Windows n'a été lancée à distance. Aucun rapport Windows réussi n'est
fabriqué dans l'archive.

`TEST_PILOTAGE.cmd` lance les **53 nouveaux cas** de `Run-PilotageTests.ps1` :
fonctions extraites du moteur, DataView réel, lecture AD remplacée par des doublures,
garde sur les commandes de mutation, fichiers temporaires et gabarit WPF isolé.
`TEST_TOUT.cmd` lance aussi les quatre suites de régression précédentes, chacune
dans un processus séparé. Quatre cas de dérive GUID/OU ont été ajoutés à la suite
moteur. La compilation exige la réussite des cinq suites et vérifie leurs codes de
sortie ; elle n'est pas elle-même une recette fonctionnelle.

**Cette RC5 doit passer les tests Windows puis la recette AD sur postes de test
avant une utilisation en production ou en lot.** Voir `docs/RECETTE_RC5.md`.

## Portée des modifications

33 fonctions ajoutées, 28 modifiées,
174 inchangées textuellement, aucune supprimée.
La décision `Get-GPRenameMoveDecision` et les orchestrateurs de mutation `Go*`
sont conservés. Les gardes d'identité sont ajoutées dans RenameComputer et
MoveComputer ; elles ne rendent pas les opérations AD transactionnelles.

Les numéros de lot sont des identifiants de traçabilité locale, pas des signatures.
Le rapport HTML décrit les intentions et les résultats consignés ; il ne relit pas
l'état appliqué après redémarrage. L'historique ne déclenche aucune relance.

## Installation et limites importantes

Conserver le `wad/cfg.json` de l'installation réelle. Le paquet de mise à jour ne
contient aucune configuration. L'archive complète contient les fichiers historiques
inchangés, dont la divergence `o.LOCAL` / suffixe DN `labo.local` déjà connue.
Elle n'a pas été remplacée par une supposition sur la configuration de production.

La préparation de lot est limitée à 200 sources et n'opère que sur le cache chargé.
Elle n'est pas une réservation de noms distribuée. Les lignes arrivent décochées
et sans redémarrage. Le contrôle AD a un délai global de 120 secondes ; la résolution
DNS n'est pas garantie par le timeout ICMP. Les droits de mutation restent à tester.

Un contrôle n'est jamais une levée du verrou de sécurité. Une observation bloquante
n'expire pas en autorisation, et un résultat partiel conserve sa reprise déplacement
seul. Les anciens checkpoints/verrous ne sont pas supprimés lors de la mise à jour.
Le changement de dossier d'installation modifie l'espace de reprise lié au chemin ;
il ne doit jamais servir à contourner un état incertain.

Empreinte du moteur livré (SHA-256) :
`8abc29e7d113352cea05bb342a59554533ddb375a2feb653840e1f5a1716e608`
