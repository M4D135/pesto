# Pesto 17.0-RC21

## Statut

Version candidate complète, construite depuis RC20. Les deux packs contiennent le même moteur et le même EXE natif x64 recompilé. **Le programme reste PowerShell 5.1/WPF sous Windows ; il n’a pas été réécrit en code natif.** Le lanceur vérifie les composants avant d’ouvrir PowerShell.

Ce n’est pas une certification pour le domaine de production. Les 90 propositions ne sont pas toutes closes : consulter `RC21_90_POINTS.md`, qui distingue code livré, options, parties restantes et essais non exécutés. Le transport djoin n’est notamment pas intégré. L’EXE est non signé.

## Contenu des distributions

```
PROD/
  Pesto.exe
  wad/
    Pesto-*.ps1 / *.xaml / Pesto-LogWriter.cs
    cfg.json
    package.json
    ... module AD et ressources
    support/
      DEBLOQUER_TOUT.cmd

DEV/
  Pesto.exe
  wad/                  mêmes composants
  tools/                fabrication, signature, coordination, mise à jour
  tests/                tests isolés et contrôles portables
  docs/                 guides et matrices
  TESTER.cmd / DEMO.cmd / DEMO_DOMAINE.cmd / ...
```

`wad` doit rester avec l’EXE. Support, documentation, tests et démos ne sont pas des dépendances obligatoires de lancement. Aucun PS1 ni lanceur de démo à la racine de PROD. Le déblocage garde sa confirmation et vise tout le dossier, pas seulement `wad\support`.

## Installer sans perdre la configuration ni les états

1. Vérifier l’issue des anciennes opérations, puis fermer Pesto. Ne pas arrêter un worker engagé pour faciliter la mise à jour.
2. Sauvegarder le dossier installé. Conserver **le même chemin d’installation et de `cfg.json`** pour les états GP historiques.
3. Remplacer ensemble l’EXE, les composants applicatifs de `wad` et `wad\package.json`. Conserver **votre `wad\cfg.json` opérationnel, préférences, journaux et états**. Le modèle du nouveau pack est volontairement non configuré : ne pas l’écraser sur votre configuration.
4. Recopier également `wad\support`, qui n’est pas dans les dépendances runtime du manifeste. Après contrôle de provenance, lancer son `DEBLOQUER_TOUT.cmd` si nécessaire.
5. Exécuter `Pesto.exe --check`, puis tester sur une copie de recette/VM avec le pack DEV avant une opération réelle.

Une modification du moteur, du XAML ou du writer C# exige de reconstruire l’EXE, pas seulement le manifeste. Le cfg métier reste personnalisable sans recompilation. Les clés et dossiers GP historiques sont conservés pour la continuité, pas supprimés comme des fichiers obsolètes.

## Noms disponibles

L’inventaire reste chargé à la demande. L’index est réutilisé pendant les changements de filtre. La GUI matérialise une page de **250 lignes**, avec Précédent/Suivant ; les compteurs décrivent le périmètre filtré calculé, pas le domaine entier supposé connu. Un calcul de plus de deux millions de numéros est refusé : préciser site ou service.

Pour un site et un service, cinq candidats au plus sont proposés. Choisir **Premier libre** ou **Après la séquence**. La seconde option évite les trous antérieurs au plus grand numéro occupé/préparé dans ce groupe ; ce n’est pas un historique garantissant qu’un numéro n’a jamais été utilisé.

Les états distinguent **Occupé dans AD**, **Préparé dans la file**, **Retenu pour vous** et **Libre dans l’inventaire**. L’ancien résultat peut rester grisé et désactivé pendant l’actualisation. Un changement de filtre annule coopérativement l’ancien calcul. Après une mutation confirmée ou incertaine, l’inventaire est marqué à actualiser, sans lancer un scan automatiquement.

**Vérifier ce nom** effectue une lecture explicite dans tout le domaine. Sa date n’est pas une réservation. **Utiliser ce nom** remplit le brouillon unitaire ou de jonction, sans lancer d’action et sans contourner une préproduction imposée. Lire d’abord la cible et choisir son organisme si le formulaire ne le permet pas encore.

Il est possible de retenir jusqu’à 64 noms dans sa préparation personnelle. Cela n’empêche pas un autre administrateur de prendre le même nom ; la coordination partagée protège l’engagement lorsqu’elle est configurée, pas ces listes personnelles.

## Favoris, brouillons et Actions

Les favoris deviennent **20 préparations nommées maximum**. L’ancien favori unique est relu comme « Mon favori ». Domaine et empreinte de configuration sont contrôlés. Aucun poste cible, reboot, credential ou confirmation n’est mémorisé dans un favori.

Le bouton **Actions** et **Ctrl+K** ouvrent la palette des pages et outils : brouillon, étiquette, capacité, conformité du nommage, différence des inventaires, performance, densité et diagnostic. La palette est une liste explicite de commandes, pas un moteur de recherche floue.

