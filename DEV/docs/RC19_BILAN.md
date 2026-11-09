# Pesto 17.0-RC19 : bilan de fabrication et limites

## Livraison réelle

Le moteur est modifié par rapport à RC18 : **33 fonctions ajoutées, 80 fonctions modifiées et 0 fonction supprimée** dans les composants applicatifs. Ce compte est une différence textuelle, pas une mesure de qualité ni de couverture. La liste est dans RC19_FUNCTION_CHANGES.json.

L’EXE est réellement recompilé : **108,544 octets**, PE32+ Windows x64 GUI, version 17.0.0.19. Deux compilations séparées ont donné les mêmes octets. SHA-256 : `dd26e6ae7400fcad634f805e10f4f0ebb8237f2a5dc3231650ed52f3cf2df63a`.

Le manifeste contient **28 composants applicatifs**. Les 27 composants immuables autres que l’EXE sont également liés à des empreintes compilées dans l’EXE, avant l’appel à PowerShell. La configuration et le support ne sont pas des composants à empreinte compilée.

## Exécuté ici, sous Linux

| Vérification | Résultat |
|---|---|
| unittest Python (distribution, nouveau contrat, mise à jour) | 40 tests, 0 échec |
| Interruptions de copie injectées dans les fixtures de mise à jour | 29 frontières, retour des fichiers contrôlé |
| Contrôles source/XML/ressources/PE | 266 passés, 0 échec |
| Point d’entrée C avec API Windows remplacées par des doubles | 24 scénarios passés |
| Construction d’arguments C | 9 cas explicites et 2 000 allers-retours indépendants passés |
| SHA-256 C confronté à hashlib | 132 cas passés |
| Recompilation indépendante | EXE identiques |

Les logs des commandes sont dans `docs/RC19_preuves`, et les détails dans RC19_VALIDATION.json. Les premières passes du chantier ont trouvé des assertions à adapter au nouveau contrat ; les résultats ci-dessus correspondent à la passe finale, pas aux fichiers de test historiques fournis avec RC18.

## Non exécuté et non certifié

Windows PowerShell 5.1, l’analyseur PowerShell, Pester, l’EXE sous Windows, WPF et ses captures, l’UAC, le Planificateur, RPC/DCOM, AD, Entra, la jonction, le renommage, le déplacement et le redémarrage réels n’ont pas été exécutés ici. Le parseur lexical Python n’est **pas** le parseur PowerShell natif. Les tests C n’appellent pas les vraies API Windows.

Le binaire reste **non signé**. Une empreinte compilée ne constitue pas une signature d’éditeur. Aucun certificat n’est automatiquement ajouté aux magasins Windows. Les bibliothèques Microsoft reçues restent à faire approuver selon les règles de l’organisation, y compris leur redistribution.

Le dossier `PROD` désigne les fichiers à distribuer après recette, pas un certificat « prêt production ». **Les 44 critères de l’audit ne sont pas tous clos** : lire RC19_SUIVI_AUDIT.md avant de choisir le périmètre de déploiement.

## Recette avant utilisation réelle

Sur une VM Windows 11 sauvegardée, avec les mêmes politiques que le poste cible :

1. Exécuter `wad\support\DEBLOQUER_TOUT.cmd`, puis `TESTER.cmd` depuis DEV ; conserver le rapport, examiner FAIL et SKIP. Les anciennes suites sont historiques, la suite RC19 est le point d’entrée courant.
2. Tester `Pesto.exe --check`, `--check --quiet`, `--check-json` avec un nouveau nom de rapport, puis les démos. Aucun de ces succès ne valide un accès AD réel.
3. Vérifier le login non maximisable, champs lisibles, clair/sombre, enregistrement cfg, navigation clavier, 100/125/150/200 %, RDP, petite fenêtre et changement d’écran.
4. Tester domaine/hors domaine/simulation ; UAC accepté/refusé ; identité Windows après UAC et absence de login redondant en domaine réel. N’utiliser que des comptes de recette.
5. Sur des cibles de test, vérifier AD seul sans /leave, hybride autorisé, hybride désactivé, état ambigu, cible DC, identité incohérente et nom déjà en attente. Ne pas supposer qu’une réponse ping valide RPC.
6. Injecter une coupure après retrait Entra, levée de protection, renommage, déplacement et retour de tâche. Vérifier le reçu et sa relecture sans relancer la mutation. Supprimer une ligne de vue seulement, puis retrouver son intervention.
7. Tester même site / autre site, résultat partiel et reprise du déplacement seulement. Aucun objet AD existant ne doit être supprimé automatiquement.
8. Tester explicitement le reboot demandé avec une application ayant des données non enregistrées. Contrôler la différence demande acceptée / redémarrage réellement constaté.
9. Vérifier la mise à jour sur une copie RC18/RC19, son refus avec état non résolu, son code de sauvegarde et la conservation du cfg. Une coupure électrique demande une inspection manuelle, pas une relance aveugle de l’installateur.

La coordination de deux opérateurs depuis deux PC différents, la signature d’entreprise et la migration exhaustive des anciens états ne sont pas résolues par ces tests unitaires. Ne pas lancer d’interventions concurrentes sur la même machine depuis plusieurs postes.
