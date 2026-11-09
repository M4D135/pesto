# C18 — preuves Windows du candidat 2adf60e

La [campagne 40675773761](https://github.com/M4D135/pesto/actions/runs/40675773761) a réussi pour le commit exact **`2adf60e15f8f7d5fd808c0471a63e1fd4457cd90`**, le 28 octobre 2026 de **10:54:17 à 11:27:27 UTC**. Le job `122773672057` compte **25 étapes réussies**, sans échec ni étape ignorée. Les métadonnées du [run](workflow-run.json), du [job](workflow-jobs.json) et des [artefacts](github-artifacts.json) sont conservées.

## Identités téléchargées et vérifiées

| Artefact | ID GitHub | SHA-256 de l’enveloppe GitHub |
|---|---:|---|
| PROD | [12811723136](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12811723136) | `ca9830cad088feee08839a581d9f51fd7e336fde19d549c2e88c42e7be7815c9` |
| DEV | [12812691213](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12812691213) | `11f95844f0e525d5118ddb4fabc1f2843936792b9ea0f51b22188dd04387f5fb` |
| Preuves | [12812880598](https://github.com/M4D135/pesto/actions/runs/40675773761/artifacts/12812880598) | `1df2c0b699b02de250a9481efe6f3045f50d0fdcaf24d683d618b479576d47e3` |

Les trois enveloppes ont été téléchargées et leur taille/digest comparés à l’API. Leur expiration annoncée est le **27 novembre 2026**. Les ZIP candidats intérieurs ont des empreintes distinctes :

- PROD : **`08a3383f7884195d1986db5b473502dfbf2a0a3999a3d975121457d6a823d5b3`**.
- DEV : **`93e3b3afb037547d125acd8866cc8ef461d8ea0988ca02d0a33e567915c24e20`**.
- EXE commun PROD/DEV : **`b8361c8b0185ab5c528eb182639ca5bf81fbb456c647f68db410382190b33e24`**.

Les ZIP livrés localement portent les noms `Pesto_V2_PROD_2adf60e.zip`, `Pesto_V2_DEV_2adf60e.zip` et `Pesto_V2_PREUVES_2adf60e.zip` dans `outputs/`. Les enveloppes d’origine restent dans `work/update-ci-20261028/c18/2adf60e/`.

Les deux commandes locales `make-pack.mjs --verify` réussissent ([PROD](logs/pack-verify-PROD.log), [DEV](logs/pack-verify-DEV.log)). Les manifestes portent la source exacte, le bon canal et `distribution=candidate`, `official=false`, `qualification=unqualified`. Les 64 fichiers web PROD sont identiques aux blobs Git du commit. Les 768 comparaisons du pack DEV, couvrant le web principal et les sources DEV, donnent 221 identités octet par octet et 547 différences limitées aux fins de ligne CRLF/LF du checkout Windows. Aucune autre différence n’est admise. Les détails figurent dans [download-verification.json](download-verification.json).

## Résultats recoupés

La [vérification indépendante](independent-validation.json) réussit **46 contrôles de cohérence** entre les preuves, les sources et les identités binaires. Elle recopie 40 pièces de la CI, avec SHA-256 d’origine et de copie ; seule la normalisation CRLF vers LF est appliquée. Ce relevé ne relance aucun test Windows ou AD.

| Domaine | Résultat et preuve |
|---|---|
| SDK | [10.0.302 exact, rollForward disable](candidate-sdk.json) |
| Moteur / pont | [616/616](logs/Engine-All.log), [15/15](logs/Bridge.log) |
| Gardes restauration | [250/250](logs/AdRestoreGuards.log), dont 105 accès aux reçus et deux ouvertures en écriture bloquées sous Windows ; aucune commande AD exécutée |
| Fabrication | [46/46 contrôles](logs/Pack-Mechanics.log) |
| Navigateur | 16 suites réussies, dont [reprise 23/23](logs/web-recovery-check.log), [métier 57/57](logs/web-business-check.log), [maintenance 41/41](logs/web-maintenance-check.log) |
| Accueil / login natifs | [5](native-welcome.json) et [16 assertions](native-login.json), résultats UAC et identifiants synthétiques |
| Configuration native | [PROD](native-configuration-PROD.json) et [DEV](native-configuration-DEV.json) : 36 assertions, 9 dialogues et 6 captures par canal |
| Démonstration native | [PROD](native-demo-PROD.json) et [DEV](native-demo-DEV.json) : 44 refus d’API réelles et 6 transitions par canal |
| Transactions distinctes | [PROD](native-update-PROD.json) et [DEV](native-update-DEV.json) : quatre scénarios, huit tentatives de santé, configurations et packs sources préservés |
| Installation depuis les boutons | [PROD](native-update-ui-PROD.json) et [DEV](native-update-ui-DEV.json) : sélection native, annulation puis confirmation, un appel d’installation, fermeture du parent, lancement du helper, remplacement/santé, puis retour séparé par le service |
| Reconstruction DEV | [18 assertions](dev-rebuild.json), cache neuf, SDK livré exact, cinq projets restaurés, [démarrage natif du PROD reconstruit](dev-rebuilt-native-demo.json) réussi |

Les mises à jour utilisent la référence `de527313b98f30d52802ec6abd51804e12f8c298` et le candidat `2adf60e`, avec des empreintes EXE distinctes. Le PROD reconstruit depuis DEV porte l’empreinte **`bf3b1a7ba8c166e4a2f9fbc2e677aa0e7dfadf502790138e768f92acaff1ce17`** ; son démarrage est vérifié sur cette propre identité. Aucune reconstruction identique octet par octet n’est affirmée. Runtime fixe Microsoft : **156.0.4314.42**, Windows observé : **10.0.26100.0**.

## Portée

Cette CI ne qualifie pas une AD réelle, une UAC réelle, un partage UNC/SMB réel ou un profil ordinaire. Le retour **par les boutons UI** reste non qualifié ; le retour par le service transactionnel est prouvé séparément. Les deux tests de partage de fichiers Windows vérifient le refus d’écriture, sans test de suppression pendant le verrouillage. Les preuves natives de laboratoire conservent leurs identités propres.

L’[échec 07dc741](../windows-07dc741-failed/README.md) reste conservé. Le succès de 2adf60e ne démontre pas davantage la cause de l’ancienne intermittence du retour DEV de C17. [SHA256SUMS](SHA256SUMS) couvre chaque fichier de ce dossier sauf lui-même. Le [rapport C18](../../../VALIDATION-C18-20261028.md) donne le contexte des changements.
