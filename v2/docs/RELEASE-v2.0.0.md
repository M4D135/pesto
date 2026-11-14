# Release Pesto V2 2.0.0 — 28 octobre 2026

**Release :** [v2.0.0](https://github.com/M4D135/pesto/releases/tag/v2.0.0), publique.
**Source exacte :** `84d76fc022eb11172021447672cfde5381a2d4ea` (tag `v2.0.0`).
**Campagne officielle :** [40720801680](https://github.com/M4D135/pesto/actions/runs/40720801680), tentative 1 :
`windows-critical` puis `publish-release` réussis, SDK .NET 10.0.302 exact. Les ZIP publiés sont les octets
testés par ce run ; aucun binaire n’est reconstruit après les tests.

| Asset | Octets | SHA-256 |
|---|---:|---|
| `Pesto_V2_PROD_2.0.0.zip` | 370 735 118 | `69aef4888f1f96cbef4c37462c45262cd6476340a7c379b73a7bbcf49aa3074c` |
| `Pesto_V2_DEV_2.0.0.zip` | 387 241 859 | `471ed253ce346640401f717376002071b18def5d234c90d6438edfec88716cc1` |
| `Pesto_V2_Windows_evidence_2.0.0.zip` | 4 228 127 | `e7f76e297bb9b579a4ad029c8704b51fc08d64c416a8dadbaff26c85a433b01f` |
| `release-manifest.json` | 3 240 | `45a20b2a66a393937d1b6101298098819bd2b34cfb9b7f3e9433963c96bf788e` |
| `SHA256SUMS` | 369 | `e46ff04d616c54fea324c5cb187250e7d4a4131fba660b72b250b8ea5ab61d26` |

`Pesto.exe` commun PROD/DEV : `15c51b086fc5f04506f00e5e0fe2fee36afd518af0f5aa9cf7afd5fa410ff715`.

## Contrôles après publication

Les cinq assets ont été téléchargés depuis la release et revérifiés : empreintes GitHub, `SHA256SUMS` et
manifeste concordants ; manifestes internes `2.0.0`, `official: true`, `qualification: unqualified`,
`sourceCommit` exact ; EXE identique au record Windows ; aucun `cfg.json` privé. L’icône native de
l’EXE publié a été inspectée statiquement, sans exécution : 9 RT_ICON (16 à 256 px) conformes aux sources
vert pastel du commit.

## Résultats Windows de la campagne officielle

| Contrôle | Résultat |
|---|---|
| Tests moteur | 617/617 |
| Pont | 15/15 |
| Gardes de restauration AD (reçus bruts, sans adaptateur) | 105/105 |
| Fabrication / publication portables | 63/63 et 50/50 |
| Auto-test du banc de mise à jour | 57/57 |
| Démarrage, démo et coexistence natifs | réussis en PROD et DEV ; parent prêt en ~2 s |
| Configuration native par les boutons | 36/36 par canal |
| Installation depuis les boutons, puis retour par le service | réussis en PROD et DEV |
| Refabrication depuis les sources DEV livrées, démarrage du PROD refabriqué | réussie |
| Mise à jour PROD depuis `de527313` | `normal`, `health-failure`, `interruption` réussis en place |
| Mise à jour DEV depuis `de527313` | refus explicite qualifié (`format-refusal`), voir ci-dessous |

## Mise à jour DEV depuis `de527313` : nouvelle installation

Le pack DEV contient six sources exactes (icône, PNG de marque, outils Python vendored) que le validateur
compilé de `de527313` refuse sous `wad/dev/`. Ce programme refuse donc le pack avant toute étape de
transaction ; sous Windows, son helper affiche « Fichier hors du contenu autorisé : wad/dev/web/assets/pesto-favicon.png »,
sort en code 2, laisse le journal `prepared`, ne lance aucune santé et conserve l’installation. Une
installation DEV de `de527313` passe à 2.0.0 en décompressant le pack DEV dans un nouveau dossier ; la
configuration du profil n’est pas dans le pack. PROD se met à jour en place. Le manifeste de release porte
pour DEV `nativeUpdateQualified: false`, `baselineFormatRefusalQualified: true`,
`newInstallationRequiredFromBaseline: true`. Détails : [PACKAGING.md](PACKAGING.md).

## Campagnes officielles en échec avant la publication

Aucune n’a publié de tag, de release ou de pack. Leurs preuves sont conservées hors dépôt.

| Run | Source | Échec | Correction |
|---|---|---|---|
| [40701751220](https://github.com/M4D135/pesto/actions/runs/40701751220) | `3c9660a` | Banc DEV attendant une mise à jour en place ; refus réel du helper `de527313` | Contrat de nouvelle installation et scénario `format-refusal` (`c310e8c`, `3fb79be`) |
| [40717463230](https://github.com/M4D135/pesto/actions/runs/40717463230) | `3fb79be` | `qualification.configuration.dialog-focus` dans le sélecteur d’export PROD | Focus redemandé pendant ~2 s ; acceptation inchangée (`78782ab`) |
| [40718867151](https://github.com/M4D135/pesto/actions/runs/40718867151) | `78782ab` | `qualification.coexistence.step-timeout` au démarrage du parent, PROD refabriqué | Diagnostic `lastWait`, premier démarrage du parent borné à 120 s sous le watchdog de 180 s (`84d76fc`) |

Le dernier échec n’a pas été reproduit : dans la campagne publiée, le parent est prêt en moins de 3 s dans
les trois démarrages. Sa cause exacte reste inconnue ; un nouvel échec enregistrera désormais le dernier
état observé (`lastWait`).

## Limites

**Qualification AD non réalisée.** Aucune adhésion AD réelle, ni UAC réel, ni retour arrière depuis les
boutons de l’interface ne sont prouvés par cette release. La campagne VM finale reste à faire.
