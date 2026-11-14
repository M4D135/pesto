# Pesto 17.0-RC21 : vérifications réellement effectuées

## Identité du livrable

Base : RC20 DEV fourni. Lanceur natif Windows x64 recompilé, **111104 octets**. SHA-256 :

`f1bf6341b88f28abe9f6408630ddad0ac942580097175b392d5d1c31c812c080`

Deux compilations indépendantes ont produit le même binaire. Le moteur reste PowerShell 5.1/WPF et le writer est un composant C# source chargé par le moteur. Il n’a pas été exécuté ni compilé par le CLR ici.

## Exécuté dans l’environnement Linux

| Vérification | Résultat réel | Ce que cela ne prouve pas |
|---|---|---|
| Tests Python | **69 réussis, zéro échec** | Ni parseur PS5.1 ni mutation AD |
| Contrôles portables | **300 réussis, zéro échec** | Ni zones cliquables ni interface WPF réelle |
| Compilation native x64 répétée | **Binaire identique** | Ni signature d’éditeur ni démarrage Windows |
| Code C du lanceur avec API remplacées | **32 scénarios réussis** | Les API Windows sont des doubles |
| Construction d’arguments C | **9 cas et 2 000 allers-retours réussis** | Pas de processus PowerShell lancé sous Windows |
| SHA-256 C contre Python | **132 cas réussis** | Pas d’authentification de l’auteur de l’EXE |
| Différences de code depuis RC20 | **26 fichiers Pesto de wad ajoutés/modifiés** | Une différence n’est pas une preuve de correction fonctionnelle |

Les sorties brutes sont conservées dans `docs/RC21_PREUVES`. Deux assertions Python ajoutées pendant le développement ont d’abord été corrigées : elles confondaient les namescopes des templates WPF et supposaient un mauvais format du fichier de version. Le rerun complet ci-dessus est celui du livrable.

## Fourni, NON exécuté ici

Les **61 cas Windows RC21** et les **25 cas de noms** sont fournis avec les suites antérieures adaptées. Le banc RC21 contient une boucle sur 3 996 noms, de vrais types .NET, une compilation du writer C# et le chargement des vrais XAML. Pester et PSScriptAnalyzer sont prévus dans la gate Windows, non installés ni exécutés dans cet environnement.

**NON exécutés :** Windows PowerShell 5.1, l’EXE sous Windows, le CLR C#, WPF, l’UAC, le registre Windows, les ACL réelles, la coordination sur partage réel et les opérations AD/Entra/Windows. Aucun compte réel ni poste du domaine de l’utilisateur n’a été modifié. Aucune couverture de tests ni accélération chiffrée n’est revendiquée.

`TESTER.cmd` et `docs/RC21_RECETTE.md` donnent le parcours de recette. Une erreur ou un SKIP critique interdit la validation. La CI est manuelle et non lancée ici ; elle ne signe ni ne publie automatiquement le programme.

## Limites de la livraison

**Ce n’est pas 90/90 critères acceptés.** `RC21_90_POINTS.md` détaille tous les points sans confondre code livré et preuve d’exécution. Le transport djoin n’est pas livré ; signature, recette interactive, endurance et certains durcissements restent ouverts. Les imports historiques sont bornés et manuels, la coordination exige une infrastructure approuvée, les retenues de noms sont personnelles, et l’outil de mise à jour n’est pas une transaction atomique universelle.

L’EXE est **non signé**. Les empreintes intégrées protègent la cohérence avec l’EXE attendu ; elles ne prouvent pas l’identité d’un auteur si l’EXE est remplacé lui aussi. Aucun certificat n’est installé en confiance automatiquement.
