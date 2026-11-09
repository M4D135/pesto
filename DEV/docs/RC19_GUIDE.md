# Pesto 17.0-RC19

## Ce que contient la livraison

Une version candidate complète avec un lanceur natif Windows x64 recompilé, le moteur PowerShell/WPF et un contrôle des composants avant PowerShell. Le pack **PROD** décrit le contenu minimal destiné à la distribution ; il ne signifie pas que les essais Windows/AD ont été effectués ici. Le pack **DEV** ajoute compilation, tests, outillage et documentation.

```text
PROD/
  Pesto.exe
  wad/
    Pesto-*.ps1 / *.xaml
    cfg.json
    package.json
    ... ressources AD et icône
    support/
      DEBLOQUER_TOUT.cmd
```

Le support de déblocage ne doit pas être déplacé seul. Il calcule sa racine deux niveaux au-dessus et traite tout Pesto après confirmation. Il ne modifie ni UAC, ni antivirus, ni politiques Windows, ni reçus métier. Il est facultatif pour le contrôle de lancement ; tests et démos le sont aussi.

## Installation / remplacement d’une RC18

1. Vérifier l’issue réelle des anciennes opérations en cours ou incertaines. Fermer Pesto normalement. Sauvegarder l’ensemble de l’installation et les états GP nécessaires à la continuité.
2. **Conserver le même emplacement et le même chemin de cfg.json.** Remplacer ensemble l’EXE, les scripts/XAML/DLL applicatifs et `wad/package.json`. Ne pas remplacer votre `wad/cfg.json`, les préférences, journaux ou états. Le moteur et l’EXE se vérifient mutuellement : ne pas copier seulement un PS1.
3. Exécuter `wad\support\DEBLOQUER_TOUT.cmd`, puis `Pesto.exe --check`. Réaliser la recette DEV sur une VM avant les opérations réelles.

Le `cfg.json` des packs neufs est volontairement **non configuré**. Il ne contient plus le domaine incohérent de l’ancien pack. À la première ouverture, importer une configuration opérationnelle valide depuis l’écran de configuration. C’est un import guidé et validé, pas un assistant complet de découverte du domaine. La modification des règles métier impose une nouvelle validation et un redémarrage de Pesto ; elle ne réapplique pas un ancien thème.

L’ancien `DEBLOQUER_TOUT.cmd` à la racine n’est plus utilisé. Après sauvegarde, le retirer pour conserver seulement l’EXE et wad dans PROD. Aucun autre fichier d’état ne doit être supprimé à titre de « nettoyage ».

## Commandes du lanceur

Depuis le dossier contenant Pesto.exe :

```powershell
.\Pesto.exe --version
.\Pesto.exe --help
.\Pesto.exe --check
.\Pesto.exe --check --quiet
.\Pesto.exe --check-json "$env:TEMP\Pesto-controle-RC19.json"
```

Le fichier JSON doit être nouveau ; le contrôle ne remplace pas un rapport préexistant. Il ne demande ni UAC ni accès AD. Son code de sortie confirme le contrôle du pack, pas la validité de la configuration, les droits AD ou une réussite métier. Aide et version fonctionnent même sans tout le moteur. Les autres commandes exigent les composants cohérents.

## Parcours conservés

Dans le domaine, lancement normal : UAC si nécessaire, puis compte Windows du processus élevé, sans second login automatique. Hors domaine, les identifiants AD restent explicitement demandés. Le mode de simulation hors domaine n’est pas le parcours de connexion intégrée. Le renommage distant peut encore nécessiter des identifiants explicites ; le repli de tâche stockant un mot de passe n’est plus activé silencieusement par l’interface.

« Un poste » renomme directement ; « Lots » prépare une file ; « Ajouter au domaine » joint ce PC sans file. Même site : nom seul, OU conservée. Changement de site : déplacement après renommage confirmé. Un déplacement ou une jonction ne lance jamais la préparation Entra du renommage.

## Ce qui change pour les opérations

**Entra :** l’état est réellement distingué. AD seul : aucune désinscription. Hybride : retrait préalable si la politique l’autorise. Entra seul, données illisibles ou politique refusant la préparation : l’action est bloquée, pas répétée par un autre transport. Un retrait déjà lancé ou confirmé est enregistré indépendamment du nom. La réinscription Entra reste une postcondition à vérifier, pas une réparation automatique.

**Identité :** avant une mutation Windows, Pesto relit la cible Windows et AD. Un rôle contrôleur, un domaine inattendu, un nom déjà en attente ou une identité incohérente bloque l’intervention avant retrait. Une identité distante non lisible ne doit pas être remplacée par une hypothèse.

**Protection AD :** la valeur initiale est inscrite avant sa modification temporaire. La restauration normale est tentée dans le moteur ; une coupure brutale peut laisser une réparation manuelle à effectuer. La reprise demande une observation cohérente, elle ne force pas arbitrairement toutes les protections à vrai.

