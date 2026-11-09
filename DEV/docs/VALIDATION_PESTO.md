# Pesto 17.0-RC18 : vérifications du renommage

## Exécuté dans l'environnement de préparation

- Compilation du lanceur natif Windows x64 : **99840 octets**.
- Deux compilations distinctes produisent des exécutables identiques.
- Métadonnées : Pesto, Pesto.exe, version 17.0.0.18 / 17.0-RC18.
- Manifeste applicatif : 25 composants nécessaires, aucune dépendance aux démos/tests/CMD.
- **251 contrôles portables** source/XML/PE, zéro échec.
- **20 tests de distribution** et **16 tests de renommage/compatibilité**, tous réussis.
- **405 fonctions** comparées au source RC17 R1 après substitutions de nom/version : aucune différence imprévue.
- 10 ressources tierces/configurations/icône conservées octet pour octet. Les images embarquées sont identiques.
- 9 cas de construction d'arguments et 2 000 allers-retours avec un décodeur indépendant, exécutés sous Linux.
- 14 simulations C du lanceur avec API Windows remplacées par des doubles.

SHA-256 Pesto.exe : `1b193ff8623092d3f9dc73f632ff68096677bc043a02000cd856308e8d170c26`

Rapports : `tests/pesto-validation.json`, `tests/pesto-portable-validation.json`,
`tests/pesto-rename-baseline.json`. Ces rapports distinguent les contrôles réels des essais Windows non exécutés.

## Non exécuté ici

Lancement du PE sous Windows, parseur Windows PowerShell 5.1, rendu WPF, UAC, accès au registre Windows,
authentification Active Directory, jonction, renommage, déplacement et redémarrage réels.
La compilation et les contrôles portables ne remplacent pas cette recette.
L'EXE est **non signé**. Un contrôle d'empreintes ne constitue pas une preuve d'identité de l'auteur.

## Recette Windows depuis DEV

1. Exécuter DEBLOQUER_TOUT.cmd après vérification de la provenance. Ne pas désactiver les protections d'entreprise.
2. Lancer TESTER.cmd, puis Pesto.exe --check et Pesto.exe --version.
3. Examiner les démos en clair/sombre et à plusieurs tailles d'affichage : nom Pesto dans toutes les fenêtres,
   petit badge P lisible, login non maximisable, raccourcis et infobulles fonctionnels.
4. En copie de recette, conserver le même chemin de configuration et vérifier la reprise des anciennes
   préférences, de l'historique et des reçus. Ne pas supprimer de verrou pour réaliser ce test.
5. Vérifier un démarrage depuis un chemin avec espaces et accents, UAC acceptée puis refusée, identité
   Windows attendue et absence de deuxième login en mode domaine normal.
6. Seulement ensuite, utiliser une VM et un domaine de test pour les opérations métier.

Aucun ancien résultat de test GP n'est présenté comme un résultat Pesto. Les documents historiques restent
inchangés dans docs/historique-gp et ne sont pas les instructions actuelles de distribution.
