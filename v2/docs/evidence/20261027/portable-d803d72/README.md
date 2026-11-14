# C16 — contrôles portables du code d803d72

Ces journaux portent sur le code [`d803d72ed1084d631364a1830d6211d841e02813`](https://github.com/M4D135/pesto/commit/d803d72ed1084d631364a1830d6211d841e02813). Ils ont été produits sous Linux avec le SDK .NET 10.0.302, Playwright 1.62.1 et Chromium 151.0.7922.34. La publication de l’hôte cible Windows x64 mais n’exécute pas Windows.

`summary.json` précise la portée, les verdicts des seize suites JavaScript/navigateur et les SHA-256 des dix-neuf fichiers du commit. `SHA256SUMS` couvre les pièces de ce dossier.

| Contrôle | Résultat | Journal |
|---|---:|---|
| Moteur complet | 615/615 | `engine-all.log` |
| Pont complet | 15/15 | `bridge-all.log` |
| Assemblage des packs | 46/46 | `pack-mechanics.log` |
| Suites JavaScript et navigateur | 16 suites réussies | Un `.log` par suite |
| Étapes DOM compilées du harnais natif | 12/12 | `native-ui-scripts-dom.log` |

Le contrôle des packs utilise le vrai exécutable de publication croisée avec un runtime WebView2 factice et un commit de provenance factice explicitement déclarés. Il reconstruit le même PROD depuis les sources livrées dans DEV, à partir des mêmes entrées de publication et de runtime ; il ne recompile pas cet exécutable depuis DEV. Le processus de validation doit réellement démarrer : un refus du sandbox ne vaut pas refus du validateur.

Le premier contrôle DOM générique avait une fixture incomplète : le panneau des réservations appelle déjà `reservations.list({})`. `web-dom-before-fixture-correction.log` conserve le résultat 31/32. La fixture corrigée autorise précisément cette lecture et en exige une occurrence ; `web-dom-check.log` conserve la relance complète 32/32. Les autres opérations hors liste restent interdites, sans changement du code produit.

Les journaux préfixés `regression-` conservent les reproductions des deux défauts moteur avant correction. Les contrôles ciblés se recouvrent avec les suites complètes et ne s’additionnent pas. Les douze contrôles DOM du harnais ne qualifient aucun dialogue Windows. Aucun AD, UNC ou UAC réel n’est exécuté dans ces preuves portables.