**Redémarrage :** aucun redémarrage n’est ajouté au plan automatiquement. Le parcours normal demandé emploie un délai zéro, sans option de fermeture forcée. Il ne donne donc plus deux minutes avant redémarrage. Enregistrer les documents avant de confirmer ; le comportement d’une application bloquant l’arrêt doit être validé sur une VM.

## Centre Interventions

Ouvrir **Historique → Interventions**. Les nouvelles opérations RC19 y sont retrouvées depuis `%ProgramData%\GP\Interventions`, même si leur ligne est retirée de la file ou si Pesto est ouvert depuis une autre copie locale avec un autre compte administrateur.

Sélectionner une intervention pour examiner son plan, les effets Entra/protection/renommage/déplacement, sa phase et les tâches associées. « Relire les tâches » n’exécute ni ne supprime de tâche : il confronte les noms et empreintes exacts et conserve les états inconnus. Puis « Vérifier » relit Windows et AD avant confirmation de résolution. Si seul le déplacement reste nécessaire, la reprise prépare uniquement ce déplacement.

Un résultat tardif reste à vérifier. Les anciennes opérations RC18 dépourvues de reçu partagé nécessitent encore le parcours historique ou une vérification manuelle. Les verrous globaux conservateurs n’ont pas tous été remplacés par des verrous par cible. Le registre ne coordonne pas deux PC opérateurs différents.

## Favori de préparation

Dans le formulaire de nommage, un favori explicite enregistre organisme, site, service et type, lié au domaine et à la configuration. Il ne conserve pas de poste, numéro d’identifiant, compte, mot de passe, redémarrage ou confirmation. Charger un favori modifie un brouillon, jamais la machine. Un site disparu ou une configuration différente impose une nouvelle préparation.

## Mise à jour avec l’outil DEV

Le générateur utilise Python (DEV seulement), déjà installé selon votre procédure. Depuis le **nouveau** dossier DEV, distinct du dossier installé :

```powershell
python .\tools\update_installation.py --destination 'C:\Outils\Pesto'
python .\tools\update_installation.py --destination 'C:\Outils\Pesto' --apply
```

La première commande ne copie rien. L’application du plan est limitée à une installation **Pesto RC18/RC19 intacte**, pas à n’importe quel ancien GP. La configuration, les préférences et les reçus ne sont pas copiés. Un refus ne doit pas être contourné en supprimant un verrou. Le support CMD n’est pas dans la liste de code mis à jour : recopier `wad\support` depuis le nouveau pack.

Une sauvegarde du code est conservée à côté de l’installation. Sur une exception interceptée, les fichiers remplacés sont rétablis. Après arrêt brutal ou panne électrique, vérifier la sauvegarde et le verrou `.pesto-update.lock` avant relance : ce n’est pas une transaction atomique couvrant tous les fichiers ni un retour arrière Windows/AD. Les anciens scripts devenus inutiles ne sont pas supprimés automatiquement.

## Développement et validation

`TESTER.cmd` lance le véritable parseur Windows PowerShell 5.1, les fonctions isolées et les chargements WPF depuis DEV. `TESTER.cmd -Capture` produit des captures locales. Ces essais n’utilisent aucun compte AD réel et n’exécutent pas de mutation Windows. **Ils n’ont pas été exécutés ici.**

Les anciens tests de versions antérieures sont conservés comme historiques, pas comme preuves RC19. Le workflow CI est manuel et n’effectue pas de publication. Pester **5.7.1** et PSScriptAnalyzer **1.24.0** doivent être préinstallés depuis une source approuvée sur le runner ; aucun téléchargement automatique au démarrage de PROD.

La recompilation LLVM se fait via `python tools/launcher/build_native.py`, puis `python tools/refresh_manifest.py`. `tools/Build-Pesto.ps1` propose le parcours MSVC/SDK Windows avec génération des empreintes par Python. Une modification d’un composant immuable impose la **recompilation de l’EXE**, pas seulement le recalcul du manifeste. `cfg.json` est personnalisable sans recompilation.

## Confiance et limites

L’EXE contient les empreintes des scripts et ressources et les vérifie avant de charger PowerShell. Modifier un script et son manifeste ne suffit plus à rendre le pack cohérent avec cet EXE. Le contrôle refuse les liens détectés et maintient des handles de lecture. Il ne remplace pas une signature Authenticode : **l’EXE reste non signé**. Ne pas désactiver les protections d’entreprise pour le lancer.

L’ensemble des 44 critères n’est pas clos : consulter `docs/RC19_SUIVI_AUDIT.md`. Les principales réserves sont les validations Windows/AD, la coordination inter-PC opérateurs, la migration complète des anciens états, l’écriture asynchrone du journal et les protections complètes contre les courses de fichiers.
