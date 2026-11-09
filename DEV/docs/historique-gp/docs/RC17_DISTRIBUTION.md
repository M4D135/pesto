# GP 17.0-RC17 : distributions PROD et DEV, révision de paquet R1

## PROD : dossier à distribuer

```text
PROD/
  GP.exe
  DEBLOQUER_TOUT.cmd
  wad/
```

Le script DEBLOQUER_TOUT.cmd est livré dans PROD et DEV. Il reconnaît GP.exe,
wad/GP-Startup.ps1 et wad/GP-Core.ps1, sans exiger l'ancien GP.ps1 à la racine.
Après extraction complète, l'exécuter uniquement si vous faites confiance au
paquet, confirmer avec O, puis ouvrir GP.exe. Il traite les fichiers du dossier
qui le contient, sans suivre les liens ou jonctions. Le journal est placé dans
wad/logs/DEBLOCAGE_GP.log. Il ne lance pas GP et ne modifie ni les politiques,
ni les droits, ni les protections, ni les verrous métier.

Les lanceurs de démo et de test, la documentation et les outils de compilation
ne sont pas livrés dans PROD. Le déblocage est fourni pour préparer la diffusion,
mais son absence n'est pas bloquante pour le contrôle du moteur au démarrage.

## DEV : développement et fabrication

```text
DEV/
  GP.exe
  DEBLOQUER_TOUT.cmd
  FABRIQUER_PACKS.cmd
  tests/
  tools/
  docs/
  wad/
  ... lanceurs de démo et de test
```

DEV contient exactement le même EXE, les mêmes composants applicatifs et le
même manifeste que PROD. FABRIQUER_PACKS.cmd génère les deux dossiers PROD et DEV
et deux ZIP correspondants dans une nouvelle destination. Les outils Python et
PowerShell conservent ces noms à l'intérieur des archives, sans sous-dossier GP.
La fabrication exige le script de déblocage pour que chaque paquet le livre ;
ce script ne fait toujours pas partie des dépendances de fonctionnement.

## Application inchangée

Cette révision de distribution n'est pas une nouvelle version du moteur :
GP reste en 17.0-RC17. GP.exe, les composants du moteur et wad/package.json sont
conservés octet pour octet. Aucun nouvel EXE n'a été recompilé pour ce changement.
Le lanceur natif appelle wad/GP-Startup.ps1 ; le moteur reste PowerShell/WPF.
GP.exe et wad doivent rester ensemble. Il n'y a pas de GP.ps1 à la racine.

## Mise à jour et configuration

Vérifier l'issue des opérations en cours, fermer GP, puis sauvegarder
l'installation. Pour une installation existante, copier le contenu de PROD
dans son emplacement habituel plutôt que de déplacer l'installation uniquement
pour la renommer : certains états historiques sont liés au chemin de configuration.
Conserver les préférences, états, reçus et journaux existants. Ne pas les effacer.

Conserver votre wad/cfg.json opérationnel. Le fichier livré est identique au
paquet source, pas une configuration validée pour votre environnement.

## Vérifications

Les tests Python de distribution vérifient les deux structures, le script fourni,
les empreintes applicatives, les noms racine des ZIP et l'absence de dépendance
runtime aux fichiers de démo, de test et de déblocage. TEST_DISTRIBUTION.cmd lance
la suite Windows, incluant le parseur du bloc PowerShell du déblocage et les
racines des archives. Les suites Windows et l'exécution du déblocage sur NTFS
n'ont pas été exécutées ici. Voir docs/RC17_R1_VALIDATION.md.

Les guides des anciennes révisions restent historiques. Le binaire est non signé.
