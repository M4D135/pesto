# Installation RC14

Fermer l'ancienne application uniquement après avoir vérifié les opérations en cours. Sauvegarder le dossier et `wad\cfg.json`. Ne pas supprimer les fichiers de verrou ou les états pour accélérer une mise à jour.

## Mise à jour d'une installation configurée

Extraire **le contenu** du paquet de mise à jour dans le dossier qui contient déjà `GP.cmd`. Accepter le remplacement des lanceurs, moteur, sources, tests et documentation. Aucun fichier `cfg*.json`, préférence, journal ou reçu machine n'est livré dans ce paquet.

Fichiers applicatifs à avoir ensemble :

```
GP.exe
GP.ps1
GP.cmd
wad\GP-Startup.ps1
wad\GP-Core.ps1
wad\GP-Join.ps1
wad\GP-Join.xaml
wad\cfg.json                    votre configuration
wad\ActiveDirectory.psd1        ressources AD existantes
```

Exécuter `DEBLOQUER_TOUT.cmd` après contrôle de provenance, puis `TESTER.cmd` sur le poste de recette. Tester l'interface sans AD avec `DEMO_DOMAINE.cmd`. Le lancement normal est `GP.exe`, version 17.0-RC14.

## Pack complet

Extraire le dossier `GP` complet. Ne pas placer ce dossier dans un second dossier `GP` de l'installation existante par erreur. Remettre la configuration opérationnelle dans `wad\cfg.json` ; le fichier conservé dans le pack source est une copie incohérente/anonymisée, pas une configuration validée.

Changer d'emplacement de configuration peut changer l'emplacement des anciens checkpoints de file. Préférer une mise à jour au même endroit pour conserver leur continuité. Le nouveau reçu de jonction est au contraire partagé au niveau du PC dans ProgramData, indépendamment du compte UAC et du dossier de lancement.

## L'EXE est bloqué

Ne pas désactiver l'antivirus, AppLocker/WDAC ou une politique d'entreprise. Faire examiner le code et signer/autoriser le programme selon les règles de l'organisation. Le pack contient le source C, le manifeste et les scripts de compilation. `GP.cmd` reste le lanceur PowerShell de diagnostic, soumis lui aussi aux règles de l'organisation.

## Revenir à la RC13

Conserver une copie séparée des fichiers de la version précédente. Un retour de version ne doit jamais être réalisé avec une mutation en cours. **La RC13 ne connaît pas le nouveau reçu de jonction de la RC14** : vérifier l'état réel du PC et de l'objet AD avant d'envisager ce retour. Ne pas effacer les états pour contourner cette vérification.
