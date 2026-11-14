# Bilan de livraison GP 17.0-RC13

## Source et portée

Base utilisée : `GP_17_WAD_RC12.zip`. Les octets de `wad\cfg.json` et des autres ressources `wad` hors moteur/démarrage sont conservés (12 fichiers).

La nouvelle version ajoute neuf fonctions de connexion/renommage intégré et modifie quatre fonctions existantes : `RenameComputer`, `Run-Queue`, `Show-LoginWindow`, `Complete-GPLoginSuccess`. Les fonctions de préparation Entra, de jonction, de déplacement, de décision selon site et de reprise de file sont identiques à la RC12. Des instructions de démarrage hors fonction, l'affichage du compte et les lanceurs changent également.

La comparaison est reproductible via `tests/rc12-sso-baseline.json` et `tests/sso_static_checks.py`. Le diff de code est dans `changes/GP-RC12-to-RC13.patch`.

## Exécuté dans le conteneur Linux

- Onze validateurs source/XML terminent avec code zéro. Le bilan exact est `tests/rc13-validation-summary.json`.
- Le validateur dédié à la connexion RC13 passe ses 50 contrôles de structure, de branchement et de conservation. Ses cinq défauts injectés dans des chaînes temporaires sont détectés.
- Les validateurs de non-régression historiques ont été adaptés aux quatre versions de titre, au septième gabarit XML et aux changements d'authentification explicitement déclarés. Les empreintes RC10/RC11 n'ont pas été recalculées pour masquer les différences.
- Les cinq suites Python de tests négatifs historiques ont été exécutées ; leurs rapports sont listés dans le bilan. Une ancre devenue absente du cfg actif a été corrigée pour tester le fichier d'exemple auquel le contrat s'applique.
- Les gabarits sont du XML bien formé. Ce n'est pas une validation de rendu WPF.
- Délimiteurs lexicaux, BOM UTF8 et CRLF vérifiés pour les sources modifiées. Le validateur lexical n'est pas un parseur PowerShell.

## Fourni, non exécuté ici

`TEST_CONNEXION_UNIQUE.cmd` lance 43 cas Windows isolés : choix du parcours, compte élevé, absence de paramètre Credential, callbacks périmés/annulés, erreur sans formulaire automatique, contrôles locaux, codes WMI, refus distant avant mutation et chargement du XAML. AD, CIM et Entra sont simulés dans cette suite.

Les fixtures des anciens tests de lanceur acceptent désormais le paramètre facultatif `AskCredential`. Le lanceur global inclut la nouvelle suite. `VERIFIER_UAC.cmd` reste un test UAC réel avec moteur factice, à lancer volontairement sur Windows ; il n'a pas été exécuté ici.

**Ni PowerShell Windows, ni le rendu WPF, ni l'UAC réelle, ni l'authentification réseau, ni une mutation AD/Windows n'ont été testés ici. Aucun EXE n'est compilé.** Les checks statiques et les doubles de test ne garantissent pas le succès dans votre domaine. La recette doit inclure l'accès AD avec le compte saisi dans l'UAC et un renommage local sur une machine de test.

## Limite fonctionnelle assumée

Cette version supprime le login GP automatique en mode domaine et implémente le renommage local sous le compte Windows. Le renommage d'un autre PC conserve le parcours RPC à identifiants explicites. Il est refusé avant lancement du lot s'ils manquent ; aucune préparation Entra n'est exécutée pour pallier cette absence. `GP_COMPTE_AD.cmd` est un choix explicite, pas le lancement normal.

La jonction hors domaine conserve son formulaire et sa file existants. Le changement d'onglet proposé en RC12 n'est pas intégré ici.

## Intégrité

Core SHA-256 : `2e178a620a3737f357e867ca5d767793342a4988d0e5d7d811b06e72b7b121d3`.

Les manifests sont des contrôles d'intégrité, pas une signature de confiance. Le correctif ne contient ni cfg, ni préférence, ni journal utilisateur, ni état de file.