Un brouillon s’enregistre volontairement ou s’exporte en JSON. Son import ne restaure ni autorisation, ni ancien contrôle, ni redémarrage. Pesto relit la cible avant d’appliquer les champs. La lecture d’étiquette accepte un nom de poste ou `pesto:nom` ; une référence CMDB/numéro de série n’est pas résolue automatiquement.

Les messages et confirmations principaux s’ouvrent dans des panneaux de la fenêtre, dont le contenu reste consultable et copiable. Interventions est également hébergé dans la fenêtre principale. Le login initial et les dialogues de sécurité Windows restent distincts. La densité compacte/confort modifie les lignes de grille, jamais les droits.

## Interventions et reprise

Les nouvelles interventions conservent un plan figé, un identifiant, une chronologie bornée, les effets Entra/nom/déplacement/protection et les tâches exactes. Les reçus connus sont rapprochés par cible. Un incident sur une cible n’impose plus partout le même blocage d’interface ; **les anciens verrous non rattachables restent conservateurs**. Une seule mutation active sur le PC opérateur reste autorisée.

L’import historique est volontaire : choisir un checkpoint JSON local de file ou d’action directe, examiner l’aperçu puis importer. Le domaine, l’identité de la machine opérateur, les types et GUID sont contrôlés. Les anciennes traces restent sur disque et aucun succès n’est déduit de l’import. Les vieux reçus de jonction ne font pas partie de cet import.

Les actions de reprise demandent une confirmation et relisent les preuves. **Protection** rétablit exclusivement la valeur initiale enregistrée pour un échec documenté code 32, si la cible et les tâches permettent de le prouver. Un crash ambigu sans cette preuve reste à examiner manuellement. **Nettoyage** supprime uniquement les tâches exactes terminées à définition inchangée ; il ne supprime pas un ensemble de tâches par préfixe.

La checklist distingue attendu et observé. La lecture volontaire de santé **du PC local** utilise `dsregcmd /status` et une vérification du canal sécurisé sans réparation. Le résultat n’est pas celui du SSO de l’utilisateur habituel. À distance, ce qui n’est pas lu reste inconnu. Un rapport de ticket masque les identifiants et n’exporte pas les exceptions brutes ; une comparaison d’interventions affiche des différences, pas une cause certaine.

## Lots et garde-fous

Les options de lot permettent de conserver type, service et numéro. Un conflit bloque la préparation plutôt que réattribuer silencieusement un numéro. L’option **premier poste pilote** arrête le lot après sa première action pour examiner le résultat ; les autres restent non lancées. Il faut une nouvelle confirmation pour continuer.

Les règles restent identiques : même site = renommage seul ; site différent = déplacement après confirmation du renommage. Jonction et renommage unitaire ne passent pas par la file. Aucun redémarrage ni retrait Entra supplémentaire n’est déclenché par un favori, une analyse, une consultation ou un brouillon.

## Consultation et contrôles sans mutation

```
Pesto.exe --consult
Pesto.exe --check
Pesto.exe --check --quiet
Pesto.exe --check-json C:\Temp\pesto-controle-nouveau.json
Pesto.exe --validate-plan C:\Temp\brouillon.json C:\Temp\pesto-plan-controle-nouveau.json
```

Les chemins de rapport doivent être nouveaux ; aucun fichier existant n’est écrasé. Le contrôle du pack et celui d’un brouillon ne demandent ni UAC ni accès AD. Un brouillon valide donne un code zéro, mais **`Authorized=false` et `Configuration=NOT_VALIDATED`**. Le contrôle d’un brouillon invalide donne 20 ; l’absence de fichier, un argument ou une erreur d’écriture restent des erreurs. Ce n’est pas une API de mutation ni une validation en ligne.

`--consult` est différent : il ouvre l’application avec le compte Windows courant, sans demander l’élévation, et peut lire AD selon ce compte. Les gardes moteur interdisent les mutations. Les préférences personnelles et traces de l’application peuvent toujours être écrites. Il ne prouve pas que ce compte pourra renommer ou joindre un poste.

## Options d’entreprise

Voir `RC21_OPTIONS_ENTREPRISE.md` avant activation. Par défaut, pas de partage de coordination, pas de réutilisation de compte précréé et pas de repli silencieux par tâche à mot de passe.

La jonction hors connexion n’est pas intégrée. La signature exige votre certificat approuvé. Ces deux points ne sont pas déclarés terminés parce qu’un réglage ou un script de préparation existe.

## Validation

Le guide `RC21_VALIDATION.md` distingue les tests exécutés des tests Windows fournis. `TESTER.cmd` enchaîne la suite native héritée, celle des noms et celle de RC21. Le fichier interne `Test-Pesto19.ps1` reste nommé historiquement mais ses attentes portent RC21. Les anciens rapports RC18/19/20 restent historiques et ne sont pas des preuves RC21.
