# Distribution GP 17.0-RC16

## Correction

La RC15 mettait dans son manifeste de démarrage `DEMO.cmd`, `DEMO_DOMAINE.cmd`, `TESTER.cmd`, `VERIFIER_PACK.cmd`, des lanceurs facultatifs et trois scripts de maintenance. Les retirer suffisait à faire échouer la cohérence du paquet alors que le moteur n'en avait pas besoin pour fonctionner.

La RC16 remplace cette détection large par une liste fermée de **26 composants applicatifs** : l'EXE, le lanceur PowerShell, les modules et interfaces GP, le module AD, les ressources de langue et l'icône. Cette liste est définie dans `Get-GPRuntimeFiles`, utilisée par le contrôleur et par les deux générateurs de manifeste. Aucun balayage récursif ne décide des dépendances au démarrage.

`wad/package.json` possède `Schema=2`, `Version=17.0-RC16` et `Scope=Runtime`. Les fichiers obligatoires manquants ou modifiés, les entrées inattendues, doublonnées ou absentes du manifeste et les chemins liés restent refusés. Un ancien manifeste n'est pas accepté. Les fichiers non listés ne sont pas consultés par ce contrôle.

La configuration reste nécessaire au fonctionnement connecté, mais n'est pas hachée : sa présence et sa validité restent traitées par le code de configuration. Les préférences, l'historique, les reçus et verrous ne deviennent jamais des composants à réinstaller.

## Deux archives

| Contenu | PROD | DEV |
|---|---|---|
| GP.exe, GP.ps1, runtime et module AD | Oui | Oui, strictement identiques |
| Manifeste Runtime | Oui | Oui, strictement identique |
| Configuration active | Copie à remplacer/valider | Même copie |
| Guide court et déblocage | Oui, facultatifs après préparation | Oui |
| Démos, aperçus, config de démonstration | Non | Oui |
| Tests et maintenance de développement | Non | Oui |
| Sources du lanceur et fabrication | Non | Oui |
| Journaux/états d'une installation vivante | Non | Non |

Le pack PROD contient **30 fichiers**, dont les 26 composants hachés, `wad/package.json`, `wad/cfg.json` et les deux aides facultatives. `GP.exe` et `wad` doivent rester accompagnés de `GP.ps1`. Le moteur est toujours PowerShell/WPF, pas un programme C autonome.

Le bouton/paramètre de contrôle se lance par `GP.exe --check`, sans dépendre d'un CMD de vérification. Un appel volontaire à `-Demo` ou `-DemoJoin` sans les données de démonstration reçoit un message invitant à utiliser DEV, avant élévation ou connexion. Le lancement normal n'exige jamais ces données. Le contrôle du code ne valide pas la configuration, l'accès AD ou les autorisations.

Les conseils d'erreur de GP ont aussi été adaptés : ils renvoient désormais à `GP.exe` ou `GP.exe -AskCredential`, pas à un CMD absent du pack PROD.

## Préparer une diffusion

1. Prendre le pack PROD complet dans un dossier de préparation distinct.
2. Remplacer sa copie `wad/cfg.json` par la configuration adaptée au périmètre de diffusion. La copie héritée est incohérente et ne doit pas être déployée telle quelle.
3. Valider le programme sur Windows de recette et suivre la procédure interne de signature/autorisation. La compilation ne prouve ni le rendu WPF ni les opérations AD.
4. Ne diffuser que le dossier propre, pas une copie contenant les journaux, préférences ou états d'une machine déjà administrée.

La configuration peut être modifiée sans recalcul de `package.json`. En revanche, après une modification légitime du code ou une signature de l'EXE, les empreintes doivent être régénérées **explicitement** par les outils DEV, puis les tests relancés. Ce n'est jamais un mécanisme automatique destiné à contourner une erreur d'intégrité.

## Installation existante

Sauvegarder l'installation et son cfg.json, vérifier les opérations en cours/incertaines avant fermeture et conserver le même emplacement. Copier ensemble le code, les ressources et le nouveau `wad/package.json`. Ne pas remplacer votre configuration par l'exemple. Ne pas effacer les verrous ou reçus. Les anciens scripts facultatifs laissés dans le dossier n'ont plus d'effet sur le contrôle de démarrage.

## Refaire les paquets

Depuis DEV :

```powershell
.\tools\New-GPDistribution.ps1 -OutputDirectory 'C:\Livraisons\GP-RC16' -Channel BOTH
```

Ou :

```text
python tools/package_distribution.py --output ../GP-RC16-livraison --channel BOTH
```

`PROD`, `DEV` ou `BOTH` sont les seuls profils de conditionnement. Ils ne changent ni les droits, ni l'authentification, ni les modes de simulation. Une destination existante est refusée ; aucune installation n'est écrasée. Les générateurs vérifient les composants avant et après copie.

## Références de la vérification

Le SHA-256 compare des contenus, pas une identité d'auteur. Le manifeste et l'EXE fournis ne sont pas signés ; la cohérence locale n'est pas une certification de sécurité ou de fonctionnement.

Documentation Microsoft consultée : Get-FileHash, https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash?view=powershell-5.1 .
