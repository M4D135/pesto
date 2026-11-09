# C15 — preuves Windows du candidat b875174

La [campagne 40479609012](https://github.com/M4D135/pesto/actions/runs/40479609012) réussit toutes ses étapes pour le commit [`b87517453a4d00d0082b8f3a346459fe0c4890c6`](https://github.com/M4D135/pesto/commit/b87517453a4d00d0082b8f3a346459fe0c4890c6), le 27 octobre 2026. Le [rapport C15](../../../VALIDATION-C15-20261027.md) décrit les corrections, les contrôles portables complémentaires et les limites.

## Résultats

- Moteur ciblé : **229 tests**, pont **15**, compagnon **30 contrôles**, gardes du retour AD **70**, tous réussis. Les gardes AD utilisent des doubles et n’exécutent aucune mutation.
- PowerShell 5.1 : 18 variantes métier et entrée du banc sans erreur de syntaxe ; deux contrôles UTF-8 réussis.
- Web : maintenance 33, opérateur 41, métier 39, démo 9, accueil/login 28, statiques 149, soit **299 contrôles**. Playwright 1.62.1 et Chrome for Testing 151.0.7922.34.
- Windows natif : accueil **5**, saisie **16**, configuration **14 par canal** ; démonstration PROD/DEV avec six transitions et 44 refus d’API réelles par canal. Profils ordinaires non utilisés, profils temporaires supprimés.
- Mises à jour : ZIP/rollback PROD et DEV, santé négative/restauration et interruption/reprise PROD. Deux vrais builds distincts, quatre scénarios réussis, huit tentatives de santé, sources et configuration sentinelle conservées.
- Runtime WebView2 fixe **156.0.4314.42** ; Windows observé **10.0.26100.0**.

## Pièces conservées

`summary.json` contient les comptes, la portée et les empreintes des huit JSON natifs copiés depuis l’archive de preuves. Leurs fins de ligne sont normalisées en LF ; les autres octets sont conservés, et les empreintes avant/après figurent dans la synthèse. `workflow-log-excerpts.txt` contient les extraits datés des journaux CI, pas leur intégralité. `workflow-run.json` conserve le résultat GitHub, `github-artifacts.json` les identités des enveloppes et leur expiration, `candidate-packages.json` les empreintes des ZIP intérieurs et des EXE. `runtime.json` identifie le runtime. `SHA256SUMS` permet de contrôler les fichiers de ce dossier.

L’archive complète des preuves a été téléchargée et son SHA-256 recoupé avec le digest GitHub : `ed05202281abb497dcc8f66bf4fc63da53dfab8b8794109221ac6671423f79e8`. Les gros packs binaires n’ont pas été retéléchargés localement. Leurs empreintes sont celles produites par la CI et recoupées dans les transactions natives.

| Livrable | Téléchargement |
|---|---|
| PROD | [Artefact 12723481580](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723481580) |
| DEV | [Artefact 12723720181](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723720181) |
| Journaux complets, captures, preuves | [Artefact 12723740186](https://github.com/M4D135/pesto/actions/runs/40479609012/artifacts/12723740186) |

Expiration GitHub : **26 novembre 2026**. Les empreintes des enveloppes GitHub sont distinctes de celles des ZIP intérieurs ci-dessous.

| Élément | SHA-256 |
|---|---|
| ZIP candidat PROD intérieur | `c0f4cf41c2c9d1f45cc2f46988e8067b4ebdada0b85cbfbdeda4046222cd1db0` |
| ZIP candidat DEV intérieur | `2bd88cbc9f7237309e5a10efb0200664b160fdb9409dd52a1e6956b7ebadc305` |
| EXE commun PROD/DEV | `981e67c8b3a3fc8a95ef3dd19a51d204a80e71348d075b2616ec842db0af7094` |
| EXE de base de52731 | `62c1786a7ec3b5321520943740699ceece6c4a39ceae11c9d1c93bcb170d4a6c` |

## Portée

Cette campagne ne qualifie **ni AD réel, ni UNC réel, ni UAC réel**. L’accueil et la saisie utilisent des réponses synthétiques. Les scénarios négatifs de mise à jour injectent des pannes dans des transactions natives avec de vrais exécutables. La configuration couvre les dialogues de fichiers et le service natif ; la sélection positive du dossier et le parcours complet du bouton web restent à qualifier. Les preuves C14 du laboratoire restent liées au binaire C14, pas à celui-ci. Les sous-totaux locaux et Windows se recouvrent et ne s’additionnent pas. Ces livrables restent des candidats ; aucune release V1 n’est remplacée.
