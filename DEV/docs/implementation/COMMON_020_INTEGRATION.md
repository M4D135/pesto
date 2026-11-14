# Intégrer le socle commun 0.2.0

La bibliothèque canonique garde `AssemblyVersion=0.1.1.0` pour la compatibilité binaire. Sa version de fichier est `0.2.0.0` et sa version informative `0.2.0`. Ne pas fabriquer un `SourceCommit` pour un arbre non committé.

1. Relire puis committer le dépôt canonique `m4d-admin-common`. Les preuves locales sont dans `validation/catalogue-120`. Vérifier que `git status --porcelain` ne retourne rien.
2. Recompiler ce commit sans modifier les sources :

```powershell
pwsh -NoProfile -File tools/build.ps1 -Tests
pwsh -NoProfile -File tools/test.ps1
```

3. Produire un bundle dans un dossier neuf situé hors du dépôt canonique :

```text
python3 tools/release.py --source dist --output CHEMIN_BUNDLE_NEUF --consumer Pesto:Core,Query,IO,Diagnostics --minimum-version 0.2.0
```

Le générateur exige le digest exact des sources compilées, les empreintes et tailles des DLL, un commit propre et une version supérieure ou égale au minimum. `--allow-dirty` sert uniquement aux expériences locales : le chargeur Pesto refuse un lock `SourceDirty=true`.

4. Dans Pesto, remplacer les quatre DLL `wad/M4D.Admin.Common.{Core,Query,IO,Diagnostics}.dll` et copier `Pesto.common.lock.json` sous `wad/common.lock.json`. Exporter le même commit canonique dans `vendor/M4D.Admin.Common`, puis écrire son SHA complet dans `vendor/M4D.Admin.Common/source-commit.txt`. Conserver la copie précédente jusqu’aux contrôles finaux. Aucune DLL de tests ne doit être livrée.
5. Vérifier `Run-CommonTests.ps1` et `test_shared_common.py`, puis faire reconstruire le module Engine, le lanceur et le manifeste fermé par le responsable de livraison. Ces étapes intègrent les nouvelles empreintes ; ne pas distribuer un EXE lié aux anciens scripts ou aux anciennes DLL.
6. Exécuter les contrats sur Windows PowerShell 5.1 avant livraison. Les preuves Mac couvrent l’API et la logique pure, pas le chargement d’un consommateur Windows réel.

`Common.Wpf` reste un module séparé. Si un consommateur l’intègre, l’ajouter au lock **et** au runtime fermé, puis appeler explicitement `Initialize-PestoCommon -IncludeWpf` sous Windows. Même sans ce switch, une DLL WPF déclarée au lock doit passer ses contrôles de taille, d’empreinte et d’identité. Pesto n’utilise actuellement pas cette DLL pour remplacer ses helpers WPF éprouvés.

Le réemploi immédiat concerne les validations, Core/Query existants et le masquage complémentaire des diagnostics textuels. Le writer d’audit Pesto garde ses contrats append/flush, et les reçus/configurations conservent leurs règles de persistance ; la présence d’une primitive IO commune ne justifie pas un remplacement sans qualification des ACL et de la reprise.
