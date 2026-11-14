# Vérification GP 17.0-RC17

## Effectué dans cet environnement

- Compilation croisée du lanceur natif Windows x64 avec LLVM : GP.exe, 99840 octets.
- Deux compilations séparées donnent le même binaire.
- Empreinte SHA-256 du binaire : `711ace8d4a7838daf4c61c81a922e22751370df6f74107a1bd79e3bc54bbe214`.
- Inspection PE32+, sous-système graphique, ressources de version 17.0.0.17 et icône conservée. Binaire non signé, sans CLR pour le lanceur. Le moteur reste PowerShell/WPF.
- 251 contrôles portables du source, XML, ressources, dépendances et manifeste réussis. Ce sont des contrôles Python, pas le parseur Windows PowerShell.
- 17 tests Python de distribution réussis, y compris suppression/modification de chaque composant requis, absence des outils facultatifs et exclusion d’un ancien GP.ps1 présent dans le dossier source.
- 14 simulations C du point d’entrée : ouverture normale, contrôle du pack, démos, diagnostic, compte explicite, chemin de configuration, arguments refusés, fichier manquant, seconde instance, erreur de création du processus, retour d’annulation et erreur enfant. Les réponses des API Windows sont simulées. Aucun appel WinAPI réel.
- 9 cas C de construction des arguments et 2 000 allers-retours avec décodeur indépendant réussis sous Linux.
- 395 des 404 définitions de fonctions de la RC16 sont identiques. Les changements restants portent sur la version, les chemins, le manifeste et la journalisation ; `Get-GPStartupLayout` est ajouté.
- Les 14 fonctions sensibles détaillées dans `tests/rc17-build-validation.json`, dont jonction, renommage, déplacement, Entra, contrôle UAC et reprise des états, sont identiques à la RC16.
- Module AD, icône et configurations reçues comparés à l’identique.

## Non effectué

Aucune exécution de l’EXE sous Windows. Aucun parseur Windows PowerShell 5.1, rendu WPF, UAC ou opération AD réelle exécuté ici. Aucun certificat de signature ajouté. Une compilation ne valide ni une authentification ni une mutation distante.

## Recette Windows fournie dans DEV

`TESTER.cmd` : chemins du démarrage et import sans effet, manifeste, fabrication PROD/DEV, parseur Windows, interface et régressions isolées. Il ne lance aucune opération AD réelle.

`VERIFIER_UAC.cmd` : test volontaire de l’UAC réelle avec les composants copiés dans un répertoire temporaire et un moteur factice. Le manifeste de la copie est reconstruit, pas celui de l’installation. Contrôler le compte affiché, Admin=True, puis l’absence de GP.ps1 et de journaux à la racine de cette copie.

## Recette manuelle avant diffusion

Tester une installation en chemin avec espaces, accents, crochets et apostrophe. Lancer depuis un raccourci dont le répertoire de travail est différent. Accepter puis refuser l’UAC. Vérifier la connexion intégrée en domaine et le mode hors domaine attendu. Vérifier que les préférences de thème et états existants restent accessibles.

Dans PROD, ouvrir GP.exe normalement : aucun script de démo/test ne doit être requis. Lancer GP.exe --check : les 25 composants doivent être cohérents sans demande UAC ni AD. Un contrôle du pack ne valide pas cfg.json ou les droits du domaine.

Les journaux de lancement vont sous wad/logs si le dossier est accessible en écriture. Un emplacement non accessible ne conduit pas à créer des fichiers à côté de GP.exe. Dans ce cas utiliser --diagnostic pour voir les erreurs de lancement.

Ne pas supprimer les anciens reçus ou verrous pour effectuer une recette. Conserver la configuration opérationnelle. Les rapports d’anciennes versions restent historiques.
