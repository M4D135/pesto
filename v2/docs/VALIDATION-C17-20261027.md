# C17 — résultats Windows du candidat e087bb1, relus le 28 octobre

La [campagne 40513849690](https://github.com/M4D135/pesto/actions/runs/40513849690), exécutée le **27 octobre 2026 de 13:38:41 à 14:12:07 UTC**, est réussie pour le commit [`e087bb16aed175bc35906fa533e9cd172d2fdaca`](https://github.com/M4D135/pesto/commit/e087bb16aed175bc35906fa533e9cd172d2fdaca). Le job `122222479628` compte **25 étapes réussies**, sans échec ni étape ignorée. Ce rapport actualise la préparation C17 du 27 octobre avec les résultats acquis ; les campagnes précédentes restent identifiées ci-dessous. La relecture du 28 octobre ne constitue pas une nouvelle exécution Windows.

Les deux nouveautés sont démontrées : **installation confirmée depuis les boutons de maintenance**, en PROD et DEV, et **recompilation depuis les seules sources du ZIP DEV livré**, suivie du démarrage natif du PROD reconstruit. Les preuves, leurs identités et leurs limites sont dans le [dossier C17](evidence/20261028/windows-e087bb1/README.md).

## Correction de la sélection de maintenance

Le lot `8a06a28` corrige une préparation périmée : préparer A puis choisir B pouvait laisser A installable à côté de la nouvelle source. Une inspection acceptée invalide désormais la préparation précédente ; annuler le sélecteur conserve le choix. Une préparation refusée ne laisse plus de bouton associé à un ancien identifiant. La confirmation indique la version, le canal et l’origine exacts du pack préparé. L’installation retire son bouton et garde les commandes désactivées pendant le relais. Les 41 contrôles Chromium de maintenance réussissent ; les parcours natifs ci-dessous apportent leurs preuves distinctes.

## Résultats acquis

| Parcours | Résultat observé |
|---|---|
| Installation depuis l’interface, PROD et DEV | Sélection native du ZIP, inspection, préparation, annulation puis confirmation positive, un seul appel d’installation, fermeture du parent, lancement du helper, installation et santé confirmées |
| Retour après cette installation | Retour explicite par le service transactionnel au build courant ; preuve distincte du parcours de boutons |
| Reconstruction DEV | Sources exactes extraites hors checkout, cache NuGet neuf, SDK livré **10.0.302**, cinq projets restaurés, nouvelle publication single-file et nouveau PROD, démarrage/fermeture et isolation de la démonstration réussis ; **18 assertions** |
| Transactions séparées | Quatre scénarios référence → candidat : installation/retour PROD, santé négative/restauration PROD, interruption/reprise PROD, installation/retour DEV ; huit tentatives de santé |
| Configuration native | **36 assertions, 9 dialogues et 6 captures par canal**, avec création de pack et choix positifs de dossier ; ce banc conserve son annulation finale d’installation |
| Accueil et saisie native | **5 et 16 assertions**, résultats UAC et identifiants synthétiques |
| Démonstration native | **44 refus d’API réelles et 6 transitions par canal**, conservation du parent et fermeture vérifiées |
| Moteur, pont et fabrication | **615**, **15** et **46** contrôles réussis, fournisseurs isolés ou runtime synthétique selon la suite |
| Scripts natifs | 18 variantes et trois entrées de qualification analysées sous PowerShell 5.1, deux contrôles UTF-8 réussis ; aucune mutation AD |
| Navigateur et contrôles web | 16 suites réussies, dont **41 contrôles de maintenance** ; backends de test déclarés |

Les scénarios UI vont de `e087bb1` vers la référence réelle `de527313b98f30d52802ec6abd51804e12f8c298`, puis reviennent à `e087bb1`. Les quatre transactions séparées vont d’abord dans l’autre sens. Les versions applicatives restent `2.0.0`, mais les commits et les empreintes EXE sont différents ; aucune version de test n’est substituée.

Les preuves UI relient la sélection, la préparation, le reçu, la transaction et le processus helper. Le reçu de relais du parent garde volontairement `nativeUpdateInstallFromUiQualified=false` : il est écrit avant la fin de l’installation. Le verdict extérieur final est `true` seulement après contrôle du remplacement, de la santé et du retour. Les configurations sentinelles et les packs sources sont préservés ; seules les copies temporaires appartenant aux bancs sont supprimées.

Le PROD reconstruit depuis DEV a une empreinte EXE distincte du candidat de la CI. Son démarrage est prouvé avec cette propre empreinte ; la reconstruction n’est pas présentée comme reproductible octet pour octet. Tous les autres fichiers du PROD sont comparés au pack initial, hors le fichier de sommes dépendant de l’EXE.

## Identités des livrables

| Livrable | Lien | SHA-256 du ZIP candidat intérieur |
|---|---|---|
| PROD | [Artefact 12739549113](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739549113) | `15a421f2c65f6197ac364f0469ec3df1c08716ca3e6afaa918077802f5460e14` |
| DEV | [Artefact 12739569321](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739569321) | `7b524c4f44414f1caf3f33fc71679f5bfccd805a4fb6f0056e040c3829b26fce` |
| Preuves | [Artefact 12739149591](https://github.com/M4D135/pesto/actions/runs/40513849690/artifacts/12739149591) | Enveloppe vérifiée : `0a9a5a9cfb96405fbc904129fea7b2e03b4ef71ba69ec094bde3cf323b94fed6` |

Expiration annoncée par GitHub : **26 novembre 2026**. Extraire l’enveloppe GitHub, puis le ZIP candidat contenant `Pesto.exe` et `wad/`. Les empreintes des enveloppes GitHub sont distinctes de celles des ZIP intérieurs.

- EXE commun PROD/DEV : `e2f45e5032ae95e0582b4eebbc58ac8ae9548b1516b198822d32033cfb341d87`.
- EXE de référence compilé pour cette campagne : `ff6b17081871d35582b328c688ec3c49927916b7cc1a82f0afe4a47fad68e1fe`.
- EXE recompilé depuis DEV : `a035214ec49c28f9d068c3b739a3ca99b2fdf97ed758947df7b55fd41e6fefc1`.
- WebView2 fixe : **156.0.4314.42** ; Windows observé : **10.0.26100.0**.

L’enveloppe des preuves a été téléchargée et son digest GitHub vérifié. Les deux grandes archives binaires n’ont pas été retéléchargées pour cette relecture ; leurs empreintes intérieures sont celles de la CI, recoupées dans les transactions et la reconstruction. Cela ne vaut pas une vérification locale supplémentaire de leurs octets.

## Échecs précédents conservés

| Source et campagne | Échec constaté | Suite observée |
|---|---|---|
| `8a06a28`, [40502069714](https://github.com/M4D135/pesto/actions/runs/40502069714) | `deliveredSdkVersionUsed` : SDK utilisé différent du SDK livré | `27d1000` fixe la version SDK et impose la vérification tôt dans le workflow |
| `27d1000`, [40506928904](https://github.com/M4D135/pesto/actions/runs/40506928904) | La restauration réutilise un cache NuGet externe | `7ce0eb7` neutralise les dossiers de fallback hérités ; cette garde réussit ensuite |
| `7ce0eb7`, [40508035980](https://github.com/M4D135/pesto/actions/runs/40508035980) | Échec d’observation du retour du parcours UI DEV, après réussite du parcours PROD | `e087bb1` ajoute des traces bornées du helper et des observations du processus ; la campagne suivante réussit dans les deux canaux |

Le dernier succès ne démontre pas la cause de l’échec d’observation précédent. **Aucune correction causale d’une intermittence n’est affirmée.** Les délais, critères de succès et exigences d’attribution restent en place. Les métadonnées et extraits de ces trois échecs sont conservés dans le dossier de preuves ; ils ne reçoivent pas rétrospectivement le verdict du candidat suivant.

## Portée restante

Ce candidat n’a pas acquis dans cette campagne de preuve **AD réelle, UAC réelle, UNC/SMB réel ou profil ordinaire**. Le retour déclenché par les **boutons UI** reste distinct du retour par le service testé ici. Les ACL réelles de déploiement, une élévation sous un autre compte et une acquisition depuis une release officielle ne sont pas couverts par ces profils temporaires du runner élevé.

Les preuves AD et UAC historiques C14 conservent leurs propres binaires. Les packs restent `distribution=candidate`, `official=false`, `qualification=unqualified` ; ce rapport ne remplace aucune release V1 et ne qualifie pas un binaire modifié après `e087bb1`.
