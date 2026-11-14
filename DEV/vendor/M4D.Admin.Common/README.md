# M4D.Admin.Common

Bibliothèques partagées de PESTO, DOMENIA et FILPRO. Le code canonique est maintenu
dans ce dépôt privé ; chaque logiciel embarque uniquement les DLL dont il a besoin,
avec version et SHA256 verrouillés dans sa distribution.

| DLL | Responsabilité | Consommateur initial |
|---|---|---|
| Core | Tirage uniforme et échantillonnage de candidats déjà filtrés | PESTO |
| Query | Filtres typés, états connu/inconnu, pagination et agrégations | DOMENIA |
| Diagnostics | Journal et événements bornés, sans dépendance WPF | Optionnel |
| Wpf | Coalescence Dispatcher, géométrie et pairs UIA existants | Optionnel Windows |
| IO | SHA256 en flux et estimation bornée de volumes de fichiers | FILPRO |

C# 5, API .NET Framework 4.7.2, sans dépendance PowerShell, Active Directory
ou package externe à l'exécution. WPF reste isolé dans la DLL optionnelle Wpf.
Les droits, les reçus de mutation et les règles métier restent dans chaque logiciel.

## Construire et vérifier localement

Prérequis de développement : Python 3 et PowerShell 7.4 avec Roslyn fourni par
PowerShell. Ils ne sont pas requis sur les postes utilisant les DLL.

```powershell
python3 tools/bootstrap.py
pwsh -NoProfile -File tools/build.ps1 -Tests
pwsh -NoProfile -File tools/test.ps1
```

Le bootstrap télécharge les références Microsoft 4.7.2, épinglées à la version
1.0.3 et vérifiées par SHA512 avant extraction. Le compilateur refuse les API
hors cible, la syntaxe postérieure à C# 5 et les avertissements. Le build et les
bibliothèques ne téléchargent rien. Les sorties sont dans `dist/`, hors Git.

`manifest.json` contient les empreintes des DLL, des sources du runtime et du
compilateur. Les tests compilés sont distingués par `M4D.Admin.Common.Tests.*` et
ne doivent pas être livrés dans les applications. Les tests Mac exécutent la
logique compilée sur .NET moderne ; ils ne qualifient pas Windows PowerShell 5.1,
WPF, le comportement AD ou les droits du système de fichiers Windows.

## Intégration

1. Construire et tester une révision du dépôt ; conserver son commit et le manifeste.
2. Copier les DLL utiles avec leur version, SHA256 et provenance dans le produit.
3. Vérifier leurs empreintes avant chargement ; refuser un assemblage absent ou mélangé.
4. Mettre à jour le manifeste global et les tests du produit dans le même commit.
5. Corriger le source commun ici puis mettre à jour explicitement les consommateurs.

Aucune résolution « dernière version », aucun téléchargement au lancement, aucun
fork de source édité séparément dans les produits. Un hash de cohérence locale
n'est pas une signature d'éditeur.

Les contrats des modules sont décrits dans `src/Core/README.md`,
`src/Query/README.md` et `src/IO/README.md`.

Contrats additifs et qualification : [COMPATIBILITY](docs/COMPATIBILITY.md).
