# Packs Pesto 1.0 — mise à jour du 23 octobre 2026

Ces archives intègrent les sources de `fdc30e74b5bfc349c349f90ba27c084a42c868bd` et le correctif d’aperçu versionné avec elles : le nom disponible est calculé après la lecture AD, avant d’activer « Ajouter au domaine ». Aucun nom provisoire pendant le chargement. Une collision ultérieure affiche une nouvelle proposition et nécessite un nouveau clic.

- `Pesto_PROD.zip` : Pesto.exe et wad/, 70 entrées, configuration neutre.
- `Pesto_DEV.zip` : application, sources, outils, tests et guides, 617 entrées.
- Guides inchangés : 24 pages technicien et 66 pages administrateur.

Nettoyage du 9 novembre 2026 : le domaine réel du labo est remplacé par `labo` dans les textes, et masqué dans les captures et les guides. L’infobulle d’exemple du domaine dans `wad/Pesto-Shell.xaml` devient `LABO.LOCAL`, ce qui change l’empreinte embarquée : le lanceur est recompilé. La compilation est reproductible : les sources d’avant le nettoyage redonnent exactement l’ancien lanceur `cbf6dc3a…`. Mêmes entrées (70 et 617) ; seuls le lanceur, le xaml, `package.json`, l’en-tête du lanceur, les guides et les documents nettoyés changent. Le nouveau lanceur n’a pas été exécuté sous Windows ; les preuves datées gardent l’empreinte qualifiée à l’époque.

Vérifier depuis la racine du dépôt :

```sh
shasum -a 256 -c packs/SHA256SUMS
```

Lanceur : `b7a20d3244125df812d3237b44d10590f4881c58da7c1d83ca0a618e4d6ac563`, compilé avec clang/lld 23.1.2 sur macOS ; 67 composants runtime. Cible : Windows PowerShell 5.1 x64 / .NET Framework 4.7.2. Les configurations privées et reçus d’exploitation sont exclus.

Contrôles de ce lot : 181 tests Python et 137 contrôles PowerShell portables réussis (7.6.7 Linux, doubles locaux). Module généré à jour, intégrité des deux packs extraits et égalité de chaque fichier avec les sources vérifiées. Aucune nouvelle exécution Windows/AD/WPF ni clôture de qualification antérieure pour ce lot.

[Preuves de ce correctif](../preuves/apercu-jonction-2026-10-23/README.md) · [Bilan des 120 points](../DEV/docs/implementation/RAPPROCHEMENT_120.md)
