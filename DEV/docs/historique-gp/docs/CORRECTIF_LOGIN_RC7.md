# GP 17.0-RC7 : saisie de connexion lisible

Base : `GP_17_WAD_RC6.zip`. Correctif de présentation uniquement, daté du 22 septembre 2026.

## Défaut identifié dans la RC6

Le thème définissait un `Padding="10,8"` pour les champs puis ajoutait
`Margin="{TemplateBinding Padding}"` sur leur `PART_ContentHost`.
WPF transmet déjà le padding du TextBox/PasswordBox au ScrollViewer interne.
Le gabarit appliquait donc cet espace une deuxième fois en marge extérieure.
Sur les champs de connexion à hauteur fixe de 40 unités, la zone de texte devenait
très petite. Ce défaut de gabarit est cohérent avec les caractères coupés de la capture.
Il ne s'agit pas d'une modification des droits ou des identifiants AD.

## Modifications du source

- Suppression de la marge doublée dans les deux templates partagés : TextBox et PasswordBox.
- Padding par défaut des champs ramené à `10,6`, sans changer les tailles des cartes.
- Alignement vertical centré pour le PasswordBox, comme pour le TextBox.
- Connexion : `MinHeight="44"` au lieu d'une hauteur imposée, police 14,
  padding `12,8` appliqué une seule fois. Le mot de passe reste dans un PasswordBox natif.
- Hauteur initiale de la connexion portée à 700. Le plafonnement existant à la zone
  de travail de l'écran et le défilement restent en place pour les petits écrans.
- Version affichée : `17.0-RC7` dans la connexion, le chargement et l'application.

Les autres champs qui utilisent le style implicite TextBox reçoivent la même correction.
Aucun mécanisme de révélation du mot de passe, aucune journalisation de saisie et
aucune nouvelle dépendance ne sont ajoutés au moteur.

## Installer sur votre GP existant

1. Fermer GP et sauvegarder le dossier actuel.
2. Extraire **le contenu** de `GP_17_RC7_CORRECTIF_LOGIN.zip` dans le dossier contenant
   déjà `GP.cmd`, avec remplacement. Ne pas créer un second dossier GP à l'intérieur.
3. Exécuter `DEBLOQUER_TOUT.cmd`, puis lancer `GP.cmd`.
4. Vérifier le titre `GP 17.0-RC7 | Connexion` et saisir un identifiant.

Le correctif ne contient aucun `cfg.json`, fichier de préférences, journal, état de
reprise ni module AD. Il ne supprime rien et ne remet pas les paramètres à zéro.
Le fichier applicatif corrigé est `wad/GP-Core.ps1`.

L'archive complète `GP_17_WAD_RC7.zip` contient tout le projet, module AD et ressources
inclus. Avec une installation neuve à partir de cette archive, remettre votre propre
`wad/cfg.json` : la configuration historique livrée avec RC6 reste inchangée et
n'est pas à substituer à votre configuration validée.

## Test ciblé, sans connexion AD

`TEST_LOGIN.cmd` charge uniquement les gabarits XAML et les ressources visuelles du
source. Il n'exécute pas le corps de GP, n'importe pas le module AD, ne lit pas votre
configuration métier et ne demande aucun vrai identifiant.

La suite prévue pour Windows PowerShell 5.1 x64 vérifie les dimensions du viewport
interne, la place nécessaire pour une ligne de texte, le contraste, le curseur,
les thèmes clair/sombre et l'agrandissement de la police. Elle contient aussi un
contrôle négatif qui réintroduit l'ancien template dans une fenêtre de test isolée.
Les résultats et les mesures numériques, pas les saisies, sont écrits dans
`tests/windows-login-results.json` seulement après exécution de cette suite.

`APERCU_LOGIN.cmd` ouvre une fenêtre de test de saisie visible : les boutons de
connexion y sont désactivés. N'y saisir que du texte fictif, pas de vrai mot de passe.
Le fonctionnement normal reste accessible avec `GP.cmd`.

Pour examiner le test visuel en sombre :

```powershell
powershell.exe -NoProfile -STA -File .\tests\Run-LoginTests.ps1 -Preview -Theme Dark
```

Ces deux outils de test sont facultatifs et distincts du lancement normal.
La suite ciblée rejoint également `TEST_TOUT.cmd` et les contrôles préalables de compilation.

## Ce qui ne change pas

Authentification, callbacks, élévation, contrôles AD, file, sauvegardes et sécurité
métier sont conservés. Changer de site entraîne un renommage puis le déplacement
nécessaire après confirmation de réussite. Même site : renommage seul, OU conservée.
Aucun redémarrage supplémentaire et aucun effacement de verrou.

## Vérifications réellement exécutées

Les 211 contrôles statiques hérités et les 29 contrôles ciblés passent dans
environnement Linux. Le validateur ciblé détecte également quatre défauts injectés
dans des copies en mémoire ; appliqué à la RC6 d'origine, il signale dix contrats
incorrects autour des champs. Ce sont des vérifications du source, pas une mesure
réelle du rendu Windows.

**La suite WPF Windows, le rendu visuel, les changements de DPI réels, une connexion
AD et la compilation EXE n'ont pas été exécutés dans l'environnement de livraison.**
Le contrôle d'une police agrandie n'est pas une certification multi-écrans ou multi-DPI.

## Références techniques

Les méthodes `TextBoxBase.AttachToVisualTree` / `OnScrollViewerPropertyChanged` et
`PasswordBox.OnPaddingChanged` montrent la transmission du Padding au ScrollViewer.
La documentation décrit `PART_ContentHost` et le rôle du PasswordBox.

```text
https://raw.githubusercontent.com/dotnet/wpf/main/src/Microsoft.DotNet.Wpf/src/PresentationFramework/System/Windows/Controls/Primitives/TextBoxBase.cs
https://raw.githubusercontent.com/dotnet/wpf/main/src/Microsoft.DotNet.Wpf/src/PresentationFramework/System/Windows/Controls/PasswordBox.cs
https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/textbox
https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/passwordbox
```
